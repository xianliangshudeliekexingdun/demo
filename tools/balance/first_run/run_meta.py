"""Meta acquisition/upgrade budgets and finite-pool spell-weight experiments."""
from __future__ import annotations

import argparse
from copy import deepcopy
import csv
import hashlib
import json
import math
from pathlib import Path
import statistics
import zlib

from artifacts import derive_config, resolve_catalog
from meta import META_MODEL_VERSION, Profile, derive_gem, dust_reward, exact_related_offer_probability, forecast, simulate_choices, spell_weights
from model import choice_count, receive_damage
from run import load, quantile

ROOT = Path(__file__).resolve().parents[3]
CONFIG = ROOT / "data/balance_candidates/meta_growth_v1.json"
SCENARIOS = Path(__file__).with_name("meta_scenarios.json")


def distribution(values):
    return {"median":statistics.median(values), "p10":quantile(values,.1), "p90":quantile(values,.9),
            "mean":statistics.mean(values), "mean_standard_error":statistics.stdev(values)/math.sqrt(len(values)) if len(values)>1 else 0}


def costs(config):
    upgrades = sum(config["progression"]["upgrade_cost_by_current_level"].values())
    items = len(config["catalysts"]) + len(config["gems"])
    return {"one_unlocked_item_to_max":upgrades, "starting_pair_to_max":2*upgrades,
            "all_six_to_max":items*upgrades+(items-2)*config["progression"]["unlock_cost"]}


