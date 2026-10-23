extends RefCounted
## Run-local unique artifacts. The runner owns reward gates and damage resolution.
## Values are read from approved tables; event effects cannot recursively proc.

const RUNTIME_PATH = "res://data/route_artifact_runtime.json"
const GENERIC_PATH = "res://data/generic_artifacts_v1.json"
const ICE_PATH = "res://data/ice_artifacts_v1.json"
const BossCatalog = preload("res://scripts/core/route_boss_catalog.gd")
var _boss_catalog = BossCatalog.new()
const GenericItems = preload("res://scripts/core/route_generic_items.gd")
const IceItems = preload("res://scripts/core/route_ice_artifacts.gd")
var error: String = ""
var _base: Dictionary = {}
var _items: Dictionary = {}
var _runtime: Dictionary = {}
var _economy: Dictionary = {}
var _owned: Array = []
var _offers: Dictionary = {}
var _rewarded_rooms: Array = []
var _natural_casts: int = 0
var _offensive_casts: int = 0
var _spring_elapsed: float = 0.0
var _sync_remaining: float = 0.0
var _patches: Array = []
var _patch_casts: Dictionary = {}
var _patch_next_hit: Dictionary = {}
var _end_casts: Dictionary = {}
var _speed_casts: Dictionary = {}
var _speed_remaining: float = 0.0
var _last_choice_room: int = -1
var _generic
var _generic_rules: Dictionary = {}
var _ice


func configure(base: Dictionary, artifact_source: Dictionary, runtime: Dictionary = {}) -> Dictionary:
	_base = base.duplicate(true)
	var boss_result: Dictionary = _boss_catalog.load_data()
	if not boss_result.ok:
		return boss_result
	_runtime = runtime.duplicate(true) if not runtime.is_empty() else _read_json(RUNTIME_PATH)
	var route_source: Dictionary = _read_json(str(_runtime.get("route_source", "")))
	var reward_rooms: Array = []
	for room in route_source.get("artifact_reward_rooms", []):
		reward_rooms.append(int(room))
	_runtime["reward_rooms"] = reward_rooms
	_economy = _read_json(str(_runtime.get("economy_source", "")))
	_items = _resolve_refs(artifact_source.get("items", {}), _base)
	var generic_source: Dictionary = _read_json(GENERIC_PATH)
	_generic_rules = generic_source.get("rules", {}).duplicate(true)
	for id in generic_source.get("items", {}):
		if _items.has(id):
			error = "通用宝物ID重复：" + str(id)
			return {"ok": false, "error": error}
		_items[id] = _resolve_refs(generic_source.items[id], _base)
	var ice_source: Dictionary = _read_json(ICE_PATH)
	for id in ice_source.get("items", {}):
		if _items.has(id):
			error = "冰系宝物ID重复：" + str(id)
			return {"ok": false, "error": error}
		_items[id] = ice_source.items[id].duplicate(true)
	for id in _boss_catalog.data.fallback_items:
		_items[id] = _boss_catalog.data.fallback_items[id].duplicate(true)
	_owned.clear()
	_offers.clear()
	_rewarded_rooms.clear()
	_last_choice_room = -1
	_generic = GenericItems.new()
	_generic.configure(_items, _generic_rules, _base, _owned)
	_ice = IceItems.new()
	_ice.configure(_items, _owned)
	reset_room()
	error = ""
	if generic_source.get("items", {}).size() != 19 or ice_source.get("items", {}).size() != 16 or _items.size() != 63 or _generic_rules.is_empty() or _economy.is_empty() or _runtime.get("reward_rooms", []).is_empty():
		error = "宝物参数缺失或格式无效。"
		return {"ok": false, "error": error}
	for id in _items:
		if _items[id].get("name", "").is_empty() or _items[id].get("rarity", "") not in ["blue", "purple", "gold"]:
			error = "宝物条目无效：" + str(id)
			return {"ok": false, "error": error}
	return {"ok": true, "error": ""}


func reset_room() -> void:
	_natural_casts = 0
	_offensive_casts = 0
	_spring_elapsed = 0.0
	_sync_remaining = 0.0
	_patches.clear()
	_patch_casts.clear()
	_patch_next_hit.clear()
	_end_casts.clear()
	_speed_casts.clear()
	_speed_remaining = 0.0
	if _generic != null:
		_generic.reset_room()
	if _ice != null:
		_ice.reset_room()


