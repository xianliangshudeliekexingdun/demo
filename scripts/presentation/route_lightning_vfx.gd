extends Node3D
## Friendly electricity from immutable snapshots. No simulation or wall-clock time.
## One cached line batch; only actual emitted edges are drawn, never the possible graph.
const LINE_LIMIT := 768
const HANDLED_EFFECTS := ["lightning_cast", "lightning_bolt_hit", "lightning_beam", "lightning_arc", "lightning_mark", "lightning_cloud_strike", "lightning_ring", "lightning_judgment", "lightning_judgment_flight", "lightning_shield"]
const TINT := Color("c5b3ff")
const CORE := Color("f3e8be")
const HALO := Color("8170bb")

var _lines: MultiMeshInstance3D
var _material: StandardMaterial3D
var _camera: Camera3D
var _clock: float = 0.0
var _reduced: bool = false
var _count: int = 0
var _revision: int = -1
var _coverage: Dictionary = {}
var _footprints: Array = []


func _ready() -> void:
	name = "LightningSpellVFX"
	set_meta("source", "original_procedural_lightning_snapshot_only")
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.render_priority = -5
	_material.emission_enabled = true
	_material.emission = Color(0.08, 0.055, 0.13)
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = mesh
	batch.instance_count = LINE_LIMIT
	batch.visible_instance_count = 0
	batch.custom_aabb = AABB(Vector3(-60, -1, -60), Vector3(120, 24, 120))
	_lines = MultiMeshInstance3D.new()
	_lines.name = "ActualLightningEdgesAndGlyphs"
	_lines.multimesh = batch
	_lines.material_override = _material
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)
	set_process(false)


func sync_snapshot(snapshot: Dictionary, camera: Camera3D, options: Dictionary = {}) -> void:
	if not is_instance_valid(_lines):
		return
	_camera = camera
	_clock = float(snapshot.get("lightning_clock", snapshot.get("combat_time", snapshot.get("time", 0))))
	_reduced = bool(options.get("reduced_motion", false))
	_revision = int(snapshot.get("room_revision", -1))
	_count = 0
	_coverage.clear()
	_footprints.clear()
	if str(snapshot.get("phase", "")) == "combat":
		var actors: Dictionary = {}
		for actor in snapshot.get("actors", []):
			actors[int(actor.id)] = actor
		# Actual attacks take precedence over decorative cloud silhouettes when
		# the fixed batch fills. No effect can allocate a second batch or timer.
		for effect in snapshot.get("effects", []):
			_effect(effect, snapshot)
		for bolt in snapshot.get("lightning_projectiles", []):
			_bolt(bolt)
		for state in snapshot.get("lightning_states", []):
			var actor: Dictionary = actors.get(int(state.get("actor_id", -1)), {})
			if not actor.is_empty() and float(actor.get("health", 0)) > 0:
				_status(actor, state)
		for zone in snapshot.get("lightning_zones", []):
			_cloud(zone)
	_lines.multimesh.visible_instance_count = _count
	visible = _count > 0


func get_debug_state() -> Dictionary:
	return {"line_count": _count, "line_limit": LINE_LIMIT, "material_count": 1, "batch_count": 1, "clock": _clock, "revision": _revision, "reduced_motion": _reduced, "coverage": _coverage.duplicate(true), "footprints": _footprints.duplicate(true)}


func _status(actor: Dictionary, state: Dictionary) -> void:
	var pos: Vector2 = actor.get("pos", Vector2.ZERO)
	var remaining: float = float(state.get("remaining", 0))
	var vulnerable: float = float(state.get("vulnerability_remaining", 0))
	if (remaining <= 0 and vulnerable <= 0) or not _in_view(pos, 0.8):
		return
	var head: float = maxf(2.65 if bool(actor.get("elite", false)) else 2.05, float(actor.get("radius", 0)) * 2.6 + 0.5)
	var center := _point(pos, head) + _right() * 0.42
	var alpha: float = minf(0.85, remaining / 0.25)
	if remaining > 0:
		# A stable lightning rune, rather than a periodically flashing whole body.
		_glyph(center, 0.21, alpha)
		_note("lightning_status")
	if vulnerable > 0:
		# Vulnerability can outlive conductivity: the two cues have independent
		# authoritative expiry and must not visually depend on one another.
		var vulnerability_alpha: float = minf(0.8, vulnerable / 0.25)
		for side in [-1.0, 1.0]:
			var corner: Vector3 = center + _right() * side * 0.18
			_line(corner + Vector3.UP * 0.14, corner - Vector3.UP * 0.14, 0.035, Color(CORE, vulnerability_alpha))
			_line(corner, corner + _right() * side * 0.09 + Vector3.UP * 0.08, 0.025, Color(CORE, vulnerability_alpha * 0.75))
		_note("lightning_vulnerability")
	_footprints.append({"kind": "lightning_status", "actor_id": actor.get("id", -1), "pos": pos, "remaining": remaining, "vulnerability_remaining": vulnerable})


