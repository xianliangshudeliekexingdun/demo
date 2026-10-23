"""Runtime-derived L05 fixed-wave budgets. Never writes runtime parameters."""
from __future__ import annotations

import argparse
import csv
import hashlib
import heapq
import itertools
import json
import math
from pathlib import Path

from model import crit_factor, effective_cd, simulate

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
VERSION = "lightning-cloud-fix-2.0"
EPS = 1e-7


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def budget(spell, level, cdr, horizon, targets=1, mode="natural", extra_scale=.25,
           refresh_spam=False, grade_at=None, crit_rate=.05, crit_multiplier=1.5):
    """One target pool, infinite health, fixed position; additive finite casts."""
    queue, serial, next_cast = [], 0, 0
    live, first_hits = {}, set()
    vulnerable_until, vulnerable_amount = -1, 0
    totals = {"damage": 0., "hits": 0, "natural_casts": 0, "extra_casts": 0,
              "max_live_clouds": 0, "finite_wave_opportunities": 0,
              "coefficient_total": 0., "pulse_times": []}

    def push(at, priority, kind, payload):
        nonlocal serial
        serial += 1
        heapq.heappush(queue, (round(at, 9), priority, serial, kind, payload))

    windup = spell["windup"]
    period = windup + effective_cd(spell["levels"][level - 1]["cooldown"], cdr)
    at = windup
    while at <= horizon + EPS:
        push(at, 1, "cast", (mode != "extra", 1 if mode != "extra" else extra_scale))
        at += period
    if mode == "mixed":
        at = 1.1
        while at <= horizon + EPS:
            push(at, 1, "cast", (False, extra_scale))
            at += .1 if refresh_spam else 7.0
    while queue:
        now, _, _, kind, payload = heapq.heappop(queue)
        if now > horizon + EPS:
            break
        if kind == "cast":
            natural, scale = payload
            current_level = grade_at[1] if grade_at and now >= grade_at[0] else level
            spec = spell["levels"][current_level - 1]
            next_cast += 1
            identity = next_cast
            totals["natural_casts" if natural else "extra_casts"] += 1
            live[identity] = now + spec["duration"]
            totals["max_live_clouds"] = max(totals["max_live_clouds"], len(live))
            for wave, delay in enumerate(spec["strike_times"]):
                push(now + delay, 0, "pulse", (identity, wave, natural, scale, spec))
            push(now + spec["duration"], 2, "expiry", identity)
        elif kind == "expiry":
            live.pop(payload, None)
        else:
            identity, wave, natural, scale, spec = payload
            # Each cast/wave/actor exists once in this schedule. No global gate.
            count = min(targets, spec["strike_target_cap"])
            coefficient = spec["coefficient"] * count * scale
            vulnerability = vulnerable_amount if vulnerable_until > now + EPS else 0
            totals["damage"] += 100 * coefficient * (1 + vulnerability) * crit_factor(crit_rate, crit_multiplier)
            totals["coefficient_total"] += coefficient
            totals["hits"] += count
            totals["finite_wave_opportunities"] += 1
            totals["pulse_times"].append((now, identity, wave, natural))
            if natural and identity not in first_hits and spec["natural_first_hit_vulnerability"]:
                vulnerable_until = now + spec["vulnerability_duration"]
                vulnerable_amount = spec["natural_first_hit_vulnerability"]
            first_hits.add(identity)
    return totals


