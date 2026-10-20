"""Inspect proposed combat equations; never starts or modifies the game."""
from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mitigation(defense: float, extra_multiplier: float, denominator: float, cap: float):
    return max(1 - cap, denominator / (denominator + max(0, defense)) * extra_multiplier)


def ordinary(attack, coefficient, scale, attack_percent=0, temporary_attack=0,
             generic=0, element=0, vulnerability=0, critical=False, crit_multiplier=1.5):
    return (attack * (1 + attack_percent) * (1 + temporary_attack) * coefficient * scale
            * (1 + generic) * (1 + element) * (1 + vulnerability)
            * (crit_multiplier if critical else 1))


def current_equation(attack, coefficient, scale, field, fire, vulnerability,
                     critical, crit_multiplier):
    # Matches the scalar terms in resolve_spell_hit, not its state/event logic.
    result = attack * (1 + field) * coefficient * scale
    result *= (1 + fire) * (1 + vulnerability)
    return result * crit_multiplier if critical else result


def split_loss(health, shield, damage):
    shield_loss = min(shield, max(0, damage))
    health_loss = min(health, max(0, damage - shield_loss))
    return {"health_loss": health_loss, "shield_loss": shield_loss,
            "health": health - health_loss, "shield": shield - shield_loss,
            "actual_loss": health_loss + shield_loss,
            "survives": health - health_loss > 0}


def expected_hits(health: float, noncritical: float, rate: float, multiplier: float):
    """Exact independent hit distribution, no sampled RNG or continuous-DPS TTK."""
    if health <= 0:
        return 0.0
    if noncritical <= 0 or not 0 <= rate <= 1 or multiplier < 1:
        raise ValueError("positive damage, bounded probability and multiplier >=1 required")
    total = 0.0
    for count in range(math.ceil(health / noncritical)):
        survival = 0.0
        for critical_count in range(count + 1):
            damage = noncritical * (count + critical_count * (multiplier - 1))
            if damage < health - 1e-9:
                survival += (math.comb(count, critical_count) * rate ** critical_count
                             * (1 - rate) ** (count - critical_count))
        total += survival
    return total


