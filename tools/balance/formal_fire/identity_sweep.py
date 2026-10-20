"""Requested fire-identity sensitivity after correcting the model, before tuning."""
from __future__ import annotations

from copy import deepcopy
import hashlib
from pathlib import Path
import shutil

from io_utils import DEFAULT_OUT, DEFAULT_PARAMETERS, ROOT, hashes, load, read, write
from model import MODEL_VERSION
from run import evaluate
from validation import validate


def main():
    initial = DEFAULT_OUT / "initial-candidate"
    snapshot_path = initial / "parameters.json"
    if not snapshot_path.exists():
        initial.mkdir(parents=True, exist_ok=True)
        snapshot_path.write_bytes(DEFAULT_PARAMETERS.read_bytes())
    inputs = load(snapshot_path)
    params, base, artifacts, generic = inputs
    legacy = read(DEFAULT_OUT / "run_manifest.json")
    paths = [p for p in legacy["source_hashes_before"] if p != "tools/balance/formal_fire/parameters.json"]
    paths.append(snapshot_path.relative_to(ROOT).as_posix())
    paths.append("tools/balance/formal_fire/identity_sweep.py")
    before = hashes(paths)
    native = read(DEFAULT_OUT / "runtime_baseline.json")
    if hashes(native["source_hashes_before"]) != native["source_hashes_before"]:
        raise AssertionError("Actual runtime sources changed")
    validation = validate(snapshot_path)
    if validation["failures"]:
        raise AssertionError(validation["failures"])
    write(initial / "model_validation.json", validation)
    retired = initial / "retired-pre-correction"
    retired.mkdir(parents=True, exist_ok=True)
    if not (retired / "STATUS.json").exists():
        for name in ("run_manifest.json", "scenario_results.json", "scenario_summary.csv", "report.md", "summary.json", "sensitivity.json", "sensitivity.md", "acceptance_checks.json"):
            source = DEFAULT_OUT / name
            if source.exists():
                shutil.copy2(source, retired / name)
    write(retired / "STATUS.json", {"status": "retired_pre_model_correction_not_current_evidence",
                                    "reason": "Fixed wait-for-readiness full windup, extra bomb current aim, and secondary bolt retarget-at-spawn; numeric parameters were unchanged",
                                    "not_valid_for_final_recommendation": True})
    rows = []
    scenes = {s["id"]: s for s in params["scenarios"]}
    builds = {"F01": ["F01"], "F11": ["F11"], "F01_F07": ["F01", "F07"], "F11_F07": ["F11", "F07"]}
    for burn in (.1, .2, .25, .3):
        for extra in (1, 2):
            override = deepcopy(params)
            override["burn"]["tick_coefficient"] = burn
            override["new_profession_items"]["G04"]["detonation_multiplier_add"] = extra
            for build, ids in builds.items():
                profiles = [{"id": "ordinary", "items": []}]
                if "F07" in ids:
                    profiles.append({"id": "P06_G04", "items": ["P06", "G04"]})
                for profile in profiles:
                    for scene in ("single_static", "spread_six"):
                        rows.append(evaluate((override, base, artifacts, generic), scenes[scene], profile, ids, 3, 60, params["seeds"],
                                             {"group": "identity_sensitivity", "build": build, "burn_tick_coefficient": burn, "G04_extra_multiplier": extra,
                                              "counterfactual_override": {"burn.tick_coefficient": burn, "G04.detonation_multiplier_add": extra}}))
    after = hashes(paths)
    if before != after:
        raise AssertionError("Sources changed during identity sensitivity")
    initial_rows = [r for r in rows if r["burn_tick_coefficient"] == .1 and r["G04_extra_multiplier"] == 1]
    write(initial / "corrected_model_results.json", {"status": "valid_initial_numeric_candidate_under_corrected_model", "model_version": MODEL_VERSION,
                                                     "parameter_sha256": hashlib.sha256(snapshot_path.read_bytes()).hexdigest(),
                                                     "scenarios": initial_rows, "scenario_count": len(initial_rows), "trajectories": len(initial_rows)*len(params["seeds"]),
                                                     "scope": "Requested identity subset only; not a rerun of retired 984 matrix", "source_hashes": before})
    write(initial / "scope.json", {"numeric_parameters": "initial tick .10, G04 +1; unchanged bytes",
                                    "current_model": MODEL_VERSION, "corrected_subset": "corrected_model_results.json",
                                    "retired_old_matrix": "retired-pre-correction", "full_main_matrix_rerun": False})
    comparisons = []
    def select(burn, extra, build, scene, profile):
        return next(r for r in rows if r["burn_tick_coefficient"] == burn and r["G04_extra_multiplier"] == extra and
                    r["build"] == build and r["scenario"] == scene and r["profile"] == profile)
    for burn in (.1, .2, .25, .3):
        for extra in (1, 2):
            main = select(burn, extra, "F01", "single_static", "ordinary")["total"]["mean"]/60
            spread = select(burn, extra, "F11", "spread_six", "ordinary")["total"]["mean"]/60
            row = {"burn_tick_coefficient": burn, "G04_extra_multiplier": extra, "F01_single_DPS": main,
                   "F11_spread_six_DPS": spread, "spread_to_primary_ratio": spread/main, "identity_target_within_0_8_to_1_2": .8 <= spread/main <= 1.2}
            for build, scene in (("F01_F07", "single_static"), ("F11_F07", "spread_six")):
                control = select(burn, extra, build, scene, "ordinary")
                combo = select(burn, extra, build, scene, "P06_G04")
                key = build+"_"+scene
                row[key+"_ordinary_DPS"] = control["total"]["mean"]/60
                row[key+"_P06_G04_DPS"] = combo["total"]["mean"]/60
                row[key+"_package_gain_fraction"] = combo["total"]["mean"]/control["total"]["mean"]-1
                row[key+"_package_detonation_DPS"] = combo["by_source"].get("detonation", {}).get("mean", 0)/60
            comparisons.append(row)
    write(DEFAULT_OUT / "identity_sensitivity.json", {"model_version": MODEL_VERSION, "status": "counterfactual_candidates_not_selected",
                                                      "seeds": params["seeds"], "scenario_count": len(rows), "trajectories": len(rows)*len(params["seeds"]),
                                                      "comparisons": comparisons, "scenarios": rows, "model_validation_checks": validation["checks"],
                                                      "invariant_failures": 0, "source_stable": before == after, "source_hashes": before,
                                                      "omissions": params["omissions"], "note": "P06+G04 gain is a two-item package, not an isolated gold-item gain"})
    lines = ["# 修正模型后的火系身份敏感性", "", f"模型：{MODEL_VERSION}；只比较候选，不改主参数或运行代码。96组×8固定seed＝768条轨迹。所有行L3／60秒／A100／默认5%暴击，单／双法术不触发三火，普通没有额外CDR；P06+G04只装备于合法F07搭配。",
             "", "| 每跳 | G04额外倍率 | F01单体DPS | F11疏散6体DPS | 比值／目标0.8～1.2 | F01+F07普通→两职业 | F11+F07疏散普通→两职业 |", "|---|---:|---:|---:|---:|---:|---:|"]
    for r in comparisons:
        a, b = "F01_F07_single_static", "F11_F07_spread_six"
        lines.append(f"| {r['burn_tick_coefficient']:.2f} | +{r['G04_extra_multiplier']} | {r['F01_single_DPS']:.2f} | {r['F11_spread_six_DPS']:.2f} | {r['spread_to_primary_ratio']:.3f} {'达标' if r['identity_target_within_0_8_to_1_2'] else '低于'} | {r[a+'_ordinary_DPS']:.2f}→{r[a+'_P06_G04_DPS']:.2f} ({r[a+'_package_gain_fraction']:+.1%}) | {r[b+'_ordinary_DPS']:.2f}→{r[b+'_P06_G04_DPS']:.2f} ({r[b+'_package_gain_fraction']:+.1%}) |")
    lines += ["", "单体与疏散的比较是此次指定的角色身份判据，不是要求各场景DPS相同。职业列含P06与G04两件，不能误称G04单件增益；同每跳下+1与+2的差才隔离额外倍率变化，复燃规则相同。",
              "", "初版.10/+1在正确模型下的12组／96轨迹与参数原字节保存在initial-candidate。修正前984矩阵留于其retired-pre-correction并标为失效证据；正式推荐选定后再重跑一次主矩阵。",
              "", "每跳提高会同时增强全部点燃来源、燃烧覆盖与引爆，不是F11独享补强。此模型仍无真实AI、控场、过量伤害、自然抽取或生存。", ""]
    (DEFAULT_OUT / "identity_sensitivity.md").write_text("\n".join(lines), encoding="utf-8")
    if hashes(legacy["source_hashes_before"]) != legacy["source_hashes_before"]:
        write(DEFAULT_OUT / "EVIDENCE_STATUS.json", {"status": "main_matrix_pending_selected_parameters_after_model_correction",
                                                     "valid_current_subset": "identity_sensitivity.json", "initial_candidate": "initial-candidate/corrected_model_results.json",
                                                     "retired_matrix": "initial-candidate/retired-pre-correction", "model_version": MODEL_VERSION})
    print(f"FORMAL_FIRE_IDENTITY_SWEEP scenarios={len(rows)} trajectories={len(rows)*len(params['seeds'])} checks={validation['checks']}/0 source_stable=True")


if __name__ == "__main__":
    main()
