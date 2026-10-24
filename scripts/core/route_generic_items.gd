extends RefCounted
## Approved cross-class item effects. The route owns damage/death ordering.
## This helper only advances inside the artifact engine's combat update.

var _items: Dictionary = {}
var _rules: Dictionary = {}
var _base: Dictionary = {}
var _owned: Array = []
var _acquired_rooms: Dictionary = {}
var _move_input: Vector2 = Vector2.ZERO
var _stationary_elapsed: float = 0.0
var _undamaged_elapsed: float = 0.0
var _shield_elapsed: float = 0.0
var _broken_this_room: bool = false
var _break_speed_remaining: float = 0.0
var _hunting_stacks: int = 0
var _hunting_remaining: float = 0.0
var _hunting_cooldown: float = 0.0
var _dead_ids: Dictionary = {}
var _regen_remaining_ticks: int = 0
var _regen_per_tick: float = 0.0
var _regen_elapsed: float = 0.0
var _regen_cooldown: float = 0.0
var _charge: float = 0.0
var _charge_cooldown: float = 0.0
var _charge_checked_casts: Dictionary = {}
var _cup_progress: float = 0.0
var _cup_cooldown: float = 0.0
var _cleared_this_room: bool = false


func configure(items: Dictionary, rules: Dictionary, base: Dictionary, owned: Array) -> void:
	_items = items
	_rules = rules
	_base = base
	_owned = owned
	_acquired_rooms.clear()
	reset_room()


func reset_room() -> void:
	_move_input = Vector2.ZERO
	_stationary_elapsed = 0.0
	_undamaged_elapsed = 0.0
	_shield_elapsed = 0.0
	_broken_this_room = false
	_break_speed_remaining = 0.0
	_hunting_stacks = 0
	_hunting_remaining = 0.0
	_hunting_cooldown = 0.0
	_dead_ids.clear()
	_regen_remaining_ticks = 0
	_regen_per_tick = 0.0
	_regen_elapsed = 0.0
	_regen_cooldown = 0.0
	_charge = 0.0
	_charge_cooldown = 0.0
	_charge_checked_casts.clear()
	_cup_progress = 0.0
	_cup_cooldown = 0.0
	_cleared_this_room = false


func has_item(id: String) -> bool:
	return id in _owned


func apply_acquisition(run, id: String) -> void:
	_acquired_rooms[id] = int(run.room_index)
	var item: Dictionary = _items[id]
	# Flat life joins the pre-contract pool. Later flats never restore life.
	if item.has("health_max_add"):
		var factor: float = float(_items.GT03.maximum_health_multiplier) if has_item("GT03") else 1.0
		run.player.max_health += float(item.health_max_add) * factor
	if item.has("crit_rate_add"):
		run.player.crit_rate += float(item.crit_rate_add)
	if id == "GT03":
		var fraction: float = float(run.player.health) / float(run.player.max_health)
		run.player.max_health *= float(item.maximum_health_multiplier)
		run.player.health = float(run.player.max_health) * fraction
	_clamp_charge(run)


func before_combat_tick(_run, _dt: float, move: Vector2) -> void:
	_move_input = move
	if move.length_squared() > 0.00001:
		_stationary_elapsed = 0.0


func update(run, dt: float) -> void:
	if not _active(run) or dt <= 0.0:
		return
	_undamaged_elapsed += dt
	var moved: bool = run.player.has("previous") and run.player.pos.distance_squared_to(run.player.previous) > 0.0000000001
	if _move_input.length_squared() <= 0.00001 and not moved:
		_stationary_elapsed += dt
	else:
		_stationary_elapsed = 0.0
	_break_speed_remaining = maxf(0.0, _break_speed_remaining - dt)
	_hunting_cooldown = maxf(0.0, _hunting_cooldown - dt)
	_hunting_remaining = maxf(0.0, _hunting_remaining - dt)
	if _hunting_remaining <= 0.000001:
		_hunting_stacks = 0
	_regen_cooldown = maxf(0.0, _regen_cooldown - dt)
	_charge_cooldown = maxf(0.0, _charge_cooldown - dt)
	_cup_cooldown = maxf(0.0, _cup_cooldown - dt)
	_clamp_charge(run)
	if has_item("GU11"):
		_shield_elapsed += dt
		var interval: float = float(_items.GU11.interval)
		while _shield_elapsed + 0.000001 >= interval:
			_shield_elapsed -= interval
			var restored: float = restore_player_shield(run, float(_items.GU11.shield_restore), "GU11")
			_emit(run, "item_shield_restore", {"artifact_id": "GU11", "pos": run.player.pos, "amount": restored})
	if _regen_remaining_ticks > 0:
		_regen_elapsed += dt
		var interval: float = float(_items.GU14.restore_interval)
		while _regen_elapsed + 0.000001 >= interval and _regen_remaining_ticks > 0:
			_regen_elapsed -= interval
			_regen_remaining_ticks -= 1
			_restore_health(run, _regen_per_tick, "GU14")


