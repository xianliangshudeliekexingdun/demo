"""Read-only runtime sources + editable proposal -> static, deterministic item budget.

All new rules below are design proposals. This does not execute game combat.
"""
from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def nonnegative(value: float, label: str) -> float:
    if not math.isfinite(value) or value < 0:
        raise ValueError(f"{label} must be finite and non-negative")
    return value


def crit_expectation(rate: float, multiplier: float, cap: float | None) -> float:
    nonnegative(multiplier, "crit multiplier")
    if cap is not None:
        nonnegative(cap, "crit cap")
    if not math.isfinite(rate):
        raise ValueError("crit rate must be finite")
    probability = min(1.0, max(0.0, rate))
    if cap is not None:
        probability = min(cap, probability)
    return 1.0 + probability * (multiplier - 1.0)


def cycle(windup: float, base_cd: float, reduction: float, cap: float, floor: float):
    for label, value in [("windup", windup), ("cooldown", base_cd), ("reduction", reduction), ("cap", cap), ("floor", floor)]:
        nonnegative(value, label)
    if cap > 1:
        raise ValueError("cooldown cap cannot exceed one")
    effective_cd = max(floor, base_cd * (1.0 - min(cap, reduction))) if base_cd > 0 else 0.0
    return windup + effective_cd, effective_cd


def damage_multiplier(armor: float, projectile: bool, defense: dict):
    nonnegative(armor, "armor")
    den = defense["armor_denominator"]
    if den <= 0:
        raise ValueError("armor denominator must be positive")
    raw = den / (den + armor)
    if projectile:
        raw *= 1.0 - defense["projectile_damage_reduction"]
    return max(1.0 - defense["final_damage_reduction_cap"], raw)


def apply_hit(raw: float, shield: float, health: float, armor: float, projectile: bool, defense: dict):
    for label, value in [("raw hit", raw), ("shield", shield), ("health", health)]:
        nonnegative(value, label)
    reduced = raw * damage_multiplier(armor, projectile, defense)
    absorbed = min(shield, reduced)
    lost = min(health, reduced - absorbed)
    return {"after_mitigation": reduced, "shield_damage": absorbed, "health_damage": lost,
            "shield_after": shield - absorbed, "health_after": health - lost}


def generic_factor(bonuses):
    for value in bonuses:
        nonnegative(value, "generic damage bonus")
    return 1.0 + sum(bonuses)


