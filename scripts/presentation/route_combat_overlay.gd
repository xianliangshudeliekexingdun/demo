extends RefCounted
## Read-only route combat drawing. Every dangerous footprint comes from core.
## Pixel primitives are clipped to the view; this file never creates combat state.

const ENEMY = Color("ff776f")
const ENEMY_CORE = Color("ffb5ba")
const FRIENDLY = Color("efbf73")
const FIRE = Color("f09b58")
const WARNING_FADE_SECONDS := 0.08
const WARNING = Color("e98aa6")
const WARNING_CORE = Color("ffd4bf")
const WARNING_SHADOW = Color(0.105, 0.075, 0.105)
const CAP_SEGMENTS := 8

static func draw(view, state: Dictionary):
	# Compatibility entry point. The live view calls the split layers explicitly
	# so hostile projectiles can stay above friendly effects and health bars.
	draw_friendly_ground(view, state)
	draw_enemy_warnings(view, state)
	draw_enemy_projectiles(view, state)

static func draw_friendly_ground(view, state: Dictionary):
	# Friendly magic is rendered by the cached 3D shader batches.
	if view.get("spell_vfx") != null:
		return
	for zone in state.get("spell_zones", []):
		var pos: Vector2 = zone.get("pos", Vector2.ZERO)
		var radius = float(zone.get("radius", 0.0))
		var kind = str(zone.get("kind", ""))
		if kind == "rain":
			_ground(view, pos, radius, Color(FRIENDLY, 0.025), Color(FRIENDLY, 0.37), 1.2)
		elif kind == "field":
			_ground(view, pos, radius, Color(FRIENDLY, 0.045), Color(FRIENDLY, 0.76), 1.8)
			_ground(view, pos, radius * 0.88, Color.TRANSPARENT, Color(FRIENDLY, 0.24), 1.0)
			for index in 4:
				var point = pos + Vector2.from_angle(index * PI * 0.5 + PI * 0.25) * radius * 0.84
				_diamond(view, point, radius * 0.07, FRIENDLY)
		elif kind == "vortex":
			_ground(view, pos, radius, Color(FIRE, 0.055), Color(FIRE, 0.60), 1.4)
			var angle = float(state.get("time", 0.0)) * 1.4 if not _reduced(view) else 0.0
			for index in 3:
				var points = PackedVector2Array()
				for segment in 13:
					var a = angle + index * TAU / 3.0 + segment * 0.13
					var r = radius * (0.24 + segment * 0.045)
					points.append(view.screen_position(pos + Vector2.from_angle(a) * r, 0.08))
				_path(view, points, Color(FRIENDLY, 0.68), 1.6 * _scale(view))
		elif kind == "rain_ground":
			_ground(view, pos, radius, Color(FIRE, 0.055), Color(FIRE, 0.57), 1.3)
			_ground(view, pos, radius * 0.58, Color.TRANSPARENT, Color(FIRE, 0.17), 1.0)
	for pending in state.get("spell_pending", []):
		if pending.get("kind", "") == "rain_drop":
			_ground(view, pending.pos, float(pending.radius), Color.TRANSPARENT, Color(FRIENDLY, 0.32), 1.0)
		elif pending.get("kind", "") == "bomb":
			_ground(view, pending.pos, float(pending.radius), Color(FRIENDLY, 0.015), Color(FRIENDLY, 0.28), 1.1)
	var units: Array = state.get("spirits", [])
	for index in range(1, units.size()):
		var unit: Dictionary = units[index]
		var pos: Vector2 = unit.get("pos", Vector2.ZERO)
		if not _visible(view, pos, 1.0, 24.0):
			continue
		var p: Vector2 = view.screen_position(pos, 1.0)
		var sf = _scale(view)
		_disc(view, p, 13.0 * sf, Color(1.0, 0.7, 0.25, 0.12))
		var diamond = PackedVector2Array([p + Vector2(0, -11) * sf, p + Vector2(7, 0) * sf, p + Vector2(0, 11) * sf, p + Vector2(-7, 0) * sf])
		_polygon(view, diamond, Color("ffd587"))
		_line(view, p + Vector2(-8, 0) * sf, p + Vector2(-17, -5) * sf, Color("edb35d"), 2.0 * sf)
		_line(view, p + Vector2(8, 0) * sf, p + Vector2(17, -5) * sf, Color("edb35d"), 2.0 * sf)
	var patches: Array = state.get("artifact_patches", state.get("artifact_state", {}).get("patches", []))
	for patch in patches:
		_ground(view, patch.get("pos", Vector2.ZERO), float(patch.get("radius", 0.0)), Color(0.92, 0.42, 0.2, 0.045), Color(0.94, 0.5, 0.31, 0.5), 1.2)

