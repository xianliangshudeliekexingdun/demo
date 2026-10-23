extends Node3D
## Wind, earth and covenant: immutable combat snapshots, one bounded friendly batch.
const LINE_LIMIT := 1536
const HANDLED_EFFECTS := ["earth_telegraph", "earth_construct", "earth_construct_end", "earth_impact", "earth_echo", "earth_wave", "earth_shield", "earth_stun", "spirit_command_start", "spirit_command_hit", "spirit_shield", "spirit_summon", "spirit_expire", "spirit_attack_windup", "spirit_attack", "spirit_recall", "spirit_chain", "spirit_mark"]
const TINT := Color("b7efce")
const WIND_SOURCE_PATH := "res://data/wind_spells_v1.json"
var _lines: MultiMeshInstance3D
var _camera: Camera3D
var _clock: float = 0.0
var _reduced: bool = false
var _count: int = 0
var _budget: int = LINE_LIMIT
var _revision: int = -1
var _coverage: Dictionary = {}
var _footprints: Array = []
var _tint: Color = TINT
var _wind_mastery_levels: Array = []

func _ready() -> void:
	name = "RemainingSchoolsVFX"
	set_meta("source", "original_procedural_six_school_snapshot_only")
	_load_wind_mastery_levels()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = -5
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
	_lines.name = "WindEarthCovenantGeometry"
	_lines.multimesh = batch
	_lines.material_override = material
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)
	set_process(false)

func sync_snapshot(snapshot: Dictionary, camera: Camera3D, options: Dictionary = {}) -> void:
	if not is_instance_valid(_lines): return
	_camera = camera
	_clock = float(snapshot.get("combat_time", snapshot.get("time", 0)))
	_reduced = bool(options.get("reduced_motion", false))
	_revision = int(snapshot.get("room_revision", -1))
	_count = 0
	_coverage.clear()
	_footprints.clear()
	if str(snapshot.get("phase", "")) == "combat":
		# Keep a bounded share available for emitted hits even if persistent
		# outlines saturate; all nodes still belong to the same cached batch.
		_budget = LINE_LIMIT - 320 if _has_friendly_effects(snapshot) else LINE_LIMIT
		_spirit(snapshot)
		_earth(snapshot)
		_wind(snapshot)
		_budget = LINE_LIMIT
		for effect in snapshot.get("effects", []): _effect(effect, snapshot)
	_lines.multimesh.visible_instance_count = _count
	visible = _count > 0

func get_debug_state() -> Dictionary:
	return {"line_count": _count, "line_limit": LINE_LIMIT, "material_count": 1, "batch_count": 1, "clock": _clock, "revision": _revision, "coverage": _coverage.duplicate(true), "footprints": _footprints.duplicate(true)}

