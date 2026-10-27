extends Node2D
## F05 reads live zones, selected real contacts and observed world paths.
## Rotation, ribbons and cooling never own movement, ticks or first-hit rules.
const CONFIG_PATH := "res://data/fire_vortex_vfx.json"
const COLUMN_SHADER = preload("res://scripts/presentation/fire_vortex_column.gdshader")
const SURFACE_SHADER = preload("res://scripts/presentation/fire_vortex_surface.gdshader")
const BODY_SHADER = preload("res://scripts/presentation/fire_bolt_body.gdshader")
const TRAIL_SHADER = preload("res://scripts/presentation/fire_bolt_trail.gdshader")

var _config: Dictionary = {}
var _available := false
var _clock := 0.0
var _revision := -1
var _reduced := false
var _coverage: Dictionary = {}
var _footprints: Array = []
var _vortices: Array = []
var _paths: Array = []
var _columns: Array = []
var _interior_flames: Array = []
var _column_faces: Array = []
var _column_effect_count := 0
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
var _column_mesh: ArrayMesh
var _column_node: MeshInstance2D
var _column_material: ShaderMaterial
var _body_material: ShaderMaterial
var _trail_material: ShaderMaterial
var _surface_material: ShaderMaterial
var _vertices := PackedVector3Array()
var _uvs := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _column_world := PackedVector3Array()
var _column_vertices := PackedVector3Array()
var _column_uvs := PackedVector2Array()
var _column_colors := PackedColorArray()
var _column_indices := PackedInt32Array()


func _ready() -> void:
	name = "FireVortexFullChain"
	set_process(false)
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not loaded is Dictionary or not _valid_config(loaded):
		push_error("Invalid F05 visual configuration; keeping legacy vortex drawing.")
		return
	_config = loaded
	_body_material = _material(BODY_SHADER)
	_body_material.set_shader_parameter("body_axes", Vector2(_config.body_axes[0], _config.body_axes[1]))
	_body_material.set_shader_parameter("core_axes", Vector2(_config.core_axes[0], _config.core_axes[1]))
	_trail_material = _material(TRAIL_SHADER)
	_surface_material = _material(SURFACE_SHADER)
	_column_material = _material(COLUMN_SHADER)
	_column_material.set_shader_parameter("body_axes", Vector2(_config.body_axes[0], _config.body_axes[1]))
	_column_material.set_shader_parameter("core_axes", Vector2(_config.core_axes[0], _config.core_axes[1]))
	_grounds = _batch("LiveVortexFootprintsAndSourceSlow", _surface_material, int(_config.surface_capacity))
	_column_mesh = ArrayMesh.new()
	_column_node = MeshInstance2D.new()
	_column_node.name = "LayeredFireTornadoWalls"
	_column_node.mesh = _column_mesh
	_column_node.material = _column_material
	add_child(_column_node)
	_mesh = ArrayMesh.new()
	_ribbons = MeshInstance2D.new()
	_ribbons.name = "ObservedShortWakes"
	_ribbons.mesh = _mesh
	_ribbons.material = _trail_material
	add_child(_ribbons)
	_bodies = _batch("SourceBurns", _body_material, int(_config.flame_capacity))
	_bursts = _batch("RealReleaseSelectedContactsAndEnd", _surface_material, int(_config.surface_capacity))
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
	if str(snapshot.get("phase", "")) != "combat" or not snapshot.has_all(["fire_vortex_facts", "fire_vortex_paths"]):
		_clear()
		return
	_reduced = bool(options.get("reduced_motion", false))
	for mat in [_body_material, _trail_material, _surface_material, _column_material]:
		mat.set_shader_parameter("core_time", now)
		mat.set_shader_parameter("reduced_motion", _reduced)
	_reset_geometry()
	for key in _cooling.keys():
		if now - float(_cooling[key].time) >= float(_config.cooling_seconds): _cooling.erase(key)
	var live: Array = snapshot.get("spell_zones", []).filter(func(z): return str(z.get("spell_id", "")) == "F05" and str(z.get("kind", "")) == "vortex" and float(z.get("remaining", 0.0)) > 0.0 and float(z.get("born_at", INF)) <= now)
	var density := maxf(float(_config.overlap_alpha_floor), 1.0 / sqrt(maxf(1.0, float(live.size()) / float(_config.overlap_soft_limit))))
	for zone: Dictionary in live:
		if _vortices.size() >= int(_config.vortex_capacity):
			_overflow += 1
			continue
		_draw_live(zone, snapshot.fire_vortex_paths.get(int(zone.id), []), density, view)
	_draw_facts(snapshot.fire_vortex_facts, density, view)
	_draw_slows(snapshot, view)
	_draw_burns(snapshot, view)
	for effect: Dictionary in snapshot.get("effects", []):
		if str(effect.get("kind", "")) != "cast" or str(effect.get("spell_id", "")) != "F05" or float(effect.get("life", 0.0)) <= 0.0: continue
		var progress := 1.0 - float(effect.life) / maxf(0.000001, float(effect.max_life))
		var pos: Vector2 = snapshot.get("player", {}).get("pos", effect.pos)
		_surface(pos, 0.035, float(_config.cast_radius_m), 5, progress, 0.53, _seed(int(effect.seq)), view, true)
		_note("F05_cast")
	for item: Dictionary in _cooling.values():
		var progress := (now - float(item.time)) / float(_config.cooling_seconds)
		if progress < 0.0 or progress >= 1.0: continue
		_surface(item.pos, 0.10, float(item.radius), 7, progress, 0.38, float(item.seed), view)
		_note("F05_burn_cooling")
	_upload()
	_grounds.multimesh.visible_instance_count = _ground_count
	_bodies.multimesh.visible_instance_count = _body_count
	_bursts.multimesh.visible_instance_count = _burst_count
	visible = _ground_count > 0 or _body_count > 0 or _burst_count > 0 or not _indices.is_empty() or not _column_indices.is_empty()


