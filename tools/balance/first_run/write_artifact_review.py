"""Historical reproduction: write migrated drafts only, never current themes.

Render artifact values from their original parameter source and executed report.
"""
import hashlib
import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from design_documents import resolve_design_document

from artifacts import resolve_catalog

ROOT=Path(__file__).resolve().parents[3]
BASE=ROOT/"data/balance_candidates/first_run_v1.json"
SOURCE=ROOT/"data/balance_candidates/fire_artifacts_v1.json"
RESULT=ROOT/"build/qa/fire-artifacts-20261017/selected/results.json"
DOC=resolve_design_document(ROOT/"docs/游戏设计/02-火系神器.md")
REVIEW=resolve_design_document(ROOT/"docs/游戏设计/06-神器数值与验证.md")
base=json.loads(BASE.read_text(encoding="utf-8"))
raw=json.loads(SOURCE.read_text(encoding="utf-8"))
catalog=resolve_catalog(base,raw)
result=json.loads(RESULT.read_text(encoding="utf-8"))
assert result["base_sha256"]==hashlib.sha256(BASE.read_bytes()).hexdigest()
assert result["catalog_sha256"]==hashlib.sha256(SOURCE.read_bytes()).hexdigest()
assert result["catalog"]==catalog
items=catalog["items"]
attack=base["player"]["attack"]
rarity={"blue":"蓝色","purple":"紫色","gold":"金色"}
def n(v):return f"{v:g}"
def pct(v):return n(v*100)+"%"
def addpct(mult):return pct(mult-1)
def description(key,item):
    if key=="B01":return f"焰弹主／次弹爆炸半径＋{addpct(item['radius_multiplier'])}"
    if key=="B02":return f"火系暴击率＋{n(item['fire_crit_rate_add']*100)}个百分点（初始5%→20%）"
    if key=="B03":return f"每次火雨首落固定在锁定位置，首落伤害＋{addpct(item['first_drop_damage_multiplier'])}（60→90）；落火总数不变"
    if key=="B04":return f"精灵存续＋{n(item['duration_add'])}秒（12→16），常规激光伤害＋{addpct(item['normal_laser_damage_multiplier'])}"
    if key=="B05":return f"同一旋涡首次命中每个敌人，减速{pct(item['slow'])}、持续{n(item['duration'])}秒"
    if key=="B06":return f"法阵伤害／增益半径＋{addpct(item['radius_multiplier'])}；攻击增益仍为20%"
    if key=="B07":return f"主爆中心伤害＋{addpct(item['main_center_damage_multiplier'])}，该次中心命中的暴伤＋{n(item['main_center_crit_multiplier_add']*100)}个百分点"
    if key=="B08":return f"玩家光束与三级脉冲宽度＋{addpct(item['width_multiplier'])}（0.5→0.7米）"
    if key=="B09":return f"灼浪命中后移速＋{pct(item['move_speed_bonus'])}、持续{n(item['duration'])}秒（5→5.75米／秒）"
    if key=="B10":return f"护持单次回盾＋{item['shield_restore_add']}（一级30→45，二／三级45→60）"
    if key=="P01":return f"精灵数量＋{item['spirit_count_add']}，上限由1变2"
    if key=="P02":return f"自然直接火伤暴击生成半径{n(item['radius'])}米刻印；每{n(item['interval'])}秒造成{pct(item['coefficient'])}攻击力伤害，持续{n(item['duration'])}秒；每次自然施放最多1片"
    if key=="P03":return f"敌人同时处于至少{item['required_distinct_areas']}种不同法术区域时，额外承受{pct(item['fire_vulnerability'])}火伤；离开即结束"
    if key=="P04":return f"每{item['natural_casts_per_extra']}次自然施放，等权随机追加1个合法主动法术，使用当前等级、{pct(item['damage_multiplier'])}伤害／完整效果"
    if key=="P05":return f"每{n(item['interval'])}秒，所有主动法术当前剩余CD×{n(item['remaining_cooldown_multiplier'])}"
    if key=="G01":return f"火伤加成＋{pct(item['fire_bonus_add'])}；每{item['offensive_casts_per_echo']}次自然伤害施法，追加同法术{pct(item['echo_damage_multiplier'])}伤害余响"
    if key=="G02":return f"精灵存在时，自然伤害施法触发{pct(item['coefficient'])}攻击力协同激光；全部精灵共享{n(item['shared_cooldown'])}秒间隔"
    if key=="G03":return f"自然持续区域正常到期，产生半径{n(item['radius'])}米、{pct(item['coefficient'])}攻击力爆炸；每次自然施放最多1次"
    if key=="U01":return f"本局生命上限＋{item['health_max_add']}；增加上限本身不回血"
    if key=="U02":return f"本局护盾上限＋{item['shield_max_add']}；下一房按新上限补满"
    if key=="U03":return f"本局攻击力＋{item['attack_add']}（100→115），放大法术与伤害型神器"
    raise ValueError(key)