static func draw_enemy_warnings(view, state: Dictionary):
	var player: Dictionary = state.get("player", {})
	var player_pos: Vector2 = player.get("pos", Vector2.ZERO)
	var player_radius: float = float(player.get("radius", 0.0))
	for actor in state.get("actors", []):
		if not actor.has("type_id") or float(actor.get("health", 0.0)) <= 0.0:
			continue
		var actor_pos: Vector2 = actor.get("pos", Vector2.ZERO)
		var contact_distance: float = float(actor.get("radius", 0.0)) + player_radius + 0.55
		if bool(actor.get("body_contact_enabled", false)) and float(player.get("invulnerable", 0.0)) <= 0.0 and actor_pos.distance_squared_to(player_pos) <= contact_distance * contact_distance:
			_ground(view, actor_pos, float(actor.radius), Color.TRANSPARENT, Color(WARNING, 0.40), 1.0)
		var danger: Dictionary = actor.get("danger", {})
		if not danger.is_empty():
			_danger(view, danger)
		for boss_danger in actor.get("dangers", []):
			_danger(view, boss_danger)
	var fades = view.get("_danger_fades")
	if fades is Dictionary:
		for key in fades:
			var entry = fades[key]
			if entry is Dictionary and float(entry.get("remaining", 0.0)) > 0.0:
				var faded: Dictionary = entry.get("danger", {}).duplicate(true)
				if not faded.is_empty():
					faded["_fade_alpha"] = clampf(float(entry.remaining) / WARNING_FADE_SECONDS, 0.0, 1.0)
					_danger(view, faded)

static func draw_spawn_warnings(view, state: Dictionary):
	for warning in state.get("spawn_warnings", []):
		_spawn_warning(view, warning, 1.0)
	var fades = view.get("_spawn_warning_fades")
	if fades is Dictionary:
		for key in fades:
			var entry = fades[key]
			if entry is Dictionary and float(entry.get("remaining", 0.0)) > 0.0:
				var warning: Dictionary = entry.get("warning", {}).duplicate(true)
				if not warning.is_empty():
					_spawn_warning(view, warning, clampf(float(entry.remaining) / WARNING_FADE_SECONDS, 0.0, 1.0))

static func draw_enemy_projectiles(view, state: Dictionary):
	var missiles = view.get("magic_missile_vfx")
	if is_instance_valid(missiles) and missiles.is_available():
		return # The bounded shader/ribbon layer draws above this overlay.
	var sf = _scale(view)
	for projectile in state.get("enemy_projectiles", []):
		var pos: Vector2 = projectile.get("pos", Vector2.ZERO)
		if not _visible(view, pos, 0.55, 20.0):
			continue
		var p: Vector2 = view.screen_position(pos, 0.55)
		var direction: Vector2 = projectile.get("direction", Vector2(0, -1))
		if direction.length_squared() < 0.000001:
			direction = Vector2(0, -1)
		direction = direction.normalized()
		var back: Vector2 = view.screen_position(pos - direction, 0.55)
		var axis = (p - back).normalized()
		if axis.length_squared() < 0.000001:
			axis = Vector2.UP
		var physical_radius: float = maxf(2.6 * sf, p.distance_to(view.screen_position(pos + Vector2(float(projectile.get("radius", 0.18)), 0), 0.55)))
		var outline_radius: float = physical_radius + maxf(1.0 * sf, physical_radius * 0.12)
		var trail: float = clampf(10.0 * sf, 8.0 * sf, 14.0 * sf)
		# The hostile shot keeps its true footprint. A one-pixel dark rim and a
		# short direction-aligned trail carry contrast without implying a radius.
		_line(view, p - axis * trail, p - axis * 2.0 * sf, Color(0.035, 0.012, 0.028, 0.78), maxf(1.8 * sf, physical_radius * 0.86))
		_line(view, p - axis * trail * 0.78, p - axis * 2.0 * sf, Color(ENEMY, 0.72), maxf(1.0 * sf, physical_radius * 0.48))
		_disc(view, p, outline_radius, Color(0.055, 0.018, 0.035, 0.92))
		_disc(view, p, physical_radius, Color("e75d91"))
		_disc(view, p, physical_radius * 0.40, ENEMY_CORE)

