"""Historical reproduction: write migrated drafts only, never current themes.

Generate the review snapshot from the original candidate and executed results.
"""
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from design_documents import resolve_design_document

ROOT = Path(__file__).resolve().parents[3]
PARAMS = ROOT/"data/balance_candidates/first_run_v1.json"
RESULT = ROOT/"build/qa/first-run-balance-20261017/selected/results.json"
DEST = resolve_design_document(ROOT/"docs/游戏设计/05-首版数值与验证.md")
c = json.loads(PARAMS.read_text(encoding="utf-8"))
r = json.loads(RESULT.read_text(encoding="utf-8"))
assert r["config_sha256"] == hashlib.sha256(PARAMS.read_bytes()).hexdigest(), "Rerun model before generating review"
assert r["parameters"] == c, "Result overrides do not match authored candidate"
attack = c["player"]["attack"]
def num(value):
    return f"{value:g}"
def damage(coefficient):
    return num(attack*coefficient)
def pct(value):
    return num(value*100)+"%"
lines = []
def add(text=""):
    lines.append(text)
def table(headers, rows):
    add("| "+" | ".join(headers)+" |")
    add("|"+"|".join("---" for _ in headers)+"|")
    for row in rows:
        add("| "+" | ".join(str(v) for v in row)+" |")
    add()

add("# 首版数值与计算验证")
add()
add(f"日期：2026-10-17。参数版本 `{c['version']}`；模型 `{r['model_version']}`。")
add()
add("用户已确认怪物按[敌人与首领](04-敌人与首领.md)推进、酒馆免费回血并提高本局生命上限，并在本轮明确同意基础数值先按本版。基础参数作为首版制作基线，文件的candidate命名保留；尚未获得实机或体验认可。酒馆沿用原五个商店点。神器三项幅度作为已接受参照，由[神器表](02-火系神器.md)新增通用条目引用；新神器机制和品质仍为候选。")
add()
add("唯一可编辑参数源为[data中的候选表](../../data/balance_candidates/first_run_v1.json)，当前游戏不加载它；本页由[生成工具](../../tools/balance/first_run/write_review.py)导出为评审快照，不作为另一套运行默认值。调整参数后先重跑模型，再生成本页。")
add()
add("## 1. 目标与取舍")
add()
table(["观察项","候选目标","适用范围"],[("最早史莱姆", "两次一级焰弹非暴击击倒", "单敌、无遮挡、命中"),("三个基础开局",f"单体持续输出最大／最小≤{num(r['targets_and_guardrails']['starter_dps_ratio_max'])}","同命中假设、无宝石神器"),("首领战", "15房25—65秒；45房35—85秒；60房40—100秒", "三条普通构筑的模型中位数"),("较弱／较强路线", "单独设更宽耗时区间，保留差别", "不要求所有路线同DPS"),("生命与盾", "生命跨房消耗；盾每房重置；成长与补给共同承担整局预算", "不以固定初始生命估算整局"),("回盾组合", "持续承伤仍会破盾掉血", "固定承伤压力测试，不等于真实难度")])
add("法术关系属于情境型与可叠加收益的混合：单体、贯穿、覆盖、控制、回盾分别比较，不把它们压成同一条DPS曲线。")
add()
add("## 2. 角色与计算顺序")
add()
p=c["player"]
table(["初始属性","候选值","含义"],[("生命上限／当前生命",f"{p['health']}／{p['health']}","无宝石、无神器开局"),("护盾上限／当前护盾",f"{p['shield']}／{p['shield']}","每房清场补满，房内无自然恢复"),("攻击力",p['attack'],"所有伤害法术的共同基数"),("暴击率",pct(p['crit_rate']),"本表伤害未预先乘暴击期望"),("暴击伤害",pct(p['crit_multiplier']),"暴击造成普通伤害的此倍率"),("火属性伤害加成",pct(p['fire_bonus']),"精通与相性同组相加"),("移动速度",f"{num(p['move_speed'])}米／秒","移动不中断、不减慢自动吟唱"),("受击保护",f"{num(p['hurt_invulnerability'])}秒","实际受击后统一保护，护盾吸收也触发；没有闪避按键")])
add("伤害＝攻击力×（1＋法阵攻击增益）×伤害系数×（1＋基础火伤＋精通＋相性）×暴击倍率。每个有效伤害包各自判定暴击，最后四舍五入取整一次；先扣盾，溢出再扣生命。首版敌人无护甲、火抗或火免；持续火伤也可暴击，仍不触发只允许直接伤害的神器事件。")
add()
add(f"至少{c['fire_synergy']['distinct_spells']}种火系：火伤＋{pct(c['fire_synergy']['fire_bonus'])}、所有主动法术CD减少{pct(c['fire_synergy']['cooldown_reduction'])}。例如一级焰弹配一级精通与三火相性，非暴击伤害＝100×（1＋15%＋15%）＝130。")
add()
crit_cap = c["limits"].get("crit_rate")
crit_rule = "暴击率不设额外上限，达到100%时必定暴击，不产生超暴击" if crit_cap is None else f"本次历史敏感性配置的暴击率上限为{pct(crit_cap)}，实际暴击概率最高100%"
add(f"施放间隔＝成功释放后CD×（1－冷却缩减）＋自动前摇。缩CD不缩前摇、精灵射击间隔或神器触发间隔；最终缩减上限{pct(c['limits']['cooldown_reduction'])}，CD至少{num(c['limits']['minimum_cooldown'])}秒；{crit_rule}。回盾不受攻击、火伤或暴击增幅。")
add()
add("## 3. 酒馆与属性神器")
add()
rec=c["recovery"]
add(f"五个酒馆每店一次免费：先加{rec['shop_max_health_gain']}点本局生命上限，再回复新上限的{pct(rec['shop_fraction'])}；增加上限本身不另加当前生命。满旧上限时仍可获得本店成长与补给；重复进入不重复结算。候选恢复顺序和具体幅度仍需用户评审。")
add()
hp=p['health']
inn_rows=[]
for room in rec['shop_after']:
    hp += rec['shop_max_health_gain']
    inn_rows.append((f"{room}房后",hp,num(hp*rec['shop_fraction'])))
