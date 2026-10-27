extends Node2D
## F09 consumes completed instant attacks and existing source-owned statuses.
## Decorative expansion never delays damage or moves an actor.
const CONFIG_PATH := "res://data/fire_wave_vfx.json"
const SURFACE_SHADER = preload("res://scripts/presentation/fire_wave_surface.gdshader")
const BODY_SHADER = preload("res://scripts/presentation/fire_bolt_body.gdshader")
const TRAIL_SHADER = preload("res://scripts/presentation/fire_bolt_trail.gdshader")

var _config: Dictionary = {}
var _available := false
var _clock := 0.0
var _revision := -1
var _reduced := false
var _coverage: Dictionary = {}
var _footprints: Array = []
var _waves: Array = []
var _strips: Array = []
var _burns: Dictionary = {}
var _cooling: Dictionary = {}
var _body_count := 0
var _ground_count := 0
var _burst_count := 0
var _overflow := 0
var _grounds: MultiMeshInstance2D
var _bodies: MultiMeshInstance2D
var _bursts: MultiMeshInstance2D
var _ribbons: MeshInstance2D
var _mesh: ArrayMesh
var _body_material: ShaderMaterial
var _trail_material: ShaderMaterial
var _surface_material: ShaderMaterial
var _vertices := PackedVector3Array()
var _uvs := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


func _ready() -> void:
	name = "FireWaveFullChain"
	set_process(false)
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not loaded is Dictionary or not _valid_config(loaded):
		push_error("Invalid F09 visual configuration; keeping legacy wave drawing.")
		return
	_config = loaded
	_body_material = _material(BODY_SHADER)
	_body_material.set_shader_parameter("body_axes", Vector2(_config.body_axes[0], _config.body_axes[1]))
	_body_material.set_shader_parameter("core_axes", Vector2(_config.core_axes[0], _config.core_axes[1]))
	_trail_material = _material(TRAIL_SHADER)
	_surface_material = _material(SURFACE_SHADER)
	_grounds = _batch("InstantCoverageAndActualStatuses", _surface_material, int(_config.surface_capacity))
	_mesh = ArrayMesh.new()
	_ribbons = MeshInstance2D.new()
	_ribbons.name = "ActualPushDisplacementTraces"
	_ribbons.mesh = _mesh
	_ribbons.material = _trail_material
	add_child(_ribbons)
	_bodies = _batch("LowWaveTonguesAndSourceBurns", _body_material, int(_config.flame_capacity))
	_bursts = _batch("ActualHitIgnitionAndCooling", _surface_material, int(_config.surface_capacity))
	_available = true
	visible = false


func is_available() -> bool:
	return _available


func sync_snapshot(snapshot: Dictionary, view, options: Dictionary = {}) -> void:
	if not _available: return
	var now := float(snapshot.get("time", 0.0))
	var revision := int(snapshot.get("room_revision", 0))
	if revision != _revision or now < _clock - 0.000001: _clear()
	_clock = now
	_revision = revision
	if str(snapshot.get("phase", "")) != "combat" or not snapshot.has_all(["fire_wave_facts", "fire_wave_speed"]):
		_clear()
		return
	_reduced = bool(options.get("reduced_motion", false))
	for mat in [_body_material, _trail_material, _surface_material]:
		mat.set_shader_parameter("core_time", now)
		mat.set_shader_parameter("reduced_motion", _reduced)
	_reset_geometry()
	for key in _cooling.keys():
		if now - float(_cooling[key].time) >= float(_config.cooling_seconds): _cooling.erase(key)
	var facts: Array = snapshot.fire_wave_facts.filter(func(f): return now >= float(f.time) and now - float(f.time) < float(_config.wave_seconds))
	var density := maxf(float(_config.overlap_alpha_floor), 1.0 / sqrt(maxf(1.0, float(facts.size()) / float(_config.overlap_soft_limit))))
	for fact: Dictionary in facts:
		if _waves.size() >= int(_config.wave_capacity):
			_overflow += 1
			continue
		_draw_wave(fact, density, view)
	_draw_statuses(snapshot, view)
	_draw_burns(snapshot, view)
	for effect: Dictionary in snapshot.get("effects", []):
		if str(effect.get("kind", "")) != "cast" or str(effect.get("spell_id", "")) != "F09" or float(effect.get("life", 0.0)) <= 0.0: continue
		var progress := 1.0 - float(effect.life) / maxf(0.000001, float(effect.max_life))
		var pos: Vector2 = snapshot.get("player", {}).get("pos", effect.pos)
		_surface(pos, 0.035, float(_config.cast_radius_m), 1, progress, 0.56, _seed(int(effect.seq)), view, true)
		_note("F09_cast")
	for item: Dictionary in _cooling.values():
		var progress := (now - float(item.time)) / float(_config.cooling_seconds)
		if progress < 0.0 or progress >= 1.0: continue
		_surface(item.pos, 0.10, float(item.radius), 7, progress, 0.38, float(item.seed), view)
		_note("F09_cooling")
	_upload()
	_grounds.multimesh.visible_instance_count = _ground_count
	_bodies.multimesh.visible_instance_count = _body_count
	_bursts.multimesh.visible_instance_count = _burst_count
	visible = _ground_count > 0 or _body_count > 0 or _burst_count > 0 or not _indices.is_empty()


