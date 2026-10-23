extends RefCounted
## Enemy rules for the 60-room route. All damage and movement belong to core;
## presentation receives locked danger shapes and already simulated projectiles.

const DATA_PATH := "res://data/route_enemy_runtime.json"
const NonbossRules = preload("res://scripts/core/route_enemy_nonboss.gd")
const Barrage = preload("res://scripts/core/route_enemy_barrage.gd")
const BossCombat = preload("res://scripts/core/route_boss_combat.gd")
var bosses = BossCombat.new()

var error: String = ""
var enemy_projectiles: Array = []
var _data: Dictionary = {}
var _types: Dictionary = {}
var _next_projectile: int = 1
var _last_heavy_warning: float = -INF
var _room_specs: Dictionary = {}
var _nonboss = NonbossRules.new()
var _barrage = Barrage.new()
var _combat_clock: float = 0.0
var _contact_ready_at: float = 0.0
var _last_curtain_warning: float = -INF
var _last_fast_warning: float = -INF


func configure(base: Dictionary, first_room_runtime: Dictionary, runtime_override: Dictionary = {}, required_room_count: int = 0) -> Dictionary:
	var rules_result: Dictionary = _nonboss.load_rules()
	if not rules_result.ok:
		return _fail(str(rules_result.error))
	# The optional explicit configuration supports native offline parameter
	# comparisons without rewriting the live project's canonical data file.
	if not runtime_override.is_empty():
		_data = runtime_override.duplicate(true)
	else:
		var file := FileAccess.open(DATA_PATH, FileAccess.READ)
		if file == null:
			return _fail("无法读取前期怪物运行规则。")
		var parser := JSON.new()
		if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
			return _fail("前期怪物运行规则格式无效。")
		_data = parser.data
	_types.clear()
	_room_specs.clear()
	for type_id in _data.types:
		var definition: Dictionary = _data.types[type_id].duplicate(true)
		if definition.has("variant_of"):
			continue
		var stats: Dictionary = {}
		if definition.has("base_type"):
			var source_id := str(definition.base_type)
			if not base.normal_types.has(source_id):
				return _fail("怪物源类型无效：" + source_id)
			stats = base.normal_types[source_id].duplicate(true)
			stats.merge(base.normal_stages[0].stats.get(source_id, _data.early_stats.get(source_id, {})), true)
			if definition.has("runtime_ref"):
				stats.merge(first_room_runtime[str(definition.runtime_ref)], true)
		else:
			for elite in base.elites:
				if str(elite.id) == str(definition.base_elite):
					stats = {"health": elite.health, "damage": elite.attacks.values()[0]}
					break
		stats.merge(definition, true)
		_types[type_id] = stats
	for type_id in _data.types:
		var definition: Dictionary = _data.types[type_id]
		if not definition.has("variant_of"):
			continue
		var parent: String = str(definition.variant_of)
		if not _types.has(parent):
			return _fail("强化精英引用无效。")
		var stats: Dictionary = _types[parent].duplicate(true)
		stats.merge(definition, true)
		stats.health = float(stats.health) * float(definition.health_multiplier)
		stats.damage = float(stats.damage) * float(definition.damage_multiplier)
		_types[type_id] = stats
	for type_id in _types:
		var stats: Dictionary = _types[type_id]
		for key in ["health", "damage", "warning", "attack_cycle", "radius", "move_speed", "attack_trigger_range", "recovery"]:
			if not stats.has(key) or not is_finite(float(stats[key])) or float(stats[key]) <= 0.0:
				return _fail("前期怪物运行值无效：%s.%s" % [type_id, key])
	var next_room := 1
	for stage in _data.get("stat_stages", []):
		if not stage is Dictionary or int(stage.get("from", 0)) != next_room or int(stage.get("to", 0)) < next_room:
			return _fail("前期怪物档位必须连续覆盖房间。")
		for category in ["normal", "elite"]:
			if not stage.get(category) is Dictionary:
				return _fail("前期怪物档位缺少普通／精英幅度。")
			for key in ["health", "move_speed", "projectile_speed", "attack_cycle"]:
				if not stage[category].has(key) or not is_finite(float(stage[category][key])) or float(stage[category][key]) <= 0.0:
					return _fail("前期怪物档位幅度无效。")
			for key in ["damage", "body_damage"]:
				if not is_finite(float(stage[category].get(key, 1.0))) or float(stage[category].get(key, 1.0)) <= 0.0:
					return _fail("怪物房间伤害倍率无效。")
		for room_id in range(int(stage.from), int(stage.to) + 1):
			_room_specs[room_id] = {}
			for type_id in _types:
				var stats: Dictionary = _types[type_id].duplicate(true)
				var factors: Dictionary = stage.elite if bool(stats.get("elite", false)) else stage.normal
				for key in factors:
					if key not in ["damage", "body_damage"] and stats.has(key):
						stats[key] = float(stats[key]) * float(factors[key])
				stats["room_damage_multiplier"] = float(factors.get("damage", 1.0))
				stats["room_body_multiplier"] = float(factors.get("body_damage", 1.0))
				stats.attack_cycle = maxf(float(stats.attack_cycle), _full_attack_duration(stats))
				stats["stat_stage_id"] = str(stage.id)
				stats["stat_room"] = room_id
				_room_specs[room_id][type_id] = stats
			_room_specs[room_id] = _nonboss.apply_specs(_room_specs[room_id], room_id)
			for stats in _room_specs[room_id].values():
				stats["base_damage"] = float(stats.damage)
				stats.damage = float(stats.base_damage) * float(stats.room_damage_multiplier)
				if stats.has("body_damage"):
					stats["base_body_damage"] = float(stats.body_damage)
					stats.body_damage = float(stats.base_body_damage) * float(stats.room_body_multiplier)
				stats.attack_cycle = maxf(float(stats.attack_cycle), _full_attack_duration(stats))
		next_room = int(stage.to) + 1
	if next_room <= 1 or (required_room_count > 0 and next_room != required_room_count + 1):
		return _fail("怪物档位须完整覆盖本次可玩路线。")
	var boss_result: Dictionary = bosses.configure()
	if not boss_result.ok:
		return _fail(str(boss_result.error))
	for definition in bosses.catalog.data.bosses:
		var boss_spec: Dictionary = bosses.catalog.spec(definition)
		var multiplier := float(_data.get("boss_damage_by_room", {}).get(str(int(definition.room)), 1.0))
		if not is_finite(multiplier) or multiplier <= 0.0:
			return _fail("首领房间伤害倍率无效。")
		boss_spec["room_damage_multiplier"] = multiplier
		boss_spec["room_body_multiplier"] = multiplier
		boss_spec["base_damage"] = float(boss_spec.damage)
		boss_spec["base_body_damage"] = float(boss_spec.body_damage)
		boss_spec.damage = float(boss_spec.damage) * multiplier
		boss_spec.body_damage = float(boss_spec.body_damage) * multiplier
		boss_spec.definition.body_damage = float(boss_spec.body_damage)
		for phase in boss_spec.definition.phases:
			for pattern in phase.patterns.values():
				pattern["base_damage"] = float(pattern.damage)
				pattern.damage = float(pattern.base_damage) * multiplier
		_types[str(definition.id)] = boss_spec
		if _room_specs.has(int(definition.room)):
			_room_specs[int(definition.room)][str(definition.id)] = boss_spec.duplicate(true)
	clear()
	error = ""
	return {"ok": true, "error": ""}


