extends RefCounted
## Read-only presentation catalog for the new courtyard interface.
## Gameplay eligibility, random offers, purchases and save data belong to core.

const SOURCE_ROOT := "res://data/balance_candidates/"
const SOURCE_FILES := {
	"base": "first_run_v1.json",
	"artifact_source": "fire_artifacts_v1.json",
	"economy": "run_economy_v1.json",
	"meta": "meta_growth_v1.json",
	"metrics": "map_metrics_v2.json",
	"spatial": "room_spatial_v1.json",
}
const SPELL_ROLES := {
	"F01": "远程爆破", "F02": "被动增伤",
	"F03": "火雨轰击", "F04": "精灵助战",
	"F05": "移动火域", "F06": "阵内强化",
	"F07": "中心爆发", "F08": "直线贯穿",
	"F09": "近身击退", "F10": "护盾回复",
	"F11": "单轮传火",
	"I01": "连续施霜", "I02": "穿线寒霜", "I03": "落点冰击",
	"I04": "近身缓敌", "I05": "寒域控制", "I06": "条带冰暴",
	"I07": "碎冰兑现", "I08": "冻结窗口", "I09": "短时防御", "I10": "被动研习",
	"L01": "快速布点", "L02": "孤立贯穿", "L03": "邻接连锁", "L04": "导电布置",
	"L05": "雷云点名", "L06": "近身放电", "L07": "强敌裁决", "L08": "网络过载",
	"L09": "回盾布点", "L10": "被动研习",
	"W01": "纵深穿透", "W02": "去回归航", "W03": "有限追击", "W04": "近身散阵",
	"W05": "定点聚敌", "W06": "真空爆破", "W07": "双翼交剪", "W08": "真实风径",
	"W09": "敌弹缓行", "W10": "走位研习",
	"R01": "重矢散片", "R02": "扩散震波", "R03": "落击支点", "R04": "地脉脉冲",
	"R05": "护盾回复", "R06": "消费构造", "R07": "借源共振", "R08": "山崩硬控",
	"R09": "固定护阵", "R10": "被动研习",
	"S01": "契印集火", "S02": "远程契灵", "S03": "近战侍从", "S04": "灵鹰扫掠",
	"S05": "有限协同", "S06": "归灵爆发", "S07": "有界续存", "S08": "契印缓敌",
	"S09": "护盾回复", "S10": "被动研习",
}
const SPELL_SUMMARIES := {
	"F01": "向最近敌人发射焰弹，炸伤并点燃周围敌人。",
	"F02": "被动强化所有火焰伤害。",
	"F03": "锁定敌人脚下落下火雨，以连续落击铺开燃烧。",
	"F04": "召唤随行火精灵，以火焰光束自动攻击。",
	"F05": "放出缓慢前进的火旋涡，持续灼伤沿途敌人。",
	"F06": "脚下展开法阵，灼伤敌人并强化阵内的你。",
	"F07": "轰击强敌，并引爆命中目标尚未结算的燃烧。",
	"F08": "射出火焰光束，贯穿并点燃同一直线的敌人。",
	"F09": "敌人近身时释放灼浪，击退周围敌人。",
	"F10": "战斗中护盾不足时，自动施法回复护盾。",
	"F11": "点燃目标，并把火种一次传向附近尚未燃烧的敌人。",
	"I01": "霜弹伤敌，累积寒霜。",
	"I02": "冰锥贯敌，沿线施霜。",
	"I03": "锁定落点砸下寒星，伤害并侵染周围敌人。",
	"I04": "近敌逼近时释放霜环，减缓追击并累积寒霜。",
	"I05": "在追击路线上展开寒域，持续伤害并累积寒霜。",
	"I06": "沿固定条带连续掠过冰晶，覆盖成群敌人。",
	"I07": "自动碎冰换取伤害，并提前解除目标剩余的冻结。",
	"I08": "锁定强敌落下冰棺，直接创造冻结或冰裂窗口。",
	"I09": "短时提高防御，并对近敌施加寒霜。",
	"I10": "被动强化冰系伤害，提升碎冰衔接的余量。",
	"L01": "雷矢快速直射，命中后为存活敌人布下导电。",
	"L02": "集中贯穿强敌，孤立目标承受更强主击。",
	"L03": "沿邻接敌人依次放电，导电让连接更加可靠。",
	"L04": "伤害主目标，并为周围未导电敌人建立有限节点。",
	"L05": "在锁定位置点名落雷，各次雷云独立完成有限波次。",
	"L06": "近敌逼近时向周围放电，高等级追加原地后脉冲。",
	"L07": "锁定强敌裁决，成熟导电可向邻敌放出有限电弧。",
	"L08": "沿既有导电网络放电，过载强化真实连出的边。",
	"L09": "真实回复护盾后，为有限邻敌布下导电。",
	"L10": "被动强化雷伤，延长导电保存并改善连接距离。",
	"W01": "锁定方向发出风刃，依真实碰撞顺序贯穿有限敌人。",
	"W02": "风环去回各可伤敌，转折时锁定一次归航点。",
	"W03": "以有限转角追击原目标，长途飞行可强化本击。",
	"W04": "向近敌方向释放锥形风压，伤敌并推散阵形。",
	"W05": "固定风涡持续伤敌，以有限预算牵引附近敌人。",
	"W06": "锁定敌点后引爆真空，高等级追加原地补压。",
	"W07": "两翼朝锁定点交会，双翼实际命中可交剪。",
	"W08": "沿你真实自主走过的路径留痕，接触才伤敌。",
	"W09": "迎向接近的敌弹展开固定风幕，减慢带内飞弹。",
	"W10": "最近走过足够真实路程时，强化风系伤害。",
	"R01": "碎岩重矢主击后散片，覆盖不同后排敌人。",
	"R02": "向四周扩散真实震波，波前触及敌人才命中。",
	"R03": "锁定落点坠击，并留下不阻路的岩棱支点。",
	"R04": "固定石柱按时脉冲，持续震伤可见近敌。",
	"R05": "战斗中缺盾时自动回复护盾，按实际缺口裁切。",
	"R06": "自动消费一个合格构造，在其中心释放坍岩震击。",
	"R07": "先伤敌，再借附近仍存构造各自发出有限回响。",
	"R08": "向强敌锁定落点山崩，伤敌并造成短时硬控。",
	"R09": "脚下立起固定护阵石碑，覆盖内提高防御。",
	"R10": "被动强化岩伤，三级在真实护盾尚存时提高防御。",
	"S01": "灵矢为首名有效目标施加唯一契印，引导契灵集火。",
	"S02": "召唤远程契灵，跟随并以实体视线光束攻击。",
	"S03": "召唤灵刃侍从，沿合法地面追击并近战伤敌。",
	"S04": "召唤灵鹰，靠近后沿真实条带扫掠有限敌人。",
	"S05": "命令合格契灵各发一次协同，不重置普通攻击。",
	"S06": "独立造成基础爆发，消费临近到期的契灵可强化。",
	"S07": "固定法阵为覆盖内契灵有限续存，改善新宠首击。",
	"S08": "锁链伤敌并缓行，已有契印者承受更强减速。",
	"S09": "回复护盾，活跃进攻契灵提供有限额外请求量。",
	"S10": "强化灵契伤害与新契印，高等级改善宠物契印普攻。",
}
const SPELL_BOUNDARIES := {
	"F01": "优先攻击射程内未被掩体挡住的敌人。掩体会挡住焰弹；次弹不再分裂。",
	"F02": "占用一个法术槽，不计施法次数。火伤、暴击率和暴伤只作用火系，不提高回盾量、击退距离或法阵的攻击加成。",
	"F03": "落点锁定后不再追踪敌人。一次火雨无论命中几次，都只计一次施法。",
	"F04": "精灵光束受掩体阻挡。精灵满员时不再召唤，也不刷新存续时间。",
	"F05": "旋涡沿施法时的方向前进，遇墙停止移动；不会吸附敌人。",
	"F06": "法阵不会随你移动，同时只能存在一个；再次施放会替换旧阵。",
	"F07": "落点锁定后不追踪。主爆先结算，存活目标才引爆旧燃烧；主爆、余震不点燃，余震不引爆。中心加成只作用主爆中心。",
	"F08": "优先攻击射程内未被掩体挡住的敌人。掩体会截断光束；追加脉冲沿原方向射出。",
	"F09": "击退距离受障碍和敌人抗性影响；可打断能被击退的敌人。",
	"F10": "只回复护盾，不回复生命，也不提高护盾上限。满盾或没有存活敌人时不施放。",
	"F11": "传播只进行一轮，选最近的未燃邻敌且受掩体阻挡。主击致死仍从命中位置传播；传播本身不造成即时伤害，也不继续传染。",
	"I01": "优先最近可直射活敌；霜弹遇墙或首敌结束，发射后不追踪。",
	"I02": "实体障碍截断冰锥，每敌每次施法只命中一次；没有用完的贯穿名额不会变成首敌追加伤害。",
	"I03": "起吟时锁定旧落点，不追踪躲开的敌人；后续冰屑不再施霜，同次施法不重复首次命中检查。",
	"I04": "以释放时玩家位置为中心，不击退；减速取最强，不与寒霜减速相加，精英和固定强敌效果降低。",
	"I05": "同时只有一个领域，重施替换旧域；新旧领域共享每敌施霜间隔，不能靠追加瞬间叠满。",
	"I06": "方向与条带在起吟时锁定，实体障碍截断；第1、3次实际命中的波施霜，空波不占有效次数。",
	"I07": "优先攻击就绪目标；无窗口仍造成基础冰击。碎冰消费命中前已有的唯一窗口，解除剩余冻结；碎冰和邻片不暴击、不继续碎冰。主击致死仍可从有效命中点发射邻敌碎片。",
	"I08": "优先当前生命最高的可见活敌；释放锁当前位置，落击不追踪，只攻击锁定目标。已有窗口只受伤害，不续冻；免控或固定强敌只形成冰裂。",
	"I09": "有近域活敌且旧防御即将结束才施法；增益唯一，不回复盾或生命，不为回盾蓄能。防御仍受综合减伤上限限制。",
	"I10": "占一个法术槽，不计自然施法；普通寒霜可保留更久；三级还延长碎冰窗口，不延长硬冻结或免控。",
	"L01": "只发射一矢，遇墙或首敌结束；发射后不追踪。未导电加成读取命中前状态，不另打一段。",
	"L02": "孤立只检查主目标周围活敌；只强化主击。未用贯穿名额不返还主目标，障碍截断枪线。",
	"L03": "每次施法共用已访问名单，每敌最多一次；逐边检查距离与遮挡。断边或空跳数不返还单体。",
	"L04": "布点只进行一轮，邻敌不受即时伤害。已导电邻敌不占名额，也不被本次刷新；主击致死仍可从有效命中点布置。",
	"L05": "每次施法生成独立有限云团，不取消旧云的剩余落雷。各波选取有限可见活敌，同一波每敌一次；空圈不储存攻击。每个自然云团对各敌首次有效落雷后施加三级易伤，当前首击不倒算受益；追加云无此效果。",
	"L06": "不击退、不麻痹。后脉冲停留在第一次释放的位置，不追随玩家，也不产生第二次施法。",
	"L07": "落点锁定后不追踪，只攻击锁定主目标。条件附伤不暴击；成熟邻弧要求命中前导电年龄合格且主目标全部伤害后仍活。",
	"L08": "只访问释放前旧导电网络；每敌一次。过载只强化实际连接边，节点不足和空余边不补主击；追加不享自然三级强化。",
	"L09": "满盾不施放。回复按实际缺口裁切，零回复不布点；布点不是第二次回复，不生成递归施法。",
	"L10": "占一个法术槽。只延长以后新施加或刷新的导电；三级增距只用于双端已有导电的连锁，不扩大首射程和独立布点范围。",
	"W01": "实体风刃锁方向、遇墙结束；按真实碰撞次序衰减，同敌只命中一次。",
	"W02": "去程结束只锁一次玩家当时位置，回程不持续追身。每程每敌一次、最多8敌，转折重叠不重复领伤；三级自然返程路程达标，本击后才施易伤。",
	"W03": "只追原目标，不重新换靶；失去视线停止修正，目标死亡沿切线前进。首敌结束，长程奖按飞弹实际弧长。",
	"W04": "推距按普通／精英／固定强敌抗性缩放一次并受墙裁剪，不重置攻击；减速与其它来源取最强并受分类上限。",
	"W05": "同术唯一，重施替换，跨实例同敌仍有0.5秒命中门。首跳延迟，到期末跳结算；伤害不受拉动名额限制，漏掉的拉动机会不补领。",
	"W06": "吟唱起手锁落点，延迟爆炸与补压不追敌。中心加值仅主爆；补压可暴击但不触发普通本体命中或新的派生。",
	"W07": "两翼各自碰墙，每翼同敌一次；只有同一cast双翼实际命中才交剪一次。交剪可暴击但不再触发派生。",
	"W08": "只记真实自主轨迹；顶墙、传送、击退不计。重施移除全部旧径，但保留每敌0.5秒门和滚动6秒共享上限；每段独立到期，风径不回盾。",
	"W09": "有接近的可见敌方飞行弹才施法，完成重查。风幕静止、按地板和障碍裁剪；只减带内飞弹位移，不反弹、删弹、改寿命、伤害或方向；落印与冲锋无效。",
	"W10": "占槽，不主动循环。窗口只统计真实自主路径；三级在条件失效后短时保留，不增加移速。",
	"R01": "碎片排除主击目标，同cast每个次敌最多一片；各片独立碰墙、有限穿透，碎片不再散片。",
	"R02": "按实际扩散波前命中，每敌一次；外缘奖励读取真实命中距离，掩体挡住波。",
	"R03": "吟唱起手锁点，落空仍可在合法落地处建支点；同名新建替换旧支点，不阻路。三级已排裂波不因支点被消费而取消。",
	"R04": "同名唯一、不阻路；先结算到点旧脉冲，再到期或替换，不补未到跳数或追加终结伤害。",
	"R05": "战斗有活敌且缺盾才施放，完成重查。只据实际回复充能，不回复生命、不抬盾上限。",
	"R06": "持有构造来源才进入候选；施法时还须有可消费构造和可伤敌人。先移除来源，再排一次震击；无源等待，余波可暴击但不递归。",
	"R07": "无构造仍有基础伤害；借源在各自中心回响，到点核原实例仍在。源消失就取消对应回响，不转借同位置新构造；回响可暴击但不递归。",
	"R08": "锁高生命敌点，预警后落击；硬控受抗性／免控限制。三级裂隙从外缘发出，排除主击敌，次敌最多一击、遇墙截停。",
	"R09": "固定不阻路石碑，覆盖内且到碑无遮挡才加防御；三级保留仅限真实走出，到期／替换／消费立即取消。不回盾，最终减伤仍受上限限制。",
	"R10": "占槽，不计自然施法。三级防御只在真实护盾大于零时生效，归零立即失效，不提高护盾上限。",
	"S01": "同场仅一个契印，只由第一有效主击施加；穿透后续不施印。目标死亡／到期清印，不自动传邻。",
	"S02": "同名容量和全队4只进攻契灵上限同时生效；满员等待，不刷新寿命。普通光束受墙阻挡，不算本体直接命中。",
	"S03": "沿合法地面追击，须进入实际近战范围才攻击；不能穿墙近战。不阻路、挡弹或吸引仇恨。",
	"S04": "先追击到扫掠距离，再沿合法条带命中；各次名额有限，孤立目标不承接空余名额。",
	"S05": "先持有召唤来源才进候选；释放和延迟命中均核实际合格宠物。协同不暴击、不施印、不重置普攻，也不生成新命令链。",
	"S06": "无可消费宠物仍有基础爆发；最多消费一只剩余寿命不超过门槛的合格宠物，先注销再付款。奖励仅加本次分量，不重复消费。",
	"S07": "先持有召唤来源才进候选。固定唯一法阵，需实际覆盖且到场心无遮挡；每宠每场一次续存，所有法阵共用终身预算，不可无限刷新。",
	"S08": "主击先检查既有契印决定减速，再处理施印；三级第二敌不施印。减速取最强并受普通／精英／固定强敌上限限制。",
	"S09": "独立回盾，不生成进攻宠物；按真实活宠数和缺盾裁切。满盾或无活敌等待，不抬盾上限、不回复生命。",
	"S10": "占槽，不计自然施法；新契印延时不追改旧印。契印普攻加成只给合格宠物普通攻击，与研习／共鸣同桶。",
}
const STARTER_SPELLS := ["F01", "F03", "F08"]
const RARITY_NAMES := {"blue": "蓝色", "purple": "紫色", "gold": "金色"}
const RARITY_COLORS := {"blue": "79b7ee", "purple": "b49ae8", "gold": "e5bd75"}
const GENERIC_SOURCE := "res://data/generic_artifacts_v1.json"
const FIRE_RUNTIME_SOURCE := "res://data/route_spell_runtime.json"
const ICE_SPELL_SOURCE := "res://data/ice_spells_v1.json"
const LIGHTNING_SPELL_SOURCE := "res://data/lightning_spells_v1.json"
const WIND_SPELL_SOURCE := "res://data/wind_spells_v1.json"
const EARTH_SPELL_SOURCE := "res://data/earth_spells_v1.json"
const SPIRIT_SPELL_SOURCE := "res://data/spirit_spells_v1.json"
const ICE_ARTIFACT_SOURCE := "res://data/ice_artifacts_v1.json"
const SpellGrowth = preload("res://scripts/core/route_spell_growth.gd")
const BOSS_SOURCE := "res://data/route_boss_runtime.json"
static var _catalog: Dictionary = {}
static var _spells_cache: Array[Dictionary] = []
static var _artifacts_cache: Array[Dictionary] = []


