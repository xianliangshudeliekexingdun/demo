"""Check the completed source-bound native Route sample, without replaying it.

The runner already performed authoritative combat and reward decisions. These
checks verify its recorded ledger; they do not duplicate combat formulas.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "build/qa/formal-ice-implementation-20261018"


def run():
    report = json.loads((OUT / "pressure/final.json").read_text(encoding="utf-8"))
    checks = []

    def check(ok, label):
        checks.append({"ok": bool(ok), "label": label})

    check(report["source_stable"], "runner declared unchanged loaded sources")
    for path, digest in report["source_sha256"].items():
        check(hashlib.sha256((ROOT / path.removeprefix("res://")).read_bytes()).hexdigest() == digest, "current bytes still match " + path)
    check("res://scripts/core/route_ice_artifacts.gd" in report["source_sha256"], "ice profession execution dependency bound before run")
    check(len(report["scenarios"]) == 1, "one declared fixed policy and seed, no population claim")
    row = report["scenarios"][0]
    check(row["phase"] == "complete" and row["termination"] == "complete", "actual Route ended complete")
    check(row["clears"] == row["room"] == row["room_total"] == 45, "all45 rooms physically traversed")
    check(row["kills"] == 466, "all466 actual enemies killed")
    check(len(row["rooms"]) == 45 and all(r["cleared"] for r in row["rooms"]), "each recorded room genuinely cleared")
    check(row["dust"] == 0 and row["account_rewards"] is False, "no invented account dust or settlement")
    check(row["game_time"] >= row["combat_seconds"] > 0, "whole-route time includes noncombat travel")
    check(abs(row["active_clock_delta"]) < 0.001, "fixed-step active time agrees with Route time")
    check(row["health"] > 0 and row["health"] <= row["max_health"], "normal live player survived within actual maximum")
    spells = row["spells"]
    check(len(spells) == 8 and all(s["level"] == 3 for s in spells), "eight slots reached level3 through real choices")
    check(len({s["id"] for s in spells}) == len(spells), "final spell IDs unique")
    artifacts = row["artifacts"]
    check(len(artifacts) == len({a["id"] for a in artifacts}) == 9, "nine actual unique treasure claims")
    check(any(a["id"].startswith(("IB", "IP", "IG")) for a in artifacts), "at least one new ice career item naturally chosen")
    expected_rooms = [6, 12, 15, 21, 27, 30, 36, 39, 45]
    item_choices = [c for c in row["choices"] if c["kind"] == "treasure"]
    spell_choices = [c for c in row["choices"] if c["kind"] == "spell"]
    check([c["room"] for c in item_choices] == expected_rooms, "all nine configured boxes claimed")
    check(len(spell_choices) == 23, "exact23 successful growth choices to full eight-slot build")
    for choice in item_choices:
        acquired = set(choice["after"]) - set(choice["before"])
        check(len(acquired) == 1 and acquired <= {item["id"] for item in choice["offer"]}, f"room{choice['room']} treasure came from actual offer")
    for choice in spell_choices:
        before = {s["id"]: s["level"] for s in choice["before"]}
        after = {s["id"]: s["level"] for s in choice["after"]}
        changed = [s for s in after if after[s] != before.get(s, 0)]
        check(len(changed) == 1 and changed[0] in choice["offer"] and after[changed[0]] == before.get(changed[0], 0) + 1 and len(after) <= 8, f"room{choice['room']} spell was actual legal one-step growth")
    events = {key: sum(r["resources"].get(key, 0) for r in row["rooms"]) for key in ["frost", "window", "shatter", "shard"]}
    check(events["frost"] > 0 and events["window"] > 0, "real frost and ready-window events observed in combat")
    result = {"checks": len(checks), "failures": sum(not c["ok"] for c in checks), "details": checks,
              "metrics": {k: row[k] for k in ["starter", "seed", "health", "max_health", "game_time", "combat_seconds", "kills", "spells", "artifacts"]}, "ice_events": events,
              "scope": "Recorded ledger from one normal authoritative Route sample. Controlled rule/VFX inventory is unrelated. No player win-rate, natural acquisition guarantee, Boss or final session-duration conclusion."}
    (OUT / "natural_acceptance.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"ICE NATURAL ACCEPTANCE {result['checks']} checks / {result['failures']} failures")
    for check_row in checks:
        if not check_row["ok"]:
            print(check_row["label"])
    return int(result["failures"] > 0)


if __name__ == "__main__":
    raise SystemExit(run())