func _draw_live(zone: Dictionary, observed: Array, density: float, view) -> void:
	var pos: Vector2 = zone.pos
	var radius := float(zone.radius)
	var hold := float(zone.travel_remaining) <= 0.000001
	var level := clampi(int(zone.context.get("spell_level", 1)) - 1, 0, 2)
	var age := maxf(0.0, _clock - float(zone.born_at))
	var birth := clampf(age / float(_config.birth_seconds), 0.0, 1.0)
	var alpha := density * (1.0 if bool(zone.context.get("natural", false)) else float(_config.extra_alpha))
	var seed := _seed(int(zone.id))
	var direction: Vector2 = zone.direction
	if direction.is_zero_approx(): direction = Vector2.RIGHT
	_surface(pos, 0.03, radius, 1 if hold else 0, clampf(age / maxf(float(zone.duration), 0.000001), 0.0, 1.0), float(_config.ground_alpha) * alpha * (0.4 + birth * 0.6), seed, view, true, direction)
	var height := float(_config.height_by_level[level]) * (float(_config.hold_height_scale) if hold else 1.0) * (0.2 + birth * 0.8)
	var turn := seed * TAU + (0.0 if _reduced else _clock * float(_config.rotation_speed))
	_draw_column(pos, radius, height, turn, seed, alpha * (0.4 + birth * 0.6), hold, int(zone.id), "live", view)
	_draw_interior_flames(pos, radius, height, turn, age, birth, alpha, int(zone.id), level, view)
	_draw_wake(observed, int(zone.id), alpha, view)
	_vortices.append({"zone_id": zone.id, "cast_id": zone.context.cast_id, "pos": pos, "radius": radius, "phase": "hold" if hold else "travel", "travel_remaining": zone.travel_remaining, "remaining": zone.remaining, "spell_level": level + 1, "height": height, "base_radius": _funnel_radius(radius, 0.0), "mouth_radius": _funnel_radius(radius, 1.0), "visual_revision": 5})
	_footprints.append({"kind": "vortex", "zone_id": zone.id, "pos": pos, "radius": radius, "phase": "hold" if hold else "travel", "remaining": zone.remaining})
	_note("F05_hold" if hold else "F05_travel")


func _funnel_radius(radius: float, u: float) -> float:
	var body := lerpf(float(_config.column_base_radius_ratio), float(_config.column_top_radius_ratio), pow(u, float(_config.column_profile_power)))
	return radius * body * (1.0 - float(_config.column_tip_taper_ratio) * pow(u, 6.0))