func has_artifact(id: String) -> bool:
	return id in _owned and not bool(_items.get(id, {}).get("retired_to_spell_growth", false))


func eligible_ids(run) -> Array:
	var result: Array = []
	for id in _items:
		if bool(_items[id].get("active", true)) and not bool(_items[id].get("boss_only", false)) and id not in _owned and _eligible(run, _items[id]):
			result.append(id)
	return result


func sample_choices(run, rng: RandomNumberGenerator) -> Array:
	var room: int = int(run.room_index)
	if not _boss_catalog.for_room(room).is_empty():
		return sample_boss_choices(run, rng)
	if room not in _runtime.reward_rooms or room in _rewarded_rooms:
		return []
	_last_choice_room = room
	if _offers.has(room):
		return _offers[room].duplicate(true)
	var result: Array = _sample_offer(run, rng, "chest", room, int(_economy.offers.chest_choices))
	_offers[room] = result.duplicate(true)
	return result


func sample_boss_choices(run, rng: RandomNumberGenerator) -> Array:
	var room: int = int(run.room_index)
	# Book transaction must be final (including replacement/skip) before sampling.
	if _boss_catalog.for_room(room).is_empty() or room in _rewarded_rooms or not bool(run.boss_rewards.get("book_resolved", false)):
		return []
	_last_choice_room = room
	if _offers.has(room):
		return _offers[room].duplicate(true)
	var pool: Array = eligible_ids(run).filter(func(id): return str(_items[id].rarity) == "gold")
	var result: Array = []
	for index in mini(pool.size(), int(_boss_catalog.data.reward.chest_choices)):
		var id: String = str(pool[rng.randi_range(0, pool.size() - 1)])
		pool.erase(id)
		result.append(_describe(id))
	if result.is_empty():
		var fallback := "BGT%d" % room
		if not has_artifact(fallback):
			result.append(_describe(fallback))
	_offers[room] = result.duplicate(true)
	return result


func sample_shop_choices(run, rng: RandomNumberGenerator) -> Array:
	return _sample_offer(run, rng, "shop", int(run.room_index), int(_economy.offers.shop_slots))


func _sample_offer(run, rng: RandomNumberGenerator, source: String, room: int, slots: int) -> Array:
	var weights: Dictionary = {}
	for stage in _economy.stages:
		if room >= int(stage.from) and room <= int(stage.to):
			weights = stage.rarity_weights
			break
	var pool = eligible_ids(run).filter(func(id): return float(weights.get(_items[id].rarity, 0.0)) > 0.0)
	var result: Array = []
	var guarantee: String = str(_economy.guarantees[source].get(str(room), ""))
	var count: int = mini(slots, pool.size())
	for index in count:
		var tiers: Dictionary = {}
		for id in pool:
			var rarity: String = str(_items[id].rarity)
			if not tiers.has(rarity):
				tiers[rarity] = []
			tiers[rarity].append(id)
		var selected_tier = ""
		if index == 0 and not guarantee.is_empty():
			if tiers.has(guarantee):
				selected_tier = guarantee
			else:
				for tier in ["gold", "purple", "blue"]:
					if tiers.has(tier):
						selected_tier = tier
						break
		else:
			var total: float = 0.0
			for rarity in tiers:
				total += float(weights[rarity])
			var roll: float = rng.randf() * total
			for rarity in tiers:
				roll -= float(weights[rarity])
				selected_tier = rarity
				if roll < 0.0:
					break
		var candidates: Array = tiers[selected_tier]
		var chosen: String = candidates[rng.randi_range(0, candidates.size() - 1)]
		pool.erase(chosen)
		result.append(_describe(chosen))
	return result


func acquire_shop_item(id: String, run, offers: Array) -> bool:
	if run.phase != "shopping" or id in _owned or id not in eligible_ids(run):
		return false
	if not offers.any(func(item): return str(item.get("id", "")) == id):
		return false
	_owned.append(id)
	apply_acquisition(run, id)
	return true


func increase_max_health(run, base_gain: float) -> void:
	var fractions: Dictionary = run._gem_combat.begin_cap_change(run) if run.has_method("gem_core") else {}
	var multiplier: float = float(_items.GT03.maximum_health_multiplier) if has_artifact("GT03") else 1.0
	run.player.max_health += base_gain * multiplier
	if run.has_method("gem_core"): run._gem_combat.finish_cap_change(run, fractions)


