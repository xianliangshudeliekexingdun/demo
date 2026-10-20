"""Boss proposal accounting only: source anchors, timed shots, space and rewards.

This is deliberately not a copy of the game combat engine. Effective damage is
an editable scenario input, not a measured build or a predicted player policy.
"""
from __future__ import annotations

import argparse
import hashlib
import heapq
import json
import math
import random
from collections import Counter, deque
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def source_health(sources, type_id, room):
    base, enemy, nonboss = (sources[key] for key in ["base", "enemy", "nonboss"])
    definition = enemy["types"][type_id]
    if "variant_of" in definition:
        return source_health(sources, definition["variant_of"], room) * definition["health_multiplier"]
    stage = next(row for row in enemy["stat_stages"] if row["from"] <= room <= row["to"])
    if type_id.startswith("EL"):
        start = next(row["health"] for row in base["elites"] if row["id"] == type_id)
        return start * stage["elite"]["health"]
    original = definition.get("base_type", type_id)
    start = base["normal_stages"][0]["stats"].get(original, enemy["early_stats"].get(original))["health"]
    return start * stage["normal"]["health"]


def live_health(sources, type_id, room):
    if room % 15 == 0:
        return source_health(sources, type_id, room)
    info = sources["nonboss"]["types"][type_id]
    factor = 1 if room <= 3 and type_id in ["M01", "M02"] else info["health_factor"]
    return source_health(sources, info["health_reference"], room) * factor


def room_geometry(sources):
    result, occurrence = {}, Counter()
    route = sources["route"]
    for item in sources["spatial"]["rooms"]:
        room, layout = int(item["room"]), item["layout"]
        if room == 1:
            result[room] = sources["first"]["room"]
            continue
        options = route["layout_templates"][layout]
        template = options[occurrence[layout] % len(options)]
        occurrence[layout] += 1
        result[room] = route["templates"][template]["geometry"]
    return result


def clear(point, radius, geometry):
    x, z = point
    if abs(x) + radius > geometry["floor"]["width"] / 2 or abs(z) + radius > geometry["floor"]["depth"] / 2:
        return False
    for block in geometry["blocks"]:
        dx = max(0, abs(x - block["center"][0]) - block["size"][0] / 2)
        dz = max(0, abs(z - block["center"][1]) - block["size"][1] / 2)
        if dx * dx + dz * dz < radius * radius - 1e-9:
            return False
    return True


def reachable_points(geometry, player_radius):
    step = 0.5
    start = tuple(geometry["entry_player_center"])
    queue, visited = deque([start]), {start}
    while queue:
        x, z = queue.popleft()
        for point in [(x + step, z), (x - step, z), (x, z + step), (x, z - step)]:
            if point not in visited and clear(point, player_radius, geometry):
                visited.add(point)
                queue.append(point)
    return visited


def shot_times(pattern):
    kind = pattern["kind"]
    if kind == "fan":
        return [pattern["warning"]] * pattern["count"]
    if kind == "ring":
        count = pattern["count"] - pattern["omitted_adjacent_spokes"]
        return [pattern["warning"] + volley * pattern["release_interval"] for volley in range(pattern["volleys"]) for _ in range(count)]
    if kind in ["sweep", "aimed"]:
        return [pattern["warning"] + shot * pattern["shot_interval"] for shot in range(pattern["count"])]
    return []


def duration(pattern):
    kind = pattern["kind"]
    if "cycle" in pattern:
        return pattern["cycle"]
    if kind == "charge":
        active_end = pattern["warning"] + pattern["duration"]
    elif kind == "marks":
        active_end = pattern["warning"] + (pattern["count"] - 1) * pattern["mark_interval"] + pattern["active"]
    elif kind == "lines":
        active_end = pattern["warning"] + pattern["active"]
    else:
        active_end = max(shot_times(pattern))
    return active_end + pattern["recovery"]


