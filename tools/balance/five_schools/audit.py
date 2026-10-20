"""Audit design documents and preserve the design-only runtime boundary."""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from design_documents import resolve_design_document

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / "build/qa/five-schools-design-20261018"


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    checks, links, warnings, inputs = [], [], [], []

    def check(label, condition, detail=None):
        checks.append({"check": label, "pass": bool(condition), "detail": detail})

    before = read(OUT / "runtime_guard_before.json")["sha256"]
    for name, expected in before.items():
        path = ROOT / name
        check("runtime/asset/engine unchanged", path.is_file() and sha(path) == expected, name)
    now = {p.relative_to(ROOT).as_posix() for base in ["scripts", "data", "assets", "scenes"]
           for p in (ROOT / base).rglob("*") if p.is_file() and p.suffix not in {".uid", ".import"}}
    check("no new runtime source or image", not (now - set(before)), sorted(now - set(before)))
    documents = [
        "README.md", "AGENTS.md", "docs/项目架构.md", "docs/功能模块.md",
        "docs/游戏设计/README.md", "docs/游戏设计/12-正式触媒与法术体系.md",
        "docs/游戏设计/14-正式冰系法术与职业宝物.md", "docs/游戏设计/15-正式雷系法术与职业宝物.md",
        "docs/游戏设计/16-正式风系法术与职业宝物.md", "docs/游戏设计/17-正式岩系法术与职业宝物.md",
        "docs/游戏设计/18-正式灵契法术与职业宝物.md", "docs/游戏设计/19-五系共通规则与数值审查.md",
        "docs/历史决策/README.md", "docs/历史决策/14-其余五系详细设计.md",
        "tools/balance/five_schools/README.md",
    ]
    for name in documents:
        path = resolve_design_document(ROOT / name)
        check("updated document exists", path.is_file(), name)
        if not path.is_file():
            continue
        inputs.append(path)
        source = path.read_text(encoding="utf-8-sig")
        for raw in re.findall(r"\]\(([^)]+)\)", source):
            target = raw.strip("<>")
            if target.startswith(("http:", "https:", "app:", "codex:", "#")):
                continue
            target = unquote(target.split("#", 1)[0])
            exists = (path.parent / target).resolve().exists()
            links.append({"document": name, "target": target, "exists": exists})
            check("relative local reference exists", exists, {"document": name, "target": target})
    counts = []
    order = read(HERE / "parameters.json")["school_order"]
    for school_id in order:
        candidate = HERE / f"{school_id}.json"
        inputs.append(candidate)
        data = read(candidate)
        document = resolve_design_document(ROOT / data["document"])
        source = document.read_text(encoding="utf-8-sig") if document.is_file() else ""
        check("school candidate document link resolves", document.is_file(), school_id)
        check("school header explicitly pending", "待" in source[:180] and ("未" in source[:220]), school_id)
        check("all ten spell IDs in markdown", all(re.search(rf"(?<![A-Za-z0-9_]){re.escape(s['id'])}(?![A-Za-z0-9_])", source) for s in data["spells"]), school_id)
        check("all sixteen profession IDs in markdown", all(re.search(rf"(?<![A-Za-z0-9_]){re.escape(i['id'])}(?![A-Za-z0-9_])", source) for i in data["items"]), school_id)
        check("all five common proposal links resolve", "19-五系共通规则与数值审查.md" in source, school_id)
        check("spell headings exactly ten", len(re.findall(r"^###\s+(?:I\d{2}|L\d{2}|W\d{2}|R\d{2}|S\d{2}|F04)\b", source, re.M)) == 10, school_id)
        check("candidate source explicitly not runtime", data["status"] == "proposed_unapproved_not_runtime", school_id)
        counts.append({"school": school_id, "spells": len(data["spells"]), "items": len(data["items"]), "starters": sum(s["starter"] for s in data["spells"])})
    model_result = read(OUT / "results.json")
    check("final numeric report has no failures", model_result["failures"] == 0)
    for name, expected in model_result["input_sha256"].items():
        path = ROOT / name
        check("numeric evidence still matches current bound source", path.is_file() and sha(path) == expected, name)
    result = {
        "scope": "Design-only local links, item/spell identity and status checks plus task-opening runtime/resource/engine SHA guard. No Godot run or asset generation.",
        "checks": len(checks), "failures": sum(not c["pass"] for c in checks),
        "failed": [c for c in checks if not c["pass"]], "warnings": warnings,
        "protected_files": len(before), "local_references": len(links),
        "counts": counts,
        "input_sha256": {p.relative_to(ROOT).as_posix(): sha(p) for p in inputs},
    }
    (OUT / "document_audit.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Five-school document/source audit: {result['checks']} checks, {result['failures']} failures; {len(before)} protected files; {len(links)} links")
    for entry in result["failed"]:
        print(entry)
    return bool(result["failures"])


if __name__ == "__main__":
    raise SystemExit(main())
