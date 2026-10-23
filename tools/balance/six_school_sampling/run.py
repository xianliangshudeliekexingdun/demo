from __future__ import annotations

import argparse
from dataclasses import asdict
import hashlib
import json
from pathlib import Path
import random
import sys

from model import Rule, eligible, exact_counts, exact_weighted_counts, offer, probabilities, summarize, trajectory

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
DEFAULT_OUTPUT = ROOT / "build/qa/six-school-sampling-20261021/model"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def load_game():
    files = [ROOT / "data/balance_candidates/first_run_v1.json", ROOT / "data/route_spell_runtime.json", ROOT / "data/courtyard_route.json"]
    base, fire, route = map(read, files)
    specs = {s: base["spells"][s] for s in fire["fire"]["spell_ids"]}
    starters = {"fire": fire["fire"]["initial_ids"]}
    for school in ["ice", "lightning", "wind", "earth", "spirit"]:
        path = ROOT / f"data/{school}_spells_v1.json"
        source = read(path)
        files.append(path)
        specs.update(source["spells"])
        starters[school] = source["mechanics"]["initial_ids"]
    if int(base["limits"]["slots"]) != 8 or int(base["limits"]["spell_level"]) != 3:
        raise ValueError("Model contract requires current eight slots / three levels; revise model when runtime limits change")
    ids = list(specs)
    schools = {s: specs[s]["school"] for s in ids}
    requirements = {s: specs[s].get("required_any_spells", []) for s in ids}
    return ids, schools, requirements, starters, route["reward_rooms"], files


def validate(ids, schools, requirements, starters, rooms):
    checks = []
    def check(ok, label): checks.append({"ok": bool(ok), "label": label})
    check(len(ids) == 60 and len(set(ids)) == 60, "sixty distinct real spell IDs")
    check("F04" not in ids, "archived F04 excluded")
    check(len(rooms) == 52 and len(set(rooms)) == 52, "actual 52 book rooms")
    check(set(eligible(ids, {}, requirements)) == set(ids) - {"R06", "S05", "S07"}, "three precise source prerequisites")
    for support, source in [("R06", "R03"), ("S05", "S02"), ("S07", "S03")]:
        check(support in eligible(ids, {source: 1}, requirements), support + " source unlock")
        check(support in eligible(ids, {support: 1}, requirements), support + " owned upgrade survives source loss")
        check(support not in eligible(ids, {support: 3}, requirements), support + " maxed excluded")
    for school in starters:
        check(len(starters[school]) == 3 and all(schools[s] == school for s in starters[school]), school + " three actual starters")
    anchor = exact_counts(10, 50, Rule("affinity", .28))
    check(abs(sum(anchor.values()) - 1) < 1e-12, "exact DP normalized")
    check(abs(sum(k*v for k,v in anchor.items()) - 1.19) < .01, "old 10/50 candidate anchor mean1.19")
    uniform = exact_counts(10, 50, Rule("affinity", 0))
    check(abs(1-uniform.get(0,0) - (1-50*49*48/(60*59*58))) < 1e-12, "uniform hand hypergeometric known case")
    for main in range(0, 11):
        for other in [0,1,2,10,47,50]:
            for a in [0,.28,.40,.52,1]:
                dist = exact_counts(main, other, Rule("affinity", a))
                check(abs(sum(dist.values())-1) < 1e-12, f"count normalization {main}/{other}/{a}")
                check(all(k <= main and k <= 3 and 3-k <= other if main+other >=3 else k <= main for k in dist), f"count availability {main}/{other}/{a}")
    cats=[(True,True),(True,False),(False,True),(False,False)]
    for counts in [[1,9,0,47],[1,8,0,48],[1,7,0,49],[1,9,0,48],[1,9,0,49],[0,0,0,5],[1,1,0,0],[0,0,0,0]]:
        for a in [0,.28,.4,.52]:
            for ow in [1,1.5,2]:
                actual=exact_weighted_counts(counts,cats,Rule("affinity",a,ow))
                check(abs(sum(actual.values())-1)<1e-12,"weighted category normalization "+str((counts,a,ow)))
                if ow == 1:
                    expected=exact_counts(sum(counts[:2]),sum(counts[2:]),Rule("affinity",a))
                    check(all(abs(actual.get(k,0)-expected.get(k,0))<1e-12 for k in range(4)),"weighted/equal DP crosscheck "+str((counts,a)))
    pool = eligible(ids, {"F01":1}, requirements)
    for a in [0,.28,.4,.52]:
        for owned_weight in [1,1.5,2]:
            probs = probabilities(pool, {"F01":1}, schools, "fire", Rule("affinity",a,owned_weight))
            check(abs(sum(probs.values())-1) < 1e-12 and all(p>=0 for p in probs.values()), f"per-ID normalization {a}/{owned_weight}")
            for i in range(30):
                drawn = offer(pool,{"F01":1},schools,"fire",Rule("affinity",a,owned_weight),random.Random(100+i))
                check(len(drawn)==3 and len(set(drawn))==3 and set(drawn)<=set(pool), f"real sequential without-replacement {a}/{owned_weight}/{i}")
    # Monte Carlo only tests distribution, not Godot's PCG trace.
    n = 20000
    school_map = {str(i): "fire" if i<10 else "ice" for i in range(60)}
    hist = [0]*4
    rng = random.Random(193847)
    for _ in range(n):
        drawn=offer(list(school_map),{},school_map,"fire",Rule("affinity",.28),rng)
        hist[sum(school_map[s]=="fire" for s in drawn)]+=1
    for k in range(4):
        check(abs(hist[k]/n-anchor.get(k,0)) < .015, "analytic/seeded aggregate fidelity count"+str(k))
    return checks


