extends RefCounted
## Boss action state and hazards. No owner references are retained (RefCounted).

const Catalog = preload("res://scripts/core/route_boss_catalog.gd")
var catalog = Catalog.new()
var grace_remaining: float = 0.0
var summon_warnings: Array = []


func configure() -> Dictionary:
	return catalog.load_data()


func clear() -> void:
	grace_remaining = 0.0
	summon_warnings.clear()


func initialize(actor: Dictionary) -> void:
	actor.merge({"boss": true, "boss_phase_index": 0, "boss_sequence_index": 0,
		"boss_action": {}, "dangers": [], "boss_ground": [], "boss_gap": Vector2.ZERO,
		"boss_sweep_reverse": false, "boss_line_vertical": false,
		"summon_opportunities": [], "summon_groups": 0, "boss_defeated": false}, true)
	_set_phase_label(actor)


func _set_phase_label(actor: Dictionary) -> void:
	var definition: Dictionary = actor.combat_spec.definition
	actor["boss_phase_id"] = str(definition.phases[int(actor.boss_phase_index)].id)
	actor["boss_phase_count"] = definition.phases.size()
	actor["boss_thresholds"] = []
	for index in range(1, definition.phases.size()):
		actor.boss_thresholds.append(float(definition.phases[index].health_at_most))


func sync_health(combat, run, actor: Dictionary) -> void:
	if not bool(actor.get("boss", false)) or bool(actor.get("boss_defeated", false)):
		return
	if float(actor.health) <= 0.0:
		actor.boss_defeated = true
		_clear_hostiles(combat, run)
		grace_remaining = 0.0
		actor.phase = "dead"
		for add in run.actors:
			if int(add.get("summoned_by", -1)) == int(actor.id):
				# Despawn is not a kill, so cannot farm kill procs or extra rewards.
				add.health = 0.0
				add["despawned"] = true
		return
	var definition: Dictionary = actor.combat_spec.definition
	var next: int = int(actor.boss_phase_index)
	for index in range(next + 1, definition.phases.size()):
		if float(actor.health) / float(actor.max_health) <= float(definition.phases[index].health_at_most) + 0.000000001:
			next = index
	if next == int(actor.boss_phase_index):
		return
	# Crossed summon opportunities stay pending even when a burst skips a phase.
	for group in definition.get("summons", {}).get("groups", []):
		for index in range(int(actor.boss_phase_index) + 1, next + 1):
			if str(group.phase) == str(definition.phases[index].id):
				actor.summon_opportunities.append(group.duplicate(true))
	actor.boss_phase_index = next
	actor.boss_sequence_index = 0
	actor.boss_gap = Vector2.ZERO
	_set_phase_label(actor)
	_clear_hostiles(combat, run)
	grace_remaining = float(definition.transition_seconds)
	actor.phase = "transition"
	actor["boss_transition_remaining"] = grace_remaining
	run._emit("boss_transition", {"pos": actor.pos, "actor_id": actor.id, "phase": actor.boss_phase_id}, grace_remaining)


func _clear_hostiles(combat, run) -> void:
	combat.enemy_projectiles.clear()
	summon_warnings.clear()
	for enemy in run.actors:
		combat._barrage.cancel(enemy)
		enemy.danger = {}
		enemy["dangers"] = []
		enemy["boss_ground"] = []
		enemy["boss_action"] = {}
		enemy.phase = "chase"
		enemy.body_contact_enabled = false
		enemy.next_attack_at = float(run.time)
		enemy.lunges_remaining = 0
	# Old mark effects must not imply damage that was removed by the transition.
	run.effects = run.effects.filter(func(effect): return str(effect.get("kind", "")) not in ["enemy_warning", "enemy_mark", "enemy_shot"])


func before_update(combat, run, dt: float) -> bool:
	for actor in run.actors:
		if bool(actor.get("boss", false)):
			sync_health(combat, run, actor)
	var was_grace := grace_remaining > 0.000000001
	grace_remaining = maxf(0.0, grace_remaining - dt)
	for actor in run.actors:
		if bool(actor.get("boss", false)):
			actor["boss_transition_remaining"] = grace_remaining
			if was_grace and grace_remaining <= 0.000000001 and float(actor.health) > 0.0:
				actor.phase = "chase"
	if was_grace:
		return true
	_update_summons(combat, run, dt)
	return false