func _bolt(bolt: Dictionary) -> void:
	var pos: Vector2 = bolt.get("pos", Vector2.ZERO)
	if not _in_view(pos, 1.0):
		return
	var direction: Vector2 = Vector2(bolt.get("direction", Vector2(0, 1))).normalized()
	var radius: float = float(bolt.get("radius", 0))
	var tail: float = minf(float(bolt.get("travelled", 0)), 0.7)
	_zigzag(_point(pos - direction * tail, 0.68), _point(pos, 0.68), maxf(0.035, radius * 0.28), 0.72, minf(radius * 0.4, 0.05))
	var wing: Vector2 = direction.orthogonal() * radius * 0.72
	var back: Vector2 = pos - direction * minf(0.22, tail)
	_line(_point(back + wing, 0.68), _point(pos, 0.68), 0.035, Color(CORE, 0.9))
	_line(_point(back - wing, 0.68), _point(pos, 0.68), 0.035, Color(CORE, 0.9))
	_footprints.append({"kind": "lightning_bolt", "pos": pos, "radius": radius})
	_note("L01_bolt")


func _cloud(zone: Dictionary) -> void:
	if str(zone.get("kind", "")) != "lightning_cloud" or float(zone.get("remaining", 0)) <= 0:
		return
	var pos: Vector2 = zone.get("pos", Vector2.ZERO)
	var radius: float = float(zone.get("radius", 0))
	if radius <= 0 or not _in_view(pos, radius):
		return
	# Thin broken boundary, with no filled ground plane over hostile telegraphs.
	_ring(pos, radius, 0.022, 0.18, true)
	var fade: float = minf(1.0, float(zone.get("remaining", 0)) / 0.35)
	var cloud := _point(pos, 2.7)
	# Overhead lobes leave the floor open. Their gentle drift consumes only
	# the supplied combat clock, so paused/repeated snapshots remain identical.
	var drift: float = 0.0 if _reduced else sin(_clock * 1.2 + float(zone.get("id", 0))) * 0.035
	for index in 3:
		var center := cloud + _right() * ((index - 1) * 0.43) + Vector3.UP * (0.12 if index == 1 else drift)
		_arc(center, 0.37 if index == 1 else 0.31, -0.15 * PI, 1.15 * PI, 4 if _reduced else 6, 0.045, Color(TINT, fade * 0.32))
	_line(cloud - _right() * 0.72 - Vector3.UP * 0.07, cloud + _right() * 0.72 - Vector3.UP * 0.07, 0.055, Color(HALO, fade * 0.3))
	_footprints.append({"kind": "lightning_cloud", "pos": pos, "radius": radius})
	_note("L05_cloud")


