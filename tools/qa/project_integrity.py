"""Check current references, explicit export resources and the external archive.

Read-only except for this audit's result JSON. Does not launch Godot or export.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from design_documents import external_archive_root, resolve_design_document


def sha(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def audit(verify_archive: bool) -> dict:
    checks = 0
    failures = []
    counts = {}

    def check(group, label, passed, detail=None):
        nonlocal checks
        checks += 1
        counts[group] = counts.get(group, 0) + 1
        if not passed:
            failures.append({"group": group, "check": label, "detail": detail})

    archive = external_archive_root(ROOT)
    check("archive", "configured archive exists", archive is not None and archive.is_dir())
    manifest = json.loads((archive / "迁移清单.json").read_text(encoding="utf-8"))
    if verify_archive:
        for record in manifest["files"]:
            file = (archive / record["path"]).resolve()
            file.relative_to(archive)
            check("archive_hash", record["path"], file.is_file() and sha(file) == record["sha256"])
        for name, expected in manifest["retained_runtime_sha256"].items():
            file = ROOT / name
            check("retained_hash", name, file.is_file() and sha(file) == expected)
        for record in manifest.get("retained_offline_dependencies", []):
            check("retained_tool_hash", record["path"], sha(ROOT / record["path"]) == record["sha256"])

    exports = (ROOT / "export_presets.cfg").read_text(encoding="utf-8-sig")
    resources = json.loads("[" + re.search(r"^export_files=PackedStringArray\((.*)\)$", exports, re.M)[1] + "]")
    exported = set(resources)
    check("export", "export resources unique", len(resources) == len(exported))
    for name in resources:
        check("export", name, name.startswith("res://") and (ROOT / name[6:]).is_file())
        check("export", "no historical/export-only dependency: " + name,
              name.startswith(("res://scripts/", "res://scenes/", "res://assets/")))
    include = json.loads(re.search(r"^include_filter=(.*)$", exports, re.M)[1]).split(",")
    for name in include:
        check("include", name, (ROOT / name).is_file())
    for file in (ROOT / "data").rglob("*.json"):
        check("include", "runtime data included: " + file.name, file.relative_to(ROOT).as_posix() in include)
        json.loads(file.read_text(encoding="utf-8-sig"))
    for name in ("build/templates/windows_debug_x86_64.exe", "build/templates/windows_release_x86_64.exe"):
        check("export_template", name, (ROOT / name).is_file() and name in exports)

    resource_pattern = re.compile(r'''["'](res://[^"'\r\n]*)["']''')
    for directory in ("scripts", "scenes", "tests", "tools"):
        for file in (ROOT / directory).rglob("*"):
            if file.suffix not in {".gd", ".tscn", ".tres", ".gdshader"}:
                continue
            relative = file.relative_to(ROOT).as_posix()
            production = directory in {"scripts", "scenes"}
            if production:
                check("production_export", relative, "res://" + relative in exported)
            text = file.read_text(encoding="utf-8-sig")
            for name in sorted(set(resource_pattern.findall(text))):
                if any(c in name for c in "[]^*%") or name.startswith("res://build/"):
                    continue
                path = ROOT / name[6:]
                check("resource_reference", relative + " -> " + name, path.exists())
                if production and path.is_file():
                    check("production_export", "dependency: " + name,
                          name in exported or name[6:] in include)

    documents = [ROOT / "AGENTS.md", ROOT / "README.md"]
    documents += sorted((ROOT / "docs").rglob("*.md"))
    documents += sorted((ROOT / "tools").rglob("README.md"))
    anchors = {}
    for file in documents:
        for raw in re.findall(r"\]\(([^)\n]+)\)", file.read_text(encoding="utf-8-sig")):
            link, _, fragment = raw.strip().strip("<>").partition("#")
            if not link or re.match(r"^[a-zA-Z][\w+.-]*:", link):
                continue
            target = (file.parent / unquote(link)).resolve()
            check("document_link", file.relative_to(ROOT).as_posix() + " -> " + raw, target.exists())
            if fragment and target.is_file() and target.suffix == ".md":
                if target not in anchors:
                    text = target.read_text(encoding="utf-8-sig")
                    found = set(re.findall(r'''\bid=["']([^"']+)["']''', text))
                    used = Counter()
                    for title in re.findall(r"^#{1,6}\s+(.+)$", text, re.M):
                        title = re.sub(r"<[^>]*>", "", title).strip().rstrip("#").strip()
                        slug = re.sub(r"[^\w\s-]", "", title.lower())
                        slug = re.sub(r"\s", "-", slug)
                        found.add(slug + ("-" + str(used[slug]) if used[slug] else ""))
                        used[slug] += 1
                    anchors[target] = found
                check("document_anchor", file.relative_to(ROOT).as_posix() + " -> " + raw,
                      unquote(fragment) in anchors[target])
    # The old path strings stay frozen, including in data and asset provenance.
    for name in ("docs/游戏设计/00-基础规则.md", "docs/历史决策/25-文档归并与维护规则.md",
                 "docs/历史决策/35-火系法术特效优化.md", "art/lina/QUATERNIUS_CC0.txt"):
        check("path_resolution", name, resolve_design_document(name).is_file())
    for name in ("docs/游戏设计/原稿迁移表.json", "docs/历史决策/归档/原稿迁移表.json"):
        migration = json.loads(resolve_design_document(name).read_text(encoding="utf-8-sig"))
        for original, destination in migration["paths"].items():
            actual = resolve_design_document(original)
            expected = resolve_design_document(destination)
            check("numbered_path_resolution", original, actual.is_file() and actual == expected)
    for name in ("scenes/build_trial.tscn", "scenes/fireball_trial.tscn", "scripts/core/battle.gd"):
        check("retired_entry", name, not (ROOT / name).exists() and (archive / name).is_file())
    check("live_parent", "route retains first_room_run parent",
          (ROOT / "scripts/core/courtyard_route_run.gd").read_text(encoding="utf-8-sig").startswith('extends "res://scripts/core/first_room_run.gd"'))
    return {"checks": checks, "failures": len(failures), "groups": counts, "failed": failures,
            "archive_files": len(manifest["files"]), "archive_bytes": sum(r["bytes"] for r in manifest["files"]),
            "protected_files": len(manifest["retained_runtime_sha256"]), "export_resources": len(resources),
            "scope": "local references, export configuration, migration hashes; no export, pixels, performance or gameplay acceptance"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-archive", action="store_true")
    parser.add_argument("--out", type=Path, default=ROOT / "build/qa/project-slimming-20261026/integrity.json")
    args = parser.parse_args()
    result = audit(args.verify_archive)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k != "failed"}, ensure_ascii=False))
    for failure in result["failed"][:20]:
        print(json.dumps(failure, ensure_ascii=False))
    raise SystemExit(bool(result["failures"]))
