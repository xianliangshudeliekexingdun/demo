extends Node2D
## F07 observes released throws and completed core facts. Its arc never collides,
## retargets, ignites or schedules damage. Four fixed draw nodes share materials.
const CONFIG_PATH := "res://data/fire_bomb_vfx.json"
const BODY_SHADER = preload("res://scripts/presentation/fire_bomb_body.gdshader")
const TRAIL_SHADER = preload("res://scripts/presentation/fire_bolt_trail.gdshader")
const SURFACE_SHADER = preload("res://scripts/presentation/fire_bomb_surface.gdshader")

var _config: Dictionary = {}
var _available := false
var _clock := 0.0
var _revision := -1
var _reduced := false
var _coverage: Dictionary = {}
var _footprints: Array = []
var _heads: Array = []
var _paths: Array = []
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
	name = "FireBombFullChain"
	set_process(false)
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not loaded is Dictionary or not _valid_config(loaded):
		push_error("Invalid F07 visual configuration; keeping legacy bomb drawing.")
		return
	_config = loaded
	_body_material = _material(BODY_SHADER)
	_trail_material = _material(TRAIL_SHADER)
	_surface_material = _material(SURFACE_SHADER)
	_grounds = _batch("ActualInnerAndOuterBlast", _surface_material, int(_config.surface_capacity))
	_mesh = ArrayMesh.new()
	_ribbons = MeshInstance2D.new()
	_ribbons.name = "ContinuousWorldArcTrails"
	_ribbons.mesh = _mesh
	_ribbons.material = _trail_material
	add_child(_ribbons)
	_bodies = _batch("MoltenHeadsAndLocalFlames", _body_material, int(_config.flame_capacity))
	_bursts = _batch("ActualFuelAndCooling", _surface_material, int(_config.surface_capacity))
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
	if str(snapshot.get("phase", "")) != "combat" or not snapshot.has_all(["fire_bomb_facts", "fire_bomb_status_facts"]):
		_clear()
		return
	_reduced = bool(options.get("reduced_motion", false))
	for mat in [_body_material, _trail_material, _surface_material]:
		mat.set_shader_parameter("core_time", now)
		mat.set_shader_parameter("reduced_motion", _reduced)
	_reset_geometry()
	for key in _cooling.keys():
		if now - float(_cooling[key].time) >= float(_config.cooling_seconds): _cooling.erase(key)
	var flights: Dictionary = {}
	var pending: Dictionary = {}
	var active := 0
	for item: Dictionary in snapshot.get("spell_pending", []):
		if str(item.get("kind", "")) == "bomb" and str(item.get("context", {}).get("spell_id", "")) == "F07": pending[int(item.context.cast_id)] = true
	for fact: Dictionary in snapshot.fire_bomb_facts:
		if str(fact.phase) == "flight": flights[int(fact.cast_id)] = fact
		elif now >= float(fact.time) and now - float(fact.time) < float(_config.impact_seconds): active += 1
	var density := maxf(float(_config.overlap_alpha_floor), 1.0 / sqrt(maxf(1.0, float(active) / float(_config.overlap_soft_limit))))
	for flight: Dictionary in flights.values():
		var elapsed := now - float(flight.time)
		if pending.has(int(flight.cast_id)) and elapsed >= 0.0 and now < float(flight.scheduled_at): _draw_flight(flight, elapsed, view)
	for fact: Dictionary in snapshot.fire_bomb_facts:
		var age := now - float(fact.time)
		if age < 0.0: continue
		if str(fact.phase) == "impact":
			if age < float(_config.impact_seconds): _draw_blast(fact, age / float(_config.impact_seconds), density, false, view)
			if age < float(_config.tail_fade_seconds) and flights.has(int(fact.cast_id)):
				var flight: Dictionary = flights[int(fact.cast_id)]
				_draw_tail(flight, float(flight.flight_seconds), 1.0 - age / float(_config.tail_fade_seconds), view)
		elif str(fact.phase) == "aftershock" and age < float(_config.aftershock_seconds):
			_draw_blast(fact, age / float(_config.aftershock_seconds), density, true, view)
	_draw_status(snapshot, view)
	_draw_burns(snapshot, view)
	for effect: Dictionary in snapshot.get("effects", []):
		if str(effect.get("kind", "")) != "cast" or str(effect.get("spell_id", "")) != "F07" or float(effect.get("life", 0.0)) <= 0.0: continue
		var progress := 1.0 - float(effect.life) / maxf(0.000001, float(effect.max_life))
		var pos: Vector2 = snapshot.get("player", {}).get("pos", effect.pos)
		_surface(pos, float(_config.launch_height_m), float(_config.cast_radius_m), 0, progress, 0.64, _seed(int(effect.seq)), view)
		_note("F07_cast")
	for item: Dictionary in _cooling.values():
		var progress := (now - float(item.time)) / float(_config.cooling_seconds)
		if progress < 0.0 or progress >= 1.0: continue
		_surface(item.pos, 0.10, float(item.radius), 6, progress, 0.40, float(item.seed), view)
		_note("F07_cooling")
	_upload()
	_grounds.multimesh.visible_instance_count = _ground_count
	_bodies.multimesh.visible_instance_count = _body_count
	_bursts.multimesh.visible_instance_count = _burst_count
	visible = _ground_count > 0 or _body_count > 0 or _burst_count > 0 or not _indices.is_empty()


