"""Compare native-core JSON outputs; contains no copied combat formula."""
import argparse
import json
from pathlib import Path
from statistics import mean


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def key(row):
    return (tuple(row["ids"]), row["level"], row["seed"], row["pattern"],
            json.dumps(row["conditions"], sort_keys=True))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--qa", type=Path,
                        default=Path("build/qa/spell-growth-implementation-20261020"))
    args = parser.parse_args()
    names = ["before", "old-gear", "current", "low", "high"]
    reports = {name: read(args.qa / f"model-{name}.json") for name in names}
    tables = {name: {key(r): r for r in d["rows"]} for name, d in reports.items()}
    assert all(not d["failures"] for d in reports.values()), "native known-case/bounded check failed"
    assert all(set(t) == set(tables["current"]) for t in tables.values()), "scenario mismatch"
    spells, regressions, builds, sensitivity = [], [], [], []
    for k, row in tables["current"].items():
        old = tables["before"][k]
        if "build" not in row and row["level"] > 1:
            record = {"spell": row["ids"][0], "level": row["level"], "pattern": row["pattern"],
                      "old_dps": old["dps"], "new_dps": row["dps"],
                      "damage_ratio": row["dps"] / old["dps"] if old["dps"] else None,
                      "old_shield": old["shield_recovered"], "new_shield": row["shield_recovered"],
                      "old_armor_uptime": old["armor_uptime"], "new_armor_uptime": row["armor_uptime"]}
            spells.append(record)
            if old["dps"] > 0 and row["dps"] < old["dps"] - 1e-6:
                regressions.append(record)
    for build in reports["current"]["parameters"]["builds"]:
        for level in reports["current"]["parameters"]["build_levels"]:
            for pattern in reports["current"]["parameters"]["patterns"]:
                subset = [k for k, row in tables["current"].items()
                          if row.get("build") == build and row["level"] == level
                          and row["pattern"] == pattern and not row["conditions"]]
                stats = {}
                for name in ["before", "current", "old-gear"]:
                    values = [tables[name][k]["dps"] for k in subset]
                    stats[name] = {"mean": mean(values), "min": min(values), "max": max(values)}
                stats["current_vs_before"] = stats["current"]["mean"] / stats["before"]["mean"]
                stats["current_vs_old_gear"] = stats["current"]["mean"] / stats["old-gear"]["mean"]
                builds.append({"build": build, "level": level, "pattern": pattern, "dps": stats})
        for k, row in tables["current"].items():
            if row.get("build") == build and row["level"] == 3 and row["pattern"] == "group" and not row["conditions"]:
                sensitivity.append({"build": build, "seed": row["seed"],
                                    "primary_coefficients_90_dps": tables["low"][k]["dps"],
                                    "primary_coefficients_100_dps": row["dps"],
                                    "primary_coefficients_110_dps": tables["high"][k]["dps"]})
    result = {"scope": reports["current"]["scope"], "scenarios_per_run": len(tables["current"]),
              "runs": {name: {"checks": d["checks"], "failures": d["failures"]} for name, d in reports.items()},
              "single_spells": spells, "single_damage_regressions": regressions,
              "builds": builds, "sensitivity": sensitivity,
              "limits": ["32 forced old profession items are a reference fixture, never a natural inventory claim",
                         "three seeds report their observed range, not a confidence interval",
                         "coefficient sweeps do not scale burns, shield, frost, sizes, or new trait coefficients",
                         "stationary immortal enemies exclude movement AI, survival, natural rewards and full-route timing"]}
    (args.qa / "model-comparison.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = ["# 原生定点模型对照", "", "攻击100，普通暴击率0；固定单敌／三敌、三种明确八槽构筑。各行取3个种子的均值，不代表自然通关。旧全职业列强制持32件旧职业，仅作参照。", "",
             "| 构筑 | 等级 | 目标 | 旧无职业DPS | 新无职业DPS | 新／旧 | 旧全职业DPS |", "|---|---|---|---|---|---|---|"]
    for row in builds:
        d = row["dps"]
        lines.append(f"| {row['build']} | {row['level']} | {row['pattern']} | {d['before']['mean']:.1f} | {d['current']['mean']:.1f} | {d['current_vs_before']:.2f}× | {d['old-gear']['mean']:.1f} |")
    lines += ["", f"单术二／三级普通伤害回退场景：{len(regressions)}；回盾与防御单独核查。每版162场景，另执行主伤系数±10%敏感性。", "",
              "此模型不预测生存率、自然升级选择、全局用时或实机性能。"]
    (args.qa / "model-comparison.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"scenarios_per_run": len(tables["current"]), "single_damage_regressions": len(regressions),
                      "build_level3": [r for r in builds if r["level"] == 3]}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