func _draw_wave(fact: Dictionary, density: float, view) -> void:
	var age := _clock - float(fact.time)
	var progress := age / float(_config.wave_seconds)
	var pos: Vector2 = fact.pos
	var radius := float(fact.radius)
	var seed := _seed(int(fact.cast_id))
	var alpha := float(_config.wave_alpha) * density * (1.0 if bool(fact.natural) else float(_config.extra_alpha))
	_surface(pos, 0.035, radius, 0, progress, alpha, seed, view, true)
	var corners := PackedVector2Array([pos + Vector2(-radius, -radius), pos + Vector2(radius, -radius), pos + Vector2(-radius, radius), pos + Vector2(radius, radius)])
	_waves.append({"seq": fact.seq, "cast_id": fact.cast_id, "pos": pos, "radius": radius, "time": fact.time, "progress": progress, "natural": fact.natural, "world_corners": corners})
	_footprints.append({"kind": "wave", "cast_id": fact.cast_id, "pos": pos, "radius": radius, "time": fact.time, "spell_level": fact.spell_level, "natural": fact.natural})
	var count := 3 if _reduced else int(_config.wave_flames)
	var front := 0.10 + pow(progress, 0.55) * 0.85
	for index in count:
		var at := pos + Vector2.from_angle(seed * TAU + float(index) * TAU / count) * radius * front
		_upright(at, 0.04, float(_config.wave_flame_height_m) * pow(1.0 - progress, 0.8), float(_config.wave_flame_width_m), alpha * pow(1.0 - progress, 1.3) * 0.64, _seed(int(fact.seq) + index * 37), view)
	for hit: Dictionary in fact.hits:
		if float(hit.damage) > 0.0 and age < float(_config.hit_seconds):
			_surface(hit.from, 0.38, float(hit.radius) * float(_config.hit_radius_ratio), 2, age / float(_config.hit_seconds), alpha * 0.70, _seed(int(hit.actor_id) + int(fact.seq)), view)
			_footprints.append({"kind": "wave_hit", "actor_id": hit.actor_id, "cast_id": fact.cast_id, "pos": hit.from, "time": fact.time, "damage": hit.damage, "alive_after": hit.alive_after})
			_note("F09_hit")
		if age < float(_config.push_seconds): _push_strip(hit, int(fact.cast_id), alpha * (1.0 - age / float(_config.push_seconds)), view)
	_note("F09_wave")


