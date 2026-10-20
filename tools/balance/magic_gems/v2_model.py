"""First-pass keystone budgets and salvage/reforge economy, with fixed-seed waits."""
from __future__ import annotations
import argparse
from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path
import random
import statistics

from draw_model import cycle_exact, core_wait_exact, quality_probabilities, transition

ROOT = Path(__file__).resolve().parents[3]
VERSION = "gem-keystones-workshop-2.0"

def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def geometric(p):
    return {"mean": 1 / p, "p50": math.ceil(math.log(.5) / math.log1p(-p)),
            "p90": math.ceil(math.log(.1) / math.log1p(-p)), "p95": math.ceil(math.log(.05) / math.log1p(-p))}

def core_wait(cfg, draw, cost, seed, trials):
    rng = random.Random(seed)
    ranks = {"green": 1, "blue": 2, "purple": 3, "gold": 3}
    qualities = ("green", "blue", "purple", "gold")
    # Cache legal probability tables; no gameplay RNG is called or emulated.
    tables = {}
    for novice in (True, False):
        for misses in range(30):
            for rare in range(10):
                state = (misses, rare, novice)
                tables[state] = quality_probabilities(state, draw)
    waits, rolls, censored = [], [], 0
    for _ in range(trials):
        state, bank, has_core = (0, 0, True), 0, False
        subs = []
        rerolls = 0
        for number in range(1, cfg["monte_carlo"]["maximum_draws"] + 1):
            u, cumulative = rng.random(), 0.0
            for quality in qualities:
                cumulative += tables[state][quality]
                if u < cumulative:
                    break
            state = transition(state, quality)
            if quality == "gold":
                if rng.randrange(8) == 0:
                    break
                if not has_core:
                    has_core = True
                    continue
            if len(subs) < 3:
                subs.append(quality)
            else:
                weakest = min(range(3), key=lambda i: ranks[subs[i]])
                if ranks[quality] > ranks[subs[weakest]]:
                    bank += cfg["workshop"]["salvage_yields"][subs[weakest]]
                    subs[weakest] = quality
                else:
                    bank += cfg["workshop"]["salvage_yields"][quality]
            if cost and has_core:
                obtained = False
                while bank >= cost:
                    bank -= cost
                    rerolls += 1
                    if rng.randrange(7) == 0:
                        obtained = True
                        break
                if obtained:
                    break
        else:
            censored += 1
        waits.append(number)
        rolls.append(rerolls)
    ordered = sorted(waits)
    return {"seed": seed, "accounts": trials, "cost": cost, "censored": censored,
            "mean_draws": statistics.mean(waits), "median_draws": statistics.median(waits),
            "p90_draws": ordered[math.ceil(.9 * trials) - 1], "p95_draws": ordered[math.ceil(.95 * trials) - 1],
            "mean_reforges": statistics.mean(rolls),
            "cdf": {str(n): sum(x <= n for x in waits) / trials for n in (15, 30, 45, 60, 90, 150)}}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--parameters", type=Path, default=Path(__file__).with_name("v2_parameters.json"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to((ROOT / "build/qa").resolve()):
        raise SystemExit("Output must be under build/qa")
    cfg = read(args.parameters)
    runtime = read(ROOT / "data/magic_gems_v1.json")
    base = read(ROOT / "data/balance_candidates/first_run_v1.json")
    draw = {k: deepcopy(runtime[k]) for k in ("pity", "base_weights")}
    draw["gold_effects"] = {"weights": {key: 1 for key in cfg["cores"]}}
    draw["exact"] = {"max_draws": 4096, "tail_tolerance": 1e-12}
    sources = [ROOT / "data/magic_gems_v1.json", ROOT / "data/balance_candidates/first_run_v1.json"]
    before = {str(p.relative_to(ROOT)): sha(p) for p in sources}
    cases = []
    def check(name, condition):
        cases.append({"name": name, "pass": bool(condition)})
    h, s, attack = (base["player"][key] for key in ("health", "shield", "attack"))
    cores = cfg["cores"]
    check("eight_unique_new_cores", len(cores) == 8)
    for field in ("cores", "tier_weights", "workshop"):
        check("runtime_matches_implemented_" + field, runtime[field] == cfg[field])
    check("tier_weight_total", sum(cfg["tier_weights"]) == 100)
    cycle = cycle_exact(draw)
    check("gold_cycle_reference", abs(cycle["mean"] - 15.5999135523) < .001)
    baseline = core_wait_exact(draw, "specified")
    check("specified_core_baseline", abs(baseline["mean"] - 117.58) < .02)
    sacrifice = cores["sacrifice"]
    floor_time = (1 - sacrifice["drain_floor_fraction"]) / sacrifice["drain_max_health_per_second"]
    check("sacrifice_floor_sixty_seconds", math.isclose(floor_time, 60))
    check("sacrifice_floor_target_band", cfg["targets"]["sacrifice_floor_seconds"][0] <= floor_time <= cfg["targets"]["sacrifice_floor_seconds"][1])
    check("sacrifice_floor_bonus", math.isclose(1 - sacrifice["drain_floor_fraction"], .9))
    aegis = cores["aegis"]
    converted = h * aegis["life_conversion"]
    capacity = h - converted + s + converted * aegis["shield_per_life"]
    check("aegis_capacity_557_5", math.isclose(capacity, 557.5))
    capacity_gain = capacity / (h + s) - 1
    check("aegis_capacity_target_band", cfg["targets"]["aegis_base_capacity_gain"][0] <= capacity_gain <= cfg["targets"]["aegis_base_capacity_gain"][1])
    damage = {}
    reaction = cores["reactor"]
    damage["reactor"] = [{"burn_coefficient": fuel, "primary": attack * (reaction["base_coefficient"] + fuel * reaction["remaining_burn_scale"]),
                          "total_with_four_neighbors": attack * (reaction["base_coefficient"] + fuel * reaction["remaining_burn_scale"]) * (1 + reaction["neighbor_cap"] * reaction["neighbor_scale"])} for fuel in (0, 2, 3, 10.5)]
    check("reaction_basic_stock", math.isclose(damage["reactor"][1]["primary"], 520))
    inferno = cores["inferno"]
    damage["inferno_dps"] = {str(n): attack * inferno["tick_coefficient_per_layer"] * n / .5 for n in range(1, inferno["cap"] + 1)}
    check("inferno_full_vs_baseline", math.isclose(damage["inferno_dps"]["6"] / 50, 2.4))
    coffin = cores["coffin"]
    damage["coffin_per_100_planned"] = {"immediate": 100 * (1 - coffin["defer_fraction"]),
                                       "burst_each": 100 * coffin["defer_fraction"] * coffin["release_multiplier"]}
    check("coffin_no_double_charge", math.isclose(damage["coffin_per_100_planned"]["immediate"], 65))
    fracture = cores["fracture"]
    crystal = 50 * fracture["extra_damage_multiplier"]
    damage["fracture_100_base_150_critical"] = {"direct": 100, "first_crystal": crystal,
                                              "all_crystals": sum(crystal * fracture["bounce_multiplier"] ** n for n in range(fracture["bounce_count"] + 1))}
    check("fracture_crystal_80", crystal == 80)
    damage["echo_vs_same_cdr_ordinary_direct_only"] = []
    for cdr in (0, .1, .3, .6):
        echo = cores["echo"]["base_multiplier"] + cores["echo"]["cdr_multiplier"] * cdr
        damage["echo_vs_same_cdr_ordinary_direct_only"].append({"cdr": cdr, "echo_multiplier": echo, "relative_direct_throughput": (1 + echo) * (1 - cdr)})
    check("echo_60pct_multiplier", math.isclose(damage["echo_vs_same_cdr_ordinary_direct_only"][-1]["echo_multiplier"], 2.4))
    damage["stride"] = {"seconds_full_at_base_speed": cores["stride"]["maximum_distance"] / base["player"]["move_speed"],
                         "full_body_multiplier": 1 + cores["stride"]["maximum_body_damage_bonus"],
                         "full_size_multiplier": 1 + cores["stride"]["maximum_size_bonus"]}
    check("stride_two_seconds", damage["stride"]["seconds_full_at_base_speed"] == 2)
    yield_per_draw = sum(cycle["effective_rates"][q] * cfg["workshop"]["salvage_yields"][q] for q in cycle["effective_rates"])
    economy = {"steady_essence_per_draw_if_all_unwanted": yield_per_draw,
               "steady_essence_per_15_draws_if_all_unwanted": yield_per_draw * 15,
               "core_target_after_base": geometric(1 / 7), "last_normal_target_top": {}}
    for old_tier, weight in enumerate(cfg["tier_weights"]):
        # Six allowed types; reject the complete old type+tier outcome only.
        target = (cfg["tier_weights"][2] / 100 / 6) / (1 - weight / 100 / 6)
        economy["last_normal_target_top"][str(old_tier + 1)] = geometric(target)
    check("same_type_still_rolls_other_tiers", economy["last_normal_target_top"]["2"]["mean"] == 22)
    samples = [core_wait(cfg, draw, cfg["workshop"]["core_cost"], seed, cfg["monte_carlo"]["accounts_per_seed"]) for seed in cfg["monte_carlo"]["seeds"]]
    sweeps = {"core_cost": [core_wait(cfg, draw, cost, cfg["monte_carlo"]["seeds"][0], cfg["monte_carlo"]["accounts_per_seed"]) for cost in cfg["sweeps"]["core_cost"]],
              "echo_cdr_multiplier": {str(k): [{"cdr": cdr, "echo_multiplier": cores["echo"]["base_multiplier"] + k * cdr, "noncritical_body_throughput_vs_same_cdr": (1 + cores["echo"]["base_multiplier"] + k * cdr) * (1 - cdr)} for cdr in (0, .1, .3, .6)] for k in cfg["sweeps"]["echo_cdr_multiplier"]},
              "sacrifice_seconds": {str(rate): .9 / rate for rate in cfg["sweeps"]["sacrifice_drain"]},
              "coffin_100_damage_one_target": {str(f): 100 * (1 - f) + 100 * f * coffin["release_multiplier"] for f in cfg["sweeps"]["defer_fraction"]}}
    for index, sample in enumerate(samples):
        check(f"uncensored_{index}", sample["censored"] == 0)
        check(f"improves_target_wait_{index}", sample["mean_draws"] < baseline["mean"])
        check(f"target_core_wait_band_{index}", cfg["targets"]["core_wait_mean_draws"][0] <= sample["mean_draws"] <= cfg["targets"]["core_wait_mean_draws"][1])
    check("runtime_inputs_unchanged", all(sha(ROOT / path) == value for path, value in before.items()))
    report = {"model_version": VERSION, "parameters": cfg, "source_hashes": before,
              "model_sha": sha(Path(__file__)), "parameters_sha": sha(args.parameters),
              "checks": cases, "failures": [c for c in cases if not c["pass"]],
              "baseline_target_core": {k: baseline[k] for k in ("mean", "p50", "p90", "p95")},
              "keystone_budgets": damage, "aegis_capacity": capacity, "sacrifice_seconds": floor_time,
              "economy": economy, "core_wait_samples": samples, "sweeps": sweeps, "omissions": cfg["omissions"]}
    output.mkdir(parents=True, exist_ok=True)
    (output / "results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = ["# 八核心与精粹经济首轮核算", "", f"模型{VERSION}，{len(cases)}项／{len(report['failures'])}失败。", "",
             f"血祭自耗到10%需{floor_time:.0f}秒；血晶基础总容量{capacity:.1f}；满火势120攻击伤害／秒；行者10米蓄满。", "",
             f"成熟期全部不需要的15抽约产{yield_per_draw * 15:.2f}精粹；新玩家保留装备会更少。", "",
             "| 核心改良费用 | 目标核心平均总抽数 | 中位 | 90%达成 |", "|---|---:|---:|---:|"]
    for row in sweeps["core_cost"]:
        lines.append(f"| {row['cost']} | {row['mean_draws']:.2f} | {row['median_draws']:.0f} | {row['p90_draws']} |")
    lines += ["", "费用60的三个固定种子各4000账号。普通改良及触媒不消费预算，保留三颗按品质排序的副宝石；不代表真实玩家毕业时间。", "",
              "复现：`python tools/balance/magic_gems/v2_model.py --output build/qa/magic-gems-v2-20261020/model`。", ""]
    (output / "summary.md").write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps({"checks": len(cases), "failures": report["failures"], "economy": economy, "samples": samples, "sweeps": sweeps}, ensure_ascii=False, indent=2))
    raise SystemExit(bool(report["failures"]))

if __name__ == "__main__":
    main()