func _column_center(pos: Vector2, height: float, u: float, turn: float) -> Vector3:
	var bend := Vector2.from_angle(turn * 0.4 + u * 0.9) * float(_config.column_sway_m) * u * u
	return Vector3(pos.x + bend.x, 0.045 + height * u, pos.y + bend.y)


func _depth(point: Vector3, view) -> float:
	if view.has_method("screen_depth"): return float(view.screen_depth(Vector2(point.x, point.z), point.y))
	return -Vector2(view.screen_position(Vector2(point.x, point.z), point.y)).y


func _draw_column(pos: Vector2, radius: float, height: float, turn: float, seed: float, alpha: float, hold: bool, zone_id: int, phase: String, view) -> void:
	if height < 0.01 or alpha <= 0.0: return
	if _column_effect_count >= int(_config.vortex_capacity):
		_overflow += 1
		return
	_column_effect_count += 1
	var sides := int(_config.column_sides)
	var rows := int(_config.column_rows)
	var stride := sides + 1
	for layer in int(_config.column_layers):
		var inner := layer > 0
		var radial_scale := float(_config.column_inner_radius_scale) if inner else 1.0
		var layer_height := height * (float(_config.column_inner_height_scale) if inner else 1.0)
		var layer_alpha := alpha * float(_config.column_alpha) * (float(_config.column_inner_alpha) if inner else 1.0)
		var base := _column_vertices.size()
		for row in range(rows + 1):
			var v := float(row) / rows
			var center := _column_center(pos, layer_height, v, turn)
			var ring_radius := _funnel_radius(radius, v) * radial_scale
			var center_depth := _depth(center, view)
			for side in range(sides + 1):
				var u := float(side) / sides
				var angle := turn * 0.72 + u * TAU + v * 0.36
				var curl := sin(angle * 3.0 - v * 5.0 + turn * 0.4) * 0.65 + sin(angle * 7.0 + v * 8.0 - turn * 0.55) * 0.35
				var ripple := 1.0 + float(_config.column_ripple_ratio) * curl
				var radial := Vector2.from_angle(angle) * ring_radius * ripple
				var crest := sin(angle * 3.0 + turn * 0.37) * 0.68 + sin(angle * 7.0 - turn * 0.53) * 0.32
				var rise := layer_height * float(_config.column_height_ripple_ratio) * pow(v, 3.0) * crest
				var point := center + Vector3(radial.x, rise, radial.y)
				var projected: Vector2 = view.screen_position(Vector2(point.x, point.z), point.y)
				var front := clampf((center_depth - _depth(point, view)) / maxf(ring_radius, 0.001), -1.0, 1.0) * 0.5 + 0.5
				_column_world.append(point)
				_column_vertices.append(Vector3(projected.x, projected.y, 0))
				_column_uvs.append(Vector2(u, v))
				_column_colors.append(Color(seed, (0.5 if inner else 0.0) + (0.25 if hold else 0.0), front, layer_alpha * lerpf(float(_config.column_back_alpha), 1.0, front)))
		for row in rows:
			for side in sides:
				var a := base + row * stride + side
				var middle := (_column_world[a] + _column_world[a + 1] + _column_world[a + stride] + _column_world[a + stride + 1]) * 0.25
				_column_faces.append({"a": a, "stride": stride, "depth": _depth(middle, view)})
		_columns.append({"zone_id": zone_id, "phase": phase, "layer": layer, "pos": pos, "radius": radius, "height": layer_height, "base_radius": _funnel_radius(radius, 0.0) * radial_scale, "mouth_radius": _funnel_radius(radius, 1.0) * radial_scale, "vertex_offset": base, "sides": sides, "rows": rows})


