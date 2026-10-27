extends Node2D
## F03 reads released falls, completed impacts, source-owned burns and live zones.
## All geometry is rebuilt from the core clock. No simulation or per-fall nodes.
const CONFIG_PATH := "res://data/fire_rain_vfx.json"
const BODY_SHADER = preload("res://scripts/presentation/fire_bolt_body.gdshader")
const TRAIL_SHADER = preload("res://scripts/presentation/fire_bolt_trail.gdshader")
const SURFACE_SHADER = preload("res://scripts/presentation/fire_rain_surface.gdshader")

var _config: Dictionary = {}
var _available := false
var _clock := 0.0
var _revision := -1
var _reduced := false
var _coverage: Dictionary = {}
var _footprints: Array = []
var _heads: Array = []
var _paths: Array = []
var _grounds_seen: Dictionary = {}
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
	name = "FireRainFullChain"
	set_process(false)
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not loaded is Dictionary or not _valid_config(loaded):
		push_error("Invalid F03 visual configuration; keeping legacy rain drawing.")
		return
	_config = loaded
	_body_material = _material(BODY_SHADER)
	_trail_material = _material(TRAIL_SHADER)
	_surface_material = _material(SURFACE_SHADER)
	_body_material.set_shader_parameter("body_axes", Vector2(_config.body_axes[0], _config.body_axes[1]))
	_body_material.set_shader_parameter("core_axes", Vector2(_config.core_axes[0], _config.core_axes[1]))
	_body_material.set_shader_parameter("quad_radii", float(_config.head_quad_radii))
	_grounds = _batch("RainCoverageAndLiveCoals", _surface_material, int(_config.ground_capacity))
	_mesh = ArrayMesh.new()
	_ribbons = MeshInstance2D.new()
	_ribbons.name = "ContinuousFallingFireTrails"
	_ribbons.mesh = _mesh
	_ribbons.material = _trail_material
	add_child(_ribbons)
	_bodies = _batch("FallingHeadsAndLowTongues", _body_material, int(_config.flame_capacity))
	_bursts = _batch("ActualLandingsAndCoolingEmbers", _surface_material, int(_config.surface_capacity))
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
	if str(snapshot.get("phase", "")) != "combat" or not snapshot.has("fire_rain_impacts"):
		_clear()
		return
	_reduced = bool(options.get("reduced_motion", false))
	for mat in [_body_material, _trail_material, _surface_material]:
		mat.set_shader_parameter("core_time", now)
		mat.set_shader_parameter("reduced_motion", _reduced)
	_reset_geometry()
	for key in _cooling.keys():
		if now - float(_cooling[key].time) >= float(_config.cooling_seconds): _cooling.erase(key)
	_draw_areas(snapshot, view)
	for item: Dictionary in snapshot.get("spell_pending", []):
		if str(item.get("kind", "")) != "rain_drop" or str(item.get("context", {}).get("spell_id", "")) != "F03": continue
		var delay := float(item.get("stats", {}).get("impact_delay", 0.0))
		var wait := float(item.at) - now
		if delay <= 0.0 or wait < 0.0 or wait > delay + 0.000001: continue
		_draw_fall(item, delay - wait, delay, view)
	var impacts: Array = snapshot.fire_rain_impacts
	var active_impacts := 0
	for impact: Dictionary in impacts:
		var age := now - float(impact.time)
		if age >= 0.0 and age < float(_config.impact_seconds): active_impacts += 1
	var alpha := _density_alpha(active_impacts)
	for impact: Dictionary in impacts:
		var age := now - float(impact.time)
		if age < 0.0: continue
		if age < float(_config.tail_fade_seconds):
			_draw_tail(impact, float(impact.fall_seconds), float(impact.fall_seconds), 1.0 - age / float(_config.tail_fade_seconds), view)
		if age < float(_config.impact_seconds): _draw_impact(impact, age / float(_config.impact_seconds), alpha, view)
	_draw_burns(snapshot, view)
	for effect: Dictionary in snapshot.get("effects", []):
		if str(effect.get("kind", "")) != "cast" or str(effect.get("spell_id", "")) != "F03": continue
		if float(effect.get("life", 0.0)) <= 0.0: continue
		var progress := 1.0 - float(effect.life) / maxf(0.000001, float(effect.max_life))
		var pos: Vector2 = snapshot.get("player", {}).get("pos", effect.pos)
		_surface(pos, 0.72, float(_config.cast_radius_m), 4, progress, 0.52, _seed(int(effect.seq)), view)
		_note("F03_cast")
	for item: Dictionary in _cooling.values():
		var progress := (now - float(item.time)) / float(_config.cooling_seconds)
		if progress < 0.0 or progress >= 1.0: continue
		_surface(item.pos, 0.08, float(item.radius), 3, progress, 0.46, float(item.seed), view)
		_footprints.append({"kind": "cooling", "pos": item.pos, "radius": item.radius, "time": item.time})
		_note("F03_cooling")
	_upload()
	_grounds.multimesh.visible_instance_count = _ground_count
	_bodies.multimesh.visible_instance_count = _body_count
	_bursts.multimesh.visible_instance_count = _burst_count
	visible = _ground_count > 0 or _body_count > 0 or _burst_count > 0 or not _indices.is_empty()


