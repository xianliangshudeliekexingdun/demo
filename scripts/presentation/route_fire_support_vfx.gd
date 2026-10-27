extends Node2D
## Existing F10 shield_restore and successful F02 reward effects only.
## No ownership inference from appearance, and no new gameplay records.
const CONFIG_PATH := "res://data/fire_support_vfx.json"
const SURFACE_SHADER = preload("res://scripts/presentation/fire_support_surface.gdshader")
const BODY_SHADER = preload("res://scripts/presentation/fire_bolt_body.gdshader")
var _config: Dictionary = {}
var _available := false
var _clock := 0.0
var _revision := -1
var _reduced := false
var _coverage: Dictionary = {}
var _footprints: Array = []
var _restores: Array = []
var _mastery: Array = []
var _sparks: Array = []
var _transforms: Array[Transform2D] = []
var _surface_count := 0
var _body_count := 0
var _spark_count := 0
var _overflow := 0
var _surfaces: MultiMeshInstance2D
var _bodies: MultiMeshInstance2D
var _spark_batch: MultiMeshInstance2D
var _surface_material: ShaderMaterial
var _body_material: ShaderMaterial


func _ready() -> void:
	name = "FireSupportFullChain"
	set_process(false)
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not loaded is Dictionary or not _valid_config(loaded):
		push_error("Invalid F10/F02 visual configuration; keeping legacy support drawing.")
		return
	_config = loaded
	_surface_material = _material(SURFACE_SHADER)
	_body_material = _material(BODY_SHADER)
	_body_material.set_shader_parameter("body_axes", Vector2(_config.body_axes[0], _config.body_axes[1]))
	_body_material.set_shader_parameter("core_axes", Vector2(_config.core_axes[0], _config.core_axes[1]))
	_surfaces = _batch("TransientWarmArcsAndMasterySeals", _surface_material, int(_config.surface_capacity))
	_bodies = _batch("SmallGatheringFlames", _body_material, int(_config.flame_capacity))
	_spark_batch = _batch("InwardWarmSparks", _surface_material, int(_config.spark_capacity))
	_available = true
	visible = false


func is_available() -> bool: return _available


func supports_snapshot(snapshot: Dictionary) -> bool:
	return _available and snapshot.has_all(["player", "effects", "spells"]) and snapshot.player.has_all(["pos", "health", "shield", "max_shield"])


func sync_snapshot(snapshot: Dictionary, view, options: Dictionary = {}) -> void:
	if not _available: return
	var now := float(snapshot.get("time", 0.0))
	var revision := int(snapshot.get("room_revision", 0))
	if now < _clock - 0.000001 or revision != _revision: _clear()
	_clock = now
	_revision = revision
	if not supports_snapshot(snapshot) or str(snapshot.get("phase", "")) not in ["combat", "exit", "pickup", "reward", "artifact", "shop", "shopping"] or float(snapshot.player.get("health", 0.0)) <= 0.0:
		_clear()
		return
	_reduced = bool(options.get("reduced_motion", false))
	for mat in [_surface_material, _body_material]:
		mat.set_shader_parameter("core_time", now)
		mat.set_shader_parameter("reduced_motion", _reduced)
	_reset_geometry()
	var mastery_level := 0
	for spell: Dictionary in snapshot.spells:
		if str(spell.id) == "F02": mastery_level = clampi(int(spell.level), 1, 3)
	var best: Dictionary = {}
	var best_alpha := -1.0
	for effect: Dictionary in snapshot.effects:
		if float(effect.get("life", 0.0)) <= 0.0: continue
		var kind := str(effect.get("kind", ""))
		var source := str(effect.get("spell_id", ""))
		var age := maxf(0.0, float(effect.max_life) - float(effect.life))
		if kind == "shield_restore" and source == "F10" and float(effect.get("amount", 0.0)) > 0.0 and age < float(_config.guard_seconds):
			if _restores.size() >= int(_config.event_capacity):
				_overflow += 1
				continue
			var strength := clampf(float(effect.amount) / maxf(0.000001, float(snapshot.player.max_shield)), 0.0, 1.0)
			var progress := age / float(_config.guard_seconds)
			_restores.append({"seq": effect.seq, "amount": effect.amount, "strength": strength, "progress": progress, "time": now - age})
			_footprints.append({"kind": "F10_restore", "amount": effect.amount, "pos": snapshot.player.pos, "time": now - age})
			_note("F10_restore")
			var alpha := (0.50 + sqrt(strength) * 0.50) * (1.0 - smoothstep(0.48, 1.0, progress))
			if alpha > best_alpha:
				best_alpha = alpha
				best = {"progress": progress, "strength": strength, "alpha": alpha, "seed": _seed(int(effect.seq))}
		elif kind == "cast" and source == "F10" and str(snapshot.phase) == "combat":
			_draw_cast(effect, snapshot.player.pos, view)
		elif kind == "reward" and source == "F02" and mastery_level > 0 and age < float(_config.mastery_seconds):
			_draw_mastery(effect, mastery_level, age, snapshot.player.pos, view)
	if not best.is_empty(): _draw_guard(best, snapshot.player, view)
	_surfaces.multimesh.visible_instance_count = _surface_count
	_bodies.multimesh.visible_instance_count = _body_count
	_spark_batch.multimesh.visible_instance_count = _spark_count
	visible = _surface_count > 0 or _body_count > 0 or _spark_count > 0


