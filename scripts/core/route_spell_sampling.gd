extends RefCounted
## Pure offer probabilities. Caller supplies the legal pool; no inventory or RNG
## mutation happens until sample() is explicitly invoked by a reward owner.
const SOURCE = "res://data/route_spell_sampling.json"
var rules: Dictionary = {}

func configure(source: Dictionary) -> Dictionary:
	if not source.get("version") is String or str(source.version).is_empty():
		return {"ok": false, "error": "六系抽取缺少规则版本。"}
	if str(source.get("method", "")) != "school_priority_mixture" or not source.get("catalyst_affinity_by_level") is Array:
		return {"ok": false, "error": "六系抽取规则无效。"}
	if source.catalyst_affinity_by_level.size() != 3:
		return {"ok": false, "error": "触媒优先强度需要三个等级。"}
	var previous: float = -1.0
	for value in source.catalyst_affinity_by_level:
		if not _number(value) or float(value) < 0.0 or float(value) >= 1.0 or float(value) <= previous:
			return {"ok": false, "error": "触媒优先强度范围或顺序无效。"}
		previous = float(value)
	for key in ["baseline_spell_weight", "owned_upgrade_weight"]:
		if not _number(source.get(key)) or float(source[key]) <= 0.0 or (key == "owned_upgrade_weight" and float(source[key]) < 1.0):
			return {"ok": false, "error": "法术基础权重无效：" + key}
	if not _number(source.get("offer_size")) or int(source.offer_size) != 3 or float(source.offer_size) != 3.0:
		return {"ok": false, "error": "正式法术书必须三选一。"}
	for key in ["unique_within_offer", "eligibility_before_weighting"]:
		if source.get(key) != true: return {"ok": false, "error": "法术抽取缺少合法池去重约束。"}
	for key in ["affects_initial_offer", "affects_artifact_quality", "new_or_upgrade_quota", "reroll", "pity"]:
		if source.get(key) != false: return {"ok": false, "error": "法术抽取包含未开放规则：" + key}
	rules = source.duplicate(true)
	return {"ok": true, "error": ""}

func probabilities(pool: Array, definitions: Dictionary, owned: Dictionary, school: String = "", level: int = 0) -> Dictionary:
	var weights: Dictionary = {}
	var total: float = 0.0
	var main: float = 0.0
	# The common baseline factor cancels. Normalize by the largest relative
	# weight before summing, keeping every accepted finite input finite.
	var scale: float = maxf(1.0, float(rules.owned_upgrade_weight))
	for id in pool:
		if weights.has(id) or not definitions.has(id): continue
		var weight: float = (float(rules.owned_upgrade_weight) if owned.has(id) else 1.0) / scale
		weights[id] = weight
		total += weight
		if not school.is_empty() and str(definitions[id].get("school", "")) == school: main += weight
	var result: Dictionary = {}
	if total <= 0.0: return result
	var affinity: float = float(rules.catalyst_affinity_by_level[level - 1]) if level >= 1 and level <= 3 and not school.is_empty() else 0.0
	var split: bool = main > 0.0 and main < total
	var main_probability: float = main / total + (1.0 - main / total) * affinity
	for id in weights:
		if affinity <= 0.0 or not split:
			result[id] = float(weights[id]) / total
		elif str(definitions[id].get("school", "")) == school:
			result[id] = main_probability * float(weights[id]) / main
		else:
			result[id] = (1.0 - main_probability) * float(weights[id]) / (total - main)
	return result

func sample(pool: Array, definitions: Dictionary, owned: Dictionary, school: String, level: int, rng: RandomNumberGenerator) -> Array:
	var remaining: Array = []
	for id in pool:
		if definitions.has(id) and id not in remaining: remaining.append(id)
	var result: Array = []
	for _index in mini(int(rules.offer_size), remaining.size()):
		var chances: Dictionary = probabilities(remaining, definitions, owned, school, level)
		if chances.is_empty(): break
		# Equivalent to group then item, with one RNG draw per card. Inspection
		# and reopening cards never call this method or advance the stream.
		var roll: float = rng.randf()
		var selected: String = str(chances.keys().back())
		for id in chances:
			roll -= float(chances[id])
			if roll < 0.0:
				selected = str(id)
				break
		result.append({"id": selected, "draw_probability": float(chances[selected])})
		remaining.erase(selected)
	return result

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
