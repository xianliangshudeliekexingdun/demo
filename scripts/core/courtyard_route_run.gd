extends "res://scripts/core/first_room_run.gd"
## Continuous authored combat route: mixed enemies, ten fire spells and treasures.
## The controller settles the authoritative clear ledger; core never writes saves.

const RouteCatalog = preload("res://scripts/core/courtyard_route_catalog.gd")
const EnemyCombat = preload("res://scripts/core/route_enemy_combat.gd")
const SpellCombat = preload("res://scripts/core/route_spell_combat.gd")
const ArtifactCombat = preload("res://scripts/core/route_artifacts.gd")
const RouteShop = preload("res://scripts/core/route_shop.gd")
const GemCombat = preload("res://scripts/core/route_gem_combat.gd")
const SpellSampling = preload("res://scripts/core/route_spell_sampling.gd")
var _spell_sampling = SpellSampling.new()
var _gem_combat = GemCombat.new()

var room_index: int = 1
var room_total: int = 0
var room_revision: int = 0
var room_time: float = 0.0
var combat_time: float = 0.0
var reward_pickup: Dictionary = {}
var reward_pickups: Array = []
var boss_rewards: Dictionary = {}
var _pickup_config: Dictionary = {}
var cleared_rooms: Array = []
var _route_catalog
var _route_rooms: Array = []
var _reward_rooms: Array = []
var _current_room: Dictionary = {}
var _packs: Array = []
var _batch_index: int = 0
var _spawned_total: int = 0
var _spawn_total: int = 0
var _transitioning: bool = false
var _enemy_combat
var _spell_combat
var _artifact_combat
var artifact_choices: Array = []
var artifact_claimed_rooms: Array = []
var _artifact_reward_rooms: Array = []
var route_school: String = "fire"
var _ice_source: Dictionary = {}
var _lightning_source: Dictionary = {}
var _wind_source: Dictionary = {}
var _earth_source: Dictionary = {}
var _spirit_source: Dictionary = {}
var pending_replacement: Dictionary = {}
var _replacement_serial: int = 0
var _reward_claimed_revision: int = -1
var gold_earned: int = 0
var gold_spent: int = 0
var _shop
var _in_shop: bool = false
var _shop_nodes: Array = []
const SpellGrowth = preload("res://scripts/core/route_spell_growth.gd")
var _growth_source: Dictionary = {}
var _progress_nodes: Array = []
var _progress_preview: Array = []


func configure(run_snapshot: Dictionary = {}, seed_value: int = 20261017) -> Dictionary:
	var result: Dictionary = super.configure(run_snapshot, seed_value)
	if not result.ok:
		return result
	_gem_combat.configure(self, run_snapshot)
	_configured = false
	var sampling_read: Dictionary = _read_json(SpellSampling.SOURCE)
	if not sampling_read.ok: return sampling_read
	var sampling_result: Dictionary = _spell_sampling.configure(sampling_read.data)
	if not sampling_result.ok: return sampling_result
	route_school = str(run_snapshot.get("route_school", "fire"))
	if route_school not in ["fire", "ice", "lightning", "wind", "earth", "spirit"]:
		return {"ok": false, "error": "本路线仅开放火、冰、雷、风、岩、灵契六系起手。"}
	var ice_read: Dictionary = _read_json("res://data/ice_spells_v1.json")
	if not ice_read.ok or not ice_read.data.get("spells") is Dictionary or not ice_read.data.get("mechanics") is Dictionary:
		return {"ok": false, "error": "正式冰系运行数据无效。"}
	_ice_source = ice_read.data.duplicate(true)
	_base.spells.merge(_ice_source.spells.duplicate(true), true)
	var lightning_read: Dictionary = _read_json("res://data/lightning_spells_v1.json")
	if not lightning_read.ok or not lightning_read.data.get("spells") is Dictionary or not lightning_read.data.get("mechanics") is Dictionary:
		return {"ok": false, "error": "正式雷系运行数据无效。"}
	_lightning_source = lightning_read.data.duplicate(true)
	for id in _lightning_source.spells:
		if _base.spells.has(id):
			return {"ok": false, "error": "正式雷系法术ID重复：" + str(id)}
	_base.spells.merge(_lightning_source.spells.duplicate(true), true)
	for school in ["wind", "earth", "spirit"]:
		var source_read: Dictionary = _read_json("res://data/" + school + "_spells_v1.json")
		if not source_read.ok or not source_read.data.get("spells") is Dictionary or not source_read.data.get("mechanics") is Dictionary:
			return {"ok": false, "error": "正式法术运行数据无效：" + school}
		var source: Dictionary = source_read.data.duplicate(true)
		for id in source.spells:
			if _base.spells.has(id):
				return {"ok": false, "error": "正式法术ID重复：" + str(id)}
		_base.spells.merge(source.spells.duplicate(true), true)
		_base[school + "_mechanics"] = source.mechanics.duplicate(true)
		set("_" + school + "_source", source)
	var growth_read: Dictionary = _read_json(SpellGrowth.SOURCE)
	if not growth_read.ok:
		return growth_read
	_growth_source = growth_read.data.duplicate(true)
	var growth_result: Dictionary = SpellGrowth.apply_source(_base.spells, _growth_source)
	if not growth_result.ok:
		return growth_result
	for id in _ice_source.spells:
		_ice_source.spells[id] = _base.spells[id].duplicate(true)
	_base["ice_mechanics"] = _ice_source.mechanics.duplicate(true)
	_base["lightning_mechanics"] = _lightning_source.mechanics.duplicate(true)
	_route_catalog = RouteCatalog.new()
	result = _route_catalog.load_catalog()
	if not result.ok:
		error = str(result.error)
		return result
	var catalog_summary: Dictionary = _route_catalog.get_summary()
	room_total = int(catalog_summary.get("active_room_count", 0))
	_reward_rooms = catalog_summary.get("reward_rooms", []).duplicate(true)
	_artifact_reward_rooms.clear()
	_pickup_config = catalog_summary.reward_pickup.duplicate(true)
	for room in catalog_summary.get("artifact_reward_rooms", []):
		_artifact_reward_rooms.append(int(room))
	_enemy_combat = EnemyCombat.new()
	result = _enemy_combat.configure(_base, _runtime, {}, room_total)
	if not result.ok:
		return result
	_spell_combat = SpellCombat.new()
	result = _spell_combat.configure(self)
	if not result.ok:
		return result
	_artifact_combat = ArtifactCombat.new()
	var artifact_read: Dictionary = _read_json(ROOT + "fire_artifacts_v1.json")
	if not artifact_read.ok:
		return artifact_read
	result = _artifact_combat.configure(_base, artifact_read.data)
	if not result.ok:
		return result
	_shop = RouteShop.new()
	result = _shop.configure(_base, _economy)
	if not result.ok:
		return result
	_shop_nodes = _shop.nodes(room_total)
	if room_total <= 0 or _reward_rooms.is_empty():
		error = "地图试玩缺少有效房间或成长节点。"
		return {"ok": false, "error": error}
	_route_rooms.clear()
	for room_id in range(1, room_total + 1):
		var definition: Dictionary = _route_catalog.get_room(room_id)
		var encounter: Dictionary = definition.get("encounter", {})
		if definition.is_empty() or not encounter.get("packs") is Array or encounter.packs.is_empty() or encounter.packs.size() > int(definition.max_batches):
			error = "地图试玩遭遇无效：第%d房。" % room_id
			return {"ok": false, "error": error}
		for pack in encounter.packs:
			var count := 0
			if not pack is Dictionary:
				return {"ok": false, "error": "怪物批次必须按类型配置。"}
			for type_id in pack:
				if _enemy_combat.type_spec(str(type_id), room_id).is_empty() or float(pack[type_id]) != float(int(pack[type_id])) or int(pack[type_id]) <= 0:
					return {"ok": false, "error": "怪物类型或数量无效。"}
				count += int(pack[type_id])
			if count <= 0 or count > int(definition.alive_cap):
				error = "地图试玩批次数量无效：第%d房。" % room_id
				return {"ok": false, "error": error}
		_route_rooms.append(definition)
	_progress_nodes.clear()
	for room in _route_rooms:
		_progress_nodes.append({"room_id": int(room.room_id), "kind": str(room.kind), "is_shop": false})
		if int(room.room_id) in _shop_nodes:
			_progress_nodes.append({"room_id": int(room.room_id), "kind": "shop", "is_shop": true})
	cleared_rooms.clear()
	artifact_claimed_rooms.clear()
	artifact_choices.clear()
	pending_replacement.clear()
	_reward_claimed_revision = -1
	room_revision = 0
	combat_time = 0.0
	gold_earned = gold
	gold_spent = 0
	reward_pickup.clear()
	_transitioning = false
	_configured = true
	_enter_room(1, true)
	error = ""
	return {"ok": true, "error": ""}