func choose(id: String, run = null) -> bool:
	var room: int = int(run.room_index) if run != null else _last_choice_room
	if bool(_items.get(id, {}).get("retired_to_spell_growth", false)) or room in _rewarded_rooms or id in _owned or not _offers.has(room):
		return false
	var offered: bool = false
	for choice in _offers[room]:
		if choice.id == id:
			offered = true
	if not offered:
		return false
	_owned.append(id)
	_rewarded_rooms.append(room)
	if run != null:
		apply_acquisition(run, id)
	return true


func owned_snapshot() -> Array:
	var result: Array = []
	for id in _owned:
		if has_artifact(str(id)): result.append(_describe(id))
	return result


func state_snapshot() -> Dictionary:
	return {"owned": owned_snapshot(), "rewarded_rooms": _rewarded_rooms.duplicate(), "natural_casts": _natural_casts, "offensive_casts": _offensive_casts, "spring_elapsed": _spring_elapsed, "sync_remaining": _sync_remaining, "patches": _patches.duplicate(true), "speed_remaining": _speed_remaining, "generic": _generic.state_snapshot() if _generic != null else {}, "ice": _ice.state_snapshot() if _ice != null else {}}


func player_bonuses() -> Dictionary:
	var result = {"health_max_add": 0.0, "shield_max_add": 0.0, "attack_add": 0.0, "fire_crit_rate_add": 0.0, "fire_bonus_add": 0.0}
	for id in _owned:
		if not has_artifact(str(id)): continue
		for key in result:
			result[key] += float(_items[id].get(key, 0.0))
	return result


func defense_bonuses() -> Dictionary:
	var all = player_bonuses()
	return {"health_max_add": all.health_max_add, "shield_max_add": all.shield_max_add}


func move_speed_multiplier(run = null) -> float:
	var bonus: float = float(_items.B09.move_speed_bonus) if has_artifact("B09") and _speed_remaining > 0.0 else 0.0
	if _generic != null:
		bonus += _generic.move_speed_bonus(run)
	if run != null and run.phase == "combat":
		bonus += float(run.player.get("gem_speed", 0.0))
		if run._spell_combat != null: bonus += run._spell_combat.growth.move_speed_bonus(run)
	return 1.0 + minf(float(_generic_rules.get("combat_move_speed_bonus_cap", 0.35)), bonus)


func before_combat_tick(run, dt: float, move: Vector2) -> void:
	_generic.before_combat_tick(run, dt, move)


func incoming_damage_multiplier(run, damage_kind: String) -> float:
	var original: float = _generic.incoming_damage_multiplier(run, damage_kind)
	var extra: float = ice_defense_bonus(run)
	if run.get("_spell_combat") != null and run._spell_combat.get("earth") != null:
		extra += run._spell_combat.earth.defense_bonus(run)
	if extra <= 0.0:
		return original
	var defense: float = float(_generic.combat_stats(run).defense)
	var coefficient: float = float(_generic_rules.defense_coefficient)
	var adjusted: float = original * (coefficient + defense) / (coefficient + defense + extra)
	return maxf(1.0 - float(_generic_rules.maximum_damage_reduction), adjusted)


func on_player_damaged(run, shield_loss: float, health_loss: float, shield_broken: bool) -> void:
	_generic.on_player_damaged(run, shield_loss, health_loss, shield_broken)
	if _ice != null:
		_ice.on_player_damaged(run, shield_loss, health_loss)


func on_enemy_killed(run, actor: Dictionary) -> void:
	_generic.on_enemy_killed(run, actor)


func on_room_cleared(run) -> void:
	_generic.on_room_cleared(run)


func restore_player_shield(run, base_amount: float, source: String) -> float:
	return _generic.restore_player_shield(run, base_amount, source)


func get_cooldown_reduction() -> float:
	return _generic.get_cooldown_reduction()


func fire_crit_rate_bonus() -> float:
	var result: float = 0.0
	for id in _owned:
		if has_artifact(str(id)) and str(_items[id].get("scope", "")) == "fire":
			result += float(_items[id].get("fire_crit_rate_add", 0.0))
	return result


