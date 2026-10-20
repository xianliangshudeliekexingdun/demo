"""Historical reproduction: write migrated drafts only, never current themes.

Generate the original simplified meta design from its source and verified result.
"""
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from design_documents import resolve_design_document

ROOT=Path(__file__).resolve().parents[3]
SOURCE=ROOT/"data/balance_candidates/meta_growth_v1.json"
REPORT=ROOT/"build/qa/meta-growth-20261017/selected/results.json"
DOC=resolve_design_document(ROOT/"docs/游戏设计/08-局外成长触媒与宝石.md")


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def table(headers, rows):
    return "\n".join(["| "+" | ".join(headers)+" |","|"+"|".join("---" for _ in headers)+"|"]+["| "+" | ".join(map(str,r))+" |" for r in rows])


def percent(value):
    return f"{value*100:.1f}%"


result=load(REPORT)
config=load(SOURCE)
assert result["parameters"]==config
for name,entry in result["input_hashes"].items():
    assert hashlib.sha256(Path(entry["path"]).read_bytes()).hexdigest()==entry["sha256"],f"Stale {name}"
base=load(SOURCE.parent/config["base_parameters"])
cost=config["progression"]
rows=result["choice_rows"]
out=[]


def write(text=""):
    out.append(text)


write("# 局外成长 · 触媒与宝石的两天版制作基线")
write()
write(f"日期：2026-10-17。用户已同意本页的局外获取、装备和升级先按此版推进，作为两天版制作基线；尚未接入游戏，也未获实机体验认可。唯一调参源为[data局外表](../../data/balance_candidates/meta_growth_v1.json)，版本 `{config['version']}`，原字节与candidate命名保留；本页由匹配执行结果生成。")
write()
write("## 1. 首版只保留这一条养成流程")
write()
write(table(["系统","首次获取","后续获取","装备","升级"],[("法术触媒","三种任选一种，免费1级","其余种类用魔尘直接解锁","一个触媒槽，不占法术槽","最高三级，强化相关法术出现倾向"),("魔力宝石","三种任选一种，免费1级","其余种类用魔尘直接解锁","一个宝石槽，不占法术槽","最高三级，只增强一种基础属性")]))
write()
write(f"两种系统共用魔尘：解锁未持有种类{cost['unlock_cost']}；1→2级{cost['upgrade_cost_by_current_level']['1']}；2→3级{cost['upgrade_cost_by_current_level']['2']}。升级必成，不要重复本体／碎片。级别效果取当前档，不把各级增幅累加。每个种类只有一份、等级永久保存。")
write()
write("首个触媒和首个宝石可以独立选择，例如爆焰触媒＋护壁宝石；不绑定成固定职业。首次各选一种后立即保存并自动装备，其他种类要正常解锁。普通解锁不自动替换已装备项。已解锁项在准备页免费更换，也可不装备作对照；开始一局后锁定至结算，仅装备中的效果生效。")
write()
write("## 2. 触媒：在当前十个火系法术里产生实际倾向")
write()
write("当前只有火系，给全部火系统一乘同一个权重不会改变概率。因此首版按已有三条流派划分触媒，直接关联具体法术。以后增加其他元素时再增加对应种类，不在本版先造空的系列概率。")
write()
write(table(["编号","触媒","提高权重的三个法术"],[(cid,c["name"],"、".join(base["spells"][s]["name"] for s in c["related_spells"])) for cid,c in config["catalysts"].items()]))
write()
write(table(["触媒等级","关联法术权重","十法术均可选时，一屏至少一个关联法术"],[("未装备","×1",percent(next(r["first_offer_exact"] for r in rows if r["level"]==0)))]+[(f"{i}级",f"×{weight:g}",percent(next(r["first_offer_exact"] for r in rows if r["level"]==i))) for i,weight in enumerate(config["catalyst_weight_by_level"],1)]))
write()
write("- 只影响后续法术三选一的抽取权重，玩家仍自己选择；新学与重复升级均受影响。")
write("- 沿用开局三个基础攻击法术的选择，不额外赠送法术；当前开局候选只有三种，触媒不改开局候选。")
write("- 先过滤满三级法术；满八槽后先过滤未持有法术；再对剩余关联法术加权，同屏三个不同法术、不放回。池不足显示实际数量。")
write("- 不额外增加法术槽、法术选择次数、相性统计或最大等级。关联法术全满后不再获得该倾向的抽取收益。")
write("- 不提高神器品质或专属神器抽取权重。配套神器是否合资格，仍由玩家实际取得的法术决定；这种间接影响保留。")
write()
write("概率锚点的假设为：十种法术基础等权、三种关联法术同倍增权、三候选不放回。这是本版触媒采用的抽样规则，实际概率随八槽、三级过滤变化；‘权重×2’不能写成‘获取概率翻倍’或必出。未装备时至少一个关联为1−C(7,3)/C(10,3)。")
write()
write("## 3. 魔力宝石：只做三种属性")
write()
stats={"health":"生命上限","shield":"护盾上限","attack":"攻击力"}
write(table(["编号","宝石","属性","1级总加成","2级总加成","3级总加成"],[(gid,g["name"],stats[g["stat"]],*[f"＋{v}" for v in g["flat_by_level"]]) for gid,g in config["gems"].items()]))
write()
write(f"原始{base['player']['health']}生命／{base['player']['shield']}盾／{base['player']['attack']}攻击基线不变，宝石是在开局额外相加，不能把三种宝石都加到同一角色上。开始一局按新生命上限满血、按新盾上限满盾；战斗中不换装、不通过换宝石回血。攻击宝石不放大暖焰护持的回盾量。")
write()
max_gems={r['gem']:r for r in result['gem_rows'] if r['level']==cost['max_level']}
max_life=max_gems['MG01']['with_three_generic_items']['health']+len(base['recovery']['shop_after'])*base['recovery']['shop_max_health_gain']
write(f"与本局神器同类属性相加，酒馆规则照旧。例如三级生机宝石＋生命琥珀＋五次酒馆，生命上限为{max_life}；三级护壁宝石＋护壁晶核的盾上限为{max_gems['MG02']['with_three_generic_items']['shield']}；三级强攻宝石＋增幅棱晶的攻击为{max_gems['MG03']['with_three_generic_items']['attack']}。生命上限神器仍不因拾取而额外补当前生命。")
write()
write("三个例子分别比较一次只装备对应宝石的状态，不是把三颗都装备。生命应对单次大额损失、盾帮助反复清房、攻击缩短战斗；尚未根据真实受击分布判定三者等值。首版暂不做暴击／暴伤／属性伤害宝石，保留以后扩充。")
write()
write("## 4. 魔尘获取与失败保留")
write()
economy=load(SOURCE.parent/config["economy_parameters"])
write(table(["阶段","每清一房暂记魔尘"],[(f"{s['name']} {s['from']}—{s['to']}",config["currency"]["room_dust_by_stage"][s["id"]]) for s in economy["stages"]]))
write()
write(table(["首领","击败后额外暂记"],[(f"{b['room']}房 {b['name']}",config["currency"]["boss_bonus_by_id"][b["id"]]) for b in base["bosses"]]))
write()
write("所有战斗房使用阶段清房收入，包括精英和首领；首领再加上表奖金，精英不另发一种材料。金币继续只在本局购买神器，不能兑换魔尘；商店节点本身不产魔尘。重复挑战照常获得同一规则的奖励，不做每日次数、首通倍率或随机材料。")
write()
write(table(["本局已清房数","结算魔尘总量","含义"],[(9,result["dust_by_cleared_rooms"]["9"],"早期失败也有积累"),(15,result["dust_by_cleared_rooms"]["15"],"第一次首领通过后，已攒够一次升级"),(45,result["dust_by_cleared_rooms"]["45"],"中期首领完成"),(59,result["dust_by_cleared_rooms"]["59"],"最终首领失败，只算此前已清房间"),(60,result["dust_by_cleared_rooms"]["60"],"完整通关")]))
write()
write("魔尘在本局内暂记，胜利、死亡或选择‘结束本局’时统一入局外账户，结算后才能解锁／升级。死在哪一房，该房未清就不计；已经清过的房间收益保留。强制关闭时不做中途续关，丢失本次尚未结算的魔尘，先前局外存档保留。重开结算界面不能重复领取。")
write()
write("## 5. 养成节奏与选择")
write()
write(table(["培养目标","魔尘总成本"],[("已拥有的一件1→3级",result["costs"]["one_unlocked_item_to_max"]),("最初免费两件都1→3级",result["costs"]["starting_pair_to_max"]),("六件全部解锁并升满",result["costs"]["all_six_to_max"])]))
write()
full=result["dust_by_cleared_rooms"]["60"]
write(f"完整通关一次结算{full}，可先把常用一对升满，或优先解锁不同路线；约{next(t['value'] for t in result['targets'] if t['name']=='full clears needed to fund all six maxed')}次完整通关的总材料可完成六件首版养成。这是快速验证版本的节奏，不是长线肝度目标，也不是承诺新玩家三局都能通关。")
write()
write("按只买得起才操作的固定策略，先提升常用一对时，连续三次各清9房，第三次结算后可完成第一次升级；连续两次各清14房，第二次结算后可升级。失败不扣已有魔尘。材料只在局外使用，不要求先有成长才能尝试首关。")
write()
write("全部满级后，余额继续保存，首版不提供无限属性升级或额外兑换，也不承诺后续版本兑换价值。没有出售、拆解或洗点返还，避免两天版增加另一套经营流程。")
write()
write("## 6. 两天版的交互与存档范围")
write()
write("复用一张准备页：上方魔尘余额，中间触媒三卡／宝石三卡，下方当前装备及下一局属性预览。卡片用现有字体和文字占位，显示关联法术／属性、等级、解锁或升级价格；支持装备、解锁、升级。开始本局时截取等级与装备快照，整局固定。结算页只增加本次魔尘来源、所得和账户余额。")
write()
write("只存一个本地档：版本号、魔尘余额、六种等级（0表示未解锁）、两个装备ID、两次免费领取状态与结算序号。解锁、升级、换装和结算成功后保存；扣款与等级／领取状态作为同一变更提交，保存失败保留原状态并显示失败，不让界面宣布成功。读取损坏档应明确报错，不能静默清空已有进度。")
write()
write("此为存档行为设计，独立Python工具只核对状态／序列化与结算幂等，未验证Godot磁盘写入。未来规则和存档归scripts/core，界面归scripts/ui，配置归data。接入点仅为准备页、结算、开局属性快照与法术候选加权；不增加背包格子、随机品质／词条、合成、拆解、镶嵌孔、天赋树、云存档或中途续关。")
write()
write("## 7. 计算证据与边界")
write()
write(f"模型 `{result['model_version']}`，{len(result['checks'])}项手算／资格／购买／装备／快照／重复结算等检查通过；{len(rows)}组法术抽取情境，每组{result['scenarios']['trials']}次，共{sum(r['trials'] for r in rows):,}次，种子{result['scenarios']['seed']}。种子值不是交付日期。两种选择策略用‘追关联法术’与‘沿原路线偏好’作为输入，初始法术沿原路径、首领前仍6／16／21次选择，候选蒙特卡洛与精确枚举误差均在四个标准误内。另有{len(result['sweeps'])}组权重／成本扫描、四种进度路径的材料账本、九种宝石等级属性与简化受击锚点。")
write()
comparison=[]
for cid,catalyst in config["catalysts"].items():
    selected={level:next(r for r in rows if r["catalyst"]==cid and r["level"]==level and r["policy"]=="seek_related") for level in (0,1,3)}
    comparison.append((catalyst["name"],*[percent(selected[level]["checkpoints"]["15"]["all_related_rate"]) for level in (0,1,3)]))
