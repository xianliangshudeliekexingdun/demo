"""Verify only the approved reward/UI changes differ from the frozen ice build."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/qa/spell-replacement-20261018"
ALLOWED = {"scripts/core/courtyard_route_run.gd", "scripts/main.gd", "scripts/ui/first_room_ui.gd", "scripts/ui/grimoire_catalog.gd"}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def main():
    checks = []

    def check(label, condition, detail=None):
        checks.append({"check": label, "pass": bool(condition), "detail": detail})

    opening = read(OUT / "opening_source.json")["sha256"]
    changed = []
    for relative, expected in opening.items():
        path = ROOT / relative
        same = path.is_file() and sha(path) == expected
        if not same:
            changed.append(relative)
        check("baseline preserved or authorized reward change", same or relative in ALLOWED, relative)
    registry = read(ROOT / "docs/assets.json")
    for row in registry:
        if "target" not in row or row["target"] == "art/lina/lina_rigged_20261016.blend":
            continue
        path = ROOT / row["target"]
        check("registered resource identity", path.is_file() and ("sha256" not in row or sha(path) == row["sha256"]), row["target"])
    preset = (ROOT / "export_presets.cfg").read_text(encoding="utf-8-sig")
    resources = re.findall(r'"res://([^\"]+)"', next(line for line in preset.splitlines() if line.startswith("export_files=")))
    includes = next(line for line in preset.splitlines() if line.startswith("include_filter=")).split('"', 2)[1].split(",")
    for relative in resources + includes:
        check("explicit export dependency exists", (ROOT / relative).is_file(), relative)
    refs = set()
    for base in ["scripts", "scenes"]:
        for path in (ROOT / base).rglob("*"):
            if path.suffix in {".gd", ".tscn", ".gdshader"}:
                refs.update(re.findall(r"res://([^\"\s']+)", path.read_text(encoding="utf-8-sig")))
    for relative in sorted(refs):
        if (ROOT / relative).is_dir() or "%" in relative or "*" in relative:
            continue
        check("runtime static reference exists", (ROOT / relative).is_file(), relative)
    for row in read(OUT / "player_file_guard.json")["files"]:
        path = Path(row["path"])
        check("real save/preferences untouched", path.is_file() == row["exists"] and (not path.is_file() or sha(path) == row["sha256"]), path.name)
    report = {"checks": len(checks), "failures": sum(not row["pass"] for row in checks), "details": [row for row in checks if not row["pass"]], "changed_runtime_sources": changed, "source_sha256": {path.relative_to(ROOT).as_posix(): sha(path) for base in ["scripts", "data", "assets", "scenes"] for path in (ROOT / base).rglob("*") if path.is_file() and path.suffix not in {".uid", ".import"}}, "scope": "Source/resource identity against final frozen ice baseline; only reward transaction and display/controller changes authorized. No export, commit or upload.", "preserved_known_discrepancy": "Original Blender working-source metadata registry mismatch is pre-existing; no Blender file changed."}
    (OUT / "source_audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f'Replacement source/resource audit: {report["checks"]} checks, {report["failures"]} failures')
    for row in report["details"]:
        print(row)
    return int(report["failures"] > 0)


if __name__ == "__main__":
    raise SystemExit(main())
