extends RefCounted
## First playable room. Positions are metres, Vector2(x,z), with +z toward the exit.
## Presentation observes dictionaries/snapshots and never decides hits or rewards.

const ROOT = "res://data/balance_candidates/"
const FIXED_STEP = 1.0 / 120.0
const INITIAL_IDS = ["F01", "F04", "F08"]
const LEGACY_REWARD_IDS = ["F01", "F02", "F03", "F04", "F05", "F06", "F07", "F08", "F09", "F10"]

var error: String = ""
var phase: String = "choosing"
var paused: bool = false
var time: float = 0.0
var player: Dictionary = {}
var actors: Array = []
var blocks: Array = []
var room_size: Vector2 = Vector2.ZERO
var portal: Dictionary = {}
var spells: Array = []
var effects: Array = []
var projectiles: Array = []
var spawn_warnings: Array = []
var spirit: Dictionary = {}
var reward_choices: Array = []
var clear_count: int = 0
var gold: int = 0
var dust: int = 0
var event_seq: int = 0
var kills: int = 0
var casts: int = 0
var damage_dealt: float = 0.0
var damage_taken: float = 0.0
var hits: int = 0

var _base: Dictionary = {}
var _ordinary: Dictionary = {}
var _spatial: Dictionary = {}
var _metrics: Dictionary = {}
var _meta: Dictionary = {}
var _economy: Dictionary = {}
var _runtime: Dictionary = {}
var _equipment: Dictionary = {}
var _rng = RandomNumberGenerator.new()
var _accumulator: float = 0.0
var _spawn_done: bool = false
var _spawn_count: int = 0
var _next_actor_id: int = 1
var _next_projectile_id: int = 1
var _configured: bool = false
var _seed: int = 0
var _selected_reward: String = ""

func configure(run_snapshot: Dictionary = {}, seed_value: int = 20261017) -> Dictionary:
	_configured = false
	for pair in [["first_run_v1.json", "_base"], ["normal_rooms_v1.json", "_ordinary"], ["room_spatial_v1.json", "_spatial"], ["map_metrics_v2.json", "_metrics"], ["meta_growth_v1.json", "_meta"], ["run_economy_v1.json", "_economy"]]:
		var read = _read_json(ROOT + pair[0])
		if not read.ok:
			error = read.error
			return {"ok": false, "error": error}
		set(pair[1], read.data)
	var runtime_read = _read_json("res://data/first_room_runtime.json")
	if not runtime_read.ok:
		error = runtime_read.error
		return {"ok": false, "error": error}
	_runtime = runtime_read.data
	var stats: Dictionary = _base.player.duplicate(true)
	# begin_run supplies an immutable snapshot with the equipped gem already applied.
	if run_snapshot.has("player"):
		for key in stats:
			if run_snapshot.player.has(key):
				stats[key] = run_snapshot.player[key]
	for key in ["health", "shield", "attack", "move_speed", "radius", "hurt_invulnerability"]:
		if not is_finite(float(stats[key])) or float(stats[key]) <= 0.0:
			error = "首房角色属性无效：" + key
			return {"ok": false, "error": error}
	_equipment = run_snapshot.duplicate(true)
	_seed = seed_value
	_rng.seed = seed_value
	phase = "choosing"
	paused = false
	time = 0.0
	_accumulator = 0.0
	_spawn_done = false
	_next_actor_id = 1
	_next_projectile_id = 1
	_selected_reward = ""
	clear_count = 0
	gold = int(_economy.currency.initial)
	dust = 0
	event_seq = 0
	kills = 0
	casts = 0
	damage_dealt = 0.0
	damage_taken = 0.0
	hits = 0
	actors.clear()
	blocks.clear()
	spells.clear()
	effects.clear()
	projectiles.clear()
	spawn_warnings.clear()
	reward_choices.clear()
	spirit = {"active": false, "remaining": 0.0, "pos": Vector2.ZERO, "attack_remaining": 0.0}
	# Only this playable room uses the current geometry. Shared historical layout
	# candidates still own spacing/clearance rules and remain byte-for-byte intact.
	room_size = Vector2(_runtime.room.floor.width, _runtime.room.floor.depth)
	var entry: Array = _runtime.room.entry_player_center
	player = stats.duplicate(true)
	player.merge({"pos": Vector2(entry[0], entry[1]), "previous": Vector2(entry[0], entry[1]), "max_health": float(stats.health), "max_shield": float(stats.shield), "invulnerable": 0.0, "face": Vector2(0, 1)}, true)
	for block in _runtime.room.blocks:
		blocks.append({"center": Vector2(block.center[0], block.center[1]), "size": Vector2(block.size[0], block.size[1])})
	var portal_center: Array = _runtime.room.portal_center
	portal = {"pos": Vector2(portal_center[0], portal_center[1]), "radius": float(_runtime.portal_trigger_radius), "visible": false, "usable": false}
	_spawn_count = int(_ordinary.rooms[0].packs[0].M01)
	error = ""
	_configured = true
	return {"ok": true, "error": ""}

