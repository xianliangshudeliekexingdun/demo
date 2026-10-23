extends RefCounted
## Authoritative finite summons, shared mark, commands and recall. The view
## consumes copies; no animation or effect lifetime decides these transactions.

const Navigation = preload("res://scripts/core/route_spirit_navigation.gd")
var navigation = Navigation.new()
var mechanics: Dictionary = {}
var effects: Dictionary = {}
var source_spells: Dictionary = {}
var units: Array = []
var fields: Array = []
var pending: Array = []
var projectiles: Array = []
var mark: Dictionary = {}
var clock: float = 0.0
var _next_id: int = 1
var _last_tick: float = -INF

func configure(source: Dictionary) -> Dictionary:
	if not source.get("mechanics") is Dictionary or not source.get("spells") is Dictionary or source.spells.size() != 10:
		return {"ok": false, "error": "正式灵契源缺失或数量无效。"}
	mechanics = source.mechanics.duplicate(true)
	effects = source.get("effects", {}).duplicate(true)
	source_spells = source.spells.duplicate(true)
	if not mechanics.has_all(["initial_ids", "resonance", "summon_sources", "total_attack_unit_capacity", "minimum_attack_windup"]):
		return {"ok": false, "error": "正式灵契机制源缺失。"}
	for key in ["hit", "beam", "summon", "attack_windup", "mark", "command", "burst", "chain", "shield"]:
		if not _positive(effects.get(key)): return {"ok": false, "error": "灵契表现时长无效：" + key}
	for number in range(1, 11):
		var id: String = "S%02d" % number
		var spec: Dictionary = source_spells.get(id, {})
		if str(spec.get("school", "")) != "spirit" or not spec.get("levels") is Array or spec.levels.size() != 3:
			return {"ok": false, "error": "正式灵契三级源无效：" + id}
		for level in spec.levels:
			if not level is Dictionary or not level.has("cooldown") or not is_finite(float(level.cooldown)) or float(level.cooldown) < 0.0:
				return {"ok": false, "error": "灵契冷却源无效：" + id}
	stop_room()
	return {"ok": true, "error": ""}

func _positive(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) > 0.0

func stop_room() -> void:
	units.clear()
	fields.clear()
	pending.clear()
	projectiles.clear()
	mark.clear()
	clock = 0.0
	_next_id = 1
	_last_tick = -INF

func before_tick(run, dt: float) -> void:
	if not _active(run) or absf(_last_tick - float(run.time)) <= 0.000000001: return
	_last_tick = float(run.time)
	clock += dt
	if not mark.is_empty() and (float(mark.expires) <= clock + 0.000001 or _actor(run, int(mark.actor_id)).is_empty()): mark.clear()

func is_spirit_spell(id: String) -> bool:
	return source_spells.has(id)

func spell_count(run) -> int:
	var distinct: Dictionary = {}
	for spell in run.spells:
		if is_spirit_spell(str(spell.id)): distinct[str(spell.id)] = true
	return distinct.size()

func school_bonus(run) -> float:
	return _mastery_value(run, "spirit_damage_bonus") + (float(mechanics.resonance.school_damage_bonus) if spell_count(run) >= int(mechanics.resonance.distinct_spells) else 0.0)

func cooldown_bonus(run) -> float:
	return float(mechanics.resonance.school_cdr) if spell_count(run) >= int(mechanics.resonance.distinct_spells) else 0.0

func target_vulnerability(_actor_value: Dictionary) -> float:
	return 0.0

func remove_actor_status(actor_id: int) -> void:
	if int(mark.get("actor_id", -1)) == actor_id: mark.clear()

func reward_eligible(run, id: String) -> bool:
	var required: Array = source_spells.get(id, {}).get("required_any_spells", [])
	if required.is_empty(): return true
	for spell in run.spells:
		if str(spell.id) in required: return true
	return false

func _mastery_value(run, key: String) -> float:
	var mastery: Dictionary = run._owned_spell("S10")
	return float(run.get_spell_stats(mastery).level.get(key, 0.0)) if not mastery.is_empty() else 0.0