func clear() -> void:
	bosses.clear()
	enemy_projectiles.clear()
	_next_projectile = 1
	_last_heavy_warning = -INF
	_last_curtain_warning = -INF
	_last_fast_warning = -INF
	_combat_clock = 0.0
	_contact_ready_at = 0.0


func type_spec(type_id: String, room_index: int = 1) -> Dictionary:
	return _room_specs.get(room_index, {}).get(type_id, {}).duplicate(true)


func get_runtime() -> Dictionary:
	return _data.duplicate(true)


func get_projectiles() -> Array:
	return enemy_projectiles.duplicate(true)


func make_actor(run, type_id: String, pos: Vector2, actor_id: int, room_index: int = -1) -> Dictionary:
	if room_index < 0:
		var actual_room: Variant = run.get("room_index")
		room_index = int(actual_room) if actual_room is int else 1
	var spec := type_spec(type_id, room_index)
	if spec.is_empty():
		return {}
	var actor := {"id": actor_id, "type_id": type_id, "name": str(spec.get("name", type_id)),
		"elite": bool(spec.get("elite", false)), "pos": pos, "previous": pos,
		"health": float(spec.health), "max_health": float(spec.health),
		"radius": float(spec.radius), "damage": float(spec.damage), "phase": "chase",
		"warning_remaining": 0.0, "lock_remaining": 0.0, "attack_from": pos,
		"attack_to": pos, "attack_elapsed": 0.0, "attack_hit": false,
		"recovery_remaining": 0.0, "next_attack_at": float(run.time),
		"recovery_duration": float(spec.recovery),
		"slow_remaining": 0.0, "slow_multiplier": 1.0, "spell_slows": {}, "danger": {},
		"lunges_remaining": 0, "spec_id": type_id, "stat_room": room_index,
		"reserved_projectiles": 0, "body_contact_enabled": false,
		"body_grace_remaining": float(spec.get("body_spawn_grace", 0.0)),
		"stat_stage_id": str(spec.stat_stage_id), "combat_spec": spec}
	if bool(spec.get("boss", false)):
		bosses.initialize(actor)
		actor["push_resistance"] = float(spec.push_resistance)
	return actor