func _wind(snapshot: Dictionary) -> void:
	_tint = Color("a4e4cf")
	for shot in snapshot.get("wind_projectiles", []):
		var pos: Vector2 = shot.get("pos", Vector2.ZERO)
		var direction: Vector2 = _direction(shot.get("direction", Vector2.UP))
		var radius: float = maxf(0.08, float(shot.get("radius", 0.15)))
		var id: String = str(shot.get("spell_id", "W01"))
		if id == "W02":
			# The ring turns with its actual leg; its diameter reads the live hit width.
			_arc(pos, radius, 0.35, 5.5, 0.045, 0.75, 0.62)
			_arrow(pos - direction * 0.16, direction, 0.26, 0.5, 0.65)
		elif id == "W03":
			_arrow(pos, direction, 0.38, 0.62, 0.8)
			_line(_point(pos - direction * 0.42, 0.62), _point(pos - direction * 0.12, 0.62), 0.025, Color(_tint, 0.4))
		else:
			var side := direction.orthogonal() * radius
			var tip := pos + direction * 0.17
			_line(_point(pos + side, 0.62), _point(tip, 0.62), 0.045, Color(_tint, 0.85))
			_line(_point(tip, 0.62), _point(pos - side, 0.62), 0.045, Color(_tint, 0.85))
			_line(_point(pos - side, 0.62), _point(pos - direction * 0.2, 0.62), 0.022, Color(_tint, 0.38))
			_line(_point(pos - direction * 0.2, 0.62), _point(pos + side, 0.62), 0.022, Color(_tint, 0.38))
			if id == "W07": _arrow(pos - direction * 0.3, direction, 0.18, 0.62, 0.4)
		_note("wind_projectile")
	for zone in snapshot.get("wind_zones", []):
		var pos: Vector2 = zone.get("pos", Vector2.ZERO)
		var radius: float = float(zone.get("radius", 0.0))
		if str(zone.get("kind", "")) == "wind_guard":
			_wind_guard(zone, 0.36)
		elif str(zone.get("kind", "")) == "wind_vortex":
			_ring(pos, radius, 0.022, 0.22, true)
			var turn: float = 0.0 if _reduced else float(snapshot.get("wind_clock", _clock)) * 1.4
			for blade in (2 if _reduced else 3):
				_spiral(pos, radius * 0.88, turn + blade * TAU / 3.0, 0.4)
			_glyph(pos, 0.12, 0.58, 0.4)
		_note(str(zone.get("kind", "wind_zone")))
	for segment in snapshot.get("wind_path_segments", []):
		var start: Vector2 = segment.get("from", Vector2.ZERO)
		var end: Vector2 = segment.get("to", Vector2.ZERO)
		var side: Vector2 = _direction(end - start).orthogonal() * float(segment.get("radius", 0.0))
		# Use the actual short pieces; never join corners into an invented shortcut.
		_line(_point(start, 0.1), _point(end, 0.1), 0.035, Color(_tint, 0.4))
		for sign_value in [-1.0, 1.0]:
			_line(_point(start + side * sign_value, 0.08), _point(end + side * sign_value, 0.08), 0.018, Color(_tint, 0.19))
		if not _reduced: _arrow(start.lerp(end, 0.5), end - start, minf(0.14, start.distance_to(end) * 0.3), 0.11, 0.32)
		_note("wind_path")
	if _wind_mastery_active(snapshot):
		var player_pos: Vector2 = snapshot.get("player", {}).get("pos", Vector2.ZERO)
		for side in [-1.0, 1.0]: _arc(player_pos, 0.38, side * PI * 0.5 - 0.35, side * PI * 0.5 + 0.35, 0.025, 0.3, 0.14)
		_note("wind_mastery")
	for state in snapshot.get("wind_states", []):
		if float(state.get("until", 0.0)) <= float(snapshot.get("wind_clock", _clock)): continue
		for actor in snapshot.get("actors", []):
			if int(actor.get("id", -1)) != int(state.get("actor_id", -2)) or float(actor.get("health", 0.0)) <= 0.0: continue
			var center: Vector3 = _point(actor.get("pos", Vector2.ZERO), 1.85) + _right() * 0.38
			for sign_value in [-1.0, 1.0]:
				_line(center + _right() * sign_value * 0.12 + Vector3.UP * 0.12, center, 0.027, Color(_tint, 0.68))
				_line(center, center + _right() * sign_value * 0.12 - Vector3.UP * 0.12, 0.027, Color(_tint, 0.68))
			_note("wind_vulnerability")


func _load_wind_mastery_levels() -> void:
	# Presentation caches the approved data, rather than owning a second set
	# of movement thresholds or adding a derived status to the combat core.
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(WIND_SOURCE_PATH))
	if not source is Dictionary:
		push_warning("Wind mastery display source could not be read: " + WIND_SOURCE_PATH)
		return
	var levels: Variant = source.get("spells", {}).get("W10", {}).get("levels", [])
	if levels is Array: _wind_mastery_levels = levels.duplicate(true)


func _wind_mastery_active(snapshot: Dictionary) -> bool:
	for spell in snapshot.get("spells", []):
		if str(spell.get("id", "")) != "W10": continue
		var index: int = int(spell.get("level", 0)) - 1
		if index < 0 or index >= _wind_mastery_levels.size(): return false
		var level: Dictionary = _wind_mastery_levels[index]
		var required: float = float(level.get("required_path", INF))
		if not is_finite(required): return false
		return float(snapshot.get("wind_recent_path", 0.0)) + 0.000001 >= required or float(snapshot.get("wind_mastery_remaining", 0.0)) > 0.000001
	return false

