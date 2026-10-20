extends RefCounted
## A volley is reserved before its warning. Pending shots belong to the actor;
## released projectiles belong to combat and survive their source's death.


func volley_size(spec: Dictionary) -> int:
	var pattern: Dictionary = spec.get("barrage", {})
	if pattern.is_empty():
		return spec.get("spread_degrees", []).size() if str(spec.behavior) == "shooter" else 0
	var per_volley := maxi(0, int(pattern.count) - (int(pattern.omitted_adjacent_spokes) if str(pattern.kind) == "ring" else 0))
	return per_volley * int(pattern.get("volleys", 1))


func emission_duration(spec: Dictionary) -> float:
	var pattern: Dictionary = spec.barrage
	var train := float(int(pattern.get("volleys", 1)) - 1) * float(pattern.get("release_interval", 0.0))
	if str(pattern.kind) in ["aimed", "sweep"]:
		train += float(int(pattern.count) - 1) * float(pattern.shot_interval)
	return maxf(0.0, train)


func reserve(combat, run, actor: Dictionary, spec: Dictionary) -> bool:
	if not bool(spec.get("nonboss", false)) or str(spec.behavior) != "shooter":
		return true
	var size := volley_size(spec)
	var reserved := 0
	var limit := int(spec.projectile_cap)
	for source in run.actors:
		if float(source.health) > 0.0:
			reserved += int(source.get("reserved_projectiles", 0))
			if bool(source.get("boss", false)):
				# Summoned ordinary actors inherit room59 attacks, but still share
				# the current Boss room's whole-scene projectile limit.
				limit = mini(limit, int(source.combat_spec.projectile_cap))
	if size <= 0 or combat.enemy_projectiles.size() + reserved + size > limit:
		return false
	actor["reserved_projectiles"] = size
	return true


func warning(actor: Dictionary, spec: Dictionary, direction: Vector2, duration: float) -> Dictionary:
	var pattern: Dictionary = spec.barrage
	var kind := str(pattern.kind)
	actor["barrage_direction"] = direction
	actor["barrage_shot_index"] = 0
	actor["barrage_followup_locked"] = false
	actor["barrage_initial_reverse"] = bool(actor.get("sweep_reverse", false))
	actor["barrage_events"] = _events(pattern)
	if kind == "ring":
		direction = actor.get("ring_next_gap", direction)
		actor.barrage_direction = direction
	actor["barrage_angles"] = _angles(actor, pattern, 0)
	actor.attack_to = actor.pos + direction * float(pattern.range)
	return _danger(actor, spec, duration, 0)


func _angles(actor: Dictionary, pattern: Dictionary, volley: int) -> Array:
	var angles: Array = []
	var kind := str(pattern.kind)
	if kind == "fan":
		for index in range(int(pattern.count)):
			angles.append((float(index) - float(int(pattern.count) - 1) * 0.5) * float(pattern.step_degrees))
	elif kind == "ring":
		var omitted_half := int(float(pattern.omitted_adjacent_spokes) * 0.5)
		for index in range(int(pattern.count)):
			if index <= omitted_half or index >= int(pattern.count) - omitted_half:
				continue
			angles.append(float(index) * 360.0 / float(pattern.count))
	elif kind == "sweep":
		for index in range(int(pattern.count)):
			angles.append(-float(pattern.sweep_arc_degrees) * 0.5 + float(pattern.sweep_arc_degrees) * float(index) / float(int(pattern.count) - 1))
		if bool(actor.barrage_initial_reverse) != (volley % 2 == 1):
			angles.reverse()
	else:
		angles = [0.0]
	return angles


func _events(pattern: Dictionary) -> Array:
	var result: Array = []
	for volley in range(int(pattern.get("volleys", 1))):
		var start := float(volley) * float(pattern.get("release_interval", 0.0))
		var sequential := str(pattern.kind) in ["aimed", "sweep"]
		for shot in range(int(pattern.count) if sequential else 1):
			result.append({"time": start + (float(shot) * float(pattern.shot_interval) if sequential else 0.0), "volley": volley, "shot": shot})
	return result


