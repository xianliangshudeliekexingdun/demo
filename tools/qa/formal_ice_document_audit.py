"""Check the current ice delivery's local documentation links and scope markers."""
import json
import argparse
import re
import sys
from pathlib import Path
from urllib.parse import unquote

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from design_documents import resolve_design_document

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/qa/formal-ice-implementation-20261018/document_audit.json"
FILES = ["README.md", "AGENTS.md", "docs/项目架构.md", "docs/功能模块.md", "docs/游戏设计/README.md", "docs/游戏设计/12-正式触媒与法术体系.md", "docs/历史决策/README.md", "docs/历史决策/14-其余五系详细设计.md", "docs/历史决策/15-正式冰系实装.md"]
FILES += ["docs/游戏设计/" + name for name in (
    "14-正式冰系法术与职业宝物.md", "15-正式雷系法术与职业宝物.md",
    "16-正式风系法术与职业宝物.md", "17-正式岩系法术与职业宝物.md",
    "18-正式灵契法术与职业宝物.md", "19-五系共通规则与数值审查.md",
)]
FILES += ["docs/历史决策/16-满槽替换与持续法术奖励.md"]
FILES += ["docs/游戏设计/00-基础规则.md", "docs/游戏设计/10-通用道具设计.md"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(OUT))
    args = parser.parse_args()
    checks = []
    for name in FILES:
        path = resolve_design_document(ROOT / name)
        text = path.read_text(encoding="utf-8-sig")
        for raw in re.findall(r"\]\(([^)]+)\)", text):
            link = raw.strip("<>").split("#", 1)[0]
            if not link or "://" in link or link.startswith("mailto:"):
                continue
            target = path.parent / unquote(link)
            checks.append({"check": "local link exists", "source": name, "target": raw, "pass": target.exists()})
        if path.name[:2] in {"15", "16", "17", "18"} and "游戏设计" in name:
            checks.append({"check": "other schools approved but unimplemented", "source": name, "pass": "方案已获用户通过，尚未实施" in text})
    for name in ["README.md", "AGENTS.md", "docs/功能模块.md"]:
        text = (ROOT / name).read_text(encoding="utf-8-sig")
        checks.append({"check": "current active item pool documented", "source": name, "pass": "56" in text and "冰" in text})
    report = {"checks": len(checks), "failures": sum(not row["pass"] for row in checks), "details": [row for row in checks if not row["pass"]], "files": FILES, "scope": "Local references and current scope markers only; not gameplay, pixel or user acceptance evidence."}
    Path(args.out).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f'Document audit: {report["checks"]} checks, {report["failures"]} failures')
    for row in report["details"]:
        print(row)
    return int(report["failures"] > 0)


if __name__ == "__main__":
    raise SystemExit(main())