func update(combat, run, actor: Dictionary, dt: float) -> void:
	if float(actor.health) <= 0.0:
		return
	_update_ground(run, actor, dt)
	if run.phase != "combat":
		return
	var action: Dictionary = actor.boss_action
	if actor.phase == "recover":
		_try_summon(combat, run, actor)
		actor.recovery_remaining = maxf(0.0, float(actor.recovery_remaining) - dt)
		if actor.recovery_remaining <= 0.000000001 and summon_warnings.is_empty():
			actor.phase = "chase"
	elif action.is_empty():
		var distance: float = actor.pos.distance_to(run.player.pos)
		var stop: float = float(catalog.data.global.approach_stop_distance)
		if distance > stop or not run.line_is_clear(actor.pos, run.player.pos):
			actor.pos = run._chase_position(actor.pos, run.player.pos, float(actor.combat_spec.move_speed) * float(actor.slow_multiplier) * dt, float(actor.radius))
		elif float(actor.lock_remaining) <= 0.000000001 and float(run.time) + 0.000000001 >= float(actor.next_attack_at):
			_begin(combat, run, actor)
	else:
		_update_action(combat, run, actor, dt)
	actor.body_contact_enabled = run.phase == "combat" and float(actor.lock_remaining) <= 0.000000001 and float(actor.body_grace_remaining) <= 0.000000001 and actor.phase != "charge"
	_sync_dangers(actor)


func _reserve(combat, run, actor: Dictionary, pattern: Dictionary) -> bool:
	var count := 0
	if str(pattern.kind) in ["fan", "ring", "sweep"]:
		count = (int(pattern.count) - int(pattern.get("omitted_adjacent_spokes", 0))) * int(pattern.get("volleys", 1))
	var pending := 0
	for enemy in run.actors:
		if float(enemy.health) > 0.0:
			pending += int(enemy.get("reserved_projectiles", 0))
	if combat.enemy_projectiles.size() + pending + count > int(actor.combat_spec.projectile_cap):
		actor.next_attack_at = float(run.time) + float(catalog.data.global.retry_delay)
		return false
	actor.reserved_projectiles = count
	return true


func _begin(combat, run, actor: Dictionary) -> void:
	var definition: Dictionary = actor.combat_spec.definition
	var stage: Dictionary = definition.phases[int(actor.boss_phase_index)]
	var key: String = str(stage.sequence[int(actor.boss_sequence_index) % stage.sequence.size()])
	var pattern: Dictionary = stage.patterns[key].duplicate(true)
	if not _reserve(combat, run, actor, pattern):
		return
	actor.boss_sequence_index = (int(actor.boss_sequence_index) + 1) % stage.sequence.size()
	var offset: Vector2 = run.player.pos - actor.pos
	var direction := offset.normalized() if offset.length_squared() > 0.000001 else Vector2.DOWN
	actor.boss_action = {"key": key, "pattern": pattern, "age": 0.0, "direction": direction,
		"shot_index": 0, "volley_index": 0, "mark_index": 0, "next_mark_at": 0.0,
		"wait": float(pattern.warning), "warning": {}, "released": false}
	actor.attack_from = actor.pos
	actor.attack_to = actor.pos + direction * float(catalog.data.global.projectile_range)
	actor.phase = "warning"
	if str(pattern.kind) == "marks":
		_add_mark(run, actor)
	elif str(pattern.kind) == "lines":
		_add_lines(run, actor, pattern)
	else:
		_lock_warning(run, actor, float(pattern.warning))


func _angles(actor: Dictionary, pattern: Dictionary) -> Array:
	var angles: Array = []
	match str(pattern.kind):
		"fan":
			for index in int(pattern.count):
				angles.append((float(index) - (float(pattern.count) - 1.0) * 0.5) * float(pattern.step_degrees))
		"ring":
			var half := int(pattern.omitted_adjacent_spokes) / 2
			for index in int(pattern.count):
				if index <= half or index >= int(pattern.count) - half:
					continue
				angles.append(float(index) * 360.0 / float(pattern.count))
		"sweep":
			for index in int(pattern.count):
				angles.append(-float(pattern.arc_degrees) * 0.5 + float(pattern.arc_degrees) * float(index) / (float(pattern.count) - 1.0))
			if bool(actor.boss_sweep_reverse):
				angles.reverse()
	return angles


