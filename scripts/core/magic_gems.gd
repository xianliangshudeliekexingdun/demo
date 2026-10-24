extends RefCounted
## Runtime gem defaults live in data. This library never writes account files.
## Four unrestricted slots; a gold gem carries one keystone plus three equal
## attributes. Only the first equipped copy of a keystone is allowed to act.
const PATH = "res://data/magic_gems_v1.json"
const SCHEMA_VERSION = 4
const RARITIES = ["green", "blue", "purple", "gold"]
var rules: Dictionary = {}
var burn_interval: float

func _init():
	rules = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	burn_interval = float(JSON.parse_string(FileAccess.get_file_as_string("res://data/route_spell_runtime.json")).fire.burning.interval)

func fresh() -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	return {"schema_version": SCHEMA_VERSION, "inventory": [], "slots": ["", "", "", ""], "serial": 0,
		"draws": 0, "gold_misses": 0, "rare_misses": 0, "rng_state": str(rng.state),
		"essence": 0, "salvaged": 0, "work_serial": 0, "pending_reforge": {},
		"cumulative_cleared": 0, "milestone_claimed": []}

func is_modern(state) -> bool:
	return state is Dictionary and state.get("schema_version") == SCHEMA_VERSION

func core_rule(id: String) -> Dictionary:
	return rules.cores.get(id, {}).duplicate(true)

func core_description(id: String) -> String:
	var spec: Dictionary = core_rule(id)
	return _formatted_description(spec) if not spec.is_empty() else "未知核心效果。"

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

func random_stat(pool: Array, rng: RandomNumberGenerator) -> String:
	return str(pool[rng.randi_range(0, pool.size()-1)])

## Gold gems use three equally weighted attribute lines and gain no main line,
## so the strength comes from the keystone rather than doubled values.
func create(state: Dictionary, rarity: String, main_stat: String, rng: RandomNumberGenerator, random_tiers: bool = false, origin: String = "craft") -> Dictionary:
	var pool: Array = rules.affixes.keys()
	var lines: Array = []
	var core: String = ""
	if rarity == "gold":
		var cores: Array = rules.cores.keys()
		core = random_stat(cores, rng)
		for index in int(rules.affix_counts.gold):
			var stat: String = random_stat(pool, rng)
			pool.erase(stat)
			lines.append(line(stat, weighted_tier(rng) if random_tiers else 1, false))
	else:
		pool.erase(main_stat)
		lines.append(line(main_stat, weighted_tier(rng) if random_tiers else 1, true))
		for index in int(rules.affix_counts[rarity])-1:
			var stat: String = random_stat(pool, rng)
			pool.erase(stat)
			lines.append(line(stat, weighted_tier(rng) if random_tiers else 1, false))
	state.serial = int(state.serial) + 1
	var gem: Dictionary = {"id": "gem-%d" % int(state.serial), "serial": int(state.serial), "rarity": rarity, "affixes": lines, "core": core, "locked": false, "origin": origin}
	state.inventory.append(gem)
	return gem.duplicate(true)

