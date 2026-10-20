"""Isolated gem design lab; reads runtime sources, never launches/writes the game.

Exact stat enumeration plus continuous-time, stationary one-primary status probes.
This is neither a replay of the route nor a replacement for native Godot tests.
"""
from __future__ import annotations

import argparse
from collections import Counter
from copy import deepcopy
from dataclasses import dataclass
import hashlib
import heapq
import itertools
import json
import math
from pathlib import Path
import random
import statistics

ROOT = Path(__file__).resolve().parents[3]
MODEL_VERSION = "magic-gem-isolated-events-1.1"
EPS = 1e-8


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def values(cfg, quality="purple", scale=1.0):
    return {k: v[quality] * scale for k, v in cfg["affixes"].items()}


def counted_gems(gems):
    if len(gems) > 4 or any(len(g) != len(set(g)) or len(g) > 3 for g in gems):
        raise ValueError("At most four gems, three distinct ordinary affixes per gem")
    return Counter(itertools.chain.from_iterable(gems))


def make_gems(counts, slots, width):
    """Construct a real four-gem layout, not just an unconstrained stat vector."""
    remaining = {k: int(v) for k, v in counts.items() if v}
    rows = []
    for _ in range(slots):
        selected = sorted(remaining, key=lambda k: (-remaining[k], k))[:width]
        if len(selected) != width:
            return None
        rows.append(selected)
        for name in selected:
            remaining[name] -= 1
        remaining = {k: v for k, v in remaining.items() if v}
    return None if remaining else rows


def stats(base, generic, profile, counts=None, affix_values=None):
    result = {
        "attack": float(base["player"]["attack"]),
        "health": float(base["player"]["health"]),
        "shield": float(base["player"]["shield"]),
        "crit_rate": float(base["player"]["crit_rate"]),
        "crit_multiplier": float(base["player"]["crit_multiplier"]),
        "defense": 0.0, "cdr": 0.0, "speed": 0.0,
        "fire_bonus": 0.0, "ice_bonus": 0.0, "generic_bonus": 0.0,
    }
    result.update(profile)
    for name, count in (counts or {}).items():
        result[name] += count * affix_values[name]
    result["cdr"] = min(base["limits"]["cooldown_reduction"], max(0.0, result["cdr"]))
    result["speed"] = min(generic["rules"]["combat_move_speed_bonus_cap"], result["speed"])
    rule = generic["rules"]
    result["incoming"] = max(1 - rule["maximum_damage_reduction"],
                             rule["defense_coefficient"] / (rule["defense_coefficient"] + max(0, result["defense"])))
    result["ehp"] = (result["health"] + result["shield"]) / result["incoming"]
    return result


def cycle(spec, stat, base):
    return spec["windup"] + max(base["limits"]["minimum_cooldown"],
                                 spec["cooldown"] * (1 - stat["cdr"]))


def direct_dps(spec, stat, base):
    expectation = 1 + min(1, max(0, stat["crit_rate"])) * (stat["crit_multiplier"] - 1)
    return stat["attack"] * spec["levels"][0]["coefficient"] * expectation / cycle(spec, stat, base)


def blood_stats(stat, cfg):
    result = dict(stat)
    converted = stat["health"] * cfg["cores"]["blood"]["life_conversion"]
    result["health"] -= converted
    result["shield"] += converted * cfg["cores"]["blood"]["shield_per_life"]
    result["ehp"] = (result["health"] + result["shield"]) / stat["incoming"]
    return result


def prism_split(base_damage, multiplier, neighbors, cfg):
    c = cfg["cores"]["prism"]
    n = min(c["neighbor_cap"], max(0, neighbors))
    bonus = base_damage * (multiplier - 1)
    moved = bonus * c["bonus_transfer_fraction"] if n else 0
    return [base_damage + bonus - moved] + ([moved / n] * n if n else [])


def prism_pack(healths, base_damage, multiplier, cfg, enabled):
    """Stationary priority-target fixture; all hits are critical for clarity."""
    healths = list(healths)
    casts = 0
    while max(healths) > EPS and casts < 10000:
        primary = next(i for i, hp in enumerate(healths) if hp > EPS)
        others = [i for i, hp in enumerate(healths) if hp > EPS and i != primary]
        split = prism_split(base_damage, multiplier, len(others), cfg) if enabled else [base_damage * multiplier]
        for actor, amount in zip([primary] + others, split):
            healths[actor] -= min(healths[actor], amount)
        casts += 1
    return casts


@dataclass
class Burn:
    token: int
    expires: float
    next_tick: float
    interval: float
    coefficient: float
    maximum_ticks: int
    stacks: int = 1
    last_gain: float = -math.inf