def run(parameters: Path, output: Path):
    cfg = load(parameters)
    base = load(ROOT / cfg["base_source"])
    item = load(ROOT / cfg["approved_item_budget_source"])
    source_paths = [ROOT / name for name in cfg["source_files"]]
    source_paths += [ROOT / cfg["approved_item_budget_source"]]
    before = {p.relative_to(ROOT).as_posix(): sha(p) for p in source_paths}
    evidence = []

    def check(name, actual, expected):
        ok = (math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-8)
              if isinstance(actual, (int, float)) and isinstance(expected, (int, float))
              else actual == expected)
        evidence.append({"name": name, "actual": actual, "expected": expected, "pass": ok})

    denominator = item["defense"]["armor_denominator"]
    cap = item["defense"]["final_damage_reduction_cap"]
    check("defense15 fraction", mitigation(15, 1, denominator, cap), 100 / 115)
    check("defense45 fraction", mitigation(45, 1, denominator, cap), 100 / 145)
    check("combined reduction cap", mitigation(85, .82, denominator, cap), .55)
    check("negative defense treated as zero", mitigation(-10, 1, denominator, cap), 1)
    check("same-bucket 20 plus20", 1 + .2 + .2, 1.4)
    check("separate generic36 and fire50", (1 + .36) * (1 + .5), 2.04)
    check("crit5 expected", 1 + .05 * (1.5 - 1), 1.025)
    check("F02 III modifies crit multiplier", base["spells"]["F02"]["levels"][2]["crit_bonus"], .25)
    check("GT03 maximum health acquisition order A", (300 + 80) * .8, 304)
    check("GT03 maximum health acquisition order B", 300 * .8 + 80 * .8, 304)
    check("GT03 current-health proportion", 200 / 300 * 240, 160)
    check("zero health target already dead", expected_hits(0, 10, .1, 1.5), 0)
    check("fixed noncritical hits", expected_hits(100, 30, 0, 1.5), 4)
    check("certain critical hits", expected_hits(100, 30, 1, 2), 2)
    check("discrete expected hits known case", expected_hits(100, 40, .5, 2), 2.25)
    check("zero damage does not heal", split_loss(100, 20, 0)["health"], 100)
    check("shield first", split_loss(100, 20, 50)["health_loss"], 30)
    check("overkill not counted as actual loss", split_loss(30, 20, 500)["actual_loss"], 50)
    check("fatal hit cannot produce survival recovery", split_loss(30, 20, 500)["survives"], False)
    reduction = min(.99, float(base["limits"]["cooldown_reduction"]))
    check("CDR cap60", reduction, .6)
    check("minimum CD floor", max(base["limits"]["minimum_cooldown"], .1 * (1 - reduction)), .2)
    check("crit stat uncapped", base["limits"]["crit_rate"], None)
    check("crit100 probability", min(1, max(0, 1.0)), 1)
    check("crit180 probability without supercrit", min(1, max(0, 1.8)), 1)

    comparisons = 0
    for attack, coeff, scale, field, fire, vuln, crit in itertools.product(
        [100, 115], [1, 1.35, 6.5], [1, .7], [0, .2], [0, .5, .65], [0, .2], [False, True]
    ):
        old = current_equation(attack, coeff, scale, field, fire, vuln, crit, 1.75)
        new = ordinary(attack, coeff, scale, temporary_attack=field,
                       element=fire, vulnerability=vuln, critical=crit, crit_multiplier=1.75)
        check(f"neutral-new-terms equivalence {comparisons}", new, old)
        comparisons += 1

    sample = cfg["example"]
    stats = base["spells"][sample["spell_id"]]
    level = stats["levels"][sample["spell_level"] - 1]
    attack = base["player"]["attack"] + sample["attack_flat"]
    noncrit = ordinary(attack, level["coefficient"], sample["cast_scale"],
                       sample["attack_percent"], sample["temporary_attack_bonus"],
                       sample["generic_bonus"], sample["element_bonus"],
                       sample["target_vulnerability"])
    check("worked noncritical before defense", noncrit, 456.0624)
    check("worked critical before defense", noncrit * sample["crit_multiplier"], 798.1092)
    cd = max(base["limits"]["minimum_cooldown"],
             level.get("cooldown", stats["cooldown"]) * (1 - min(sample["cooldown_reduction"], base["limits"]["cooldown_reduction"])))
    cycle = cd + stats["windup"]
    rows = []
    for health, defense in itertools.product(cfg["diagnostic_targets"]["health"], cfg["diagnostic_targets"]["defense"]):
        taken = mitigation(defense, 1, denominator, cap)
        normal = noncrit * taken
        hits = expected_hits(health, normal, sample["crit_rate"], sample["crit_multiplier"])
        rows.append({"diagnostic_health": health, "defense": defense,
                     "noncritical": normal, "critical": normal * sample["crit_multiplier"],
                     "expected_per_hit": normal * (1 + sample["crit_rate"] * (sample["crit_multiplier"] - 1)),
                     "expected_hits": hits,
                     "stationary_first_cast_to_kill_seconds": stats["windup"] + (hits - 1) * cycle,
                     "fixed_derived_probe_after_mitigation": cfg["fixed_derived_damage_probe"] * taken})
    check("worked defense20 noncritical", rows[1]["noncritical"], 380.052)
    check("worked expected discrete hits", rows[1]["expected_hits"], 2.7569)
    bucket_rows = [{"generic": g, "element": e, "separate_buckets": (1 + g) * (1 + e),
                    "incorrect_collapse_to_one_bucket": 1 + g + e}
                   for g, e in itertools.product(cfg["element_and_generic_probes"], repeat=2)]
    attack_rows = [{"attack_percent": p, "attack": attack * (1 + p),
                    "with_temporary20percent": attack * (1 + p) * 1.2}
                   for p in cfg["attack_percent_probes"]]
    stable = all(sha(ROOT / path) == value for path, value in before.items())
    check("runtime sources unchanged", stable, True)
    report = {"model_version": "combat-foundation-math-1", "scope": cfg["status"],
              "parameters": cfg, "source_sha256": before, "tool_sha256": sha(Path(__file__)),
              "parameter_sha256": sha(parameters), "source_stable": stable,
              "checks": len(evidence), "failures": sum(not x["pass"] for x in evidence),
              "neutral_formula_cases": comparisons, "validation_cases": evidence,
              "worked_example": rows, "cycle_seconds": cycle, "effective_cd_seconds": cd,
              "bucket_sensitivity": bucket_rows, "attack_percent_sensitivity": attack_rows,
              "assumptions": [
                  "Current equation equivalence covers scalar terms only, not runtime execution or events.",
                  "Enemy defense and derived fixed damage passing defense are new discussion proposals.",
                  "Critical rolls are independent per effective hit; targets have no regeneration or invulnerability.",
                  "One F01 primary hit per cast: no secondary, travel, target loss, movement, overkill transfer or procs.",
                  "Cycle uses continuous windup+cooldown, not120Hz quantization or P04/P05 dynamics.",
                  "Dummy health values are diagnostics, not authored enemy or Boss stats.",
                  "No snapshot-policy, event chain, AI, control, healing-over-time, route, probability-of-winning or30minute validation.",
                  "Generic items and revised caps are authorized; runtime event evidence is kept separately from this formula report."
              ]}
    output.mkdir(parents=True, exist_ok=True)
    (output / "results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = ["# 战斗底层公式核对", "", "讨论稿的确定性算式核对，未运行或修改游戏。不是敌人或Boss数值定案，也不证明完整路线时长。", "",
             f"检查{len(evidence)}项，失败{report['failures']}；其中{comparisons}项比较新项为中性时与现行乘式的等价。源哈希保持：{stable}。", "",
             "例子为F01三级主弹，攻击100+15、临时攻击20%、系数1.35、通用增伤36%、火伤50%、易伤20%、暴击率13%、暴击倍率1.75；无附加施法。", "",
             f"防御前非暴击{noncrit:.6f}，暴击{noncrit * sample['crit_multiplier']:.6f}；有效CD{cd:.6f}秒、循环{cycle:.6f}秒。", "",
             "| 诊断生命 | 防御 | 非暴击 | 暴击 | 每击期望 | 击杀所需命中期望 | 首次吟唱起算秒数 | 固定附伤200减伤后 |", "|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for row in rows:
        lines.append("| %d | %d | %.3f | %.3f | %.3f | %.5f | %.5f | %.3f |" % tuple(row.values()))
    lines += ["", "命中期望由逐次独立暴击分布精确求和，非生命除平均伤害；秒数只用于固定单目标、主弹瞬时命中且无事件链的数学例子。", "",
              "同桶20%+20%=40%；通用36%与火伤50%在两桶时倍率为2.04，误合一桶仅1.86，不能混写。", "",
              "完整公式、参数、敏感性、校验和限制见results.json。敌方防御和固定附伤是否经过防御仍是本次待讨论规则；24件条目认可与该项扩展决策分别记录。"]
    (output / "results.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({k: report[k] for k in ["checks", "failures", "neutral_formula_cases", "source_stable"]}))
    return bool(report["failures"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--parameters", type=Path, default=Path(__file__).with_name("parameters.json"))
    parser.add_argument("--out", type=Path, default=ROOT / "build/qa/generic-items-implementation-20261018/formulas")
    args = parser.parse_args()
    raise SystemExit(run(args.parameters, args.out))