func _effect(effect: Dictionary, snapshot: Dictionary) -> void:
	var kind: String = str(effect.get("kind", ""))
	var lightning_cast: bool = kind == "cast" and str(effect.get("spell_id", "")).begins_with("L")
	if kind not in HANDLED_EFFECTS and not lightning_cast:
		return
	var alpha: float = clampf(float(effect.get("life", 0)) / maxf(0.001, float(effect.get("max_life", 0))), 0, 1)
	if alpha <= 0:
		return
	var pos: Vector2 = effect.get("pos", Vector2.ZERO)
	var radius: float = float(effect.get("radius", 0))
	var progress: float = 1.0 - alpha
	match kind:
		"cast", "lightning_cast":
			_cast_glyph(pos, str(effect.get("spell_id", "")), alpha)
		"lightning_beam":
			var from: Vector2 = effect.get("from", pos)
			var to: Vector2 = effect.get("to", pos)
			var width: float = maxf(0.0, float(effect.get("width", 0)))
			var side: Vector2 = (to - from).normalized().orthogonal() * width * 0.5
			# The rails show this release's actual full width; the thin center
			# retains the long straight lance silhouette among short chain arcs.
			for sign_value in [-1.0, 1.0]:
				_line(_point(from + side * sign_value, 0.72), _point(to + side * sign_value, 0.72), 0.025, Color(HALO, alpha * 0.28))
			_line(_point(from, 0.72), _point(to, 0.72), 0.045, Color(CORE, alpha * 0.86))
			_zigzag(_point(from, 0.72), _point(to, 0.72), 0.028, alpha * 0.62, minf(0.08, width * 0.2))
			_footprints.append({"kind": kind, "from": from, "to": to, "width": width})
		"lightning_arc":
			var from: Vector2 = effect.get("from", pos)
			var to: Vector2 = effect.get("to", pos)
			var spell_id: String = str(effect.get("spell_id", ""))
			var network: bool = spell_id == "L08"
			_zigzag(_point(from, 0.76), _point(to, 0.76), 0.038 if network else 0.03, alpha * 0.78, 0.07)
			if network:
				# Parallel current and small endpoint terminals distinguish the
				# existing electric grid from a free chain, only on the real edge.
				_line(_point(from, 0.86), _point(to, 0.86), 0.018, Color(CORE, alpha * 0.45))
				_diamond(_point(to, 0.76), 0.13, 0.026, Color(CORE, alpha * 0.65))
			elif spell_id == "L07":
				_line(_point(from, 0.76), _point(to, 0.76), 0.016, Color(CORE, alpha * 0.8))
			else:
				_burst(_point(to, 0.76), 0.14, alpha * 0.65, 3)
			_footprints.append({"kind": kind, "from": from, "to": to, "spell_id": spell_id, "derived": bool(effect.get("derived", false))})
		"lightning_cloud_strike":
			var cloud_pos: Vector2 = effect.get("from", pos)
			_zigzag(_point(cloud_pos, 2.65), _point(pos, 0.3), 0.038, alpha * 0.76, 0.09)
			_line(_point(cloud_pos, 2.65), _point(pos, 0.3), 0.014, Color(CORE, alpha * 0.8))
			_burst(_point(pos, 0.62), 0.24, alpha * 0.62, 4)
			_footprints.append({"kind": kind, "from": cloud_pos, "to": pos, "cloud_id": effect.get("cloud_id", -1), "wave": effect.get("wave", -1)})
		"lightning_judgment":
			_zigzag(_point(pos, 3.5), _point(pos, 0.25), 0.075, alpha * 0.8, 0.13)
			_line(_point(pos, 3.5), _point(pos, 0.25), 0.026, Color(CORE, alpha * 0.88))
			_burst(_point(pos, 0.65), minf(radius * 0.72, 0.55), alpha * 0.7, 5)
			if radius > 0:
				_ground_brackets(pos, radius, alpha * 0.35)
			_footprints.append({"kind": kind, "pos": pos, "radius": radius, "actor_id": effect.get("actor_id", -1)})
		"lightning_judgment_flight":
			var height: float = 2.7 if _reduced else lerpf(3.2, 2.2, progress)
			_diamond(_point(pos, height), 0.27, 0.038, Color(CORE, 0.65))
			_glyph(_point(pos, height), 0.16, 0.75)
			if radius > 0:
				_ground_brackets(pos, radius, 0.25)
			_footprints.append({"kind": kind, "pos": pos, "radius": radius, "actor_id": effect.get("actor_id", -1)})
		"lightning_ring":
			_ring(pos, radius, 0.038, alpha * 0.68)
			if not _reduced:
				_ring(pos, radius * (0.6 + progress * 0.4), 0.02, alpha * 0.3, true)
			_footprints.append({"kind": kind, "pos": pos, "radius": radius})
		"lightning_shield":
			var player_pos: Vector2 = snapshot.get("player", {}).get("pos", pos)
			var center := _point(player_pos, 1.0)
			_shield(center, 0.6, alpha * 0.62)
			_glyph(center, 0.23, alpha * 0.7)
			_footprints.append({"kind": kind, "pos": player_pos, "amount": effect.get("amount", 0)})
		"lightning_bolt_hit":
			_burst(_point(pos, 0.68), 0.28, alpha * 0.72, 3 if bool(effect.get("blocked", false)) else 5)
		"lightning_mark":
			var center := _point(pos, 1.05)
			_glyph(center, 0.25, alpha * 0.72)
			# Broken seal brackets signal application rather than inventing an
			# impact explosion on neighbors that only received conductivity.
			for sign_value in [-1.0, 1.0]:
				var corner: Vector3 = center + _right() * sign_value * 0.3
				_line(corner - Vector3.UP * 0.14, corner + Vector3.UP * 0.14, 0.025, Color(CORE, alpha * 0.55))
	_note("lightning_cast" if lightning_cast else kind)


