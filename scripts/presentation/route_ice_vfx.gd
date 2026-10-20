extends Node3D
## Read-only cold magic batches. Snapshot clocks own every phase and lifetime.
const ICE_SHADER = preload("res://scripts/presentation/procedural_ice.gdshader")
const QUAD_LIMIT = 512
const CRYSTAL_LIMIT = 256
const HANDLED_EFFECTS = ["ice_frost", "ice_window", "ice_thawed", "ice_shatter", "ice_shard", "ice_ring", "ice_star", "ice_coffin", "ice_guard", "ice_guard_pulse", "ice_beam", "ice_bolt_hit", "ice_star_flight", "ice_coffin_flight", "ice_storm_wave", "ice_artifact_restore"]

var _quads: MultiMeshInstance3D
var _crystals: MultiMeshInstance3D
var _ice_material: ShaderMaterial
var _crystal_material: StandardMaterial3D
var _camera: Camera3D
var _clock: float = 0.0
var _reduced: bool = false
var _q: int = 0
var _c: int = 0
var _coverage: Dictionary = {}
var _footprints: Array = []
var _revision: int = -1


func _ready():
	name = "IceSpellVFX"
	set_meta("source", "original_procedural_ice_geometry_snapshot_only")
	_ice_material = ShaderMaterial.new()
	_ice_material.shader = ICE_SHADER
	_ice_material.render_priority = -5
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_quads = _make_batch("IceTracesAndStatus", quad, _ice_material, QUAD_LIMIT, true)
	var crystal := SphereMesh.new()
	crystal.radius = 0.5
	crystal.height = 1.0
	crystal.radial_segments = 4
	crystal.rings = 1
	_crystal_material = StandardMaterial3D.new()
	_crystal_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crystal_material.vertex_color_use_as_albedo = true
	_crystal_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crystal_material.emission_enabled = true
	_crystal_material.emission = Color(0.04, 0.10, 0.13)
	_crystals = _make_batch("IcePrisms", crystal, _crystal_material, CRYSTAL_LIMIT, false)
	set_process(false)


func sync_snapshot(snapshot: Dictionary, camera: Camera3D, options: Dictionary = {}):
	if not is_instance_valid(_quads):
		return
	_camera = camera
	_reduced = bool(options.get("reduced_motion", false))
	_clock = float(snapshot.get("ice_clock", snapshot.get("combat_time", snapshot.get("time", 0))))
	_revision = int(snapshot.get("room_revision", -1))
	_q = 0
	_c = 0
	_coverage.clear()
	_footprints.clear()
	_ice_material.set_shader_parameter("core_time", _clock)
	_ice_material.set_shader_parameter("reduced_motion", _reduced)
	if snapshot.get("phase", "") == "combat":
		var actors: Dictionary = {}
		for actor in snapshot.get("actors", []):
			actors[int(actor.id)] = actor
		for state in snapshot.get("ice_states", []):
			var actor: Dictionary = actors.get(int(state.get("actor_id", -1)), {})
			if not actor.is_empty() and float(actor.get("health", 0)) > 0:
				_status(actor, state)
		for bolt in snapshot.get("ice_projectiles", []):
			_bolt(bolt)
		for zone in snapshot.get("ice_zones", []):
			_zone(zone)
		var defense: Dictionary = snapshot.get("ice_defense", {})
		if float(defense.get("remaining", 0)) > 0:
			_guard(snapshot.get("player", {}).get("pos", Vector2.ZERO), 0.42, false)
			_note("ice_defense")
		for spell in snapshot.get("spells", []):
			if str(spell.get("id", "")) == "I10":
				_ground(snapshot.player.pos, 0.34, 5, 0.22)
				_note("I10_passive")
		for effect in snapshot.get("effects", []):
			_effect(effect, snapshot)
	_quads.multimesh.visible_instance_count = _q
	_crystals.multimesh.visible_instance_count = _c
	visible = _q > 0 or _c > 0


func get_debug_state() -> Dictionary:
	return {"quad_count": _q, "crystal_count": _c, "quad_limit": QUAD_LIMIT, "crystal_limit": CRYSTAL_LIMIT, "coverage": _coverage.duplicate(true), "footprints": _footprints.duplicate(true), "clock": _clock, "revision": _revision, "reduced_motion": _reduced, "material_count": 2, "batch_count": 2}


