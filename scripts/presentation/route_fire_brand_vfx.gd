extends Node2D
## Read-only F11 primary contacts and original successful fire_spread effects.
const CONFIG_PATH := "res://data/fire_brand_vfx.json"
const SURFACE_SHADER = preload("res://scripts/presentation/fire_brand_surface.gdshader")
const BODY_SHADER = preload("res://scripts/presentation/fire_bolt_body.gdshader")
var _config: Dictionary = {}
var _available := false
var _clock := 0.0
var _revision := -1
var _reduced := false
var _coverage: Dictionary = {}
var _footprints: Array = []
var _links: Array = []
var _marks: Array = []
var _link_transforms: Array[Transform2D] = []
var _ground_transforms: Array[Transform2D] = []
var _burns: Dictionary = {}
var _cooling: Dictionary = {}
var _body_count := 0
var _ground_count := 0
var _burst_count := 0
var _overflow := 0
var _grounds: MultiMeshInstance2D
var _bodies: MultiMeshInstance2D
var _bursts: MultiMeshInstance2D
var _body_material: ShaderMaterial
var _surface_material: ShaderMaterial


func _ready() -> void:
	name = "FireBrandFullChain"
	set_process(false)
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not loaded is Dictionary or not _valid_config(loaded):
		push_error("Invalid F11 visual configuration; keeping legacy brand drawing.")
		return
	_config = loaded
	_body_material = _material(BODY_SHADER)
	_body_material.set_shader_parameter("body_axes", Vector2(_config.body_axes[0], _config.body_axes[1]))
	_body_material.set_shader_parameter("core_axes", Vector2(_config.core_axes[0], _config.core_axes[1]))
	_surface_material = _material(SURFACE_SHADER)
	_grounds = _batch("ShortCastingGather", _surface_material, int(_config.surface_capacity))
	_bodies = _batch("TrueBrandIgnitionAndSourceBurns", _body_material, int(_config.flame_capacity))
	_bursts = _batch("PrimarySealsSuccessfulLinksAndCooling", _surface_material, int(_config.surface_capacity))
	_available = true
	visible = false


func is_available() -> bool: return _available


func sync_snapshot(snapshot: Dictionary, view, options: Dictionary = {}) -> void:
	if not _available: return
	var now := float(snapshot.get("time", 0.0))
	var revision := int(snapshot.get("room_revision", 0))
	if revision != _revision or now < _clock - 0.000001: _clear()
	_clock = now
	_revision = revision
	if str(snapshot.get("phase", "")) != "combat" or not snapshot.has("fire_brand_facts"):
		_clear()
		return
	_reduced = bool(options.get("reduced_motion", false))
	for mat in [_body_material, _surface_material]:
		mat.set_shader_parameter("core_time", now)
		mat.set_shader_parameter("reduced_motion", _reduced)
	_reset_geometry()
	for key in _cooling.keys():
		if now - float(_cooling[key].time) >= float(_config.cooling_seconds): _cooling.erase(key)
	for fact: Dictionary in snapshot.fire_brand_facts: _draw_mark(fact, view)
	for effect: Dictionary in snapshot.get("effects", []):
		if float(effect.get("life", 0.0)) <= 0.0: continue
		if str(effect.get("kind", "")) == "fire_spread" and str(effect.get("spell_id", "")) == "F11":
			_draw_link(effect, view)
		elif str(effect.get("kind", "")) == "cast" and str(effect.get("spell_id", "")) == "F11":
			var progress := 1.0 - float(effect.life) / maxf(0.000001, float(effect.max_life))
			var pos: Vector2 = snapshot.get("player", {}).get("pos", effect.pos)
			_surface(pos, 0.035, float(_config.cast_radius_m), 0, progress, 0.68, _seed(int(effect.seq)), view, true)
			_note("F11_cast")
	_draw_burns(snapshot, view)
	for item: Dictionary in _cooling.values():
		var progress := (now - float(item.time)) / float(_config.cooling_seconds)
		if progress >= 0.0 and progress < 1.0:
			_surface(item.pos, 0.10, float(item.radius), 4, progress, 0.38, float(item.seed), view)
			_note("F11_burn_cooling")
	_grounds.multimesh.visible_instance_count = _ground_count
	_bodies.multimesh.visible_instance_count = _body_count
	_bursts.multimesh.visible_instance_count = _burst_count
	visible = _ground_count > 0 or _body_count > 0 or _burst_count > 0


