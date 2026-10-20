"""Reproducible design-only spatial checks; does not start or modify Godot."""
import argparse
from collections import Counter
import csv
import hashlib
import json
from math import hypot, isclose
from pathlib import Path
import random

from spatial import (Grid, box, free, spawn_slots, eligible_slots, reserve_batch,
                     valid_reservation, spike_clock, spike_contacts)

ROOT = Path(__file__).resolve().parents[3]


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=ROOT / "data/balance_candidates/room_spatial_v1.json")
    parser.add_argument("--scenarios", type=Path, default=Path(__file__).with_name("spatial_scenarios.json"))
    parser.add_argument("--out", type=Path, default=ROOT / "build/qa/room-spatial-20261017/selected")
    args = parser.parse_args()
    config, scenarios = load(args.config), load(args.scenarios)
    sources = {key: args.config.parent / config[key + "_parameters"]
               for key in ("metrics", "base", "ordinary_room", "economy", "meta")}
    metrics, base, ordinary, economy, meta = [load(sources[k]) for k in sources]
    width, depth = metrics["floor"]["width"], metrics["floor"]["depth"]
    radius, speed = base["player"]["radius"], base["player"]["move_speed"]
    rules, spikes, spawn = config["layout_rules"], config["spikes"], config["spawn"]
    margin, step = rules["walk_validation_margin"], scenarios["grid_step"]
    checks = []

    def check(name, condition):
        checks.append({"name": name, "pass": bool(condition)})
        if not condition:
            raise AssertionError(name)

    # Independently calculable fixtures, not copies of proposed content.
    fixture = Grid(8, 8, [box((0, 0), (2, 2))], .3, 0, .25)
    route = fixture.distances([fixture.nearest((-2, 0))])[fixture.nearest((2, 0))] * .25
    check("known_obstacle_detour_7m_not_direct_4m", isclose(route, 7))
    empty = Grid(8, 8, [], .3, .05, .25)
    check("known_1m_plate_grid_escape_1m", isclose(empty.escape_distance([box((0, 0), 1)], .3, .05), 1))

    normal_by_room = {r["room"]: r for r in ordinary["rooms"]}
    elite_by_room = {r["room"]: r for r in base["elites"]}
    boss_by_room = {r["room"]: r for r in base["bosses"]}
    mapping = {r["room"]: r for r in config["rooms"]}
    check("sixty_unique_rooms_no_gap", len(config["rooms"]) == 60 and set(mapping) == set(range(1, 61)))
    check("ordinary_special_partition", len(normal_by_room) == 50 and len(elite_by_room) == 7 and
          len(boss_by_room) == 3 and not (set(normal_by_room) & (set(elite_by_room) | set(boss_by_room))))
    check("ordinary_layout_intent_preserved", all(mapping[n]["layout"] == r["layout"] for n, r in normal_by_room.items()))
    check("legal_map_ids", all(r["layout"] in config["layouts"] and r["spikes"] in spikes["profiles"] for r in mapping.values()))
    check("at_most_two_plates_per_activation", all(len(g) <= 2 for groups in spikes["profiles"].values() for g in groups))
    check("positive_clock_inputs", min(spikes[k] for k in ("first_warning_after_room_start", "warning", "active", "rest_after_retract")) > 0)
    check("single_attempt_including_invulnerable_contact", spikes["max_damage_attempts_per_activation"] == 1 and
          spikes["invulnerable_contact_consumes_activation_attempt"])
    off_count = sum(r["spikes"] == "off" for r in mapping.values())
    check("majority_rooms_have_spikes", 60 - off_count > 30)

    portal = (0, depth / 2 - metrics["zones_bottom_to_top"][-1]["depth"] / 2)
    slots = spawn_slots(spawn)
    check("eight_areas_sixteen_slots", len(slots) == 16 and len(spawn["side_x"]) * len(spawn["anchor_z"]) == 8)
    check("slot_spacing", min(hypot(a[0] - b[0], a[1] - b[1]) for i, a in enumerate(slots)
                              for b in slots[i + 1:]) >= spawn["minimum_slot_spacing"] - 1e-9)
    combat_half = metrics["zones_bottom_to_top"][1]["depth"] / 2
    check("spawn_footprints_inside_combat_band", all(abs(p[1]) + spawn["normal_footprint_radius"] +
          spawn["static_clearance"] <= combat_half for p in slots))

    masks = {"none": [], **{k: [k] for k in spikes["plates"]},
             "diagonal_SW_NE": ["SW", "NE"], "diagonal_NW_SE": ["NW", "SE"],
             "all_four_guardrail": list(spikes["plates"])}
    geometry, sweeps, spawn_results = [], [], []
    grids, rectangles = {}, {}
    hazard_boxes = [box(p, spikes["plate_size"]) for p in spikes["plates"].values()]
    rng = random.Random(scenarios["seed"])
    all_spawn_rows = []
    for layout_id, layout in config["layouts"].items():
        rects = [box(b["center"], b["size"]) for b in layout["blocks"]]
        rectangles[layout_id] = rects
        solid_gap = min(min(r[0] + width / 2, width / 2 - r[2], r[1] + depth / 2,
                            depth / 2 - r[3]) for r in rects)
        check(f"{layout_id}:solid_wall_gap", solid_gap >= rules["minimum_solid_wall_gap"])
        check(f"{layout_id}:clear_central_strip", all(r[2] <= -rules["central_clear_width"] / 2 or
              r[0] >= rules["central_clear_width"] / 2 for r in rects))
        check(f"{layout_id}:blocks_in_combat", all(-combat_half <= r[1] <= r[3] <= combat_half for r in rects))
        pair_gaps = [hypot(max(a[0] - b[2], b[0] - a[2], 0), max(a[1] - b[3], b[1] - a[3], 0))
                     for i, a in enumerate(rects) for b in rects[i + 1:]]
        check(f"{layout_id}:between_blocks_gap", min(pair_gaps) >= rules["minimum_solid_wall_gap"])
        grid = Grid(width, depth, rects, radius, margin, step)
        grids[layout_id] = grid
        normal_grid = Grid(width, depth, rects, rules["agent_probe_radius"], margin, step)
        check(f"{layout_id}:normal_agent_connected", len(normal_grid.distances([normal_grid.nearest(spawn["major_enemy_center"])])) == len(normal_grid.nodes))
        check(f"{layout_id}:major_center_reservation", free(spawn["major_enemy_center"], width, depth, rects,
              spawn["major_footprint_radius"], spawn["static_clearance"]))
        check(f"{layout_id}:all_spawn_slots_static_clear", len(eligible_slots(slots, spawn["entry_player_center"], [], rects,
              hazard_boxes, width, depth, spawn, ordinary["spawn"]["safe_player_distance"])) == len(slots))
        for mask_id, ids in masks.items():
            hazards = [box(spikes["plates"][p], spikes["plate_size"]) for p in ids]
            safe = grid.safe_nodes(hazards, radius, margin)
            reached = grid.distances([grid.nearest(spawn["entry_player_center"])], safe)
            check(f"{layout_id}:{mask_id}:safe_grid_connected", len(reached) == len(safe))
            check(f"{layout_id}:{mask_id}:entry_to_portal", grid.nearest(portal) in reached)
            distance = grid.escape_distance(hazards, radius, margin)
            profiles = {k: round(spikes["warning"] - p["reaction"] - distance /
                                (speed * p["effective_speed_ratio"]), 6)
                        for k, p in scenarios["escape_profiles"].items()}
            check(f"{layout_id}:{mask_id}:warning_escape_margin", min(profiles.values()) >= scenarios["minimum_escape_margin"])
            geometry.append({"layout": layout_id, "mask": mask_id, "walkable_nodes": len(grid.nodes),
                             "safe_nodes": len(safe), "safe_grid_connected": len(reached) == len(safe),
                             "entry_to_portal": grid.nearest(portal) in reached,
                             "worst_escape_m": distance, "escape_margin_seconds": profiles})
        for size in scenarios["plate_size_sweep"]:
            hazards = [box(p, size) for p in spikes["plates"].values()]
            distance = grid.escape_distance(hazards, radius, margin)
            for warning in scenarios["warning_sweep"]:
                worst = min(warning - p["reaction"] - distance / (speed * p["effective_speed_ratio"])
                            for p in scenarios["escape_profiles"].values())
                sweeps.append({"layout": layout_id, "plate_size": size, "warning": warning,
                               "worst_escape_m": distance, "minimum_margin_seconds": round(worst, 6),
                               "passes_declared_margin": worst >= scenarios["minimum_escape_margin"]})

        probes = rng.sample(sorted(grid.nodes), min(scenarios["slot_capacity_player_probes"], len(grid.nodes)))
        capacities = [len(eligible_slots(slots, grid.world(p), [], rects, hazard_boxes, width, depth, spawn,
                                         ordinary["spawn"]["safe_player_distance"])) for p in probes]
        reinforcement_rooms = [r for r in normal_by_room.values() if len(r["packs"]) > 1]
        trial_count, deferred = scenarios["reinforcement_trials_per_layout"], 0
        for i in range(trial_count):
            player = grid.world(rng.choice(sorted(grid.nodes)))
            existing = []
            for _ in range(i % (ordinary["spawn"]["next_batch_when_alive_at_most"] + 1)):
                candidates = [normal_grid.world(p) for p in sorted(normal_grid.nodes)
                              if hypot(normal_grid.world(p)[0] - player[0], normal_grid.world(p)[1] - player[1]) > radius + rules["agent_probe_radius"]]
                point = rng.choice(candidates)
                if all(hypot(point[0] - e[0], point[1] - e[1]) >= rules["agent_probe_radius"] + e[2] for e in existing):
                    existing.append((*point, rules["agent_probe_radius"]))
            origin = rng.choice(reinforcement_rooms)
            size = sum(origin["packs"][1].values())
            stage_index = next(j for j, s in enumerate(base["normal_stages"])
                               if s["from"] <= origin["room"] <= s["to"])
            cap = ordinary["spawn"]["alive_cap_by_normal_stat_stage"][stage_index]
            picked = reserve_batch(slots, player, existing, rects, hazard_boxes, width, depth,
                                   spawn, ordinary["spawn"], size, cap, rng)
            if picked is None:
                deferred += 1
            else:
                check(f"{layout_id}:reinforcement_{i}_reservation_valid", valid_reservation(picked, player, existing,
                      rects, hazard_boxes, width, depth, spawn, ordinary["spawn"], cap) and len(picked) == size)
            all_spawn_rows.append({"layout": layout_id, "phase": "reinforcement", "trial": i,
                                   "source_room": origin["room"], "cap": cap,
                                   "size": size, "alive": len(existing), "deferred": picked is None})
        spawn_results.append({"layout": layout_id, "capacity_probes": len(probes), "min_eligible_slots_no_existing": min(capacities),
                              "max_eligible_slots_no_existing": max(capacities), "reinforcement_trials": trial_count,
                              "reinforcement_deferred": deferred})

    for n, r in normal_by_room.items():
        row, size = mapping[n], sum(r["packs"][0].values())
        rects, grid = rectangles[row["layout"]], grids[row["layout"]]
        stage_index = next(i for i, s in enumerate(base["normal_stages"]) if s["from"] <= n <= s["to"])
        cap = ordinary["spawn"]["alive_cap_by_normal_stat_stage"][stage_index]
        for i in range(scenarios["spawn_trials_per_normal_room"]):
            entry = spawn["entry_player_center"]
            player = (entry[0] + rng.uniform(-.4, .4), entry[1] + rng.uniform(-.15, .15))
            picked = reserve_batch(slots, player, [], rects, [], width, depth, spawn, ordinary["spawn"], size, cap, rng)
            check(f"room_{n}:initial_{i}_whole_batch", picked is not None and len(picked) == size and
                  valid_reservation(picked, player, [], rects, [], width, depth, spawn, ordinary["spawn"], cap))
            all_spawn_rows.append({"layout": row["layout"], "phase": "initial", "trial": i,
                                   "room": n, "size": size, "alive": 0, "deferred": picked is None})
    for n, major in {**elite_by_room, **boss_by_room}.items():
        check(f"room_{n}:major_entry_separation", hypot(spawn["major_enemy_center"][0] - spawn["entry_player_center"][0],
              spawn["major_enemy_center"][1] - spawn["entry_player_center"][1]) >= ordinary["spawn"]["safe_player_distance"])
        companions = major.get("adds", []) if n not in boss_by_room else []
        if companions:
            picked = reserve_batch(slots, spawn["entry_player_center"], [(*spawn["major_enemy_center"], spawn["major_footprint_radius"])],
                                   rectangles[mapping[n]["layout"]], [], width, depth, spawn, ordinary["spawn"],
                                   len(companions), max(ordinary["spawn"]["alive_cap_by_normal_stat_stage"]), rng)
            check(f"room_{n}:major_companion_slots", picked is not None and len(picked) == len(companions))

    # Whole-batch failure paths, not silently spawning a partial group.
    args0 = (slots, (0, -6), [], rectangles["open"], [], width, depth, spawn, ordinary["spawn"])
    check("blocked_all_slots_returns_no_batch", reserve_batch([], *args0[1:], 2, 8, rng) is None)
    check("capacity_cannot_fit_batch", reserve_batch(*args0, 3, 2, rng) is None)
    occupied = [(0, 1, .5), (1.5, 1, .5), (-1.5, 1, .5)]
    check("alive_trigger_blocks_preview", reserve_batch(slots, (0, -6), occupied, rectangles["open"], [],
          width, depth, spawn, ordinary["spawn"], 2, 8, rng) is None)
    picked = reserve_batch(*args0, 2, 8, rng)
    check("player_enters_reserved_point_invalidates_whole_preview", not valid_reservation(picked, picked[0], [],
          rectangles["open"], [], width, depth, spawn, ordinary["spawn"], 8))

    gap = ordinary["spawn"]["minimum_heavy_warning_start_gap"]
    clock = spike_clock(spikes, spikes["profiles"]["standard"], [], gap, scenarios["clock_horizon"])
    check("nominal_warning_starts_2_8_14", [round(e["start"], 6) for e in clock] == [2, 8, 14])
    check("diagonal_alternation", clock[0]["group"] == clock[2]["group"] and clock[0]["group"] != clock[1]["group"])
    heavy_clock = spike_clock(spikes, spikes["profiles"]["standard"], scenarios["heavy_request_fixture"], gap, scenarios["clock_horizon"])
    check("known_running_heavy_delays_first_spike_to_3point6", isclose(next(e["start"] for e in heavy_clock if e["kind"] == "spike"), 3.6))
    check("no_heavy_spike_window_overlap", all(b["start"] >= a["end"] + (gap if "heavy" in (a["kind"], b["kind"]) else 0) - 1e-9
          for a, b in zip(heavy_clock, heavy_clock[1:])))
    check("fixture_no_starvation", sum(e["kind"] == "heavy" for e in heavy_clock) == len(scenarios["heavy_request_fixture"]) and
          sum(e["kind"] == "spike" for e in heavy_clock) >= 2)
    event = clock[0]
    contacts = [event["active_start"] + .01 * i for i in range(20)]
    common = (18, 300, 100)
    invuln = base["player"]["hurt_invulnerability"]
    once = spike_contacts(event, contacts, *common, 0, invuln)
    check("continuous_contact_only_one_damage", once[0] == 300 and once[1] == 82 and once[3] == 18)
    reenter = spike_contacts(event, [event["active_start"], event["end"] - .01], *common, 0, invuln)
    check("reenter_same_activation_no_second_damage", reenter[1] == 82)
    check("late_entry_damage", spike_contacts(event, [event["end"] - .01], *common, 0, invuln)[3] == 18)
    check("retraction_boundary_no_damage", spike_contacts(event, [event["end"]], *common, 0, invuln)[3] == 0)
    check("invulnerable_attempt_no_late_catchup", spike_contacts(event, [event["active_start"], event["end"] - .01],
          *common, event["active_start"] + .4, invuln)[3] == 0)
    check("clear_cancels_pending_contact", spike_contacts(event, contacts, *common, 0, invuln, event["start"] + .1)[3] == 0)
    check("dead_actor_no_contact", spike_contacts(event, contacts, 18, 0, 0, 0, invuln)[3] == 0)
    check("shield_first_known_spill", spike_contacts(event, contacts, 30, 300, 20, 0, invuln)[:2] == (290, 0))

    pressure = []
    shields = {"base": base["player"]["shield"],
               "U02": base["player"]["shield"] + base["attribute_artifact_candidates"]["shield_max_flat"],
               "U02_MG02_level3": base["player"]["shield"] + base["attribute_artifact_candidates"]["shield_max_flat"] + meta["gems"]["MG02"]["flat_by_level"][-1]}
    for stage in base["normal_stages"]:
        n = stage["from"]
        e = next(s for s in economy["stages"] if s["from"] <= n <= s["to"])
        sd = spikes["damage_by_economy_stage"][e["id"]]
        for case in scenarios["pressure_cases"]:
            if case == "one_charger_hit_and_spike" and "M03" not in stage["stats"]:
                continue
            enemy = "M03" if "charger" in case else "M01"
            count = 2 if case.startswith("two") else 1
            total = count * stage["stats"][enemy]["damage"] + sd
            pressure.append({"rooms": [stage["from"], stage["to"]], "case": case,
                             "damage_before_recovery": total, "health_loss_by_shield_loadout":
                             {key: max(0, total - value) for key, value in shields.items()}})
    check("known_late_two_slimes_and_spike_26hp_base", pressure[-2]["damage_before_recovery"] == 126 and
          pressure[-2]["health_loss_by_shield_loadout"]["base"] == 26)
    check("known_late_two_slimes_1hp_U02_0hp_with_gem", pressure[-2]["health_loss_by_shield_loadout"]["U02"] == 1 and
          pressure[-2]["health_loss_by_shield_loadout"]["U02_MG02_level3"] == 0)

    input_paths = [args.config, args.scenarios, *sources.values(), Path(__file__), Path(__file__).with_name("spatial.py"),
                   Path(__file__).with_name("write_spatial_review.py")]
    result = {"model_version": "room-spatial-1.0", "status": "isolated_design_checks_passed_not_gameplay_acceptance",
              "input_sha256": {p.resolve().relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in input_paths},
              "checks_passed": len(checks), "checks": checks, "geometry": geometry, "sweeps": sweeps,
              "spawn": spawn_results, "spawn_trials": len(all_spawn_rows),
              "nominal_clock": clock, "heavy_fixture_clock": heavy_clock, "pressure": pressure,
              "shield_loadouts": shields,
              "room_counts": {"spikes": 60 - off_count, "off": off_count,
                              "spikes_by_economy_stage": {s["id"]: sum(r["spikes"] != "off" for n, r in mapping.items() if s["from"] <= n <= s["to"]) for s in economy["stages"]},
                              "layout": dict(Counter(r["layout"] for r in mapping.values()))},
              "limitations": ["Conservative square-expanded AABB, 0.25m grid, axis paths; no Godot collision or AI.",
                              "Static escape excludes enemies, projectiles and concurrent normal attacks; not a no-hit guarantee.",
                              "Spawn probes are seeded fixtures, not player probability or a proof every dynamic configuration can spawn immediately.",
                              "Heavy job durations are timing fixtures, not proposed boss attack durations.",
                              "Pressure checks count separated effective hits before recovery, excluding F10; no campaign win-rate model."]}
    args.out.mkdir(parents=True, exist_ok=True)
    save(args.out / "parameters_used.json", config)
    save(args.out / "scenarios_used.json", scenarios)
    save(args.out / "results.json", result)
    for filename, rows in (("sweeps.csv", sweeps), ("spawn_trials.csv", all_spawn_rows)):
        fields = list(dict.fromkeys(k for r in rows for k in r))
        with (args.out / filename).open("w", encoding="utf-8-sig", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
    print(json.dumps({"checks_passed": len(checks), "geometry_masks": len(geometry), "sweeps": len(sweeps),
                      "spawn_trials": len(all_spawn_rows), "spawn_summary": spawn_results,
                      "minimum_escape_margin": min(min(g["escape_margin_seconds"].values()) for g in geometry),
                      "out": str(args.out)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