func get_snapshot(run) -> Dictionary:
	var visible_mark: Dictionary = mark.duplicate(true)
	if not visible_mark.is_empty():
		visible_mark["remaining"] = maxf(0.0, float(visible_mark.expires) - clock)
		var marked_actor: Dictionary = _actor(run, int(visible_mark.actor_id))
		if not marked_actor.is_empty(): visible_mark["pos"] = marked_actor.pos
	return {"spirit_units": units.duplicate(true), "spirit_fields": fields.duplicate(true),
		"spirit_pending": pending.duplicate(true), "spirit_projectiles": projectiles.duplicate(true),
		"spirit_mark": visible_mark, "spirit_clock": clock}

func legal_target(run, spell: Dictionary, stats: Dictionary) -> Dictionary:
	if not _active(run) or str(stats.kind) == "passive": return {}
	var id: String = str(spell.id)
	if id in mechanics.summon_sources:
		if _vacancies(id, stats.level) <= 0: return {}
		var enemies: Array = _sorted_targets(run, run.player.pos, float(stats.level.get("range", stats.level.get("search_range", 8.0))), false, false)
		return enemies[0] if not enemies.is_empty() else {}
	if id == "S09":
		return {"id": -1, "pos": run.player.pos} if float(run.player.shield) < float(run.player.max_shield) - 0.000001 and _has_enemy(run) else {}
	if id == "S07":
		return {"id": -1, "pos": run.player.pos} if not _live_units().is_empty() and _has_enemy(run) else {}
	if id == "S05":
		for actor in _sorted_targets(run, run.player.pos, float(stats.level.range), true, true):
			if not _command_sources(run, actor, stats.level).is_empty(): return actor
		return {}
	return _preferred(run, run.player.pos, float(stats.level.get("range", 8.0)), id in ["S06", "S08"])

func finish_target(run, spell: Dictionary, stats: Dictionary) -> Dictionary:
	if str(spell.id) in ["S02", "S03", "S04", "S07", "S09"]: return legal_target(run, spell, stats)
	var original: Dictionary = _actor(run, int(spell.get("target_id", -1)))
	if original.is_empty() or run.player.pos.distance_to(original.pos) > float(stats.level.get("range", 8.0)) + 0.000001 or not run.line_is_clear(run.player.pos, original.pos): return {}
	if str(spell.id) == "S05" and _command_sources(run, original, stats.level).is_empty(): return {}
	return original

func cast(run, spell: Dictionary, stats: Dictionary, target: Dictionary, source_context: Dictionary) -> void:
	if not _active(run): return
	var id: String = str(spell.id)
	var level: Dictionary = stats.level.duplicate(true)
	var context: Dictionary = source_context.duplicate(true)
	context.merge({"school": "spirit", "spirit_level": level, "spell_level": int(spell.level), "kind": str(stats.kind)}, true)
	match id:
		"S01":
			projectiles.append({"id": _new_id(), "spell_id": id, "pos": run.player.pos, "from": run.player.pos,
				"direction": (target.pos - run.player.pos).normalized(), "travelled": 0.0, "visited": [], "context": context})
		"S02", "S03", "S04": _summon(run, id, level, context)
		"S05":
			var sources: Array = _command_sources(run, target, level)
			_queue(clock + float(level.command_delay), "command", {"source_ids": sources, "actor_id": int(target.id), "context": context})
			run._emit("spirit_command_start", {"pos": target.pos, "actor_id": target.id, "source_ids": sources, "spell_id": id}, float(level.command_delay))
		"S06": _recall(run, spell.get("locked_pos", target.pos), context)
		"S07":
			fields = [{"id": _new_id(), "spell_id": id, "pos": run.player.pos, "radius": level.radius,
				"born_at": clock, "expires": clock + float(level.duration), "context": context, "granted": {}}]
			_update_fields(run)
		"S08": _chains(run, target, context)
		"S09":
			var request: float = float(level.shield_restore) + float(level.shield_per_alive_unit) * mini(_live_units().size(), int(level.bonus_unit_cap))
			var actual: float = run.restore_player_shield(request, id)
			run._emit("spirit_shield", {"pos": run.player.pos, "amount": actual, "spell_id": id}, float(effects.shield))

func update_existing(run, dt: float) -> void:
	if not _active(run): return
	_update_fields(run)
	_update_units(run, dt)
	_update_pending(run)
	_update_projectiles(run, dt)