class StatusLab:
    def __init__(self, cfg, base, fire, ice, stat, core=None, horizon=30.0,
                 control="normal", neighbors=0, target_health=1e12,
                 burn_duration=None, window_duration=None, seed=0, critical=False):
        self.cfg, self.base, self.fire, self.ice, self.stat = cfg, base, fire, ice, stat
        self.core, self.horizon, self.control = core, horizon, control
        self.neighbors = neighbors
        self.health = target_health
        self.rng, self.critical = random.Random(seed), critical
        self.burn_rule = deepcopy(fire["fire"]["burning"])
        if burn_duration is not None:
            self.burn_rule["duration"] = burn_duration
            self.burn_rule["maximum_ticks"] = round(burn_duration / self.burn_rule["interval"])
        if core == "flash":
            scale = cfg["cores"]["flash"]["time_scale"]
            self.burn_rule["duration"] *= scale
            self.burn_rule["interval"] *= scale
        if core == "layers":
            self.burn_rule["coefficient"] = cfg["cores"]["layers"]["tick_coefficient_per_layer"]
        self.frost_rule = ice["mechanics"]["frost"]
        self.window_duration = self.frost_rule["ready_window"] if window_duration is None else window_duration
        self.queue, self.seq, self.token = [], 0, 0
        self.now, self.burn, self.stacks = 0.0, None, 0
        self.stack_expires, self.window = -math.inf, None
        self.immune_until = -math.inf
        self.control_intervals = []
        self.consumed, self.expired = set(), set()
        self.weave_last, self.weave_progress = None, 0
        self.weave_expires, self.weave_ready = -math.inf, -math.inf
        self.weave_casts = set()
        self.thermal_ready = -math.inf
        self.metrics, self.damage = Counter(), Counter()
        self.trigger_times = []
        self.ttk = None

    def add(self, at, kind, payload=None, priority=2):
        if at <= self.horizon + EPS:
            self.seq += 1
            heapq.heappush(self.queue, (round(at, 9), priority, self.seq, kind, payload))

    def hit_stream(self, interval, school, coefficient=0.0, start=0.0, natural=True):
        if interval <= 0:
            raise ValueError("Positive event interval required")
        for n in range(max(0, math.floor((self.horizon - start + EPS) / interval) + 1)):
            self.add(start + n * interval, "hit", {"school": school, "coefficient": coefficient,
                     "cast": f"{school}-{start}-{n}", "natural": natural})

    def amplify(self, coefficient, school):
        school_bonus = max(self.stat["fire_bonus"], self.stat["ice_bonus"]) if school == "hybrid" else self.stat.get(f"{school}_bonus", 0.0)
        return self.stat["attack"] * coefficient * (1 + self.stat["generic_bonus"]) * (1 + school_bonus)

    def deal(self, amount, kind):
        actual = min(self.health, max(0, amount))
        self.health -= actual
        self.damage[kind] += actual
        if self.health <= EPS and self.ttk is None:
            self.ttk = self.now

    def ignite(self):
        rule = self.burn_rule
        if self.burn is not None:
            self.burn.expires = self.now + rule["duration"]
            if self.core == "layers" and self.now + EPS >= self.burn.last_gain + self.cfg["cores"]["layers"]["gain_interval"]:
                self.burn.stacks = min(self.cfg["cores"]["layers"]["cap"], self.burn.stacks + 1)
                self.burn.last_gain = self.now
        else:
            self.token += 1
            self.burn = Burn(self.token, self.now + rule["duration"], self.now + rule["interval"],
                             rule["interval"], rule["coefficient"], rule["maximum_ticks"], last_gain=self.now)
            self.add(self.burn.next_tick, "burn_tick", self.burn.token, 0)
        self.add(self.burn.expires, "burn_end", self.burn.token, 1)
        self.metrics["ignitions"] += 1
        self.metrics["maximum_layers"] = max(self.metrics["maximum_layers"], self.burn.stacks)

    def future_burn(self):
        if self.burn is None:
            return 0.0
        b = self.burn
        count = min(b.maximum_ticks, max(0, math.floor((b.expires - b.next_tick + EPS) / b.interval) + 1))
        return count * b.coefficient * b.stacks

    def frost(self):
        if self.window is not None:
            return
        if self.now + EPS >= self.stack_expires:
            self.stacks = 0
        self.stacks += 1
        self.stack_expires = self.now + self.frost_rule["expiry"]
        if self.stacks < self.frost_rule["max_stacks"]:
            return
        self.stacks = 0
        self.token += 1
        freeze = 0.0
        if self.core != "erosion" and self.now + EPS >= self.immune_until:
            freeze = self.frost_rule["base_freeze"] * self.frost_rule["control_duration_coefficients"][self.control]
        index = len(self.control_intervals)
        self.control_intervals.append([self.now, self.now + freeze])
        self.window = {"token": self.token, "expires": self.now + self.window_duration,
                       "freeze_end": self.now + freeze, "control_index": index}
        self.metrics["windows"] += 1
        self.add(self.window["expires"], "window_end", self.token, 1)
        if freeze > 0:
            self.add(self.now + freeze, "freeze_end", self.token, 0)
        if self.core == "erosion":
            self.add(self.now + self.cfg["cores"]["erosion"]["interval"], "erosion_tick", self.token, 0)

    def consume_window(self):
        if self.window is None:
            return False
        w = self.window
        self.consumed.add(w["token"])
        if self.now < w["freeze_end"] - EPS:
            self.control_intervals[w["control_index"]][1] = self.now
            self.immune_until = self.now + self.frost_rule["post_freeze_immunity"]
        self.window, self.stacks = None, 0
        return True

    def weave(self, payload):
        if not payload["natural"] or payload["cast"] in self.weave_casts:
            return
        self.weave_casts.add(payload["cast"])
        c = self.cfg["cores"]["weave"]
        if self.now >= self.weave_expires - EPS:
            self.weave_last, self.weave_progress = None, 0
        school = payload["school"]
        if self.weave_last is not None and school != self.weave_last:
            self.weave_progress += 1
        self.weave_last, self.weave_expires = school, self.now + c["mark_duration"]
        if self.weave_progress >= c["alternations"] and self.now + EPS >= self.weave_ready:
            self.weave_progress = 0
            self.weave_ready = self.now + c["cooldown"]
            amount = self.amplify(c["coefficient"], school)
            self.deal(amount, "weave_primary")
            self.damage["weave_neighbors"] += amount * min(self.neighbors, c["target_cap"] - 1)
            self.metrics["weave_triggers"] += 1
            self.trigger_times.append(self.now)
        elif self.weave_progress >= c["alternations"]:
            self.weave_progress = c["alternations"] - 1

    def thermal(self):
        c = self.cfg["cores"]["thermal"]
        fuel = self.future_burn()
        if self.window is None or fuel <= 0 or self.now < self.thermal_ready - EPS:
            return
        self.burn = None
        self.consume_window()
        self.thermal_ready = self.now + c["cooldown"]
        amount = self.amplify(c["base_coefficient"] + fuel * c["remaining_burn_scale"], "hybrid")
        self.deal(amount, "thermal_primary")
        self.damage["thermal_neighbors"] += amount * c["neighbor_scale"] * min(self.neighbors, c["neighbor_cap"])
        self.metrics["thermal_triggers"] += 1
        self.trigger_times.append(self.now)

    def run(self):
        while self.queue and self.health > EPS:
            self.now, _, _, kind, p = heapq.heappop(self.queue)
            if kind == "hit":
                self.metrics["hits"] += 1
                self.metrics[f"{p['school']}_hits"] += 1
                amount = self.amplify(p["coefficient"], p["school"])
                if self.critical and self.rng.random() < min(1, max(0, self.stat["crit_rate"])):
                    amount *= self.stat["crit_multiplier"]
                self.deal(amount, "direct")
                if self.health <= EPS:
                    continue
                if p["school"] == "fire":
                    self.ignite()
                elif p["school"] == "ice":
                    self.frost()
                if self.core == "weave":
                    self.weave(p)
                elif self.core == "thermal":
                    self.thermal()
            elif kind == "burn_tick" and self.burn is not None and self.burn.token == p:
                b = self.burn
                if self.now <= b.expires + EPS:
                    self.deal(self.amplify(b.coefficient * b.stacks, "fire"), "burn")
                    b.next_tick += b.interval
                    self.add(b.next_tick, "burn_tick", b.token, 0)
            elif kind == "burn_end" and self.burn is not None and self.burn.token == p:
                if self.burn.expires <= self.now + EPS:
                    self.burn = None
            elif kind == "detonate":
                fuel = self.future_burn()
                if fuel > 0:
                    self.burn = None
                    self.deal(self.amplify(fuel * p["multiplier"], "fire"), "detonation")
                    self.metrics["detonations"] += 1
                    if p.get("reignite_delay") is not None:
                        self.add(self.now + p["reignite_delay"], "reignite")
            elif kind == "reignite":
                self.ignite()
            elif kind == "freeze_end" and self.window is not None and self.window["token"] == p:
                self.immune_until = self.now + self.frost_rule["post_freeze_immunity"]
            elif kind == "window_end" and self.window is not None and self.window["token"] == p:
                self.expired.add(p)
                if self.core == "collapse":
                    self.deal(self.amplify(self.cfg["cores"]["collapse"]["coefficient"], "ice"), "collapse")
                    self.metrics["auto_shatters"] += 1
                self.window = None
            elif kind == "erosion_tick" and self.window is not None and self.window["token"] == p:
                if self.now <= self.window["expires"] + EPS:
                    self.deal(self.amplify(self.cfg["cores"]["erosion"]["coefficient"], "ice"), "erosion")
                    self.add(self.now + self.cfg["cores"]["erosion"]["interval"], "erosion_tick", p, 0)
            elif kind == "shatter" and self.consume_window():
                coefficient = self.ice["spells"]["I07"]["levels"][0]["shatter_coefficient"]
                self.deal(self.amplify(coefficient, "ice"), "manual_shatter")
                self.metrics["manual_shatters"] += 1
        control = sum(max(0, min(end, self.horizon) - start) for start, end in self.control_intervals)
        return {"damage": dict(self.damage), "metrics": dict(self.metrics), "ttk": self.ttk,
                "control_seconds": control, "control_fraction": control / self.horizon,
                "consumed_tokens": sorted(self.consumed), "expired_tokens": sorted(self.expired),
                "trigger_times": self.trigger_times}


