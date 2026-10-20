"""Design-only finite-pool reward and shop model; no Godot state or defaults."""
from __future__ import annotations

from collections import Counter
import random
import zlib

from artifacts import eligible
from model import build_at

ECONOMY_MODEL_VERSION = "run-economy-1.1"
RARITIES = ("blue", "purple", "gold")


def stage_at(config, room):
    return next(s for s in config["stages"] if s["from"] <= room <= s["to"])


def room_income(config, base, room):
    final = max(b["room"] for b in base["bosses"])
    if room == final and not config["income"]["final_room_in_run_reward"]:
        return 0
    stage = stage_at(config, room)
    amount = stage["clear_gold"]
    if any(e["room"] == room for e in base["elites"]):
        amount += stage["elite_bonus"]
    amount += config["income"]["boss_bonus"].get(str(room), 0)
    return amount


def tier_probabilities(items, pool, weights):
    """Zero weight tiers never become available via fallback."""
    present = {items[i]["rarity"] for i in pool}
    total = sum(weights[t] for t in RARITIES if t in present)
    if not total:
        return {}
    return {t: weights[t] / total for t in RARITIES if t in present and weights[t] > 0}


def make_offer(items, legal, owned, weights, count, rng, guarantee=None):
    remaining = [i for i in legal if i not in owned and weights[items[i]["rarity"]] > 0]
    result, logs = [], []
    for slot in range(count):
        probabilities = tier_probabilities(items, remaining, weights)
        if not probabilities:
            break
        forced = slot == 0 and guarantee is not None
        if forced:
            tier = guarantee if guarantee in probabilities else next(t for t in reversed(RARITIES) if t in probabilities)
        else:
            x, total = rng.random(), 0.0
            tier = next(reversed(probabilities))
            for candidate, probability in probabilities.items():
                total += probability
                if x < total:
                    tier = candidate
                    break
        item = rng.choice([i for i in remaining if items[i]["rarity"] == tier])
        remaining.remove(item)
        result.append(item)
        logs.append({"slot": slot, "item": item, "tier": tier, "forced": forced,
                     "requested_guarantee": guarantee if forced else None,
                     "ordinary_tier_probabilities": probabilities})
    return result, logs