func _vacancies(id: String, level: Dictionary) -> int:
	var count: int = 0
	for unit in _live_units():
		if str(unit.spell_id) == id: count += 1
	return maxi(0, mini(int(level.capacity) - count, int(mechanics.total_attack_unit_capacity) - _live_units().size()))

func _summon(run, id: String, level: Dictionary, context: Dictionary) -> void:
	var count: int = mini(_vacancies(id, level), int(level.summon_per_cast))
	for _index in count:
		var unit_id: int = _new_id()
		var unit: Dictionary = {"id": unit_id, "spell_id": id, "family": str(source_spells[id].summon_family),
			"pos": _safe_home(run, unit_id), "born_at": clock, "expires": clock + float(level.duration),
			"remaining": float(level.duration), "extension_used": 0.0, "context": context.duplicate(true),
			"level": level.duplicate(true), "next_at": clock + float(level.attack_delay), "attack_id": 0,
			"windup_target_id": -1, "windup_due": 0.0, "path": [], "path_target_id": -1, "path_goal": run.player.pos}
		for field in fields:
			if _covered(run, field, unit):
				var field_level: Dictionary = field.context.spirit_level
				unit.next_at = clock + maxf(float(field_level.minimum_first_attack_delay), float(level.attack_delay) - float(field_level.new_unit_first_attack_delay_reduction))
		units.append(unit)
		run._emit("spirit_summon", {"pos": unit.pos, "unit_id": unit_id, "spell_id": id, "family": unit.family}, float(effects.summon))
	_update_fields(run)

func _safe_home(run, unit_id: int) -> Vector2:
	var angle: float = float((unit_id - 1) % int(mechanics.total_attack_unit_capacity)) * TAU / float(mechanics.total_attack_unit_capacity)
	return run._clip_motion(run.player.pos, Vector2.from_angle(angle) * float(mechanics.spawn_distance), float(mechanics.unit_radius))

func _live_units() -> Array:
	var live: Array = []
	for unit in units:
		if not bool(unit.get("consumed", false)) and float(unit.expires) > clock + 0.000001: live.append(unit)
	return live

func _unit(id: int) -> Dictionary:
	for unit in _live_units():
		if int(unit.id) == id: return unit
	return {}

func _update_units(run, dt: float) -> void:
	var retained: Array = []
	for unit in units:
		if not _active(run): break
		if bool(unit.get("consumed", false)): continue
		if unit.pos.distance_to(run.player.pos) > float(mechanics.leash_distance):
			unit.pos = _safe_home(run, int(unit.id))
			unit.windup_target_id = -1
			unit.path = []
			unit.next_at = maxf(float(unit.next_at), clock + float(mechanics.minimum_attack_windup))
			# Recovery never grants an attack in the relocation frame.
		elif float(unit.expires) >= clock - 0.000001:
			_update_unit(run, unit, dt)
		unit.remaining = maxf(0.0, float(unit.expires) - clock)
		if float(unit.remaining) > 0.000001: retained.append(unit)
		else: run._emit("spirit_expire", {"pos": unit.pos, "unit_id": unit.id, "spell_id": unit.spell_id}, float(effects.summon))
	units = retained
	if run.has_method("gem_core"): run._gem_combat.schools.spirit_presence(run)

func _update_unit(run, unit: Dictionary, dt: float) -> void:
	var level: Dictionary = unit.level
	if str(unit.family) == "ranged":
		_move_toward(run, unit, _safe_home(run, int(unit.id)), float(mechanics.follow_speed) * dt, -1)
	var target: Dictionary = _pet_target(run, unit)
	if target.is_empty():
		unit.windup_target_id = -1
		if str(unit.family) != "ranged": _move_toward(run, unit, _safe_home(run, int(unit.id)), float(level.move_speed) * dt, -1)
		return
	if str(unit.family) != "ranged" and not _attack_legal(run, unit, target):
		_move_toward(run, unit, target.pos, float(level.move_speed) * dt, int(target.id))
	if not _attack_legal(run, unit, target):
		unit.windup_target_id = -1
		return
	var window: float = float(level.attack_windup)
	if int(unit.windup_target_id) != int(target.id):
		unit.windup_target_id = -1
		if clock < float(unit.next_at) - window - 0.000001: return
		unit.windup_target_id = int(target.id)
		unit.windup_due = maxf(float(unit.next_at), clock + window)
		run._emit("spirit_attack_windup", {"pos": unit.pos, "to": target.pos, "unit_id": unit.id, "spell_id": unit.spell_id}, float(effects.attack_windup))
	if clock + 0.000001 < float(unit.windup_due): return
	unit.attack_id = int(unit.attack_id) + 1
	_attack(run, unit, target)
	unit.windup_target_id = -1
	unit.next_at = float(unit.windup_due) + float(level.attack_interval)