func _point_at(flight: Dictionary, elapsed: float) -> Vector3:
	var p := clampf(elapsed / maxf(float(flight.flight_seconds), 0.000001), 0.0, 1.0)
	var pos: Vector2 = Vector2(flight.from).lerp(flight.pos, p)
	var height := lerpf(float(_config.launch_height_m), float(_config.contact_height_m), p) + float(_config.arc_height_m) * 4.0 * p * (1.0 - p)
	return Vector3(pos.x, height, pos.y)


func _project(point: Vector3, view) -> Vector2:
	return view.screen_position(Vector2(point.x, point.z), point.y)


func _scale(flight: Dictionary) -> float:
	return float(_config.head_scale_by_level[clampi(int(flight.spell_level) - 1, 0, 2)])


func _draw_flight(flight: Dictionary, elapsed: float, view) -> void:
	if _heads.size() >= int(_config.head_capacity):
		_overflow += 1
		return
	var point := _point_at(flight, elapsed)
	var previous := _point_at(flight, maxf(0.0, elapsed - 0.002))
	var following := _point_at(flight, minf(float(flight.flight_seconds), elapsed + 0.002))
	var center := _project(point, view)
	var axis := (_project(following, view) - _project(previous, view)).normalized()
	if axis.is_zero_approx(): axis = Vector2.DOWN
	var size := _radius(Vector2(point.x, point.z), float(_config.head_radius_m) * _scale(flight), point.y, view) * float(_config.quad_radii)
	var alpha := 0.96 if bool(flight.natural) else 0.96 * float(_config.extra_alpha)
	_body(Transform2D(axis * size, Vector2(-axis.y, axis.x) * size, center), Color(_seed(int(flight.cast_id)), 0, 0, alpha))
	_heads.append({"cast_id": flight.cast_id, "world": point, "screen": center, "axis": axis, "to": flight.pos, "from": flight.from, "scheduled_at": flight.scheduled_at, "natural": flight.natural, "scale": _scale(flight)})
	_draw_tail(flight, elapsed, 1.0, view)
	if elapsed < float(_config.release_seconds):
		_surface(flight.from, float(_config.launch_height_m), float(_config.release_radius_m), 7, elapsed / float(_config.release_seconds), alpha * 0.62, _seed(int(flight.cast_id)), view)
		_note("F07_release")
	_note("F07_flight")


func _draw_tail(flight: Dictionary, elapsed: float, fade: float, view) -> void:
	if _paths.size() >= int(_config.head_capacity): return
	var points := PackedVector3Array()
	var distances := PackedFloat32Array([0.0])
	var length := 0.0
	for index in int(_config.tail_points):
		var age := maxf(0.0, elapsed - float(index) / float(int(_config.tail_points) - 1) * float(_config.tail_seconds))
		var point := _point_at(flight, age)
		if not points.is_empty():
			var distance := points[-1].distance_to(point)
			if length + distance > float(_config.tail_max_m):
				point = points[-1].lerp(point, (float(_config.tail_max_m) - length) / maxf(distance, 0.000001))
				points.append(point)
				distances.append(float(_config.tail_max_m))
				break
			length += distance
			distances.append(length)
		points.append(point)
	if points.size() < 2 or float(distances[-1]) < 0.000001: return
	_paths.append({"cast_id": flight.cast_id, "world": points, "fade": fade, "length": float(distances[-1])})
	var base := _vertices.size()
	for index in points.size():
		var u := float(distances[index]) / float(distances[-1])
		var center := _project(points[index], view)
		var tangent := _project(points[maxi(index - 1, 0)], view) - _project(points[mini(index + 1, points.size() - 1)], view)
		var normal := Vector2(-tangent.y, tangent.x).normalized()
		var width := _radius(Vector2(points[index].x, points[index].z), float(_config.tail_half_width_m) * _scale(flight), points[index].y, view)
		for side in [-1.0, 1.0]:
			var vertex: Vector2 = center + normal * width * pow(1.0 - u, 0.7) * float(side)
			_vertices.append(Vector3(vertex.x, vertex.y, 0))
			_uvs.append(Vector2(u, 0.0 if side < 0.0 else 1.0))
			_colors.append(Color(_seed(int(flight.cast_id)), 0, 0, fade * (1.0 if bool(flight.natural) else float(_config.extra_alpha))))
		if index > 0:
			var a := base + (index - 1) * 2
			_indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))