func fire_damage_bonus() -> float:
	var result: float = 0.0
	for id in _owned:
		if has_artifact(str(id)) and str(_items[id].get("scope", "")) == "fire":
			result += float(_items[id].get("fire_bonus_add", 0.0))
	return result


func burn_parameters(base_parameters: Dictionary) -> Dictionary:
	var result: Dictionary = base_parameters.duplicate(true)
	if has_artifact("P06"):
		result.duration = float(_items.P06.burn_duration)
		result.maximum_ticks = int(_items.P06.maximum_ticks)
	return result


func reignite_spec() -> Dictionary:
	return _items.G04.duplicate(true) if has_artifact("G04") else {}


func combat_stats(run) -> Dictionary:
	var result: Dictionary = _generic.combat_stats(run)
	result["ice_defense_add"] = ice_defense_bonus(run)
	result.defense = float(result.defense) + float(result.ice_defense_add)
	result["move_speed_multiplier"] = move_speed_multiplier(run)
	result["damage_reduction"] = 1.0 - incoming_damage_multiplier(run, "ordinary")
	result["projectile_damage_reduction"] = 1.0 - incoming_damage_multiplier(run, "projectile")
	return result


func apply_acquisition(run, id: String) -> void:
	if bool(_items.get(id, {}).get("retired_to_spell_growth", false)): return
	var item: Dictionary = _items[id]
	var before_health: float = float(run.player.health)
	var before_shield: float = float(run.player.shield)
	var fractions: Dictionary = run._gem_combat.begin_cap_change(run) if run.has_method("gem_core") else {}
	_generic.apply_acquisition(run, id)
	if item.has("shield_max_add"):
		run.player.max_shield += float(item.shield_max_add)
	if item.has("attack_add"):
		run.player.attack += float(item.attack_add)
	if run.has_method("gem_core"): run._gem_combat.finish_cap_change(run, fractions)
	if bool(item.get("boss_only", false)):
		# A seal changes capacity, including the existing life-to-shield conversion,
		# but never restores current resources through percentage preservation.
		run.player.health = minf(before_health, float(run.player.max_health))
		run.player.shield = minf(before_shield, float(run.player.max_shield))
	# Scoped fire bonuses are read for fire damage only, never copied into
	# shared player critical/fire fields that would affect legacy spirits.
	if id == "P01" and run.has_method("artifact_refresh_spirits"):
		run.artifact_refresh_spirits()


func modify_spell_stats(id: String, data: Dictionary, _level: int = 1) -> Dictionary:
	if str(data.get("school", "")) == "ice" and _ice != null:
		return _ice.modify_spell_stats(id, data, _level)
	var result: Dictionary = data.duplicate(true)
	var target: Dictionary = result.level if result.get("level") is Dictionary else result
	match id:
		"F01":
			if has_artifact("B01"):
				_modify_numeric(result, target, "radius", float(_items.B01.radius_multiplier), 0.0)
		"F03":
			if has_artifact("B03"):
				result.fixed_center_drops = _items.B03.fixed_center_drops
				result.first_drop_damage_multiplier = _items.B03.first_drop_damage_multiplier
		"F04":
			if has_artifact("B04"):
				_modify_numeric(result, target, "duration", 1.0, float(_items.B04.duration_add))
				result.normal_laser_damage_multiplier = _items.B04.normal_laser_damage_multiplier
			if has_artifact("P01"):
				_modify_numeric(result, target, "count", 1.0, float(_items.P01.spirit_count_add))
		"F05":
			if has_artifact("B05"):
				result.first_hit_slow = _items.B05.slow
				result.first_hit_slow_duration = _items.B05.duration
		"F06":
			if has_artifact("B06"):
				_modify_numeric(result, target, "radius", float(_items.B06.radius_multiplier), 0.0)
		"F07":
			if has_artifact("B07"):
				result.main_center_damage_multiplier = _items.B07.main_center_damage_multiplier
				result.main_center_crit_multiplier_add = _items.B07.main_center_crit_multiplier_add
		"F08":
			if has_artifact("B08"):
				_modify_numeric(result, target, "width", float(_items.B08.width_multiplier), 0.0)
		"F10":
			if has_artifact("B10"):
				_modify_numeric(result, target, "shield", 1.0, float(_items.B10.shield_restore_add))
		"F11":
			if has_artifact("B11"):
				_modify_numeric(result, target, "spread_targets", 1.0, float(_items.B11.spread_targets_add))
	return result


