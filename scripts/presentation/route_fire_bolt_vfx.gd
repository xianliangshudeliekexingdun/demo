extends Node2D
## F01's complete read-only chain. All geometry is projected from world facts;
## no wall clock, gameplay RNG, per-shot nodes or disappearance-as-hit guesses.
const CONFIG_PATH := "res://data/fire_bolt_vfx.json"
const BODY_SHADER = preload("res://scripts/presentation/fire_bolt_body.gdshader")
const TRAIL_SHADER = preload("res://scripts/presentation/fire_bolt_trail.gdshader")
const SURFACE_SHADER = preload("res://scripts/presentation/fire_bolt_surface.gdshader")
const BoltMotion = preload("res://scripts/core/route_fire_bolt_motion.gd")

class Trace extends RefCounted:
	var id: int
	var pos := Vector2.ZERO
	var origin := Vector2.ZERO
	var direction := Vector2.UP
	var radius := 0.0
	var born := 0.0
	var last_time := 0.0
	var ended_at := -1.0
	var active := false
	var flight: Dictionary = {}
	var age := 0.0
	var visual_scale := 1.0
	var speed_fraction := 1.0
	var samples := PackedVector2Array()
	var stamps := PackedFloat64Array()
	var path := PackedVector2Array()

var _config: Dictionary = {}
var _available := false
var _clock := 0.0
var _revision := -1
var _last_end_seq := -1
var _reduced := false
var _traces: Dictionary = {}
var _impacts: Array = []
var _burns: Dictionary = {}
var _coverage: Dictionary = {}
var _footprints: Array = []
var _head_ids := PackedInt64Array()
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
	name = "FireBoltFullChain"
	set_process(false)
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not loaded is Dictionary or not _valid_config(loaded):
		push_error("Invalid F01 visual configuration; keeping legacy F01 drawing.")
		return
	_config = loaded
	_body_material = _material(BODY_SHADER)
	_trail_material = _material(TRAIL_SHADER)
	_surface_material = _material(SURFACE_SHADER)
	_body_material.set_shader_parameter("body_axes", Vector2(_config.head_body_axes[0], _config.head_body_axes[1]))
	_body_material.set_shader_parameter("core_axes", Vector2(_config.head_core_axes[0], _config.head_core_axes[1]))
	_body_material.set_shader_parameter("rear_stretch", float(_config.head_rear_stretch))
	_body_material.set_shader_parameter("quad_radii", float(_config.head_quad_radii))
	_grounds = _batch("LiveCriticalFireFootprints", _surface_material, int(_config.surface_capacity))
	_mesh = ArrayMesh.new()
	_ribbons = MeshInstance2D.new()
	_ribbons.name = "ContinuousWorldFireTrails"
	_ribbons.mesh = _mesh
	_ribbons.material = _trail_material
	add_child(_ribbons)
	_bodies = _batch("FlameHeadsAndAttachedTongues", _body_material, int(_config.flame_capacity))
	_bursts = _batch("ChantReleaseContactAndCooling", _surface_material, int(_config.surface_capacity))
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
	_clock = now
	_revision = revision
	if str(snapshot.get("phase", "")) != "combat" or not snapshot.has("fire_bolt_ends"):
		_clear()
		return
	_reduced = bool(options.get("reduced_motion", false))
	for mat in [_body_material, _trail_material, _surface_material]:
		mat.set_shader_parameter("core_time", now)
		mat.set_shader_parameter("reduced_motion", _reduced)
	_body_count = 0
	_ground_count = 0
	_burst_count = 0
	_overflow = 0
	_head_ids.clear()
	_coverage.clear()
	_footprints.clear()
	_vertices.clear()
	_uvs.clear()
	_colors.clear()
	_indices.clear()
	for trace: Trace in _traces.values(): trace.active = false
	for shot: Dictionary in snapshot.get("projectiles", []):
		if str(shot.get("spell_id", "")) != "F01": continue
		var trace: Trace = _traces.get(int(shot.id))
		if trace == null: trace = _new_trace(shot, now)
		trace.active = true
		trace.ended_at = -1.0
		trace.radius = float(shot.radius)
		trace.direction = Vector2(shot.direction).normalized()
		trace.age = float(shot.get("age", 0.0))
		trace.visual_scale = _visual_scale(shot)
		trace.speed_fraction = clampf(float(shot.speed) / float(trace.flight.get("cruise_speed", shot.speed)), 0.0, 1.0)
		_sample(trace, shot.pos, now)
		_draw_head(trace, view)
	_consume_ends(snapshot.fire_bolt_ends, now)
	for id in _traces.keys():
		var trace: Trace = _traces[id]
		if not trace.active and trace.ended_at < 0.0: trace.ended_at = now
		if trace.ended_at >= 0.0 and now - trace.ended_at >= float(_config.tail_fade_seconds):
			_traces.erase(id)
			continue
		trace.path = _path(trace, now if trace.active else trace.ended_at)
		if trace.path.size() >= 2: _ribbon(trace, view)
		var release_age := now - trace.born
		if release_age >= 0.0 and release_age < float(_config.release_seconds):
			_surface(trace.origin, float(_config.height_m), float(_config.release_radius_m), 6, release_age / float(_config.release_seconds), 0.75, _seed(trace.id), view)
			_note("release")
	# Evict only ended decorative history. Live shots always keep their heads.
	for id in _traces.keys():
		if _traces.size() <= int(_config.trace_capacity): break
		if not _traces[id].active: _traces.erase(id)
	var actors: Dictionary = {}
	for actor: Dictionary in snapshot.get("actors", []): actors[int(actor.id)] = actor
	_draw_burns(snapshot, actors, view)
	for patch: Dictionary in snapshot.get("artifact_patches", []):
		if str(patch.get("context", {}).get("spell_id", "")) == "F01": _draw_patch(patch, view)
	for effect: Dictionary in snapshot.get("effects", []):
		if str(effect.get("kind", "")) != "cast" or str(effect.get("spell_id", "")) != "F01": continue
		var life := float(effect.get("life", 0.0))
		if life <= 0.0: continue
		var progress := 1.0 - life / maxf(0.000001, float(effect.max_life))
		var pos: Vector2 = snapshot.get("player", {}).get("pos", effect.pos)
		_surface(pos, float(_config.height_m), float(_config.cast_radius_m), 0, progress, 0.6, _seed(int(effect.get("seq", 0))), view)
		_note("cast")
	for index in range(_impacts.size() - 1, -1, -1):
		var event: Dictionary = _impacts[index]
		var age := now - float(event.time)
		var duration := _duration(str(event.reason))
		if age >= duration or age < -0.000001: _impacts.remove_at(index)
		else: _draw_end(event, age / duration, view)
	_upload()
	_grounds.multimesh.visible_instance_count = _ground_count
	_bodies.multimesh.visible_instance_count = _body_count
	_bursts.multimesh.visible_instance_count = _burst_count
	visible = _ground_count > 0 or _body_count > 0 or _burst_count > 0 or not _indices.is_empty()


