"""Bind an evidence run to its explicit res:// dependency closure.

The scope is the declared script/data literals, not a claim that every project
file is unchanged. Missing optional/dynamic paths are listed for audit.
"""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "build/qa/formal-ice-implementation-20261018"


def snapshot(entry):
    pending = [entry]
    seen, missing = {}, []
    while pending:
        relative = pending.pop().removeprefix("res://")
        if relative in seen or relative.startswith("build/"):
            continue
        path = ROOT / relative
        if not path.is_file():
            if relative not in missing:
                missing.append(relative)
            continue
        seen[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        if path.suffix in {".gd", ".json", ".tscn", ".tres"}:
            text = path.read_text(encoding="utf-8-sig")
            pending += re.findall(r'[\"\']res://([^\"\'\n]+\.(?:gd|json|tscn|tres|csv|png|ttf|glb|gdshader))[\"\']', text)
    return {"entry": entry, "sha256": dict(sorted(seen.items())), "unresolved_literals": sorted(missing)}


def main():
    mode, label, entry = sys.argv[1:4]
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / (label + "_source_before.json")
    current = snapshot(entry)
    if mode == "before":
        path.write_text(json.dumps(current, indent=2) + "\n", encoding="utf-8")
        print(f"Bound {len(current['sha256'])} explicit dependencies for {label}")
        return 0
    previous = json.loads(path.read_text(encoding="utf-8"))
    changed = [p for p in set(previous["sha256"]) | set(current["sha256"]) if previous["sha256"].get(p) != current["sha256"].get(p)]
    result = {"scope": "Explicit res literals in the script/data dependency closure; unrelated evolving QA scripts are outside this run.", "entry": entry, "files": len(current["sha256"]), "source_stable": not changed, "changed": sorted(changed), "before": previous, "after": current}
    (OUT / (label + "_source_check.json")).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"{label}: {len(current['sha256'])} dependencies, {len(changed)} changed")
    return int(bool(changed))


if __name__ == "__main__":
    raise SystemExit(main())
