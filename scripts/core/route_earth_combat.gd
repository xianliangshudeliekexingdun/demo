extends RefCounted
## Finite, nonblocking earth constructions. No construction is an actor/collider.

var mechanics: Dictionary = {}
var effects: Dictionary = {}
var source_spells: Dictionary = {}
var constructs: Array = []
var pending: Array = []
var projectiles: Array = []
var waves: Array = []
var stuns: Dictionary = {}
var terminations: Array = []
var clock: float = 0.0
var _next_id: int = 1
var _last_tick: float = -INF
var _new_builds: Array = []

func configure(source: Dictionary) -> Dictionary:
	if not source.get("mechanics") is Dictionary or not source.get("spells") is Dictionary or source.spells.size() != 10:
		return {"ok": false, "error": "正式岩系源缺失或数量无效。"}
	mechanics = source.mechanics.duplicate(true)
	effects = source.get("effects", {}).duplicate(true)
	source_spells = source.spells.duplicate(true)
	if not mechanics.has_all(["initial_ids", "resonance", "construct_sources", "control_coefficients", "construct_max_lifetime"]):
		return {"ok": false, "error": "正式岩系机制缺失。"}
	for key in ["hit", "impact", "wave", "construct", "consume", "echo", "shield", "stun"]:
		if not effects.has(key) or not is_finite(float(effects[key])) or float(effects[key]) <= 0.0:
			return {"ok": false, "error": "正式岩系表现参数无效：" + key}
	for number in range(1, 11):
		var id: String = "R%02d" % number
		var spec: Dictionary = source_spells.get(id, {})
		if str(spec.get("school", "")) != "earth" or not spec.get("levels") is Array or spec.levels.size() != 3:
			return {"ok": false, "error": "正式岩系三级源无效：" + id}
		for level in spec.levels:
			if not level is Dictionary or not level.has("cooldown") or not is_finite(float(level.cooldown)) or float(level.cooldown) < 0.0:
				return {"ok": false, "error": "正式岩系冷却无效：" + id}
	stop_room()
	return {"ok": true, "error": ""}

func stop_room() -> void:
	constructs.clear()
	pending.clear()
	projectiles.clear()
	waves.clear()
	stuns.clear()
	_secondary_hits.clear()
	_new_builds.clear()
	terminations.clear()
	clock = 0.0
	_last_tick = -INF
	_next_id = 1

func before_tick(run, dt: float) -> void:
	if not _active(run) or absf(_last_tick - float(run.time)) <= 0.000000001: return
	_last_tick = float(run.time)
	clock += maxf(0.0, dt)
	for actor_id in stuns.keys():
		if float(stuns[actor_id]) <= clock + _epsilon(): stuns.erase(actor_id)

func is_earth_spell(id: String) -> bool:
	return source_spells.has(id)

func reward_eligible(run, id: String) -> bool:
	if not is_earth_spell(id): return false
	var required: Array = source_spells[id].get("required_any_spells", [])
	if required.is_empty(): return true
	for owned in run.spells:
		if str(owned.id) in required: return true
	return false

func spell_count(run) -> int:
	var found: Dictionary = {}
	for spell in run.spells:
		if is_earth_spell(str(spell.id)): found[str(spell.id)] = true
	return found.size()

func school_bonus(run) -> float:
	return _mastery(run, "earth_bonus") + (float(mechanics.resonance.school_damage_bonus) if spell_count(run) >= int(mechanics.resonance.distinct_spells) else 0.0)

func cooldown_bonus(run) -> float:
	return float(mechanics.resonance.school_cdr) if spell_count(run) >= int(mechanics.resonance.distinct_spells) else 0.0

func _mastery(run, key: String) -> float:
	var spell: Dictionary = run._owned_spell("R10")
	return float(run.get_spell_stats(spell).level.get(key, 0.0)) if not spell.is_empty() else 0.0

func target_vulnerability(_actor: Dictionary) -> float:
	return 0.0