func _new_trace(source: Dictionary, now: float) -> Trace:
	var trace := Trace.new()
	trace.id = int(source.get("id", source.get("projectile_id", -1)))
	trace.pos = source.pos
	trace.origin = source.get("origin", source.get("from", trace.pos))
	trace.direction = Vector2(source.direction).normalized()
	trace.radius = float(source.radius)
	trace.flight = source.get("flight", {}).duplicate(true)
	trace.age = float(source.get("age", 0.0))
	trace.visual_scale = _visual_scale(source)
	var speed := maxf(0.000001, float(source.speed))
	var travelled := float(source.get("travelled", trace.origin.distance_to(trace.pos)))
	trace.born = float(source.born_at) if not trace.flight.is_empty() else now - travelled / speed
	trace.last_time = now
	# New F01 geometry is reconstructed from its released control points and
	# actual age. Old snapshots retain their former straight-history fallback.
	var length := 0.0 if not trace.flight.is_empty() else minf(travelled, minf(float(_config.tail_max_m), speed * float(_config.history_seconds)))
	trace.samples.append(trace.pos - trace.direction * length)
	trace.stamps.append(now - length / speed)
	_traces[trace.id] = trace
	return trace


func _sample(trace: Trace, pos: Vector2, now: float) -> void:
	trace.pos = pos
	trace.last_time = now
	if now - trace.stamps[-1] >= float(_config.history_interval) - 0.000001:
		trace.samples.append(pos)
		trace.stamps.append(now)
	while trace.samples.size() > int(_config.history_points) or (trace.samples.size() > 2 and now - trace.stamps[1] > float(_config.history_seconds)):
		trace.samples.remove_at(0)
		trace.stamps.remove_at(0)


