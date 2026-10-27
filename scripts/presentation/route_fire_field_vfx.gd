extends Node2D
## F06 consumes real fields, contact/maturity facts and actual bonus/grace/overlap state.
## Runes, charge, flames and cooling never grant a bonus or advance an attack.
const CONFIG_PATH := "res://data/fire_field_vfx.json"
const SURFACE_SHADER = preload("res://scripts/presentation/fire_field_surface.gdshader")
const BODY_SHADER = preload("res://scripts/presentation/fire_bolt_body.gdshader")
var _config: Dictionary = {}
var _available := false
var _clock := 0.0
var _revision := -1
var _reduced := false
var _coverage: Dictionary = {}
var _footprints: Array = []
var _fields: Array = []
var _flames: Array = []
var _embers: Array = []
var _ground_transforms: Array[Transform2D] = []
var _ember_transforms: Array[Transform2D] = []
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
	name = "FireFieldFullChain"
	set_process(false)
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not loaded is Dictionary or not _valid_config(loaded):
		push_error("Invalid F06 visual configuration; keeping legacy field drawing.")
		return
	_config = loaded
	_body_material = _material(BODY_SHADER)
	_body_material.set_shader_parameter("body_axes", Vector2(_config.body_axes[0], _config.body_axes[1]))
	_body_material.set_shader_parameter("core_axes", Vector2(_config.core_axes[0], _config.core_axes[1]))
	_surface_material = _material(SURFACE_SHADER)
	_grounds = _batch("FixedRunesAndRealBonusOverlap", _surface_material, int(_config.surface_capacity))
	_bodies = _batch("LowFieldFlamesAndSourceBurns", _body_material, int(_config.flame_capacity))
	_bursts = _batch("TrueReleaseContactsMaturityAndCooling", _surface_material, int(_config.surface_capacity))
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
	if str(snapshot.get("phase", "")) != "combat" or not snapshot.has_all(["fire_field_facts", "fire_field_state"]):
		_clear()
		return
	_reduced = bool(options.get("reduced_motion", false))
	for mat in [_body_material, _surface_material]:
		mat.set_shader_parameter("core_time", now)
		mat.set_shader_parameter("reduced_motion", _reduced)
	_reset_geometry()
	for key in _cooling.keys():
		if now - float(_cooling[key].time) >= float(_config.cooling_seconds): _cooling.erase(key)
	for zone: Dictionary in snapshot.get("spell_zones", []):
		if str(zone.get("spell_id", "")) != "F06" or str(zone.get("kind", "")) != "field" or float(zone.get("remaining", 0.0)) <= 0.0 or float(zone.get("born_at", INF)) > now: continue
		if _fields.size() >= int(_config.field_capacity):
			_overflow += 1
			continue
		_draw_field(zone, snapshot.fire_field_state, view)
	_draw_facts(snapshot.fire_field_facts, view)
	_draw_statuses(snapshot, view)
	_draw_burns(snapshot, view)
	for effect: Dictionary in snapshot.get("effects", []):
		if str(effect.get("kind", "")) != "cast" or str(effect.get("spell_id", "")) != "F06" or float(effect.get("life", 0.0)) <= 0.0: continue
		var progress := 1.0 - float(effect.life) / maxf(0.000001, float(effect.max_life))
		_surface(snapshot.get("player", {}).get("pos", effect.pos), 0.035, float(_config.cast_radius_m), 1, progress, 0.65, _seed(int(effect.seq)), view, true)
		_note("F06_cast")
	for item: Dictionary in _cooling.values():
		var progress := (now - float(item.time)) / float(_config.cooling_seconds)
		if progress >= 0.0 and progress < 1.0:
			_surface(item.pos, 0.10, float(item.radius), 7, progress, 0.38, float(item.seed), view)
			_note("F06_burn_cooling")
	_grounds.multimesh.visible_instance_count = _ground_count
	_bodies.multimesh.visible_instance_count = _body_count
	_bursts.multimesh.visible_instance_count = _burst_count
	visible = _ground_count > 0 or _body_count > 0 or _burst_count > 0