func remove_actor_status(actor_id: int) -> void:
	stuns.erase(actor_id)

func actor_stunned(actor: Dictionary) -> bool:
	return float(stuns.get(int(actor.get("id", -1)), -INF)) > clock + _epsilon()

func control_state(actor: Dictionary) -> Dictionary:
	return {"frozen": actor_stunned(actor), "earth_stun": actor_stunned(actor)}

func defense_bonus(run) -> float:
	var result: float = _mastery(run, "shielded_defense") if float(run.player.get("shield", 0.0)) > 0.0 else 0.0
	for construct in constructs:
		if str(construct.spell_id) != "R09" or float(construct.expires) <= clock + _epsilon(): continue
		var inside: bool = run.player.pos.distance_to(construct.pos) <= float(construct.radius) + _epsilon()
		var clear: bool = run.line_is_clear(run.player.pos, construct.pos)
		if clear and (inside or float(construct.get("grace_until", -INF)) > clock + _epsilon()):
			result += float(construct.defense)
	return result

func after_player_motion(run) -> void:
	# Authoritative movement boundary, called after the school clock advances and
	# before enemy damage. Snapshot/defense reads never create or refresh grace.
	if _active(run): _update_guard(run)

func get_snapshot(run) -> Dictionary:
	return {"earth_constructs": constructs.duplicate(true), "earth_pending": pending.duplicate(true),
		"earth_projectiles": projectiles.duplicate(true), "earth_waves": waves.duplicate(true),
		"earth_clock": clock, "earth_defense": defense_bonus(run), "earth_terminations": terminations.duplicate(true)}

func legal_target(run, spell: Dictionary, stats: Dictionary) -> Dictionary:
	if not _active(run) or str(stats.kind) == "passive": return {}
	var id: String = str(spell.id)
	var level: Dictionary = stats.level
	if id == "R05":
		return {"id": -1, "pos": run.player.pos} if float(run.player.shield) < float(run.player.max_shield) - _epsilon() and _has_enemy(run) else {}
	if id == "R06": return _consumable(run, level)
	if id == "R09":
		return {"id": -1, "pos": run.player.pos} if not _targets(run, run.player.pos, float(level.range)).is_empty() and _legal_floor(run, run.player.pos) else {}
	var found: Array = _targets(run, run.player.pos, float(level.get("range", level.get("radius", 0.0))))
	if id == "R08":
		found.sort_custom(func(a, b): return float(a.health) > float(b.health) if not is_equal_approx(float(a.health), float(b.health)) else _distance_before(a, b, run.player.pos))
	return found[0] if not found.is_empty() else {}

func finish_target(run, spell: Dictionary, stats: Dictionary) -> Dictionary:
	if str(spell.id) in ["R02", "R05", "R06", "R09"]: return legal_target(run, spell, stats)
	if str(spell.id) in ["R03", "R08"]:
		var point: Vector2 = spell.get("locked_pos", run.player.pos)
		return {"id": int(spell.get("target_id", -1)), "pos": point} if _active(run) and _legal_floor(run, point) else {}
	var original: Dictionary = _actor(run, int(spell.get("target_id", -1)))
	return original if not original.is_empty() and run.player.pos.distance_to(original.pos) <= float(stats.level.range) + _epsilon() and run.line_is_clear(run.player.pos, original.pos) else {}