func get_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_snapshot()
	snapshot.merge(_route_metadata(), true)
	if _enemy_combat != null:
		snapshot["enemy_projectiles"] = _enemy_combat.get_projectiles()
	if _spell_combat != null:
		snapshot.merge(_spell_combat.get_snapshot(), true)
	snapshot["artifacts"] = _artifact_combat.owned_snapshot() if _artifact_combat != null else []
	snapshot["artifact_patches"] = _artifact_combat.state_snapshot().patches if _artifact_combat != null else []
	if _spell_combat != null:
		snapshot.artifact_patches.append_array(_spell_combat.growth.patches.duplicate(true))
	snapshot["generic_items"] = _artifact_combat.state_snapshot().generic if _artifact_combat != null else {}
	snapshot["combat_stats"] = _artifact_combat.combat_stats(self) if _artifact_combat != null else {}
	if _artifact_combat != null and _spell_combat != null:
		snapshot.combat_stats["fire_crit_rate"] = float(player.crit_rate) + _artifact_combat.fire_crit_rate_bonus() + _spell_combat.crit_rate_bonus()
		snapshot.combat_stats["fire_crit_multiplier"] = float(player.crit_multiplier) + _spell_combat.crit_multiplier_bonus() + float(snapshot.combat_stats.get("crit_multiplier_add", 0.0))
		snapshot.combat_stats["fire_bonus"] = _fire_damage_bonus()
		snapshot.combat_stats["formal_fire_count"] = _spell_combat.fire_spell_count(self)
		snapshot.combat_stats["fire_synergy_active"] = _spell_combat.fire_spell_count(self) >= int(_base.fire_synergy.distinct_spells)
		snapshot.combat_stats["fire_cooldown_reduction"] = minf(float(_base.limits.cooldown_reduction), artifact_cooldown_reduction() + (float(_base.fire_synergy.cooldown_reduction) if snapshot.combat_stats.fire_synergy_active else 0.0))
		snapshot.combat_stats["ice_bonus"] = _spell_combat.ice.school_bonus(self)
		snapshot.combat_stats["formal_ice_count"] = _spell_combat.ice.spell_count(self)
		snapshot.combat_stats["ice_synergy_active"] = _spell_combat.ice.spell_count(self) >= int(_base.ice_mechanics.resonance.distinct_spells)
		snapshot.combat_stats["ice_cooldown_reduction"] = minf(float(_base.limits.cooldown_reduction), artifact_cooldown_reduction() + _spell_combat.ice.cooldown_bonus(self))
		snapshot.combat_stats["ice_defense"] = _spell_combat.ice.defense_bonus()
		snapshot.combat_stats["ice_crit_rate"] = float(player.crit_rate)
		snapshot.combat_stats["ice_crit_multiplier"] = float(player.crit_multiplier) + float(snapshot.combat_stats.get("crit_multiplier_add", 0.0))
		snapshot.combat_stats["lightning_bonus"] = _spell_combat.lightning.school_bonus(self)
		snapshot.combat_stats["formal_lightning_count"] = _spell_combat.lightning.spell_count(self)
		snapshot.combat_stats["lightning_synergy_active"] = _spell_combat.lightning.spell_count(self) >= int(_base.lightning_mechanics.resonance.distinct_spells)
		snapshot.combat_stats["lightning_cooldown_reduction"] = minf(float(_base.limits.cooldown_reduction), artifact_cooldown_reduction() + _spell_combat.lightning.cooldown_bonus(self))
		snapshot.combat_stats["lightning_crit_rate"] = float(player.crit_rate)
		snapshot.combat_stats["lightning_crit_multiplier"] = float(player.crit_multiplier) + float(snapshot.combat_stats.get("crit_multiplier_add", 0.0))
	if _spell_combat != null:
		for school in ["wind", "earth", "spirit"]:
			var module = _spell_combat.school_module(school)
			var count: int = module.spell_count(self)
			snapshot.combat_stats[school + "_bonus"] = module.school_bonus(self)
			snapshot.combat_stats["formal_" + school + "_count"] = count
			snapshot.combat_stats[school + "_synergy_active"] = count >= int(_base[school + "_mechanics"].resonance.distinct_spells)
			snapshot.combat_stats[school + "_cooldown_reduction"] = minf(float(_base.limits.cooldown_reduction), artifact_cooldown_reduction() + module.cooldown_bonus(self))
		snapshot.combat_stats["earth_defense"] = _spell_combat.earth.defense_bonus(self)
	snapshot["artifact_choices"] = artifact_choices.duplicate(true)
	snapshot["artifact_claimed_rooms"] = artifact_claimed_rooms.duplicate()
	snapshot["reward_pickup"] = reward_pickup.duplicate(true)
	snapshot["reward_pickups"] = reward_pickups.duplicate(true)
	snapshot["boss_rewards"] = boss_rewards.duplicate(true)
	if _enemy_combat != null:
		snapshot.spawn_warnings.append_array(_enemy_combat.bosses.summon_warnings.duplicate(true))
	snapshot["combat_time"] = combat_time
	snapshot["initial_choices"] = initial_choices()
	snapshot["pending_replacement"] = pending_replacement.duplicate(true)
	snapshot["can_skip_spell_reward"] = can_skip_spell_reward()
	snapshot["shop"] = _shop.snapshot() if _shop != null else {}
	snapshot["gold_earned"] = gold_earned
	snapshot["gold_spent"] = gold_spent
	snapshot["gems"] = _gem_combat.snapshot()
	return snapshot


func get_summary() -> Dictionary:
	var summary: Dictionary = super.get_summary()
	summary.merge(_route_metadata(), true)
	summary["cleared_rooms"] = cleared_rooms.duplicate()
	summary["clear_count"] = cleared_rooms.size()
	summary["artifacts"] = _artifact_combat.owned_snapshot() if _artifact_combat != null else []
	summary["artifact_claimed_rooms"] = artifact_claimed_rooms.duplicate()
	summary["combat_time"] = combat_time
	summary["gold_earned"] = gold_earned
	summary["gold_spent"] = gold_spent
	summary["shops"] = _shop.summary() if _shop != null else []
	return summary


