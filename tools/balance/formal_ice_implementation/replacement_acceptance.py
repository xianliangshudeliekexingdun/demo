"""Read recorded native results; no combat/reward model or source mutation."""
import hashlib
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
QA = ROOT / "build/qa/spell-replacement-20261018"
checks = []


def read(relative):
    return json.loads((QA / relative).read_text(encoding="utf-8-sig"))


def check(ok, label):
    checks.append({"ok": bool(ok), "label": label})


def main():
    visual = read("visual/results.json")
    for file in ["rules.json", "main/main_suite_results.json", "ice/rules.json", "fire/rules.json", "cards/results.json", "route45-rules.json", "visual/results.json"]:
        result = read(file)
        check(result["failures"] == 0, "recorded zero failures: " + file)
        if "source_stable" in result:
            check(result["source_stable"], "native run declared stable source: " + file)
    check(read("main_source_check.json")["source_stable"], "main explicit dependency closure unchanged")
    summary = visual["final_summary"]
    check(summary["phase"] == "complete" and summary["clear_count"] == 45, "actual Main completes all45 rooms")
    check(summary["kills"] == 466 and len(summary["artifacts"]) == 9, "actual466 defeats and9 distinct treasure claims")
    pickups = visual["pickup_records"]
    kinds = Counter(item["kind"] for item in pickups)
    check(len(pickups) == 45 and kinds == {"spell": 36, "artifact": 9}, "exact45 real physical pickups:36 books and9 chests")
    check(sorted(item["room"] for item in pickups) == list(range(1, 46)), "one physical reward at every room, no exhausted-book omission")
    check(all(item["time_after"] >= item["time_before"] and item["combat_after"] == item["combat_before"] for item in pickups), "all45 pickup walks advance only route clock")
    transitions = visual["transitions"]
    check([(row["from"], row["to"]) for row in transitions] == [(room, room + 1) for room in range(1, 45)], "all44 real portals traverse exactly once")
    check(all(len(row["spells"]) <= 8 for row in transitions), "actual transitions never exceed8 slots")
    records = visual["replacement_records"]
    commits = [row for row in records if row["mode"] == "actual_mouse_keyboard_confirm"]
    skips = [row for row in records if row["mode"] == "actual_cancel_then_skip"]
    check(len(commits) >= 1 and len(skips) >= 1, "actual Main contains confirm and cancel-to-skip interaction")
    check(all(row["new"]["level"] == 1 and row["new"]["remaining"] == 0 for row in commits), "actual replacements begin lv1 without inherited cooldown")
    check(all(len(row["original_cards"]) == 3 for row in records), "transactions preserve original three actual candidates")
    for result_name in ["rules.json", "cards/results.json", "visual/results.json"]:
        result = read(result_name)
        bound = result.get("source_sha256", result.get("source_hashes", {}))
        for path, expected in bound.items():
            file = ROOT / path.removeprefix("res://")
            check(file.is_file() and hashlib.sha256(file.read_bytes()).hexdigest() == expected, result_name + " current bound bytes: " + path)
    ice_reference = json.loads((ROOT / "build/qa/formal-ice-implementation-20261018/materials/results.json").read_text(encoding="utf-8-sig"))["source_sha256"]
    protected = [path for path in ice_reference if path.startswith("res://data/") or path.startswith("res://assets/ui/ice_formal_v1/") or path in ["res://scripts/presentation/route_ice_vfx.gd", "res://scripts/presentation/procedural_ice.gdshader", "res://scripts/presentation/route_spell_vfx.gd"]]
    for path in protected:
        file = ROOT / path.removeprefix("res://")
        check(hashlib.sha256(file.read_bytes()).hexdigest() == ice_reference[path], "ice data/26png/VFX unchanged by replacement: " + path)
    for label in visual["captures"]:
        check((QA / "visual" / (label + ".png")).is_file(), "declared native screenshot exists: " + label)
    exit_path = QA / "visual_exit_code.txt"
    check(exit_path.exists() and exit_path.read_text(encoding="utf-8-sig").strip() == "0", "original native console exit code recorded0")
    failed = sum(not row["ok"] for row in checks)
    result = {"checks": len(checks), "failures": failed, "details": checks, "pickup_counts": dict(kinds), "replacement_records": records, "scope": "Read-only artifact/source/pickup ledger audit. Counts overlap referenced native tests and do not add combat coverage; not player win rate or final30-minute balance."}
    (QA / "acceptance.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Replacement evidence acceptance: {len(checks)} checks, {failed} failures")
    return bool(failed)


if __name__ == "__main__":
    raise SystemExit(main())