func _consume_ends(events: Array, now: float) -> void:
	for event: Dictionary in events:
		var seq := int(event.seq)
		if seq <= _last_end_seq: continue
		_last_end_seq = seq
		if now - float(event.time) > maxf(float(_config.impact_seconds), float(_config.tail_fade_seconds)): continue
		var trace: Trace = _traces.get(int(event.projectile_id))
		if trace == null: trace = _new_trace(event, float(event.time))
		_sample(trace, event.pos, float(event.time))
		trace.age = float(event.get("age", 0.0))
		trace.active = false
		trace.ended_at = float(event.time)
		if _impacts.size() < int(_config.surface_capacity): _impacts.append(event.duplicate(true))


func _path(trace: Trace, now: float) -> PackedVector2Array:
	if not trace.flight.is_empty():
		var raw := BoltMotion.trail(trace.flight, trace.age, float(_config.history_seconds), float(_config.history_interval), int(_config.history_points))
		raw[0] = trace.pos
		return _trim_path(raw, trace.radius * trace.visual_scale)
	var points := PackedVector2Array([trace.pos])
	var maximum := minf(trace.radius * trace.visual_scale * float(_config.tail_max_radii), float(_config.tail_max_m))
	var cutoff := now - float(_config.history_seconds)
	var recent := trace.pos
	var recent_time := trace.last_time
	var length := 0.0
	for index in range(trace.samples.size() - 1, -1, -1):
		var point: Vector2 = trace.samples[index]
		var stamp := trace.stamps[index]
		var last := stamp < cutoff
		if last:
			if recent_time <= cutoff or recent_time <= stamp: break
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
		if last: break
	return points


func _trim_path(raw: PackedVector2Array, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array([raw[0]])
	var maximum := minf(radius * float(_config.tail_max_radii), float(_config.tail_max_m))
	var length := 0.0
	for index in range(1, raw.size()):
		var segment := raw[index - 1].distance_to(raw[index])
		if length + segment >= maximum:
			points.append(raw[index - 1].lerp(raw[index], (maximum - length) / maxf(0.000001, segment)))
			break
		if segment > 0.000001: points.append(raw[index])
		length += segment
	return points


func _visual_scale(source: Dictionary) -> float:
	var level := clampi(int(source.get("spell_level", source.get("context", {}).get("spell_level", 1))), 1, 3)
	return float(_config.head_scale_by_level[level - 1])


func _draw_head(trace: Trace, view) -> void:
	if _head_ids.size() >= int(_config.head_capacity):
		_overflow += 1
		return
	var axis := _axis(trace.pos, trace.direction, view)
	var dimension := _radius(trace.pos, trace.radius * trace.visual_scale, view) * float(_config.head_quad_radii)
	var alpha := 0.8 + 0.2 * clampf((_clock - trace.born) / float(_config.head_appear_seconds), 0.0, 1.0)
	_body(Transform2D(axis * dimension, Vector2(-axis.y, axis.x) * dimension, view.screen_position(trace.pos, float(_config.height_m))), Color(_seed(trace.id), trace.speed_fraction, 0, alpha))
	_head_ids.append(trace.id)
	_note("F01_bolt")


func _ribbon(trace: Trace, view) -> void:
	var points := PackedVector2Array()
	var distances := PackedFloat32Array([0.0])
	var total := 0.0
	for index in trace.path.size():
		points.append(view.screen_position(trace.path[index], float(_config.height_m)))
		if index > 0:
			total += trace.path[index - 1].distance_to(trace.path[index])
			distances.append(total)
	if total <= 0.00001: return
	var fade := 1.0 if trace.active else clampf(1.0 - (_clock - trace.ended_at) / float(_config.tail_fade_seconds), 0.0, 1.0)
	var width := _radius(trace.pos, trace.radius * trace.visual_scale, view) * float(_config.tail_half_width_radii)
	var base := _vertices.size()
	for index in points.size():
		var tangent := points[maxi(0, index - 1)] - points[mini(points.size() - 1, index + 1)]
		var normal := Vector2(-tangent.y, tangent.x).normalized() if tangent.length_squared() > 0.000001 else Vector2.UP
		var u := float(distances[index]) / total
		var half_width := width * pow(maxf(0.0, 1.0 - u), float(_config.tail_taper_power))
		for side in [-1.0, 1.0]:
			var p: Vector2 = points[index] + normal * half_width * side
			_vertices.append(Vector3(p.x, p.y, 0))
			_uvs.append(Vector2(u, 0.0 if side < 0.0 else 1.0))
			_colors.append(Color(_seed(trace.id), 0, 0, fade))
		if index > 0:
			var a := base + (index - 1) * 2
			_indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))