func _draw_interior_flames(pos: Vector2, radius: float, height: float, turn: float, age: float, birth: float, alpha: float, zone_id: int, level: int, view) -> void:
	var count := int(_config.interior_flames_by_level[level])
	if _reduced: count = mini(count, 3)
	var elapsed := 0.0 if _reduced else age
	for index in count:
		var seed := _decoration_seed(zone_id, index, 1)
		var cycle := lerpf(float(_config.interior_flame_cycle_seconds[0]), float(_config.interior_flame_cycle_seconds[1]), _decoration_seed(zone_id, index, 2))
		var progress := fposmod(_decoration_seed(zone_id, index, 3) + elapsed / cycle, 1.0)
		var u := lerpf(float(_config.interior_flame_lift_range[0]), float(_config.interior_flame_lift_range[1]), progress)
		var fade := smoothstep(0.0, 0.18, progress) * (1.0 - smoothstep(0.72, 1.0, progress))
		var flame_alpha := alpha * birth * float(_config.interior_flame_alpha) * fade * (0.68 + seed * 0.32)
		if flame_alpha < 0.002: continue
		var angle := turn * 0.72 + _decoration_seed(zone_id, index, 4) * TAU + u * 0.36 + sin(elapsed * 1.1 + seed * TAU) * float(_config.interior_flame_angle_wobble)
		var radial_ratio := lerpf(float(_config.interior_flame_radius_range[0]), float(_config.interior_flame_radius_range[1]), _decoration_seed(zone_id, index, 5))
		var radial := _funnel_radius(radius, u) * radial_ratio + sin(elapsed * 1.7 + seed * TAU) * radius * float(_config.interior_flame_sway_ratio)
		var center := _column_center(pos, height, u, turn)
		var point := center + Vector3(cos(angle) * radial, 0.0, sin(angle) * radial)
		var pulse := 0.86 + sin(elapsed * 4.3 + seed * TAU) * 0.14
		var flame_height := minf(lerpf(float(_config.interior_flame_height_m[0]), float(_config.interior_flame_height_m[1]), seed) * pulse, height * 0.18)
		var width := minf(lerpf(float(_config.interior_flame_width_m[0]), float(_config.interior_flame_width_m[1]), _decoration_seed(zone_id, index, 6)), height * 0.07)
		var lean := lerpf(float(_config.interior_flame_lean[0]), float(_config.interior_flame_lean[1]), _decoration_seed(zone_id, index, 7))
		var tangent := Vector2(-sin(angle), cos(angle))
		var base := _interior_flame_quad(point, tangent, flame_height, width, lean, flame_alpha, seed, view)
		_interior_flames.append({"zone_id": zone_id, "index": index, "world": point, "height": flame_height, "width": width, "angle": angle, "progress": progress, "alpha": flame_alpha, "vertex_offset": base})
		_note("F05_interior_flame")


func _interior_flame_quad(point: Vector3, tangent: Vector2, height: float, width: float, lean: float, alpha: float, seed: float, view) -> int:
	var center := point + Vector3(0.0, height * 0.28, 0.0)
	var up := Vector3(tangent.x * height * lean, height, tangent.y * height * lean) * float(_config.quad_radii) / 3.5
	var projected: Vector2 = view.screen_position(Vector2(center.x, center.z), center.y)
	var up_screen: Vector2 = view.screen_position(Vector2(center.x + up.x, center.z + up.z), center.y + up.y) - projected
	var right_screen := Vector2(-up_screen.y, up_screen.x).normalized()
	var dx: Vector2 = view.screen_position(Vector2(center.x + 1.0, center.z), center.y) - projected
	var dz: Vector2 = view.screen_position(Vector2(center.x, center.z + 1.0), center.y) - projected
	var determinant := dx.cross(dz)
	var right := Vector2.RIGHT
	if absf(determinant) > 0.000001:
		right = Vector2(right_screen.x * dz.y - right_screen.y * dz.x, dx.x * right_screen.y - dx.y * right_screen.x).normalized()
	var across := Vector3(right.x, 0.0, right.y) * width * float(_config.quad_radii) / 1.65
	var base := _column_world.size()
	for side_y in [-0.5, 0.5]:
		for side_x in [-0.5, 0.5]:
			var at: Vector3 = center + up * side_x + across * side_y
			var screen: Vector2 = view.screen_position(Vector2(at.x, at.z), at.y)
			_column_world.append(at)
			_column_vertices.append(Vector3(screen.x, screen.y, 0.0))
			_column_uvs.append(Vector2(side_x + 0.5, side_y + 0.5))
			_column_colors.append(Color(seed, 1.0, 1.0, alpha))
	# Flame quads share the wall's depth ordering, so the shell can obscure them.
	_column_faces.append({"a": base, "stride": 2, "depth": _depth(center, view), "kind": "interior_flame"})
	return base