func initial_choices() -> Array:
	var choices: Array = []
	if not _configured:
		return choices
	for spell_id in INITIAL_IDS:
		var choice = _choice(spell_id, true)
		choice.weight = float(_meta.spell_sampling_assumptions.baseline_spell_weight)
		choices.append(choice)
	return choices

func choose_initial(spell_id: String) -> bool:
	if not _configured or paused or phase != "choosing" or spell_id not in INITIAL_IDS:
		return false
	spells.append(_new_spell(spell_id))
	phase = "combat"
	_reserve_batch()
	return true

func set_paused(value: bool):
	paused = value
	_accumulator = 0.0

func step(delta: float, move: Vector2 = Vector2.ZERO):
	if not _configured or paused or phase not in ["combat", "exit"]:
		_accumulator = 0.0
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	_accumulator += minf(delta, 0.1)
	while _accumulator + 0.000000001 >= FIXED_STEP:
		_accumulator -= FIXED_STEP
		_tick(FIXED_STEP, move.limit_length())
		if phase not in ["combat", "exit"]:
			_accumulator = 0.0
			break

func choose_reward(spell_id: String) -> bool:
	if phase != "reward" or paused:
		return false
	var offered = false
	for choice in reward_choices:
		if choice.id == spell_id:
			offered = true
	if not offered:
		return false
	var owned = _owned_spell(spell_id)
	if owned.is_empty():
		spells.append(_new_spell(spell_id))
	else:
		owned.level += 1
		_refresh_spell(owned)
	_selected_reward = spell_id
	phase = "exit"
	portal.usable = true
	_emit("reward", {"pos": player.pos, "spell_id": spell_id}, 0.8)
	# Movement resumes only on a subsequent step; selecting while standing at the exit
	# does not itself complete the room.
	return true

func get_snapshot() -> Dictionary:
	return {"phase": phase, "paused": paused, "time": time, "player": player.duplicate(true), "actors": actors.duplicate(true), "blocks": blocks.duplicate(true), "room_size": room_size, "portal": portal.duplicate(true), "spells": spells.duplicate(true), "effects": effects.duplicate(true), "projectiles": projectiles.duplicate(true), "spawn_warnings": spawn_warnings.duplicate(true), "spirit": spirit.duplicate(true), "reward_choices": reward_choices.duplicate(true), "clear_count": clear_count, "gold": gold, "dust": dust, "event_seq": event_seq, "kills": kills, "casts": casts, "error": error}

func get_summary() -> Dictionary:
	return {"phase": phase, "result": "success" if phase == "complete" else ("failure" if phase == "dead" else "playing"), "clear_count": clear_count, "cleared_rooms": [1] if clear_count == 1 else [], "gold": gold, "dust": dust, "time": time, "elapsed": time, "kills": kills, "casts": casts, "shots": casts, "hits": hits, "damage_dealt": damage_dealt, "damage": damage_dealt, "damage_taken": damage_taken, "taken": damage_taken, "health": player.get("health", 0.0), "max_health": player.get("max_health", 0.0), "reward": _selected_reward, "seed": _seed, "scope": "first_room_only"}

func eligible_reward_ids() -> Array:
	var result: Array = []
	for spell_id in _base.spells:
		if spell_id not in LEGACY_REWARD_IDS:
			continue
		var owned = _owned_spell(spell_id)
		if not owned.is_empty():
			if int(owned.level) < int(_base.limits.spell_level):
				result.append(spell_id)
		elif spells.size() < int(_base.limits.slots):
			result.append(spell_id)
	return result

