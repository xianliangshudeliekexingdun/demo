"""Design-only deterministic parameter sweep; writes only its QA output folder."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
from time import perf_counter

from model import DrawRule, aggregate, offer_metrics, one_trajectory
from validation import validate

ROOT = Path(__file__).resolve().parents[3]
TOOLS = Path(__file__).resolve().parent
DEFAULT_OUT = ROOT / "build/qa/formal-spell-framework-20261018"


def write(path: Path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def batch(parameters: dict, source: dict, rule: DrawRule, school_count: int, policy: str, per_seed: int) -> dict:
    slots = int(source["base"]["limits"]["slots"])
    level = int(source["base"]["limits"]["spell_level"])
    offers = int(source["meta"]["spell_sampling_assumptions"]["offer_size"])
    school_size = int(parameters["spells_per_school"])
    rows = []
    batches = []
    for seed in parameters["seed_batches"]:
        current = [one_trajectory(school_count, school_size, rule, policy,
                                  int(seed) * 100000 + i, slots, level, offers,
                                  source["route"]["reward_rooms"], starter=int(parameters["starter_spell_index"]))
                   for i in range(per_seed)]
        rows.extend(current)
        batches.append({"base_seed": seed, "trials": per_seed, "mean_final_primary_slots": sum(row["final"]["primary_slots"] for row in current) / per_seed})
    result = aggregate(rows, slots, level)
    result.update({"active_schools": school_count, "spells_per_school": school_size,
                   "rule": rule.label, "policy": policy, "seed_batches": batches,
                   "all_primary_final_rate_mc_95_half_width": 1.96 * (result["all_primary_final_fraction"] * (1 - result["all_primary_final_fraction"]) / len(rows)) ** 0.5})
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--sweep-trials-per-seed", type=int)
    parser.add_argument("--accepted-trials-per-seed", type=int)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    out = args.out.resolve()
    if out != DEFAULT_OUT.resolve():
        raise SystemExit("This task tool writes only its declared QA folder.")
    out.mkdir(parents=True, exist_ok=True)
    parameters = json.loads((TOOLS / "parameters.json").read_text(encoding="utf-8"))
    if args.sweep_trials_per_seed:
        parameters["sweep_trials_per_seed"] = args.sweep_trials_per_seed
    if args.accepted_trials_per_seed:
        parameters["accepted_trials_per_seed"] = args.accepted_trials_per_seed
    source = {key: json.loads((ROOT / path).read_text(encoding="utf-8")) for key, path in parameters["source_files"].items() if key in ["base", "meta", "route"]}
    paths = [ROOT / path for path in parameters["source_files"].values()] + list(TOOLS.glob("*.py")) + [TOOLS / "parameters.json", TOOLS / "runtime_fidelity.gd"]
    initial = {str(path.relative_to(ROOT)).replace("\\", "/"): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
    native = json.loads((out / "runtime_fidelity.json").read_text(encoding="utf-8"))
    validation = validate(parameters, source, native)
    write(out / "model_validation.json", validation)
    print(f"model validation: {validation['checks']} checks, {validation['failures']} failures", flush=True)
    if validation["failures"]:
        raise SystemExit(1)
    if args.validate_only:
        return
    started = perf_counter()
    rules = [DrawRule("uniform")] + [DrawRule("fixed", value) for value in parameters["fixed_primary_probabilities"]] + [DrawRule("old_weight", value) for value in source["meta"]["catalyst_weight_by_level"]] + [DrawRule("adaptive", value) for value in parameters["adaptive_strengths"]]
    static = []
    for m, o, label in [(10, 10, "two_school_fresh"), (10, 20, "three_school_fresh"), (10, 50, "six_school_fresh"),
                         (6, 2, "full_slots_six_primary_two_other_upgrades"), (1, 7, "full_slots_one_primary_seven_other_upgrades"),
                         (2, 50, "only_two_primary_legal"), (1, 50, "only_one_primary_legal"),
                         (1, 2, "only_three_total_legal"), (0, 5, "primary_empty"), (5, 0, "other_empty"), (0, 0, "all_maxed")]:
        for rule in rules:
            row = offer_metrics(m, o, 3, rule)
            row["scenario"] = label
            static.append(row)
    write(out / "exact_offer_cases.json", static)
    sweep = []
    for school_count in parameters["active_school_counts"]:
        for rule in rules:
            for policy in parameters["policies"]:
                row = batch(parameters, source, rule, school_count, policy, int(parameters["sweep_trials_per_seed"]))
                sweep.append(row)
            print(f"sweep schools={school_count} rule={rule.label}", flush=True)
    write(out / "sweep.json", sweep)
    write(out / "baseline.json", [row for row in sweep if row["rule"] == "uniform" or row["rule"].startswith("old_weight:")])
    accepted = []
    for school_count in parameters["active_school_counts"]:
        for value in parameters["recommended_level_strengths"]:
            for policy in parameters["policies"]:
                row = batch(parameters, source, DrawRule("adaptive", value), school_count, policy, int(parameters["accepted_trials_per_seed"]))
                accepted.append(row)
            print(f"accepted schools={school_count} adaptive={value}", flush=True)
    write(out / "recommended.json", accepted)
    traces = []
    for school_count in parameters["active_school_counts"]:
        for policy in parameters["policies"]:
            traces.append({"schools": school_count, "policy": policy, "seed": parameters["seed_batches"][0], "rule": "adaptive:0.4",
                           "trajectory": one_trajectory(school_count, int(parameters["spells_per_school"]), DrawRule("adaptive", 0.4), policy,
                                                        int(parameters["seed_batches"][0]), 8, 3, 3, source["route"]["reward_rooms"], trace=True)})
    write(out / "example_trajectories.json", traces)
    invariant_failures = [f"{row['active_schools']}:{row['rule']}:{row['policy']}" for row in sweep + accepted if not row["all_trajectories_23_growth"] or not row["all_trajectories_exhausted"] or row["legal_violation_count"] or not row["first_capacity_matches_final_count"]]
    stable = all(hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest for path, digest in initial.items())
    write(out / "run_manifest.json", {"model_version": parameters["model_version"], "parameters": parameters, "source_sha256": initial,
                                      "source_stable": stable, "model_validation_checks": validation["checks"], "model_validation_failures": validation["failures"],
                                      "trajectory_invariant_failures": invariant_failures, "sweep_scenarios": len(sweep), "recommended_scenarios": len(accepted),
                                      "total_trajectories": sum(row["trials"] for row in sweep + accepted), "elapsed_seconds": perf_counter() - started,
                                      "claim_level": "mathematical design prediction; no combat or live new-school implementation"})
    with (out / "trajectory_summary.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.writer(handle)
        writer.writerow(["schools", "rule", "policy", "n", "first8_main_slots_mean", "final_main_slots_mean", "final_main_p05", "final_main_p50", "final_main_p95", "all_main_final_rate", "mixed4_4_rate", "early_offer_other_fraction", "growth_to8_mean"])
        for row in sweep + accepted:
            writer.writerow([row["active_schools"], row["rule"], row["policy"], row["trials"], row["first_eight_primary_slots"]["mean"], row["final_primary_slots"]["mean"], row["final_primary_slots"]["p05"], row["final_primary_slots"]["p50"], row["final_primary_slots"]["p95"], row["all_primary_final_fraction"], row["mixed_four_four_final_fraction"], row["early_eight_offer_other_fraction"]["mean"], row["growth_to_eight_slots"]["mean"]])
    print(f"complete: {len(sweep)} sweep + {len(accepted)} recommended scenarios; {sum(row['trials'] for row in sweep + accepted)} trajectories; source_stable={stable}; invariant_failures={len(invariant_failures)}", flush=True)
    if not stable or invariant_failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
