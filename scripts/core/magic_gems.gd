extends RefCounted
## Runtime gem defaults live in data. This library never writes account files.
const PATH = "res://data/magic_gems_v1.json"
var rules: Dictionary = {}
var burn_interval: float

func _init():
	rules = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	burn_interval = float(JSON.parse_string(FileAccess.get_file_as_string("res://data/route_spell_runtime.json")).fire.burning.interval)

func fresh() -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	return {"schema_version": 3, "inventory": [], "slots": ["", "", "", ""], "serial": 0,
		"draws": 0, "gold_misses": 0, "rare_misses": 0, "first_gold": false,
		"rng_state": str(rng.state), "essence": 0, "salvaged": 0, "work_serial": 0, "pending_reforge": {},
		"unlocked_cores": [], "core_claimed": false, "core_choice_credits": 0, "starter_attributes_claimed": 0,
		"cumulative_cleared": 0, "milestone_claimed": [], "migration": {}}

func is_modern(state: Dictionary) -> bool:
	return state.get("schema_version") == 3

func core_rule(id: String) -> Dictionary:
	return rules.cores.get(id, {}).duplicate(true)

func core_description(id: String) -> String:
	var spec: Dictionary = core_rule(id)
	if spec.is_empty(): return "旧核心已退场；选择待定结果后会保留属性并转换为新核心权益。"
	return _formatted_description(spec)

func legacy_core_description(id: String) -> String:
	var spec: Dictionary = rules.legacy_cores.get(id,{})
	return _formatted_description(spec) if not spec.is_empty() else "未知旧核心。"

func _formatted_description(spec: Dictionary) -> String:
	var values: Dictionary = {}
	for key in spec:
		if spec[key] is int or spec[key] is float:
			values[key] = number(float(spec[key]))
			values[str(key)+"_pct"] = number(float(spec[key])*100.0)
	values["burn_interval"] = number(burn_interval)
	return str(spec.get("description", "")).format(values)

func weighted_tier(rng: RandomNumberGenerator) -> int:
	return rng.rand_weighted(PackedFloat32Array(rules.tier_weights)) + 1

func line(stat: String, tier: int, main: bool) -> Dictionary:
	return {"stat": stat, "tier": tier, "value": rules.affixes[stat].main_tiers[tier-1] if main else rules.affixes[stat].tiers[tier-1], "role": "main" if main else "side"}

func create(state: Dictionary, rarity: String, main_stat: String, rng: RandomNumberGenerator, random_tiers: bool = false, origin: String = "craft") -> Dictionary:
	var pool: Array = rules.affixes.keys()
	pool.erase(main_stat)
	var lines: Array = [line(main_stat, weighted_tier(rng) if random_tiers else 1, true)]
	for index in int(rules.affix_counts[rarity])-1:
		var key: String = str(pool.pop_at(rng.randi_range(0,pool.size()-1)))
		lines.append(line(key, weighted_tier(rng) if random_tiers else 1, false))
	state.serial = int(state.serial) + 1
	var gem: Dictionary = {"id": "gem-%d" % int(state.serial), "serial": int(state.serial), "rarity": rarity, "affixes": lines, "core": "", "locked": false, "origin": origin}
	state.inventory.append(gem)
	return gem.duplicate(true)

func gold_probability(_state: Dictionary) -> float:
	return 0.0

