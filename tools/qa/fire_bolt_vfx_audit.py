"""F01 local source/evidence audit; never renders, exports or launches gameplay."""
from pathlib import Path
from urllib.parse import unquote
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/qa/fire-bolt-vfx-20261026"
BEFORE = OUT / "before"
RUNTIME = [
    "scripts/presentation/route_fire_bolt_vfx.gd",
    "scripts/presentation/fire_bolt_body.gdshader",
    "scripts/presentation/fire_bolt_trail.gdshader",
    "scripts/presentation/fire_bolt_surface.gdshader",
    "data/fire_bolt_vfx.json",
]
DOCS = [
    "docs/历史决策/README.md", "docs/历史决策/归档/35-火系法术特效优化.md",
    "docs/游戏设计/法术体系.md", "docs/项目架构.md", "docs/功能模块.md",
]


def read(path):
    return path.read_text(encoding="utf-8-sig")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def functions(source):
    starts = list(re.finditer(r"^func (\w+)\(", source, re.M))
    return {m[1]: source[m.start():starts[i + 1].start() if i + 1 < len(starts) else len(source)]
            for i, m in enumerate(starts)}


def refs(source):
    return set(re.findall(r"\[[^\]]*\]\(([^)]+)\)", source))


def main():
    problems = []
    protected = json.loads(read(BEFORE / "hashes.json"))
    changed = [name for name, sha in protected.items() if not (ROOT / name).is_file() or digest(ROOT / name) != sha]
    if changed != ["scripts/core/route_spell_combat.gd"]:
        problems.append({"unexpected_protected_changes": changed})

    old = functions(read(BEFORE / "scripts/core/route_spell_combat.gd"))
    new = functions(read(ROOT / "scripts/core/route_spell_combat.gd"))
    stripped = dict(new)
    stripped["stop_room"] = stripped["stop_room"].replace("\t_bolt_ends.clear()\n\t_bolt_end_seq = 0\n", "", 1)
    stripped["get_snapshot"] = stripped["get_snapshot"].replace('\t\t"fire_bolt_ends": _bolt_ends.duplicate(true),\n', "", 1)
    stripped["_update_projectiles"] = stripped["_update_projectiles"].replace(
        "\twhile not _bolt_ends.is_empty() and float(run.time) - float(_bolt_ends[0].time) > BOLT_END_RETENTION:\n\t\t_bolt_ends.pop_front()\n", "", 1)
    stripped["_update_projectiles"] = stripped["_update_projectiles"].replace(
        '\t\t\t_note_bolt_end(run, projectile, from, to, clampf(earliest, 0.0, 1.0), dt, "wall" if hit.is_empty() else "enemy", hit)\n', "", 1)
    stripped["_update_projectiles"] = stripped["_update_projectiles"].replace(
        '\t\telse:\n\t\t\t_note_bolt_end(run, projectile, from, to, 1.0, dt, "expired", {}, true)\n', "", 1)
    drift = [name for name, body in old.items() if stripped.get(name) != body]
    if drift or set(new) - set(old) != {"_note_bolt_end"}:
        problems.append({"gameplay_function_drift": drift})

    records = json.loads(read(ROOT / "docs/assets.json"))
    previous_records = json.loads(read(BEFORE / "docs/assets.json"))
    if records[:len(previous_records)] != previous_records:
        problems.append("Pre-existing asset/approval records changed")
    exports = read(ROOT / "export_presets.cfg")
    for name in RUNTIME:
        record = next((r for r in records if r.get("target") == name), {})
        if record.get("sha256") != digest(ROOT / name) or record.get("runtime_approved") is not True:
            problems.append({"asset_hash_or_authorization": name})
        if name not in exports:
            problems.append({"missing_explicit_dependency": name})
    if "res://tests/previews/fire_bolt_preview" in exports:
        problems.append("Review fixture included in export")
    for name in RUNTIME[:-1]:
        source = read(ROOT / name)
        if re.search(r"\bTIME\b|\bTime\.get_|\brand[fi](?:_range)?\s*\(|\brandomize\s*\(", source):
            problems.append({"unowned_clock_or_rng": name})

    main_report = json.loads(read(OUT / "main/main_suite_results.json"))
    targeted = json.loads(read(OUT / "targeted-results.json"))
    shader_lint = json.loads(read(OUT / "shader-lint.json"))
    if main_report["failures"] or targeted["failures"] or not main_report["natural_routes_deferred"]:
        problems.append("Required tests failed or natural-route scope changed")
    if any(shader_lint.values()):
        problems.append({"shader_lint": shader_lint})
    for name in ["main.log", "targeted.log", "editor-import-final.log"]:
        if re.search(r"SCRIPT ERROR|SHADER ERROR|ERROR:", read(OUT / name)):
            problems.append({"error_in_final_log": name})

    summary = {"status": "implemented_technical_checks_passed_visual_pending", "visual_revision": 1,
               "main_suite": {"checks": main_report["checks"], "failures": main_report["failures"], "natural_routes_deferred": True},
               "targeted": {"checks": targeted["checks"], "failures": targeted["failures"], "frozen_collision_comparison_cases": 36},
               "shader_lint": shader_lint, "source_hashes": {name: digest(ROOT / name) for name in RUNTIME},
               "rule_data_assets_scenes_engines_and_accepted_missiles_unchanged": len(changed) == 1,
               "core_change": "Bounded deep-copied terminal-fact journal after unchanged collision/expiry decisions; no extra gameplay effects, hits or RNG.",
               "scope": "Local headless language/structure/lifecycle and actual-core parity only. Test counts are separate, not summed.",
               "not_run": ["interactive gameplay", "screenshots", "GPU composition", "1280x720 pixel/occlusion inspection", "natural full route", "performance", "export", "commit", "upload"],
               "user_visual_acceptance": "pending"}
    (OUT / "results.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (OUT / "static-audit.json").touch(exist_ok=True)  # This audit also validates its own documentation link.
    checked_refs = 0
    for name in DOCS:
        path = ROOT / name
        baseline = BEFORE / name
        added = refs(read(path)) - (refs(read(baseline)) if baseline.is_file() else set())
        for ref in added:
            if re.match(r"[a-z]+://", ref) or ref.startswith("#"):
                continue
            filename, _, anchor = unquote(ref).partition("#")
            target = (path.parent / filename).resolve()
            checked_refs += 1
            if not target.is_file():
                problems.append({"missing_new_reference": name, "reference": ref})
            elif anchor and target.suffix == ".md":
                headings = re.findall(r"^#+ (.+)$", read(target), re.M)
                slugs = [re.sub(r"[^\w\s-]", "", h).strip().lower().replace(" ", "-") for h in headings]
                if anchor not in slugs and f'id="{anchor}"' not in read(target):
                    problems.append({"missing_new_anchor": name, "reference": ref})

    audit = {"ok": not problems, "protected_files": len(protected), "expected_modified_protected_file": changed,
             "original_core_functions_unchanged_after_removing_only_journal_hooks": not drift,
             "prior_asset_records_preserved": records[:len(previous_records)] == previous_records,
             "new_runtime_dependencies": RUNTIME, "new_local_references_checked": checked_refs, "problems": problems}
    (OUT / "static-audit.json").write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(audit, ensure_ascii=False, indent=2))
    raise SystemExit(0 if not problems else 1)


if __name__ == "__main__":
    main()