static func load_catalog(force_reload: bool = false) -> Dictionary:
	if _catalog.is_empty() or force_reload:
		_spells_cache.clear()
		_artifacts_cache.clear()
		var result: Dictionary = {"errors": []}
		for key in SOURCE_FILES:
			var path: String = SOURCE_ROOT + str(SOURCE_FILES[key])
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null:
				result["errors"].append("无法读取目录数据：" + path)
				result[key] = {}
				continue
			var parser := JSON.new()
			var error := parser.parse(file.get_as_text())
			if error != OK or not parser.data is Dictionary:
				result["errors"].append("目录数据格式错误：" + path)
				result[key] = {}
				continue
			result[key] = parser.data
		var generic_file := FileAccess.open(GENERIC_SOURCE, FileAccess.READ)
		var generic_parser := JSON.new()
		if generic_file == null or generic_parser.parse(generic_file.get_as_text()) != OK or not generic_parser.data is Dictionary:
			result["errors"].append("无法读取通用道具目录：" + GENERIC_SOURCE)
			result["generic_source"] = {}
		else:
			result["generic_source"] = generic_parser.data
			var merged_items: Dictionary = result.get("artifact_source", {}).get("items", {})
			for id in generic_parser.data.get("items", {}):
				if merged_items.has(id):
					result["errors"].append("宝物目录ID重复：" + str(id))
				else:
					merged_items[id] = generic_parser.data.items[id]
		var runtime_file := FileAccess.open(FIRE_RUNTIME_SOURCE, FileAccess.READ)
		var runtime_parser := JSON.new()
		if runtime_file == null or runtime_parser.parse(runtime_file.get_as_text()) != OK or not runtime_parser.data is Dictionary:
			result["errors"].append("无法读取法术表现参数：" + FIRE_RUNTIME_SOURCE)
			result["spell_runtime"] = {}
		else:
			result["spell_runtime"] = runtime_parser.data
		for entry in [["ice_source", ICE_SPELL_SOURCE, "spells"], ["ice_artifact_source", ICE_ARTIFACT_SOURCE, "items"], ["lightning_source", LIGHTNING_SPELL_SOURCE, "spells"], ["wind_source", WIND_SPELL_SOURCE, "spells"], ["earth_source", EARTH_SPELL_SOURCE, "spells"], ["spirit_source", SPIRIT_SPELL_SOURCE, "spells"]]:
			var extra_file := FileAccess.open(str(entry[1]), FileAccess.READ)
			var extra_parser := JSON.new()
			if extra_file == null or extra_parser.parse(extra_file.get_as_text()) != OK or not extra_parser.data is Dictionary:
				result["errors"].append("无法读取学派目录：" + str(entry[1]))
				result[str(entry[0])] = {}
				continue
			result[str(entry[0])] = extra_parser.data
			var merged: Dictionary = result.get("base", {}).get("spells", {}) if str(entry[2]) == "spells" else result.get("artifact_source", {}).get("items", {})
			for id in extra_parser.data.get(str(entry[2]), {}):
				if merged.has(id):
					result["errors"].append("学派目录ID重复：" + str(id))
				else:
					merged[id] = extra_parser.data[str(entry[2])][id]
		var boss_file := FileAccess.open(BOSS_SOURCE, FileAccess.READ)
		var boss_data = JSON.parse_string(boss_file.get_as_text()) if boss_file != null else null
		if not boss_data is Dictionary:
			result.errors.append("无法读取首领目录。")
		else:
			result["boss_source"] = boss_data
			result.artifact_source.items.merge(boss_data.fallback_items.duplicate(true), true)
		result["legacy_spell_source"] = result.base.spells.duplicate(true)
		var growth_data = JSON.parse_string(FileAccess.get_file_as_string(SpellGrowth.SOURCE))
		if not growth_data is Dictionary:
			result.errors.append("无法读取法术三级成长表。")
		else:
			var applied: Dictionary = SpellGrowth.apply_source(result.base.spells, growth_data)
			if not applied.ok: result.errors.append(applied.error)
		result["ok"] = result["errors"].is_empty()
		_catalog = result
	# Never expose the cached source dictionaries to interface mutation.
	return _catalog.duplicate(true)


static func spells() -> Array[Dictionary]:
	if not _spells_cache.is_empty(): return _spells_cache
	var result: Array[Dictionary] = []
	var catalog: Dictionary = load_catalog()
	var source: Dictionary = catalog.get("base", {}).get("spells", {})
	for id in source:
		if bool(source[id].get("active", true)):
			result.append(_describe_spell(catalog, str(id), 1))
	_spells_cache = result
	return result


static func artifacts() -> Array[Dictionary]:
	if not _artifacts_cache.is_empty(): return _artifacts_cache
	var result: Array[Dictionary] = []
	var catalog: Dictionary = load_catalog()
	var source: Dictionary = catalog.get("artifact_source", {}).get("items", {})
	for scope in ["generic", "fire", "ice"]:
		for id in source:
			if str(source[id].get("scope", "")) == scope and bool(source[id].get("active", true)):
				result.append(_describe_artifact(catalog, str(id)))
	_artifacts_cache = result
	return result


static func spell_name(id: String) -> String:
	var source: Dictionary = load_catalog().get("base", {}).get("spells", {})
	return str(source.get(id, {}).get("name", id))


static func describe_spell(id: String, level: int = 1, route_growth: bool = true) -> Dictionary:
	return _describe_spell(load_catalog(), id, level, route_growth)


static func _describe_spell(catalog: Dictionary, id: String, level: int = 1, route_growth: bool = true) -> Dictionary:
	var source: Dictionary = catalog.get("base", {}).get("spells", {}) if route_growth else catalog.get("legacy_spell_source", {})
	if not source.has(id):
		return {}
	var spell: Dictionary = source[id]
	var levels: Array = spell.get("levels", [])
	if levels.is_empty():
		return {}
	var current_level := clampi(level, 1, levels.size())
	var values: Dictionary = spell.duplicate(false)
	values.merge(levels[current_level - 1], true)
	values.erase("levels")
	var level_details: Array[String] = []
	for index in levels.size():
		var level_values: Dictionary = spell.duplicate(false)
		level_values.merge(levels[index], true)
		level_details.append(_spell_effect(id, level_values))
	var stats: Array[String] = []
	if spell.get("kind") != "passive":
		if values.has("cooldown"):
			stats.append("冷却 " + _number(values["cooldown"]) + " 秒")
		if values.has("windup"):
			stats.append("吟唱 " + _number(values["windup"]) + " 秒")
		if values.has("range"):
			stats.append("射程 " + _number(values["range"]) + " 米")
	else:
		stats.append("被动生效")
	return {
		"id": id, "name": spell["name"], "kind": spell["kind"],
		"role": SPELL_ROLES.get(id, ""), "summary": SPELL_SUMMARIES.get(id, ""),
		"description": _spell_effect(id, values), "detail": _spell_effect(id, values),
		"card_description": _new_school_card_effect(id, values) if str(spell.get("school", "")) in ["wind", "earth", "spirit"] else _spell_effect(id, values),
		"upgrade_text": spell_upgrade_text(id, current_level, route_growth),
		"boundary": str(SPELL_BOUNDARIES.get(id, "")) + ("\n" + lightning_state_rule() if str(spell.get("school", "")) == "lightning" else "\n" + _ice_spell_boundary(id, values) + "\n" + ice_state_rule() if str(spell.get("school", "fire")) == "ice" else ("\n" + burning_rule() if str(spell.get("school", "fire")) == "fire" and id not in ["F02", "F10"] else "")), "stats": stats,
		"level": current_level, "max_level": levels.size(), "level_details": level_details,
		"starter": id in starter_ids(str(spell.get("school", "fire"))), "element": {"ice":"冰", "fire":"火", "lightning":"雷", "wind":"风", "earth":"岩", "spirit":"灵契"}.get(str(spell.get("school", "fire")), ""), "school": spell.get("school", "fire"), "active": spell.get("active", true), "color": school_color(str(spell.get("school", "fire"))).to_html(false),
		"values": values, "source_version": spell.get("growth_version", catalog.get(str(spell.get("school", "fire")) + "_source" if str(spell.get("school", "fire")) != "fire" else "base", {}).get("version", "")),
	}


static func describe_artifact(id: String) -> Dictionary:
	return _describe_artifact(load_catalog(), id)


static func _describe_artifact(catalog: Dictionary, id: String) -> Dictionary:
	var items: Dictionary = catalog.get("artifact_source", {}).get("items", {})
	if not items.has(id):
		return {}
	var item: Dictionary = _resolve_refs(items[id], catalog.get("base", {}))
	var rarity := str(item.get("rarity", ""))
	var price: Variant = catalog.get("economy", {}).get("prices", {}).get(rarity)
	return {
		"id": id, "name": item["name"], "rarity": rarity,
		"rarity_name": RARITY_NAMES.get(rarity, rarity), "color": RARITY_COLORS.get(rarity, "ffffff"),
		"scope": item.get("scope", ""), "scope_name": "通用道具" if item.get("scope") == "generic" else "历史职业宝物", "school_name": {"fire":"火系", "ice":"冰系", "generic":"通用"}.get(str(item.get("scope", "")), ""), "description": _artifact_effect(id, item),
		"summary": _artifact_card_effect(id, item), "card_description": _artifact_card_effect(id, item),
		"requirement": _artifact_requirement(item, catalog), "card_requirement": _artifact_card_requirement(item, catalog),
		"required_spell": item.get("required_spell", ""), "price": price,
		"values": item, "source_version": catalog.get("ice_artifact_source" if item.get("scope") == "ice" else ("generic_source" if id.begins_with("GU") or id.begins_with("GT") else "artifact_source"), {}).get("version", ""),
	}


static func run_overview() -> Dictionary:
	var catalog := load_catalog()
	var base: Dictionary = catalog.get("base", {})
	var economy: Dictionary = catalog.get("economy", {})
	var spatial: Dictionary = catalog.get("spatial", {})
	var stages: Array = economy.get("stages", []).duplicate(true)
	var bosses: Array = catalog.get("boss_source", {}).get("bosses", []).duplicate(true)
	var elites: Array = base.get("elites", []).duplicate(true)
	var room_count := 0
	for stage in stages:
		room_count = maxi(room_count, int(stage.get("to", 0)))
	var elite_rooms: Array[int] = []
	for elite in elites:
		elite_rooms.append(int(elite["room"]))
	var boss_rooms: Array[int] = []
	for boss in bosses:
		boss_rooms.append(int(boss["room"]))
	var layouts: Array[Dictionary] = []
	for id in spatial.get("layouts", {}):
		var layout: Dictionary = spatial["layouts"][id]
		layouts.append({"id": str(id), "name": layout.get("name", ""), "blocks": layout.get("blocks", []).duplicate(true)})
	return {
		"name": "遗迹庭院", "room_count": room_count,
		"normal_room_count": room_count - elites.size() - bosses.size(),
		"stages": stages, "bosses": bosses, "elites": elites,
		"elite_rooms": elite_rooms, "boss_rooms": boss_rooms,
		"shops_after": base.get("recovery", {}).get("shop_after", []).duplicate(true),
		"limits": base.get("limits", {}).duplicate(true),
		"synergy": base.get("fire_synergy", {}).duplicate(true),
		"floor": catalog.get("metrics", {}).get("floor", {}).duplicate(true),
		"layouts": layouts,
		"flow": ["下方进入", "中部战斗", "清场与选择", "上方传送"],
	}


static func economy_summary() -> Dictionary:
	var catalog := load_catalog()
	var economy: Dictionary = catalog.get("economy", {})
	var recovery: Dictionary = catalog.get("base", {}).get("recovery", {})
	return {
		"currency_name": economy.get("currency", {}).get("name", ""),
		"prices": economy.get("prices", {}).duplicate(true),
		"shop_slots": economy.get("offers", {}).get("shop_slots"),
		"chest_choices": economy.get("offers", {}).get("chest_choices"),
		"max_purchases": economy.get("shop", {}).get("max_purchases_per_visit"),
		"shop_health_gain": recovery.get("shop_max_health_gain"),
		"shop_heal_fraction": recovery.get("shop_fraction"),
		"shop_supply_text": "本店免费补给：生命上限 +%s，再回复新上限的 %s 生命。" % [_number(recovery.get("shop_max_health_gain")), _percent(recovery.get("shop_fraction"))],
		"shop_rule_text": "商品入店时固定，每店限购 %s 件；不刷新、不回购。" % _number(economy.get("shop", {}).get("max_purchases_per_visit")),
		"currency_rule_text": "金币用于本局购买宝物，结算时清零。魔尘用于局外成长。",
	}