def quantile(data, fraction):
    ordered = sorted(data)
    return ordered[round((len(ordered) - 1) * fraction)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--parameters", type=Path, default=Path(__file__).with_name("parameters.json"))
    parser.add_argument("--output", type=Path, default=ROOT / "build/qa/magic-gems-20261019")
    parser.add_argument("--ttk-trials", type=int)
    args = parser.parse_args()
    args.output = args.output.resolve()
    if not args.output.is_relative_to((ROOT / "build/qa").resolve()):
        raise ValueError("Reports must stay under this project's build/qa directory")
    cfg = load(args.parameters)
    if args.ttk_trials is not None:
        cfg["fixtures"]["ttk_trials"] = args.ttk_trials
    source_paths = {k: ROOT / v for k, v in cfg["sources"].items()}
    sources = {k: load(v) for k, v in source_paths.items()}
    hashes = {str(v.relative_to(ROOT)).replace("\\", "/"): sha(v) for v in source_paths.values()}
    base, fire, ice, generic = (sources[x] for x in ("base", "fire", "ice", "generic"))
    items = generic["items"]
    p06 = sources["fire_items"]["items"]["P06"]
    g04 = sources["fire_items"]["items"]["G04"]
    extended_window = ice["mechanics"]["frost"]["ready_window"] + ice["spells"]["I10"]["levels"][2]["ready_window_add"]
    g04_multiplier = base["spells"]["F07"]["levels"][2]["detonation_multiplier"] + g04["detonation_multiplier_add"]
    validation = []

    def check(name, actual, expected=True):
        ok = math.isclose(actual, expected, abs_tol=1e-7, rel_tol=1e-9) if isinstance(actual, (int, float)) and isinstance(expected, (int, float)) else actual == expected
        validation.append({"name": name, "actual": actual, "expected": expected, "pass": ok})

    check("known player attack", base["player"]["attack"], 100)
    check("known player health", base["player"]["health"], 300)
    check("known player shield", base["player"]["shield"], 100)
    check("crit attribute remains uncapped", base["limits"]["crit_rate"], None)
    check("CDR cap remains 60%", base["limits"]["cooldown_reduction"], 0.6)
    check("ordinary affix count", len(cfg["affixes"]), 8)
    check("core count", len(cfg["cores"]), 8)
    check("ordinary grade magnitudes valid", all(v["green"] <= v["blue"] <= v["purple"] == v["gold"] for v in cfg["affixes"].values()))
    check("F07 future-burn multiplier", base["spells"]["F07"]["levels"][2]["detonation_multiplier"], 1.5)
    check("frost max stacks", ice["mechanics"]["frost"]["max_stacks"], 3)
    check("I07 base shatter", ice["spells"]["I07"]["levels"][0]["shatter_coefficient"], 2.0)
    check("P06 known burn duration", p06["burn_duration"], 6.0)
    check("P06 known maximum future ticks", p06["maximum_ticks"], 12)
    check("G04 known detonation addition", g04["detonation_multiplier_add"], 2.0)
    check("G04 known delayed reignition", g04["reapply_delay"], 0.5)
    check("I10 III known window addition", ice["spells"]["I10"]["levels"][2]["ready_window_add"], 0.5)
    basic = stats(base, generic, {})
    neutral = dict(basic, crit_rate=0.0)

    def lab(core=None, **kwargs):
        return StatusLab(cfg, base, fire, ice, neutral, core=core, **kwargs)

    # Independent hand cases establish model fidelity before parameter comparisons.
    probe = lab(horizon=4)
    probe.add(0, "hit", {"school": "fire", "coefficient": 0, "cast": "one", "natural": True})
    check("one isolated current burn = 8*25", probe.run()["damage"].get("burn", 0), 200.0)
    probe = lab(horizon=4.1)
    for at in (0, 0.1):
        probe.add(at, "hit", {"school": "fire", "coefficient": 0, "cast": str(at), "natural": True})
    check("refresh preserves existing next tick", probe.run()["damage"].get("burn", 0), 200.0)
    probe = lab(horizon=p06["burn_duration"], burn_duration=p06["burn_duration"])
    probe.hit_stream(100, "fire")
    check("P06 six-second burn = 12*25", probe.run()["damage"].get("burn", 0), 300.0)
    probe = lab(horizon=3, burn_duration=p06["burn_duration"])
    probe.hit_stream(100, "fire")
    probe.add(0.001, "detonate", {"multiplier": g04_multiplier})
    outcome = probe.run()
    check("P06 plus F07 III/G04 = 12*.25*3.5*100", outcome["damage"].get("detonation", 0), 1050.0)
    check("consumed burn stops ticking", outcome["damage"].get("burn", 0), 0)
    for control, expected in (("normal", 1.2), ("elite", 0.42), ("fixed_strong", 0.0)):
        probe = lab(horizon=4, control=control)
        for at in (0, 0.1, 0.2):
            probe.add(at, "hit", {"school": "ice", "coefficient": 0, "cast": str(at), "natural": True})
        outcome = probe.run()
        check(f"current freeze duration {control}", outcome["control_seconds"], expected)
    check("F01 cycle includes windup", cycle(base["spells"]["F01"], basic, base), 1.35)
    ice_cycle = ice["spells"]["I01"]["windup"] + ice["spells"]["I01"]["levels"][0]["cooldown"]
    check("I01 cycle includes windup", ice_cycle, 1.45)
    capped = stats(base, generic, {"crit_rate": 1.8, "cdr": 0.8, "defense": 1000})
    check("uncapped crit value retained", capped["crit_rate"], 1.8)
    check("CDR clamped not added past60", capped["cdr"], 0.6)
    check("combined mitigation cap respected", capped["incoming"], 0.55)
    check("known raw EHP no gems", basic["ehp"], 400.0)
    if any(not case["pass"] for case in validation):
        for case in validation:
            if not case["pass"]:
                print(json.dumps(case, ensure_ascii=False))
        raise SystemExit("Baseline fidelity failed; do not tune candidate parameters")

    profiles = {
        "starter": {},
        "developed_fire": {
            "attack": base["player"]["attack"] + base["attribute_artifact_candidates"]["attack_flat"],
            "crit_rate": base["player"]["crit_rate"] + items["GU06"]["crit_rate_add"] + sources["fire_items"]["items"]["B02"]["fire_crit_rate_add"],
            "crit_multiplier": base["player"]["crit_multiplier"] + items["GU07"]["crit_multiplier_add"] + base["spells"]["F02"]["levels"][2]["crit_bonus"],
            "cdr": base["fire_synergy"]["cooldown_reduction"] + items["GU05"]["cooldown_reduction_add"]
        },
        "saturated": {"attack": 115, "crit_rate": 1.1, "crit_multiplier": 2.0, "cdr": 0.6, "defense": 1000}
    }
    spec = base["spells"]["F01"]
    names = list(cfg["affixes"])
    affix_values = values(cfg)
    best = {name: {"gain": -math.inf} for name in profiles}
    enumeration_count = 0
    for vector in itertools.product(range(cfg["slots"] + 1), repeat=len(names)):
        if sum(vector) != cfg["slots"] * cfg["affix_counts"]["purple"]:
            continue
        counts = dict(zip(names, vector))
        rows = make_gems(counts, cfg["slots"], cfg["affix_counts"]["purple"])
        if rows is None:
            continue
        enumeration_count += 1
        for name, profile in profiles.items():
            no_gems = stats(base, generic, profile)
            with_gems = stats(base, generic, profile, counts, affix_values)
            gain = direct_dps(spec, with_gems, base) / direct_dps(spec, no_gems, base) - 1
            if gain > best[name]["gain"] + EPS or (abs(gain - best[name]["gain"]) <= EPS and with_gems["ehp"] > best[name]["stats"]["ehp"] + EPS):
                best[name] = {"gain": gain, "counts": counts, "gems": rows, "stats": with_gems}
    check("each best layout is physically equippable", all(dict(counted_gems(v["gems"])) == {k: n for k, n in v["counts"].items() if n} for v in best.values()))
    expected_vectors = sum((-1) ** k * math.comb(8, k) * math.comb(12 - 5 * k + 7, 7) for k in range(3))
    check("exhaustive count vectors match independent inclusion-exclusion", enumeration_count, expected_vectors)
    all_defense = counted_gems([["health", "shield", "defense"]] * 4)
    defense = stats(base, generic, {}, all_defense, affix_values)
    check("defensive layout EHP hand case", defense["ehp"], (380 + 132) * 1.16)
    blood = blood_stats(basic, cfg)
    check("blood converts base HP to225", blood["health"], 225)
    check("blood converts shield to250", blood["shield"], 250)
    check("blood first-room combined capacity", blood["ehp"], 475)
    # Excess healing is not stored and cannot create a loss/recovery feedback loop.
    restore = min(20 * cfg["cores"]["blood"]["combat_health_restore_conversion"], 7)
    check("converted20 heal with7 missing shield restores7", restore, 7)
    check("converted heal at full shield restores0", min(20, 0), 0)
    cup_restore = items["GT04"]["health_restore"] * cfg["cores"]["blood"]["combat_health_restore_conversion"]
    cup_restore *= items["GT01"]["shield_restore_multiplier"]
    check("GT04 plus converted healing plus GT01 restores10 when missing", cup_restore, 10)
    check("same real10 shield restores store40 charge once", cup_restore * items["GT01"]["charge_per_restored_shield"], 40)
    burst = cfg["fixtures"]["burst_damage"]
    burst_cases = {"baseline_hits_to_die": math.ceil((basic["health"] + basic["shield"]) / (burst * basic["incoming"]) - EPS),
                   "defensive_gem_hits_to_die": math.ceil((defense["health"] + defense["shield"]) / (burst * defense["incoming"]) - EPS)}
    check("baseline dies on fourth100 raw hit without recovery", burst_cases["baseline_hits_to_die"], 4)
    check("four defensive gems die on sixth100 raw hit", burst_cases["defensive_gem_hits_to_die"], 6)

    for neighbors in (0, 1, 2, 10):
        split = prism_split(100, 2.0, neighbors, cfg)
        check(f"prism conserves pre-mitigation budget n={neighbors}", sum(split), 200)
        check(f"prism cap n={neighbors}", len(split) <= 3)
    prism_results = {"split": prism_split(100, 2, 2, cfg), "pack_fixture": {"healths": [300, 50, 50],
                     "without": prism_pack([300, 50, 50], 100, 2, cfg, False),
                     "with": prism_pack([300, 50, 50], 100, 2, cfg, True)}}
    check("prism synthetic pack baseline", prism_results["pack_fixture"]["without"], 4)
    check("prism synthetic pack proposed", prism_results["pack_fixture"]["with"], 3)

    fire_rows = []
    for duration in (fire["fire"]["burning"]["duration"], p06["burn_duration"]):
        for cadence in cfg["fixtures"]["pulse_intervals"]:
            for core in (None, "flash", "layers"):
                probe = lab(core, horizon=cfg["fixtures"]["horizon"], burn_duration=duration)
                probe.hit_stream(cadence, "fire")
                out = probe.run()
                fire_rows.append({"duration": duration, "cadence": cadence, "core": core or "none", **out})
                check(f"bounded layers {duration}/{cadence}/{core}", out["metrics"].get("maximum_layers", 0) <= (cfg["cores"]["layers"]["cap"] if core == "layers" else 1))
    isolated = {}
    for core in (None, "flash"):
        probe = lab(core, horizon=4)
        probe.hit_stream(100, "fire")
        isolated[core or "none"] = probe.run()
    check("flash isolated total budget conserved", isolated["flash"]["damage"]["burn"], isolated["none"]["damage"]["burn"])
    probe = lab("layers", horizon=2.01, burn_duration=p06["burn_duration"])
    probe.hit_stream(0.5, "fire")
    probe.add(2.001, "detonate", {"multiplier": g04_multiplier, "reignite_delay": g04["reapply_delay"]})
    layer_burst = probe.run()
    check("layer plus P06/G04 maximum inventory hand case", layer_burst["damage"]["detonation"], 2520)
    probe = lab("layers", horizon=2.51, burn_duration=p06["burn_duration"])
    for at in (0, 0.5, 1, 1.5, 2):
        probe.add(at, "hit", {"school": "fire", "coefficient": 0, "cast": str(at), "natural": True})
    probe.add(2.001, "detonate", {"multiplier": g04_multiplier, "reignite_delay": g04["reapply_delay"]})
    probe.run()
    check("post-consumption reignite starts from one layer", probe.burn.stacks, 1)

    ice_rows = []
    for control in cfg["fixtures"]["control_classes"]:
        for cadence in (0.25, 0.5, ice_cycle, 5.0):
            for core in (None, "erosion", "collapse"):
                probe = lab(core, horizon=30, control=control)
                probe.hit_stream(cadence, "ice")
                out = probe.run()
                ice_rows.append({"control": control, "cadence": cadence, "core": core or "none", **out})
                check(f"one consumption per ice window {control}/{cadence}/{core}", not set(out["consumed_tokens"]) & set(out["expired_tokens"]))
                if core == "erosion":
                    check(f"erosion gives up hard control {control}/{cadence}", out["control_seconds"], 0)
    for core, expected in (("erosion", 200), ("collapse", 150)):
        probe = lab(core, horizon=4)
        for at in (0, 0.1, 0.2):
            probe.add(at, "hit", {"school": "ice", "coefficient": 0, "cast": str(at), "natural": True})
        check(f"isolated {core} damage hand case", sum(probe.run()["damage"].values()), expected)
    probe = lab("erosion", horizon=4, window_duration=extended_window)
    for at in (0, 0.1, 0.2):
        probe.add(at, "hit", {"school": "ice", "coefficient": 0, "cast": str(at), "natural": True})
    check("I10 extended erosion window adds sixth tick", probe.run()["damage"]["erosion"], 240)
    probe = lab("collapse", horizon=4)
    for at in (0, 0.1, 0.2):
        probe.add(at, "hit", {"school": "ice", "coefficient": 0, "cast": str(at), "natural": True})
    probe.add(0.7, "shatter")
    out = probe.run()
    check("I07 consumption suppresses automatic collapse", out["damage"].get("collapse", 0), 0)
    check("I07 retains its own extra200", out["damage"].get("manual_shatter", 0), 200)
    check("early shatter ends control at0.5s", out["control_seconds"], 0.5)
    probe = lab("erosion", horizon=4)
    for at in (0, 0.1, 0.2):
        probe.add(at, "hit", {"school": "ice", "coefficient": 0, "cast": str(at), "natural": True})
    probe.add(0.71, "shatter")
    out = probe.run()
    check("early shatter cancels remaining erosion ticks", out["damage"].get("erosion", 0), 40)
    check("erosion still permits ordinary I07 extra damage", out["damage"].get("manual_shatter", 0), 200)

    mixed_rows = []
    for cadence in (0.1, 0.5, 1.35):
        for core in (None, "weave", "thermal"):
            for neighbors in cfg["fixtures"]["valid_neighbors"]:
                probe = lab(core, horizon=30, neighbors=neighbors)
                probe.hit_stream(cadence, "fire", coefficient=1)
                probe.hit_stream(cadence * ice_cycle / cycle(base["spells"]["F01"], basic, base), "ice", coefficient=1.2, start=0.15)
                out = probe.run()
                mixed_rows.append({"cadence": cadence, "neighbors": neighbors, "core": core or "none", **out})
                if core in ("weave", "thermal"):
                    gap = cfg["cores"][core]["cooldown"]
                    check(f"shared cooldown bounded {cadence}/{core}/{neighbors}", all(b - a >= gap - EPS for a, b in itertools.pairwise(out["trigger_times"])))
    for core in ("weave", "thermal"):
        probe = lab(core, horizon=10)
        probe.hit_stream(0.1, "fire", natural=False)
        # Additional casts cannot charge interweave. Thermal still responds to actual statuses,
        # but no frost exists in this fixture, so it cannot manufacture a reaction.
        out = probe.run()
        check(f"no free {core} from single school", out["metrics"].get(f"{core}_triggers", 0), 0)
    probe = lab("weave", horizon=3)
    for at, school, natural, cast in ((0, "fire", True, "a"), (.1, "ice", True, "b"), (.2, "fire", False, "c"), (.3, "ice", True, "b")):
        probe.add(at, "hit", {"school": school, "coefficient": 0, "natural": natural, "cast": cast})
    check("weave excludes extra casts and duplicate hit identity", probe.run()["metrics"].get("weave_triggers", 0), 0)
    probe = lab("thermal", horizon=4, neighbors=3)
    probe.add(0, "hit", {"school": "fire", "coefficient": 0, "cast": "f", "natural": True})
    for n, at in enumerate((0.1, 0.2, 0.3)):
        probe.add(at, "hit", {"school": "ice", "coefficient": 0, "cast": str(n), "natural": True})
    thermal_single = probe.run()
    check("thermal full fuel primary hand case", thermal_single["damage"]["thermal_primary"], 400)
    check("thermal at most3 half-damage neighbors", thermal_single["damage"]["thermal_neighbors"], 600)
    check("thermal cancels old burn ticks", thermal_single["damage"].get("burn", 0), 0)
    check("thermal consumes window once", len(thermal_single["consumed_tokens"]), 1)

    ttk_rows = []
    best_stat = best["starter"]["stats"]
    trials = cfg["fixtures"]["ttk_trials"]
    if trials < 1:
        raise ValueError("Positive trial count required")
    for hp in cfg["fixtures"]["ttk_target_health"]:
        for label, stat, core in (("no_gems", basic, None), ("four_optimized_ordinary", best_stat, None),
                                  ("same_ordinary_plus_flash", best_stat, "flash"), ("same_ordinary_plus_layers", best_stat, "layers")):
            times, hits = [], []
            for n in range(trials):
                probe = StatusLab(cfg, base, fire, ice, stat, core=core, horizon=120,
                                  target_health=hp, seed=cfg["fixtures"]["seed"] + n, critical=True)
                probe.hit_stream(cycle(spec, stat, base), "fire", coefficient=spec["levels"][0]["coefficient"])
                out = probe.run()
                if out["ttk"] is None:
                    raise AssertionError("TTK fixture did not terminate within120s")
                times.append(out["ttk"])
                hits.append(out["metrics"]["hits"])
            ttk_rows.append({"health": hp, "case": label, "trials": trials, "mean": statistics.mean(times),
                             "p10": quantile(times, .1), "p50": quantile(times, .5), "p90": quantile(times, .9), "mean_hits": statistics.mean(hits)})

    sweeps = []
    for name, candidates in cfg["sweeps"].items():
        for value in candidates:
            candidate = deepcopy(cfg)
            if name == "ordinary_value_scale":
                counts = best["starter"]["counts"]
                changed = stats(base, generic, {}, counts, values(cfg, scale=value))
                metric = direct_dps(spec, changed, base) / direct_dps(spec, basic, base) - 1
                key = "fixed_layout_direct_gain"
            elif name == "prism_transfer_fraction":
                candidate["cores"]["prism"]["bonus_transfer_fraction"] = value
                metric = prism_pack([300, 50, 50], 100, 2, candidate, True)
                key = "synthetic_pack_casts"
            elif name == "blood_life_conversion":
                candidate["cores"]["blood"]["life_conversion"] = value
                metric = blood_stats(basic, candidate)["ehp"]
                key = "first_room_ehp"
            else:
                core, parameter = {
                    "flash_time_scale": ("flash", "time_scale"),
                    "layer_tick_coefficient": ("layers", "tick_coefficient_per_layer"),
                    "weave_coefficient": ("weave", "coefficient"),
                    "erosion_tick_coefficient": ("erosion", "coefficient"),
                    "collapse_coefficient": ("collapse", "coefficient"),
                    "thermal_base_coefficient": ("thermal", "base_coefficient")
                }[name]
                candidate["cores"][core][parameter] = value
                probe = StatusLab(candidate, base, fire, ice, neutral, core=core, horizon=30, neighbors=3)
                if core in ("flash", "layers", "weave", "thermal"):
                    probe.hit_stream(1.35, "fire")
                if core in ("weave", "thermal", "erosion", "collapse"):
                    probe.hit_stream(ice_cycle, "ice", start=0.15)
                metric = sum(probe.run()["damage"].values())
                key = "isolated_status_and_core_damage_30s"
            sweeps.append({"parameter": name, "value": value, "metric": key, "result": metric})

    targets = []
    actuals = {
        "ordinary_optimized_direct_gain": best["starter"]["gain"],
        "defense_four_gem_first_room_ehp_gain": defense["ehp"] / basic["ehp"] - 1,
        "layer_full_rate_multiple": cfg["cores"]["layers"]["cap"] * cfg["cores"]["layers"]["tick_coefficient_per_layer"] / fire["fire"]["burning"]["coefficient"],
        "single_isolated_flash_total_multiple": isolated["flash"]["damage"]["burn"] / isolated["none"]["damage"]["burn"]
    }
    for name, band in cfg["targets"].items():
        actual = actuals[name]
        status = "within" if band[0] - EPS <= actual <= band[1] + EPS else ("below" if actual < band[0] else "above")
        targets.append({"name": name, "target": band, "actual": actual, "status": status})
    after = {str(v.relative_to(ROOT)).replace("\\", "/"): sha(v) for v in source_paths.values()}
    check("runtime source bytes unchanged by model", hashes, after)
    report = {
        "model_version": MODEL_VERSION, "model_sha256": sha(__file__), "parameter_version": cfg["version"], "parameters_sha256": sha(args.parameters),
        "source_sha256": hashes, "model_validation_cases": validation,
        "model_changes": ["1.0: isolated continuous-time model, not a route replay", "1.1: baseline gating, equal-DPS tie resolved by first-room EHP, longer-target fixture, converted-heal and canceled-erosion regression cases"],
        "parameters": cfg, "profiles": profiles, "enumerated_legal_count_vectors": enumeration_count,
        "ordinary_best": best, "defensive_four_gem_stats": defense,
        "blood_base_stats": blood, "blood_with_defensive_gems": blood_stats(defense, cfg),
        "raw_burst_probe": burst_cases,
        "prism": prism_results, "fire_scenarios": fire_rows, "layer_maximum_inventory": layer_burst,
        "ice_scenarios": ice_rows, "mixed_scenarios": mixed_rows, "thermal_single": thermal_single,
        "ttk_distributions": ttk_rows, "seed": cfg["fixtures"]["seed"], "sweeps": sweeps,
        "targets_and_guardrails": targets,
        "assumptions_and_omissions": [
            "Stationary synthetic target, all scheduled hits connect; target positions/AI/player survival not simulated",
            "Continuous events rather than120Hz engine steps; no Godot API or runtime core invoked",
            "Ordinary optimization uses F01 level1 normalized direct DPS only; it is not total build/route DPS",
            "Status rows separate component damage from direct damage; neighbor counts are valid-target assumptions, not real geometry",
            "No gacha price/probability/pity model; no account save migration or gem inventory implementation",
            "TTK fixtures start at first impact, omit flight/travel, use one level1F01 with legitimate burning",
            "Only explicit isolated P06/G04/I07/I10 boundary probes; no claim of exhaustive treasure/skill interaction coverage"
        ]
    }
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = ["# Magic gem isolated numerical proposal", "", f"Model: {MODEL_VERSION}",
             f"Validation: {sum(v['pass'] for v in validation)}/{len(validation)}; source files unchanged: {hashes == after}",
             f"Legal purple/gold count vectors: {enumeration_count}", "", "## Ordinary first pass", ""]
    for name, result in best.items():
        lines.append(f"- {name}: best normalized F01 direct gain {result['gain']:.2%}; counts {result['counts']}")
    lines += [f"- Four defensive gems: first-room raw EHP {defense['ehp']:.2f}, gain {defense['ehp']/basic['ehp']-1:.2%}",
              f"- Blood core base: health {blood['health']}, shield {blood['shield']}, EHP {blood['ehp']}", "", "## Target checks", ""]
    lines += [f"- {v['name']}: {v['actual']:.6f} vs {v['target']} => {v['status']}" for v in targets]
    lines += ["", "## F01 deterministic-seed TTK distributions", "", "| HP | Case | Mean | P10 | P50 | P90 | Mean hits |", "|---|---|---|---|---|---|---|"]
    lines += [f"| {r['health']} | {r['case']} | {r['mean']:.4f} | {r['p10']:.4f} | {r['p50']:.4f} | {r['p90']:.4f} | {r['mean_hits']:.4f} |" for r in ttk_rows]
    lines += ["", "## Limitations", ""] + [f"- {v}" for v in report["assumptions_and_omissions"]]
    (args.output / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    failures = [v for v in validation if not v["pass"]]
    print(json.dumps({"model": MODEL_VERSION, "checks": len(validation), "failed": len(failures),
                      "legal_vectors": enumeration_count, "targets": targets, "output": str(args.output)}, ensure_ascii=False))
    for failure in failures:
        print(json.dumps(failure, ensure_ascii=False))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