def markdown_table(headers,rows):
    return "\n".join(["| "+" | ".join(headers)+" |","|"+"|".join("---" for _ in headers)+"|"]+["| "+" | ".join(str(x) for x in row)+" |" for row in rows])+"\n"

block=["<!-- GENERATED:ARTIFACT-NUMBERS:BEGIN -->","## 首版数值制作基线","",f"参数版本 `{catalog['version']}`。用户已确认基础数值和本表21件神器先按此版推进；数值源保留candidate命名及原字节，未接入游戏、未实机验收。唯一神器调参源为[data神器表](../../data/balance_candidates/fire_artifacts_v1.json)，通用三件幅度通过base_ref引用已确认的基础表，不再复制一组默认值。","","18件火系配套保持蓝10／紫5／金3；另加3件通用（蓝2／紫1），合计21件。每件本局最多一件，不占法术槽，无神器升级或同名叠层。","",markdown_table(["编号","品质","名称","具体数值"],[(k,rarity[v['rarity']],v['name'],description(k,v)) for k,v in items.items()]),"伤害系数以角色当时攻击力为基数；示例按攻击100、未计精通／相性／法阵／暴击。15%暴击率是加15个百分点；半径＋30%对应理想几何面积＋69%，不等于实际伤害＋69%。完整计算及限制见[神器数值与验证](06-神器数值与验证.md)。","","<!-- GENERATED:ARTIFACT-NUMBERS:END -->",""]
text=DOC.read_text(encoding="utf-8-sig")
if "<!-- GENERATED:ARTIFACT-NUMBERS:BEGIN -->" in text:
    text=re.sub(r"<!-- GENERATED:ARTIFACT-NUMBERS:BEGIN -->[\s\S]*?<!-- GENERATED:ARTIFACT-NUMBERS:END -->\n?","\n".join(block),text,count=1)
else:
    text=text.replace("## 1. 品质分工","\n".join(block)+"## 1. 品质分工",1)
DOC.write_text(text,encoding="utf-8")