func _draw_areas(snapshot: Dictionary, view) -> void:
	var live: Dictionary = {}
	var count := 0
	for zone: Dictionary in snapshot.get("spell_zones", []):
		if str(zone.get("spell_id", "")) == "F03" and float(zone.get("remaining", 0.0)) > 0.0: count += 1
	var density := _density_alpha(count)
	for zone: Dictionary in snapshot.get("spell_zones", []):
		if str(zone.get("spell_id", "")) != "F03" or float(zone.get("remaining", 0.0)) <= 0.0: continue
		var kind := str(zone.get("kind", ""))
		var pos: Vector2 = zone.pos
		var radius := float(zone.radius)
		var seed := _seed(int(zone.id))
		if kind == "rain":
			_surface(pos, 0.025, radius, 0, 0.0, float(_config.marker_alpha) * density, seed, view, true)
			var age := _clock - float(zone.born_at)
			if age >= 0.0 and age < float(_config.release_seconds) and zone.has("release_pos"):
				_surface(zone.release_pos, 0.72, float(_config.release_radius_m), 6, age / float(_config.release_seconds), 0.58, seed, view)
				_note("F03_release")
			_note("F03_marker")
		elif kind == "rain_ground":
			var cooling := 1.0 - clampf(float(zone.remaining) / float(_config.ground_cooling_seconds), 0.0, 1.0)
			_surface(pos, 0.025, radius, 2, cooling, float(_config.ground_alpha) * density, seed, view, true)
			var flames := 3 if _reduced else int(_config.ground_flames)
			for index in flames:
				var part := _seed(int(zone.id) + index * 53)
				var at := pos + Vector2.from_angle(part * TAU) * radius * (0.18 + 0.52 * _seed(index + 19))
				_upright(at, 0.04, float(_config.ground_flame_height_m) * (1.0 - cooling * 0.65), float(_config.ground_flame_width_m), float(_config.ground_alpha) * density * (1.0 - cooling * 0.6), part, view)
			if _grounds_seen.has(int(zone.id)) or _grounds_seen.size() < int(_config.ground_capacity):
				_grounds_seen[int(zone.id)] = {"pos": pos, "radius": radius, "expires": _clock + float(zone.remaining), "seed": seed}
			live[int(zone.id)] = true
			_note("F03_ground")
		else: continue
		_footprints.append({"kind": kind, "pos": pos, "radius": radius, "remaining": zone.remaining, "zone_id": zone.id})
	for id in _grounds_seen.keys():
		if live.has(id): continue
		var old: Dictionary = _grounds_seen[id]
		# Early removal/clear is cancellation, never natural cooling or an impact.
		if _clock + 0.000001 >= float(old.expires): _cool("zone:%d" % id, old)
		_grounds_seen.erase(id)


func _draw_fall(item: Dictionary, elapsed: float, delay: float, view) -> void:
	if _heads.size() >= int(_config.head_capacity):
		_overflow += 1
		return
	var pos: Vector2 = item.pos
	var progress := clampf(elapsed / delay, 0.0, 1.0)
	var height := _height(progress)
	var scale := _drop_scale(item)
	var seed := _drop_seed(item)
	var center: Vector2 = view.screen_position(pos, height)
	var axis: Vector2 = view.screen_position(pos, height - 1.0) - center
	axis = axis.normalized() if axis.length_squared() > 0.000001 else Vector2.DOWN
	var dimension := _radius(pos, float(_config.drop_radius_m) * scale, height, view) * float(_config.head_quad_radii)
	_body(Transform2D(axis * dimension, Vector2(-axis.y, axis.x) * dimension, center), Color(seed, 0.25 + progress * 0.75, 0, 0.94))
	_heads.append({"cast_id": int(item.context.cast_id), "drop_index": int(item.get("drop_index", -1)), "pos": pos,
		"height": height, "progress": progress, "scale": scale, "screen": center, "axis": axis, "scheduled_at": item.at})
	_draw_tail(item, elapsed, delay, 1.0, view)
	if not _reduced:
		_surface(pos, height + 0.25, float(_config.drop_radius_m) * scale * 1.5, 7, progress, 0.44, seed, view)
	_note("F03_rainfall")