static func draw_effect(view, effect: Dictionary) -> bool:
	var kind = str(effect.get("kind", ""))
	if kind not in ["rain_impact", "bomb_flight", "bomb_impact", "aftershock", "wave", "shield_restore", "summon", "enemy_warning", "enemy_mark", "enemy_shot", "artifact_patch", "artifact_explosion", "artifact_speed", "artifact_cooldown", "artifact_acquired"]:
		return false
	# Warning and mark events are drawn from the actor's present danger dictionary.
	# Historical events must not duplicate or outlive an interrupted footprint.
	if kind in ["enemy_warning", "enemy_mark"]:
		return true
	var alpha = clampf(float(effect.get("life", 0.0)) / maxf(0.0001, float(effect.get("max_life", 0.1))), 0.0, 1.0)
	var progress = 1.0 - alpha
	var pos: Vector2 = effect.get("pos", Vector2.ZERO)
	var radius = float(effect.get("radius", 0.7))
	var sf = _scale(view)
	match kind:
		"rain_impact":
			_ground(view, pos, radius, Color(FIRE, alpha * 0.11), Color(FRIENDLY, alpha * 0.88), 2.0)
			if _visible(view, pos, 0.05, 50):
				var p: Vector2 = view.screen_position(pos, 0.05)
				var top: Vector2 = view.screen_position(pos, 1.3 * alpha)
				_line(view, top, p, Color(1.0, 0.65, 0.29, alpha * 0.7), 4 * sf)
		"bomb_flight":
			var start: Vector2 = effect.get("from", pos)
			var end: Vector2 = effect.get("to", pos)
			var current = start.lerp(end, progress)
			var height = 0.65 + sin(progress * PI) * 2.7
			if _visible(view, current, height, 24):
				var p: Vector2 = view.screen_position(current, height)
				_disc(view, p, 11 * sf, Color(FIRE, alpha * 0.22))
				_disc(view, p, 6 * sf, FRIENDLY)
		"bomb_impact", "aftershock", "artifact_explosion":
			_ground(view, pos, radius, Color(FIRE, alpha * 0.08), Color(FRIENDLY, alpha * 0.9), 2.5 if kind == "bomb_impact" else 1.7)
			_ground(view, pos, radius * (0.36 + progress * 0.64), Color.TRANSPARENT, Color(FIRE, alpha * 0.7), 2.0)
		"wave":
			_ground(view, pos, radius * (0.18 + progress * 0.82), Color(FIRE, alpha * 0.04), Color(FRIENDLY, alpha * 0.85), 2.4)
		"shield_restore":
			_ground(view, pos, 0.65 + progress * 0.25, Color(1.0, 0.76, 0.35, alpha * 0.03), Color(1.0, 0.83, 0.46, alpha * 0.8), 2.2)
			if _visible(view, pos, 1.0, 28):
				var p: Vector2 = view.screen_position(pos, 1.0)
				var shield = PackedVector2Array([p + Vector2(0, -13) * sf, p + Vector2(11, -7) * sf, p + Vector2(8, 8) * sf, p + Vector2(0, 14) * sf, p + Vector2(-8, 8) * sf, p + Vector2(-11, -7) * sf, p + Vector2(0, -13) * sf])
				_path(view, shield, Color(1.0, 0.84, 0.48, alpha), 2.0 * sf)
		"summon":
			_ground(view, pos, 0.28 + progress * 0.22, Color.TRANSPARENT, Color(FRIENDLY, alpha * 0.8), 1.8)
		"enemy_shot":
			if _visible(view, pos, 0.55, 20):
				_disc(view, view.screen_position(pos, 0.55), (6 + progress * 7) * sf, Color(ENEMY, alpha * 0.45))
		"artifact_patch":
			# Persistent patches are represented by their real active snapshot; this
			# event provides a brief birth ring and cannot imply additional damage.
			if progress < 0.15:
				_ground(view, pos, radius, Color.TRANSPARENT, Color(FIRE, alpha * 0.55), 1.5)
		"artifact_speed":
			if _visible(view, pos, 0.1, 24):
				var p: Vector2 = view.screen_position(pos, 0.1)
				for index in 2:
					var y = (8 + index * 7) * sf
					_path(view, PackedVector2Array([p + Vector2(-8 * sf, y), p + Vector2(0, y - 5 * sf), p + Vector2(8 * sf, y)]), Color(FRIENDLY, alpha * 0.75), 1.5 * sf)
		"artifact_cooldown":
			_ground(view, pos, 0.72, Color.TRANSPARENT, Color(0.68, 0.72, 0.95, alpha * 0.75), 1.6)
			_diamond(view, pos, 0.24, Color(0.75, 0.7, 0.98, alpha))
		"artifact_acquired":
			_ground(view, pos, 0.45 + progress * 0.65, Color.TRANSPARENT, Color(FRIENDLY, alpha * 0.85), 2.0)
	return true