func _pet_target(run, unit: Dictionary) -> Dictionary:
	var level: Dictionary = unit.level
	var ranged: bool = str(unit.family) == "ranged"
	var reach: float = float(level.range) if ranged else float(level.search_range)
	var found: Array = _sorted_targets(run, unit.pos, reach, ranged, str(unit.family) != "hawk")
	if str(unit.family) == "hawk":
		found.sort_custom(func(a, b):
			var ad: float = unit.pos.distance_squared_to(a.pos)
			var bd: float = unit.pos.distance_squared_to(b.pos)
			if not is_equal_approx(ad, bd): return ad < bd
			if _marked(a) != _marked(b): return _marked(a)
			return int(a.id) < int(b.id))
	for actor in found:
		if ranged or _attack_legal(run, unit, actor) or not navigation.path(run, unit.pos, actor.pos, float(mechanics.unit_radius), float(mechanics.navigation_margin)).is_empty(): return actor
	return {}

func _move_toward(run, unit: Dictionary, goal: Vector2, distance: float, target_id: int) -> void:
	if unit.pos.distance_to(goal) <= 0.000001: return
	if int(unit.path_target_id) != target_id or unit.path_goal.distance_to(goal) >= float(mechanics.path_replan_distance) or unit.path.is_empty():
		unit.path = navigation.path(run, unit.pos, goal, float(mechanics.unit_radius), float(mechanics.navigation_margin))
		unit.path_target_id = target_id
		unit.path_goal = goal
	var budget: float = distance
	while not unit.path.is_empty() and budget > 0.000001:
		var point: Vector2 = unit.path[0]
		var step: Vector2 = (point - unit.pos).limit_length(budget)
		var origin: Vector2 = unit.pos
		unit.pos = run._clip_motion(origin, step, float(mechanics.unit_radius))
		budget -= origin.distance_to(unit.pos)
		if unit.pos.distance_to(point) <= 0.00001: unit.path.pop_front()
		else: break

func _attack_legal(run, unit: Dictionary, actor: Dictionary) -> bool:
	var reach: float = float(unit.level.range) if str(unit.family) == "ranged" else float(unit.level.attack_range)
	return float(actor.get("health", 0.0)) > 0.0 and unit.pos.distance_to(actor.pos) <= reach + 0.000001 and run.line_is_clear(unit.pos, actor.pos)