func _draw_tail(item: Dictionary, elapsed: float, delay: float, fade: float, view) -> void:
	if _paths.size() >= int(_config.head_capacity): return
	var pos: Vector2 = item.pos
	var points := PackedVector3Array()
	var length := 0.0
	for index in int(_config.tail_points):
		var age := maxf(0.0, elapsed - float(index) / float(int(_config.tail_points) - 1) * float(_config.tail_seconds))
		var point := Vector3(pos.x, _height(clampf(age / maxf(delay, 0.000001), 0.0, 1.0)), pos.y)
		if not points.is_empty():
			var distance := points[-1].distance_to(point)
			if length + distance > float(_config.tail_max_m):
				point = points[-1].lerp(point, (float(_config.tail_max_m) - length) / maxf(distance, 0.000001))
				points.append(point)
				break
			length += distance
		points.append(point)
	if points.size() < 2 or points[0].distance_to(points[-1]) < 0.000001: return
	_paths.append({"cast_id": int(item.get("cast_id", item.get("context", {}).get("cast_id", -1))), "drop_index": int(item.get("drop_index", -1)), "world": points, "fade": fade})
	var total := points[0].distance_to(points[-1])
	var width := _radius(pos, float(_config.tail_half_width_m) * _drop_scale(item), points[0].y, view)
	var base := _vertices.size()
	var top: Vector2 = view.screen_position(pos, points[0].y)
	var bottom: Vector2 = view.screen_position(pos, points[-1].y)
	var tangent := top - bottom
	var normal := Vector2(-tangent.y, tangent.x).normalized()
	for index in points.size():
		var u := points[0].distance_to(points[index]) / total
		var center: Vector2 = view.screen_position(pos, points[index].y)
		for side in [-1.0, 1.0]:
			var vertex: Vector2 = center + normal * width * pow(1.0 - u, 0.7) * float(side)
			_vertices.append(Vector3(vertex.x, vertex.y, 0))
			_uvs.append(Vector2(u, 0.0 if side < 0.0 else 1.0))
			_colors.append(Color(_drop_seed(item), 0, 0, fade))
		if index > 0:
			var a := base + (index - 1) * 2
			_indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))


func _draw_impact(item: Dictionary, progress: float, density: float, view) -> void:
	var pos: Vector2 = item.pos
	var radius := float(item.radius)
	var scale := _drop_scale(item)
	var seed := _drop_seed(item)
	var alpha := float(_config.impact_alpha) * density
	_surface(pos, 0.04, radius, 1, progress, minf(alpha * scale, 1.0), seed, view, true)
	var count := 2 if _reduced else int(_config.impact_flames)
	for index in count:
		var at := pos + Vector2.from_angle(seed * TAU + float(index) * TAU / count) * radius * (0.12 + progress * 0.28)
		_upright(at, 0.04, float(_config.impact_flame_height_m) * scale * (1.0 - progress), float(_config.impact_flame_width_m) * scale, alpha * pow(1.0 - progress, 1.5), _seed(int(item.seq) + index), view)
	_footprints.append({"kind": "rain_impact", "pos": pos, "radius": radius, "cast_id": item.cast_id,
		"drop_index": item.drop_index, "spell_level": item.spell_level, "first": int(item.drop_index) == 0, "scale": scale, "time": item.time})
	_note("F03_impact")
	if int(item.drop_index) == 0: _note("F03_first_impact")


func _draw_burns(snapshot: Dictionary, view) -> void:
	var actors: Dictionary = {}
	for actor: Dictionary in snapshot.get("actors", []): actors[int(actor.id)] = actor
	var all_live: Dictionary = {}
	var owned: Dictionary = {}
	for burn: Dictionary in snapshot.get("spell_burns", []):
		var id := int(burn.actor_id)
		all_live[id] = true
		if str(burn.get("source", "")) != "F03" or not actors.has(id) or float(actors[id].health) <= 0.0 or float(burn.remaining) <= 0.0: continue
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
			_surface(actor.pos, 0.36, float(actor.radius) * 1.2, 5, (_clock - born) / float(_config.ignite_seconds), 0.48, _seed(id), view)
			_note("F03_ignited")
		_footprints.append({"kind": "burning", "actor_id": id, "pos": actor.pos, "remaining": burn.remaining})
		_note("burning")
	for id in _burns:
		if all_live.has(id) or not actors.has(id) or float(actors[id].health) <= 0.0: continue
		var old: Dictionary = _burns[id]
		if _clock + 0.000001 < float(old.expires): continue
		var consumed := false
		for effect: Dictionary in snapshot.get("effects", []):
			if str(effect.get("kind", "")) == "fire_detonation" and int(effect.get("actor_id", -1)) == int(id): consumed = true
		if not consumed:
			old = old.duplicate(true)
			old.pos = actors[id].pos
			_cool("burn:%d:%d" % [id, int(old.token)], old)
	_burns = owned


