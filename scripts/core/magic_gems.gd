extends RefCounted
## Instance generation, validation and read-only descriptions. No account writes.
const PATH = "res://data/magic_gems_v1.json"
var rules: Dictionary = {}
var burn_interval: float

func _init():
	rules = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	burn_interval = float(JSON.parse_string(FileAccess.get_file_as_string("res://data/route_spell_runtime.json")).fire.burning.interval)

func fresh() -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	return {"inventory": [], "slots": ["", "", "", ""], "serial": 0,
		"draws": 0, "gold_misses": 0, "rare_misses": 0, "first_gold": true,
		"rng_state": str(rng.state), "essence": 0, "salvaged": 0, "work_serial": 0, "pending_reforge": {}}

func core_rule(id: String) -> Dictionary:
	return rules.cores.get(id, {}).duplicate(true)

func core_description(id: String) -> String:
	var s: Dictionary = core_rule(id)
	if s.is_empty(): return ""
	match id:
		"reactor": return "法术命中同时燃烧、冻结或脆化的敌人时，消耗两种状态引发反应：造成%s倍攻击＋剩余燃烧伤害×%s，附近至多%d名敌人受到%s%%伤害。共用冷却%s秒。" % [number(s.base_coefficient), number(s.remaining_burn_scale), s.neighbor_cap, number(s.neighbor_scale*100), number(s.cooldown)]
		"sacrifice": return "战斗中每秒消耗最大生命的%s%%，自身消耗最低到%s%%生命。每损失1%%生命，造成的全部伤害独立提高%s%%。消耗不触发受伤效果，敌人仍可造成致命伤害。" % [number(s.drain_max_health_per_second*100), number(s.drain_floor_fraction*100), number(s.damage_per_missing_fraction)]
		"aegis": return "将%s%%最大生命转化为护盾，每1点生命换取%s点护盾。战斗中的生命回复改为%s%%护盾回复，不产生溢出收益。清房和商店的生命补给照常生效。" % [number(s.life_conversion*100), number(s.shield_per_life), number(s.combat_health_restore_conversion*100)]
		"inferno": return "燃烧可叠至%d层，每层每%s秒造成%s倍攻击。重复点燃增加1层，增层间隔%s秒；停止点燃%s秒后，每%s秒掉1层，燃烧结束时清空。引爆按实际剩余燃料结算。" % [s.cap, number(burn_interval), number(s.tick_coefficient_per_layer), number(s.gain_interval), number(s.decay_delay), number(s.decay_interval)]
		"coffin": return "冻结或脆化期间，敌人承受的法术本体伤害有%s%%暂存，上限为%s倍攻击。状态结束、被碎冰消耗或敌人死亡时，按%s倍暂存值爆发，命中附近至多%d名敌人。" % [number(s.defer_fraction*100), number(s.stored_attack_cap), number(s.release_multiplier), s.target_cap]
		"fracture": return "法术本体暴击时，基础伤害立即生效，暴击额外伤害×%s变为晶刺，%s秒后命中。随后至多弹射%d次，每次为上次的%s%%；弹射不重复命中同一目标。" % [number(s.extra_damage_multiplier), number(s.first_delay), s.bounce_count, number(s.bounce_multiplier*100)]
		"echo": return "冷却缩减不再缩短法术冷却。自然施法的基础伤害区域在%s秒后回响，造成%s%%本体伤害；每1%%冷却缩减再增加%s%%。回响不暴击、不施加状态或触发宝物，可被走位躲开。" % [number(s.delay), number(s.base_multiplier*100), number(s.cdr_multiplier)]
		"stride": return "移动时暂停伤害法术吟唱；每移动1米积蓄力量，%s米满蓄。停下后首个完成的伤害法术消耗蓄势，本体伤害最多＋%s%%、范围最多＋%s%%。防护法术照常施放。" % [number(s.maximum_distance), number(s.maximum_body_damage_bonus*100), number(s.maximum_size_bonus*100)]
	return ""

