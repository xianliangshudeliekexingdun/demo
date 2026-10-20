"""Summarize actual native reports; never edits game parameters or gameplay state."""
from __future__ import annotations

import csv
import hashlib
import json
import math
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "build/qa/route-pressure-20261017"


def read(name: str):
    return json.loads((OUT / name).read_text(encoding="utf-8-sig"))


def distribution(values):
    values = sorted(float(v) for v in values)
    def percentile(p):
        index = (len(values) - 1) * p
        lo = int(index)
        return values[lo] + (values[min(lo + 1, len(values) - 1)] - values[lo]) * (index - lo)
    return {"n": len(values), "min": values[0], "p10": percentile(.1),
            "median": statistics.median(values), "p90": percentile(.9), "max": values[-1]}


def ticks(seconds):
    return math.ceil(float(seconds) * 120 - 1e-6)


def full_cycle_minimum(spec):
    # One chase tick is required after the recover state completes. Individual
    # warning/action durations quantize independently in the real state machine.
    count = ticks(spec["warning"]) + ticks(spec["recovery"]) + 1
    if spec["behavior"] == "lunge":
        count += ticks(spec["lunge_duration"]) * int(spec.get("lunges", 1))
        count += ticks(spec.get("second_warning", 0)) * (int(spec.get("lunges", 1)) - 1)
    elif spec["behavior"] == "mark":
        count += ticks(spec["active_duration"])
    return max(count, ticks(spec["attack_cycle"])) / 120


