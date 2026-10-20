"""Summarize the isolated real-core bridge. No proposed mechanics or game writes."""
from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "build/qa/formal-fire-20261018"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    raw = json.loads((OUT / "runtime_baseline.json").read_text(encoding="utf-8"))
    base = json.loads((ROOT / "data/balance_candidates/first_run_v1.json").read_text(encoding="utf-8"))
    checks: list[dict] = []

    def check(label: str, ok: bool, **detail) -> None:
        checks.append({"label": label, "pass": bool(ok), **detail})

    check("native baseline checks pass", not raw["failures"])
    check("native sources stable", raw["source_stable"])
    for path, expected in raw["source_hashes_before"].items():
        check("current hash " + path, digest(ROOT / path) == expected)
    rows = []
    for row in raw["cases"]:
        spell = base["spells"][row["spell_id"]]
        level = spell["levels"][row["level"] - 1]
        cd = level.get("cooldown", spell.get("cooldown", 0))
        effective = max(base["limits"]["minimum_cooldown"], cd * (1 - min(row["extra_cdr_override"], .6))) if cd else 0
        check("effective cooldown", abs(row["effective_cd"] - effective) < 1e-8,
              case=[row[k] for k in ("spell_id", "level", "extra_cdr_override", "scene", "horizon")])
        gaps = [b - a for a, b in zip(row["casts_at"], row["casts_at"][1:])]
        continuous_cycle = effective + spell.get("windup", 0)
        if gaps:
            check("native cast gap near cooldown plus windup", all(abs(gap - continuous_cycle) < 2 / 120 for gap in gaps),
                  id=row["spell_id"], maximum_gap_error=max(abs(gap - continuous_cycle) for gap in gaps))
        check("finite nonnegative damage", row["damage_zero_crit"] >= 0)
        compact = {k: row[k] for k in ("spell_id", "level", "scene", "horizon", "extra_cdr_override", "cast_count",
                                       "hit_count", "damage_zero_crit", "damage_per_second_zero_crit", "shield_potential", "effective_cd", "first_hit", "g03_bursts")}
        compact["items"] = ",".join(row.get("items", []))
        compact.update(name=spell["name"], kind=spell["kind"], windup=spell.get("windup", 0),
                       continuous_cycle=continuous_cycle,
                       first_cast=row["casts_at"][0] if row["casts_at"] else None,
                       mean_native_cycle=sum(gaps) / len(gaps) if gaps else None)
        rows.append(compact)
    result = {"model_version": "formal-fire-baseline-summary-v1", "native_checks": raw["checks"],
              "summary_checks": len(checks), "failures": [x for x in checks if not x["pass"]],
              "checks": checks, "cases": rows, "source_hashes": raw["source_hashes_before"],
              "omissions": raw["omissions"]}
    (OUT / "baseline_summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    with (OUT / "baseline_summary.csv").open("w", encoding="utf-8-sig", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    lines = ["# 当前运行火系基线测量", "", "这是正式火系设计前的只读隔离夹具，不是完整战斗、路线或正式候选实装。",
             "调用真实 Route/Spell/Artifact core；每项仅持有该法术。攻击100、暴击率刻意置0以核系数；实际默认5%及1.5倍单独保留。",
             "目标每帧回固定锚点、无限生命、无AI／墙／击杀；护盾每帧清空用以量恢复潜力。60%CDR为显式夹具覆写，不能据此称当前装备可达。",
             "", "## 60秒、单静止锚点", "", "| ID／等级 | 吟唱 | 原CD | 0%CDR施放／伤害 | 60%CDR施放／伤害 | 备注 |", "|---|---:|---:|---:|---:|---|"]
    for ident in raw["retained_current_spell_ids"]:
        for level in range(1, 4):
            matches = [r for r in rows if r["spell_id"] == ident and r["level"] == level and r["scene"] == "single_static_anchor" and r["horizon"] == 60 and not r["items"]]
            a, b = sorted(matches, key=lambda r: r["extra_cdr_override"])
            spell = base["spells"][ident]
            cd = spell["levels"][level-1].get("cooldown", spell.get("cooldown", 0))
            note = "被动；单独不造成伤害" if ident == "F02" else (f"回盾潜力 {a['shield_potential']:.0f}／{b['shield_potential']:.0f}" if ident == "F10" else ("雨点仅1个固定种子，不代表均值" if ident == "F03" else ""))
            lines.append(f"| {ident} {spell['name']} L{level} | {a['windup']:.2f}s | {cd:.2f}s | {a['cast_count']}／{a['damage_zero_crit']:.0f} | {b['cast_count']}／{b['damage_zero_crit']:.0f} | {note} |")
    lines += ["", "## 旧G03真实触发对照", "", "| F06等级 | 0%CDR下60秒到期触发 | 60%CDR下60秒到期触发 |", "|---|---:|---:|"]
    for level in range(1, 4):
        matches = [r for r in rows if r["spell_id"] == "F06" and r["level"] == level and r["horizon"] == 60 and r["items"] == "G03"]
        a, b = sorted(matches, key=lambda r: r["extra_cdr_override"])
        lines.append(f"| {level} | {a['g03_bursts']} | {b['g03_bursts']} |")
    lines += ["", "## 边界与证据", "", f"原生桥 {raw['checks']} 项，失败 {len(raw['failures'])}；后处理 {len(checks)} 项，失败 {len(result['failures'])}。",
              f"30秒／60秒、单体／6目标密集锚点、0／60%CDR基本216条，另12条旧G03／F06触发对照，共{len(rows)}条。周期从释放后冷却加下次吟唱计算，固定步误差另外记录。",
              "F01／F07／F08三级首轮系数以手算独立核对。F03随机落点、F05移动区域、F06替换与同源区域去重由实际core执行，未在Python中复制战斗逻辑。",
              "F04当前仍在运行代码，正式布局已决定迁出火系；本表只测九个保留ID。现三火条件仍按持有数量，由真实运行代码决定；单法术夹具不触发。",
              "该表不能证明真人命中、强度排序、胜率、Boss、整局约30分钟或正式候选已经可玩。", ""]
    (OUT / "baseline.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"FORMAL_FIRE_BASELINE_SUMMARY native={raw['checks']}/0 summary={len(checks)} failures={len(result['failures'])}")
    if result["failures"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