func update(run, dt: float) -> void:
	if run.phase != "combat" or run.paused or dt <= 0.0 or not is_finite(dt):
		return
	_combat_clock += dt
	if run.has_method("advance_ice_control"):
		run.advance_ice_control(dt)
	var boss_grace: bool = bosses.before_update(self, run, dt)
	for actor in run.actors:
		actor["body_contact_enabled"] = false
		if actor.health <= 0.0 or run.phase != "combat":
			_barrage.cancel(actor)
			continue
		var spec: Dictionary = actor.get("combat_spec", _types.get(str(actor.get("type_id", "M01")), {}))
		if spec.is_empty():
			continue
		actor.previous = actor.pos
		if boss_grace:
			continue
		actor["body_grace_remaining"] = maxf(0.0, float(actor.get("body_grace_remaining", 0.0)) - dt)
		var active_body_attack: bool = str(actor.phase) == "lunge" and str(spec.behavior) == "lunge"
		var ice: Dictionary = run.get_ice_control_state(actor) if run.has_method("get_ice_control_state") else {}
		var frozen_time: float = clampf(float(ice.get("frozen_time", 0.0)), 0.0, dt)
		if bool(ice.get("frozen", false)):
			# A prior actor can freeze this one during the same enemy update.
			# Apply that event immediately, even before the next clock advance.
			frozen_time = dt
		var action_dt: float = maxf(0.0, dt - frozen_time)
		actor["ice_frozen"] = bool(ice.get("frozen", false))
		# AI timers are local while the world's clock, slow deadlines and
		# already released attacks continue. Preserve absolute attack readiness.
		actor.next_attack_at = float(actor.next_attack_at) + frozen_time
		actor.lock_remaining = maxf(0.0, float(actor.lock_remaining) - action_dt)
		actor.slow_remaining = maxf(0.0, float(actor.get("slow_remaining", 0.0)) - dt)
		if actor.slow_remaining <= 0.0:
			actor.slow_multiplier = 1.0
		var live_slows: Dictionary = {}
		for source in actor.get("spell_slows", {}):
			var slow: Dictionary = actor.spell_slows[source]
			if float(slow.until) > float(run.time) + 0.000001:
				live_slows[source] = slow
				actor.slow_multiplier = minf(float(actor.slow_multiplier), 1.0 - clampf(float(slow.amount), 0.0, 1.0))
		actor.spell_slows = live_slows
		var legacy_slow: float = float(actor.slow_multiplier)
		actor.slow_multiplier = minf(legacy_slow, 1.0 - float(ice.get("slow", 0.0)))
		var released_mark: bool = str(actor.phase) == "lunge" and str(spec.behavior) == "mark"
		if action_dt <= 0.000000001 and not released_mark:
			actor.slow_multiplier = legacy_slow
			continue
		if bool(actor.get("boss", false)):
			actor.slow_multiplier = maxf(1.0 - float(bosses.catalog.data.global.slow_cap), float(actor.slow_multiplier))
			var was_charge: bool = str(actor.phase) == "charge"
			bosses.update(self, run, actor, action_dt)
			if was_charge:
				actor.body_contact_enabled = false
		elif actor.phase == "chase":
			_update_chase(run, actor, spec, action_dt)
		elif actor.phase == "warning":
			actor.warning_remaining = maxf(0.0, float(actor.warning_remaining) - action_dt)
			actor.danger["remaining"] = actor.warning_remaining
			if actor.warning_remaining <= 0.000001:
				_start_attack(run, actor, spec)
		elif actor.phase == "lunge":
			_update_attack(run, actor, spec, dt if released_mark else action_dt, 0.0 if released_mark else frozen_time / dt)
		elif actor.phase == "barrage":
			_barrage.update(self, run, actor, spec, action_dt)
		elif actor.phase == "chain_wait":
			if float(run.time) - _last_heavy_warning + 0.000001 >= float(_data.heavy_warning_spacing):
				_start_warning(run, actor, spec, float(spec.second_warning))
		elif actor.phase == "recover":
			actor.recovery_remaining = maxf(0.0, float(actor.recovery_remaining) - action_dt)
			if actor.recovery_remaining <= 0.000001:
				actor.phase = "chase"
		actor.slow_multiplier = legacy_slow
		if not bool(actor.get("boss", false)):
			actor.body_contact_enabled = bool(spec.get("nonboss", false)) and frozen_time <= 0.000000001 and not active_body_attack and not (str(actor.phase) == "lunge" and str(spec.behavior) == "lunge") and float(actor.lock_remaining) <= 0.000001 and float(actor.body_grace_remaining) <= 0.000001
	_update_projectiles(run, dt)
	_update_body_contact(run)