func _draw_blast(fact: Dictionary, progress: float, density: float, aftershock: bool, view) -> void:
	var pos: Vector2 = fact.pos
	var radius := float(fact.radius)
	var seed := _seed(int(fact.cast_id))
	var alpha := float(_config.aftershock_alpha if aftershock else _config.impact_alpha) * density
	if not bool(fact.natural): alpha *= float(_config.extra_alpha)
	_surface(pos, 0.035, radius, 3 if aftershock else 2, progress, alpha, seed, view, true)
	if not aftershock:
		_surface(pos, 0.045, float(fact.center_radius), 1, progress, alpha, seed, view, true)
		_footprints.append({"kind": "bomb_center", "pos": pos, "radius": fact.center_radius, "cast_id": fact.cast_id, "time": fact.time})
	var count := (2 if aftershock else 3) if _reduced else int(_config.aftershock_flames if aftershock else _config.impact_flames)
	var height := float(_config.aftershock_flame_height_m if aftershock else _config.impact_flame_height_m)
	var width := float(_config.aftershock_flame_width_m if aftershock else _config.impact_flame_width_m)
	for index in count:
		var offset := Vector2.from_angle(seed * TAU + float(index) * TAU / count) * radius * (0.10 + progress * (0.58 if aftershock else 0.30))
		_upright(pos + offset, 0.05, height * (1.0 - progress), width, alpha * pow(1.0 - progress, 1.4), _seed(int(fact.seq) + index * 47), view)
	_footprints.append({"kind": "aftershock" if aftershock else "bomb_impact", "pos": pos, "radius": radius, "cast_id": fact.cast_id, "spell_level": fact.spell_level, "natural": fact.natural, "time": fact.time})
	_note("F07_aftershock" if aftershock else "F07_impact")


func _draw_status(snapshot: Dictionary, view) -> void:
	for fact: Dictionary in snapshot.fire_bomb_status_facts:
		var reignite := str(fact.phase) == "reignite"
		var duration := float(_config.reignite_seconds if reignite else _config.detonation_seconds)
		var age := _clock - float(fact.time)
		if age < 0.0 or age >= duration: continue
		var progress := age / duration
		_surface(fact.pos, 0.40, float(fact.radius) * 1.35, 5 if reignite else 4, progress, 0.66 if reignite else 0.84, _seed(int(fact.actor_id) + int(fact.seq)), view)
		if not reignite: _upright(fact.pos, 0.08, float(_config.detonation_flame_height_m) * (1.0 - progress), float(_config.detonation_flame_width_m), 0.78 * (1.0 - progress), _seed(int(fact.seq)), view)
		_footprints.append({"kind": "fuel_reignite" if reignite else "fuel_detonation", "actor_id": fact.actor_id, "cast_id": fact.cast_id, "pos": fact.pos, "radius": fact.radius, "time": fact.time, "amount": fact.amount, "future_ticks": fact.future_ticks})
		_note("F07_reignite" if reignite else "F07_detonation")