static func _decoration_seed(zone_id: int, index: int, salt: int) -> float:
	var value: int = ((zone_id * 73856093) ^ (index * 19349663) ^ (salt * 83492791)) & 0x7fffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	return float(value) / 2147483647.0


func _draw_wake(observed: Array, zone_id: int, alpha: float, view) -> void:
	var points := PackedVector3Array()
	var length := 0.0
	var youngest := INF
	for index in range(observed.size() - 1, -1, -1):
		var sample: Dictionary = observed[index]
		var age := _clock - float(sample.time)
		if age < 0.0 or age > float(_config.wake_seconds) or points.size() >= int(_config.wake_points): continue
		youngest = minf(youngest, age)
		var at: Vector2 = sample.pos
		var point := Vector3(at.x, 0.045, at.y)
		if not points.is_empty():
			var distance := points[-1].distance_to(point)
			if length + distance > float(_config.wake_max_m):
				points.append(points[-1].lerp(point, (float(_config.wake_max_m) - length) / maxf(distance, 0.000001)))
				break
			length += distance
		points.append(point)
	if points.size() >= 2:
		_ribbon(points, float(_config.wake_half_width_m), float(_config.wake_alpha) * alpha * clampf(1.0 - youngest / float(_config.wake_seconds), 0.0, 1.0), _seed(zone_id), "wake", zone_id, view)


func _ribbon(points: PackedVector3Array, width: float, alpha: float, seed: float, kind: String, zone_id: int, view) -> void:
	if points.size() < 2 or alpha <= 0.0: return
	if _paths.size() >= int(_config.ribbon_capacity):
		_overflow += 1
		return
	var distances := PackedFloat32Array([0.0])
	for index in range(1, points.size()): distances.append(distances[-1] + points[index - 1].distance_to(points[index]))
	if float(distances[-1]) < 0.000001: return
	var base := _vertices.size()
	for index in points.size():
		var point := points[index]
		var center: Vector2 = view.screen_position(Vector2(point.x, point.z), point.y)
		var previous := points[maxi(index - 1, 0)]
		var following := points[mini(index + 1, points.size() - 1)]
		var tangent: Vector2 = view.screen_position(Vector2(previous.x, previous.z), previous.y) - view.screen_position(Vector2(following.x, following.z), following.y)
		var normal := Vector2(-tangent.y, tangent.x).normalized()
		var u := float(distances[index]) / float(distances[-1])
		var pixels := _radius(Vector2(point.x, point.z), width, point.y, view) * (0.9 - u * 0.6)
		for side in [-1.0, 1.0]:
			var at: Vector2 = center + normal * pixels * float(side)
			_vertices.append(Vector3(at.x, at.y, 0))
			_uvs.append(Vector2(u, 0.0 if side < 0.0 else 1.0))
			_colors.append(Color(seed, 0, 0, alpha))
		if index > 0:
			var a := base + (index - 1) * 2
			_indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
	_paths.append({"kind": kind, "zone_id": zone_id, "world": points.duplicate(), "alpha": alpha})