out=[]
def write(value=""):out.append(value)
write("# 神器数值与组合验证")
write()
write(f"日期：2026-10-17。用户已同意基础数值与21件神器先按本版推进；神器参数 `{catalog['version']}`、模型 `{result['model_version']}`。本页保留当时数值推导、固定库存模型证据与限制，不作为另一份运行默认参数，也不代表用户已确认神器体验。")
write()
write("[完整条目表](02-火系神器.md)读取[data神器源](../../data/balance_candidates/fire_artifacts_v1.json)生成；基础表保持字节不变。通用三件引用原基础表的80生命／25盾／15攻击参照。当前运行原型没有加载新表或新规则。")
write()
write("## 1. 本轮选择与目标")
write()
write(markdown_table(["内容","本轮选择","理由／观察目标"],[("数量","火系18＋通用3＝21","火系蓝10／紫5／金3；通用蓝2／紫1"),("普通专属蓝色","强化对应法术，保留范围／控制／防御价值","不把所有蓝色强行换算成相同单体DPS"),("紫色","组合、追加施法与冷却","以构筑实际边际收益比较，避免误读50%剩余CD"),("金色","围绕一条路线提供明显变化，有限触发","固定九件路线最终首领中位目标18—55秒"),("通用攻击","紫色、攻击＋15","影响全套法术与伤害型神器，价值范围大于单一法术伤害蓝色"),("生命／盾","蓝色、上限80／25","两者收益受当前缺口、房间重置与补给时机影响")]))
write("本轮数值没有新增神器装备槽、免费奖励、道具升级或额外恢复服务。后续已获用户同意的[金币、商店与品质基线](07-金币商店与品质.md)独立设计真实获取预算；本页九件路线仍是固定库存对照，不假设三件通用必定获得。")
write()
write("## 2. 三项蓝色补强与金色定位")
write()
write("B03保留首落固定锁定位置，并让原有首落伤害＋50%；不是追踪目标，也不增加第七／第九次落火。B04仅延长精灵时长收益很小，因为基础存续与冷却都为12秒，所以增加常规激光伤害10%。B07在初始5%暴击率下仅加暴伤不明显，补中心主爆伤害15%，再加50个百分点中心暴伤。")
write()
write("G01增加15%火伤加成并保留70%弱余响，帮助它与紫色序列之书区分；火伤与精通／三火同组相加。例如三级精通35%＋三火15%＋炎冠15%＝65%，伤害火伤因子1.65，不是三个百分比相乘。G02为独立250%攻击力协同激光；G03为400%攻击力终焰。所有调整仅作用神器，基础法术与敌人未调。")
write()
write("## 3. 结算与组合边界")
write()
write("- 蓝色的范围、暴击、激光伤害、固定首落、推浪移速与回盾改造，作用于对应自然／附加法术。B05和B09属于法术附带状态，不另外生成伤害或施法计数。")
write("- 序列每3次自然施放追加1次当前等级法术；被动不算，精灵射击不算。排除满盾回盾、满员召唤及无合法近敌的灼浪；无候选就跳过本次，不存次数。附加法术不等前摇、不修改本体CD、不再触发事件型神器。")
write("- 炎冠只计玩家主动伤害法术，排除精通、召唤与回盾。余响伤害70%，持续／范围／控制保留；法阵余响仍替换原阵，不能叠攻击增益。")
write("- 刻印只由自然直接火伤暴击触发：焰弹、火雨落击、爆弹、玩家光束、灼浪可触发；火雨地表、旋涡、法阵、精灵射击及神器附加结果不触发。同次自然施放最多1片；重叠对同敌取最高有效伤害，0.5秒内不重复跳。")
write("- 共鸣需同时处于至少两种不同法术区域：火雨、旋涡、法阵；同法术两片不够，刻印与终焰不算新法术种类。20%为敌方额外火伤承受因子，和玩家火伤组分别计算；离开立即取消。")
write("- 协同激光只在精灵存在、目标合法且共享2秒间隔结束时触发；一只或两只精灵都只追加一次，不重置常规射击。继承精灵等级的贯穿资格（三级才贯穿）与射程；伤害使用独立系数，不吃B04仅限常规激光的10%，也不吃B08玩家光束宽度。")
write("- 终焰只认自然区域正常到期，每次施放1次；火雨需三级留地。提前替换法阵、碰撞／清场提前移除与神器附加区域都不触发。序列、炎冠可能提前替换法阵，减少终焰次数；源泉加速后也可能出现这种取舍。")
write("- 回风25%减速与灼浪三级30%减速取较高者；减速只影响追击／换位，不改变已锁定冲锋或弹速。鼓风15%移速刷新2秒，最高仍15%，不按人数或追加次数叠百分比。")
write("- 每房清场清空序列／炎冠计数与源泉计时；奖励、酒馆、暂停、结算不推进。源泉首轮在进入战斗8秒后，不减自身或其他神器CD、不减前摇与精灵射击间隔。")
write()
write("## 4. 通用神器与酒馆")
write()
write("三件无元素／持有法术条件，均限本局、各一件。生命琥珀增加上限本身不补当前生命；未来酒馆20%与首领25%按新上限计算。早拿生命80时，后续每店理论最多多恢复16、每个首领节点最多多恢复20，均受缺血封顶；五店后无其他生命加成的上限为480。")
write()
write("护壁晶核增加盾上限，后续每房按新上限125补满；暖焰护持单次回复量不随盾上限变大。增幅棱晶让攻击100→115，也放大刻印、协同激光、终焰，仍不放大回盾。")
write()
write("酒馆按原流程首次进入先结算免费成长／回血，再购买；当店买到生命神器不重结算已完成的免费补给。拿神器占该次奖励或购买机会，不在原9个神器箱外再赠送。")
write()
write("## 5. 执行验证与单件结果")
write()
write(f"执行{len(result['checks'])}项检查（含基础模型回归），报告{len(result['metrics'])}组情境，主要每组{result['scenarios']['trials']}次、基础种子{result['scenarios']['seed']}；另{len(result['sweeps'])}组参数网格各16次。保留[初始方案](../../build/qa/fire-artifacts-20261017/baseline/results.json)与[当前结果](../../build/qa/fire-artifacts-20261017/selected/results.json)。")
write()
write("模型有来源标记，逐项区分自然施法、精灵普攻、序列、炎冠、刻印、协同与终焰；单次多弹不多计自然次数。新基础扩展与旧115组无神器指标／生存结果一致，基础源SHA256保持不变。另验证叠加刻印取高、附加不递归、共享协同CD、三级贯穿、被替换法阵无终焰与0.5秒同源跳频。")
write()
singles={}
for m in result['metrics']:
    if m['kind']=='single_item':singles.setdefault(m['item'],{})[m['targets']]=m