func _status(actor: Dictionary, state: Dictionary):
	var pos: Vector2 = actor.get("pos", Vector2.ZERO)
	var radius: float = maxf(0.25, float(actor.get("radius", 0.4)))
	if not _in_view(pos, radius):
		return
	var stage: String = str(state.get("stage", "none"))
	# Keep status glyphs above the existing 1.65/2.2-world-unit health bars.
	var head: float = maxf(2.65 if bool(actor.get("elite", false)) else 2.05, radius * 2.6 + 0.5)
	var opacity: float = clampf(float(state.get("remaining", 0)) / 0.25, 0.0, 1.0)
	if stage == "frozen":
		# Thin clear-center cage edges preserve the enemy and its red warning.
		_quad(_point(pos, 0.84), _billboard_basis(), Vector2(radius * 2.5, maxf(1.55, radius * 2.9)), 4, opacity * 0.72)
		_ground(pos, radius + 0.12, 0, opacity * 0.58)
		for index in 3:
			var offset := Vector2.from_angle(index * TAU / 3.0 + 0.4) * (radius + 0.08)
			_crystal(_point(pos + offset, 0.25), Vector3(0.13, 0.46, 0.13), 0.65)
		_quad(_point(pos, head), _billboard_basis(), Vector2(0.4, 0.44), 5, opacity * 0.95, 0.08)
		_note("ice_frozen_status")
	elif stage == "brittle":
		# A broken snow-crack above the body means an output window, not hard stop.
		_quad(_point(pos, head), _billboard_basis(), Vector2(0.60, 0.60), 5, opacity * 0.98, 0.39)
		_ground(pos, radius + 0.08, 5, opacity * 0.35, 0.39)
		_note("ice_brittle_status")
	elif stage == "frost":
		var stacks: int = clampi(int(state.get("stacks", 0)), 0, 3)
		for index in stacks:
			var center := _point(pos, head) + _billboard_basis().x * ((index - (stacks - 1) * 0.5) * 0.24)
			_quad(center, _billboard_basis(), Vector2(0.20, 0.30), 3, opacity * 0.98)
		_ground(pos, radius + 0.05, 0, opacity * 0.24)
		_note("ice_frost_status")
	elif float(state.get("slow_amount", 0)) > 0:
		_ground(pos, radius + 0.06, 0, 0.25)
		_note("ice_slow_status")
	if float(state.get("immunity_remaining", 0)) > 0:
		var badge_pos := _point(pos, head) + _billboard_basis().x * 0.52
		_quad(badge_pos, _billboard_basis(), Vector2(0.46, 0.42), 6, 0.98)
		_note("ice_immunity_status")
	if stage != "none" or float(state.get("immunity_remaining", 0)) > 0:
		_footprints.append({"kind": "ice_status", "actor_id": actor.get("id", -1), "pos": pos, "stage": stage, "stacks": state.get("stacks", 0), "freeze_remaining": state.get("freeze_remaining", 0), "immunity_remaining": state.get("immunity_remaining", 0)})


func _bolt(bolt: Dictionary):
	var pos: Vector2 = bolt.get("pos", Vector2.ZERO)
	var direction: Vector2 = bolt.get("direction", Vector2(0, 1))
	var radius: float = maxf(0.08, float(bolt.get("radius", 0.18)))
	if not _in_view(pos, 0.9):
		return
	_crystal(_point(pos, 0.66), Vector3(radius * 1.4, radius * 2.4, radius * 1.4), 0.92, _clock * 2.0 if not _reduced else 0.0)
	var tail: float = minf(float(bolt.get("travelled", 0)), 0.9)
	if tail > 0.01:
		_line(_point(pos - direction * tail, 0.66), _point(pos, 0.66), radius * 0.8, 0.7)
	_footprints.append({"kind": "ice_bolt", "pos": pos, "radius": radius})
	_note("ice_bolt")


func _zone(zone: Dictionary):
	var kind: String = str(zone.get("kind", ""))
	var alpha: float = minf(1.0, float(zone.get("remaining", 0)) / 0.25)
	if kind == "ice_domain":
		var pos: Vector2 = zone.get("pos", Vector2.ZERO)
		var radius: float = float(zone.get("radius", 0))
		_ground(pos, radius, 1, alpha * 0.62)
		var count: int = 4 if _reduced else 7
		for index in count:
			var offset := Vector2.from_angle(index * TAU / count + 0.2) * radius * 0.78
			_crystal(_point(pos + offset, 0.13), Vector3(0.10, 0.28, 0.10), alpha * 0.5)
		_footprints.append({"kind": kind, "pos": pos, "radius": radius})
	elif kind == "ice_storm":
		var from: Vector2 = zone.get("from", Vector2.ZERO)
		var to: Vector2 = zone.get("to", from)
		var width: float = float(zone.get("width", 0))
		_strip(from, to, width, 7, alpha * 0.45)
		var side: Vector2 = (to - from).normalized().orthogonal() * width * 0.43
		for index in 3:
			var center: Vector2 = from.lerp(to, (index + 0.5) / 3.0)
			for sign_value in [-1, 1]:
				_crystal(_point(center + side * sign_value, 0.12), Vector3(0.09, 0.28, 0.09), alpha * 0.45)
		_footprints.append({"kind": kind, "from": from, "to": to, "width": width})
	else:
		return
	_note(kind)