def exact_cases(affinity, owned_weight):
    result=[]
    for main,other,owned,label in [(10,50,0,"theoretical_all_60"),(10,47,1,"fire_ice_lightning_wind_start"),(9,48,1,"earth_start_without_R03"),(8,49,1,"spirit_S01_start"),(10,48,1,"earth_R03_start"),(10,49,1,"spirit_summon_start"),(6,2,0,"scarce_cross_pool"),(0,5,0,"no_main"),(5,0,0,"only_main"),(1,1,0,"fewer_than_three")]:
        for mode,level,rule in [("none",0,Rule("affinity",0,owned_weight)),("legacy_none",0,Rule("legacy",legacy_weight=1)), *[("legacy",i+1,Rule("legacy",legacy_weight=w)) for i,w in enumerate([1.5,1.75,2])], *[("affinity",i+1,Rule("affinity",a,owned_weight)) for i,a in enumerate(affinity)]]:
            counts=[owned,main-owned,0,other]
            dist=exact_weighted_counts(counts,[(True,True),(True,False),(False,True),(False,False)],rule)
            main_w=main+owned*(rule.owned_weight-1)
            if main+other == 0: first=0
            elif not main: first=0
            elif not other: first=1
            elif rule.mode=="legacy":first=main_w*rule.legacy_weight/(main_w*rule.legacy_weight+other)
            else:first=main_w/(main_w+other)+(other/(main_w+other))*rule.strength
            result.append({"pool":label,"main":main,"other":other,"owned_main":owned,"owned_weight":rule.owned_weight,"mode":mode,"level":level,"first_main":first,"any_main":1-dist.get(0,0),"all_main":dist.get(min(3,main+other),0),"mean_main":sum(k*p for k,p in dist.items()),"count_distribution":dist})
    return result


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--trials",type=int)
    parser.add_argument("--schools",default="")
    parser.add_argument("--out",type=Path,default=DEFAULT_OUTPUT)
    parser.add_argument("--runtime",type=Path,default=ROOT/"data/route_spell_sampling.json")
    parser.add_argument("--sweep",action="store_true")
    parser.add_argument("--validation-only",action="store_true")
    parser.add_argument("--compact-sweep",action="store_true")
    args=parser.parse_args()
    config=read(HERE/"scenarios.json")
    start_hashes = {}
    ids,schools,requirements,starters,rooms,source_files=load_game()
    source_files += [HERE/"model.py", HERE/"run.py", HERE/"scenarios.json", ROOT/"data/balance_candidates/meta_growth_v1.json", ROOT/"data/magic_gems_v1.json"]
    checks=validate(ids,schools,requirements,starters,rooms)
    out=args.out;out.mkdir(parents=True,exist_ok=True)
    start_hashes.update({p: hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files})
    (out/"model_validation.json").write_text(json.dumps({"checks":len(checks),"failures":sum(not row["ok"] for row in checks),"details":[row["label"] for row in checks if not row["ok"]]},indent=2),encoding="utf-8")
    if any(not c["ok"] for c in checks):
        print("Model fidelity failed",[c for c in checks if not c["ok"]]);return 1
    if args.validation_only:print("Model validation",len(checks),"passed");return 0
    affinity=config["proposal_affinity"]
    owned_weight=config["proposal_owned_weight"]
    runtime=None
    if args.runtime.is_file():
        runtime_text = args.runtime.read_bytes()
        runtime=json.loads(runtime_text.decode("utf-8-sig"))
        start_hashes[args.runtime] = hashlib.sha256(runtime_text).hexdigest()
        (out/"runtime_input.json").write_bytes(runtime_text)
        # The runtime schema is intentionally adapted only after root finalizes it.
        affinity=runtime.get("affinity_by_level", runtime.get("catalyst_affinity_by_level", affinity))
        owned_weight=runtime.get("owned_upgrade_weight", runtime.get("owned_weight",runtime.get("owned_spell_weight",owned_weight)))
        source_files.append(args.runtime)
    (out/"exact_offer_cases.json").write_text(json.dumps(exact_cases(affinity,owned_weight),indent=2),encoding="utf-8")
    chosen_schools=args.schools.split(",") if args.schools else config["schools"]
    trials=args.trials if args.trials is not None else config["trials_per_batch"]
    cases=[("none",0,Rule("affinity",0,owned_weight)),*[("legacy",i+1,Rule("legacy",legacy_weight=w)) for i,w in enumerate([1.5,1.75,2])],*[("accepted" if runtime else "proposal",i+1,Rule("affinity",a,owned_weight)) for i,a in enumerate(affinity)]]
    if args.compact_sweep:
        cases = [(f"compact_a{a}_owned{ow}",0,Rule("affinity",a,ow)) for a in [0,.28,.40,.52] for ow in [1.0,1.5,2.0]]
    if args.sweep:
        cases += [(f"sweep_a{a}_owned{ow}",0,Rule("affinity",a,ow)) for a in config["affinity_sweep"] for ow in config["owned_weight_sweep"]]
    output=[]
    for mode,level,rule in cases:
        for school in chosen_schools:
            index=config["schools"].index(school);secondary=config["schools"][(index+1)%6]
            for policy in config["policies"]:
                rows=[]
                for batch,seed in enumerate(config["seeds"]):
                    for trial in range(trials):
                        rows.append(trajectory(ids,schools,requirements,school,secondary,starters,rule,policy,rooms,seed*100000+trial))
                summary=summarize(rows,len(rooms))
                entry={"mode":mode,"level":level,"school":school,"secondary":secondary,"policy":policy,"rule":asdict(rule),"metrics":summary}
                output.append(entry)
                print(mode,level,school,policy,"main",round(summary["final_main"]["mean"],3),"levels",round(summary["final_levels"]["p10"],3),"res8",round(summary["resonance"]["by_book8"],3),"maxed",round(summary["eight_level3"]["completion_rate"],3),flush=True)
    manifest={"model_version":config["model_version"],"runtime_version":runtime.get("version") if runtime else "proposal_not_runtime", "seeds":config["seeds"],"trials_per_batch":trials,"horizon_books":len(rooms),"initial_spell":"one random actual starter in chosen school","parameters":config,"source_sha256":{p.relative_to(ROOT).as_posix():start_hashes[p] for p in source_files},"source_changed_during_run":[p.relative_to(ROOT).as_posix() for p in source_files if hashlib.sha256(p.read_bytes()).hexdigest()!=start_hashes[p]],"runtime_snapshot":"runtime_input.json" if runtime else None,"omissions":["combat and deaths before book52","spell power and human utility","Godot PCG trace equivalence","treasures and gems","paid currency economics"],"skip_rule":"only full slots with all three cards unowned; no rerolls","model_changes":["Real IDs/source prerequisites and old source replacement retention, continuous reward/replacement/skip replace old synthetic/finite-growth framework."]}
    (out/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
    (out/"trajectories.json").write_text(json.dumps(output,ensure_ascii=False,indent=2),encoding="utf-8")
    print("Completed",len(output),"scenarios;",len(checks),"fidelity checks")
    return 0


if __name__=="__main__":sys.exit(main())
