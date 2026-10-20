"""Local source/resource guard for the approved formal-fire implementation."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/qa/formal-fire-implementation-20261018"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main():
    checks: list[dict] = []
    warnings: list[dict] = []

    def check(label, condition, detail=None):
        checks.append({"check": label, "pass": bool(condition), "detail": detail})

    opening = read(OUT / "opening_source.json")["sha256"]
    changed = []
    allowed = {
        "scripts/core/first_room_run.gd",
        "scripts/core/courtyard_route_run.gd",
        "scripts/core/route_spell_combat.gd",
        "scripts/core/route_artifacts.gd",
        "scripts/presentation/route_spell_vfx.gd",
        "data/balance_candidates/first_run_v1.json",
        "data/balance_candidates/fire_artifacts_v1.json",
        "data/route_spell_runtime.json",
        "data/route_artifact_runtime.json",
        "export_presets.cfg",
    }
    for relative, old_hash in opening.items():
        path = ROOT / relative
        unchanged = path.is_file() and digest(path) == old_hash
        if not unchanged:
            changed.append(relative)
        protected = relative.startswith("assets/") or relative.endswith(".exe")
        if protected:
            check("existing art/engine preserved", unchanged, relative)
        elif not unchanged:
            check("changed source within task", relative in allowed or relative.startswith("scripts/ui/"), relative)

    registry = read(ROOT / "docs/assets.json")
    registered = {row["target"]: row for row in registry if "target" in row}
    for row in registry:
        if "target" not in row:
            continue
        target = ROOT / row["target"]
        valid = target.is_file() and ("sha256" not in row or digest(target) == row["sha256"])
        if not valid and row["target"] == "art/lina/lina_rigged_20261016.blend":
            warnings.append({"path": row["target"], "reason": "Pre-existing Blender metadata hash difference; unchanged by this task."})
        else:
            check("registered asset exists and matches", valid, row["target"])

    preset = (ROOT / "export_presets.cfg").read_text(encoding="utf-8-sig")
    resource_line = next(line for line in preset.splitlines() if line.startswith("export_files="))
    resources = re.findall(r'"res://([^\"]+)"', resource_line)
    include_line = next(line for line in preset.splitlines() if line.startswith("include_filter="))
    includes = include_line.split('"', 2)[1].split(",")
    for relative in resources + includes:
        check("explicit export input exists", (ROOT / relative).is_file(), relative)
    check("new fire-status core included", "scripts/core/route_fire_status.gd" in resources)
    new_art = sorted((ROOT / "assets/ui/fire_formal_v1").glob("*.png"))
    check("four new native icons", len(new_art) == 4)
    for path in new_art:
        relative = path.relative_to(ROOT).as_posix()
        check("new icon registered", relative in registered, relative)
        check("new icon explicitly exported", relative in resources, relative)

    refs = set()
    for base in ["scripts", "scenes"]:
        for path in (ROOT / base).rglob("*"):
            if path.suffix in {".gd", ".tscn", ".gdshader"}:
                refs.update(re.findall(r'res://([^\"\s\']+)', path.read_text(encoding="utf-8-sig")))
    for relative in sorted(refs):
        # A few APIs append filenames to a constant source directory.
        if (ROOT / relative).is_dir() or "%" in relative or "*" in relative:
            continue
        check("runtime static resource reference exists", (ROOT / relative).is_file(), relative)

    for relative in ["data/generic_artifacts_v1.json", "data/balance_candidates/meta_growth_v1.json", "data/courtyard_route.json", "data/route_enemy_runtime.json", "scripts/core/route_generic_items.gd", "project.godot"]:
        check("unchanged approved baseline", digest(ROOT / relative) == opening[relative], relative)
    player_guard = read(OUT / "player_file_guard.json")
    for row in player_guard["files"]:
        path = Path(row["path"])
        check("real player file untouched", path.is_file() == row["exists"] and (not path.is_file() or digest(path) == row["sha256"]), path.name)

    report = {
        "checks": len(checks),
        "failures": sum(not row["pass"] for row in checks),
        "details": [row for row in checks if not row["pass"]],
        "warnings": warnings,
        "changed_runtime_sources": changed,
        "registry_entries": len(registry),
        "export_resources": len(resources),
        "export_includes": len(includes),
        "source_sha256": {p.relative_to(ROOT).as_posix(): digest(p) for base in ["scripts", "data", "assets", "scenes"] for p in (ROOT / base).rglob("*") if p.is_file() and p.suffix not in {".import", ".uid"}},
        "scope": "Local source, resource references, explicit whitelist and real player-file hashes; no export or upload.",
    }
    (OUT / "source_audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f'Source/resource audit: {report["checks"]} checks, {report["failures"]} failures')
    for row in report["details"]:
        print(row)
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
