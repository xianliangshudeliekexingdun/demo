"""Proposal-only bounded common-core arithmetic, never a Godot/runtime simulator."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MODEL_VERSION = 'gem-redesign-v3-common-model-1.1'

def critical_factor(rate, multiplier):
    return 1 + min(1, max(0, rate)) * (multiplier - 1)

def fracture_factor(rate, multiplier, targets, spec):
    links = min(max(0, targets - 1), spec['bounce_count'])
    extra = spec['primary_extra_multiplier'] * sum(spec['bounce_multiplier'] ** i for i in range(links + 1))
    return 1 + min(1, max(0, rate)) * (multiplier - 1) * extra

def echo_factor(rate, multiplier, hit_fraction, spec):
    return spec['immediate_multiplier'] + spec['replay_noncritical_multiplier'] * hit_fraction / critical_factor(rate, multiplier)

def blood_average(horizon, initial_fraction, spec):
    # Analytic average, no enemy hit/heal: start below drain floor is never healed.
    rate, floor = spec['drain_max_health_fraction_per_second'], spec['drain_floor_fraction']
    stop = max(0, (initial_fraction - floor) / rate)
    moving = min(horizon, stop)
    end = initial_fraction - rate * moving
    area = (initial_fraction + end) * 0.5 * moving + end * (horizon - moving)
    return {'end_health_fraction': end, 'average_damage_multiplier': 1 + (1 - area / horizon) * spec['damage_per_missing_fraction']}

def aegis_caps(health, shield, spec):
    consumed = health * spec['life_conversion']
    return health - consumed, shield + consumed * spec['shield_per_life']

def run(params):
    checks = []
    def check(name, ok, details=None):
        checks.append({'id': name, 'passed': bool(ok), 'details': details})
    # Fixed calibration fixtures are independent of editable candidate parameters.
    canonical_fracture = {'primary_extra_multiplier':1.8, 'bounce_count':2, 'bounce_multiplier':.5}
    canonical_echo = {'immediate_multiplier':.8, 'replay_noncritical_multiplier':.65}
    canonical_blood = {'drain_max_health_fraction_per_second':.01, 'drain_floor_fraction':.35, 'damage_per_missing_fraction':1.0}
    canonical_aegis = {'life_conversion':.3, 'shield_per_life':2.2}
    check('candidate fracture parameter domain', params['fracture']['primary_extra_multiplier'] >= 0 and 0 <= params['fracture']['bounce_multiplier'] <= 1 and isinstance(params['fracture']['bounce_count'], int) and params['fracture']['bounce_count'] >= 0)
    check('candidate echo parameter domain', params['echo']['immediate_multiplier'] >= 0 and params['echo']['replay_noncritical_multiplier'] >= 0)
    check('candidate blood parameter domain', params['sacrifice']['drain_max_health_fraction_per_second'] > 0 and 0 <= params['sacrifice']['drain_floor_fraction'] <= 1 and params['sacrifice']['damage_per_missing_fraction'] >= 0)
    check('candidate aegis parameter domain', 0 < params['aegis']['life_conversion'] < 1 and params['aegis']['shield_per_life'] > 1 and params['aegis']['combat_health_restore_conversion'] >= 0)
    invalid = [item['id'] for item in checks if not item['passed']]
    if invalid:
        raise ValueError('Invalid candidate parameters: '+', '.join(invalid))
    check('baseline 100 attack 5pct crit 1.5 => 102.5', math.isclose(100 * critical_factor(.05, 1.5), 102.5))
    check('critical excess above 100pct does not add layers', critical_factor(1.25, 2) == critical_factor(1, 2))
    check('fracture calibration solo 25pct 2x => 145', math.isclose(100 * fracture_factor(.25, 2, 1, canonical_fracture), 145))
    check('fracture no crit changes nothing', fracture_factor(0, 3, 6, params['fracture']) == 1)
    check('fracture calibration no unused bounce to solo', fracture_factor(.5, 2, 1, canonical_fracture) < fracture_factor(.5, 2, 3, canonical_fracture))
    finite_targets = params['fracture']['bounce_count'] + 1
    check('fracture finite links exhaust at candidate cap', fracture_factor(.5, 2, finite_targets, params['fracture']) == fracture_factor(.5, 2, finite_targets+100, params['fracture']))
    check('echo calibration no geometry hit => immediate 80pct', echo_factor(.25, 2, 0, canonical_echo) == .8)
    check('echo calibration no crit full hit => 145pct', math.isclose(echo_factor(0, 2, 1, canonical_echo), 1.45))
    check('echo cdr preserved proposal', params['echo']['preserve_cdr'] is True)
    blood = blood_average(30, 1, canonical_blood)
    check('blood hand 30s full health => end70pct mean115pct', math.isclose(blood['end_health_fraction'], .7) and math.isclose(blood['average_damage_multiplier'], 1.15))
    check('blood calibration does not heal initial10pct to35pct', math.isclose(blood_average(30, .1, canonical_blood)['end_health_fraction'], .1))
    h, s = aegis_caps(300, 100, canonical_aegis)
    check('aegis hand 300/100 => 210/298', math.isclose(h, 210) and math.isclose(s, 298))
    check('aegis full shield discards restoration', min(25, max(0, s-s)) == 0)
    crit_rows, echo_rows, blood_rows, shield_rows = [], [], [], []
    scenarios = params['scenarios']
    for rate in scenarios['crit_rates']:
        for mult in scenarios['crit_multipliers']:
            baseline = critical_factor(rate, mult)
            for targets in [1, 2, 3, 6]:
                outcome = fracture_factor(rate, mult, targets, params['fracture']) / baseline
                crit_rows.append({'crit_rate': rate, 'crit_multiplier': mult, 'targets': targets, 'gain_fraction': outcome-1})
                check('fracture finite nonnegative', math.isfinite(outcome) and outcome >= 1)
            for hit in scenarios['echo_hit_fractions']:
                outcome = echo_factor(rate, mult, hit, params['echo'])
                echo_rows.append({'crit_rate': rate, 'crit_multiplier': mult, 'replay_hit_fraction': hit, 'body_gain_fraction': outcome-1})
                check('echo bounded analytic body ratio', params['echo']['immediate_multiplier'] - 1e-9 <= outcome <= params['echo']['immediate_multiplier'] + params['echo']['replay_noncritical_multiplier'] + 1e-9)
    for seconds in scenarios['blood_horizons']:
        for initial in scenarios['initial_health_fractions']:
            row = blood_average(seconds, initial, params['sacrifice'])
            row.update(horizon_seconds=seconds, initial_health_fraction=initial)
            blood_rows.append(row)
            check('blood no healing or negative health from selfdrain', 0 <= row['end_health_fraction'] <= initial)
            floor = params['sacrifice']['drain_floor_fraction']
            check('blood floor applies only when started above floor', initial < floor or row['end_health_fraction'] >= floor-1e-9)
    for health in scenarios['aegis_health']:
        for shield in scenarios['aegis_shield']:
            new_h, new_s = aegis_caps(health, shield, params['aegis'])
            for defense in scenarios['defense_values']:
                mitigation_factor = max(.55, 100/(100+max(0, defense)))
                shield_rows.append({'health': health, 'shield': shield, 'defense': defense, 'new_health':new_h,'new_shield':new_s,
                                    'effective_pool_before':(health+shield)/mitigation_factor,'effective_pool_after':(new_h+new_s)/mitigation_factor,
                                    'pool_gain_fraction':(new_h+new_s)/(health+shield)-1})
                check('aegis caps finite positive', new_h > 0 and new_s > 0 and new_h+new_s > health+shield)
    # Adjacent existing GT04 -> GT01 healing-conversion loop loses resources.
    cup = json.loads((ROOT/'data/generic_artifacts_v1.json').read_text(encoding='utf-8-sig'))
    artifacts = cup.get('artifacts', cup.get('items', {}))
    if isinstance(artifacts, list): artifacts = {item['id']:item for item in artifacts}
    vessel, reliquary = artifacts['GT04'], artifacts['GT01']
    refund_ratio = vessel['health_restore'] * params['aegis']['combat_health_restore_conversion'] * reliquary['shield_restore_multiplier'] / vessel['shield_loss_threshold']
    check('GT04 converted heal cannot replace all triggering shield loss', refund_ratio < 1, refund_ratio)
    sweep = {'fracture':[], 'echo':[], 'aegis':[]}
    for value in params['tuning']['fracture_primary_candidates']:
        spec = {**params['fracture'], 'primary_extra_multiplier':value}
        sweep['fracture'].append({'primary_extra_multiplier':value,'solo_25pct_crit_gain':fracture_factor(.25,2,1,spec)/1.25-1,
                                  'three_target_25pct_crit_gain':fracture_factor(.25,2,3,spec)/1.25-1})
    for value in params['tuning']['echo_replay_candidates']:
        spec = {**params['echo'], 'replay_noncritical_multiplier':value}
        sweep['echo'].append({'replay_multiplier':value,'gain_5pctcrit_80pcthit':echo_factor(.05,1.5,.8,spec)-1,
                              'gain_50pctcrit_50pcthit':echo_factor(.5,2,.5,spec)-1})
    for value in params['tuning']['aegis_shield_per_life_candidates']:
        spec = {**params['aegis'], 'shield_per_life':value}
        h,s=aegis_caps(300,100,spec)
        sweep['aegis'].append({'shield_per_life':value,'pool_gain_fraction':(h+s)/400-1})
    warning_cases = []
    if max(row['gain_fraction'] for row in crit_rows) > 1:
        warning_cases.append('High crit-damage plus three valid targets more than doubles aggregate damage from this source; situational chain ceiling, not single-target gain or measured whole-build DPS. Needs native geometry/TTK comparison.')
    if any(row['body_gain_fraction'] < 0 for row in echo_rows):
        warning_cases.append('Echo loses damage at low replay hit rate/high crit damage by design; UI must disclose delayed-shot risk and compatible body-only scope.')
    return {'model_version':MODEL_VERSION,'parameter_version':params['version'],'status':'proposal_only_not_implemented',
            'model_validation_cases':checks,'checks':len(checks),'failures':sum(not item['passed'] for item in checks),
            'scenarios':{'fracture':crit_rows,'echo':echo_rows,'sacrifice':blood_rows,'aegis':shield_rows},
            'sweep':sweep,'warnings':warning_cases,'existing_GT04_GT01_refund_ratio':refund_ratio,
            'assumptions_and_omissions':['Deterministic algebra and analytic no-heal health integration. Hit fraction/target availability are inputs, not simulated aim or navigation.',
            'No enemy AI, positions, route, actual spell rotation, natural reward RNG, invulnerability phases or player testing. Body gain does not equal whole-build gain.',
            'Fracture links replace only critical extra damage and never revisit; no critical RNG sampled, exact expectation with chance clamped at one.',
            'Echo replay is noncritical and causes no status/on-hit callbacks; ordinary CDR remains intact. Other body/state timing is not simulated.',
            'Blood self-loss does not trigger hurt/recovery; ordinary enemy damage can still kill below its drain floor.',
            'Effective shield+life pool is an arithmetic pool, not survival time or safety against a specific boss.']}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--parameters',type=Path,default=Path(__file__).with_name('common_parameters.json'))
    parser.add_argument('--output',type=Path,default=ROOT/'build/qa/gem-redesign-v3-20261022/common')
    args=parser.parse_args()
    output=args.output.resolve(); allowed=(ROOT/'build/qa').resolve()
    if not output.is_relative_to(allowed): raise SystemExit('Output must stay inside project build/qa')
    params=json.loads(args.parameters.read_text(encoding='utf-8-sig'))
    try:
        result=run(params)
    except (ValueError, KeyError, TypeError) as exc:
        print(json.dumps({'status':'invalid_parameters','error':str(exc)},ensure_ascii=False))
        raise SystemExit(1)
    result['parameters']=params
    result['source_sha256']={str(path.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__),args.parameters,ROOT/'data/generic_artifacts_v1.json']}
    output.mkdir(parents=True,exist_ok=True)
    (output/'results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    lines=['# Common core proposal arithmetic',f'Model: {MODEL_VERSION}; checks {result["checks"]}, failures {result["failures"]}.',
           'Proposal only. No runtime integration or gameplay acceptance.','',
           'Fracture @25% crit / 2.0x: solo '+format((fracture_factor(.25,2,1,params['fracture'])/1.25-1)*100,'.2f')+'%, three real targets '+format((fracture_factor(.25,2,3,params['fracture'])/1.25-1)*100,'.2f')+'%.',
           'Echo @5% crit / 1.5x / 80% replay accuracy: '+format((echo_factor(.05,1.5,.8,params['echo'])-1)*100,'.2f')+'% body gain.',
           'Blood 30s from full: '+json.dumps(blood_average(30,1,params['sacrifice'])),
           'Aegis 300HP/100shield: '+json.dumps(aegis_caps(300,100,params['aegis'])),
           'Fixed hand-calibration fixtures are separate from editable candidate parameter validation.','',*result['warnings']]
    (output/'report.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(json.dumps({'checks':result['checks'],'failures':result['failures'],'warnings':result['warnings']},ensure_ascii=False))
    raise SystemExit(1 if result['failures'] else 0)

if __name__=='__main__': main()