func _draw_facts(facts: Array, density: float, view) -> void:
	for fact: Dictionary in facts:
		var age := _clock - float(fact.time)
		if age < 0.0: continue
		var alpha := density * (1.0 if bool(fact.natural) else float(_config.extra_alpha))
		var seed := _seed(int(fact.zone_id))
		match str(fact.phase):
			"release":
				if age >= float(_config.birth_seconds): continue
				_surface(fact.pos, 0.22, float(_config.release_radius_m), 2, age / float(_config.birth_seconds), alpha * 0.55, seed, view)
				_note("F05_release")
			"hit":
				var hit: Dictionary = fact.contact
				if age >= float(_config.hit_seconds) or float(hit.damage) <= 0.0: continue
				_surface(hit.pos, 0.40, float(hit.radius) * float(_config.hit_radius_ratio), 2, age / float(_config.hit_seconds), alpha * float(_config.first_hit_alpha if bool(hit.first) else _config.repeat_hit_alpha), _seed(int(hit.actor_id) + int(fact.seq)), view)
				_footprints.append({"kind": "vortex_hit", "zone_id": fact.zone_id, "actor_id": hit.actor_id, "pos": hit.pos, "time": fact.time, "damage": hit.damage, "first": hit.first, "alive_after": hit.alive_after})
				_note("F05_hit")
			"end":
				if age >= float(_config.end_seconds): continue
				var progress := age / float(_config.end_seconds)
				var level := clampi(int(fact.spell_level) - 1, 0, 2)
				var height := float(_config.height_by_level[level]) * 0.60 * pow(1.0 - progress, 0.75)
				var turn := seed * TAU + (0.0 if _reduced else _clock * float(_config.rotation_speed))
				_draw_column(fact.pos, float(fact.radius) * (0.60 - progress * 0.20), height, turn, seed, alpha * pow(1.0 - progress, 1.3) * 0.55, true, int(fact.zone_id), "end", view)
				_surface(fact.pos, 0.06, float(fact.radius) * float(_config.end_radius_ratio), 4, age / float(_config.end_seconds), alpha * 0.48, seed, view)
				_draw_wake(fact.get("path", []), int(fact.zone_id), alpha * (1.0 - age / float(_config.end_seconds)), view)
				_footprints.append({"kind": "vortex_end", "zone_id": fact.zone_id, "pos": fact.pos, "time": fact.time})
				_note("F05_end")


func _draw_slows(snapshot: Dictionary, view) -> void:
	for actor: Dictionary in snapshot.get("actors", []):
		if float(actor.get("health", 0.0)) <= 0.0: continue
		var selected: Dictionary = {}
		var source := ""
		var sources: Array = []
		for key in actor.get("spell_slows", {}):
			if not str(key).begins_with("F05:") and not str(key).begins_with("B05:"): continue
			var slow: Dictionary = actor.spell_slows[key]
			if float(slow.get("until", -INF)) <= _clock or float(slow.get("amount", 0.0)) <= 0.0: continue
			sources.append(str(key))
			if selected.is_empty() or float(slow.amount) > float(selected.amount) or (is_equal_approx(float(slow.amount), float(selected.amount)) and float(slow.until) > float(selected.until)):
				selected = slow
				source = str(key)
		if selected.is_empty(): continue
		var remaining := float(selected.until) - _clock
		_surface(actor.pos, 0.035, float(actor.radius) * float(_config.slow_radius_ratio), 3, 0.0, float(_config.slow_alpha) * clampf(remaining / float(_config.status_fade_seconds), 0.0, 1.0), _seed(int(actor.id)), view, true)
		_footprints.append({"kind": "vortex_slow", "actor_id": actor.id, "pos": actor.pos, "source": source, "sources": sources, "amount": selected.amount, "remaining": remaining})
		_note("F05_slow")