func modify_damage_context(run, actor: Dictionary, _context: Dictionary) -> Dictionary:
	var result = {"damage_multiplier": 1.0, "crit_multiplier_add": 0.0}
	if _generic != null:
		result.damage_multiplier *= 1.0 + _generic.damage_bonus(run, actor)
		result.crit_multiplier_add += float(_generic.combat_stats(run).crit_multiplier_add)
	if _is_fire_context(_context) and has_artifact("P03") and run.has_method("artifact_overlapping_spells"):
		var kinds: Array = run.artifact_overlapping_spells(actor.pos, float(actor.radius))
		var unique: Array = []
		for id in kinds:
			if id in _runtime.area_spells and id not in unique:
				unique.append(id)
		if unique.size() >= int(_items.P03.required_distinct_areas):
			result.damage_multiplier *= 1.0 + float(_items.P03.fire_vulnerability)
	return result


func on_cast(run, spell: Dictionary, target: Dictionary, context: Dictionary) -> void:
	if not bool(context.get("natural", false)):
		return
	var id: String = str(spell.id)
	if str(_base.spells.get(id, {}).get("kind", "")) == "passive":
		return
	var offensive: bool = id in _runtime.offensive_player_spells
	var fire_offensive: bool = offensive and _is_fire_context(context)
	_natural_casts += 1
	if fire_offensive:
		_offensive_casts += 1
	if has_artifact("P04") and _natural_casts % int(_items.P04.natural_casts_per_extra) == 0:
		var legal: Array = _legal_extras(run)
		if not legal.is_empty():
			var chosen: Dictionary = legal[run._rng.randi_range(0, legal.size() - 1)]
			run.cast_extra_spell(chosen.id, chosen.target, float(_items.P04.damage_multiplier))
	if has_artifact("G01") and fire_offensive and _offensive_casts % int(_items.G01.offensive_casts_per_echo) == 0:
		run.cast_extra_spell(id, target, float(_items.G01.echo_damage_multiplier))
	if has_artifact("G02") and offensive and _sync_remaining <= 0.0 and run.has_method("artifact_spirit_sync"):
		if run.artifact_spirit_sync(target, float(_items.G02.coefficient)):
			_sync_remaining = float(_items.G02.shared_cooldown)


func on_hit(run, actor: Dictionary, context: Dictionary, result: Dictionary = {}) -> void:
	_generic.on_hit(run, actor, context, result)
	var spell_id: String = str(context.get("spell_id", ""))
	var cast_id: String = str(context.get("cast_id", ""))
	if spell_id == "F09" and has_artifact("B09") and not _speed_casts.has(cast_id) and float(result.get("damage", 1.0)) > 0.0:
		_speed_casts[cast_id] = true
		_speed_remaining = float(_items.B09.duration)
		_emit(run, "artifact_speed", {"artifact_id": "B09", "pos": run.player.pos}, float(_items.B09.duration))
	if not has_artifact("P02") or not _is_fire_context(context) or not bool(context.get("natural", false)) or not bool(result.get("critical", false)) or float(result.get("damage", 1.0)) <= 0.0 or spell_id not in _runtime.direct_player_spells:
		return
	if str(context.get("kind", "")) in ["area", "spirit", "artifact"] or _patch_casts.has(cast_id):
		return
	_patch_casts[cast_id] = true
	var patch = {"pos": actor.pos, "radius": float(_items.P02.radius), "remaining": float(_items.P02.duration), "interval_remaining": float(_items.P02.interval), "cast_id": cast_id}
	_patches.append(patch)
	_emit(run, "artifact_patch", {"artifact_id": "P02", "pos": patch.pos, "radius": patch.radius}, patch.remaining)


func on_area_expired(run, context: Dictionary, pos: Vector2) -> void:
	# Historical endpoint remains callable, but the approved G03 now belongs
	# to a real zone-age event rather than deletion/expiration.
	if _items.G03.has("trigger_age"):
		return
	on_area_matured(run, context, pos, INF)


