extends Node2D
## F08 is reconstructed from actual lines/hits, never from a visual raycast.
## A same-time, same-line native echo is one bounded two-stream composition.
const CONFIG_PATH := "res://data/fire_beam_vfx.json"
const LINE_SHADER = preload("res://scripts/presentation/fire_beam_line.gdshader")
const SURFACE_SHADER = preload("res://scripts/presentation/fire_beam_surface.gdshader")
const BODY_SHADER = preload("res://scripts/presentation/fire_bolt_body.gdshader")

var _config: Dictionary = {}
var _available := false
var _clock := 0.0
var _revision := -1
var _reduced := false
var _coverage: Dictionary = {}
var _footprints: Array = []
var _beams: Array = []
var _groups: Array = []
var _burns: Dictionary = {}
var _cooling: Dictionary = {}
var _overflow := 0
var _body_count := 0
var _surface_count := 0
var _lines: MeshInstance2D
var _mesh: ArrayMesh
var _bodies: MultiMeshInstance2D
var _surfaces: MultiMeshInstance2D
var _line_material: ShaderMaterial
var _body_material: ShaderMaterial
var _surface_material: ShaderMaterial
var _vertices := PackedVector3Array()
var _uvs := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


func _ready() -> void:
	name = "FireBeamFullChain"
	set_process(false)
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not loaded is Dictionary or not _valid_config(loaded):
		push_error("Invalid F08 visual configuration; keeping legacy beam drawing.")
		return
	_config = loaded
	_line_material = _material(LINE_SHADER)
	_body_material = _material(BODY_SHADER)
	_surface_material = _material(SURFACE_SHADER)
	_body_material.set_shader_parameter("body_axes", Vector2(_config.body_axes[0], _config.body_axes[1]))
	_body_material.set_shader_parameter("core_axes", Vector2(_config.core_axes[0], _config.core_axes[1]))
	_body_material.set_shader_parameter("quad_radii", float(_config.head_quad_radii))
	_mesh = ArrayMesh.new()
	_lines = MeshInstance2D.new()
	_lines.name = "AuthoritativeWholeBeamLines"
	_lines.mesh = _mesh
	_lines.material = _line_material
	add_child(_lines)
	_bodies = _batch("SourceOwnedAttachedFlames", _body_material, int(_config.flame_capacity))
	_surfaces = _batch("ChantActualHitsAndContraction", _surface_material, int(_config.surface_capacity))
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
	if str(snapshot.get("phase", "")) != "combat" or not snapshot.has("fire_beam_facts"):
		_clear()
		return
	_reduced = bool(options.get("reduced_motion", false))
	for mat in [_line_material, _body_material, _surface_material]:
		mat.set_shader_parameter("core_time", now)
		mat.set_shader_parameter("reduced_motion", _reduced)
	_reset_geometry()
	for key in _cooling.keys():
		if now - float(_cooling[key].time) >= float(_config.cooling_seconds): _cooling.erase(key)
	var echoes: Dictionary = {}
	for fact: Dictionary in snapshot.fire_beam_facts:
		var age := now - float(fact.time)
		if age < 0.0 or age >= float(fact.lifetime): continue
		_beams.append(fact.duplicate(true))
		if str(fact.source) == "echo": echoes["%d:%s" % [int(fact.parent_cast_id), str(fact.phase)]] = fact
	var used: Dictionary = {}
	var density := maxf(float(_config.overlap_alpha_floor), 1.0 / sqrt(maxf(1.0, float(_beams.size()) / float(_config.overlap_soft_limit))))
	for fact: Dictionary in _beams:
		if used.has(int(fact.seq)): continue
		var events: Array = [fact]
		var echo: Dictionary = echoes.get("%d:%s" % [int(fact.cast_id), str(fact.phase)], {})
		if str(fact.source) == "natural" and not echo.is_empty() and _same_line(fact, echo):
			events.append(echo)
			used[int(echo.seq)] = true
		used[int(fact.seq)] = true
		if _groups.size() >= int(_config.beam_capacity):
			_overflow += 1
			continue
		_draw_group(events, density, view)
	_draw_burns(snapshot, view)
	for effect: Dictionary in snapshot.get("effects", []):
		if str(effect.get("kind", "")) != "cast" or str(effect.get("spell_id", "")) != "F08" or float(effect.get("life", 0.0)) <= 0.0: continue
		var progress := 1.0 - float(effect.life) / maxf(0.000001, float(effect.max_life))
		var pos: Vector2 = snapshot.get("player", {}).get("pos", effect.pos)
		_surface(pos, float(_config.height_m), float(_config.cast_radius_m), 0, progress, 0.56, _seed(int(effect.seq)), view)
		_note("F08_cast")
	for item: Dictionary in _cooling.values():
		var age := now - float(item.time)
		if age < 0.0 or age >= float(_config.cooling_seconds): continue
		_surface(item.pos, 0.10, float(item.radius), 5, age / float(_config.cooling_seconds), 0.44, float(item.seed), view)
		_note("F08_cooling")
	_upload()
	_bodies.multimesh.visible_instance_count = _body_count
	_surfaces.multimesh.visible_instance_count = _surface_count
	visible = not _indices.is_empty() or _body_count > 0 or _surface_count > 0