func reward_weight(spell_id: String) -> float:
	var weight = float(_meta.spell_sampling_assumptions.baseline_spell_weight)
	var catalyst_id: String = _equipment.get("equipment", {}).get("catalyst", "")
	var level = int(_equipment.get("levels", {}).get(catalyst_id, 0))
	if _meta.catalysts.has(catalyst_id) and level > 0 and spell_id in _meta.catalysts[catalyst_id].related_spells:
		weight *= float(_meta.catalyst_weight_by_level[level - 1])
	return weight

func nearest_target(origin: Vector2, maximum_range: float, direct: bool = true, clearance: float = 0.0) -> Dictionary:
	var best: Dictionary = {}
	var best_distance = INF
	for actor in actors:
		if actor.health <= 0.0:
			continue
		var distance = origin.distance_to(actor.pos)
		if distance > maximum_range + 0.00001 or (direct and _first_block_contact(origin, actor.pos, clearance) != INF):
			continue
		if distance < best_distance - 0.00001 or (absf(distance - best_distance) < 0.00001 and (best.is_empty() or actor.id < best.id)):
			best = actor
			best_distance = distance
	return best

func line_is_clear(from: Vector2, to: Vector2) -> bool:
	return _first_block_contact(from, to, 0.0) == INF

func move_body(from: Vector2, displacement: Vector2, radius: float) -> Vector2:
	var result = from
	# Fixed tiny steps and separate axes give stable sliding without corner tunnelling.
	var count = maxi(1, int(ceil(displacement.length() / maxf(radius * 0.5, 0.05))))
	var part = displacement / float(count)
	for index in count:
		result.x += part.x
		result = _resolve_body(result, radius, Vector2(part.x, 0.0))
		result.y += part.y
		result = _resolve_body(result, radius, Vector2(0.0, part.y))
	return result

func damage_player(amount: float, _damage_kind: String = "direct") -> bool:
	if phase != "combat" or player.health <= 0.0 or player.invulnerable > 0.0 or amount <= 0.0:
		return false
	var absorbed = minf(player.shield, amount)
	player.shield -= absorbed
	var health_loss = minf(player.health, amount - absorbed)
	player.health -= health_loss
	damage_taken += absorbed + health_loss
	player.invulnerable = float(_base.player.hurt_invulnerability)
	_emit("hurt", {"pos": player.pos, "amount": amount, "shield_damage": absorbed, "health_damage": health_loss}, 0.45)
	if player.health <= 0.0:
		phase = "dead"
		_stop_combat()
		portal.visible = false
		portal.usable = false
	return true

func damage_enemy(actor: Dictionary, amount: float, spell_id: String = ""):
	if phase != "combat" or actor.is_empty() or actor.health <= 0.0:
		return
	var actual = minf(actor.health, amount)
	actor.health -= actual
	hits += 1
	damage_dealt += actual
	_emit("damage", {"pos": actor.pos, "amount": actual, "spell_id": spell_id, "actor_id": actor.id}, 0.55)
	if actor.health <= 0.0:
		kills += 1
		actor.phase = "dead"
		_emit("death", {"pos": actor.pos, "actor_id": actor.id}, 0.5)

func _tick(dt: float, move: Vector2):
	_fade_effects(dt)
	player.previous = player.pos
	player.pos = move_body(player.pos, move * player.move_speed * dt, player.radius)
	if move.length_squared() > 0.00001:
		player.face = move
	if phase == "exit":
		if portal.usable and move.length_squared() > 0.00001 and player.pos.distance_to(portal.pos) <= float(portal.radius):
			phase = "complete"
			portal.usable = false
			_emit("complete", {"pos": portal.pos}, 1.0)
		return
	time += dt
	player.invulnerable = maxf(0.0, player.invulnerable - dt)
	_update_spawn(dt)
	_update_enemies(dt)
	if phase != "combat":
		return
	_update_projectiles(dt)
	_update_spirit(dt)
	_update_spells(dt)
	_check_clear()