static func _danger(view, danger: Dictionary):
	var kind = str(danger.get("kind", ""))
	var start: Vector2 = danger.get("from", danger.get("pos", Vector2.ZERO))
	var end: Vector2 = danger.get("to", start)
	var radius = float(danger.get("radius", 0.0))
	var progress = clampf(1.0 - float(danger.get("remaining", 0.0)) / maxf(0.001, float(danger.get("duration", 1.0))), 0.0, 1.0)
	var active = bool(danger.get("active", false))
	var fade_alpha = clampf(float(danger.get("_fade_alpha", 1.0)), 0.0, 1.0)
	var late = clampf((progress - 0.70) / 0.30, 0.0, 1.0)
	var fill: Color
	var line: Color
	var line_width: float
	if active:
		fill = Color(WARNING, 0.15 * fade_alpha)
		line = Color(WARNING_CORE, 0.98 * fade_alpha)
		line_width = 2.25
	else:
		# The full footprint is readable from the first frame. Fill and line
		# strengthen continuously instead of switching from broken dashes to fill.
		fill = Color(WARNING, (0.040 + 0.060 * progress) * fade_alpha)
		line = Color(WARNING.lerp(WARNING_CORE, 0.12 + 0.30 * progress), (0.78 + 0.18 * progress) * fade_alpha)
		line_width = 1.55 + 0.40 * progress
	var spread_fill := Color(fill, fill.a * (0.52 if active else 0.42))
	if kind == "circle":
		var center: Vector2 = danger.get("pos", end)
		_ground_outlined(view, center, radius, fill, line, line_width)
		if not active and late > 0.0:
			# A thin closing ring shows urgency without replacing the true edge.
			_ground(view, center, radius * (1.0 - 0.18 * late), Color.TRANSPARENT, Color(WARNING_CORE, 0.30 * late * fade_alpha), 1.0)
	elif kind == "lane":
		_lane(view, start, end, radius, fill, line, line_width)
	elif kind in ["ray", "fan"]:
		var direction = end - start
		for degrees in danger.get("spread_degrees", [0.0]):
			var ray_end = start + direction.rotated(deg_to_rad(float(degrees)))
			_lane(view, start, ray_end, radius, spread_fill, line, line_width)
	elif kind == "ring":
		var direction: Vector2 = end - start
		for degrees in danger.get("spread_degrees", []):
			_lane(view, start, start + direction.rotated(deg_to_rad(float(degrees))), radius, spread_fill, line, line_width)
		# A short open chevron marks the actual omitted spokes, never a safe disk.
		var axis: Vector2 = direction.normalized()
		var half_gap: float = TAU / maxf(1.0, float(danger.get("nominal_count", 1))) * 1.5
		var a: Vector2 = start + axis.rotated(-half_gap) * 2.1
		var b: Vector2 = start + axis * 2.8
		var c: Vector2 = start + axis.rotated(half_gap) * 2.1
		_outlined_path(view, PackedVector2Array([view.screen_position(a, 0.05), view.screen_position(b, 0.05), view.screen_position(c, 0.05)]), Color(WARNING_CORE, 0.85 * fade_alpha), 1.6 * _scale(view))
	elif kind == "sweep":
		var direction: Vector2 = end - start
		var angles: Array = danger.get("spread_degrees", [])
		var first: int = int(danger.get("shot_index", 0)) if active else 0
		for index in range(first, angles.size()):
			var sweep_line := Color(line, line.a if index == first else line.a * 0.72)
			_lane(view, start, start + direction.rotated(deg_to_rad(float(angles[index]))), radius, spread_fill, sweep_line, line_width)
		# Ordered points show the fixed sweep direction; aim never follows art.
		var arc := PackedVector2Array()
		for degrees in angles:
			arc.append(view.screen_position(start + direction.normalized().rotated(deg_to_rad(float(degrees))) * 2.4, 0.05))
		_outlined_path(view, arc, Color(WARNING_CORE, 0.78 * fade_alpha), 1.6 * _scale(view))
		if angles.size() >= 2:
			var tip: Vector2 = start + direction.normalized().rotated(deg_to_rad(float(angles[-1]))) * 2.4
			_outlined_diamond(view, tip, 0.15, WARNING_CORE)