func _attack(run, unit: Dictionary, target: Dictionary) -> void:
	var level: Dictionary = unit.level
	var contacts: Array = []
	var end: Vector2 = target.pos
	if str(unit.family) in ["ranged", "hawk"]:
		var width: float = float(level.beam_width) if str(unit.family) == "ranged" else float(level.sweep_width)
		var length: float = float(level.range) if str(unit.family) == "ranged" else float(level.sweep_length)
		end = run._clip_motion(unit.pos, (target.pos - unit.pos).normalized() * length, width * 0.5)
		for actor in run.actors:
			if float(actor.health) <= 0.0 or not run.line_is_clear(unit.pos, actor.pos): continue
			var at: float = run.segment_circle_time(unit.pos, end, actor.pos, float(actor.radius) + width * 0.5)
			if at != INF: contacts.append({"actor": actor, "at": at})
		contacts.sort_custom(func(a, b): return float(a.at) < float(b.at) if not is_equal_approx(float(a.at), float(b.at)) else int(a.actor.id) < int(b.actor.id))
	else:
		contacts.append({"actor": target, "at": 0.0})
		if int(level.target_cap) > 1:
			var direction: Vector2 = (target.pos - unit.pos).normalized()
			for actor in _sorted_targets(run, unit.pos, float(level.cleave_radius), true, false):
				if int(actor.id) == int(target.id): continue
				if direction.dot((actor.pos - unit.pos).normalized()) >= cos(deg_to_rad(float(level.cleave_angle_degrees) * 0.5)) - 0.000001:
					contacts.append({"actor": actor, "at": unit.pos.distance_to(actor.pos)})
	var count: int = 0
	var gem_contacts: Array = []
	for contact in contacts:
		if not _active(run) or count >= int(level.target_cap): break
		count += 1
		var actor: Dictionary = contact.actor
		var context: Dictionary = unit.context.duplicate(true)
		context.merge({"kind": "spirit_normal", "natural": false, "source_kind": "summon", "summon_id": unit.id,
			"source_spell_id": unit.spell_id, "attack_id": unit.attack_id,
			"summon_school_bonus": float(mechanics.mark_normal_pet_spirit_damage_bonus) + _mastery_value(run, "mark_normal_attack_bonus_add") if _marked(actor) else 0.0}, true)
		var before: float = float(actor.health)
		var base: float = _normal_noncritical_plan(run, actor, float(level.coefficient), context)
		run.resolve_summon_hit(actor, float(level.coefficient), context)
		gem_contacts.append({"actor": actor, "base": base, "actual": before - maxf(0.0, float(actor.health))})
	if run.has_method("gem_core"): run._gem_combat.schools.spirit_action(run, str(unit.spell_id), gem_contacts)
	run._emit("spirit_attack", {"from": unit.pos, "to": end, "pos": target.pos, "unit_id": unit.id,
		"spell_id": unit.spell_id, "family": unit.family, "attack_id": unit.attack_id}, float(effects.beam))


func _normal_noncritical_plan(run, actor: Dictionary, coefficient: float, context: Dictionary) -> float:
	if not run.has_method("gem_core") or run.gem_core() != "spirit": return 0.0
	# Match the existing normal-pet plan once, including its live mark condition,
	# while deliberately omitting critical RNG. The fixed core payout is already valued.
	var metadata: Dictionary = context.duplicate(true)
	metadata.merge({"school": "spirit", "kind": "summon", "natural": false, "can_crit": false}, true)
	var bonus: Dictionary = run._artifact_combat.modify_damage_context(run, actor, metadata)
	var damage: float = float(run.player.attack) * (1.0 + run._spell_combat.field_attack_bonus()) * coefficient * float(metadata.get("damage_scale", 1.0))
	damage *= (1.0 + school_bonus(run) + float(metadata.get("summon_school_bonus", 0.0))) * float(bonus.damage_multiplier)
	return damage * (1.0 + target_vulnerability(actor))

func _command_sources(run, target: Dictionary, level: Dictionary) -> Array:
	var sources: Array = []
	for unit in _live_units():
		if sources.size() >= int(level.command_unit_cap): break
		if unit.pos.distance_to(target.pos) <= float(level.range) + 0.000001 and run.line_is_clear(unit.pos, target.pos): sources.append(int(unit.id))
	return sources

func _update_pending(run) -> void:
	var retained: Array = []
	for item in pending:
		if not _active(run): break
		if float(item.at) > clock + 0.000001:
			retained.append(item)
			continue
		var target: Dictionary = _actor(run, int(item.actor_id))
		if target.is_empty(): continue
		var level: Dictionary = item.context.spirit_level
		for source_id in item.source_ids:
			var unit: Dictionary = _unit(int(source_id))
			if unit.is_empty() or target.is_empty() or float(target.health) <= 0.0: continue
			if unit.pos.distance_to(target.pos) > float(level.range) + 0.000001 or not run.line_is_clear(unit.pos, target.pos): continue
			var context: Dictionary = item.context.duplicate(true)
			context.merge({"kind": "spirit_command", "natural": false, "source_kind": "spirit_derived", "summon_id": source_id}, true)
			run.resolve_school_derived_hit(target, float(level.command_coefficient), context)
			run._emit("spirit_command_hit", {"from": unit.pos, "to": target.pos, "pos": target.pos, "unit_id": source_id, "spell_id": "S05"}, float(effects.command))
	pending = retained