func _draw_field(zone: Dictionary, state: Dictionary, view) -> void:
	var pos: Vector2 = zone.pos
	var radius := float(zone.radius)
	var age := float(zone.get("age", 0.0))
	var birth := clampf(age / float(_config.rune_reveal_seconds), 0.0, 1.0)
	var natural := bool(zone.context.get("natural", false))
	var level := clampi(int(zone.context.get("spell_level", 1)) - 1, 0, 2)
	var growth: Dictionary = zone.context.get("growth_level", {})
	var matured: bool = state.get("matured_casts", []).has(str(zone.context.cast_id))
	var charge := 0.0
	if natural and not matured and float(growth.get("mature_after", 0.0)) > 0.0 and float(growth.get("mature_coefficient", 0.0)) > 0.0:
		charge = clampf(age / float(growth.mature_after), 0.0, 1.0)
	var alpha := float(_config.field_alpha) * (1.0 if natural else float(_config.extra_alpha))
	# Mode 0 stores reveal progress in R; its geometry never rotates with time.
	# The complete, true outer boundary is visible even at reveal == 0.
	_surface(pos, 0.035, radius, 0, charge, alpha, birth, view, true)
	var count := 4 if _reduced else int(_config.field_flames_by_level[level])
	for index in count:
		var flame_seed := _seed(int(zone.id) * 31 + index * 73)
		var angle := float(index % 6) * TAU / 6.0 + (flame_seed - 0.5) * 0.26
		var radial := radius * ((0.39 if index % 4 == 3 else 0.64) + (flame_seed - 0.5) * 0.10)
		var anchor := pos + Vector2.from_angle(angle) * radial
		var cycle := lerpf(float(_config.field_flame_cycle_seconds[0]), float(_config.field_flame_cycle_seconds[1]), flame_seed)
		var progress := fposmod(age / cycle + _seed(index * 37 + int(zone.id) * 23), 1.0)
		var envelope := 0.65 if _reduced else smoothstep(0.0, 0.16, progress) * (1.0 - smoothstep(0.60, 1.0, progress))
		var sway := 0.0 if _reduced else sin(progress * TAU + flame_seed * TAU) * float(_config.field_flame_sway_m)
		var at := anchor + Vector2.from_angle(angle + PI * 0.5) * sway
		var height := float(_config.field_flame_height_m) * (0.55 + flame_seed * 0.65) * (0.35 + envelope * 0.65)
		var width := float(_config.field_flame_width_m) * (0.65 + _seed(index * 19 + int(zone.id) * 43) * 0.60)
		var flame_alpha := float(_config.field_flame_alpha) * alpha * envelope * birth
		_upright(at, 0.045, height, width, flame_alpha, flame_seed, view)
		_flames.append({"zone_id": zone.id, "index": index, "pos": at, "anchor": anchor, "height": height, "width": width, "alpha": flame_alpha, "cycle": cycle, "progress": progress})
	if not _reduced: _draw_field_embers(zone, level, alpha * birth, view)
	_fields.append({"zone_id": zone.id, "cast_id": zone.context.cast_id, "pos": pos, "radius": radius, "remaining": zone.remaining, "age": age, "charge": charge, "matured": matured, "natural": natural, "spell_level": level + 1, "rune_reveal": birth})
	_footprints.append({"kind": "field", "zone_id": zone.id, "pos": pos, "radius": radius, "remaining": zone.remaining})
	_note("F06_field")
	if charge > 0.0: _note("F06_charge")