static func _spawn_warning(view, warning: Dictionary, fade_alpha: float):
	var pos: Vector2 = warning.get("pos", Vector2.ZERO)
	var radius := float(warning.get("radius", 0.5))
	var progress := clampf(1.0 - float(warning.get("remaining", 0.0)) / maxf(0.01, float(warning.get("duration", 1.0))), 0.0, 1.0)
	var late := clampf((progress - 0.70) / 0.30, 0.0, 1.0)
	if late <= 0.001:
		_ground_dashed(view, pos, radius, Color(0.9, 0.69, 0.4, 0.42 * fade_alpha), 1.1)
		return
	var fill := Color(0.9, 0.69, 0.4, (0.025 + 0.075 * late) * fade_alpha)
	var line := Color(0.93, 0.76, 0.48, (0.60 + 0.28 * late) * fade_alpha)
	_ground(view, pos, radius, fill, line, 1.3 + 0.7 * late)
	_ground(view, pos, radius * (1.0 - 0.18 * late), Color.TRANSPARENT, Color(0.9, 0.69, 0.4, 0.20 * late * fade_alpha), 1.0)

static func _lane(view, start: Vector2, end: Vector2, radius: float, fill: Color, line: Color, line_width: float = 1.5):
	if not _front(view, start, 0.05) and not _front(view, end, 0.05):
		return
	var direction = end - start
	if direction.length_squared() < 0.000001:
		_ground_outlined(view, end, radius, fill, line, line_width)
		return
	var sf := _scale(view)
	var points := _lane_outline_points(view, start, end, radius)
	if fill.a > 0.0:
		_polygon(view, points, fill)
	var pixel_width := line_width * sf
	_path(view, points, _outline_color(line), _outline_width(view, pixel_width))
	_path(view, points, line, pixel_width)
	if _visible(view, end, 0.05, 0):
		var point: Vector2 = view.screen_position(end, 0.05)
		var axis = (point - view.screen_position(start, 0.05)).normalized()
		var normal_pixel = Vector2(-axis.y, axis.x)
		_outlined_path(view, PackedVector2Array([point - axis * 11 * sf + normal_pixel * 5 * sf, point, point - axis * 11 * sf - normal_pixel * 5 * sf]), Color(WARNING_CORE, line.a), maxf(1.1 * sf, line_width * 0.78 * sf))

static func _lane_outline_points(view, start: Vector2, end: Vector2, radius: float) -> PackedVector2Array:
	var direction := end - start
	var axis := direction.normalized()
	var normal := Vector2(-axis.y, axis.x) * radius
	var forward_angle := axis.angle()
	var points := PackedVector2Array([
		view.screen_position(start - normal, 0.05),
		view.screen_position(end - normal, 0.05),
	])
	for index in range(1, CAP_SEGMENTS):
		var angle := forward_angle - PI * 0.5 + PI * float(index) / float(CAP_SEGMENTS)
		points.append(view.screen_position(end + Vector2.from_angle(angle) * radius, 0.05))
	points.append(view.screen_position(end + normal, 0.05))
	points.append(view.screen_position(start + normal, 0.05))
	points.append(points[0])
	return points