func eligible(run, item: Dictionary) -> bool:
	if item.has("cooldown_reduction_add"):
		var current_reduction: float = 0.0
		if run.spells.size() >= int(_base.fire_synergy.distinct_spells):
			current_reduction += float(_base.fire_synergy.cooldown_reduction)
		for id in _owned:
			current_reduction += float(_items[id].get("cooldown_reduction_add", 0.0))
		if current_reduction + 0.000001 >= float(_base.limits.cooldown_reduction):
			return false
	if item.has("defense_add") and not item.has("damage_bonus"):
		var permanent_defense: float = float(run.player.get("gem_defense", 0.0))
		for id in ["GU04", "GU12"]:
			if has_item(id):
				permanent_defense += float(_items[id].defense_add)
		var coefficient: float = float(_rules.defense_coefficient)
		if coefficient / (coefficient + permanent_defense) <= 1.0 - float(_rules.maximum_damage_reduction) + 0.000001:
			return false
	match str(item.get("requirement", "")):
		"permanent_crit_rate":
			return float(run.player.crit_rate) + 0.000001 >= float(item.minimum_crit_rate)
		"combat_shield_recovery_and_player_damage":
			var recovery: bool = has_item("GU11") or has_item("GU16") or (run.has_method("gem_core") and run.has_gem_effect("aegis") and (has_item("GU14") or has_item("GT04")))
			var player_damage: bool = false
			for spell in run.spells:
				var kind: String = str(_base.spells.get(str(spell.id), {}).get("kind", ""))
				if kind == "shield":
					recovery = true
				if kind not in ["", "passive", "shield", "spirit", "wind_guard", "earth_guard", "spirit_guard"]:
					player_damage = true
			return recovery and player_damage
	return true


func incoming_damage_multiplier(run, damage_kind: String) -> float:
	var defense: float = float(combat_stats(run).defense)
	var coefficient: float = float(_rules.defense_coefficient)
	var multiplier: float = coefficient / (coefficient + maxf(0.0, defense))
	if damage_kind == "projectile" and has_item("GU10"):
		multiplier *= float(_items.GU10.projectile_damage_multiplier)
	return maxf(1.0 - float(_rules.maximum_damage_reduction), multiplier)


func on_player_damaged(run, shield_loss: float, health_loss: float, shield_broken: bool) -> void:
	if not _active(run) or shield_loss + health_loss <= 0.0:
		return
	_undamaged_elapsed = 0.0
	# All losses were fixed by the runner before this hook. Recovery cannot
	# absorb the same hit again, nor can a lethal hit reach this function.
	if has_item("GU14") and health_loss > 0.0 and _regen_cooldown <= 0.000001 and _regen_remaining_ticks == 0:
		var item: Dictionary = _items.GU14
		_regen_remaining_ticks = int(item.restore_ticks)
		_regen_per_tick = minf(health_loss * float(item.health_loss_restore_fraction), float(item.maximum_health_restore)) / float(item.restore_ticks)
		_regen_elapsed = 0.0
		_regen_cooldown = float(item.shared_cooldown)
	if has_item("GU16") and shield_broken and not _broken_this_room:
		_broken_this_room = true
		_break_speed_remaining = float(_items.GU16.duration)
		var restored: float = restore_player_shield(run, float(_items.GU16.shield_restore), "GU16")
		_emit(run, "item_shield_restore", {"artifact_id": "GU16", "pos": run.player.pos, "amount": restored})
	if has_item("GT04") and shield_loss > 0.0:
		var item: Dictionary = _items.GT04
		_cup_progress += shield_loss
		if _cup_cooldown <= 0.000001 and _cup_progress + 0.000001 >= float(item.shield_loss_threshold):
			_cup_progress = minf(float(item.maximum_retained_progress), _cup_progress - float(item.shield_loss_threshold))
			_cup_cooldown = float(item.shared_cooldown)
			_restore_health(run, float(item.health_restore), "GT04")
		elif _cup_cooldown > 0.000001:
			_cup_progress = minf(float(item.maximum_retained_progress), _cup_progress)