func cast(run, spell: Dictionary, stats: Dictionary, target: Dictionary, source_context: Dictionary) -> void:
	if not _active(run): return
	var level: Dictionary = stats.level.duplicate(true)
	var context: Dictionary = source_context.duplicate(true)
	context.merge({"earth_level": level, "earth_direct": true, "school": "earth", "kind": "area" if str(stats.kind) == "area" else "direct", "spell_level": int(spell.level)}, true)
	var id: String = str(spell.id)
	match id:
		"R01":
			_projectile(run.player.pos, (target.pos - run.player.pos).normalized(), float(level.speed), float(level.range), float(level.width), float(level.main), context, "main", 1, [])
		"R02":
			waves.append({"id": _new_id(), "pos": run.player.pos, "distance": 0.0, "hit_ids": [], "context": context})
		"R03", "R08":
			var point: Vector2 = spell.get("locked_pos", target.pos)
			_queue(clock + float(level.delay), "fall", {"pos": point, "origin": run.player.pos, "context": context})
			run._emit("earth_telegraph", {"pos": point, "radius": level.radius, "spell_id": id}, float(level.delay))
		"R04":
			_build(run, id, target.pos, float(level.duration), float(level.radius), context)
		"R05":
			var restored: float = run.restore_player_shield(float(level.shield_restore), id)
			run._emit("earth_shield", {"pos": run.player.pos, "amount": restored, "spell_id": id}, float(effects.shield))
		"R06":
			# Recheck immediately, so an extra cannot reuse a source consumed by its parent.
			var chosen: Dictionary = _consumable(run, level)
			if chosen.is_empty(): return
			var point: Vector2 = chosen.pos
			_end_construct(run, chosen, "consumption")
			_queue(clock + float(level.delay), "collapse", {"pos": point, "context": context})
		"R07":
			_area(run, target.pos, float(level.main_radius), float(level.main), context)
			var sources: Array = _near_sources(run, target.pos, float(level.anchor_search_range))
			for index in mini(sources.size(), int(level.echo_construct_cap)):
				var construct: Dictionary = sources[index]
				_queue(clock + float(level.echo_delay) * float(index + 1), "echo", {"source_id": construct.id, "pos": construct.pos, "radius": level.echo_radius, "coefficient": float(level.echo) if index == 0 else float(level.second_echo), "context": context})
		"R09":
			_build(run, id, run.player.pos, float(level.duration), float(level.radius), context)

func update_existing(run, dt: float) -> void:
	if not _active(run): return
	_update_projectiles(run, dt)
	_update_waves(run, dt)
	_update_due(run)
	_expire(run)
	for request in _new_builds:
		_build(run, request.spell_id, request.pos, request.duration, request.radius, request.context)
	_new_builds.clear()
	_update_guard(run)
	_clean_secondary_ledger()
	if run.has_method("gem_core"): run._gem_combat.schools.earth_tick(run, dt)

func _update_due(run) -> void:
	var due: Array = []
	for construct in constructs:
		if str(construct.spell_id) != "R04": continue
		var level: Dictionary = construct.context.earth_level
		while float(construct.next_at) <= minf(clock, float(construct.expires)) + _epsilon():
			due.append({"id": _new_id(), "at": construct.next_at, "kind": "pulse", "source_id": construct.id, "pos": construct.pos, "context": construct.context})
			construct.next_at = float(construct.next_at) + float(level.interval)
	var retained: Array = []
	for item in pending:
		if float(item.at) <= clock + _epsilon(): due.append(item)
		else: retained.append(item)
	pending = retained
	due.sort_custom(func(a, b): return float(a.at) < float(b.at) if not is_equal_approx(float(a.at), float(b.at)) else int(a.id) < int(b.id))
	for item in due:
		if not _active(run): break
		var context: Dictionary = item.context
		var level: Dictionary = context.earth_level
		match str(item.kind):
			"pulse":
				if not _construct(int(item.source_id)).is_empty():
					var area_context: Dictionary = context.duplicate(true)
					area_context.kind = "area"
					_area(run, item.pos, float(level.radius), float(level.tick), area_context)
			"fall":
				_fall(run, item)
			"after":
				_area(run, item.pos, float(level.after_radius), float(level.after), context)
			"collapse":
				_area(run, item.pos, float(level.radius), float(level.main), context)
				if float(level.after) > 0.0:
					_queue(float(item.at) + float(level.after_delay), "collapse_after", {"pos": item.pos, "context": context})
			"collapse_after":
				_area(run, item.pos, float(level.radius), float(level.after), context, true)
			"echo":
				if not _construct(int(item.source_id)).is_empty():
					_area(run, item.pos, float(item.radius), float(item.coefficient), context, true)
			"shards":
				for angle in mechanics.shard_angles_degrees:
					_projectile(item.pos, item.direction.rotated(deg_to_rad(float(angle))), float(level.shard_speed), float(level.shard_range), float(level.shard_width), float(level.shard), context, "shard", int(level.shard_pierce), [int(item.main_id)])
			"fractures":
				var direction: Vector2 = (item.pos - item.origin).normalized()
				if direction.is_zero_approx(): direction = Vector2.DOWN
				for angle in mechanics.fracture_angles_degrees:
					var ray: Vector2 = direction.rotated(deg_to_rad(float(angle)))
					_projectile(item.pos + ray * float(level.radius), ray, float(level.fracture_speed), float(level.fracture_length), float(level.fracture_width), float(level.fracture), context, "fracture", -1, item.excluded)