func _update_spawn(dt: float):
	if _spawn_done:
		return
	if spawn_warnings.is_empty():
		_reserve_batch()
		return
	for warning in spawn_warnings:
		warning.remaining = maxf(0.0, warning.remaining - dt)
	if float(spawn_warnings[0].remaining) > 0.000001:
		return
	var positions: Array = []
	for warning in spawn_warnings:
		positions.append(warning.pos)
	if not _valid_batch(positions):
		spawn_warnings.clear()
		_reserve_batch()
		return
	for pos in positions:
		var actor = {"id": _next_actor_id, "type": "M01", "name": _base.normal_types.M01.name, "pos": pos, "previous": pos, "health": float(_base.normal_stages[0].stats.M01.health), "max_health": float(_base.normal_stages[0].stats.M01.health), "damage": float(_base.normal_stages[0].stats.M01.damage), "radius": float(_runtime.M01.radius), "danger_radius": float(_base.normal_types.M01.danger_radius), "phase": "chase", "warning_remaining": 0.0, "lock_remaining": float(_spatial.spawn.attack_lock_after_appearance), "attack_from": pos, "attack_to": pos, "attack_elapsed": 0.0, "attack_hit": false, "recovery_remaining": 0.0, "next_attack_at": time}
		_next_actor_id += 1
		actors.append(actor)
		_emit("spawn", {"pos": pos, "actor_id": actor.id}, 0.5)
	spawn_warnings.clear()
	_spawn_done = true

func _reserve_batch():
	var candidates: Array = []
	for side in _runtime.room.spawn.side_x:
		for anchor in _runtime.room.spawn.anchor_z:
			for offset in _spatial.spawn.slot_offsets_z:
				candidates.append(Vector2(side, anchor + offset))
	for index in range(candidates.size() - 1, 0, -1):
		var other = _rng.randi_range(0, index)
		var value = candidates[index]
		candidates[index] = candidates[other]
		candidates[other] = value
	var selected: Array = []
	# First try one from each side, then fill any remaining slot without replacement.
	for side in [-1, 1]:
		for pos in candidates:
			if selected.size() >= _spawn_count:
				break
			if signf(pos.x) == side and _valid_spawn_position(pos, selected):
				selected.append(pos)
				break
	for pos in candidates:
		if selected.size() >= _spawn_count:
			break
		if pos not in selected and _valid_spawn_position(pos, selected):
			selected.append(pos)
	if selected.size() != _spawn_count:
		return
	var duration = float(_ordinary.spawn.preview_seconds)
	for pos in selected:
		spawn_warnings.append({"pos": pos, "radius": float(_spatial.spawn.normal_footprint_radius), "remaining": duration, "duration": duration})

func _valid_batch(positions: Array) -> bool:
	if positions.size() != _spawn_count:
		return false
	var checked: Array = []
	for pos in positions:
		if not _valid_spawn_position(pos, checked):
			return false
		checked.append(pos)
	return true

func _valid_spawn_position(pos: Vector2, others: Array) -> bool:
	var radius = float(_spatial.spawn.normal_footprint_radius)
	var clearance = float(_spatial.spawn.static_clearance)
	if pos.distance_to(player.pos) < float(_ordinary.spawn.safe_player_distance) - 0.000001:
		return false
	if not _body_clear(pos, radius + clearance):
		return false
	for other in others:
		if pos.distance_to(other) < float(_spatial.spawn.minimum_slot_spacing) - 0.000001:
			return false
	for actor in actors:
		if actor.health > 0.0 and pos.distance_to(actor.pos) < radius + float(actor.radius) + float(_spatial.spawn.existing_enemy_clearance):
			return false
	return true

func _update_enemies(dt: float):
	for actor in actors:
		if actor.health <= 0.0 or phase != "combat":
			continue
		actor.previous = actor.pos
		actor.lock_remaining = maxf(0.0, actor.lock_remaining - dt)
		if actor.phase == "chase":
			var offset: Vector2 = player.pos - actor.pos
			if actor.lock_remaining <= 0.0 and time + 0.000001 >= actor.next_attack_at and offset.length() <= float(_runtime.M01.attack_trigger_range) and line_is_clear(actor.pos, player.pos):
				actor.phase = "warning"
				actor.warning_remaining = float(_base.normal_types.M01.warning)
				actor.attack_from = actor.pos
				var direction = offset.normalized() if offset.length_squared() > 0.000001 else Vector2(0, -1)
				actor.attack_to = _clip_motion(actor.pos, direction * float(_runtime.M01.lunge_distance), actor.radius)
				actor.next_attack_at = time + float(_base.normal_types.M01.attack_cycle)
				actor.attack_hit = false
			else:
				actor.pos = _chase_position(actor.pos, player.pos, float(_runtime.M01.move_speed) * dt, actor.radius)
		elif actor.phase == "warning":
			actor.warning_remaining = maxf(0.0, actor.warning_remaining - dt)
			if actor.warning_remaining <= 0.000001:
				actor.phase = "lunge"
				actor.attack_elapsed = 0.0
		elif actor.phase == "lunge":
			actor.attack_elapsed = minf(float(_runtime.M01.lunge_duration), actor.attack_elapsed + dt)
			actor.pos = actor.attack_from.lerp(actor.attack_to, actor.attack_elapsed / float(_runtime.M01.lunge_duration))
			if not actor.attack_hit:
				var relative_start: Vector2 = actor.previous - player.previous
				var relative_end: Vector2 = actor.pos - player.pos
				if segment_circle_time(relative_start, relative_end, Vector2.ZERO, float(_base.normal_types.M01.danger_radius) + float(player.radius)) != INF:
					actor.attack_hit = true
					damage_player(actor.damage)
			if actor.attack_elapsed >= float(_runtime.M01.lunge_duration) - 0.000001:
				actor.phase = "recover"
				actor.recovery_remaining = float(_runtime.M01.recovery)
		elif actor.phase == "recover":
			actor.recovery_remaining = maxf(0.0, actor.recovery_remaining - dt)
			if actor.recovery_remaining <= 0.000001:
				actor.phase = "chase"