func sample(state: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var rarity: String = "purple"
	var gold_pity: int = int(rules.pity.gold)
	var purple_pity: int = int(rules.pity.purple_or_better)
	if int(state.gold_misses) >= gold_pity-1:
		rarity = "gold"
	elif int(state.rare_misses) >= purple_pity-1:
		rarity = "purple"
	else:
		var weights: Array = [float(rules.base_weights.green), float(rules.base_weights.blue), float(rules.base_weights.purple), float(rules.gold_weight)]
		rarity = str(RARITIES[rng.rand_weighted(PackedFloat32Array(weights))])
	var keys: Array = rules.affixes.keys()
	var gem: Dictionary = create(state, rarity, random_stat(keys, rng), rng, true, "draw")
	state.draws = int(state.draws)+1
	state.gold_misses = 0 if rarity == "gold" else int(state.gold_misses)+1
	state.rare_misses = 0 if rarity in ["purple", "gold"] else int(state.rare_misses)+1
	return gem

func totals(state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in rules.affixes: result[key] = 0.0
	for id in state.get("slots", []):
		var gem: Dictionary = find(state, str(id))
		if gem.is_empty(): continue
		for affix in gem.affixes: result[str(affix.stat)] += float(affix.value)
	return result

func effect_of(gem: Dictionary) -> String:
	return str(gem.get("core", "")) if str(gem.get("rarity", "")) == "gold" else ""

## Slot order decides which duplicate keystone is allowed to act.
func active_effects(state: Dictionary) -> Array:
	var result: Array = []
	for id in state.get("slots", []):
		var effect: String = effect_of(find(state, str(id)))
		if effect.is_empty() or effect in result: continue
		result.append(effect)
	return result

func first_effect(state: Dictionary) -> String:
	var effects: Array = active_effects(state)
	return "" if effects.is_empty() else str(effects[0])

func duplicate_effects(state: Dictionary) -> Array:
	var seen: Array = []
	var duplicated: Array = []
	for id in state.get("slots", []):
		var effect: String = effect_of(find(state, str(id)))
		if effect.is_empty(): continue
		if effect in seen and effect not in duplicated: duplicated.append(effect)
		seen.append(effect)
	return duplicated

func find(state: Dictionary, id: String) -> Dictionary:
	if id.is_empty(): return {}
	for gem in state.get("inventory", []):
		if str(gem.id) == id: return gem.duplicate(true)
	return {}

func title(gem: Dictionary) -> String:
	if gem.is_empty(): return "空槽"
	if str(gem.get("rarity", "")) == "gold":
		return str(core_rule(str(gem.get("core", ""))).get("name", "未知效果")) + "宝石"
	var main: String = str(rules.affixes[gem.affixes[0].stat].label) if not gem.affixes.is_empty() else ""
	return str(rules.rarity_names.get(gem.rarity, gem.rarity)) + main + "宝石"

func affix_text(gem: Dictionary) -> String:
	var lines: PackedStringArray = []
	var gold: bool = str(gem.get("rarity", "")) == "gold"
	for affix in gem.get("affixes", []):
		var rule: Dictionary = rules.affixes[affix.stat]
		var amount: float = float(affix.value)
		var value: String = number(amount)
		if str(rule.unit) in ["probability_add", "fraction_add"]: value = number(amount*100.0) + "%"
		elif str(rule.unit) == "multiplier_add": value += "倍"
		var role: String = "" if gold else ("主 · " if affix.get("role") == "main" else ("副 · " if affix.get("role") == "side" else ""))
		lines.append(role + str(rule.label) + " +" + value + ("  [%s]" % ["I", "II", "III"][int(affix.tier)-1] if affix.has("tier") else ""))
	return "\n".join(lines)

func number(value: float) -> String:
	return str(int(roundf(value))) if is_equal_approx(value, roundf(value)) else String.num(value, 2)

func salvage_yield(gem: Dictionary) -> int:
	return int(rules.salvage_yields.get(str(gem.get("rarity", "")), 0))

func salvage_value(gem: Dictionary) -> int:
	return salvage_yield(gem)

## Locks hold "core" or an attribute index. Locked parts keep their exact line;
## everything else is rerolled, and attribute types stay unique.
func lock_count(gem: Dictionary, locks: Array) -> int:
	var count: int = 0
	for lock in locks:
		if lock is String and lock == "core" and effect_of(gem) != "": count += 1
		elif (lock is int or lock is float) and float(lock) == floor(float(lock)) and int(lock) >= 0 and int(lock) < gem.affixes.size(): count += 1
	return count

func lockable_count(gem: Dictionary) -> int:
	return gem.affixes.size() + (1 if effect_of(gem) != "" else 0)

func reforge_cost(gem: Dictionary, locks: Array) -> int:
	return int(rules.reforge.base) + int(rules.reforge.per_lock) * lock_count(gem, locks)

func roll_gem(gem: Dictionary, locks: Array, rng: RandomNumberGenerator) -> Dictionary:
	var result: Dictionary = gem.duplicate(true)
	var gold: bool = effect_of(gem) != ""
	if gold and "core" not in locks:
		var pool: Array = rules.cores.keys()
		var current: String = str(gem.get("core", ""))
		if pool.size() > 1: pool.erase(current)
		result.core = random_stat(pool, rng)
	var kept: Array = []
	var kept_stats: Array = []
	for index in gem.affixes.size():
		if index in locks:
			kept.append(gem.affixes[index].duplicate(true))
			kept_stats.append(str(gem.affixes[index].stat))
	var lines: Array = []
	for index in gem.affixes.size():
		if index in locks:
			lines.append(gem.affixes[index].duplicate(true))
			continue
		var pool: Array = rules.affixes.keys()
		for stat in kept_stats: pool.erase(stat)
		var stat: String = random_stat(pool, rng)
		kept_stats.append(stat)
		# The main line keeps its doubled role on green/blue/purple gems.
		lines.append(line(stat, weighted_tier(rng), not gold and index == 0))
	result.affixes = lines
	return result

func validate(state: Variant) -> String:
	if not state is Dictionary: return "宝石记录无效。"
	if not is_modern(state): return "宝石存档版本无效。"
	for key in ["serial", "draws", "gold_misses", "rare_misses", "essence", "salvaged", "work_serial", "cumulative_cleared"]:
		if not integer(state.get(key)): return "宝石计数无效："+key
	if not state.get("rng_state") is String or not str(state.rng_state).is_valid_int() or str(int(state.rng_state)) != str(state.rng_state): return "宝石随机状态无效。"
	if int(state.gold_misses) >= int(rules.pity.gold) or int(state.gold_misses) > int(state.draws): return "金色保障记录无效。"
	if int(state.rare_misses) >= int(rules.pity.purple_or_better) or int(state.rare_misses) > int(state.draws): return "紫色保障记录无效。"
	if not state.get("inventory") is Array or not state.get("slots") is Array or state.slots.size() != int(rules.slots): return "宝石背包或槽位无效。"
	if not state.get("milestone_claimed") is Array: return "里程记录无效。"
	var thresholds: Array = []
	for milestone in rules.milestone_essence: thresholds.append(int(milestone.cleared))
	var milestones: Array = []
	for threshold in state.milestone_claimed:
		if not integer(threshold, 1) or int(threshold) not in thresholds or int(threshold) in milestones or int(threshold) > int(state.cumulative_cleared): return "里程补给记录无效。"
		milestones.append(int(threshold))
	for threshold in thresholds:
		if int(state.cumulative_cleared) >= threshold and threshold not in milestones: return "已达里程缺少领取凭证。"
	var seen: Array = []
	for gem in state.inventory:
		if not gem is Dictionary or not integer(gem.get("serial"), 1) or int(gem.serial) > int(state.serial) or gem.get("id") != "gem-%d" % int(gem.serial) or gem.id in seen: return "宝石实例标识无效。"
		seen.append(gem.id)
		if not gem.get("locked") is bool or not gem.get("affixes") is Array or not gem.get("core") is String: return "宝石记录无效。"
		var rarity: String = str(gem.get("rarity", ""))
		if rarity not in RARITIES: return "宝石品质无效。"
		var expected: int = int(rules.affix_counts[rarity])
		if gem.affixes.size() != expected: return "宝石属性条数与品质不匹配。"
		var gold: bool = rarity == "gold"
		if gold and not rules.cores.has(str(gem.core)): return "金色宝石效果无效。"
		if not gold and not str(gem.core).is_empty(): return "非金色宝石不能携带效果。"
		var used: Array = []
		for index in gem.affixes.size():
			var affix: Variant = gem.affixes[index]
			if not affix is Dictionary or not rules.affixes.has(str(affix.get("stat", ""))) or affix.stat in used or not integer(affix.get("tier"), 1) or int(affix.tier) > 3: return "属性类型或档位无效。"
			used.append(affix.stat)
			var values: Array = rules.affixes[affix.stat].tiers if gold or index > 0 else rules.affixes[affix.stat].main_tiers
			if affix.get("value") != values[int(affix.tier)-1]: return "属性数值不匹配。"
			if gold and affix.get("role") != "side": return "金色宝石属性不分主副。"
			if not gold and affix.get("role") != ("main" if index == 0 else "side"): return "主副属性位置无效。"
	if int(state.serial) != seen.size() + int(state.salvaged) or int(state.draws) != int(state.serial): return "宝石实例收支记录不一致。"
	var equipped: Array = []
	for index in int(rules.slots):
		var id: Variant = state.slots[index]
		if not id is String: return "宝石槽引用无效。"
		if id.is_empty(): continue
		if id not in seen or id in equipped: return "宝石未持有或重复装备。"
		equipped.append(id)
	if not state.get("pending_reforge") is Dictionary: return "重洗候选记录无效。"
	return _validate_pending(state)

func _validate_pending(state: Dictionary) -> String:
	var pending: Dictionary = state.pending_reforge
	if pending.is_empty(): return ""
	var gem: Dictionary = find(state, str(pending.get("gem_id", "")))
	if gem.is_empty() or pending.get("mode") != "reroll": return "重洗候选来源无效。"
	if not integer(pending.get("token"), 1) or int(pending.token) != int(state.work_serial): return "重洗候选标识无效。"
	if not pending.get("locks") is Array: return "重洗候选锁定无效。"
	var locks: Array = pending.locks
	if locks.size() > int(rules.reforge.max_locks) or lock_count(gem, locks) != locks.size(): return "重洗候选锁定无效。"
	if int(pending.get("cost", -1)) != reforge_cost(gem, locks): return "重洗候选费用无效。"
	if not pending.get("old") is Dictionary or not pending.get("candidate") is Dictionary: return "重洗候选内容无效。"
	var old: Dictionary = pending.old
	var candidate: Dictionary = pending.candidate
	if old.get("core") != gem.get("core") or old.get("affixes") != gem.affixes: return "重洗候选与当前宝石不一致。"
	if not candidate.get("core") is String or not candidate.get("affixes") is Array or candidate.affixes.size() != gem.affixes.size(): return "重洗候选结果无效。"
	if effect_of(gem) != "" and "core" in locks and candidate.core != gem.core: return "锁定效果不得改变。"
	if effect_of(gem) == "" and not candidate.core.is_empty(): return "非金色宝石不得获得效果。"
	if effect_of(gem) != "" and not rules.cores.has(str(candidate.core)): return "重洗候选效果无效。"
	var used: Array = []
	var gold: bool = effect_of(gem) != ""
	for index in candidate.affixes.size():
		var affix: Variant = candidate.affixes[index]
		if not affix is Dictionary or not rules.affixes.has(str(affix.get("stat", ""))) or affix.stat in used or not integer(affix.get("tier"), 1) or int(affix.tier) > 3: return "重洗候选属性无效。"
		used.append(affix.stat)
		var values: Array = rules.affixes[affix.stat].tiers if gold or index > 0 else rules.affixes[affix.stat].main_tiers
		if affix.get("value") != values[int(affix.tier)-1]: return "重洗候选数值无效。"
		if gold and affix.get("role") != "side": return "重洗候选属性无效。"
		if not gold and affix.get("role") != ("main" if index == 0 else "side"): return "重洗候选位置无效。"
		if index in locks and candidate.affixes[index] != gem.affixes[index]: return "锁定属性不得改变。"
	return ""

func integer(value: Variant, minimum: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= 9007199254740991 and float(value) == floor(float(value))
