extends Node2D
## World-space path history, projected only when drawing. No gameplay mutation,
## wall clock, gameplay RNG, per-projectile nodes, or inferred collision events.

const CONFIG_PATH := "res://data/magic_missile_vfx.json"
const HEAD_SHADER = preload("res://scripts/presentation/magic_missile_head.gdshader")
const TRAIL_SHADER = preload("res://scripts/presentation/magic_missile_trail.gdshader")
const ENERGY_SHADER = preload("res://scripts/presentation/magic_missile_energy.gdshader")

class Trace extends RefCounted:
	var id: int
	var pos := Vector2.ZERO
	var direction := Vector2.UP
	var radius := 0.0
	var first_time := 0.0
	var last_time := 0.0
	var ended_at := -1.0
	var active := false
	var samples := PackedVector2Array()
	var stamps := PackedFloat64Array()
	var path := PackedVector2Array()

var _config: Dictionary = {}
var _available := false
var _traces: Dictionary = {}
var _impacts: Array = []
var _clock := 0.0
var _revision := -1
var _last_end_seq := -1
var _head_count := 0
var _impact_count := 0
var _overflow := 0
var _head_ids := PackedInt64Array()
var _vertices := PackedVector3Array()
var _uvs := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _heads: MultiMeshInstance2D
var _halos: MultiMeshInstance2D
var _bursts: MultiMeshInstance2D
var _ribbons: MeshInstance2D
var _ribbon_mesh: ArrayMesh
var _head_material: ShaderMaterial
var _trail_material: ShaderMaterial
var _energy_material: ShaderMaterial


func _ready() -> void:
	name = "EnemyMagicMissiles"
	set_process(false)
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not loaded is Dictionary or not _valid_config(loaded):
		push_error("Invalid magic missile visual configuration; keeping legacy drawing.")
		return
	_config = loaded
	_head_material = _material(HEAD_SHADER)
	_trail_material = _material(TRAIL_SHADER)
	_energy_material = _material(ENERGY_SHADER)
	for mat in [_head_material, _trail_material, _energy_material]:
		for uniform: Dictionary in mat.shader.get_shader_uniform_list():
			var key := str(uniform.name)
			if key.ends_with("_color") and _config.has(key):
				var c: Array = _config[key]
				mat.set_shader_parameter(key, Color(c[0], c[1], c[2], c[3]))
	_head_material.set_shader_parameter("body_axes", Vector2(_config.head_body_axes[0], _config.head_body_axes[1]))
	_head_material.set_shader_parameter("core_axes", Vector2(_config.head_core_axes[0], _config.head_core_axes[1]))
	_head_material.set_shader_parameter("rear_stretch", float(_config.head_rear_stretch))
	_head_material.set_shader_parameter("quad_radii", float(_config.head_quad_radii))
	_head_material.set_shader_parameter("flow_speed", float(_config.head_flow_speed))
	_head_material.set_shader_parameter("warp_amount", float(_config.head_warp))
	_trail_material.set_shader_parameter("tail_alpha", float(_config.tail_alpha))
	_trail_material.set_shader_parameter("flow_alpha", float(_config.flow_alpha))
	_energy_material.set_shader_parameter("halo_alpha", float(_config.halo_alpha))
	_energy_material.set_shader_parameter("aura_quad_radii", float(_config.aura_quad_radii))
	_energy_material.set_shader_parameter("aura_filament_alpha", float(_config.aura_filament_alpha))
	_ribbon_mesh = ArrayMesh.new()
	_ribbons = MeshInstance2D.new()
	_ribbons.name = "ContinuousWorldPathRibbons"
	_ribbons.mesh = _ribbon_mesh
	_ribbons.material = _trail_material
	add_child(_ribbons)
	_heads = _batch("ConcentratedMagicHeads", _head_material, int(_config.head_capacity))
	# Flowing light is foreground scatter, not a faint image hidden by the body.
	_halos = _batch("ForegroundEnergyFlow", _energy_material, int(_config.head_capacity))
	_bursts = _batch("ConfirmedContactBursts", _energy_material, int(_config.impact_capacity))
	_available = true
	visible = false


func is_available() -> bool:
	return _available


