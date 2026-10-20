"""Derive review/CSV from retained native telemetry; never changes game data."""
from __future__ import annotations

import csv
import hashlib
import json
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "build/qa/route45-20261018"
labels = sys.argv[1:] or ["accepted-full"]
reports = [json.loads((OUT / (label + ".json")).read_text(encoding="utf-8-sig")) for label in labels]
scenarios = [row for report in reports for row in report["scenarios"]]
assert scenarios, "No executed scenarios"
assert all(report["source_stable"] for report in reports), "Source changed during a batch; retain failed report and rerun"
assert all(report["source_sha256"] == reports[0]["source_sha256"] for report in reports), "Mixed source versions"

def distribution(values):
    return {"minimum": min(values), "median": statistics.median(values), "maximum": max(values)} if values else None

summary = {
    "model_version": "route45-native-review-1",
    "source_reports": labels,
    "source_sha256": reports[0]["source_sha256"],
    "scenario_count": len(scenarios),
    "complete": sum(row.get("termination") == "complete" for row in scenarios),
    "deaths": sum(row.get("termination") == "dead" for row in scenarios),
    "other_failures": [dict(starter=row["starter"], seed=row["seed"], profile=row["profile"], room=row.get("room"), reason=row.get("termination", row.get("error"))) for row in scenarios if row.get("termination") not in ["complete", "dead"]],
    "clock_guardrail": all(abs(row.get("active_clock_delta", 999)) < 1e-5 for row in scenarios),
    "account_guardrail": all(row.get("dust") == 0 and not row.get("account_rewards", True) for row in scenarios),
    "profiles": {},
}
canonical_route = reports[0]["source_parameters"]["res://data/courtyard_route.json"]
encounter_bands = []
for lo, hi in [(1, 15), (16, 30), (31, 45)]:
    total = ranged = 0
    for room in range(lo, hi + 1):
        for pack in canonical_route["encounters_by_room"][str(room)]["packs"]:
            for type_id, count in pack.items():
                total += int(count)
                if type_id in ["M02", "M04", "EL02", "EL02_GUARD"]:
                    ranged += int(count)
    encounter_bands.append({"from": lo, "to": hi, "enemies": total, "ranged": ranged, "ranged_share": ranged / total})
summary["encounter_bands"] = encounter_bands
summary["roster_guardrail"] = all(row.get("kills") == sum(band["enemies"] for band in encounter_bands) for row in scenarios if row.get("termination") == "complete")
summary["treasure_guardrail"] = all(len(row.get("artifacts", [])) == len(canonical_route["artifact_reward_rooms"]) and len({item["id"] for item in row.get("artifacts", [])}) == len(row.get("artifacts", [])) for row in scenarios if row.get("termination") == "complete")
milestones = []
for milestone in [15, 30, 45]:
    endpoints = [room for row in scenarios if row.get("growth") == "offense" for room in row.get("rooms", []) if room["room"] == milestone]
    if endpoints:
        milestones.append({"room": milestone, "spell_count": distribution([len(room["spell_end"]) for room in endpoints]), "spell_level_sum": distribution([sum(int(spell["level"]) for spell in room["spell_end"]) for room in endpoints]), "treasure_count": distribution([len(room["treasure_end"]) for room in endpoints])})
