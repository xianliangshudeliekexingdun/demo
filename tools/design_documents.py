"""Resolve historical design and decision paths through migration manifests.

Candidate JSON and frozen numeric evidence retain their original source paths.
Only document readers and historical renderers use this local compatibility map.
"""
from __future__ import annotations

import json
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]


def resolve_design_document(path: str | Path, root: Path = PROJECT_ROOT) -> Path:
    """Return the migrated document path, without reading or writing its content."""
    root = Path(root).resolve()
    source = Path(path)
    if not source.is_absolute():
        source = root / source
    source = source.resolve()
    try:
        relative = source.relative_to(root).as_posix()
    except ValueError:
        return source
    for manifest_name in (
        "docs/游戏设计/原稿迁移表.json",
        "docs/历史决策/归档/原稿迁移表.json",
    ):
        manifest = root / manifest_name
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
        target = (root / destination).resolve()
        try:
            target.relative_to(root)
        except ValueError as error:
            raise ValueError(f"Migrated document escapes project root: {relative}") from error
        return target
    return source
