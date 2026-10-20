"""Reproducible acceptance of the native core route, not a combat simulation."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
QA = ROOT / "build/qa/formal-fire-implementation-20261018"

def run() -> None:
    data = json.loads((QA / "pressure/final.json").read_text(encoding="utf-8"))
    checks = []
    def check(ok, label):
        checks.append({"label": label, "passed": bool(ok)})
    check(data["source_stable"], "native runner stayed on one source revision")
    check(all(hashlib.sha256((ROOT / k.removeprefix("res://")).read_bytes()).hexdigest() == v for k, v in data["source_sha256"].items()), "bound core/tool/data source hashes still match")
    check(len(data["scenarios"]) == 1, "one declared seed and policy; no win-rate inference")
    row = data["scenarios"][0]
    check(row["phase"] == "complete" and row["termination"] == "complete", "actual completion")
    check(row["room"] == 45 and row["clears"] == 45 and row["kills"] == 466, "45 rooms and all 466 actual enemies cleared")
    check([r["room"] for r in row["rooms"]] == list(range(1,46)) and all(r["cleared"] for r in row["rooms"]), "every room appears once in real ledger")
    treasures = [c for c in row["choices"] if c["kind"] == "treasure"]
    growth = [c for c in row["choices"] if c["kind"] == "spell"]
    check(len(treasures) == 9 and len(row["artifacts"]) == 9, "nine genuine chest selections")
    check(all(len(c["after"]) == len(c["before"]) + 1 and c["after"][-1] in [x["id"] for x in c["offer"]] for c in treasures), "each chest grants exactly one genuinely offered item")
    ids = [x["id"] for x in row["artifacts"]]
    check(len(ids) == len(set(ids)), "no duplicate held treasures")
    check(len(growth) == 23, "23 real growth selections; no artificial inventory fill")
    check(len(row["spells"]) == 8 and all(x["level"] == 3 for x in row["spells"]), "eight real slots reached level three")
    check("F11" in [x["id"] for x in row["spells"]] and "F07" in [x["id"] for x in row["spells"]], "new brand and detonation acquired from natural offers")
    check("F04" not in [x["id"] for x in row["spells"]] and not {"B04","P01","G02"}.intersection(ids), "normal pool excludes archived spirit entries")
    check(row["dust"] == 0 and not row["account_rewards"], "route has no account dust or reward settlement")
    check(abs(row["active_clock_delta"]) < 0.00001, "actual route clock agrees with native fixed steps")
    check(row["health"] > 0 and row["combat_seconds"] < row["active_seconds"], "surviving sample includes real noncombat travel")
    totals = {key: sum(room["resources"][key] for room in row["rooms"]) for key in ("ignition","spread","detonation","reignited","burn_damage","detonation_damage")}
    check(totals["burn_damage"] > 0 and totals["detonation_damage"] > 0 and totals["spread"] > 0, "actual new status damage and one-step spread observed")
    check("P06" in ids and any("P06" in r["treasure_start"] for r in row["rooms"]), "naturally acquired P06 carried into later real combat")
    result = {"checks": len(checks), "failures": sum(not x["passed"] for x in checks), "details": checks,
              "source_sha256": hashlib.sha256((QA / "pressure/final.json").read_bytes()).hexdigest(),
              "fire_totals": totals, "scope": "Acceptance of one native real core route. G04 arrives at final chest; zero natural re-ignitions is reported honestly and controlled VFX/rule tests cover it separately. No human win-rate, final balance, Boss or thirty-minute conclusion."}
    (QA / "natural_acceptance.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"NATIVE NATURAL ACCEPTANCE: {len(checks)} checks, {result['failures']} failures")
    if result["failures"]:
        raise SystemExit(1)
if __name__ == "__main__":
    run()
