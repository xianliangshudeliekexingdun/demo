"""Exact three-tier/selected-line proposal; standalone, read-only runtime input."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import statistics

ROOT = Path(__file__).resolve().parents[3]
VERSION = "gem-affix-tiers-1.0"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def geometric(probability):
    if probability == 0:
        return {"mean": None, "p50": None, "p90": None, "p95": None, "guarantee": None}
    if probability == 1:
        return {"mean": 1, "p50": 1, "p90": 1, "p95": 1, "guarantee": 1}
    assert 0 < probability < 1
    return {"mean": 1 / probability,
            **{key: math.ceil(math.log1p(-q) / math.log1p(-probability))
               for key, q in (("p50", .5), ("p90", .9), ("p95", .95))},
            "guarantee": None}


def candidates(pool_size, other_lines, weights):
    allowed = [kind for kind in range(pool_size) if kind not in other_lines]
    return {(kind, tier): chance / len(allowed)
            for kind in allowed for tier, chance in enumerate(weights)}


def sample(weights, rng):
    threshold = rng.random()
    total = 0.0
    for index, chance in enumerate(weights):
        total += chance
        if chance and threshold < total:
            return index
    raise AssertionError("Invalid probability table")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--parameters", type=Path, default=Path(__file__).with_name("affix_roll_parameters.json"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to((ROOT / "build/qa").resolve()):
        raise SystemExit("Output must stay inside this project's build/qa")
    cfg = read(args.parameters)
    source = ROOT / cfg["runtime_source"]
    original_hash = sha(source)
    data = read(source)
    checks = []

    def check(name, condition):
        checks.append({"name": name, "pass": bool(condition)})

    weights = cfg["tier_probabilities"]
    check("three_tiers_valid", len(weights) == 3 and min(weights) > 0 and math.isclose(sum(weights), 1))
    check("runtime_quality_counts", data["affix_counts"] == {"green": 1, "blue": 2, "purple": 3, "gold": 3})
    check("runtime_eight_types", len(data["affixes"]) == 8)
    check("known_geometric_half", geometric(.5)["mean"] == 2 and geometric(.5)["p90"] == 4)
    check("zero_probability_no_guarantee", geometric(0)["mean"] is None)
    check("certain_probability_one", geometric(1)["p90"] == 1)
    check("known_bundle_count", math.comb(8, 3) == 56)
    pool = len(data["affixes"])
    anchors = cfg["tier_anchor_rarities"]
    values = {name: [row[anchor] for anchor in anchors] for name, row in data["affixes"].items()}
    averages = {}
    for name, row in data["affixes"].items():
        average = sum(w * value for w, value in zip(weights, values[name]))
        averages[name] = {"label": row["label"], "tiers": values[name], "unit": row["unit"],
                          "mean_per_line": average, "ratio_to_old_purple_line": average / row["purple"]}
        check(f"{name}_unchanged_max", max(values[name]) == row["purple"] == row["gold"])
        check(f"{name}_ascending", values[name] == sorted(values[name]))

    scenarios = {}
    for rarity, count in data["affix_counts"].items():
        # The other (count - 1) types are held fixed. The old selected type is allowed.
        others = set(range(count - 1))
        target = count - 1
        table = candidates(pool, others, weights)
        check(f"{rarity}_mass", math.isclose(sum(table.values()), 1))
        check(f"{rarity}_no_duplicate_other", all(kind not in others for kind, tier in table))
        check(f"{rarity}_same_type_can_upgrade", all((target, tier) in table for tier in range(3)))
        chance = table[target, 2]
        scenarios[rarity] = {
            "normal_line_count": count, "candidate_types": pool - count + 1,
            "wanted_type_and_top_tier_probability": chance,
            "wanted_top_final_line_wait": geometric(chance),
            "at_least_one_top_line_on_new_gem": 1 - (1 - weights[2]) ** count,
            "all_lines_top_on_new_gem": weights[2] ** count,
            "specified_type_set_and_all_top_on_new_gem": weights[2] ** count / math.comb(pool, count)
        }

    triple_probability = scenarios["gold"]["specified_type_set_and_all_top_on_new_gem"]
    exact = {"rarities": scenarios, "affix_values": averages,
             "specified_gold_core_and_type_set_and_all_top_given_gold": triple_probability / len(data["cores"]),
             "hypothetical_type_only_final_line_wait": geometric(1 / (pool - 2)),
             "tier_only_upgrade_wait": geometric(weights[2])}
    sweeps = []
    for trial_weights in cfg["tier_probability_sweeps"]:
        check(f"sweep_valid_{trial_weights}", len(trial_weights) == 3 and math.isclose(sum(trial_weights), 1))
        sweeps.append({"weights": trial_weights, "final_line_wait": geometric(trial_weights[2] / (pool - 2)),
                       "new_three_line_all_top_probability": trial_weights[2] ** 3})

    simulations = []
    candidate_count = pool - 2
    probability = weights[2] / candidate_count
    theoretical_mean = 1 / probability
    trials = cfg["monte_carlo"]["trials_per_seed"]
    for seed in cfg["monte_carlo"]["seeds"]:
        rng = random.Random(seed)
        waits = []
        for _ in range(trials):
            attempts = 0
            while True:
                attempts += 1
                kind, tier = rng.randrange(candidate_count), sample(weights, rng)
                if kind == 0 and tier == 2:
                    break
            waits.append(attempts)
        ordered = sorted(waits)
        standard_error = math.sqrt((1 - probability) / probability ** 2 / trials)
        observed_cdf = sum(n <= exact["rarities"]["gold"]["wanted_top_final_line_wait"]["p90"] for n in waits) / trials
        true_cdf = 1 - (1 - probability) ** exact["rarities"]["gold"]["wanted_top_final_line_wait"]["p90"]
        check(f"seed_{seed}_mean_within_6se", abs(statistics.mean(waits) - theoretical_mean) < 6 * standard_error)
        check(f"seed_{seed}_p90_cdf_within_6se", abs(observed_cdf - true_cdf) < 6 * math.sqrt(true_cdf * (1 - true_cdf) / trials))
        simulations.append({"seed": seed, "trials": trials, "mean": statistics.mean(waits),
                            "median": statistics.median(waits), "p90": ordered[math.ceil(.9 * trials) - 1],
                            "mean_standard_error": standard_error, "maximum_observed_not_guarantee": max(waits)})
    final_wait = scenarios["gold"]["wanted_top_final_line_wait"]
    targets = []
    for metric in ("mean", "p90"):
        low, high = cfg["targets"][f"desired_top_final_line_{metric}_rolls"]
        targets.append({"name": metric, "range": [low, high], "value": final_wait[metric],
                        "status": "within" if low <= final_wait[metric] <= high else "outside"})
    check("runtime_bytes_unchanged", sha(source) == original_hash)
    report = {"model_version": VERSION, "parameters": cfg, "runtime_version": data["version"],
              "source_hash": original_hash, "parameters_sha": sha(args.parameters), "model_sha": sha(Path(__file__)),
              "model_validation_cases": checks, "failures": [c for c in checks if not c["pass"]],
              "exact": exact, "monte_carlo": simulations, "sweeps": sweeps, "provisional_targets": targets,
              "limitations": cfg["omissions"],
              "interpretation": "Independent full type+tier rerolls; choose old/new after paying. No material price or finite target guarantee."}
    output.mkdir(parents=True, exist_ok=True)
    (output / "results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = ["# 三档普通词条与改良讨论模型", "", f"模型：{VERSION}；参数：{cfg['version']}。仅讨论，不修改游戏。", "",
             f"核对：{len(checks)}项／{len(report['failures'])}失败。运行数据SHA不变。", "",
             "| 宝石 | 保留其他词条后的候选属性数 | 指定属性III档平均次数 | 中位 | 90%达成次数 |", "|---|---:|---:|---:|---:|"]
    for rarity, row in scenarios.items():
        wait = row["wanted_top_final_line_wait"]
        lines.append(f"| {rarity} | {row['candidate_types']} | {wait['mean']:.2f} | {wait['p50']} | {wait['p90']} |")
    lines += ["", "III档使用旧紫／金的上限，I／II档沿用旧绿／蓝值；所有品质同一档位池。",
              f"本次I／II／III概率：{weights}；三词条自然全III概率{weights[2] ** 3:.8f}；指定三属性再全III概率{triple_probability:.8f}。",
              "普通改良可保留旧值、固定其他词条和核心；候选允许原属性／完全相同结果，没有保底。",
              "成本、分解、迁移、战斗收益未建模；均为待认可提案。材料预算另算。", "",
              "复现：`python tools/balance/magic_gems/affix_roll_model.py --output build/qa/magic-gem-affix-tiers-20261020`", ""]
    (output / "summary.md").write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps({"version": VERSION, "checks": len(checks), "failures": report["failures"],
                      "final_line": final_wait, "sweeps": sweeps, "monte_carlo": simulations}, ensure_ascii=False, indent=2))
    raise SystemExit(bool(report["failures"]))


if __name__ == "__main__":
    main()
