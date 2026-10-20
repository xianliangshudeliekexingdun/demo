"""Source-based damage/volley accounting and conservative projectile reservations.

Not a movement AI, hit-rate, performance, win-rate or natural route simulator.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import heapq
import itertools
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def source(proposal=False):
    frozen = read(HERE / "baseline.json")
    current = {p: read(ROOT / p) for p in frozen}
    if not proposal:
        return frozen, current
    current = copy.deepcopy(frozen)
    p = read(HERE / "accepted_proposal.json")
    r, n = current["data/route_enemy_runtime.json"], current["data/route_nonboss_runtime.json"]
    for i, stage in enumerate(r["stat_stages"]):
        for category in ("normal", "elite"):
            stage[category]["damage"] = p["attack_factors"][i]
            stage[category]["body_damage"] = p["body_factors"][i]
    r["boss_damage_by_room"] = p["boss_damage_by_room"]
    n["body_contact"]["base_damage_by_group"] = p["body_base"]
    n["projectiles"].update(p["projectiles"])
    n["teaching_aimed"] = p["teaching_aimed"]
    for i, stage in enumerate(n["stages"]):
        stage["projectile_cap"] = p["projectile_caps"][i]
    for key, patch in p["patterns"].items():
        n["patterns"][key].update(patch)
    return frozen, current


def full_duration(s):
    value = s["warning"] + s["recovery"]
    if s["behavior"] == "lunge":
        value += s["lunge_duration"] * s.get("lunges", 1)
        value += s.get("second_warning", 0) * (s.get("lunges", 1) - 1)
    elif s["behavior"] == "mark":
        value += s["active_duration"]
    elif s.get("barrage"):
        value += max(t for t, _ in emissions(s))
    return value


def spec(inputs, type_id, room):
    b, f, r, n = (inputs[p] for p in ("data/balance_candidates/first_run_v1.json", "data/first_room_runtime.json", "data/route_enemy_runtime.json", "data/route_nonboss_runtime.json"))
    definition = r["types"][type_id]
    if "variant_of" in definition:
        # Rebuild the unscaled parent, then apply this room exactly once.
        patched = copy.deepcopy(inputs)
        parent = copy.deepcopy(r["types"][definition["variant_of"]])
        parent.update(definition)
        parent.pop("variant_of")
        patched["data/route_enemy_runtime.json"]["types"][type_id] = parent
        s = spec(patched, type_id, room)
        s["health"] *= definition["health_multiplier"]
        s["damage"] *= definition["damage_multiplier"]
        return s
    if "base_type" in definition:
        id_ = definition["base_type"]
        s = copy.deepcopy(b["normal_types"][id_])
        s.update(b["normal_stages"][0]["stats"].get(id_, r["early_stats"].get(id_, {})))
        if "runtime_ref" in definition:
            s.update(f[definition["runtime_ref"]])
    else:
        elite = next(e for e in b["elites"] if e["id"] == definition["base_elite"])
        s = {"health": elite["health"], "damage": next(iter(elite["attacks"].values()))}
    s.update(definition)
    stage = next(st for st in r["stat_stages"] if st["from"] <= room <= st["to"])
    factors = stage["elite" if s["elite"] else "normal"]
    for key in ("health", "move_speed", "projectile_speed", "attack_cycle"):
        if key in s:
            s[key] *= factors[key]
    s["attack_cycle"] = max(s["attack_cycle"], full_duration(s))
    if room % 15 and type_id in n["types"]:
        i = (room - 1) // 15
        info = n["types"][type_id]
        raw_ref = info["health_reference"]
        if raw_ref != type_id:
            reference_factor = 1.0 if room <= 3 and raw_ref in ("M01", "M02") else n["types"][raw_ref]["health_factor"]
            s["health"] = spec(inputs, raw_ref, room)["health"] / reference_factor
        s["health"] *= 1.0 if room <= 3 and type_id in ("M01", "M02") else info["health_factor"]
        contact = n["body_contact"]
        s["body_damage"] = (contact["base_damage_by_group"][info["body_group"]] * factors.get("body_damage", 1) if "base_damage_by_group" in contact else contact["damage_by_group"][info["body_group"]][i])
        if info["pattern"]:
            p = {key: (value[i] if isinstance(value, list) else value) for key, value in n["patterns"][info["pattern"]].items()}
            if room <= 3 and info["pattern"] == "aimed":
                p.update(n.get("teaching_aimed", {}))
            p["count"] = p["counts"]
            p.setdefault("min_start_distance", 0 if info["pattern"] == "aimed" else n["projectiles"]["new_pattern_min_start_distance"])
            s["barrage"] = p
            s["attack_disabled"] = p["count"] <= 0
            if p["count"] > 0:
                s.update(warning=p["warning"], damage=p["damage"], projectile_speed=p["speed"], projectile_radius=p["radius"], projectile_range=n["projectiles"]["range"], attack_cycle=p["cycle"])
                s["attack_cycle"] = max(s["attack_cycle"], full_duration(s))
    s["damage"] *= factors.get("damage", 1)
    return s


def emissions(s):
    """Emission offsets from first release; ring count excludes missing spokes."""
    p = s.get("barrage", {})
    if not p:
        return [(0.0, len(s.get("spread_degrees", [])))]
    count = p["count"]
    if count <= 0:
        return []
    rows = []
    for volley in range(p.get("volleys", 1)):
        start = volley * p.get("release_interval", 0)
        if p["kind"] in ("fan", "ring"):
            rows.append((start, count - p.get("omitted_adjacent_spokes", 0)))
        else:
            rows.extend((start + i * p["shot_interval"], 1) for i in range(count))
    return rows


def capacity(inputs, room, roster, horizon, scale=1.0):
    """Discrete events; no impacts/walls/deaths: released bullets live max range.

    Whole packet reserved until its own emission. Uses warning/recovery floors,
    curtain and fast warning spacing. Rejection is a .25s retry, never truncation.
    Enemies have uninterrupted line of sight; movement/control are omitted.
    """
    n = inputs["data/route_nonboss_runtime.json"]
    stage = n["stages"][(room - 1) // 15]
    cap = int(stage["projectile_cap"] * scale)
    sources = [spec(inputs, key, room) for key, count in roster.items() for _ in range(count) if spec(inputs, key, room)["behavior"] == "shooter" and not spec(inputs, key, room).get("attack_disabled", False)]
    queue, counter = [], itertools.count()

    def add(t, kind, source, amount=0):
        heapq.heappush(queue, (round(t, 8), {"expire": 0, "release": 1, "start": 2}[kind], next(counter), kind, source, amount))

    for i in range(len(sources)):
        add(0, "start", i)
    live = reserved = peak = rejected = requests = starts = emitted = 0
    last_curtain = last_fast = -1000.0
    while queue:
        t, _, _, kind, i, amount = heapq.heappop(queue)
        if t > horizon:
            break
        s = sources[i]
        if kind == "expire":
            live -= amount
        elif kind == "release":
            reserved -= amount
            live += amount
            emitted += amount
            life = min(n["projectiles"]["lifetime"], s["projectile_range"] / s["projectile_speed"])
            add(t + life, "expire", i, amount)
        else:
            p = s.get("barrage", {})
            curtain = not p or p["kind"] != "aimed"
            fast = "fast_speed_threshold" in n["projectiles"] and s["projectile_speed"] >= n["projectiles"]["fast_speed_threshold"]
            ready = max(t, last_curtain + n["projectiles"]["curtain_start_spacing"] if curtain else t, last_fast + n["projectiles"].get("fast_start_spacing", 0) if fast else t)
            if ready > t + 1e-7:
                add(ready, "start", i)
                continue
            requests += 1
            shots = emissions(s)
            size = sum(count for _, count in shots)
            if live + reserved + size > cap:
                rejected += 1
                add(t + n["projectiles"]["retry_delay"], "start", i)
                continue
            starts += 1
            reserved += size
            if curtain:
                last_curtain = t
            if fast:
                last_fast = t
            for offset, count in shots:
                add(t + s["warning"] + offset, "release", i, count)
            add(t + max(s["attack_cycle"], full_duration(s)), "start", i)
        peak = max(peak, live + reserved)
        assert 0 <= live and 0 <= reserved and live + reserved <= cap
    return {"room": room, "roster": roster, "cap": cap, "peak": peak, "starts": starts, "emitted": emitted, "capacity_retries": rejected, "request_rejection_ratio": rejected / max(1, requests)}


def run(args):
    baseline, current = source(args.proposal)
    config = read(args.config)
    native_base = read(HERE / "native-baseline.json")
    checks, metrics, packets, survival = [], [], [], []

    def check(name, ok, detail=None):
        checks.append({"name": name, "pass": bool(ok), "detail": detail})

    check("hand baseline M02 room59 damage", spec(baseline, "M02", 59)["damage"] == 28)
    check("hand baseline missing-spoke ring is seventeen", sum(n for _, n in emissions(spec(baseline, "M06", 59))) == 17)
    check("regression teaching reference has no .8 health compensation", spec(baseline, "M05", 1)["health"] == 112)
    for inputs, native, label in ((baseline, native_base, "baseline"), (current, read(args.native) if args.native else None, "current")):
        if native:
            for room, room_specs in native["specs"].items():
                for key, actual in room_specs.items():
                    if key.startswith("BOSS"):
                        continue
                    predicted = spec(inputs, key, int(room))
                    for field in ("health", "damage", "body_damage", "warning", "move_speed", "projectile_speed", "attack_cycle"):
                        if field in actual:
                            check(f"{label} native {room}/{key}/{field}", abs(predicted[field] - actual[field]) < 0.001, [predicted.get(field), actual[field]])
            for row in native["cadence"]:
                predicted = spec(inputs, row["type"], row["room"])
                packet = sum(count for _, count in emissions(predicted))
                for a, b in zip(row["warnings"], row["warnings"][1:]):
                    check(f"{label} cadence period {row['room']}/{row['type']}", abs(b - a - predicted["attack_cycle"]) <= .04)
                    actual_count = sum(r["count"] for r in row["releases"] if a - 1e-6 <= r["time"] < b - 1e-6)
                    check(f"{label} complete packet {row['room']}/{row['type']}", actual_count == packet, [actual_count, packet])
    for room in (14, 29, 44, 59):
        stage_index = (room - 1) // 15
        for key in ("M01", "M02", "M03", "M04", "M05", "M06", "M07", "EL01", "EL02"):
            before, s = spec(baseline, key, room), spec(current, key, room)
            check(f"unchanged HP {room}/{key}", before["health"] == s["health"])
            if s.get("attack_disabled", False) or s["behavior"] != "shooter":
                continue
            count = sum(n for _, n in emissions(s))
            old_count = sum(n for _, n in emissions(before))
            p = s.get("barrage", {})
            check(f"full readable cycle {room}/{key}", s["attack_cycle"] + 1e-8 >= full_duration(s))
            row = {"room": room, "type": key, "base_damage": before["damage"], "damage": s["damage"], "speed": s["projectile_speed"], "old_speed": before["projectile_speed"], "bullets_per_activation": count, "old_bullets": old_count, "cycle": s["attack_cycle"], "old_cycle": before["attack_cycle"], "emissions_per_second": count / s["attack_cycle"], "old_emissions_per_second": old_count / before["attack_cycle"], "full_action": full_duration(s)}
            if key == "M02":
                distance = p.get("min_start_distance", 0)
                flight = max(0, distance - .3 - s["projectile_radius"]) / s["projectile_speed"]
                row["followup_reaction_seconds_at_start_distance"] = p["followup_warning"] + flight
                row["single_ray_reaction_margin"] = row["followup_reaction_seconds_at_start_distance"] - config["reaction_allowance"] - (.3 + s["projectile_radius"]) / 5
                check(f"fast ray reaction geometry {room}", row["single_ray_reaction_margin"] >= config["guardrails"]["single_ray_reaction_margin"])
            packets.append(row)
        for build in config["survival_cases"]:
            s = spec(current, "M02", room)
            multiplier = max(.55, 100 / (100 + build["defense"]))
            budget = build["health"] + build["shield"]
            survival.append({"room": room, "case": build["id"], "raw_damage": s["damage"], "damage_after_defense": s["damage"] * multiplier, "accepted_hits_to_exhaust_fresh_health_and_shield": math.ceil(budget / (s["damage"] * multiplier)), "baseline_hits": math.ceil(budget / (28 * multiplier)), "no_recovery_no_control": True})
        # Every authored pack; upper-bound role-capped all-slow composition too.
        n, route = current["data/route_nonboss_runtime.json"], current["data/courtyard_route.json"]
        packs = []
        for room_id, encounter in route["encounters_by_room"].items():
            if int(room_id) % 15 and (int(room_id) - 1) // 15 == stage_index:
                packs.extend(encounter["packs"])
        cap = n["stages"][stage_index]["ranged_alive_cap"]
        packs += [{"M05": cap}, {"M02": cap}]
        if stage_index >= 1:
            rings = n["stages"][stage_index]["ring_alive_cap"]
            packs.append({"M06": rings, "M05": cap - rings})
        unique = {json.dumps(p, sort_keys=True): p for p in packs}
        for p in unique.values():
            metrics.append(capacity(current, room, p, config["capacity_horizon"]))
        worst = max((r for r in metrics if r["room"] == room), key=lambda r: r["peak"])
        check(f"no capacity overflow {room}", worst["peak"] <= worst["cap"])
        check(f"capacity allows sustained pressure {room}", max(r["request_rejection_ratio"] for r in metrics if r["room"] == room) <= config["guardrails"]["capacity_rejection_ratio_max"])
    # HP/encounters/maps/rewards/economy do not secretly cancel stronger spells.
    check("all authored encounters and geometry unchanged", baseline["data/courtyard_route.json"] == current["data/courtyard_route.json"])
    check("player/spells baseline unchanged", baseline["data/balance_candidates/first_run_v1.json"] == current["data/balance_candidates/first_run_v1.json"])
    baseline_capacity = [capacity(baseline, row["room"], row["roster"], config["capacity_horizon"]) for row in metrics]
    sweep = []
    for scale in config["capacity_sweep"]:
        for room in (14, 29, 44, 59):
            section = [r for r in metrics if r["room"] == room]
            worst_peak = max(section, key=lambda r: r["peak"])
            worst_rejection = max(section, key=lambda r: r["request_rejection_ratio"])
            for worst in {json.dumps(r["roster"], sort_keys=True): r for r in (worst_peak, worst_rejection)}.values():
                sweep.append({"kind": "capacity", "scale": scale, **capacity(current, room, worst["roster"], config["capacity_horizon"], scale)})
    for scale in config["damage_sweep"]:
        for row in survival:
            build = next(b for b in config["survival_cases"] if b["id"] == row["case"])
            sweep.append({"kind": "damage", "scale": scale, "room": row["room"], "case": row["case"], "accepted_hits": math.ceil((build["health"] + build["shield"]) / (row["damage_after_defense"] * scale))})
    boss_rows = []
    for boss in current["data/route_boss_runtime.json"]["bosses"]:
        factor = current["data/route_enemy_runtime.json"].get("boss_damage_by_room", {}).get(str(boss["room"]), 1)
        boss_rows.append({"room": boss["room"], "multiplier": factor, "body_damage": boss["body_damage"] * factor, "pattern_damage": {f"{phase['id']}/{key}": p["damage"] * factor for phase in boss["phases"] for key, p in phase["patterns"].items()}})
    failed = [r for r in checks if not r["pass"]]
    versions = {label: {p: {"version": d.get("version"), "normalized_json_sha256": hashlib.sha256(json.dumps(d, sort_keys=True, ensure_ascii=False).encode()).hexdigest()} for p, d in inputs.items()} for label, inputs in (("baseline", baseline), ("current", current))}
    report = {"model_version": config["model_version"], "mode": "proposal" if args.proposal else "current", "inputs": versions, "parameters": config, "model_validation_cases": checks, "failures": failed, "packet_metrics": packets, "baseline_capacity_metrics": baseline_capacity, "capacity_metrics": metrics, "survival_reference_cases": survival, "boss_damage": boss_rows, "sensitivity": sweep, "assumptions_and_omissions": ["60s capacity scenarios retain full legal range/lifetime, uninterrupted sources. No collisions, deaths, movement or freezes; conservative occupancy envelope, not actual fight.", "Reference health/defense builds are fixtures, not the user's observed loadout; recovery/control and real hit probability excluded from hit-count table.", "Reaction gap uses start distance; player voluntarily approaching after lock reduces flight time.", "Native 20s one-source captures validate spec/cadence, not performance, complete route time or human difficulty."]}
    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Enemy pressure model: {len(checks)} checks, {len(failed)} failures, {len(metrics)} capacity cases")
    for room in (14, 29, 44, 59):
        row = next(r for r in packets if r["room"] == room and r["type"] == "M02")
        section = [r for r in metrics if r["room"] == room]
        print(f"room {room}: aimed {row['base_damage']} -> {row['damage']:g}, {row['bullets_per_activation']} shots @ {row['speed']:g}m/s; capacity peak {max(r['peak'] for r in section)}/{section[0]['cap']}, max retries {max(r['request_rejection_ratio'] for r in section):.1%}")
    for failure in failed[:8]:
        print("FAIL", failure)
    return bool(failed)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--proposal", action="store_true")
    parser.add_argument("--config", type=Path, default=HERE / "parameters.json")
    parser.add_argument("--native", type=Path)
    parser.add_argument("--out", type=Path, default=ROOT / "build/qa/enemy-pressure-20261020/model-current.json")
    raise SystemExit(run(parser.parse_args()))