func _draw_burns(snapshot: Dictionary, actors: Dictionary, view) -> void:
	var all_live: Dictionary = {}
	var owned: Dictionary = {}
	for burn: Dictionary in snapshot.get("spell_burns", []):
		var id := int(burn.actor_id)
		all_live[id] = true
		if str(burn.get("source", "")) != "F01" or not actors.has(id) or float(actors[id].health) <= 0.0: continue
		var actor: Dictionary = actors[id]
		var previous: Dictionary = _burns.get(id, {})
		var born := float(previous.born) if int(previous.get("token", -1)) == int(burn.token) else _ignition_time(snapshot, id)
		owned[id] = {"token": int(burn.token), "born": born, "pos": actor.pos, "radius": float(actor.radius)}
		var fade := clampf(float(burn.remaining) / float(_config.source_fade_seconds), 0, 1)
		var count := 2 if _reduced else int(_config.burn_flames)
		for index in count:
			var seed := _seed(id + index * 71)
			var pos: Vector2 = actor.pos + Vector2.from_angle(seed * TAU) * float(actor.radius) * 0.48
			_upright(pos, 0.08, float(_config.burn_flame_height_m), float(_config.burn_flame_width_m), fade * float(_config.burn_alpha), seed, view)
		if _clock - born < float(_config.ignite_seconds):
			_surface(actor.pos, 0.38, float(actor.radius) * 1.3, 4, (_clock - born) / float(_config.ignite_seconds), 0.52, _seed(id), view)
			_note("fire_ignited")
		_footprints.append({"kind": "burning", "actor_id": id, "pos": actor.pos, "remaining": burn.remaining})
		_note("burning")
	for id in _burns:
		# A refreshed burn handed to another source stays that source's visual;
		# detonation/death/clear never masquerades as a natural cooling puff.
		if all_live.has(id) or not actors.has(id) or float(actors[id].health) <= 0.0: continue
		var detonated := false
		for effect: Dictionary in snapshot.get("effects", []):
			if effect.get("kind", "") == "fire_detonation" and int(effect.get("actor_id", -1)) == int(id): detonated = true
		if not detonated and _impacts.size() < int(_config.surface_capacity):
			_impacts.append({"reason": "burn_end", "pos": actors[id].pos, "radius": float(_burns[id].radius), "time": _clock, "projectile_id": int(id)})
	_burns = owned


func _ignition_time(snapshot: Dictionary, actor_id: int) -> float:
	# Attaching the view midway through an old burn is not a new ignition.
	var born := -INF
	for effect: Dictionary in snapshot.get("effects", []):
		if str(effect.get("kind", "")) == "fire_ignited" and str(effect.get("source", "")) == "F01" and int(effect.get("actor_id", -1)) == actor_id:
			born = maxf(born, _clock - maxf(0.0, float(effect.get("max_life", 0.0)) - float(effect.get("life", 0.0))))
	return born