func _effect(effect: Dictionary, snapshot: Dictionary):
	var kind: String = str(effect.get("kind", ""))
	var ice_cast: bool = kind == "cast" and str(effect.get("spell_id", "")).begins_with("I")
	if kind not in HANDLED_EFFECTS and not ice_cast:
		return
	var alpha: float = clampf(float(effect.get("life", 0)) / maxf(0.001, float(effect.get("max_life", 0.1))), 0.0, 1.0)
	if alpha <= 0:
		return
	var progress: float = 1.0 - alpha
	var pos: Vector2 = effect.get("pos", Vector2.ZERO)
	var radius: float = float(effect.get("radius", 0.45))
	match kind:
		"cast":
			_ground(pos, 0.36, 5, alpha * 0.36)
			_quad(_point(pos, 0.85), _billboard_basis(), Vector2(0.18, 0.28), 3, alpha * 0.45)
		"ice_beam", "ice_storm_wave":
			var from: Vector2 = effect.get("from", pos)
			var to: Vector2 = effect.get("to", pos)
			var width: float = float(effect.get("width", 0.4))
			_strip(from, to, width, 2, alpha * 0.58)
			var count: int = 3 if _reduced else 7
			for index in count:
				var point: Vector2 = from.lerp(to, (index + 0.5) / count)
				_crystal(_point(point, 0.35), Vector3(0.12, 0.48, 0.12), alpha * 0.7, index * 0.7)
			_footprints.append({"kind": kind, "from": from, "to": to, "width": width})
		"ice_star_flight", "ice_coffin_flight":
			_ground(pos, radius, 0, 0.28)
			var height: float = 0.25 + alpha * 3.2
			_crystal(_point(pos, height), Vector3(0.26, 0.65, 0.26), 0.85)
			if kind == "ice_star_flight":
				_quad(_point(pos, height), _billboard_basis(), Vector2(0.62, 0.62), 5, 0.72)
		"ice_star", "ice_ring", "ice_guard_pulse":
			_ground(pos, radius * (0.45 + progress * 0.55), 0, alpha * 0.7)
			_ground(pos, radius, 1, alpha * 0.3)
			var count: int = 3 if _reduced else 6
			for index in count:
				var point := pos + Vector2.from_angle(index * TAU / count + 0.3) * radius * 0.7
				_crystal(_point(point, 0.20 + 0.22 * alpha), Vector3(0.13, 0.58 * alpha + 0.1, 0.13), alpha * 0.7, index)
			_footprints.append({"kind": kind, "pos": pos, "radius": radius})
		"ice_coffin":
			_quad(_point(pos, 0.95), _billboard_basis(), Vector2(0.95, 1.95), 4, alpha * 0.8)
			_ground(pos, radius, 0, alpha * 0.5)
		"ice_shatter":
			# Target-local break, no extra AoE ring around every frozen victim.
			_quad(_point(pos, 1.05), _billboard_basis(), Vector2(0.8, 0.9), 9, alpha * 0.9)
			var count: int = 4 if _reduced else 8
			for index in count:
				var angle: float = index * TAU / count
				var point := pos + Vector2.from_angle(angle) * (0.18 + progress * 0.55)
				_crystal(_point(point, 0.55 + sin(progress * PI) * 0.6), Vector3(0.10, 0.30, 0.10) * (0.8 + alpha * 0.2), alpha * 0.85, angle)
			_footprints.append({"kind": kind, "pos": pos, "actor_id": effect.get("actor_id", -1)})
		"ice_shard":
			var from: Vector2 = effect.get("from", pos)
			var to: Vector2 = effect.get("to", pos)
			_line(_point(from, 0.62), _point(to, 0.62), 0.065, alpha * 0.78)
			_quad(_point(to, 0.9), _billboard_basis(), Vector2(0.24, 0.34), 3, alpha * 0.85)
			_footprints.append({"kind": kind, "from": from, "to": to})
		"ice_frost", "ice_bolt_hit":
			_quad(_point(pos, 0.94), _billboard_basis(), Vector2(0.26, 0.38), 3, alpha * 0.65)
		"ice_window":
			_quad(_point(pos, 1.53), _billboard_basis(), Vector2(0.52, 0.52), 5, alpha * 0.8)
		"ice_thawed":
			_quad(_point(pos, 1.35), _billboard_basis(), Vector2(0.36, 0.36), 5, alpha * 0.55, 0.4)
		"ice_guard":
			_guard(snapshot.get("player", {}).get("pos", pos), alpha * 0.8, false)
		"ice_artifact_restore":
			if float(effect.get("amount", 0)) > 0:
				_guard(snapshot.get("player", {}).get("pos", pos), alpha * 0.95, true)
				_footprints.append({"kind": kind, "pos": pos, "amount": effect.get("amount", 0)})
	_note("ice_cast" if ice_cast else kind)