func _chase_position(from: Vector2, target: Vector2, distance: float, radius: float) -> Vector2:
	var next = target
	if _first_block_contact(from, target, radius + 0.04) != INF:
		# Visibility graph through inflated rectangle corners; exact local routes around
		# the two approved covers avoid a chase getting stuck against a flat face.
		var points: Array = [from, target]
		for block in blocks:
			var half: Vector2 = block.size * 0.5 + Vector2.ONE * (radius + 0.06)
			for corner in [Vector2(-half.x, -half.y), Vector2(-half.x, half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y)]:
				var point: Vector2 = block.center + corner
				if _body_clear(point, radius):
					points.append(point)
		var costs: Array = []
		var previous: Array = []
		var visited: Array = []
		for point in points:
			costs.append(INF)
			previous.append(-1)
			visited.append(false)
		costs[0] = 0.0
		for iteration in points.size():
			var best = -1
			for index in points.size():
				if not visited[index] and (best == -1 or costs[index] < costs[best]):
					best = index
			if best == -1 or costs[best] == INF:
				break
			visited[best] = true
			if best == 1:
				break
			for index in points.size():
				if visited[index] or _first_block_contact(points[best], points[index], radius + 0.03) != INF:
					continue
				var cost: float = costs[best] + points[best].distance_to(points[index])
				if cost < costs[index]:
					costs[index] = cost
					previous[index] = best
		if previous[1] >= 0:
			var node = 1
			while previous[node] > 0:
				node = previous[node]
			next = points[node]
	return move_body(from, (next - from).limit_length(distance), radius)

func _update_spells(dt: float):
	for spell in spells:
		if phase != "combat":
			return
		spell.remaining = maxf(0.0, spell.remaining - dt)
		if spell.id not in INITIAL_IDS:
			continue
		if spell.id == "F04" and spirit.active:
			continue
		var clearance = float(_runtime.bolt_collision_radius) if spell.id == "F01" else (float(_base.spells.F08.width) * 0.5 if spell.id == "F08" else 0.0)
		if spell.cast_remaining > 0.0:
			spell.cast_remaining = maxf(0.0, spell.cast_remaining - dt)
			if spell.cast_remaining <= 0.000001:
				var target = nearest_target(player.pos, float(spell.range), spell.id != "F04", clearance)
				if not target.is_empty():
					_release_spell(spell, target)
				else:
					spell.target_id = -1
		elif spell.remaining <= 0.000001:
			var target = nearest_target(player.pos, float(spell.range), spell.id != "F04", clearance)
			if not target.is_empty():
				spell.cast_remaining = float(spell.windup)
				spell.target_id = target.id
				_emit("cast", {"pos": player.pos, "spell_id": spell.id, "target_id": target.id}, spell.windup)

