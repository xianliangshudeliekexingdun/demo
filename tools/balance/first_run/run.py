"""Reproducible first-pass balance reports. Uses only Python's standard library."""
from __future__ import annotations

import argparse
from collections import Counter
from copy import deepcopy
import csv
import hashlib
import json
from pathlib import Path
import statistics
import sys
import zlib

from model import Combat, MODEL_VERSION, attrition, build_at, choice_count, combat_stats, normal_stats, receive_damage, rounded_damage

ROOT = Path(__file__).resolve().parents[3]
PARAMETERS = ROOT / "data/balance_candidates/first_run_v1.json"
SCENARIOS = Path(__file__).with_name("scenarios.json")


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def quantile(values, fraction):
    values = sorted(values)
    i = (len(values)-1)*fraction
    low = int(i)
    return values[low] + (values[min(low+1,len(values)-1)]-values[low])*(i-low)


def validate(config, scenarios):
    checks = []
    def check(name, condition):
        if not condition:
            raise AssertionError(name)
        checks.append({"case": name, "status": "pass"})
    perfect = scenarios["profiles"]["perfect"]
    no_crit = deepcopy(config)
    no_crit["player"]["crit_rate"] = 0
    # Fixed hand fixtures are intentionally independent of selected actor stats.
    no_crit["player"]["attack"] = 100
    no_crit["player"]["fire_bonus"] = 0
    no_crit["spells"]["F01"].update(windup=0.15,cooldown=1.2,travel_delay=0.15)
    no_crit["spells"]["F01"]["levels"][0]["coefficient"] = 1.0
    no_crit["spells"]["F04"].update(windup=0.35,cooldown=12.0,duration=12.0)
    no_crit["spells"]["F04"]["levels"][0].update(coefficient=1.0,interval=1.25)
    no_crit["spells"]["F07"].update(windup=0.65,cooldown=6.0,travel_delay=0.45,aftershock_delay=0.6)
    no_crit["spells"]["F07"]["levels"][2].update(coefficient=6.5,outer=3.25,aftershock=1.5)
    dummy = [{"health": 10**12}]
    check("damage: 100*1*1.4*1.75*1.15 rounds once to 282", rounded_damage(100,1,0.4,1.75,0.15) == 282)
    check("shield overflow reaches HP exactly once", receive_damage(300,20,50) == (270,0))
    check("milestones exclude current-room reward", [choice_count(r) for r in (15,45,60)] == [6,16,21])
    for name, path in scenarios["paths"].items():
        for room in range(1,61):
            b = build_at(path,room)
            check(f"legal prefix {name} room {room}", len(b)<=config["limits"]["slots"] and max(b.values())<=config["limits"]["spell_level"] and sum(b.values())==choice_count(room))
    for name, profile in scenarios["profiles"].items():
        check(f"probabilities {name}", all(0 <= v <= 1 for k,v in profile.items() if k not in ("neighbor_candidates","wave_recheck_seconds")) and isinstance(profile["neighbor_candidates"],int) and profile["neighbor_candidates"]>=0 and profile["wave_recheck_seconds"]>0)
    for sid, spell in config["spells"].items():
        check(f"three levels {sid}", len(spell["levels"]) == 3)
        for row in spell["levels"]:
            check(f"finite nonnegative {sid} {len(checks)}", all(not isinstance(v,(int,float)) or (v >= 0 and v < float("inf")) for v in row.values()))
    c = Combat(no_crit,{"F01":1},perfect,[{"health":180}],0,10)
    result = c.run()
    check("hand anchor: two noncrit bolts kill 180 HP at 1.65s", result["casts"] == {"F01":2} and abs(result["time"]-1.65)<1e-7)
    c = Combat(no_crit,{"F04":1},perfect,dummy,0,12.34)
    r = c.run()
    check("spirit first waits 1.25s: nine shots before expiry", r["raw_damage"]==900 and r["casts"]["F04"]==1)
    c = Combat(no_crit,{"F04":1},perfect,dummy,0,12.71)
    r = c.run()
    check("spirit recast includes windup, no instant laser", r["casts"]["F04"]==2 and r["raw_damage"]==900)
    r = Combat(no_crit,{"F02":3},perfect,dummy,0,10).run()
    check("mastery neither casts nor deals damage", r["natural_count"]==0 and r["raw_damage"]==0)
    r = Combat(no_crit,{"F10":3},perfect,dummy,0,30).run()
    check("full shield does not start CD/count/cast", r["natural_count"]==0 and r["shield_restored"]==0)
    c = Combat(no_crit,{"F10":1},perfect,dummy,0,0.36)
    c.shield = 0
    r = c.run()
    check("broken shield can restore, HP unchanged", r["shield"]==min(no_crit["spells"]["F10"]["levels"][0]["shield"],no_crit["player"]["shield"]) and r["health"]==no_crit["player"]["health"] and r["natural_count"]==1)
    c = Combat(no_crit,{"F10":3},perfect,dummy,0,30)
    c.shield = 0
    r = c.run()
    check("restoration clipped to base shield cap", r["shield"]==no_crit["player"]["shield"] and r["shield_restored"]==no_crit["player"]["shield"])
    c = Combat(no_crit,{"F01":1},perfect,dummy,0,20,{"book":True})
    r = c.run()
    plain = Combat(no_crit,{"F01":1},perfect,dummy,0,20).run()
    check("book extra casts cannot recursively count", r["natural_count"]==plain["natural_count"] and sum(r["extra_casts"].values())==r["natural_count"]//3)
    c = Combat(no_crit,{"F01":1},perfect,dummy,0,10)
    c.states["F01"]["ready"] = 1.35
    c.flags["fountain_interval"] = 12
    c.time = 0.5
    c.event("fountain",None)
    check("fountain halves remaining CD, not base CD", abs(c.states["F01"]["ready"]-0.925)<1e-7)
    c.states["F01"]["casting"] = True
    c.states["F01"]["ready"] = 2.0
    c.event("fountain",None)
    check("fountain does not shorten active windup", c.states["F01"]["ready"]==2.0)
    r = Combat(no_crit,{"F01":1},perfect,dummy,0,20,{"fountain_interval":0.5}).run()
    check("stale CD events do not duplicate casts", r["casts"]["F01"]<40)
    c = Combat(no_crit,{"F05":1},perfect,dummy,0,5)
    c.time = 1
    packet = ("F05",[0],0.3,1,1,0,"vortex",0.5,None)
    c.event("damage",packet)
    c.event("damage",packet)
    check("same-source zone cannot double tick in one interval", c.damage["F05"]==30)
    c = Combat(no_crit,{"F06":1},perfect,dummy,0,5)
    c.field_token = 2
    c.event("damage",("F06",[0],0.25,1,1,0,"field",0.5,1))
    check("replaced field no longer deals damage", c.damage["F06"]==0)
    c = Combat(no_crit,{"F07":3},dict(perfect,bomb_center=0),dummy,0,2)
    r = c.run()
    check("regression: outer bomb 325 plus outer aftershock 75 = 400", r["raw_damage"]==400)
    c = Combat(no_crit,{"F10":1},perfect,dummy,0,1)
    c.shield = no_crit["player"]["shield"]-10
    c.event("try","F10")
    c.shield = no_crit["player"]["shield"]
    c.time = 0.35
    c.event("release","F10")
    check("shield filled during windup cancels without CD or count", c.natural_count==0 and c.states["F10"]["ready"]==0)
    boss = deepcopy(config["bosses"][2])
    boss["health"] = 1800
    p = dict(perfect, bolt_extra=0, add_priority=0)
    c = Combat(no_crit,{"F01":1},p,[dict(boss,boss=boss)],0,60)
    r = c.run()
    check("final boss finite adds, no mandatory add kill", r["status"]=="clear" and r["max_adds"]==2 and r["summon_groups"]==1 and sum(t.get("add",False) and t["hp"]>0 for t in c.targets)==2)
    check("three-fire passive+shield count once each", abs(combat_stats(config,{"F01":1,"F02":1,"F10":3})["fire"]-0.3)<1e-7)
    check("early normals have positive HP, no resistance field", normal_stats(config,"M01",1)["health"]>0 and "fire_resistance" not in normal_stats(config,"M01",1))
    empty = {"normal_hits":0,"extra_every":0,"elite_hits":0,"boss_hits":0}
    budget = attrition(config,empty)
    expected_max = config["player"]["health"]+len(config["recovery"]["shop_after"])*config["recovery"].get("shop_max_health_gain",0)
    check("five free inn growths occur once, no combat-room count change", budget["max_health"]==expected_max and len(budget["rows"])==60)
    for row in budget["rows"]:
        if row["room"] in config["recovery"]["shop_after"]:
            expected = min(row["max_health"],row["hp_before_heal"]+row["max_health"]*config["recovery"]["shop_fraction"])
            check(f"inn {row['room']}: raise cap then heal, no double refill", row["hp_close"]==expected)
    doomed = attrition(config,dict(empty,normal_hits=100))
    check("death cannot be undone by inn/boss healing", doomed["status"]=="dead" and doomed["room"]==1 and doomed["max_health"]==config["player"]["health"])
    gained = attrition(config,empty,attribute_rewards=True)
    check("stat artifact gains don't consume spell slots or repeat", gained["max_health"]==expected_max+config["attribute_artifact_candidates"]["health_max_flat"] and gained["rows"][-1]["shield_max"]==config["player"]["shield"]+config["attribute_artifact_candidates"]["shield_max_flat"])
    return checks


def summary(name, results, target=None, **fields):
    times = [r["time"] for r in results]
    median = statistics.median(times)
    timed_out = sum(r["status"] == "timeout" for r in results)
    status = "within"
    if target:
        status = "below" if median < target[0] else "above" if median > target[1] or timed_out else "within"
    return dict(name=name, **fields, n=len(results), mean_s=statistics.mean(times), median_s=median, p10_s=quantile(times,0.1), p90_s=quantile(times,0.9), mean_dps=statistics.mean(r["dps"] for r in results), mean_sem_s=statistics.stdev(times)/(len(times)**0.5) if len(times)>1 else None, timeouts=timed_out, target_s=target, status=status, max_adds=max(r["max_adds"] for r in results))


def batch(config, scenarios, name, build, profile, enemies, horizon=None, flags=None, n=None, incoming=None):
    n = n or scenarios["trials"]
    base = scenarios["seed"] + zlib.crc32(name.encode("utf-8"))
    return [Combat(config,build,profile,enemies,base+i,horizon or scenarios["horizon"],flags,incoming).run() for i in range(n)]


def reports(config, scenarios, with_sweep=True):
    rows, raw_stress = [], []
    ordinary = scenarios["profiles"]["ordinary"]
    # Infinite-health output tests reveal startup, cooldown and duration effects.
    for sid in config["spells"]:
        if sid in ("F02","F10"):
            continue
        for level in (1,2,3):
            name = f"output:{sid}:{level}"
            r = batch(config,scenarios,name,{sid:level},ordinary,[{"health":10**12}],scenarios["output_window"])
            rows.append(summary(name,r,kind="spell_output",spell=sid,level=level))
    starter = []
    for sid in ("F01","F04","F08"):
        name = f"starter:{sid}"
        r = batch(config,scenarios,name,{sid:1},ordinary,[{"health":10**12}],scenarios["output_window"])
        starter.append(summary(name,r,kind="starter",spell=sid))
    rows.extend(starter)
    starter_ratio = max(r["mean_dps"] for r in starter)/min(r["mean_dps"] for r in starter)
    for sid in ("F01","F04","F08"):
        boss = config["bosses"][0]
        name = "two_types_no_synergy:"+sid
        r = batch(config,scenarios,name,{sid:3,"F10":3},ordinary,[dict(boss,boss=boss)])
        rows.append(summary(name,r,[35.0,110.0],kind="two_type_boundary",spell=sid,room=15))
    edge_build = {"F01":3,"F02":3,"F03":3,"F04":3,"F05":3,"F08":3,"F06":2,"F10":1}
    name = "eight_slots_21_choices"
    boss = config["bosses"][2]
    r = batch(config,scenarios,name,edge_build,scenarios["profiles"]["optimized"],[dict(boss,boss=boss)])
    rows.append(summary(name,r,[22.0,90.0],kind="eight_slot_boundary",room=60,build=edge_build))
    for path_name, path in scenarios["paths"].items():
        profile = scenarios["profiles"][path["profile"]]
        for boss in config["bosses"]:
            room = boss["room"]
            build = build_at(path,room)
            name = f"boss:{room}:{path_name}"
            r = batch(config,scenarios,name,build,profile,[dict(boss,boss=boss)])
            segment = path_name if path_name in ("weak","optimized") else "ordinary"
            rows.append(summary(name,r,scenarios["targets"]["boss_"+segment][str(room)],kind="boss",room=room,path=path_name,build=build))
        for elite in config["elites"]:
            room = elite["room"]
            enemies = [elite] + [normal_stats(config,k,room) for k in elite["adds"]]
            name = f"elite:{room}:{path_name}"
            r = batch(config,scenarios,name,build_at(path,room),profile,enemies)
            rows.append(summary(name,r,scenarios["targets"]["elite"],kind="elite",room=room,path=path_name))
        for bench in scenarios["normal_benchmarks"]:
            room = bench["room"]
            enemies = [normal_stats(config,k,room) for k in bench["enemies"]]
            name = f"normal:{room}:{path_name}"
            r = batch(config,scenarios,name,build_at(path,room),profile,enemies)
            rows.append(summary(name,r,scenarios["targets"]["normal"],kind="normal",room=room,path=path_name))
    h = scenarios["stress_hypotheses_not_item_balance"]
    late_build = build_at(scenarios["paths"]["spirit"],60)
    flags = {"book":True,"fountain_interval":h["fountain_interval"],"shield_bonus":h["shield_bonus"],"spirit_extra":h["spirit_extra"]}
    stress_results = {}
    for label, f in (("shield_only",{}),("shield_book_fountain_stress",flags)):
        results = batch(config,scenarios,label,late_build,ordinary,[{"health":10**12}],h["horizon"],f,incoming={"damage":h["incoming_damage"],"interval":h["incoming_interval"]})
        stress_results[label] = dict(median_survival_s=statistics.median(r["time"] for r in results),survived=sum(r["status"]!="dead" for r in results),trials=len(results),median_shield_restored=statistics.median(r["shield_restored"] for r in results),max_extra_casts=max(sum(r["extra_casts"].values()) for r in results),status="pass" if all(r["status"]=="dead" for r in results) else "warning")
        raw_stress.extend(dict(scenario=label,trial=i,**r) for i,r in enumerate(results))
    # One extra familiar is a fixed-rule mechanic; no unknown damage item bonus.
    for path_name in ("spirit","optimized"):
        path = scenarios["paths"][path_name]
        for boss in config["bosses"]:
            build = build_at(path,boss["room"])
            name = f"extra_spirit:{boss['room']}:{path_name}"
            r = batch(config,scenarios,name,build,scenarios["profiles"][path["profile"]],[dict(boss,boss=boss)],flags={"spirit_extra":1})
            rows.append(summary(name,r,kind="extra_spirit",room=boss["room"],path=path_name))
    stronger = deepcopy(config)
    stronger["player"]["attack"] += config["attribute_artifact_candidates"]["attack_flat"]
    for path_name in ("burst","spirit","area"):
        path = scenarios["paths"][path_name]
        boss = config["bosses"][2]
        name = f"stat_attack:60:{path_name}"
        r = batch(stronger,scenarios,name,build_at(path,60),scenarios["profiles"][path["profile"]],[dict(boss,boss=boss)])
        rows.append(summary(name,r,kind="stat_attack",room=60,path=path_name))
    budgets = {name:attrition(config,p) for name,p in scenarios["attrition_patterns"].items()}
    budgets["ordinary_skip_shops"] = attrition(config,scenarios["attrition_patterns"]["ordinary"],True)
    no_growth = deepcopy(config)
    no_growth["recovery"]["shop_max_health_gain"] = 0
    budgets["ordinary_no_inn_growth"] = attrition(no_growth,scenarios["attrition_patterns"]["ordinary"])
    budgets["ordinary_stat_artifacts"] = attrition(config,scenarios["attrition_patterns"]["ordinary"],attribute_rewards=True)
    for path_name in ("burst","spirit","area"):
        path = scenarios["paths"][path_name]
        budgets["ordinary_F10_"+path_name] = attrition(config,scenarios["attrition_patterns"]["ordinary"],path=path,profile=scenarios["profiles"][path["profile"]],durations=scenarios["attrition_timing"],seed=scenarios["seed"])
        clustered = dict(scenarios["attrition_timing"],hit_cluster_spacing=scenarios["attrition_cluster_spacing"])
        budgets["ordinary_F10_cluster_"+path_name] = attrition(config,scenarios["attrition_patterns"]["ordinary"],path=path,profile=scenarios["profiles"][path["profile"]],durations=clustered,seed=scenarios["seed"])
    sweeps = []
    if with_sweep:
        for scale in scenarios["sweeps"]["boss_health_scales"]:
            for path_name in ("burst","spirit","area","weak","optimized"):
                path = scenarios["paths"][path_name]
                for boss in config["bosses"]:
                    candidate = dict(boss,health=boss["health"]*scale)
                    name = f"hp_sweep:{scale}:{boss['room']}:{path_name}"
                    r = batch(config,scenarios,name,build_at(path,boss["room"]),scenarios["profiles"][path["profile"]],[dict(candidate,boss=candidate)],n=16)
                    segment = path_name if path_name in ("weak","optimized") else "ordinary"
                    sweeps.append(summary(name,r,scenarios["targets"]["boss_"+segment][str(boss["room"])],kind="boss_hp",scale=scale,room=boss["room"],path=path_name))
        for hit in scenarios["sweeps"]["direct_hit_values"]:
            boss = config["bosses"][2]
            path = scenarios["paths"]["burst"]
            profile = dict(ordinary,direct_hit=hit)
            name = f"accuracy_sweep:{hit}"
            r = batch(config,scenarios,name,build_at(path,60),profile,[dict(boss,boss=boss)],n=32)
            sweeps.append(summary(name,r,kind="direct_accuracy",direct_hit=hit))
        for shield in scenarios["sweeps"]["shield_values"]:
            c = deepcopy(config)
            c["player"]["shield"] = shield
            outcome = attrition(c,scenarios["attrition_patterns"]["ordinary"])
            sweeps.append(dict(kind="shield_budget",shield=shield,status=outcome["status"],room=outcome["room"],health=outcome["health"]))
        for gain in scenarios["sweeps"]["shop_max_health_gains"]:
            c = deepcopy(config)
            c["recovery"]["shop_max_health_gain"] = gain
            outcome = attrition(c,scenarios["attrition_patterns"]["ordinary"])
            sweeps.append(dict(kind="inn_growth",gain=gain,status=outcome["status"],room=outcome["room"],health=outcome["health"],max_health=outcome["max_health"]))
    return {
        "metrics_by_scenario": rows,
        "starter_ratio": starter_ratio,
        "starter_ratio_guardrail": "pass" if starter_ratio <= scenarios["targets"]["starter_dps_ratio_max"] else "fail",
        "shield_stress": stress_results,
        "stress_raw": raw_stress,
        "attrition": budgets,
        "sensitivity_or_sweep_summary": sweeps,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config",type=Path,default=PARAMETERS)
    parser.add_argument("--scenarios",type=Path,default=SCENARIOS)
    parser.add_argument("--out",type=Path,default=ROOT/"build/qa/first-run-balance-20261017/selected")
    parser.add_argument("--set",action="append",default=[],metavar="DOT.PATH=JSON",help="e.g. player.shield=120")
    parser.add_argument("--trials",type=int)
    parser.add_argument("--no-sweep",action="store_true")
    args = parser.parse_args()
    config, scenarios = load(args.config), load(args.scenarios)
    for assignment in args.set:
        key,value = assignment.split("=",1)
        node = config
        parts = key.split(".")
        for part in parts[:-1]:
            node = node[int(part)] if isinstance(node,list) else node[part]
        if isinstance(node,list):
            node[int(parts[-1])] = json.loads(value)
        else:
            node[parts[-1]] = json.loads(value)
    if args.trials:
        scenarios["trials"] = args.trials
    if scenarios["trials"] < 2:
        parser.error("at least two trials are required")
    checks = validate(config,scenarios)
    result = reports(config,scenarios,not args.no_sweep)
    result.update({
        "model_version": MODEL_VERSION, "game_or_config_version": config["version"],
        "model_validation_cases": checks,
        "model_changes": ["1.1 adds newly confirmed free inn max-HP growth, stat-artifact comparison and timed F10 mistakes-budget comparison.","1.2 fixes F07 outer aftershock center/edge selection; regression expects outer main 325 + outer aftershock 75 = 400. Adds clustered-hit sensitivity; do not use old uncorrected F07 results for parameter comparisons."],
        "parameters": config, "scenarios": scenarios,
        "config_sha256": hashlib.sha256(args.config.read_bytes()).hexdigest(),
        "targets_and_guardrails": scenarios["targets"],
        "seed_and_trial_count": {"seed":scenarios["seed"],"trials":scenarios["trials"],"sweep_trials":16,"seed_rule":"base_seed + crc32(scenario_name) + trial_index"},
        "assumptions_and_omissions": [
            "Design candidate; current game does not load these numbers; no runtime fidelity claim.",
            "Fixed legal reward paths, not reward-pool RNG or estimates of obtaining a build.",
            "Abstract accuracy, locked target cohorts and coverage; no navigation, collision, line-of-sight or enemy attack AI.",
            "Every encounter starts with spells ready; no claim about cross-room cooldown/summon persistence.",
            "F06 buff occupancy/grace abstracted by supplied aura_stay; its own damage does not self-buff.",
            "Final boss finite adds and core-target diversion modeled; enemy phase attack timing not modeled.",
            "Survival uses scripted mistakes/intervals, never estimated player survival probability.",
            "F10 budget uses supplied room durations (12/25/50-80s) and evenly timed effective hits, not simulated enemy AI or a predicted campaign.",
            "Cluster sensitivity puts effective hits 1.5s apart; the difference shows why a fixed mistake count cannot establish difficulty.",
            "Stat-artifact comparison deliberately grants HP/shield/attack at 6/12/21; acquisition is not guaranteed and rarity/economy not designed.",
            "No gems, artifacts, resistances or armor in base TTK. +1 familiar tested separately.",
            "Book/fountain/shield bonus stress uses explicitly provisional item hypotheses, no other event artifacts.",
            "AoE cohort contains primary+2 possible neighbors as benchmark density; not an in-game hit cap.",
        ],
    })
    args.out.mkdir(parents=True,exist_ok=True)
    (args.out/"results.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
    (args.out/"parameters_used.json").write_text(json.dumps(config,ensure_ascii=False,indent=2),encoding="utf-8")
    (args.out/"scenarios_used.json").write_text(json.dumps(scenarios,ensure_ascii=False,indent=2),encoding="utf-8")
    fields = ["name","kind","room","path","spell","level","n","mean_s","median_s","p10_s","p90_s","mean_dps","mean_sem_s","timeouts","status","max_adds"]
    with (args.out/"metrics.csv").open("w",encoding="utf-8-sig",newline="") as f:
        writer = csv.DictWriter(f,fieldnames=fields,extrasaction="ignore")
        writer.writeheader()
        writer.writerows(result["metrics_by_scenario"])
    failures = [r for r in result["metrics_by_scenario"] if r["status"]!="within"]
    print(json.dumps({"model_version":MODEL_VERSION,"checks_passed":len(checks),"scenarios":len(result["metrics_by_scenario"]),"starter_ratio":round(result["starter_ratio"],3),"starter_guardrail":result["starter_ratio_guardrail"],"target_misses":[{k:r.get(k) for k in ("name","median_s","status")} for r in failures],"bosses":[{k:r[k] for k in ("room","path","median_s","p90_s","status")} for r in result["metrics_by_scenario"] if r["kind"]=="boss"],"shield_stress":result["shield_stress"],"attrition":{k:{key:v[key] for key in ("status","room","health")} for k,v in result["attrition"].items()},"output":str(args.out)},ensure_ascii=False,indent=2))
    # Target warnings remain reviewable, but model validity and core guardrails fail loudly.
    return 0 if result["starter_ratio_guardrail"]=="pass" and all(r["status"]=="pass" for r in result["shield_stress"].values()) else 2


if __name__ == "__main__":
    sys.exit(main())