static func _spell_effect(id: String, value: Dictionary) -> String:
	var traits: String = _growth_traits(id, value)
	return _spell_effect_base(id, value) + ("\n" + traits if not traits.is_empty() else "")


static func _spell_effect_base(id: String, value: Dictionary) -> String:
	if str(value.get("school", "")) in ["wind", "earth", "spirit"]:
		return _new_school_spell_effect(id, value)
	if str(value.get("school", "")) == "lightning":
		return _lightning_spell_effect(id, value)
	if str(value.get("school", "")) == "ice":
		return _ice_spell_effect(id, value)
	match id:
		"F01":
			var text := "伤害：%s 攻击力\n爆炸半径：%s 米" % [_percent(value["coefficient"]), _number(value["radius"])]
			if float(value["secondary"]) > 0.0:
				text += "\n追加一枚焰弹：%s 攻击力" % _percent(value["secondary"])
			return text + "\n命中点燃，燃烧不叠层"
		"F02":
			var text := "火焰伤害 +%s" % _percent(value["fire_bonus"])
			if float(value["crit_bonus"]) > 0.0:
				text += "\n火焰暴击伤害 +%s 个百分点" % _number(float(value["crit_bonus"]) * 100.0)
			return text
		"F03":
			var text := "首落 %s 攻击力，固定中心\n其余 %s 落各 %s，命中点燃" % [_percent(value.get("first_drop_coefficient", value["coefficient"])), _number(int(value["drops"])-1), _percent(value["coefficient"])]
			if float(value["ground_duration"]) > 0.0:
				text += "\n余火持续 %s 秒\n每 %s 秒伤害：%s 攻击力" % [_number(value["ground_duration"]), _number(value["ground_interval"]), _percent(value["ground_coefficient"])]
			return text
		"F04":
			var text := "召唤 %s 只，持续 %s 秒\n攻击间隔：%s 秒\n伤害：%s 攻击力" % [_number(value["count"]), _number(value["duration"]), _number(value["interval"]), _percent(value["coefficient"])]
			if bool(value["pierce"]):
				text += "\n光束可贯穿敌人"
			return text
		"F05":
			var text := "旋涡半径 %s 米，移动 %s 秒\n每 %s 秒伤害：%s 攻击力" % [_number(value["radius"]), _number(value["duration"]), _number(value["interval"]), _percent(value["coefficient"])]
			if float(value["end_duration"]) > 0.0:
				text += "\n到达终点后继续灼烧 %s 秒" % _number(value["end_duration"])
			return text + "\n每次施法对每敌首次命中点燃"
		"F06":
			var text := "半径 %s 米，持续 %s 秒\n每 %s 秒伤害：%s 攻击力\n阵内攻击力 +%s" % [_number(value["radius"]), _number(value["duration"]), _number(value["interval"]), _percent(value["coefficient"]), _percent(value["attack_bonus"])]
			if float(value["grace"]) > 0.0:
				text += "\n离阵后加成保留 %s 秒" % _number(value["grace"])
			return text + "\n每次施法对每敌首次命中点燃"
		"F07":
			var text := "伤害按攻击力计算\n中心 %s 米内：%s\n外围至 %s 米：%s" % [_number(value["center_radius"]), _percent(float(value["coefficient"]) * float(value.get("main_center_damage_multiplier", 1.0))), _number(value["radius"]), _percent(value["outer"])]
			if float(value["aftershock"]) > 0.0:
				text += "\n%s 秒后余震：%s" % [_number(value["aftershock_delay"]), _percent(value["aftershock"])]
			return text + "\n引爆剩余燃烧：%s 倍，不暴击" % _number(value.get("detonation_multiplier", 1))
		"F08":
			var text := "伤害：%s 攻击力\n长 %s 米，宽 %s 米" % [_percent(value["coefficient"]), _number(value["range"]), _number(value["width"])]
			if float(value["secondary"]) > 0.0:
				text += "\n追加同向脉冲：%s 攻击力" % _percent(value["secondary"])
			return text + "\n主光束点燃，脉冲不点燃"
		"F09":
			var text := "半径 %s 米，伤害 %s 攻击力\n击退 %s 米" % [_number(value["radius"]), _percent(value["coefficient"]), _number(value["push"])]
			if float(value["slow"]) > 0.0:
				text += "\n减速 %s，持续 %s 秒" % [_percent(value["slow"]), _number(value["slow_duration"])]
			return text + "\n命中点燃"
		"F10":
			return "回复 %s 点护盾\n冷却 %s 秒" % [_number(value["shield"]), _number(value["cooldown"])]
		"F11":
			return "主目标伤害：%s 攻击\n传播%s米内%s名未燃邻敌\n只传一轮，燃烧不叠层" % [_percent(value["coefficient"]), _number(value["spread_radius"]), _number(value["spread_targets"])]
	return ""

static func burning_rule() -> String:
	var burning: Dictionary = load_catalog().get("spell_runtime", {}).get("fire", {}).get("burning", {})
	return "基础燃烧：持续%s秒，每%s秒造成%s当前攻击力火伤。每敌一份，刷新不叠层、不重置下跳；燃烧与引爆不暴击。" % [_number(burning.get("duration")), _number(burning.get("interval")), _percent(burning.get("coefficient"))]


static func spell_upgrade_text(id: String, level: int, route_growth: bool = true) -> String:
	# Display only what this choice changes; values still come from the core source.
	var catalog: Dictionary = load_catalog()
	var source: Dictionary = catalog.get("base", {}).get("spells", {}) if route_growth else catalog.get("legacy_spell_source", {})
	if not source.has(id):
		return ""
	var spell: Dictionary = source[id]
	var levels: Array = spell.get("levels", [])
	if level < 2 or level > levels.size():
		return ""
	var before: Dictionary = spell.duplicate(true)
	before.merge(levels[level - 2], true)
	var after: Dictionary = spell.duplicate(true)
	after.merge(levels[level - 1], true)
	if str(spell.get("school", "")) in ["wind", "earth", "spirit"]:
		return _new_school_upgrade_text(id, before, after)
	if str(spell.get("school", "")) == "lightning":
		return _lightning_upgrade_text(id, before, after)
	if spell.has("growth_version"):
		return _growth_upgrade_text(id, before, after)
	var changes: Array[String] = []
	if str(spell.get("school", "")) == "ice":
		return _ice_upgrade_text(id, before, after)
	match id:
		"F01":
			if before["coefficient"] != after["coefficient"]:
				changes.append("伤害：%s → %s 攻击力" % [_percent(before["coefficient"]), _percent(after["coefficient"])])
			if before["radius"] != after["radius"]:
				changes.append("爆炸半径：%s → %s 米" % [_number(before["radius"]), _number(after["radius"])])
			if before["secondary"] != after["secondary"]:
				changes.append("追加一枚焰弹\n伤害：%s 攻击力" % _percent(after["secondary"]))
		"F02":
			changes.append("火焰伤害加成：%s → %s" % [_percent(before["fire_bonus"]), _percent(after["fire_bonus"])])
			if before["crit_bonus"] != after["crit_bonus"]:
				changes.append("火焰暴击伤害 +%s 个百分点" % _number(float(after["crit_bonus"]) * 100.0))
		"F03":
			if before["drops"] != after["drops"]:
				changes.append("落火次数：%s → %s 次" % [_number(before["drops"]), _number(after["drops"])])
			if before["ground_duration"] != after["ground_duration"]:
				changes.append("火雨结束后留下 %s 秒余火\n每 %s 秒伤害：%s 攻击力" % [_number(after["ground_duration"]), _number(after["ground_interval"]), _percent(after["ground_coefficient"])])
		"F04":
			if before["coefficient"] != after["coefficient"]:
				changes.append("伤害：%s → %s 攻击力" % [_percent(before["coefficient"]), _percent(after["coefficient"])])
			if before["interval"] != after["interval"]:
				changes.append("攻击间隔：%s → %s 秒" % [_number(before["interval"]), _number(after["interval"])])
			if before["pierce"] != after["pierce"]:
				changes.append("光束可贯穿沿途所有敌人")
		"F05":
			if before["coefficient"] != after["coefficient"]:
				changes.append("伤害：%s → %s 攻击力" % [_percent(before["coefficient"]), _percent(after["coefficient"])])
			if before["radius"] != after["radius"]:
				changes.append("旋涡半径：%s → %s 米" % [_number(before["radius"]), _number(after["radius"])])
			if before["end_duration"] != after["end_duration"]:
				changes.append("到达终点后继续灼烧 %s 秒\n伤害与频率保持不变" % _number(after["end_duration"]))
		"F06":
			if before["radius"] != after["radius"]:
				changes.append("法阵半径：%s → %s 米" % [_number(before["radius"]), _number(after["radius"])])
			if before["duration"] != after["duration"]:
				changes.append("持续时间：%s → %s 秒" % [_number(before["duration"]), _number(after["duration"])])
			if before["grace"] != after["grace"]:
				changes.append("离阵后攻击加成保留 %s 秒" % _number(after["grace"]))
		"F07":
			if before["coefficient"] != after["coefficient"]:
				changes.append("中心伤害：%s → %s" % [_percent(before["coefficient"]), _percent(after["coefficient"])])
			if before["outer"] != after["outer"]:
				changes.append("外围伤害：%s → %s" % [_percent(before["outer"]), _percent(after["outer"])])
			if before["center_radius"] != after["center_radius"]:
				changes.append("中心半径：%s → %s 米" % [_number(before["center_radius"]), _number(after["center_radius"])])
			if before.get("detonation_multiplier") != after.get("detonation_multiplier"):
				changes.append("引爆倍率：%s → %s" % [_number(before.get("detonation_multiplier")), _number(after.get("detonation_multiplier"))])
			if before["aftershock"] != after["aftershock"]:
				changes.append("%s秒后余震，伤害%s\n余震半径：%s 米" % [_number(after["aftershock_delay"]), _percent(after["aftershock"]), _number(after["radius"])])
		"F08":
			if before["coefficient"] != after["coefficient"]:
				changes.append("伤害：%s → %s 攻击力" % [_percent(before["coefficient"]), _percent(after["coefficient"])])
			if before["range"] != after["range"]:
				changes.append("光束长度：%s → %s 米" % [_number(before["range"]), _number(after["range"])])
			if before["secondary"] != after["secondary"]:
				changes.append("追加一道同向脉冲\n伤害：%s 攻击力" % _percent(after["secondary"]))
		"F09":
			if before["radius"] != after["radius"]:
				changes.append("冲击半径：%s → %s 米" % [_number(before["radius"]), _number(after["radius"])])
			if before["push"] != after["push"]:
				changes.append("击退距离：%s → %s 米" % [_number(before["push"]), _number(after["push"])])
			if before["slow"] != after["slow"]:
				changes.append("命中后减速 %s，持续 %s 秒" % [_percent(after["slow"]), _number(after["slow_duration"])])
		"F10":
			if before["shield"] != after["shield"]:
				changes.append("护盾回复：%s → %s 点" % [_number(before["shield"]), _number(after["shield"])])
			if before["cooldown"] != after["cooldown"]:
				changes.append("冷却时间：%s → %s 秒" % [_number(before["cooldown"]), _number(after["cooldown"])])
		"F11":
			if before["coefficient"] != after["coefficient"]:
				changes.append("主目标伤害：%s → %s 攻击力" % [_percent(before["coefficient"]), _percent(after["coefficient"])])
			changes.append("传播半径：%s → %s 米\n未燃邻敌：%s → %s 个" % [_number(before["spread_radius"]), _number(after["spread_radius"]), _number(before["spread_targets"]), _number(after["spread_targets"])])
	return "\n".join(changes)


static func _growth_traits(id: String, v: Dictionary) -> String:
	var rows: Array[String] = []
	match id:
		"F01":
			if float(v.get("crit_patch_coefficient", 0.0)) > 0.0:
				rows.append("自然焰弹暴击留火：半径%s米，持续%s秒，每%s秒%s攻击；每次释放最多一处" % [_number(v.crit_patch_radius), _number(v.crit_patch_duration), _number(v.crit_patch_interval), _percent(v.crit_patch_coefficient)])
		"F02":
			if float(v.get("fire_crit_rate_add", 0.0)) > 0.0: rows.append("火系暴击率 +%s" % _percent(v.fire_crit_rate_add))
		"F03":
			rows.append("前%s滴固定中心，其余散落" % _number(v.get("fixed_center_drops", 1)))
		"F05":
			if float(v.get("first_hit_slow", 0.0)) > 0.0: rows.append("每敌首次命中减速%s，持续%s秒" % [_percent(v.first_hit_slow), _number(v.first_hit_slow_duration)])
		"F06":
			if float(v.get("overlap_fire_vulnerability", 0.0)) > 0.0: rows.append("本自然法阵与另一种自然火区域重叠：敌人所受火伤 +%s，只生效一份" % _percent(v.overlap_fire_vulnerability))
			if float(v.get("mature_coefficient", 0.0)) > 0.0: rows.append("自然法阵满%s秒爆发一次：半径%s米，%s攻击" % [_number(v.mature_after), _number(v.mature_radius), _percent(v.mature_coefficient)])
		"F07":
			if float(v.get("main_center_crit_multiplier_add", 0.0)) > 0.0: rows.append("主爆中心暴伤 +%s个百分点" % _number(float(v.main_center_crit_multiplier_add) * 100.0))
			if float(v.get("reapply_delay", 0.0)) > 0.0: rows.append("自然引爆额外 +%s倍；消耗旧燃烧后%s秒复燃，每敌%s秒一次，不连锁引爆" % [_number(v.get("natural_detonation_multiplier_add", 0.0)), _number(v.reapply_delay), _number(v.reapply_shared_cooldown)])
		"F08":
			if int(v.get("echo_every", 0)) > 0: rows.append("每%s次自然释放追加一次%s威力光束；追加不计数" % [_number(v.echo_every), _percent(v.echo_scale)])
		"F09":
			if float(v.get("hit_move_speed_bonus", 0.0)) > 0.0: rows.append("自然释放命中后移速 +%s，持续%s秒" % [_percent(v.hit_move_speed_bonus), _number(v.hit_move_speed_duration)])
		"F11":
			rows.append("持有时全局燃烧持续%s秒，最多剩余%s跳；不新增独立燃烧" % [_number(v.get("burn_duration", 4)), _number(v.get("burn_maximum_ticks", 8))])
		"I01":
			if float(v.get("frosted_coefficient_add", 0.0)) > 0.0: rows.append("命中前有1至2层寒霜且未就绪：额外%s攻击伤害" % _percent(v.frosted_coefficient_add))
		"I02", "I03":
			if int(v.get("first_direct_extra_frost", 0)) > 0: rows.append("自然释放首次有效主段命中：命中前1至2层且存活未就绪者额外1层寒霜；落空或后续冰屑不补发")
		"I06":
			if float(v.get("final_wave_multiplier", 1.0)) > 1.0: rows.append("末波伤害 ×%s" % _number(v.final_wave_multiplier))
			if int(v.get("second_area_extra_frost", 0)) > 0: rows.append("自然释放对每敌第二次合资格施霜额外1层；共享命中门槛不重置")
		"I07":
			if int(v.get("fragment_frost_targets", 0)) > 0: rows.append("自然碎冰的邻片给最多%s名存活邻敌施加1层寒霜" % _number(v.fragment_frost_targets))
			if float(v.get("natural_shatter_multiplier", 1.0)) > 1.0: rows.append("自然主冰裂 ×%s并留%s层寒霜；每敌%s秒一次，不影响邻片" % [_number(v.natural_shatter_multiplier), _number(v.retained_frost), _number(v.shatter_per_actor_cooldown)])
		"I08":
			if float(v.get("immune_coefficient_add", 0.0)) > 0.0: rows.append("免控期或免疫硬冻目标额外%s攻击伤害" % _percent(v.immune_coefficient_add))
			if float(v.get("window_restore", 0.0)) > 0.0: rows.append("自然新建冰裂窗口回盾%s，共享%s秒；已有窗口不续、不回盾" % [_number(v.window_restore), _number(v.window_restore_cooldown)])
		"I09":
			if int(v.get("retaliate_frost", 0)) > 0: rows.append("护体中受伤且存活：给%s米内最近可视敌人1层寒霜，间隔%s秒" % [_number(v.retaliate_range), _number(v.retaliate_cooldown)])
		"I10":
			rows.append("普通寒霜有效期%s秒；不延长硬冻或免控时间" % _number(v.get("frost_expiry", 4)))
	return "\n".join(rows)


