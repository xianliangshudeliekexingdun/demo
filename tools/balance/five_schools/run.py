"""Reproduce provisional five-school numeric checks; never writes runtime data."""
from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import itertools
import json
import math
from pathlib import Path

from model import (MODEL_VERSION, aim_center_reachable, coefficient_buckets, construction_remove,
                   crit_expectation, effective_cd, evaluate, ordered_chain,
                   spell_events, track_path)
from mechanics import checks_for_schools

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def execute(output: Path):
    output.mkdir(parents=True, exist_ok=True)
    config = read(HERE / "parameters.json")
    checks, warnings, inputs = [], [], [HERE / "parameters.json", HERE / "geometry_baseline.json", HERE / "model.py", HERE / "mechanics.py", HERE / "run.py"]

    def check(label, condition, detail=None):
        checks.append({"check": label, "pass": bool(condition), "detail": detail})

    def near(label, actual, expected):
        check(label, math.isclose(actual, expected, abs_tol=1e-7), {"actual": actual, "expected": expected})

    check("config and executable model versions agree", config["model_version"] == MODEL_VERSION)

    anchor_path = ROOT / "data/balance_candidates/first_run_v1.json"
    artifact_path = ROOT / "data/balance_candidates/fire_artifacts_v1.json"
    anchor = read(anchor_path)
    inputs.extend([anchor_path, artifact_path])
    near("configured attack matches observed baseline", config["attack"], anchor["player"]["attack"])
    near("configured base crit matches observed baseline", config["crit_rate"], anchor["player"]["crit_rate"])
    near("configured base crit multiplier matches baseline", config["crit_multiplier"], anchor["player"]["crit_multiplier"])
    check("observed crit attribute uncapped", anchor["limits"]["crit_rate"] is None)
    near("CDR rule matches observed baseline", config["targets"]["cooldown_reduction_cap"], anchor["limits"]["cooldown_reduction"])
    near("minimum CD matches observed baseline", config["targets"]["minimum_cd"], anchor["limits"]["minimum_cooldown"])
    known_ids = set(anchor["spells"]) | set(read(artifact_path)["items"])
    geometry_baseline = read(HERE / "geometry_baseline.json")
    old = geometry_baseline["wind_ring"]
    for distance in old["outbound_limits"]:
        check("rejected old ring far aim not center reachable", not aim_center_reachable(old["target_range"], distance))
    old = geometry_baseline["wind_wings"]
    check("rejected old level1 wing aim not center reachable", not aim_center_reachable(old["target_range"], old["blade_limits"][0], old["side_offset"]))
    old = geometry_baseline["blue_vortex_level2"]
    actual = old["opportunities"] * min(old["intended_total"] / old["opportunities"], old["old_per_pulse_limit"])
    near("rejected old blue pull total only2.4", actual, old["old_reachable_total"])
    check("old pull budget did not meet declared intent", actual < old["intended_total"])

    # Known cases and regressions precede proposal evaluation.
    near("CDR caps at60 percent", effective_cd(10, 3), 4)
    near("minimum CD is .2", effective_cd(.1, .6), .2)
    near("crit above100 no supercrit", crit_expectation(1.8, 1.5), 1.5)
    near("crit baseline expectation", crit_expectation(.05, 1.5), 1.025)
    near("scope buckets add once", coefficient_buckets(100, 1, common=(.18, .18), school=(.15, .25)), 190.4)
    dummy = {"id": "known", "windup": .15, "cooldowns": [1.2] * 3}
    probe = {"mode": "casts", "events": [{"delay": [.15] * 3, "coefficients": [1] * 3, "target_caps": [1] * 3}]}
    ev, count, _ = spell_events(dummy, probe, 1, 60, 0, 1)
    check("known60s cast count45", count == 45 and len(ev) == 45)
    near("first hit after windup and flight", ev[0][0], .3)
    near("last hit horizon retained", ev[-1][0], 59.7)
    late = {"mode": "casts", "events": [{"delay": [2] * 3, "coefficients": [1] * 3, "target_caps": [1] * 3}]}
    check("future damage clipped rather than paid early", not spell_events(dummy, late, 1, 1, 0, 1)[0])
    chained = {"mode": "casts", "events": [
        {"delay": [0] * 3, "coefficients": [1] * 3, "target_caps": [1] * 3},
        {"delay": [.06] * 3, "coefficients": [.75] * 3, "target_caps": [1] * 3, "minimum_targets": [2] * 3},
    ]}
    check("unused chain never returns to lone target", len(spell_events(dummy, chained, 1, .4, 0, 1)[0]) == 1)
    check("second chain requires second live target", len(spell_events(dummy, chained, 1, .4, 0, 2)[0]) == 2)
    excluded = {"mode": "casts", "events": [{"delay": [0] * 3, "coefficients": [1] * 3, "target_caps": [3] * 3, "excluded_targets": 1}]}
    check("fragment cannot hit excluded primary", not spell_events(dummy, excluded, 1, .4, 0, 1)[0])
    pet_spell = {"id": "pet-known", "windup": .5, "cooldowns": [1] * 3}
    pet = {"mode": "summon", "capacity": [1] * 3, "duration": [2] * 3,
           "attack_interval": [.5] * 3, "attack_delay": [.5] * 3,
           "attack_coefficient": [1] * 3, "target_caps": [1] * 3, "summon_per_cast": [1] * 3}
    ev, count, stats = spell_events(pet_spell, pet, 1, 2.5, .6, 1)
    check("pet includes final attack before expiry", len(ev) == 4 and count == 1 and stats["max_alive"] == 1)
    ev, count, _ = spell_events(pet_spell, pet, 1, 3, .6, 1)
    check("full pet board waits then casts complete windup", count == 2 and len(ev) == 4)
    for horizon in (30, 60, 300):
        check("summon capacity bounded", spell_events(pet_spell, pet, 1, horizon, .6, 6)[2]["max_alive"] <= 1, horizon)
    positions = {"a": (0, 0), "b": (2, 0), "c": (4, 0), "d": (12, 0)}
    check("chain path distance and no revisit", ordered_chain("a", positions, 20, 3.5) == ["a", "b", "c"])
    check("per-edge LOS blocks connection", ordered_chain("a", positions, 20, 3.5, {frozenset(("b", "c"))}) == ["a", "b"])
    check("single node remains single", ordered_chain("a", {"a": (0, 0)}, 20, 3.5) == ["a"])
    for reason in ("consume", "expire", "replace"):
        objects = {1: {"kind": "pillar"}}
        paid = [construction_remove(objects, 1, value, {"consume", "expire"}) for value in (reason, "expire", "consume")]
        check("construction one terminal transition", sum(paid) <= 1 and not objects, reason)
    near("wall input grants no path distance", track_path([(0, 0)] * 10), 0)
    near("resolved movement grants real path", track_path([(0, 0), (1, 0), (1, 1)]), 2)
    near("teleport edge excluded", track_path([(0, 0), (100, 100), (101, 100)], {1}), 1)

    schools, rows, starters = [], [], []
    all_ids = set()
    for school_id in config["school_order"]:
        path = HERE / f"{school_id}.json"
        school = read(path)
        inputs.append(path)
        schools.append(school)
        check("explicit pending design status", school.get("status") == "proposed_unapproved_not_runtime", school_id)
        spells, items = school["spells"], school["items"]
        check("ten spells per school", len(spells) == 10, school_id)
        check("one passive per school", sum(bool(s["passive"]) for s in spells) == 1, school_id)
        check("three independent starters", sum(bool(s["starter"]) for s in spells) == 3, school_id)
        check("sixteen profession items", len(items) == 16, school_id)
        check("ten blue three purple three gold", [sum(i["rarity"] == rarity for i in items) for rarity in ["blue", "purple", "gold"]] == [10, 3, 3], school_id)
        for entry in spells + items:
            check("global stable ID unique", entry["id"] not in all_ids, entry["id"])
            all_ids.add(entry["id"])
            check("localized name exists", bool(entry.get("name")), entry["id"])
            check("new IDs do not overwrite approved content", entry["id"] not in known_ids or entry["id"] in {"F04", "B04", "P01", "G02"}, entry["id"])
        for spell in spells:
            check("three complete level objects", len(spell["levels"]) == 3 and all(isinstance(x, dict) and x for x in spell["levels"]), spell["id"])
            check("explicit level CD array", len(spell["cooldowns"]) == 3 and all(math.isfinite(x) and x >= 0 for x in spell["cooldowns"]), spell["id"])
            check("finite nonnegative windup", math.isfinite(spell["windup"]) and spell["windup"] >= 0, spell["id"])
        for item in items:
            check("item qualification and full effect", isinstance(item.get("requires"), list) and bool(item.get("effect")), item["id"])
            check("item explicit numeric parameters", isinstance(item.get("params"), dict) and bool(item["params"]), item["id"])
        spells_by_id = {s["id"]: s for s in spells}
        probes = school["starter_probes"]
        check("starter probe IDs match", {p["spell_id"] for p in probes} == {s["id"] for s in spells if s["starter"]} and len(probes) == 3, school_id)
        for probe in probes:
            spell = spells_by_id[probe["spell_id"]]
            check("probe assumptions named", bool(probe.get("assumptions")), spell["id"])
            if probe["mode"] == "summon":
                check("summon probe finite positive life and intervals", all(x > 0 and math.isfinite(x) for key in ["duration", "attack_interval", "attack_delay"] for x in probe[key]), spell["id"])
                check("summon probe capacity is bounded positive integer", all(isinstance(x, int) and x > 0 for key in ["capacity", "summon_per_cast"] for x in probe[key]), spell["id"])
            starter = evaluate(spell, probe, 1, 30, 0, 1, 1, config["attack"], 0, config["crit_multiplier"], config["target_health"])
            starters.append({"school": school_id, "name": spell["name"], **starter})
            check("starter first hit within2s in stated static scenario", starter["first_hit"] is not None and starter["first_hit"] <= config["targets"]["starter_max_first_hit_seconds"], spell["id"])
            check("starter defeats180 within6s all-hit noncrit", starter["ttk180_isolated_noncritical_all_hit"] is not None and starter["ttk180_isolated_noncritical_all_hit"] <= config["targets"]["starter_max_ttk180_seconds"], spell["id"])
            for level, horizon, cdr, targets, accuracy in itertools.product(range(1, 4), config["horizons"], config["cooldown_reductions"], config["target_counts"], config["accuracy_expectations"]):
                result = evaluate(spell, probe, level, horizon, cdr, targets, accuracy, config["attack"], config["crit_rate"], config["crit_multiplier"], config["target_health"])
                rows.append({"school": school_id, "name": spell["name"], **result})
                check("finite nonnegative event budget", math.isfinite(result["expected_dps"]) and result["expected_dps"] >= 0, f"{spell['id']}/{level}/{horizon}/{cdr}/{targets}/{accuracy}")
                if probe["mode"] == "summon":
                    check("candidate summon occupancy bounded", result["max_alive"] <= probe["capacity"][level - 1], spell["id"])

    mechanic_samples = checks_for_schools(schools, check, near)
    school_map = {s["school_id"]: s for s in schools}
    geometry_sensitivity = []
    for school_id, spell_id, case in [("wind", "W02", "return_path_misses"), ("wind", "W03", "short_path_no_long_flight_bonus"), ("earth", "R02", "inner_radius_no_outer_bonus")]:
        school = school_map[school_id]
        spell = next(s for s in school["spells"] if s["id"] == spell_id)
        base = next(p for p in school["starter_probes"] if p["spell_id"] == spell_id)
        changed = copy.deepcopy(base)
        if spell_id == "W02":
            changed["events"] = changed["events"][:1]
        elif spell_id == "W03":
            changed["events"][0]["coefficients"][2] = spell["levels"][2]["main"]
        else:
            changed["events"][0]["coefficients"][2] = spell["levels"][2]["main"]
        original = evaluate(spell, base, 3, 60, 0, 1, 1, config["attack"], 0, config["crit_multiplier"])
        degraded = evaluate(spell, changed, 3, 60, 0, 1, 1, config["attack"], 0, config["crit_multiplier"])
        check("geometric advantage removed changes damage", degraded["expected_damage"] < original["expected_damage"], spell_id)
        geometry_sensitivity.append({"spell_id": spell_id, "case": case, "all_hit_noncrit_dps": degraded["expected_dps"], "baseline_geometry_dps": original["expected_dps"], "note": "Declared fixed-path counterfactual, not an AI or movement prediction."})
    spirit = school_map["spirit"]
    pet_spell = next(s for s in spirit["spells"] if s["id"] == "F04")
    p01_probe = copy.deepcopy(next(p for p in spirit["starter_probes"] if p["spell_id"] == "F04"))
    p01_probe["capacity"] = [x + 1 for x in p01_probe["capacity"]]
    p01_probe["summon_per_cast"] = [x + 1 for x in p01_probe["summon_per_cast"]]
    for horizon in (30, 60, 300):
        data = evaluate(pet_spell, p01_probe, 3, horizon, .6, 1, 1, config["attack"], 0, config["crit_multiplier"])
        check("P01 real event schedule still capacity2", data["max_alive"] <= 2 and data["summons"] >= 2, horizon)
    wind_spells = {s["id"]: s for s in school_map["wind"]["spells"]}
    for index in range(3):
        level = wind_spells["W02"]["levels"][index]
        check("wind ring legal aim is within outbound travel", aim_center_reachable(wind_spells["W02"]["target_range_by_level"][index], level["out_distance"]))
        level = wind_spells["W07"]["levels"][index]
        check("wing offset still reaches legal aim", aim_center_reachable(wind_spells["W07"]["target_range_by_level"][index], level["length"], level["side_offset"]))
    wind_items = {i["id"]: i for i in school_map["wind"]["items"]}
    blue = wind_items["WB05"]["params"]
    for level in wind_spells["W05"]["levels"]:
        opportunities = int(level["duration"] / level["interval"])
        intent = min(blue["pull_total_max"], level["pull_total"] + blue["pull_total_add"])
        achievable = opportunities * min(intent / opportunities, blue["pull_tick_max"])
        near("selected blue vortex can achieve declared full budget", achievable, intent)
    report = {
        "model_version": MODEL_VERSION,
        "model_changes": [geometry_baseline["model_revision"], "1.1 also separates short/long/return-miss geometry and capacity-bound P01 schedules; these are design constraints, not runtime changes."],
        "scope": "Pending design-only isolated cast/summon event budgets and finite-state boundary checks, not current Godot effects or population playtesting.",
        "checks": len(checks), "failures": sum(not row["pass"] for row in checks),
        "check_details": checks,
        "failed": [row for row in checks if not row["pass"]], "warnings": warnings,
        "counts": {"schools": len(schools), "spells": sum(len(s["spells"]) for s in schools), "items": sum(len(s["items"]) for s in schools), "starter_scenarios": len(rows)},
        "seed_and_trial_count": {"random_model": False, "seeds": None, "deterministic_starter_scenarios": len(rows), "note": "Accuracy and crit are explicit expectation factors; no random proc trajectory or human population sampled."},
        "assumptions_and_omissions": config["assumptions"],
        "starters": starters,
        "mechanic_samples": mechanic_samples,
        "geometry_sensitivity": geometry_sensitivity,
        "input_sha256": {p.relative_to(ROOT).as_posix(): sha(p) for p in inputs},
        "sensitivity": "The same chosen parameters were swept over CDR0/30/60%,1/6 valid targets,100/65% accuracy expectation,30/60seconds and all three levels. No one-score optimizer or automatic runtime change.",
    }
    (output / "results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    with (output / "starter_scenarios.csv").open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    lines = ["# 五系候选数值核验", "", f"模型 `{MODEL_VERSION}`；{report['checks']}项检查／{report['failures']}失败；{len(rows)}条确定性起手包络。", "",
             "本报告只核验候选文档的独立起手、事件预算和边界，不表示其余五系已实现或平衡通过。不模拟敌人AI、玩家生存、路径寻找、自然库存、正式Boss及整局时长。", "",
             "| 学派 | 起手 | 一级首击(秒) | 180生命孤立沙包非暴击全中TTK(秒) |", "|---|---|---:|---:|"]
    for row in starters:
        first, ttk = row["first_hit"], row["ttk180_isolated_noncritical_all_hit"]
        lines.append(f"| {row['school']} | {row['name']} | {first:.3f} | {ttk:.3f} |" if first is not None and ttk is not None else f"| {row['school']} | {row['name']} | {first} | {ttk} |")
    lines += ["", "## 数值敏感性", "", report["sensitivity"], "", "逐场景数据见 `starter_scenarios.csv`。65%命中是线性期望输入，不是执行随机命中或玩家分段；暴击DPS为基础5%/1.5倍期望，TTK另用无暴击全中，不以平均伤害除生命冒充离散TTK。", "",
              "冻结基础时长0.9/1.2/1.5秒×免控2.5/3/4秒，共9组宽松硬控占空上界；普通连锁距离3/3.5/4米在3.4米点列测连接断点。选定3秒免控保证有限硬控，选定3.5米能连该点列；这些是候选取舍，未从静态推断真人难度。", "",
              "| 退化情境 | 三级单体60秒无暴击DPS | 对照路径DPS |", "|---|---:|---:|"]
    for row in geometry_sensitivity:
        lines.append(f"| {row['spell_id']} {row['case']} | {row['all_hit_noncrit_dps']:.2f} | {row['baseline_geometry_dps']:.2f} |")
    lines += ["", "这三组分别移除回程、长程和外缘奖励；反映几何条件丢失的代价，不保证玩家实际命中。群体投射物包络用声明的代表测距／分量时间，未逐敌求飞行到达；因此不将帧级末尾的差异视作实机精度。", "",
              "## 独立机制与组合边界", "", "寒霜单阶段/早碎冰免控/不续窗、单敌连锁无回压、过载只增强旧边、风痕跨实例滚动命中预算、构造唯一终结/替换上限、P01容量与有限延寿分别检查，详见results.json的mechanic_samples。IB07+IG02一级碎冰分量为384%；L08三级+LG03在6节点的总系数17；RG02替换旧弱次回响后R07三级总系数5.8；S05三级四只合法契灵总系数4.4。上述各有目标/资源/自然事件前提，不是四个单体绝对排名或自然库存承诺。", "", "SP02原先仅要求契印/召唤来源时，三级S08+F04可领却裸周期5.25秒大于自身契印4秒，没有旧印命中；当前候选额外要求S01或S06，保留标记来源条件。该反例及灵鹰索敌8米、追至实际扫掠3米再攻击的可达性均加回归。", "", "## 失败与局限", ""]
    lines.extend(f"- {row['check']}: {row['detail']}" for row in report["failed"])
    lines.extend(f"- {line}" for line in config["assumptions"])
    (output / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Five-school candidate checks: {report['checks']}, failures: {report['failures']}, scenarios: {len(rows)}")
    for row in report["failed"]:
        print(row)
    return report["failures"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/qa/five-schools-design-20261018")
    args = parser.parse_args()
    raise SystemExit(bool(execute(args.output.resolve())))