func _release_spell(spell: Dictionary, target: Dictionary):
	spell.cast_remaining = 0.0
	spell.remaining = float(spell.cooldown)
	spell.target_id = target.id
	casts += 1
	var data: Dictionary = _base.spells[spell.id]
	var level: Dictionary = data.levels[int(spell.level) - 1]
	if spell.id == "F01":
		var direction: Vector2 = (target.pos - player.pos).normalized()
		var duration = float(data.travel_delay)
		var length: float = spell.range
		# The configured travel delay is time to the locked target distance. A miss
		# continues along the locked ray only as far as this spell's actual range.
		var speed = maxf(player.pos.distance_to(target.pos), float(player.radius)) / duration
		projectiles.append({"id": _next_projectile_id, "spell_id": spell.id, "from": player.pos, "to": _clip_motion(player.pos, direction * length, 0.0), "pos": player.pos, "direction": direction, "speed": speed, "travelled": 0.0, "range": length, "duration": length / speed, "remaining": length / speed, "radius": float(_runtime.bolt_collision_radius), "blast_radius": float(level.radius), "damage": _roll_damage(float(level.coefficient))})
		_next_projectile_id += 1
	elif spell.id == "F08":
		var direction: Vector2 = (target.pos - player.pos).normalized()
		var end = _clip_motion(player.pos, direction * float(spell.range), float(data.width) * 0.5)
		_fire_beam(player.pos, end, float(data.width) * 0.5, _roll_damage(float(level.coefficient)), spell.id, true)
	elif spell.id == "F04":
		spirit.active = true
		spirit.remaining = float(data.duration)
		spirit.attack_remaining = float(level.interval)
		spirit.pos = _spirit_position()
		_emit("summon", {"pos": spirit.pos, "spell_id": spell.id}, 0.7)

func _update_projectiles(dt: float):
	var retained: Array = []
	for projectile in projectiles:
		var from: Vector2 = projectile.pos
		var distance = minf(float(projectile.speed) * dt, float(projectile.range) - float(projectile.travelled))
		var to: Vector2 = from + projectile.direction * distance
		var block_time = _first_block_contact(from, to, projectile.radius)
		var earliest = block_time
		var hit: Dictionary = {}
		for actor in actors:
			if actor.health <= 0.0:
				continue
			var contact = segment_circle_time(from - actor.previous, to - actor.pos, Vector2.ZERO, float(actor.radius) + float(projectile.radius))
			if contact < earliest - 0.000001 or (absf(contact - earliest) < 0.000001 and contact != INF and not hit.is_empty() and actor.id < hit.id):
				earliest = contact
				hit = actor
		if earliest != INF:
			var impact = from.lerp(to, clampf(earliest, 0.0, 1.0))
			if not hit.is_empty():
				# The selected blast is a range effect and may affect enemies around
				# cover, as required by the shared range-versus-direct rule.
				for actor in actors:
					if actor.health > 0.0 and actor.pos.distance_to(impact) <= float(projectile.blast_radius) + float(actor.radius):
						damage_enemy(actor, projectile.damage, projectile.spell_id)
			_emit("bolt_hit", {"pos": impact, "radius": projectile.blast_radius, "spell_id": projectile.spell_id, "blocked": hit.is_empty()}, 0.35)
			continue
		projectile.pos = to
		projectile.travelled += distance
		projectile.remaining = maxf(0.0, projectile.remaining - dt)
		if projectile.travelled < projectile.range - 0.000001 and _inside_floor(projectile.pos, projectile.radius):
			retained.append(projectile)
	projectiles = retained

func _update_spirit(dt: float):
	if not spirit.active:
		return
	spirit.pos = _spirit_position()
	var spell = _owned_spell("F04")
	var data: Dictionary = _base.spells.F04
	var level: Dictionary = data.levels[int(spell.level) - 1]
	spirit.remaining = maxf(0.0, spirit.remaining - dt)
	spirit.attack_remaining = maxf(0.0, spirit.attack_remaining - dt)
	if spirit.attack_remaining <= 0.000001:
		var target = nearest_target(spirit.pos, float(data.range), true)
		if not target.is_empty():
			var end: Vector2 = target.pos
			if level.pierce:
				end = _clip_motion(spirit.pos, (target.pos - spirit.pos).normalized() * float(data.range), 0.0)
			_fire_beam(spirit.pos, end, 0.0, _roll_damage(float(level.coefficient)), "F04", bool(level.pierce))
		# No stored attacks: every attempt starts a fresh full interval.
		spirit.attack_remaining = float(level.interval)
	if spirit.remaining <= 0.000001:
		spirit.active = false

func _spirit_position() -> Vector2:
	var offset: Array = _runtime.spirit_offset
	return move_body(player.pos, Vector2(offset[0], offset[1]), 0.1)

