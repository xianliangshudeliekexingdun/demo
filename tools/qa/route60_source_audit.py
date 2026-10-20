"""Static route/content/source audit. Does not launch Godot or simulate play."""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from design_documents import resolve_design_document

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/qa/route60-20261020"


def read(relative: str):
    return json.loads((ROOT / relative).read_text(encoding="utf-8-sig"))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    checks, warnings = [], []

    def check(name, valid, detail=None):
        checks.append({"check": name, "pass": bool(valid), "detail": detail})

    before = read("build/qa/route60-20261020/before.json")
    baseline = read("tests/fixtures/route45_baseline.json")
    route = read("data/courtyard_route.json")
    enemy = read("data/route_enemy_runtime.json")
    gems = read("data/magic_gems_v1.json")
    economy = read("data/balance_candidates/run_economy_v1.json")
    base = read("data/balance_candidates/first_run_v1.json")
    previous_route = read("build/qa/route60-20261020/before/data/courtyard_route.json")
    previous_gems = read("build/qa/route60-20261020/before/data/magic_gems_v1.json")
    check("sixty continuous authored combat rooms", route["active_room_count"] == 60 and list(route["encounters_by_room"]) == [str(r) for r in range(1, 61)])
    spells, chests = route["reward_rooms"], route["artifact_reward_rooms"]
    for label, nodes in [("spells", spells), ("chests", chests)]:
        check("ordered unique legal " + label, nodes == sorted(set(nodes)) and all(isinstance(r, int) and 1 <= r < 60 for r in nodes))
    check("one reward per nonterminal room; no terminal build choice", set(spells).isdisjoint(chests) and set(spells + chests) == set(range(1, 60)))
    check("expected books and boxes", len(spells) == 48 and len(chests) == 11 and chests[-2:] == [51, 57])
    check("original spell and chest nodes retained", [r for r in spells if r <= 45] == baseline["spell_rooms"] and [r for r in chests if r <= 45] == baseline["treasure_rooms"])
    check("first forty-five exact encounters retained", all(route["encounters_by_room"][str(r)] == baseline["encounters"][str(r)] for r in range(1, 46)))
    for key in ["reward_pickup", "sources", "first_room", "layout_templates", "stage_themes", "templates", "quantity_overrides", "selection"]:
        check("original geometry/source field retained", route[key] == previous_route[key], key)
    check("first forty-five capacity and difficulty retained", route["encounter_limits"]["stages"][:len(baseline["encounter_limits"]["stages"])] == baseline["encounter_limits"]["stages"] and route["difficulty_bands"][:3] == baseline["difficulty_bands"])
    check("first forty-five enemy stages retained", enemy["stat_stages"][:len(baseline["enemy_runtime"]["stat_stages"])] == baseline["enemy_runtime"]["stat_stages"])
    for key, value in baseline["enemy_runtime"].items():
        if key not in ["version", "scope", "stat_stages"]:
            check("shared enemy behavior retained", enemy[key] == value, key)
    for label, stages in [("capacity", route["encounter_limits"]["stages"]), ("difficulty", route["difficulty_bands"]), ("enemy", enemy["stat_stages"])]:
        check("continuous stages " + label, stages[0]["from"] == 1 and stages[-1]["to"] == 60 and all(a["to"] + 1 == b["from"] for a, b in zip(stages, stages[1:])))
    anchor = baseline["enemy_runtime"]["stat_stages"][-1]
    for stage in enemy["stat_stages"][len(baseline["enemy_runtime"]["stat_stages"]):]:
        for kind in ["normal", "elite"]:
            check("final pressure only changes durability", {k: v for k, v in stage[kind].items() if k != "health"} == {k: v for k, v in anchor[kind].items() if k != "health"}, [stage["id"], kind])
    anchor_count = len(enemy["north_spawn"]["x_fractions"]) * len(enemy["north_spawn"]["portal_z_offsets"])
    rows, total, income = [], 0, 0
    ranged_ids = {"M02", "M04", "EL02", "EL02_GUARD"}
    for room in range(1, 61):
        encounter = route["encounters_by_room"][str(room)]
        cap = next(s for s in route["encounter_limits"]["stages"] if s["from"] <= room <= s["to"])
        count = sum(sum(p.values()) for p in encounter["packs"])
        ranged = sum(n for p in encounter["packs"] for k, n in p.items() if k in ranged_ids)
        check("bounded finite packs", 0 < len(encounter["packs"]) <= cap["max_batches"] and cap["alive_cap"] <= anchor_count and all(0 < sum(p.values()) <= cap["alive_cap"] and all(k in enemy["types"] and isinstance(n, int) and n > 0 for k, n in p.items()) for p in encounter["packs"]), room)
        check("implemented encounter kind", encounter["kind"] in ["normal", "elite", "elite_guard"], room)
        stage = next(s for s in economy["stages"] if s["from"] <= room <= s["to"])
        income += stage["clear_gold"] + (stage["elite_bonus"] if encounter["kind"] in ["elite", "elite_guard"] else 0)
        rows.append({"room": room, "kind": encounter["kind"], "total": count, "ranged": ranged, "alive_cap": cap["alive_cap"], "cumulative_gold_without_spending": income})
        total += count
    check("original and new totals", sum(r["total"] for r in rows[:45]) == 466 and total == 753 and sum(r["total"] for r in rows[45:]) == 287)
    check("elite placeholders and final retreat", route["encounters_by_room"]["51"]["kind"] == route["encounters_by_room"]["57"]["kind"] == "elite" and route["encounters_by_room"]["60"]["kind"] == "elite_guard" and rows[56]["total"] > rows[57]["total"] > rows[58]["total"])
    shops = [r for r in base["recovery"]["shop_after"] if r < route["active_room_count"]]
    check("five existing approved shop nodes now active", shops == [9, 24, 33, 42, 54])
    check("elite-only economic anchors", rows[44]["cumulative_gold_without_spending"] == 486 and rows[53]["cumulative_gold_without_spending"] == 606 and income == 726)
    income_rule = gems["route_income"]
    check("gem income aligned with route length", income_rule["max_room"] == route["active_room_count"])
    previous_gems["route_income"]["max_room"] = 60
    check("all other gem/save/draw/workshop parameters retained", gems == previous_gems)
    dust = sum(income_rule["early_dust"] if r <= income_rule["early_end"] else income_rule["later_dust"] for r in range(1, 61))
    check("unchanged per-room dust yields full route income", dust == 105)
    changed = []
    runtime_allowed = {"data/courtyard_route.json", "data/route_enemy_runtime.json", "data/magic_gems_v1.json", "scripts/core/meta_progression.gd", "scripts/ui/atelier_ui.gd", "scripts/ui/first_room_ui.gd", "scripts/ui/gem_workshop.gd"}
    for relative, record in before.items():
        path = ROOT / relative
        equal = path.is_file() and sha(path) == record["sha256"]
        if not equal:
            changed.append(relative)
            check("source change within authorized route scope", relative in runtime_allowed or relative.startswith(("tests/", "docs/")) or relative in ["README.md", "AGENTS.md"], relative)
        if relative.startswith("assets/") or relative.endswith(".exe") or relative in ["project.godot", "export_presets.cfg"]:
            check("art/engine/project/export unchanged", equal, relative)
    registry = read("docs/assets.json")
    for row in registry:
        relative = row.get("target")
        if not relative:
            continue
        path = ROOT / relative
        if path.is_file() and (not row.get("sha256") or sha(path) == row["sha256"]):
            continue
        if relative == "art/lina/lina_rigged_20261016.blend" and path.is_file():
            warnings.append({"path": relative, "reason": "Previously documented Blender registry metadata mismatch; non-runtime creation source is outside this task's preservation snapshot."})
        elif relative in before and path.is_file() and sha(path) == before[relative]["sha256"]:
            warnings.append({"path": relative, "reason": "Pre-existing registry metadata mismatch; file unchanged."})
        else:
            check("registered changed resources match", False, relative)
    export = (ROOT / "export_presets.cfg").read_text(encoding="utf-8-sig").splitlines()
    resources = re.findall(r'"res://([^\"]+)"', next(l for l in export if l.startswith("export_files=")))
    includes = next(l for l in export if l.startswith("include_filter=")).split('"')[1].split(",")
    exported = set(resources + includes)
    for relative in exported:
        check("export dependency exists and excludes QA", (ROOT / relative).is_file() and not relative.startswith(("build/", "tests/", ".godot/")), relative)
    for relative in runtime_allowed:
        check("changed runtime file already exported", relative in exported, relative)
    for relative in resources:
        if relative.endswith((".gd", ".tscn", ".tres", ".gdshader")):
            for dependency in re.findall(r'[\"\']res://([^\"\'\n]+)[\"\']', (ROOT / relative).read_text(encoding="utf-8-sig")):
                check("literal runtime dependency exists", (ROOT / dependency).exists(), [relative, dependency])
                if (ROOT / dependency).is_file():
                    check("literal runtime dependency exported", dependency in exported, [relative, dependency])
    docs = ["README.md", "AGENTS.md", "docs/功能模块.md", "docs/项目架构.md", "docs/历史决策/README.md", "docs/历史决策/20-六十房路线补齐.md", "docs/游戏设计/README.md", "docs/游戏设计/03-首关流程与场景.md", "docs/游戏设计/07-金币商店与品质.md", "docs/游戏设计/09-普通房配置与难度节奏.md", "docs/游戏设计/20-魔法宝石词条与核心流派.md"]
    for relative in docs:
        path = resolve_design_document(ROOT / relative)
        for link in re.findall(r'\]\(([^\)]+)\)', path.read_text(encoding="utf-8-sig")):
            if "://" not in link and not link.startswith("#"):
                target = link.split("#", 1)[0]
                # The report being written below may reference itself.
                check("local documentation reference exists", (path.parent / target).exists() or (path.parent / target).resolve() == OUT / "source_audit.json", [relative, link])
    parse_report = read("build/qa/route60-20261020/parse-results.json")
    for row in parse_report:
        log = OUT / ("parse-" + Path(row["Script"]).stem + ".log")
        check("modified GDScript parses without execution", row["ExitCode"] == 0 and sha(ROOT / row["Script"]) == row["SHA256"] and log.is_file() and "SCRIPT ERROR" not in log.read_text(encoding="utf-8-sig"), row["Script"])
    result = {"checks": len(checks), "failures": sum(not c["pass"] for c in checks), "details": checks, "warnings": warnings, "changed_existing_sources": changed, "rooms": rows, "derived_totals": {"enemies": total, "books": len(spells), "chests": len(chests), "shops_after": shops, "gold_without_spending": income, "dust": dust}, "scope": "Static data/source/dependency/reference checks only. Native play, screenshots, gameplay suites, natural routes and balance validation deferred by explicit user instruction."}
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "source_audit.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: result[k] for k in ["checks", "failures", "warnings", "derived_totals"]}, ensure_ascii=False, indent=2))
    for c in checks:
        if not c["pass"]:
            print("FAIL", c)
    return int(result["failures"] > 0)


if __name__ == "__main__":
    raise SystemExit(main())