func _earth(snapshot: Dictionary) -> void:
	_tint = Color("d7b580")
	for construct in snapshot.get("earth_constructs", []):
		var pos: Vector2 = construct.get("pos", Vector2.ZERO)
		var radius: float = float(construct.get("radius", 0.0))
		var id: String = str(construct.get("spell_id", "R03"))
		var height: float = 0.48 if id == "R03" else 1.05 if id == "R04" else 0.85
		# Hollow, translucent outlines keep constructs visibly nonblocking.
		if id == "R09":
			_slab(pos, 0.25, height, 0.58)
			_shield(pos, 0.19, 0.55, 0.62)
		elif id == "R04":
			for tier in 3: _slab(pos, 0.24 - tier * 0.045, 0.36, 0.52, float(tier) * 0.29)
			_glyph(pos, 0.13, 0.73, height)
		else:
			_rock(pos, 0.3, height, 0.63)
			_glyph(pos, 0.12, 0.7, 0.42)
		_ring(pos, radius, 0.025, 0.16, true)
		if id == "R09":
			for index in 4:
				var offset: Vector2 = Vector2.from_angle(index * PI * 0.5) * radius
				_line(_point(pos + offset * 0.95, 0.08), _point(pos + offset, 0.08), 0.04, Color(_tint, 0.42))
		_footprints.append({"kind": "earth_construct", "id": construct.id, "pos": pos, "radius": radius})
		_note(id + "_construct")
	for shot in snapshot.get("earth_projectiles", []):
		var pos: Vector2 = shot.get("pos", Vector2.ZERO)
		var direction: Vector2 = _direction(shot.get("direction", Vector2.UP))
		var component: String = str(shot.get("component", "main"))
		if component == "fracture":
			var side: Vector2 = direction.orthogonal() * minf(0.2, float(shot.get("width", 0.3)) * 0.5)
			var points: Array[Vector2] = [pos - direction * 0.32, pos - direction * 0.12 + side, pos + direction * 0.06 - side, pos + direction * 0.25]
			for index in points.size() - 1: _line(_point(points[index], 0.1), _point(points[index + 1], 0.1), 0.05, Color(_tint, 0.75))
		else:
			_rock(pos, minf(0.28, maxf(0.1, float(shot.get("width", 0.3)) * 0.5)), 0.63, 0.75)
			_line(_point(pos - direction * 0.3, 0.63), _point(pos - direction * 0.14, 0.63), 0.03, Color(_tint, 0.32))
		_note("earth_projectile")
	for wave in snapshot.get("earth_waves", []):
		var center: Vector2 = wave.get("pos", Vector2.ZERO)
		var distance: float = float(wave.get("distance", 0))
		_ring(center, distance, 0.05, 0.48, true)
		var width: float = float(wave.get("context", {}).get("earth_level", {}).get("wave_width", 0.0))
		_ring(center, maxf(0.0, distance - width * 0.5), 0.02, 0.18, true)
		_note("earth_wave")
	if float(snapshot.get("earth_defense", 0.0)) > 0.0:
		_shield(snapshot.get("player", {}).get("pos", Vector2.ZERO), 0.2, 0.48, 1.28)
		_note("earth_defense")

