"""Local v2 authorization/source/evidence audit. No gameplay or capture."""
from pathlib import Path
from urllib.parse import unquote
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/qa/fire-bolt-curve-v2-20261026"
BEFORE = OUT / "before"
RUNTIME = ["scripts/core/route_spell_combat.gd", "scripts/core/route_fire_bolt_motion.gd",
           "scripts/presentation/route_fire_bolt_vfx.gd", "scripts/presentation/fire_bolt_body.gdshader",
           "data/route_spell_runtime.json", "data/fire_bolt_vfx.json"]
DOCS = ["docs/历史决策/README.md", "docs/历史决策/归档/35-火系法术特效优化.md",
        "docs/游戏设计/法术体系.md", "docs/项目架构.md", "docs/功能模块.md"]
AUTHORIZED_CHANGES = {"data/fire_bolt_vfx.json", "data/route_spell_runtime.json", "scripts/core/route_spell_combat.gd"}
ASSET_CHANGES = {"scripts/presentation/route_fire_bolt_vfx.gd", "scripts/presentation/fire_bolt_body.gdshader", "data/fire_bolt_vfx.json"}


def read(path):
    return path.read_text(encoding="utf-8-sig")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def functions(source):
    starts = list(re.finditer(r"^func (\w+)\(", source, re.M))
    return {m[1]: source[m.start():starts[i + 1].start() if i + 1 < len(starts) else len(source)]
            for i, m in enumerate(starts)}


def refs(source):
    return set(re.findall(r"\[[^\]]*\]\(([^)]+)\)", source))