table(["酒馆节点","无生命神器时的新上限","本店最多回复"],inn_rows)
add(f"15／45房首领胜利后回复当时生命上限的{pct(rec['boss_fraction'])}，不加上限；无生命神器时分别最多回复80／95。恢复均封顶，死亡不能被战后补给救回。60房直接结算。")
add()
a=c['attribute_artifact_candidates']
table(["单件属性参照","候选幅度","边界"],[("生命上限",f"＋{a['health_max_flat']}","本局生效；增加上限本身不另回血，后续比例恢复读取新上限"),("护盾上限",f"＋{a['shield_max_flat']}","本局生效；下房按新盾上限补满，回盾单次值不自动变大"),("攻击力",f"＋{a['attack_flat']}","本局加算；不放大护盾回复")])
add("这是三个单件属性强度参照，未新建神器ID、名称、品质或掉落保证，也不表示同一件同时加三项。现有18件火系配套数量与职责保留；基础属性放入哪些现有／通用条目、品质权重和价格后续逐项设计。数值比较中的三件要占真实奖励选择，不能额外免费叠送。")
add()
add("## 4. 火系十法术：三级伤害与冷却")
add()
add(f"下表按攻击{attack}、无火伤／精通／相性／法阵／暴击／神器列值；伤害随攻击系数计算，不是固定点伤。持续伤害写完整命中上限，离开落点或火区会少受伤。")
add()
spell_rows=[]
for sid,s in c['spells'].items():
    lv=s['levels']; cells=[]
    for i,v in enumerate(lv):
        if sid=='F02': text=f"火伤＋{pct(v['fire_bonus'])}"+(f"；火系暴伤＋{num(v['crit_bonus']*100)}个百分点" if v['crit_bonus'] else "")
        elif sid=='F10': text=f"回复{num(v['shield'])}护盾"
        elif sid=='F01': text=damage(v['coefficient'])+(f"＋次弹{damage(v['secondary'])}" if v['secondary'] else "")
        elif sid=='F03': text=f"{v['drops']}落×{damage(v['coefficient'])}"+(f"；地表{damage(v['ground_coefficient'])}／{num(s['ground_interval'])}秒×{num(v['ground_duration'])}秒" if v['ground_duration'] else "")
        elif sid=='F04': text=f"{damage(v['coefficient'])}／{num(v['interval'])}秒"+("；贯穿" if v['pierce'] else "")
        elif sid=='F05': text=f"{damage(v['coefficient'])}／{num(s['interval'])}秒×{num(s['duration']+v['end_duration'])}秒"
        elif sid=='F06': text=f"{damage(v['coefficient'])}／{num(s['interval'])}秒×{num(v['duration'])}秒"+(f"；离阵增益保留{num(v['grace'])}秒" if v['grace'] else "")
        elif sid=='F07': text=f"中心{damage(v['coefficient'])}／外围{damage(v['outer'])}"+(f"；余震中心{damage(v['aftershock'])}／外围{damage(v['aftershock']*.5)}" if v['aftershock'] else "")
        elif sid=='F08': text=damage(v['coefficient'])+(f"＋脉冲{damage(v['secondary'])}" if v['secondary'] else "")
        elif sid=='F09': text=f"{damage(v['coefficient'])}；推{num(v['push'])}米"+(f"；减速{pct(v['slow'])}持续{num(v['slow_duration'])}秒" if v['slow'] else "")
        cells.append(text)
    cd="被动" if sid=='F02' else "／".join(num(v['cooldown']) for v in lv)+"秒" if sid=='F10' else num(s['cooldown'])+"秒"
    wind="—" if sid=='F02' else num(s['windup'])+"秒"
    spell_rows.append((sid+' '+s['name'],*cells,cd,wind))