func _draw_mark(fact: Dictionary, view) -> void:
	var age := _clock - float(fact.time)
	if age < 0.0 or age >= float(_config.mark_seconds) or float(fact.contact.damage) <= 0.0: return
	if _marks.size() >= int(_config.mark_capacity):
		_overflow += 1
		return
	var progress := age / float(_config.mark_seconds)
	var level := clampi(int(fact.spell_level) - 1, 0, 2)
	var contact: Dictionary = fact.contact
	var alpha := 0.95 * (1.0 if bool(fact.natural) else float(_config.extra_alpha))
	_surface(contact.pos, 0.65, float(_config.mark_radii_m[level]), 1, progress, alpha, _seed(int(fact.seq)), view)
	_upright(contact.pos, 0.08, float(_config.mark_flame_heights_m[level]) * pow(1.0 - progress, 0.8), float(_config.mark_flame_width_m), alpha * (1.0 - progress), _seed(int(fact.seq)), view)
	_marks.append({"cast_id": fact.cast_id, "actor_id": contact.actor_id, "pos": contact.pos, "damage": contact.damage, "time": fact.time, "natural": fact.natural, "spell_level": fact.spell_level})
	_footprints.append({"kind": "brand_hit", "actor_id": contact.actor_id, "pos": contact.pos, "damage": contact.damage, "time": fact.time})
	_note("F11_mark")


func _curve_point(from: Vector2, to: Vector2, phase: float, seed: float) -> Dictionary:
	if phase <= 0.0: return {"pos": from, "height": float(_config.link_height_m)}
	if phase >= 1.0: return {"pos": to, "height": float(_config.link_height_m)}
	var axis := to - from
	var normal := Vector2(-axis.y, axis.x).normalized()
	var arch := sin(phase * PI)
	var bend := (seed - 0.5) * 2.0 * axis.length() * float(_config.link_curve_side_ratio)
	return {"pos": from.lerp(to, phase) + normal * bend * arch,
		"height": float(_config.link_height_m) + float(_config.link_curve_lift_m) * arch * (0.6 + seed * 0.4)}


func _draw_link(effect: Dictionary, view) -> void:
	var age := maxf(0.0, float(effect.max_life) - float(effect.life))
	if age >= float(_config.link_seconds): return
	if _links.size() >= int(_config.link_capacity):
		_overflow += 1
		return
	var from: Vector2 = effect.from
	var to: Vector2 = effect.to
	var seed := _seed(int(effect.seq))
	var progress := age / float(_config.link_seconds)
	var alpha := float(_config.link_alpha) * pow(1.0 - progress, 1.15)
	var count := int(_config.reduced_link_segments) if _reduced else int(_config.link_segments)
	var points: Array = []
	for index in range(count + 1): points.append(_curve_point(from, to, float(index) / float(count), seed))
	for index in count:
		var a: Vector2 = view.screen_position(points[index].pos, points[index].height)
		var b: Vector2 = view.screen_position(points[index + 1].pos, points[index + 1].height)
		var along := b - a
		if along.length_squared() < 0.000001: continue
		if _burst_count >= int(_config.surface_capacity):
			_overflow += 1
			break
		var midpoint: Vector2 = (points[index].pos + points[index + 1].pos) * 0.5
		var radius := float(_config.link_half_width_m) * (0.75 + 0.25 * sin(float(index + 1) / float(count + 1) * PI))
		var width := _radius(midpoint, radius, float(_config.link_height_m), view) * 2.0
		var normal := Vector2(-along.y, along.x).normalized()
		var transform := Transform2D(along * 1.08, normal * width * 3.0, (a + b) * 0.5)
		_bursts.multimesh.set_instance_transform_2d(_burst_count, transform)
		_bursts.multimesh.set_instance_custom_data(_burst_count, Color((float(index) + 0.5) / float(count), progress, 3.0 / 8.0, alpha))
		_link_transforms.append(transform)
		_burst_count += 1
	# The whole link and destination ignition exist on the original effect time.
	_upright(to, 0.08, float(_config.link_tip_height_m) * (1.0 - progress), float(_config.burn_flame_width_m), alpha * 0.66, seed, view)
	_links.append({"seq": effect.seq, "actor_id": effect.actor_id, "from": from, "to": to, "points": points, "time": _clock - age, "progress": progress})
	_footprints.append({"kind": "brand_spread", "actor_id": effect.actor_id, "from": from, "to": to, "time": _clock - age})
	_note("F11_spread")


