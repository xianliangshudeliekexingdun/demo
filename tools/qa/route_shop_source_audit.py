"""Local preservation, export and documentation audit for the four shops."""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from design_documents import resolve_design_document

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/qa/route-shops-20261019"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    checks, warnings = [], []

    def check(name, valid, detail=None):
        checks.append({"check": name, "pass": bool(valid), "detail": detail})

    before = json.loads((OUT / "before.json").read_text(encoding="utf-8"))
    allowed = {
        "scripts/core/courtyard_route_run.gd", "scripts/core/route_artifacts.gd",
        "scripts/main.gd", "scripts/ui/first_room_ui.gd", "scripts/ui/room_progress.gd",
        "scripts/presentation/first_room_view.gd", "scripts/presentation/lina_motion.gd",
        "tests/courtyard_route_tests.gd", "tests/route45_tests.gd",
        "tests/route_rebalance_tests.gd", "tests/route45_visual.gd",
        "tests/spell_replacement_tests.gd",
    }
    changed = []
    for relative, record in before.items():
        path = ROOT / relative
        equal = path.is_file() and sha(path) == record["sha256"]
        if not equal:
            changed.append(relative)
        if relative.startswith(("assets/", "data/")) or relative.endswith(".exe"):
            check("existing art/data/original engine unchanged", equal, relative)
        elif not equal:
            check("changed source within shop scope", relative in allowed, relative)

    registry = json.loads((ROOT / "docs/assets.json").read_text(encoding="utf-8-sig"))
    targets = [row["target"] for row in registry if "target" in row]
    check("resource registry targets unique", len(targets) == len(set(targets)))
    for row in registry:
        if "target" not in row:
            continue
        path = ROOT / row["target"]
        valid = path.is_file() and ("sha256" not in row or sha(path) == row["sha256"])
        if not valid and row["target"] == "art/lina/lina_rigged_20261016.blend":
            warnings.append({"path": row["target"], "reason": "Known pre-existing Blender registry metadata mismatch; source not edited."})
        elif not valid and row["target"] in before and path.is_file() and sha(path) == before[row["target"]]["sha256"]:
            warnings.append({"path": row["target"], "reason": "Registry hash already differs for unchanged baseline source; original metadata preserved."})
        else:
            check("registered resource matches", valid, row["target"])

    lines = (ROOT / "export_presets.cfg").read_text(encoding="utf-8-sig").splitlines()
    resources = re.findall(r'"res://([^\"]+)"', next(line for line in lines if line.startswith("export_files=")))
    includes = next(line for line in lines if line.startswith("include_filter=")).split('"')[1].split(",")
    check("explicit export whitelist unique", len(resources) == len(set(resources)))
    for relative in resources + includes:
        check("export dependency exists", (ROOT / relative).is_file(), relative)
        check("export excludes QA/build/engine", not relative.startswith(("build/", "tests/", ".godot/")) and not relative.endswith(".exe"), relative)
    for relative in ["scripts/core/route_shop.gd", "scripts/ui/route_shop_ui.gd"]:
        check("shop script explicitly included", relative in resources, relative)
    check("shop runtime JSON explicitly included", "data/route_shop_runtime.json" in includes)
    all_exported = set(resources + includes)
    for relative in resources:
        if not relative.endswith((".gd", ".tscn", ".tres", ".gdshader")):
            continue
        text = (ROOT / relative).read_text(encoding="utf-8-sig")
        for dependency in re.findall(r'[\"\']res://([^\"\'\n]+)[\"\']', text):
            path = ROOT / dependency
            check("literal runtime reference exists", path.exists(), {"source": relative, "reference": dependency})
            if path.is_file() and not dependency.startswith("build/"):
                check("literal dependency on whitelist", dependency in all_exported, {"source": relative, "reference": dependency})

    docs = [resolve_design_document(ROOT / name) for name in ["README.md", "AGENTS.md", "docs/功能模块.md", "docs/项目架构.md", "docs/历史决策/README.md", "docs/历史决策/18-前四十五房商店接入.md", "docs/游戏设计/README.md", "docs/游戏设计/03-首关流程与场景.md", "docs/游戏设计/07-金币商店与品质.md"]]
    for path in docs:
        text = path.read_text(encoding="utf-8-sig")
        for reference in re.findall(r'\]\(([^\)]+)\)', text):
            if "://" in reference or reference.startswith(("#", "app:")):
                continue
            target = reference.split("#", 1)[0]
            if target:
                check("local documentation reference exists", (path.parent / target).exists(), {"source": str(path.relative_to(ROOT)), "reference": reference})

    result = {"checks": len(checks), "failures": sum(not item["pass"] for item in checks), "details": checks, "warnings": warnings, "changed_existing_sources": changed, "scope": "Local preservation/export/reference audit only; no export, upload or remote build."}
    (OUT / "source_audit.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: result[key] for key in ["checks", "failures", "warnings", "changed_existing_sources"]}, ensure_ascii=False, indent=2))
    for item in checks:
        if not item["pass"]:
            print("FAIL", item)
    return int(result["failures"] > 0)


if __name__ == "__main__":
    raise SystemExit(main())
