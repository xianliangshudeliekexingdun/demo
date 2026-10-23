"""Proposal-only source/sink and attribute-budget model; never writes runtime data.

Run from any directory. Editable proposal parameters and current sources are
read independently; Python RNG is not claimed to reproduce Godot RNG.
"""
from __future__ import annotations
import argparse
from collections import Counter
from copy import deepcopy
import hashlib
import itertools
import json
import math
from pathlib import Path
import random
import statistics

ROOT = Path(__file__).resolve().parents[3]
DEFAULT = Path(__file__).with_name('economy_parameters.json')
RARITIES = ['green', 'blue', 'purple']

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def percentile(values, p):
    values = sorted(values)
    return values[max(0, math.ceil(len(values) * p) - 1)] if values else None

def income(room, source):
    route = source['route_income']
    return sum(route['early_dust'] if index <= route['early_end'] else route['later_dust'] for index in range(1, min(room, route['max_room']) + 1))

def distribution(values):
    finite = [x for x in values if x is not None]
    ordered=sorted(finite)
    def censored_quantile(p):
        index=max(0,math.ceil(len(values)*p)-1)
        return ordered[index] if index<len(ordered) else None
    return {'n':len(values),'reached':len(finite),'censored':len(values)-len(finite),
            'mean_reached':statistics.fmean(finite) if finite else None,
            'p50':censored_quantile(.5),'p90':censored_quantile(.9),
            'minimum':min(finite) if finite else None,'maximum_reached':max(finite) if finite else None}

def milestone_awards(before,after,claimed,p):
    updated=set(claimed); amount=0
    for milestone in p.get('account_milestone_essence',[]):
        threshold=milestone['cleared_rooms']
        if before < threshold <= after and threshold not in updated:
            amount+=milestone['essence']; updated.add(threshold)
    return amount,updated

def tier(rng,p): return rng.choices([1,2,3],weights=p['tier_weights'])[0]

def side_line(rng,main,existing,p,forced_tier=None):
    candidates = [key for key in p['side_tiers'] if key != main and key not in {line['stat'] for line in existing}]
    return {'stat':rng.choice(candidates),'tier':forced_tier or tier(rng,p)}

def gem(rng,rarity,main,p,crafted=False):
    result={'rarity':rarity,'main':main,'tier':1 if crafted else tier(rng,p),'sides':[]}
    for _ in range(p['affix_counts'][rarity]-1): result['sides'].append(side_line(rng,main,result['sides'],p,1 if crafted else None))
    return result

def draw(rng,misses,p):
    if misses+1 >= p['purple_hard_pity']: rarity='purple'
    else: rarity=rng.choices(list(p['rarity_weights']),weights=list(p['rarity_weights'].values()))[0]
    result=gem(rng,rarity,rng.choice(list(p['main_tiers'])),p)
    return result,0 if rarity=='purple' else misses+1

def remaining_cost(item,p):
    rarity=item['rarity']; main=item['main']; cost=sum(p['main_tier_upgrade_essence'][item['tier']-1:])
    if rarity=='green': cost+=p['grade_upgrade_essence']['green_to_blue']+p['grade_upgrade_essence']['blue_to_purple']
    elif rarity=='blue': cost+=p['grade_upgrade_essence']['blue_to_purple']
    needed=set(p['profile']['desired_sides'][main])
    kept={line['stat'] for line in item['sides']}
    cost+=len(needed-kept)*p['targeted_side_type_reforge_essence']
    cost+=sum(sum(p['side_tier_upgrade_essence'][line['tier']-1:]) for line in item['sides'])
    # Not-yet-created sides are conservatively assumed tier I and wrong type.
    cost+=(2-len(item['sides']))*sum(p['side_tier_upgrade_essence'])
    return cost

def finished(item,p):
    return item['rarity']=='purple' and item['tier']==3 and all(line['tier']==3 for line in item['sides']) and {line['stat'] for line in item['sides']} == set(p['profile']['desired_sides'][item['main']])