def main():
    problems = []
    baseline = json.loads(read(BEFORE / "hashes.json"))
    changed = {p for p, h in baseline.items() if not (ROOT / p).is_file() or sha(ROOT / p) != h}
    if changed != AUTHORIZED_CHANGES:
        problems.append({"unexpected_protected_changes": sorted(changed ^ AUTHORIZED_CHANGES)})
    old_runtime = json.loads(read(BEFORE / "data/route_spell_runtime.json"))
    runtime = json.loads(read(ROOT / "data/route_spell_runtime.json"))
    flight = runtime["fire"].pop("bolt_flight", None)
    if runtime != old_runtime or not flight or flight["version"] != 2:
        problems.append("Running data changed outside the approved F01 flight object")

    old_functions = functions(read(BEFORE / "scripts/core/route_spell_combat.gd"))
    new_functions = functions(read(ROOT / "scripts/core/route_spell_combat.gd"))
    allowed = {"configure", "_spawn_bolt", "_update_projectiles", "_advance_curved_bolt", "_note_bolt_end"}
    drift = [name for name, body in old_functions.items() if name not in allowed and new_functions.get(name) != body]
    if drift or set(new_functions) - set(old_functions) != {"_advance_curved_bolt"}:
        problems.append({"unrelated_core_function_changes": drift})
    legacy = new_functions["_update_projectiles"].replace(
        '\t\tif projectile.has("flight"):\n\t\t\tif _advance_curved_bolt(run, projectile, dt): retained.append(projectile)\n\t\t\tcontinue\n', "", 1)
    if legacy != old_functions["_update_projectiles"]:
        problems.append("Legacy-shaped projectile branch changed")

    for name in ["scripts/core/route_fire_bolt_motion.gd", "scripts/presentation/route_fire_bolt_vfx.gd", "scripts/presentation/fire_bolt_body.gdshader"]:
        if re.search(r"\bTIME\b|\bTime\.get_|\brand[fi](?:_range)?\s*\(|\brandomize\s*\(", read(ROOT / name)):
            problems.append({"unexpected_clock_or_rng": name})
    records = json.loads(read(ROOT / "docs/assets.json"))
    previous = json.loads(read(BEFORE / "docs/assets.json"))
    if len(records) != len(previous):
        problems.append("Unexpected asset records were added or removed")
    for before, after in zip(previous, records):
        if before.get("target") not in ASSET_CHANGES and before != after:
            problems.append({"unrelated_asset_record_changed": before.get("target")})
    for name in ASSET_CHANGES:
        record = next(r for r in records if r.get("target") == name)
        if record.get("sha256") != sha(ROOT / name) or record.get("visual_revision") != 2 or not record.get("runtime_approved"):
            problems.append({"asset_hash_or_authorization": name})
    exports = read(ROOT / "export_presets.cfg")
    for name in RUNTIME:
        if name not in exports:
            problems.append({"missing_runtime_dependency": name})
    if "res://tests/previews/fire_bolt_preview" in exports:
        problems.append("Preview was included in export dependencies")
    feedback = json.loads(read(OUT / "feedback-image.json"))
    if sha(ROOT / feedback["target"]) != feedback["sha256"]:
        problems.append("User feedback image bytes changed")

    evidence = {
        "main": json.loads(read(OUT / "main/main_suite_results.json")),
        "curve": json.loads(read(OUT / "curve-results.json")),
        "presentation": json.loads(read(OUT / "presentation-results.json")),
        "fire": json.loads(read(OUT / "fire/rules.json")),
        "spells": json.loads(read(OUT / "spells/results.json")),
    }
    for key, report in evidence.items():
        if report.get("failures") != 0:
            problems.append({"failing_suite": key})
    if not evidence["main"]["natural_routes_deferred"]:
        problems.append("Natural-route scope was not deferred")
    for path, digest in evidence["fire"]["source_hashes"].items():
        if sha(ROOT / path.removeprefix("res://")) != digest:
            problems.append({"stale_fire_evidence": path})
    lint = json.loads(read(OUT / "shader-lint.json"))
    if any(lint.values()):
        problems.append({"shader_lint": lint})
    for name in ["main.log", "curve.log", "presentation.log", "fire.log", "spells.log", "editor-import-final.log"]:
        if re.search(r"SCRIPT ERROR|SHADER ERROR|ERROR:", read(OUT / name)):
            problems.append({"error_in_final_log": name})

    result = {
        "status": "implemented_v2_technical_checks_passed_visual_pending",
        "authorization": "2026-10-26 user: 对的，请你实现. Authorizes F01 real curved launch/acceleration and released level visual growth.",
        "visual_revision": 2, "flight_version": 2,
        "suites": {k: {"checks": v["checks"], "failures": v["failures"]} for k, v in evidence.items()},
        "natural_routes_deferred": True, "counts": "Separate scopes overlap; do not sum as independent gameplay evidence.",
        "examples": evidence["curve"]["examples"], "source_hashes": {n: sha(ROOT / n) for n in RUNTIME},
        "legacy_branch_preserved": legacy == old_functions["_update_projectiles"],
        "physical_scope": "Changed F01 released trajectory, speed and actual arrival time only. Same direct coefficients, windup, cooldown, burn/critical patches, bolt count/delay, collision radius and AoE growth. No additional gameplay RNG.",
        "not_run": ["interactive launch", "screenshots", "GPU composition", "normal-speed appearance", "1280x720 pixels/occlusion", "natural full route", "performance", "export", "commit", "upload"],
        "user_visual_acceptance": "pending for v2; the supplied image records v1 size feedback only",
    }
    (OUT / "results.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (OUT / "static-audit.json").touch(exist_ok=True)
    checked = 0
    for name in DOCS:
        path = ROOT / name
        added = refs(read(path)) - refs(read(BEFORE / name))
        for ref in added:
            if re.match(r"[a-z]+://", ref) or ref.startswith("#"):
                continue
            filename, _, anchor = unquote(ref).partition("#")
            target = (path.parent / filename).resolve()
            checked += 1
            if not target.is_file():
                problems.append({"missing_reference": name, "target": ref})
            elif anchor and target.suffix == ".md":
                slugs = [re.sub(r"[^\w\s-]", "", h).strip().lower().replace(" ", "-")
                         for h in re.findall(r"^#+ (.+)$", read(target), re.M)]
                if anchor not in slugs and f'id="{anchor}"' not in read(target):
                    problems.append({"missing_anchor": name, "target": ref})
    audit = {"ok": not problems, "protected_files": len(baseline), "authorized_modified_files": sorted(changed),
             "unrelated_core_functions_unchanged": not drift, "legacy_projectile_branch_unchanged": legacy == old_functions["_update_projectiles"],
             "new_local_references_checked": checked, "feedback_image_sha256": feedback["sha256"], "problems": problems}
    (OUT / "static-audit.json").write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(audit, ensure_ascii=False, indent=2))
    raise SystemExit(0 if not problems else 1)


if __name__ == "__main__":
    main()