def fidelity_checks(base: dict, proposal: dict):
    cases = []

    def check(name, actual, expected):
        ok = math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-10) if isinstance(actual, (int, float)) else actual == expected
        cases.append({"case": name, "actual": actual, "expected": expected, "pass": ok})

    def rejects(name, call):
        try:
            call()
        except ValueError:
            check(name, True, True)
        else:
            check(name, False, True)

    defense = proposal["defense"]
    limits = base["limits"]
    check("runtime base ATK", base["player"]["attack"], 100)
    check("runtime base HP", base["player"]["health"], 300)
    check("runtime base shield", base["player"]["shield"], 100)
    check("U03 source ATK flat", base["attribute_artifact_candidates"]["attack_flat"], 15)
    check("U01 source HP cap", base["attribute_artifact_candidates"]["health_max_flat"], 80)
    check("U02 source shield cap", base["attribute_artifact_candidates"]["shield_max_flat"], 25)
    check("F02 III adds crit multiplier", base["spells"]["F02"]["levels"][2]["crit_bonus"], 0.25)
    check("known crit 5pct x1.5", crit_expectation(.05, 1.5, .8), 1.025)
    check("known crit 28pct x2.0", crit_expectation(.28, 2.0, .8), 1.28)
    check("negative crit clamps zero", crit_expectation(-.1, 1.5, .8), 1)
    check("crit cap 80pct", crit_expectation(1, 1.5, .8), 1.4)
    check("F01 level1 base cycle", cycle(.15, 1.2, .1, .5, .2)[0], 1.23)
    check("F01 plus6pp cycle", cycle(.15, 1.2, .16, .5, .2)[0], 1.158)
    check("F07 base cycle", cycle(.65, 6, .1, .5, .2)[0], 6.05)
    check("F10 III level cooldown overrides 12", base["spells"]["F10"]["levels"][2]["cooldown"], 9)
    check("F10 III base cycle", cycle(.35, 9, .1, .5, .2)[0], 8.45)
    check("cooldown floor", cycle(.1, .1, .5, .5, .2)[1], .2)
    check("cooldown cap", cycle(.15, 1.2, .9, .5, .2)[1], .6)
    check("zero cooldown stays zero", cycle(.1, 0, .9, .5, .2)[1], 0)
    check("DEF0 melee", damage_multiplier(0, False, defense), 1)
    check("DEF0 projectile", damage_multiplier(0, True, defense), .82)
    check("DEF15 melee hand case", damage_multiplier(15, False, defense), 100 / 115)
    check("DEF45 projectile hand case", damage_multiplier(45, True, defense), 82 / 145)
    check("DEF85 melee cap45pct", damage_multiplier(85, False, defense), .55)
    check("DEF65 projectile cap45pct", damage_multiplier(65, True, defense), .55)
    check("extreme DEF cannot exceed cap", damage_multiplier(1e9, True, defense), .55)
    hit = apply_hit(100, 20, 300, 45, True, defense)
    check("mitigate before shield: shield", hit["shield_damage"], 20)
    check("mitigate before shield: HP", hit["health_damage"], 82 / 145 * 100 - 20)
    check("zero hit preserves HP", apply_hit(0, 20, 300, 15, False, defense)["health_after"], 300)
    check("HP loss capped at stock", apply_hit(1000, 0, 10, 0, False, defense)["health_damage"], 10)
    for name, call in [
        ("negative armor rejected", lambda: damage_multiplier(-1, False, defense)),
        ("negative raw hit rejected", lambda: apply_hit(-1, 20, 300, 0, False, defense)),
        ("negative shield rejected", lambda: apply_hit(1, -1, 300, 0, False, defense)),
        ("negative cooldown rejected", lambda: cycle(.1, -1, .1, .5, .2)),
        ("negative reduction rejected", lambda: cycle(.1, 1, -.1, .5, .2)),
        ("nonfinite hit rejected", lambda: apply_hit(float("nan"), 0, 300, 0, False, defense)),
    ]:
        rejects(name, call)
    # Regression: F10 III uses its per-level 9s CD; F02 III changes multiplier, not crit chance.
    check("proposal crit source independent of F02", proposal["offense"]["crit_rate_add"], .08)
    check("runtime CDR limit", limits["cooldown_reduction"], .6)
    check("runtime crit stat uncapped", limits["crit_rate"], None)
    check("100pct crit guaranteed", crit_expectation(1, 1.5, None), 1.5)
    check("over100pct has no supercrit", crit_expectation(1.8, 1.5, None), 1.5)
    check("current cooldown cap60pct", cycle(.15, 1.2, .9, .6, .2)[1], .48)
    check("generic conditional bonuses add, do not multiply", generic_factor([.18, .18]), 1.36)
    check("all four new damage conditions same bucket", generic_factor([.18, .18, .20, .25]), 1.81)
    rejects("negative generic damage rejected", lambda: generic_factor([-.1]))
    if not all(c["pass"] for c in cases):
        raise AssertionError([c for c in cases if not c["pass"]])
    return cases