func _draw_field_embers(zone: Dictionary, level: int, alpha: float, view) -> void:
	var age := float(zone.get("age", 0.0))
	var radius := float(zone.radius)
	for index in int(_config.field_embers_by_level[level]):
		var seed := _seed(int(zone.id) * 41 + index * 97)
		var cycle := lerpf(float(_config.ember_cycle_seconds[0]), float(_config.ember_cycle_seconds[1]), seed)
		var progress := fposmod(age / cycle + _seed(int(zone.id) * 17 + index * 53), 1.0)
		var angle := float((index * 5) % 6) * TAU / 6.0 + (seed - 0.5) * 0.22
		var radial := radius * ((0.39 if index % 4 == 3 else 0.64) + (seed - 0.5) * 0.12)
		var anchor: Vector2 = zone.pos + Vector2.from_angle(angle) * radial
		var tangent := Vector2.from_angle(angle + (PI * 0.5 if index % 2 == 0 else -PI * 0.5))
		var bend := Vector2.from_angle(seed * TAU)
		var drift := radius * float(_config.ember_drift_ratio)
		var at := anchor + tangent * drift * progress + bend * drift * sin(progress * PI) * 0.45
		var lift := lerpf(float(_config.ember_lift_m[0]), float(_config.ember_lift_m[1]), _seed(index * 31 + int(zone.id) * 67))
		var height := 0.055 + lift * pow(progress, 0.8)
		var previous := maxf(0.0, progress - 0.10)
		var previous_at := anchor + tangent * drift * previous + bend * drift * sin(previous * PI) * 0.45
		var previous_height := 0.055 + lift * pow(previous, 0.8)
		var size := lerpf(float(_config.ember_radius_m[0]), float(_config.ember_radius_m[1]), _seed(index * 47 + int(zone.id) * 13))
		var ember_alpha := float(_config.ember_alpha) * alpha * smoothstep(0.0, 0.12, progress) * (1.0 - smoothstep(0.54, 1.0, progress))
		_ember(at, height, previous_at, previous_height, size, progress, ember_alpha, seed, view)
		_embers.append({"phase": "field", "zone_id": zone.id, "index": index, "pos": at, "anchor": anchor, "height": height, "radius": size, "alpha": ember_alpha, "progress": progress, "cycle": cycle})
	_note("F06_embers")


func _draw_facts(facts: Array, view) -> void:
	for fact: Dictionary in facts:
		var age := _clock - float(fact.time)
		if age < 0.0: continue
		var seed := _seed(int(fact.seq))
		match str(fact.phase):
			"release":
				if age >= float(_config.birth_seconds): continue
				_surface(fact.pos, 0.04, float(_config.release_radius_m), 1, age / float(_config.birth_seconds), 0.75, seed, view, true)
				_note("F06_release")
			"hit":
				var hit: Dictionary = fact.contact
				if age >= float(_config.hit_seconds) or float(hit.damage) <= 0.0: continue
				_surface(hit.pos, 0.38, float(hit.radius) * float(_config.hit_radius_ratio), 2, age / float(_config.hit_seconds), 0.70, seed, view)
				_footprints.append({"kind": "field_hit", "actor_id": hit.actor_id, "zone_id": fact.zone_id, "pos": hit.pos, "damage": hit.damage, "time": fact.time})
				_note("F06_hit")
			"mature":
				if age >= float(_config.mature_seconds): continue
				var progress := age / float(_config.mature_seconds)
				_surface(fact.pos, 0.06, float(fact.radius), 5, progress, 0.92, seed, view, true)
				for index in (3 if _reduced else int(_config.mature_flames)):
					var s := _seed(int(fact.seq) * 13 + index * 41)
					var at: Vector2 = fact.pos + Vector2.from_angle(s * TAU) * float(fact.radius) * (0.18 + sqrt(progress) * 0.65)
					_upright(at, 0.045, float(_config.mature_flame_height_m) * pow(1.0 - progress, 0.9), float(_config.mature_flame_width_m), 0.84 * (1.0 - progress), s, view)
				if not _reduced:
					for index in int(_config.mature_embers):
						var s := _seed(int(fact.seq) * 19 + index * 47)
						var at: Vector2 = fact.pos + Vector2.from_angle(s * TAU) * float(fact.radius) * (0.16 + sqrt(progress) * 0.60)
						var height := 0.06 + sin(progress * PI * 0.5) * (0.22 + s * 0.60)
						_ember(at, height, fact.pos, 0.06, float(_config.ember_radius_m[1]), progress, 0.85 * sin(progress * PI) * (1.0 - progress), s, view)
						_embers.append({"phase": "mature", "cast_id": fact.cast_id, "pos": at, "height": height, "progress": progress})
				_footprints.append({"kind": "field_mature", "cast_id": fact.cast_id, "pos": fact.pos, "radius": fact.radius, "time": fact.time})
				_note("F06_mature")
			"end", "replace":
				if age >= float(_config.end_seconds): continue
				_surface(fact.pos, 0.035, float(fact.radius) * float(_config.end_radius_ratio), 7, age / float(_config.end_seconds), 0.45, seed, view, true)
				_note("F06_" + str(fact.phase))