def work_once(equipped,essence,rng,p):
    # First make all three slots blue, then purple, then target types and tiers.
    for origin,destination,key in [('green','blue','green_to_blue'),('blue','purple','blue_to_purple')]:
        for item in equipped:
            cost=p['grade_upgrade_essence'][key]
            if item['rarity']==origin:
                if essence < cost: return essence,0
                item['rarity']=destination
                item['sides'].append(side_line(rng,item['main'],item['sides'],p,1))
                return essence-cost,cost
    for item in equipped:
        wanted=set(p['profile']['desired_sides'][item['main']]); current={line['stat'] for line in item['sides']}
        for line in item['sides']:
            if line['stat'] not in wanted:
                cost=p['targeted_side_type_reforge_essence']
                if essence < cost: return essence,0
                line['stat']=sorted(wanted-current)[0]
                return essence-cost,cost
    for item in equipped:
        if item['tier'] < 3:
            cost=p['main_tier_upgrade_essence'][item['tier']-1]
            if essence < cost: return essence,0
            item['tier']+=1
            return essence-cost,cost
    for item in equipped:
        for line in item['sides']:
            if line['tier'] < 3:
                cost=p['side_tier_upgrade_essence'][line['tier']-1]
                if essence < cost: return essence,0
                line['tier']+=1
                return essence-cost,cost
    return essence,0