rows=[]
for key,item in items.items():
    one,group=singles[key][1],singles[key][3]
    note="含假设覆盖收益" if key in {"B01","B06","B08"} else "状态收益另看，未假设自动少挨打" if key in {"B05","B09","B10","U01","U02"} else "该固定构筑的边际值"
    rows.append((key+' '+item['name'],f"{(one['damage_ratio']-1)*100:.1f}%",f"{(group['damage_ratio']-1)*100:.1f}%",note))
write(markdown_table(["单件","单体平均输出变化","三目标平均输出变化","解释"],rows))
write("探针是八槽21选择点，不是单法术：B07／B09各用对应法术替换F05，保证资格。单体测试把几何收益设零，三目标使用显式密度／覆盖假设；B05、B09与生存件的零输出变化不等于零价值。微小差异可有抽样波动，不能用小数点后的收益强行排序。")
write()
pair_rows=[(m['name'],'＋'.join(items[k]['name'] for k in m['owned']),f"{(m['damage_ratio']-1)*100:.1f}%") for m in result['metrics'] if m['kind']=='pair']
write(markdown_table(["交互对照","组合","该探针平均输出变化"],pair_rows))
write("暴击书也提高刻印触发概率；精灵数量与协同激光不按人数相乘；炎冠／序列的边际收益要按当前主动池与法阵替换计算，不能把两件的单件百分比直接相加。")
write()
write("## 6. 固定成长路线与压力")
write()
route_rows=[]
route_names={"burst":"连发爆破","spirit":"精灵协同","area":"阵地覆盖","event_stack":"高频事件组合参考"}
for m in result['metrics']:
    if m['kind']=='route':
        route_rows.append((route_names[m['route']],m['room'],len(m['owned']),f"{m['baseline_median_s']:.1f}",f"{m['median_s']:.1f}",f"{m['p90_s']:.1f}",m.get('status','基准观察')))