func _recall(run, center: Vector2, context: Dictionary) -> void:
	var level: Dictionary = context.spirit_level
	var candidates: Array = []
	for unit in _live_units():
		if float(unit.expires) - clock <= float(level.consume_max_remaining) + 0.000001: candidates.append(unit)
	candidates.sort_custom(func(a, b): return float(a.expires) < float(b.expires) if not is_equal_approx(float(a.expires), float(b.expires)) else int(a.id) < int(b.id))
	var coefficient: float = float(level.base_coefficient)
	var consumed_id: int = -1
	if not candidates.is_empty():
		var chosen: Dictionary = candidates[0]
		consumed_id = int(chosen.id)
		chosen["consumed"] = true
		units = units.filter(func(unit): return int(unit.id) != consumed_id)
		if run.has_method("gem_core"): run._gem_combat.schools.spirit_presence(run)
		coefficient += float(level.consume_bonus_coefficient)
		# Each delayed command rechecks registration. Removing its source here is
		# sufficient even if this command was queued before the recall.
	var direct_context: Dictionary = context.duplicate(true)
	direct_context.merge({"kind": "area", "echo_shape_recorded": true}, true)
	if run.has_method("gem_record_shape"):
		run.gem_record_shape({"kind": "area", "pos": center, "radius": level.radius, "block": true, "target_cap": int(level.target_cap)}, coefficient, direct_context)
	var count: int = 0
	for actor in _sorted_targets(run, center, float(level.radius), true, false):
		if not _active(run) or count >= int(level.target_cap): break
		count += 1
		_direct_hit(run, actor, coefficient, direct_context)
	run._emit("spirit_recall", {"pos": center, "radius": level.radius, "consumed_id": consumed_id, "spell_id": "S06"}, float(effects.burst))

func _covered(run, field: Dictionary, unit: Dictionary) -> bool:
	return float(field.expires) > clock + 0.000001 and unit.pos.distance_to(field.pos) <= float(field.radius) + 0.000001 and run.line_is_clear(field.pos, unit.pos)

func _update_fields(run) -> void:
	var retained: Array = []
	for field in fields:
		if float(field.expires) <= clock + 0.000001: continue
		var level: Dictionary = field.context.spirit_level
		for unit in _live_units():
			if field.granted.has(int(unit.id)) or not _covered(run, field, unit): continue
			field.granted[int(unit.id)] = true
			var extension: float = minf(float(level.extension_per_unit), maxf(0.0, float(level.lifetime_extension_cap) - float(unit.extension_used)))
			unit.expires = float(unit.expires) + extension
			unit.extension_used = float(unit.extension_used) + extension
			unit.remaining = maxf(0.0, float(unit.expires) - clock)
		field["remaining"] = maxf(0.0, float(field.expires) - clock)
		retained.append(field)
	fields = retained

func _chains(run, target: Dictionary, context: Dictionary) -> void:
	var level: Dictionary = context.spirit_level
	var selected: Array = [target]
	for actor in _sorted_targets(run, target.pos, float(level.secondary_radius), true, false):
		if int(actor.id) != int(target.id) and selected.size() < int(level.target_cap): selected.append(actor)
	var main: bool = true
	for actor in selected:
		if not _active(run): break
		var premarked: bool = _marked(actor)
		var actual: float = _direct_hit(run, actor, float(level.coefficient), context)
		if actual > 0.0 and float(actor.health) > 0.0:
			var slow: float = float(level.marked_slow) if premarked else float(level.base_slow)
			var category: String = run._spell_combat.ice.status.category(actor)
			run._spell_combat.apply_slow(run, actor, minf(slow, float(mechanics.control_slow_caps[category])), float(level.slow_duration), "S08")
			if main and bool(level.can_apply_mark): _apply_mark(run, actor, float(level.mark_duration))
		run._emit("spirit_chain", {"from": run.player.pos if main else target.pos, "to": actor.pos, "pos": actor.pos, "spell_id": "S08"}, float(effects.chain))
		main = false

