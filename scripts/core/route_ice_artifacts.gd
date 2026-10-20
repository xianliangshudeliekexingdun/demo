extends RefCounted
## Approved ice profession hooks. This owns only item gates, not frost or damage.

var _items: Dictionary = {}
var _owned: Array = []
var _ip01_checked: Dictionary = {}
var _ig01_checked: Dictionary = {}
var _ig02_ready: Dictionary = {}
var _ig03_casts: Dictionary = {}
var _ig03_ready: float = 0.0
var _ip03_ready: float = 0.0


func configure(items: Dictionary, owned: Array) -> void:
	_items = items
	_owned = owned
	reset_room()


func reset_room() -> void:
	_ip01_checked.clear()
	_ig01_checked.clear()
	_ig02_ready.clear()
	_ig03_casts.clear()
	_ig03_ready = 0.0
	_ip03_ready = 0.0


func has_item(id: String) -> bool:
	return id in _owned and _items.has(id) and not bool(_items[id].get("retired_to_spell_growth", false))


func modify_spell_stats(id: String, data: Dictionary, spell_level: int) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	var level: Dictionary = result.level if result.get("level") is Dictionary else result
	match id:
		"I01":
			if has_item("IB01"):
				level["frosted_coefficient_add"] = float(_items.IB01.coefficient_add)
		"I02":
			if has_item("IB02"):
				level.width = float(level.width) * float(_items.IB02.width_multiplier)
				level.target_cap = int(level.target_cap) + int(_items.IB02.target_cap_add)
		"I03":
			if has_item("IB03"):
				level.impact_delay = float(_items.IB03.first_impact_delay)
				level.radius = float(level.radius) + float(_items.IB03.radius_add)
		"I04":
			if has_item("IB04"):
				level.radius = float(level.radius) + float(_items.IB04.radius_add)
				for kind in ["normal", "elite", "fixed_strong"]:
					level["slow_" + kind] = float(_items.IB04["slow_" + kind])
		"I05":
			if has_item("IB05"):
				level.duration = float(level.duration) + float(_items.IB05.duration_add)
				level.ticks = int(_items.IB05.ticks[clampi(spell_level - 1, 0, 2)])
		"I06":
			if has_item("IB06"):
				result["final_wave_multiplier"] = float(_items.IB06.final_wave_multiplier)
		"I07":
			if has_item("IB07"):
				if spell_level <= 1:
					level.shatter_coefficient = float(level.shatter_coefficient) + float(_items.IB07.level1_shatter_add)
				else:
					level.shard_coefficient = float(level.shard_coefficient) + float(_items.IB07.shard_coefficient_add)
					level.shard_radius = float(level.shard_radius) + float(_items.IB07.shard_radius_add)
		"I08":
			if has_item("IB08"):
				level["immune_coefficient_add"] = float(_items.IB08.coefficient_add)
		"I09":
			if has_item("IB09"):
				level.radius = float(level.radius) + float(_items.IB09.radius_add)
	return result


func frost_expiry(run) -> float:
	if has_item("IB10"):
		return float(_items.IB10.frost_expiry)
	return float(run._base.get("ice_mechanics", {}).get("frost", {}).get("expiry", 4.0))


func extra_frost(run, actor: Dictionary, context: Dictionary, result: Dictionary, pre_state: Dictionary, ordinal: int) -> int:
	if not _active(run):
		return 0
	var id: String = str(context.get("spell_id", ""))
	var cast_id: String = str(context.get("cast_id", ""))
	var natural: bool = bool(context.get("natural", false))
	var direct: bool = bool(context.get("ice_direct", false))
	var extra: int = 0
	if has_item("IP01") and natural and direct and id in ["I01", "I02", "I03"] and not _ip01_checked.has(cast_id):
		# The first effective direct hit owns the check even if it kills or has no frost.
		_ip01_checked[cast_id] = true
		if float(result.get("damage", 0.0)) > 0.0 and float(actor.get("health", 0.0)) > 0.0 and not _ready(pre_state) and int(pre_state.get("stacks", 0)) in [1, 2]:
			extra += int(_items.IP01.extra_stacks)
	if has_item("IG01") and natural and not direct and str(context.get("kind", "")) == "area" and id in ["I05", "I06"] and ordinal == int(_items.IG01.qualified_chill_ordinal):
		var key: String = "%s:%s" % [cast_id, actor.get("id", -1)]
		if not _ig01_checked.has(key) and float(result.get("damage", 0.0)) > 0.0 and float(actor.get("health", 0.0)) > 0.0 and not _ready(pre_state):
			_ig01_checked[key] = true
			extra += int(_items.IG01.extra_stacks)
	return extra


