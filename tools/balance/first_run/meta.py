"""Isolated meta progression, spell weighting and run-start stat model."""
from __future__ import annotations

from collections import Counter
from copy import deepcopy
import random

from model import choice_count

META_MODEL_VERSION = "meta-growth-1.0"


def dust_reward(config, economy, base, cleared):
    final = max(b["room"] for b in base["bosses"])
    if type(cleared) is not int or not 0 <= cleared <= final:
        raise ValueError("Cleared-room count out of range")
    normal = sum(sum(config["currency"]["room_dust_by_stage"][s["id"]] for s in economy["stages"] if s["from"] <= r <= s["to"]) for r in range(1, cleared + 1))
    return normal + sum(config["currency"]["boss_bonus_by_id"][b["id"]] for b in base["bosses"] if b["room"] <= cleared)


def derive_gem(base, config, gem_id=None, level=0):
    derived = deepcopy(base)
    if gem_id is not None:
        if not 1 <= level <= config["progression"]["max_level"]:
            raise ValueError("Gem level out of range")
        gem = config["gems"][gem_id]
        derived["player"][gem["stat"]] += gem["flat_by_level"][level - 1]
    return derived


def legal_spells(base, build):
    return [s for s in base["spells"] if build.get(s, 0) < base["limits"]["spell_level"] and (s in build or len(build) < base["limits"]["slots"])]


def spell_weights(base, config, build, catalyst_id=None, level=0, multiplier=None):
    legal = legal_spells(base, build)
    related = config["catalysts"][catalyst_id]["related_spells"] if catalyst_id else []
    boost = (config["catalyst_weight_by_level"][level - 1] if level else 1) if multiplier is None else multiplier
    basic = config["spell_sampling_assumptions"]["baseline_spell_weight"]
    return {s: basic * (boost if s in related else 1) for s in legal}


def weighted_offer(weights, count, rng):
    remaining, result = dict(weights), []
    for _ in range(min(count, len(remaining))):
        total = sum(remaining.values())
        if total <= 0:
            raise ValueError("Nonpositive candidate pool")
        draw, cumulative = rng.random() * total, 0.0
        picked = next(reversed(remaining))
        for item, weight in remaining.items():
            cumulative += weight
            if draw < cumulative:
                picked = item
                break
        result.append(picked)
        del remaining[picked]
    return result


def exact_related_offer_probability(weights, targets, count):
    """Enumerate the no-target branches; accounts for without-replacement weights."""
    if count == 0 or not weights or not set(weights) & set(targets):
        return 0.0
    total = sum(weights.values())
    no_target = 0.0
    for item, weight in weights.items():
        if item not in targets:
            remaining = {k:v for k,v in weights.items() if k != item}
            no_target += weight / total * (1 - exact_related_offer_probability(remaining, targets, count - 1))
    return max(0.0, min(1.0, 1 - no_target))


def simulate_choices(base, config, legacy, catalyst_id, level, policy, seed):
    catalyst = config["catalysts"][catalyst_id]
    route = legacy["paths"][catalyst["route"]]
    # Existing opening choice is an input; catalyst only changes subsequent offers.
    build = Counter([route["choices"][0]])
    targets = set(catalyst["related_spells"])
    rng, snapshots, appearances, offer_count = random.Random(seed), {}, 0, 0
    first_offer_related = False

    def pending_index(sid):
        seen = 0
        for index, wanted in enumerate(route["choices"]):
            if wanted == sid:
                seen += 1
                if seen > build.get(sid, 0):
                    return index
        return len(route["choices"])

    for room in range(1, 61):
        if room in (15, 45, 60):
            snapshots[room] = {"build": dict(build), "all_related": targets <= set(build),
                               "related_levels": sum(build[t] for t in targets), "distinct": len(build),
                               "synergy": len(build) >= base["fire_synergy"]["distinct_spells"]}
        if room == 60:
            break
        if choice_count(room + 1) == choice_count(room):
            continue
        weights = spell_weights(base, config, build, catalyst_id, level)
        offer = weighted_offer(weights, config["spell_sampling_assumptions"]["offer_size"], rng)
        if not offer:
            raise AssertionError("Legal 21-choice path unexpectedly exhausted")
        appearances += bool(targets & set(offer))
        offer_count += 1
        if offer_count == 1:
            first_offer_related = bool(targets & set(offer))
        if policy == "seek_related":
            # First learn missing related types, then strengthen them; not a DPS optimizer.
            key = lambda s: (0 if s in targets and not build[s] else 1 if s in targets else 2, pending_index(s), s)
        elif policy == "follow_route":
            key = lambda s: (pending_index(s), s)
        else:
            raise ValueError("Unknown choice policy")
        build[min(offer, key=key)] += 1
        if len(build) > base["limits"]["slots"] or max(build.values()) > base["limits"]["spell_level"]:
            raise AssertionError("Spell limits violated")
    return {"snapshots": snapshots, "appearances": appearances, "offer_count": offer_count, "first_offer_related":first_offer_related}