func _draw_patch(patch: Dictionary, view) -> void:
	var remaining := float(patch.get("remaining", 0.0))
	if remaining <= 0.0: return
	var pos: Vector2 = patch.pos
	var radius := float(patch.radius)
	var seed := _seed(int(patch.get("context", {}).get("cast_id", 0)))
	var fade := clampf(remaining / float(_config.source_fade_seconds), 0, 1)
	_surface(pos, 0.025, radius, 3, 0.0, fade * float(_config.patch_alpha), seed, view, true)
	var count := 3 if _reduced else int(_config.patch_flames)
	for index in count:
		var part := _seed(int(seed * 10000) + index * 53)
		var at := pos + Vector2.from_angle(part * TAU) * radius * (0.22 + 0.50 * _seed(index + 19))
		_upright(at, 0.04, float(_config.patch_flame_height_m), float(_config.patch_flame_width_m), fade * float(_config.patch_alpha), part, view)
	_footprints.append({"kind": "artifact_patch", "pos": pos, "radius": radius, "remaining": remaining})
	_note("artifact_patch")


func _draw_end(event: Dictionary, progress: float, view) -> void:
	var reason := str(event.reason)
	var mode := 1 if reason == "enemy" else 2 if reason == "wall" else 5
	var radius := float(event.get("blast_radius", 0.0)) if reason == "enemy" else float(event.radius) * _visual_scale(event) * float(_config.wall_extent_radii if reason == "wall" else _config.extinguish_radius_radii)
	var pos: Vector2 = event.pos if reason == "enemy" else event.get("contact_pos", event.pos)
	var height := 0.08 if reason == "enemy" else float(_config.height_m)
	var direction: Vector2 = -Vector2(event.get("normal", Vector2.LEFT))
	_surface(pos, height, radius, mode, progress, 0.72 if _reduced else 0.92, _seed(int(event.projectile_id)), view, reason == "enemy", direction)
	if reason == "enemy":
		var seed := _seed(int(event.projectile_id))
		for index in (2 if _reduced else 4):
			var at := pos + Vector2.from_angle(seed * TAU + index * TAU / 4.0) * radius * (0.18 + progress * 0.40)
			_upright(at, 0.06, float(_config.burn_flame_height_m) * (1.0 - progress), float(_config.burn_flame_width_m) * 1.4, pow(1.0 - progress, 1.4) * 0.85, _seed(index + int(event.projectile_id)), view)
		_note("bolt_hit")
	elif reason == "wall": _note("bolt_blocked")
	else: _note("extinguish")
	_footprints.append({"kind": reason, "pos": pos, "radius": radius})


func _duration(reason: String) -> float:
	return float(_config.impact_seconds if reason == "enemy" else _config.wall_seconds if reason == "wall" else _config.extinguish_seconds)


func _surface(pos: Vector2, height: float, radius: float, mode: int, progress: float, alpha: float, seed: float, view, ground: bool = false, direction: Vector2 = Vector2.RIGHT) -> void:
	var center: Vector2 = view.screen_position(pos, height)
	var transform: Transform2D
	if ground:
		transform = Transform2D(view.screen_position(pos + Vector2(radius * 2.0, 0), height) - center, view.screen_position(pos + Vector2(0, radius * 2.0), height) - center, center)
	else:
		var axis := _axis(pos, direction, view)
		var size := _radius(pos, radius, view) * 2.0
		transform = Transform2D(axis * size, Vector2(-axis.y, axis.x) * size, center)
	var batch := _grounds if ground else _bursts
	var index := _ground_count if ground else _burst_count
	if index >= int(_config.surface_capacity):
		_overflow += 1
		return
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


func _axis(pos: Vector2, direction: Vector2, view) -> Vector2:
	var axis: Vector2 = view.screen_position(pos + direction, float(_config.height_m)) - view.screen_position(pos, float(_config.height_m))
	return axis.normalized() if axis.length_squared() > 0.000001 else Vector2.RIGHT


func _radius(pos: Vector2, radius: float, view) -> float:
	var center: Vector2 = view.screen_position(pos, float(_config.height_m))
	var x: Vector2 = view.screen_position(pos + Vector2(radius, 0), float(_config.height_m)) - center
	var y: Vector2 = view.screen_position(pos + Vector2(0, radius), float(_config.height_m)) - center
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
		if key.ends_with("_color"):
			var value: Array = _config[key]
			mat.set_shader_parameter(key, Color(value[0], value[1], value[2], value[3]))
		elif _config.has(key): mat.set_shader_parameter(key, float(_config[key]))
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