static func _growth_upgrade_text(id: String, a: Dictionary, b: Dictionary) -> String:
	# At most five explicit lines on compact cards; full rules are in the tooltip.
	match id:
		"F01": return "焰弹 %s → %s\n爆炸 %s → %s米\n%s" % [_percent(a.coefficient), _percent(b.coefficient), _number(a.radius), _number(b.radius), ("追加%s焰弹\n" % _percent(b.secondary) if float(b.secondary) > 0.0 else "") + "暴击留火：%s/跳·%s秒" % [_percent(b.crit_patch_coefficient), _number(b.crit_patch_duration)]]
		"F02": return "火伤 %s → %s\n火系暴击率 +%s\n火系暴伤 +%s个百分点" % [_percent(a.fire_bonus), _percent(b.fire_bonus), _percent(b.fire_crit_rate_add), _number(float(b.crit_bonus)*100.0)]
		"F03": return "每落 %s → %s·共%s落\n首落%s·前%s落固定中心\n%s" % [_percent(a.coefficient), _percent(b.coefficient), _number(b.drops), _percent(b.first_drop_coefficient), _number(b.fixed_center_drops), "余火%s/跳·%s秒" % [_percent(b.ground_coefficient), _number(b.ground_duration)] if float(b.ground_duration)>0.0 else "命中点燃"]
		"F05": return "每跳 %s → %s\n半径%s米·终点停留%s秒\n首次命中减速%s·%s秒" % [_percent(a.coefficient), _percent(b.coefficient), _number(b.radius), _number(b.end_duration), _percent(b.first_hit_slow), _number(b.first_hit_slow_duration)]
		"F06": return "每跳 %s → %s\n半径%s米·持续%s秒\n双区域重叠火伤 +%s\n%s" % [_percent(a.coefficient), _percent(b.coefficient), _number(b.radius), _number(b.duration), _percent(b.overlap_fire_vulnerability), "满%s秒爆发%s·离阵保留%s秒" % [_number(b.mature_after), _percent(b.mature_coefficient), _number(b.grace)] if float(b.mature_coefficient)>0.0 else "阵内攻击力 +%s" % _percent(b.attack_bonus)]
		"F07": return "中心%s·外围%s\n中心暴伤 +%s个百分点\n自然引爆 ×%s\n%s" % [_percent(float(b.coefficient)*float(b.main_center_damage_multiplier)), _percent(b.outer), _number(float(b.main_center_crit_multiplier_add)*100.0), _number(float(b.detonation_multiplier) + float(b.natural_detonation_multiplier_add)), "自然消耗后%s秒复燃·余震%s" % [_number(b.reapply_delay), _percent(b.aftershock)] if float(b.reapply_delay)>0.0 else "主爆与引爆不点燃"]
		"F08": return "主束 %s → %s\n长%s米·宽%s米\n%s" % [_percent(a.coefficient), _percent(b.coefficient), _number(b.range), _number(b.width), "脉冲%s\n每%s次自然释放追加%s" % [_percent(b.secondary), _number(b.echo_every), _percent(b.echo_scale)] if int(b.echo_every)>0 else "贯穿沿途敌人"]
		"F09": return "冲击 %s → %s\n半径%s米·击退%s米\n命中移速 +%s·%s秒\n%s" % [_percent(a.coefficient), _percent(b.coefficient), _number(b.radius), _number(b.push), _percent(b.hit_move_speed_bonus), _number(b.hit_move_speed_duration), "敌人减速%s·%s秒" % [_percent(b.slow), _number(b.slow_duration)] if float(b.slow)>0 else "命中点燃"]
		"F10": return "回盾 %s → %s\n冷却 %s → %s秒" % [_number(a.shield), _number(b.shield), _number(a.cooldown), _number(b.cooldown)]
		"F11": return "主击 %s → %s\n传播%s米内%s名未燃邻敌\n全局燃烧%s秒·最多%s跳" % [_percent(a.coefficient), _percent(b.coefficient), _number(b.spread_radius), _number(b.spread_targets), _number(b.burn_duration), _number(b.burn_maximum_ticks)]
		"I01": return "霜弹 %s → %s\n对1至2层寒霜额外%s攻击\n%s" % [_percent(a.coefficient), _percent(b.coefficient), _percent(b.frosted_coefficient_add), "对上述目标施霜2层" if b.has("chill_stacks_if_pre_frost_1_or_2") else "命中施霜1层"]
		"I02": return "首敌%s·后敌%s\n宽%s米·最多%s敌\n%s" % [_percent(b.coefficient), _percent(b.following_coefficient), _number(b.width), _number(b.target_cap), "首次主段命中已有寒霜者\n额外施霜1层" if int(b.first_direct_extra_frost)>0 else "每敌施霜1层"]
		"I03": return "主击 %s → %s\n半径%s米·%s秒后落下\n%s" % [_percent(a.coefficient), _percent(b.coefficient), _number(b.radius), _number(b.impact_delay), "后冰屑%s·首次主段\n命中已有寒霜者多施1层" % _percent(b.followup_coefficient) if float(b.followup_coefficient)>0 else "命中施霜1层"]
		"I04": return "霜环 %s → %s\n半径%s米·施霜%s层\n短减速：普通%s／精英%s" % [_percent(a.coefficient), _percent(b.coefficient), _number(b.radius), _number(b.chill_stacks), _percent(b.slow_normal), _percent(b.slow_elite)]
		"I05": return "每跳 %s → %s\n半径%s米·%s秒共%s跳\n首次有效施霜%s层" % [_percent(a.coefficient), _percent(b.coefficient), _number(b.radius), _number(b.duration), _number(b.ticks), _number(b.first_valid_chill_stacks)]
		"I06": return "每波%s·共%s波·宽%s米\n末波额外 ×%s\n%s" % [_percent(b.coefficient), _number(b.waves), _number(b.width), _number(b.final_wave_multiplier), "第二次合资格施霜多1层\n末波对就绪者基础%s" % _percent(b.final_ready_coefficient) if int(b.second_area_extra_frost)>0 else "第1、3次有效波施霜"]
		"I07": return "主击%s·冰裂%s\n邻片%s·%s米内最多%s敌\n邻片给%s名存活敌人施霜\n%s" % [_percent(b.coefficient), _percent(b.shatter_coefficient), _percent(b.shard_coefficient), _number(b.shard_radius), _number(b.shard_target_cap), _number(b.fragment_frost_targets), "自然主冰裂 ×%s并留1层" % _number(b.natural_shatter_multiplier) if float(b.natural_shatter_multiplier)>1.0 else "旧窗口只能消费一次"]
		"I08": return "主击 %s → %s\n免控目标额外%s攻击\n新建窗口回盾%s·间隔%s秒\n基础硬冻%s秒" % [_percent(a.coefficient), _percent(b.coefficient), _percent(b.immune_coefficient_add), _number(b.window_restore), _number(b.window_restore_cooldown), _number(b.freeze_base)]
		"I09": return "防御 +%s·持续%s秒\n%s米内施霜1层\n受伤反霜：%s米·间隔%s秒\n%s" % [_number(b.defense_add), _number(b.duration), _number(b.radius), _number(b.retaliate_range), _number(b.retaliate_cooldown), "%s秒后追加施霜1层" % _number(b.followup_delay) if int(b.followup_chill_stacks)>0 else "受伤且存活后触发"]
		"I10": return "冰伤 %s → %s\n普通寒霜有效期%s秒\n冰裂窗口 +%s秒" % [_percent(a.school_damage_bonus), _percent(b.school_damage_bonus), _number(b.frost_expiry), _number(b.ready_window_add)]
	return ""


static func _artifact_card_effect(id: String, value: Dictionary) -> String:
	if bool(value.get("boss_only", false)):
		return "常规伤害 +%s\n最大生命 +%s\n获得时不恢复生命" % [_percent(value.damage_bonus), _number(value.health_max_add)]
	# Cards show the decision; the complete interaction limits remain in description.
	if str(value.get("scope", "")) == "ice":
		return _ice_artifact_card_effect(id, value)
	if value.has("description"):
		return str(value.description)
	match id:
		"P02": return "法术直接命中并暴击时，留下熔火刻印。\n半径 %s 米，持续 %s 秒。\n每 %s 秒伤害：%s 攻击力。" % [_number(value["radius"]), _number(value["duration"]), _number(value["interval"]), _percent(value["coefficient"])]
		"P04": return "每正常施法 %s 次，随机追加一个可用的已学主动法术。\n保留当前等级，产生 %s 效果。" % [_number(value["natural_casts_per_extra"]), _percent(value["damage_multiplier"])]
		"G01": return "火系伤害 +%s。\n每正常施放进攻火术 %s 次，追加一次该法术，造成 %s 本体伤害。" % [_percent(value["fire_bonus_add"]), _number(value["offensive_casts_per_echo"]), _percent(value["echo_damage_multiplier"])]
		"G02": return "精灵在场时，正常施放伤害法术会引发协同光束。\n伤害：%s 攻击力。\n触发间隔：%s 秒，所有精灵共享。" % [_percent(value["coefficient"]), _number(value["shared_cooldown"])]
		"G03": return "自然火区存在满 %s 秒时爆发一次。\n伤害：%s 攻击力。\n爆炸半径：%s 米。" % [_number(value["trigger_age"]), _percent(value["coefficient"]), _number(value["radius"])]
		"P06": return "燃烧持续时间延长至 %s 秒。\n每跳伤害与间隔不变。\n传播与复燃同样延长。" % _number(value["burn_duration"])
		"G04": return "自然爆弹引爆倍率 +%s。\n成功引爆后 %s 秒复燃。\n同敌每 %s 秒最多安排一次。" % [_number(value["detonation_multiplier_add"]), _number(value["reapply_delay"]), _number(value["reapply_shared_cooldown"])]
	return _artifact_effect(id, value)


static func _artifact_effect(id: String, value: Dictionary) -> String:
	if bool(value.get("boss_only", false)):
		return str(value.description)
	if str(value.get("scope", "")) == "ice":
		return _ice_artifact_effect(id, value)
	if value.has("description"):
		return str(value.description)
	match id:
		"B01": return "焰弹与追加焰弹的爆炸半径 +%s。" % _increase(value["radius_multiplier"])
		"B02": return "火焰暴击率 +%s 个百分点。" % _number(float(value["fire_crit_rate_add"]) * 100.0)
		"B03": return "火雨首落伤害 +%s；前 %s 落固定原中心。第二落仍用原伤害，总落数不变。" % [_increase(value["first_drop_damage_multiplier"]), _number(value["fixed_center_drops"])]
		"B04": return "精灵持续时间 +%s 秒，自行攻击的光束伤害 +%s。" % [_number(value["duration_add"]), _increase(value["normal_laser_damage_multiplier"])]
		"B05": return "每个旋涡首次命中敌人时，使其减速 %s，持续 %s 秒。" % [_percent(value["slow"]), _number(value["duration"])]
		"B06": return "法阵半径 +%s，同时扩大伤敌与强化范围。" % _increase(value["radius_multiplier"])
		"B07": return "熔核爆弹主爆中心伤害 +%s，该分量暴击伤害 +%s 个百分点；不影响外围、余震和引爆。" % [_increase(value["main_center_damage_multiplier"]), _number(float(value["main_center_crit_multiplier_add"]) * 100.0)]
		"B08": return "贯焰光束与其脉冲宽度 +%s。" % _increase(value["width_multiplier"])
		"B09": return "灼浪命中后，你的移动速度 +%s，持续 %s 秒。" % [_percent(value["move_speed_bonus"]), _number(value["duration"])]
		"B10": return "暖焰护持每次多回复 %s 点护盾，不超过护盾上限。" % _number(value["shield_restore_add"])
		"B11": return "引燃之印向未燃邻敌传播的数量上限 +%s。仍只传一轮，不增加即时伤害。" % _number(value["spread_targets_add"])
		"P01": return "赤焰灵契的精灵数量 +%s；满员时不重复召唤。" % _number(value["spirit_count_add"])
		"P02": return "自然直接火伤暴击时留下刻印：半径 %s 米，持续 %s 秒，每 %s 秒伤害为 %s 攻击力。每次施法至多 %s 片；追加施法不触发，刻印不点燃。" % [_number(value["radius"]), _number(value["duration"]), _number(value["interval"]), _percent(value["coefficient"]), _number(value["patches_per_natural_cast"])]
		"P03": return "同时处于火雨、焰流旋涡、法阵中至少 %s 种火区的敌人，受到的火系伤害 +%s。刻印地火不补种类，离开重叠立即失效。" % [_number(value["required_distinct_areas"]), _percent(value["fire_vulnerability"])]
		"P04": return "每正常施法 %s 次，随机追加一个可用的已学主动法术，保留等级和 %s 效果。追加施法不计数。" % [_number(value["natural_casts_per_extra"]), _percent(value["damage_multiplier"])]
		"P05": return "每 %s 秒，所有主动法术的当前剩余冷却缩短 %s。" % [_number(value["interval"]), _percent(1.0 - float(value["remaining_cooldown_multiplier"]))]
		"G01": return "火系伤害 +%s。每正常施放进攻火术 %s 次，追加同法术的 %s 本体直伤／区域伤害；点燃与燃烧引爆按独立规则，追加不计数。" % [_percent(value["fire_bonus_add"]), _number(value["offensive_casts_per_echo"]), _percent(value["echo_damage_multiplier"])]
		"G02": return "精灵在场时，你正常施放伤害法术会引发协同光束，伤害为 %s 攻击力。所有精灵共享 %s 秒间隔；宝物追加施法不触发。" % [_percent(value["coefficient"]), _number(value["shared_cooldown"])]
		"G03": return "自然持续火区存在满 %s 秒时爆炸：半径 %s 米，伤害为 %s 攻击力。每次施法至多 %s 次；提前替换、清场或追加火区不触发，爆炸不点燃。" % [_number(value["trigger_age"]), _number(value["radius"]), _percent(value["coefficient"]), _number(value["explosions_per_natural_cast"])]
		"P06": return "新施加或刷新时，燃烧持续 %s 秒，完整燃烧共 %s 次跳伤；每跳伤害与间隔不变。传播和复燃同样延长。" % [_number(value["burn_duration"]), _number(value["maximum_ticks"])]
		"G04": return "自然熔核爆弹的引爆倍率 +%s。实际消费旧燃烧后 %s 秒，若目标仍活且仍在本房则复燃；同敌每 %s 秒最多安排一次。追加爆弹不享受强化或复燃，且可能提前消耗燃料。" % [_number(value["detonation_multiplier_add"]), _number(value["reapply_delay"]), _number(value["reapply_shared_cooldown"])]
		"U01": return "本局生命上限 +%s，当前生命不变。" % _number(value["health_max_add"])
		"U02": return "本局护盾上限 +%s，下次清场时按新上限补满。" % _number(value["shield_max_add"])
		"U03": return "本局攻击力 +%s，提升法术与伤害型宝物。" % _number(value["attack_add"])
	return ""