func sync_snapshot(snapshot: Dictionary, view, options: Dictionary = {}) -> void:
	if not _available:
		return
	var now := float(snapshot.get("time", 0.0))
	var revision := int(snapshot.get("room_revision", 0))
	if revision != _revision or now < _clock - 0.000001:
		_clear()
	_revision = revision
	_clock = now
	if str(snapshot.get("phase", "")) != "combat":
		_clear()
		return
	var reduced := bool(options.get("reduced_motion", false))
	for mat in [_head_material, _trail_material, _energy_material]:
		mat.set_shader_parameter("core_time", now)
		mat.set_shader_parameter("reduced_motion", reduced)
	_head_count = 0
	_impact_count = 0
	_overflow = 0
	_head_ids.clear()
	_vertices.clear()
	_uvs.clear()
	_colors.clear()
	_indices.clear()
	for trace: Trace in _traces.values():
		trace.active = false
	for shot: Dictionary in snapshot.get("enemy_projectiles", []):
		var id := int(shot.get("id", -1))
		var radius := float(shot.get("radius", 0.0))
		if id < 0 or radius <= 0.0:
			continue
		var trace: Trace = _traces.get(id)
		if trace == null:
			trace = _new_trace(id, shot.pos, shot.get("direction", Vector2.UP), radius, now)
			var previous: Vector2 = shot.get("previous", trace.pos)
			if previous.distance_squared_to(trace.pos) > 0.00000001:
				trace.samples[0] = previous
				trace.stamps[0] = now - minf(float(_config.history_interval), previous.distance_to(trace.pos) / maxf(0.001, float(shot.get("speed", 1.0))))
		trace.active = true
		trace.ended_at = -1.0
		trace.radius = radius
		trace.direction = Vector2(shot.get("direction", trace.direction)).normalized()
		_sample(trace, shot.pos, now)
		_draw_head(trace, view)
	_consume_ends(snapshot.get("enemy_projectile_ends", []), now)
	var remove: Array = []
	for id in _traces:
		var trace: Trace = _traces[id]
		if not trace.active and trace.ended_at < 0.0:
			# Missing IDs without a confirmed contact only lose their tail.
			trace.ended_at = now
		if trace.ended_at >= 0.0 and now - trace.ended_at >= float(_config.tail_fade_seconds):
			remove.append(id)
			continue
		trace.path = _path(trace, now)
		if trace.path.size() >= 2:
			_ribbon(trace, view, reduced)
	for id in remove:
		_traces.erase(id)
	# Only old, decorative terminal histories can be evicted, never live heads.
	if _traces.size() > int(_config.trace_capacity):
		for id in _traces.keys():
			if _traces.size() <= int(_config.trace_capacity):
				break
			if not _traces[id].active:
				_traces.erase(id)
	for index in range(_impacts.size() - 1, -1, -1):
		var event: Dictionary = _impacts[index]
		var age := now - float(event.time)
		if age >= float(_config.impact_seconds) or age < -0.000001:
			_impacts.remove_at(index)
		else:
			_draw_impact(event, view, age, reduced)
	_upload_ribbons()
	_heads.multimesh.visible_instance_count = _head_count
	_halos.multimesh.visible_instance_count = _head_count
	_bursts.multimesh.visible_instance_count = _impact_count
	visible = _head_count > 0 or _impact_count > 0 or not _indices.is_empty()


func _new_trace(id: int, pos: Vector2, direction: Vector2, radius: float, now: float) -> Trace:
	var trace := Trace.new()
	trace.id = id
	trace.pos = pos
	trace.direction = direction.normalized()
	trace.radius = radius
	trace.first_time = now
	trace.last_time = now
	trace.samples.append(pos)
	trace.stamps.append(now)
	_traces[id] = trace
	return trace


func _sample(trace: Trace, pos: Vector2, now: float) -> void:
	trace.pos = pos
	trace.last_time = now
	if now - float(trace.stamps[-1]) >= float(_config.history_interval) - 0.000001:
		trace.samples.append(pos)
		trace.stamps.append(now)
	while trace.samples.size() > int(_config.history_points) or (trace.samples.size() > 2 and now - float(trace.stamps[1]) > float(_config.history_seconds)):
		trace.samples.remove_at(0)
		trace.stamps.remove_at(0)


func _consume_ends(events: Array, now: float) -> void:
	for event: Dictionary in events:
		var seq := int(event.get("seq", -1))
		if seq <= _last_end_seq:
			continue
		_last_end_seq = seq
		var age := now - float(event.get("time", now))
		if age < -0.000001 or age >= maxf(float(_config.impact_seconds), float(_config.tail_fade_seconds)):
			continue
		var id := int(event.get("projectile_id", -1))
		var trace: Trace = _traces.get(id)
		if trace == null:
			trace = _new_trace(id, event.get("from", event.pos), event.direction, float(event.radius), float(event.from_time))
		_sample(trace, event.pos, float(event.time))
		trace.active = false
		trace.ended_at = float(event.time)
		if str(event.reason) in ["player", "wall"] and _impacts.size() < int(_config.impact_capacity):
			_impacts.append(event.duplicate(true))