func _fall(run, item: Dictionary) -> void:
	var context: Dictionary = item.context
	var level: Dictionary = context.earth_level
	var hit_ids: Array = _area(run, item.pos, float(level.radius), float(level.main), context)
	if str(context.spell_id) == "R03":
		# Support belongs to the actual landing, including an otherwise missed impact.
		if _legal_floor(run, item.pos): _new_builds.append({"spell_id": "R03", "pos": item.pos, "duration": float(level.construct_duration), "radius": float(level.radius), "context": context})
		if float(level.after) > 0.0:
			_queue(float(item.at) + float(level.after_delay), "after", {"pos": item.pos, "context": context})
	else:
		for actor_id in hit_ids:
			var actor: Dictionary = _actor(run, int(actor_id))
			if not actor.is_empty(): _stun(run, actor, float(level.stun))
		if float(level.fracture) > 0.0:
			_queue(float(item.at) + float(level.fracture_delay), "fractures", {"pos": item.pos, "origin": item.origin, "excluded": hit_ids, "context": context})

func _build(run, spell_id: String, point: Vector2, duration: float, radius: float, context: Dictionary) -> void:
	if not _active(run) or not _legal_floor(run, point): return
	for old in constructs.duplicate():
		if str(old.spell_id) == spell_id: _end_construct(run, old, "replacement")
	if constructs.size() >= int(mechanics.construct_global_cap): return
	var level: Dictionary = context.earth_level
	var lifetime: float = minf(duration, float(mechanics.construct_max_lifetime))
	var construct: Dictionary = {"id": _new_id(), "spell_id": spell_id, "cast_id": context.cast_id,
		"pos": point, "radius": radius, "born_at": clock, "expires": clock + lifetime, "remaining": lifetime,
		"blocking": false, "targetable": false, "context": context.duplicate(true)}
	if spell_id == "R04": construct["next_at"] = clock + float(level.first_tick)
	if spell_id == "R09":
		construct.merge({"defense": level.defense, "exit_grace": level.exit_grace, "was_covered": true, "grace_until": -INF})
	constructs.append(construct)
	run._emit("earth_construct", {"pos": point, "radius": radius, "source_id": construct.id, "spell_id": spell_id, "duration": lifetime}, float(effects.construct))
	# The level-three first pulse is part of this release, never a second cast.
	if spell_id == "R04" and float(level.first_tick) <= _epsilon():
		var area_context: Dictionary = context.duplicate(true)
		area_context.kind = "area"
		_area(run, point, radius, float(level.tick), area_context)
		construct.next_at = clock + float(level.interval)