func _spirit(snapshot: Dictionary) -> void:
	_tint = Color("e6b7e5")
	for unit in snapshot.get("spirit_units", []):
		var pos: Vector2 = unit.get("pos", Vector2.ZERO)
		var family: String = str(unit.get("family", "ranged"))
		var height: float = 1.1 if family == "ranged" else 0.8
		var pulse: float = 0.0 if _reduced else sin(float(snapshot.get("spirit_clock", _clock)) * 2.4 + float(unit.get("id", 0))) * 0.04
		height += pulse
		var c := _point(pos, height)
		var right := _right()
		var direction := _direction(unit.get("path_goal", pos + Vector2.UP) - pos)
		var forward := Vector3(direction.x, 0, -direction.y)
		var wing := Vector3(-direction.y, 0, -direction.x)
		if family == "ranged":
			_glyph(pos, 0.14, 0.85, height + 0.1)
			_arc(pos, 0.28, 0.3, TAU - 0.3, 0.026, 0.48, height)
			# Hood and split cloak distinguish the caster from the armed servant.
			for sign_value in [-1.0, 1.0]:
				_line(c + right * sign_value * 0.17, c + right * sign_value * 0.28 - Vector3.UP * 0.4, 0.04, Color(_tint, 0.58))
				_line(c + right * sign_value * 0.28 - Vector3.UP * 0.4, c - Vector3.UP * 0.3, 0.025, Color(_tint, 0.42))
		elif str(unit.spell_id) == "S03":
			_glyph(pos, 0.13, 0.78, height + 0.18)
			_line(c + Vector3.UP * 0.04, c - Vector3.UP * 0.35, 0.08, Color(_tint, 0.5))
			# A single clear sword silhouette, rather than a solid friendly actor.
			var hilt: Vector3 = c + right * 0.21 - Vector3.UP * 0.13
			var tip: Vector3 = hilt + right * 0.21 + Vector3.UP * 0.47
			_line(hilt, tip, 0.045, Color(_tint.lightened(0.3), 0.85))
			_line(hilt - right * 0.08, hilt + right * 0.1, 0.045, Color(_tint, 0.7))
			for sign_value in [-1.0, 1.0]: _line(c - Vector3.UP * 0.25, c + right * sign_value * 0.18 - Vector3.UP * 0.46, 0.035, Color(_tint, 0.4))
		else:
			_line(c - forward * 0.22, c + forward * 0.25, 0.07, Color(_tint, 0.75))
			for sign_value in [-1.0, 1.0]:
				var elbow: Vector3 = c + wing * sign_value * 0.23 - forward * 0.08 + Vector3.UP * 0.12
				var tip: Vector3 = c + wing * sign_value * 0.5 - forward * 0.22
				_line(c + forward * 0.08, elbow, 0.05, Color(_tint, 0.72))
				_line(elbow, tip, 0.037, Color(_tint, 0.6))
				_line(tip, c - forward * 0.14, 0.025, Color(_tint, 0.3))
			_line(c - forward * 0.2, c - forward * 0.38 - Vector3.UP * 0.04, 0.035, Color(_tint, 0.5))
		_ring(pos, 0.18, 0.018, 0.17, true, 0.06)
		_footprints.append({"kind": "spirit_unit", "id": unit.id, "pos": pos, "family": family})
		_note(str(unit.spell_id) + "_unit")
	for shot in snapshot.get("spirit_projectiles", []):
		var pos: Vector2 = shot.get("pos", Vector2.ZERO)
		var direction := _direction(shot.get("direction", Vector2.UP))
		_glyph(pos, 0.1, 0.8, 0.62)
		_arrow(pos, direction, 0.22, 0.62, 0.65)
		_line(_point(pos - direction * 0.44, 0.62), _point(pos - direction * 0.15, 0.62), 0.026, Color(_tint, 0.38))
		_note("spirit_projectile")
	for field in snapshot.get("spirit_fields", []):
		var pos: Vector2 = field.get("pos", Vector2.ZERO)
		var radius: float = float(field.get("radius", 0.0))
		_ring(pos, radius, 0.022, 0.22, true)
		for index in 6:
			var offset: Vector2 = Vector2.from_angle(index * TAU / 6) * radius * 0.9
			_glyph(pos + offset, 0.07, 0.3, 0.08)
		_note("spirit_field")
	var mark: Dictionary = snapshot.get("spirit_mark", {})
	if not mark.is_empty():
		for actor in snapshot.get("actors", []):
			if int(actor.id) == int(mark.get("actor_id", -1)) and float(actor.health) > 0:
				# Reticle sits over the marked actor, separate from the ground aura.
				_glyph(actor.pos, 0.19, 0.8, 2.0)
				var center := _point(actor.pos, 2.0)
				for sign_value in [-1.0, 1.0]: _line(center + _right() * sign_value * 0.26, center + _right() * sign_value * 0.35, 0.035, Color(_tint, 0.65))
				_note("spirit_mark")