func eligible_reward_ids() -> Array:
	var result: Array = []
	for id in _base.spells:
		if not bool(_base.spells[id].get("active", true)):
			continue
		var owned: Dictionary = _owned_spell(str(id))
		var requirements: Array = _base.spells[id].get("required_any_spells", [])
		if owned.is_empty() and not requirements.is_empty():
			var eligible: bool = false
			for source_id in requirements:
				if not _owned_spell(str(source_id)).is_empty(): eligible = true
			if not eligible: continue
		if owned.is_empty() or int(owned.level) < int(_base.limits.spell_level):
			result.append(id)
	return result


func _sampling_ownership() -> Dictionary:
	var result: Dictionary = {}
	for spell in spells: result[str(spell.id)] = int(spell.level)
	return result


func _sampling_catalyst() -> Dictionary:
	var id: String = str(_equipment.get("equipment", {}).get("catalyst", ""))
	var level: int = int(_equipment.get("levels", {}).get(id, 0))
	if not _meta.catalysts.has(id) or level < 1 or level > 3: return {"school": "", "level": 0}
	return {"school": str(_meta.catalysts[id].school), "level": level}


func reward_probabilities() -> Dictionary:
	if _spell_sampling.rules.is_empty(): return {}
	var catalyst: Dictionary = _sampling_catalyst()
	return _spell_sampling.probabilities(eligible_reward_ids(), _base.spells, _sampling_ownership(), catalyst.school, catalyst.level)


func reward_weight(spell_id: String) -> float:
	if _spell_sampling.rules.is_empty(): return super.reward_weight(spell_id)
	var chances: Dictionary = reward_probabilities()
	# A relative weight with mean one, for compatibility with offer metadata.
	# Actual drawing recalculates the full conditional probability after removal.
	return float(chances.get(spell_id, 0.0)) * chances.size()


func _sample_rewards() -> Array:
	var catalyst: Dictionary = _sampling_catalyst()
	var drawn: Array = _spell_sampling.sample(eligible_reward_ids(), _base.spells, _sampling_ownership(), catalyst.school, catalyst.level, _rng)
	var result: Array = []
	for entry in drawn:
		var choice: Dictionary = _choice(str(entry.id))
		choice["draw_probability"] = float(entry.draw_probability)
		choice["sampling_version"] = str(_spell_sampling.rules.version)
		result.append(choice)
	return result


func choose_reward(spell_id: String, expected_room_revision: int = -1) -> bool:
	if not _reward_request_valid(expected_room_revision) or not pending_replacement.is_empty():
		return false
	var offered: Dictionary = {}
	for choice in reward_choices:
		if str(choice.get("id", "")) == spell_id:
			offered = choice
			break
	if offered.is_empty() or spell_id not in eligible_reward_ids():
		return false
	var owned: Dictionary = _owned_spell(spell_id)
	if owned.is_empty() and spells.size() >= int(_base.limits.slots):
		if spells.size() != int(_base.limits.slots):
			return false
		_replacement_serial += 1
		pending_replacement = {"request_id": _replacement_serial, "room_revision": room_revision,
			"room_index": room_index, "spell_id": spell_id, "choice": offered.duplicate(true),
			"slots": spells.duplicate(true)}
		portal.usable = false
		_accumulator = 0.0
		_emit("replacement_requested", {"pos": player.pos, "spell_id": spell_id, "request_id": _replacement_serial}, 0.5)
		return true
	if owned.is_empty():
		spells.append(_new_spell(spell_id))
	else:
		owned.level += 1
		_refresh_spell(owned)
	_refresh_reward_spell_parameters()
	_complete_spell_reward(spell_id)
	return true


func confirm_spell_replacement(slot_index: int, request_id: int, expected_room_revision: int = -1) -> bool:
	if not _replacement_request_valid(request_id, expected_room_revision):
		return false
	if slot_index < 0 or slot_index >= spells.size() or spells.size() != int(_base.limits.slots):
		return false
	# Validate the entire original inventory before removing anything. A stale
	# modal cannot replace a different spell after an intervening mutation.
	if spells != pending_replacement.slots:
		return false
	var spell_id: String = str(pending_replacement.spell_id)
	if not _owned_spell(spell_id).is_empty() or spell_id not in eligible_reward_ids():
		return false
	var offered: bool = false
	for choice in reward_choices:
		if str(choice.get("id", "")) == spell_id:
			offered = true
			break
	if not offered:
		return false
	var old_id: String = str(spells[slot_index].id)
	var replacement: Dictionary = _new_spell(spell_id)
	spells[slot_index] = replacement
	_refresh_reward_spell_parameters()
	_complete_spell_reward(spell_id, old_id, slot_index)
	return true


func cancel_spell_replacement(request_id: int, expected_room_revision: int = -1) -> bool:
	if not _replacement_request_valid(request_id, expected_room_revision):
		return false
	pending_replacement.clear()
	portal.usable = false
	_accumulator = 0.0
	return true


func can_skip_spell_reward() -> bool:
	if not _reward_request_valid(-1) or not pending_replacement.is_empty() or spells.size() != int(_base.limits.slots) or reward_choices.is_empty():
		return false
	var eligible: Array = eligible_reward_ids()
	for choice in reward_choices:
		var id: String = str(choice.get("id", ""))
		if id not in eligible or not _owned_spell(id).is_empty():
			return false
	return true


func skip_spell_reward(expected_room_revision: int = -1) -> bool:
	if not _reward_request_valid(expected_room_revision) or not can_skip_spell_reward():
		return false
	_complete_spell_reward("", "", -1, true)
	return true


func _reward_request_valid(expected_room_revision: int) -> bool:
	return _configured and phase == "reward" and not paused and float(player.get("health", 0.0)) > 0.0 and _reward_claimed_revision != room_revision and (expected_room_revision == -1 or expected_room_revision == room_revision)


func _replacement_request_valid(request_id: int, expected_room_revision: int) -> bool:
	return _reward_request_valid(expected_room_revision) and not pending_replacement.is_empty() and int(pending_replacement.get("request_id", -1)) == request_id and int(pending_replacement.get("room_revision", -1)) == room_revision and int(pending_replacement.get("room_index", -1)) == room_index


func _refresh_reward_spell_parameters() -> void:
	for spell in spells:
		var stats: Dictionary = get_spell_stats(spell)
		var base_cd: float = float(stats.level.get("cooldown", stats.get("cooldown", 0.0)))
		var reduction: float = artifact_cooldown_reduction()
		if _spell_combat.is_fire_spell(str(spell.id)) and _spell_combat.fire_spell_count(self) >= int(_base.fire_synergy.distinct_spells):
			reduction += float(_base.fire_synergy.cooldown_reduction)
		elif _spell_combat.ice.is_ice_spell(str(spell.id)):
			reduction += _spell_combat.ice.cooldown_bonus(self)
		else:
			var module = _spell_combat.spell_module(str(spell.id), str(stats.get("school", "")))
			if module != null: reduction += module.cooldown_bonus(self)
		reduction = _gem_combat.cooldown_reduction(reduction)
		spell.cooldown = maxf(float(_base.limits.minimum_cooldown), base_cd * (1.0 - minf(reduction, float(_base.limits.cooldown_reduction)))) if base_cd > 0.0 else 0.0
		spell.windup = float(stats.get("windup", 0.0))
		spell.range = float(stats.level.get("range", stats.get("range", 0.0)))