func on_area_matured(run, context: Dictionary, pos: Vector2, age: float) -> void:
	if not has_artifact("G03") or not bool(context.get("natural", false)) or str(context.get("spell_id", "")) not in _runtime.area_spells:
		return
	if run.phase != "combat" or bool(run.paused) or age + 0.000001 < float(_items.G03.get("trigger_age", 0.0)):
		return
	var cast_id: String = str(context.get("cast_id", ""))
	if _end_casts.has(cast_id):
		return
	_end_casts[cast_id] = true
	var radius: float = float(_items.G03.radius)
	for actor in run.actors:
		if actor.health > 0.0 and actor.pos.distance_to(pos) <= radius + float(actor.radius):
			run.resolve_spell_hit(actor, float(_items.G03.coefficient), {"natural": false, "cast_id": cast_id, "spell_id": "G03", "kind": "artifact", "artifact_id": "G03", "pos": pos, "school": "fire"})
	_emit(run, "artifact_explosion", {"artifact_id": "G03", "pos": pos, "radius": radius, "age": age, "trigger": "area_age"}, float(_runtime.effects.explosion_lifetime))


func update(run, dt: float) -> void:
	if run.phase != "combat" or bool(run.paused) or dt <= 0.0:
		return
	_generic.update(run, dt)
	_sync_remaining = maxf(0.0, _sync_remaining - dt)
	_speed_remaining = maxf(0.0, _speed_remaining - dt)
	if has_artifact("P05"):
		_spring_elapsed += dt
		var interval: float = float(_items.P05.interval)
		while _spring_elapsed + 0.000001 >= interval:
			_spring_elapsed -= interval
			for spell in run.spells:
				if str(_base.spells.get(str(spell.id), {}).get("kind", "")) != "passive":
					spell.remaining *= float(_items.P05.remaining_cooldown_multiplier)
			_emit(run, "artifact_cooldown", {"artifact_id": "P05", "pos": run.player.pos}, float(_runtime.effects.cooldown_lifetime))
	for key in _patch_next_hit:
		_patch_next_hit[key] = maxf(0.0, float(_patch_next_hit[key]) - dt)
	var retained: Array = []
	var candidates: Dictionary = {}
	for patch in _patches:
		patch.remaining = maxf(0.0, float(patch.remaining) - dt)
		patch.interval_remaining -= dt
		if float(patch.interval_remaining) <= 0.000001:
			patch.interval_remaining += float(_items.P02.interval)
			for actor in run.actors:
				if actor.health > 0.0 and actor.pos.distance_to(patch.pos) <= float(patch.radius) + float(actor.radius):
					candidates[actor.id] = {"actor": actor, "patch": patch}
		if patch.remaining > 0.000001:
			retained.append(patch)
	_patches = retained
	for key in candidates:
		if float(_patch_next_hit.get(key, 0.0)) <= 0.000001:
			var value: Dictionary = candidates[key]
			run.resolve_spell_hit(value.actor, float(_items.P02.coefficient), {"natural": false, "cast_id": value.patch.cast_id, "spell_id": "P02", "kind": "artifact", "artifact_id": "P02", "pos": value.patch.pos, "school": "fire"})
			_patch_next_hit[key] = float(_items.P02.interval)


func _legal_extras(run) -> Array:
	var result: Array = []
	for spell in run.spells:
		var id: String = str(spell.id)
		if run.has_method("artifact_extra_spell_target"):
			var actual_target: Dictionary = run.artifact_extra_spell_target(spell)
			if not actual_target.is_empty():
				result.append({"id": id, "target": actual_target})
			continue
		# Legacy standalone artifact harnesses keep the same geometry rules.
		var stats: Dictionary = run.get_spell_stats(spell)
		if str(stats.kind) == "passive":
			continue
		if str(stats.get("school", "")) == "lightning" and run.has_method("artifact_extra_spell_target"):
			var lightning_target: Dictionary = run.artifact_extra_spell_target(spell)
			if not lightning_target.is_empty():
				result.append({"id": id, "target": lightning_target})
			continue
		if str(stats.kind) == "shield":
			var alive: bool = false
			for actor in run.actors:
				if float(actor.health) > 0.0:
					alive = true
					break
			if run.player.shield < run.player.max_shield and alive:
				result.append({"id": id, "target": {}})
			continue
		if str(stats.kind) == "spirit":
			if run.has_method("artifact_spirit_count") and int(run.artifact_spirit_count()) >= int(stats.count):
				continue
			if not run.has_method("artifact_spirit_count") and bool(run.spirit.get("active", false)):
				continue
		var direct: bool = str(stats.kind) in ["bolt", "beam", "brand"]
		var range_value: float = float(stats.level.get("radius", 0.0)) if str(stats.kind) == "wave" else float(stats.level.get("range", stats.get("range", 0.0)))
		var clearance: float = float(run._runtime.bolt_collision_radius) if str(stats.kind) == "bolt" else (float(stats.width) * 0.5 if str(stats.kind) == "beam" else 0.0)
		var target: Dictionary = run.nearest_target(run.player.pos, range_value, direct, clearance)
		if str(stats.kind) == "bomb":
			for actor in run.actors:
				if float(actor.health) > 0.0 and run.player.pos.distance_to(actor.pos) <= range_value:
					if target.is_empty() or float(actor.health) > float(target.health) or (is_equal_approx(float(actor.health), float(target.health)) and int(actor.id) < int(target.id)):
						target = actor
		if not target.is_empty():
			result.append({"id": id, "target": target})
	return result