func _draw_statuses(snapshot: Dictionary, view) -> void:
	var state: Dictionary = snapshot.fire_field_state
	if float(state.get("attack_bonus", 0.0)) > 0.0:
		var inside := bool(state.get("inside", false))
		var remaining := float(state.get("grace_remaining", 0.0))
		var alpha := float(_config.bonus_alpha) if inside else float(_config.grace_alpha) * clampf(remaining / float(_config.grace_fade_seconds), 0.0, 1.0)
		var pos: Vector2 = snapshot.get("player", {}).get("pos", Vector2.ZERO)
		_surface(pos, 0.055, float(_config.bonus_radius_m), 3, 0.0, alpha, 0.31, view, true)
		_footprints.append({"kind": "field_bonus", "pos": pos, "bonus": state.attack_bonus, "inside": inside, "grace_remaining": remaining})
		_note("F06_bonus" if inside else "F06_grace")
	for item: Dictionary in state.get("vulnerable", []):
		_surface(item.pos, 0.04, float(item.radius) * float(_config.vulnerability_radius_ratio), 4, 0.0, float(_config.vulnerability_alpha), _seed(int(item.actor_id)), view, true)
		_footprints.append({"kind": "field_overlap", "actor_id": item.actor_id, "pos": item.pos, "bonus": item.bonus})
		_note("F06_overlap")


func _note(kind: String) -> void: _coverage[kind] = int(_coverage.get(kind, 0)) + 1


func _reset_geometry() -> void:
	_body_count = 0
	_ground_count = 0
	_burst_count = 0
	_overflow = 0
	_coverage.clear()
	_footprints.clear()
	_fields.clear()
	_flames.clear()
	_embers.clear()
	_ground_transforms.clear()
	_ember_transforms.clear()


func _clear() -> void:
	_reset_geometry()
	_burns.clear()
	_cooling.clear()
	if _available:
		for node in [_grounds, _bodies, _bursts]: node.multimesh.visible_instance_count = 0
	visible = false


func get_debug_state() -> Dictionary:
	return {"available": _available, "clock": _clock, "revision": _revision, "coverage": _coverage.duplicate(true), "footprints": _footprints.duplicate(true),
		"fields": _fields.duplicate(true), "flames": _flames.duplicate(true), "embers": _embers.duplicate(true), "burns": _burns.duplicate(true), "cooling": _cooling.duplicate(true),
		"ground_transforms": _ground_transforms.duplicate(),
		"ember_transforms": _ember_transforms.duplicate(), "visual_revision": int(_config.get("visual_revision", 0)),
		"ground_instances": _ground_count, "body_instances": _body_count, "burst_instances": _burst_count, "overflow": _overflow,
		"batch_nodes": get_child_count(), "material_count": 2}