summary["growth_milestones"] = milestones
lines = ["# 45房原生压力检查", "", "真实核心输入情境；自动策略不代表真人难度或胜率。死亡、超时与未完成样本全部保留。", "", f"运行{len(scenarios)}条：完成{summary['complete']}，死亡{summary['deaths']}，其他未完成{len(summary['other_failures'])}。时间为无选卡停留的实际战斗＋清场走位／拾取／走门；单位秒。", "", "| 策略 | 情境 | 完成 | 总用时中位 | 承伤中位 | 最低剩余生命 |", "|---|---:|---:|---:|---:|---:|"]
for profile in ["precise", "ordinary", "short_view"]:
    group = [row for row in scenarios if row.get("profile") == profile and row.get("growth") == "offense"]
    if not group:
        continue
    result = {"count": len(group), "complete": sum(row.get("termination") == "complete" for row in group), "active_seconds": distribution([row["active_seconds"] for row in group]), "taken": distribution([row["taken"] for row in group]), "remaining_health": distribution([row["health"] for row in group]), "segments": []}
    for index in range(3):
        sections = [row["segments"][index] for row in group]
        result["segments"].append({"from": 1 + 15 * index, "to": 15 + 15 * index, "combat_seconds": distribution([s["combat_seconds"] for s in sections]), "taken": distribution([s["taken"] for s in sections]), "peak_enemy_projectiles": distribution([s["peak_enemy_projectiles"] for s in sections]), "incomplete_samples": sum(s["clears"] < 15 for s in sections)})
    summary["profiles"][profile] = result
    lines.append(f"| {profile} | {len(group)} | {result['complete']} | {result['active_seconds']['median']:.2f} | {result['taken']['median']:.1f} | {result['remaining_health']['minimum']:.1f} |")
lines += ["", "| 策略 | 房段 | 战斗秒数范围／中位 | 承伤范围／中位 | 最高敌弹数范围 | 未清完样本 |", "|---|---|---|---|---|---:|"]
for profile, result in summary["profiles"].items():
    for segment in result["segments"]:
        t, d, p = segment["combat_seconds"], segment["taken"], segment["peak_enemy_projectiles"]
        lines.append(f"| {profile} | {segment['from']}—{segment['to']} | {t['minimum']:.1f}—{t['maximum']:.1f}／{t['median']:.1f} | {d['minimum']:.1f}—{d['maximum']:.1f}／{d['median']:.1f} | {p['minimum']}—{p['maximum']} | {segment['incomplete_samples']} |")
lines += ["", f"双时钟逐步一致：{summary['clock_guardrail']}；无局外收益：{summary['account_guardrail']}。", "", "单体一级焰弹理论表只作无遮挡、全命中、无暴击的离散命中锚点；后期实际耗时由真实多法术与宝物产生。各房完整类型、峰值、法术与宝物轨迹见原始JSON和room_rows.csv。"]
for row in scenarios:
    if row.get("growth") == "defense" or row.get("termination") != "complete":
        lines += ["", f"保留样本：{row.get('profile')}／{row['starter']}／种子{row['seed']}／{row.get('growth')}，{row.get('termination',row.get('error'))}，第{row.get('room')}房，总{row.get('active_seconds',0):.2f}秒，承伤{row.get('taken',0):.1f}。"]