func _fire_beam(from: Vector2, to: Vector2, half_width: float, damage: float, spell_id: String, piercing: bool):
	var hits: Array = []
	for actor in actors:
		if actor.health <= 0.0:
			continue
		var contact = segment_circle_time(from, to, actor.pos, float(actor.radius) + half_width)
		if contact != INF:
			hits.append({"actor": actor, "at": contact})
	hits.sort_custom(func(a, b): return a.at < b.at if not is_equal_approx(a.at, b.at) else a.actor.id < b.actor.id)
	for hit in hits:
		damage_enemy(hit.actor, damage, spell_id)
		if not piercing:
			to = hit.actor.pos
			break
	_emit("beam" if spell_id == "F08" else "spirit_bolt", {"from": from, "to": to, "pos": to, "radius": half_width, "spell_id": spell_id}, 0.23)

func _check_clear():
	if phase != "combat" or not _spawn_done or not spawn_warnings.is_empty() or player.health <= 0.0:
		return
	for actor in actors:
		if actor.health > 0.0:
			return
	clear_count += 1
	gold += int(_economy.stages[0].clear_gold)
	dust += int(_meta.currency.room_dust_by_stage[_economy.stages[0].id])
	player.shield = player.max_shield
	_stop_combat()
	portal.visible = true
	portal.usable = false
	phase = "reward"
	reward_choices = _sample_rewards()
	_emit("clear", {"pos": portal.pos, "gold": gold, "dust": dust}, 1.0)
	if reward_choices.is_empty():
		phase = "exit"
		portal.usable = true

func _stop_combat():
	projectiles.clear()
	spawn_warnings.clear()
	spirit.active = false
	for spell in spells:
		spell.cast_remaining = 0.0
		spell.target_id = -1

func _sample_rewards() -> Array:
	var pool = eligible_reward_ids()
	var choices: Array = []
	var count = mini(pool.size(), int(_meta.spell_sampling_assumptions.offer_size))
	for index in count:
		var total = 0.0
		for spell_id in pool:
			total += reward_weight(spell_id)
		var roll = _rng.randf() * total
		var selected: String = pool.back()
		for spell_id in pool:
			roll -= reward_weight(spell_id)
			if roll < 0.0:
				selected = spell_id
				break
		pool.erase(selected)
		choices.append(_choice(selected))
	return choices

func _choice(spell_id: String, initial: bool = false) -> Dictionary:
	var owned = _owned_spell(spell_id)
	var level = 0 if initial or owned.is_empty() else int(owned.level)
	return {"id": spell_id, "name": _base.spells[spell_id].name, "level": level, "next_level": level + 1, "is_new": level == 0, "kind": _base.spells[spell_id].kind, "weight": reward_weight(spell_id), "next_stats": _base.spells[spell_id].levels[level].duplicate(true)}

func _new_spell(spell_id: String) -> Dictionary:
	var spell = {"id": spell_id, "name": _base.spells[spell_id].name, "level": 1, "cooldown": 0.0, "windup": 0.0, "cast_remaining": 0.0, "remaining": 0.0, "target_id": -1, "range": 0.0}
	_refresh_spell(spell)
	return spell

func _refresh_spell(spell: Dictionary):
	var data: Dictionary = _base.spells[spell.id]
	var level: Dictionary = data.levels[int(spell.level) - 1]
	spell.windup = float(data.get("windup", 0.0))
	spell.cooldown = float(level.get("cooldown", data.get("cooldown", 0.0)))
	spell.range = float(level.get("range", data.get("range", 0.0)))

func _owned_spell(spell_id: String) -> Dictionary:
	for spell in spells:
		if spell.id == spell_id:
			return spell
	return {}

func _roll_damage(coefficient: float) -> float:
	var damage = float(player.attack) * coefficient * (1.0 + float(player.fire_bonus))
	var roll := _rng.randf()
	var rate := maxf(0.0, float(player.crit_rate))
	if rate >= 1.0 or roll < rate:
		damage *= float(player.crit_multiplier)
	return damage

func _emit(kind: String, values: Dictionary, lifetime: float):
	event_seq += 1
	var effect = values.duplicate(true)
	effect.merge({"seq": event_seq, "kind": kind, "life": lifetime, "max_life": lifetime}, true)
	effects.append(effect)

func _fade_effects(dt: float):
	var live: Array = []
	for effect in effects:
		effect.life -= dt
		if effect.life > 0.0:
			live.append(effect)
	effects = live