func _end_construct(run, construct: Dictionary, reason: String) -> void:
	if _construct(int(construct.id)).is_empty(): return
	constructs.erase(construct)
	if run.has_method("gem_core"): run._gem_combat.schools.earth_source_removed(int(construct.id))
	var event: Dictionary = {"id": construct.id, "spell_id": construct.spell_id, "reason": reason, "at": clock}
	terminations.append(event)
	# Bounded diagnostic history; source-dependent callbacks never transfer identity.
	if terminations.size() > int(mechanics.termination_history_cap): terminations.pop_front()
	var retained: Array = []
	for item in pending:
		if int(item.get("source_id", -1)) != int(construct.id): retained.append(item)
	pending = retained
	run._emit("earth_construct_end", {"pos": construct.pos, "source_id": construct.id, "spell_id": construct.spell_id, "reason": reason}, float(effects.consume))

func _expire(run) -> void:
	for construct in constructs.duplicate():
		construct.remaining = maxf(0.0, float(construct.expires) - clock)
		if float(construct.expires) <= clock + _epsilon(): _end_construct(run, construct, "natural_expiry")

func _update_guard(run) -> void:
	for construct in constructs:
		if str(construct.spell_id) != "R09": continue
		var inside: bool = run.player.pos.distance_to(construct.pos) <= float(construct.radius) + _epsilon()
		var clear: bool = run.line_is_clear(run.player.pos, construct.pos)
		if not clear:
			construct.grace_until = -INF
		elif inside:
			construct.grace_until = -INF
		elif bool(construct.was_covered):
			construct.grace_until = clock + float(construct.exit_grace)
		construct.was_covered = inside and clear

func _consumable(run, level: Dictionary) -> Dictionary:
	var found: Array = []
	for construct in constructs:
		if float(construct.expires) <= clock + _epsilon() or run.player.pos.distance_to(construct.pos) > float(level.range) + _epsilon(): continue
		if not _targets(run, construct.pos, float(level.radius), true).is_empty(): found.append(construct)
	found.sort_custom(func(a, b): return float(a.expires) < float(b.expires) if not is_equal_approx(float(a.expires), float(b.expires)) else int(a.id) < int(b.id))
	return found[0] if not found.is_empty() else {}

func _near_sources(run, point: Vector2, radius: float) -> Array:
	var found: Array = []
	for construct in constructs:
		if float(construct.expires) > clock + _epsilon() and point.distance_to(construct.pos) <= radius + _epsilon() and run.line_is_clear(point, construct.pos): found.append(construct)
	found.sort_custom(func(a, b): return _distance_before(a, b, point))
	return found

func _construct(id: int) -> Dictionary:
	for construct in constructs:
		if int(construct.id) == id: return construct
	return {}

func _projectile(point: Vector2, direction: Vector2, speed: float, reach: float, width: float, coefficient: float, context: Dictionary, component: String, pierce: int, excluded: Array) -> void:
	projectiles.append({"id": _new_id(), "pos": point, "direction": direction, "speed": speed, "range": reach, "width": width,
		"travelled": 0.0, "coefficient": coefficient, "context": context.duplicate(true), "component": component, "pierce": pierce, "hits": [], "excluded": excluded.duplicate()})