func _eligible(run, item: Dictionary) -> bool:
	if bool(item.get("retired_to_spell_growth", false)): return false
	if _generic != null:
		if item.has("cooldown_reduction_add"):
			if not _has_uncapped_cooldown(run):
				return false
		elif str(item.get("requirement", "")) == "permanent_crit_rate":
			# A permanent fire-only critical source can qualify the unchanged
			# generic critical-damage item without leaking that source globally.
			var effective_rate: float = float(run.player.crit_rate)
			for spell in run.spells:
				if str(spell.id) in _runtime.offensive_player_spells and str(_base.spells.get(str(spell.id), {}).get("school", "fire")) == "fire":
					effective_rate += fire_crit_rate_bonus() + run._spell_combat.crit_rate_bonus()
					break
			if effective_rate + 0.000001 < float(item.minimum_crit_rate):
				return false
		elif str(item.get("requirement", "")) == "combat_shield_recovery_and_player_damage":
			var can_damage: bool = false
			var can_restore: bool = has_artifact("GU11") or has_artifact("GU16") or has_artifact("IG03")
			if run.has_method("gem_core") and run.gem_core() == "aegis" and (has_artifact("GU14") or has_artifact("GT04")): can_restore = true
			for spell in run.spells:
				if str(spell.id) in _runtime.offensive_player_spells:
					can_damage = true
				if str(spell.id) in ["F10", "L09", "R05", "S09"] or (str(spell.id) == "I08" and float(run.get_spell_stats(spell).level.get("window_restore", 0.0)) > 0.0):
					can_restore = true
			if not can_damage or not can_restore:
				return false
		elif not _generic.eligible(run, item):
			return false
	if str(item.get("scope", "")) == "ice":
		return _ice != null and _ice.eligible(run, item)
	var ids: Array = []
	var levels: Dictionary = {}
	for spell in run.spells:
		if spell.id not in ids:
			ids.append(spell.id)
		levels[spell.id] = int(spell.level)
	if item.has("required_spell"):
		return item.required_spell in ids
	var offensive: Array = ids.filter(func(id): return id in _runtime.offensive_player_spells and str(_base.spells.get(id, {}).get("school", "fire")) == "fire")
	var all_offensive: Array = ids.filter(func(id): return id in _runtime.offensive_player_spells)
	var fire_ids: Array = ids.filter(func(id): return str(_base.spells.get(id, {}).get("school", "fire")) == "fire")
	var active: Array = ids.filter(func(id): return str(_base.spells.get(id, {}).get("kind", "")) not in ["", "passive"])
	match str(item.get("requirement", "")):
		"natural_direct_fire": return not ids.filter(func(id): return id in _runtime.direct_player_spells and str(_base.spells.get(id, {}).get("school", "fire")) == "fire").is_empty()
		"two_area_spells": return ids.filter(func(id): return id in _runtime.area_spells).size() >= int(item.required_distinct_areas)
		"any_active_spell": return not active.is_empty()
		"any_cooldown_spell": return not active.is_empty()
		"synergy_and_player_offense": return fire_ids.size() >= int(_base.fire_synergy.distinct_spells) and not offensive.is_empty()
		"spirit_and_player_offense": return "F04" in ids and not all_offensive.is_empty()
		"persistent_area_spell":
			return not ids.filter(func(id): return id in _runtime.persistent_spells).is_empty() or int(levels.get("F03", 0)) >= int(_runtime.persistent_rain_level)
		"any_igniter": return not ids.filter(func(id): return id in _runtime.igniter_spells).is_empty()
		"bomb_and_igniter": return "F07" in ids and not ids.filter(func(id): return id in _runtime.igniter_spells).is_empty()
	return str(item.get("scope", "")) == "generic"