func interrupt_by_push(actor: Dictionary, position: Vector2) -> void:
	if actor.health <= 0.0 or not _types.has(str(actor.get("spec_id", ""))):
		return
	actor.pos = position
	actor.attack_from = position
	actor.attack_to = position
	actor.lunges_remaining = 0
	actor.attack_elapsed = 0.0
	actor.attack_hit = false
	_recover(actor, actor.get("combat_spec", _types[str(actor.spec_id)]))


func _full_attack_duration(spec: Dictionary) -> float:
	var duration := float(spec.warning) + float(spec.recovery)
	if spec.behavior == "lunge":
		duration += float(spec.lunge_duration) * float(spec.get("lunges", 1))
		if int(spec.get("lunges", 1)) > 1:
			duration += float(spec.second_warning) * float(int(spec.lunges) - 1)
	elif spec.behavior == "mark":
		duration += float(spec.active_duration)
	elif spec.has("barrage") and not bool(spec.get("attack_disabled", false)):
		duration += _barrage.emission_duration(spec)
	return duration


func _update_chase(run, actor: Dictionary, spec: Dictionary, dt: float) -> void:
	var offset: Vector2 = run.player.pos - actor.pos
	var spacing_ok := not bool(spec.get("heavy", false)) or float(run.time) - _last_heavy_warning + 0.000001 >= float(_data.heavy_warning_spacing)
	var pattern: Dictionary = spec.get("barrage", {})
	var min_distance := float(pattern.get("min_start_distance", 0.0))
	var curtain: bool = str(spec.behavior) == "shooter" and (pattern.is_empty() or str(pattern.kind) != "aimed") and bool(spec.get("nonboss", false))
	var fast: bool = str(spec.behavior) == "shooter" and bool(spec.get("nonboss", false)) and float(spec.get("projectile_speed", 0.0)) >= float(_nonboss.data.projectiles.fast_speed_threshold)
	if curtain and _combat_clock - _last_curtain_warning + 0.000001 < float(_nonboss.data.projectiles.curtain_start_spacing):
		spacing_ok = false
	if fast and _combat_clock - _last_fast_warning + 0.000001 < float(_nonboss.data.projectiles.fast_start_spacing):
		spacing_ok = false
	if not bool(spec.get("attack_disabled", false)) and actor.lock_remaining <= 0.0 and spacing_ok and float(run.time) + 0.000001 >= float(actor.next_attack_at) and offset.length() >= min_distance and offset.length() <= float(spec.attack_trigger_range) and run.line_is_clear(actor.pos, run.player.pos):
		if not _barrage.reserve(self, run, actor, spec):
			actor.next_attack_at = float(run.time) + float(_nonboss.data.projectiles.retry_delay)
			return
		actor.lunges_remaining = int(spec.get("lunges", 1))
		_start_warning(run, actor, spec, float(spec.warning))
		actor.next_attack_at = float(run.time) + float(spec.attack_cycle)
		if bool(spec.get("heavy", false)):
			_last_heavy_warning = float(run.time)
		if curtain:
			_last_curtain_warning = _combat_clock
		if fast:
			_last_fast_warning = _combat_clock
		return
	var step_distance := float(spec.move_speed) * float(actor.slow_multiplier) * dt
	if min_distance > 0.0 and offset.length() < min_distance:
		# Only create enough casting distance; never kite across the entire room.
		var away := -offset.normalized() if offset.length_squared() > 0.000001 else Vector2.RIGHT
		var moved: Vector2 = run.move_body(actor.pos, away * minf(step_distance, min_distance - offset.length()), float(actor.radius))
		if moved.distance_squared_to(actor.pos) < 0.000001:
			moved = run.move_body(actor.pos, away.orthogonal() * step_distance, float(actor.radius))
		actor.pos = moved
		return
	# Ranged enemies approach when out of range or occluded, but cannot shoot
	# through cover. They stay reachable, rather than retreating into corners.
	if spec.behavior == "lunge" or offset.length() > float(spec.get("stop_range", 0.0)) or not run.line_is_clear(actor.pos, run.player.pos):
		actor.pos = run._chase_position(actor.pos, run.player.pos, step_distance, float(actor.radius))