func _effect(effect: Dictionary, snapshot: Dictionary) -> void:
	var kind: String = str(effect.get("kind", ""))
	var cast_school: String = {"W":"wind", "R":"earth", "S":"spirit"}.get(str(effect.get("spell_id", "")).left(1), "") if kind == "cast" else ""
	if not cast_school.is_empty(): kind = cast_school + "_cast"
	var school: String = "wind" if kind.begins_with("wind_") else "earth" if kind.begins_with("earth_") else "spirit" if kind.begins_with("spirit_") else ""
	if school.is_empty(): return
	_tint = Color({"wind": "a4e4cf", "earth": "d7b580", "spirit": "e6b7e5"}[school])
	var alpha: float = clampf(float(effect.get("life", 0)) / maxf(0.001, float(effect.get("max_life", 0))), 0, 1)
	var pos: Vector2 = effect.get("pos", Vector2.ZERO)
	if alpha <= 0: return
	var progress: float = 1.0 - alpha
	var radius: float = float(effect.get("radius", 0))
	var start: Vector2 = effect.get("from", pos)
	var end: Vector2 = effect.get("to", pos)
	match kind:
		"wind_scatter":
			var direction := _direction(effect.get("direction", Vector2.UP))
			var angle: float = deg_to_rad(float(effect.get("angle_degrees", 0)))
			var middle: float = direction.angle()
			_arc(pos, radius, middle - angle * 0.5, middle + angle * 0.5, 0.025, alpha * 0.4, 0.1)
			for index in 5:
				var ray: Vector2 = direction.rotated(angle * (float(index) / 4.0 - 0.5))
				_arrow(pos + ray * radius * (0.55 if _reduced else 0.3 + progress * 0.5), ray, minf(radius * 0.12, 0.28), 0.16, alpha * 0.6)
		"wind_guard": _wind_guard(effect, alpha * 0.35)
		"wind_vacuum_flight":
			var point: Vector2 = start.lerp(end, progress)
			_glyph(point, 0.13, alpha * 0.7, 0.65)
			_ring(pos, radius, 0.02, alpha * 0.14, true)
		"wind_vacuum", "wind_vacuum_followup":
			_ring(pos, radius, 0.025, alpha * 0.35, true)
			for index in (4 if _reduced else 6):
				var ray := Vector2.from_angle(index * TAU / 6)
				_arrow(pos + ray * radius * 0.6, -ray, minf(0.28, radius * 0.15), 0.2, alpha * 0.6)
			_glyph(pos, 0.18 if kind == "wind_vacuum" else 0.11, alpha * 0.8, 0.48)
		"wind_vortex_hit":
			_arrow(start.lerp(pos, 0.7), start - pos, 0.2, 0.35, alpha * 0.6)
		"wind_hit", "wind_path_hit":
			_arc(pos, 0.19, -0.5, 2.5, 0.035, alpha * 0.7, 0.65)
		"wind_mark":
			for sign_value in [-1.0, 1.0]: _arrow(pos + Vector2(sign_value * 0.23, 0), Vector2(-sign_value, 0), 0.1, 1.85, alpha * 0.55)
		"earth_telegraph":
			_ring(pos, radius, 0.025, 0.22 + progress * 0.12, true)
			var height: float = 1.7 if _reduced else lerpf(3.6, 0.4, progress)
			_rock(pos, 0.35 if str(effect.get("spell_id", "")) == "R03" else 0.48, height, alpha * 0.68)
			if not _reduced: _line(_point(pos, height + 0.3), _point(pos, height + 0.85), 0.035, Color(_tint, alpha * 0.3))
		"earth_impact", "earth_echo":
			_ring(pos, radius, 0.028, alpha * (0.3 if kind == "earth_echo" else 0.42), true)
			for index in (4 if _reduced else 6):
				var ray := Vector2.from_angle(index * TAU / 6.0 + 0.2)
				var joint: Vector2 = pos + ray * radius * 0.43 + ray.orthogonal() * radius * 0.12
				_line(_point(pos + ray * 0.12, 0.09), _point(joint, 0.09), 0.028, Color(_tint, alpha * 0.55))
				_line(_point(joint, 0.09), _point(pos + ray * radius * 0.84, 0.09), 0.022, Color(_tint, alpha * 0.4))
			if kind == "earth_impact": _rock(pos, 0.18, 0.35, alpha * 0.58)
		"earth_wave":
			# Core emits a sample every fixed step. A live front already supplies
			# its exact current radius; historical samples would create a solid disk.
			if snapshot.get("earth_waves", []).is_empty(): _ring(pos, radius, 0.025, alpha * 0.2, true)
		"earth_construct": _ring(pos, minf(radius, 0.4), 0.024, alpha * 0.4, true)
		"earth_construct_end":
			for index in 4:
				var ray := Vector2.from_angle(index * PI * 0.5 + PI * 0.25)
				var offset: float = 0.18 if _reduced else 0.16 + progress * 0.22
				_line(_point(pos + ray * offset, 0.12), _point(pos + ray * (offset + 0.12), 0.26), 0.035, Color(_tint, alpha * 0.4))
		"earth_stun":
			_glyph(pos, 0.14, alpha * 0.75, 1.85)
			_arc(pos, 0.23, 0.0, PI, 0.025, alpha * 0.4, 1.8)
		"earth_shield", "spirit_shield":
			var player_pos: Vector2 = snapshot.get("player", {}).get("pos", pos)
			_shield(player_pos, 0.35, alpha * 0.66, 1.1)
			if kind == "spirit_shield":
				for sign_value in [-1.0, 1.0]: _glyph(player_pos + Vector2(sign_value * 0.5, 0), 0.08, alpha * 0.45, 0.8)
		"spirit_summon", "spirit_expire":
			_ring(pos, 0.32, 0.025, alpha * 0.5, true)
			_glyph(pos, 0.14, alpha * 0.65, 0.6)
			for sign_value in [-1.0, 1.0]:
				var height: float = 0.35 if _reduced else progress * 0.65
				_line(_point(pos + Vector2(sign_value * 0.22, 0), height), _point(pos + Vector2(sign_value * 0.22, 0), height + 0.14), 0.025, Color(_tint, alpha * 0.35))
		"spirit_attack_windup": _glyph(pos, 0.12, alpha * 0.6, 1.05)
		"spirit_attack": _spirit_attack(effect, snapshot, alpha)
		"spirit_command_start":
			_glyph(pos, 0.16, alpha * 0.65, 1.6)
			for unit in snapshot.get("spirit_units", []):
				if int(unit.get("id", -1)) in effect.get("source_ids", []): _glyph(unit.pos, 0.11, alpha * 0.6, 1.5)
		"spirit_command_hit":
			_line(_point(start, 0.65), _point(end, 0.65), 0.035, Color(_tint, alpha * 0.6))
			_glyph(end, 0.2, alpha * 0.8, 0.7)
		"spirit_chain": _chain(start, end, alpha)
		"spirit_recall":
			_ring(pos, radius, 0.03, alpha * 0.37, true)
			for index in 4:
				var ray := Vector2.from_angle(index * PI * 0.5)
				_arrow(pos + ray * radius * 0.5, -ray, 0.24, 0.4, alpha * 0.62)
			_glyph(pos, 0.22, alpha * 0.8, 0.5)
		"spirit_mark": _glyph(pos, 0.18, alpha * 0.7, 1.9)
		_:
			if kind.ends_with("cast"):
				_ring(pos, 0.28, 0.022, alpha * 0.22, true)
				if school == "earth": _rock(pos, 0.1, 0.4, alpha * 0.45)
				elif school == "spirit": _glyph(pos, 0.1, alpha * 0.5, 0.55)
				else: _arc(pos, 0.24, 0.0, PI * 1.3, 0.028, alpha * 0.4, 0.3)
	_note(kind)


