"""Offline proposal accounting: waves, geometry and contact cadence, no Godot."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_CONFIG = Path(__file__).with_name("parameters.json")
DEFAULT_OUT = ROOT / "build/qa/nonboss-difficulty-design-20261020"
DEFAULT_BASELINE = Path(__file__).with_name("baseline")
RANGED = {"A", "F", "R", "W", "EF"}


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def body_timeline(config, base, *, group="small", stage=0, fps=60, frozen=False, swap=False, attack=False):
    """Proposed global contact clock sampled by the existing 120 Hz time base.

    Assumes continuous overlap; ignores defense, gear, movement and attack AI.
    Display fps only changes how the same fixed ticks are delivered.
    """
    tick = 0
    accumulator = 0.0
    ready_contact = 0.0
    protected_until = -1.0
    hits = []

    def attempt(t):
        nonlocal ready_contact, protected_until
        active_charge = attack and 0.9 - 1e-9 <= t <= 1.7 + 1e-9
        attack_due = attack and abs(t - 1.6) < 1e-6
        if t < protected_until - 1e-9:
            return
        if attack_due:
            hits.append({"time": round(t, 6), "kind": "attack", "damage": 38})
            protected_until = t + base["player"]["hurt_invulnerability"]
        elif not frozen and not active_charge and t >= ready_contact - 1e-9:
            # Actor swapping intentionally does not reset the player clock.
            damage = config["body_contact"]["damage_by_group"][group][stage]
            hits.append({"time": round(t, 6), "kind": "body", "damage": damage,
                         "actor": int(t * 10) % 2 if swap else 0})
            ready_contact = t + config["body_contact"]["player_contact_interval"]
            protected_until = t + base["player"]["hurt_invulnerability"]

    attempt(0.0)
    for _ in range(4 * fps):
        accumulator += 1 / fps
        while accumulator + 1e-10 >= 1 / 120:
            tick += 1
            attempt(tick / 120)
            accumulator -= 1 / 120
    return hits


def build_report(config, baseline_root):
    base = read(baseline_root / "data/balance_candidates/first_run_v1.json")
    runtime = read(baseline_root / "data/route_enemy_runtime.json")
    current = read(baseline_root / "data/courtyard_route.json")
    first = read(baseline_root / "data/first_room_runtime.json")
    results, room_rows, stage_rows = [], [], []

    def check(name, valid, detail=None):
        results.append({"check": name, "pass": bool(valid), "detail": detail})

    def pressure(room):
        return next(s for s in runtime["stat_stages"] if s["from"] <= room <= s["to"])

    def health(type_id, room):
        if type_id in runtime["types"] and runtime["types"][type_id].get("variant_of"):
            t = runtime["types"][type_id]
            return health(t["variant_of"], room) * t["health_multiplier"]
        if type_id.startswith("EL"):
            initial = next(e["health"] for e in base["elites"] if e["id"] == type_id)
            return initial * pressure(room)["elite"]["health"]
        early = base["normal_stages"][0]["stats"].get(type_id, runtime["early_stats"].get(type_id))
        return early["health"] * pressure(room)["normal"]["health"]

    def candidate_hp(pack, room, light_override=None):
        total = 0.0
        for key, count in pack.items():
            unit = config["roster"][key]
            factor = unit["health_factor"]
            if light_override is not None and key in ["S", "A", "F", "R", "W"]:
                factor = light_override
            if room in config["health_budget"]["teaching_rooms_preserved"]:
                factor = 1.0
            total += count * health(unit["health_reference"], room) * factor
        return total

    expected_rooms = [r for r in range(1, 61) if r not in config["boss_rooms"]]
    check("exactly 56 non-Boss rooms", [r["room"] for r in config["rooms"]] == expected_rooms)
    check("known baseline M01 room 1", health("M01", 1) == 180)
    check("known baseline M02 room 59", health("M02", 59) == 5120)
    check("known baseline EL02 room 12", health("EL02", 12) == 10400)
    for index, stage in enumerate(config["stages"]):
        rows = [r for r in config["rooms"] if stage["from"] <= r["room"] <= stage["to"]]
        for row in rows:
            room = row["room"]
            check("wave count in stage budget", 1 <= len(row["waves"]) <= stage["max_waves"], room)
            for wave in row["waves"]:
                check("all units positive and introduced", all(k in config["roster"] and isinstance(v, int) and v > 0 and config["roster"][k]["introduced"] <= room for k, v in wave.items()), [room, wave])
                check("whole wave fits total alive cap", sum(wave.values()) <= stage["alive_cap"], [room, wave])
                check("whole wave fits ranged cap", sum(v for k, v in wave.items() if k in RANGED) <= stage["ranged_alive_cap"], [room, wave])
                check("ring/sweep/heavy caps", wave.get("R", 0) <= stage["ring_alive_cap"] and wave.get("W", 0) <= stage["sweep_alive_cap"] and sum(wave.get(k, 0) for k in ["C", "Z", "ES"]) <= stage["heavy_alive_cap"], room)
            baseline = current["encounters_by_room"][str(room)]
            baseline_total = sum(sum(w.values()) for w in baseline["packs"])
            baseline_hp = sum(v * health(k, room) for w in baseline["packs"] for k, v in w.items())
            roster = {}
            for wave in row["waves"]:
                for key, n in wave.items():
                    roster[key] = roster.get(key, 0) + n
            hp = sum(candidate_hp(w, room) for w in row["waves"])
            room_rows.append({"room": room, "stage": stage["id"], "kind": row["kind"], "beat": row["beat"], "total": sum(roster.values()), "roster": roster, "wave_sizes": [sum(w.values()) for w in row["waves"]], "baseline_total": baseline_total, "baseline_health": baseline_hp, "proposed_health_proxy": hp, "health_ratio": hp / baseline_hp})
        section = [r for r in room_rows if r["stage"] == stage["id"]]
        stage_rows.append({"stage": stage["name"], "room_count": len(rows), "baseline_enemies": sum(r["baseline_total"] for r in section), "proposed_enemies": sum(r["total"] for r in section), "minimum": min(r["total"] for r in section), "maximum": max(r["total"] for r in section), "ordinary_minimum": min(r["total"] for r in section if r["kind"] == "normal"), "ordinary_maximum": max(r["total"] for r in section if r["kind"] == "normal"), "alive_cap": stage["alive_cap"], "baseline_health": sum(r["baseline_health"] for r in section), "proposed_health_proxy": sum(r["proposed_health_proxy"] for r in section), "health_ratio": sum(r["proposed_health_proxy"] for r in section) / sum(r["baseline_health"] for r in section)})
        band = config["targets"]["health_proxy_ratio_band"]
        check("stage health workload inside provisional observation band", band[0] <= stage_rows[-1]["health_ratio"] <= band[1], stage["name"])
        check("stage ends below prior room density", section[-1]["total"] < section[-2]["total"], stage["name"])

    spawn_rows = []
    geometries = [("first", first["room"])] + [(k, v["geometry"]) for k, v in current["templates"].items()]
    for key, geo in geometries:
        free = []
        radius = max(u["radius"] for u in config["roster"].values()) + 0.1
        for dz in config["spawn"]["north_portal_z_offsets"]:
            for fraction in config["spawn"]["north_x_fractions"]:
                x, z = geo["floor"]["width"] / 2 * fraction, geo["portal_center"][1] + dz
                legal = abs(x) + radius < geo["floor"]["width"] / 2 and abs(z) + radius < geo["floor"]["depth"] / 2
                for block in geo["blocks"]:
                    dx = max(abs(x - block["center"][0]) - block["size"][0] / 2, 0)
                    dy = max(abs(z - block["center"][1]) - block["size"][1] / 2, 0)
                    if dx * dx + dy * dy < radius * radius:
                        legal = False
                if legal:
                    free.append([x, z])
        check("new static north anchors support 12 actors", len(free) >= 12, [key, len(free)])
        spawn_rows.append({"template": key, "statically_valid_largest_body_slots": len(free), "ignores_dynamic_player_and_survivor_occupancy": True})

    diameter = base["player"]["radius"] * 2
    fan = config["patterns"]["F"]
    fan_gap = 2 * config["projectiles"]["new_pattern_min_start_distance"] * math.sin(math.radians(fan["step_degrees"] / 2)) - 2 * fan["radius"]
    ring_gaps = []
    for spokes in config["patterns"]["R"]["counts"][1:]:
        gap_angle = 360 / spokes * (config["patterns"]["R"]["omitted_adjacent_spokes"] + 1)
        # Chord between the two bordering projectiles at 1m from the emitter.
        clear_width = 2 * math.sin(math.radians(gap_angle / 2)) - 2 * config["patterns"]["R"]["radius"]
        check("ring authored gap fits player plus margin at 1m", clear_width >= diameter + 0.2, [spokes, clear_width])
        ring_gaps.append({"nominal_spokes": spokes, "actual_projectiles": spokes - 3, "opening_degrees": gap_angle, "clear_chord_at_1m": clear_width})
    check("fan adjacent gap fits player at firing distance", fan_gap >= diameter + 0.2, fan_gap)

    contact_rows = []
    for fps in [30, 60, 120, 144]:
        for name, kwargs in [("early_body_overlap", {}), ("extreme_elite_overlap", {"group": "elite", "stage": 3}), ("alternating_bodies", {"swap": True}), ("frozen_body", {"frozen": True}), ("charge_overlap", {"attack": True})]:
            hits = body_timeline(config, base, fps=fps, **kwargs)
            if name in ["early_body_overlap", "alternating_bodies", "extreme_elite_overlap"]:
                check("contact interval gives six hits including t=0 in four seconds", len(hits) == 6, [fps, name])
            if name == "frozen_body":
                check("frozen bodies never contact hit", not hits, fps)
            if name == "charge_overlap":
                check("charge and body do not double hit", sum(h["kind"] == "attack" for h in hits) == 1 and not any(h["kind"] == "body" and 0.9 <= h["time"] <= 1.7 for h in hits), fps)
            check("all accepted hits respect existing hurt protection", all(b["time"] - a["time"] + 1e-6 >= base["player"]["hurt_invulnerability"] for a, b in zip(hits, hits[1:])), [name, fps])
            contact_rows.append({"scenario": name, "display_fps": fps, "hits": hits, "raw_damage_without_defense": sum(h["damage"] for h in hits)})
    for name in {r["scenario"] for r in contact_rows}:
        versions = [r for r in contact_rows if r["scenario"] == name]
        check("contact cadence display-fps invariant", all(r["hits"] == versions[0]["hits"] for r in versions), name)

    sweeps = []
    for factor in config["sensitivity_light_health_factors"]:
        for stage in config["stages"]:
            rows = [r for r in config["rooms"] if stage["from"] <= r["room"] <= stage["to"]]
            hp = sum(candidate_hp(w, r["room"], factor) for r in rows for w in r["waves"])
            old = next(s["baseline_health"] for s in stage_rows if s["stage"] == stage["name"])
            sweeps.append({"stage": stage["name"], "shared_light_health_factor": factor, "health_ratio": hp / old})

    return {"model_version": "nonboss-offline-accounting-1", "proposal_version": config["version"], "model_contract": "Counts and exact formula proxies only; current native stage inheritance re-read as anchor. Proposed body clock is independently enumerated at 120Hz. Single-source angular gaps only, not full projectile/AI/path simulation. No RNG, win-rate, clear-time or natural-combat claim.", "checks": len(results), "failures": sum(not r["pass"] for r in results), "checks_detail": results, "stages": stage_rows, "rooms": room_rows, "spawn_static_checks": spawn_rows, "single_source_gap_checks": {"player_diameter": diameter, "fan_gap_at_min_distance": fan_gap, "ring": ring_gaps}, "contact_scenarios": contact_rows, "sensitivity": sweeps, "assumptions_and_omissions": ["Proposed role caps must also gate surviving actors, not only fresh waves.", "Static spawn checks omit current player and live actor occupancy; full safe reservation may still wait.", "Health sums are workload proxies. Area damage/control/build choices and Boss rewards are not simulated.", "No victory probability, route duration, multi-source escape guarantee, pixel visibility or performance conclusion."], "status": "proposal arithmetic checked; user review and later unified native testing pending"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--parameters", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--baseline-dir", type=Path, default=DEFAULT_BASELINE)
    args = parser.parse_args()
    config = read(args.parameters)
    report = build_report(config, args.baseline_dir)
    paths = [args.baseline_dir / p for p in config["runtime_sources"]] + [args.parameters, Path(__file__)]
    report["source_sha256"] = {p.relative_to(ROOT).as_posix(): digest(p) for p in paths}
    report["status"] = "historical approved proposal accounting; runtime implementation verified separately"
    report["baseline_scope"] = "Frozen pre-implementation sources; never apply the compensation twice to the new live runtime."
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"checks": report["checks"], "failures": report["failures"], "stages": report["stages"], "sensitivity": report["sensitivity"]}, ensure_ascii=False, indent=2))
    for failure in report["checks_detail"]:
        if not failure["pass"]:
            print("FAIL", failure)
    return int(report["failures"] > 0)


if __name__ == "__main__":
    raise SystemExit(main())