func _guard(pos: Vector2, alpha: float, restoring: bool):
	var basis := _billboard_basis()
	for side in [-1, 1]:
		var center: Vector3 = _point(pos, 0.98) + basis.x * (float(side) * 0.48)
		_quad(center, basis, Vector2(0.65, 1.18), 8, alpha, 0.0 if side < 0 else 1.0)
	if restoring:
		_quad(_point(pos, 1.68), basis, Vector2(0.32, 0.32), 5, alpha)


func _ground(pos: Vector2, radius: float, mode: int, alpha: float, phase: float = 0):
	if radius > 0:
		_quad(_point(pos, 0.065), Basis(Vector3.RIGHT, Vector3(0, 0, -1), Vector3.UP), Vector2.ONE * radius * 2.0, mode, alpha, phase)


func _strip(from: Vector2, to: Vector2, width: float, mode: int, alpha: float):
	var start := _point(from, 0.07)
	var finish := _point(to, 0.07)
	var length: float = start.distance_to(finish)
	if length <= 0.001:
		return
	var x: Vector3 = (finish - start).normalized()
	var y: Vector3 = Vector3.UP.cross(x).normalized()
	_quad((start + finish) * 0.5, Basis(x, y, x.cross(y)), Vector2(length, width), mode, alpha)


func _line(from: Vector3, to: Vector3, width: float, alpha: float):
	var length: float = from.distance_to(to)
	if length <= 0.001:
		return
	var center := (from + to) * 0.5
	var x: Vector3 = (to - from).normalized()
	var facing: Vector3 = (_camera.global_position - center).normalized() if _camera != null else Vector3(0, 0.6, 0.8)
	var y: Vector3 = facing.cross(x).normalized()
	if y.length_squared() < 0.001:
		y = Vector3.UP
	_quad(center, Basis(x, y, x.cross(y)), Vector2(length, width), 2, alpha)


func _quad(pos: Vector3, basis: Basis, dimensions: Vector2, mode: int, alpha: float, phase: float = 0):
	if _q >= QUAD_LIMIT or alpha <= 0 or not _in_view(Vector2(pos.x, -pos.z), maxf(dimensions.x, dimensions.y) * 0.5):
		return
	_quads.multimesh.set_instance_transform(_q, Transform3D(Basis(basis.x * dimensions.x, basis.y * dimensions.y, basis.z), pos))
	_quads.multimesh.set_instance_color(_q, Color.WHITE)
	_quads.multimesh.set_instance_custom_data(_q, Color(float(mode) / 10.0, phase, alpha, 0.27))
	_q += 1


func _crystal(pos: Vector3, dimensions: Vector3, alpha: float, angle: float = 0):
	if _c >= CRYSTAL_LIMIT or alpha <= 0 or not _in_view(Vector2(pos.x, -pos.z), maxf(dimensions.x, dimensions.z)):
		return
	var basis := Basis(Vector3.UP, angle).scaled(dimensions)
	_crystals.multimesh.set_instance_transform(_c, Transform3D(basis, pos))
	_crystals.multimesh.set_instance_color(_c, Color(0.63, 0.87, 1.0, clampf(alpha, 0, 0.9)))
	_c += 1


func _make_batch(batch_name: String, mesh: Mesh, material: Material, limit: int, custom: bool) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.name = batch_name
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.use_custom_data = custom
	batch.mesh = mesh
	batch.instance_count = limit
	batch.visible_instance_count = 0
	batch.custom_aabb = AABB(Vector3(-60, -1, -60), Vector3(120, 24, 120))
	node.multimesh = batch
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _billboard_basis() -> Basis:
	if _camera == null:
		return Basis.IDENTITY
	var x: Vector3 = _camera.global_basis.x.normalized()
	return Basis(x, Vector3.UP, x.cross(Vector3.UP).normalized())


func _point(pos: Vector2, height: float) -> Vector3:
	return Vector3(pos.x, height, -pos.y)


func _in_view(pos: Vector2, radius: float) -> bool:
	if _camera == null:
		return true
	var point := _point(pos, 0.8)
	if _camera.is_position_behind(point):
		return false
	var rect := Rect2(Vector2.ZERO, _camera.get_viewport().get_visible_rect().size)
	var projected := _camera.unproject_position(point)
	var margin: float = projected.distance_to(_camera.unproject_position(point + Vector3(radius, 0, 0))) + 42.0
	return rect.grow(margin).has_point(projected)


func _note(kind: String):
	_coverage[kind] = int(_coverage.get(kind, 0)) + 1