func _spirit_attack(effect: Dictionary, snapshot: Dictionary, alpha: float) -> void:
	var start: Vector2 = effect.get("from", effect.get("pos", Vector2.ZERO))
	var end: Vector2 = effect.get("to", start)
	var id: String = str(effect.get("spell_id", "S02"))
	var level: Dictionary = {}
	for unit in snapshot.get("spirit_units", []):
		if int(unit.get("id", -1)) == int(effect.get("unit_id", -2)):
			level = unit.get("level", {})
			break
	if id == "S03":
		if int(level.get("target_cap", 1)) > 1 and float(level.get("cleave_angle_degrees", 0.0)) > 0.0:
			var heading: float = (end - start).angle()
			var angle: float = deg_to_rad(float(level.cleave_angle_degrees)) * 0.5
			_arc(start, float(level.cleave_radius), heading - angle, heading + angle, 0.04, alpha * 0.6, 0.55)
		else:
			_line(_point(start, 0.55), _point(end, 0.55), 0.045, Color(_tint, alpha * 0.65))
	elif id == "S04":
		var side := _direction(end - start).orthogonal() * float(level.get("sweep_width", 0.3)) * 0.5
		for sign_value in [-1.0, 1.0]: _line(_point(start + side * sign_value, 0.65), _point(end + side * sign_value, 0.65), 0.025, Color(_tint, alpha * 0.48))
	else:
		_line(_point(start, 0.72), _point(end, 0.72), 0.045, Color(_tint, alpha * 0.68))
		_line(_point(start, 0.72), _point(end, 0.72), 0.018, Color(_tint.lightened(0.4), alpha * 0.8))
	_glyph(effect.get("pos", end), 0.1, alpha * 0.7, 0.65)