table(["法术","一级","二级","三级","基础CD（一／二／三级）","前摇"],spell_rows)
add(f"精灵持续{num(c['spells']['F04']['duration'])}秒，首次射击等完整间隔，存续时不重召；F06站阵攻击＋{pct(c['spells']['F06']['attack_bonus'])}，自身区域不自我叠快照，同时仅一个法阵。旋涡／法阵／火雨留地从首个完整间隔开始跳伤；火雨首落另延迟{num(c['spells']['F03']['impact_delay'])}秒，额外区域遵守同源跳频与替换规则。")
add()
add("射程、半径、持续时间与推距也列在候选源表；F01典型飞行0.15秒、F07落地0.45秒仅为模型弹道假设，尚未确定真实弹速。不同法术可同时前摇，不建立全局吟唱锁。")
add()
add("## 5. 普通怪、精英与首领")
add()
add("采用四段固定表：段内不逐房自动涨血；难度也来自敌人组合、数量、地形与攻击错峰。数字格式为“生命／一次有效伤害”。M04在第二段第25房后才出现。")
add()
normal_rows=[]
for sid,info in c['normal_types'].items():
    values=[]
    for stage in c['normal_stages']:
        s=stage['stats'].get(sid)
        values.append(f"{s['health']}／{s['damage']}" if s else "—")
    normal_rows.append((info['name'],*values))