func _complete_spell_reward(spell_id: String, old_id: String = "", slot_index: int = -1, skipped: bool = false) -> void:
	_selected_reward = spell_id
	_reward_claimed_revision = room_revision
	pending_replacement.clear()
	reward_choices.clear()
	phase = "exit"
	portal.usable = true
	if not boss_rewards.is_empty():
		_resolve_boss_book()
	_accumulator = 0.0
	_emit("reward_skipped" if skipped else "reward", {"pos": player.pos, "spell_id": spell_id, "replaced_spell_id": old_id, "slot_index": slot_index, "room_index": room_index}, 0.8)


func _initial_spell_ids() -> Array:
	if route_school == "ice":
		return _spell_combat.ice.mechanics.initial_ids
	var module = _spell_combat.school_module(route_school)
	if module != null:
		return module.mechanics.initial_ids
	return _spell_combat.runtime.fire.initial_ids


func initial_choices() -> Array:
	var result: Array = []
	if not _configured or _spell_combat == null:
		return result
	var ids: Array = _initial_spell_ids()
	for id in ids:
		var choice: Dictionary = _choice(str(id), true)
		choice.weight = float(_meta.spell_sampling_assumptions.baseline_spell_weight)
		result.append(choice)
	return result


func choose_initial(spell_id: String) -> bool:
	if not _configured or paused or phase != "choosing":
		return false
	var ids: Array = _initial_spell_ids()
	if spell_id not in ids:
		return false
	spells.append(_new_spell(spell_id))
	phase = "combat"
	_reserve_batch()
	return true


func step(delta: float, move: Vector2 = Vector2.ZERO):
	if not _configured or paused or phase not in ["combat", "pickup", "reward", "artifact", "exit", "shop", "shopping"]:
		_accumulator = 0.0
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	_accumulator += minf(delta, 0.1)
	while _accumulator + 0.000000001 >= FIXED_STEP:
		_accumulator -= FIXED_STEP
		_tick(FIXED_STEP, move.limit_length())
		if phase not in ["combat", "pickup", "reward", "artifact", "exit", "shop", "shopping"]:
			_accumulator = 0.0
			break


func choose_artifact(artifact_id: String) -> bool:
	if phase != "artifact" or paused or _artifact_combat == null or room_index in artifact_claimed_rooms:
		return false
	if not _artifact_combat.choose(artifact_id, self):
		return false
	artifact_claimed_rooms.append(room_index)
	artifact_choices.clear()
	phase = "exit"
	portal.usable = true
	if not boss_rewards.is_empty():
		boss_rewards.chest_resolved = true
		portal.usable = bool(boss_rewards.book_resolved)
	_emit("artifact_acquired", {"pos": player.pos, "artifact_id": artifact_id}, 0.8)
	return true


func _route_metadata() -> Dictionary:
	return {
		"scope": "early_route_map_trial", "account_rewards": not bool(_equipment.get("preview_only", true)),
		"route_school": route_school,
		"preview_only": bool(_equipment.get("preview_only", true)), "room_index": room_index, "room_total": room_total,
		"room_name": str(_current_room.get("name", "")), "room_revision": room_revision,
		"difficulty_band": _current_room.get("difficulty_band", {}).duplicate(true),
		"room_time": room_time, "room_geometry": _current_room.get("geometry", {}).duplicate(true),
		"template_id": str(_current_room.get("template_id", "")),
		"source_kind": str(_current_room.get("source_kind", _current_room.get("kind", "normal"))),
		"spawn_total": _spawn_total, "spawned_total": _spawned_total,
		"batch_index": _batch_index, "batch_count": _packs.size(),
		"pending_batch_index": _batch_index + 1 if _batch_index < _packs.size() else 0,
		"all_batches_spawned": _spawn_done, "cleared_rooms": cleared_rooms.duplicate(),
		"theme_id": str(_current_room.get("theme_id", "")),
		"landmark": str(_current_room.get("landmark", "")),
		"spike_profile": "off", "shop_after": not _in_shop and room_index in _shop_nodes,
		"in_shop": _in_shop, "shop_nodes": _shop_nodes.duplicate(),
		"room_progress": _progress_preview.duplicate(true),
		"encounter_kind": str(_current_room.get("encounter", {}).get("kind", "normal")),
		"alive_cap": int(_current_room.get("alive_cap", 0)),
		"max_batches": int(_current_room.get("max_batches", 0)),
		"nonboss": bool(_current_room.get("nonboss", false)),
		"role_limits": _current_room.get("role_limits", {}).duplicate(true),
		"artifact_reward_rooms": _artifact_reward_rooms.duplicate(),
	}


func _enter_room(next_room: int, initial: bool = false) -> void:
	_in_shop = false
	if _shop != null:
		_shop.leave()
	room_index = next_room
	room_revision += 1
	room_time = 0.0
	_current_room = _route_rooms[room_index - 1].duplicate(true)
	var geometry: Dictionary = _current_room.geometry
	_runtime["room"] = geometry.duplicate(true)
	room_size = Vector2(geometry.floor.width, geometry.floor.depth)
	blocks.clear()
	for block in geometry.blocks:
		blocks.append({"center": Vector2(block.center[0], block.center[1]), "size": Vector2(block.size[0], block.size[1])})
	_stop_combat()
	actors.clear()
	effects.clear()
	reward_choices.clear()
	artifact_choices.clear()
	pending_replacement.clear()
	reward_pickup.clear()
	reward_pickups.clear()
	boss_rewards.clear()
	var entry: Array = geometry.entry_player_center
	player.pos = Vector2(entry[0], entry[1])
	player.previous = player.pos
	player.face = Vector2(0, 1)
	player.invulnerable = 0.0
	spirit = {"active": false, "remaining": 0.0, "pos": player.pos, "attack_remaining": 0.0}
	var destination: Array = geometry.portal_center
	portal = {"pos": Vector2(destination[0], destination[1]), "radius": float(_runtime.portal_trigger_radius), "visible": false, "usable": false}
	_packs = _current_room.encounter.packs.duplicate(true)
	_batch_index = 0
	_spawned_total = 0
	_spawn_total = 0
	for pack in _packs:
		_spawn_total += _pack_count(pack)
	_spawn_count = _pack_count(_packs[0])
	_spawn_done = false
	phase = "choosing" if initial else "combat"
	if not initial:
		_reserve_batch()
	_refresh_progress_preview()


func _enter_shop() -> void:
	_in_shop = true
	room_revision += 1
	room_time = 0.0
	_stop_combat()
	actors.clear()
	effects.clear()
	reward_choices.clear()
	artifact_choices.clear()
	pending_replacement.clear()
	reward_pickup.clear()
	reward_pickups.clear()
	boss_rewards.clear()
	_shop.enter(room_index)
	var geometry: Dictionary = _shop.config.geometry.duplicate(true)
	_current_room = {"name": str(_shop.config.name) + " · 第%d房后" % room_index,
		"template_id": "SHOP_COURTYARD", "source_kind": "shop", "encounter": {"kind": "shop"},
		"geometry": geometry, "difficulty_band": _route_rooms[room_index - 1].difficulty_band.duplicate(true)}
	_runtime.room = geometry.duplicate(true)
	room_size = Vector2(geometry.floor.width, geometry.floor.depth)
	blocks.clear()
	for block in geometry.blocks:
		blocks.append({"center": Vector2(block.center[0], block.center[1]), "size": Vector2(block.size[0], block.size[1])})
	player.pos = Vector2(geometry.entry_player_center[0], geometry.entry_player_center[1])
	player.previous = player.pos
	player.face = Vector2(0, 1)
	player.invulnerable = 0.0
	portal = {"pos": Vector2(geometry.portal_center[0], geometry.portal_center[1]), "radius": float(_runtime.portal_trigger_radius), "visible": true, "usable": true}
	_packs.clear()
	_batch_index = 0
	_spawned_total = 0
	_spawn_total = 0
	_spawn_done = true
	phase = "shop"
	_accumulator = 0.0
	_refresh_progress_preview()