write(table(["追关联法术策略：15房首领前拥有三种关联法术","无触媒","一级","三级"],comparison))
write()
write("这是相关法术到手率，不是成型率或通关率。燎原初始沿原路径选贯焰光束，三种目标都要后续取得；另外两条路径初始已含一种目标，因此不能把三行差异直接当成触媒强弱。强化不保证三法术，更不保证精确等级或神器组合。")
write()
write("扫描中关联权重2.5倍时，完整十法术池的一屏关联展示约91.4%；本版止于2倍，保留其他法术的选择空间。升级费用提高50%会把六件培养材料量拉至约五次完整通关；首版选择20／40以加快验证。宝石压力例只比较两／三次固定有效受击，不含走位、法术、神器或整局承伤，不能据此宣布生命／盾谁更强。")
write()
write("未实现局外页面和存档、未启动游戏。07经济模型使用的是其当时固定法术路径；本轮没有把新的随机法术路径、实际神器选择和整局战斗联合模拟，不能宣称其原有库存或首领耗时分布在新触媒下完全不变。后续试玩检查：第一次失败后是否愿意再试、解锁与升级是否有真实取舍、触媒倾向能否感知、宝石是否成为单一必选，以及升级后首领二阶段是否仍有展示时间。")
write()
write("[源与假设、模型复现](../../tools/balance/first_run/README.md)、[执行结果及输入哈希](../../build/qa/meta-growth-20261017/selected/results.json)、[法术抽取统计CSV](../../build/qa/meta-growth-20261017/selected/choices.csv)。本轮已确认的基础、神器与金币源保持原字节；新局外表与工具由.gdignore隔离，不进入当前游戏。")
write()
DOC.write_text("\n".join(out),encoding="utf-8")
print(f"generated {DOC}")