def output_scenarios(base: dict, proposal: dict):
    rows = []
    off, sc = proposal["offense"], proposal["scenarios"]
    synergy = base["fire_synergy"]["cooldown_reduction"] if sc["baseline_has_three_fire_synergy"] else 0
    cap, floor = base["limits"]["cooldown_reduction"], base["limits"]["minimum_cooldown"]
    atk, atk_add = base["player"]["attack"], base["attribute_artifact_candidates"]["attack_flat"]
    full_conditional = off["flawless"]["bonus"] + off["hunt"]["bonus_per_stack"] * off["hunt"]["max_stacks"]
    for spell_id in sc["spell_ids"]:
        spec = base["spells"][spell_id]
        for level in sc["spell_levels"]:
            level_spec = spec["levels"][level - 1]
            base_cd = level_spec.get("cooldown", spec.get("cooldown", 0))
            base_cycle, baseline_cd = cycle(spec.get("windup", 0), base_cd, synergy, cap, floor)
            candidate_cycle, candidate_cd = cycle(spec.get("windup", 0), base_cd, synergy + off["cooldown_reduction_add"], cap, floor)
            for old_rate in sc["baseline_crit_rates"]:
                for old_multi in sc["baseline_crit_multipliers"]:
                    old_crit = crit_expectation(old_rate, old_multi, base["limits"]["crit_rate"])
                    new_crit = crit_expectation(old_rate + off["crit_rate_add"], old_multi + off["crit_multiplier_add"], base["limits"]["crit_rate"])
                    for uptime in sc["conditional_uptime"]:
                        for build in sc["builds"]:
                            rate_factor = 1 if build == "baseline" else base_cycle / candidate_cycle
                            attack_factor = 1 if build == "baseline" or spell_id == "F10" else (atk + atk_add) / atk
                            crit_factor = new_crit / old_crit if build == "offense_six" and spell_id != "F10" else 1
                            generic_mult = generic_factor([full_conditional * uptime]) if build == "offense_six" and spell_id != "F10" else 1
                            ratio = rate_factor * attack_factor * crit_factor * generic_mult
                            # Absolute diagnostics omit unchanged fire/P03/field buckets, so comparisons are normalized.
                            if spell_id == "F10":
                                amount = level_spec["shield"]
                                baseline_output = amount / base_cycle
                                metric = "theoretical_shield_points_per_second"
                            else:
                                coeff = level_spec["coefficient"]
                                coeff += level_spec.get("secondary", 0) if spell_id == "F01" else level_spec.get("aftershock", 0)
                                baseline_output = atk * coeff * old_crit / base_cycle
                                metric = "normalized_single_target_damage_per_second"
                            rows.append({"spell": spell_id, "level": level, "old_crit_rate": old_rate,
                                         "old_crit_multiplier": old_multi, "joint_conditional_uptime": uptime,
                                         "build": build, "metric": metric, "baseline_cycle_seconds": base_cycle,
                                         "candidate_cycle_seconds": base_cycle if build == "baseline" else candidate_cycle,
                                         "baseline_cooldown_seconds": baseline_cd, "candidate_cooldown_seconds": baseline_cd if build == "baseline" else candidate_cd,
                                         "baseline_output": baseline_output, "candidate_output": baseline_output * ratio,
                                         "relative_output": ratio, "uplift_fraction": ratio - 1,
                                         "attack_factor": attack_factor, "cast_frequency_factor": rate_factor,
                                         "crit_factor": crit_factor, "generic_additive_factor": generic_mult})
    return rows


def output_boundary(base: dict, proposal: dict, choose_count=6, item_ids=None):
    """Coincident-conditions upper boundary; no event or offer simulation."""
    ids = item_ids or ["attack", "CDR", "crit_rate", "crit_multiplier", "flawless", "hunt", "elite", "half_health"]
    off, sc = proposal["offense"], proposal["scenarios"]
    result = []
    synergy = base["fire_synergy"]["cooldown_reduction"] if sc["baseline_has_three_fire_synergy"] else 0
    for chosen in itertools.combinations(ids, choose_count):
        for spell_id in [x for x in sc["spell_ids"] if x != "F10"]:
            spec = base["spells"][spell_id]
            for level in sc["spell_levels"]:
                level_spec = spec["levels"][level - 1]
                cd = level_spec.get("cooldown", spec["cooldown"])
                before = cycle(spec["windup"], cd, synergy, base["limits"]["cooldown_reduction"], base["limits"]["minimum_cooldown"])[0]
                after = cycle(spec["windup"], cd, synergy + (off["cooldown_reduction_add"] if "CDR" in chosen else 0), base["limits"]["cooldown_reduction"], base["limits"]["minimum_cooldown"])[0]
                attack_factor = (base["player"]["attack"] + base["attribute_artifact_candidates"]["attack_flat"]) / base["player"]["attack"] if "attack" in chosen else 1
                bonuses = [off["flawless"]["bonus"]] if "flawless" in chosen else []
                if "hunt" in chosen:
                    bonuses.append(off["hunt"]["bonus_per_stack"] * off["hunt"]["max_stacks"])
                bonuses.extend(off[f"{k}_bonus"] for k in ["elite", "half_health"] if k in chosen)
                for old_rate in sc["baseline_crit_rates"]:
                    for old_multi in sc["baseline_crit_multipliers"]:
                        new_rate = old_rate + (off["crit_rate_add"] if "crit_rate" in chosen else 0)
                        # The new crit-multiplier item has an offer gate; all emitted rows obey it.
                        if "crit_multiplier" in chosen and new_rate < off["crit_multiplier_offer_requires_permanent_crit_rate"]:
                            continue
                        crit_before = crit_expectation(old_rate, old_multi, base["limits"]["crit_rate"])
                        crit_after = crit_expectation(new_rate, old_multi + (off["crit_multiplier_add"] if "crit_multiplier" in chosen else 0), base["limits"]["crit_rate"])
                        ratio = attack_factor * before / after * crit_after / crit_before * generic_factor(bonuses)
                        result.append({"items": list(chosen), "spell": spell_id, "level": level, "old_crit_rate": old_rate,
                                       "old_crit_multiplier": old_multi, "permanent_crit_rate_with_items": new_rate,
                                       "all_selected_conditions_damage_uptime": 1, "generic_bucket_bonus": sum(bonuses),
                                       "relative_output": ratio, "uplift_fraction": ratio - 1})
    return {"status": "optimistic_boundary_not_practical_average", "enumerated_rows": len(result),
            "scenario": "All selected conditions simultaneously active; no event uptime or acquisition-order simulation",
            "maximum_case": max(result, key=lambda x: x["uplift_fraction"]),
            "minimum_case": min(result, key=lambda x: x["uplift_fraction"]),
            "cases_above_former_90pct_reference_line": sum(r["uplift_fraction"] > proposal["design_references"]["offense_six_full_uptime_damage_uplift_reference_line"] for r in result),
            "above_reference_interpretation": "用户接受强构筑带来的明显输出跃升；超过旧参考线不是失败、上限违规或阻止完整库的理由。",
            "metrics": result}


