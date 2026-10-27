"""Resolve original project paths and numbered drafts through the external archive.

Runtime data, asset records and frozen evidence retain their original path strings.
This resolver is for offline readers only; the game never depends on the archive.
"""
from __future__ import annotations

import json
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]


def external_archive_root(root: Path = PROJECT_ROOT) -> Path | None:
    root = Path(root).resolve()
    location = root / "docs/外置资料.json"
    if not location.is_file():
        return None
    config = json.loads(location.read_text(encoding="utf-8-sig"))
    if config.get("version") != 1 or not isinstance(config.get("archive_root"), str):
        raise ValueError(f"Unsupported external archive location: {location}")
    return (root / config["archive_root"]).resolve()


def _logical_target(relative: str, root: Path, archive: Path | None) -> Path:
    local = (root / relative).resolve()
    local.relative_to(root)
    if local.exists() or archive is None:
        return local
    external = (archive / relative).resolve()
    external.relative_to(archive)
    return external if external.exists() else local


def resolve_design_document(path: str | Path, root: Path = PROJECT_ROOT) -> Path:
    """Resolve a current, archived or pre-migration path without editing its source."""
    root = Path(root).resolve()
    archive = external_archive_root(root)
    source = Path(path)
    source = (source if source.is_absolute() else root / source).resolve()
    if source.exists():
        return source
    try:
        relative = source.relative_to(root).as_posix()
    except ValueError:
        if archive is None:
            return source
        try:
            relative = source.relative_to(archive).as_posix()
        except ValueError:
            return source
    for manifest_name in (
        "docs/游戏设计/原稿迁移表.json",
        "docs/历史决策/归档/原稿迁移表.json",
    ):
        manifest = _logical_target(manifest_name, root, archive)
        if not manifest.is_file():
            continue
        migration = json.loads(manifest.read_text(encoding="utf-8-sig"))
        if migration.get("version") != 1 or not isinstance(migration.get("paths"), dict):
            raise ValueError(f"Unsupported document migration manifest: {manifest}")
        destination = migration["paths"].get(relative)
        if destination is None:
            continue
        if not isinstance(destination, str) or Path(destination).is_absolute():
            raise ValueError(f"Invalid migrated document path: {relative}")
        return _logical_target(destination, root, archive)
    target = _logical_target(relative, root, archive)
    if target.exists():
        return target
    # Later decision numbers never had entries in the original 01-25 manifest.
    if relative.startswith("docs/历史决策/") and "/归档/" not in relative:
        return _logical_target("docs/历史决策/归档/" + Path(relative).name, root, archive)
    return target


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", help="Original project-relative or absolute path")
    args = parser.parse_args()
    resolved = resolve_design_document(args.path)
    print(resolved)
    raise SystemExit(0 if resolved.exists() else 1)