func on_window_created(run, actor: Dictionary, context: Dictionary, _state: Dictionary) -> void:
	if not has_item("IG03") or not bool(context.get("natural", false)) or str(context.get("spell_id", "")) != "I08":
		return
	if not _active(run) or float(actor.get("health", 0.0)) <= 0.0:
		return
	var cast_id: String = str(context.get("cast_id", ""))
	if _ig03_casts.has(cast_id):
		return
	_ig03_casts[cast_id] = true
	var now: float = _clock(run)
	if now + 0.000001 < _ig03_ready:
		return
	_ig03_ready = now + float(_items.IG03.shared_cooldown)
	var actual: float = run._artifact_combat.restore_player_shield(run, float(_items.IG03.restore_request), "IG03")
	run._emit("ice_artifact_restore", {"artifact_id": "IG03", "pos": run.player.pos, "amount": actual, "requested": float(_items.IG03.restore_request)}, 0.5)


func shatter_effect(run, actor: Dictionary, context: Dictionary, _info: Dictionary) -> Dictionary:
	var result: Dictionary = {"damage_multiplier": 1.0, "retain_frost": 0, "fragment_frost_targets": 0, "fragment_frost_stacks": 0}
	if not _active(run) or not bool(context.get("natural", false)) or str(context.get("spell_id", "")) != "I07":
		return result
	if has_item("IP02") and int(context.get("spell_level", 1)) >= int(_items.IP02.minimum_I07_level):
		result.fragment_frost_targets = int(_items.IP02.neighbor_cap)
		result.fragment_frost_stacks = int(_items.IP02.chill_stacks)
	if has_item("IG02") and float(actor.get("health", 0.0)) > 0.0:
		var key: String = str(actor.get("id", -1))
		var now: float = _clock(run)
		if now + 0.000001 >= float(_ig02_ready.get(key, 0.0)):
			_ig02_ready[key] = now + float(_items.IG02.per_actor_cooldown)
			result.damage_multiplier = float(_items.IG02.shatter_multiplier)
			result.retain_frost = int(_items.IG02.retained_stacks)
	return result


func on_player_damaged(run, shield_loss: float, health_loss: float) -> void:
	if not has_item("IP03") or not _active(run) or shield_loss + health_loss <= 0.0:
		return
	if run._spell_combat == null or run._spell_combat.ice == null or run._spell_combat.ice.defense_bonus() <= 0.0:
		return
	var now: float = _clock(run)
	if now + 0.000001 < _ip03_ready:
		return
	var actor: Dictionary = run.nearest_target(run.player.pos, float(_items.IP03.range), true)
	if actor.is_empty():
		return
	_ip03_ready = now + float(_items.IP03.shared_cooldown)
	run._spell_combat.ice.apply_frost(run, actor, int(_items.IP03.chill_stacks), {"kind": "ice_status", "spell_id": "IP03", "school": "ice", "natural": false, "cast_id": "IP03:%s" % now})


func eligible(run, item: Dictionary) -> bool:
	var ids: Array = []
	var levels: Dictionary = {}
	for spell in run.spells:
		if str(spell.id) not in ids:
			ids.append(str(spell.id))
		levels[str(spell.id)] = maxi(int(levels.get(str(spell.id), 0)), int(spell.level))
	if item.has("required_spell"):
		return str(item.required_spell) in ids
	var frost_sources: Array = ["I01", "I02", "I03", "I04", "I05", "I06", "I08"]
	var has_frost: bool = not ids.filter(func(id): return id in frost_sources).is_empty()
	var ice_count: int = ids.filter(func(id): return str(run._base.spells.get(id, {}).get("school", "")) == "ice").size()
	match str(item.get("requirement", "")):
		"ice_two_starters": return ids.filter(func(id): return id in ["I01", "I02", "I03"]).size() >= 2
		"ice_shards_and_frost": return int(levels.get("I07", 0)) >= int(item.minimum_I07_level) and has_frost
		"ice_armor_and_damage": return "I09" in ids and not ids.filter(func(id): return id in frost_sources or id == "I07").is_empty()
		"ice_synergy_and_area": return ice_count >= int(run._base.get("ice_mechanics", {}).get("resonance", {}).get("distinct_spells", 3)) and ("I05" in ids or "I06" in ids)
		"ice_shatter_and_frost": return "I07" in ids and has_frost
		"ice_prison_and_armor": return "I08" in ids and "I09" in ids
	return false


func state_snapshot() -> Dictionary:
	return {"ip01_checked": _ip01_checked.keys(), "ig01_checked": _ig01_checked.keys(), "ig02_ready": _ig02_ready.duplicate(true), "ig03_casts": _ig03_casts.keys(), "ig03_ready": _ig03_ready, "ip03_ready": _ip03_ready}


func _clock(run) -> float:
	return float(run._spell_combat.ice.status.clock) if run._spell_combat != null and run._spell_combat.ice != null else 0.0


func _active(run) -> bool:
	return run.phase == "combat" and not bool(run.paused) and float(run.player.health) > 0.0


func _ready(state: Dictionary) -> bool:
	return bool(state.get("ready", false)) or float(state.get("window_remaining", 0.0)) > 0.000001
