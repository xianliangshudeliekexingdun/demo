extends RefCounted
## Finite wind bodies, real voluntary paths and a static projectile-only guard.
## Geometry/levels belong to each release; offensive stats are read on hit.

var mechanics: Dictionary = {}
var effects: Dictionary = {}
var source_spells: Dictionary = {}
var clock: float = 0.0
var projectiles: Array = []
var pending: Array = []
var zones: Array = []
var path_segments: Array = []
var recording: Dictionary = {}
var states: Dictionary = {}
var _motion: Array = []
var _total_motion: float = 0.0
var _mastery_until: float = -INF
var _vortex_hits: Dictionary = {}
var _path_hits: Dictionary = {}
var _wing_hits: Dictionary = {}
var _next_id: int = 1
var _last_tick: float = -INF


func configure(source: Dictionary) -> Dictionary:
	if not source.get("mechanics") is Dictionary or not source.get("spells") is Dictionary or source.spells.size() != 10:
		return {"ok": false, "error": "正式风系源缺失或数量无效。"}
	mechanics = source.mechanics.duplicate(true)
	effects = source.get("effects", {}).duplicate(true)
	source_spells = source.spells.duplicate(true)
	if not mechanics.has_all(["resonance", "initial_ids", "control_coefficients", "shared_slow_caps", "motion_window", "path_hit_gate", "path_shared_window"]):
		return {"ok": false, "error": "正式风系机制参数缺失。"}
	for key in ["hit", "blade", "ring", "push", "impact", "mark", "path", "guard"]:
		if not _positive(effects.get(key)):
			return {"ok": false, "error": "正式风系表现时长无效：" + key}
	for number in range(1, 11):
		var id: String = "W%02d" % number
		var spec: Dictionary = source_spells.get(id, {})
		if str(spec.get("school", "")) != "wind" or not spec.get("levels") is Array or spec.levels.size() != 3:
			return {"ok": false, "error": "正式风系三级源无效：" + id}
		for level in spec.levels:
			if not level is Dictionary or not level.has("cooldown") or not is_finite(float(level.cooldown)) or float(level.cooldown) < 0.0:
				return {"ok": false, "error": "正式风系冷却源无效：" + id}
	stop_room()
	return {"ok": true, "error": ""}