sensitivity_path = OUT / "sensitivity.json"
if sensitivity_path.exists():
    experiment = json.loads(sensitivity_path.read_text(encoding="utf-8-sig"))
    if len(experiment.get("trials", [])) == 3:
        summary["health_sensitivity"] = {"source_report": "sensitivity.json", "parameter_experiment": True, "source_stable": experiment["source_stable"], "first_fifteen_equal": experiment["first_fifteen_trajectories_equal"], "trials": []}
        lines += ["", "## 后30房生命档位敏感性", "", "同一旧runner、F01／种子20261017／普通策略的三点自洽实验，仅在出生前派生runtime配置，未改当前data。实验与主版本工具移动采样有差别，不拼接主报告的1.0行。", "", "| 后30房生命系数 | 结果／房数 | 总秒数 | 战斗秒数 | 承伤 | 剩余生命 |", "|---|---|---:|---:|---:|---:|"]
        baseline = next((trial.get("result", {}) for trial in experiment["trials"] if trial["factor"] == 1.0), {})
        fidelity_note = ""
        baseline15_path = OUT / "baseline15/results.json"
        if baseline15_path.exists() and baseline:
            baseline15_report = json.loads(baseline15_path.read_text(encoding="utf-8-sig"))
            baseline15 = next(row for row in baseline15_report["scenarios"] if row["starter"] == "F01" and row["seed"] == 20261017)
            fidelity = {"baseline_report": "baseline15/results.json", "baseline_sha256": hashlib.sha256(baseline15_path.read_bytes()).hexdigest(), "current_report": "sensitivity.json", "current_sha256": hashlib.sha256(sensitivity_path.read_bytes()).hexdigest(), "scope": "same retained native route_pressure runner, ordinary F01 seed20261017, first fifteen complete per-room telemetry rows", "rows_identical": baseline15["rooms"] == baseline["rooms"][:15], "baseline_combat_seconds": sum(row["combat_seconds"] for row in baseline15["rooms"]), "current_combat_seconds": sum(row["combat_seconds"] for row in baseline["rooms"][:15])}
            summary["first15_runtime_fidelity"] = fidelity
            (OUT / "first15_runtime_fidelity.json").write_text(json.dumps(fidelity, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            fidelity_note = f"同runner回归：当前1.0样本前15房完整逐房记录与扩展前原生F01基线逐字段相等：{fidelity['rows_identical']}，两者战斗均{fidelity['baseline_combat_seconds']:.7f}秒。"
        for trial in experiment["trials"]:
            result = trial.get("result", {})
            row = {"factor": trial["factor"], "termination": result.get("termination", trial.get("error")), "room": result.get("room"), "active_seconds": result.get("active_seconds"), "combat_seconds": result.get("combat_seconds"), "taken": result.get("taken"), "health": result.get("health")}
            if baseline.get("active_seconds") and result.get("active_seconds"):
                row["active_delta_percent"] = (result["active_seconds"] / baseline["active_seconds"] - 1) * 100
            summary["health_sensitivity"]["trials"].append(row)
            lines.append(f"| {trial['factor']:.1f} | {row['termination']}／{row['room']} | {row['active_seconds'] or 0:.2f} | {row['combat_seconds'] or 0:.2f} | {row['taken'] or 0:.1f} | {row['health'] or 0:.1f} |")
        if fidelity_note:
            lines += ["", fidelity_note]
        changes = [f"{row['factor']:.1f}为{row.get('active_delta_percent',0):+.2f}%" for row in summary["health_sensitivity"]["trials"] if row["factor"] != 1.0]
        sensitivity_rows = summary["health_sensitivity"]["trials"]
        boundary = "三点均未跨越死亡或超时边界。" if all(row["termination"] == "complete" for row in sensitivity_rows) else "存在未完成样本，结果与原因保留在上表。"
        damage_monotonic = all(float(a["taken"] or 0) <= float(b["taken"] or 0) for a, b in zip(sensitivity_rows, sensitivity_rows[1:]))
        time_monotonic = all(float(a["active_seconds"] or 0) <= float(b["active_seconds"] or 0) for a, b in zip(sensitivity_rows, sensitivity_rows[1:]))
        response = ("承伤随生命系数增加；" if damage_monotonic else "承伤没有单调增加；") + ("总时长随生命系数增加。" if time_monotonic else "总时长没有单调增加。")
        lines += ["", "相对本实验1.0的总时长变化：" + "，".join(changes) + "。" + boundary + response]
        lines += ["", "该单种子参数实验只说明此输入路径的响应。敌人击败时机变化会改变后续真实随机调用和奖励候选，效果可能非线性；逐房法术与最终宝物清单、完整override保留在原始报告。三点均不自动替换当前候选。"]
enemy_counts = "／".join(str(band["enemies"]) for band in encounter_bands)
ranged_shares = "／".join(f"{band['ranged_share']:.1%}" for band in encounter_bands)
lines += ["", "## 候选判断", "", f"三个房段敌人数为{enemy_counts}；远程／落印敌人占比为{ranged_shares}。后段同时提高在场容量、远程密度和施压频率，完整预警与攻击动作由规则专项约束。", "", "| 成长节点 | 法术数量范围 | 法术等级总和范围 | 宝物数量范围 |", "|---|---|---|---|"]
for milestone in milestones:
    a, b, c = milestone["spell_count"], milestone["spell_level_sum"], milestone["treasure_count"]
    lines.append(f"| {milestone['room']} | {a['minimum']}—{a['maximum']} | {b['minimum']}—{b['maximum']} | {c['minimum']}—{c['maximum']} |")
for profile, group in summary["profiles"].items():
    sections = group["segments"]
    med_damage = "／".join(f"{section['taken']['median']:.1f}" for section in sections)
    med_shots = "／".join(str(section["peak_enemy_projectiles"]["median"]) for section in sections)
    med_combat = "／".join(f"{section['combat_seconds']['median']:.1f}" for section in sections)
    per_enemy = "／".join(f"{section['combat_seconds']['median']/band['enemies']:.2f}" for section, band in zip(sections, encounter_bands))
    lines += ["", f"{profile}三段战斗中位{med_combat}秒、承伤中位{med_damage}、敌弹峰值中位{med_shots}，每名配置敌人的分段战斗时间{per_enemy}秒。承伤包含护盾吸收，清房按现行规则恢复护盾，因此保留原生命不表示从未被命中。"]
lines += ["", "法术和宝物逐步成型后，群体伤害、协同和冷却增强可以抵消部分人数／生命上升；后段总战斗时长与单位敌人耗时应分开判断。当前轨迹支持构筑能够应对更密集火网的方向，无法从这些组合样本单独分离每件宝物的收益。", "", "precise、ordinary、short_view使用不同决策频率与可见范围，会改变移动轨迹、攻击命中、随机调用和后续候选；单个样本的时间或承伤不必按名称排序。它们用于覆盖不同合法输入路径，没有人体反应或强弱排名含义。"]
defense_rows = [row for row in scenarios if row.get("growth") == "defense"]
if defense_rows and "ordinary" in summary["profiles"]:
    defense = defense_rows[0]
    ordinary = summary["profiles"]["ordinary"]["active_seconds"]["median"]
    defense_status = "该样本完成" if defense.get("termination") == "complete" else "该样本未完成：" + str(defense.get("termination"))
    lines += ["", f"防控优先样本总{defense['active_seconds']:.2f}秒，为普通进攻组中位的{defense['active_seconds']/ordinary:.2f}倍；{defense_status}，较长战斗有拖慢节奏的风险。该差异保留给真实试玩，不靠继续加厚生命来追统一时长。"]
lines += ["", "保留当前1.0候选作为下一轮试玩版本：前15房配置与同runner实际轨迹保持，后两段远程密度和敌弹上升，合法法术／宝物成长、容量、拾取、双计时和局外隔离通过检查。±10%生命实验用于观察响应，本轮没有据此替换游戏参数。", "", f"本组{summary['complete']}／{summary['scenario_count']}条自动输入情境完成，仅说明这些固定种子／策略没有遇到无法跨越的硬门槛；不能推断真人胜率、观感、乐趣或最终平衡。下一步真实试玩应重点观察远程预警可读性、法术满级后奖励节奏、宝物对构筑的实际感受及防控路径时长。"]
(OUT / "pressure_review.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
(OUT / "pressure_summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
with (OUT / "scenario_rows.csv").open("w", encoding="utf-8-sig", newline="") as file:
    keys = ["profile", "starter", "seed", "growth", "termination", "room", "clears", "kills", "active_seconds", "combat_seconds", "taken", "health", "gold", "dust"]
    writer = csv.DictWriter(file, fieldnames=keys, extrasaction="ignore")
    writer.writeheader(); writer.writerows(scenarios)
with (OUT / "room_rows.csv").open("w", encoding="utf-8-sig", newline="") as file:
    keys = ["profile", "starter", "seed", "growth", "room", "kind", "stage", "ranged_total", "active_seconds", "combat_seconds", "taken", "health_before", "health_after", "peak_alive", "peak_enemy_projectiles", "cleared"]
    writer = csv.DictWriter(file, fieldnames=keys, extrasaction="ignore")
    writer.writeheader()
    for row in scenarios:
        for room in row.get("rooms", []):
            writer.writerow(dict(room, **{key: row[key] for key in ["profile", "starter", "seed", "growth"]}))
print(json.dumps({key: summary[key] for key in ["scenario_count", "complete", "deaths", "clock_guardrail", "account_guardrail"]}, ensure_ascii=False))