def validate(config, economy, base, catalog, legacy):
    checks = []
    def check(name, ok):
        if not ok:
            raise AssertionError(name)
        checks.append({"case":name, "status":"pass"})
    check("three catalysts and three gems", len(config["catalysts"])==len(config["gems"])==3)
    check("three levels, nondecreasing finite positive catalyst weights", len(config["catalyst_weight_by_level"])==config["progression"]["max_level"]==3 and config["catalyst_weight_by_level"]==sorted(config["catalyst_weight_by_level"]) and all(math.isfinite(w) and w>=1 for w in config["catalyst_weight_by_level"]))
    check("upgrade costs integer positive", set(config["progression"]["upgrade_cost_by_current_level"])=={"1","2"} and all(type(v) is int and v>0 for v in config["progression"]["upgrade_cost_by_current_level"].values()))
    check("no gold conversion or stochastic upgrade failure", not config["currency"]["gold_conversion"] and config["progression"]["failure_chance"]==config["progression"]["copies_required"]==0)
    fixture=deepcopy(config)
    fixture["currency"]["room_dust_by_stage"]={s["id"]:1 for s in economy["stages"]}
    fixture["currency"]["boss_bonus_by_id"]={b["id"]:2 for b in base["bosses"]}
    check("hand: zero clears pay zero", dust_reward(fixture,economy,base,0)==0)
    check("hand: 14 clears pay14, fifteenth plus boss2 pays17", dust_reward(fixture,economy,base,14)==14 and dust_reward(fixture,economy,base,15)==17)
    check("hand: 60 clears + three boss2 =66", dust_reward(fixture,economy,base,60)==66)
    for bad in (-1,61,15.5,True):
        try:
            dust_reward(config,economy,base,bad)
            valid=False
        except ValueError:
            valid=True
        check(f"invalid clear count rejected {bad!r}",valid)
    original=json.dumps(base,sort_keys=True)
    for gid,gem in config["gems"].items():
        check(f"one positive ascending stat per gem {gid}", gem["stat"] in ("health","shield","attack") and len(gem["flat_by_level"])==3 and gem["flat_by_level"]==sorted(gem["flat_by_level"]) and all(type(x)is int and x>0 for x in gem["flat_by_level"]))
        for level in (1,2,3):
            derived=derive_gem(base,config,gid,level)
            field=gem["stat"]
            check(f"gem is additive and changes only its stat {gid}/{level}", derived["player"][field]==base["player"][field]+gem["flat_by_level"][level-1] and sum(derived["player"][k]!=base["player"][k] for k in base["player"])==1 and derived["spells"]==base["spells"])
    check("base data never mutated",json.dumps(base,sort_keys=True)==original)
    for cid,catalyst in config["catalysts"].items():
        targets=catalyst["related_spells"]
        check(f"three distinct real spells {cid}",len(set(targets))==3 and all(t in base["spells"] for t in targets))
        weights=spell_weights(base,config,{},cid,0)
        check(f"unweighted related probability matches choose7,3 / choose10,3 {cid}",abs(exact_related_offer_probability(weights,targets,3)-(1-math.comb(7,3)/math.comb(10,3)))<1e-12)
        maxed={t:base["limits"]["spell_level"] for t in targets}
        reduced=spell_weights(base,config,maxed,cid,3)
        check(f"maxed targets filtered before boost {cid}",not set(reduced)&set(targets) and len(set(reduced.values()))==1 and exact_related_offer_probability(reduced,targets,3)==0)
    full={sid:1 for sid in list(base["spells"])[:base["limits"]["slots"]]}
    check("full eight slots do not offer ninth spell",set(spell_weights(base,config,full,"MC01",3))<=set(full))
    p=Profile(config)
    check("empty profile begins with no purchased copies",not any(p.levels.values()) and p.dust==config["currency"]["initial"])
    check("first catalyst and gem claim free and auto equipped",p.claim_starter("catalysts","MC01") and p.claim_starter("gems","MG01") and p.equipped=={"catalysts":"MC01","gems":"MG01"})
    check("cannot claim other free starters on reopen",not p.claim_starter("catalysts","MC02") and not p.claim_starter("gems","MG02"))
    snapshot=p.snapshot()
    check("cannot upgrade with insufficient dust, state unchanged",not p.advance("MG01") and p.snapshot()==snapshot)
    run=p.begin()
    check("equips and upgrades locked during run",not p.equip("gems",None) and not p.advance("MG01"))
    amount=p.settle_run(run["run_id"],15,economy,base)
    check("normal end grants exact cleared-room budget",amount==dust_reward(config,economy,base,15) and p.dust==amount)
    check("repeat settlement grants nothing",p.settle_run(run["run_id"],60,economy,base)==0 and p.dust==amount)
    p.dust=config["progression"]["unlock_cost"]
    check("unlock exact price grants only one level and no auto switch",p.advance("MG02") and p.levels["MG02"]==1 and p.equipped["gems"]=="MG01" and p.dust==0)
    check("unlocked item can be equipped for free",p.equip("gems","MG02") and p.dust==0)
    p.dust=sum(config["progression"]["upgrade_cost_by_current_level"].values())
    check("two successful upgrades reach cap without copies",p.advance("MG02") and p.advance("MG02") and p.levels["MG02"]==3 and p.dust==0 and not p.advance("MG02"))
    run=p.begin()
    frozen=deepcopy(run)
    p.levels["MG02"]=1 # External future-profile mutation cannot rewrite a captured run.
    check("run snapshot isolated from future level state",run==frozen and p.active["levels"]["MG02"]==3)
    before=p.dust
    p.forced_close()
    check("forced close loses only pending run currency",p.dust==before and p.settle_run(run["run_id"],60,economy,base)==0)
    check("profile JSON roundtrip preserves persistent fields",json.loads(json.dumps(p.snapshot()))==p.snapshot())
    combined=derive_config(derive_gem(base,config,"MG03",3),catalog,["U03"])
    check("gem and generic attack bonuses add, no multiplier double count",combined["player"]["attack"]==base["player"]["attack"]+config["gems"]["MG03"]["flat_by_level"][-1]+catalog["items"]["U03"]["attack_add"])
    check("attack gem cannot raise shield-restoring amounts",combined["spells"]["F10"]==base["spells"]["F10"])
    for cid in config["catalysts"]:
        for level in (0,3):
            for policy in ("seek_related","follow_route"):
                r=simulate_choices(base,config,legacy,cid,level,policy,11)
                check(f"6/16/21 choices remain legal {cid}/{level}/{policy}",all(sum(r["snapshots"][room]["build"].values())==choice_count(room) for room in (15,45,60)) and r["offer_count"]==20)
    return checks


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--config",type=Path,default=CONFIG)
    parser.add_argument("--scenarios",type=Path,default=SCENARIOS)
    parser.add_argument("--out",type=Path,default=ROOT/"build/qa/meta-growth-20261017/selected")
    parser.add_argument("--trials",type=int)
    args=parser.parse_args()
    config,scenario=load(args.config),load(args.scenarios)
    if args.trials:
        if args.trials<2:
            raise ValueError("At least two trials")
        scenario["trials"]=args.trials
    source=args.config.parent
    base_path,economy_path,catalog_path=(source/config[k] for k in ("base_parameters","economy_parameters","artifact_parameters"))
    legacy_path=Path(__file__).with_name("scenarios.json")
    base,economy,raw_catalog,legacy=map(load,(base_path,economy_path,catalog_path,legacy_path))
    catalog=resolve_catalog(base,raw_catalog)
    checks=validate(config,economy,base,catalog,legacy)
    rows=[]
    for cid,catalyst in config["catalysts"].items():
        targets=set(catalyst["related_spells"])
        for level in scenario["levels"]:
            exact=exact_related_offer_probability(spell_weights(base,config,{},cid,level),targets,config["spell_sampling_assumptions"]["offer_size"])
            for policy in scenario["choice_policies"]:
                seed=scenario["seed"]+zlib.crc32(f"{cid}/{policy}".encode())
                results=[simulate_choices(base,config,legacy,cid,level,policy,seed+i) for i in range(scenario["trials"])]
                first=statistics.mean(r["first_offer_related"] for r in results)
                if abs(first-exact)>4*math.sqrt(exact*(1-exact)/len(results)):
                    raise AssertionError("First-offer simulation disagrees with exact probability")
                rows.append({"catalyst":cid,"level":level,"policy":policy,"trials":len(results),
                             "first_offer_exact":exact,"first_offer_mc":first,
                             "related_offer_count":distribution([r["appearances"] for r in results]),
                             "checkpoints":{str(room):{"all_related_rate":statistics.mean(r["snapshots"][room]["all_related"] for r in results),"synergy_rate":statistics.mean(r["snapshots"][room]["synergy"] for r in results),"related_levels":distribution([r["snapshots"][room]["related_levels"] for r in results])} for room in (15,45,60)},
                             "independent_seed_halves":[statistics.mean(r["snapshots"][15]["all_related"] for r in half) for half in (results[:len(results)//2],results[len(results)//2:])],
                             "sample":results[0]})
        print(f"{cid}: completed four levels x two policies",flush=True)
    cost=costs(config)
    full_income=dust_reward(config,economy,base,60)
    forecasts={name:{mode:forecast(config,economy,base,depths,mode) for mode in ("focus","breadth","no_spend")} for name,depths in scenario["progress_sessions"].items()}
    sweeps=[]
    for value in scenario["sweep_weight_multipliers"]:
        weights=spell_weights(base,config,{},"MC01",1,multiplier=value)
        sweeps.append({"kind":"weight","value":value,"first_offer_exact":exact_related_offer_probability(weights,config["catalysts"]["MC01"]["related_spells"],config["spell_sampling_assumptions"]["offer_size"])})
    for value in scenario["sweep_upgrade_cost_scales"]:
        candidate=deepcopy(config)
        candidate["progression"]["upgrade_cost_by_current_level"]={k:round(v*value) for k,v in candidate["progression"]["upgrade_cost_by_current_level"].items()}
        sweeps.append({"kind":"upgrade_cost_scale","value":value,"costs":costs(candidate),"full_clears_to_fund_all":math.ceil(costs(candidate)["all_six_to_max"]/full_income)})
    gems=[]
    for gid in config["gems"]:
        for level in (1,2,3):
            derived=derive_gem(base,config,gid,level)
            combined=derive_config(derived,catalog,["U01","U02","U03"])
            pressures=[]
            late=base["normal_stages"][-1]["stats"]["M01"]["damage"]
            for hits in (2,3):
                hp,shield=derived["player"]["health"],derived["player"]["shield"]
                for _ in range(hits):
                    hp,shield=receive_damage(hp,shield,late)
                pressures.append({"hits":hits,"damage_each":late,"health_damage":derived["player"]["health"]-hp,"health_left":hp,"shield_left":shield})
            gems.append({"gem":gid,"level":level,"player":derived["player"],"with_three_generic_items":combined["player"],"single_room_pressure":pressures})
    targets=[]
    first_upgrade=min(int(k) for k in config["progression"]["upgrade_cost_by_current_level"])
    first_cost=config["progression"]["upgrade_cost_by_current_level"][str(first_upgrade)]
    targets.append({"name":"first boss clear funds first upgrade","value":dust_reward(config,economy,base,base["bosses"][0]["room"]),"status":"within" if dust_reward(config,economy,base,base["bosses"][0]["room"])>=first_cost else "below"})
    n=math.ceil(cost["all_six_to_max"]/full_income)
    lo,hi=scenario["target_complete_runs_to_max_all"]
    targets.append({"name":"full clears needed to fund all six maxed","value":n,"status":"within" if lo<=n<=hi else "outside"})
    for level,limits in scenario["target_full_pool_related_offer_probability"].items():
        p=next(r["first_offer_exact"] for r in rows if r["level"]==int(level))
        targets.append({"name":f"level{level} full-pool related offer probability","value":p,"status":"within" if limits[0]<=p<=limits[1] else "outside"})
    paths={"meta":args.config,"base":base_path,"economy":economy_path,"catalog":catalog_path,"scenarios":args.scenarios,"legacy_scenarios":legacy_path,"meta_model":Path(__file__).with_name("meta.py"),"runner":Path(__file__),"combat_model":Path(__file__).with_name("model.py"),"artifact_model":Path(__file__).with_name("artifacts.py")}
    result={"model_version":META_MODEL_VERSION,"parameters":config,"scenarios":scenario,"checks":checks,"targets":targets,
            "input_hashes":{k:{"path":str(p),"sha256":hashlib.sha256(p.read_bytes()).hexdigest()} for k,p in paths.items()},
            "dust_by_cleared_rooms":{str(i):dust_reward(config,economy,base,i) for i in range(61)},
            "costs":cost,"choice_rows":rows,"forecasts":forecasts,"sweeps":sweeps,"gem_rows":gems,
            "omissions":["Design-only; not game UI, GDScript implementation or filesystem durability test","Spell baseline weights are uniform assumptions; opening choice and two selection policies are explicit inputs","Conditional on listed cleared-room depths, not predicted skill, success rate or minutes per run","Gem pressure anchors have no spells/artifacts/AI and do not predict run survival; no claim all six combinations have equal utility"]}
    args.out.mkdir(parents=True,exist_ok=True)
    for file,data in (("results.json",result),("parameters_used.json",config),("scenarios_used.json",scenario)):
        (args.out/file).write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding="utf-8")
    with (args.out/"choices.csv").open("w",newline="",encoding="utf-8-sig") as stream:
        writer=csv.writer(stream)
        writer.writerow(["catalyst","level","policy","trials","first_offer_exact","all_related_by15","related_levels15_median","all_related_by60"])
        writer.writerows([r["catalyst"],r["level"],r["policy"],r["trials"],r["first_offer_exact"],r["checkpoints"]["15"]["all_related_rate"],r["checkpoints"]["15"]["related_levels"]["median"],r["checkpoints"]["60"]["all_related_rate"]] for r in rows)
    print(f"checks={len(checks)}, campaigns={sum(r['trials'] for r in rows)}, target_misses={sum(t['status']!='within' for t in targets)}, saved={args.out}",flush=True)


if __name__=="__main__":
    main()
