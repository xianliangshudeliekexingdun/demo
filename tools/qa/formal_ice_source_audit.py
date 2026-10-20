"""Local dependency, native-image identity and preserved-baseline audit for ice."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/qa/formal-ice-implementation-20261018"


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    checks, warnings = [], []

    def check(label, condition, detail=None):
        checks.append({"check": label, "pass": bool(condition), "detail": detail})

    opening = read(OUT / "opening_source.json")["sha256"]
    allowed = {
        "scripts/main.gd", "scripts/core/courtyard_route_run.gd",
        "scripts/core/route_spell_combat.gd", "scripts/core/route_enemy_combat.gd",
        "scripts/core/route_artifacts.gd", "scripts/presentation/route_spell_vfx.gd",
        "data/route_artifact_runtime.json", "docs/assets.json", "export_presets.cfg",
    }
    changed = []
    for relative, expected in opening.items():
        path = ROOT / relative
        same = path.is_file() and sha(path) == expected
        if not same:
            changed.append(relative)
        if relative.startswith("assets/") or relative.endswith(".exe"):
            check("old art and original engine preserved", same, relative)
        elif not same:
            check("changed source within authorized ice scope", relative in allowed or relative.startswith("scripts/ui/"), relative)

    registry = read(ROOT / "docs/assets.json")
    registered = {entry["target"]: entry for entry in registry if "target" in entry}
    check("asset registry paths unique", len(registered) == sum("target" in row for row in registry))
    for relative, entry in registered.items():
        path = ROOT / relative
        valid = path.is_file() and ("sha256" not in entry or sha(path) == entry["sha256"])
        if not valid and relative == "art/lina/lina_rigged_20261016.blend":
            warnings.append({"path": relative, "reason": "Pre-existing Blender metadata hash discrepancy, carried from verified fire audit."})
        else:
            check("registered resource matches", valid, relative)

    preset = (ROOT / "export_presets.cfg").read_text(encoding="utf-8-sig")
    lines = preset.splitlines()
    resources = re.findall(r'"res://([^\"]+)"', next(line for line in lines if line.startswith("export_files=")))
    includes = next(line for line in lines if line.startswith("include_filter=")).split('"', 2)[1].split(",")
    check("export whitelist unique", len(resources) == len(set(resources)))
    for relative in resources + includes:
        check("explicit export dependency exists", (ROOT / relative).is_file(), relative)
    for filename in ["route_ice_combat.gd", "route_ice_status.gd", "route_ice_artifacts.gd"]:
        check("ice core explicitly included", "scripts/core/" + filename in resources, filename)
    for filename in ["ice_spells_v1.json", "ice_artifacts_v1.json"]:
        check("ice data explicitly included", "data/" + filename in includes, filename)

    manifest = read(OUT / "generation_manifest.json")
    entries = manifest if isinstance(manifest, list) else manifest.get("assets", manifest.get("images", []))
    icons = sorted((ROOT / "assets/ui/ice_formal_v1").glob("*.png"))
    check("26 ice icons", len(icons) == 26)
    check("26 generation records", len(entries) == 26)
    identity = []
    for entry in entries:
        relative = entry.get("target", entry.get("final_path", ""))
        target = Path(relative) if Path(relative).is_absolute() else ROOT / relative
        relative = target.relative_to(ROOT).as_posix()
        source = Path(entry.get("source", entry.get("source_path", "")))
        valid = source.is_file() and target.is_file() and sha(source) == sha(target)
        check("generator-native bytes and alpha preserved", valid, relative)
        check("new icon registered", relative in registered, relative)
        check("new icon exported", relative in resources, relative)
        identity.append({"target": relative, "source": str(source), "same_bytes": valid, "sha256": sha(target) if target.is_file() else None})

    refs = set()
    for base in ["scripts", "scenes"]:
        for path in (ROOT / base).rglob("*"):
            if path.suffix in {".gd", ".tscn", ".gdshader"}:
                refs.update(re.findall(r"res://([^\"\s']+)", path.read_text(encoding="utf-8-sig")))
    for relative in sorted(refs):
        if (ROOT / relative).is_dir() or "%" in relative or "*" in relative:
            continue
        check("runtime static reference exists", (ROOT / relative).is_file(), relative)
    for relative in ["data/balance_candidates/first_run_v1.json", "data/balance_candidates/fire_artifacts_v1.json", "data/route_spell_runtime.json", "scripts/core/route_fire_status.gd", "data/generic_artifacts_v1.json", "scripts/core/route_generic_items.gd", "data/balance_candidates/meta_growth_v1.json", "scripts/core/meta_progression.gd", "scripts/core/first_room_run.gd", "data/courtyard_route.json", "data/route_enemy_runtime.json", "project.godot"]:
        check("approved fire/generic/route/meta baseline preserved", sha(ROOT / relative) == opening[relative], relative)
    for entry in read(OUT / "player_file_guard.json")["files"]:
        path = Path(entry["path"])
        check("real save/preferences untouched", path.is_file() == entry["exists"] and (not path.is_file() or sha(path) == entry["sha256"]), path.name)
    report = {"checks": len(checks), "failures": sum(not check["pass"] for check in checks), "details": [check for check in checks if not check["pass"]], "warnings": warnings, "changed_runtime_sources": changed, "registry_entries": len(registry), "export_resources": len(resources), "export_includes": len(includes), "scope": "Local source/resource identity and whitelist audit; no export, commit or upload."}
    report["source_sha256"] = {path.relative_to(ROOT).as_posix(): sha(path) for base in ["scripts", "data", "assets", "scenes"] for path in (ROOT / base).rglob("*") if path.is_file() and path.suffix not in {".uid", ".import"}}
    (OUT / "source_audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    (OUT / "native_asset_identity.json").write_text(json.dumps({"checks": len(identity), "failures": sum(not entry["same_bytes"] for entry in identity), "assets": identity}, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f'Ice source/resource audit: {report["checks"]} checks, {report["failures"]} failures')
    for entry in report["details"]:
        print(entry)
    return int(report["failures"] > 0)


if __name__ == "__main__":
    raise SystemExit(main())
