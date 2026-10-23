"""Reproduce lightning growth proposal checks without launching Godot."""
from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import itertools
import json
import math
from pathlib import Path

from model import (EPS, MODEL_VERSION, actual_shield, connected_component,
                   connection_path, crit_factor, effective_cd, overload_budget,
                   simulate)

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_csv(path, rows):
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def execute(output, proposal_path, scenarios_path):
    output.mkdir(parents=True, exist_ok=True)
    old_path = ROOT / "tools/balance/five_schools/lightning.json"
    old_model_path = old_path.parent / "model.py"
    baseline, proposal, config = read(old_path), read(proposal_path), read(scenarios_path)
    anchor_path = ROOT / "data/balance_candidates/first_run_v1.json"
    anchor = read(anchor_path)
    checks = []

    def check(name, condition, detail=None):
        checks.append({"check": name, "pass": bool(condition), "detail": detail})

    def near(name, a, b):
        check(name, math.isclose(a, b, abs_tol=1e-6), {"actual": a, "expected": b})

    check("model and scenario versions agree", config["model_version"] == MODEL_VERSION)
    check("proposal explicitly is not runtime", proposal["status"] == "proposed_not_runtime_not_final_balance")
    for key in ("attack", "crit_rate", "crit_multiplier"):
        near("observed runtime anchor " + key, config[key], anchor["player"][key])
    near("runtime CDR cap", anchor["limits"]["cooldown_reduction"], .6)
    near("runtime minimum CD", anchor["limits"]["minimum_cooldown"], .2)
    near("CDR60 and above caps", effective_cd(10, 1.2), 4)
    near("minimum CD", effective_cd(.1, .6), .2)
    near("no supercrit above100", crit_factor(1.8, 1.5), 1.5)
    near("baseline crit expectation", crit_factor(.05, 1.5), 1.025)
    check("exactly ten stable spell IDs", [s["id"] for s in proposal["spells"]] == [f"L{i:02d}" for i in range(1, 11)])
    check("three starters one passive", sum(s["starter"] for s in proposal["spells"]) == 3 and sum(s["passive"] for s in proposal["spells"]) == 1)
    for old, new in zip(baseline["spells"], proposal["spells"]):
        check("level1 remains original baseline", old["levels"][0] == {k: v for k, v in new["levels"][0].items() if k != "conductive_duration_add"}, old["id"])
        check("three complete level objects", len(new["levels"]) == 3 and all(new["levels"]), new["id"])
    old_spells = {s["id"]: s for s in baseline["spells"]}
    spells = {s["id"]: s for s in proposal["spells"]}
    geometries = {g["id"]: g for g in config["geometries"]}
    isolated, dense = geometries["isolated"], geometries["dense"]
    # Independent original three-starter implementation checks timing and damage.
    module_spec = importlib.util.spec_from_file_location("frozen_five_school_model", old_model_path)
    frozen = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(frozen)
    for probe in baseline["starter_probes"]:
        spell = old_spells[probe["spell_id"]]
        for level, cdr in itertools.product((1, 2, 3), (0, .6)):
            expected = frozen.evaluate(spell, probe, level, 60, cdr, 1, 1)
            actual = simulate(baseline, spell["id"], level, isolated, 60, cdr)
            near("original independent starter baseline damage", actual["damage"], expected["expected_damage"])
            near("original independent starter baseline first hit", actual["first_hit"], expected["first_hit"])
            check("original independent starter baseline casts", actual["casts"] == expected["casts"])
    for spell_id in ("L01", "L02", "L03"):
        budget = simulate(proposal, spell_id, 1, isolated, 10, crit_rate=0)
        check("starter first hit within0.5s and TTK180 within4s", budget["first_hit"] <= .5 and budget["ttk180_noncrit_all_hit"] <= 4, {"spell": spell_id, **budget})
    near("L03 original level3 finite geometric sum", sum(2.2 * .75 ** j for j in range(5)), 6.71171875)
    near("L03 candidate level3 finite geometric sum", sum(2.2 * .85 ** j for j in range(5)), 8.15898875)
    positions = {"a": (0, 0), "b": (3.4, 0), "c": (6.8, 0), "d": (12, 0)}
    check("chain no revisit and no disconnected target", connection_path("a", positions, lambda k: False, 99) == ["a", "b", "c"])
    check("chain edge-specific LOS", connection_path("a", positions, lambda k: False, 99, blocked=[("b", "c")]) == ["a", "b"])
    long = {"a": (0, 0), "b": (4.8, 0)}
    check("L10level3 connects old marks at4.8m", len(connection_path("a", long, lambda k: True, 2, mastery_add=.5)) == 2)
    check("L10 does not connect unmarked4.8m", len(connection_path("a", long, lambda k: False, 2, mastery_add=.5)) == 1)
    check("without L10old marks4.8m disconnected", len(connection_path("a", long, lambda k: True, 2)) == 1)
    branch = {"a": (0, 0), "b": (4, 0), "c": (-4, 0), "d": (0, 4)}
    check("overload counts complete branched component", len(connected_component("a", branch, lambda k: True)) == 4)
    expires_chain = {"id": "expiry_between_chain_edges", "positions": {"a": [2, 0], "b": [6, 0]},
                     "initial_conduction": {"a": {"expiry": 20, "start": -2}, "b": {"expiry": .24, "start": -2}}}
    expires_net = {"id": "expiry_between_network_edges", "positions": {"a": [2, 0], "b": [6, 0]},
                   "initial_conduction": {"a": {"expiry": 20, "start": -2}, "b": {"expiry": .45, "start": -2}}}
    check("chain rechecks expired endpoint at actual delayed hop", simulate(proposal, "L03", 3, expires_chain, .5)["hit_events"] == 1)
    check("network rechecks expired endpoint at actual delayed edge", simulate(proposal, "L08", 3, expires_net, .8)["hit_events"] == 1)
    stable_net = {**expires_net, "initial_conduction": {"a": {"expiry": 20, "start": -2}, "b": {"expiry": 20, "start": -2}}}
    check("network live endpoint still permits delayed edge", simulate(proposal, "L08", 3, stable_net, .8)["hit_events"] == 2)
    overload_rows = []
    for nodes, natural in itertools.product((1, 2, 3, 6), (False, True)):
        total, edges, boosted = overload_budget(spells["L08"]["levels"][2], proposal["mechanics"]["overload"], nodes, natural)
        check("overload only boosts existing edges", 0 <= boosted <= edges <= nodes - 1)
        if nodes == 1:
            near("isolated network no empty-edge compensation", total, 2.6)
        if nodes == 3 and natural:
            near("three-node network has only two boosted edges", total, 8.9)
        if nodes == 6:
            near("six-node natural or extra coefficient known", total, 17 if natural else 13.4)
        overload_rows.append({"nodes": nodes, "natural": natural, "edges": edges, "boosted": boosted, "coefficient": total})
    for missing, expected in ((0, 0), (10, 10), (100, 37.5)):
        near("actual shield clipped after restoration multiplier", actual_shield(30, missing, 1.25), expected)
    # Baseline has no state-proc assumptions needed for cloud replacement check.
    cloud = simulate(baseline, "L05", 3, isolated, 30, .6, crit_rate=0)
    check("highCDR unique cloud cancels old fourth strikes", cloud["unique_cloud_cancellations"] > 0)
    cloud_natural = simulate(proposal, "L05", 3, isolated, 2.3, crit_rate=0)
    cloud_extra = simulate(proposal, "L05", 3, isolated, 2.3, natural=False, crit_rate=0)
    near("cloud first hit no retroactive vulnerability then second benefits", cloud_natural["damage"], 258)
    near("extra cloud never supplies natural vulnerability", cloud_extra["damage"], 240)
    # End-of-horizon delays never pay future damage early.
    late = simulate(proposal, "L01", 1, isolated, .15)
    check("projectile after horizon not prepaid", late["casts"] == 1 and late["hit_events"] == 0)
    no_arc = simulate(proposal, "L07", 3, dense, 1.0, maintained=True, target_survives=False, crit_rate=0)
    near("killed judgment main prevents conditional and arcs", no_arc["damage"], 720)
    check("killed judgment main never receives a mark", no_arc["mark_applications"] == 0)
    natural = simulate(proposal, "L07", 3, dense, 1.0, maintained=True, crit_rate=0)
    extra = simulate(proposal, "L07", 3, dense, 1.0, maintained=True, natural=False, crit_rate=0)
    near("mature judgment natural upper bound", natural["damage"], 1320)
    near("extra judgment lacks natural neighbor arcs", extra["damage"], 960)
    bare = simulate(proposal, "L07", 3, dense, 1.0, maintained=False, crit_rate=0)
    near("bare judgment first hit cannot self-supply old mark", bare["damage"], 720)
    near("mastery3 and resonance share bucket", 1 + spells["L10"]["levels"][2]["school_damage_bonus"] + proposal["mechanics"]["resonance"]["school_damage_bonus"], 1.35)
    near("mastery2 normal mark duration", 4 + spells["L10"]["levels"][1]["conductive_duration_add"], 4.75)
    near("mastery3 long mark duration", 6 + spells["L10"]["levels"][2]["conductive_duration_add"], 7.5)
    draining_full_shield = simulate(proposal, "L09", 3, dense, 60, .6, shield_missing=0, shield_drain_per_second=5, missing_cap=100)
    check("initial full shield later drain creates legal restore", draining_full_shield["casts"] > 0 and 0 < draining_full_shield["restored_shield"] <= 300 + EPS)
    first_wave_marks = simulate(proposal, "L04", 3, dense, .25)
    check("L04 level3 single round marks only main plus five", first_wave_marks["mark_applications"] == 6)
    maintained_wave = simulate(proposal, "L04", 3, dense, .25, maintained=True)
    check("L04 does not refresh marked neighbors", maintained_wave["mark_applications"] == 1)

    rows, indexed = [], {}
    for version, data in (("original_20261018", baseline), ("proposal_v1_20261021", proposal)):
        for spell, level, horizon, cdr, geometry, maintained, accuracy in itertools.product(
                data["spells"], (1, 2, 3), config["horizons"], config["cdr"], config["geometries"],
                config["maintained_conduction"], config["accuracy_expectations"]):
            result = simulate(data, spell["id"], level, geometry, horizon, cdr, accuracy,
                              maintained, config["attack"], config["crit_rate"], config["crit_multiplier"])
            if geometry["id"] != "isolated" or accuracy != 1:
                result["ttk180_noncrit_all_hit"] = None
            row = {"version": version, "spell_id": spell["id"], "level": level, "horizon": horizon,
                   "cdr": cdr, "geometry": geometry["id"], "externally_maintained_old_conduction": maintained,
                   "accuracy_linear_expectation": accuracy, "expected_dps": result["damage"] / horizon, **result}
            rows.append(row)
            indexed[(version, spell["id"], level, horizon, cdr, geometry["id"], maintained, accuracy)] = row
            check("finite nonnegative budget", math.isfinite(result["damage"]) and result["damage"] >= 0, [version, spell["id"], level, horizon, cdr, geometry["id"], maintained, accuracy])
    for spell_id, horizon, cdr, geometry, maintained, accuracy in itertools.product(
            [f"L{i:02d}" for i in range(1, 9)], config["horizons"], config["cdr"],
            [g["id"] for g in config["geometries"]], config["maintained_conduction"], config["accuracy_expectations"]):
        growth = [indexed[("proposal_v1_20261021", spell_id, level, horizon, cdr, geometry, maintained, accuracy)]["damage"] for level in (1, 2, 3)]
        check("same-scenario growth never reduces budget", growth[0] <= growth[1] + 1e-6 <= growth[2] + 2e-6, [spell_id, horizon, cdr, geometry, maintained, accuracy, growth])
    for maintained in (False, True):
        a = indexed[("proposal_v1_20261021", "L02", 3, 60, 0, "isolated", maintained, 1)]["damage"]
        b = indexed[("proposal_v1_20261021", "L03", 3, 60, 0, "isolated", maintained, 1)]["damage"]
        c = indexed[("proposal_v1_20261021", "L02", 3, 60, 0, "dense", maintained, 1)]["damage"]
        d = indexed[("proposal_v1_20261021", "L03", 3, 60, 0, "dense", maintained, 1)]["damage"]
        check("situational advantage: gun solo chain dense", a > b and d > c, {"maintained": maintained, "gun_solo": a, "chain_solo": b, "gun_dense": c, "chain_dense": d})

    sensitivity = []
    for spell_id, scale, geometry, maintained in itertools.product([f"L{i:02d}" for i in range(1, 11)], config["primary_scales"], (isolated, dense), (False, True)):
        result = simulate(proposal, spell_id, 3, geometry, 60, .6, maintained=maintained, primary_scale=scale)
        sensitivity.append({"spell_id": spell_id, "primary_body_scale": scale, "geometry": geometry["id"], "maintained_old_conduction": maintained,
                            "expected_dps": result["damage"] / 60, "derived_damage": result["derived_damage"], "restored_shield": result["restored_shield"]})
    build_rows = []
    for version, data in (("original", baseline), ("proposal", proposal)):
        for spell_id, maintained in itertools.product(("L01", "L03", "L07", "L08"), (False, True)):
            result = simulate(data, spell_id, 3, dense, 60, .6, maintained=maintained, mastery_level=3, resonance=True, crit_rate=1.8)
            build_rows.append({"version": version, "spell_id": spell_id, "maintained_old_conduction": maintained, "mastery_level": 3,
                               "resonance": True, "attribute_cdr": .6, "crit_rate": 1.8, "expected_dps": result["damage"] / 60, **result})
    shield_rows = []
    for level, missing, drain in itertools.product((1, 2, 3), (0, 10, 100), (0, 5)):
        result = simulate(proposal, "L09", level, dense, 60, .6, shield_missing=missing, shield_drain_per_second=drain)
        shield_rows.append({"level": level, "initial_missing": missing, "missing_cap": 100, "declared_shield_drain_per_second": drain, **result})
        check("shield cannot exceed supplied deficit", result["restored_shield"] <= missing + drain * 60 + EPS, shield_rows[-1])
        if missing == 0 and drain == 0:
            check("full shield no cast no marks", result["casts"] == result["mark_applications"] == 0)
        if missing == 10 and drain == 0:
            near("missing10 no phantom extra restore", result["restored_shield"], 10)
    # Direct-body scale cannot multiply the explicitly derived part.
    for spell_id in ("L07", "L08"):
        values = [r["derived_damage"] for r in sensitivity if r["spell_id"] == spell_id and r["geometry"] == "dense" and r["maintained_old_conduction"]]
        check("body sensitivity leaves derived component unchanged", max(values) - min(values) < 1e-6, spell_id)

    cloud_sweep = []
    for version, data in (("original", baseline), ("proposal", proposal)):
        for cdr in (.45, .5, .55, .6):
            result = simulate(data, "L05", 3, isolated, 60, cdr)
            cloud_sweep.append({"version": version, "cdr": cdr, "expected_dps": result["damage"] / 60, **result})
    cloud_warnings = []
    for version in ("original", "proposal"):
        series = [r for r in cloud_sweep if r["version"] == version]
        for low, high in zip(series, series[1:]):
            if high["expected_dps"] + EPS < low["expected_dps"]:
                cloud_warnings.append({"warning": "CDR threshold lowers cloud output under persistent1.4s shared gate", "version": version,
                                       "lower_cdr": low["cdr"], "higher_cdr": high["cdr"], "lower_cdr_dps": low["expected_dps"], "higher_cdr_dps": high["expected_dps"]})
    check("cloud threshold sweep actually encounters shared-gate blocks", any(r["shared_cloud_gate_blocks"] for r in cloud_sweep))

    inputs = [proposal_path, scenarios_path, old_path, old_model_path, anchor_path, HERE / "model.py", HERE / "run.py"]
    report = {"model_version": MODEL_VERSION, "proposal_version": proposal["proposal_version"],
              "scope": "Design-only independent spell budgets and fixed-state boundary checks; not Godot gameplay or final balance.",
              "checks": len(checks), "failures": sum(not c["pass"] for c in checks), "failed": [c for c in checks if not c["pass"]],
              "check_details": checks, "deterministic_budget_rows": len(rows), "sensitivity_rows": len(sensitivity), "build_boundary_rows": len(build_rows),
              "seed_and_trials": {"random_sampling": False, "seeds": None, "note": "Crit and65% accuracy are expectation factors, not random event trajectories or human skill bands."},
              "input_sha256": {p.relative_to(ROOT).as_posix(): sha(p) for p in inputs},
              "assumptions_and_omissions": config["assumptions_and_omissions"],
              "overload_boundaries": overload_rows, "shield_cases": shield_rows, "build_boundaries": build_rows,
              "cloud_cdr_threshold_sweep": cloud_sweep, "warnings": cloud_warnings,
              "selected_tradeoff": "Preserve original level1 and direct-damage anchors; migrate10 bounded effects, reserve6 sources. No proposed L03 tail arc, L07+80pp, L09+10shield or L10higher damage inflation.",
              "model_changes": ["Separate versioned proposal; original candidate unchanged.", "Full old-conductive component is counted for overload; an actual no-revisit path alone delivers damage.", "Unique-cloud cancellation and persistent per-actor shared gate are executed before interpreting high-CDR output."]}
    (output / "results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_csv(output / "spell_budgets.csv", rows)
    write_csv(output / "sensitivity.csv", sensitivity)
    write_csv(output / "build_boundaries.csv", build_rows)
    write_csv(output / "cloud_cdr_thresholds.csv", cloud_sweep)
    lines = ["# 雷系三级成长提案离线核算", "", f"模型 `{MODEL_VERSION}`；{len(checks)}项检查／{report['failures']}失败；{len(rows)}条独立法术预算。", "",
             "提案未接入游戏。静止永生目标预算不是自然命中、完整八槽构筑、真人难度、性能或最终平衡结论。", "",
             "## 同情境对照", "", "攻击100，基础5%／1.5倍暴击期望，60秒、0CDR、全中。旧导电列是外部持续布点且年龄≥2秒的设置上界，外部法术的槽位／时间／伤害未计入。", "",
             "| 法术 | 情境 | 原稿三级DPS | 本版三级DPS |", "|---|---|---:|---:|"]
    for spell_id, geometry, maintained in itertools.product([f"L{i:02d}" for i in range(1, 9)], ("isolated", "dense"), (False, True)):
        old = indexed[("original_20261018", spell_id, 3, 60, 0, geometry, maintained, 1)]["expected_dps"]
        new = indexed[("proposal_v1_20261021", spell_id, 3, 60, 0, geometry, maintained, 1)]["expected_dps"]
        lines.append(f"| {spell_id} | {geometry}／{'维持旧导电' if maintained else '仅自身导电'} | {old:.3f} | {new:.3f} |")
    lines += ["", "## 边界与取舍", "",
              "- L03三级满5目标总系数原稿6.71171875，本版8.15898875；不新增第6敌或尾弧。",
              "- L08三级自然、6个旧导电节点时总系数17；追加保留13.4；3节点自然总系数8.9，只有两条实际边，单敌2.6。",
              "- L07三级首次裁决：无旧导电或本次主击击杀时720%；成熟旧导电且主目标始终存活时，720%+240%+2×180%=1320%群体上界；孤立旧导电为960%。",
              "- L09缺10只回10；满盾不施放。持续5盾／秒损失仅为显式供给探针，不是敌人伤害或存活率。",
              "- L10三级和共鸣同桶雷伤35%，普通新导电5.5秒、长导电7.5秒，双端旧导电连接5米；其他布点／邻弧范围不扩大。",
              "- 直接本体±10%扫描详见sensitivity.csv；没有缩放非暴击派生、回复或状态期限。",
              "", "## 云团高CDR时序", ""]
    for version in ("original_20261018", "proposal_v1_20261021"):
        for cdr in (0, .3, .6):
            row = indexed[(version, "L05", 3, 60, cdr, "isolated", False, 1)]
            lines.append(f"- {version}／CDR{cdr:.0%}：释放{row['casts']}次，有效落雷{row['hit_events']}次，因替换取消旧波{row['unique_cloud_cancellations']}次；DPS {row['expected_dps']:.3f}。")
    lines += ["", "## 模型边界", ""] + ["- " + note for note in config["assumptions_and_omissions"]]
    lines += ["", "## 云团CDR阈值警告", "", "唯一替换与跨云1.4秒门可能让CDR增加反而降低输出；保留真实结果，不以改伤害掩盖。目标先按固定名额选择，门挡后不补选，也不刷新导电或消耗该cast首次真实命中资格。", ""]
    for row in cloud_sweep:
        lines.append(f"- {row['version']}／{row['cdr']:.0%}CDR：{row['hit_events']}次有效落雷、{row['shared_cloud_gate_blocks']}次门挡、DPS {row['expected_dps']:.3f}。")
    lines += ["- " + json.dumps(note, ensure_ascii=False) for note in cloud_warnings]
    if report["failed"]:
        lines += ["", "## 失败", ""] + ["- " + json.dumps(c, ensure_ascii=False) for c in report["failed"]]
    (output / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"checks": report["checks"], "failures": report["failures"], "budget_rows": len(rows), "sensitivity_rows": len(sensitivity), "build_rows": len(build_rows), "failed": report["failed"][:10]}, ensure_ascii=False))
    return bool(report["failures"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/qa/lightning-growth-design-20261021")
    parser.add_argument("--proposal", type=Path, default=HERE / "proposal_v1.json")
    parser.add_argument("--scenarios", type=Path, default=HERE / "scenarios.json")
    args = parser.parse_args()
    raise SystemExit(execute(args.output.resolve(), args.proposal.resolve(), args.scenarios.resolve()))
