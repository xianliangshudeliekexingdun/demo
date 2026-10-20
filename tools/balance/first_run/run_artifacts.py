"""Concrete item values, fixed-build comparisons and bounded interaction sweeps."""
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

from artifacts import ArtifactCombat, ARTIFACT_MODEL_VERSION, derive_config, eligible, resolve_catalog
from model import Combat, build_at, normal_stats, receive_damage
from run import load, quantile, validate as validate_base

ROOT=Path(__file__).resolve().parents[3]
BASE=ROOT/"data/balance_candidates/first_run_v1.json"
CATALOG=ROOT/"data/balance_candidates/fire_artifacts_v1.json"
SCENARIOS=Path(__file__).with_name("artifact_scenarios.json")
PROBE={"F01":3,"F02":3,"F03":3,"F04":3,"F05":3,"F06":2,"F08":3,"F10":1}


def simulate(base,catalog,owned,build,profile,assumptions,enemies,seed,horizon,**kwargs):
    return ArtifactCombat(base,catalog,owned,build,profile,assumptions,enemies,seed,horizon,**kwargs).run()


def validate_items(base,catalog,s,legacy):
    positive_clocks={"interval","shared_cooldown","natural_casts_per_extra","offensive_casts_per_echo"}
    fractions={"slow","move_speed_bonus","fire_vulnerability","remaining_cooldown_multiplier","echo_damage_multiplier","fire_crit_rate_add"}
    for item_id,item in catalog["items"].items():
        for key,value in item.items():
            if isinstance(value,(int,float)):
                if not math.isfinite(value) or value<0 or (key in positive_clocks and value<=0) or (key in fractions and value>1):
                    raise ValueError(f"Invalid numeric item field {item_id}.{key}: {value}")
        if "duration" in item and "interval" in item and item["duration"]<item["interval"]:
            raise ValueError(f"Item {item_id} duration is shorter than its first tick")
    checks=[]
    def check(name,ok):
        if not ok:
            raise AssertionError(name)
        checks.append({"case":name,"status":"pass"})
    counts=Counter(i["rarity"] for i in catalog["items"].values() if i["scope"]=="fire")
    check("fire 10 blue / 5 purple / 3 gold, plus 3 generic",counts=={"blue":10,"purple":5,"gold":3} and len(catalog["items"])==21)
    check("blue spells are one-to-one",[catalog["items"][f"B{i:02}"]["required_spell"] for i in range(1,11)]==[f"F{i:02}" for i in range(1,11)])
    fixture=deepcopy(base)
    fixture["player"].update(attack=100,fire_bonus=0,crit_rate=0)
    fixture["fire_synergy"].update(fire_bonus=0,cooldown_reduction=0)
    p=dict(legacy["profiles"]["perfect"],bolt_extra=1)
    a=dict(s["assumptions"]["perfect"])
    dummy=[{"health":10**12}]
    original=json.dumps(base,sort_keys=True)
    derived=derive_config(base,catalog,list(catalog["items"]))
    check("derivation never mutates approved base",json.dumps(base,sort_keys=True)==original)
    check("generic values match approved references",derived["player"]["health"]==base["player"]["health"]+80 and derived["player"]["shield"]==base["player"]["shield"]+25 and derived["player"]["attack"]==base["player"]["attack"]+15)
    for route in ("burst","spirit","area","optimized"):
        b=build_at(legacy["paths"][route],60)
        for seed in (31,73):
            plain=Combat(base,b,legacy["profiles"]["ordinary"],dummy,seed,20).run()
            itemless=simulate(base,catalog,[],b,legacy["profiles"]["ordinary"],dict(a,geometry_benefit_capture=0),dummy,seed,20)
            keys=("time","raw_damage","effective_damage","casts","natural_count","by_spell","status")
            check(f"itemless exact base fidelity {route} seed {seed}",all(plain[k]==itemless[k] for k in keys))
    try:
        ArtifactCombat(base,catalog,["U01","U01"],{"F01":1},p,a,dummy,0,1)
        valid=False
    except ValueError:
        valid=True
    check("unique item cannot duplicate",valid)
    try:
        ArtifactCombat(base,catalog,["B04"],{"F01":1},p,a,dummy,0,1)
        valid=False
    except ValueError:
        valid=True
    check("spell condition enforced",valid)
    c=ArtifactCombat(fixture,catalog,["U01"],{"F01":1},p,a,dummy,0,1,current_health=173)
    check("life artifact increases cap with no pickup heal",c.health==173 and c.config["player"]["health"]==380)
    r=simulate(fixture,catalog,["P01"],{"F04":1},p,a,dummy,0,12.34)
    check("one extra familiar doubles normal shots, one summon cast",r["raw_damage"]==1800 and r["natural_count"]==1)
    c=ArtifactCombat(fixture,catalog,["P01"],{"F04":1},p,a,dummy,0,2)
    c.q.clear();c.release("F04",True)
    end=c.spirit_until
    check("full familiar population rejects extra summon",not c.release("F04",False) and c.spirit_until==end)
    r=simulate(fixture,catalog,["B04"],{"F04":1},p,a,dummy,0,16.69)
    check("lamp duration 16s, 12 delayed shots x110",r["raw_damage"]==1320 and r["natural_count"]==1)
    c=ArtifactCombat(fixture,catalog,["B10"],{"F10":1},p,a,dummy,0,0.36)
    c.shield=0;r=c.run()
    check("shield charm adds flat15, no attack scaling",r["shield"]==45)
    powerful=deepcopy(fixture);powerful["player"]["attack"]=1000
    c=ArtifactCombat(powerful,catalog,["B10"],{"F10":3},p,a,dummy,0,0.36)
    c.shield=0;r=c.run()
    check("shield3 stays 60 at attack1000",r["shield"]==60 and r["health"]==300)
    critical=deepcopy(fixture)
    critical["player"]["crit_rate"]=1
    critical["limits"]["crit_rate"]=1
    r=simulate(critical,catalog,["B07"],{"F07":3},p,a,dummy,0,2)
    check("center: 1495 crit main +225 aftershock",r["raw_damage"]==1720)
    r=simulate(critical,catalog,["B07"],{"F07":3},dict(p,bomb_center=0),a,dummy,0,2)
    check("outer main and aftershock do not inherit center bonuses",r["raw_damage"]==601)
    r=simulate(fixture,catalog,["B03"],{"F03":1},dict(p,rain_hit=0),a,dummy,0,3)
    check("rain item fixes and amplifies one existing drop, not an added drop",r["raw_damage"]==60*catalog["items"]["B03"].get("first_drop_damage_multiplier",1.0))
    r=simulate(fixture,catalog,["B03"],{"F03":1},dict(p,rain_hit=0),dict(a,rain_stay_probability=0),dummy,0,3)
    check("fixed rain does not track a departed target",r["raw_damage"]==0)
    r=simulate(critical,catalog,["P02"],{"F01":3},p,a,dummy*3,0,0.7)
    check("multi-bolt multi-enemy crit creates only one patch",r["item_events"].get("P02_patch",0)==1)
    c=ArtifactCombat(critical,catalog,["P02"],{"F01":1,"F05":1},p,a,dummy,0,3)
    c.q.clear();c.release("F05",True);r=c.run()
    check("zone critical hits cannot create patches",r["item_events"].get("P02_patch",0)==0)
    c=ArtifactCombat(critical,catalog,["P02"],{"F01":1},p,a,dummy,0,1)
    c.q.clear()
    with c.context(origin="book",natural=False):
        c.release("F01",False)
    r=c.run()
    check("extra direct crit cannot create patches",r["item_events"].get("P02_patch",0)==0 and r["natural_count"]==0)
    c=ArtifactCombat(fixture,catalog,["P02"],{"F01":1},p,a,dummy,0,3)
    c.q.clear()
    c.patches=[{"ids":[0],"first":0.5,"end":3,"aura":0},{"ids":[0],"first":0.5,"end":3,"aura":0.2}]
    c.time=0.5
    with c.context(origin="P02",natural=False):
        c.patch_tick();c.patch_tick()
    check("overlapping patches take highest aura, one tick",c.damage["P02"]==48)
    c=ArtifactCombat(fixture,catalog,["P03"],{"F03":1,"F05":1},p,a,dummy,0,3)
    c.q.clear()
    zone={"sid":"F05","ids":[0],"start":0,"end":2,"field_token":None}
    c.zones=[dict(zone),dict(zone)]
    c.deal("F03",0,1,0)
    check("two copies of same area don't resonate",c.damage["F03"]==100)
    c.zones[1]["sid"]="F03"
    c.deal("F03",0,1,0)
    check("two distinct areas add separate20percent vulnerability",c.damage["F03"]==220)
    c.time=2;c.deal("F03",0,1,0)
    check("vulnerability ends immediately on area expiry",c.damage["F03"]==320)
    r=simulate(fixture,catalog,["P04"],{"F01":1},p,a,dummy,0,20)
    check("book extra does not increment natural counts",sum(r["extra_casts"].values())==r["natural_count"]//3 and r["extra_by_origin"]["book"]==r["natural_count"]//3)
    c=ArtifactCombat(fixture,catalog,["P05"],{"F01":1},p,a,dummy,0,5)
    c.states["F01"]["ready"]=5;c.time=1
    c.event("fountain",None)
    check("fountain4s remaining becomes2s, not half base",c.states["F01"]["ready"]==3)
    build={"F01":1,"F03":1,"F04":1}
    r=simulate(fixture,catalog,["G01","P04"],build,p,a,dummy,0,20)
    offensive=sum(v for k,v in r["casts"].items() if k!="F04")
    check("echo excludes summon and all extra casts",r["item_events"]["G01_echo"]==offensive//3)
    results=[]
    for items in (["G02"],["G02","P01"]):
        results.append(simulate(fixture,catalog,items,{"F04":1,"F01":1,"F08":1},p,a,dummy,0,20))
    check("synced laser uses one shared cooldown across familiars",results[0]["item_events"]["G02_laser"]==results[1]["item_events"]["G02_laser"] and results[0]["item_events"]["G02_laser"]<=11)
    for level,targets in ((1,1),(3,3)):
        c=ArtifactCombat(fixture,catalog,["G02"],{"F04":level,"F01":1},p,a,dummy*3,0,0.1)
        c.q.clear();c.release("F04",True);c.release("F01",True);r=c.run()
        check(f"sync inherits familiar pierce only at level3, level {level}",r["by_spell"]["G02"]==100*catalog["items"]["G02"]["coefficient"]*targets)
    c=ArtifactCombat(fixture,catalog,["G03"],{"F06":1},p,a,dummy,0,4.01)
    c.q.clear();c.release("F06",True);r=c.run()
    check("natural field expiry one terminal explosion",r["by_spell"]["F06"]==320 and r["by_spell"]["G03"]==400 and r["item_events"]["G03_explosion"]==1)
    c=ArtifactCombat(fixture,catalog,["G03"],{"F06":1},p,a,dummy,0,6)
    c.q.clear();c.release("F06",True)
    with c.context(origin="book",natural=False):
        c.schedule(1,"extra","F06")
    r=c.run()
    check("field replacement cancels terminal, extra field cannot generate one",r["item_events"].get("G03_explosion",0)==0 and r["item_events"]["G03_cancelled_replacement"]==1)
    c=ArtifactCombat(fixture,catalog,["B05"],{"F05":1},p,a,dummy,0,4.4)
    r=c.run();c.time=3
    check("vortex slows once per enemy per cast, no tick refresh",r["item_events"]["B05_slow"]==1 and c.slow_at(0)==0)
    c=ArtifactCombat(fixture,catalog,["B09"],{"F09":1},p,a,dummy*3,0,0.3)
    r=c.run();c.time=0.21
    check("wave multi-hit grants one15percent speed boost",r["item_events"]["B09_speed"]==1 and abs(c.move_speed()-5.75)<1e-8)
    c.time=2.21
    check("speed ends after2s",c.move_speed()==5)
    return checks


def batch(base,catalog,s,legacy,name,owned,build,enemies,kind="ordinary",horizon=None,n=None,assumption_overrides=None,incoming=None):
    profile=legacy["profiles"][kind]
    assumptions=dict(s["assumptions"][kind],**(assumption_overrides or {}))
    seed=s["seed"]+zlib.crc32(name.encode())
    return [simulate(base,catalog,owned,build,profile,assumptions,enemies,seed+i,horizon or s["ttk_horizon"],incoming=incoming) for i in range(n or s["trials"])]


def summarize(name,results,**fields):
    return dict(name=name,**fields,n=len(results),mean_dps=statistics.mean(r["dps"] for r in results),median_s=statistics.median(r["time"] for r in results),p10_s=quantile([r["time"] for r in results],0.1),p90_s=quantile([r["time"] for r in results],0.9),timeouts=sum(r["status"]=="timeout" for r in results),max_events=max(r["event_count"] for r in results),max_events_per_natural=max(r["event_count"]/max(1,r["natural_count"]) for r in results),mean_item_events={k:statistics.mean(r["item_events"].get(k,0) for r in results) for k in set().union(*(r["item_events"] for r in results))})


def generic_budget(base,catalog,item_id,pattern,gain_room):
    hp=cap=base["player"]["health"]
    shield=base["player"]["shield"]
    elites={e["room"]:e for e in base["elites"]}
    bosses={e["room"]:e for e in base["bosses"]}
    rows=[]
    for room in range(1,61):
        current_shield=shield
        special=bosses.get(room) or elites.get(room)
        hits=pattern["boss_hits"] if room in bosses else pattern["elite_hits"] if special else pattern["normal_hits"]+bool(pattern["extra_every"] and room%pattern["extra_every"]==0)
        damages=list(special["attacks"].values()) if special else [normal_stats(base,"M01",room)["damage"]]
        for i in range(hits):
            hp,current_shield=receive_damage(hp,current_shield,damages[i%len(damages)])
            if hp<=0:break
        if hp<=0:
            return {"status":"dead","room":room,"health":0,"cap":cap,"rows":rows}
        if room==gain_room and item_id:
            item=catalog["items"][item_id]
            cap+=item.get("health_max_add",0)
            shield+=item.get("shield_max_add",0)
        if room in base["recovery"]["shop_after"]:
            cap+=base["recovery"]["shop_max_health_gain"]
            hp=min(cap,hp+cap*base["recovery"]["shop_fraction"])
        elif room in base["recovery"]["boss_after"]:
            hp=min(cap,hp+cap*base["recovery"]["boss_fraction"])
        rows.append({"room":room,"hp":hp,"cap":cap,"shield_cap":shield})
    return {"status":"clear","room":60,"health":hp,"cap":cap,"rows":rows}


def report(base,catalog,s,legacy,sweeps=True):
    rows=[]
    for item_id,item in catalog["items"].items():
        build=dict(PROBE)
        if item_id in ("B07","B09"):
            level=build.pop("F05")
            build[item["required_spell"]]=level
        for count in (1,3):
            label=f"single:{item_id}:{count}"
            enemies=[{"health":10**12} for _ in range(count)]
            assumptions={"geometry_benefit_capture":0} if count==1 else None
            plain=batch(base,catalog,s,legacy,label,[],build,enemies,horizon=s["output_horizon"],assumption_overrides=assumptions)
            with_item=batch(base,catalog,s,legacy,label,[item_id],build,enemies,horizon=s["output_horizon"],assumption_overrides=assumptions)
            row=summarize(label,with_item,kind="single_item",item=item_id,targets=count,build=build)
            row["baseline_dps"]=statistics.mean(r["dps"] for r in plain)
            row["damage_ratio"]=row["mean_dps"]/row["baseline_dps"]
            rows.append(row)
    for route_name,route in s["routes"].items():
        for boss in base["bosses"]:
            room=boss["room"]
            if route.get("build") and room!=60:
                continue
            build=route.get("build") or build_at(legacy["paths"][route["path"]],room)
            budget=sum(r<room for r in [6,12,15,21,30,39,45,51,57])
            owned=[k for k in route["items"] if eligible(base,build,catalog["items"][k])][:budget]
            kind="optimized" if route_name=="event_stack" else "ordinary"
            enemies=[dict(boss,boss=boss)]
            name=f"route:{route_name}:{room}"
            plain=batch(base,catalog,s,legacy,name,[],build,enemies,kind=kind)
            results=batch(base,catalog,s,legacy,name,owned,build,enemies,kind=kind)
            row=summarize(name,results,kind="route",route=route_name,room=room,owned=owned,build=build)
            row["baseline_median_s"]=statistics.median(r["time"] for r in plain)
            if room==60:
                lo,hi=s["targets"]["nine_item_final_boss_median_s"]
                row["status"]="below" if row["median_s"]<lo else "above" if row["median_s"]>hi or row["timeouts"] else "within"
            rows.append(row)
    # Legally eligible inventory upper bound, beyond nine chest choices; not an expected run.
    owned=[k for k,item in catalog["items"].items() if eligible(base,PROBE,item)]
    boss=base["bosses"][-1]
    upper=batch(base,catalog,s,legacy,"legal_inventory_upper_bound",owned,PROBE,[dict(boss,boss=boss)],kind="optimized",n=16)
    rows.append(summarize("legal_inventory_upper_bound",upper,kind="inventory_upper_bound",owned=owned))
    # Joint benefit differs from sum of individual benefits (crit->patch; familiar->sync).
    pairs={"crit_patch":["B02","P02"],"lamp_spirit":["B04","P01"],"spirit_sync":["P01","G02"],"book_echo":["P04","G01"],"book_terminal":["P04","G03"],"echo_terminal":["G01","G03"],"fountain_book":["P04","P05"]}
    for label,owned in pairs.items():
        out=batch(base,catalog,s,legacy,label,owned,PROBE,[{"health":10**12}],horizon=s["output_horizon"])
        row=summarize(label,out,kind="pair",owned=owned)
        plain=batch(base,catalog,s,legacy,label,[],PROBE,[{"health":10**12}],horizon=s["output_horizon"])
        row["baseline_dps"]=statistics.mean(x["dps"] for x in plain)
        row["damage_ratio"]=row["mean_dps"]/row["baseline_dps"]
        rows.append(row)
    pressure={}
    late=deepcopy(base)
    late["player"]["health"]+=len(base["recovery"]["shop_after"])*base["recovery"]["shop_max_health_gain"]
    pressure_build=dict(PROBE,F03=1,F10=3)
    for strength in ("light","heavy"):
        for label,owned in (("F10_only",[]),("defense_combo",s["pressure"]["items"])):
            name=f"pressure:{strength}:{label}"
            out=batch(late,catalog,s,legacy,name,owned,pressure_build,[{"health":10**12}],horizon=s["pressure"]["horizon"],incoming={"damage":s["pressure"][strength+"_damage"],"interval":s["pressure"]["interval"]})
            pressure[name]={"median_s":statistics.median(x["time"] for x in out),"p90_s":quantile([x["time"] for x in out],0.9),"survived_to_horizon":sum(x["status"]!="dead" for x in out),"trials":len(out),"median_shield_restored":statistics.median(x["shield_restored"] for x in out),"status":"pass" if strength=="light" or all(x["status"]=="dead" for x in out) else "warning"}
    budgets={key:generic_budget(base,catalog,key,legacy["attrition_patterns"]["ordinary"],s["generic_gain_room"]) for key in (None,"U01","U02","U03")}
    grid=[]
    if sweeps:
        axes=(("fountain_interval","P05","interval"),("echo_multiplier","G01","echo_damage_multiplier"),("synced_laser_coefficient","G02","coefficient"),("terminal_coefficient","G03","coefficient"))
        for axis,item,field in axes:
            for value in s["sweeps"][axis]:
                candidate=deepcopy(catalog)
                candidate["items"][item][field]=value
                for route_name,route in s["routes"].items():
                    if item not in route["items"]:continue
                    build=route.get("build") or build_at(legacy["paths"][route["path"]],60)
                    out=batch(base,candidate,s,legacy,"sweep:"+axis+":"+route_name,route["items"],build,[dict(boss,boss=boss)],kind="optimized" if route_name=="event_stack" else "ordinary",n=16)
                    grid.append(summarize(f"{axis}:{value}:{route_name}",out,kind="sweep",axis=axis,value=value,route=route_name))
    return {"metrics":rows,"pressure":pressure,"pressure_build":pressure_build,"generic_budgets":{str(k):v for k,v in budgets.items()},"sweeps":grid}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--catalog",type=Path,default=CATALOG)
    parser.add_argument("--out",type=Path,default=ROOT/"build/qa/fire-artifacts-20261017/selected")
    parser.add_argument("--trials",type=int)
    parser.add_argument("--no-sweep",action="store_true")
    args=parser.parse_args()
    base,raw_catalog,s,legacy=load(BASE),load(args.catalog),load(SCENARIOS),load(Path(__file__).with_name("scenarios.json"))
    catalog=resolve_catalog(base,raw_catalog)
    if args.trials:s["trials"]=args.trials
    if s["trials"]<2:parser.error("At least two trials")
    checks=validate_base(base,legacy)+validate_items(base,catalog,s,legacy)
    result=report(base,catalog,s,legacy,not args.no_sweep)
    result.update(model_version=ARTIFACT_MODEL_VERSION,base_version=base["version"],catalog_version=catalog["version"],base_sha256=hashlib.sha256(BASE.read_bytes()).hexdigest(),catalog_sha256=hashlib.sha256(args.catalog.read_bytes()).hexdigest(),catalog=catalog,raw_catalog=raw_catalog,scenarios=s,checks=checks,model_changes=["Base1.3 adds damage hooks; all115 previous no-item metrics and survival outputs remain identical.","Items1.1 supports a boosted first existing rain drop, third-level defense stress, and explicit level3 familiar pierce inheritance for synced lasers."],seed_rule="base_seed + crc32(comparison_name) + trial_index; paired parameter comparisons use same name",assumptions_and_omissions=["Approved base numbers unchanged; isolated tool only, not Godot implementation.","Fixed eligible item choices respect 2/6/9 chest opportunities before15/45/60; no reward RNG, shops, prices or guaranteed inventory.","Single-item tests compare same build and seed. Blue B07/B09 replace probe F05 with the required spell.","Geometry benefit interpolates explicit zero-to-uniform-density area/width assumptions; not measured movement, collision or coverage.","B03 removes scatter on first existing drop, still subject to supplied rain_stay_probability; no homing.","Slow/speed logged as state, not transformed into unmeasured damage avoidance or longer zone occupancy.","P03 uses supplied overlap fraction when two real spell-type zones are active; no physical position reconstruction.","Pressure encounters enter at full late-game400HP (+U01 if present). Generic acquisition budget increases cap without healing.","Upper inventory stress exceeds nine chest choices and is not an obtainable-build guarantee.","Model checks and seeded trials do not validate readability, fun, real survival rate or all future mechanics."])
    args.out.mkdir(parents=True,exist_ok=True)
    (args.out/"results.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
    (args.out/"catalog_used.json").write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding="utf-8")
    fields=["name","kind","item","targets","route","room","n","mean_dps","baseline_dps","damage_ratio","median_s","baseline_median_s","p90_s","status","max_events_per_natural"]
    with (args.out/"metrics.csv").open("w",encoding="utf-8-sig",newline="") as f:
        writer=csv.DictWriter(f,fieldnames=fields,extrasaction="ignore");writer.writeheader();writer.writerows(result["metrics"])
    print(json.dumps({"checks":len(checks),"metric_groups":len(result["metrics"]),"sweep_groups":len(result["sweeps"]),"routes":[{k:r[k] for k in ("route","room","owned","median_s","baseline_median_s")} for r in result["metrics"] if r["kind"]=="route"],"pressure":result["pressure"],"budgets":{k:{field:v[field] for field in ("status","room","health","cap")} for k,v in result["generic_budgets"].items()}},ensure_ascii=False,indent=2))


if __name__=="__main__":main()
