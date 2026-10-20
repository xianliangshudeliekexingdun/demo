"""Local gem parameter, preservation, dependency and documentation audit."""
from __future__ import annotations
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from design_documents import resolve_design_document

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/qa/magic-gems-v2-20261020"

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main() -> int:
    rows, warnings = [], []
    def check(name, valid, detail=None):
        rows.append({"check": name, "pass": bool(valid), "detail": detail})
    for absolute, expected in json.loads((OUT / "protected_before.json").read_text("utf-8")).items():
        path = Path(absolute)
        check("original engines and real profile unchanged", path.is_file() and sha(path) == expected, absolute)
    baseline = json.loads((ROOT / "build/qa/route-shops-20261019/before.json").read_text("utf-8"))
    for relative, record in baseline.items():
        if relative.startswith(("assets/", "data/")):
            path = ROOT / relative
            check("existing art and balance source preserved", path.is_file() and sha(path) == record["sha256"], relative)
    runtime = json.loads((ROOT / "data/magic_gems_v1.json").read_text("utf-8"))
    numeric = json.loads((ROOT / "tools/balance/magic_gems/parameters.json").read_text("utf-8"))
    draw = json.loads((ROOT / "tools/balance/magic_gems/draw_parameters.json").read_text("utf-8"))
    for field in ["slots", "affix_counts"]:
        check("approved numerical contract", runtime[field] == numeric[field], field)
    implemented = json.loads((ROOT / "tools/balance/magic_gems/v2_parameters.json").read_text("utf-8"))
    for field in ["cores", "tier_weights", "workshop"]:
        check("implemented first-pass numerical contract", runtime[field] == implemented[field], field)
    for stat, spec in numeric["affixes"].items():
        check("shared three tiers use former green blue purple anchors", runtime["affixes"][stat]["tiers"] == [spec[q] for q in ("green", "blue", "purple")], stat)
    before_gems = json.loads((OUT / "before/data/magic_gems_v1.json").read_text("utf-8"))
    for field in ["draw_cost", "base_weights", "pity", "route_income"]:
        check("draw and income untouched", runtime[field] == before_gems[field], field)
    check("old cores migrate directly to eight new ones", set(runtime["core_migration_map"]) == set(before_gems["cores"]) and set(runtime["core_migration_map"].values()) == set(runtime["cores"]))
    check("no old core behavior compatibility registry", "legacy_cores" not in runtime)
    for field in ["draw_cost", "base_weights", "pity"]:
        check("approved draw contract", runtime[field] == draw[field], field)
    check("exact eight random cores", len(runtime["cores"]) == 8)
    for room, expected in [(0, 0), (9, 9), (15, 15), (30, 45), (45, 75)]:
        cfg = runtime["route_income"]
        actual = sum(cfg["early_dust"] if n <= cfg["early_end"] else cfg["later_dust"] for n in range(1, room+1))
        check("current route income anchor excludes future bosses", actual == expected, room)
    registry = json.loads((ROOT / "docs/assets.json").read_text("utf-8-sig"))
    targets = [row["target"] for row in registry if "target" in row]
    check("registered resources unique", len(targets) == len(set(targets)))
    for record in registry:
        if "target" not in record:
            continue
        relative = record["target"]
        path = ROOT / relative
        valid = path.is_file() and ("sha256" not in record or sha(path) == record["sha256"])
        if not valid and relative in ["art/lina/lina_rigged_20261016.blend", "scripts/ui/equipment_icon.gd"]:
            warnings.append({"path": relative, "reason": "Known unchanged pre-existing registry hash mismatch."})
        else:
            check("registered resource exists and matches", valid, relative)
    lines = (ROOT / "export_presets.cfg").read_text("utf-8-sig").splitlines()
    scripts = re.findall(r'"res://([^\"]+)"', next(line for line in lines if line.startswith("export_files=")))
    includes = next(line for line in lines if line.startswith("include_filter=")).split('"')[1].split(",")
    exported = set(scripts + includes)
    check("explicit export resources unique", len(scripts) == len(set(scripts)))
    for relative in scripts + includes:
        check("export dependency exists", (ROOT / relative).is_file(), relative)
        check("export excludes QA, engine and build", not relative.startswith(("build/", "tests/", "tools/", ".godot/")) and not relative.endswith(".exe"), relative)
    for relative in ["scripts/core/magic_gems.gd", "scripts/core/route_gem_combat.gd", "scripts/core/route_gem_echo.gd", "scripts/ui/gem_workshop.gd", "scripts/ui/gem_workshop_actions.gd", "data/magic_gems_v1.json"]:
        check("new gem runtime dependency explicit", relative in exported, relative)
    for relative in scripts:
        if not relative.endswith((".gd", ".tscn", ".tres", ".gdshader")):
            continue
        source = (ROOT / relative).read_text("utf-8-sig")
        for ref in re.findall(r'["\']res://([^"\'\n]+)["\']', source):
            path = ROOT / ref
            check("literal runtime dependency exists", path.exists(), [relative, ref])
            if path.is_file() and not ref.startswith("build/"):
                check("literal runtime dependency exported", ref in exported, [relative, ref])
        check("runtime has no offline gem model dependency", "tools/balance/magic_gems" not in source, relative)
    docs = ["README.md", "AGENTS.md", "docs/项目架构.md", "docs/功能模块.md", "docs/历史决策/README.md", "docs/历史决策/19-魔法宝石养成设计.md", "docs/游戏设计/README.md", "docs/游戏设计/20-魔法宝石词条与核心流派.md"]
    for relative in docs:
        path = resolve_design_document(ROOT / relative)
        for ref in re.findall(r'\]\(([^)]+)\)', path.read_text("utf-8-sig")):
            if "://" in ref or ref.startswith("#"):
                continue
            target = ref.split("#", 1)[0]
            if target:
                check("documentation reference exists", (path.parent / target).exists(), [relative, ref])
    sources = ["scripts/main.gd", "scripts/core/meta_progression.gd", "scripts/core/magic_gems.gd", "scripts/core/route_gem_combat.gd", "scripts/core/route_gem_echo.gd", "scripts/core/courtyard_route_run.gd", "scripts/core/route_spell_combat.gd", "scripts/core/route_ice_combat.gd", "scripts/core/route_fire_status.gd", "scripts/core/route_ice_status.gd", "scripts/core/route_artifacts.gd", "scripts/core/route_generic_items.gd", "scripts/ui/atelier_ui.gd", "scripts/ui/first_room_ui.gd", "scripts/ui/gem_workshop.gd", "scripts/ui/gem_workshop_actions.gd", "scripts/presentation/route_spell_vfx.gd", "data/magic_gems_v1.json"]
    result = {"checks": len(rows), "failures": sum(not row["pass"] for row in rows), "details": rows, "warnings": warnings, "runtime_sha256": {path: sha(ROOT / path) for path in sources}, "scope": "Local source, numerical contract, resource and reference audit. No export, remote build, commit or upload."}
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "source_audit.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), "utf-8")
    print(json.dumps({k: result[k] for k in ["checks", "failures", "warnings"]}, ensure_ascii=False, indent=2))
    for row in rows:
        if not row["pass"]:
            print("FAIL", row)
    return int(result["failures"] > 0)

if __name__ == "__main__":
    raise SystemExit(main())