def progression(seed,room,policy,p,current,meta):
    rng=random.Random(seed)
    desired=p['profile']['desired_mains']
    equipped=[gem(rng,'green',main,p,crafted=True) for main in desired]
    dust=essence=0; cores=p['core_first_choice_free']; catalyst_upgrades=0; draws=0; misses=0; core_savings=0
    source=spend_dust=source_essence=spend_essence=0
    cumulative_rooms=0; claimed_milestones=set(); awarded_milestone_essence=0
    moments={'extra_core':None,'three_blue':None,'three_purple':None,'perfect_selected_set':None,'all_cores':None}
    for run in range(1,p['simulation']['routes']+1):
        earned=income(room,current); dust+=earned; source+=earned
        award,claimed_milestones=milestone_awards(cumulative_rooms,cumulative_rooms+room,claimed_milestones,p)
        cumulative_rooms+=room; essence+=award; source_essence+=award; awarded_milestone_essence+=award
        while True:
            essence,paid=work_once(equipped,essence,rng,p)
            if not paid: break
            spend_essence+=paid
        if policy=='balanced':
            core_savings=min(dust,p['core_unlock_dust']) if cores==1 else min(dust,core_savings+earned*3//10) if cores<p['core_count'] else 0
            max_cores=1
        elif policy=='collection_first':
            core_savings=dust if cores<p['core_count'] else 0
            max_cores=9
        else:
            if cores==1:
                core_savings=min(dust,p['core_unlock_dust']); max_cores=1
            else:
                pursuing=all(finished(item,p) for item in equipped)
                core_savings=dust if pursuing and cores<p['core_count'] else 0
                max_cores=9 if pursuing else 0
        for _ in range(max_cores):
            if cores < p['core_count'] and core_savings >= p['core_unlock_dust']:
                dust-=p['core_unlock_dust']; spend_dust+=p['core_unlock_dust']; cores+=1
                core_savings-=p['core_unlock_dust']
        if cores==p['core_count']: core_savings=0
        # One starter catalyst's actual existing II/III fees, no assumed price change.
        fees=[meta['progression']['upgrade_cost_by_current_level']['1'],meta['progression']['upgrade_cost_by_current_level']['2']]
        hold_for_catalyst=False
        if catalyst_upgrades<2 and dust-core_savings>=fees[catalyst_upgrades]:
            dust-=fees[catalyst_upgrades]; spend_dust+=fees[catalyst_upgrades]; catalyst_upgrades+=1
        elif catalyst_upgrades<2: hold_for_catalyst=True
        while not hold_for_catalyst and dust-core_savings >= p['draw_dust']:
            dust-=p['draw_dust']; spend_dust+=p['draw_dust']; draws+=1
            incoming,misses=draw(rng,misses,p)
            keep=False
            if incoming['main'] in desired:
                index=desired.index(incoming['main']); old=equipped[index]
                # Prefer a cheaper remaining target path, including salvage opportunity cost.
                if RARITIES.index(incoming['rarity'])>=RARITIES.index(old['rarity']) and remaining_cost(incoming,p)-p['salvage_essence'][old['rarity']] < remaining_cost(old,p)-p['salvage_essence'][incoming['rarity']]:
                    equipped[index]=incoming; incoming=old; keep=True
            value=p['salvage_essence'][incoming['rarity']]
            essence+=value; source_essence+=value
            while True:
                essence,paid=work_once(equipped,essence,rng,p)
                if not paid: break
                spend_essence+=paid
            assert dust>=0 and essence>=0 and dust==source-spend_dust and essence==source_essence-spend_essence
        if cores>=2 and moments['extra_core'] is None: moments['extra_core']=run
        if all(item['rarity']!='green' for item in equipped) and moments['three_blue'] is None: moments['three_blue']=run
        if all(item['rarity']=='purple' for item in equipped) and moments['three_purple'] is None: moments['three_purple']=run
        if all(finished(item,p) for item in equipped) and moments['perfect_selected_set'] is None: moments['perfect_selected_set']=run
        if cores==p['core_count'] and moments['all_cores'] is None: moments['all_cores']=run
    assert awarded_milestone_essence<=sum(row['essence'] for row in p.get('account_milestone_essence',[]))
    assert dust==source-spend_dust and essence==source_essence-spend_essence
    return {'moments':moments,'dust':dust,'essence':essence,'cores':cores,'draws':draws,'earned_dust':source,'spent_dust':spend_dust,'generated_essence':source_essence,'spent_essence':spend_essence,'milestone_essence':awarded_milestone_essence}

def current_target_core(rng,current):
    misses=0; first=True; count=0
    while count<100000:
        count+=1; next_draw=misses+1; pity=current['pity']
        probability=1.0 if (first and next_draw>=pity['first_gold']) or next_draw>=pity['gold_hard'] else current['base_weights']['gold']/100+max(0,next_draw-pity['gold_soft_start']+1)*pity['gold_soft_increment']
        if rng.random()<probability:
            first=False; misses=0
            if rng.randrange(len(current['cores']))==0: return count
        else: misses+=1
    raise AssertionError('current target core model did not terminate')

def attribute_budget(p,current,base,generic_rules,limits):
    stats=list(p['main_tiers']); max_side={key:values[-1] for key,values in p['side_tiers'].items()}
    old_gems=[]; new_gems=[]
    for group in itertools.combinations(['attack','crit_rate','crit_multiplier','cdr'],3): old_gems.append({key:current['affixes'][key]['tiers'][-1] for key in group})
    for main in ['attack','crit_rate','crit_multiplier','cdr']:
        for sides in itertools.combinations([key for key in ['attack','crit_rate','crit_multiplier','cdr'] if key!=main],2):
            new_gems.append({main:p['main_tiers'][main][-1],**{key:max_side[key] for key in sides}})
    def damage(items,prior_cdr,cast,cd):
        totals={key:sum(item.get(key,0) for item in items) for key in stats}
        atk=base['attack']+totals['attack']; critical=1+min(1,base['crit_rate']+totals['crit_rate'])*(base['crit_multiplier']+totals['crit_multiplier']-1)
        return atk*critical/(cast+max(.2,cd*(1-min(.6,prior_cdr+totals['cdr'])))),totals
    rows=[]
    for prior_cdr in [0.0,.3,.6]:
        for cast,cd in [(.25,1.5),(.5,6.0)]:
            old=max(((damage(items,prior_cdr,cast,cd),items) for items in itertools.combinations_with_replacement(old_gems,4)),key=lambda entry:entry[0][0])
            new=max(((damage(items,prior_cdr,cast,cd),items) for items in itertools.combinations_with_replacement(new_gems,3)),key=lambda entry:entry[0][0])
            rows.append({'prior_cdr':prior_cdr,'cast':cast,'base_cd':cd,'old_max_dps':old[0][0],'new_max_dps':new[0][0],'ratio':new[0][0]/old[0][0],'old_totals':old[0][1],'new_totals':new[0][1]})
    defensive=[]
    keys=['health','shield','defense']
    old_def=[{key:current['affixes'][key]['tiers'][-1] for key in keys}]*4
    def ehp(items):
        totals={key:sum(item.get(key,0) for item in items) for key in keys}
        health=base['health']+totals['health']; shield=base['shield']+totals['shield']; reduction=min(.45,1-100/(100+totals['defense']))
        return (health+shield)/(1-reduction),totals
    variants=[]
    for main in keys: variants.append({main:p['main_tiers'][main][-1],**{key:max_side[key] for key in keys if key!=main}})
    for items in itertools.combinations_with_replacement(variants,3):
        value,totals=ehp(items); defensive.append({'totals':totals,'ehp':value,'ratio_to_old_defensive':value/ehp(old_def)[0]})
    stacking=[]
    for stat in stats:
        value=3*p['main_tiers'][stat][-1]
        row={'stat':stat,'three_III_mains_total':value,'scope':'Each row is a separate three-mains configuration; not simultaneously attainable.'}
        if stat=='cdr': row.update(external_bonus=.5,effective_combined=min(limits['cooldown_reduction'],.5+value),cap=limits['cooldown_reduction'])
        if stat=='speed': row.update(external_bonus=.3,effective_combined=min(generic_rules['combat_move_speed_bonus_cap'],.3+value),cap=generic_rules['combat_move_speed_bonus_cap'],effective_speed=base['move_speed']*(1+min(generic_rules['combat_move_speed_bonus_cap'],.3+value)))
        if stat=='defense': row.update(external_bonus=70,raw_combined_reduction=1-100/(100+70+value),effective_combined_reduction=min(generic_rules['maximum_damage_reduction'],1-100/(100+70+value)),cap=generic_rules['maximum_damage_reduction'])
        if stat=='crit_rate': row.update(base_rate=base['crit_rate'],effective_rate=min(1,base['crit_rate']+value))
        stacking.append(row)
    return {'weighted_line_budget':{'old_III_lines':12,'new_III_lines':9,'new_main_old_line_equivalents':2,'new_total_equivalents':12,'warning':'Equal sum of normalized attribute-line units is an anchor only; not proof of equal utility or damage.'},'offense_optimized_grid':rows,'defensive_grid':defensive,'old_defensive_ehp':ehp(old_def)[0],'three_main_stack_boundaries':stacking}

def main():
    cli=argparse.ArgumentParser(); cli.add_argument('--parameters',type=Path,default=DEFAULT); cli.add_argument('--output',type=Path,default=ROOT/'build/qa/gem-redesign-v3-20261022/economy'); cli.add_argument('--accounts-per-seed',type=int)
    args=cli.parse_args(); p=json.loads(args.parameters.read_text(encoding='utf-8-sig'))
    args.parameters=args.parameters.resolve()
    if args.accounts_per_seed: p['simulation']['accounts_per_seed']=args.accounts_per_seed
    current_path=ROOT/'data/magic_gems_v1.json'; meta_path=ROOT/'data/balance_candidates/meta_growth_v1.json'; base_path=ROOT/'data/balance_candidates/first_run_v1.json'; generic_path=ROOT/'data/generic_artifacts_v1.json'
    current=json.loads(current_path.read_text(encoding='utf-8-sig')); meta=json.loads(meta_path.read_text(encoding='utf-8-sig')); base_source=json.loads(base_path.read_text(encoding='utf-8-sig')); base=base_source['player']; generic=json.loads(generic_path.read_text(encoding='utf-8-sig'))['rules']
    checks=[]
    def check(name,condition):
        checks.append({'name':name,'passed':bool(condition)})
        if not condition: raise AssertionError(name)
    check('source route income 0/15/30/45/60',[income(n,current) for n in [0,15,30,45,60]]==[0,15,45,75,105])
    check('censored quantiles use all accounts not reached-only subgroup',distribution([1,2,3,4,None])['p50']==3 and distribution([1,2,3,4,None])['p90'] is None)
    check('known budget one clear 105 minus core30 minus catalyst20 permits 11 draws', (105-30-20)//5==11)
    check('rarity weights sum100',sum(p['rarity_weights'].values())==100)
    check('tier weights sum100',sum(p['tier_weights'])==100)
    check('three starter mains distinct and supported',len(p['profile']['desired_mains'])==len(set(p['profile']['desired_mains']))==3)
    for stat in p['main_tiers']:
        check('main tiers twice old '+stat,all(abs(a-2*b)<1e-9 for a,b in zip(p['main_tiers'][stat],current['affixes'][stat]['tiers'])))
        check('side tiers retain old '+stat,p['side_tiers'][stat]==current['affixes'][stat]['tiers'])
    for rarity in RARITIES: check('craft-salvage loses essence '+rarity,p['craft_essence'][rarity]>p['salvage_essence'][rarity])
    check('green-blue upgrade cannot create essence',p['grade_upgrade_essence']['green_to_blue']>p['salvage_essence']['blue']-p['salvage_essence']['green'])
    check('blue-purple upgrade cannot create essence',p['grade_upgrade_essence']['blue_to_purple']>p['salvage_essence']['purple']-p['salvage_essence']['blue'])
    check('incremental grade route no cheaper than direct craft',p['craft_essence']['green']+sum(p['grade_upgrade_essence'].values())>=p['craft_essence']['purple'])
    rng=random.Random(17); misses=p['purple_hard_pity']-1; forced,misses=draw(rng,misses,p)
    check('pity forces purple then resets',forced['rarity']=='purple' and misses==0)
    anchor=deepcopy(p); anchor.update(core_unlock_dust=30,draw_dust=5,core_count=10,core_first_choice_free=1)
    check('early-failure collection policy banks rather than spending away its core goal',progression(7,15,'collection_first',anchor,current,meta)['moments']['extra_core']==2)
    check('all-core collection hand-case three full105 routes funds nine paid cores',progression(7,60,'collection_first',anchor,current,meta)['moments']['all_cores']==3)
    one_route=deepcopy(anchor); one_route['simulation']['routes']=1
    check('first extra-core reserve releases surplus to11 ordinary draws',progression(7,60,'balanced',one_route,current,meta)['draws']==11)
    check('growth-first buys exactly one extra core before prioritizing attributes',progression(7,60,'growth_first',one_route,current,meta)['cores']==2)
    check('zero cleared-room income does not award milestones',progression(7,0,'balanced',p,current,meta)['milestone_essence']==0)
    check('two15-room settlements grant24 exactly once',progression(7,15,'collection_first',p,current,meta)['milestone_essence']==sum(row['essence'] for row in p.get('account_milestone_essence',[])))
    award_one,claims=milestone_awards(0,15,set(),p)
    award_two,claims=milestone_awards(15,30,claims,p)
    award_combined,combined_claims=milestone_awards(0,30,set(),p)
    check('milestone split and combined settlement conserve awards',award_one+award_two==award_combined and claims==combined_claims)
    check('claimed milestone is never awarded twice',milestone_awards(0,30,claims,p)[0]==0)
    check('no room progress cannot farm a milestone',milestone_awards(15,15,set(),p)[0]==0)
    check('repeating routes cannot exceed finite account gifts',progression(7,60,'balanced',p,current,meta)['milestone_essence']==sum(row['essence'] for row in p.get('account_milestone_essence',[])))
    # Long-run exact renewal: E[min(Geom(p),hard)] = (1-(1-p)^hard)/p.
    purple=p['rarity_weights']['purple']/100; hard=p['purple_hard_pity']; expected_interval=(1-(1-purple)**hard)/purple
    effective_purple=1/expected_interval; effective_blue=(1-effective_purple)*p['rarity_weights']['blue']/(100-p['rarity_weights']['purple']); effective_green=1-effective_purple-effective_blue
    long_run={'green':effective_green,'blue':effective_blue,'purple':effective_purple}
    expected_salvage=sum(long_run[key]*p['salvage_essence'][key] for key in long_run)
    rarity_samples=[]
    for seed in p['simulation']['seeds']:
        rng=random.Random(seed); misses=0; counts=Counter()
        for _ in range(100000):
            item,misses=draw(rng,misses,p); counts[item['rarity']]+=1
        observed={key:counts[key]/100000 for key in RARITIES}; rarity_samples.append({'seed':seed,'draws':100000,'observed':observed})
        check('renewal sample close to exact '+str(seed),all(abs(observed[key]-long_run[key])<.01 for key in RARITIES))
    old_target=[]
    for seed in p['simulation']['seeds']:
        rng=random.Random(seed)
        old_target.extend(current_target_core(rng,current) for _ in range(p['simulation']['accounts_per_seed']))
    segments=[]
    for room in p['simulation']['cleared_room_segments']:
        for policy in ['balanced','collection_first','growth_first']:
            runs=[]
            for seed in p['simulation']['seeds']:
                runs.extend(progression(seed*1000003+index,room,policy,p,current,meta) for index in range(p['simulation']['accounts_per_seed']))
            moments={key:distribution([row['moments'][key] for row in runs]) for key in runs[0]['moments']}
            segments.append({'cleared_rooms_per_route':room,'dust_per_route':income(room,current),'policy':policy,'milestones_routes':moments,'end_of_horizon':{key:distribution([row[key] for row in runs]) for key in ['dust','essence','cores','draws','earned_dust','spent_dust','generated_essence','spent_essence','milestone_essence']}})
    full_balanced=next(row for row in segments if row['cleared_rooms_per_route']==60 and row['policy']=='balanced')
    target_checks=[]
    for milestone,key in [('three_blue','balanced_full_route_three_blue_p90_maximum'),('three_purple','balanced_full_route_three_purple_p90_maximum'),('perfect_selected_set','balanced_full_route_selected_perfect_set_p90_maximum')]:
        actual=full_balanced['milestones_routes'][milestone]['p90']; maximum=p['targets'][key]
        target_checks.append({'metric':milestone,'target_p90_maximum_routes':maximum,'actual_p90':actual,'status':'within' if actual is not None and actual<=maximum else 'warning'})
    sweeps=[]
    for cost in [20,30,40]:
        q=deepcopy(p); q['core_unlock_dust']=cost
        outcomes=[progression(20261022+i,60,'balanced',q,current,meta) for i in range(120)]
        sweeps.append({'core_cost':cost,'milestones':{key:distribution([row['moments'][key] for row in outcomes]) for key in ['extra_core','three_purple','perfect_selected_set','all_cores']}})
    pity_sweep=[]
    for n in [8,10,12]:
        fp=purple/(1-(1-purple)**n); pity_sweep.append({'purple_hard_pity':n,'effective_purple':fp,'mean_draws_per_purple':1/fp})
    grade_price_sweep=[]
    for fee in [15,20,25]:
        q=deepcopy(p); q['grade_upgrade_essence']['blue_to_purple']=fee; q['craft_essence']['purple']=q['craft_essence']['blue']+fee
        outcomes=[progression(20261022+i,60,'balanced',q,current,meta) for i in range(300)]
        grade_price_sweep.append({'blue_to_purple':fee,'direct_purple_craft':q['craft_essence']['purple'],'milestones':{key:distribution([row['moments'][key] for row in outcomes]) for key in ['three_blue','three_purple','perfect_selected_set']}})
    milestone_sweep=[]
    for total in [0,12,24]:
        q=deepcopy(p); q['account_milestone_essence']=[] if total==0 else [{'cleared_rooms':15,'essence':12}] if total==12 else [{'cleared_rooms':15,'essence':12},{'cleared_rooms':30,'essence':12}]
        for depth in [15,60]:
            outcomes=[]
            for seed in p['simulation']['seeds']:
                outcomes.extend(progression(seed*1000003+i,depth,'balanced',q,current,meta) for i in range(p['simulation']['accounts_per_seed']))
            milestone_sweep.append({'total_milestone_essence':total,'cleared_rooms_per_route':depth,'accounts':len(outcomes),'milestones':{key:distribution([row['moments'][key] for row in outcomes]) for key in ['three_blue','three_purple','perfect_selected_set']}})
    budget=attribute_budget(p,current,base,generic,base_source['limits'])
    check('offense optimized scan finite',all(math.isfinite(row['ratio']) and row['ratio']>0 for row in budget['offense_optimized_grid']))
    check('new normalized budget12',(2+1+1)*3==12)
    result={'model_version':p['model_version'],'parameter_version':p['version'],'proposal_only':True,'parameters':p,
            'source_sha256':{str(path.relative_to(ROOT)).replace('\\','/'):sha(path) for path in [current_path,meta_path,base_path,generic_path,args.parameters,Path(__file__)]},
            'validation_cases':checks,'failures':sum(not row['passed'] for row in checks),'targets':target_checks,
            'model_corrections':['Censored quantiles use the whole cohort, not only accounts that reached the milestone.','Core-pursuit policies reserve dust; an earlier greedy-spend draft could never buy a30-dust core from repeated15-dust settlements. Regression covers second core after two15-room settlements.','Incoming lower-rarity items cannot undo an already achieved quality milestone.','The first extra-core reserve is capped at its price and releases surplus to growth; an earlier draft accidentally reserved the entire first105-dust settlement. Regression verifies11 first-route draws and exactly one growth-first extra core.'],
            'baseline_current':{'target_specific_core_draws':distribution(old_target),'draw_cost':current['draw_cost'],'note':'Current runtime quality/core probabilities reimplemented with Python independent RNG. Counts exclude reforge and existing ownership; not Godot sequence or player simulation.'},
            'proposal_core_access':{'first_extra_core_dust':p['core_unlock_dust'],'room_threshold':next(room for room in range(1,61) if income(room,current)>=p['core_unlock_dust']),'remaining_nine_cost':9*p['core_unlock_dust'],'all_cores_if_save_only_full_routes':math.ceil(9*p['core_unlock_dust']/105)},
            'rarity_long_run_exact':long_run,'mean_draws_per_purple':expected_interval,'mean_salvage_essence_per_draw':expected_salvage,'rarity_seed_validation':rarity_samples,
            'progression_segments':segments,'core_price_sensitivity':sweeps,'purple_pity_sensitivity':pity_sweep,'grade_price_sensitivity':grade_price_sweep,'milestone_sensitivity':milestone_sweep,'attribute_budget':budget,
            'assumptions_and_omissions':['No new dust source; actual current route income read from data.','One-time new-account essence gifts12 at cumulative15 real settled cleared rooms and12 more at30 are proposal-only; they do not recur or increase105-dust route income.','Players repeat same clear-depth segment; no changing skill, win probability, elapsed minutes, full combat or real route.','Simulation starts with three selected green I stones.','Balanced policy banks for its first extra core, then reserves30% rounded-down of each new settlement for one core purchase per route; this is player budgeting, not a new wallet or purchase restriction.','Collection-first banks until all cores are unlocked, then funds one starter catalyst II/III before drawing. Growth-first banks for one extra core, then prioritizes attributes before returning to the catalog.','Selection policy models target profiles and deterministic upgrade/reforge path; does not claim globally optimal play.','Core mechanism changes are not included in attribute-only damage/EHP comparison.','Line-equivalent budgets are not utility equality; defense/heal/burn/summon interactions require combat validation.','Python independent seeds do not reproduce Godot RNG.','Existing inventory migration and compensation are only a design proposal; no accounts read or changed.']}
    output=args.output.resolve(); allowed=(ROOT/'build/qa').resolve()
    if not output.is_relative_to(allowed): raise SystemExit('Output must remain in project build/qa')
    output.mkdir(parents=True,exist_ok=True)
    (output/'results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    lines=['# Gem redesign v3: economy proposal model','',f'Validation: {len(checks)} checks / {result["failures"]} failures. Proposal only; no runtime changes.','',f'Exact steady purple fraction: {effective_purple:.6%}; mean {expected_interval:.3f} draws/purple. Mature all-salvage EV {expected_salvage:.3f} essence/draw. This is not new-player net materials.','',f'Current target-specific core draw distribution: {json.dumps(distribution(old_target))}. Proposed next core: {p["core_unlock_dust"]} dust, no random wait.','','| Clear depth | Policy | Three blue p50/p90 | Three purple p50/p90 | Perfect selected set p50/p90 | All cores p50/p90 |','|---|---|---|---|---|---|']
    for row in segments:
        values=[]
        for key in ['three_blue','three_purple','perfect_selected_set','all_cores']:
            d=row['milestones_routes'][key]; values.append(f'{d["p50"]}/{d["p90"]} ({d["reached"]}/{d["n"]} reached)')
        lines.append(f'| {row["cleared_rooms_per_route"]} | {row["policy"]} | '+ ' | '.join(values)+' |')
    lines+=['','## Targets',json.dumps(target_checks,ensure_ascii=False,indent=2),'','## Attribute-only comparison','',json.dumps(budget,ensure_ascii=False,indent=2),'','## Omissions','']+['- '+item for item in result['assumptions_and_omissions']]
    (output/'report.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(json.dumps({'checks':len(checks),'failures':result['failures'],'targets':target_checks,'balanced_full':full_balanced['milestones_routes'],'old_target_draws':distribution(old_target),'purple_exact':long_run,'salvage_ev':expected_salvage},ensure_ascii=False))

if __name__=='__main__': main()