func _push_strip(hit: Dictionary, cast_id: int, alpha: float, view) -> void:
	var from: Vector2 = hit.from
	var to: Vector2 = hit.to
	if from.distance_squared_to(to) < 0.00000001: return
	if _strips.size() >= int(_config.stroke_capacity):
		_overflow += 1
		return
	var direction := (to - from).normalized()
	var normal := Vector2(-direction.y, direction.x) * float(_config.push_half_width_m)
	var corners := PackedVector2Array([to - normal, to + normal, from - normal, from + normal])
	var base := _vertices.size()
	for index in 4:
		var point: Vector2 = view.screen_position(corners[index], 0.10)
		_vertices.append(Vector3(point.x, point.y, 0))
		_uvs.append(Vector2(0.0 if index < 2 else 1.0, float(index % 2)))
		_colors.append(Color(_seed(int(hit.actor_id) + cast_id), 0, 0, alpha))
	_indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	_strips.append({"actor_id": hit.actor_id, "cast_id": cast_id, "from": from, "to": to, "world_corners": corners})
	_note("F09_push")


func _draw_statuses(snapshot: Dictionary, view) -> void:
	var speed: Dictionary = snapshot.fire_wave_speed
	if float(speed.get("bonus", 0.0)) > 0.0 and float(speed.get("remaining", 0.0)) > 0.0 and float(speed.get("until", -INF)) > _clock:
		var player: Dictionary = snapshot.get("player", {})
		var pos: Vector2 = player.get("pos", Vector2.ZERO)
		var delta: Vector2 = pos - Vector2(player.get("previous", pos))
		var moving := delta.length_squared() > 0.00000001
		var direction := delta.normalized() if moving else Vector2.RIGHT
		var fade := clampf(float(speed.remaining) / float(_config.status_fade_seconds), 0.0, 1.0)
		_surface(pos, 0.03, float(_config.speed_radius_m), 4 if moving else 5, 0.0, float(_config.speed_alpha) * fade, 0.37, view, true, direction)
		_footprints.append({"kind": "wave_speed", "pos": pos, "moving": moving, "bonus": speed.bonus, "remaining": speed.remaining})
		_note("F09_speed")
	for actor: Dictionary in snapshot.get("actors", []):
		if float(actor.get("health", 0.0)) <= 0.0: continue
		var slow: Dictionary = actor.get("spell_slows", {}).get("F09", {})
		var remaining := float(slow.get("until", -INF)) - _clock
		if remaining <= 0.0 or float(slow.get("amount", 0.0)) <= 0.0: continue
		var fade := clampf(remaining / float(_config.status_fade_seconds), 0.0, 1.0)
		_surface(actor.pos, 0.035, float(actor.radius) * float(_config.slow_radius_ratio), 3, 0.0, float(_config.slow_alpha) * fade, _seed(int(actor.id)), view, true)
		_footprints.append({"kind": "wave_slow", "actor_id": actor.id, "pos": actor.pos, "amount": slow.amount, "remaining": remaining})
		_note("F09_slow")


func _draw_burns(snapshot: Dictionary, view) -> void:
	var actors: Dictionary = {}
	for actor: Dictionary in snapshot.get("actors", []): actors[int(actor.id)] = actor
	var all_live: Dictionary = {}
	var owned: Dictionary = {}
	for burn: Dictionary in snapshot.get("spell_burns", []):
		var id := int(burn.actor_id)
		all_live[id] = true
		if str(burn.get("source", "")) != "F09" or not actors.has(id) or float(actors[id].health) <= 0.0 or float(burn.remaining) <= 0.0: continue
		var actor: Dictionary = actors[id]
		var previous: Dictionary = _burns.get(id, {})
		var born := float(previous.born) if int(previous.get("token", -1)) == int(burn.token) else _ignition_time(snapshot, id)
		owned[id] = {"pos": actor.pos, "radius": float(actor.radius), "expires": _clock + float(burn.remaining), "seed": _seed(id), "born": born, "token": int(burn.token)}
		var fade := clampf(float(burn.remaining) / float(_config.source_fade_seconds), 0.0, 1.0)
		for index in (2 if _reduced else int(_config.burn_flames)):
			var seed := _seed(id + index * 71)
			var at: Vector2 = actor.pos + Vector2.from_angle(seed * TAU) * float(actor.radius) * 0.48
			_upright(at, 0.08, float(_config.burn_flame_height_m), float(_config.burn_flame_width_m), float(_config.burn_alpha) * fade, seed, view)
		if _clock - born >= 0.0 and _clock - born < float(_config.ignite_seconds):
			_surface(actor.pos, 0.36, float(actor.radius) * 1.2, 6, (_clock - born) / float(_config.ignite_seconds), 0.48, _seed(id), view)
			_note("F09_ignited")
		_footprints.append({"kind": "burning", "actor_id": id, "pos": actor.pos, "remaining": burn.remaining})
		_note("burning")
	for id in _burns:
		if all_live.has(id) or not actors.has(id) or float(actors[id].health) <= 0.0: continue
		var old: Dictionary = _burns[id]
		if _clock + 0.000001 < float(old.expires): continue
		var consumed := false
		for effect: Dictionary in snapshot.get("effects", []):
			if str(effect.get("kind", "")) == "fire_detonation" and int(effect.get("actor_id", -1)) == int(id): consumed = true
		if not consumed and _cooling.size() < int(_config.cooling_capacity):
			_cooling["burn:%d:%d" % [id, int(old.token)]] = {"pos": actors[id].pos, "radius": old.radius, "time": old.expires, "seed": old.seed}
	_burns = owned