func _update_projectiles(run, dt: float) -> void:
	var retained: Array = []
	for bolt in projectiles:
		if not _active(run): break
		var level: Dictionary = bolt.context.spirit_level
		var origin: Vector2 = bolt.pos
		var distance: float = minf(float(level.projectile_speed) * dt, float(level.range) - float(bolt.travelled))
		var end: Vector2 = origin + bolt.direction * distance
		var wall: float = run._first_block_contact(origin, end, float(level.projectile_radius))
		var contacts: Array = []
		for actor in run.actors:
			if float(actor.health) <= 0.0 or int(actor.id) in bolt.visited: continue
			var at: float = run.segment_circle_time(origin - actor.get("previous", actor.pos), end - actor.pos, Vector2.ZERO, float(actor.radius) + float(level.projectile_radius))
			if at < wall - 0.000001: contacts.append({"actor": actor, "at": at})
		contacts.sort_custom(func(a, b): return float(a.at) < float(b.at) if not is_equal_approx(float(a.at), float(b.at)) else int(a.actor.id) < int(b.actor.id))
		for contact in contacts:
			if not _active(run) or bolt.visited.size() >= int(level.target_cap): break
			var actor: Dictionary = contact.actor
			var main: bool = bolt.visited.is_empty()
			bolt.visited.append(int(actor.id))
			var actual: float = _direct_hit(run, actor, float(level.coefficient), bolt.context)
			if main and actual > 0.0 and float(actor.health) > 0.0: _apply_mark(run, actor, float(level.mark_duration))
		bolt.pos = end
		bolt.travelled = float(bolt.travelled) + distance
		if wall == INF and bolt.visited.size() < int(level.target_cap) and float(bolt.travelled) < float(level.range) - 0.000001: retained.append(bolt)
	projectiles = retained

func _direct_hit(run, actor: Dictionary, coefficient: float, context: Dictionary) -> float:
	if not _active(run) or actor.is_empty() or float(actor.get("health", 0.0)) <= 0.0: return 0.0
	context["gem_echo_eligible"] = bool(context.get("natural", false))
	if run.has_method("gem_record_shape") and not bool(context.get("echo_shape_recorded", false)):
		run.gem_record_shape({"kind": "area", "pos": actor.pos, "radius": 0.0, "block": true, "target_cap": 1}, coefficient, context)
	var before: float = float(actor.health)
	run.resolve_spell_hit(actor, coefficient, context)
	var actual: float = before - maxf(0.0, float(actor.health))
	if actual > 0.0 and run.has_method("gem_after_spell_status"): run.gem_after_spell_status(actor, context)
	return actual

func _apply_mark(run, actor: Dictionary, duration: float) -> void:
	if float(actor.get("health", 0.0)) <= 0.0: return
	var actual: float = duration + _mastery_value(run, "mark_duration_add")
	mark = {"actor_id": int(actor.id), "pos": actor.pos, "expires": clock + actual}
	run._emit("spirit_mark", {"pos": actor.pos, "actor_id": actor.id, "duration": actual, "spell_id": "spirit"}, float(effects.mark))

func _marked(actor: Dictionary) -> bool:
	return not mark.is_empty() and int(mark.actor_id) == int(actor.id) and float(mark.expires) > clock + 0.000001

func _preferred(run, origin: Vector2, reach: float, prefer_mark: bool) -> Dictionary:
	var targets: Array = _sorted_targets(run, origin, reach, true, prefer_mark)
	return targets[0] if not targets.is_empty() else {}

func _sorted_targets(run, origin: Vector2, reach: float, clear: bool, prefer_mark: bool) -> Array:
	var targets: Array = []
	for actor in run.actors:
		if float(actor.health) > 0.0 and origin.distance_to(actor.pos) <= reach + 0.000001 and (not clear or run.line_is_clear(origin, actor.pos)): targets.append(actor)
	targets.sort_custom(func(a, b):
		if prefer_mark and _marked(a) != _marked(b): return _marked(a)
		var ad: float = origin.distance_squared_to(a.pos)
		var bd: float = origin.distance_squared_to(b.pos)
		return ad < bd if not is_equal_approx(ad, bd) else int(a.id) < int(b.id))
	return targets

func _actor(run, id: int) -> Dictionary:
	for actor in run.actors:
		if int(actor.id) == id and float(actor.health) > 0.0: return actor
	return {}

func _has_enemy(run) -> bool:
	for actor in run.actors:
		if float(actor.health) > 0.0: return true
	return false

func _queue(at: float, kind: String, values: Dictionary) -> void:
	values.merge({"id": _new_id(), "kind": kind, "at": at}, true)
	pending.append(values)

func _new_id() -> int:
	var value: int = _next_id
	_next_id += 1
	return value

func _active(run) -> bool:
	return run.phase == "combat" and not run.paused and float(run.player.health) > 0.0
