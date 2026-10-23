"""Isolated proposal event ledgers. No Godot, runtime writes, AI, or route simulation.

Fire reproduces shared burn next-tick/refresh/consume order for scheduled F01/F08
and main F07 hits only. Lightning retains old conductivity age, limited selected
network edges and consume-before-snapshot order for the modeled spells. Ice is
an explicit window/input ledger, NOT a reimplementation of frost/control.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import heapq
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
VERSION = 'gem-v3-fil-event-ledgers-20261022-r3'
EPS = 1e-8

def load(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def source_spells():
    base = load(ROOT/'data/balance_candidates/first_run_v1.json')
    growth = load(ROOT/'data/route_spell_growth.json')['spells']
    fire = copy.deepcopy(base['spells'])
    for key, item in growth.items():
        if key in fire:
            fire[key]['levels'] = item['levels']
    lightning = load(ROOT/'data/lightning_spells_v1.json')['spells']
    burn = load(ROOT/'data/route_spell_runtime.json')['fire']['burning']
    return fire, lightning, burn

def cycle(spec, level, cdr):
    tier = spec['levels'][level-1]
    cd = tier.get('cooldown', spec.get('cooldown',0))
    # Fire source uses cast rather than windup in some definitions.
    windup = spec.get('windup', spec.get('cast',0.25))
    return float(windup) + max(0.2,float(cd)*(1-min(0.6,cdr)))

def schedule(spells, ids, level, cdr, horizon):
    events=[]
    for ordinal, key in enumerate(ids):
        period=cycle(spells[key],level,cdr)
        t=ordinal*0.17
        while t < horizon-EPS:
            events.append((round(t,9),ordinal,key))
            t+=period
    return sorted(events)

def fire_ledger(p, scenario, enabled=True):
    fire,_,burn=source_spells()
    horizon=p['horizon_seconds']; attack=p['attack']; cfg=p['fire']
    targets=scenario['targets']; health=[scenario.get('health',1e12)]*targets
    states={}; queue=[]; serial=0; totals={'body':0.,'burn':0.,'detonation':0.,'core':0.}
    burst_count=0; max_reserve=0.; first_kill=None
    def push(t,priority,kind,payload):
        nonlocal serial
        serial+=1; heapq.heappush(queue,(t,priority,serial,kind,payload))
    def damage(index,amount,kind,t):
        nonlocal first_kill
        if health[index]<=0:return 0.
        value=min(health[index],max(0.,amount)); health[index]-=value; totals[kind]+=value
        if health[index]<=0:
            states.pop(index,None)
            if first_kill is None:first_kill=t
        return value
    def ignite(index,t):
        if health[index]<=0:return
        if index in states and states[index]['expires']>t+EPS:
            states[index]['expires']=max(states[index]['expires'],t+burn['duration'])
        else:
            states[index]={'expires':t+burn['duration'],'next':t+burn['interval'],
                           'token':serial,'reserve':0.,'ticks':0}
            push(t+burn['interval'],0,'tick',(index,states[index]['token']))
    for t,ordinal,key in schedule(fire,scenario['spells'],scenario['level'],scenario['cdr'],horizon):
        push(t,10,'cast',key)
    while queue:
        t,priority,_,kind,payload=heapq.heappop(queue)
        if t>horizon+EPS:break
        if kind=='tick':
            index,token=payload; state=states.get(index)
            if not state or state['token']!=token or t>state['expires']+EPS:continue
            actual=damage(index,attack*burn['coefficient'],'burn',t)
            if enabled and actual>0 and health[index]>0:
                state['reserve']=min(attack*cfg['reserve_attack_cap'],state['reserve']+actual*cfg['ember_fraction_of_effective_burn_damage'])
                max_reserve=max(max_reserve,state['reserve']); state['ticks']+=1
                if state['ticks']>=cfg['ticks_per_burst']:
                    amount=state['reserve']; state['reserve']=0.; state['ticks']=0; burst_count+=1
                    damage(index,amount*cfg['primary_payout'],'core',t)
                    others=[i for i in range(targets) if i!=index and health[i]>0][:cfg['neighbor_cap']]
                    for neighbor in others:damage(neighbor,amount*cfg['neighbor_payout'],'core',t)
            if index in states and t < state['expires']-EPS:
                state['next']=t+burn['interval'];push(state['next'],0,'tick',(index,token))
            else:states.pop(index,None)
        elif kind=='ignite':ignite(payload,t)
        else:
            key=payload; tier=fire[key]['levels'][scenario['level']-1]
            for index in range(targets):
                if health[index]<=0:continue
                coefficient=float(tier.get('coefficient',0))
                if key=='F07':coefficient*=float(tier.get('main_center_damage_multiplier',1))
                old_burn = index in states
                actual_body=damage(index,attack*coefficient,'body',t)
                if enabled and key!='F07' and old_burn and index in states:
                    state=states[index]
                    state['reserve']=min(attack*cfg['reserve_attack_cap'],state['reserve']+actual_body*cfg.get('ember_fraction_of_preburn_natural_body_damage',0))
                    max_reserve=max(max_reserve,state['reserve'])
                if key=='F07' and index in states:
                    state=states.pop(index)
                    ticks=max(0,int((state['expires']-state['next']+EPS)//burn['interval'])+1)
                    mult=float(tier.get('detonation_multiplier',1))+float(tier.get('natural_detonation_multiplier_add',0))
                    damage(index,ticks*burn['coefficient']*attack*mult,'detonation',t)
                    if tier.get('reapply_delay',0)>0:push(t+float(tier['reapply_delay']),11,'ignite',index)
                elif key!='F07':ignite(index,t)
    return {'damage':sum(totals.values()),'components':totals,'bursts':burst_count,'max_reserve':max_reserve,'first_kill_seconds':first_kill}

def ice_ledger(p, s, enabled=True):
    cfg=p['ice']; h=p['horizon_seconds']; attack=p['attack']; n=s['targets']
    hits=[round(i*s['interval'],9) for i in range(int(h/s['interval']))]
    windows=[]; period=s['window_period']
    if period>0:
        start=0.
        while start<h-EPS:
            end=start+s.get('consume_at',s['window_duration'])
            windows.append((start,end,'early' if 'consume_at' in s else 'natural'))
            start+=period
    baseline=len(hits)*s['damage_per_hit']*n
    if not enabled:return {'damage':baseline,'immediate':baseline,'deferred':0.,'released':0.,'window_input_damage':0.,'max_reserve':0.}
    deferred=0.;released=0.;eligible=0.;max_reserve=0.
    for start,end,cause in windows:
        # The hit creating the window and a hit exactly at natural expiry are
        # excluded: old-token status is checked before the new application.
        window_hits=[t for t in hits if start+EPS<t<end-EPS]
        incoming=len(window_hits)*s['damage_per_hit']; eligible+=incoming*n
        reserve=min(attack*cfg['reserve_attack_cap'],incoming*cfg['defer_fraction'])
        max_reserve=max(max_reserve,reserve);deferred+=reserve*n
        if end<=h+EPS:
            mult=cfg['early_consume_payout'] if cause=='early' else cfg['natural_payout']
            released+=reserve*mult*n*(cfg['primary_payout'] if 'primary_payout' in cfg else 1)
            released+=reserve*mult*min(cfg['neighbor_cap'],n-1)*cfg['neighbor_payout']*n
    return {'damage':baseline-deferred+released,'immediate':baseline-deferred,'deferred':deferred,'released':released,
            'window_input_damage':eligible,'max_reserve':max_reserve}

def lightning_ledger(p,s,enabled=True):
    _,spells,_=source_spells();cfg=p['lightning'];attack=p['attack'];h=p['horizon_seconds'];n=s['targets']
    marks={};charges=0;reserve=0.;last_gain=-1e9;ready=-1e9;body=0.;conditional=0.;core=0.;bursts=0;consumed=0;max_reserve=0.;queue=[]
    for t,ordinal,key in schedule(spells,s['spells'],s['level'],s['cdr'],h):
        tier=spells[key]['levels'][s['level']-1]
        marks={i:m for i,m in marks.items() if m['until']>t+EPS}
        if enabled and charges and t-last_gain>=cfg['idle_expiry_seconds']-EPS:charges=0;reserve=0.
        paid=False
        if enabled and charges>=cfg['charges_required'] and 0 in marks:
            selected=[0]+[i for i in sorted(marks) if i!=0][:cfg['neighbor_cap']]
            for i in selected:marks.pop(i)
            consumed+=len(selected);bursts+=1;paid=True
            if t+cfg['strike_delay_seconds']<=h+EPS:
                core+=reserve*(cfg['primary_payout']+cfg['neighbor_payout']*(len(selected)-1))
            charges=0;reserve=0.
        old=0 in marks;age=t-marks[0]['since'] if old else 0.;nodes=len(marks) if old else 0
        coefficient=float(tier['coefficient'])
        if key=='L01' and not old: coefficient+=float(tier.get('unconductive_coefficient_add',0))
        amount=attack*coefficient; extra=0.
        if key=='L02':
            amount*=float(tier.get('isolated_main_multiplier',1)) if n==1 else 1
            extra+=attack*float(tier.get('secondary_coefficient',0))*min(n-1,int(tier.get('secondary_target_cap',0)))
        elif key=='L03':
            extra+=sum(attack*float(tier['coefficient'])*float(tier['hop_decay'])**i for i in range(1,min(n,int(tier['target_cap']))))
        elif key=='L07':
            if old:extra+=attack*float(tier['conductive_extra_coefficient'])
            if old and age>=float(tier.get('mature_age',1e9)):
                extra+=attack*float(tier.get('mature_arc_coefficient',0))*min(n-1,int(tier.get('mature_arc_target_cap',0)),max(0,nodes-1))
        elif key=='L08':
            count=min(max(0,nodes-1),int(tier['target_cap'])-1)
            for i in range(count):
                overload=nodes>=3 and i<int(tier.get('natural_overload_edges',2))
                extra+=attack*float(tier['edge_coefficient'])*(float(tier.get('natural_overload_multiplier',1.5)) if overload else 1)
        body+=amount;conditional+=extra
        if enabled and not paid and old and t>=ready-EPS and charges<cfg['charges_required']:
            charges+=1;reserve=min(attack*cfg['reserve_attack_cap'],reserve+amount*cfg['stored_fraction'])
            last_gain=t;ready=t+cfg['gain_gate_seconds'];max_reserve=max(max_reserve,reserve)
        # Existing-age refresh is preserved; consumed state gets a fresh age.
        duration=float(tier.get('conductive_duration',4))
        ids=[0]
        if key=='L04':ids+=list(range(1,min(n,int(tier.get('neighbor_cap',0))+1)))
        elif key in ['L02','L03']:ids=list(range(min(n, int(tier.get('target_cap',tier.get('secondary_target_cap',0)+1)))))
        for i in ids:marks[i]={'since':marks[i]['since'] if i in marks else t,'until':t+duration}
    return {'damage':body+conditional+core,'body':body,'conditional_and_secondary':conditional,'core':core,
            'bursts':bursts,'consumed_marks':consumed,'max_reserve':max_reserve,'unpaid_charges':charges,'unpaid_reserve':reserve}

def canonical_fixture():
    """Fixed hand-calculation inputs, independent of every CLI tuning parameter."""
    return {
        'attack':100.,'horizon_seconds':30.,
        'fire':{'ember_fraction_of_effective_burn_damage':.6,'ember_fraction_of_preburn_natural_body_damage':.15,
                'ticks_per_burst':4,'reserve_attack_cap':3.,'primary_payout':1.,'neighbor_payout':.35,'neighbor_cap':2},
        'ice':{'defer_fraction':.4,'reserve_attack_cap':8.,'natural_payout':1.8,'early_consume_payout':1.45,
               'death_payout':1.,'primary_payout':1.,'neighbor_payout':.3,'neighbor_cap':2},
        'lightning':{'charges_required':4,'gain_gate_seconds':.6,'stored_fraction':.4,'reserve_attack_cap':8.,
                     'idle_expiry_seconds':6.,'neighbor_cap':2,'primary_payout':1.,'neighbor_payout':.3,'strike_delay_seconds':.15}
    }

def check_model(p):
    checks=[]
    def check(test,label):
        checks.append({'label':label,'passed':bool(test)})
    def nonnegative(value):
        return isinstance(value,(int,float)) and not isinstance(value,bool) and math.isfinite(value) and value>=0
    for key in ['attack','horizon_seconds']:
        check(nonnegative(p.get(key)) and p[key]>0,'candidate domain: '+key+' finite and positive')
    positive={'fire':['reserve_attack_cap'],
              'ice':['reserve_attack_cap'],
              'lightning':['gain_gate_seconds','reserve_attack_cap','idle_expiry_seconds']}
    nonnegative_fields={
        'fire':['ember_fraction_of_effective_burn_damage','ember_fraction_of_preburn_natural_body_damage','primary_payout','neighbor_payout','neighbor_radius_m'],
        'ice':['natural_payout','early_consume_payout','death_payout','primary_payout','neighbor_payout','neighbor_radius_m'],
        'lightning':['stored_fraction','primary_payout','neighbor_payout','consume_radius_m','strike_delay_seconds','strike_locked_radius_m']}
    for group in positive:
        cfg=p[group]
        for key in positive[group]:check(nonnegative(cfg.get(key)) and cfg[key]>0,'candidate domain: '+group+'.'+key+' positive')
        for key in nonnegative_fields[group]:check(nonnegative(cfg.get(key)),'candidate domain: '+group+'.'+key+' finite nonnegative')
        value=cfg.get('neighbor_cap')
        check(isinstance(value,int) and not isinstance(value,bool) and value>=0,'candidate domain: '+group+'.neighbor_cap nonnegative integer')
    for group,key in [('fire','ticks_per_burst'),('lightning','charges_required')]:
        value=p[group].get(key)
        check(isinstance(value,int) and not isinstance(value,bool) and value>0,'candidate domain: '+group+'.'+key+' positive integer')
    check(nonnegative(p['ice'].get('defer_fraction')) and p['ice']['defer_fraction']<=1,'candidate domain: ice defer fraction in [0,1]')
    for group,items in p['scenarios'].items():
        for s in items:
            valid=isinstance(s.get('targets'),int) and s['targets']>=1
            if group=='ice':
                valid=valid and nonnegative(s.get('interval')) and s['interval']>0 and nonnegative(s.get('damage_per_hit'))
                valid=valid and nonnegative(s.get('window_period')) and nonnegative(s.get('window_duration'))
                valid=valid and (s['window_period']==0 or s['window_period']>=s['window_duration'])
                valid=valid and ('consume_at' not in s or 0<s['consume_at']<=s['window_duration'])
            else:
                valid=valid and s.get('level') in [1,2,3] and nonnegative(s.get('cdr')) and s['cdr']<=.6
            check(valid,'candidate scenario domain: '+group+' '+s['id'])
    if any(not case['passed'] for case in checks):return checks
    fixed=canonical_fixture();f=fixed['fire'];i=fixed['ice'];l=fixed['lightning'];a=fixed['attack']
    check(abs(4*25*f['ember_fraction_of_effective_burn_damage']*f['primary_payout']-60)<EPS,'four 25-damage ticks create exactly 60 primary ember damage')
    check(abs(4*25*f['ember_fraction_of_effective_burn_damage']*(1+2*f['neighbor_payout'])-102)<EPS,'same ember with two real neighbors totals 102, not three full payouts')
    reserve=400*i['defer_fraction']
    check(abs(400-reserve+reserve*i['natural_payout']-528)<EPS,'400 window body: 240 immediate + 288 natural release = 528')
    check(abs(400-reserve+reserve*i['early_consume_payout']-472)<EPS,'same token early consumption = 472, not natural-release multiplier')
    check(abs(min(a*i['reserve_attack_cap'],10000*i['defer_fraction'])-800)<EPS,'ice per-token stock cap clips at 800 with attack100')
    check(abs(4*100*l['stored_fraction']-160)<EPS,'four qualifying 100 primary hits bank160 lightning')
    check(abs(4*100*l['stored_fraction']*(1+2*l['neighbor_payout'])-256)<EPS,'bank160 with two consumed neighbors pays256 total')
    _,lightning,_=source_spells()
    check(abs((float(lightning['L01']['levels'][2]['coefficient'])+float(lightning['L01']['levels'][2]['unconductive_coefficient_add']))*a-210)<EPS,'regression: L01 level3 unmarked hit is210, not180')
    candidate=copy.deepcopy(fixed);candidate['fire']['ember_fraction_of_preburn_natural_body_damage']=0
    s={'spells':['F01','F08'],'level':3,'targets':1,'cdr':.3}
    check(fire_ledger(fixed,s)['damage']>fire_ledger(candidate,s)['damage'],'canonical: fire body contribution supports mature direct builds without changing basic burn')
    lightning_s={'spells':[],'level':1,'targets':3,'cdr':0}
    check(lightning_ledger(fixed,lightning_s)['damage']==0,'canonical: zero events cannot create lightning damage')
    for group,func in [('fire',fire_ledger),('ice',ice_ledger),('lightning',lightning_ledger)]:
        for s in p['scenarios'][group]:
            result=func(p,s)
            check(result['damage']>=0 and result['max_reserve']<=p['attack']*p[group]['reserve_attack_cap']+EPS,group+' '+s['id']+' nonnegative finite capped stock')
    return checks

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--parameters',type=Path,default=Path(__file__).with_name('fire_ice_lightning_parameters.json'))
    parser.add_argument('--output',type=Path,default=ROOT/'build/qa/gem-redesign-v3-20261022/fire-ice-lightning');args=parser.parse_args()
    out=args.output.resolve();allowed=(ROOT/'build/qa').resolve()
    if not out.is_relative_to(allowed):raise SystemExit('output must stay in project build/qa')
    p=load(args.parameters);checks=check_model(p);results=[]
    if any(not case['passed'] for case in checks):
        print(json.dumps({'model_version':VERSION,'checks':len(checks),'failed':sum(not c['passed'] for c in checks),
                          'details':[case['label'] for case in checks if not case['passed']],
                          'output_written':False},ensure_ascii=False))
        raise SystemExit(1)
    for group,func in [('fire',fire_ledger),('ice',ice_ledger),('lightning',lightning_ledger)]:
        for s in p['scenarios'][group]:
            baseline=func(p,s,False);proposed=func(p,s,True)
            ratio=proposed['damage']/baseline['damage']-1 if baseline['damage'] else None
            results.append({'core':group,'id':s['id'],'inputs':s,'baseline':baseline,'proposal':proposed,'relative_total_damage_change':ratio,
                            'status':'no_input' if ratio is None else 'situational_warning' if ratio<0 or ratio>.6 else 'within_inspected_scenario_band'})
    sweeps=[]
    for group,key,values,sid in [('fire','ember_fraction_of_effective_burn_damage',p['sweeps']['fire_ember_fraction'],'F01_F08_L3_single'),
                                ('ice','natural_payout',p['sweeps']['ice_natural_payout'],'dense_window_single'),
                                ('lightning','stored_fraction',p['sweeps']['lightning_stored_fraction'],'L01_L02_L3_single')]:
        func={'fire':fire_ledger,'ice':ice_ledger,'lightning':lightning_ledger}[group]
        scenario=next(s for s in p['scenarios'][group] if s['id']==sid)
        for value in values:
            candidate=copy.deepcopy(p);candidate[group][key]=value
            b=func(candidate,scenario,False)['damage'];r=func(candidate,scenario,True)['damage']
            sweeps.append({'core':group,'parameter':key,'value':value,'scenario':sid,'gain':r/b-1})
    paths=['data/balance_candidates/first_run_v1.json','data/route_spell_growth.json','data/route_spell_runtime.json','data/lightning_spells_v1.json',
           'scripts/core/route_fire_status.gd','scripts/core/route_ice_status.gd','scripts/core/route_lightning_combat.gd']
    hashes={path:hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in paths}
    for source in [Path(__file__).resolve(),args.parameters.resolve()]:
        key=source.relative_to(ROOT).as_posix() if source.is_relative_to(ROOT) else str(source)
        hashes[key]=hashlib.sha256(source.read_bytes()).hexdigest()
    report={'model_version':VERSION,'parameter_version':p['version'],'parameters':p,'source_sha256':hashes,
            'checks':len(checks),'failed':sum(not c['passed'] for c in checks),'model_validation_cases':checks,'scenarios':results,'sensitivity':sweeps,
            'model_changes':['r2 model correction: include actual L01 level2/3 unmarked-hit coefficient before judging lightning figures; regression case210 vs180 added.',
                             'Separate r2 parameter decision: add15% natural fire body credit on a pre-existing burn; F07 excluded, same four-tick payout and token reset preserved. This fixes low mature-build utility without inflating all basic burn ticks.',
                             'r3 tool correction only: hand-calculation expectations use an independent fixed canonical fixture; editable candidate parameters get separate domain and invariant checks. Recommended parameters and mechanisms are unchanged.'],
            'seed_and_trial_count':'Deterministic event ledgers; no stochastic process or RNG draws are modeled.',
            'assumptions_and_omissions':['All scheduled direct hits land on stationary visible targets; extra targets are explicitly assumed in range and LOS.',
             'Fire ignores F01 secondary/crit patches, F08 conditional extra pulses and F07 aftershock; only named main hits and shared basic burn modeled.',
             'Ice window timing and incoming damage are declared inputs; frost/immune cycles, target death, enemy AI and actual build DPS are not predicted.',
             'Lightning models instantaneous primary contacts for L01/L02/L03/L04/L07/L08; real flight, per-edge timing, enemies dying, cloud and shield actions omitted.',
             'No crit, field/stat buffs, artifacts, collision, real fight, natural route, performance, economy or game-save writes. Core derived damage never feeds a ledger.',
             'Stock caps are per reserve. They are not overall DPS caps or claims of final balance.']}
    out.mkdir(parents=True,exist_ok=True)
    (out/'results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    lines=['# 火冰雷核心离线提案核算','',f"版本：{VERSION}；模型检查{report['checks']}项，失败{report['failed']}项。",'',
           '| 核心／情境 | 基线伤害 | 提案伤害 | 变化 |','|---|---:|---:|---:|']
    for row in results:
        gain='无输入' if row['relative_total_damage_change'] is None else f"{row['relative_total_damage_change']:+.1%}"
        lines.append(f"| {row['core']} / {row['id']} | {row['baseline']['damage']:.1f} | {row['proposal']['damage']:.1f} | {gain} |")
    lines+=['','这些是同一输入下的确定性事件账本；不是原生运行、完整八术构筑、真人输出或60房通关预测。','',
            '受控扫值见results.json；自然冷却/时间来自实际源，仅明确列出的主体分量被模型化。']
    (out/'summary.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(json.dumps({'checks':report['checks'],'failed':report['failed'],'scenarios':len(results),'sweeps':len(sweeps),'output':str(out)},ensure_ascii=False))
    for row in results:
        print(row['core'],row['id'],None if row['relative_total_damage_change'] is None else round(row['relative_total_damage_change']*100,2))
    raise SystemExit(1 if report['failed'] else 0)

if __name__=='__main__':main()