func _ignition_time(snapshot: Dictionary, id: int) -> float:
	var born := -INF
	for effect: Dictionary in snapshot.get("effects", []):
		if str(effect.get("kind", "")) == "fire_ignited" and str(effect.get("source", "")) == "F09" and int(effect.get("actor_id", -1)) == id:
			born = maxf(born, _clock - maxf(0.0, float(effect.max_life) - float(effect.life)))
	return born


func _surface(pos: Vector2, height: float, radius: float, mode: int, progress: float, alpha: float, seed: float, view, ground: bool = false, direction: Vector2 = Vector2.RIGHT) -> void:
	if radius <= 0.0: return
	var center: Vector2 = view.screen_position(pos, height)
	var transform: Transform2D
	if ground:
		var axis := direction.normalized()
		var normal := Vector2(-axis.y, axis.x)
		transform = Transform2D(view.screen_position(pos + axis * radius * 2.0, height) - center, view.screen_position(pos + normal * radius * 2.0, height) - center, center)
	else:
		var size := _radius(pos, radius, height, view) * 2.0
		transform = Transform2D(Vector2.RIGHT * size, Vector2.DOWN * size, center)
	var index := _ground_count if ground else _burst_count
	if index >= int(_config.surface_capacity):
		_overflow += 1
		return
	var batch := _grounds if ground else _bursts
	batch.multimesh.set_instance_transform_2d(index, transform)
	batch.multimesh.set_instance_custom_data(index, Color(seed, progress, float(mode) / 8.0, alpha))
	if ground: _ground_count += 1
	else: _burst_count += 1


func _upright(pos: Vector2, base: float, height: float, width: float, alpha: float, seed: float, view) -> void:
	if height <= 0.000001 or alpha <= 0.0: return
	var center: Vector2 = view.screen_position(pos, base + height * 0.28)
	var up: Vector2 = view.screen_position(pos, base + height) - view.screen_position(pos, base)
	var across: Vector2 = view.screen_position(pos + Vector2(width, 0), base) - view.screen_position(pos, base)
	_body(Transform2D(up * float(_config.quad_radii) / 3.5, Vector2(-up.y, up.x).normalized() * across.length() * float(_config.quad_radii) / 1.65, center), Color(seed, 0, 1, alpha))


func _body(transform: Transform2D, data: Color) -> void:
	if _body_count >= int(_config.flame_capacity):
		_overflow += 1
		return
	_bodies.multimesh.set_instance_transform_2d(_body_count, transform)
	_bodies.multimesh.set_instance_custom_data(_body_count, data)
	_body_count += 1


func _radius(pos: Vector2, radius: float, height: float, view) -> float:
	var center: Vector2 = view.screen_position(pos, height)
	var x: Vector2 = view.screen_position(pos + Vector2(radius, 0), height) - center
	var y: Vector2 = view.screen_position(pos + Vector2(0, radius), height) - center
	return sqrt(absf(x.cross(y)))