func _path(trace: Trace, now: float) -> PackedVector2Array:
	var points := PackedVector2Array([trace.pos])
	var maximum := minf(trace.radius * float(_config.tail_max_radii), float(_config.tail_max_m))
	var cutoff := now - float(_config.history_seconds)
	var recent := trace.pos
	var recent_time := trace.last_time
	var length := 0.0
	for index in range(trace.samples.size() - 1, -1, -1):
		var point: Vector2 = trace.samples[index]
		var stamp := float(trace.stamps[index])
		var last := stamp < cutoff
		if last:
			if recent_time <= cutoff or recent_time <= stamp:
				break
			point = point.lerp(recent, clampf((cutoff - stamp) / (recent_time - stamp), 0.0, 1.0))
		var segment := recent.distance_to(point)
		if segment > 0.00001:
			if length + segment >= maximum:
				points.append(recent.lerp(point, (maximum - length) / segment))
				break
			points.append(point)
			length += segment
		recent = point
		recent_time = stamp
		if last:
			break
	return points


func _draw_head(trace: Trace, view) -> void:
	if _head_count >= int(_config.head_capacity):
		_overflow += 1
		return
	var p: Vector2 = view.screen_position(trace.pos, float(_config.height_m))
	var axis := _axis(trace.pos, trace.direction, view)
	var radius := _radius(trace.pos, trace.radius, view)
	var side := Vector2(-axis.y, axis.x)
	var dimension := radius * float(_config.head_quad_radii)
	var transform := Transform2D(axis * dimension, side * dimension, p)
	var envelope := 0.9 + 0.1 * clampf((_clock - trace.first_time) / float(_config.head_appear_seconds), 0.0, 1.0)
	var seed := _seed(trace.id)
	_heads.multimesh.set_instance_transform_2d(_head_count, transform)
	_heads.multimesh.set_instance_custom_data(_head_count, Color(seed, 0.0, 0.0, envelope))
	var aura_dimension := radius * float(_config.aura_quad_radii)
	var aura_transform := Transform2D(axis * aura_dimension, side * aura_dimension, p)
	_halos.multimesh.set_instance_transform_2d(_head_count, aura_transform)
	_halos.multimesh.set_instance_custom_data(_head_count, Color(seed, 0.0, 0.0, 1.0))
	_head_ids.append(trace.id)
	_head_count += 1


func _ribbon(trace: Trace, view, _reduced: bool) -> void:
	var points := PackedVector2Array()
	var distances := PackedFloat32Array([0.0])
	var total := 0.0
	for index in trace.path.size():
		points.append(view.screen_position(trace.path[index], float(_config.height_m)))
		if index > 0:
			total += trace.path[index].distance_to(trace.path[index - 1])
			distances.append(total)
	if total <= 0.00001:
		return
	var alpha := 1.0 if trace.ended_at < 0.0 else clampf(1.0 - (_clock - trace.ended_at) / float(_config.tail_fade_seconds), 0.0, 1.0)
	var width := _radius(trace.pos, trace.radius, view) * float(_config.tail_half_width_radii)
	var base := _vertices.size()
	for index in points.size():
		var tangent: Vector2 = points[maxi(0, index - 1)] - points[mini(points.size() - 1, index + 1)]
		if tangent.length_squared() < 0.000001:
			tangent = Vector2.RIGHT
		var normal := Vector2(-tangent.y, tangent.x).normalized()
		var u := float(distances[index]) / total
		var half_width := width * pow(maxf(0.0, 1.0 - u), float(_config.tail_taper_power))
		for sign_value in [-1.0, 1.0]:
			var at: Vector2 = points[index] + normal * half_width * sign_value
			_vertices.append(Vector3(at.x, at.y, 0.0))
			_uvs.append(Vector2(u, 0.0 if sign_value < 0.0 else 1.0))
			_colors.append(Color(_seed(trace.id), 0.0, 0.0, alpha))
		if index > 0:
			var a := base + (index - 1) * 2
			_indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))


func _draw_impact(event: Dictionary, view, age: float, reduced: bool) -> void:
	if _impact_count >= int(_config.impact_capacity):
		return
	var contact: Vector2 = event.get("contact_pos", event.pos)
	var p: Vector2 = view.screen_position(contact, float(_config.height_m))
	var axis := _axis(contact, -Vector2(event.get("normal", -Vector2(event.direction))), view)
	var radius := _radius(event.pos, float(event.radius), view)
	var dimension := radius * float(_config.impact_extent_radii) * 2.0
	var transform := Transform2D(axis * dimension, Vector2(-axis.y, axis.x) * dimension, p)
	_bursts.multimesh.set_instance_transform_2d(_impact_count, transform)
	_bursts.multimesh.set_instance_custom_data(_impact_count, Color(_seed(int(event.projectile_id)), age / float(_config.impact_seconds), 1.0, 0.6 if reduced else 1.0))
	_impact_count += 1