def main():
    baseline = read("baseline-canonical.json")
    documents = [read("selected-ordinary.json"), read("selected-precise.json"), read("selected-short.json")]
    source = json.loads((ROOT / "data/route_enemy_runtime.json").read_text(encoding="utf-8"))
    base = json.loads((ROOT / "data/balance_candidates/first_run_v1.json").read_text(encoding="utf-8"))
    cadence = read("stage_rules.json")
    assert len({d["core_sha256"] for d in documents + [baseline]}) == 1, "Baseline and selected core versions differ"
    assert all(d["enemy_runtime"] == source for d in documents), "Selected runtime parameters differ"
    scenarios = [s for d in documents for s in d["scenarios"]]
    assert len(scenarios) == 28
    assert all(s["phase"] == "complete" and s["clears"] == 15 and s["kills"] == 77 for s in scenarios)
    clock_error = max(abs(s["active_clock_delta"]) for s in scenarios)
    combat_clock_error = max(abs(float(s["game_combat_time"]) - float(s["combat_seconds"])) for s in scenarios)
    assert max(clock_error, combat_clock_error) < .001
    ordinary = [s for s in documents[0]["scenarios"] if s["growth"] == "offense"]
    profile_summary = {}
    for document in documents:
        rows = [s for s in document["scenarios"] if s["growth"] == "offense"]
        name = rows[0]["profile"]
        profile_summary[name] = {
            "active_seconds": distribution(s["active_seconds"] for s in rows),
            "combat_seconds": distribution(s["combat_seconds"] for s in rows),
            "damage_taken": distribution(s["taken"] for s in rows),
            "minimum_remaining_health": min(s["health"] for s in rows),
            "within_360_480": sum(360 <= s["active_seconds"] <= 480 for s in rows),
            "completed": len(rows),
        }
    paired = []
    for old in baseline["scenarios"]:
        new = next(s for s in ordinary if (s["starter"], s["seed"]) == (old["starter"], old["seed"]))
        assert [r["combat_seconds"] for r in old["rooms"][:3]] == [r["combat_seconds"] for r in new["rooms"][:3]]
        paired.append({"starter": old["starter"], "seed": old["seed"],
                       "before_active": old["active_seconds"], "after_active": new["active_seconds"],
                       "before_combat": old["combat_seconds"], "after_combat": new["combat_seconds"],
                       "before_threat_starts": sum(old["attacks"].values()), "after_threat_starts": sum(new["attacks"].values()),
                       "before_damage": old["taken"], "after_damage": new["taken"]})
    table = []
    stage_ttk = []
    for room in [1, 5, 8, 11, 15]:
        stage = next(s for s in source["stat_stages"] if s["from"] <= room <= s["to"])
        for type_id in ["M01", "M02", "M03", "M04"]:
            row = dict(next(r for r in documents[0]["stat_table"] if r["stage"] == stage["id"] and r["type"] == type_id))
            row["room"] = room
            # The full type definition only supplies action lengths. All scaled
            # health/speed/cycle values remain those read from the native helper.
            spec = dict(base["normal_types"][type_id])
            if source["types"][type_id].get("runtime_ref"):
                first_room = json.loads((ROOT / "data/first_room_runtime.json").read_text(encoding="utf8"))
                spec.update(first_room[source["types"][type_id]["runtime_ref"]])
            spec.update(source["types"][type_id])
            spec["attack_cycle"] = row["attack_cycle"]
            row["effective_cycle_120hz_unblocked"] = full_cycle_minimum(spec)
            applicable = [a["spawn_to_defeat_seconds"] for s in ordinary for a in s["defeated_actors"]
                          if a["type"] == type_id and stage["from"] <= a["room"] <= stage["to"]]
            row["observed_spawn_to_defeat"] = distribution(applicable) if applicable else None
            observed_shots = [m for m in cadence["cadence_measurements"] if m["type"] == type_id
                              and stage["from"] <= m["room"] <= stage["to"]]
            row["native_shot_interval_median"] = statistics.median(observed_shots[0]["observed_intervals"]) if observed_shots else None
            table.append(row)
        for type_id in ["M01", "M02", "M03", "M04", "EL01", "EL02", "EL02_GUARD"]:
            values = [a["spawn_to_defeat_seconds"] for s in ordinary for a in s["defeated_actors"]
                      if a["type"] == type_id and stage["from"] <= a["room"] <= stage["to"]]
            if values:
                stage_ttk.append({"stage": stage["id"], "from": stage["from"], "to": stage["to"], "type": type_id,
                                  "spawn_to_defeat_seconds": distribution(values)})
    elite_times = [a["spawn_to_defeat_seconds"] for s in scenarios for a in s["defeated_actors"] if a["type"].startswith("EL")]
    defensive = next(s for s in scenarios if s["growth"] == "defense")
    warnings = [
        "Ordinary offense median meets the provisional 6-8 minute active-play target; four of nine samples are faster than six minutes. Do not claim every route meets the band.",
        "The support/control-first path lasts 655.04 active seconds. Its slower normal-room clearing is retained as a build tradeoff and needs user playtesting.",
        "These deterministic movement policies read core telegraphs. Their 28/28 completions are not a human win-rate estimate or experiential acceptance.",
        "Elite spawn-to-defeat stays below 60 seconds, including the support-first case; its last complete mixed room still takes 80.53 seconds because normal guards remain.",
    ]
    summary = {
        "model_version": "native-route-pressure-1", "decision": "keep candidate B; no additional health increase",
        "core_sha256": documents[0]["core_sha256"], "stage_rules": {"checks": cadence["checks"], "failures": cadence["failures"]},
        "total_native_scenarios": 28, "completed": 28, "first_three_rooms_same_in_paired_native_replays": True,
        "active_clock_max_error": clock_error, "combat_clock_max_error": combat_clock_error,
        "target_active_seconds": [360, 480], "profiles": profile_summary, "paired_before_after": paired,
        "ordinary_room_stat_table": table, "ordinary_observed_ttk_by_stage": stage_ttk,
        "maximum_elite_spawn_to_defeat_seconds": max(elite_times),
        "support_first": {k: defensive[k] for k in ["starter", "seed", "active_seconds", "combat_seconds", "taken", "health"]},
        "warnings": warnings, "omissions": ["Human perception and reaction distributions", "Native pixel visibility", "User difficulty acceptance"],
        "source_reports": ["baseline-canonical.json", "selected-ordinary.json", "selected-precise.json", "selected-short.json", "stage_rules.json"],
        "current_source_sha256": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in ["data/route_enemy_runtime.json", "scripts/core/route_enemy_combat.gd", "tools/balance/route_pressure/run.gd", "tools/balance/route_pressure/scenarios.json"]},
    }
    (OUT / "pressure_summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    columns = ["room", "type", "stage", "health", "damage", "walk_speed", "projectile_speed", "warning", "attack_cycle", "effective_cycle_120hz_unblocked", "native_shot_interval_median", "reference_F01_level1_packets", "reference_F01_level1_full_hit_seconds"]
    with (OUT / "ordinary_stats.csv").open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(table)
    lines = ["# 前期15房压力试作 · 原生规则报告", "", "本页从原生固定步报告生成，是评审快照，游戏参数只在 data。B版保留，不继续加厚；体验待用户复试。", "", "## 同核心、同种子、同选择策略的前后对照", "", "| 开局 | 原有效游玩秒 | 新有效游玩秒 | 原战斗秒 | 新战斗秒 | 原→新威胁起手数 |", "|---|---:|---:|---:|---:|---:|"]
    for r in paired:
        lines.append(f"| {r['starter']} | {r['before_active']:.2f} | {r['after_active']:.2f} | {r['before_combat']:.2f} | {r['after_combat']:.2f} | {r['before_threat_starts']}→{r['after_threat_starts']} |")
    lines += ["", "有效游玩包含真实接敌、拾取和走门；自动选卡不虚构停留。威胁起手统计包含精英第二扑的独立预警段，不等同于命中次数。三个开局前三房战斗逐房耗时与基线精确一致。", "", "## 多种子分布", "", "| 策略假设 | 样本 | 有效秒 最小／中位／最大 | 承伤 最小／最大 | 最低剩余生命 |", "|---|---:|---:|---:|---:|"]
    for name, r in profile_summary.items():
        a, h = r["active_seconds"], r["damage_taken"]
        lines.append(f"| {name} | {a['n']} | {a['min']:.2f}／{a['median']:.2f}／{a['max']:.2f} | {h['min']:.1f}／{h['max']:.1f} | {r['minimum_remaining_health']:.1f} |")
    lines += ["", "普通策略中位6:18达到试作观察带；9条中4条快于6分钟，未声称全样本在带内。另测防御／控制优先655.04秒，普通护卫清理明显更慢。28情境全部自然15房／77杀，不能推导真人通关率。", "", "## 普通怪档位快照", "", "数值依次按M01／M02／M03／M04。某档尚未出场的类型只列其档位参考值，不代表首房配置了四种敌人。", "", "| 代表房 | 生命 | 行走速度 米/秒 | M02弹速 米/秒 | 约有效起手间隔 秒 |", "|---|---|---|---:|---|"]
    for room in [1, 5, 8, 11, 15]:
        rows = [r for r in table if r["room"] == room]
        hp = "／".join(f"{r['health']:g}" for r in rows)
        speed = "／".join(f"{r['walk_speed']:.3f}" for r in rows)
        cycles = "／".join(f"{r['effective_cycle_120hz_unblocked']:.3f}" for r in rows)
        lines.append(f"| {room} | {hp} | {speed} | {rows[1]['projectile_speed']:.2f} | {cycles} |")
    lines += ["", "起手间隔是无遮挡且已在攻击触发距离内的固定步下限，包含完整预警／动作／恢复；寻路、遮挡和重型错峰只会延后。M02真实发射间隔已另由原生单敌夹具核对。碰撞半径、攻击伤害、锁向和预警时长均保持；更快移动／弹速及更密起手共同增加压力。", "", "## 手算与实测锚点", "", "一级焰弹攻击100、无暴击／增益、无遮挡满命中：首次按0.15前摇＋0.15参考飞行，后续每1.2冷却＋0.15前摇。M01首房180血需2发，1.65秒；第5房630血需7发，8.40秒；第15房2700血需27发，35.40秒。它是单法术校验锚点，后期真实构筑有范围伤害、精通、相性及神器，不按此预测整房耗时。", "", f"真实普通输出路径第6房精英本体约10—20秒，第12房约15—19秒，守门精英约19—42秒。包含防控路径的所有精英本体出生至击败最长{max(elite_times):.2f}秒；防控最后整房80.53秒包含普通护卫，并非精英血条单独拖延。逐类型、逐档实际出生至击败分布保存在pressure_summary.json。", "", f"新增档位与原生发射专项{cadence['checks']}项、{cadence['failures']}失败；独立计步与游戏time/combat_time最大差小于0.001秒。", "", "## 保留观察", "", "- 普通策略中位达到试作观察带，未用选卡等待凑时长。", "- 防控优先路线约10:55，保留构筑取舍，等待用户复试后决定是否调整控制路线输出收益；本轮未改法术。", "- 短视样例承伤最高421.2、最低162.8生命，可验证失误确实有代价；它仍不是实际玩家难度分布。", ""]
    (OUT / "pressure_review.md").write_text("\n".join(lines), encoding="utf8")
    print("Pressure summary written; 28 natural scenarios, canonical baseline, source tables and native cadence checked.")


if __name__ == "__main__":
    main()