func on_enemy_killed(run, actor: Dictionary) -> void:
	if not _active(run) or not has_item("GU17") or float(actor.get("health", 0.0)) > 0.0:
		return
	var key: String = str(actor.get("id", ""))
	if key.is_empty() or _dead_ids.has(key):
		return
	_dead_ids[key] = true
	if _hunting_cooldown > 0.000001:
		return
	_hunting_stacks = mini(int(_items.GU17.maximum_stacks), _hunting_stacks + 1)
	_hunting_remaining = float(_items.GU17.duration)
	_hunting_cooldown = float(_items.GU17.shared_cooldown)
	_emit(run, "item_hunting", {"artifact_id": "GU17", "pos": run.player.pos, "stacks": _hunting_stacks, "remaining": _hunting_remaining})


func on_room_cleared(run) -> void:
	if _cleared_this_room or not _active(run):
		return
	_cleared_this_room = true
	if has_item("GU09") and int(run.room_index) > int(_acquired_rooms.get("GU09", -1)):
		_restore_health(run, float(_items.GU09.clear_health_restore), "GU09")


func restore_player_shield(run, base_amount: float, _source: String) -> float:
	if not _active(run) or not is_finite(base_amount) or base_amount <= 0.0:
		return 0.0
	var amount: float = base_amount
	if has_item("GT01"):
		amount *= float(_items.GT01.shield_restore_multiplier)
	var actual: float = minf(amount, maxf(0.0, float(run.player.max_shield) - float(run.player.shield)))
	run.player.shield += actual
	if has_item("GT01") and actual > 0.0:
		_charge += actual * float(_items.GT01.charge_per_restored_shield)
		_clamp_charge(run)
	return actual


func on_hit(run, actor: Dictionary, context: Dictionary, result: Dictionary) -> void:
	if not has_item("GT01") or not _active(run) or not bool(context.get("natural", false)) or float(result.get("damage", 0.0)) <= 0.0:
		return
	var kind: String = str(context.get("kind", ""))
	var spell_kind: String = str(_base.spells.get(str(context.get("spell_id", "")), {}).get("kind", ""))
	if spell_kind in ["", "passive", "shield", "spirit", "wind_guard", "earth_guard", "spirit_guard"] or kind in ["spirit", "artifact", "artifact_sync"]:
		return
	var cast_key: String = str(context.get("cast_id", ""))
	if cast_key.is_empty() or _charge_checked_casts.has(cast_key):
		return
	# Even an empty store, cooling release or already-killed first target
	# consumes this cast's first-check eligibility, never the stored resource.
	_charge_checked_casts[cast_key] = true
	_clamp_charge(run)
	if _charge <= 0.0 or _charge_cooldown > 0.000001 or float(actor.get("health", 0.0)) <= 0.0 or not run.has_method("resolve_fixed_item_hit"):
		return
	var before: float = float(actor.health)
	run.resolve_fixed_item_hit(actor, _charge, "GT01")
	if before - maxf(0.0, float(actor.health)) > 0.0:
		var released: float = _charge
		_charge = 0.0
		_charge_cooldown = float(_items.GT01.shared_cooldown)
		_emit(run, "item_charge_release", {"artifact_id": "GT01", "pos": actor.pos, "amount": released, "spell_id": str(context.get("spell_id", "")), "cast_id": context.get("cast_id", "")})


func get_cooldown_reduction() -> float:
	return float(_items.GU05.cooldown_reduction_add) if has_item("GU05") else 0.0


func move_speed_bonus(run = null) -> float:
	if run != null and not _in_combat(run):
		return 0.0
	var result: float = float(_items.GU08.move_speed_bonus) if has_item("GU08") else 0.0
	if has_item("GU16") and _break_speed_remaining > 0.000001:
		result += float(_items.GU16.move_speed_bonus)
	return result


