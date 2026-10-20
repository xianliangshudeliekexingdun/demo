"""Bounded source/dependency/document audit for the design24 implementation."""
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
OUT = ROOT / "build/qa/enemy-pressure-20261020/source_audit.json"
baseline = json.loads((HERE / "baseline_manifest.json").read_text(encoding="utf-8-sig"))
allowed = {
    "data/route_enemy_runtime.json", "data/route_nonboss_runtime.json",
    "scripts/core/route_enemy_combat.gd", "scripts/core/route_enemy_nonboss.gd", "scripts/core/route_enemy_barrage.gd",
    "tests/nonboss_difficulty_tests.gd", "tests/route_enemy_pressure_tests.gd", "tests/route_boss_tests.gd", "tests/route45_tests.gd", "tests/run_tests.gd",
}
checks, changed = [], []


def check(name, passed, detail=None):
    checks.append({"name": name, "pass": bool(passed), "detail": detail})


for name, digest in baseline.items():
    file = ROOT / name
    same = file.is_file() and hashlib.sha256(file.read_bytes()).hexdigest() == digest
    if not same:
        changed.append(name)
    check("approved change or byte-preserved: " + name, same or name in allowed)
new_files = []
for directory in ("data", "scripts", "scenes", "assets", "tests"):
    for file in (ROOT / directory).rglob("*"):
        if file.is_file() and file.suffix not in (".import", ".uid"):
            name = file.relative_to(ROOT).as_posix()
            if name not in baseline:
                new_files.append(name)
check("new production/core sources limited to intended test files", sorted(new_files) == ["tests/enemy_damage_growth_tests.gd", "tests/run_enemy_damage_growth_tests.gd"], new_files)
for directory in (ROOT / "data", HERE):
    for file in directory.rglob("*.json"):
        try:
            json.loads(file.read_text(encoding="utf-8-sig"))
            check("valid JSON: " + file.relative_to(ROOT).as_posix(), True)
        except ValueError as error:
            check("valid JSON: " + file.name, False, str(error))
export = (ROOT / "export_presets.cfg").read_text(encoding="utf-8-sig")
for file in sorted(allowed):
    if file.startswith(("scripts/", "data/")):
        check("runtime path explicitly included: " + file, file in export)
check("tuning tool ignored by Godot", (HERE / ".gdignore").is_file())
check("tuning tool not in export whitelist", "enemy_pressure" not in export)
for file in ("scripts/core/route_enemy_combat.gd", "scripts/core/route_enemy_nonboss.gd", "scripts/core/route_enemy_barrage.gd"):
    text = (ROOT / file).read_text(encoding="utf-8-sig")
    check("production has no tools/balance dependency: " + file, "res://tools/" not in text)
docs = [ROOT / "README.md", ROOT / "docs/项目架构.md", ROOT / "docs/功能模块.md", ROOT / "docs/游戏设计/README.md", ROOT / "docs/历史决策/README.md", HERE / "README.md"]
docs += [resolve_design_document(ROOT / "docs/游戏设计" / name) for name in (
    "21-非Boss四阶段与弹幕碰撞方案.md", "22-四个Boss与必金双奖励方案.md",
    "24-四阶段伤害成长与快慢弹幕.md",
)]
docs += [resolve_design_document(ROOT / "docs/历史决策" / name) for name in (
    "21-非Boss难度方案细化.md", "22-四Boss设计.md", "24-四阶段伤害成长与快慢弹幕.md",
)]
for file in docs:
    for ref in re.findall(r"\]\(([^)]+)\)", file.read_text(encoding="utf-8-sig")):
        ref = unquote(ref.strip("<> ").split("#")[0])
        if not ref or "://" in ref:
            continue
        target = (file.parent / ref).resolve()
        # Directory navigation links and this report's own impending path are
        # legitimate; the first run must not require an older audit report.
        check("local doc link: " + file.relative_to(ROOT).as_posix(), target == OUT.resolve() or target.exists(), ref)
failed = [c for c in checks if not c["pass"]]
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps({"checks": len(checks), "failures": len(failed), "failed": failed, "changed_protected_files": changed, "new_protected_files": new_files, "results": checks, "scope": "Local hashes, JSON, explicit inclusion and references only. No export, runtime performance, pixels or natural route. Production save access was not invoked by this audit."}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Source audit: {len(checks)} checks, {len(failed)} failures; {len(changed)} approved existing files changed")
for failure in failed[:8]:
    print(failure)
raise SystemExit(bool(failed))