class Economy:
    def __init__(self, config, base, catalog, spell_scenarios, assumptions):
        self.config, self.base = config, base
        self.items, self.spells, self.assumptions = catalog["items"], spell_scenarios, assumptions
        self.final = max(b["room"] for b in base["bosses"])
        self.shops = set(base["recovery"]["shop_after"])
        self.chests = {e["room"] for e in base["elites"]} | set(base["recovery"]["boss_after"])
        self.income = {r: room_income(config, base, r) for r in range(1, self.final + 1)}
        self.legal, self.ranks = {}, {}
        for name, path in spell_scenarios["paths"].items():
            for room in sorted(self.shops | self.chests):
                # Ordinary spell selection is completed BEFORE current-room artifact selection.
                build = build_at(path, room + 1)
                self.legal[name, room] = [i for i, item in self.items.items() if eligible(base, build, item)]
            preferred = assumptions["preferred_items"][name]
            self.ranks[name] = {i: (len(preferred) - preferred.index(i)) if i in preferred else 0 for i in self.items}

    def ranked(self, path, offer):
        # Scenario preferences, not an estimate of item DPS or player optimality.
        return sorted(offer, key=lambda i: (-self.ranks[path][i], i))

    def purchase(self, path, policy, stock, bank, owned, purchased_count=0, room=None):
        if policy == "no_shop":
            return [], bank
        stock = [i for i in dict.fromkeys(stock) if i not in owned]
        bought = []
        while stock:
            limit = self.config["shop"].get("max_purchases_per_visit")
            if limit is not None and len(bought) + purchased_count >= limit:
                break
            candidates = stock
            if policy == "save_gold" and room != min(self.shops) and not any(self.items[i]["rarity"] == "gold" for i in list(owned) + bought):
                candidates = [i for i in stock if self.items[i]["rarity"] == "gold"]
            ordered = self.ranked(path, candidates)
            if policy == "cheapest":
                ordered.sort(key=lambda i: self.config["prices"][self.items[i]["rarity"]])
            affordable = [i for i in ordered if self.config["prices"][self.items[i]["rarity"]] <= bank]
            if not affordable:
                break
            item = affordable[0]
            bank -= self.config["prices"][self.items[item]["rarity"]]
            bought.append(item)
            stock.remove(item)
        return bought, bank

    def campaign(self, path, policy, seed, trace=False):
        if policy not in self.assumptions["policies"]:
            raise ValueError(f"Unknown purchase policy {policy}")
        owned, purchased, chosen = set(), [], []
        bank = self.config["currency"]["initial"]
        earned = spent = empty_chests = thin_offers = 0
        first_gold = None
        first_gold_offered = None
        events, visits, offer_tiers = [], [], Counter()
        checkpoints = {}
        for room in range(1, self.final + 1):
            # No post-final coins, chests, spells, or shop branch.
            if room == self.final:
                checkpoints[room] = {"bank": bank, "owned": len(owned), "gold": sum(self.items[i]["rarity"] == "gold" for i in owned)}
                break
            earned += self.income[room]
            bank += self.income[room]
            for source, nodes in (("chest", self.chests), ("shop", self.shops)):
                if room not in nodes:
                    continue
                event_seed = seed + zlib.crc32(f"{source}:{room}".encode("utf-8"))
                rng = random.Random(event_seed)
                guarantee = self.config["guarantees"][source].get(str(room))
                slots = self.config["offers"]["chest_choices" if source == "chest" else "shop_slots"]
                offer, logs = make_offer(self.items, self.legal[path, room], owned,
                                         stage_at(self.config, room)["rarity_weights"], slots, rng, guarantee)
                if len(offer) < slots:
                    thin_offers += 1
                if first_gold_offered is None and any(self.items[i]["rarity"] == "gold" for i in offer):
                    first_gold_offered = room
                for log in logs:
                    offer_tiers[source, stage_at(self.config, room)["id"], log["tier"]] += 1
                if source == "chest":
                    picked = self.ranked(path, offer)[:1]
                    chosen.extend(picked)
                    empty_chests += not bool(picked)
                else:
                    arrival = bank
                    affordable = [i for i in offer if self.config["prices"][self.items[i]["rarity"]] <= bank]
                    picked, bank = self.purchase(path, policy, offer, bank, owned, room=room)
                    spent += arrival - bank
                    purchased.extend(picked)
                    visits.append({"room": room, "arrival": arrival, "bank_after": bank,
                                   "purchases": len(picked), "affordable": bool(affordable),
                                   "gold_offered": any(self.items[i]["rarity"] == "gold" for i in offer),
                                   "gold_affordable": arrival >= self.config["prices"]["gold"],
                                   "stock_count": len(offer)})
                if len(set(picked)) != len(picked) or any(i in owned for i in picked):
                    raise AssertionError("Duplicate ownership")
                owned.update(picked)
                if first_gold is None and any(self.items[i]["rarity"] == "gold" for i in picked):
                    first_gold = room
                if trace:
                    events.append({"room": room, "source": source, "offer": offer, "picked": picked,
                                   "bank": bank, "owned": sorted(owned), "slots": logs})
            if room in (14, 44, 59):
                checkpoints[room + 1] = {"bank": bank, "owned": len(owned), "gold": sum(self.items[i]["rarity"] == "gold" for i in owned)}
            if bank != self.config["currency"]["initial"] + earned - spent or bank < 0:
                raise AssertionError("Gold conservation or nonnegative bank failed")
        return {"owned": sorted(owned), "purchased": purchased, "chosen": chosen, "earned": earned,
                "spent": spent, "bank": bank, "first_gold_room": first_gold, "first_gold_offered_room": first_gold_offered, "visits": visits,
                "checkpoints": checkpoints, "empty_chests": empty_chests, "thin_offers": thin_offers,
                "offer_tiers": [{"source": a, "stage": b, "tier": c, "count": n} for (a,b,c), n in offer_tiers.items()], "trace": events}