func _lock_warning(run, actor: Dictionary, duration: float) -> void:
	var action: Dictionary = actor.boss_action
	var p: Dictionary = action.pattern
	var direction: Vector2 = action.direction
	var kind: String = str(p.kind)
	if kind == "charge":
		actor.attack_to = run._clip_motion(actor.pos, direction * float(p.distance), float(actor.radius))
		action.warning = {"kind": "lane", "from": actor.pos, "to": actor.attack_to, "pos": actor.pos, "radius": float(p.half_width)}
	else:
		if kind == "ring":
			if actor.boss_gap == Vector2.ZERO:
				actor.boss_gap = direction
			direction = actor.boss_gap
			action.direction = direction
		action["angles"] = _angles(actor, p)
		actor.attack_to = actor.pos + direction * float(catalog.data.global.projectile_range)
		action.warning = {"kind": kind, "from": actor.pos, "to": actor.attack_to, "pos": actor.pos,
			"radius": float(p.radius), "spread_degrees": action.angles.duplicate(),
			"nominal_count": int(p.count), "arc_degrees": float(p.get("arc_degrees", 0.0)), "sweep_reverse": bool(actor.boss_sweep_reverse)}
		action["warning_direction"] = direction
		action["warning_origin"] = actor.pos
	# Ring gap is committed only by release, never by warning or reservation.
	action.warning["remaining"] = duration
	action.warning["duration"] = duration
	actor.warning_remaining = duration


func _update_action(combat, run, actor: Dictionary, dt: float) -> void:
	var a: Dictionary = actor.boss_action
	var p: Dictionary = a.pattern
	a.age = float(a.age) + dt
	if str(p.kind) == "marks":
		if int(a.mark_index) < int(p.count) and float(a.age) + 0.000000001 >= float(a.next_mark_at):
			_add_mark(run, actor)
		var last_end := (float(p.count) - 1.0) * float(p.mark_interval) + float(p.warning) + float(p.active)
		if float(a.age) + 0.000000001 >= last_end:
			_recover(actor, p)
		return
	if str(p.kind) == "lines":
		if float(a.age) + 0.000000001 >= float(p.warning) + float(p.active):
			_recover(actor, p)
		return
	if actor.phase == "charge":
		actor.attack_elapsed = minf(float(p.duration), float(actor.attack_elapsed) + dt)
		actor.pos = actor.attack_from.lerp(actor.attack_to, float(actor.attack_elapsed) / float(p.duration))
		if not actor.attack_hit and run.segment_circle_time(actor.previous - run.player.previous, actor.pos - run.player.pos, Vector2.ZERO, float(p.half_width) + float(run.player.radius)) != INF:
			actor.attack_hit = true
			run.damage_player(float(p.damage), "direct")
		if float(actor.attack_elapsed) + 0.000000001 >= float(p.duration):
			_recover(actor, p)
		return
	# Retain sub-frame overshoot, so fixed steps do not accumulate extra delay
	# between sweep shots or between the two rings.
	a.wait = float(a.wait) - dt
	if not a.warning.is_empty():
		a.warning.remaining = maxf(0.0, float(a.wait))
		actor.warning_remaining = maxf(0.0, float(a.wait))
	# The follow-up ring's gap and full warning lock at their own warning start.
	if str(p.kind) == "ring" and actor.phase == "ring_wait" and float(a.wait) <= float(p.followup_warning) + 0.000000001 and a.warning.is_empty():
		_lock_warning(run, actor, float(p.followup_warning))
	if float(a.wait) > 0.000000001:
		return
	if str(p.kind) == "charge":
		actor.phase = "charge"
		actor.attack_elapsed = 0.0
		actor.attack_hit = false
		a.warning["active"] = true
		return
	if str(p.kind) == "sweep":
		if int(a.shot_index) == 0:
			actor.boss_sweep_reverse = not bool(actor.boss_sweep_reverse)
		_emit(combat, actor, p, a.direction.rotated(deg_to_rad(float(a.angles[int(a.shot_index)]))))
		a.shot_index = int(a.shot_index) + 1
		if int(a.shot_index) < a.angles.size():
			actor.phase = "barrage"
			a.wait = float(a.wait) + float(p.shot_interval)
			a.warning["active"] = true
			a.warning["shot_index"] = int(a.shot_index)
		else:
			_recover(actor, p)
	else:
		for angle in a.angles:
			_emit(combat, actor, p, a.direction.rotated(deg_to_rad(float(angle))))
		if str(p.kind) == "ring":
			actor.boss_gap = a.direction.rotated(deg_to_rad(float(p.gap_rotation_degrees)))
		a.volley_index = int(a.volley_index) + 1
		if int(a.volley_index) < int(p.get("volleys", 1)):
			actor.phase = "ring_wait"
			a.wait = float(a.wait) + float(p.release_interval)
			a.warning = {}
		else:
			_recover(actor, p)