def defense_scenarios(base: dict, proposal: dict):
    d = proposal["defense"]
    hp, shield = base["player"]["health"], base["player"]["shield"]
    hp_add, shield_add = base["attribute_artifact_candidates"]["health_max_flat"], base["attribute_artifact_candidates"]["shield_max_flat"]
    armor = sum(d["armor_items"])
    baseline = hp + shield
    table = []
    for defense in d["armor_table"]:
        for projectile in [False, True]:
            multiplier = damage_multiplier(defense, projectile, d)
            table.append({"armor": defense, "enemy_projectile_reduction_equipped": projectile,
                          "incoming_damage_type": "enemy_projectile" if projectile else "all_other_direct_hits",
                          "damage_multiplier": multiplier, "total_reduction_fraction": 1 - multiplier,
                          "raw_damage_potential_per_100_resource": 100 / multiplier})
    upper = []
    for label, resources in [("acquisition_current_stock_no_refill", baseline), ("fully_filled_new_caps", baseline + hp_add + shield_add)]:
        for projectile in [False, True]:
            multiplier = damage_multiplier(armor, projectile, d)
            without = resources / multiplier
            with_once = (resources + d["broken_shield_restore_once_per_room"]) / multiplier
            upper.append({"state": label, "HP_plus_shield_stock": resources, "armor": armor,
                          "incoming_damage_type": "enemy_projectile" if projectile else "all_other_direct_hits",
                          "damage_multiplier": multiplier, "raw_damage_capacity_without_break_restore": without,
                          "relative_to_baseline_400_without_break_restore": without / baseline,
                          "maximum_consumable_once_room_restore": d["broken_shield_restore_once_per_room"],
                          "raw_damage_capacity_with_all_break_restore_consumed": with_once,
                          "relative_to_baseline_400_with_all_break_restore_consumed": with_once / baseline})
    return {"baseline_HP": hp, "baseline_shield": shield, "baseline_resource_stock": baseline,
            "six_item_upper_build": {"HP_max_add": hp_add, "shield_max_add": shield_add, "armor_item_values": d["armor_items"],
                                     "projectile_damage_reduction": d["projectile_damage_reduction"],
                                     "once_room_break_shield_restore": d["broken_shield_restore_once_per_room"], "item_count": 6},
            "armor_table": table, "resource_potential_cases": upper}


def sensitivity(base: dict, proposal: dict):
    cdr_rows, armor_rows = [], []
    sc = proposal["scenarios"]
    synergy = base["fire_synergy"]["cooldown_reduction"] if sc["baseline_has_three_fire_synergy"] else 0
    for spell_id in sc["spell_ids"]:
        spell = base["spells"][spell_id]
        level_spec = spell["levels"][2]
        cd = level_spec.get("cooldown", spell["cooldown"])
        before = cycle(spell["windup"], cd, synergy, base["limits"]["cooldown_reduction"], base["limits"]["minimum_cooldown"])[0]
        for add in proposal["sensitivity"]["cooldown_reduction_add"]:
            after, effective_cd = cycle(spell["windup"], cd, synergy + add, base["limits"]["cooldown_reduction"], base["limits"]["minimum_cooldown"])
            cdr_rows.append({"spell": spell_id, "level": 3, "added_CDR_pp": add * 100, "total_CDR_fraction": synergy + add,
                             "cooldown_seconds": effective_cd, "cycle_seconds": after, "frequency_uplift_fraction": before / after - 1})
    for armor in proposal["sensitivity"]["armor_single_item"]:
        for projectile in [False, True]:
            mult = damage_multiplier(armor, projectile, proposal["defense"])
            armor_rows.append({"armor": armor, "enemy_projectile_reduction_equipped": projectile, "damage_multiplier": mult,
                               "resource_potential_relative_to_no_items": 1 / mult,
                               "marginal_relative_to_projectile_item_alone": ((1 - proposal["defense"]["projectile_damage_reduction"]) if projectile else 1) / mult})
    return {"CDR": cdr_rows, "armor": armor_rows}