func _start_warning(run, actor: Dictionary, spec: Dictionary, duration: float) -> void:
	if bool(spec.get("nonboss", false)) and bool(spec.get("heavy", false)):
		_last_heavy_warning = float(run.time)
	actor.phase = "warning"
	actor.warning_remaining = duration
	actor.attack_from = actor.pos
	actor.attack_hit = false
	var offset: Vector2 = run.player.pos - actor.pos
	var direction := offset.normalized() if offset.length_squared() > 0.000001 else Vector2(0, -1)
	if spec.behavior == "lunge":
		actor.attack_to = run._clip_motion(actor.pos, direction * float(spec.lunge_distance), float(actor.radius))
		var half_width := float(spec.get("danger_half_width", spec.get("danger_radius", actor.radius)))
		actor.danger = {"kind": "lane", "from": actor.attack_from, "to": actor.attack_to, "pos": actor.pos, "radius": half_width, "remaining": duration, "duration": duration}
	elif spec.behavior == "mark":
		actor.attack_to = run.player.pos
		actor.danger = {"kind": "circle", "from": actor.pos, "to": actor.attack_to, "pos": actor.attack_to, "radius": float(spec.danger_radius), "remaining": duration, "duration": duration}
	elif spec.has("barrage"):
		actor.danger = _barrage.warning(actor, spec, direction, duration)
	else:
		actor.attack_to = actor.pos + direction * float(spec.projectile_range)
		actor.danger = {"kind": "fan" if spec.spread_degrees.size() > 1 else "ray", "from": actor.pos, "to": actor.attack_to, "pos": actor.pos, "radius": float(spec.projectile_radius), "spread_degrees": spec.spread_degrees.duplicate(), "remaining": duration, "duration": duration}
	run._emit("enemy_warning", {"pos": actor.pos, "actor_id": actor.id, "type_id": actor.type_id, "danger": actor.danger.duplicate(true)}, duration)


func _start_attack(run, actor: Dictionary, spec: Dictionary) -> void:
	actor.attack_elapsed = 0.0
	if spec.behavior == "shooter":
		if spec.has("barrage"):
			_barrage.start(self, run, actor, spec)
		else:
			_shoot(run, actor, spec)
			_recover(actor, spec)
	else:
		actor.phase = "lunge"
		actor.danger["active"] = true
		if spec.behavior == "mark":
			run._emit("enemy_mark", {"pos": actor.attack_to, "radius": spec.danger_radius, "actor_id": actor.id}, float(spec.active_duration))


func _update_attack(run, actor: Dictionary, spec: Dictionary, dt: float, player_motion_start: float = 0.0) -> void:
	if spec.behavior == "lunge":
		actor.attack_elapsed = minf(float(spec.lunge_duration), float(actor.attack_elapsed) + dt)
		actor.pos = actor.attack_from.lerp(actor.attack_to, float(actor.attack_elapsed) / float(spec.lunge_duration))
		if not actor.attack_hit:
			var relative_from: Vector2 = actor.previous - run.player.previous.lerp(run.player.pos, player_motion_start)
			var relative_to: Vector2 = actor.pos - run.player.pos
			var radius := float(spec.get("danger_half_width", spec.get("danger_radius", actor.radius))) + float(run.player.radius)
			if run.segment_circle_time(relative_from, relative_to, Vector2.ZERO, radius) != INF:
				actor.attack_hit = true
				run.damage_player(float(actor.damage))
		if float(actor.attack_elapsed) >= float(spec.lunge_duration) - 0.000001:
			actor.lunges_remaining -= 1
			if actor.lunges_remaining > 0 and run.phase == "combat":
				if bool(spec.get("nonboss", false)) and bool(spec.get("heavy", false)) and float(run.time) - _last_heavy_warning + 0.000001 < float(_data.heavy_warning_spacing):
					actor.phase = "chain_wait"
					actor.danger = {}
				else:
					_start_warning(run, actor, spec, float(spec.second_warning))
			else:
				_recover(actor, spec)
	else:
		actor.attack_elapsed += dt
		if not actor.attack_hit and run.segment_circle_time(run.player.previous, run.player.pos, actor.attack_to, float(spec.danger_radius) + float(run.player.radius)) != INF:
			actor.attack_hit = true
			run.damage_player(float(actor.damage))
		if float(actor.attack_elapsed) >= float(spec.active_duration) - 0.000001:
			_recover(actor, spec)