func _draw_burns(snapshot: Dictionary, view) -> void:
	var actors: Dictionary = {}
	for actor: Dictionary in snapshot.get("actors", []): actors[int(actor.id)] = actor
	var all_live: Dictionary = {}
	var owned: Dictionary = {}
	for burn: Dictionary in snapshot.get("spell_burns", []):
		var id := int(burn.actor_id)
		all_live[id] = true
		if str(burn.get("source", "")) != "F05" or not actors.has(id) or float(actors[id].health) <= 0.0 or float(burn.remaining) <= 0.0: continue
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
			_note("F05_ignited")
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
		if str(effect.get("kind", "")) == "fire_ignited" and str(effect.get("source", "")) == "F05" and int(effect.get("actor_id", -1)) == id:
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
	_upload_column()
	if _mesh.get_surface_count() > 0: _mesh.clear_surfaces()
	if _indices.is_empty(): return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _upload_column() -> void:
	if _column_mesh.get_surface_count() > 0: _column_mesh.clear_surfaces()
	if _column_faces.is_empty(): return
	_column_faces.sort_custom(func(left, right): return int(left.a) < int(right.a) if float(left.depth) == float(right.depth) else float(left.depth) > float(right.depth))
	for face: Dictionary in _column_faces:
		var a := int(face.a)
		var stride := int(face.stride)
		_column_indices.append_array(PackedInt32Array([a, a + stride, a + 1, a + 1, a + stride, a + stride + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _column_vertices
	arrays[Mesh.ARRAY_TEX_UV] = _column_uvs
	arrays[Mesh.ARRAY_COLOR] = _column_colors
	arrays[Mesh.ARRAY_INDEX] = _column_indices
	_column_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _reset_geometry() -> void:
	_body_count = 0
	_ground_count = 0
	_burst_count = 0
	_overflow = 0
	_coverage.clear()
	_footprints.clear()
	_vortices.clear()
	_paths.clear()
	_columns.clear()
	_interior_flames.clear()
	_column_faces.clear()
	_column_effect_count = 0
	_column_world.clear()
	_column_vertices.clear()
	_column_uvs.clear()
	_column_colors.clear()
	_column_indices.clear()
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
		if _column_mesh.get_surface_count() > 0: _column_mesh.clear_surfaces()
	visible = false


func get_debug_state() -> Dictionary:
	return {"available": _available, "clock": _clock, "revision": _revision, "vortices": _vortices.duplicate(true),
		"paths": _paths.duplicate(true), "coverage": _coverage.duplicate(true), "footprints": _footprints.duplicate(true),
		"columns": _columns.duplicate(true), "column_world": _column_world.duplicate(), "column_vertices": _column_vertices.duplicate(), "column_indices": _column_indices.duplicate(),
		"interior_flames": _interior_flames.duplicate(true),
		"burns": _burns.duplicate(true), "cooling": _cooling.duplicate(true), "vertices": _vertices.duplicate(),
		"uvs": _uvs.duplicate(), "indices": _indices.duplicate(), "body_instances": _body_count,
		"ground_instances": _ground_count, "burst_instances": _burst_count, "overflow": _overflow,
		"batch_nodes": get_child_count(), "material_count": 4, "visual_revision": 5}


func _valid_config(cfg: Dictionary) -> bool:
	if int(cfg.get("version", 0)) != 1: return false
	if not cfg.has_all(["version", "scope", "vortex_capacity", "surface_capacity", "flame_capacity", "ribbon_capacity", "cooling_capacity", "rotation_speed", "height_by_level", "hold_height_scale", "ground_alpha", "birth_seconds", "cast_radius_m", "release_radius_m", "hit_seconds", "hit_radius_ratio", "first_hit_alpha", "repeat_hit_alpha", "end_seconds", "end_radius_ratio", "wake_seconds", "wake_points", "wake_max_m", "wake_half_width_m", "wake_alpha", "tail_alpha", "slow_radius_ratio", "slow_alpha", "status_fade_seconds", "body_axes", "core_axes", "quad_radii", "rear_stretch", "flow_speed", "ignite_seconds", "burn_flames", "burn_flame_height_m", "burn_flame_width_m", "burn_alpha", "source_fade_seconds", "cooling_seconds", "overlap_soft_limit", "overlap_alpha_floor", "extra_alpha", "edge_color", "shell_color", "energy_color", "core_color", "ember_color", "visual_revision", "column_sides", "column_rows", "column_layers", "column_alpha", "column_base_radius_ratio", "column_top_radius_ratio", "column_profile_power", "column_sway_m", "column_ripple_ratio", "column_inner_radius_scale", "column_inner_height_scale", "column_inner_alpha", "column_back_alpha", "column_height_ripple_ratio", "column_tip_taper_ratio", "interior_flames_by_level", "interior_flame_height_m", "interior_flame_width_m", "interior_flame_radius_range", "interior_flame_lift_range", "interior_flame_cycle_seconds", "interior_flame_lean", "interior_flame_alpha", "interior_flame_sway_ratio", "interior_flame_angle_wobble", "interior_flame_light_boost"]): return false
	for key in cfg:
		var value: Variant = cfg[key]
		if key in ["version", "scope"]: continue
		if value is Array:
			var count := 3 if key in ["height_by_level", "interior_flames_by_level"] else 2 if key in ["body_axes", "core_axes"] or key.begins_with("interior_flame_") else 4
			if value.size() != count: return false
			for part in value:
				if not (part is int or part is float) or not is_finite(float(part)) or float(part) < 0.0: return false
		elif not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0.0: return false
	return int(cfg.wake_points) >= 2 and int(cfg.column_sides) >= 8 and int(cfg.column_rows) >= 3 and int(cfg.column_layers) == 2 and float(cfg.column_base_radius_ratio) < float(cfg.column_top_radius_ratio)