func _has_friendly_effects(snapshot: Dictionary) -> bool:
	for effect in snapshot.get("effects", []):
		var kind: String = str(effect.get("kind", ""))
		if float(effect.get("life", 0.0)) <= 0.0: continue
		if kind.begins_with("wind_") or kind.begins_with("earth_") or kind.begins_with("spirit_"): return true
		if kind == "cast" and str(effect.get("spell_id", "")).left(1) in ["W", "R", "S"]: return true
	return false

func _ring(pos: Vector2, radius: float, width: float, alpha: float, dashed: bool = false, height: float = 0.08) -> void:
	if radius <= 0: return
	var count: int = 16 if _reduced else 24
	for index in count:
		if dashed and index % 2 == 1: continue
		var from: Vector2 = pos + Vector2.from_angle(index * TAU / count) * radius
		var to: Vector2 = pos + Vector2.from_angle((index + 1) * TAU / count) * radius
		_line(_point(from, height), _point(to, height), width, Color(_tint, alpha))


func _arc(pos: Vector2, radius: float, start: float, end: float, width: float, alpha: float, height: float) -> void:
	if radius <= 0.0: return
	var count: int = 8 if _reduced else 14
	for index in count:
		var a: Vector2 = pos + Vector2.from_angle(lerpf(start, end, float(index) / count)) * radius
		var b: Vector2 = pos + Vector2.from_angle(lerpf(start, end, float(index + 1) / count)) * radius
		_line(_point(a, height), _point(b, height), width, Color(_tint, alpha))


func _arrow(pos: Vector2, direction: Vector2, length: float, height: float, alpha: float) -> void:
	if length <= 0.0: return
	var forward := _direction(direction)
	var side := forward.orthogonal()
	var tip: Vector2 = pos + forward * length * 0.5
	_line(_point(pos - forward * length * 0.5, height), _point(tip, height), 0.027, Color(_tint, alpha))
	for sign_value in [-1.0, 1.0]:
		_line(_point(tip, height), _point(pos - forward * length * 0.05 + side * sign_value * length * 0.35, height), 0.027, Color(_tint, alpha))


func _spiral(pos: Vector2, radius: float, turn: float, alpha: float) -> void:
	var count: int = 6 if _reduced else 10
	for index in count:
		var t: float = float(index) / count
		var u: float = float(index + 1) / count
		var a: Vector2 = pos + Vector2.from_angle(turn + t * 2.8) * radius * (1.0 - t * 0.8)
		var b: Vector2 = pos + Vector2.from_angle(turn + u * 2.8) * radius * (1.0 - u * 0.8)
		_line(_point(a, 0.14 + t * 0.22), _point(b, 0.14 + u * 0.22), 0.025, Color(_tint, alpha))


func _wind_guard(zone: Dictionary, alpha: float) -> void:
	var pos: Vector2 = zone.get("pos", Vector2.ZERO)
	var normal := _direction(zone.get("normal", Vector2.UP))
	var side: Vector2 = normal.orthogonal() * float(zone.get("width", 0.0)) * 0.5
	var depth: Vector2 = normal * float(zone.get("depth", 0.0)) * 0.5
	var corners: Array[Vector2] = [pos - side - depth, pos + side - depth, pos + side + depth, pos - side + depth]
	for index in 4: _line(_point(corners[index], 0.08), _point(corners[(index + 1) % 4], 0.08), 0.021, Color(_tint, alpha * 0.8))
	for height in [0.32, 0.72, 1.12]:
		_line(_point(pos - side, height), _point(pos + side, height), 0.025, Color(_tint, alpha * 0.7))
	for sign_value in [-1.0, 1.0]: _line(_point(pos + side * sign_value, 0.12), _point(pos + side * sign_value, 1.15), 0.025, Color(_tint, alpha))
	# Open bars leave the incoming bullets visible through the slow band.
	if not _reduced:
		for index in 3: _arrow(pos + side * (float(index) - 1.0) * 0.6, -normal, 0.17, 0.42, alpha * 0.8)