static func _artifact_card_requirement(item: Dictionary, catalog: Dictionary) -> String:
	if bool(item.get("boss_only", false)):
		return "第%d房首领金池取尽后的专属庭印" % int(item.boss_room)
	if str(item.get("scope",""))=="ice" and item.has("required_spell"):
		return "条件："+spell_name(str(item["required_spell"]))
	match str(item.get("requirement", "")):
		"ice_two_starters": return "条件：霜弹、冰锥、寒星\n持有其中至少两种"
		"ice_shards_and_frost": return "条件：二级碎冰＋另一施霜术"
		"ice_armor_and_damage": return "条件：护体＋冰系主动伤害术"
		"ice_synergy_and_area": return "条件：三种冰术\n含极寒领域或冰晶风暴"
		"ice_shatter_and_frost": return "条件：碎冰术＋另一施霜术"
		"ice_prison_and_armor": return "条件：冰封棺＋凝霜护体"
		"natural_direct_fire": return "条件：持有直接造成火伤的法术"
		"synergy_and_player_offense": return "条件：大火魔法师＋主动伤害法术"
		"spirit_and_player_offense": return "条件：赤焰灵契＋其他伤害法术"
		"persistent_area_spell": return "条件：焰流旋涡、法阵或三级火雨"
		"any_igniter": return "条件：持有能点燃的法术"
		"bomb_and_igniter": return "条件：熔核爆弹＋点燃法术"
	return _artifact_requirement(item, catalog)


static func _artifact_requirement(item: Dictionary, catalog: Dictionary) -> String:
	if bool(item.get("boss_only", false)):
		return "仅第%d房首领必金箱兜底；不进入普通宝箱或商店。" % int(item.boss_room)
	if item.has("required_spell"):
		return "持有 " + spell_name(str(item["required_spell"]))
	match str(item.get("requirement", "")):
		"ice_two_starters": return "持有霜弹、冰锥、寒星中至少两种"
		"ice_shards_and_frost": return "持有至少二级碎冰术与另一种施霜法术"
		"ice_armor_and_damage": return "持有凝霜护体与冰系伤害主动术"
		"ice_synergy_and_area": return "持有至少三种冰术，含极寒领域或冰晶风暴"
		"ice_shatter_and_frost": return "持有碎冰术与另一种施霜法术"
		"ice_prison_and_armor": return "持有冰封棺与凝霜护体"
		"natural_direct_fire": return "持有可直接造成火焰伤害的主动法术"
		"two_area_spells": return "持有火雨、焰流旋涡、法阵中至少 %s 种" % _number(item.get("required_distinct_areas"))
		"any_active_spell": return "持有主动法术"
		"any_cooldown_spell": return "持有带冷却的主动法术"
		"synergy_and_player_offense": return "大火魔法师已激活，并持有主动伤害法术"
		"spirit_and_player_offense": return "持有赤焰灵契与另一主动伤害法术"
		"persistent_area_spell": return "持有持续区域法术（焰流旋涡、法阵或满级火雨）"
		"any_igniter": return "持有能施加燃烧的正式火系法术"
		"bomb_and_igniter": return "持有熔核爆弹和至少一种点燃法术"
		"permanent_crit_rate": return "常驻暴击率达到 %s" % _percent(item.get("minimum_crit_rate"))
		"combat_shield_recovery_and_player_damage": return "持有战斗回盾来源与玩家主动伤害法术"
	return "通用道具 · 无法术条件" if item.get("scope") == "generic" else ""



static func starter_ids(school: String = "fire") -> Array:
	var content := load_catalog()
	if school in ["lightning", "wind", "earth", "spirit"]:
		return content.get(school + "_source", {}).get("mechanics", {}).get("initial_ids", [])
	return content.get("ice_source", {}).get("mechanics", {}).get("initial_ids", []) if school == "ice" else content.get("spell_runtime", {}).get("fire", {}).get("initial_ids", STARTER_SPELLS)


static func school_name(school: String) -> String:
	return {"fire": "火系", "ice": "冰系", "lightning": "雷系", "wind": "风系", "earth": "岩系", "spirit": "灵契"}.get(school, school)


static func school_color(school: String) -> Color:
	return Color({"fire": "eea175", "ice": "8bd9ed", "lightning": "c5b3ff", "wind": "a5e2bd", "earth": "e0bd83", "spirit": "e9b2e1"}.get(school, "eea175"))


static func _new_school_spell_effect(id: String, v: Dictionary) -> String:
	match id:
		"W01": return "主击%s攻击·全宽%s米\n最多%s敌·逐敌保留%s伤害\n弹速%s米／秒，锁定方向" % [_percent(v.coefficient), _number(v.width), _number(v.target_cap), _percent(v.falloff), _number(v.speed)]
		"W02":
			var text := "去程%s／回程%s攻击\n去程%s米·全宽%s米\n回程宽×%s·每程最多%s敌" % [_percent(v.out_coefficient), _percent(v.return_coefficient), _number(v.out_length), _number(v.width), _number(v.return_width_multiplier), _number(v.leg_target_cap)]
			if float(v.return_vulnerability) > 0.0: text += "\n自然返程：自主路程≥%s米\n本击后风易伤＋%s，%s秒" % [_number(v.required_player_path), _percent(v.return_vulnerability), _number(v.vulnerability_duration)]
			return text
		"W03":
			var text := "主击%s攻击·全宽%s米\n转速%s度／秒，累计最多%s度\n最多飞行%s米／%s秒" % [_percent(v.coefficient), _number(v.width), _number(v.turn_speed_degrees), _number(v.turn_budget_degrees), _number(v.max_path), _number(v.lifetime)]
			if float(v.long_multiplier) > 1.0: text += "\n实际飞行≥%s米：本击×%s" % [_number(v.long_path), _number(v.long_multiplier)]
			return text
		"W04":
			var text := "%s度锥形·长%s米\n伤害%s·基础推距%s米" % [_number(v.angle_degrees), _number(v.range), _percent(v.coefficient), _number(v.push_distance)]
			if float(v.slow) > 0.0: text += "\n减速%s，持续%s秒（受抗性上限）" % [_percent(v.slow), _number(v.slow_duration)]
			return text
		"W05": return "半径%s米·持续%s秒\n每%s秒各%s攻击，首跳同间隔\n基本总拉距%s米，单跳最多%s米\n每跳最多拉%s敌；伤害不限此名额" % [_number(v.radius), _number(v.duration), _number(v.interval), _percent(v.coefficient), _number(v.pull_total), _number(v.pull_tick_cap), _number(v.pull_target_cap)]
		"W06":
			var text := "%s秒后固定落点主爆%s\n半径%s米" % [_number(v.impact_delay), _percent(v.coefficient), _number(v.radius)]
			if float(v.center_coefficient_add) > 0.0: text += "\n中心%s米额外＋%s个百分点" % [_number(v.center_radius), _number(float(v.center_coefficient_add) * 100.0)]
			if float(v.followup_coefficient) > 0.0: text += "\n再隔%s秒补压%s，可暴击" % [_number(v.followup_delay), _percent(v.followup_coefficient)]
			return text
		"W07":
			var text := "每翼%s攻击·长%s／宽%s米\n两翼分别最多%s敌" % [_percent(v.coefficient), _number(v.length), _number(v.width), _number(v.target_cap)]
			if float(v.cross_coefficient) > 0.0: text += "\n同cast双翼实际命中：交剪%s一次" % _percent(v.cross_coefficient)
			return text
		"W08": return "录制%s秒，最多%s米真实路径\n每%s米成段·半径%s米·段寿%s秒\n接触每击%s攻击\n每敌每cast最多%s击，任意%s秒最多%s击\n同敌最短间隔%s秒" % [_number(v.record_duration), _number(v.total_length), _number(v.spacing), _number(v.radius), _number(v.segment_lifetime), _percent(v.coefficient), _number(v.cast_hit_cap), _number(load_catalog().wind_source.mechanics.path_shared_window), _number(v.shared_hit_cap), _number(load_catalog().wind_source.mechanics.path_hit_gate)]
		"W09": return "固定带宽%s米／厚%s米\n持续%s秒，带内敌飞弹速度×%s\n不回盾、不直接伤害" % [_number(v.width), _number(v.depth), _number(v.duration), _number(v.speed_multiplier)]
		"W10": return "最近%s秒自主实际走过≥%s米\n满足时风伤＋%s\n条件失效后保留%s秒" % [_number(load_catalog().wind_source.mechanics.motion_window), _number(v.required_path), _percent(v.school_damage_bonus), _number(v.grace_duration)]
		"R01": return "主矢%s攻击·全宽%s米\n%s片各%s，长%s／全宽%s米\n每片最多%s敌，同cast次敌最多一片" % [_percent(v.main), _number(v.width), _number(v.shard_count), _percent(v.shard), _number(v.shard_range), _number(v.shard_width), _number(v.shard_pierce)]
		"R02": return "震波%s攻击·最远%s米\n波速%s米／秒·波宽%s米\n实际命中距离≥%s米：额外＋%s个百分点" % [_percent(v.main), _number(v.radius), _number(v.speed), _number(v.wave_width), _number(v.outer_threshold), _number(float(v.outer_bonus) * 100.0)]
		"R03":
			var text := "%s秒后落击%s·半径%s米\n留下%s秒岩棱支点，不阻路" % [_number(v.delay), _percent(v.main), _number(v.radius), _number(v.construct_duration)]
			if float(v.after) > 0.0: text += "\n再隔%s秒原地裂波%s·半径%s米" % [_number(v.after_delay), _percent(v.after), _number(v.after_radius)]
			return text
		"R04": return "固定石柱半径%s米·存续%s秒\n首跳%s秒，每%s秒%s攻击\n同名唯一，不阻路" % [_number(v.radius), _number(v.duration), _number(v.first_tick), _number(v.interval), _percent(v.tick)]
		"R05": return "请求回复%s护盾\n基础冷却%s秒\n回复量按真实缺盾裁切" % [_number(v.shield_restore), _number(v.cooldown)]
		"R06":
			var text := "消费一个合格构造\n%s秒后主震%s·半径%s米" % [_number(v.delay), _percent(v.main), _number(v.radius)]
			if float(v.after) > 0.0: text += "\n主震后%s秒余波%s，可暴击" % [_number(v.after_delay), _percent(v.after)]
			return text
		"R07":
			var text := "基础%s·半径%s米\n%s米内最多借%s个不同构造\n首回响%s·半径%s米，%s秒后" % [_percent(v.main), _number(v.main_radius), _number(v.anchor_search_range), _number(v.echo_construct_cap), _percent(v.echo), _number(v.echo_radius), _number(v.echo_delay)]
			if float(v.second_echo) > 0.0: text += "\n第二源再隔同一间隔回响%s" % _percent(v.second_echo)
			return text
		"R08":
			var text := "%s秒后山崩%s·半径%s米\n基础硬控%s秒，受分类抗性" % [_number(v.delay), _percent(v.main), _number(v.radius), _number(v.stun)]
			if float(v.fracture) > 0.0: text += "\n外缘两条裂隙各%s·长%s／宽%s米" % [_percent(v.fracture), _number(v.fracture_length), _number(v.fracture_width)]
			return text
		"R09": return "固定护阵半径%s米·存续%s秒\n覆盖内且可见石碑：防御＋%s\n真实走出后保留%s秒" % [_number(v.radius), _number(v.duration), _number(v.defense), _number(v.exit_grace)]
		"R10": return "岩系伤害＋%s\n真实护盾大于零时：防御＋%s" % [_percent(v.earth_bonus), _number(v.shielded_defense)]
		"S01": return "灵矢%s攻击·最多贯%s敌\n第一有效主击施契印%s秒\n射程%s米，契印全队共享唯一" % [_percent(v.coefficient), _number(v.target_cap), _number(v.mark_duration), _number(v.range)]
		"S02": return "远程同名最多%s只，每次补至多%s只\n寿命%s秒·首击%s秒\n每%s秒光束%s，最多%s敌" % [_number(v.capacity), _number(v.summon_per_cast), _number(v.duration), _number(v.attack_delay), _number(v.attack_interval), _percent(v.coefficient), _number(v.target_cap)]
		"S03": return "侍从最多%s只，寿命%s秒\n每%s秒近战%s，最多%s敌\n索敌%s米·移动%s米／秒\n挥击角%s度，半径%s米" % [_number(v.capacity), _number(v.duration), _number(v.attack_interval), _percent(v.coefficient), _number(v.target_cap), _number(v.search_range), _number(v.move_speed), _number(v.cleave_angle_degrees), _number(v.cleave_radius)]
		"S04": return "灵鹰最多%s只，寿命%s秒\n每%s秒扫掠%s，最多%s敌\n扫掠长%s／宽%s米" % [_number(v.capacity), _number(v.duration), _number(v.attack_interval), _percent(v.coefficient), _number(v.target_cap), _number(v.sweep_length), _number(v.sweep_width)]
		"S05": return "最多%s名合格契灵各发一份协同\n%s秒后每份%s攻击\n每名来源最多%s敌，不暴击" % [_number(v.command_unit_cap), _number(v.command_delay), _percent(v.command_coefficient), _number(v.targets_per_unit)]
		"S06": return "基础爆发%s攻击·半径%s米\n最多消费%s只剩余寿命≤%s秒的宠物\n成功消费额外＋%s攻击，最多%s敌" % [_percent(v.base_coefficient), _number(v.radius), _number(v.consume_unit_cap), _number(v.consume_max_remaining), _percent(v.consume_bonus_coefficient), _number(v.target_cap)]
		"S07": return "固定法阵半径%s米·持续%s秒\n每宠每场首次合格覆盖续存%s秒\n每宠所有场累计额外上限%s秒\n新宠首击部署缩短%s秒，最低%s秒" % [_number(v.radius), _number(v.duration), _number(v.extension_per_unit), _number(v.lifetime_extension_cap), _number(v.new_unit_first_attack_delay_reduction), _number(v.minimum_first_attack_delay)]
		"S08": return "伤害%s·最多%s敌\n普通减速%s，已有契印改为%s\n持续%s秒，受分类上限\n%s" % [_percent(v.coefficient), _number(v.target_cap), _percent(v.base_slow), _percent(v.marked_slow), _number(v.slow_duration), "主击随后施契印%s秒" % _number(v.mark_duration) if bool(v.can_apply_mark) else "本级锁链不施契印"]
		"S09": return "基础请求回复%s护盾\n每只活跃进攻契灵额外＋%s\n最多计%s只·不生成宠物" % [_number(v.shield_restore), _number(v.shield_per_alive_unit), _number(v.bonus_unit_cap)]
		"S10": return "灵契伤害＋%s\n新施契印延长%s秒\n宠物契印普通攻击另＋%s（同系桶）" % [_percent(v.spirit_damage_bonus), _number(v.mark_duration_add), _percent(v.mark_normal_attack_bonus_add)]
	return ""