func _update_projectiles(run, dt: float) -> void:
	var retained: Array = []
	for shot in projectiles:
		if not _active(run): break
		var distance: float = minf(float(shot.speed) * dt, float(shot.range) - float(shot.travelled))
		var start: Vector2 = shot.pos
		var end: Vector2 = start + shot.direction * distance
		var wall: float = run._first_block_contact(start, end, float(shot.width) * 0.5)
		var candidates: Array = []
		for actor in run.actors:
			if float(actor.health) <= 0.0 or int(actor.id) in shot.hits or int(actor.id) in shot.excluded: continue
			if str(shot.component) != "main" and _cast_secondary_has(shot.context, int(actor.id)): continue
			var t: float = run.segment_circle_time(start - actor.get("previous", actor.pos), end - actor.pos, Vector2.ZERO, float(shot.width) * 0.5 + float(actor.radius))
			if t >= 0.0 and t <= 1.0 and (wall == INF or t < wall - _epsilon()): candidates.append({"actor": actor, "t": t})
		candidates.sort_custom(func(a, b): return float(a.t) < float(b.t) if not is_equal_approx(float(a.t), float(b.t)) else int(a.actor.id) < int(b.actor.id))
		var ended: bool = wall != INF
		for candidate in candidates:
			if not _active(run): break
			var actor: Dictionary = candidate.actor
			if float(actor.health) <= 0.0: continue
			if str(shot.component) != "main" and _cast_secondary_has(shot.context, int(actor.id)): continue
			var hitpoint: Vector2 = start.lerp(end, float(candidate.t))
			var actual: float = _hit(run, actor, float(shot.coefficient), shot.context)
			shot.hits.append(int(actor.id))
			if str(shot.component) != "main": _mark_secondary(shot.context, int(actor.id))
			if str(shot.component) == "main" and actual > 0.0:
				_queue(clock + float(shot.context.earth_level.shard_delay), "shards", {"pos": hitpoint, "direction": shot.direction, "main_id": int(actor.id), "context": shot.context})
			if int(shot.pierce) > 0 and shot.hits.size() >= int(shot.pierce): ended = true; break
		shot.pos = end
		shot.travelled = float(shot.travelled) + distance
		if not ended and float(shot.travelled) < float(shot.range) - _epsilon(): retained.append(shot)
	projectiles = retained

# Secondary hits share one finite cast ledger across the three/two independent rays.
var _secondary_hits: Dictionary = {}
func _cast_secondary_has(context: Dictionary, actor_id: int) -> bool:
	return actor_id in _secondary_hits.get(int(context.cast_id), [])
func _mark_secondary(context: Dictionary, actor_id: int) -> void:
	var id: int = int(context.cast_id)
	if not _secondary_hits.has(id): _secondary_hits[id] = []
	_secondary_hits[id].append(actor_id)

func _clean_secondary_ledger() -> void:
	var alive: Dictionary = {}
	for shot in projectiles: alive[int(shot.context.cast_id)] = true
	for item in pending: alive[int(item.context.cast_id)] = true
	for id in _secondary_hits.keys():
		if not alive.has(id): _secondary_hits.erase(id)

func _update_waves(run, dt: float) -> void:
	var retained: Array = []
	for wave in waves:
		var level: Dictionary = wave.context.earth_level
		var previous: float = float(wave.distance)
		wave.distance = minf(float(level.radius), previous + float(level.speed) * dt)
		for actor in _targets(run, wave.pos, float(wave.distance) + float(level.wave_width) * 0.5, true):
			if int(actor.id) in wave.hit_ids: continue
			var actual_distance: float = wave.pos.distance_to(actor.pos)
			if actual_distance + float(actor.radius) < previous - float(level.wave_width) * 0.5: continue
			var coefficient: float = float(level.main) + (float(level.outer_bonus) if actual_distance >= float(level.outer_threshold) - _epsilon() else 0.0)
			_hit(run, actor, coefficient, wave.context)
			wave.hit_ids.append(int(actor.id))
		run._emit("earth_wave", {"pos": wave.pos, "radius": wave.distance, "width": level.wave_width, "spell_id": "R02"}, float(effects.wave))
		if float(wave.distance) < float(level.radius) - _epsilon(): retained.append(wave)
	waves = retained

func _area(run, point: Vector2, radius: float, coefficient: float, context: Dictionary, derived: bool = false) -> Array:
	var hit_ids: Array = []
	var area_context: Dictionary = context.duplicate(true)
	area_context["echo_shape_recorded"] = true
	if not derived and run.has_method("gem_record_shape"):
		run.gem_record_shape({"kind": "area", "pos": point, "radius": radius, "block": true}, coefficient, context)
	for actor in _targets(run, point, radius, true):
		if not _active(run): break
		if _hit(run, actor, coefficient, area_context, derived) > 0.0: hit_ids.append(int(actor.id))
	run._emit("earth_echo" if derived else "earth_impact", {"pos": point, "radius": radius, "spell_id": context.spell_id, "derived": derived}, float(effects.echo if derived else effects.impact))
	return hit_ids