func _rock(pos: Vector2, radius: float, height: float, alpha: float) -> void:
	var c := _point(pos, height)
	var side := _right() * radius
	var up := Vector3.UP * radius
	var points: Array[Vector3] = [c - side * 0.9, c - side * 0.55 + up * 0.85, c + side * 0.5 + up, c + side, c + side * 0.5 - up * 0.75, c - side * 0.55 - up * 0.7]
	for index in points.size(): _line(points[index], points[(index + 1) % points.size()], 0.035, Color(_tint, alpha))
	_line(points[1], points[4], 0.02, Color(_tint.lightened(0.18), alpha * 0.6))
	_line(points[1], points[3], 0.02, Color(_tint, alpha * 0.4))


func _slab(pos: Vector2, half_width: float, height: float, alpha: float, base: float = 0.08) -> void:
	var c := _point(pos, base)
	var side := _right() * half_width
	var up := Vector3.UP * height
	var points: Array[Vector3] = [c - side, c + side, c + side + up * 0.82, c + side * 0.55 + up, c - side * 0.6 + up * 0.96, c - side + up * 0.72]
	for index in points.size(): _line(points[index], points[(index + 1) % points.size()], 0.04, Color(_tint, alpha))
	_line(c - side * 0.35, c - side * 0.35 + up * 0.8, 0.022, Color(_tint.lightened(0.18), alpha * 0.55))


func _shield(pos: Vector2, radius: float, alpha: float, height: float) -> void:
	var c := _point(pos, height)
	var side := _right() * radius
	var up := Vector3.UP * radius
	var points: Array[Vector3] = [c + up, c + side + up * 0.65, c + side * 0.8 - up * 0.4, c - up, c - side * 0.8 - up * 0.4, c - side + up * 0.65]
	for index in points.size(): _line(points[index], points[(index + 1) % points.size()], 0.035, Color(_tint, alpha))
	_line(c + up * 0.6, c - up * 0.5, 0.025, Color(_tint, alpha * 0.55))


func _chain(start: Vector2, end: Vector2, alpha: float) -> void:
	var direction := _direction(end - start)
	var side := direction.orthogonal()
	var count: int = clampi(ceili(start.distance_to(end) / 0.32), 1, 24)
	if _reduced: count = maxi(1, count / 2)
	for index in count:
		var a: Vector2 = start.lerp(end, float(index) / count)
		var b: Vector2 = start.lerp(end, float(index + 1) / count)
		var c: Vector2 = a.lerp(b, 0.5)
		var offset: Vector2 = side * minf(0.07, a.distance_to(b) * 0.3)
		for sign_value in [-1.0, 1.0]:
			_line(_point(a, 0.58), _point(c + offset * sign_value, 0.58), 0.022, Color(_tint, alpha * 0.65))
			_line(_point(c + offset * sign_value, 0.58), _point(b, 0.58), 0.022, Color(_tint, alpha * 0.65))
	_glyph(end, 0.12, alpha * 0.7, 0.65)


func _direction(value: Vector2) -> Vector2:
	return value.normalized() if value.length_squared() > 0.000001 else Vector2.UP

func _glyph(pos: Vector2, radius: float, alpha: float, height: float) -> void:
	var center: Vector3 = _point(pos, height)
	var right: Vector3 = _right() * radius
	var up: Vector3 = Vector3.UP * radius * 1.5
	_line(center - up, center + right, 0.035, Color(_tint, alpha))
	_line(center + right, center + up, 0.035, Color(_tint, alpha))
	_line(center + up, center - right, 0.035, Color(_tint, alpha))
	_line(center - right, center - up, 0.035, Color(_tint, alpha))

func _line(from: Vector3, to: Vector3, width: float, color: Color) -> void:
	if _count >= mini(_budget, LINE_LIMIT) or color.a <= 0:
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