static func _seed(id: int) -> float:
	return fposmod(float(id) * 0.61803398875, 1.0)


func _note(kind: String) -> void:
	_coverage[kind] = int(_coverage.get(kind, 0)) + 1


func _material(shader: Shader) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for uniform: Dictionary in shader.get_shader_uniform_list():
		var key := str(uniform.name)
		if not _config.has(key): continue
		if key.ends_with("_color"):
			var value: Array = _config[key]
			mat.set_shader_parameter(key, Color(value[0], value[1], value[2], value[3]))
		elif _config[key] is int or _config[key] is float: mat.set_shader_parameter(key, float(_config[key]))
	return mat


func _batch(title: String, mat: Material, capacity: int) -> MultiMeshInstance2D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-16384, -16384, -1), Vector3(32768, 32768, 2))
	var node := MultiMeshInstance2D.new()
	node.name = title
	node.multimesh = mm
	node.material = mat
	add_child(node)
	return node


func _upload() -> void:
	if _mesh.get_surface_count() > 0: _mesh.clear_surfaces()
	if _indices.is_empty(): return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _reset_geometry() -> void:
	_body_count = 0
	_ground_count = 0
	_burst_count = 0
	_overflow = 0
	_coverage.clear()
	_footprints.clear()
	_waves.clear()
	_strips.clear()
	_vertices.clear()
	_uvs.clear()
	_colors.clear()
	_indices.clear()


func _clear() -> void:
	_reset_geometry()
	_burns.clear()
	_cooling.clear()
	if _available:
		_grounds.multimesh.visible_instance_count = 0
		_bodies.multimesh.visible_instance_count = 0
		_bursts.multimesh.visible_instance_count = 0
		if _mesh.get_surface_count() > 0: _mesh.clear_surfaces()
	visible = false


func get_debug_state() -> Dictionary:
	return {"available": _available, "clock": _clock, "revision": _revision, "waves": _waves.duplicate(true),
		"strips": _strips.duplicate(true), "coverage": _coverage.duplicate(true), "footprints": _footprints.duplicate(true),
		"burns": _burns.duplicate(true), "cooling": _cooling.duplicate(true), "vertices": _vertices.duplicate(),
		"uvs": _uvs.duplicate(), "indices": _indices.duplicate(), "body_instances": _body_count,
		"ground_instances": _ground_count, "burst_instances": _burst_count, "overflow": _overflow,
		"batch_nodes": get_child_count(), "material_count": 3}


func _valid_config(cfg: Dictionary) -> bool:
	if int(cfg.get("version", 0)) != 1: return false
	if not cfg.has_all(["version", "scope", "wave_capacity", "surface_capacity", "flame_capacity", "stroke_capacity", "cooling_capacity", "wave_seconds", "wave_alpha", "wave_flames", "wave_flame_height_m", "wave_flame_width_m", "hit_seconds", "hit_radius_ratio", "push_seconds", "push_half_width_m", "tail_alpha", "cast_radius_m", "speed_radius_m", "speed_alpha", "status_fade_seconds", "slow_radius_ratio", "slow_alpha", "body_axes", "core_axes", "quad_radii", "rear_stretch", "flow_speed", "ignite_seconds", "burn_flames", "burn_flame_height_m", "burn_flame_width_m", "burn_alpha", "source_fade_seconds", "cooling_seconds", "overlap_soft_limit", "overlap_alpha_floor", "extra_alpha", "edge_color", "shell_color", "energy_color", "core_color", "ember_color"]): return false
	for key in cfg:
		var value: Variant = cfg[key]
		if key in ["version", "scope"]: continue
		if value is Array:
			if value.size() != (2 if key in ["body_axes", "core_axes"] else 4): return false
			for part in value:
				if not (part is int or part is float) or not is_finite(float(part)) or float(part) < 0.0: return false
		elif not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0.0: return false
	return true