static func _new_school_card_effect(id: String, v: Dictionary) -> String:
	# Choice faces expose the defining result; full mechanics remain in details.
	match id:
		"W01": return "主击%s·最多%s敌\n每穿一敌余伤×%s\n锁定方向，遇墙结束" % [_percent(v.coefficient), _number(v.target_cap), _number(v.falloff)]
		"W02": return "去程%s／回程%s\n程长%s米，各可命中一次\n转折只锁一次归航点" % [_percent(v.out_coefficient), _percent(v.return_coefficient), _number(v.out_length)]
		"W03": return "追击主击%s\n累计转角最多%s度\n只追原目标，首敌结束" % [_percent(v.coefficient), _number(v.turn_budget_degrees)]
		"W04": return "锥形%s·长%s米\n基础推距%s米\n推距受抗性及墙限制" % [_percent(v.coefficient), _number(v.range), _number(v.push_distance)]
		"W05": return "每%s秒%s，持续%s秒\n半径%s米，定点聚敌\n基本总拉距%s米" % [_number(v.interval), _percent(v.coefficient), _number(v.duration), _number(v.radius), _number(v.pull_total)]
		"W06": return "主爆%s·半径%s米\n释放后%s秒固定点引爆\n落点锁定后不追踪" % [_percent(v.coefficient), _number(v.radius), _number(v.impact_delay)]
		"W07": return "每翼%s·各最多%s敌\n长%s／全宽%s米\n两翼独立碰撞与去重" % [_percent(v.coefficient), _number(v.target_cap), _number(v.length), _number(v.width)]
		"W08": return "接触每击%s·同敌最多%s击\n录制%s秒／最多%s米\n只沿真实自主路径留痕\n重施不重置共享命中预算" % [_percent(v.coefficient), _number(v.cast_hit_cap), _number(v.record_duration), _number(v.total_length)]
		"W09": return "带宽%s米·持续%s秒\n带内敌飞弹速度×%s\n固定风幕，只减弹速" % [_number(v.width), _number(v.duration), _number(v.speed_multiplier)]
		"W10": return "最近%s秒自主走≥%s米\n满足时风伤＋%s\n不增加移动速度" % [_number(load_catalog().wind_source.mechanics.motion_window), _number(v.required_path), _percent(v.school_damage_bonus)]
		"R01": return "主矢%s，散片各%s\n%s片，各最多%s名次敌\n同一敌人最多中一片" % [_percent(v.main), _percent(v.shard), _number(v.shard_count), _number(v.shard_pierce)]
		"R02": return "扩散震波%s\n最远%s米·每敌一次\n波前经过才命中" % [_percent(v.main), _number(v.radius)]
		"R03": return "落击%s·半径%s米\n%s秒后命中固定落点\n留下%s秒不阻路支点" % [_percent(v.main), _number(v.radius), _number(v.delay), _number(v.construct_duration)]
		"R04": return "每%s秒脉冲%s\n半径%s米·持续%s秒\n同名唯一，不阻路" % [_number(v.interval), _percent(v.tick), _number(v.radius), _number(v.duration)]
		"R05": return "请求回复%s护盾\n基础冷却%s秒\n按真实缺盾裁切" % [_number(v.shield_restore), _number(v.cooldown)]
		"R06": return "消费一个构造，主震%s\n半径%s米·延迟%s秒\n无合格构造就等待" % [_percent(v.main), _number(v.radius), _number(v.delay)]
		"R07": return "基础%s·半径%s米\n最多借%s源回响%s\n无构造仍有基础伤害" % [_percent(v.main), _number(v.main_radius), _number(v.echo_construct_cap), _percent(v.echo)]
		"R08": return "山崩%s·半径%s米\n延迟%s秒·基础硬控%s秒\n硬控受抗性，落点不追踪" % [_percent(v.main), _number(v.radius), _number(v.delay), _number(v.stun)]
		"R09": return "固定护阵半径%s米\n覆盖内防御＋%s，持续%s秒\n需到石碑无遮挡，不回盾" % [_number(v.radius), _number(v.defense), _number(v.duration)]
		"R10": return "岩系伤害＋%s\n被动占槽，参与岩系共鸣" % _percent(v.earth_bonus)
		"S01": return "灵矢%s·最多%s敌\n首名有效主击施契印%s秒\n契印全队共享唯一" % [_percent(v.coefficient), _number(v.target_cap), _number(v.mark_duration)]
		"S02": return "召唤远程契灵，最多%s只\n每%s秒光束%s\n存续%s秒，最多%s敌\n满员等待，不刷新寿命" % [_number(v.capacity), _number(v.attack_interval), _percent(v.coefficient), _number(v.duration), _number(v.target_cap)]
		"S03": return "召唤近战侍从，存续%s秒\n每%s秒近战%s\n须沿合法地面追击到位" % [_number(v.duration), _number(v.attack_interval), _percent(v.coefficient)]
		"S04": return "召唤灵鹰，存续%s秒\n每%s秒扫掠%s\n每次最多%s敌，须追击到位" % [_number(v.duration), _number(v.attack_interval), _percent(v.coefficient), _number(v.target_cap)]
		"S05": return "每名合格契灵协同%s\n%s秒后命中，不暴击\n不重置普通攻击" % [_percent(v.command_coefficient), _number(v.command_delay)]
		"S06": return "基础%s·半径%s米\n消费合格宠物额外＋%s\n无可消费宠物仍可施放" % [_percent(v.base_coefficient), _number(v.radius), _percent(v.consume_bonus_coefficient)]
		"S07": return "固定场半径%s米·%s秒\n每宠每场合格续存%s秒\n终身续存预算%s秒" % [_number(v.radius), _number(v.duration), _number(v.extension_per_unit), _number(v.lifetime_extension_cap)]
		"S08": return "主击%s·减速%s\n已有契印改减速%s\n持续%s秒，受分类上限" % [_percent(v.coefficient), _percent(v.base_slow), _percent(v.marked_slow), _number(v.slow_duration)]
		"S09": return "基础请求回复%s护盾\n每活宠另＋%s，最多%s只\n按真实缺盾裁切" % [_number(v.shield_restore), _number(v.shield_per_alive_unit), _number(v.bonus_unit_cap)]
		"S10": return "灵契伤害＋%s\n被动占槽，参与灵契共鸣" % _percent(v.spirit_damage_bonus)
	return ""


static func _new_school_upgrade_text(id: String, a: Dictionary, b: Dictionary) -> String:
	match id:
		"W01": return "最多%s → %s敌\n%s\n主击%s" % [_number(a.target_cap), _number(b.target_cap), "穿透不再衰减" if float(b.falloff) >= 1.0 else "全宽增至%s米，仍逐敌衰减" % _number(b.width), "%s → %s" % [_percent(a.coefficient), _percent(b.coefficient)] if not is_equal_approx(float(a.coefficient), float(b.coefficient)) else "保持" + _percent(b.coefficient)]
		"W02": return "去程%s／回程%s\n%s" % [_percent(b.out_coefficient), _percent(b.return_coefficient), "自然返程自主走≥%s米\n本击后风易伤＋%s" % [_number(b.required_player_path), _percent(b.return_vulnerability)] if float(b.return_vulnerability) > 0.0 else "去程增至%s米\n回程宽×%s" % [_number(b.out_length), _number(b.return_width_multiplier)]]
		"W03": return "主击%s\n%s" % ["%s → %s" % [_percent(a.coefficient), _percent(b.coefficient)] if not is_equal_approx(float(a.coefficient), float(b.coefficient)) else "保持" + _percent(b.coefficient), "新增长程强化\n实际飞行≥%s米：本击×%s" % [_number(b.long_path), _number(b.long_multiplier)] if float(b.long_multiplier) > 1.0 else "全宽%s米，累计转角%s度" % [_number(b.width), _number(b.turn_budget_degrees)]]
		"W04": return "伤害%s·基础推距%s米\n长度%s米\n%s" % [_percent(b.coefficient), _number(b.push_distance), _number(b.range), "减速%s／%s秒，受分类上限" % [_percent(b.slow), _number(b.slow_duration)] if float(b.slow) > 0.0 else "推距受抗性与墙裁剪"]
		"W05": return "每跳%s，持续%s → %s秒\n半径%s米\n基本总拉距%s米" % [_percent(b.coefficient), _number(a.duration), _number(b.duration), _number(b.radius), _number(b.pull_total)]
		"W06": return "主爆%s·半径%s米\n%s" % [_percent(b.coefficient), _number(b.radius), "中心另＋%s个百分点\n追加%s补压" % [_number(float(b.center_coefficient_add) * 100.0), _percent(b.followup_coefficient)] if float(b.followup_coefficient) > 0.0 else "伤害与范围提高，仍锁固定点"]
		"W07": return "每翼%s → %s\n长%s／宽%s米\n%s" % [_percent(a.coefficient), _percent(b.coefficient), _number(b.length), _number(b.width), "同cast双翼命中再交剪%s" % _percent(b.cross_coefficient) if float(b.cross_coefficient) > 0.0 else "每翼最多%s敌" % _number(b.target_cap)]
		"W08": return "录制%s秒／最多%s米\n每击%s，间距%s米\n段寿%s秒，同敌最多%s击" % [_number(b.record_duration), _number(b.total_length), _percent(b.coefficient), _number(b.spacing), _number(b.segment_lifetime), _number(b.cast_hit_cap)]
		"W09": return "带宽%s → %s米\n持续%s → %s秒\n带内敌飞弹速度×%s" % [_number(a.width), _number(b.width), _number(a.duration), _number(b.duration), _number(b.speed_multiplier)]
		"W10": return "条件风伤%s → %s\n路程门槛%s米\n失效后保留%s秒" % [_percent(a.school_damage_bonus), _percent(b.school_damage_bonus), _number(b.required_path), _number(b.grace_duration)]
		"R01": return "主矢%s／碎片各%s\n碎片全宽%s米、长%s米\n每片最多%s敌" % [_percent(b.main), _percent(b.shard), _number(b.shard_width), _number(b.shard_range), _number(b.shard_pierce)]
		"R02": return "伤害%s·最远%s米\n波速%s米／秒\n%s" % [_percent(b.main), _number(b.radius), _number(b.speed), "实际距离≥%s米：＋%s个百分点" % [_number(b.outer_threshold), _number(float(b.outer_bonus) * 100)] if float(b.outer_bonus) > 0.0 else "波速和范围提高"]
		"R03": return "主击%s·半径%s米\n支点%s秒\n%s" % [_percent(b.main), _number(b.radius), _number(b.construct_duration), "%s秒后追加%s裂波" % [_number(b.after_delay), _percent(b.after)] if float(b.after) > 0.0 else "落空也可在合法点留支点"]
		"R04": return "每%s秒%s，半径%s米\n存续%s秒\n首跳%s" % [_number(b.interval), _percent(b.tick), _number(b.radius), _number(b.duration), "改为立即" if float(b.first_tick) <= 0.0 else _number(b.first_tick) + "秒后"]
		"R05": return "回盾请求%s → %s\n基础CD%s → %s秒\n按真实缺盾裁切" % [_number(a.shield_restore), _number(b.shield_restore), _number(a.cooldown), _number(b.cooldown)]
		"R06": return "消费主震%s → %s\n半径%s米\n%s" % [_percent(a.main), _percent(b.main), _number(b.radius), "%s秒后余波%s" % [_number(b.after_delay), _percent(b.after)] if float(b.after) > 0.0 else "仍只消费一个构造"]
		"R07": return "基础%s·找源%s米\n最多借%s个不同构造\n首回响%s%s" % [_percent(b.main), _number(b.anchor_search_range), _number(b.echo_construct_cap), _percent(b.echo), "，第二份" + _percent(b.second_echo) if float(b.second_echo) > 0.0 else ""]
		"R08": return "主击%s·半径%s米\n延迟%s秒、基础硬控%s秒\n%s" % [_percent(b.main), _number(b.radius), _number(b.delay), _number(b.stun), "外缘两裂隙各%s" % _percent(b.fracture) if float(b.fracture) > 0.0 else "硬控受分类抗性"]
		"R09": return "覆盖防御%s → %s\n半径%s米，持续%s秒\n真实走出保留%s秒" % [_number(a.defense), _number(b.defense), _number(b.radius), _number(b.duration), _number(b.exit_grace)]
		"R10": return "岩伤%s → %s\n真实盾>0时防御＋%s" % [_percent(a.earth_bonus), _percent(b.earth_bonus), _number(b.shielded_defense)]
		"S01": return "灵矢%s·最多%s → %s敌\n射程%s米、主击契印%s秒\n穿透后续不施印" % [_percent(b.coefficient), _number(a.target_cap), _number(b.target_cap), _number(b.range), _number(b.mark_duration)]
		"S02": return "同名最多%s只，寿命%s秒\n每%s秒光束%s\n最多%s敌；满员等待" % [_number(b.capacity), _number(b.duration), _number(b.attack_interval), _percent(b.coefficient), _number(b.target_cap)]
		"S03": return "近战%s·寿命%s秒\n每%s秒，索敌%s米\n%s" % [_percent(b.coefficient), _number(b.duration), _number(b.attack_interval), _number(b.search_range), "%s度挥击，最多%s敌" % [_number(b.cleave_angle_degrees), _number(b.target_cap)] if int(b.target_cap) > 1 else "移动%s米／秒，单敌近战" % _number(b.move_speed)]
		"S04": return "每%s秒扫掠%s\n寿命%s秒\n最多%s → %s敌" % [_number(b.attack_interval), _percent(b.coefficient), _number(b.duration), _number(a.target_cap), _number(b.target_cap)]
		"S05": return "每名来源协同%s → %s\n最多%s名契灵各一份\n不重置普通攻击" % [_percent(a.command_coefficient), _percent(b.command_coefficient), _number(b.command_unit_cap)]
		"S06": return "基础爆发%s，半径%s米\n成功消费奖励%s → %s\n最多消费一只合格契灵" % [_percent(b.base_coefficient), _number(b.radius), _percent(a.consume_bonus_coefficient), _percent(b.consume_bonus_coefficient)]
		"S07": return "半径%s米／持续%s秒\n每宠每场续存%s秒\n终身续存预算%s秒" % [_number(b.radius), _number(b.duration), _number(b.extension_per_unit), _number(b.lifetime_extension_cap)]
		"S08": return "伤害%s·减速持续%s秒\n已有契印减速%s\n%s" % [_percent(b.coefficient), _number(b.slow_duration), _percent(b.marked_slow), "最多%s敌，主击可施契印" % _number(b.target_cap) if bool(b.can_apply_mark) else "本级不施契印"]
		"S09": return "基础回盾%s → %s\n基础CD%s → %s秒\n每活宠＋%s，最多%s只" % [_number(a.shield_restore), _number(b.shield_restore), _number(a.cooldown), _number(b.cooldown), _number(b.shield_per_alive_unit), _number(b.bonus_unit_cap)]
		"S10": return "灵契伤害%s → %s\n新契印延长%s秒\n契印普攻另＋%s（同桶）" % [_percent(a.spirit_damage_bonus), _percent(b.spirit_damage_bonus), _number(b.mark_duration_add), _percent(b.mark_normal_attack_bonus_add)]
	return ""


