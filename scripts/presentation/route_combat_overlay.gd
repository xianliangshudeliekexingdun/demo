extends RefCounted
## Read-only route combat drawing. Every dangerous footprint comes from core.
## Pixel primitives are clipped to the view; this file never creates combat state.

const ENEMY = Color("ff776f")
const ENEMY_CORE = Color("ffb5ba")
const FRIENDLY = Color("efbf73")
const FIRE = Color("f09b58")


static func draw(view, state: Dictionary):
	for actor in state.get("actors", []):
		if not actor.has("type_id") or float(actor.get("health", 0.0)) <= 0.0:
			continue
		if bool(actor.get("body_contact_enabled", false)):
			_ground(view, actor.pos, float(actor.radius), Color.TRANSPARENT, Color(ENEMY, 0.54), 1.1)
		var danger: Dictionary = actor.get("danger", {})
		if not danger.is_empty():
			_danger(view, danger)
		for boss_danger in actor.get("dangers", []):
			_danger(view, boss_danger)
	for projectile in state.get("enemy_projectiles", []):
		var pos: Vector2 = projectile.get("pos", Vector2.ZERO)
		if not _visible(view, pos, 0.55, 20.0):
			continue
		var p: Vector2 = view.screen_position(pos, 0.55)
		var direction: Vector2 = projectile.get("direction", Vector2(0, -1))
		var back: Vector2 = view.screen_position(pos - direction, 0.55)
		var axis = (p - back).normalized()
		var sf = _scale(view)
		var physical_radius: float = maxf(2.6 * sf, p.distance_to(view.screen_position(pos + Vector2(float(projectile.get("radius", 0.18)), 0), 0.55)))
		# A dark separation halo keeps the hostile shot readable over fire, gold
		# trim and bright spell impacts without enlarging its real footprint.
		_disc(view, p, physical_radius * 2.35, Color(0.05, 0.015, 0.035, 0.55))
		_line(view, p - axis * 17.0 * sf, p, Color(ENEMY, 0.64), physical_radius * 1.5)
		_disc(view, p, physical_radius * 1.8, Color(0.9, 0.2, 0.42, 0.14))
		_disc(view, p, physical_radius, Color("e75d91"))
		_disc(view, p, physical_radius * 0.40, ENEMY_CORE)
	# Friendly magic is rendered by the cached 3D shader batches. Keep hostile
	# footprints above it so flame art cannot hide a live attack's safe gaps.
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