table(["普通怪","1—15房","16—30房","31—45房","46—60房"],normal_rows)
table(["精英房","精英","生命","各攻击伤害","普通伴随"],[(e['room'],e['name'],e['health'],'；'.join(f"{k}{v}" for k,v in e['attacks'].items()),'、'.join(c['normal_types'][k]['name'] for k in e['adds']) or '无') for e in c['elites']])
table(["首领房","首领","生命","各攻击伤害"],[(e['room'],e['name'],e['health'],'；'.join(f"{k}{v}" for k,v in e['attacks'].items())) for e in c['bosses']])
add("同一扑击／冲锋对同一玩家最多一次；多枚弹仍经过统一受击保护。最终首领50%生命切第二阶段，转换2秒，核心始终可受伤；一组史莱姆＋花妖最多2只，本组清空且18秒召唤间隔结束才可重召，死亡立即结算。")
add()
add("普通怪预警候选：史莱姆0.65秒、花妖0.8秒、冲锋兽1秒、术士1.1秒；首领主招至少1.1秒。只说明裸移速具有离开典型危险区的距离余量，不能据此认定墙角、导航、组合弹幕或实际像素都可躲。")
add()
add("## 6. 执行模型所得结果")
add()
add(f"{len(r['model_validation_cases'])}项已执行检查通过；{len(r['metrics_by_scenario'])}组报告情境，每组{r['seed_and_trial_count']['trials']}次固定种子试验，基础种子{r['seed_and_trial_count']['seed']}；敏感性网格另用16或32次。采用离散事件、逐包暴击与命中、死亡截断与过量伤害、独立前摇/CD、精灵寿命、法阵替换、有限召唤。")
add()
table(["基础开局","120秒单体平均DPS","说明"],[(c['spells'][e['spell']]['name'],f"{e['mean_dps']:.1f}","85%直射命中假设，无其他法术") for e in r['metrics_by_scenario'] if e['kind']=='starter'])
add(f"最大／最小比为{r['starter_ratio']:.3f}，在1.2以内。手算锚点：180生命史莱姆，两次100伤害焰弹，首次0.30秒、第二次1.65秒击倒；不是简单用180除DPS。")
add()
boss_rows=[]
for e in r['metrics_by_scenario']:
    if e['kind']=='boss':
        boss_rows.append((e['room'],r['scenarios']['paths'][e['path']]['name'],f"{e['median_s']:.1f}",f"{e['p90_s']:.1f}",e['status']))
table(["房间","固定构筑路线","中位耗时（秒）","P90（秒）","相对目标"],boss_rows)
add("三条普通路线无宝石神器；较弱路线同时降低命中／火区覆盖，不将差距全部归因于选法术。选择次数严格按首领前6／16／21次。固定路径不等于真实三选一获得概率，详见[情境输入](../../tools/balance/first_run/scenarios.json)。")
add()
table(["额外边界","模型中位结果","含义"],[(c['spells'][e['spell']]['name']+'三级＋护持三级，仅两种',f"15房{e['median_s']:.1f}秒", "不需三火或指定神器也有输出解") for e in r['metrics_by_scenario'] if e['kind']=='two_type_boundary']+[("八槽共21级选择点",f"60房{e['median_s']:.1f}秒","没有偷用八槽全三级24点") for e in r['metrics_by_scenario'] if e['kind']=='eight_slot_boundary'])
add("基础攻击神器＋15时，三条普通路线最终首领中位耗时约65—69秒；额外精灵也会明显加速。它们尚未证明与所有紫／金组合等价，后续需加入价格、品质与真实获取机会。")
add()
add("### 生存预算：区分固定失误、回盾时序与真实玩家")
add()
add("失误账本的中档假设：普通房2次史莱姆等价受击，房号为4的倍数时多1次；精英3次、首领4次，重型多招依次轮用伤害。不是实际AI、真实敌人配比或玩家通关率；该名字只表示情境档位。")
add()
labels={'cautious':'较少失误，无神器无F10','ordinary':'中档固定失误，酒馆成长，无神器无F10','ordinary_no_inn_growth':'同上但不加酒馆生命上限','ordinary_stat_artifacts':'同上并在6／12／21后分别拿生命80／盾25／攻击15','ordinary_F10_burst':'爆破路径带F10，受击分散','ordinary_F10_cluster_burst':'相同次数集中为每1.5秒受击','frequent_mistakes':'频繁失误，无神器无F10','ordinary_skip_shops':'跳过全部酒馆，中档固定失误'}
budget_rows=[]
for key,label in labels.items():
    e=r['attrition'][key]
    budget_rows.append((label,'到60房' if e['status']=='clear' else f"第{e['room']}房失败",num(e['health']),e['max_health']))