func _recover(actor: Dictionary, spec: Dictionary) -> void:
	actor.phase = "recover"
	actor.recovery_remaining = float(spec.recovery)
	_barrage.cancel(actor)


func _shoot(run, actor: Dictionary, spec: Dictionary) -> void:
	var locked: Vector2 = (actor.attack_to - actor.attack_from).normalized()
	for degrees in spec.spread_degrees:
		var direction := locked.rotated(deg_to_rad(float(degrees)))
		_emit_projectile(actor, spec, direction)
	run._emit("enemy_shot", {"pos": actor.pos, "to": actor.attack_to, "actor_id": actor.id, "count": spec.spread_degrees.size()}, 0.3)


func _emit_projectile(actor: Dictionary, spec: Dictionary, direction: Vector2) -> void:
	enemy_projectiles.append({"id": _next_projectile, "source_id": actor.id, "type_id": actor.type_id, "pos": actor.pos, "previous": actor.pos, "direction": direction, "speed": float(spec.projectile_speed), "radius": float(spec.projectile_radius), "damage": float(actor.damage), "remaining": float(spec.get("projectile_lifetime", _data.projectile_lifetime)), "range_remaining": float(spec.projectile_range)})
	_next_projectile += 1
	actor["reserved_projectiles"] = maxi(0, int(actor.get("reserved_projectiles", 0)) - 1)


func _update_body_contact(run) -> void:
	if run.phase != "combat" or _combat_clock + 0.000001 < _contact_ready_at:
		return
	var strongest: Dictionary = {}
	for actor in run.actors:
		if float(actor.health) <= 0.0 or not bool(actor.get("body_contact_enabled", false)):
			continue
		var spec: Dictionary = actor.combat_spec
		var amount := float(spec.get("body_damage", 0.0))
		if amount <= 0.0:
			continue
		var radius := float(actor.radius) + float(run.player.radius)
		if run.segment_circle_time(actor.previous - run.player.previous, actor.pos - run.player.pos, Vector2.ZERO, radius) == INF:
			continue
		# All body hits use the same direct-damage multiplier and defense path.
		# Ranking their raw amounts therefore also ranks their final damage.
		if strongest.is_empty() or amount > float(strongest.combat_spec.body_damage) or (is_equal_approx(amount, float(strongest.combat_spec.body_damage)) and int(actor.id) < int(strongest.id)):
			strongest = actor
	if not strongest.is_empty() and run.damage_player(float(strongest.combat_spec.body_damage), "direct"):
		_contact_ready_at = _combat_clock + float(strongest.combat_spec.body_interval)
		run._emit("enemy_contact", {"pos": strongest.pos, "actor_id": strongest.id, "type_id": strongest.type_id}, 0.2)


func _update_projectiles(run, dt: float) -> void:
	var retained: Array = []
	for projectile in enemy_projectiles:
		if run.phase != "combat":
			break
		var from: Vector2 = projectile.pos
		var speed_scale: float = run.enemy_projectile_speed_multiplier(from) if run.has_method("enemy_projectile_speed_multiplier") else 1.0
		var distance := minf(float(projectile.speed) * speed_scale * dt, float(projectile.range_remaining))
		var to: Vector2 = from + projectile.direction * distance
		var wall_time: float = run._first_block_contact(from, to, float(projectile.radius))
		var hit_time: float = run.segment_circle_time(from - run.player.previous, to - run.player.pos, Vector2.ZERO, float(projectile.radius) + float(run.player.radius))
		if hit_time != INF and hit_time < wall_time - 0.000001:
			run.damage_player(float(projectile.damage), "projectile")
			continue
		if wall_time != INF:
			continue
		projectile.previous = from
		projectile.pos = to
		projectile.remaining -= dt
		projectile.range_remaining -= distance
		if projectile.remaining > 0.000001 and projectile.range_remaining > 0.000001 and run._inside_floor(to, float(projectile.radius)):
			retained.append(projectile)
	enemy_projectiles = retained


func _fail(message: String) -> Dictionary:
	error = message
	return {"ok": false, "error": error}