func combat_stats(run) -> Dictionary:
	var defense: float = float(run.player.get("gem_defense", 0.0))
	for id in ["GU04", "GU12"]:
		if has_item(id):
			defense += float(_items[id].defense_add)
	var damage_bonus: float = 0.0
	for id in _owned:
		if bool(_items[id].get("boss_only", false)):
			damage_bonus += float(_items[id].damage_bonus)
	var stationary: bool = _in_combat(run) and has_item("GU18") and _stationary_elapsed + 0.000001 >= float(_items.GU18.stationary_seconds) and _move_input.length_squared() <= 0.00001
	var undamaged: bool = _in_combat(run) and has_item("GU15") and _undamaged_elapsed + 0.000001 >= float(_items.GU15.undamaged_seconds)
	var low_health: bool = has_item("GT02") and float(run.player.health) <= float(run.player.max_health) * float(_items.GT02.health_fraction_threshold)
	if stationary:
		defense += float(_items.GU18.defense_add)
		damage_bonus += float(_items.GU18.damage_bonus)
	if undamaged:
		damage_bonus += float(_items.GU15.damage_bonus)
	if has_item("GU17") and _in_combat(run):
		damage_bonus += _hunting_stacks * float(_items.GU17.damage_bonus_per_stack)
	if low_health:
		defense += float(_items.GT02.defense_add)
		damage_bonus += float(_items.GT02.damage_bonus)
	if has_item("GT03"):
		damage_bonus += float(_items.GT03.damage_bonus)
	return {"defense": maxf(0.0, defense), "generic_damage_bonus": damage_bonus,
		"elite_damage_bonus": float(_items.GU13.elite_damage_bonus) if has_item("GU13") else 0.0,
		"crit_multiplier_add": float(_items.GU07.crit_multiplier_add) if has_item("GU07") else 0.0,
		"cooldown_reduction_add": get_cooldown_reduction(), "combat_move_speed_bonus": move_speed_bonus(run),
		"stationary_active": stationary, "undamaged_active": undamaged, "low_health_active": low_health,
		"hunting_stacks": _hunting_stacks, "hunting_remaining": _hunting_remaining,
		"charge": _charge, "charge_cooldown": _charge_cooldown, "cup_progress": _cup_progress}


func damage_bonus(run, actor: Dictionary) -> float:
	var stats: Dictionary = combat_stats(run)
	var result: float = float(stats.generic_damage_bonus)
	if bool(actor.get("elite", false)) or bool(actor.get("boss", false)) or str(actor.get("rank", "")) in ["elite", "boss"]:
		result += float(stats.elite_damage_bonus)
	return result


func state_snapshot() -> Dictionary:
	return {"stationary_elapsed": _stationary_elapsed, "undamaged_elapsed": _undamaged_elapsed,
		"shield_elapsed": _shield_elapsed, "broken_this_room": _broken_this_room, "break_speed_remaining": _break_speed_remaining,
		"hunting_stacks": _hunting_stacks, "hunting_remaining": _hunting_remaining, "hunting_cooldown": _hunting_cooldown,
		"regen_remaining_ticks": _regen_remaining_ticks, "regen_per_tick": _regen_per_tick, "regen_elapsed": _regen_elapsed, "regen_cooldown": _regen_cooldown,
		"charge": _charge, "charge_cooldown": _charge_cooldown, "charge_checked_casts": _charge_checked_casts.keys(),
		"cup_progress": _cup_progress, "cup_cooldown": _cup_cooldown}


func _restore_health(run, amount: float, source: String) -> float:
	if not _active(run) or amount <= 0.0:
		return 0.0
	if source != "GU09" and run.has_method("gem_core") and run.has_gem_effect("aegis"):
		var shield: float = restore_player_shield(run, amount * float(run._gem_combat.spec_of("aegis").combat_health_restore_conversion), source)
		_emit(run, "item_shield_restore", {"artifact_id": source, "pos": run.player.pos, "amount": shield, "gem_core": "aegis"})
		return shield
	var actual: float = minf(amount, maxf(0.0, float(run.player.max_health) - float(run.player.health)))
	run.player.health += actual
	_emit(run, "item_health_restore", {"artifact_id": source, "pos": run.player.pos, "amount": actual})
	return actual


func _clamp_charge(run) -> void:
	if has_item("GT01"):
		_charge = clampf(_charge, 0.0, maxf(0.0, float(run.player.attack)) * float(_items.GT01.charge_attack_cap_multiplier))


func _active(run) -> bool:
	return _in_combat(run) and not bool(run.paused)


func _in_combat(run) -> bool:
	return run != null and run.phase == "combat" and float(run.player.get("health", 0.0)) > 0.0


func _emit(run, kind: String, value: Dictionary) -> void:
	if run.has_method("_emit"):
		run._emit(kind, value, 0.8)
