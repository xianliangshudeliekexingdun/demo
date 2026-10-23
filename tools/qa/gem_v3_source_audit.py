"""Current gem implementation: runtime contract, protected files, dependencies, sources and docs.

No gameplay, image rendering, profile access, export or remote operations.
"""
from __future__ import annotations
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/qa/gem-v3-implementation-20261022'

def sha(path: Path) -> str:
    result = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024*1024), b''):
            result.update(block)
    return result.hexdigest()

def main() -> int:
    checks, warnings = [], []
    def check(label, passed, details=None):
        checks.append({'check':label,'passed':bool(passed),'details':details})
    before = json.loads((ROOT/'build/qa/gem-redesign-v3-20261022/runtime_baseline.json').read_text('utf-8-sig'))
    protected = {path:value for path,value in before.items() if path.startswith(('assets/','scenes/')) or path.startswith('data/') and path!='data/magic_gems_v1.json' or path.endswith('.exe') or path=='project.godot'}
    for relative,value in protected.items():
        path=ROOT/relative
        check('protected original art/scenes/other data/engine unchanged',path.is_file() and sha(path)==value,relative)
    data = json.loads((ROOT/'data/magic_gems_v1.json').read_text('utf-8-sig'))
    check('exact approved ten active core IDs',set(data['cores'])=={'inferno','coffin','lightning','wind','earth','spirit','fracture','echo','sacrifice','aegis'})
    check('separate fixed core and three attribute slots',data['slots']==4 and data['affix_counts']=={'green':1,'blue':2,'purple':3,'gold':0})
    check('core price, three starter stones and one-time supply',data['core_unlock_cost']==30 and data['starter_attribute_count']==3 and data['milestone_essence']==[{'cleared':15,'essence':12},{'cleared':30,'essence':12}])
    check('attribute-only random pool and purple guarantee',data['draw_cost']==5 and data['base_weights']=={'green':60,'blue':30,'purple':10} and data['pity']=={'purple_or_better':10} and data['tier_weights']==[60,30,10])
    for stat,spec in data['affixes'].items():
        check('main two side-budget units in each tier',spec['main_tiers']==[value*2 for value in spec['tiers']],stat)
    proposal=json.loads((ROOT/'tools/balance/gem_redesign_v3/common_parameters.json').read_text('utf-8-sig'))
    maps={'fracture':{'extra_damage_multiplier':'primary_extra_multiplier','first_delay':'first_delay','bounce_delay':'bounce_delay','bounce_count':'bounce_count','bounce_multiplier':'bounce_multiplier','radius':'radius'},
          'echo':{'immediate_multiplier':'immediate_multiplier','base_multiplier':'replay_noncritical_multiplier','delay':'delay'},
          'sacrifice':{'drain_max_health_per_second':'drain_max_health_fraction_per_second','drain_floor_fraction':'drain_floor_fraction','damage_per_missing_fraction':'damage_per_missing_fraction'},
          'aegis':{'life_conversion':'life_conversion','shield_per_life':'shield_per_life','combat_health_restore_conversion':'combat_health_restore_conversion'}}
    for core,fields in maps.items():
        for field,source in fields.items():check('approved common-core numeric mapping',data['cores'][core][field]==proposal[core][source],[core,field])
    lines=(ROOT/'export_presets.cfg').read_text('utf-8-sig').splitlines()
    scripts=re.findall(r'"res://([^\"]+)"',next(line for line in lines if line.startswith('export_files=')))
    includes=next(line for line in lines if line.startswith('include_filter=')).split('"')[1].split(',')
    exported=set(scripts+includes)
    check('explicit export resource entries unique',len(scripts)==len(set(scripts)))
    for relative in scripts+includes:
        check('explicit runtime dependency exists',(ROOT/relative).is_file(),relative)
        check('no test/tool/build/engine bundled',not relative.startswith(('build/','tools/','tests/','.godot/')) and not relative.endswith('.exe'),relative)
    for relative in ['scripts/core/route_gem_schools.gd','scripts/ui/gem_icon.gd','scripts/presentation/route_gem_vfx.gd']:
        check('new runtime dependency explicitly exported',relative in exported,relative)
    for relative in scripts:
        path=ROOT/relative
        if path.suffix not in {'.gd','.tscn','.tres','.gdshader'}: continue
        content=path.read_text('utf-8-sig')
        for ref in re.findall(r'["\']res://([^"\'\n]+)["\']',content):
            target=ROOT/ref
            check('literal runtime dependency exists',target.exists(),[relative,ref])
            if target.is_file():check('literal runtime dependency exported',ref in exported,[relative,ref])
        check('no offline gem model runtime dependency','tools/balance/gem_redesign_v3' not in content,relative)
    registry=json.loads((ROOT/'docs/assets.json').read_text('utf-8-sig'))
    targets=[row['target'] for row in registry if 'target' in row]
    check('registry has no duplicate target',len(targets)==len(set(targets)))
    for row in registry:
        if 'gem_v3_revision' not in row: continue
        path=ROOT/row['target']
        check('gem presentation source registered and current',path.is_file() and sha(path)==row['sha256'] and len(path.read_bytes())==row['bytes'],row['target'])
    documents=['README.md','docs/项目架构.md','docs/功能模块.md','docs/游戏设计/局外养成.md','docs/游戏设计/未来方案/README.md','docs/游戏设计/未来方案/25-新版魔法宝石十核心与养成提案.md','docs/历史决策/README.md','docs/历史决策/归档/30-新版宝石整体规划与十核心提案.md','tools/balance/gem_redesign_v3/README.md']
    for relative in documents:
        path=ROOT/relative
        for ref in re.findall(r'\]\(([^\s)]+)\)',path.read_text('utf-8-sig')):
            if '://' in ref or ref.startswith('#'): continue
            check('documentation reference exists',(path.parent/ref.split('#',1)[0]).exists(),[relative,ref])
    # Each native report's declared sources must be the current bytes.
    for folder,file in [('economy','results.json'),('schools','results.json'),('ui-vfx','results.json'),('formal-fire','rules.json'),('formal-ice','rules.json'),('formal-lightning','results.json'),('formal-earth','results.json'),('formal-spirit','results.json')]:
        path=OUT/folder/file
        report=json.loads(path.read_text('utf-8-sig'))
        for relative,value in report.get('source_sha256',report.get('source_hashes',{})).items():
            target=ROOT/relative.removeprefix('res://')
            check('native report inputs match final source bytes',target.is_file() and sha(target)==value,[folder,relative])
    if (OUT/'historical-report-recovery.json').exists():
        warnings.append('Historical report default-path incident: see historical-report-recovery.json. Do not use missing prior raw reports as direct evidence.')
    result={'checks':len(checks),'failures':sum(not row['passed'] for row in checks),'details':checks,'warnings':warnings,'protected_files':len(protected),'exported_resources':len(exported),'scope':'Local source/contract/reference/dependency audit only; no export, pixels, performance, real profile access or remote work.'}
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'static-audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({key:result[key] for key in ['checks','failures','protected_files','exported_resources','warnings']},ensure_ascii=False))
    for row in checks:
        if not row['passed']:print('FAIL',row)
    return int(result['failures']>0)

if __name__=='__main__': raise SystemExit(main())