func _emit(combat, actor: Dictionary, pattern: Dictionary, direction: Vector2) -> void:
	var spec := {"projectile_speed": pattern.speed, "projectile_radius": pattern.radius,
		"projectile_lifetime": catalog.data.global.projectile_lifetime, "projectile_range": catalog.data.global.projectile_range}
	# Actor body damage is independent of each pattern's projectile damage.
	combat._emit_projectile(actor, spec, direction)
	combat.enemy_projectiles[-1].damage = float(pattern.damage)


func _recover(actor: Dictionary, pattern: Dictionary) -> void:
	actor.phase = "recover"
	actor.recovery_remaining = float(pattern.recovery)
	actor.reserved_projectiles = 0
	actor.boss_action = {}
	actor.danger = {}


func _add_mark(run, actor: Dictionary) -> void:
	var a: Dictionary = actor.boss_action
	var p: Dictionary = a.pattern
	actor.boss_ground.append({"age": 0.0, "warning": float(p.warning), "active_time": float(p.active),
		"damage": float(p.damage), "hit": false, "shapes": [{"kind": "circle", "pos": run.player.pos, "radius": float(p.radius)}]})
	a.mark_index = int(a.mark_index) + 1
	a.next_mark_at = float(a.mark_index) * float(p.mark_interval)


func _add_lines(run, actor: Dictionary, pattern: Dictionary) -> void:
	var shapes: Array = []
	var pos: Vector2 = run.player.pos
	for index in int(pattern.count):
		var vertical := (bool(actor.boss_line_vertical) if int(pattern.count) == 1 else index == 1)
		var direction := Vector2.UP if vertical else Vector2.RIGHT
		# Footprint is a capsule, with total width including its end caps.
		var half_width: float = float(pattern.width) * 0.5
		var reach: float = maxf(0.0, float(pattern.length) * 0.5 - half_width)
		var extent: Vector2 = run.room_size * 0.5 - Vector2.ONE * half_width
		var start: Vector2 = (pos - direction * reach).clamp(-extent, extent)
		var end: Vector2 = (pos + direction * reach).clamp(-extent, extent)
		shapes.append({"kind": "lane", "pos": pos, "from": start, "to": end, "radius": half_width})
	actor.boss_line_vertical = not bool(actor.boss_line_vertical)
	actor.boss_ground.append({"age": 0.0, "warning": float(pattern.warning), "active_time": float(pattern.active), "damage": float(pattern.damage), "hit": false, "shapes": shapes})


func _update_ground(run, actor: Dictionary, dt: float) -> void:
	var retained: Array = []
	for group in actor.boss_ground:
		var old_age: float = float(group.age)
		group.age = old_age + dt
		var warning: float = float(group.warning)
		var end: float = warning + float(group.active_time)
		if float(group.age) + 0.000000001 >= warning and old_age < end and not bool(group.hit):
			# Clip player movement to the active part of this frame. At a crossing,
			# the entire line group can accept only one hit, even after i-frames.
			var from: Vector2 = run.player.previous.lerp(run.player.pos, clampf((warning - old_age) / dt, 0.0, 1.0))
			var to: Vector2 = run.player.previous.lerp(run.player.pos, clampf((end - old_age) / dt, 0.0, 1.0))
			for shape in group.shapes:
				var touched := false
				if shape.kind == "circle":
					touched = run.segment_circle_time(from, to, shape.pos, float(shape.radius) + float(run.player.radius)) != INF
				else:
					touched = _segments_distance_squared(from, to, shape.from, shape.to) <= pow(float(shape.radius) + float(run.player.radius), 2)
				if touched and run.damage_player(float(group.damage), "direct"):
					group.hit = true
					break
		if float(group.age) < end - 0.000000001:
			retained.append(group)
	actor.boss_ground = retained