func _cast_glyph(pos: Vector2, spell_id: String, alpha: float) -> void:
	# These are local charging motifs at the caster. Target connections only
	# appear in actual emitted hit/arc events, never from windup target IDs.
	var center := _point(pos, 0.85)
	match spell_id:
		"L02":
			_line(center - _right() * 0.33, center + _right() * 0.33, 0.028, Color(CORE, alpha * 0.55))
			_diamond(center + _right() * 0.3, 0.1, 0.025, Color(TINT, alpha * 0.6))
		"L03":
			for index in 3:
				var at: Vector3 = center + _right() * (index - 1) * 0.24
				_diamond(at, 0.065, 0.022, Color(TINT, alpha * 0.6))
			_line(center - _right() * 0.24, center + _right() * 0.24, 0.018, Color(CORE, alpha * 0.4))
		"L04":
			_diamond(center, 0.31, 0.026, Color(TINT, alpha * 0.48))
			_glyph(center, 0.18, alpha * 0.65)
		"L05":
			for sign_value in [-1.0, 1.0]:
				_arc(center + _right() * sign_value * 0.15, 0.21, 0.0, PI, 4, 0.028, Color(TINT, alpha * 0.55))
		"L06":
			_ring(pos, 0.36, 0.025, alpha * 0.28, true)
		"L07":
			_diamond(center, 0.31, 0.03, Color(CORE, alpha * 0.6))
			_line(center + Vector3.UP * 0.46, center + Vector3.UP * 0.13, 0.035, Color(TINT, alpha * 0.65))
		"L08":
			_glyph(center - _right() * 0.13, 0.24, alpha * 0.62)
			_glyph(center + _right() * 0.13, 0.24, alpha * 0.62)
		"L09":
			_shield(center, 0.36, alpha * 0.4)
		_:
			_glyph(center, 0.26, alpha * 0.6)


func _diamond(center: Vector3, radius: float, width: float, color: Color) -> void:
	var right: Vector3 = _right() * radius * 0.65
	var points := [center + Vector3.UP * radius, center + right, center - Vector3.UP * radius, center - right]
	for index in 4:
		_line(points[index], points[(index + 1) % 4], width, color)


func _shield(center: Vector3, radius: float, alpha: float) -> void:
	var points := [center + Vector3.UP * radius, center + _right() * radius * 0.77 + Vector3.UP * radius * 0.5,
		center + _right() * radius * 0.58 - Vector3.UP * radius * 0.47, center - Vector3.UP * radius,
		center - _right() * radius * 0.58 - Vector3.UP * radius * 0.47, center - _right() * radius * 0.77 + Vector3.UP * radius * 0.5]
	for index in points.size():
		_line(points[index], points[(index + 1) % points.size()], 0.035, Color(TINT, alpha))
	_line(points[2], points[3], 0.019, Color(CORE, alpha * 0.85))
	_line(points[3], points[4], 0.019, Color(CORE, alpha * 0.85))