def execute(output):
    runtime_path = ROOT / "data/lightning_spells_v1.json"
    runtime, old = read(runtime_path), read(HERE / "proposal_v1.json")
    spell = runtime["spells"]["L05"]
    checks, rows, comparisons, warnings = [], [], [], []

    def check(label, ok, detail=None):
        checks.append({"check": label, "pass": bool(ok), "detail": detail})

    check("runtime policy is independent finite casts", spell["cloud_policy"] == "independent_finite_casts")
    check("finite original wave timings retained", [x["strike_times"] for x in spell["levels"]] == [[.4, 1.8, 3.2], [.4, 1.8, 3.2], [.4, 1.8, 3.2, 4.6]])
    check("no damage coefficient inflation for fix", [x["coefficient"] for x in spell["levels"]] == [.9, 1.2, 1.2])
    for level in (1, 2, 3):
        one = budget(spell, level, 0, 6, crit_rate=0)
        expected = [270, 360, 516][level - 1]
        check("single cast hand budget", math.isclose(one["damage"], expected, abs_tol=1e-6), [level, one["damage"], expected])
    known = budget(spell, 3, 0, 60)
    isolated = {"id": "isolated", "positions": {"a": [2, 0]}}
    legacy = simulate(old, "L05", 3, isolated, 60, 0)
    check("lowCDR old and new share unchanged hand anchor", math.isclose(known["damage"], legacy["damage"], abs_tol=1e-6), [known["damage"], legacy["damage"]])
    for level, horizon, targets, mode in itertools.product((1, 2, 3), (30, 60, 300), (1, 6), ("natural", "extra", "mixed")):
        previous, previous_body = -1, -1
        for step in range(61):
            cdr = step / 100
            result = budget(spell, level, cdr, horizon, targets, mode)
            natural = budget(spell, level, cdr, horizon, targets, "natural") if mode == "mixed" else None
            if mode == "mixed":
                if result["damage"] + EPS < previous:
                    warnings.append({"warning": "mixed conditional-window timing sensitivity; original finite waves preserved", "level": level,
                                     "horizon": horizon, "targets": targets, "lower_cdr": (step - 1) / 100, "higher_cdr": cdr,
                                     "lower_damage": previous, "higher_damage": result["damage"],
                                     "relative_change": result["damage"] / previous - 1})
            else:
                check("every1percent CDR has nondecreasing independent-source budget", result["damage"] + EPS >= previous,
                      [level, horizon, targets, mode, cdr, previous, result["damage"]])
            check("raw body coefficient never decreases withCDR", result["coefficient_total"] + EPS >= previous_body)
            previous_body = result["coefficient_total"]
            previous = result["damage"]
            check("natural cadence needs at most two live clouds", mode != "natural" or result["max_live_clouds"] <= 2,
                  [level, horizon, cdr, result["max_live_clouds"]])
            check("finite waves bounded by releases", result["finite_wave_opportunities"] <= (result["natural_casts"] + result["extra_casts"]) * len(spell["levels"][level - 1]["strike_times"]))
            if natural:
                check("fixed weak extras cannot reduce natural-only budget", result["damage"] + EPS >= natural["damage"], [level, horizon, targets, cdr])
            compact = {k: v for k, v in result.items() if k != "pulse_times"}
            rows.append({"level": level, "horizon": horizon, "targets": targets, "mode": mode, "cdr": cdr, "expected_dps": result["damage"] / horizon, **compact})
    # Finite stress: spam is an explicit external schedule, never a proc recursion.
    spam = budget(spell, 3, .6, 30, mode="mixed", refresh_spam=True)
    check("spam adds a finite number of full casts", spam["extra_casts"] < 300 and spam["finite_wave_opportunities"] <= 4 * (spam["natural_casts"] + spam["extra_casts"]))
    normal = budget(spell, 3, .6, 30)
    check("spam never cancels original scheduled pulses", spam["damage"] + EPS >= normal["damage"])
    upgraded = budget(spell, 1, 0, 6, grade_at=(.5, 3), crit_rate=0)
    check("already released level1 cloud keeps three original waves", math.isclose(upgraded["damage"], 270, abs_tol=1e-6))
    # First future wave is never prepaid; a same-timestamp new release cannot erase it.
    clipped = budget(spell, 3, .6, .6)
    check("initial first strike respects release plus0.4 delay", clipped["hits"] == 0)
    for cdr in (.45, .5, .55, .6):
        legacy = simulate(old, "L05", 3, isolated, 60, cdr)
        result = budget(spell, 3, cdr, 60)
        comparisons.append({"cdr": cdr, "legacy_unique_dps": legacy["damage"] / 60, "runtime_finite_dps": result["damage"] / 60,
                            "legacy_hits": legacy["hit_events"], "runtime_hits": result["hits"], "max_live_clouds": result["max_live_clouds"]})
    warnings.append("Independent waves restore previously truncated damage and remove cross-cast throttling; higher output is an explicit rule benefit, not an extra coefficient increase.")
    report = {"model_version": VERSION, "runtime_version": runtime["version"], "status": "runtime-derived_offline_budget_not_playtest",
              "checks": len(checks), "failures": sum(not x["pass"] for x in checks), "failed": [x for x in checks if not x["pass"]],
              "check_details": checks, "rows": len(rows), "comparison": comparisons, "warnings": warnings,
              "input_sha256": {str(p.relative_to(ROOT)).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in (runtime_path, HERE / "proposal_v1.json", HERE / "model.py", Path(__file__))},
              "scope": "Runtime-derived stationary immortal target L05 budgets only. Shared vulnerability updates follow stable cast order; same selected target pool assumed.",
              "assumptions_and_omissions": ["Attack100,5%crit/1.5 multiplier expectation; no random draws.",
                    "Targets remain alive at fixed position; no AI, motion, collider edges, misses or player survival.",
                    "Dense six-target envelope repeatedly selects a fixed capped pool; health-based retargeting after finite HP loss is omitted.",
                    "Natural, extra-only and fixed7s weak-extra schedules are separate deterministic probes; spam100ms probe is finite and not an in-game proc promise.",
                    "No natural inventory, full eight-slot combo, other gem/item effects, whole-route time or performance inference.",
                    "L05 natural-cast concurrency at most2 does not cap arbitrarily supplied extra casts; each extra is finite, nonrecursive and removed at expiry.",
                    "Old proposal and original frozen reports remain unchanged; formal data is the unique default parameter source."]}
    output.mkdir(parents=True, exist_ok=True)
    (output / "results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    with (output / "cdr_sweep.csv").open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
    lines = ["# 雷暴云团高CDR修复核算", "", f"模型 `{VERSION}`，{len(checks)}项／{report['failures']}失败，{len(rows)}条确定性预算。参数直接读取正式data，不另存运行默认值。", "",
             "每cast保留独立有限3／3／4波，后施不取消旧波，取消跨cast共享1.4秒门，单cast单波同敌只命中一次。自然与追加保留各自等级、位置、倍率、首次逐敌易伤资格。", "",
             "| CDR | 旧唯一云DPS | 新有限云DPS | 旧／新有效落雷 | 自然峰值云数 |", "|---|---:|---:|---:|---:|"]
    for row in comparisons:
        lines.append(f"| {row['cdr']:.0%} | {row['legacy_unique_dps']:.4f} | {row['runtime_finite_dps']:.4f} | {row['legacy_hits']}／{row['runtime_hits']} | {row['max_live_clouds']} |")
    lines += ["", "逐百分点0—60%CDR，三级、30／60／300秒、单体／密集六敌包络、自然／追加／固定弱追加混合均逐一比较；自然只由既有冷却产生，未加伤害来压平问题。自然单独及追加单独无反降；混合各档不少于同档自然单独，原始波数／本体系数不减。", "",
              "自然首次命中的3秒易伤窗口随冷却移动，对另一来源固定到达时点的覆盖可能略变，因此混合有条件总量不承诺每个百分点严格单调。该小幅时序波动如实记录在warnings；没有取消原波次、追加覆盖或共享门截断。", "",
              "额外时序压力为有限100ms外部追加注入，只证明每次施法的落雷排程有界、不会反写自然排程，不承诺实际玩家能取得该施放率。", "",
              "## 短易伤窗口敏感性", ""]
    timing_warnings = [x for x in warnings if isinstance(x, dict)]
    largest_drop = -min((x["relative_change"] for x in timing_warnings), default=0)
    lines += [f"共{len(timing_warnings)}处混合窗口波动，最大下降{largest_drop:.4%}；完整情境保留在results.json的warnings。", ""]
    for example in timing_warnings[:2]:
        lines.append(f"- 三级、{example['horizon']}秒、{example['targets']}目标，CDR {example['lower_cdr']:.0%}→{example['higher_cdr']:.0%}：总量{example['lower_damage']:.4f}→{example['higher_damage']:.4f}；自然原波仍完整，变化来自对固定追加的短易伤覆盖。")
    lines += ["", "## 取舍与边界", ""] + ["- " + x for x in [w for w in warnings if isinstance(w, str)] + report["assumptions_and_omissions"]]
    if report["failed"]:
        lines += ["", "## 失败", ""] + ["- " + json.dumps(x, ensure_ascii=False) for x in report["failed"][:20]]
    (output / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"checks": report["checks"], "failures": report["failures"], "rows": len(rows), "failed": report["failed"][:5], "comparison": comparisons}, ensure_ascii=False))
    return bool(report["failures"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/qa/lightning-cloud-fix-20261021")
    raise SystemExit(execute(parser.parse_args().output.resolve()))