func _danger(actor: Dictionary, spec: Dictionary, duration: float, volley: int) -> Dictionary:
	var pattern: Dictionary = spec.barrage
	var kind := str(pattern.kind)
	return {"kind": "ray" if kind == "aimed" else kind, "from": actor.pos,
		"to": actor.attack_to, "pos": actor.pos, "radius": float(pattern.radius),
		"spread_degrees": actor.barrage_angles.duplicate(), "remaining": duration, "duration": duration,
		"nominal_count": int(pattern.count), "volley_index": volley,
		"sweep_reverse": bool(actor.barrage_initial_reverse) != (volley % 2 == 1),
		"arc_degrees": float(pattern.get("sweep_arc_degrees", 0.0))}


func start(combat, run, actor: Dictionary, spec: Dictionary) -> void:
	actor.phase = "barrage"
	if str(spec.barrage.kind) == "sweep":
		actor["sweep_reverse"] = not bool(actor.get("sweep_reverse", false))
	_emit_next(combat, run, actor, spec)


func update(combat, run, actor: Dictionary, spec: Dictionary, dt: float) -> void:
	var pattern: Dictionary = spec.barrage
	var time_left := dt
	while time_left > 0.000000001 and actor.phase == "barrage":
		var remaining := float(actor.barrage_shot_remaining)
		var warning_duration := float(actor.barrage_next_warning_duration)
		if warning_duration > 0.0 and not bool(actor.barrage_followup_locked):
			var until_warning := maxf(0.0, remaining - warning_duration)
			if time_left + 0.000000001 < until_warning:
				actor.barrage_shot_remaining = remaining - time_left
				break
			time_left -= until_warning
			remaining -= until_warning
			var event: Dictionary = actor.barrage_events[int(actor.barrage_shot_index)]
			if str(pattern.kind) == "aimed":
				var offset: Vector2 = run.player.pos - actor.pos
				actor.barrage_direction = offset.normalized() if offset.length_squared() > 0.000001 else Vector2(0, -1)
			actor.barrage_angles = _angles(actor, pattern, int(event.volley))
			actor.attack_from = actor.pos
			actor.attack_to = actor.pos + actor.barrage_direction * float(pattern.range)
			actor.barrage_followup_locked = true
			actor.danger = _danger(actor, spec, warning_duration, int(event.volley))
		if time_left + 0.000000001 < remaining:
			actor.barrage_shot_remaining = remaining - time_left
			if not actor.danger.is_empty():
				actor.danger["remaining"] = actor.barrage_shot_remaining
			break
		time_left -= remaining
		_emit_next(combat, run, actor, spec)


func _emit_next(combat, run, actor: Dictionary, spec: Dictionary) -> void:
	var pattern: Dictionary = spec.barrage
	var index := int(actor.barrage_shot_index)
	var event: Dictionary = actor.barrage_events[index]
	var kind := str(pattern.kind)
	if kind in ["fan", "ring"]:
		for angle in actor.barrage_angles:
			combat._emit_projectile(actor, spec, actor.barrage_direction.rotated(deg_to_rad(float(angle))))
		if kind == "ring" and index == 0:
			actor["ring_next_gap"] = actor.barrage_direction.rotated(deg_to_rad(float(pattern.gap_rotation_degrees)))
	else:
		var angle := float(actor.barrage_angles[int(event.shot)]) if kind == "sweep" else 0.0
		combat._emit_projectile(actor, spec, actor.barrage_direction.rotated(deg_to_rad(angle)))
	if int(event.shot) == 0:
		run._emit("enemy_shot", {"pos": actor.pos, "to": actor.attack_to, "actor_id": actor.id, "count": volley_size(spec)}, 0.3)
	actor.barrage_shot_index = index + 1
	actor.barrage_followup_locked = false
	if int(actor.barrage_shot_index) >= actor.barrage_events.size():
		combat._recover(actor, spec)
		return
	var next: Dictionary = actor.barrage_events[int(actor.barrage_shot_index)]
	actor["barrage_shot_remaining"] = float(next.time) - float(event.time)
	var next_volley := int(next.volley) != int(event.volley)
	actor["barrage_next_warning_duration"] = float(pattern.followup_warning) if kind == "aimed" or next_volley else 0.0
	if kind != "sweep" or next_volley:
		actor.danger = {}
	else:
		actor.danger["active"] = true
		actor.danger["shot_index"] = int(next.shot)


func cancel(actor: Dictionary) -> void:
	actor["reserved_projectiles"] = 0
	actor["barrage_angles"] = []
	actor["barrage_events"] = []
	actor["barrage_shot_remaining"] = 0.0
	actor["barrage_next_warning_duration"] = 0.0
	actor["danger"] = {}