func _note(kind: String) -> void: _coverage[kind] = int(_coverage.get(kind, 0)) + 1


func _reset_geometry() -> void:
	_body_count = 0
	_ground_count = 0
	_burst_count = 0
	_overflow = 0
	_coverage.clear()
	_footprints.clear()
	_marks.clear()
	_links.clear()
	_link_transforms.clear()
	_ground_transforms.clear()


func _clear() -> void:
	_reset_geometry()
	_burns.clear()
	_cooling.clear()
	if _available:
		for node in [_grounds, _bodies, _bursts]: node.multimesh.visible_instance_count = 0
	visible = false


func get_debug_state() -> Dictionary:
	return {"available": _available, "clock": _clock, "revision": _revision, "coverage": _coverage.duplicate(true), "footprints": _footprints.duplicate(true),
		"marks": _marks.duplicate(true), "links": _links.duplicate(true), "burns": _burns.duplicate(true), "cooling": _cooling.duplicate(true),
		"ground_transforms": _ground_transforms.duplicate(), "link_transforms": _link_transforms.duplicate(),
		"ground_instances": _ground_count, "body_instances": _body_count, "burst_instances": _burst_count, "overflow": _overflow,
		"batch_nodes": get_child_count(), "material_count": 2}


func _valid_config(cfg: Dictionary) -> bool:
	if int(cfg.get("version", 0)) != 1: return false
	for key in ["surface_capacity", "flame_capacity", "cooling_capacity", "mark_capacity", "link_capacity", "mark_seconds", "mark_radii_m", "mark_flame_heights_m", "mark_flame_width_m", "cast_radius_m", "link_seconds", "link_height_m", "link_curve_lift_m", "link_curve_side_ratio", "link_half_width_m", "link_segments", "reduced_link_segments", "link_alpha", "link_tip_height_m", "extra_alpha", "body_axes", "core_axes", "quad_radii", "rear_stretch", "flow_speed", "ignite_seconds", "burn_flames", "burn_flame_height_m", "burn_flame_width_m", "burn_alpha", "source_fade_seconds", "cooling_seconds", "edge_color", "shell_color", "energy_color", "core_color"]:
		if not cfg.has(key): return false
	for key in cfg:
		if key in ["version", "scope"]: continue
		var value: Variant = cfg[key]
		if value is Array:
			var count := 3 if key in ["mark_radii_m", "mark_flame_heights_m"] else 2 if key in ["body_axes", "core_axes"] else 4
			if value.size() != count: return false
			for part in value:
				if not (part is int or part is float) or not is_finite(float(part)) or float(part) < 0.0: return false
		elif not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0.0: return false
	return true


func _draw_burns(snapshot: Dictionary, view) -> void:
	var actors: Dictionary = {}
	for actor: Dictionary in snapshot.get("actors", []): actors[int(actor.id)] = actor
	var all_live: Dictionary = {}
	var owned: Dictionary = {}
	for burn: Dictionary in snapshot.get("spell_burns", []):
		var id := int(burn.actor_id)
		all_live[id] = true
		if str(burn.get("source", "")) != "F11" or not actors.has(id) or float(actors[id].health) <= 0.0 or float(burn.remaining) <= 0.0: continue
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
			_surface(actor.pos, 0.36, float(actor.radius) * 1.2, 2, (_clock - born) / float(_config.ignite_seconds), 0.48, _seed(id), view)
			_note("F11_ignited")
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
		if str(effect.get("kind", "")) == "fire_ignited" and str(effect.get("source", "")) == "F11" and int(effect.get("actor_id", -1)) == id:
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
	if ground: _ground_transforms.append(transform)
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