func _same_line(left: Dictionary, right: Dictionary) -> bool:
	return Vector2(left.from).is_equal_approx(right.from) and Vector2(left.to).is_equal_approx(right.to) and is_equal_approx(float(left.half_width), float(right.half_width)) and absf(float(left.time) - float(right.time)) < 0.000001


func _draw_group(events: Array, density: float, view) -> void:
	var first: Dictionary = events[0]
	var pulse := str(first.phase) == "pulse"
	var source := str(first.source)
	var mode := (7 if pulse else 6) if events.size() == 2 else (3 if pulse else 2) if source == "echo" else (5 if pulse else 4) if source == "extra" else (1 if pulse else 0)
	var age := _clock - float(first.time)
	var duration := float(first.lifetime)
	var progress := clampf(age / maxf(0.000001, duration), 0.0, 1.0)
	var alpha := float(_config.pulse_alpha if pulse else _config.main_alpha)
	if source == "echo": alpha *= float(_config.echo_alpha)
	elif source == "extra": alpha *= float(_config.extra_alpha)
	alpha *= density
	var from: Vector2 = first.from
	var to: Vector2 = first.to
	var direction := (to - from).normalized()
	if direction.is_zero_approx(): direction = Vector2.RIGHT
	var normal := Vector2(-direction.y, direction.x)
	var half := float(first.half_width)
	var corners := PackedVector2Array([from - normal * half, from + normal * half, to - normal * half, to + normal * half])
	var sequences: Array = []
	for fact: Dictionary in events:
		sequences.append(int(fact.seq))
		_note("F08_pulse" if str(fact.phase) == "pulse" else "F08_main")
		if str(fact.source) == "echo": _note("F08_echo")
		_footprints.append({"kind": "beam", "seq": fact.seq, "cast_id": fact.cast_id, "parent_cast_id": fact.parent_cast_id,
			"source": fact.source, "phase": fact.phase, "from": fact.from, "to": fact.to, "half_width": fact.half_width, "time": fact.time})
	_groups.append({"seqs": sequences, "mode": mode, "from": from, "to": to, "half_width": half, "world_corners": corners, "progress": progress, "alpha": alpha})
	if from.distance_squared_to(to) > 0.00000001 and half > 0.0:
		var base := _vertices.size()
		for index in 4:
			var point: Vector2 = view.screen_position(corners[index], float(_config.height_m))
			_vertices.append(Vector3(point.x, point.y, 0))
			_uvs.append(Vector2(0.0 if index < 2 else 1.0, float(index % 2)))
			_colors.append(Color(_seed(int(first.cast_id)), progress, float(mode) / 8.0, alpha))
		_indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	if not pulse and age < minf(float(_config.release_seconds), duration):
		_surface(from, float(_config.height_m), float(_config.release_radius_m), 1, age / minf(float(_config.release_seconds), duration), alpha, _seed(int(first.cast_id)), view, direction)
		_note("F08_release")
	var ending := minf(float(_config.end_seconds), duration)
	if age >= duration - ending:
		_surface(to, float(_config.height_m), float(_config.end_radius_m), 3, (age - duration + ending) / ending, alpha * 0.55, _seed(int(first.cast_id)), view, direction)
		_note("F08_contract")
	var flashed: Dictionary = {}
	for fact: Dictionary in events:
		for hit: Dictionary in fact.hits:
			_footprints.append({"kind": "beam_hit", "actor_id": hit.actor_id, "pos": hit.pos, "damage": hit.damage,
				"seq": fact.seq, "source": fact.source, "phase": fact.phase, "time": fact.time, "alive_after": hit.alive_after})
			var key := "%d:%s" % [int(hit.actor_id), str(hit.pos)]
			if flashed.has(key) or age >= minf(float(_config.hit_seconds), duration): continue
			flashed[key] = true
			_surface(hit.pos, float(_config.height_m), float(hit.radius) * float(_config.hit_radius_ratio), 2, age / minf(float(_config.hit_seconds), duration), alpha, _seed(int(hit.actor_id) + int(fact.seq)), view, direction)
			_note("F08_hit")