func _inside_floor(pos: Vector2, radius: float) -> bool:
	return absf(pos.x) <= room_size.x * 0.5 - radius + 0.000001 and absf(pos.y) <= room_size.y * 0.5 - radius + 0.000001

func _body_clear(pos: Vector2, radius: float) -> bool:
	if not _inside_floor(pos, radius):
		return false
	for block in blocks:
		var half: Vector2 = block.size * 0.5
		var nearest = Vector2(clampf(pos.x, block.center.x - half.x, block.center.x + half.x), clampf(pos.y, block.center.y - half.y, block.center.y + half.y))
		if pos.distance_squared_to(nearest) < radius * radius - 0.0000001:
			return false
	return true

func _resolve_body(pos: Vector2, radius: float, motion: Vector2) -> Vector2:
	pos.x = clampf(pos.x, -room_size.x * 0.5 + radius, room_size.x * 0.5 - radius)
	pos.y = clampf(pos.y, -room_size.y * 0.5 + radius, room_size.y * 0.5 - radius)
	for block in blocks:
		var half: Vector2 = block.size * 0.5
		var nearest = Vector2(clampf(pos.x, block.center.x - half.x, block.center.x + half.x), clampf(pos.y, block.center.y - half.y, block.center.y + half.y))
		var offset = pos - nearest
		if offset.length_squared() >= radius * radius:
			continue
		if offset.length_squared() > 0.00000001:
			pos = nearest + offset.normalized() * radius
		elif absf(motion.x) > 0.0:
			pos.x = block.center.x - half.x - radius if motion.x > 0.0 else block.center.x + half.x + radius
		else:
			pos.y = block.center.y - half.y - radius if motion.y > 0.0 else block.center.y + half.y + radius
	return pos

func _clip_motion(from: Vector2, displacement: Vector2, radius: float) -> Vector2:
	var to = from + displacement
	var limit = _first_block_contact(from, to, radius)
	if limit != INF:
		to = from.lerp(to, maxf(0.0, limit - 0.00001))
	var floor_limit = Vector2(room_size.x * 0.5 - radius, room_size.y * 0.5 - radius)
	var actual = to - from
	var fraction = 1.0
	for axis in [0, 1]:
		if actual[axis] > 0.0:
			fraction = minf(fraction, (floor_limit[axis] - from[axis]) / actual[axis])
		elif actual[axis] < 0.0:
			fraction = minf(fraction, (-floor_limit[axis] - from[axis]) / actual[axis])
	return from + actual * clampf(fraction, 0.0, 1.0)

func _first_block_contact(from: Vector2, to: Vector2, inflate: float) -> float:
	var earliest = INF
	for block in blocks:
		var half: Vector2 = block.size * 0.5 + Vector2.ONE * inflate
		earliest = minf(earliest, segment_rectangle_time(from, to, block.center - half, block.center + half))
	return earliest

static func segment_rectangle_time(from: Vector2, to: Vector2, minimum: Vector2, maximum: Vector2) -> float:
	var enter = 0.0
	var leave = 1.0
	var difference = to - from
	for axis in [0, 1]:
		if absf(difference[axis]) < 0.0000001:
			if from[axis] < minimum[axis] or from[axis] > maximum[axis]:
				return INF
		else:
			var first = (minimum[axis] - from[axis]) / difference[axis]
			var second = (maximum[axis] - from[axis]) / difference[axis]
			enter = maxf(enter, minf(first, second))
			leave = minf(leave, maxf(first, second))
			if enter > leave:
				return INF
	return enter if leave >= 0.0 and enter <= 1.0 else INF

static func segment_circle_time(from: Vector2, to: Vector2, center: Vector2, radius: float) -> float:
	var offset = from - center
	if offset.length_squared() <= radius * radius:
		return 0.0
	var difference = to - from
	var a = difference.length_squared()
	if a < 0.00000001:
		return INF
	var b = 2.0 * offset.dot(difference)
	var c = offset.length_squared() - radius * radius
	var discriminant = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return INF
	var result = (-b - sqrt(discriminant)) / (2.0 * a)
	return result if result >= 0.0 and result <= 1.0 else INF

func _read_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "无法读取首房参数：" + path}
	var parser = JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "首房参数格式无效：" + path}
	return {"ok": true, "data": parser.data}