static func _ground_outlined(view, pos: Vector2, radius: float, fill: Color, line: Color, width: float):
	if radius <= 0.0 or not _front(view, pos, 0.045):
		return
	var points = PackedVector2Array()
	for index in 49:
		points.append(view.screen_position(pos + Vector2.from_angle(index * TAU / 48.0) * radius, 0.045))
	if fill.a > 0.0:
		_polygon(view, points, fill)
	var pixel_width := width * _scale(view)
	_path(view, points, _outline_color(line), _outline_width(view, pixel_width))
	_path(view, points, line, pixel_width)

static func _outline_color(color: Color) -> Color:
	return Color(WARNING_SHADOW, clampf(color.a * 0.45, 0.0, 0.52))

static func _outline_width(view, pixel_width: float) -> float:
	var sf := _scale(view)
	return pixel_width + maxf(0.75 * sf, pixel_width * 0.18)

static func _outlined_path(view, points: PackedVector2Array, color: Color, width: float):
	_path(view, points, _outline_color(color), _outline_width(view, width))
	_path(view, points, color, width)

static func _outlined_diamond(view, pos: Vector2, radius: float, color: Color):
	if not _front(view, pos, 0.05):
		return
	var points := PackedVector2Array()
	for offset in [Vector2(0, -radius), Vector2(radius, 0), Vector2(0, radius), Vector2(-radius, 0), Vector2(0, -radius)]:
		points.append(view.screen_position(pos + offset, 0.05))
	_outlined_path(view, points, color, 1.3 * _scale(view))

static func _ground(view, pos: Vector2, radius: float, fill: Color, line: Color, width: float):
	if radius <= 0.0 or not _front(view, pos, 0.045):
		return
	var points = PackedVector2Array()
	for index in 49:
		points.append(view.screen_position(pos + Vector2.from_angle(index * TAU / 48.0) * radius, 0.045))
	if fill.a > 0.0:
		_polygon(view, points, fill)
	_path(view, points, line, width * _scale(view))

static func _ground_dashed(view, pos: Vector2, radius: float, line: Color, width: float, dashes: int = 12):
	if radius <= 0.0 or not _front(view, pos, 0.045):
		return
	var count := maxi(4, dashes)
	var step := TAU / float(count)
	for index in count:
		var from_angle := float(index) * step
		var to_angle := from_angle + step * 0.52
		_line(view, view.screen_position(pos + Vector2.from_angle(from_angle) * radius, 0.045), view.screen_position(pos + Vector2.from_angle(to_angle) * radius, 0.045), line, width * _scale(view))

static func _diamond(view, pos: Vector2, radius: float, color: Color):
	if not _front(view, pos, 0.05):
		return
	var points = PackedVector2Array()
	for offset in [Vector2(0, -radius), Vector2(radius, 0), Vector2(0, radius), Vector2(-radius, 0), Vector2(0, -radius)]:
		points.append(view.screen_position(pos + offset, 0.05))
	_path(view, points, color, 1.3 * _scale(view))

static func _visible(view, pos: Vector2, height: float, margin: float) -> bool:
	if not _front(view, pos, height):
		return false
	return Rect2(Vector2.ZERO, view.size).grow(margin * _scale(view)).has_point(view.screen_position(pos, height))

static func _front(view, pos: Vector2, height: float) -> bool:
	if view.get("camera") != null:
		return not view.camera.is_position_behind(Vector3(pos.x, height, -pos.y))
	return true

static func _scale(view) -> float:
	return float(view.size.x) / 1280.0

static func _reduced(view) -> bool:
	var options = view.get("_visual_options")
	return bool(options.get("reduced_motion", false)) if options is Dictionary else false