write(markdown_table(["路线","首领房","神器件数","无神器中位秒","有神器中位秒","有神器P90秒","相对目标"],route_rows))
write("15／45／60房前分别只有2／6／9个已讨论的箱子机会，路线按此限制，法术仍6／16／21次选择。未加入商店购买与局外宝石。指定拿取是对照条件，不代表真实掉落或必出；高频参考没有经过全组合最优化。")
write()
upper=next(m for m in result['metrics'] if m['kind']=='inventory_upper_bound')
write(f"额外测试该八槽构筑全部{len(upper['owned'])}件合资格神器：最终首领中位{upper['median_s']:.1f}秒。它超过9箱预算，商店获取能力也未确定，故只作库存／事件上界压测，不能当普通成型构筑，也不能据此说最强构筑只需此时间。")
write()
pressure_rows=[]
for name,m in result['pressure'].items():
    pressure_rows.append((name,f"{m['median_s']:.1f}",f"{m['p90_s']:.1f}",f"{m['survived_to_horizon']}／{m['trials']}"))
write(markdown_table(["固定承伤情境","中位生存秒","P90秒","撑到120秒次数"],pressure_rows))
write("压力从五店后的400满生命进入，组合加入生命80／盾25；三级护持与其他法术共21点。每1.5秒受轻型48或重型75伤害，组合为B10＋序列＋源泉＋生命琥珀＋护壁晶核。不是实际敌人AI、玩家受击率或通关率，也未把控制／速度虚构成减伤。")
write()
budget_rows=[]
for key,m in result['generic_budgets'].items():
    budget_rows.append(('无属性神器' if key=='None' else items[key]['name'],f"到60房，余{n(m['health'])}" if m['status']=='clear' else f"第{m['room']}房失败",m['cap']))
write(markdown_table(["第6房后选一件的固定失误账本","结果","当时生命上限"],budget_rows))
write("账本用上一轮固定失误，不含F10与输出缩短战斗所减少的挨打次数。因此攻击件与无道具相同是模型限制；盾件在这组跨房消耗中较好，也不能据此断言生命件没有价值。")
write()
write("## 7. 扫描、选择与后续试玩")
write()
scan_rows=[]
for axis,label in (("fountain_interval","源泉间隔"),("echo_multiplier","炎冠余响系数"),("synced_laser_coefficient","协同伤害系数"),("terminal_coefficient","终焰伤害系数")):
    for value in result['scenarios']['sweeps'][axis]:
        entries=[m for m in result['sweeps'] if m['axis']==axis and m['value']==value]
        scan_rows.append((label,n(value),'；'.join(route_names[m['route']]+f" {m['median_s']:.1f}秒" for m in entries)))
write(markdown_table(["参数","扫描值","固定九件路线最终首领中位"],scan_rows))
write("采用8秒源泉、70%余响、250%协同与400%终焰作为首版中间方案。更快源泉未在每条路线都更强，法阵替换、首领召唤分流、离散落击与采样都会影响结果；不声称8秒为数学最优。更高终焰／100%余响会进一步压缩强组合，先保留首领展示窗口。")
write()
write("本固定库存模型未含真实奖励分布、价格与投放时机；这些由后续已同意的07经济基线与模型另行处理，不回写本页固定九件证据。仍需实机核对：专属蓝色的范围／命中一致性在真实地形里是否有足够价值；所有九件组合的强弱上界；实际预警可读性与首领攻防。几何收益在零至均匀密度假设之间插值，缺少导航／碰撞／站位实测，不是同等百分比的伤害承诺。")
write()
write("最小试玩：每条路线分别比较无神器、1件核心、6件、9件；记录每件实际追加伤害／回盾、无效追加、终焰被替换次数、到酒馆的生命／上限与首领阶段存续时间。若通用攻击压过所有专属选项，或固定某件才可通关，再调整该品质投放与具体效果，不回改已确认基础值掩盖问题。")
write()
write("本轮只维护设计参数、独立模型与文档，未修改运行游戏规则／场景／资产，未启动游戏或进行Godot画面、导出、用户体验验收。复现步骤见[工具说明](../../tools/balance/first_run/README.md)，逐情境数据见[CSV](../../build/qa/fire-artifacts-20261017/selected/metrics.csv)。")
write()
REVIEW.write_text("\n".join(out),encoding="utf-8")
print("Artifact tables and review generated from matching source/report hashes.")
