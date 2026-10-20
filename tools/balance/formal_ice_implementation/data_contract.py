"""Read-only comparison of approved ice numbers and runtime inputs.

This does not validate combat behavior or generate runtime values. The original
candidate status text is historical; the current user authorization is recorded
by the implementation task, not inferred from that label.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "build/qa/formal-ice-implementation-20261018"


def run() -> int:
    checks: list[dict] = []

    def check(ok: bool, label: str, **evidence):
        checks.append({"ok": bool(ok), "label": label, **evidence})

    def read(relative: str):
        return json.loads((ROOT / relative).read_text(encoding="utf-8-sig"))

    def compare(expected, actual, label: str):
        if isinstance(expected, dict):
            check(isinstance(actual, dict), label + " object")
            if isinstance(actual, dict):
                for key, value in expected.items():
                    check(key in actual, label + "." + key + " exists")
                    if key in actual:
                        compare(value, actual[key], label + "." + key)
        elif isinstance(expected, list):
            check(isinstance(actual, list) and len(expected) == len(actual), label + " length")
            if isinstance(actual, list):
                for index, (left, right) in enumerate(zip(expected, actual)):
                    compare(left, right, f"{label}[{index}]")
        else:
            check(expected == actual, label, expected=expected, actual=actual)

    candidate_path = "tools/balance/five_schools/ice.json"
    spells_path = "data/ice_spells_v1.json"
    items_path = "data/ice_artifacts_v1.json"
    approved, runtime, treasures = map(read, [candidate_path, spells_path, items_path])
    check(len(approved["spells"]) == len(runtime["spells"]) == 10, "ten ice spells")
    check(len(approved["items"]) == len(treasures["items"]) == 16, "sixteen ice profession items")
    compare(approved["mechanics"], runtime["mechanics"], "approved.mechanics")
    for spell in approved["spells"]:
        source = runtime["spells"].get(spell["id"], {})
        for key in ["name", "windup", "levels", "targeting"]:
            if key in spell:
                compare(spell[key], source.get(key), spell["id"] + "." + key)
        for index, value in enumerate(spell["cooldowns"]):
            compare(value, source["levels"][index].get("cooldown"), spell["id"] + f".cooldown.L{index + 1}")
        check(source.get("school") == "ice" and source.get("active") is True, spell["id"] + " active ice")
        for key in ["shared_hit_gate", "shared_chill_gate", "extra_cast_resets_shared_gate", "extra_cast_scales_all_damage", "combat_enemy_range", "recast_remaining_gate", "natural_cast_count", "freeze_duration_add"]:
            if key in spell:
                compare(spell[key], source.get(key), spell["id"] + "." + key)
    for item in approved["items"]:
        source = treasures["items"].get(item["id"], {})
        compare(item["params"], source, item["id"] + ".params")
        for key in ["name", "rarity"]:
            compare(item[key], source.get(key), item["id"] + "." + key)
        compare(item["effect"], source.get("description"), item["id"] + ".description")
        check(source.get("scope") == "ice" and source.get("active") is True, item["id"] + " active ice career")
        if len(item["requires"]) == 1 and item["requires"][0] in runtime["spells"]:
            check(source.get("required_spell") == item["requires"][0], item["id"] + " single-source prerequisite")
    for rarity, count in [("blue", 10), ("purple", 3), ("gold", 3)]:
        check(sum(row["rarity"] == rarity for row in treasures["items"].values()) == count, "ice rarity " + rarity)

    opening_path = OUT / "opening_source.json"
    opening = json.loads(opening_path.read_text(encoding="utf-8-sig"))["sha256"]
    protected = [
        "data/balance_candidates/first_run_v1.json", "data/balance_candidates/fire_artifacts_v1.json",
        "data/generic_artifacts_v1.json", "data/balance_candidates/meta_growth_v1.json",
        "data/courtyard_route.json", "data/route_enemy_runtime.json", "data/first_room_runtime.json",
        "scripts/core/meta_progression.gd", "scripts/core/route_fire_status.gd", "scripts/core/route_generic_items.gd",
        "Godot_v4.7.2-stable_win64.exe", "Godot_v4.7.2-stable_win64_console.exe",
    ]
    for relative in protected:
        expected = opening.get(relative)
        actual = hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()
        check(expected is not None and expected == actual, "protected bytes " + relative, expected=expected, actual=actual)
    bound = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in [candidate_path, spells_path, items_path, "tools/balance/formal_ice_implementation/data_contract.py"]}
    result = {"checks": len(checks), "failures": sum(not row["ok"] for row in checks), "details": checks, "source_sha256": bound,
              "scope": "Static approved-parameter subset identity and original protected-file identity only. Runtime may add execution fields. Does not prove core timing, geometry, eligibility evaluation, rendering or natural acquisition."}
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "data_contract.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"ICE DATA CONTRACT {result['checks']} checks / {result['failures']} failures")
    for row in checks:
        if not row["ok"]:
            print(json.dumps(row, ensure_ascii=False))
    return int(result["failures"] > 0)


if __name__ == "__main__":
    raise SystemExit(run())