func _refresh_progress_preview() -> void:
	var current: int = 0
	for index in _progress_nodes.size():
		if int(_progress_nodes[index].room_id) == room_index and bool(_progress_nodes[index].is_shop) == _in_shop:
			current = index
			break
	var start: int = mini(current, maxi(0, _progress_nodes.size() - 3))
	_progress_preview.clear()
	for index in range(start, mini(start + 3, _progress_nodes.size())):
		var node: Dictionary = _progress_nodes[index].duplicate(true)
		node["state"] = "done" if index < current else "current" if index == current else "pending"
		_progress_preview.append(node)


func buy_shop_item(id: String, expected_room_revision: int) -> bool:
	return _configured and _in_shop and expected_room_revision == room_revision and _shop.buy(self, id)


func close_shop(expected_room_revision: int) -> bool:
	return _configured and _in_shop and expected_room_revision == room_revision and _shop.close(self)


func _tick(dt: float, move: Vector2):
	var previous_time: float = time
	if phase == "combat":
		_gem_combat.advance(dt, self)
		var speed := float(player.move_speed)
		if _artifact_combat != null:
			_artifact_combat.before_combat_tick(self, dt, move)
			player.move_speed = speed * _artifact_combat.move_speed_multiplier(self)
		super._tick(dt, move)
		player.move_speed = speed
		combat_time += time - previous_time
	else:
		# The route clock includes travel and reward decisions. Enemies, spells
		# and their cooldowns stay inactive once combat ends.
		time += dt
		if phase in ["pickup", "exit", "shop"]:
			_fade_effects(dt)
			player.previous = player.pos
			player.pos = move_body(player.pos, move * player.move_speed * dt, player.radius)
			if move.length_squared() > 0.00001:
				player.face = move
			if phase == "pickup":
				_try_pickup(player.previous, player.pos)
			elif phase == "shop":
				_shop.try_contact(self, player.previous, player.pos)
				if phase == "shop" and portal.usable and move.length_squared() > 0.00001 and player.pos.distance_to(portal.pos) <= float(portal.radius):
					phase = "complete"
					portal.usable = false
			elif portal.usable and move.length_squared() > 0.00001 and player.pos.distance_to(portal.pos) <= float(portal.radius):
				phase = "complete"
				portal.usable = false
				_emit("complete", {"pos": portal.pos}, 1.0)
	room_time += time - previous_time
	if phase != "complete" or _transitioning:
		return
	# Base movement owns the actual portal contact. A transition is consumed once;
	# the next room starts in combat with a hidden, locked portal.
	if room_index < room_total:
		_transitioning = true
		if not _in_shop and room_index in _shop_nodes:
			_enter_shop()
		else:
			_enter_room(room_index + 1)
		_transitioning = false


func _try_pickup(from: Vector2, to: Vector2) -> void:
	if phase != "pickup" or not bool(reward_pickup.get("visible", false)) or bool(reward_pickup.get("claimed", false)):
		return
	var center: Vector2 = reward_pickup.pos
	var radius: float = float(reward_pickup.radius) + float(player.radius)
	if segment_circle_time(from, to, center, radius) == INF:
		return
	reward_pickup.visible = false
	reward_pickup.claimed = true
	phase = "artifact" if reward_pickup.kind == "artifact" else "reward"
	_accumulator = 0.0
	_emit("reward_touched", {"pos": center, "reward_kind": reward_pickup.kind, "room_index": room_index}, 0.5)


func _spawn_reward_pickup(kind: String) -> void:
	reward_pickup = {"kind": kind, "pos": portal.pos + Vector2(0.0, float(_pickup_config.portal_z_offset)),
		"radius": float(_pickup_config.radius), "visible": true, "claimed": false}
	phase = "pickup"
	portal.usable = false


func _spawn_boss_rewards() -> void:
	var offsets: Array = _enemy_combat.bosses.catalog.data.reward.pickup_x_offsets
	boss_rewards = {"book_resolved": false, "chest_resolved": false}
	reward_pickups.clear()
	for index in 2:
		reward_pickups.append({"kind": "spell" if index == 0 else "artifact",
			"pos": portal.pos + Vector2(float(offsets[index]), float(_pickup_config.portal_z_offset)),
			"radius": float(_pickup_config.radius), "visible": true, "claimed": false,
			"locked": index == 1, "gold_only": index == 1})
	reward_choices = _sample_rewards()
	reward_pickup = reward_pickups[0]
	phase = "pickup"
	portal.usable = false
	if reward_choices.is_empty():
		_resolve_boss_book()


func _resolve_boss_book() -> void:
	if boss_rewards.is_empty() or bool(boss_rewards.book_resolved):
		return
	boss_rewards.book_resolved = true
	reward_pickups[0].visible = false
	reward_pickups[0].claimed = true
	reward_pickups[1].locked = false
	# Eligibility uses the newly chosen/upgraded/replaced spell inventory.
	artifact_choices = _artifact_combat.sample_boss_choices(self, _rng)
	reward_pickup = reward_pickups[1]
	phase = "pickup"
	portal.usable = false


func _update_spawn(dt: float):
	if _spawn_done:
		return
	if spawn_warnings.is_empty():
		_reserve_batch()
		return
	for warning in spawn_warnings:
		warning.remaining = maxf(0.0, float(warning.remaining) - dt)
	if float(spawn_warnings[0].remaining) > 0.000001:
		return
	if not _batch_fits_role_caps(_packs[_batch_index]):
		spawn_warnings.clear()
		return
	var checked: Array = []
	for warning in spawn_warnings:
		if not _valid_typed_spawn(warning.pos, float(warning.radius), checked):
			spawn_warnings.clear()
			_reserve_batch()
			return
		checked.append(warning)
	for warning in spawn_warnings:
		var enemy: Dictionary = _enemy_combat.make_actor(self, str(warning.type_id), warning.pos, _next_actor_id)
		_next_actor_id += 1
		enemy.lock_remaining = float(enemy.combat_spec.get("body_spawn_grace", _spatial.spawn.attack_lock_after_appearance))
		actors.append(enemy)
		_spawned_total += 1
		_emit("spawn", {"pos": enemy.pos, "actor_id": enemy.id, "elite": enemy.elite}, 0.5)
	spawn_warnings.clear()
	_batch_index += 1
	_spawn_done = _batch_index >= _packs.size()