func _positive(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0.0


func stop_room() -> void:
	clock = 0.0
	projectiles.clear()
	pending.clear()
	zones.clear()
	path_segments.clear()
	recording.clear()
	states.clear()
	_motion.clear()
	_total_motion = 0.0
	_mastery_until = -INF
	_vortex_hits.clear()
	_path_hits.clear()
	_wing_hits.clear()
	_next_id = 1
	_last_tick = -INF


func before_tick(run, dt: float) -> void:
	if not _active(run) or dt <= 0.0 or absf(_last_tick - float(run.time)) <= 0.000000001:
		return
	_last_tick = float(run.time)
	clock += dt
	var retained: Array = []
	for part in _motion:
		if float(part.at) > clock - float(mechanics.motion_window) + 0.000001: retained.append(part)
	_motion = retained
	_refresh_mastery(run)
	var alive: Dictionary = {}
	for actor in run.actors:
		if float(actor.health) > 0.0: alive[int(actor.id)] = true
	for actor_id in states.keys():
		if not alive.has(actor_id) or float(states[actor_id].until) <= clock + 0.000001: states.erase(actor_id)
	for actor_id in _vortex_hits.keys():
		if not alive.has(actor_id): _vortex_hits.erase(actor_id)
	for actor_id in _path_hits.keys():
		if not alive.has(actor_id): _path_hits.erase(actor_id)
		else:
			var hits: Array = []
			for at in _path_hits[actor_id]:
				if float(at) > clock - float(mechanics.path_shared_window) + 0.000001: hits.append(at)
			if hits.is_empty(): _path_hits.erase(actor_id)
			else: _path_hits[actor_id] = hits


func is_wind_spell(id: String) -> bool:
	return source_spells.has(id)


func spell_count(run) -> int:
	var distinct: Dictionary = {}
	for spell in run.spells:
		if is_wind_spell(str(spell.id)): distinct[str(spell.id)] = true
	return distinct.size()


func school_bonus(run) -> float:
	var result: float = 0.0
	var mastery: Dictionary = _mastery(run)
	if not mastery.is_empty():
		var valid: bool = motion_distance() + 0.000001 >= float(mastery.required_path)
		if valid or clock < _mastery_until - 0.000001: result += float(mastery.school_damage_bonus)
	if spell_count(run) >= int(mechanics.resonance.distinct_spells): result += float(mechanics.resonance.school_damage_bonus)
	return result


func cooldown_bonus(run) -> float:
	return float(mechanics.resonance.school_cdr) if spell_count(run) >= int(mechanics.resonance.distinct_spells) else 0.0


func target_vulnerability(actor: Dictionary) -> float:
	var state: Dictionary = states.get(int(actor.get("id", -1)), {})
	return float(state.amount) if not state.is_empty() and float(state.until) > clock + 0.000001 else 0.0


func remove_actor_status(actor_id: int) -> void:
	states.erase(actor_id)
	_path_hits.erase(actor_id)
	_vortex_hits.erase(actor_id)
	for ledger in _wing_hits.values(): ledger.erase(actor_id)


func movement_multiplier(actor: Dictionary) -> float:
	var amount: float = 0.0
	for entry in actor.get("spell_slows", {}).values():
		if str(entry.get("school", "")) == "wind" and float(entry.get("wind_until", 0.0)) > clock + 0.000001:
			amount = maxf(amount, float(entry.amount))
	return 1.0 - minf(amount, float(mechanics.shared_slow_caps[_category(actor)]))


func motion_distance() -> float:
	var length: float = 0.0
	for part in _motion:
		if float(part.at) > clock - float(mechanics.motion_window) + 0.000001: length += float(part.length)
	return length


func _mastery(run) -> Dictionary:
	var spell: Dictionary = run._owned_spell("W10")
	return run.get_spell_stats(spell).level if not spell.is_empty() else {}


func _refresh_mastery(run) -> void:
	var mastery: Dictionary = _mastery(run)
	if not mastery.is_empty() and motion_distance() + 0.000001 >= float(mastery.required_path):
		_mastery_until = clock + float(mastery.grace_duration)


func record_player_motion(run, from: Vector2, to: Vector2, dt: float) -> void:
	# Called only by the voluntary movement owner after actual collision sliding.
	# Teleports/knockback never call it; a held key against a wall yields zero.
	if not _active(run) or dt <= 0.0 or not from.is_finite() or not to.is_finite(): return
	var length: float = from.distance_to(to)
	if length <= 0.000001 or not run.line_is_clear(from, to): return
	if run.has_method("gem_core"): run._gem_combat.schools.wind_motion(run, length)
	_motion.append({"at": clock, "length": length})
	_total_motion += length
	_refresh_mastery(run)
	if recording.is_empty() or clock >= float(recording.until) - 0.000001: return
	var level: Dictionary = recording.context.wind_level
	var usable: float = minf(length, maxf(0.0, float(level.total_length) - float(recording.length)))
	if usable <= 0.000001: return
	var cursor: Vector2 = from
	var direction: Vector2 = (to - from) / length
	while usable > 0.000001:
		var take: float = minf(usable, float(level.spacing) - float(recording.buffer_length))
		var end: Vector2 = cursor + direction * take
		_append_piece(recording.buffer, cursor, end, float(level.radius))
		recording.buffer_length = float(recording.buffer_length) + take
		recording.length = float(recording.length) + take
		usable -= take
		cursor = end
		if float(recording.buffer_length) >= float(level.spacing) - 0.000001:
			for piece in recording.buffer:
				piece.merge({"id": _new_id(), "expires": clock + float(level.segment_lifetime), "remaining": float(level.segment_lifetime), "context": recording.context}, true)
				path_segments.append(piece)
			recording.buffer = []
			recording.buffer_length = 0.0
	# Damage is resolved once in update_existing after combat clocks/status advance.


func _append_piece(pieces: Array, from: Vector2, to: Vector2, radius: float) -> void:
	if not pieces.is_empty():
		var last: Dictionary = pieces.back()
		if last.to.distance_to(from) <= 0.000001 and (last.to - last.from).normalized().dot((to - from).normalized()) >= 0.999999:
			last.to = to
			return
	pieces.append({"from": from, "to": to, "width": radius, "radius": radius})


func legal_target(run, spell: Dictionary, stats: Dictionary) -> Dictionary:
	if not _active(run) or str(stats.kind) == "passive": return {}
	if str(spell.id) == "W09": return _incoming_projectile(run, float(stats.level.range))
	var found: Array = _targets(run, run.player.pos, float(stats.level.range))
	return found[0] if not found.is_empty() else {}


func finish_target(run, spell: Dictionary, stats: Dictionary) -> Dictionary:
	if str(spell.id) in ["W04", "W08", "W09"]: return legal_target(run, spell, stats)
	var original: Dictionary = _actor(run, int(spell.get("target_id", -1)))
	if original.is_empty() or run.player.pos.distance_to(original.pos) > float(stats.level.range) + 0.000001 or not run.line_is_clear(run.player.pos, original.pos): return {}
	return original


func cast(run, spell: Dictionary, stats: Dictionary, target: Dictionary, source_context: Dictionary) -> void:
	if not _active(run): return
	var level: Dictionary = stats.level.duplicate(true)
	var context: Dictionary = source_context.duplicate(true)
	context.merge({"kind": "direct", "school": "wind", "wind_level": level, "spell_level": int(spell.level)}, true)
	var id: String = str(spell.id)
	if run.has_method("gem_core"): run._gem_combat.schools.wind_cast(run, id, level, context)
	var origin: Vector2 = run.player.pos
	var direction: Vector2 = (target.pos - origin).normalized()
	if direction.length_squared() <= 0.000001: direction = Vector2.UP
	match id:
		"W01":
			var body: Dictionary = _body(id, origin, direction, float(level.speed), float(level.width) * 0.5, float(level.range), context)
			projectiles.append(body)
			_record_segment(run, origin, run._clip_motion(origin, direction * float(level.range), float(body.radius)), float(body.radius), float(level.coefficient), int(level.target_cap), context, {"falloff": level.falloff})
		"W02":
			var body: Dictionary = _body(id, origin, direction, float(level.out_speed), float(level.width) * 0.5, float(level.out_length), context)
			body.merge({"leg": "out", "lifetime": float(level.lifetime), "motion_start": _total_motion, "out_hits": {}, "return_hits": {}, "out_cleared": {}, "return_to": origin}, true)
			projectiles.append(body)
			_record_segment(run, origin, run._clip_motion(origin, direction * float(level.out_length), float(body.radius)), float(body.radius), float(level.out_coefficient), int(level.leg_target_cap), context)
		"W03":
			var body: Dictionary = _body(id, origin, direction, float(level.speed), float(level.width) * 0.5, float(level.max_path), context)
			body.merge({"target_id": int(target.id), "lifetime": float(level.lifetime), "turned": 0.0}, true)
			projectiles.append(body)
		"W04": _scatter(run, origin, direction, context)
		"W05":
			_remove_zone("wind_vortex")
			zones.append({"id": _new_id(), "kind": "wind_vortex", "spell_id": id, "pos": target.pos, "radius": level.radius, "born_at": clock, "expires": clock + float(level.duration), "next_at": clock + float(level.interval), "wave": 0, "planned_ticks": roundi(float(level.duration) / float(level.interval)), "context": context, "remaining": level.duration})
		"W06":
			var center: Vector2 = spell.get("locked_pos", target.pos)
			_queue(clock + float(level.impact_delay), "wind_vacuum", {"pos": center, "context": context})
			run._emit("wind_vacuum_flight", {"from": origin, "to": center, "pos": center, "radius": level.radius, "spell_id": id}, float(level.impact_delay))
		"W07":
			var forward: Vector2 = target.pos - origin
			var cross_at: Vector2 = origin + direction * maxf(float(level.minimum_cross_distance), forward.length())
			var tangent: Vector2 = Vector2(-direction.y, direction.x)
			_wing_hits[int(context.cast_id)] = {}
			for side in [-1, 1]:
				var start: Vector2 = run._clip_motion(origin, tangent * float(side) * float(level.offset), float(level.width) * 0.5)
				var wing_dir: Vector2 = (cross_at - start).normalized()
				var body: Dictionary = _body(id, start, wing_dir, float(level.speed), float(level.width) * 0.5, float(level.length), context)
				body["side"] = side
				projectiles.append(body)
				_record_segment(run, start, run._clip_motion(start, wing_dir * float(level.length), float(body.radius)), float(body.radius), float(level.coefficient), int(level.target_cap), context)
		"W08":
			path_segments.clear()
			recording = {"id": _new_id(), "kind": "wind_recording", "spell_id": id, "until": clock + float(level.record_duration), "length": 0.0, "buffer_length": 0.0, "buffer": [], "hits": {}, "context": context}
		"W09":
			_remove_zone("wind_guard")
			var center: Vector2 = run._clip_motion(origin, direction * float(level.offset), 0.0)
			zones.append({"id": _new_id(), "kind": "wind_guard", "spell_id": id, "pos": center, "normal": direction, "width": level.width, "depth": level.depth, "speed_multiplier": level.speed_multiplier, "expires": clock + float(level.duration), "remaining": level.duration, "context": context})
			run._emit("wind_guard", {"pos": center, "normal": direction, "width": level.width, "depth": level.depth, "spell_id": id}, float(effects.guard))


func _body(id: String, origin: Vector2, direction: Vector2, speed: float, radius: float, length: float, context: Dictionary) -> Dictionary:
	return {"id": _new_id(), "kind": "wind_projectile", "spell_id": id, "pos": origin, "from": origin, "direction": direction, "speed": speed, "radius": radius, "range": length, "travelled": 0.0, "hits": {}, "context": context, "echo_shape_recorded": true}


func update_existing(run, dt: float) -> void:
	if not _active(run): return
	_update_pending(run)
	_update_projectiles(run, dt)
	_update_zones(run)
	_update_path(run)
	var active_casts: Dictionary = {}
	for body in projectiles:
		if str(body.spell_id) == "W07": active_casts[int(body.context.cast_id)] = true
	for cast_id in _wing_hits.keys():
		if not active_casts.has(cast_id): _wing_hits.erase(cast_id)


func _update_projectiles(run, dt: float) -> void:
	var retained: Array = []
	for body in projectiles:
		if not _active(run): break
		var level: Dictionary = body.context.wind_level
		var id: String = str(body.spell_id)
		var use_dt: float = dt
		if body.has("lifetime"):
			use_dt = minf(dt, maxf(0.0, float(body.lifetime)))
			body.lifetime = maxf(0.0, float(body.lifetime) - dt)
		if id == "W03":
			var target: Dictionary = _actor(run, int(body.target_id))
			if not target.is_empty() and run.line_is_clear(body.pos, target.pos):
				var wanted: Vector2 = (target.pos - body.pos).normalized()
				var angle: float = body.direction.angle_to(wanted)
				var budget: float = maxf(0.0, deg_to_rad(float(level.turn_budget_degrees)) - float(body.turned))
				var turn: float = clampf(angle, -minf(deg_to_rad(float(level.turn_speed_degrees)) * use_dt, budget), minf(deg_to_rad(float(level.turn_speed_degrees)) * use_dt, budget))
				body.direction = body.direction.rotated(turn)
				body.turned = float(body.turned) + absf(turn)
		var old: Vector2 = body.pos
		var requested: float = minf(float(body.speed) * use_dt, maxf(0.0, float(body.range) - float(body.travelled)))
		var end: Vector2 = run._clip_motion(old, body.direction * requested, float(body.radius))
		var moved: float = old.distance_to(end)
		var blocked: bool = moved + 0.000001 < requested
		if id == "W02" and str(body.leg) == "return":
			var distance_left: float = old.distance_to(body.return_to)
			if moved > distance_left:
				end = body.return_to
				moved = distance_left
		var contacts: Array = _contacts(run, old, end, float(body.radius))
		var terminate: bool = false
		for contact in contacts:
			if not _active(run): break
			var actor: Dictionary = contact.actor
			var actor_id: int = int(actor.id)
			var context: Dictionary = body.context.duplicate(true)
			context["echo_shape_recorded"] = id != "W03"
			match id:
				"W01":
					if body.hits.has(actor_id) or body.hits.size() >= int(level.target_cap): continue
					var coefficient: float = float(level.coefficient) * pow(float(level.falloff), body.hits.size())
					body.hits[actor_id] = true
					_hit(run, actor, coefficient, context)
					if body.hits.size() >= int(level.target_cap): terminate = true
				"W02":
					var returning: bool = str(body.leg) == "return"
					var ledger: Dictionary = body.return_hits if returning else body.out_hits
					if ledger.has(actor_id) or ledger.size() >= int(level.leg_target_cap): continue
					if returning and body.out_hits.has(actor_id) and not bool(body.out_cleared.get(actor_id, false)): continue
					ledger[actor_id] = true
					var actual: float = _hit(run, actor, float(level.return_coefficient if returning else level.out_coefficient), context)
					if actual > 0.0 and returning and bool(context.get("natural", false)) and _total_motion - float(body.motion_start) + 0.000001 >= float(level.required_player_path) and float(level.return_vulnerability) > 0.0 and float(actor.health) > 0.0:
						states[actor_id] = {"actor_id": actor_id, "amount": level.return_vulnerability, "until": clock + float(level.vulnerability_duration)}
						run._emit("wind_mark", {"pos": actor.pos, "actor_id": actor_id, "spell_id": id}, float(effects.mark))
				"W03":
					var flown: float = float(body.travelled) + moved * float(contact.at)
					var coefficient: float = float(level.coefficient) * (float(level.long_multiplier) if flown + 0.000001 >= float(level.long_path) else 1.0)
					_hit(run, actor, coefficient, context)
					terminate = true
				"W07":
					if body.hits.has(actor_id) or body.hits.size() >= int(level.target_cap): continue
					body.hits[actor_id] = true
					var actual: float = _hit(run, actor, float(level.coefficient), context)
					if actual > 0.0:
						var ledger: Dictionary = _wing_hits.get(int(context.cast_id), {})
						var sides: Dictionary = ledger.get(actor_id, {})
						sides[int(body.side)] = true
						if sides.size() == 2 and not bool(sides.get("crossed", false)):
							sides["crossed"] = true
							if float(level.cross_coefficient) > 0.0: _derived(run, actor, float(level.cross_coefficient), context, "wind_cross")
						ledger[actor_id] = sides
						_wing_hits[int(context.cast_id)] = ledger
					if body.hits.size() >= int(level.target_cap): terminate = true
			if terminate: break
		body.pos = end
		body.travelled = float(body.travelled) + moved
		if id == "W02":
			for actor_id in body.out_hits:
				var actor: Dictionary = _actor(run, int(actor_id))
				if actor.is_empty() or end.distance_to(actor.pos) > float(body.radius) + float(actor.radius) + 0.000001: body.out_cleared[actor_id] = true
			if str(body.leg) == "out" and (blocked or float(body.travelled) >= float(body.range) - 0.000001):
				body.leg = "return"
				body.return_to = run.player.pos
				body.from = end
				body.direction = (body.return_to - end).normalized()
				body.range = end.distance_to(body.return_to)
				body.travelled = 0.0
				body.speed = float(level.return_speed)
				body.radius = float(level.width) * 0.5 * float(level.return_width_multiplier)
				_record_segment(run, end, run._clip_motion(end, body.direction * float(body.range), float(body.radius)), float(body.radius), float(level.return_coefficient), int(level.leg_target_cap), body.context)
				blocked = false
				if float(body.range) <= 0.000001: terminate = true
			elif str(body.leg) == "return" and float(body.travelled) >= float(body.range) - 0.000001: terminate = true
		elif float(body.travelled) >= float(body.range) - 0.000001: terminate = true
		if body.has("lifetime") and float(body.lifetime) <= 0.000001: terminate = true
		if not blocked and not terminate: retained.append(body)
	projectiles = retained


func _scatter(run, center: Vector2, direction: Vector2, context: Dictionary) -> void:
	var level: Dictionary = context.wind_level
	var hit_context: Dictionary = context.duplicate(true)
	hit_context["echo_shape_recorded"] = true
	if run.has_method("gem_record_shape"):
		run.gem_record_shape({"kind": "cone", "pos": center, "radius": level.range, "direction": direction, "angle_degrees": level.angle_degrees, "block": true}, float(level.coefficient), context)
	for actor in _targets(run, center, float(level.range), true):
		var offset: Vector2 = actor.pos - center
		if offset.length_squared() > 0.000001 and absf(direction.angle_to(offset)) > deg_to_rad(float(level.angle_degrees) * 0.5): continue
		if _hit(run, actor, float(level.coefficient), hit_context) <= 0.0 or float(actor.health) <= 0.0: continue
		_displace(run, actor, offset.normalized() * float(level.push_distance))
		if float(level.slow) > 0.0:
			var slow: float = minf(float(level.slow), float(mechanics.shared_slow_caps[_category(actor)]))
			var slows: Dictionary = actor.get("spell_slows", {})
			slows["wind_W04"] = {"school": "wind", "amount": slow, "until": float(run.time) + float(level.slow_duration), "wind_until": clock + float(level.slow_duration)}
			actor["spell_slows"] = slows
	run._emit("wind_scatter", {"pos": center, "direction": direction, "radius": level.range, "angle_degrees": level.angle_degrees, "spell_id": "W04"}, float(effects.push))


func _update_zones(run) -> void:
	var retained: Array = []
	for zone in zones:
		var level: Dictionary = zone.context.wind_level
		if str(zone.kind) == "wind_vortex":
			while float(zone.next_at) <= minf(clock, float(zone.expires)) + 0.000001 and _active(run):
				var at: float = float(zone.next_at)
				zone.next_at = at + float(level.interval)
				zone.wave = int(zone.wave) + 1
				var actors: Array = _targets(run, zone.pos, float(zone.radius), true)
				var context: Dictionary = zone.context.duplicate(true)
				context.merge({"kind": "area", "echo_shape_recorded": true}, true)
				if run.has_method("gem_record_shape"):
					run.gem_record_shape({"kind": "area", "pos": zone.pos, "radius": zone.radius, "block": true}, float(level.coefficient), zone.context)
				var pull_index: int = 0
				for actor in actors:
					var actor_id: int = int(actor.id)
					if at < float(_vortex_hits.get(actor_id, -INF)) + float(level.interval) - 0.000001: continue
					_vortex_hits[actor_id] = at
					_hit(run, actor, float(level.coefficient), context)
					if pull_index < int(level.pull_target_cap) and int(zone.wave) <= int(zone.planned_ticks) and float(actor.health) > 0.0:
						pull_index += 1
						var base: float = minf(float(level.pull_tick_cap), float(level.pull_total) / float(zone.planned_ticks))
						var offset: Vector2 = zone.pos - actor.pos
						_displace(run, actor, offset.normalized() * minf(base, offset.length()))
					run._emit("wind_vortex_hit", {"pos": actor.pos, "from": zone.pos, "actor_id": actor_id, "spell_id": "W05"}, float(effects.hit))
		zone.remaining = maxf(0.0, float(zone.expires) - clock)
		if float(zone.remaining) > 0.000001: retained.append(zone)
	zones = retained


func _update_pending(run) -> void:
	while not pending.is_empty() and _active(run):
		pending.sort_custom(func(a, b): return float(a.at) < float(b.at) if not is_equal_approx(float(a.at), float(b.at)) else int(a.id) < int(b.id))
		if float(pending[0].at) > clock + 0.000001: break
		var item: Dictionary = pending.pop_front()
		var level: Dictionary = item.context.wind_level
		var followup: bool = str(item.kind) == "wind_followup"
		var coefficient: float = float(level.followup_coefficient if followup else level.coefficient)
		var context: Dictionary = item.context.duplicate(true)
		context.merge({"kind": "area", "echo_shape_recorded": true}, true)
		var impact_radius: float = float(context.get("gem_wind_followup_radius", level.radius)) if followup else float(level.radius)
		if not followup and run.has_method("gem_record_shape"):
			var inner: float = (coefficient + float(level.center_coefficient_add)) / coefficient
			run.gem_record_shape({"kind": "area", "pos": item.pos, "radius": level.radius, "block": true, "inner_radius": level.center_radius, "inner_scale": inner, "outer_scale": 1.0}, coefficient, item.context)
		for actor in _targets(run, item.pos, impact_radius, true):
			if followup: _derived(run, actor, coefficient, context, "wind_followup")
			else:
				var add: float = float(level.center_coefficient_add) if item.pos.distance_to(actor.pos) <= float(level.center_radius) + float(actor.radius) + 0.000001 else 0.0
				_hit(run, actor, coefficient + add, context)
		run._emit("wind_vacuum_followup" if followup else "wind_vacuum", {"pos": item.pos, "radius": impact_radius, "spell_id": "W06", "derived": followup}, float(effects.impact))
		if not followup and float(level.followup_coefficient) > 0.0:
			_queue(float(item.at) + float(level.followup_delay), "wind_followup", {"pos": item.pos, "context": item.context})


func _update_path(run) -> void:
	var retained: Array = []
	for piece in path_segments:
		piece.remaining = maxf(0.0, float(piece.expires) - clock)
		if float(piece.remaining) > 0.000001: retained.append(piece)
	path_segments = retained
	if recording.is_empty() or path_segments.is_empty(): return
	var level: Dictionary = recording.context.wind_level
	var context: Dictionary = recording.context.duplicate(true)
	context.merge({"kind": "area", "echo_shape_recorded": true}, true)
	var contacts: Array = []
	for actor in run.actors:
		if float(actor.health) <= 0.0: continue
		for piece in path_segments:
			if run.segment_circle_time(piece.from, piece.to, actor.pos, float(piece.radius) + float(actor.radius)) != INF and run.line_is_clear(piece.from, actor.pos):
				contacts.append(actor)
				break
	contacts.sort_custom(func(a, b): return int(a.id) < int(b.id))
	var echo_recorded: bool = false
	for actor in contacts:
		var actor_id: int = int(actor.id)
		var history: Array = _path_hits.get(actor_id, [])
		var live: Array = []
		for at in history:
			if float(at) > clock - float(mechanics.path_shared_window) + 0.000001: live.append(at)
		if int(recording.hits.get(actor_id, 0)) >= int(level.cast_hit_cap) or live.size() >= int(level.shared_hit_cap): continue
		if not live.is_empty() and clock < float(live.back()) + float(mechanics.path_hit_gate) - 0.000001: continue
		if _hit(run, actor, float(level.coefficient), context) <= 0.0: continue
		live.append(clock)
		_path_hits[actor_id] = live
		recording.hits[actor_id] = int(recording.hits.get(actor_id, 0)) + 1
		if not echo_recorded and run.has_method("gem_record_shape"):
			var pieces: Array = []
			for piece in path_segments: pieces.append({"from": piece.from, "to": piece.to, "width": piece.radius})
			run.gem_record_shape({"kind": "segments", "segments": pieces, "block": true, "wind_path": true, "cast_id": context.cast_id, "per_actor_cap": level.cast_hit_cap, "shared_cap": level.shared_hit_cap, "shared_window": mechanics.path_shared_window, "hit_gate": mechanics.path_hit_gate}, float(level.coefficient), recording.context)
			echo_recorded = true
		run._emit("wind_path_hit", {"pos": actor.pos, "actor_id": actor_id, "spell_id": "W08"}, float(effects.path))


func projectile_speed_multiplier(run, pos: Vector2) -> float:
	if not _active(run): return 1.0
	var result: float = 1.0
	for zone in zones:
		if str(zone.kind) != "wind_guard" or float(zone.expires) <= clock + 0.000001: continue
		var local: Vector2 = pos - zone.pos
		var tangent: Vector2 = Vector2(-zone.normal.y, zone.normal.x)
		if absf(local.dot(zone.normal)) > float(zone.depth) * 0.5 + 0.000001 or absf(local.dot(tangent)) > float(zone.width) * 0.5 + 0.000001: continue
		# The mathematical strip is clipped against real floor and obstacles.
		if absf(pos.x) > float(run.room_size.x) * 0.5 or absf(pos.y) > float(run.room_size.y) * 0.5 or not run.line_is_clear(zone.pos, pos): continue
		result = minf(result, float(zone.speed_multiplier))
	return result


func _incoming_projectile(run, radius: float) -> Dictionary:
	var selected: Dictionary = {}
	if run._enemy_combat == null: return selected
	for body in run._enemy_combat.enemy_projectiles:
		if float(body.get("remaining", 0.0)) <= 0.0 or float(body.get("speed", 0.0)) <= 0.0: continue
		var relative: Vector2 = run.player.pos - body.pos
		if relative.length() > radius + 0.000001 or body.direction.dot(relative) <= 0.000001 or not run.line_is_clear(run.player.pos, body.pos): continue
		if selected.is_empty() or relative.length_squared() < run.player.pos.distance_squared_to(selected.pos) - 0.000001 or (is_equal_approx(relative.length_squared(), run.player.pos.distance_squared_to(selected.pos)) and int(body.id) < int(selected.id)):
			selected = {"id": int(body.id), "pos": body.pos, "wind_projectile": true}
	return selected


func _displace(run, actor: Dictionary, displacement: Vector2) -> float:
	if actor.is_empty() or float(actor.health) <= 0.0: return 0.0
	if bool(actor.get("uninterruptible", false)) or bool(actor.get("displacement_immune", false)) or str(actor.get("phase", "")) in ["charge", "stamp"]: return 0.0
	var factor: float = float(mechanics.control_coefficients[_category(actor)])
	var start: Vector2 = actor.pos
	actor.pos = run._clip_motion(start, displacement * factor, float(actor.radius))
	return start.distance_to(actor.pos)


func _category(actor: Dictionary) -> String:
	if bool(actor.get("boss", false)): return "fixed_strong"
	var id: String = str(actor.get("type_id", actor.get("type", "")))
	var configured: String = str(mechanics.control_class_by_type.get(id, ""))
	if not configured.is_empty(): return configured
	return "elite" if bool(actor.get("elite", false)) or id.begins_with("EL") else "normal"


func _hit(run, actor: Dictionary, coefficient: float, context: Dictionary) -> float:
	if not _active(run) or actor.is_empty() or float(actor.health) <= 0.0: return 0.0
	context["gem_echo_eligible"] = bool(context.get("natural", false))
	if not bool(context.get("echo_shape_recorded", false)) and run.has_method("gem_record_shape"):
		run.gem_record_shape({"kind": "area", "pos": actor.pos, "radius": 0.0, "block": true, "target_cap": 1}, coefficient, context)
	var before: float = float(actor.health)
	run.resolve_spell_hit(actor, coefficient, context)
	var actual: float = before - maxf(0.0, float(actor.health))
	if actual > 0.0 and run.has_method("gem_after_spell_status"): run.gem_after_spell_status(actor, context)
	if actual > 0.0: run._emit("wind_hit", {"pos": actor.pos, "actor_id": actor.id, "spell_id": context.spell_id}, float(effects.hit))
	return actual


func _derived(run, actor: Dictionary, coefficient: float, context: Dictionary, kind: String) -> float:
	if not _active(run) or actor.is_empty() or float(actor.health) <= 0.0 or coefficient <= 0.0: return 0.0
	var derived: Dictionary = context.duplicate(true)
	# Wind layers enhance natural body only, never conditional cross/follow-up damage.
	derived["damage_scale"] = float(derived.get("damage_scale", 1.0)) / maxf(1.0, float(derived.get("gem_wind_multiplier", 1.0)))
	derived.merge({"kind": kind, "natural": false, "can_crit": true, "echo_shape_recorded": true}, true)
	return run.resolve_school_derived_hit(actor, coefficient, derived)


func _record_segment(run, from: Vector2, to: Vector2, width: float, coefficient: float, target_cap: int, context: Dictionary, extras: Dictionary = {}) -> void:
	if not run.has_method("gem_record_shape"): return
	var shape: Dictionary = {"kind": "segment", "from": from, "to": to, "width": width, "target_cap": target_cap}
	shape.merge(extras, true)
	run.gem_record_shape(shape, coefficient, context)


func _contacts(run, from: Vector2, to: Vector2, radius: float) -> Array:
	var found: Array = []
	for actor in run.actors:
		if float(actor.health) <= 0.0 or not run.line_is_clear(from, actor.pos): continue
		var at: float = run.segment_circle_time(from, to, actor.pos, radius + float(actor.radius))
		if at != INF: found.append({"actor": actor, "at": at})
	found.sort_custom(func(a, b): return float(a.at) < float(b.at) if not is_equal_approx(float(a.at), float(b.at)) else int(a.actor.id) < int(b.actor.id))
	return found


func _targets(run, center: Vector2, radius: float, include_body: bool = false) -> Array:
	var found: Array = []
	for actor in run.actors:
		if float(actor.health) > 0.0 and center.distance_to(actor.pos) <= radius + (float(actor.radius) if include_body else 0.0) + 0.000001 and run.line_is_clear(center, actor.pos): found.append(actor)
	found.sort_custom(func(a, b):
		var ad: float = center.distance_squared_to(a.pos)
		var bd: float = center.distance_squared_to(b.pos)
		return ad < bd if not is_equal_approx(ad, bd) else int(a.id) < int(b.id))
	return found


func _actor(run, actor_id: int) -> Dictionary:
	for actor in run.actors:
		if int(actor.id) == actor_id and float(actor.health) > 0.0: return actor
	return {}


func _remove_zone(kind: String) -> void:
	var retained: Array = []
	for zone in zones:
		if str(zone.kind) != kind: retained.append(zone)
	zones = retained


func _queue(at: float, kind: String, values: Dictionary) -> void:
	values.merge({"id": _new_id(), "kind": kind, "at": at}, true)
	pending.append(values)


func _new_id() -> int:
	var value: int = _next_id
	_next_id += 1
	return value


func get_snapshot(_run) -> Dictionary:
	return {"wind_clock": clock, "wind_projectiles": projectiles.duplicate(true), "wind_zones": zones.duplicate(true), "wind_pending": pending.duplicate(true), "wind_path_segments": path_segments.duplicate(true), "wind_recording": recording.duplicate(true), "wind_states": states.values().duplicate(true), "wind_recent_path": motion_distance(), "wind_mastery_remaining": maxf(0.0, _mastery_until - clock)}


func _active(run) -> bool:
	return run.phase == "combat" and not run.paused and float(run.player.health) > 0.0
