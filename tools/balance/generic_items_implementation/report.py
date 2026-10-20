"""Summarize native-core output; never substitutes for combat simulation."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "build/qa/generic-items-implementation-20261018/pressure"
raw = json.loads((OUT / "selected.json").read_text(encoding="utf-8-sig"))
lines = ["# 通用道具真实 core 样本", "", f"引擎：{raw['engine']['string']}；来源稳定：{raw['source_stable']}。", "", "两种选择偏好均运行当前 40 件合法池、同一种子与相同普通移动策略。旧偏好对照不是旧版本重放；随机消耗和实际掉落路径不同，样本不能估计真人胜率或单件的因果贡献。", "", "| 选择偏好 | 结果 | 路线秒 | 战斗秒 | 实际承伤 | 结束生命 | 通用／职业实取 |", "|---|---|---:|---:|---:|---:|---|"]
for row in raw["scenarios"]:
    if "error" in row:
        lines.append(f"| {row.get('item_policy','')} | {row['error']} | — | — | — | — | — |")
        continue
    generic = sum(x["scope"] == "generic" for x in row["artifacts"])
    lines.append(f"| {row['item_policy']} | {row['termination']} {row['clears']} 房 | {row['game_time']:.2f} | {row['combat_seconds']:.2f} | {row['taken']:.2f} | {row['health']:.2f} | {generic}／{len(row['artifacts']) - generic} |")
lines += ["", "以下资源数来自真实 core 效果事件按 seq 去重，开场／清房补满盾未计入战斗回复。零回复事件只说明该次没有实际恢复量，不能推出所有溢出浪费总量。", "", "| 偏好 | 实际失盾 | 实际失血 | 战斗实际回盾 | 道具实际回血 | 蓄能释放记录量 | 零回复事件 |", "|---|---:|---:|---:|---:|---:|---:|"]
for row in raw["scenarios"]:
    if "error" in row:
        continue
    totals = {key: sum(room.get("resources", {}).get(key, 0) for room in row["rooms"]) for key in ["shield_loss", "health_loss", "combat_shield_restore", "item_health_restore", "charge_release", "zero_restore_events"]}
    lines.append("| " + row["item_policy"] + " | " + " | ".join(f"{v:.2f}" for v in totals.values()) + " |")
lines.append("")
for row in raw["scenarios"]:
    if "error" not in row:
        lines += [f"{row['item_policy']} 实取轨迹：" + " → ".join(f"{choice['room']}房 {choice['after'][-1]}" for choice in row["choices"] if choice["kind"] == "treasure") + "。", ""]
lines += ["固定配置不限制强构筑输出跃升，不反向加厚现有敌人。当前只验证 45 房的集成与两种实际取得轨迹；46—60 房、正式 Boss、最终约 30 分钟和真人美术／体验验收仍属后续范围。", "", "复现命令见同目录 README.md，完整逐房、候选、持有与来源哈希见 selected.json。"]
(OUT / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
print(OUT / "report.md")