static func _disc(view, pos: Vector2, radius: float, color: Color):
	if not Rect2(Vector2.ZERO, view.size).grow(radius).has_point(pos):
		return
	var points = PackedVector2Array()
	for index in 21:
		points.append(pos + Vector2.from_angle(index * TAU / 20.0) * radius)
	_polygon(view, points, color)

static func _path(view, points: PackedVector2Array, color: Color, width: float):
	if points.size() < 2:
		return
	var run := PackedVector2Array()
	for index in range(1, points.size()):
		var clipped = _clip_line(points[index - 1], points[index], Rect2(Vector2.ZERO, view.size))
		if clipped.size() != 2:
			_draw_path_run(view, run, color, width)
			run = PackedVector2Array()
			continue
		if run.is_empty():
			run.append(clipped[0])
			run.append(clipped[1])
		elif run[run.size() - 1].distance_squared_to(clipped[0]) < 0.000001:
			run.append(clipped[1])
		else:
			_draw_path_run(view, run, color, width)
			run = PackedVector2Array([clipped[0], clipped[1]])
	_draw_path_run(view, run, color, width)

static func _draw_path_run(view, points: PackedVector2Array, color: Color, width: float):
	if points.size() == 2:
		view._overlay.draw_line(points[0], points[1], color, width, true)
	elif points.size() > 2:
		view._overlay.draw_polyline(points, color, width, true)

static func _line(view, from: Vector2, to: Vector2, color: Color, width: float):
	var clipped = _clip_line(from, to, Rect2(Vector2.ZERO, view.size))
	if clipped.size() == 2:
		view._overlay.draw_line(clipped[0], clipped[1], color, width, true)

static func _polygon(view, points: PackedVector2Array, color: Color):
	var clipped = _clip_polygon(points, Rect2(Vector2.ZERO, view.size))
	var clean = PackedVector2Array()
	for point in clipped:
		if clean.is_empty() or clean[clean.size() - 1].distance_squared_to(point) > 0.000001:
			clean.append(point)
	if clean.size() > 2 and clean[0].distance_squared_to(clean[clean.size() - 1]) < 0.000001:
		clean.remove_at(clean.size() - 1)
	if clean.size() >= 3 and not Geometry2D.triangulate_polygon(clean).is_empty():
		view._overlay.draw_colored_polygon(clean, color)

static func _clip_line(from: Vector2, to: Vector2, bounds: Rect2) -> PackedVector2Array:
	var delta = to - from
	var minimum = 0.0
	var maximum = 1.0
	var p = [-delta.x, delta.x, -delta.y, delta.y]
	var q = [from.x - bounds.position.x, bounds.end.x - from.x, from.y - bounds.position.y, bounds.end.y - from.y]
	for index in 4:
		if absf(p[index]) < 0.000001:
			if q[index] < 0.0:
				return PackedVector2Array()
		else:
			var fraction = q[index] / p[index]
			if p[index] < 0.0:
				minimum = maxf(minimum, fraction)
			else:
				maximum = minf(maximum, fraction)
			if minimum > maximum:
				return PackedVector2Array()
	return PackedVector2Array([from + delta * minimum, from + delta * maximum])

static func _clip_polygon(points: PackedVector2Array, bounds: Rect2) -> PackedVector2Array:
	var result = points
	for edge in 4:
		if result.is_empty():
			break
		var input = result
		result = PackedVector2Array()
		var previous = input[input.size() - 1]
		for current in input:
			var inside_current = _inside_edge(current, bounds, edge)
			var inside_previous = _inside_edge(previous, bounds, edge)
			if inside_current != inside_previous:
				var delta = current - previous
				var value = bounds.position.x if edge == 0 else (bounds.end.x if edge == 1 else (bounds.position.y if edge == 2 else bounds.end.y))
				var fraction = (value - previous.x) / delta.x if edge < 2 else (value - previous.y) / delta.y
				result.append(previous.lerp(current, clampf(fraction, 0.0, 1.0)))
			if inside_current:
				result.append(current)
			previous = current
	return result

static func _inside_edge(point: Vector2, bounds: Rect2, edge: int) -> bool:
	match edge:
		0: return point.x >= bounds.position.x
		1: return point.x <= bounds.end.x
		2: return point.y >= bounds.position.y
		_: return point.y <= bounds.end.y