func _draw_burns(snapshot: Dictionary, view) -> void:
	var actors: Dictionary = {}
	for actor: Dictionary in snapshot.get("actors", []): actors[int(actor.id)] = actor
	var all_live: Dictionary = {}
	var owned: Dictionary = {}
	for burn: Dictionary in snapshot.get("spell_burns", []):
		var id := int(burn.actor_id)
		all_live[id] = true
		if str(burn.get("source", "")) != "F06" or not actors.has(id) or float(actors[id].health) <= 0.0 or float(burn.remaining) <= 0.0: continue
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
			_note("F06_ignited")
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
		if str(effect.get("kind", "")) == "fire_ignited" and str(effect.get("source", "")) == "F06" and int(effect.get("actor_id", -1)) == id:
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


func _ember(pos: Vector2, height: float, previous: Vector2, previous_height: float, radius: float, progress: float, alpha: float, seed: float, view) -> void:
	if alpha <= 0.00001: return
	if _burst_count >= int(_config.surface_capacity):
		_overflow += 1
		return
	var center: Vector2 = view.screen_position(pos, height)
	var along: Vector2 = center - view.screen_position(previous, previous_height)
	if along.length_squared() < 0.000001: along = Vector2.UP
	along = along.normalized()
	var across := Vector2(-along.y, along.x)
	var width := _radius(pos, radius, height, view) * 2.0
	var length := _radius(pos, float(_config.ember_trail_m), height, view) * (0.65 + seed * 0.55)
	var transform := Transform2D(across * width, along * length, center)
	_bursts.multimesh.set_instance_transform_2d(_burst_count, transform)
	_bursts.multimesh.set_instance_custom_data(_burst_count, Color(seed, progress, 1.0, alpha))
	_ember_transforms.append(transform)
	_burst_count += 1


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


func _valid_config(cfg: Dictionary) -> bool:
	if int(cfg.get("version", 0)) != 1 or not cfg.has_all(["version", "scope", "field_capacity", "surface_capacity", "flame_capacity", "cooling_capacity", "field_alpha", "field_flames_by_level", "field_flame_height_m", "field_flame_width_m", "field_flame_alpha", "birth_seconds", "cast_radius_m", "release_radius_m", "hit_seconds", "hit_radius_ratio", "mature_seconds", "mature_flames", "mature_flame_height_m", "mature_flame_width_m", "end_seconds", "end_radius_ratio", "bonus_radius_m", "bonus_alpha", "grace_alpha", "grace_fade_seconds", "vulnerability_radius_ratio", "vulnerability_alpha", "body_axes", "core_axes", "quad_radii", "rear_stretch", "flow_speed", "ignite_seconds", "burn_flames", "burn_flame_height_m", "burn_flame_width_m", "burn_alpha", "source_fade_seconds", "cooling_seconds", "extra_alpha", "edge_color", "shell_color", "energy_color", "core_color", "buff_color"]): return false
	if int(cfg.get("visual_revision", 0)) != 2 or not cfg.has_all(["rune_reveal_seconds", "rune_line_width", "rune_flow_speed", "rune_glow_strength", "field_flame_cycle_seconds", "field_flame_sway_m", "field_embers_by_level", "ember_cycle_seconds", "ember_lift_m", "ember_radius_m", "ember_trail_m", "ember_drift_ratio", "ember_alpha", "mature_embers", "rune_color", "rune_hot_color", "rune_glow_color", "ember_color"]): return false
	for key in cfg:
		if key in ["version", "scope"]: continue
		var value: Variant = cfg[key]
		if value is Array:
			var count := 3 if key in ["field_flames_by_level", "field_embers_by_level"] else 2 if key in ["body_axes", "core_axes", "field_flame_cycle_seconds", "ember_cycle_seconds", "ember_lift_m", "ember_radius_m"] else 4
			if value.size() != count: return false
			for part in value:
				if not (part is int or part is float) or not is_finite(float(part)) or float(part) < 0.0: return false
		elif not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0.0: return false
	return true