func _reserve_batch():
	if _batch_index >= _packs.size():
		_spawn_done = true
		return
	var alive: int = 0
	for enemy in actors:
		if enemy.health > 0.0:
			alive += 1
	var pack: Dictionary = _packs[_batch_index]
	var count: int = _pack_count(pack)
	var cap: int = int(_current_room.alive_cap)
	var survivor_limit := int(_current_room.get("spawn_rules", {}).get("max_survivors_before_next_wave", _ordinary.spawn.next_batch_when_alive_at_most))
	if _batch_index > 0 and (alive > survivor_limit or alive + count > cap):
		return
	if not _batch_fits_role_caps(pack):
		return
	_spawn_count = count
	var candidates: Array = []
	var boss_definition: Dictionary = _enemy_combat.bosses.catalog.for_room(room_index)
	var spawn_points: Array = _runtime.room.spawn.north_band if boss_definition.is_empty() else [_enemy_combat.bosses.catalog.data.global.spawn]
	for entry in spawn_points:
		candidates.append(Vector2(float(entry[0]), float(entry[1])))
	for i in range(candidates.size() - 1, 0, -1):
		var other := _rng.randi_range(0, i)
		var point: Vector2 = candidates[i]
		candidates[i] = candidates[other]
		candidates[other] = point
	var selected: Array = []
	for type_id in pack:
		var spec: Dictionary = _enemy_combat.type_spec(str(type_id), room_index)
		for unit in range(int(pack[type_id])):
			var found := false
			for point in candidates:
				if _valid_typed_spawn(point, float(spec.radius), selected):
					selected.append({"pos": point, "radius": float(spec.radius), "type_id": str(type_id), "elite": bool(spec.get("elite", false))})
					found = true
					break
			if not found:
				return
	var duration := float(_current_room.get("spawn_rules", {}).get("preview_seconds", _ordinary.spawn.preview_seconds))
	if not boss_definition.is_empty():
		duration = float(_enemy_combat.bosses.catalog.data.global.spawn_preview)
	for warning in selected:
		warning["remaining"] = duration
		warning["duration"] = duration
		spawn_warnings.append(warning)


func _batch_fits_role_caps(pack: Dictionary) -> bool:
	var limits: Dictionary = _current_room.get("role_limits", {})
	if limits.is_empty():
		return true
	var counts := {"ranged": 0, "ring": 0, "sweep": 0, "heavy": 0}
	var alive := 0
	for enemy in actors:
		if float(enemy.health) <= 0.0:
			continue
		alive += 1
		for role in enemy.get("combat_spec", {}).get("roles", []):
			counts[role] += 1
	if alive + _pack_count(pack) > int(limits.alive_cap):
		return false
	if _batch_index > 0 and alive > int(_current_room.spawn_rules.max_survivors_before_next_wave):
		return false
	for type_id in pack:
		var spec: Dictionary = _enemy_combat.type_spec(str(type_id), room_index)
		for role in spec.get("roles", []):
			counts[role] += int(pack[type_id])
	for role in counts:
		if int(counts[role]) > int(limits[str(role) + "_alive_cap"]):
			return false
	return true


func _pack_count(pack: Dictionary) -> int:
	var count := 0
	for value in pack.values():
		count += int(value)
	return count


func _valid_typed_spawn(pos: Vector2, radius: float, selected: Array) -> bool:
	var safe_distance := float(_current_room.get("spawn_rules", {}).get("safe_player_distance", _ordinary.spawn.safe_player_distance))
	if pos.distance_to(player.pos) < safe_distance or not _body_clear(pos, radius + float(_spatial.spawn.static_clearance)):
		return false
	for warning in selected:
		if pos.distance_to(warning.pos) < maxf(float(_spatial.spawn.minimum_slot_spacing), radius + float(warning.radius)) - 0.000001:
			return false
	for enemy in actors:
		if enemy.health > 0.0 and pos.distance_to(enemy.pos) < radius + float(enemy.radius) + float(_spatial.spawn.existing_enemy_clearance):
			return false
	return true


func _check_clear():
	if _enemy_combat != null:
		for actor in actors:
			if bool(actor.get("boss", false)):
				_enemy_combat.bosses.sync_health(_enemy_combat, self, actor)
	if phase != "combat" or not _spawn_done or not spawn_warnings.is_empty() or player.health <= 0.0 or room_index in cleared_rooms:
		return
	for enemy in actors:
		if enemy.health > 0.0:
			return
	cleared_rooms.append(room_index)
	clear_count = cleared_rooms.size()
	# Boss conversion preserves the previously approved milestone coin income.
	for stage in _economy.stages:
		if room_index >= int(stage.from) and room_index <= int(stage.to):
			var income: int = int(stage.clear_gold)
			if str(_current_room.encounter.kind) in ["elite", "elite_guard", "boss"]:
				income += int(stage.elite_bonus)
			gold += income
			gold_earned += income
			break
	if _artifact_combat != null:
		_artifact_combat.on_room_cleared(self)
	player.shield = player.max_shield
	_stop_combat()
	portal.visible = true
	portal.usable = false
	reward_choices.clear()
	artifact_choices.clear()
	if str(_current_room.encounter.kind) == "boss":
		_spawn_boss_rewards()
		_emit("clear", {"pos": portal.pos, "room_index": room_index}, 1.0)
		return
	if room_index in _artifact_reward_rooms:
		artifact_choices = _artifact_combat.sample_choices(self, _rng)
		if not artifact_choices.is_empty():
			_spawn_reward_pickup("artifact")
		else:
			phase = "exit"
		portal.usable = artifact_choices.is_empty()
		_emit("clear", {"pos": portal.pos, "room_index": room_index}, 1.0)
		return
	for reward_room in _reward_rooms:
		if int(reward_room) == room_index:
			reward_choices = _sample_rewards()
			break
	if not reward_choices.is_empty():
		_spawn_reward_pickup("spell")
	else:
		phase = "exit"
	portal.usable = reward_choices.is_empty()
	_emit("clear", {"pos": portal.pos, "gold": gold, "dust": dust, "room_index": room_index}, 1.0)


func _update_enemies(dt: float):
	advance_ice_control(dt)
	_spell_combat.earth.after_player_motion(self)
	_spell_combat.wind.record_player_motion(self, player.previous, player.pos, dt)
	_enemy_combat.update(self, dt)


func advance_ice_control(dt: float) -> void:
	if _spell_combat != null and _spell_combat.ice != null:
		_spell_combat.ice.before_tick(self, dt)
		for module in _spell_combat.school_modules(): module.before_tick(self, dt)


func get_ice_control_state(actor: Dictionary) -> Dictionary:
	if _spell_combat == null or _spell_combat.ice == null:
		return {}
	var status = _spell_combat.ice.status
	var hard_control: bool = _spell_combat.earth.actor_stunned(actor)
	var movement: float = _spell_combat.wind.movement_multiplier(actor)
	return {"frozen": status.is_frozen(int(actor.id)) or hard_control, "frozen_time": status.frozen_frame_time(int(actor.id)), "slow": maxf(status.slow_amount(actor), 1.0 - movement)}


func _update_spells(dt: float):
	_gem_combat.before_spells(self)
	_spell_combat.before_damage_tick(self, dt)
	_artifact_combat.update(self, dt)
	_spell_combat.update(self, dt)


func _update_projectiles(_dt: float):
	pass # Owned once by RouteSpellCombat.


func _update_spirit(_dt: float):
	pass


func _stop_combat():
	super._stop_combat()
	if _enemy_combat != null:
		_enemy_combat.clear()
	if _spell_combat != null:
		_spell_combat.stop_room()
	if _artifact_combat != null:
		_artifact_combat.reset_room()
	_gem_combat.reset_room()


func get_spell_stats(spell: Dictionary) -> Dictionary:
	var stats: Dictionary = _base.spells[spell.id].duplicate(true)
	stats["level"] = stats.levels[int(spell.level) - 1].duplicate(true)
	stats.merge(stats.level, true)
	return _artifact_combat.modify_spell_stats(str(spell.id), stats, int(spell.level)) if _artifact_combat != null else stats