func migrate_v3(source: Dictionary) -> Dictionary:
	if not source.get("inventory") is Array: return {}
	var result: Dictionary = source.duplicate(true)
	result["essence"] = 0
	result["salvaged"] = 0
	result["work_serial"] = 0
	result["pending_reforge"] = {}
	for gem in result.get("inventory", []):
		if not gem is Dictionary or not gem.get("affixes") is Array: return {}
		gem["locked"] = false
		if gem.has("legacy_id"): continue
		if str(gem.get("rarity", "")) == "gold":
			if not rules.core_migration_map.has(str(gem.get("core", ""))): return {}
			gem.core = rules.core_migration_map[gem.core]
		for line in gem.get("affixes", []):
			if not line is Dictionary: return {}
			if not rules.affixes.has(str(line.get("stat", ""))): continue
			if line.get("value") != rules.affixes[line.stat].get(str(gem.get("rarity", ""))): return {}
			var tier: int = -1
			for index in 3:
				if line.get("value") == rules.affixes[line.stat].tiers[index]: tier = index + 1
			line["tier"] = tier
	return result

func weighted_tier(rng: RandomNumberGenerator) -> int:
	return rng.rand_weighted(PackedFloat32Array(rules.tier_weights)) + 1

func roll_affix(gem: Dictionary, index: int, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array = rules.affixes.keys()
	for other in gem.affixes.size():
		if other != index: pool.erase(str(gem.affixes[other].stat))
	# Reject only the complete old outcome. The old type can still gain tiers.
	var outcomes: Array = []
	var weights: PackedFloat32Array = []
	for stat in pool:
		for tier in 3:
			if stat == gem.affixes[index].stat and tier + 1 == int(gem.affixes[index].tier): continue
			outcomes.append({"stat": stat, "tier": tier + 1, "value": rules.affixes[stat].tiers[tier]})
			weights.append(float(rules.tier_weights[tier]))
	return outcomes[rng.rand_weighted(weights)].duplicate(true)

func roll_core(current: String, rng: RandomNumberGenerator) -> String:
	var pool: Array = rules.cores.keys()
	pool.erase(current)
	return str(pool[rng.randi_range(0, pool.size() - 1)])

func gold_probability(state: Dictionary) -> float:
	var next: int = int(state.gold_misses) + 1
	if (bool(state.first_gold) and next >= int(rules.pity.first_gold)) or next >= int(rules.pity.gold_hard):
		return 1.0
	return float(rules.base_weights.gold) / 100.0 + maxf(0.0, next - int(rules.pity.gold_soft_start) + 1) * float(rules.pity.gold_soft_increment)

func sample(state: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var rarity: String = "gold"
	var probability: float = gold_probability(state)
	if probability < 1.0 and rng.randf() >= probability:
		if int(state.rare_misses) >= int(rules.pity.purple_or_better) - 1:
			rarity = "purple"
		else:
			var weights: Dictionary = rules.base_weights
			var roll: float = rng.randf() * (float(weights.green) + float(weights.blue) + float(weights.purple))
			rarity = "green" if roll < float(weights.green) else ("blue" if roll < float(weights.green) + float(weights.blue) else "purple")
	var pool: Array = rules.affixes.keys()
	var lines: Array = []
	for index in int(rules.affix_counts[rarity]):
		var pick: int = rng.randi_range(0, pool.size() - 1)
		var key: String = str(pool.pop_at(pick))
		var tier: int = weighted_tier(rng)
		lines.append({"stat": key, "tier": tier, "value": rules.affixes[key].tiers[tier - 1]})
	var core: String = ""
	if rarity == "gold":
		var cores: Array = rules.cores.keys()
		core = str(cores[rng.randi_range(0, cores.size() - 1)])
	state.serial = int(state.serial) + 1
	var gem: Dictionary = {"id": "gem-%d" % int(state.serial), "serial": int(state.serial), "rarity": rarity, "affixes": lines, "core": core, "locked": false}
	state.inventory.append(gem)
	state.draws = int(state.draws) + 1
	state.gold_misses = 0 if rarity == "gold" else int(state.gold_misses) + 1
	state.rare_misses = 0 if rarity in ["purple", "gold"] else int(state.rare_misses) + 1
	if rarity == "gold": state.first_gold = false
	return gem.duplicate(true)

func totals(state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in rules.affixes: result[key] = 0.0
	for gem in state.inventory:
		if str(gem.id) not in state.slots: continue
		for line in gem.affixes: result[str(line.stat)] += float(line.value)
	return result

func core_id(state: Dictionary) -> String:
	for gem in state.inventory:
		if gem.id == state.slots[0] and gem.rarity == "gold": return str(gem.core)
	return ""

func find(state: Dictionary, id: String) -> Dictionary:
	for gem in state.inventory:
		if str(gem.id) == id: return gem.duplicate(true)
	return {}

func title(gem: Dictionary) -> String:
	if gem.is_empty(): return "空槽"
	if gem.has("legacy_id"): return str(gem.legacy_name) + " · 传承"
	return str(core_rule(str(gem.core)).name) if gem.rarity == "gold" else str(rules.rarity_names[gem.rarity]) + "魔法宝石"

func affix_text(gem: Dictionary) -> String:
	var lines: PackedStringArray = []
	for line in gem.get("affixes", []):
		var rule: Dictionary = rules.affixes[line.stat]
		var amount: float = float(line.value)
		var value: String = number(amount)
		if str(rule.unit) in ["probability_add", "fraction_add"]: value = number(amount * 100.0) + "%"
		elif str(rule.unit) == "multiplier_add": value += "倍"
		lines.append(str(rule.label) + " +" + value + ("  [%s]" % ["I", "II", "III"][int(line.tier) - 1] if line.has("tier") else ""))
	return "\n".join(lines)

func number(value: float) -> String:
	return str(int(roundf(value))) if is_equal_approx(value, roundf(value)) else String.num(value, 2)

func validate(state: Variant, legacy_catalog: Dictionary, levels: Dictionary) -> String:
	if not state is Dictionary: return "宝石记录无效。"
	for key in ["serial", "draws", "gold_misses", "rare_misses", "essence", "salvaged", "work_serial"]:
		if not integer(state.get(key)): return "宝石计数无效。"
	if not state.get("first_gold") is bool or not state.get("rng_state") is String or not str(state.rng_state).is_valid_int(): return "宝石随机记录无效。"
	if str(int(state.rng_state)) != str(state.rng_state): return "宝石随机状态超出范围。"
	if int(state.gold_misses) >= int(rules.pity.gold_hard) or int(state.rare_misses) >= int(rules.pity.purple_or_better): return "宝石保底计数超出范围。"
	if int(state.gold_misses) > int(state.draws) or int(state.rare_misses) > int(state.draws) or int(state.rare_misses) > int(state.gold_misses): return "宝石保底记录不一致。"
	if bool(state.first_gold) and (int(state.gold_misses) != int(state.draws) or int(state.draws) >= int(rules.pity.first_gold)): return "首金记录不一致。"
	if not state.get("inventory") is Array or not state.get("slots") is Array or state.slots.size() != int(rules.slots): return "宝石背包或槽位无效。"
	var seen: Array = []
	var legacy_seen: Array = []
	var generated: int = 0
	var gold_count: int = 0
	for gem in state.inventory:
		if not gem is Dictionary or not integer(gem.get("serial"), 1) or int(gem.serial) > int(state.serial) or gem.get("id") != "gem-%d" % int(gem.serial) or gem.id in seen: return "宝石实例标识无效。"
		seen.append(gem.id)
		if not gem.get("affixes") is Array or not gem.get("core") is String: return "宝石词条无效。"
		if not gem.get("locked") is bool: return "宝石锁定标记无效。"
		if gem.has("legacy_id"):
			var old: String = str(gem.legacy_id)
			if old in legacy_seen or not legacy_catalog.has(old) or int(levels.get(old, 0)) <= 0: return "传承宝石引用无效。"
			legacy_seen.append(old)
			var source: Dictionary = legacy_catalog[old]
			if gem.get("rarity") != "legacy" or not str(gem.core).is_empty() or gem.get("legacy_name") != source.name or gem.affixes.size() != 1: return "传承宝石定义无效。"
			if gem.affixes[0] != {"stat": source.stat, "value": source.flat_by_level[int(levels[old]) - 1]}: return "传承属性不匹配。"
			continue
		var rarity: String = str(gem.get("rarity", ""))
		generated += 1
		if rarity == "gold": gold_count += 1
		if not rules.affix_counts.has(rarity) or gem.affixes.size() != int(rules.affix_counts[rarity]): return "宝石品质不匹配。"
		if (rarity == "gold" and core_rule(str(gem.core)).is_empty()) or (rarity != "gold" and not str(gem.core).is_empty()): return "宝石核心无效。"
		var used: Array = []
		for line in gem.affixes:
			if not line is Dictionary or not rules.affixes.has(str(line.get("stat", ""))) or line.stat in used: return "重复或未知词条。"
			used.append(line.stat)
			if not integer(line.get("tier"), 1) or int(line.tier) > 3 or line.get("value") != rules.affixes[line.stat].tiers[int(line.tier) - 1]: return "词条数值或档位不匹配。"
	var equipped: Array = []
	if int(state.serial) != seen.size() + int(state.salvaged) or int(state.draws) != generated + int(state.salvaged) or (bool(state.first_gold) and gold_count > 0) or (not bool(state.first_gold) and gold_count == 0 and int(state.salvaged) == 0): return "宝石抽取与实例记录不一致。"
	for id in state.slots:
		if not id is String: return "宝石槽引用无效。"
		if id.is_empty(): continue
		if id not in seen or id in equipped: return "宝石重复装备或未持有。"
		equipped.append(id)
	for old in legacy_catalog:
		if int(levels.get(old, 0)) > 0 and old not in legacy_seen: return "传承宝石缺失。"
	if not state.get("pending_reforge") is Dictionary: return "改良候选记录无效。"
	var pending: Dictionary = state.pending_reforge
	if not pending.is_empty():
		var gem: Dictionary = find(state, str(pending.get("gem_id", "")))
		if gem.is_empty() or gem.has("legacy_id") or not integer(pending.get("token"), 1) or int(pending.token) != int(state.work_serial): return "改良候选引用无效。"
		if pending.get("mode") == "core":
			if pending.get("index") != -1 or gem.rarity != "gold" or not rules.cores.has(str(pending.get("candidate", ""))) or pending.candidate == gem.core or pending.get("old") != gem.core or pending.get("cost") != rules.workshop.core_cost: return "核心改良候选无效。"
		elif pending.get("mode") == "affix":
			if not integer(pending.get("index")) or int(pending.index) >= gem.affixes.size(): return "词条改良位置无效。"
			if pending.get("old") != gem.affixes[int(pending.index)] or pending.get("cost") != rules.workshop.affix_costs[gem.rarity]: return "词条改良来源无效。"
			var line: Variant = pending.get("candidate")
			if not line is Dictionary or not rules.affixes.has(str(line.get("stat", ""))) or not integer(line.get("tier"), 1) or int(line.tier) > 3: return "词条改良候选无效。"
			if line.get("value") != rules.affixes[line.stat].tiers[int(line.tier) - 1] or line == pending.old: return "词条改良档位无效。"
			for index in gem.affixes.size():
				if index != int(pending.index) and gem.affixes[index].stat == line.stat: return "词条改良候选重复。"
		else: return "改良类型无效。"
	return ""

func integer(value: Variant, minimum: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= 9007199254740991 and float(value) == floor(float(value))
