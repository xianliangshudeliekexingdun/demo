"""Validate 50 authored normal rooms and probe bounded reinforcements."""
from __future__ import annotations

import argparse
from collections import Counter
from copy import deepcopy
import csv
import hashlib
import json
import math
from pathlib import Path
import statistics
import zlib

from artifacts import ArtifactCombat, resolve_catalog
from economy import Economy
from meta import derive_gem
from model import build_at
from rooms import ROOM_MODEL_VERSION, RoomCombat, composition, room_budget
from run import load, quantile

ROOT=Path(__file__).resolve().parents[3]
CONFIG=ROOT/"data/balance_candidates/normal_rooms_v1.json"
SCENARIOS=Path(__file__).with_name("room_scenarios.json")


def distribution(values):
    return {"median":statistics.median(values),"p10":quantile(values,.1),"p90":quantile(values,.9),
            "mean":statistics.mean(values),"mean_standard_error":statistics.stdev(values)/math.sqrt(len(values)) if len(values)>1 else 0}


def validate(config, base, catalog, legacy, artifact_assumptions):
    checks=[]
    def check(name, ok):
        if not ok:
            raise AssertionError(name)
        checks.append({"case":name,"status":"pass"})
    specials={e["room"] for e in base["elites"]+base["bosses"]}
    check("50 unique normal rooms plus 7 elite and 3 bosses cover 60",[r["room"] for r in config["rooms"]]==[r for r in range(1,61) if r not in specials])
    check("alive caps align with four approved HP stages",len(config["spawn"]["alive_cap_by_normal_stat_stage"])==len(base["normal_stages"]))
    check("wave switches never heal or reset cooldowns",not config["spawn"]["shield_reset_between_batches"] and not config["spawn"]["cooldown_reset_between_batches"] and config["spawn"]["clear_requires_all_batches_spawned"])
    for row in config["rooms"]:
        room=row["room"]
        budget=room_budget(base,config,row)
        check(f"one or two nonempty integer packs room{room}",1<=len(row["packs"])<=config["spawn"]["max_batches"] and all(pack and all(type(v)is int and v>0 for v in pack.values()) for pack in row["packs"]))
        check(f"known legal monsters and teaching order room{room}",all(k in base["normal_types"] and room>=base["normal_types"][k]["introduced"] for k in budget["counts"]))
        check(f"composition and cap room{room}",budget["peak_upper_bound"]<=budget["alive_cap"] and max(budget["batch_sizes"])<=budget["alive_cap"])
        check(f"readable role limits room{room}",budget["counts"].get("M03",0)<=config["spawn"]["max_normal_chargers_per_room"] and budget["counts"].get("M04",0)<=config["spawn"]["max_normal_casters_per_room"] and budget["counts"].get("M02",0)<=config["spawn"]["max_normal_shooters_alive"])
        check(f"layout defined room{room}",row["layout"] in config["layouts"])
    rows={r["room"]:r for r in config["rooms"]}
    for room,kind in ((4,"M02"),(16,"M03"),(25,"M04")):
        check(f"new type isolated room{room}",dict(composition(rows[room]))=={kind:1})
    for before,after in ((11,14),(42,44),(56,59)):
        a,b=(room_budget(base,config,rows[r]) for r in (before,after))
        check(f"boss approach reduces total and HP {before}->{after}",a["total"]>b["total"] and a["total_health"]>b["total_health"])
    fixture=deepcopy(base)
    fixture["player"].update(health=300,shield=100,attack=100,crit_rate=0,fire_bonus=0)
    fixture["fire_synergy"].update(fire_bonus=0,cooldown_reduction=0)
    fixture["spells"]["F01"].update(windup=.15,cooldown=1.2,travel_delay=.15)
    fixture["spells"]["F01"]["levels"][0]["coefficient"]=1
    fixture["normal_stages"][0]["stats"]["M01"]["health"]=100
    p=dict(legacy["profiles"]["perfect"],bolt_extra=0)
    a=artifact_assumptions["assumptions"]["perfect"]
    spawn=dict(config["spawn"],next_batch_when_alive_at_most=0,preview_seconds=.8)
    pair={"room":1,"packs":[{"M01":1},{"M01":1}]}
    trial=RoomCombat(fixture,catalog,[],{"F01":1},p,a,pair,spawn,2,0,10)
    outcome=trial.run()
    check("hand: two100-HP bolts, .8s warnings, unchanged CD -> 2.45s",outcome["status"]=="clear" and abs(outcome["time"]-2.45)<1e-8 and outcome["casts"]=={"F01":2})
    check("never clear while second wave is pending",len(outcome["spawn_log"])==2 and outcome["spawned"]==2 and outcome["spawn_log"][1]["time"]>outcome["spawn_log"][0]["time"])
    trial=RoomCombat(fixture,catalog,[],{"F01":1},p,a,pair,spawn,2,0,10)
    trial.schedule(1.2,"incoming",50)
    outcome=trial.run()
    check("wave gap does not refill shield or HP",outcome["shield"]==50 and outcome["health"]==300)
    trial=RoomCombat(fixture,catalog,[],{"F01":1,"F10":1},p,a,pair,spawn,2,0,10)
    trial.schedule(1.2,"incoming",50)
    trial.schedule(1.8,"incoming",75)
    outcome=trial.run()
    check("self-target shield recovers before second gap hit, not only after next spawn",outcome["shield_restored"]==fixture["spells"]["F10"]["levels"][0]["shield"] and outcome["health"]==300 and outcome["shield"]==5)
    fixture["spells"]["F04"].update(windup=.35,cooldown=12,duration=12)
    fixture["spells"]["F04"]["levels"][0].update(coefficient=1,interval=1.25)
    trial=RoomCombat(fixture,catalog,[],{"F04":1},p,a,pair,spawn,2,0,10)
    outcome=trial.run()
    check("familiar persists across gap: .8+.35+2x1.25=3.65s, one summon",outcome["status"]=="clear" and abs(outcome["time"]-3.65)<1e-8 and outcome["casts"]=={"F04":1} and outcome["event_count"]<100)
    # One-wave equivalence isolates the extension from established item/damage formulas.
    for build,owned in (({"F01":1},[]),({"F04":3,"F08":3,"F10":1},["P01","P04","G02"]),({"F03":3,"F05":3,"F06":3},["P03","P05","G03"])):
        for seed in (11,93):
            pack={"room":56,"packs":[{"M01":2,"M02":1}]}
            specs=[dict(base["normal_stages"][-1]["stats"][kind],kind=kind,pack=0) for kind,count in pack["packs"][0].items() for _ in range(count)]
            plain=ArtifactCombat(base,catalog,owned,build,p,a,specs,seed,60).run()
            extended=RoomCombat(base,catalog,owned,build,p,a,pack,config["spawn"],3,seed,60,preview_override=0).run()
            check(f"zero-warning single-wave exact legacy equivalence {list(build)} seed{seed}",all(plain[k]==extended[k] for k in ("status","time","raw_damage","effective_damage","casts","natural_count","item_events")))
    return checks


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--config",type=Path,default=CONFIG)
    parser.add_argument("--scenarios",type=Path,default=SCENARIOS)
    parser.add_argument("--out",type=Path,default=ROOT/"build/qa/normal-rooms-20261017/selected")
    parser.add_argument("--trials",type=int)
    parser.add_argument("--no-sweep",action="store_true")
    args=parser.parse_args()
    config,scenario=load(args.config),load(args.scenarios)
    if args.trials:
        if args.trials<2:
            raise ValueError("At least two trials")
        scenario["trials"]=args.trials
    parent=args.config.parent
    sources={key:parent/config[key+"_parameters"] for key in ("base","economy","artifact","meta")}
    base,economy,raw_catalog,meta=(load(sources[k]) for k in ("base","economy","artifact","meta"))
    paths={"legacy_scenarios":Path(__file__).with_name("scenarios.json"),"artifact_scenarios":Path(__file__).with_name("artifact_scenarios.json"),"economy_scenarios":Path(__file__).with_name("economy_scenarios.json")}
    legacy,art_s,econ_s=(load(paths[k]) for k in paths)
    catalog=resolve_catalog(base,raw_catalog)
    checks=validate(config,base,catalog,legacy,art_s)
    economy_engine=Economy(economy,base,catalog,legacy,econ_s)
    input_cache={}
    def inputs(case_name,idx,room):
        case=scenario["cases"][case_name]
        key=case_name,idx
        if key not in input_cache:
            seed=scenario["seed"]+zlib.crc32(case["path"].encode())+idx
            input_cache[key]=economy_engine.campaign(case["path"],case["buy_policy"],seed,trace=True)
        owned=[]
        for event in input_cache[key]["trace"]:
            if event["room"]<room:
                owned=event["owned"]
        derived=derive_gem(base,meta,case["gem"],case["gem_level"])
        return derived,owned,build_at(legacy["paths"][case["path"]],room)
    def simulate(case_name,row,idx,spawn):
        derived,owned,build=inputs(case_name,idx,row["room"])
        case=scenario["cases"][case_name]
        kind=case["profile"]
        seed=scenario["seed"]+zlib.crc32(f"{case_name}/{row['room']}".encode())+idx
        budget=room_budget(base,config,row)
        r=RoomCombat(derived,catalog,owned,build,legacy["profiles"][kind],art_s["assumptions"][kind],row,spawn,budget["alive_cap"],seed,scenario["horizon"]).run()
        r.update(owned=owned,build=build)
        return r
    reports=[]
    for case_name,case in scenario["cases"].items():
        for row in config["rooms"]:
            outcomes=[simulate(case_name,row,i,config["spawn"]) for i in range(scenario["trials"])]
            room=row["room"]
            stage=next(s for s in economy["stages"] if s["from"]<=room<=s["to"])
            timing=distribution([r["time"] for r in outcomes])
            lo,hi=scenario["timing_observation_bands"][stage["id"]]
            watch="tutorial" if room in scenario["tutorial_rooms"] else "below" if timing["median"]<lo else "above" if timing["median"]>hi else "within"
            reports.append({"case":case_name,"room":room,"trials":len(outcomes),"time":timing,"status":watch,
                            "timeouts":sum(r["status"]!="clear" for r in outcomes),"peak_alive":max(r["peak_alive"] for r in outcomes),
                            "empty_enemy_seconds":distribution([r["empty_enemy_seconds"] for r in outcomes]),
                            "owned_count":distribution([len(r["owned"]) for r in outcomes]),"sample":outcomes[0]})
        print(f"{case_name}: 50 normal rooms x {scenario['trials']} trials",flush=True)
    sweeps=[]
    if not args.no_sweep:
        room_map={r["room"]:r for r in config["rooms"]}
        variants=[]
        for key,values in (("preview_seconds",scenario["sweeps"]["preview_seconds"]),("next_batch_when_alive_at_most",scenario["sweeps"]["remaining_alive_threshold"])):
            for value in values:
                if value!=config["spawn"][key]:
                    variants.append((key,value))
        for key,value in variants:
            spawn=dict(config["spawn"],**{key:value})
            for case in ("area","weak_no_shop"):
                for room in scenario["sweep_rooms"]:
                    outcomes=[simulate(case,room_map[room],i,spawn) for i in range(scenario["sweep_trials"])]
                    sweeps.append({"parameter":key,"value":value,"case":case,"room":room,"trials":len(outcomes),"time":distribution([r["time"] for r in outcomes]),"peak_alive":max(r["peak_alive"] for r in outcomes),"timeouts":sum(r["status"]!="clear" for r in outcomes)})
            print(f"sweep {key}={value} complete",flush=True)
    hashes={"rooms":args.config,"scenarios":args.scenarios,**sources,**paths,"room_model":Path(__file__).with_name("rooms.py"),"runner":Path(__file__),"base_model":Path(__file__).with_name("model.py"),"artifact_model":Path(__file__).with_name("artifacts.py"),"economy_model":Path(__file__).with_name("economy.py"),"meta_model":Path(__file__).with_name("meta.py")}
    result={"model_version":ROOM_MODEL_VERSION,"parameters":config,"scenarios":scenario,"checks":checks,
            "input_hashes":{k:{"path":str(p),"sha256":hashlib.sha256(p.read_bytes()).hexdigest()} for k,p in hashes.items()},
            "room_budgets":[room_budget(base,config,r) for r in config["rooms"]],"rows":reports,"sweeps":sweeps,
            "limits":["Enemy positions, attack AI, telegraph overlaps and real safety paths are not simulated","Fields/locked cohorts follow the previous abstract model; future births don't enter old target cohorts","Fixed spell paths and sampled actual shop/chest inventories; no full randomized catalyst+combat campaign","Each probe begins with ready spell clocks and full stats; cooldown behavior across rooms and full-run attrition remain unverified","The warning interval is included in reported times; active caps are safety maxima, not minimum enemy counts"]}
    args.out.mkdir(parents=True,exist_ok=True)
    for filename,data in (("results.json",result),("parameters_used.json",config),("scenarios_used.json",scenario)):
        (args.out/filename).write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding="utf-8")
    with (args.out/"rooms.csv").open("w",newline="",encoding="utf-8-sig") as stream:
        writer=csv.writer(stream)
        writer.writerow(["case","room","trials","median_seconds","p10_seconds","p90_seconds","status","timeouts","peak_alive","owned_median"])
        writer.writerows([r["case"],r["room"],r["trials"],r["time"]["median"],r["time"]["p10"],r["time"]["p90"],r["status"],r["timeouts"],r["peak_alive"],r["owned_count"]["median"]] for r in reports)
    print(f"checks={len(checks)}, encounters={sum(r['trials'] for r in reports)}, timeouts={sum(r['timeouts'] for r in reports)}, saved={args.out}",flush=True)


if __name__=="__main__":
    main()