def summarize(rows, proposal):
    references = []
    mixed = [r["uplift_fraction"] for r in rows if r["build"] == "mixed_four" and r["spell"] != "F10"]
    full = [r["uplift_fraction"] for r in rows if r["build"] == "offense_six" and r["spell"] != "F10" and r["joint_conditional_uptime"] == 1]
    lo, hi = proposal["design_references"]["mixed_four_damage_uplift_reference"]
    reference_line = proposal["design_references"]["offense_six_full_uptime_damage_uplift_reference_line"]
    references.append({"reference": "mixed_four_damage_uplift", "comparison_range": [lo, hi], "observed_range": [min(mixed), max(mixed)],
                       "comparison": "within_reference" if min(mixed) >= lo and max(mixed) <= hi else "outside_reference",
                       "is_acceptance_gate": False})
    references.append({"reference": "offense_six_full_uptime_uplift", "comparison_line": reference_line, "observed_range": [min(full), max(full)],
                       "comparison": "below_reference" if max(full) <= reference_line else "above_reference",
                       "is_acceptance_gate": False})
    by_uptime = []
    for uptime in proposal["scenarios"]["conditional_uptime"]:
        selected = [r["uplift_fraction"] for r in rows if r["build"] == "offense_six" and r["spell"] != "F10" and r["joint_conditional_uptime"] == uptime]
        by_uptime.append({"joint_conditional_uptime": uptime, "damage_uplift_range": [min(selected), max(selected)]})
    return {"design_reference_comparisons": references, "offense_six_by_uptime": by_uptime,
            "user_direction": proposal["design_references"]["user_direction"],
            "experience_target": proposal["experience_target"],
            "rule_guardrails": {"crit_CDR_mitigation_caps_and_units": "verified_by_model_fidelity_cases",
                                "event_effects_do_not_recursively_trigger_event_effects": "implementation_contract_not_simulated_by_this_static_tool"}}


def pct(value):
    return f"{value * 100:.2f}%"