func _draw_cast(effect: Dictionary, pos: Vector2, view) -> void:
	var progress := 1.0 - float(effect.life) / maxf(0.000001, float(effect.max_life))
	_disc(pos, float(_config.cast_radius_m), 0, progress, 0.58, _seed(int(effect.seq)), view)
	for side in [-1, 1]:
		var at := pos + Vector2(float(side) * 0.18 * (1.0 - progress * 0.6), 0.0)
		_upright(at, 0.70, float(_config.cast_flame_height_m), float(_config.cast_flame_width_m), 0.30 + progress * 0.25, _seed(int(effect.seq) + side), view)
	_note("F10_cast")


func _draw_guard(state: Dictionary, player: Dictionary, view) -> void:
	var pos: Vector2 = player.pos
	var progress := float(state.progress)
	var alpha := float(_config.guard_alpha) * float(state.alpha)
	# A completed restoration flash is truthful even if the new shield was hit.
	_disc(pos, 0.48, 0, progress, alpha * pow(1.0 - progress, 2.0) * 0.65, float(state.seed), view)
	if float(player.shield) > 0.0:
		var opening := 0.90 + smoothstep(0.0, 0.16, progress) * 0.10
		_card(pos, float(_config.guard_base_m), float(_config.guard_width_m) * opening, float(_config.guard_height_m), 1, progress, alpha, float(state.strength), view)
		_note("F10_guard")
		if not _reduced: _draw_sparks(pos, progress, alpha * 0.80, int(_config.guard_sparks), float(state.seed), "F10", view)
	else:
		_note("F10_spent_flash")


func _draw_mastery(effect: Dictionary, level: int, age: float, pos: Vector2, view) -> void:
	if _mastery.size() >= int(_config.event_capacity):
		_overflow += 1
		return
	var progress := age / float(_config.mastery_seconds)
	var alpha := float(_config.mastery_alpha) * (1.0 - smoothstep(0.38, 1.0, progress))
	_disc(pos, float(_config.mastery_radius_m), 2, progress, alpha, float(level - 1) / 2.0, view)
	_upright(pos, 0.10, 0.32 + float(level) * 0.06, 0.17, alpha * (1.0 - progress), _seed(int(effect.seq)), view)
	if not _reduced: _draw_sparks(pos, progress, alpha * 0.70, int(_config.mastery_sparks_by_level[level - 1]), _seed(int(effect.seq)), "F02", view)
	_mastery.append({"seq": effect.seq, "level": level, "pos": pos, "progress": progress, "time": _clock - age})
	_footprints.append({"kind": "F02_reward", "level": level, "pos": pos, "time": _clock - age})
	_note("F02_learn" if level == 1 else "F02_upgrade")


func _draw_sparks(pos: Vector2, progress: float, alpha: float, count: int, seed: float, source: String, view) -> void:
	for index in count:
		var varied := _seed(index * 59 + int(seed * 1000.0))
		var local_progress := clampf(progress * (0.85 + varied * 0.30) - varied * 0.08, 0.0, 1.0)
		var angle := varied * TAU + sin(local_progress * PI) * (varied - 0.5) * 0.45
		var radius := lerpf(float(_config.spark_start_radius_m), float(_config.spark_finish_radius_m), local_progress)
		var at := pos + Vector2.from_angle(angle) * radius
		var height := 0.12 + float(_config.spark_lift_m) * local_progress * (0.55 + varied * 0.45)
		var strength := alpha * smoothstep(0.0, 0.10, local_progress) * (1.0 - smoothstep(0.60, 1.0, local_progress))
		if strength <= 0.00001: continue
		if _spark_count >= int(_config.spark_capacity):
			_overflow += 1
			break
		var center: Vector2 = view.screen_position(at, height)
		var size := _radius(at, float(_config.spark_radius_m), height, view) * (1.1 + varied * 0.7)
		var transform := Transform2D(Vector2.RIGHT * size * 2.0, Vector2.DOWN * size * 3.4, center)
		_spark_batch.multimesh.set_instance_transform_2d(_spark_count, transform)
		_spark_batch.multimesh.set_instance_custom_data(_spark_count, Color(varied, local_progress, 3.0 / 8.0, strength))
		_transforms.append(transform)
		_spark_count += 1
		_sparks.append({"source": source, "pos": at, "height": height, "progress": local_progress, "alpha": strength})