func _draw_burns(snapshot: Dictionary, view) -> void:
	var actors: Dictionary = {}
	for actor: Dictionary in snapshot.get("actors", []): actors[int(actor.id)] = actor
	var all_live: Dictionary = {}
	var owned: Dictionary = {}
	for burn: Dictionary in snapshot.get("spell_burns", []):
		var id := int(burn.actor_id)
		all_live[id] = true
		if str(burn.get("source", "")) != "F08" or not actors.has(id) or float(actors[id].health) <= 0.0 or float(burn.remaining) <= 0.0: continue
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
			_surface(actor.pos, 0.36, float(actor.radius) * 1.2, 4, (_clock - born) / float(_config.ignite_seconds), 0.48, _seed(id), view)
			_note("F08_ignited")
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
		if str(effect.get("kind", "")) == "fire_ignited" and str(effect.get("source", "")) == "F08" and int(effect.get("actor_id", -1)) == id:
			born = maxf(born, _clock - maxf(0.0, float(effect.max_life) - float(effect.life)))
	return born


func _surface(pos: Vector2, height: float, radius: float, mode: int, progress: float, alpha: float, seed: float, view, direction: Vector2 = Vector2.RIGHT) -> void:
	if _surface_count >= int(_config.surface_capacity):
		_overflow += 1
		return
	var center: Vector2 = view.screen_position(pos, height)
	var axis: Vector2 = view.screen_position(pos + direction, height) - center
	axis = axis.normalized() if axis.length_squared() > 0.000001 else Vector2.RIGHT
	var dimension := _radius(pos, radius, height, view) * 2.0
	_surfaces.multimesh.set_instance_transform_2d(_surface_count, Transform2D(axis * dimension, Vector2(-axis.y, axis.x) * dimension, center))
	_surfaces.multimesh.set_instance_custom_data(_surface_count, Color(seed, progress, float(mode) / 8.0, alpha))
	_surface_count += 1


func _upright(pos: Vector2, base: float, height: float, width: float, alpha: float, seed: float, view) -> void:
	if height <= 0.000001 or alpha <= 0.0: return
	if _body_count >= int(_config.flame_capacity):
		_overflow += 1
		return
	var center: Vector2 = view.screen_position(pos, base + height * 0.28)
	var up: Vector2 = view.screen_position(pos, base + height) - view.screen_position(pos, base)
	var across: Vector2 = view.screen_position(pos + Vector2(width, 0), base) - view.screen_position(pos, base)
	var x := up * float(_config.head_quad_radii) / 3.5
	var y := Vector2(-up.y, up.x).normalized() * across.length() * float(_config.head_quad_radii) / 1.65
	_bodies.multimesh.set_instance_transform_2d(_body_count, Transform2D(x, y, center))
	_bodies.multimesh.set_instance_custom_data(_body_count, Color(seed, 0, 1, alpha))
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
	_coverage.clear()
	_footprints.clear()
	_beams.clear()
	_groups.clear()
	_vertices.clear()
	_uvs.clear()
	_colors.clear()
	_indices.clear()
	_body_count = 0
	_surface_count = 0
	_overflow = 0


func _clear() -> void:
	_reset_geometry()
	_burns.clear()
	_cooling.clear()
	if _available:
		_bodies.multimesh.visible_instance_count = 0
		_surfaces.multimesh.visible_instance_count = 0
		if _mesh.get_surface_count() > 0: _mesh.clear_surfaces()
	visible = false


func get_debug_state() -> Dictionary:
	return {"available": _available, "clock": _clock, "revision": _revision,
		"beams": _beams.duplicate(true), "groups": _groups.duplicate(true), "coverage": _coverage.duplicate(true), "footprints": _footprints.duplicate(true),
		"burns": _burns.duplicate(true), "cooling": _cooling.duplicate(true), "vertices": _vertices.duplicate(), "uvs": _uvs.duplicate(), "colors": _colors.duplicate(), "indices": _indices.duplicate(),
		"body_instances": _body_count, "surface_instances": _surface_count, "overflow": _overflow, "batch_nodes": get_child_count(), "material_count": 3}


func _valid_config(cfg: Dictionary) -> bool:
	if int(cfg.get("version", 0)) != 1: return false
	for key in ["body_axes", "core_axes"]:
		if not cfg.get(key) is Array or cfg[key].size() != 2: return false
		for value in cfg[key]:
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0.0: return false
	for key in ["height_m", "beam_capacity", "surface_capacity", "flame_capacity", "cooling_capacity", "main_alpha", "pulse_alpha", "echo_alpha", "extra_alpha", "flow_speed", "cast_radius_m", "release_radius_m", "release_seconds", "hit_seconds", "hit_radius_ratio", "end_seconds", "end_radius_m", "head_quad_radii", "rear_stretch", "ignite_seconds", "burn_flames", "burn_flame_height_m", "burn_flame_width_m", "burn_alpha", "source_fade_seconds", "cooling_seconds", "overlap_soft_limit", "overlap_alpha_floor"]:
		var value: Variant = cfg.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0.0: return false
	for key in ["edge_color", "shell_color", "energy_color", "core_color", "ember_color"]:
		if not cfg.get(key) is Array or cfg[key].size() != 4: return false
		for value in cfg[key]:
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0: return false
	return true