def markdown(result):
    lines = ["# 通用道具候选：静态数值预算", "", "状态：待审设计，未接入游戏。最终体验目标为**60房含正式Boss通关约30分钟**；当前只实现45房，另15房和正式Boss待设计。本公式预算不模拟关卡战斗，不能推断最终通关时长。", "",
             "用户已明确允许强构筑带来明显输出跃升。10%—30%与90%保留为设计对照，不是用户硬要求、上限或通过门槛；121.32%属于允许探索的强构筑参考。真正需要约束的是暴击／冷却／减伤规则、事件效果不递归触发同类事件、单位和公式正确性。", "",
             "同一已拥有法术、等级、命中、攻击对象与火伤/P03/法阵状态下，对照只变候选通用道具。基线角色读取实际运行引用的源文件：300生命、100护盾、100攻击。", "",
             f"模型版本：`{result['model_version']}`；确定性枚举，随机种子与抽样次数不适用；{len(result['model_validation_cases'])}项手算/边界检查全部通过。", "",
             "## 输出预算", "", "候选三火10%冷却缩减与新增6个百分点相加到16%，上限50%；先按等级取基础CD，再应用0.2秒下限，完整周期=吟唱+有效CD。F10只算理论回盾频率，不能乘攻击、暴击与增伤。", "",
             "| 构筑 | 条件加成覆盖 | 相对同构筑无新增通用道具的伤害提升 | 设计对照 | 说明 |", "|---|---:|---:|---|---|"]
    references = result["summary"]["design_reference_comparisons"]
    mixed = references[0]
    lines.append(f"| 4件混合：攻击15 / CDR6个百分点 / 防御15 / 护盾25 | 不依赖条件 | {pct(mixed['observed_range'][0])}—{pct(mixed['observed_range'][1])} | 10%—30% | 数学对照，不作门槛 |")
    for row in result["summary"]["offense_six_by_uptime"]:
        a, b = row["damage_uplift_range"]
        lines.append(f"| 6件输出：攻击 / CDR / 暴击 / 暴伤 / 完璧 / 狩猎 | {pct(row['joint_conditional_uptime'])} | {pct(a)}—{pct(b)} | 旧90%参考线 | 不设输出硬上限 |")
    first_batch = result["first_batch_all_five_output_items"]
    boundary = result["six_piece_combination_boundary"]
    lines.extend(["", f"首批12件中的全部5个输出项（U03攻击15 / CDR6个百分点 / 暴击8个百分点 / 完璧18% / 狩猎满层18%）同时生效，伤害提升{pct(first_batch['minimum_case']['uplift_fraction'])}—{pct(first_batch['maximum_case']['uplift_fraction'])}。这是既有5%/20%暴击率与1.5/1.75暴击倍率、F01/F07两等级的范围，未包括新暴伤／金色精英／半血项。", "", f"**允许的强构筑参考：**另枚举8种输出候选中任取6件的{boundary['enumerated_rows']}行合法满条件组合。攻击15 / CDR6个百分点 / 完璧18% / 狩猎18% / 精英20% / 半血25%的通用桶合计81%，最高提升{pct(boundary['maximum_case']['uplift_fraction'])}。它高于旧90%参考线，用户已接受这一输出跃升方向；不因此设新增伤硬上限、不判失败，也不据此阻止完整候选库。该数值仍只是精英、半血且两个状态全部生效的短窗口算术上界，不代表整局平均输出。"])
    lines.extend(["", "范围枚举F01/F07的1级与3级、既有暴击率5%/20%、既有暴击倍率1.5/1.75。1.75来自炎法精通三级加0.25暴击倍率，不能误算为加25个百分点暴击率。完璧18%与狩猎满层18%同一通用桶相加为36%，不是1.18×1.18。0/50/100%为两项的伤害加权联合覆盖率假设，不是实测时间占比。", "",
                  "| 法术（3级） | 新增CDR | 有效CD | 完整周期 | 施放频率提升 |", "|---|---:|---:|---:|---:|"])
    for row in result["sensitivity_or_sweep_summary"]["CDR"]:
        lines.append(f"| {row['spell']} | {row['added_CDR_pp']:.0f}个百分点 | {row['cooldown_seconds']:.3f}秒 | {row['cycle_seconds']:.3f}秒 | {pct(row['frequency_uplift_fraction'])} |")
    lines.extend(["", "P04额外施法、P05每8秒削减剩余CD的动态事件未模拟；不能用这里的周期比乘旧21宝物连锁来宣称总收益。F10须存在可回护盾缺口，本表不是保证实际每秒回盾。", "", "## 防御预算", "",
                  "候选最终承伤倍率 = max(0.55, 100/(100+防御) × 敌方弹丸时0.82)，先减伤再消耗护盾和生命。所有减伤合并后最多45%，而非每件分别封顶。不是闪避/无敌；环境和消耗型扣血需实现时另定伤害标签。", "",
                  "| 防御 | 普通直接伤害减免 | 带弹丸减伤道具时的敌方弹丸减免 |", "|---:|---:|---:|"])
    table = result["defense"]["armor_table"]
    for i in range(0, len(table), 2):
        a, b = table[i:i+2]
        lines.append(f"| {a['armor']} | {pct(a['total_reduction_fraction'])} | {pct(b['total_reduction_fraction'])} |")
    lines.extend(["", "6件防御上界：生命上限80 / 护盾上限25 / 防御15 / 防御30 / 弹丸减伤18% / 每房一次破盾回35。基线满资源300+100=400；新上限全满380+125=505。领取时不补生命/护盾，若原为300+100则当刻仍400。", "",
                  "| 资源口径 | 全部伤害类型 | 资源点 | 不触发破盾的原始伤害承受潜力 | 35回盾全部消耗后的潜力上界 |", "|---|---|---:|---:|---:|"])
    for row in result["defense"]["resource_potential_cases"]:
        label = "领取当刻原400未补充" if row["state"].startswith("acquisition") else "新上限505已全满"
        kind = "敌方弹丸" if row["incoming_damage_type"] == "enemy_projectile" else "其他直接命中"
        lines.append(f"| {label} | 100%{kind} | {row['HP_plus_shield_stock']} | {row['raw_damage_capacity_without_break_restore']:.2f}（基线×{row['relative_to_baseline_400_without_break_restore']:.3f}） | {row['raw_damage_capacity_with_all_break_restore_consumed']:.2f}（基线×{row['relative_to_baseline_400_with_all_break_restore_consumed']:.3f}） |")
    lines.extend(["", "以上是纯伤害类型、资源能全部消费的数学潜力上下口径，不能称为平均有效生命、真实容错次数或胜率。35点破盾回盾可能未触发、未全部消耗，满资源505也不保证当场取得；另有当前实际过房护盾回满。未叠加现有F10/B10等持续回盾、无敌帧、走位和伤害离散化。", "",
                  "| 单件防御敏感性 | 其他直接伤害承伤倍率 | 相对无防御的资源潜力 |", "|---:|---:|---:|"])
    for row in result["sensitivity_or_sweep_summary"]["armor"]:
        if not row["enemy_projectile_reduction_equipped"]:
            lines.append(f"| {row['armor']} | {row['damage_multiplier']:.4f} | ×{row['resource_potential_relative_to_no_items']:.2f} |")
    recovery = result["recovery"]
    lines.extend(["", "## 恢复与边界", "", f"每清房恢复3生命，若第6房奖励获得，则仅第7—45房最多{recovery['eligible_future_clear_count']}次，共{recovery['maximum_future_heal']}点；每次实际值=min(3, 缺失生命)。第6房不追补；满血为0；死亡不复活。", "",
                  "## 解释限制与复核", "", *[f"- {x}" for x in result["assumptions_and_omissions"]], "", f"输入哈希、全部{len(result['metrics_by_scenario'])}个指定构筑行（含重复条件用于完整枚举）、{boundary['enumerated_rows']}个6件组合边界行、设计对照与模型检查见同目录budget.json。若运行源变化，先核对模型，再用相同命令重算。"])
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proposal", default=str(Path(__file__).with_name("proposal.json")))
    parser.add_argument("--out", default="build/qa/generic-items-implementation-20261018/static-budget")
    args = parser.parse_args()
    proposal_path = Path(args.proposal).resolve()
    proposal = read_json(proposal_path)
    sources = {name: sha(ROOT / name) for name in proposal["source_files"]}
    base = read_json(ROOT / "data/balance_candidates/first_run_v1.json")
    artifacts = read_json(ROOT / "data/balance_candidates/fire_artifacts_v1.json")
    route = read_json(ROOT / "data/courtyard_route.json")
    # Verify source wiring rather than relying on historical candidate status strings.
    assert '"first_run_v1.json", "_base"' in (ROOT / "scripts/core/first_room_run.gd").read_text(encoding="utf-8-sig")
    assert 'ROOT + "fire_artifacts_v1.json"' in (ROOT / "scripts/core/courtyard_route_run.gd").read_text(encoding="utf-8-sig")
    assert artifacts["items"]["U03"]["attack_add"]["base_ref"] == "attribute_artifact_candidates.attack_flat"
    cases = fidelity_checks(base, proposal)
    rows = output_scenarios(base, proposal)
    summary = summarize(rows, proposal)
    acquisition = proposal["defense"]["recovery_acquired_after_room"]
    count = max(0, route["active_room_count"] - acquisition)
    result = {
        "model_version": proposal["model_version"], "proposal_version": proposal["proposal_version"],
        "status": "static_budget_only_runtime_evidence_separate", "game_or_config_version": {"base": base["version"], "route": route["version"]},
        "source_hashes_sha256": sources, "proposal_hash_sha256": sha(proposal_path), "tool_hash_sha256": sha(Path(__file__)),
        "source_stable": sources == {name: sha(ROOT / name) for name in sources},
        "model_validation_cases": cases, "model_changes": ["v1: correct F02 crit-multiplier classification and F10 level-CD override from inception", "v1.1: expand adjacent six-piece composition boundary; expose coincident elite/half-HP generic-bucket values without changing proposal numbers", "v1.2: follow user direction allowing power jumps; retain10-30percent and90percent only as comparisons, accept121.32percent as a strong-build reference, and clarify final60rooms including Bosses target about30minutes; formulas and numerical outputs unchanged"],
        "parameters": proposal, "seed_and_trial_count": {"deterministic_enumeration": True, "random_seed": None, "random_trials": 0, "output_rows": len(rows)},
        "units": {"time": "seconds", "resource": "HP/shield points", "damage": "raw incoming damage points", "rates": "fraction unless marked pp", "crit_multiplier": "times base hit"},
        "metrics_by_scenario": rows, "summary": summary, "defense": defense_scenarios(base, proposal),
        "six_piece_combination_boundary": output_boundary(base, proposal),
        "first_batch_all_five_output_items": output_boundary(base, proposal, 5, ["attack", "CDR", "crit_rate", "flawless", "hunt"]),
        "recovery": {"acquired_after_room": acquisition, "first_eligible_clear": acquisition + 1,
                     "last_room": route["active_room_count"], "eligible_future_clear_count": count,
                     "heal_per_clear": proposal["defense"]["clear_health_restore"],
                     "maximum_future_heal": count * proposal["defense"]["clear_health_restore"], "actual_heal_rule": "min(3, missing_HP) per eligible clear"},
        "sensitivity_or_sweep_summary": sensitivity(base, proposal),
        "assumptions_and_omissions": [
            "All new items/rules in proposal.json are review candidates; no runtime data/scripts/tests are written and no Godot process is launched.",
            "Runtime source filenames contain candidate but their current core load path is confirmed. Baseline100ATK/300HP/100shield is not copied from unrelated old prototype data.",
            "Output ratios compare identical spells, levels, targets, hit rates and unchanged existing fire/P03/field buckets. Normalized absolute diagnostic damage omits those unchanged buckets, target count, misses, overkill and travel delay.",
            "F01 III assumes primary+secondary hit same target; F07 III assumes center+aftershock hit. This cancels within ratios but is not real realized DPS.",
            "F10 is fixed shield amount, is not crit/ATK-scaled, and only casts with missing shield and a live enemy. Its rate is a theoretical ceiling.",
            "Cycle ratios use continuous windup+cooldown, not120Hz step quantization, targeting availability, initial-cast transient or per-room resets; displayed precision is arithmetic precision, not empirical confidence.",
            "P04 extra-cast selection and P05 interval/remaining-CD dynamics are omitted, as are all other event chains, summons and area-overlap dynamics.",
            "Condition uptime is damage-weighted joint uptime assumed at0/50/100percent, not simulated player uptime; hunt stack ramp and flawless hit resets can substantially reduce it.",
            "Elite20percent and half-health25percent use same additive generic bucket in proposal, but are not both included in the specific six-output build (would require more items).",
            "The proposed crit-multiplier offer requires permanent effective crit chance >=10percent. Base5percent + new8pp reaches13percent and can unlock it without B02. Enumeration checks static eligibility, not offer/acquisition order.",
            "Defense raw-damage capacity is a pure-type, fully-consumable resource bound, not average EHP, guaranteed hits survived, or win rate. Acquisition does not fill new caps.",
            "Full-new-cap and once-room-shield35 are explicit optimistic bounds; actual current stock, discrete hit size, invulnerability, trigger timing and damage mix matter.",
            "最终目标为60房含正式Boss通关约30分钟；当前运行内容仍45房，另15房和Boss待设计。本工具不模拟奖励概率、领取曲线、关卡战斗或时长，不能推断该整局目标是否成立。",
            "用户允许强构筑显著跃升；10%—30%和90%是设计对照，不是硬上限或实施门槛。121.32%保留为允许探索的强构筑参考，不为了压回参考线调整参数。",
            "暴击、冷却、减伤上限及单位／公式通过本模型检查；事件效果不得递归触发事件效果是实施约束，本静态工具未执行任何动态事件链，不能冒充已验证无递归。",
            "Before implementation compare actual ordinary/optimized/short-view builds across fixed seeds; log conditional damage uptime, effective recovery, incoming type mix and any old-treasure feedback loops."
        ],
        "warnings": [],
        "interpretation_notes": ["用户接受明显输出跃升，121.32%作为允许的强构筑参考，超过旧90%线不标平衡失败。", "本工具不能据静态输出推断最终60房含Boss约30分钟的体验目标；仍需后续真实关卡、Boss与试玩证据。"]
    }
    assert result["source_stable"], "source mutated during budget calculation"
    out = Path(args.out)
    if not out.is_absolute():
        out = ROOT / out
    out.mkdir(parents=True, exist_ok=True)
    (out / "budget.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (out / "budget.md").write_text(markdown(result), encoding="utf-8")
    print(json.dumps({"status": result["status"], "model_checks_passed": len(cases), "scenario_rows": len(rows), "source_stable": result["source_stable"],
                      "summary": summary, "recovery": result["recovery"], "out": str(out)}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