table(["对照情境","结果","剩余生命","当时上限"],budget_rows)
add("属性神器对照明确给定三件，不是保证每局获得；攻击15在固定受击账本中不减少失误次数。真实战斗里输出加快可能减少承伤，但本模型未把它虚构成已测收益。F10账本用普通12秒、精英25秒、首领50／70／80秒的假设时长；365与162生命的差异说明受击时序会大幅改变回盾价值，不能把某个结余当预测。")
add()
h=r['scenarios']['stress_hypotheses_not_item_balance']
add(f"另测每{num(h['incoming_interval'])}秒承受{h['incoming_damage']}伤害、持续60秒：只带回盾，中位生存{r['shield_stress']['shield_only']['median_survival_s']:.1f}秒；搭配序列、每{num(h['fountain_interval'])}秒减剩余CD及回盾＋{pct(h['shield_bonus'])}，中位{r['shield_stress']['shield_book_fountain_stress']['median_survival_s']:.1f}秒，64次均在60秒前倒下。该神器间隔／加成是压力假设，不是本轮批准的神器定值；也未覆盖全部金色联动，不能据此保证所有组合都需要走位。")
add()
add("## 7. 调整依据、未达目标与验收边界")
add()
add("保留300生命与100护盾开局。取消依据“全程固定上限、无神器、无回盾”的账本直接提高基础生命的推断，按用户追加规则引入酒馆与神器成长。酒馆每店＋20只是首版幅度；扫0／20／30说明仅提高上限并不能替代所有防御与走位。")
add()
add("同一修正后模型重跑基线：覆盖路线45房由101.8秒降至80.8秒，选择提高火雨、旋涡与法阵收益；6／12房精英生命调为2400／4000，避免初成型构筑过早结束检验。首领血量扫描75%会令初期强输出约14秒结束，125%会使中期覆盖／精灵或最终覆盖超过目标，保留当前血量。")
add()
misses=[e for e in r['metrics_by_scenario'] if e['status']!='within']
table(["保留观察项","中位耗时","相对目标"],[(e['name'],f"{e['median_s']:.2f}秒",e['status']) for e in misses])
add("四项偏离没有被隐藏：部分密集普通房开局爆发很快，39房辅助偏多且低命中的路径略慢。尚未确定实际房内数量、出生时序与可走区域，先保留观察，不用整体抬血抵消所有成长。更强的火焰宝石／金色组合也还需单独控制奖励时机。")
add()
add("模型1.2修正过F07余震：外围应为主爆325＋余震75＝400，不能给外围目标误结中心余震150。已经增加回归并重跑[同模型基线](../../build/qa/first-run-balance-20261017/baseline_replayed/results.json)与[当前结果](../../build/qa/first-run-balance-20261017/selected/results.json)。最初1.0基线仅作历史记录，不用它比较爆弹前后收益。")
add()
add("最小试玩安排：三个开局各完成1—15房；再用覆盖／精灵／爆破各测一次45与60房。记录每房耗时、首领前选择与神器、有效受击次数／间隔、到酒馆前生命、溢出治疗、F10有效回盾、是否看得清可走区域。若无F10路线普遍被迫拿某件生存神器，优先检查房内攻击重叠与生存选项，再调伤害／补给。")
add()
add("本轮未改旧游戏规则、场景、已有运行表或资产，未启动游戏、做Godot规则／画面验收或导出。模型不含完整位置、遮挡、导航、真实选敌、奖励抽样、宝石数值、商店经济、全部18件事件联动、真实局时长和跨房冷却行为；它给候选数量级与边界，不能替代实现后的体验验证。")
add()
add("复现命令与模型合同见[计算工具说明](../../tools/balance/first_run/README.md)；逐情境表见[CSV](../../build/qa/first-run-balance-20261017/selected/metrics.csv)。")
add()
DEST.write_text("\n".join(lines),encoding="utf-8")
print(f"Wrote {DEST} ({len(lines)} lines)")