def capacity(phase, cap, horizon, global_rules, add_pattern=None):
    """Conservative occupancy: no player/wall hits, range/lifetime still apply.

    Full pending volley is reserved before warning. One source serializes the
    authored sequence; the optional worst case keeps a ranged add alive forever.
    """
    queue, serial = [], 0
    reserved, alive, peak, stalls, emitted = 0, 0, 0, 0, 0
    positions = Counter()

    def push(time, priority, kind, detail):
        nonlocal serial
        serial += 1
        heapq.heappush(queue, (round(time, 9), priority, serial, kind, detail))

    push(0, 1, "start", "boss")
    if add_pattern:
        push(0, 1, "start", "add")
    while queue:
        now, _, _, kind, detail = heapq.heappop(queue)
        if now > horizon:
            break
        if kind == "expire":
            alive -= 1
        elif kind == "release":
            reserved -= 1
            alive += 1
            emitted += 1
            push(now + min(global_rules["projectile_lifetime"], global_rules["projectile_range"] / detail), 0, "expire", None)
        else:
            source = detail
            pattern = add_pattern if source == "add" else phase["patterns"][phase["sequence"][positions[source] % len(phase["sequence"])]]
            shots = shot_times(pattern)
            if reserved + alive + len(shots) > cap:
                stalls += 1
                push(now + global_rules["retry_delay"], 1, "start", source)
                continue
            reserved += len(shots)
            positions[source] += 1
            for when in shots:
                push(now + when, 2, "release", pattern["speed"])
            push(now + duration(pattern), 1, "start", source)
        peak = max(peak, reserved + alive)
        if reserved < 0 or alive < 0 or reserved + alive > cap:
            raise AssertionError("projectile conservation or cap violated")
    return {"peak_alive_plus_reserved": peak, "cap": cap, "capacity_retries": stalls, "emitted": emitted, "horizon": horizon, "cycle_seconds": sum(duration(phase["patterns"][name]) for name in phase["sequence"]), "worst_case_add_always_alive": add_pattern is not None}


def effective_damage_case(boss, dps, interval):
    """Discrete damage packets; zero armor/invulnerability/recovery gates."""
    if dps <= 0:
        return {"status": "no_damage", "seconds": None, "phase_entries": []}
    packet = dps * interval
    hits = math.ceil(boss["health"] / packet - 1e-12)
    remaining, current_phase, transitions = float(boss["health"]), 0, []
    for hit in range(1, hits + 1):
        remaining -= packet
        if remaining <= 1e-8:
            break  # death before threshold processing, no mandatory phase.
        destination = max(index for index, row in enumerate(boss["phases"]) if remaining / boss["health"] <= row["health_at_most"] + 1e-9)
        if destination > current_phase:
            transitions.append({"at": round(hit * interval, 3), "phase": destination + 1})
            current_phase = destination
    return {"status": "resolved", "seconds": round(hits * interval, 3), "packets": hits, "phase_entries": transitions}


def gold_offer(pool, owned, room, reward_rules, rng):
    candidates = sorted(set(pool) - set(owned))
    if not candidates:
        return [reward_rules["fallback_ids"][str(room)]]
    return rng.sample(candidates, min(reward_rules["max_choices"], len(candidates)))


class RewardRights:
    """Proposed two-right transaction, with eligibility supplied by each case."""
    def __init__(self, room, reward_rules, rng):
        self.room, self.rules, self.rng = room, reward_rules, rng
        self.book, self.gold, self.cached = False, False, None
        self.owned = set()

    def resolve_book(self):
        if self.book:
            return False
        self.book = True
        return True

    def open_gold(self, pool):
        if not self.book or self.gold:
            return []
        if self.cached is None:
            self.cached = gold_offer(pool, self.owned, self.room, self.rules, self.rng)
        return self.cached.copy()

    def claim_gold(self, item):
        if not self.book or self.gold or self.cached is None or item not in self.cached or item in self.owned:
            return False
        self.owned.add(item)
        self.gold = True
        return True

    def can_exit(self):
        return self.book and self.gold