func _arc(center: Vector3, radius: float, start: float, end: float, segments: int, width: float, color: Color) -> void:
	for index in segments:
		var a: float = lerpf(start, end, float(index) / segments)
		var b: float = lerpf(start, end, float(index + 1) / segments)
		_line(center + _right() * cos(a) * radius + Vector3.UP * sin(a) * radius * 0.66,
			center + _right() * cos(b) * radius + Vector3.UP * sin(b) * radius * 0.66, width, color)


func _burst(center: Vector3, radius: float, alpha: float, spokes: int) -> void:
	if radius <= 0:
		return
	for index in spokes:
		var angle: float = index * TAU / spokes + 0.2
		var direction: Vector3 = _right() * cos(angle) + Vector3.UP * sin(angle)
		_line(center + direction * radius * 0.38, center + direction * radius, 0.028, Color(CORE if index % 2 == 0 else TINT, alpha))


func _ground_brackets(pos: Vector2, radius: float, alpha: float) -> void:
	# Four short boundary brackets suggest a single locked target point,
	# rather than the filled area explosion used by crowd-damage spells.
	for index in 4:
		var angle: float = index * TAU / 4.0
		for segment in 2:
			var a: float = angle - 0.13 + segment * 0.13
			var b: float = a + 0.13
			_line(_point(pos + Vector2.from_angle(a) * radius, 0.08), _point(pos + Vector2.from_angle(b) * radius, 0.08), 0.026, Color(TINT, alpha))


func _glyph(center: Vector3, radius: float, alpha: float) -> void:
	var points := [center + Vector3.UP * radius, center - _right() * radius * 0.55, center + _right() * radius * 0.3, center - Vector3.UP * radius]
	for index in points.size() - 1:
		_line(points[index], points[index + 1], 0.035, Color(TINT, alpha))


func _zigzag(from: Vector3, to: Vector3, width: float, alpha: float, deviation: float) -> void:
	if _reduced:
		_line(from, to, width, Color(TINT, alpha * 0.8))
		return
	var direction: Vector3 = (to - from).normalized()
	var facing: Vector3 = (_camera.global_position - (from + to) * 0.5).normalized() if _camera != null else Vector3(0, 0.6, 0.8).normalized()
	var normal: Vector3 = facing.cross(direction).normalized()
	if normal.length_squared() < 0.001:
		normal = _right()
	var side: Vector3 = normal * deviation
	var points := [from, from.lerp(to, 0.3) + side, from.lerp(to, 0.55) - side, from.lerp(to, 0.78) + side * 0.5, to]
	for index in points.size() - 1:
		_line(points[index], points[index + 1], width, Color(TINT, alpha))


func _ring(pos: Vector2, radius: float, width: float, alpha: float, dashed: bool = false) -> void:
	if radius <= 0:
		return
	var count: int = 16 if _reduced else 24
	for index in count:
		if dashed and index % 2 == 1:
			continue
		var from := pos + Vector2.from_angle(index * TAU / count) * radius
		var to := pos + Vector2.from_angle((index + 1) * TAU / count) * radius
		_line(_point(from, 0.08), _point(to, 0.08), width, Color(TINT, alpha))


func _line(from: Vector3, to: Vector3, width: float, color: Color) -> void:
	if _count >= LINE_LIMIT or color.a <= 0:
		return
	var length: float = from.distance_to(to)
	if length <= 0.0001:
		return
	var center := (from + to) * 0.5
	if not _in_view(Vector2(center.x, -center.z), length * 0.5):
		return
	var x: Vector3 = (to - from).normalized()
	var facing: Vector3 = (_camera.global_position - center).normalized() if _camera != null else Vector3(0, 0.6, 0.8)
	var y: Vector3 = facing.cross(x).normalized()
	if y.length_squared() < 0.001:
		y = Vector3.RIGHT
	var z := x.cross(y).normalized()
	_lines.multimesh.set_instance_transform(_count, Transform3D(Basis(x * length, y * width, z * width * 0.5), center))
	_lines.multimesh.set_instance_color(_count, color)
	_count += 1


func _right() -> Vector3:
	return _camera.global_basis.x.normalized() if _camera != null else Vector3.RIGHT


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


func _note(kind: String) -> void:
	_coverage[kind] = int(_coverage.get(kind, 0)) + 1