static func lightning_state_rule() -> String:
	var source: Dictionary = load_catalog().get("lightning_source", {})
	var conductive: Dictionary = source.get("mechanics", {}).get("conductive", {})
	return "导电每敌一份，不叠层、不造成持续伤害或麻痹。普通连接%s米，双端已有导电时另加%s米；逐边检查遮挡，同次施法不重访，空跳数不返还单体。" % [_number(conductive.get("base_hop_range")), _number(conductive.get("both_conductive_range_add"))]


static func _lightning_spell_effect(id: String, v: Dictionary) -> String:
	match id:
		"L01":
			var text := "主击%s攻击·弹速%s米／秒\n命中后导电%s秒" % [_percent(v.get("coefficient")), _number(v.get("speed")), _number(v.get("conductive_duration"))]
			if float(v.get("unconductive_coefficient_add", 0)) > 0:
				text += "\n未导电主击另＋%s个百分点" % _number(float(v.unconductive_coefficient_add) * 100.0)
			return text
		"L02":
			var text := "主击%s·穿线最多%s名其他敌人\n次目标各%s·全宽%s米" % [_percent(v.get("coefficient")), _number(v.get("secondary_target_cap")), _percent(v.get("secondary_coefficient")), _number(v.get("width"))]
			if float(v.get("isolated_main_multiplier", 1)) > 1:
				text += "\n主目标%s米内孤立：主击×%s" % [_number(v.get("isolated_radius")), _number(v.get("isolated_main_multiplier"))]
			return text + "\n存活受击者导电%s秒" % _number(v.get("conductive_duration"))
		"L03":
			return "首击%s·最多%s名不同敌人\n后跳逐次保留%s伤害\n每跳间隔%s秒·存活者导电%s秒" % [_percent(v.get("coefficient")), _number(v.get("target_cap")), _percent(v.get("hop_decay")), _number(v.get("hop_interval")), _number(v.get("conductive_duration"))]
		"L04":
			return "主击%s\n%s米内最多%s名未导电邻敌布点\n导电%s秒·仅传播一轮" % [_percent(v.get("coefficient")), _number(v.get("spread_range")), _number(v.get("neighbor_cap")), _number(v.get("conductive_duration"))]
		"L05":
			var times: Array = v.get("strike_times", [])
			var text := "半径%s米·持续%s秒\n共%s次落雷，最多%s敌各%s\n各次云团独立，不取消旧波" % [_number(v.get("radius")), _number(v.get("duration")), _number(times.size()), _number(v.get("strike_target_cap")), _percent(v.get("coefficient"))]
			if float(v.get("natural_first_hit_vulnerability", 0)) > 0:
				text += "\n自然云首次命中后雷易伤＋%s·%s秒" % [_percent(v.get("natural_first_hit_vulnerability")), _number(v.get("vulnerability_duration"))]
			return text
		"L06":
			var text := "半径%s米·主脉冲%s\n存活命中者导电%s秒" % [_number(v.get("radius")), _percent(v.get("coefficient")), _number(v.get("conductive_duration"))]
			if float(v.get("followup_coefficient", 0)) > 0:
				text += "\n%s秒后原地追加%s脉冲\n后脉冲也刷新导电" % [_number(v.get("followup_delay")), _percent(v.get("followup_coefficient"))]
			return text
		"L07":
			var text := "主击%s\n旧导电目标另受%s非暴击雷伤" % [_percent(v.get("coefficient")), _percent(v.get("conductive_extra_coefficient"))]
			if int(v.get("mature_arc_target_cap", 0)) > 0:
				text += "\n自然裁决：导电满%s秒且存活\n向最多%s名旧导电邻敌各放%s电弧" % [_number(v.get("mature_age")), _number(v.get("mature_arc_target_cap")), _percent(v.get("mature_arc_coefficient"))]
			return text
		"L08":
			var overload: Dictionary = load_catalog().get("lightning_source", {}).get("mechanics", {}).get("overload", {})
			var text := "主击%s·边伤%s，不暴击\n含主目标最多%s敌" % [_percent(v.get("coefficient")), _percent(v.get("edge_coefficient")), _number(v.get("target_cap"))]
			text += "\n旧导电至少%s节点：前%s边×%s" % [_number(overload.get("minimum_precast_conductive_component")), _number(v.get("natural_overload_edges", overload.get("boosted_existing_edges"))), _number(v.get("natural_overload_multiplier", overload.get("coefficient_multiplier")))]
			if v.has("natural_overload_edges"):
				text += "\n追加仍按基础过载规则"
			return text
		"L09":
			return "回复%s护盾·冷却%s秒\n实际回复后%s米内最多%s敌布点\n导电%s秒；不回复生命" % [_number(v.get("shield_restore")), _number(v.get("cooldown")), _number(v.get("conductive_range")), _number(v.get("conductive_target_cap")), _number(v.get("conductive_duration"))]
		"L10":
			var text := "雷系伤害＋%s" % _percent(v.get("school_damage_bonus"))
			if float(v.get("conductive_duration_add", 0)) > 0:
				text += "\n以后新施加／刷新导电延长%s秒" % _number(v.get("conductive_duration_add"))
			if float(v.get("both_conductive_range_add", 0)) > 0:
				text += "\n双端导电的连接再加%s米" % _number(v.get("both_conductive_range_add"))
			return text
	return ""


static func _lightning_upgrade_text(id: String, a: Dictionary, b: Dictionary) -> String:
	# Compact choice cards expose the resulting mechanism; full boundaries stay in tooltips.
	match id:
		"L01": return "主击%s → %s\n未导电另＋%s个百分点\n导电%s秒" % [_percent(a.get("coefficient")), _percent(b.get("coefficient")), _number(float(b.get("unconductive_coefficient_add", 0)) * 100), _number(b.get("conductive_duration"))]
		"L02": return "主击%s → %s\n最多%s名次目标各%s\n孤立主目标×%s" % [_percent(a.get("coefficient")), _percent(b.get("coefficient")), _number(b.get("secondary_target_cap")), _percent(b.get("secondary_coefficient")), _number(b.get("isolated_main_multiplier", 1))]
		"L03": return "首击%s → %s\n最多%s敌·后跳保留%s\n断边不返还单体" % [_percent(a.get("coefficient")), _percent(b.get("coefficient")), _number(b.get("target_cap")), _percent(b.get("hop_decay"))]
		"L04": return "主击%s → %s\n布点邻敌%s → %s名\n不对邻敌造成即时伤害" % [_percent(a.get("coefficient")), _percent(b.get("coefficient")), _number(a.get("neighbor_cap")), _number(b.get("neighbor_cap"))]
		"L05": return "每次落雷%s·最多%s敌\n共%s次·半径%s米\n%s" % [_percent(b.get("coefficient")), _number(b.get("strike_target_cap")), _number(b.get("strike_times", []).size()), _number(b.get("radius")), "自然落雷后雷易伤＋%s" % _percent(b.get("natural_first_hit_vulnerability")) if float(b.get("natural_first_hit_vulnerability", 0)) > 0 else "各次云团独立，不取消旧波"]
		"L06": return "半径%s → %s米\n主脉冲%s\n%s" % [_number(a.get("radius")), _number(b.get("radius")), _percent(b.get("coefficient")), "%s秒后原地追加%s\n两段均刷新导电" % [_number(b.get("followup_delay")), _percent(b.get("followup_coefficient"))] if float(b.get("followup_coefficient", 0)) > 0 else "命中刷新导电"]
		"L07": return "主击%s·旧导电附伤%s\n%s" % [_percent(b.get("coefficient")), _percent(b.get("conductive_extra_coefficient")), "自然裁决对成熟导电\n可向最多%s名邻敌各放%s弧" % [_number(b.get("mature_arc_target_cap")), _percent(b.get("mature_arc_coefficient"))] if int(b.get("mature_arc_target_cap", 0)) > 0 else "附伤不暴击"]
		"L08": return _lightning_spell_effect(id, b)
		"L09": return "回盾%s·冷却%s秒\n%s米内最多%s敌布点\n只据实际回复触发" % [_number(b.get("shield_restore")), _number(b.get("cooldown")), _number(b.get("conductive_range")), _number(b.get("conductive_target_cap"))]
		"L10": return "雷伤%s → %s\n新导电延长%s秒\n双端导电连接再加%s米" % [_percent(a.get("school_damage_bonus")), _percent(b.get("school_damage_bonus")), _number(b.get("conductive_duration_add")), _number(b.get("both_conductive_range_add"))]
	return ""


static func ice_state_rule() -> String:
	var frost: Dictionary = load_catalog().get("ice_source", {}).get("mechanics", {}).get("frost", {})
	return "基础寒霜最多%s层，期限%s秒。满层形成%s秒冻结／冰裂窗口，普通目标基础冻结%s秒，硬冻解除后%s秒免控。窗口不刷新；自动碎冰会提前解除冻结。精英冻结较短，固定强敌只冰裂；碎冰与邻片不暴击。" % [_number(frost.get("max_stacks")), _number(frost.get("expiry")), _number(frost.get("ready_window")), _number(frost.get("base_freeze")), _number(frost.get("post_freeze_immunity"))]


static func _ice_spell_effect(id: String, value: Dictionary) -> String:
	match id:
		"I01":
			var text := "伤害：%s 攻击\n命中施加 %s 层寒霜" % [_percent(value.get("coefficient")), _number(value.get("chill_stacks"))]
			if value.has("chill_stacks_if_pre_frost_1_or_2"):
				text += "\n已有1—2层时改施 %s 层" % _number(value.get("chill_stacks_if_pre_frost_1_or_2"))
			return text
		"I02":
			return "首敌 %s，后续 %s\n长 %s 米，宽 %s 米\n最多 %s 敌，各施 %s 层寒霜" % [_percent(value.get("coefficient")), _percent(value.get("following_coefficient")), _number(value.get("length")), _number(value.get("width")), _number(value.get("target_cap")), _number(value.get("chill_stacks"))]
		"I03":
			var text := "%s秒后落击，伤害%s\n半径 %s 米；首击施霜" % [_number(value.get("impact_delay")), _percent(value.get("coefficient")), _number(value.get("radius"))]
			if float(value.get("followup_coefficient", 0)) > 0:
				text += "\n%s秒后冰屑：%s，不施霜" % [_number(value.get("followup_delay")), _percent(value.get("followup_coefficient"))]
			return text
		"I04":
			return "半径 %s 米，伤害 %s\n施加 %s 层寒霜\n普通敌减速%s，持续%s秒" % [_number(value.get("radius")), _percent(value.get("coefficient")), _number(value.get("chill_stacks")), _percent(value.get("slow_normal")), _number(value.get("slow_duration"))]
		"I05":
			return "半径 %s 米，持续 %s 秒\n每%s秒伤害：%s 攻击\n首跳延迟 %s 秒\n首次施霜%s层，后续%s层" % [_number(value.get("radius")), _number(value.get("duration")), _number(value.get("interval")), _percent(value.get("coefficient")), _number(value.get("first_tick")), _number(value.get("first_valid_chill_stacks")), _number(value.get("chill_stacks"))]
		"I06":
			var text := "长 %s 米，宽 %s 米\n共 %s 波，每波 %s 攻击\n第1、3次命中各施1层霜" % [_number(value.get("length")), _number(value.get("width")), _number(value.get("waves")), _percent(value.get("coefficient"))]
			if float(value.get("final_ready_coefficient", 0)) > float(value.get("coefficient", 0)):
				text += "\n末波对就绪目标：%s" % _percent(value.get("final_ready_coefficient"))
			return text
		"I07":
			var text := "基础伤害：%s 攻击\n碎冰：%s，不暴击" % [_percent(value.get("coefficient")), _percent(value.get("shatter_coefficient"))]
			if int(value.get("shard_target_cap", 0)) > 0:
				text += "\n邻片%s，最多%s名邻敌" % [_percent(value.get("shard_coefficient")), _number(value.get("shard_target_cap"))]
			return text + "\n自动碎冰，提前解除冻结"
		"I08":
			return "伤害：%s 攻击\n建立 %s 秒碎冰窗口\n普通敌冻结 %s 秒" % [_percent(value.get("coefficient")), _number(value.get("ready_window")), _number(value.get("freeze_base"))]
		"I09":
			var text := "防御+%s，持续%s秒\n周围%s米施加%s层寒霜" % [_number(value.get("defense_add")), _number(value.get("duration")), _number(value.get("radius")), _number(value.get("chill_stacks"))]
			if float(value.get("followup_delay", 0)) > 0:
				text += "\n%s秒后再次施霜%s层" % [_number(value.get("followup_delay")), _number(value.get("followup_chill_stacks"))]
			return text
		"I10":
			var text := "冰系伤害 +%s" % _percent(value.get("school_damage_bonus"))
			if float(value.get("ready_window_add", 0)) > 0:
				text += "\n碎冰窗口延长 %s 秒\n不延长硬冻结" % _number(value.get("ready_window_add"))
			return text
	return ""