static func draw_effect(view, effect: Dictionary) -> bool:
	var kind = str(effect.get("kind", ""))
	if kind not in ["rain_impact", "bomb_flight", "bomb_impact", "aftershock", "wave", "shield_restore", "summon", "enemy_warning", "enemy_mark", "enemy_shot", "artifact_patch", "artifact_explosion", "artifact_speed", "artifact_cooldown", "artifact_acquired"]:
		return false
	# enemy_warning is drawn exclusively from the actor's present danger dictionary.
	# The emitted historical event must not leave a stale footprint after an interrupt.
	if kind == "enemy_warning":
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
		"enemy_mark":
			_ground(view, pos, radius, Color(ENEMY, alpha * 0.18), Color(ENEMY_CORE, alpha), 2.2)
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
	var fill = Color(ENEMY, 0.16 if active else 0.055 + progress * 0.055)
	var line = Color(ENEMY_CORE if active else ENEMY, 0.95)
	if kind == "circle":
		_ground(view, danger.get("pos", end), radius, fill, line, 2.0)
		if not active:
			_ground(view, danger.get("pos", end), radius * (1.0 - progress), Color.TRANSPARENT, Color(ENEMY, 0.3), 1.0)
	elif kind == "lane":
		_lane(view, start, end, radius, fill, line)
	elif kind in ["ray", "fan"]:
		var direction = end - start
		for degrees in danger.get("spread_degrees", [0.0]):
			var ray_end = start + direction.rotated(deg_to_rad(float(degrees)))
			_lane(view, start, ray_end, radius, Color(ENEMY, 0.025 + progress * 0.035), Color(ENEMY, 0.65))
	elif kind == "ring":
		var direction: Vector2 = end - start
		for degrees in danger.get("spread_degrees", []):
			_lane(view, start, start + direction.rotated(deg_to_rad(float(degrees))), radius, Color(ENEMY, 0.018), Color(ENEMY, 0.52))
		# A short open chevron marks the actual omitted spokes, never a safe disk.
		var axis: Vector2 = direction.normalized()
		var half_gap: float = TAU / maxf(1.0, float(danger.get("nominal_count", 1))) * 1.5
		var a: Vector2 = start + axis.rotated(-half_gap) * 2.1
		var b: Vector2 = start + axis * 2.8
		var c: Vector2 = start + axis.rotated(half_gap) * 2.1
		_line(view, view.screen_position(a, 0.05), view.screen_position(b, 0.05), Color(ENEMY_CORE, 0.85), 1.6 * _scale(view))
		_line(view, view.screen_position(b, 0.05), view.screen_position(c, 0.05), Color(ENEMY_CORE, 0.85), 1.6 * _scale(view))
	elif kind == "sweep":
		var direction: Vector2 = end - start
		var angles: Array = danger.get("spread_degrees", [])
		var first: int = int(danger.get("shot_index", 0)) if active else 0
		for index in range(first, angles.size()):
			_lane(view, start, start + direction.rotated(deg_to_rad(float(angles[index]))), radius, Color(ENEMY, 0.018), Color(ENEMY, 0.48 if index != first else 0.85))
		# Ordered points show the fixed sweep direction; aim never follows art.
		var arc := PackedVector2Array()
		for degrees in angles:
			arc.append(view.screen_position(start + direction.normalized().rotated(deg_to_rad(float(degrees))) * 2.4, 0.05))
		_path(view, arc, Color(ENEMY_CORE, 0.75), 1.6 * _scale(view))
		if angles.size() >= 2:
			var tip: Vector2 = start + direction.normalized().rotated(deg_to_rad(float(angles[-1]))) * 2.4
			_diamond(view, tip, 0.15, ENEMY_CORE)


static func _lane(view, start: Vector2, end: Vector2, radius: float, fill: Color, line: Color):
	if not _front(view, start, 0.05) and not _front(view, end, 0.05):
		return
	var direction = (end - start).normalized()
	if direction.length_squared() < 0.000001:
		_ground(view, end, radius, fill, line, 1.5)
		return
	var normal = Vector2(-direction.y, direction.x) * radius
	var polygon = PackedVector2Array([view.screen_position(start - normal, 0.05), view.screen_position(end - normal, 0.05), view.screen_position(end + normal, 0.05), view.screen_position(start + normal, 0.05)])
	_polygon(view, polygon, fill)
	_line(view, polygon[0], polygon[1], line, 1.5 * _scale(view))
	_line(view, polygon[3], polygon[2], line, 1.5 * _scale(view))
	_ground(view, end, radius, Color.TRANSPARENT, line, 1.2)
	if _visible(view, end, 0.05, 0):
		var point: Vector2 = view.screen_position(end, 0.05)
		var axis = (point - view.screen_position(start, 0.05)).normalized()
		var normal_pixel = Vector2(-axis.y, axis.x)
		var sf = _scale(view)
		_path(view, PackedVector2Array([point - axis * 9 * sf + normal_pixel * 4 * sf, point, point - axis * 9 * sf - normal_pixel * 4 * sf]), line, 1.6 * sf)


static func _ground(view, pos: Vector2, radius: float, fill: Color, line: Color, width: float):
	if radius <= 0.0 or not _front(view, pos, 0.045):
		return
	var points = PackedVector2Array()
	for index in 49:
		points.append(view.screen_position(pos + Vector2.from_angle(index * TAU / 48.0) * radius, 0.045))
	if fill.a > 0.0:
		_polygon(view, points, fill)
	_path(view, points, line, width * _scale(view))


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
	for index in range(1, points.size()):
		_line(view, points[index - 1], points[index], color, width)


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