func _ignition_time(snapshot: Dictionary, id: int) -> float:
	var born := -INF
	for effect: Dictionary in snapshot.get("effects", []):
		if str(effect.get("kind", "")) == "fire_ignited" and str(effect.get("source", "")) == "F03" and int(effect.get("actor_id", -1)) == id:
			born = maxf(born, _clock - maxf(0.0, float(effect.max_life) - float(effect.life)))
	return born


func _cool(key: String, source: Dictionary) -> void:
	if _cooling.size() >= int(_config.ground_capacity): return
	_cooling[key] = {"pos": source.pos, "radius": source.radius, "time": source.expires, "seed": source.seed}


func _height(progress: float) -> float:
	return float(_config.contact_height_m) + float(_config.fall_height_m) * (1.0 - lerpf(progress, progress * progress, float(_config.fall_acceleration_mix)))


func _drop_scale(item: Dictionary) -> float:
	if int(item.get("drop_index", -1)) != 0: return 1.0
	var level := clampi(int(item.get("spell_level", item.get("context", {}).get("spell_level", 1))), 1, 3)
	return float(_config.first_scale_by_level[level - 1])


func _drop_seed(item: Dictionary) -> float:
	return _seed(int(item.get("cast_id", item.get("context", {}).get("cast_id", 0))) * 17 + int(item.get("drop_index", 0)) * 71)


func _density_alpha(count: int) -> float:
	return maxf(float(_config.overlap_alpha_floor), 1.0 / sqrt(maxf(1.0, float(count) / float(_config.overlap_soft_limit))))


func _surface(pos: Vector2, height: float, radius: float, mode: int, progress: float, alpha: float, seed: float, view, ground: bool = false) -> void:
	var center: Vector2 = view.screen_position(pos, height)
	var transform: Transform2D
	if ground:
		transform = Transform2D(view.screen_position(pos + Vector2(radius * 2.0, 0), height) - center, view.screen_position(pos + Vector2(0, radius * 2.0), height) - center, center)
	else:
		var size := _radius(pos, radius, height, view) * 2.0
		transform = Transform2D(Vector2.RIGHT * size, Vector2.DOWN * size, center)
	var index := _ground_count if ground else _burst_count
	var limit := int(_config.ground_capacity if ground else _config.surface_capacity)
	if index >= limit:
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
	var x := up * float(_config.head_quad_radii) / 3.5
	var y := Vector2(-up.y, up.x).normalized() * across.length() * float(_config.head_quad_radii) / 1.65
	_body(Transform2D(x, y, center), Color(seed, 0, 1, alpha))


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
	_grounds_seen.clear()
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
		"burns": _burns.duplicate(true), "live_grounds": _grounds_seen.duplicate(true), "cooling": _cooling.duplicate(true),
		"vertices": _vertices.duplicate(), "uvs": _uvs.duplicate(), "indices": _indices.duplicate(),
		"body_instances": _body_count, "ground_instances": _ground_count, "burst_instances": _burst_count,
		"overflow": _overflow, "batch_nodes": get_child_count(), "material_count": 3}


func _valid_config(cfg: Dictionary) -> bool:
	if int(cfg.get("version", 0)) != 1: return false
	for key in ["body_axes", "core_axes", "first_scale_by_level"]:
		if not cfg.get(key) is Array or cfg[key].size() != (3 if key == "first_scale_by_level" else 2): return false
		for value in cfg[key]:
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0.0: return false
	for key in ["head_capacity", "ground_capacity", "surface_capacity", "flame_capacity", "fall_height_m", "contact_height_m", "drop_radius_m", "head_quad_radii", "rear_stretch", "flow_speed", "tail_alpha", "tail_seconds", "tail_max_m", "tail_half_width_m", "tail_fade_seconds", "tail_points", "impact_seconds", "impact_flame_height_m", "impact_flame_width_m", "impact_flames", "impact_alpha", "marker_alpha", "ground_alpha", "ground_flames", "ground_flame_height_m", "ground_flame_width_m", "ground_cooling_seconds", "cooling_seconds", "cast_radius_m", "release_radius_m", "release_seconds", "ignite_seconds", "burn_flames", "burn_flame_height_m", "burn_flame_width_m", "burn_alpha", "source_fade_seconds", "overlap_soft_limit", "overlap_alpha_floor"]:
		var value: Variant = cfg.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0.0: return false
	if int(cfg.tail_points) < 2: return false
	if not cfg.get("fall_acceleration_mix") is float or not is_finite(float(cfg.fall_acceleration_mix)) or float(cfg.fall_acceleration_mix) < 0.0 or float(cfg.fall_acceleration_mix) > 1.0: return false
	for key in ["edge_color", "shell_color", "energy_color", "core_color", "ember_color"]:
		if not cfg.get(key) is Array or cfg[key].size() != 4: return false
		for value in cfg[key]:
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0: return false
	return true
