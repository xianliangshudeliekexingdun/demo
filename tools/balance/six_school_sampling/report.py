from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path

from model import Rule, probabilities, eligible
from run import ROOT, HERE, read, load_game


def wilson(successes, count):
    z=1.959963984540054
    p=successes/count
    divisor=1+z*z/count
    center=(p+z*z/(2*count))/divisor
    radius=z*math.sqrt(p*(1-p)/count+z*z/(4*count*count))/divisor
    return [center-radius,center+radius]


def bridge_checks(path, runtime, schools):
    checks=[]
    rows=read(path)
    affinity=runtime["catalyst_affinity_by_level"]
    ow=float(runtime["owned_upgrade_weight"])
    for index,row in enumerate(rows):
        a=affinity[int(row["level"])-1] if row["level"] else 0
        if row.get("case"):
            mapping={s:spec["school"] for s,spec in row["definitions"].items()} if "definitions" in row else schools
            pool=list(row.get("pool",row.get("probabilities",{})))
            main=row.get("school","fire")
            probs=probabilities(pool,row["owned"],mapping,main,Rule("affinity",a,ow))
            for s,actual in row["probabilities"].items():
                checks.append({"ok":abs(probs[s]-float(actual))<1e-12,"label":f"native per-ID bridge {row['case']} {s}"})
            predicted=sum(p for s,p in probs.items() if mapping[s]==main)
        elif "pool" in row:
            main=row["school"]
            predicted=sum(p for s,p in probabilities(row["pool"],{},schools,main,Rule("affinity",a,ow)).items() if schools[s]==main)
        else:
            m,o=row["main"],row["other"]
            q=m/(m+o) if m+o else 0
            predicted=q+(1-q)*a if m and o else q
        checks.append({"ok":abs(predicted-float(row["main_probability"]))<1e-12,"label":f"native main-probability bridge row{index}"})
    return {"checks":len(checks),"failures":sum(not x["ok"] for x in checks),"details":[x["label"] for x in checks if not x["ok"]],"bridge_sha256":hashlib.sha256(path.read_bytes()).hexdigest(),"scope":"Independent Python formula against native Godot conditional per-ID and school probabilities; does not claim identical RNG traces."}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--out",type=Path,default=ROOT/"build/qa/six-school-sampling-20261021/model/final")
    parser.add_argument("--sweep",type=Path,default=ROOT/"build/qa/six-school-sampling-20261021/model/compact-sweep")
    parser.add_argument("--bridge",type=Path,default=ROOT/"build/qa/six-school-sampling-20261021/sampling/runtime_bridge.json")
    args=parser.parse_args();out=args.out
    manifest=read(out/"manifest.json");rows=read(out/"trajectories.json");exact=read(out/"exact_offer_cases.json")
    runtime=read(out/"runtime_input.json")
    ids,schools,requirements,_,rooms,_=load_game()
    regression_cases=[
        ({"F01":1},57,"ordinary first-book pool57"),
        ({"R03":1},58,"R03 unlocks R06:58 IDs, regression against erroneous59 label"),
        ({"S01":1},57,"S01 does not unlock summon supports"),
        ({"S02":1},59,"S02 unlocks two summon supports:59 IDs"),
        ({"R03":1,"S02":1},60,"both source groups unlock the entire60-ID pool"),
    ]
    regression={"checks":len(regression_cases),"failures":0,"details":[]}
    for owned,count,label in regression_cases:
        if len(eligible(ids,owned,requirements))!=count:
            regression["failures"]+=1;regression["details"].append(label)
    (out/"pool_regressions.json").write_text(json.dumps(regression,ensure_ascii=False,indent=2),encoding="utf-8")
    bridge=bridge_checks(args.bridge,runtime,schools)
    (out/"runtime_bridge_validation.json").write_text(json.dumps(bridge,ensure_ascii=False,indent=2),encoding="utf-8")
    targets=manifest["parameters"]["targets"]
    findings=[]
    for r in rows:
        if r["mode"] not in ["accepted","none"]:continue
        m=r["metrics"];key=r["school"]+"/"+r["mode"]+str(r["level"])+"/"+r["policy"]
        expected=None;actual=None
        if r["policy"]=="upgrade_priority":
            expected=targets["no_catalyst_upgrade_priority_final_levels_p10_min"] if r["mode"]=="none" else targets["upgrade_priority_final_levels_p10_min"]
            actual=m["final_levels"]["p10"]
        elif r["policy"]=="dual_four_four":
            expected=targets["dual_four_four_final_levels_p10_min"];actual=m["final_levels"]["p10"]
        elif r["level"]==1:
            expected=targets["level1_main_priority_main_resonance_by_book8_min"];actual=m["resonance"]["by_book8"]
        if expected is not None:
            findings.append({"scenario":key,"metric":"final_total_levels_p10" if r["policy"]!="main_priority" else "main_resonance_by_book8","actual":actual,"target_min":expected,"status":"within" if actual>=expected else "below_warning"})
    values=[r for r in exact if r["pool"]=="theoretical_all_60" and r["mode"]=="affinity"]
    for r in values:
        cross=1-r["all_main"]
        findings.append({"scenario":"exact_all60_L"+str(r["level"]),"metric":"screen_has_cross_option","actual":cross,"target_min":targets["level3_main_priority_cross_option_rate_min"],"status":"within" if cross>=targets["level3_main_priority_cross_option_rate_min"] else "below_warning"})
    with (out/"trajectory_summary.csv").open("w",encoding="utf-8-sig",newline="") as f:
        fields=["mode","level","school","secondary","policy","trials","final_levels_p10","final_levels_p50","final_levels_p90","final_main_mean","resonance_by_book8","first_level3_book_p50","room15_levels_p10","room15_levels_p50","room30_levels_p10","room30_levels_p50","room45_levels_p10","room45_levels_p50","eight_level3_rate","max_upgrade_drought_p95"]
        writer=csv.DictWriter(f,fieldnames=fields);writer.writeheader()
        for r in rows:
            m=r["metrics"];writer.writerow({**{k:r[k] for k in ["mode","level","school","secondary","policy"]},"trials":m["trials"],"final_levels_p10":m["final_levels"]["p10"],"final_levels_p50":m["final_levels"]["p50"],"final_levels_p90":m["final_levels"]["p90"],"final_main_mean":m["final_main"]["mean"],"resonance_by_book8":m["resonance"]["by_book8"],"first_level3_book_p50":m["first_level3"].get("p50_among_completed"),"eight_level3_rate":m["eight_level3"]["completion_rate"],"max_upgrade_drought_p95":m["max_upgrade_drought"]["p95"],**{f"room{room}_levels_p{q}":m["snapshots"][str(book)][f"levels_p{q}"] for room,book in [(15,13),(30,26),(45,39)] for q in [10,50]}})
    gems=read(ROOT/"data/magic_gems_v1.json");meta=read(ROOT/"data/balance_candidates/meta_growth_v1.json")
    income=gems["route_income"];cost=meta["progression"]
    budgets=[{"cleared_room":room,"dust":min(room,income["early_end"])*income["early_dust"]+max(0,room-income["early_end"])*income["later_dust"]} for room in [15,30,45,60]]
    economics={"source":"actual magic_gems_v1 route_income, meta progression costs; not old meta currency legacy stage fields","rooms":budgets,"first_free_to_level3":sum(cost["upgrade_cost_by_current_level"].values()),"other_five_level1":5*cost["unlock_cost"],"other_one_to_level3":cost["unlock_cost"]+sum(cost["upgrade_cost_by_current_level"].values()),"gems_single_draw":gems["draw_cost"]["single"] if isinstance(gems["draw_cost"],dict) else gems["draw_cost"]}
    (out/"affordability.json").write_text(json.dumps(economics,ensure_ascii=False,indent=2),encoding="utf-8")
    warnings=[x for x in findings if x["status"]!="within"]
    acceptance={"model_version":manifest["model_version"],"model_fidelity_checks":read(out/"model_validation.json"),"pool_regressions":regression,"runtime_bridge":bridge,"targets":findings,"parameter_fitness_warning_count":len(warnings),"accepted_first_pass":bridge["failures"]==0 and regression["failures"]==0 and not manifest["source_changed_during_run"],"reason":"Adopt school affinity .28/.40/.52 plus owned weight2 for observable main-school direction and stronger existing-build growth; retain explicit late off-school drought tradeoff, no guarantee. Free unequip supplies the even-mix option; owned catalyst levels cannot be lowered.","omissions":manifest["omissions"],"rates_are_empirical_not_guarantees":True,"guaranteed_maximum_books_to_any_specific_id":None,"guaranteed_maximum_books_to_upgrade":None}
    (out/"acceptance.json").write_text(json.dumps(acceptance,ensure_ascii=False,indent=2),encoding="utf-8")
    lines=["# Six-school sampling model — accepted first pass","",f"Model {manifest['model_version']}; {len(rows)} scenarios × {manifest['trials_per_batch']*len(manifest['seeds'])} independent seeded trajectories = {sum(r['metrics']['trials'] for r in rows):,} trajectories. Each begins with one real starter, then follows all {len(rooms)} actual book nodes. No combat/death/clear or human play is simulated.","","## Exact card/screen odds","","The 10+50 table is a mathematical all-eligible anchor with zero owned IDs. It is not the actual 57/58/59-ID first-book state. Per-ID weights and q are recomputed after each removal; owned weight2 also applies without a catalyst.","","| Tier | First main | At least one main | Three main | Mean main |","|---|---:|---:|---:|---:|"]
    for r in [x for x in exact if x["pool"]=="theoretical_all_60" and x["mode"] in ["none","affinity"]]:lines.append(f"| {r['mode']} L{r['level']} | {r['first_main']:.4%} | {r['any_main']:.4%} | {r['all_main']:.4%} | {r['mean_main']:.4f} |")
    lines += ["","## Real-content growth distributions","","Entries are final total-level p10/median, out of a maximum24, after book52. A slash separates p10 and median. The designated secondary is the next listed school cyclically; this is a specific pair, not four arbitrary off-school spells.","","| Main | Policy | No catalyst ×2 | L1 | L2 | L3 |","|---|---|---:|---:|---:|---:|"]
    for school in manifest["parameters"]["schools"]:
        for policy in manifest["parameters"]["policies"]:
            entries=[]
            for mode,level in [("none",0),("accepted",1),("accepted",2),("accepted",3)]:
                r=next(x for x in rows if x["school"]==school and x["policy"]==policy and x["mode"]==mode and x["level"]==level);m=r["metrics"]["final_levels"];entries.append(f"{m['p10']:g}/{m['p50']:g}")
            lines.append("| "+" | ".join([school,policy,*entries])+" |")
    lines += ["","## Targets and explicit limitations","",f"{len(warnings)} scenario guardrails are below their provisional target; these are recorded as parameter tradeoff warnings, not hidden test successes. Formula/native bridge checks have {bridge['failures']} failures.","","High-tier affinity can make a retained off-school level2 spell much slower to upgrade. Owned weight2 improves growth but does not establish a guarantee or maximum drought. A first-pass school specialist is intentional; a balanced dual-school strategy can freely unequip the catalyst. No candidate card slot is reserved for upgrade/new/main/off-school.","","The tracked longest upgrade drought only counts books while at least one held spell is below level3, and measures screens containing no legal owned upgrade. It can include long late tails when only off-school upgrades remain. It is not a pity counter and is not promised to the player.","","Main-priority can reach eight same-school level3 spells reliably in a 52-book simulation with replacement. An observed rate100% in 500 trials has a Wilson95% lower bound about99.24%; it is not a mathematical guarantee. Real deaths, spell utility, treasures, enemies, time, human adaptation and combat power are omitted.","","## Fidelity, versions and reproduction","","v2 corrects the initial equal-weight anchor label for R03: its unlocked R06 creates58 legal IDs, not59. It also enumerates owned/new categories exactly for the new ×2 weight. The trajectory eligibility always loaded actual prerequisites; the corrected case is retained as a known-case check. `initial`/`sweep-initial`/`compact-sweep` are provisional tuning results, not the accepted executable snapshot.","",f"Source modifications during accepted run: {manifest['source_changed_during_run']}. Native bridge snapshot: `{args.bridge.relative_to(ROOT).as_posix()}`. Full inputs and hashes: `manifest.json`, `runtime_input.json`; probabilities: `exact_offer_cases.json`; detailed distributions: `trajectories.json` and `trajectory_summary.csv`; warnings: `acceptance.json`.","","```powershell","python tools/balance/six_school_sampling/run.py --trials 125 --out build/qa/six-school-sampling-20261021/model/final","python tools/balance/six_school_sampling/report.py","```",""]
    (out/"report.md").write_text("\n".join(lines),encoding="utf-8")
    print("Native bridge",bridge["checks"],"checks",bridge["failures"],"failures;",len(warnings),"parameter warnings; first-pass accepted",acceptance["accepted_first_pass"])
    return 0 if acceptance["accepted_first_pass"] else 1


if __name__=="__main__":raise SystemExit(main())