class Profile:
    """Small policy model, not the game save implementation."""
    def __init__(self, config):
        self.config = config
        self.dust = config["currency"]["initial"]
        self.levels = {i:0 for group in ("catalysts", "gems") for i in config[group]}
        self.equipped = {"catalysts":None, "gems":None}
        self.claimed = {"catalysts":False, "gems":False}
        self.started = self.settled = 0
        self.active = None
        self.earned = self.spent = 0

    def claim_starter(self, group, item):
        if self.active or self.claimed[group] or item not in self.config[group]:
            return False
        self.claimed[group] = True
        self.levels[item] = self.config["progression"]["free_choice_level"]
        self.equipped[group] = item
        return True

    def equip(self, group, item):
        if self.active or (item is not None and (item not in self.config[group] or not self.levels[item])):
            return False
        self.equipped[group] = item
        return True

    def price(self, item):
        level = self.levels[item]
        if level >= self.config["progression"]["max_level"]:
            return None
        return self.config["progression"]["unlock_cost"] if not level else self.config["progression"]["upgrade_cost_by_current_level"][str(level)]

    def advance(self, item):
        price = self.price(item)
        group = "catalysts" if item in self.config["catalysts"] else "gems"
        if self.active or not self.claimed[group] or price is None or self.dust < price:
            return False
        self.dust -= price
        self.spent += price
        self.levels[item] = self.config["progression"]["unlock_level"] if not self.levels[item] else self.levels[item] + 1
        return True

    def begin(self):
        if self.active or not all(self.claimed.values()):
            raise ValueError("Profile not ready or a run is already active")
        self.started += 1
        self.active = {"run_id": self.started, "equipped": deepcopy(self.equipped),
                       "levels": {i:self.levels[i] for i in self.equipped.values() if i is not None}}
        return deepcopy(self.active)

    def settle_run(self, run_id, cleared, economy, base):
        if self.active is None or run_id != self.active["run_id"] or run_id <= self.settled:
            return 0
        amount = dust_reward(self.config, economy, base, cleared)
        self.dust += amount
        self.earned += amount
        self.settled = run_id
        self.active = None
        return amount

    def forced_close(self):
        if self.active:
            self.settled = self.active["run_id"]
            self.active = None

    def snapshot(self):
        return {"schema_version":1, "dust":self.dust, "levels":dict(self.levels),
                "equipped":dict(self.equipped), "starter_claimed":dict(self.claimed),
                "last_started_run":self.started, "last_settled_run":self.settled}


def forecast(config, economy, base, depths, mode):
    profile = Profile(config)
    profile.claim_starter("catalysts", "MC01")
    profile.claim_starter("gems", "MG01")
    primary, rest = ["MG01", "MC01"], [i for i in profile.levels if i not in ("MC01", "MG01")]
    focus = [i for _ in range(config["progression"]["max_level"] - 1) for i in primary]
    breadth = list(rest)
    all_upgrades = [i for _ in range(config["progression"]["max_level"] - 1) for i in rest]
    queue = focus + breadth + all_upgrades if mode == "focus" else breadth + [i for _ in range(config["progression"]["max_level"] - 1) for i in profile.levels]
    rows = []
    for depth in depths:
        run = profile.begin()
        amount = profile.settle_run(run["run_id"], depth, economy, base)
        purchases = []
        while queue and mode != "no_spend" and profile.advance(queue[0]):
            purchases.append(queue.pop(0))
        assert profile.dust == config["currency"]["initial"] + profile.earned - profile.spent
        rows.append({"cleared":depth, "income":amount, "bank":profile.dust,
                     "purchases":purchases, "levels":dict(profile.levels)})
    return rows
