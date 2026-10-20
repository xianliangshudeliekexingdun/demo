"""Small explicitly requested counterfactuals; main accepted inputs stay frozen."""
from __future__ import annotations

from copy import deepcopy
import hashlib
from pathlib import Path

from io_utils import DEFAULT_OUT, hashes, load, read, write
from run import evaluate


def main():
    inputs = load()
    params, base, artifacts, generic = inputs
    manifest = read(DEFAULT_OUT / "run_manifest.json")
    before = hashes(manifest["source_hashes_before"])
    if before != manifest["source_hashes_before"]:
        raise AssertionError("Main parameters or source changed before sensitivity")
    profile = deepcopy(next(p for p in params["profiles"] if p["id"] == "ordinary"))
    scenes = {s["id"]: s for s in params["scenarios"]}
    rows = []
    for cd in (4.0, 5.0, 6.0):
        override = deepcopy(params)
        override["new_spells"]["F11"]["cooldown"] = cd
        for scene in ("single_static", "spread_six"):
            row = evaluate((override, base, artifacts, generic), scenes[scene], profile, ["F11"], 3, 60, params["seeds"],
                           {"group": "F11_cd", "build": "F11", "counterfactual_override": {"new_spells.F11.cooldown": cd}})
            rows.append(row)
    for coefficient in (.08, .1, .12):
        override = deepcopy(params)
        override["burn"]["tick_coefficient"] = coefficient
        rows.append(evaluate((override, base, artifacts, generic), scenes["single_static"], profile, ["F01", "F07"], 3, 60, params["seeds"],
                             {"group": "burn_tick", "build": "F01_F07", "counterfactual_override": {"burn.tick_coefficient": coefficient}}))
    after = hashes(manifest["source_hashes_before"])
    if before != after:
        raise AssertionError("Bound sources changed during sensitivity")
    result = {"status": "counterfactual_sensitivity_only_main_recommendation_unchanged", "model_version": params["model_version"],
              "scenarios": rows, "scenario_count": len(rows), "trajectories": len(rows)*len(params["seeds"]), "seeds": params["seeds"],
              "main_sources_unchanged": True, "invariant_failures": 0, "source_hashes": before,
              "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "scope": "Only nine requested counterfactual groups, same eight fixed seeds. No parameter search, recommendation change, combat difficulty or acquisition inference."}
    write(DEFAULT_OUT / "sensitivity.json", result)
    lines = ["# 小范围参数敏感性", "", "独立deepcopy覆盖；主parameters.json、984场景结果和推荐均保持。所有行L3／60秒／无额外CDR／无道具／A100／默认5%暴击，8固定seed。不是输出平衡验收。",
             "", "| 变化 | 场景 | 本体DPS | 燃烧DPS | 引爆DPS | 总DPS均值 | 8seed范围 |", "|---|---|---:|---:|---:|---:|---:|"]
    for row in rows:
        label = ", ".join(f"{k}={v}" for k, v in row["counterfactual_override"].items())
        values = [row["by_source"].get(s, {}).get("mean", 0)/60 for s in ("direct", "burn", "detonation")]
        lines.append(f"| {label} | {row['scenario']} | "+" | ".join(f"{v:.2f}" for v in values)+f" | {row['total']['mean']/60:.2f} | {row['total']['minimum']/60:.2f}～{row['total']['maximum']/60:.2f} |")
    lines += ["", "F11缩CD同时增加本体次数与共享燃烧覆盖；没有把同一目标每秒燃烧率叠高。调整共用每跳系数会同时改变所有点燃来源与引爆库存，不能只当F11的专属补强。此小表仅显示方向与幅度，由设计方决定是否维持CD6秒，不自动采用最强行。",
              "", "注意single_static为1目标，spread_six为6个无限HP目标；不转火／不计补刀与过量伤害。固定seed范围只描述模拟中的暴击差异，不是真人区间。", ""]
    (DEFAULT_OUT / "sensitivity.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"FORMAL_FIRE_SENSITIVITY scenarios={len(rows)} trajectories={len(rows)*len(params['seeds'])} invariant_failures=0 main_sources_unchanged=True")


if __name__ == "__main__":
    main()