func _draw_burns(snapshot: Dictionary, view) -> void:
	var actors: Dictionary = {}
	for actor: Dictionary in snapshot.get("actors", []): actors[int(actor.id)] = actor
	var all_live: Dictionary = {}
	var owned: Dictionary = {}
	for burn: Dictionary in snapshot.get("spell_burns", []):
		var id := int(burn.actor_id)
		all_live[id] = true
		if str(burn.get("source", "")) != "F07" or not actors.has(id) or float(actors[id].health) <= 0.0 or float(burn.remaining) <= 0.0: continue
		var actor: Dictionary = actors[id]
		var previous: Dictionary = _burns.get(id, {})
		var born := float(previous.born) if int(previous.get("token", -1)) == int(burn.token) else _ignition_time(snapshot, id)
		owned[id] = {"pos": actor.pos, "radius": float(actor.radius), "expires": _clock + float(burn.remaining), "seed": _seed(id), "born": born, "token": int(burn.token)}
		var fade := clampf(float(burn.remaining) / float(_config.source_fade_seconds), 0.0, 1.0)
		for index in (2 if _reduced else int(_config.burn_flames)):
			var seed := _seed(id + index * 71)
			var at: Vector2 = actor.pos + Vector2.from_angle(seed * TAU) * float(actor.radius) * 0.48
			_upright(at, 0.08, float(_config.burn_flame_height_m), float(_config.burn_flame_width_m), float(_config.burn_alpha) * fade, seed, view)
		# Successful delayed reapply already has a journal flare. Never add a second
		# ignition burst for the accompanying original fire_ignited event.
		var journal_reignite := false
		for fact: Dictionary in snapshot.fire_bomb_status_facts:
			if str(fact.phase) == "reignite" and int(fact.actor_id) == id and absf(float(fact.time) - born) < 0.00001: journal_reignite = true
		if not journal_reignite and _clock - born >= 0.0 and _clock - born < float(_config.ignite_seconds):
			_surface(actor.pos, 0.36, float(actor.radius) * 1.2, 5, (_clock - born) / float(_config.ignite_seconds), 0.48, _seed(id), view)
			_note("F07_ignited")
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
		if str(effect.get("kind", "")) != "fire_ignited" or str(effect.get("source", "")) != "F07" or int(effect.get("actor_id", -1)) != id: continue
		born = maxf(born, _clock - (float(effect.max_life) - float(effect.life)))
	return born


func _surface(pos: Vector2, height: float, radius: float, mode: int, progress: float, alpha: float, seed: float, view, ground: bool = false) -> void:
	if radius <= 0.0: return
	var center: Vector2 = view.screen_position(pos, height)
	var transform: Transform2D
	if ground:
		transform = Transform2D(view.screen_position(pos + Vector2(radius * 2.0, 0), height) - center, view.screen_position(pos + Vector2(0, radius * 2.0), height) - center, center)
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
	_heads.clear()
	_paths.clear()
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
	return {"available": _available, "clock": _clock, "revision": _revision, "heads": _heads.duplicate(true),
		"paths": _paths.duplicate(true), "coverage": _coverage.duplicate(true), "footprints": _footprints.duplicate(true),
		"burns": _burns.duplicate(true), "cooling": _cooling.duplicate(true), "vertices": _vertices.duplicate(),
		"uvs": _uvs.duplicate(), "indices": _indices.duplicate(), "body_instances": _body_count,
		"ground_instances": _ground_count, "burst_instances": _burst_count, "overflow": _overflow,
		"batch_nodes": get_child_count(), "material_count": 3}


func _valid_config(cfg: Dictionary) -> bool:
	if int(cfg.get("version", 0)) != 1: return false
	if not cfg.get("head_scale_by_level") is Array or cfg.head_scale_by_level.size() != 3: return false
	for value in cfg.head_scale_by_level:
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0.0: return false
	for key in ["head_capacity", "surface_capacity", "flame_capacity", "cooling_capacity", "launch_height_m", "contact_height_m", "arc_height_m", "head_radius_m", "quad_radii", "flow_speed", "tail_alpha", "tail_seconds", "tail_points", "tail_max_m", "tail_half_width_m", "tail_fade_seconds", "impact_seconds", "impact_alpha", "impact_flames", "impact_flame_height_m", "impact_flame_width_m", "aftershock_seconds", "aftershock_alpha", "aftershock_flames", "aftershock_flame_height_m", "aftershock_flame_width_m", "detonation_seconds", "detonation_flame_height_m", "detonation_flame_width_m", "reignite_seconds", "release_seconds", "release_radius_m", "cast_radius_m", "ignite_seconds", "burn_flames", "burn_flame_height_m", "burn_flame_width_m", "burn_alpha", "source_fade_seconds", "cooling_seconds", "overlap_soft_limit", "overlap_alpha_floor", "extra_alpha"]:
		var value: Variant = cfg.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0.0: return false
	if int(cfg.tail_points) < 2: return false
	for key in ["edge_color", "shell_color", "energy_color", "core_color", "ember_color"]:
		if not cfg.get(key) is Array or cfg[key].size() != 4: return false
		for value in cfg[key]:
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0: return false
	return true