static func _ice_spell_boundary(id: String, value: Dictionary) -> String:
	match id:
		"I01": return "霜弹碰撞半径%s米，速度%s米／秒。" % [_number(value.get("projectile_radius")), _number(value.get("speed"))]
		"I02": return "伤害均按攻击力计算；后续目标独立命中，不重复伤首敌。"
		"I03": return "首落施加%s层寒霜，后续冰屑只补直接伤害。" % _number(value.get("chill_stacks"))
		"I04": return "短减速：普通%s、精英%s、固定强敌%s，均持续%s秒。" % [_percent(value.get("slow_normal")), _percent(value.get("slow_elite")), _percent(value.get("slow_fixed_strong")), _number(value.get("slow_duration"))]
		"I05": return "完整最多%s跳；每敌伤害与施霜共享%s秒间隔，窗口中不继续累层或续窗。" % [_number(value.get("ticks")), _number(value.get("shared_chill_gate"))]
		"I06": return "首波延迟%s秒，此后每%s秒一波；同敌共享伤害／施霜间隔，后续命中不延长既有窗口。" % [_number(value.get("first_wave")), _number(value.get("wave_interval"))]
		"I07": return "邻片范围%s米、最多%s名其他活敌；主目标排除，逐边受掩体阻挡。没有旧窗口时只有基础伤害。" % [_number(value.get("shard_radius")), _number(value.get("shard_target_cap"))]
		"I08": return "释放后%s秒落击，单目标检测半径%s米。冻结不取消预警，解冻按剩余攻击时序恢复；已离体敌弹照常。" % [_number(value.get("impact_delay")), _number(value.get("radius"))]
		"I09": return "需%s米内有可见活敌；完成时重查。没有可施霜近敌时仍获得防御；满减伤上限不等于免疫。" % _number(value.get("combat_enemy_range"))
		"I10": return "冰伤与三冰共鸣同桶相加；窗口延长不提高寒霜层数。"
	return ""


static func _ice_upgrade_text(id: String, before: Dictionary, after: Dictionary) -> String:
	var lines: Array[String] = []
	match id:
		"I01":
			lines.append("伤害：%s → %s" % [_percent(before.get("coefficient")), _percent(after.get("coefficient"))])
			if before.get("projectile_radius") != after.get("projectile_radius"):
				lines.append("弹体半径：%s → %s米" % [_number(before.get("projectile_radius")), _number(after.get("projectile_radius"))])
			if after.has("chill_stacks_if_pre_frost_1_or_2"):
				lines.append("已有1—2层时，改施%s层霜" % _number(after.get("chill_stacks_if_pre_frost_1_or_2")))
		"I02":
			if before.get("coefficient") != after.get("coefficient"):
				lines.append("伤害：%s → %s" % [_percent(before.get("coefficient")), _percent(after.get("coefficient"))])
				lines.append("长度：%s → %s米" % [_number(before.get("length")), _number(after.get("length"))])
				lines.append("全宽：%s → %s米" % [_number(before.get("width")), _number(after.get("width"))])
				lines.append("目标上限：%s → %s" % [_number(before.get("target_cap")), _number(after.get("target_cap"))])
			else:
				lines.append("后续目标伤害：%s → %s" % [_percent(before.get("following_coefficient")), _percent(after.get("following_coefficient"))])
		"I03":
			if before.get("coefficient") != after.get("coefficient"):
				lines.append("伤害：%s → %s" % [_percent(before.get("coefficient")), _percent(after.get("coefficient"))])
				lines.append("半径：%s → %s米" % [_number(before.get("radius")), _number(after.get("radius"))])
			if float(after.get("followup_coefficient", 0)) > 0:
				lines.append("%s秒后追加%s冰屑\n冰屑不再施霜" % [_number(after.get("followup_delay")), _percent(after.get("followup_coefficient"))])
		"I04":
			if before.get("coefficient") != after.get("coefficient"):
				lines.append("伤害：%s → %s" % [_percent(before.get("coefficient")), _percent(after.get("coefficient"))])
				lines.append("半径：%s → %s米" % [_number(before.get("radius")), _number(after.get("radius"))])
			if before.get("chill_stacks") != after.get("chill_stacks"):
				lines.append("寒霜：%s → %s层" % [_number(before.get("chill_stacks")), _number(after.get("chill_stacks"))])
		"I05":
			if before.get("coefficient") != after.get("coefficient"):
				lines.append("每跳伤害：%s → %s" % [_percent(before.get("coefficient")), _percent(after.get("coefficient"))])
				lines.append("半径：%s → %s米" % [_number(before.get("radius")), _number(after.get("radius"))])
				lines.append("持续：%s → %s秒" % [_number(before.get("duration")), _number(after.get("duration"))])
			if before.get("first_valid_chill_stacks") != after.get("first_valid_chill_stacks"):
				lines.append("各敌首次施霜：%s → %s层" % [_number(before.get("first_valid_chill_stacks")), _number(after.get("first_valid_chill_stacks"))])
		"I06":
			if before.get("coefficient") != after.get("coefficient"):
				lines.append("每波伤害：%s → %s" % [_percent(before.get("coefficient")), _percent(after.get("coefficient"))])
				lines.append("条带全宽：%s → %s米" % [_number(before.get("width")), _number(after.get("width"))])
			lines.append("波数：%s → %s" % [_number(before.get("waves")), _number(after.get("waves"))])
			if float(after.get("final_ready_coefficient", 0)) > float(after.get("coefficient", 0)):
				lines.append("末波对就绪目标伤害%s" % _percent(after.get("final_ready_coefficient")))
		"I07":
			lines.append("基础伤害：%s → %s" % [_percent(before.get("coefficient")), _percent(after.get("coefficient"))])
			lines.append("碎冰伤害：%s → %s" % [_percent(before.get("shatter_coefficient")), _percent(after.get("shatter_coefficient"))])
			lines.append("邻片：%s · %s米／%s敌" % [_percent(after.get("shard_coefficient")), _number(after.get("shard_radius")), _number(after.get("shard_target_cap"))])
		"I08":
			lines.append("伤害：%s → %s" % [_percent(before.get("coefficient")), _percent(after.get("coefficient"))])
			lines.append("普通冻结：%s → %s秒" % [_number(before.get("freeze_base")), _number(after.get("freeze_base"))])
		"I09":
			if before.get("defense_add") != after.get("defense_add"):
				lines.append("防御：%s → %s" % [_number(before.get("defense_add")), _number(after.get("defense_add"))])
				lines.append("施霜半径：%s → %s米" % [_number(before.get("radius")), _number(after.get("radius"))])
			if before.get("duration") != after.get("duration"):
				lines.append("持续：%s → %s秒" % [_number(before.get("duration")), _number(after.get("duration"))])
				lines.append("%s秒后再施霜%s层" % [_number(after.get("followup_delay")), _number(after.get("followup_chill_stacks"))])
		"I10":
			lines.append("冰伤加成：%s → %s" % [_percent(before.get("school_damage_bonus")), _percent(after.get("school_damage_bonus"))])
			if float(after.get("ready_window_add", 0)) > 0:
				lines.append("碎冰窗口延长%s秒\n硬冻结时长不变" % _number(after.get("ready_window_add")))
	return "\n".join(lines)


static func _ice_artifact_card_effect(id: String, value: Dictionary) -> String:
	match id:
		"IB01": return "霜弹命中已有1—2层寒霜的敌人时，伤害系数 +%s 个百分点。\n不额外施霜。" % _number(float(value.get("coefficient_add", 0)) * 100)
		"IB02": return "冰锥全宽 +%s。\n最多命中目标 +%s。\n同一敌人仍只命中一次。" % [_increase(value.get("width_multiplier")), _number(value.get("target_cap_add"))]
		"IB03": return "寒星更快落下：延迟改为%s秒。\n首击与冰屑半径 +%s 米。\n落点仍不追踪。" % [_number(value.get("first_impact_delay")), _number(value.get("radius_add"))]
		"IB04": return "霜环半径 +%s 米。\n普通敌短减速提高至%s。\n精英与固定强敌效果降低。" % [_number(value.get("radius_add")), _percent(value.get("slow_normal"))]
		"IB05": return "极寒领域延长 %s 秒。\n伤害与施霜间隔不变。\n提前替换不补跳。" % _number(value.get("duration_add"))
		"IB06": return "冰晶风暴最后一波伤害 +%s。\n仅提高末波，不额外施霜。" % _increase(value.get("final_wave_multiplier"))
		"IB07": return "二／三级碎冰邻片范围 +%s米，伤害系数 +%s个百分点。\n一级改为提高主目标碎冰。" % [_number(value.get("shard_radius_add")), _number(float(value.get("shard_coefficient_add", 0)) * 100)]
		"IB08": return "冰封棺命中免控或不可冻结目标时，伤害系数 +%s 个百分点。\n不解除免控。" % _number(float(value.get("coefficient_add", 0)) * 100)
		"IB09": return "凝霜护体的施霜半径 +%s 米。\n不增加施霜层数或回盾。" % _number(value.get("radius_add"))
		"IB10": return "未满层寒霜期限延长至 %s 秒。\n不延长冻结、碎冰窗口或免控。" % _number(value.get("frost_expiry"))
		"IP01": return "自然施放霜弹、冰锥、寒星时，首个有效直击若命中已有1—2层寒霜且存活的敌人，额外施霜%s层。\n每次施法只检查一次。" % _number(value.get("extra_stacks"))
		"IP02": return "自然碎冰后，最多%s名实际受伤且存活的碎片邻敌各获得%s层寒霜。\n每次施法只扩散一轮。" % [_number(value.get("neighbor_cap")), _number(value.get("chill_stacks"))]
		"IP03": return "凝霜护体期间承伤并存活，使最近%s米内敌人获得%s层寒霜。\n共享间隔%s秒。" % [_number(value.get("range")), _number(value.get("chill_stacks")), _number(value.get("shared_cooldown"))]
		"IG01": return "自然领域／冰暴对各敌第二次合格施霜时，额外施霜%s层。\n每敌每次施法一次，不续窗口。" % _number(value.get("extra_stacks"))
		"IG02": return "自然碎冰伤害 +%s。\n成功消费后，存活主目标保留%s层寒霜。\n同敌间隔%s秒，不清免控。" % [_increase(value.get("shatter_multiplier")), _number(value.get("retained_stacks")), _number(value.get("per_actor_cooldown"))]
		"IG03": return "自然冰封棺对存活目标建立新窗口时，回复%s盾。\n共享间隔%s秒；已有窗口不回盾。" % [_number(value.get("restore_request")), _number(value.get("shared_cooldown"))]
	return ""


static func _ice_artifact_effect(id: String, value: Dictionary) -> String:
	var text := _ice_artifact_card_effect(id, value).replace("\n", " ")
	match id:
		"IB01": return text + " 只改霜弹本击，不扩到已就绪目标或其他冰伤。"
		"IB02": return text + " 不增加长度，空余名额不返还主目标。"
		"IB03": return text + " 后续冰屑仍在首击后按原延迟出现。"
		"IB04": return text + " 短减速精英%s、固定强敌%s，持续%s秒；同类减速取最强。" % [_percent(value.get("slow_elite")), _percent(value.get("slow_fixed_strong")), _number(value.get("duration"))]
		"IB05": return text + " 完整跳数为%s／%s／%s，不缩短共享施霜间隔。" % [_number(value.get("ticks", [0,0,0])[0]), _number(value.get("ticks", [0,0,0])[1]), _number(value.get("ticks", [0,0,0])[2])]
		"IB06": return text + " 三级末波对旧就绪目标的强化也只结算一次，不消费窗口。"
		"IB07": return text + " 一级主目标碎冰系数+%s个百分点；不增加邻片目标上限，不提高基础冰击。" % _number(float(value.get("level1_shatter_add", 0)) * 100)
		"IB08": return text + " 命中前判资格；不续窗，不向已死目标补伤。"
		"IB09": return text + " 不增加起吟的活敌检索范围，也不产生伤害命中链。"
		"IB10": return text + " 只影响新施加或刷新，不追改旧状态。"
		"IP01": return text + " 首敌无层或已被主伤／蓄能击杀时也用掉检查，不转给后排；基础施霜后额外加层，不能续已有窗口。追加与派生不触发。"
		"IP02": return text + " 仅自然碎冰赢得旧窗口消费权才触发；排除主目标，邻敌不足不补主伤，碎片施霜不再递归。"
		"IP03": return text + " 必须有实际盾血损失；无敌挡伤、零损失、致死或离战不触发。该反应不造成伤害或算施法。"
		"IG01": return text + " 必须在施霜前尚无窗口，并服从区域共享间隔；追加区域不享此奖励。"
		"IG02": return text + " 只强化主目标碎冰，不强化基础冰击或邻片。系数平加后再乘本倍率；保留层数不重置或延长现有免控，只有实际提前解除硬冻结才从解除时起计免控。追加碎冰不享此奖励。"
		"IG03": return text + " 回盾按回复增幅后再取实际缺盾量，不溢出、不加盾上限。旧窗口只受伤害，追加、碎冰或死亡不触发；每次自然施法至多一次。"
	return text

static func _resolve_refs(value: Variant, base: Dictionary) -> Variant:
	if value is Dictionary:
		if value.has("base_ref"):
			var resolved: Variant = base
			for key in str(value["base_ref"]).split("."):
				if not resolved is Dictionary or not resolved.has(key):
					return null
				resolved = resolved[key]
			return resolved
		var result: Dictionary = {}
		for key in value:
			result[key] = _resolve_refs(value[key], base)
		return result
	if value is Array:
		var result: Array = []
		for entry in value:
			result.append(_resolve_refs(entry, base))
		return result
	return value


static func _number(value: Variant) -> String:
	if value == null:
		return "—"
	return String.num(float(value), 3).trim_suffix("0").trim_suffix(".") if not is_equal_approx(float(value), roundf(float(value))) else str(int(roundf(float(value))))


static func _percent(value: Variant) -> String:
	return "—" if value == null else _number(float(value) * 100.0) + "%"


static func _increase(multiplier: Variant) -> String:
	return "—" if multiplier == null else _percent(float(multiplier) - 1.0)


static func catalyst_description(school:String, count:int, sampling:Dictionary)->String:
	var text: String = "%s · %d 术\n起始法术从本系三张中选一。\n法术书出现本系的倾向随等级提高；同屏不重复，也不保证出现。" % [school_name(school),count]
	if float(sampling.get("owned_upgrade_weight",1.0)) > 1.0:
		text += "\n已学可升级法术权重 ×%s。" % _number(sampling.owned_upgrade_weight)
	text += "\n需要均衡混学时，可以随时卸下。"
	return text


static func catalyst_reference_text(sampling:Dictionary, level:int)->String:
	var values:Array=sampling.get("catalyst_affinity_by_level",[])
	if level<1 or level>values.size(): return "未读取触媒倾向参数。"
	var priority:float=float(values[level-1])
	var first:float=1.0/6.0+(1.0-1.0/6.0)*priority
	return "本系优先 %s：抽取每一张时先加入本系分量，其余按合法池分配。\n本系 10 术、跨系 50 术都可抽时，第一张为本系的概率约 %s。\n满级、前置与已学权重会改变结果；这是倾向，不是保底。" % [_percent(priority),_percent(first)]