func sample(state: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var rarity: String = "purple"
	if int(state.rare_misses) < int(rules.pity.purple_or_better)-1:
		var pick: int = rng.rand_weighted(PackedFloat32Array([rules.base_weights.green,rules.base_weights.blue,rules.base_weights.purple]))
		rarity = ["green","blue","purple"][pick]
	var keys: Array = rules.affixes.keys()
	var gem: Dictionary = create(state,rarity,str(keys[rng.randi_range(0,keys.size()-1)]),rng,true,"draw")
	state.draws = int(state.draws)+1
	state.rare_misses = 0 if rarity == "purple" else int(state.rare_misses)+1
	return gem

func roll_affix(gem: Dictionary, index: int, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array = rules.affixes.keys()
	for existing in gem.affixes: pool.erase(str(existing.stat))
	return line(str(pool[rng.randi_range(0,pool.size()-1)]),int(gem.affixes[index].tier),false)

func roll_core(current: String, rng: RandomNumberGenerator) -> String:
	var pool: Array = rules.cores.keys()
	pool.erase(current)
	return str(pool[rng.randi_range(0,pool.size()-1)])

func totals(state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in rules.affixes: result[key] = 0.0
	for gem in state.get("inventory", []):
		if str(gem.id) not in state.slots.slice(1): continue
		for affix in gem.affixes: result[str(affix.stat)] += float(affix.value)
	return result

func core_id(state: Dictionary) -> String:
	if not is_modern(state): return ""
	var ref: String = str(state.slots[0])
	return ref.trim_prefix("core:") if ref.begins_with("core:") and ref.trim_prefix("core:") in state.unlocked_cores else ""

func find(state: Dictionary, id: String) -> Dictionary:
	if id.begins_with("core:") and id.trim_prefix("core:") in state.get("unlocked_cores", []):
		return {"id":id,"serial":0,"rarity":"gold","core":id.trim_prefix("core:"),"affixes":[],"locked":true}
	for gem in state.get("inventory", []):
		if str(gem.id) == id: return gem.duplicate(true)
	return {}

func title(gem: Dictionary) -> String:
	if gem.is_empty(): return "空槽"
	if gem.has("legacy_id"): return str(gem.legacy_name) + " · 传承"
	if str(gem.get("rarity","")) == "gold": return str(core_rule(str(gem.core)).get("name", "旧核心"))
	if str(gem.get("rarity","")) == "transition": return "过渡属性石 · " + str(rules.rarity_names.get(str(gem.get("transition_rarity","purple")),"旧"))
	var main: String = str(rules.affixes[gem.affixes[0].stat].label) if not gem.affixes.is_empty() else ""
	return str(rules.rarity_names.get(gem.rarity,gem.rarity)) + main + "宝石"

func affix_text(gem: Dictionary) -> String:
	var lines: PackedStringArray = []
	for affix in gem.get("affixes", []):
		var rule: Dictionary = rules.affixes[affix.stat]
		var amount: float = float(affix.value)
		var value: String = number(amount)
		if str(rule.unit) in ["probability_add", "fraction_add"]: value = number(amount*100.0) + "%"
		elif str(rule.unit) == "multiplier_add": value += "倍"
		var role: String = "主 · " if affix.get("role") == "main" else ("副 · " if affix.get("role") == "side" else "")
		lines.append(role + str(rule.label) + " +" + value + ("  [%s]" % ["I","II","III"][int(affix.tier)-1] if affix.has("tier") else ""))
	return "\n".join(lines)

func number(value: float) -> String:
	return str(int(roundf(value))) if is_equal_approx(value,roundf(value)) else String.num(value,2)

func salvage_yield(gem: Dictionary) -> int:
	if gem.has("legacy_id") or str(gem.get("rarity","")) == "gold": return 0
	var rarity: String = str(gem.get("transition_rarity", "purple")) if gem.get("rarity") == "transition" else str(gem.get("rarity",""))
	if rarity == "gold": return int(rules.migration.transition_gold_salvage)
	return int(rules.workshop.salvage_yields.get(rarity,0))

func salvage_value(gem: Dictionary) -> int:
	return salvage_yield(gem)

func converted(gem: Dictionary, main_stat: String) -> Dictionary:
	if gem.get("rarity") != "transition" or gem.has("legacy_id"): return {}
	var chosen: int = -1
	for index in gem.affixes.size():
		if gem.affixes[index].stat == main_stat: chosen = index
	if chosen < 0: return {}
	var result: Dictionary = gem.duplicate(true)
	var original: Array = gem.affixes.duplicate(true)
	var main: Dictionary = original.pop_at(chosen)
	result.affixes = [line(str(main.stat),int(main.tier),true)]
	for side in original: result.affixes.append(line(str(side.stat),int(side.tier),false))
	result.rarity = "purple" if gem.transition_rarity == "gold" else str(gem.transition_rarity)
	result["converted_from_transition"] = true
	return result

func migrate_legacy(source: Dictionary) -> Dictionary:
	if is_modern(source): return source.duplicate(true)
	if not source.pending_reforge.is_empty(): return source.duplicate(true)
	var result: Dictionary = source.duplicate(true)
	result["schema_version"] = 3
	result["unlocked_cores"] = []
	result["core_claimed"] = false
	result["core_choice_credits"] = 0
	result["starter_attributes_claimed"] = 0
	result["cumulative_cleared"] = 0
	result["milestone_claimed"] = []
	var old_core_slot: String = str(source.slots[0])
	result.slots[0] = ""
	var duplicate_essence: int = 0
	var old_seen: Array = []
	for gem in result.inventory:
		if gem.has("legacy_id"): continue
		var rarity: String = str(gem.rarity)
		if rarity == "gold":
			var old_core: String = str(gem.core)
			if old_core in old_seen: duplicate_essence += int(rules.migration.duplicate_core_essence)
			else:
				old_seen.append(old_core)
				if rules.cores.has(old_core): result.unlocked_cores.append(old_core)
				else: result.core_choice_credits += 1
			if str(gem.id) == old_core_slot and rules.cores.has(old_core): result.slots[0] = "core:"+old_core
			gem["transition_core"] = old_core
		gem["transition_rarity"] = rarity
		gem["rarity"] = "transition"
		gem["core"] = ""
		gem["origin"] = "migration"
	# Preserve the formerly equipped attribute asset without ever deleting a fourth stone.
	if not old_core_slot.is_empty() and old_core_slot not in result.slots:
		for index in range(1,4):
			if str(result.slots[index]).is_empty(): result.slots[index] = old_core_slot; break
	var goal: int = int(rules.legacy_pity.first_gold if bool(source.first_gold) else rules.legacy_pity.gold_hard)
	var pity_credit: int = int(floor(float(rules.migration.core_pity_dust_budget)*float(source.gold_misses)/float(goal)))
	result.essence = int(result.essence)+duplicate_essence
	result["migration"] = {"version":rules.migration.version,"old_gold_misses":int(source.gold_misses),"old_first_gold":bool(source.first_gold),"pity_dust_credit":pity_credit,"duplicate_core_essence":duplicate_essence,"original_slots":source.slots.duplicate(),"old_core_types":old_seen}
	result.gold_misses = 0
	result.first_gold = false
	result.rare_misses = mini(int(rules.pity.purple_or_better)-1,int(source.rare_misses))
	return result

func validate(state: Variant, legacy_catalog: Dictionary, levels: Dictionary) -> String:
	if not state is Dictionary: return "宝石记录无效。"
	if not is_modern(state): return validate_old(state,legacy_catalog,levels)
	for key in ["serial","draws","gold_misses","rare_misses","essence","salvaged","work_serial","core_choice_credits","starter_attributes_claimed","cumulative_cleared"]:
		if not integer(state.get(key)): return "宝石计数无效："+key
	if not state.get("first_gold") is bool or not state.get("core_claimed") is bool or int(state.starter_attributes_claimed)>int(rules.starter_attribute_count): return "宝石领取状态无效。"
	if not state.get("rng_state") is String or not str(state.rng_state).is_valid_int() or str(int(state.rng_state)) != str(state.rng_state): return "宝石随机状态无效。"
	if int(state.rare_misses)>=int(rules.pity.purple_or_better) or int(state.rare_misses)>int(state.draws): return "属性石保障记录无效。"
	if not state.get("inventory") is Array or not state.get("slots") is Array or state.slots.size()!=4: return "宝石背包或槽位无效。"
	if not state.get("unlocked_cores") is Array or not state.get("milestone_claimed") is Array or not state.get("migration") is Dictionary: return "宝石解锁记录无效。"
	var cores: Array = []
	for id in state.unlocked_cores:
		if not id is String or not rules.cores.has(id) or id in cores: return "核心解锁记录无效。"
		cores.append(id)
	var milestones: Array = []
	var thresholds: Array = []
	for milestone in rules.milestone_essence: thresholds.append(int(milestone.cleared))
	for threshold in state.milestone_claimed:
		if not integer(threshold,1) or int(threshold) not in thresholds or threshold in milestones or int(threshold)>int(state.cumulative_cleared): return "里程补给记录无效。"
		milestones.append(threshold)
	for threshold in thresholds:
		if int(state.cumulative_cleared)>=threshold and threshold not in milestones: return "已达里程缺少领取凭证。"
	var seen: Array = []
	var inherited: Array = []
	for gem in state.inventory:
		if not gem is Dictionary or not integer(gem.get("serial"),1) or int(gem.serial)>int(state.serial) or gem.get("id")!="gem-%d" % int(gem.serial) or gem.id in seen: return "宝石实例标识无效。"
		seen.append(gem.id)
		if not gem.get("locked") is bool or not gem.get("affixes") is Array or gem.get("core")!="": return "属性石记录无效。"
		if gem.has("legacy_id"):
			var id: String = str(gem.legacy_id)
			if id in inherited or not legacy_catalog.has(id) or int(levels.get(id,0))<=0: return "传承宝石引用无效。"
			inherited.append(id)
			var source: Dictionary = legacy_catalog[id]
			if gem.get("rarity")!="legacy" or gem.get("legacy_name")!=source.name or gem.affixes!=[{"stat":source.stat,"value":source.flat_by_level[int(levels[id])-1]}]: return "传承属性不匹配。"
			continue
		var rarity: String = str(gem.get("rarity",""))
		var transition: bool = rarity=="transition"
		var base_rarity: String = str(gem.get("transition_rarity","")) if transition else rarity
		var expected: int = int(rules.legacy_affix_counts.get(base_rarity,0)) if transition else int(rules.affix_counts.get(rarity,0))
		if expected<=0 or gem.affixes.size()!=expected or (not transition and rarity not in ["green","blue","purple"]): return "属性石品质不匹配。"
		var used: Array = []
		for index in gem.affixes.size():
			var affix: Variant = gem.affixes[index]
			if not affix is Dictionary or not rules.affixes.has(str(affix.get("stat",""))) or affix.stat in used or not integer(affix.get("tier"),1) or int(affix.tier)>3: return "属性类型或档位无效。"
			used.append(affix.stat)
			var values: Array = rules.affixes[affix.stat].tiers if transition or index>0 else rules.affixes[affix.stat].main_tiers
			if affix.get("value")!=values[int(affix.tier)-1]: return "属性数值不匹配。"
			if not transition and affix.get("role")!=("main" if index==0 else "side"): return "主副属性位置无效。"
	if int(state.serial)!=seen.size()+int(state.salvaged) or int(state.draws)>int(state.serial): return "宝石实例收支记录不一致。"
	var equipped: Array = []
	for index in 4:
		var id: Variant = state.slots[index]
		if not id is String: return "宝石槽引用无效。"
		if id.is_empty(): continue
		if index==0:
			if not id.begins_with("core:") or id.trim_prefix("core:") not in cores: return "核心槽只接受已解锁核心。"
		elif id not in seen or id in equipped: return "属性石未持有或重复装备。"
		equipped.append(id)
	for id in legacy_catalog:
		if int(levels.get(id,0))>0 and id not in inherited: return "传承宝石缺失。"
	if not state.get("pending_reforge") is Dictionary: return "改良候选记录无效。"
	var pending: Dictionary = state.pending_reforge
	if not pending.is_empty():
		var gem: Dictionary = find(state,str(pending.get("gem_id","")))
		if gem.is_empty() or gem.rarity not in ["blue","purple"] or pending.get("mode")!="affix" or not integer(pending.get("token"),1) or int(pending.token)!=int(state.work_serial): return "重铸候选来源无效。"
		if not integer(pending.get("index"),1) or int(pending.index)>=gem.affixes.size() or pending.get("old")!=gem.affixes[int(pending.index)] or pending.get("cost")!=rules.workshop.random_retype_cost: return "重铸候选位置无效。"
		var candidate: Variant = pending.get("candidate")
		if not candidate is Dictionary or not rules.affixes.has(str(candidate.get("stat",""))) or candidate.get("tier")!=pending.old.tier or candidate.get("role")!="side" or candidate.get("value")!=rules.affixes[candidate.stat].tiers[int(candidate.tier)-1]: return "重铸候选档位无效。"
		for affix in gem.affixes:
			if affix.stat==candidate.stat: return "重铸候选类型重复。"
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

func validate_old(state: Variant, legacy_catalog: Dictionary, levels: Dictionary) -> String:
	var legacy_rules: Dictionary = {"slots": rules.slots, "pity": rules.legacy_pity, "affixes": rules.affixes, "affix_counts": rules.legacy_affix_counts, "cores": rules.legacy_cores, "workshop": rules.legacy_workshop}
	if not state is Dictionary: return "宝石记录无效。"
	for key in ["serial", "draws", "gold_misses", "rare_misses", "essence", "salvaged", "work_serial"]:
		if not integer(state.get(key)): return "宝石计数无效。"
	if not state.get("first_gold") is bool or not state.get("rng_state") is String or not str(state.rng_state).is_valid_int(): return "宝石随机记录无效。"
	if str(int(state.rng_state)) != str(state.rng_state): return "宝石随机状态超出范围。"
	if int(state.gold_misses) >= int(legacy_rules.pity.gold_hard) or int(state.rare_misses) >= int(legacy_rules.pity.purple_or_better): return "宝石保底计数超出范围。"
	if int(state.gold_misses) > int(state.draws) or int(state.rare_misses) > int(state.draws) or int(state.rare_misses) > int(state.gold_misses): return "宝石保底记录不一致。"
	if bool(state.first_gold) and (int(state.gold_misses) != int(state.draws) or int(state.draws) >= int(legacy_rules.pity.first_gold)): return "首金记录不一致。"
	if not state.get("inventory") is Array or not state.get("slots") is Array or state.slots.size() != int(legacy_rules.slots): return "宝石背包或槽位无效。"
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
		if not legacy_rules.affix_counts.has(rarity) or gem.affixes.size() != int(legacy_rules.affix_counts[rarity]): return "宝石品质不匹配。"
		if (rarity == "gold" and legacy_rules.cores.get(str(gem.core), {}).is_empty()) or (rarity != "gold" and not str(gem.core).is_empty()): return "宝石核心无效。"
		var used: Array = []
		for line in gem.affixes:
			if not line is Dictionary or not legacy_rules.affixes.has(str(line.get("stat", ""))) or line.stat in used: return "重复或未知词条。"
			used.append(line.stat)
			if not integer(line.get("tier"), 1) or int(line.tier) > 3 or line.get("value") != legacy_rules.affixes[line.stat].tiers[int(line.tier) - 1]: return "词条数值或档位不匹配。"
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
			if pending.get("index") != -1 or gem.rarity != "gold" or not legacy_rules.cores.has(str(pending.get("candidate", ""))) or pending.candidate == gem.core or pending.get("old") != gem.core or pending.get("cost") != legacy_rules.workshop.core_cost: return "核心改良候选无效。"
		elif pending.get("mode") == "affix":
			if not integer(pending.get("index")) or int(pending.index) >= gem.affixes.size(): return "词条改良位置无效。"
			if pending.get("old") != gem.affixes[int(pending.index)] or pending.get("cost") != legacy_rules.workshop.affix_costs[gem.rarity]: return "词条改良来源无效。"
			var line: Variant = pending.get("candidate")
			if not line is Dictionary or not legacy_rules.affixes.has(str(line.get("stat", ""))) or not integer(line.get("tier"), 1) or int(line.tier) > 3: return "词条改良候选无效。"
			if line.get("value") != legacy_rules.affixes[line.stat].tiers[int(line.tier) - 1] or line == pending.old: return "词条改良档位无效。"
			for index in gem.affixes.size():
				if index != int(pending.index) and gem.affixes[index].stat == line.stat: return "词条改良候选重复。"
		else: return "改良类型无效。"
	return ""

func integer(value: Variant, minimum: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= 9007199254740991 and float(value) == floor(float(value))