func _disc(pos: Vector2, radius: float, mode: int, progress: float, alpha: float, seed: float, view) -> void:
	var center: Vector2 = view.screen_position(pos, 0.035)
	var transform := Transform2D(view.screen_position(pos + Vector2(radius * 2.0, 0), 0.035) - center, view.screen_position(pos + Vector2(0, radius * 2.0), 0.035) - center, center)
	_submit(transform, Color(seed, progress, float(mode) / 8.0, alpha))


func _card(pos: Vector2, base: float, width: float, height: float, mode: int, progress: float, alpha: float, seed: float, view) -> void:
	var bottom: Vector2 = view.screen_position(pos, base)
	var top: Vector2 = view.screen_position(pos, base + height)
	var up := top - bottom
	var across := Vector2(-up.y, up.x).normalized()
	var screen_width := _radius(pos, width, base, view)
	_submit(Transform2D(across * screen_width, -up, (top + bottom) * 0.5), Color(seed, progress, float(mode) / 8.0, alpha))


func _submit(transform: Transform2D, data: Color) -> void:
	if _surface_count >= int(_config.surface_capacity):
		_overflow += 1
		return
	_surfaces.multimesh.set_instance_transform_2d(_surface_count, transform)
	_surfaces.multimesh.set_instance_custom_data(_surface_count, data)
	_transforms.append(transform)
	_surface_count += 1


func _note(kind: String) -> void: _coverage[kind] = int(_coverage.get(kind, 0)) + 1


func _reset_geometry() -> void:
	_surface_count = 0
	_body_count = 0
	_spark_count = 0
	_overflow = 0
	_coverage.clear()
	_footprints.clear()
	_restores.clear()
	_mastery.clear()
	_sparks.clear()
	_transforms.clear()


func _clear() -> void:
	_reset_geometry()
	if _available:
		for node in [_surfaces, _bodies, _spark_batch]: node.multimesh.visible_instance_count = 0
	visible = false


func get_debug_state() -> Dictionary:
	return {"available": _available, "clock": _clock, "revision": _revision, "coverage": _coverage.duplicate(true), "footprints": _footprints.duplicate(true),
		"restores": _restores.duplicate(true), "mastery": _mastery.duplicate(true), "sparks": _sparks.duplicate(true), "transforms": _transforms.duplicate(),
		"surface_instances": _surface_count, "body_instances": _body_count, "spark_instances": _spark_count, "overflow": _overflow,
		"batch_nodes": get_child_count(), "material_count": 2}


func _valid_config(cfg: Dictionary) -> bool:
	if int(cfg.get("version", 0)) != 1: return false
	if not cfg.has_all(["surface_capacity", "flame_capacity", "spark_capacity", "event_capacity", "cast_radius_m", "cast_flame_height_m", "cast_flame_width_m", "guard_seconds", "guard_width_m", "guard_height_m", "guard_base_m", "guard_alpha", "guard_sparks", "mastery_seconds", "mastery_radius_m", "mastery_alpha", "mastery_sparks_by_level", "spark_radius_m", "spark_start_radius_m", "spark_finish_radius_m", "spark_lift_m", "body_axes", "core_axes", "quad_radii", "rear_stretch", "flow_speed", "edge_color", "shell_color", "energy_color", "core_color", "guard_color"]): return false
	for key in cfg:
		if key in ["version", "scope"]: continue
		var value: Variant = cfg[key]
		if value is Array:
			var count := 3 if key == "mastery_sparks_by_level" else 2 if key in ["body_axes", "core_axes"] else 4
			if value.size() != count: return false
			for part in value:
				if not (part is int or part is float) or not is_finite(float(part)) or float(part) < 0.0: return false
		elif not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0.0: return false
	return true


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