func resolve_spell_hit(actor: Dictionary, coefficient: float, context: Dictionary) -> Dictionary:
	if actor.health <= 0.0 or phase != "combat" or paused:
		return {"damage": 0.0, "critical": false}
	var old_burn: int = _spell_combat.fire_status.burn_token(self, actor) if gem_core() == "inferno" else -1
	var artifact_bonus: Dictionary = _artifact_combat.modify_damage_context(self, actor, context)
	var fire: bool = _is_fire_damage(context)
	var rate := maxf(0.0, float(player.crit_rate) + (_artifact_combat.fire_crit_rate_bonus() + _spell_combat.crit_rate_bonus() if fire else 0.0))
	var roll := _rng.randf()
	var critical := rate >= 1.0 or roll < rate
	var multiplier: float = float(player.crit_multiplier) + (_spell_combat.crit_multiplier_bonus() if fire else 0.0) + float(context.get("crit_multiplier_bonus", 0.0)) + float(artifact_bonus.get("crit_multiplier_add", 0.0))
	var field: float = _spell_combat.field_attack_bonus() if str(context.get("school", "fire")) != "fire" else float(context.get("field_bonus", 0.0))
	var damage := float(player.attack) * (1.0 + field) * coefficient * float(context.get("damage_scale", 1.0)) * float(context.get("gem_body_scale", 1.0))
	if fire:
		damage *= 1.0 + _fire_damage_bonus()
	else:
		var module = _spell_combat.school_module(str(context.get("school", "")))
		if module != null: damage *= 1.0 + module.school_bonus(self)
	damage *= float(artifact_bonus.damage_multiplier)
	if fire:
		damage *= 1.0 + _spell_combat.growth.fire_vulnerability(self, actor)
	else:
		var module = _spell_combat.school_module(str(context.get("school", "")))
		if module != null and module.has_method("target_vulnerability"): damage *= 1.0 + module.target_vulnerability(actor)
	damage *= _gem_combat.outgoing_multiplier(self)
	if gem_core() == "echo" and bool(context.get("natural", false)) and bool(context.get("gem_echo_eligible", false)) and _gem_combat.body(context):
		damage *= float(_gem_combat.spec.immediate_multiplier)
	var uncritical: float = damage
	if critical:
		damage *= multiplier
	var planned: float = _gem_combat.critical_plan(self, actor, uncritical, damage, context) if critical else damage
	planned = _gem_combat.defer_plan(self, actor, planned, context)
	var before := float(actor.health)
	damage_enemy(actor, planned, str(context.get("spell_id", "")))
	var result := {"damage": before - maxf(0.0, float(actor.health)), "critical": critical}
	_gem_combat.fire_body_hit(self, actor, float(result.damage), context, old_burn)
	_artifact_combat.on_hit(self, actor, context, result)
	_spell_combat.growth.on_hit(self, actor, context, result)
	return result


func resolve_fire_status_hit(actor: Dictionary, coefficient: float, kind: String, metadata: Dictionary = {}) -> float:
	if phase != "combat" or actor.is_empty() or float(actor.health) <= 0.0 or coefficient <= 0.0:
		return 0.0
	var context: Dictionary = metadata.duplicate(true)
	context.merge({"spell_id": kind, "kind": kind, "natural": false, "school": "fire"}, true)
	var bonus: Dictionary = _artifact_combat.modify_damage_context(self, actor, context)
	var damage: float = float(player.attack) * coefficient * (1.0 + _spell_combat.field_attack_bonus()) * (1.0 + _fire_damage_bonus()) * float(bonus.damage_multiplier)
	damage *= 1.0 + _spell_combat.growth.fire_vulnerability(self, actor)
	damage *= _gem_combat.outgoing_multiplier(self)
	var before: float = float(actor.health)
	# Status damage has neither a critical RNG draw nor an on-hit callback.
	damage_enemy(actor, damage, kind)
	return before - maxf(0.0, float(actor.health))


func resolve_ice_derived_hit(actor: Dictionary, coefficient: float, context: Dictionary = {}) -> float:
	if phase != "combat" or actor.is_empty() or float(actor.get("health", 0.0)) <= 0.0 or coefficient <= 0.0:
		return 0.0
	var metadata: Dictionary = context.duplicate(true)
	metadata.merge({"school": "ice", "natural": false, "ice_direct": false}, true)
	var bonus: Dictionary = _artifact_combat.modify_damage_context(self, actor, metadata)
	var damage: float = float(player.attack) * (1.0 + _spell_combat.field_attack_bonus()) * coefficient * float(metadata.get("damage_scale", 1.0))
	damage *= (1.0 + _spell_combat.ice.school_bonus(self)) * float(bonus.damage_multiplier)
	damage *= _gem_combat.outgoing_multiplier(self)
	var before: float = float(actor.health)
	# No RNG or on-hit callback: the finite parent transaction owns all effects.
	damage_enemy(actor, damage, str(metadata.get("kind", "ice_shatter")))
	return before - maxf(0.0, float(actor.health))


func resolve_lightning_derived_hit(actor: Dictionary, coefficient: float, context: Dictionary = {}) -> float:
	if phase != "combat" or paused or actor.is_empty() or float(actor.get("health", 0.0)) <= 0.0 or coefficient <= 0.0:
		return 0.0
	var metadata: Dictionary = context.duplicate(true)
	metadata.merge({"school": "lightning", "natural": false, "lightning_direct": false}, true)
	var bonus: Dictionary = _artifact_combat.modify_damage_context(self, actor, metadata)
	var damage: float = float(player.attack) * (1.0 + _spell_combat.field_attack_bonus()) * coefficient * float(metadata.get("damage_scale", 1.0))
	damage *= (1.0 + _spell_combat.lightning.school_bonus(self)) * float(bonus.damage_multiplier)
	damage *= 1.0 + _spell_combat.lightning.target_vulnerability(actor)
	damage *= _gem_combat.outgoing_multiplier(self)
	var before: float = float(actor.health)
	# The finite parent owns all status/proc effects. No critical RNG or on-hit reentry.
	damage_enemy(actor, damage, str(metadata.get("kind", "lightning_derived")))
	return before - maxf(0.0, float(actor.health))


func _is_fire_damage(context: Dictionary) -> bool:
	if context.has("school"):
		return str(context.school) == "fire"
	var id: String = str(context.get("spell_id", ""))
	if _spell_combat.is_fire_spell(id):
		return true
	return id in ["P02", "G03", "burning", "detonation"]


func _fire_damage_bonus() -> float:
	var synergy: float = float(_base.fire_synergy.fire_bonus) if _spell_combat.fire_spell_count(self) >= int(_base.fire_synergy.distinct_spells) else 0.0
	return float(player.fire_bonus) + _spell_combat.fire_bonus() + synergy + _artifact_combat.fire_damage_bonus()


func damage_player(amount: float, damage_kind: String = "direct") -> bool:
	if _artifact_combat == null:
		return super.damage_player(amount, damage_kind)
	var before_health := float(player.health)
	var before_shield := float(player.shield)
	var multiplier: float = _artifact_combat.incoming_damage_multiplier(self, damage_kind)
	var accepted := super.damage_player(amount * multiplier, damage_kind)
	if accepted and phase == "combat" and float(player.health) > 0.0:
		var shield_loss := maxf(0.0, before_shield - float(player.shield))
		var health_loss := maxf(0.0, before_health - float(player.health))
		var shield_broken := before_shield > 0.0 and float(player.shield) <= 0.0
		_artifact_combat.on_player_damaged(self, shield_loss, health_loss, shield_broken)
		_spell_combat.ice.growth.on_player_damaged(self, shield_loss, health_loss)
	return accepted