func ice_defense_bonus(run) -> float:
	if run.get("_spell_combat") == null or run._spell_combat.get("ice") == null:
		return 0.0
	return float(run._spell_combat.ice.defense_bonus())


func ice_frost_expiry(run) -> float:
	return _ice.frost_expiry(run)


func ice_extra_frost(run, actor: Dictionary, context: Dictionary, result: Dictionary, pre_state: Dictionary, ordinal: int) -> int:
	return _ice.extra_frost(run, actor, context, result, pre_state, ordinal) if _ice != null else 0


func on_ice_window_created(run, actor: Dictionary, context: Dictionary, state: Dictionary) -> void:
	if _ice != null:
		_ice.on_window_created(run, actor, context, state)


func ice_shatter_effect(run, actor: Dictionary, context: Dictionary, info: Dictionary) -> Dictionary:
	return _ice.shatter_effect(run, actor, context, info) if _ice != null else {}


func _has_uncapped_cooldown(run) -> bool:
	var count: Dictionary = {}
	for spell in run.spells:
		if str(spell.id) == "F04": continue
		var school: String = str(_base.spells.get(str(spell.id), {}).get("school", "fire"))
		count[school] = int(count.get(school, 0)) + 1
	var active: int = 0
	for spell in run.spells:
		var definition: Dictionary = _base.spells.get(str(spell.id), {})
		if str(definition.get("kind", "")) in ["", "passive"]:
			continue
		active += 1
		var school: String = str(definition.get("school", "fire"))
		var reduction: float = get_cooldown_reduction()
		if school == "fire" and int(count.get(school, 0)) >= int(_base.fire_synergy.distinct_spells):
			reduction += float(_base.fire_synergy.cooldown_reduction)
		elif school == "ice":
			var resonance: Dictionary = _base.get("ice_mechanics", {}).get("resonance", {})
			if int(count.get(school, 0)) >= int(resonance.get("distinct_spells", 3)):
				reduction += float(resonance.get("school_cdr", 0.0))
		elif str(spell.id) != "F04" and school in ["lightning", "wind", "earth", "spirit"]:
			var resonance: Dictionary = _base.get(school + "_mechanics", {}).get("resonance", {})
			if int(count.get(school, 0)) >= int(resonance.get("distinct_spells", 3)):
				reduction += float(resonance.get("school_cdr", 0.0))
		if reduction + 0.000001 < float(_base.limits.cooldown_reduction):
			return true
	return active == 0 and get_cooldown_reduction() + 0.000001 < float(_base.limits.cooldown_reduction)


func _is_fire_context(context: Dictionary) -> bool:
	if context.has("school"):
		return str(context.school) == "fire"
	var id: String = str(context.get("spell_id", ""))
	if _base.spells.has(id):
		return str(_base.spells[id].get("school", "fire")) == "fire"
	return _items.has(id) and str(_items[id].get("scope", "")) == "fire"


func _describe(id: String) -> Dictionary:
	var item: Dictionary = _items[id].duplicate(true)
	return {"id": id, "name": item.name, "rarity": item.rarity, "scope": item.scope, "required_spell": item.get("required_spell", ""), "values": item}


func _modify_numeric(result: Dictionary, target: Dictionary, key: String, factor: float, add: float) -> void:
	if target.has(key):
		target[key] = float(target[key]) * factor + add
		result[key] = target[key]
	elif result.has(key):
		result[key] = float(result[key]) * factor + add


func _emit(run, kind: String, value: Dictionary, duration: float) -> void:
	if run.has_method("_emit"):
		run._emit(kind, value, duration)


func _resolve_refs(value: Variant, base: Dictionary) -> Variant:
	if value is Dictionary:
		if value.has("base_ref"):
			var resolved: Variant = base
			for key in str(value.base_ref).split("."):
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


func _read_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var result = JSON.parse_string(file.get_as_text())
	return result if result is Dictionary else {}