func _hit(run, actor: Dictionary, coefficient: float, context: Dictionary, derived: bool = false) -> float:
	if not _active(run) or actor.is_empty() or float(actor.health) <= 0.0: return 0.0
	if derived:
		var metadata: Dictionary = context.duplicate(true)
		metadata.merge({"kind": "earth_derived", "earth_direct": false, "natural": false, "can_crit": bool(mechanics.derived_can_crit)}, true)
		return run.resolve_school_derived_hit(actor, coefficient, metadata)
	context["gem_echo_eligible"] = bool(context.get("natural", false))
	if not bool(context.get("echo_shape_recorded", false)) and run.has_method("gem_record_shape"):
		run.gem_record_shape({"kind": "area", "pos": actor.pos, "radius": 0.0, "block": true, "target_cap": 1}, coefficient, context)
	var before: float = float(actor.health)
	run.resolve_spell_hit(actor, coefficient, context)
	var actual: float = before - maxf(0.0, float(actor.health))
	if actual > 0.0 and run.has_method("gem_after_spell_status"): run.gem_after_spell_status(actor, context)
	return actual

func _stun(run, actor: Dictionary, duration: float) -> void:
	var category: String = str(mechanics.control_class_by_type.get(str(actor.get("type_id", actor.get("type", ""))), "normal"))
	if bool(actor.get("boss", false)) or bool(actor.get("fixed_strong", false)): category = "fixed_strong"
	elif bool(actor.get("elite", false)) and category == "normal": category = "elite"
	if bool(actor.get("control_immune", false)) or bool(actor.get("hard_control_immune", false)) or bool(actor.get("uninterruptible", false)): return
	var actual: float = duration * float(mechanics.control_coefficients[category])
	if actual <= _epsilon(): return
	stuns[int(actor.id)] = maxf(float(stuns.get(int(actor.id), clock)), clock + actual)
	run._emit("earth_stun", {"pos": actor.pos, "actor_id": actor.id, "duration": actual, "spell_id": "R08"}, float(effects.stun))

func _legal_floor(run, point: Vector2) -> bool:
	return absf(point.x) <= float(run.room_size.x) * 0.5 and absf(point.y) <= float(run.room_size.y) * 0.5 and run._first_block_contact(point, point, 0.0) == INF

func _targets(run, point: Vector2, radius: float, body: bool = false) -> Array:
	var found: Array = []
	for actor in run.actors:
		if float(actor.health) > 0.0 and point.distance_to(actor.pos) <= radius + (float(actor.radius) if body else 0.0) + _epsilon() and run.line_is_clear(point, actor.pos): found.append(actor)
	found.sort_custom(func(a, b): return _distance_before(a, b, point))
	return found

func _distance_before(a: Dictionary, b: Dictionary, point: Vector2) -> bool:
	var ad: float = point.distance_squared_to(a.pos)
	var bd: float = point.distance_squared_to(b.pos)
	return ad < bd if not is_equal_approx(ad, bd) else int(a.id) < int(b.id)

func _actor(run, id: int) -> Dictionary:
	for actor in run.actors:
		if int(actor.id) == id and float(actor.health) > 0.0: return actor
	return {}

func _has_enemy(run) -> bool:
	for actor in run.actors:
		if float(actor.health) > 0.0: return true
	return false

func _queue(at: float, kind: String, values: Dictionary) -> void:
	values.merge({"id": _new_id(), "at": at, "kind": kind}, true)
	pending.append(values)

func _new_id() -> int:
	var result: int = _next_id
	_next_id += 1
	return result

func _epsilon() -> float:
	return float(mechanics.geometry_epsilon)

func _active(run) -> bool:
	return run.phase == "combat" and not run.paused and float(run.player.health) > 0.0