def build(config, sources):
    checks, boss_rows, phase_rows, scenarios, geometry_rows, local_escapes = [], [], [], [], [], []

    def check(label, valid, detail=None):
        checks.append({"check": label, "pass": bool(valid), "detail": detail})

    base, route, common = sources["base"], sources["route"], config["global"]
    check("known native anchor EL02 room12", source_health(sources, "EL02", 12) == 10400)
    check("known native anchor M02 room59 after one compensation", live_health(sources, "M02", 59) == 4096)
    budgets, counts = [0.0] * 4, [0] * 4
    for room in range(1, 61):
        if room % 15 == 0:
            continue
        for pack in route["encounters_by_room"][str(room)]["packs"]:
            for type_id, count in pack.items():
                budgets[(room - 1) // 15] += live_health(sources, type_id, room) * count
                counts[(room - 1) // 15] += count
    check("known current non-Boss counts", counts == [104, 195, 266, 364])
    check("known current health workload", all(abs(a - b) < 1e-6 for a, b in zip(budgets, [129026, 570614, 1029773, 1647859])))
    known = {"health": 100, "phases": [{"health_at_most": 1.0}, {"health_at_most": 0.5}]}
    check("known discrete TTK 100 health / 30 damage per second", effective_damage_case(known, 30, 1)["seconds"] == 4)
    check("known one-packet kill has no forced phase", effective_damage_case(known, 1000, 1)["phase_entries"] == [])
    three_phase = {"health": 100, "phases": [{"health_at_most": 1.0}, {"health_at_most": 0.65}, {"health_at_most": 0.3}]}
    check("single packet can skip middle phase", [row["phase"] for row in effective_damage_case(three_phase, 80, 1)["phase_entries"]] == [3])
    check("zero DPS terminates without false victory", effective_damage_case(known, 0, 1)["status"] == "no_damage")
    check("four distinct Boss rooms", [row["room"] for row in config["bosses"]] == [15, 30, 45, 60])
    check("legacy three ids remain on their original rooms", {row["room"]: row["id"] for row in config["bosses"]} == {15: "BOSS01", 30: "BOSS04", 45: "BOSS02", 60: "BOSS03"})
    geometries = room_geometry(sources)
    for boss in config["bosses"]:
        room = boss["room"]
        anchor = source_health(sources, "EL02", boss["anchor_elite_room"])
        prior_health = sum(source_health(sources, type_id, room) * amount for pack in route["encounters_by_room"][str(room)]["packs"] for type_id, amount in pack.items())
        boss_rows.append({"room": room, "name": boss["name"], "health": boss["health"], "anchor_room": boss["anchor_elite_room"], "anchor_elite_health": anchor, "health_to_elite_ratio": round(boss["health"] / anchor, 3), "previous_placeholder_total_health": prior_health, "target_seconds": boss["target_seconds"], "effective_dps_assumption": boss["ordinary_effective_dps"]})
        check("slow movement below basic player speed room%d" % room, boss["move_speed"] < base["player"]["move_speed"])
        melee_clearance = 2.2 - boss["radius"] - base["player"]["radius"]
        check("level-one frost ring has an outside-body attack interval room%d" % room, melee_clearance > common["minimum_melee_safety_margin"])
        geometry = geometries[room]
        reach = reachable_points(geometry, base["player"]["radius"])
        check("Boss spawn statically clear room%d" % room, clear(common["spawn"], boss["radius"], geometry))
        melee_points = [p for p in reach if boss["radius"] + base["player"]["radius"] + common["minimum_melee_safety_margin"] <= math.dist(p, common["spawn"]) <= 2.2]
        check("entry reaches a melee attack position room%d" % room, len(melee_points) > 0)
        check("entry reaches reward forecourt room%d" % room, (0, geometry["portal_center"][1] - 2) in reach)
        geometry_rows.append({"room": room, "floor": geometry["floor"], "spawn": common["spawn"], "reachable_half_metre_samples": len(reach), "reachable_melee_samples": len(melee_points), "minimum_melee_clearance": round(melee_clearance, 3)})
        add_pattern = None
        if "summons" in boss:
            attack = sources["nonboss"]["patterns"]["aimed"]
            add_pattern = dict(kind="aimed", count=attack["counts"][3], speed=attack["speed"][3], warning=attack["warning"], shot_interval=attack["shot_interval"], recovery=0.8, cycle=attack["cycle"][3])
            check("summons remain two finite groups", boss["summons"]["groups_per_fight"] == 2 and len(boss["summons"]["groups"]) == 2)
        for phase in boss["phases"]:
            active_add = add_pattern if phase["health_at_most"] < 1.0 else None
            measured = capacity(phase, boss["projectile_cap"], common["capacity_horizon_seconds"], common, active_add)
            phase_rows.append({"room": room, "phase": phase["id"], **measured})
            check("serial patterns fit capacity without waiting %d %s" % (room, phase["id"]), measured["capacity_retries"] == 0)
            for name, pattern in phase["patterns"].items():
                check("warning and recovery positive %d %s %s" % (room, phase["id"], name), pattern["warning"] >= 1.1 and pattern["recovery"] >= 1.5)
                check("whole volley fits %d %s %s" % (room, phase["id"], name), len(shot_times(pattern)) <= boss["projectile_cap"])
                kind = pattern["kind"]
                if kind == "fan":
                    gap = 2 * 3 * math.sin(math.radians(pattern["step_degrees"] / 2)) - 2 * pattern["radius"]
                    check("fan individual gap at three metres %d %s" % (room, phase["id"]), gap >= 2 * base["player"]["radius"] + common["minimum_melee_safety_margin"])
                elif kind == "ring":
                    gap_angle = (pattern["omitted_adjacent_spokes"] + 1) * 360 / pattern["count"]
                    distance = boss["radius"] + base["player"]["radius"] + common["minimum_melee_safety_margin"]
                    gap = 2 * distance * math.sin(math.radians(gap_angle / 2)) - 2 * pattern["radius"]
                    check("ring gap exceeds player width just outside body %d %s" % (room, phase["id"]), gap >= 2 * base["player"]["radius"] + common["minimum_melee_safety_margin"])
                    if pattern["volleys"] > 1:
                        check("second ring has independent full warning", pattern["release_interval"] >= pattern["followup_warning"] >= 1.1)
                if kind in ["charge", "marks", "lines"]:
                    radius = pattern["half_width"] if kind == "charge" else pattern["radius"] if kind == "marks" else pattern["width"] / 2
                    exit_seconds = (radius + base["player"]["radius"] + 0.1) / base["player"]["move_speed"] + common["reaction_allowance"]
                    check("open-ground single-threat escape %d %s %s" % (room, phase["id"], name), exit_seconds < pattern["warning"])
                    local_escapes.append({"room": room, "phase": phase["id"], "attack": name, "escape_seconds": round(exit_seconds, 3), "warning": pattern["warning"], "scope": "single threat, unobstructed straight exit, not multi-source dodge proof"})
        for scenario in config["scenarios"]:
            outcome = effective_damage_case(boss, boss["ordinary_effective_dps"] * scenario["dps_multiplier"], scenario["damage_interval"])
            low, high = boss["target_seconds"]
            status = "within" if low <= outcome["seconds"] <= high else "below" if outcome["seconds"] < low else "above"
            scenarios.append({"room": room, "scenario": scenario["id"], "effective_dps_input": boss["ordinary_effective_dps"] * scenario["dps_multiplier"], **outcome, "ordinary_target_comparison": status})
            if scenario["id"] == "ordinary_assumption":
                check("ordinary conditional TTK within design band room%d" % room, status == "within")
            if scenario["id"] in ["strong_build", "burst_build"]:
                check("strong output shortens encounter without a minimum time", outcome["seconds"] < boss["health"] / boss["ordinary_effective_dps"])
    rewards, reward_rows = config["rewards"], []
    for size in [0, 1, 2, 3, 10]:
        rng = random.Random(20261020 + size)
        pool = ["G%02d" % i for i in range(size)]
        observed = Counter()
        for _ in range(1000):
            offer = gold_offer(pool, [], 15, rewards, rng)
            observed.update(offer)
            if not (1 <= len(offer) <= 3 and len(offer) == len(set(offer))):
                raise AssertionError("empty/duplicate gold offer in deterministic sampling")
        check("1000 gold offers nonempty and unique pool size%d" % size, sum(observed.values()) == 1000 * max(1, min(size, 3)))
        reward_rows.append({"eligible_pool_size": size, "seed": 20261020 + size, "draws": 1000, "offer_inclusion_counts": dict(observed), "all_options_gold_by_input_contract": True})
    check("four fallback ids preserve unique ownership", len(set(rewards["fallback_ids"].values())) == 4)
    rng = random.Random(20261020)
    owned = []
    for room in rewards["boss_rooms"]:
        offer = gold_offer([], owned, room, rewards, rng)
        check("exhausted pool still grants unique gold room%d" % room, offer[0] not in owned)
        owned.extend(offer)
        stage = next(row for row in sources["economy"]["stages"] if row["from"] <= room <= row["to"])
        check("proposed Boss coins preserve current placeholder income room%d" % room, stage["clear_gold"] + stage["elite_bonus"] == rewards["coin_clear_totals"][rewards["boss_rooms"].index(room)])
    rights = RewardRights(60, rewards, random.Random(20261020))
    initial_rng = rights.rng.getstate()
    check("gold waits for book without consuming RNG", rights.open_gold(["G01"]) == [] and rights.rng.getstate() == initial_rng and not rights.can_exit())
    check("book right resolves exactly once", rights.resolve_book() and not rights.resolve_book())
    offer = rights.open_gold(["G01", "G02", "G03", "G04"])
    current_rng = rights.rng.getstate()
    check("cancel or reentry retains actual gold offer", rights.open_gold(["OTHER"]) == offer and rights.rng.getstate() == current_rng)
    check("book alone cannot exit final room", not rights.can_exit())
    check("invalid gold choice is nonmutating", not rights.claim_gold("OTHER") and not rights.owned)
    check("final room exits only after both rights", rights.claim_gold(offer[0]) and rights.can_exit())
    check("replayed gold transaction cannot grant twice", not rights.claim_gold(offer[0]) and rights.open_gold(["G05"]) == [] and len(rights.owned) == 1)
    proposed_books = set(int(room) for room in route["reward_rooms"]) | set(rewards["boss_rooms"])
    proposed_chests = set(int(room) for room in route["artifact_reward_rooms"]) | set(rewards["boss_rooms"])
    check("four dual rewards produce 52 books and 12 chests", len(proposed_books) == 52 and len(proposed_chests) == 12)
    check("all non-Boss reward nodes stay exact", proposed_books - set(rewards["boss_rooms"]) == set(route["reward_rooms"]) and proposed_chests - set(rewards["boss_rooms"]) == set(route["artifact_reward_rooms"]) - set(rewards["boss_rooms"]))
    ice = sources["ice"]["mechanics"]
    check("Boss control plan matches existing fixed-strong rules", common["control_coeff"] == ice["frost"]["control_duration_coefficients"]["fixed_strong"] and common["slow_cap"] == ice["shared_slow_caps"]["fixed_strong"])
    check("body interval preserves current non-Boss rule", common["body_interval"] == sources["nonboss"]["body_contact"]["player_contact_interval"])
    sensitivities = []
    for factor in config["sensitivity_health_factors"]:
        rows = []
        for boss in config["bosses"]:
            adjusted = dict(boss, health=round(boss["health"] * factor))
            outcome = effective_damage_case(adjusted, boss["ordinary_effective_dps"], 0.5)
            rows.append({"room": boss["room"], "health": adjusted["health"], "conditional_seconds": outcome["seconds"], "within_ordinary_band": boss["target_seconds"][0] <= outcome["seconds"] <= boss["target_seconds"][1]})
        sensitivities.append({"health_factor": factor, "outcomes": rows})
    return {"model_version": "boss-proposal-accounting-1", "parameters_version": config["version"], "status": "proposal checked offline; user review and future gameplay validation pending", "model_contract": config["model_contract"], "checks": len(checks), "failures": sum(not row["pass"] for row in checks), "checks_detail": checks, "bosses": boss_rows, "phase_capacity": phase_rows, "scenarios": scenarios, "geometry": geometry_rows, "local_escape_checks": local_escapes, "gold_offer_sampling": reward_rows, "sensitivity": sensitivities, "assumptions_and_omissions": ["Effective DPS values are editable assumptions, not measured fire/ice/mixed builds.", "Conservative bullet occupancy omits wall and player hits; it does not simulate dodging or automatic targeting.", "Static grid and single-threat warnings do not prove a safe route against every multi-source combination.", "Golden fallback items and the full Boss/reward behavior remain draft; nothing is loaded by the game.", "No native gameplay, screenshots, population win rate, performance or total-route duration result."]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--parameters", type=Path, default=HERE / "parameters.json")
    parser.add_argument("--source-root", type=Path, default=HERE / "baseline")
    parser.add_argument("--out", type=Path, default=ROOT / "build/qa/boss-design-20261020")
    args = parser.parse_args()
    config = read(args.parameters)
    paths = dict(route="data/courtyard_route.json", enemy="data/route_enemy_runtime.json", nonboss="data/route_nonboss_runtime.json", first="data/first_room_runtime.json", base="data/balance_candidates/first_run_v1.json", spatial="data/balance_candidates/room_spatial_v1.json", economy="data/balance_candidates/run_economy_v1.json", ice="data/ice_spells_v1.json", generic="data/generic_artifacts_v1.json")
    sources = {key: read(args.source_root / name) for key, name in paths.items()}
    report = build(config, sources)
    report["source_sha256"] = {name: hashlib.sha256((args.source_root / name).read_bytes()).hexdigest() for name in paths.values()}
    report["parameter_sha256"] = hashlib.sha256(args.parameters.read_bytes()).hexdigest()
    report["tool_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"checks": report["checks"], "failures": report["failures"], "bosses": report["bosses"], "capacity": report["phase_capacity"], "scenario_seconds": [{"room": row["room"], "scenario": row["scenario"], "seconds": row["seconds"]} for row in report["scenarios"]]}, ensure_ascii=False, indent=2))
    for row in report["checks_detail"]:
        if not row["pass"]:
            print("FAIL", row)
    return int(report["failures"] > 0)


if __name__ == "__main__":
    raise SystemExit(main())