func _segments_distance_squared(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return 0.0
	return minf(minf(a.distance_squared_to(Geometry2D.get_closest_point_to_segment(a, c, d)), b.distance_squared_to(Geometry2D.get_closest_point_to_segment(b, c, d))), minf(c.distance_squared_to(Geometry2D.get_closest_point_to_segment(c, a, b)), d.distance_squared_to(Geometry2D.get_closest_point_to_segment(d, a, b))))


func _sync_dangers(actor: Dictionary) -> void:
	actor.dangers = []
	if not actor.boss_action.is_empty() and not actor.boss_action.warning.is_empty():
		actor.dangers.append(actor.boss_action.warning.duplicate(true))
	for group in actor.boss_ground:
		for shape in group.shapes:
			var danger: Dictionary = shape.duplicate(true)
			danger.merge({"active": float(group.age) >= float(group.warning), "remaining": maxf(0.0, float(group.warning) - float(group.age)), "duration": float(group.warning)}, true)
			actor.dangers.append(danger)
	actor.danger = {} # Legacy enemies still expose their single warning.


func _alive_adds(run, actor: Dictionary) -> int:
	var count := 0
	for add in run.actors:
		if int(add.get("summoned_by", -1)) == int(actor.id) and float(add.health) > 0.0:
			count += 1
	return count


func _try_summon(combat, run, actor: Dictionary) -> void:
	if actor.summon_opportunities.is_empty() or not summon_warnings.is_empty() or _alive_adds(run, actor) > 0:
		return
	var config: Dictionary = actor.combat_spec.definition.get("summons", {})
	if config.is_empty() or int(actor.summon_groups) >= int(config.groups_per_fight):
		return
	var selected: Array = []
	var group: Dictionary = actor.summon_opportunities[0]
	for type_id in group.types:
		var spec: Dictionary = combat.type_spec(str(type_id), int(config.stat_room))
		for unit in int(group.types[type_id]):
			var found := false
			for candidate in run._runtime.room.spawn.north_band:
				var point := Vector2(float(candidate[0]), float(candidate[1]))
				if run._valid_typed_spawn(point, float(spec.radius), selected):
					selected.append({"pos": point, "radius": spec.radius, "type_id": str(type_id), "elite": false,
					"remaining": float(config.preview), "duration": float(config.preview), "summoned_by": actor.id})
					found = true
					break
			if not found:
				return
	summon_warnings = selected


func _update_summons(combat, run, dt: float) -> void:
	if summon_warnings.is_empty():
		return
	var boss: Dictionary = {}
	for actor in run.actors:
		if int(actor.id) == int(summon_warnings[0].summoned_by):
			boss = actor
	if boss.is_empty() or float(boss.health) <= 0.0 or str(boss.phase) != "recover" or _alive_adds(run, boss) > 0:
		summon_warnings.clear()
		return
	for warning in summon_warnings:
		warning.remaining = maxf(0.0, float(warning.remaining) - dt)
	if float(summon_warnings[0].remaining) > 0.000000001:
		return
	var selected: Array = []
	for warning in summon_warnings:
		if not run._valid_typed_spawn(warning.pos, float(warning.radius), selected):
			summon_warnings.clear()
			return
		selected.append(warning)
	var config: Dictionary = boss.combat_spec.definition.summons
	for warning in selected:
		var add: Dictionary = combat.make_actor(run, str(warning.type_id), warning.pos, run._next_actor_id, int(config.stat_room))
		run._next_actor_id += 1
		add["summoned_by"] = boss.id
		add.lock_remaining = float(config.attack_lock)
		add.body_grace_remaining = float(config.attack_lock)
		run.actors.append(add)
		run._spawn_total += 1
		run._spawned_total += 1
		run._emit("spawn", {"pos": add.pos, "actor_id": add.id, "elite": false}, 0.5)
	boss.summon_groups = int(boss.summon_groups) + 1
	boss.summon_opportunities.pop_front()
	summon_warnings.clear()
