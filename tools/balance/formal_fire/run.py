"""Reproducible controlled design scenarios, never edits game files or saves."""
from __future__ import annotations

import argparse
from collections import Counter
from copy import deepcopy
import csv
import math
from pathlib import Path
import random
import statistics
import time

from io_utils import DEFAULT_OUT, DEFAULT_PARAMETERS, ROOT, hashes, load, read, write
from model import MODEL_VERSION, Model
from validation import validate


def describe(values):
    return {"mean": statistics.mean(values), "median": statistics.median(values), "minimum": min(values),
            "maximum": max(values), "sample_sd": statistics.stdev(values) if len(values) > 1 else 0,
            "mean_standard_error": statistics.stdev(values)/math.sqrt(len(values)) if len(values) > 1 else 0,
            "count": len(values)}


def evaluate(inputs, scenario, profile, ids, level, horizon, seeds, metadata):
    runs = []
    for seed in seeds:
        result = Model(*inputs, scenario, profile, ids, level, seed, horizon).run()
        if result["failed_guards"]:
            raise AssertionError(result["failed_guards"])
        runs.append({"seed": seed, **{key: value for key, value in result.items() if key != "casts_at"}})
    sources = set().union(*(r["by_source"] for r in runs))
    spell_sources = set().union(*(r["by_spell"] for r in runs))
    metrics = set().union(*(r["metrics"] for r in runs))
    return {**metadata, "scenario": scenario["id"], "profile": profile["id"], "spell_ids": ids, "level": level,
            "horizon": horizon, "items": profile.get("items", []), "total": describe([r["damage"] for r in runs]),
            "by_source": {x: describe([r["by_source"].get(x, 0) for r in runs]) for x in sorted(sources)},
            "by_spell": {x: describe([r["by_spell"].get(x, 0) for r in runs]) for x in sorted(spell_sources)},
            "metrics": {x: describe([r["metrics"].get(x, 0) for r in runs]) for x in sorted(metrics)},
            "runs": runs}


def rain_math(params, base):
    geo = params["geometry"]
    radius = base["spells"]["F03"]["radius"]*geo["rain_scatter_fraction"]
    hit_radius = geo["rain_impact_radius"]+geo["actor_radius"]
    probability = min(1, (hit_radius/radius)**2)
    config = params["rain_probability_validation"]
    rng = random.Random(config["seed"])
    hits = sum(math.sqrt(rng.random())*radius <= hit_radius for _ in range(config["trials"]))
    observed = hits/config["trials"]
    rows = []
    for level, spec in enumerate(base["spells"]["F03"]["levels"], 1):
        drops = spec["drops"]
        ordinary = spec["coefficient"]
        first = params["spell_overrides"]["F03"]["first_drop_coefficient"]
        rows.append({"level": level, "drops": drops,
                     "current_random_expected_direct_coefficient": drops*ordinary*probability,
                     "current_all_hit_upper_direct_coefficient": drops*ordinary,
                     "candidate_expected_direct_coefficient": first+(drops-1)*ordinary*probability,
                     "candidate_all_hit_upper_direct_coefficient": first+(drops-1)*ordinary,
                     "candidate_first_drop_reliable_damage_zero_crit": first*base["player"]["attack"],
                     "with_B03_expected_direct_coefficient": 1.5*first+ordinary+(drops-2)*ordinary*probability,
                     "with_B03_all_hit_upper_direct_coefficient": 1.5*first+(drops-1)*ordinary})
    return {"scope": "Single stationary target exactly at rain center, radius .3, no crit/amplification; direct drops only; not moving-target accuracy or full damage",
            "uniform_disk_random_drop_hit_probability": probability, "monte_carlo_observed": observed,
            "seed": config["seed"], "trials": config["trials"], "absolute_error": abs(observed-probability),
            "guard_pass": abs(observed-probability) <= config["absolute_error_guard"], "levels": rows}