func damage_enemy(actor: Dictionary, amount: float, spell_id: String = ""):
	var was_alive := not actor.is_empty() and float(actor.get("health", 0.0)) > 0.0
	super.damage_enemy(actor, amount, spell_id)
	if was_alive and bool(actor.get("boss", false)):
		_enemy_combat.bosses.sync_health(_enemy_combat, self, actor)
	if was_alive and float(actor.health) <= 0.0 and _artifact_combat != null:
		_gem_combat.actor_died(self, actor, not spell_id.begins_with("gem_"))
		actor["ice_frozen"] = false
		if _spell_combat != null:
			_spell_combat.remove_actor_status(int(actor.id))
		_artifact_combat.on_enemy_killed(self, actor)


func resolve_fixed_item_hit(actor: Dictionary, amount: float, item_id: String) -> float:
	if phase != "combat" or paused or actor.is_empty() or float(actor.health) <= 0.0 or amount <= 0.0:
		return 0.0
	var before := float(actor.health)
	damage_enemy(actor, amount, item_id)
	return before - maxf(0.0, float(actor.health))


func restore_player_shield(amount: float, source: String) -> float:
	if _artifact_combat == null:
		var actual := minf(maxf(0.0, amount), maxf(0.0, float(player.max_shield) - float(player.shield)))
		player.shield += actual
		return actual
	return _artifact_combat.restore_player_shield(self, amount, source)


func artifact_cooldown_reduction() -> float:
	return float(player.get("gem_cdr", 0.0)) + (_artifact_combat.get_cooldown_reduction() if _artifact_combat != null else 0.0)


func artifact_burn_parameters(parameters: Dictionary) -> Dictionary:
	var grown: Dictionary = _spell_combat.growth.burn_parameters(self, parameters) if _spell_combat != null else parameters.duplicate(true)
	var result: Dictionary = _artifact_combat.burn_parameters(grown) if _artifact_combat != null else grown
	return result

func gem_core() -> String:
	return _gem_combat.core

func gem_planned_damage(actor: Dictionary, coefficient: float, school: String) -> float:
	var context: Dictionary = {"school": school, "natural": false, "kind": "gem", "spell_id": "gem_" + school}
	var bonus: Dictionary = _artifact_combat.modify_damage_context(self, actor, context)
	var school_bonus: float = 0.0
	if school == "fire": school_bonus = _fire_damage_bonus()
	elif school == "ice": school_bonus = _spell_combat.ice.school_bonus(self)
	else:
		var module = _spell_combat.school_module(school)
		if module != null: school_bonus = module.school_bonus(self)
	if school == "thermal": school_bonus = maxf(_fire_damage_bonus(), _spell_combat.ice.school_bonus(self))
	if school == "fire": bonus.damage_multiplier *= 1.0 + _spell_combat.growth.fire_vulnerability(self, actor)
	else:
		var module = _spell_combat.school_module(school)
		if module != null and module.has_method("target_vulnerability"): bonus.damage_multiplier *= 1.0 + module.target_vulnerability(actor)
	return float(player.attack) * (1.0 + _spell_combat.field_attack_bonus()) * coefficient * (1.0 + school_bonus) * float(bonus.damage_multiplier)

func gem_derived_hit(actor: Dictionary, coefficient: float, school: String, source: String) -> float:
	if actor.is_empty() or float(actor.health) <= 0.0: return 0.0
	return resolve_fixed_item_hit(actor, gem_planned_damage(actor, coefficient, school), source)

func gem_after_spell_status(actor: Dictionary, context: Dictionary) -> void:
	_gem_combat.after_spell_status(self, actor, context)

func gem_record_shape(shape: Dictionary, coefficient: float, context: Dictionary) -> void:
	if bool(context.get("natural", false)) and _gem_combat.body(context): context["gem_echo_eligible"] = true
	_gem_combat.echo.record(self, shape, coefficient, context)


func artifact_reignite_spec() -> Dictionary:
	return _artifact_combat.reignite_spec() if _artifact_combat != null else {}


func on_spell_cast(spell: Dictionary, target: Dictionary, context: Dictionary):
	_artifact_combat.on_cast(self, spell, target, context)
	_spell_combat.growth.on_cast(self, spell, target, context)


func on_spell_area_expired(context: Dictionary, pos: Vector2):
	_artifact_combat.on_area_expired(self, context, pos)


func on_spell_area_matured(context: Dictionary, pos: Vector2, age: float):
	_artifact_combat.on_area_matured(self, context, pos, age)
	_spell_combat.growth.on_area_matured(self, context, pos, age)


func cast_extra_spell(spell_id: String, target: Dictionary = {}, scale: float = 1.0) -> bool:
	return _spell_combat.cast_extra(self, spell_id, target, scale)


func artifact_extra_spell_target(spell: Dictionary) -> Dictionary:
	return _spell_combat.legal_target(self, spell)


func artifact_refresh_spirits():
	_spell_combat.refresh_spirit_capacity(self)


func artifact_spirit_count() -> int:
	return _spell_combat.spirits.size()


func artifact_overlapping_spells(pos: Vector2, radius: float) -> Array:
	return _spell_combat.overlapping_spell_kinds(pos, radius)


func artifact_spirit_sync(target: Dictionary, coefficient: float) -> bool:
	return _spell_combat.fire_spirit_sync(self, target, coefficient)


func interrupt_enemy_by_push(actor: Dictionary, pos: Vector2):
	_enemy_combat.interrupt_by_push(actor, pos)


func resolve_school_derived_hit(actor: Dictionary, coefficient: float, context: Dictionary = {}) -> float:
	if phase != "combat" or paused or actor.is_empty() or float(actor.get("health", 0.0)) <= 0.0 or coefficient <= 0.0:
		return 0.0
	var metadata: Dictionary = context.duplicate(true)
	metadata["natural"] = false
	var school: String = str(metadata.get("school", ""))
	var module = _spell_combat.school_module(school)
	if module == null: return 0.0
	var bonus: Dictionary = _artifact_combat.modify_damage_context(self, actor, metadata)
	var damage: float = float(player.attack) * (1.0 + _spell_combat.field_attack_bonus()) * coefficient * float(metadata.get("damage_scale", 1.0))
	damage *= (1.0 + module.school_bonus(self) + float(metadata.get("summon_school_bonus", 0.0))) * float(bonus.damage_multiplier)
	damage *= 1.0 + module.target_vulnerability(actor)
	damage *= _gem_combat.outgoing_multiplier(self)
	if bool(metadata.get("can_crit", false)):
		var roll: float = _rng.randf()
		if roll < float(player.crit_rate):
			damage *= float(player.crit_multiplier) + float(bonus.get("crit_multiplier_add", 0.0))
	var before: float = float(actor.health)
	# A finite parent owns the event; these hits never enter ordinary body callbacks.
	damage_enemy(actor, damage, str(metadata.get("kind", "school_derived")))
	return before - maxf(0.0, float(actor.health))


func resolve_summon_hit(actor: Dictionary, coefficient: float, context: Dictionary = {}) -> float:
	var metadata: Dictionary = context.duplicate(true)
	metadata.merge({"school": "spirit", "kind": "summon", "natural": false, "can_crit": true}, true)
	return resolve_school_derived_hit(actor, coefficient, metadata)


func enemy_projectile_speed_multiplier(pos: Vector2) -> float:
	return _spell_combat.wind.projectile_speed_multiplier(self, pos) if _spell_combat != null else 1.0