func _clear() -> void:
	_traces.clear()
	_impacts.clear()
	_burns.clear()
	_coverage.clear()
	_footprints.clear()
	_head_ids.clear()
	_last_end_seq = -1
	_body_count = 0
	_ground_count = 0
	_burst_count = 0
	_vertices.clear()
	_overflow = 0
	_uvs.clear()
	_colors.clear()
	_indices.clear()
	if _available:
		_grounds.multimesh.visible_instance_count = 0
		_bodies.multimesh.visible_instance_count = 0
		_bursts.multimesh.visible_instance_count = 0
		if _mesh.get_surface_count() > 0: _mesh.clear_surfaces()
	visible = false


func get_debug_state() -> Dictionary:
	var paths: Array = []
	for trace: Trace in _traces.values():
		paths.append({"id": trace.id, "pos": trace.pos, "world_path": trace.path.duplicate(), "samples": trace.samples.size(), "active": trace.active, "ended_at": trace.ended_at,
			"visual_scale": trace.visual_scale, "age": trace.age, "speed_fraction": trace.speed_fraction, "curved": not trace.flight.is_empty()})
	return {"available": _available, "clock": _clock, "revision": _revision, "visual_revision": int(_config.get("visual_revision", 0)),
		"head_ids": _head_ids.duplicate(), "heads": _head_ids.size(), "paths": paths, "impacts": _impacts.duplicate(true),
		"body_instances": _body_count, "ground_instances": _ground_count, "burst_instances": _burst_count,
		"vertices": _vertices.duplicate(), "uvs": _uvs.duplicate(), "indices": _indices.duplicate(), "colors": _colors.duplicate(),
		"coverage": _coverage.duplicate(true), "footprints": _footprints.duplicate(true), "burns": _burns.duplicate(true),
		"overflow": _overflow, "batch_nodes": get_child_count(), "material_count": 3}


func _valid_config(cfg: Dictionary) -> bool:
	if int(cfg.get("version", 0)) != 1: return false
	if not cfg.get("head_scale_by_level") is Array or cfg.head_scale_by_level.size() != 3: return false
	var last_scale := 0.0
	for scale in cfg.head_scale_by_level:
		if not (scale is int or scale is float) or not is_finite(float(scale)) or float(scale) <= last_scale: return false
		last_scale = float(scale)
	for key in ["height_m", "head_capacity", "trace_capacity", "surface_capacity", "flame_capacity", "history_seconds", "history_interval", "history_points", "tail_max_radii", "tail_max_m", "tail_half_width_radii", "tail_taper_power", "tail_fade_seconds", "head_quad_radii", "head_appear_seconds", "head_rear_stretch", "flow_speed", "tail_alpha", "release_seconds", "release_radius_m", "cast_radius_m", "impact_seconds", "wall_seconds", "wall_extent_radii", "extinguish_seconds", "extinguish_radius_radii", "ignite_seconds", "burn_flame_height_m", "burn_flame_width_m", "burn_alpha", "burn_flames", "patch_flames", "patch_flame_height_m", "patch_flame_width_m", "patch_alpha", "source_fade_seconds"]:
		if not cfg.has(key) or not (cfg[key] is int or cfg[key] is float) or not is_finite(float(cfg[key])) or float(cfg[key]) <= 0.0: return false
	for key in ["edge_color", "shell_color", "energy_color", "core_color", "ember_color", "head_body_axes", "head_core_axes"]:
		if not cfg.get(key) is Array or cfg[key].size() != (2 if key.ends_with("axes") else 4): return false
		for value in cfg[key]:
			if not (value is int or value is float) or not is_finite(float(value)): return false
			if key.ends_with("axes") and float(value) <= 0.0: return false
	return int(cfg.trace_capacity) >= int(cfg.head_capacity) and int(cfg.flame_capacity) > int(cfg.head_capacity) and int(cfg.history_points) >= 2