def cashout_math(params, base):
    rows = []
    for duration, maximum in ((params["burn"]["duration"], params["burn"]["maximum_future_ticks"]),
                              (params["new_profession_items"]["P06"]["burn_duration"], params["new_profession_items"]["P06"]["maximum_future_ticks"])):
        for level, multiplier in enumerate(params["burn"]["detonation_multiplier_by_F07_level"], 1):
            for count in range(maximum+1):
                base_value = count*params["burn"]["tick_coefficient"]*base["player"]["attack"]
                rows.append({"burn_duration": duration, "maximum_future_ticks": maximum, "future_ticks": count,
                             "F07_level": level, "unamplified_remaining_burn_value": base_value,
                             "normal_detonation": base_value*multiplier,
                             "G04_natural_detonation": base_value*(multiplier+params["new_profession_items"]["G04"]["detonation_multiplier_add"]),
                             "G04_extra_detonation": base_value*multiplier})
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--parameters", type=Path, default=DEFAULT_PARAMETERS)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--max-seeds", type=int, default=None)
    args = parser.parse_args()
    started = time.perf_counter()
    inputs = load(args.parameters)
    params, base, _, _ = inputs
    bridge = read(DEFAULT_OUT / "runtime_baseline.json")
    source_paths = list(bridge["source_hashes_before"])
    source_paths += ["tools/balance/formal_fire/"+name for name in ("runtime_baseline.gd", "baseline.py", "model.py", "io_utils.py", "run.py", "validation.py")]
    parameter_relative = args.parameters.resolve().relative_to(ROOT).as_posix()
    source_paths.append(parameter_relative)
    before = hashes(source_paths)
    validation = validate(args.parameters)
    write(args.out / "model_validation.json", validation)
    if validation["failures"]:
        raise AssertionError(validation["failures"])
    seeds = params["seeds"][:args.max_seeds] if args.max_seeds else params["seeds"]
    if not seeds:
        raise ValueError("Need at least one seed")
    rows = []
    for ident in params["retained_ids"]+list(params["new_spells"]):
        for level in range(1, 4):
            for profile in params["profiles"][:2]:
                for scenario in params["scenarios"]:
                    for horizon in params["horizons"]:
                        rows.append(evaluate(inputs, scenario, profile, [ident], level, horizon, seeds, {"group": "spell", "build": ident}))
    print(f"FORMAL_FIRE spell scenarios={len(rows)} seeds={len(seeds)}", flush=True)
    skipped = []
    for build in params["builds"]:
        for profile in params["profiles"]:
            ids = build["spells"]
            if not set(profile.get("requires", [])) <= set(ids) or len(ids) < profile.get("minimum_spells", 1):
                skipped.append({"build": build["id"], "profile": profile["id"], "reason": "explicit fixture requirements not met"})
                continue
            for scenario in params["scenarios"]:
                for horizon in params["horizons"]:
                    rows.append(evaluate(inputs, scenario, profile, ids, 3, horizon, seeds, {"group": "build", "build": build["id"]}))
    print(f"FORMAL_FIRE with build scenarios={len(rows)}", flush=True)
    for probe in params["item_probes"]:
        for with_item in (False, True):
            profile = {"id": "with_item" if with_item else "control", "items": [probe["item"]] if with_item else []}
            if probe.get("shield_loss_feed"):
                profile["shield_loss_feed"] = probe["shield_loss_feed"]
            for scenario in params["scenarios"]:
                for horizon in params["horizons"]:
                    rows.append(evaluate(inputs, scenario, profile, probe["spells"], 3, horizon, seeds,
                                         {"group": "item", "build": probe["item"]}))
    math_result = rain_math(params, base)
    if not math_result["guard_pass"]:
        raise AssertionError("rain Monte Carlo disagrees with disk geometry")
    after = hashes(source_paths)
    if after != before:
        raise AssertionError("Bound source changed during model run")
    write(args.out / "rain_math.json", math_result)
    write(args.out / "cashout_math.json", cashout_math(params, base))
    write(args.out / "scenario_results.json", {"model_version": params["model_version"], "seeds": seeds,
                                               "scenarios": rows, "skipped_profile_build_pairs": skipped})
    csv_rows = []
    for row in rows:
        compact = {key: row[key] for key in ("group", "build", "scenario", "profile", "level", "horizon")}
        compact.update(damage_mean=row["total"]["mean"], damage_min=row["total"]["minimum"], damage_max=row["total"]["maximum"],
                       damage_sd=row["total"]["sample_sd"], damage_mean_se=row["total"]["mean_standard_error"],
                       dps_mean=row["total"]["mean"]/row["horizon"],
                       **{source+"_mean": row["by_source"].get(source, {}).get("mean", 0) for source in ("direct", "burn", "detonation", "profession_proc", "fixed_charge")},
                       **{metric+"_mean": row["metrics"].get(metric, {}).get("mean", 0) for metric in ("natural_casts", "extra_casts", "burn_ticks", "detonated_future_ticks", "propagated_targets", "reignites_applied", "g03_bursts", "shield_restored")})
        csv_rows.append(compact)
    args.out.mkdir(parents=True, exist_ok=True)
    with (args.out / "scenario_summary.csv").open("w", encoding="utf-8-sig", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=list(csv_rows[0]))
        writer.writeheader()
        writer.writerows(csv_rows)
    count_by_group = dict(Counter(row["group"] for row in rows))
    manifest = {"model_version": MODEL_VERSION, "parameter_version": params["model_version"], "status": "hypothetical_candidate_not_runtime", "parameters": parameter_relative,
                "seed_and_trial_count": {"seeds": seeds, "seeds_per_scenario": len(seeds), "scenarios": len(rows), "trajectories": len(rows)*len(seeds)},
                "group_counts": count_by_group, "validation": {"checks": validation["checks"], "failures": len(validation["failures"])},
                "native_bridge": {"cases": len(bridge["cases"]), "checks": bridge["checks"], "failures": len(bridge["failures"])},
                "invariant_failures": 0, "source_hashes_before": before, "source_hashes_after": after, "source_stable": before == after,
                "elapsed_seconds": time.perf_counter()-started, "assumptions_and_omissions": params["omissions"], "not_damage_valued_items": params["not_damage_valued_items"],
                "model_corrections_and_parameter_selection": params.get("selection_evidence", {}),
                "reproduction": "python tools/balance/formal_fire/run.py", "args": vars(args) | {"parameters": str(args.parameters), "out": str(args.out)}}
    write(args.out / "run_manifest.json", manifest)
    write(args.out / "EVIDENCE_STATUS.json", {"status": "current_run_valid", "model_version": MODEL_VERSION,
                                             "main_run_source_stable": before == after, "invariant_failures": 0})
    print(f"FORMAL_FIRE_COMPLETE scenarios={len(rows)} trajectories={len(rows)*len(seeds)} validation={validation['checks']}/0 source_stable={before == after}", flush=True)


if __name__ == "__main__":
    main()
