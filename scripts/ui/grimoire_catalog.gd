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
}
const STARTER_SPELLS := ["F01", "F03", "F08"]
const RARITY_NAMES := {"blue": "蓝色", "purple": "紫色", "gold": "金色"}
const RARITY_COLORS := {"blue": "79b7ee", "purple": "b49ae8", "gold": "e5bd75"}
const GENERIC_SOURCE := "res://data/generic_artifacts_v1.json"
const FIRE_RUNTIME_SOURCE := "res://data/route_spell_runtime.json"
const ICE_SPELL_SOURCE := "res://data/ice_spells_v1.json"
const ICE_ARTIFACT_SOURCE := "res://data/ice_artifacts_v1.json"
const SpellGrowth = preload("res://scripts/core/route_spell_growth.gd")
const BOSS_SOURCE := "res://data/route_boss_runtime.json"
static var _catalog: Dictionary = {}


static func load_catalog(force_reload: bool = false) -> Dictionary:
	if _catalog.is_empty() or force_reload:
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
		for entry in [["ice_source", ICE_SPELL_SOURCE, "spells"], ["ice_artifact_source", ICE_ARTIFACT_SOURCE, "items"]]:
			var extra_file := FileAccess.open(str(entry[1]), FileAccess.READ)
			var extra_parser := JSON.new()
			if extra_file == null or extra_parser.parse(extra_file.get_as_text()) != OK or not extra_parser.data is Dictionary:
				result["errors"].append("无法读取冰系目录：" + str(entry[1]))
				result[str(entry[0])] = {}
				continue
			result[str(entry[0])] = extra_parser.data
			var merged: Dictionary = result.get("base", {}).get("spells", {}) if str(entry[2]) == "spells" else result.get("artifact_source", {}).get("items", {})
			for id in extra_parser.data.get(str(entry[2]), {}):
				if merged.has(id):
					result["errors"].append("冰系目录ID重复：" + str(id))
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
	var result: Array[Dictionary] = []
	var source: Dictionary = load_catalog().get("base", {}).get("spells", {})
	for id in source:
		if bool(source[id].get("active", true)):
			result.append(describe_spell(str(id), 1))
	return result


static func artifacts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source: Dictionary = load_catalog().get("artifact_source", {}).get("items", {})
	for scope in ["generic", "fire", "ice"]:
		for id in source:
			if str(source[id].get("scope", "")) == scope and bool(source[id].get("active", true)):
				result.append(describe_artifact(str(id)))
	return result


static func spell_name(id: String) -> String:
	var source: Dictionary = load_catalog().get("base", {}).get("spells", {})
	return str(source.get(id, {}).get("name", id))


static func describe_spell(id: String, level: int = 1, route_growth: bool = true) -> Dictionary:
	var catalog := load_catalog()
	var source: Dictionary = catalog.get("base", {}).get("spells", {}) if route_growth else catalog.get("legacy_spell_source", {})
	if not source.has(id):
		return {}
	var spell: Dictionary = source[id]
	var levels: Array = spell.get("levels", [])
	if levels.is_empty():
		return {}
	var current_level := clampi(level, 1, levels.size())
	var values: Dictionary = spell.duplicate(true)
	values.merge(levels[current_level - 1], true)
	values.erase("levels")
	var level_details: Array[String] = []
	for index in levels.size():
		var level_values: Dictionary = spell.duplicate(true)
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
		"upgrade_text": spell_upgrade_text(id, current_level, route_growth),
		"boundary": str(SPELL_BOUNDARIES.get(id, "")) + ("\n" + _ice_spell_boundary(id, values) + "\n" + ice_state_rule() if str(spell.get("school", "fire")) == "ice" else ("\n" + burning_rule() if str(spell.get("school", "fire")) == "fire" and id not in ["F02", "F10"] else "")), "stats": stats,
		"level": current_level, "max_level": levels.size(), "level_details": level_details,
		"starter": id in starter_ids(str(spell.get("school", "fire"))), "element": {"ice":"冰", "fire":"火", "spirit":"灵契（历史首房）"}.get(str(spell.get("school", "fire")), ""), "school": spell.get("school", "fire"), "active": spell.get("active", true), "color": "8bd9ed" if spell.get("school") == "ice" else "eea175",
		"values": values, "source_version": spell.get("growth_version", catalog.get("ice_source" if spell.get("school") == "ice" else "base", {}).get("version", "")),
	}


static func describe_artifact(id: String) -> Dictionary:
	var catalog := load_catalog()
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
	return content.get("ice_source", {}).get("mechanics", {}).get("initial_ids", []) if school == "ice" else content.get("spell_runtime", {}).get("fire", {}).get("initial_ids", STARTER_SPELLS)


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
