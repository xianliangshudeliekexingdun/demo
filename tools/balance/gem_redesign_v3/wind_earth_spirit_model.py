"""Proposal-only deterministic event envelopes, never the game's combat engine.

Loads current source spell levels/cast clocks, but prescribes legal contacts,
movement, proximity and LOS. No enemy AI, natural route, hit-rate prediction,
save mutation, rendering, or performance claims. Persistent tuning tool.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
EPS = 1e-8


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def near(a, b):
    return abs(a - b) < 1e-6


def cyc(spell, level, cdr):
    values = spell["levels"][level - 1]
    return float(spell["windup"]) + max(0.2, float(values["cooldown"]) * (1 - min(0.6, cdr)))


def cast_times(spell, level, cdr, horizon):
    at = float(spell["windup"])
    while at <= horizon + EPS:
        yield at
        at += cyc(spell, level, cdr)


def wind_coeff(spell_id, level, targets, data):
    p = data["spells"][spell_id]["levels"][level - 1]
    if spell_id == "W01":
        return sum(float(p["coefficient"]) * float(p["falloff"]) ** i for i in range(min(targets, p["target_cap"])))
    if spell_id == "W02":
        return (float(p["out_coefficient"]) + float(p["return_coefficient"])) * min(targets, p["leg_target_cap"])
    if spell_id == "W03":
        return float(p["coefficient"])  # No assumed 4m long-flight condition.
    if spell_id == "W05":
        return float(p["coefficient"]) * round(float(p["duration"]) / float(p["interval"])) * targets
    if spell_id == "W07":
        return float(p["coefficient"]) * 2 * min(targets, p["target_cap"])
    raise ValueError(f"Unmodeled wind source {spell_id}")


def wind_model(p, source, ids, level=1, cdr=0.0, move_duty=1.0, speed=5.0, targets=1, horizon=30.0):
    events = []
    for spell_id in ids:
        for at in cast_times(source["spells"][spell_id], level, cdr, horizon):
            events.append((at, spell_id, wind_coeff(spell_id, level, targets, source)))
    events.sort()
    charge = 0
    remainder = 0.0
    last_cast = float("-inf")
    stop_age = 0.0
    decay_count = 0
    event_index = 0
    base = extra = 0.0
    spent = gained = 0
    dt = 1.0 / 120.0
    trace = []
    for tick in range(round(horizon / dt) + 1):
        now = tick * dt
        moving = speed > 0 and (now % 4.0) < 4.0 * move_duty - EPS
        flow_valid = moving and now - last_cast <= p["successful_cast_memory_s"] + EPS
        if moving and (flow_valid or not p.get("decay_after_flow_loss",False)):
            stop_age = 0.0
            decay_count = 0
            if now - last_cast <= p["successful_cast_memory_s"] + EPS:
                remainder += speed * dt
                while remainder + EPS >= p["distance_per_charge_m"]:
                    remainder -= p["distance_per_charge_m"]
                    if charge < p["charge_cap"]:
                        charge += 1
                        gained += 1
                    else:
                        remainder = 0.0
                        break
        else:
            stop_age += dt
            # r2: first loss exactly at 0.5s of stopped motion/expired flow;
            # r1's archived policy used one additional interval after grace.
            if p.get("decay_after_flow_loss",False):
                due = 0 if stop_age + EPS < p["stop_grace_s"] else 1 + int((stop_age - p["stop_grace_s"] + EPS) / p["charge_decay_interval_s"])
            else:
                due = max(0, int((stop_age - p["stop_grace_s"] + EPS) / p["charge_decay_interval_s"]))
            if due > decay_count:
                charge = max(0, charge - (due - decay_count))
                remainder = 0.0
                decay_count = due
        while event_index < len(events) and events[event_index][0] <= now + EPS:
            at, spell_id, coeff = events[event_index]
            base += coeff
            extra += coeff * charge * p["damage_bonus_per_charge"]
            if len(trace) < 12:
                trace.append({"at": round(at, 4), "spell": spell_id, "spent": charge})
            if p.get("consume_on_cast",True):
                spent += charge
                charge = 0
            last_cast = at
            event_index += 1
    return dict(base_coefficient=base, extra_coefficient=extra, gain_fraction=extra / base if base else 0,
                casts=len(events), charges_gained=gained, charges_spent=spent, remaining_charges=charge,
                trace=trace, geometry_gain_unvalued=True)


def earth_model(p, source, ids=("R03",), level=1, cdr=0, proximity_duty=1.0, targets=1, horizon=30.0, consume_every=None):
    """Construct lifecycles/first pulses modeled; contacts/LOS are prescribed.

    R03 main damage and R04 discrete normal pulses form the stated baseline.
    Other Earth spells are deliberately not approximated into this envelope.
    """
    births = []
    base = 0.0
    for spell_id in ids:
        s = source["spells"][spell_id]
        v = s["levels"][level - 1]
        for at in cast_times(s, level, cdr, horizon):
            born = at + float(v.get("delay", 0.0))
            if born > horizon + EPS:
                continue
            duration = float(v.get("construct_duration", v.get("duration", 0)))
            births.append((born, spell_id, duration))
            if spell_id == "R03":
                base += float(v["main"]) * targets
                if v["after"] and born + float(v["after_delay"]) <= horizon + EPS:
                    base += float(v["after"]) * targets
    births.sort()
    active = {}
    next_birth = 0
    serial = 0
    selected = None
    dwell = outside = 0.0
    next_pulse = None
    pulses = 0
    extra = 0.0
    trace = []
    dt = 1.0 / 120
    consume_at = float(consume_every) if consume_every else float("inf")
    for tick in range(round(horizon / dt) + 1):
        now = tick * dt
        inside = (now % 6.0) < 6.0 * proximity_duty - EPS
        # Existing authoritative construct ticks/pulses precede expiration.
        for construct in list(active.values()):
            if construct["spell"] == "R04" and now + EPS >= construct["next_tick"] and construct["next_tick"] <= min(now, construct["expires"]) + EPS:
                vals = source["spells"]["R04"]["levels"][level - 1]
                base += float(vals["tick"]) * targets
                construct["next_tick"] += float(vals["interval"])
        if selected in active and next_pulse is not None and now + EPS >= next_pulse:
            if inside:
                pulses += 1
                extra += p["pulse_coefficient"] * min(targets, p["pulse_target_cap"])
                trace.append(round(now, 4))
            next_pulse += p["pulse_interval_s"]
        for key in list(active):
            if active[key]["expires"] <= now + EPS:
                del active[key]
        # Controlled consumer removes the selected real source, not all sources.
        if now + EPS >= consume_at:
            active.pop(selected, None)
            consume_at += float(consume_every)
        while next_birth < len(births) and births[next_birth][0] <= now + EPS:
            at, spell_id, duration = births[next_birth]
            for key in list(active):
                if active[key]["spell"] == spell_id:
                    del active[key]
            serial += 1
            vals = source["spells"][spell_id]["levels"][level - 1]
            active[serial] = dict(spell=spell_id, expires=at + duration, next_tick=at + float(vals.get("first_tick", 99999)))
            next_birth += 1
        if selected not in active:
            selected = None
            dwell = 0.0
            next_pulse = None
        if inside:
            outside = 0.0
            just_selected = False
            if selected is None and active:
                selected = min(active)  # All scenario anchors at equal declared distance.
                just_selected = True
            if selected is not None and next_pulse is None:
                if not just_selected:
                    dwell += dt
                if dwell + EPS >= p["mature_after_s"]:
                    pulses += 1
                    extra += p["pulse_coefficient"] * min(targets, p["pulse_target_cap"])
                    trace.append(round(now, 4))
                    next_pulse = now + p["pulse_interval_s"]
        else:
            outside += dt
            if outside > p["leave_grace_s"] + EPS:
                selected = None
                dwell = 0.0
                next_pulse = None
    return dict(base_coefficient=base, extra_coefficient=extra, gain_fraction=extra / base if base else None,
                pulse_count=pulses, pulses_at=trace, targets_per_pulse=min(targets, p["pulse_target_cap"]),
                note="Consumer scenario excludes R06's own damage, so its ratio is only loss of the source-core contribution.")


def spirit_actions(source, ids, level, cdr, horizon, targets):
    events = []
    for sid in ids:
        s = source["spells"][sid]
        p = s["levels"][level - 1]
        birth = float(s["windup"])
        lifetime = float(p["duration"])
        period = max(lifetime, float(p["cooldown"]) * (1 - min(0.6, cdr))) + float(s["windup"])
        serial = 0
        while birth <= horizon + EPS:
            for index in range(int(p["capacity"])):
                uid = f"{sid}-{serial}-{index}"
                events.append((birth, 2, uid, "birth", {}))
                end = birth + lifetime
                at = birth + float(p["attack_delay"])
                aid = 0
                while at <= min(end, horizon) + EPS:
                    events.append((at, 0, uid, "attack", {"family":s["summon_family"],"coefficient":float(p["coefficient"]),"contacts":min(targets,int(p["target_cap"])),"attack_id":aid}))
                    aid += 1
                    at += float(p["attack_interval"])
                events.append((end, 1, uid, "expire", {}))
            serial += 1
            birth += period
    return sorted(events)


def concord(actions, p, crit_rate=0, crit_multiplier=1.5, legal_duty=1.0):
    charge = 0
    ready = False
    last_family = None
    last_hit = float("-inf")
    base = extra = 0.0
    procs = successes = 0
    live = set()
    peak = 0
    for at, _, uid, kind, event in actions:
        if kind == "birth":
            live.add(uid)
            peak = max(peak,len(live))
            continue
        if kind == "expire":
            live.discard(uid)
            if not live:
                charge,ready,last_family = 0,False,None
            continue
        if at - last_hit > p["idle_reset_s"] + EPS:
            charge,ready,last_family = 0,False,None
        if at % 5.0 >= legal_duty * 5.0 - EPS:
            continue
        coeff = event["coefficient"] * event["contacts"]
        base += coeff * (1 + crit_rate * (crit_multiplier - 1))
        successes += 1
        family = event["family"]
        if ready:
            extra += coeff * p["enhanced_action_extra_noncritical_fraction"]
            procs += 1
            charge,ready = 0,False
        else:
            charge += p["gain_per_successful_normal_action"]
            if last_family is not None and family != last_family:
                charge += p["different_family_extra_gain"]
            charge = min(charge,p["charge_threshold"])
            ready = charge >= p["charge_threshold"]
        last_family,last_hit = family,at
    return dict(base_coefficient=base,extra_coefficient=extra,gain_fraction=extra/base if base else 0,
                enhanced_actions=procs,successful_actions=successes,peak_units=peak,remaining_charge=charge)


def run(params, sources):
    horizon = params["horizon_seconds"]
    scenarios = {}
    wind_cases = [
        ("wind_stationary",["W01"],1,0,0,5,1),
        ("wind_wall_zero_motion",["W01"],1,0,1,0,1),
        ("wind_starter_continuous",["W01"],1,0,1,5,1),
        ("wind_ordinary",["W01","W03","W05"],2,0.1,0.65,5,1),
        ("wind_optimized_boss",["W01","W02","W03","W07"],3,0.4,0.9,5,1),
        ("wind_optimized_group",["W01","W02","W03","W07"],3,0.4,0.9,5,4),
        ("wind_high_cdr",["W01","W02","W03","W05","W07"],3,0.6,1,5,4),
    ]
    for name,ids,level,cdr,duty,speed,targets in wind_cases:
        scenarios[name] = wind_model(params["wind"],sources["wind"],ids,level,cdr,duty,speed,targets,horizon)
    for name,ids,level,cdr,duty,targets,consume in [
        ("earth_no_source",[],1,0,1,1,None),
        ("earth_starter_anchor",["R03"],1,0,1,1,None),
        ("earth_ordinary",["R03","R04"],2,0.1,0.65,1,None),
        ("earth_optimized_boss",["R03","R04"],3,0.3,1,1,None),
        ("earth_optimized_group",["R03","R04"],3,0.3,1,4,None),
        ("earth_high_cdr_replacement",["R03","R04"],3,0.6,1,1,None),
        ("earth_forced_movement",["R03","R04"],2,0.1,0.25,1,None),
        ("earth_frequent_consumption",["R03","R04"],3,0.3,1,1,2.0),
    ]:
        scenarios[name] = earth_model(params["earth"],sources["earth"],ids,level,cdr,duty,targets,horizon,consume)
    for name,ids,level,cdr,targets,legal,crit in [
        ("spirit_no_pet",[],1,0,1,1,0),
        ("spirit_single_starter",["S02"],1,0,1,1,0.05),
        ("spirit_single_melee",["S03"],1,0,1,1,0.05),
        ("spirit_two_same_family",["S02"],3,0.1,1,1,0.05),
        ("spirit_ordinary_two_families",["S02","S03"],2,0.1,1,0.8,0.05),
        ("spirit_optimized_boss",["S02","S03","S04"],3,0.3,1,1,0.2),
        ("spirit_optimized_group",["S02","S03","S04"],3,0.3,4,1,0.2),
        ("spirit_los_downtime",["S02","S03"],2,0.1,1,0.2,0.05),
    ]:
        scenarios[name] = concord(spirit_actions(sources["spirit"],ids,level,cdr,horizon,targets),params["spirit"],crit,1.5,legal)
    return scenarios


def checks(params,sources):
    results=[]
    def check(value,label):
        results.append({"name":label,"passed":bool(value)})
    check(near(cyc(sources["wind"]["spells"]["W01"],1,0),1.35),"current W01 windup+CD hand case 0.15+1.2=1.35")
    check(near(cyc(sources["earth"]["spells"]["R03"],1,0),4.35),"current R03 cycle hand case 0.35+4=4.35")
    spirit=params["spirit"]
    threshold=spirit["charge_threshold"]
    gain=spirit["gain_per_successful_normal_action"]
    switch_gain=gain+spirit["different_family_extra_gain"]
    same_procs=100//(math.ceil(threshold/gain)+1)
    first_mixed_fill=1+math.ceil(max(0,threshold-gain)/switch_gain)
    mixed_cycle=math.ceil(threshold/switch_gain)+1
    mixed_procs=0 if first_mixed_fill>=100 else 1+(99-first_mixed_fill)//mixed_cycle
    for family_alternates, expected in [(False,same_procs*spirit["enhanced_action_extra_noncritical_fraction"]),(True,mixed_procs*spirit["enhanced_action_extra_noncritical_fraction"])]:
        actions=[(float(i)*0.5,0,"u","attack",{"family":"a" if not family_alternates or i%2==0 else "b","coefficient":1.0,"contacts":1}) for i in range(100)]
        actual=concord(actions,params["spirit"])
        check(near(actual["extra_coefficient"],expected),f"100 normal actions concord hand case alternating={family_alternates}")
    zero=wind_model(params["wind"],sources["wind"],["W01"],move_duty=0)
    check(zero["extra_coefficient"]==0,"stationary wind earns no core damage")
    check(wind_model(params["wind"],sources["wind"],["W01"],speed=0)["extra_coefficient"]==0,"wall input with zero actual path earns no charges")
    check(earth_model(params["earth"],sources["earth"],ids=[])["pulse_count"]==0,"no actual construct gives no earth pulses")
    first_anchor=earth_model(params["earth"],sources["earth"],ids=["R03"],horizon=3)
    expected_first=float(sources["earth"]["spells"]["R03"]["windup"])+float(sources["earth"]["spells"]["R03"]["levels"][0]["delay"])+params["earth"]["mature_after_s"]
    check(near(first_anchor["pulses_at"][0],expected_first),"R03 impact + configured maturity hand case; default 0.35+0.3+1.5=2.15, no inclusive tick credit")
    scenarios=run(params,sources)
    for name,result in scenarios.items():
        check(result["base_coefficient"]>=0 and result["extra_coefficient"]>=0,name+" nonnegative damage envelope")
        if name.startswith("spirit"):
            check(result["peak_units"]<=4,name+" keeps current four-unit cap")
            check(0<=result["remaining_charge"]<=params["spirit"]["charge_threshold"],name+" bounded cooperation")
        if name.startswith("wind"):
            check(0<=result["remaining_charges"]<=params["wind"]["charge_cap"],name+" bounded wind charges")
            check(result["charges_spent"]<=result["charges_gained"],name+" wind resource conservation")
    return results


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--parameters",type=Path,default=HERE/"wind_earth_spirit_parameters.json")
    parser.add_argument("--output",type=Path,default=ROOT/"build/qa/gem-redesign-v3-20261022/wind-earth-spirit")
    args=parser.parse_args()
    output=args.output.resolve()
    if not output.is_relative_to((ROOT/"build/qa").resolve()):
        parser.error("Output must stay within D:/demo/build/qa")
    output.mkdir(parents=True,exist_ok=True)
    params=read(args.parameters)
    sources={school:read(ROOT/"data"/(school+"_spells_v1.json")) for school in ["wind","earth","spirit"]}
    validation=checks(params,sources)
    scenarios=run(params,sources)
    sweeps={}
    for school,key,values in [("wind","damage_bonus_per_charge",params["sweeps"]["wind_damage_per_charge"]),("earth","pulse_coefficient",params["sweeps"]["earth_pulse_coefficient"]),("spirit","enhanced_action_extra_noncritical_fraction",params["sweeps"]["spirit_extra_fraction"])]:
        sweeps[school]=[]
        for value in values:
            candidate=copy.deepcopy(params)
            candidate[school][key]=value
            rows=run(candidate,sources)
            sweeps[school].append({"parameter":key,"value":value,"gains":{name:r["gain_fraction"] for name,r in rows.items() if name.startswith(school)}})
    baseline=copy.deepcopy(params)
    baseline["wind"]["damage_bonus_per_charge"]=0
    baseline["earth"]["pulse_coefficient"]=0
    baseline["spirit"]["enhanced_action_extra_noncritical_fraction"]=0
    current_stats=read(ROOT/"data/magic_gems_v1.json")
    paths=[args.parameters,Path(__file__),ROOT/"data/magic_gems_v1.json"]+[ROOT/"data"/(s+"_spells_v1.json") for s in sources]+[ROOT/"scripts/core"/("route_"+s+"_combat.gd") for s in sources]
    hashes={str(p.resolve().relative_to(ROOT)).replace("\\","/"):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    warnings=[]
    for name,r in scenarios.items():
        gain=r["gain_fraction"]
        if gain is not None and gain>0.45:
            warnings.append(name+" exceeds ordinary +45% anchor; preserves conditional/source limitation, requires later play validation")
        if "ordinary" in name and gain is not None and gain<0.20:
            warnings.append(name+" below +20% tuning anchor; retain explicit setup/coverage limitation rather than call it passed")
    report=dict(model_version="wes-event-envelope-1.2",proposal_version=params["version"],status="proposal_not_game_implementation",
                model_changes=["1.1: fixed one inclusive tick of false maturity on first selecting an anchor; regression verifies R03 0.65s impact +1.5s dwell =2.15s first core pulse before any parameter change.","1.2/r2 specification change after faithful r1 evaluation: wind sustained-flow charges no longer consumed; flow loss first decay at 0.5s. Earth pulse 0.8->2.0 coefficient. Concord threshold 4->3; stronger action still cannot charge itself. r1 exact parameters/script/report retained separately."],
                source_sha256=hashes,parameters=params,model_validation_cases=validation,model_failures=sum(not x["passed"] for x in validation),
                no_core_baseline=run(baseline,sources),scenarios=scenarios,sensitivity=sweeps,warnings=warnings,
                current_runtime_core_names={k:v["name"] for k,v in current_stats["cores"].items()},
                randomization="Deterministic prescribed movement/proximity/LOS scenarios; no RNG/seed or claimed behavioral distribution.",
                assumptions_and_omissions=["Infinite-health legal targets at declared contact counts; no actual spatial collision/AI or spawn/clear.","Damage is attack-normalized coefficient; passive/school/common multipliers held equal and canceled in ratios. Spirit crit uses stated expected factor, not sampled RNG.","Wind complete legal per-cast body envelopes are credited at release, so setup/flight/end-horizon effects are omitted; no value assigned to wider geometry.","Earth only R03/R04 baseline damage and actual-source lifecycles; side spell loss/gain, forced movement, range and LOS are prescribed. R06 consumer case excludes its own payoff.","Spirit static-target legal ordinary actions with native birth/lifetime/interval/cap; pursuit, S05/S06/S07/S08 interactions are not simulated.","No Godot run, native rule check, user playtest, full route, survival/clear-time, pixel or performance evidence."])
    (output/"results.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    lines=["# 风岩灵契三核心离线事件包络","","状态：提案；未接入游戏。",f"模型检查 {len(validation)} 项，失败 {report['model_failures']} 项。","","| 情境 | 无核心系数 | 核心额外系数 | 比例 |","|---|---:|---:|---:|"]
    for name,r in scenarios.items():
        gain="无基线" if r["gain_fraction"] is None else f"{r['gain_fraction']:.2%}"
        lines.append(f"| {name} | {r['base_coefficient']:.3f} | {r['extra_coefficient']:.3f} | {gain} |")
    lines.extend(["","## 提醒",*['- '+w for w in warnings],"","## 遗漏",*['- '+w for w in report["assumptions_and_omissions"]]])
    (output/"report.md").write_text("\n".join(lines)+"\n",encoding="utf-8")
    print(json.dumps({"checks":len(validation),"failures":report["model_failures"],"scenarios":len(scenarios),"warnings":warnings,"ordinary":{name:r["gain_fraction"] for name,r in scenarios.items() if "ordinary" in name}},ensure_ascii=False))
    return 1 if report["model_failures"] else 0


if __name__=="__main__":
    raise SystemExit(main())