func _upload_ribbons() -> void:
	if _ribbon_mesh.get_surface_count() > 0:
		_ribbon_mesh.clear_surfaces()
	if not _indices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vertices
		arrays[Mesh.ARRAY_TEX_UV] = _uvs
		arrays[Mesh.ARRAY_COLOR] = _colors
		arrays[Mesh.ARRAY_INDEX] = _indices
		_ribbon_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _axis(pos: Vector2, direction: Vector2, view) -> Vector2:
	var axis: Vector2 = view.screen_position(pos + direction, float(_config.height_m)) - view.screen_position(pos, float(_config.height_m))
	return axis.normalized() if axis.length_squared() > 0.000001 else Vector2.RIGHT


func _radius(pos: Vector2, radius: float, view) -> float:
	var p: Vector2 = view.screen_position(pos, float(_config.height_m))
	var x: Vector2 = view.screen_position(pos + Vector2(radius, 0.0), float(_config.height_m)) - p
	var y: Vector2 = view.screen_position(pos + Vector2(0.0, radius), float(_config.height_m)) - p
	# Area-equivalent projected radius retains the real world size without a
	# fixed pixel minimum or a large decorative collision ring.
	return maxf(0.25, sqrt(absf(x.cross(y))))


static func _seed(id: int) -> float:
	return fposmod(float(id) * 0.61803398875, 1.0)


func _material(shader: Shader) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


func _batch(title: String, mat: ShaderMaterial, capacity: int) -> MultiMeshInstance2D:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_2D
	batch.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	batch.mesh = quad
	batch.instance_count = capacity
	batch.visible_instance_count = 0
	batch.custom_aabb = AABB(Vector3(-16384, -16384, -1), Vector3(32768, 32768, 2))
	var node := MultiMeshInstance2D.new()
	node.name = title
	node.multimesh = batch
	node.material = mat
	add_child(node)
	return node


func _clear() -> void:
	_traces.clear()
	_impacts.clear()
	_last_end_seq = -1
	_head_count = 0
	_impact_count = 0
	_head_ids.clear()
	_vertices.clear()
	_uvs.clear()
	_colors.clear()
	_indices.clear()
	if _available:
		_heads.multimesh.visible_instance_count = 0
		_halos.multimesh.visible_instance_count = 0
		_bursts.multimesh.visible_instance_count = 0
		if _ribbon_mesh.get_surface_count() > 0:
			_ribbon_mesh.clear_surfaces()
	visible = false


func get_debug_state() -> Dictionary:
	var paths: Array = []
	for trace: Trace in _traces.values():
		paths.append({"id": trace.id, "pos": trace.pos, "world_path": trace.path.duplicate(),
			"samples": trace.samples.size(), "active": trace.active, "ended_at": trace.ended_at})
	return {"available": _available, "clock": _clock, "revision": _revision, "visual_revision": int(_config.get("visual_revision", 1)),
		"heads": _head_count, "head_ids": _head_ids.duplicate(), "head_capacity": int(_config.get("head_capacity", 0)),
		"impacts": _impacts.duplicate(true), "impact_instances": _impact_count, "paths": paths,
		"vertices": _vertices.duplicate(), "uvs": _uvs.duplicate(), "indices": _indices.duplicate(),
		"overflow": _overflow, "batch_nodes": get_child_count(), "material_count": 3}


func _valid_config(cfg: Dictionary) -> bool:
	if int(cfg.get("version", 0)) != 1:
		return false
	for key in ["height_m", "head_capacity", "trace_capacity", "impact_capacity", "history_seconds", "history_interval", "history_points", "tail_max_radii", "tail_max_m", "tail_half_width_radii", "tail_taper_power", "tail_fade_seconds", "impact_seconds", "impact_extent_radii", "head_quad_radii", "aura_quad_radii", "aura_filament_alpha", "head_rear_stretch", "head_appear_seconds", "head_flow_speed", "head_warp", "halo_alpha", "tail_alpha", "flow_alpha"]:
		if not cfg.has(key) or not is_finite(float(cfg[key])) or float(cfg[key]) <= 0.0:
			return false
	for key in ["edge_color", "shell_color", "energy_color", "core_color", "glow_color", "head_body_axes", "head_core_axes"]:
		if not cfg.get(key) is Array or cfg[key].size() != (2 if key.ends_with("axes") else 4):
			return false
		for value in cfg[key]:
			if not is_finite(float(value)):
				return false
			if key.ends_with("axes") and float(value) <= 0.0:
				return false
	return int(cfg.head_capacity) >= 320 and int(cfg.impact_capacity) >= 320 and int(cfg.trace_capacity) >= int(cfg.head_capacity) and int(cfg.history_points) >= 2 and float(cfg.head_quad_radii) > 2.0 * maxf(float(cfg.head_body_axes[0]), float(cfg.head_body_axes[1]))
