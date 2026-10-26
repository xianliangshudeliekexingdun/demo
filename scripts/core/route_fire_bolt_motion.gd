extends RefCounted
## Pure released-flight geometry, shared by authoritative sweeps and read-only
## trail reconstruction. No clocks, actors, damage, rendering or random state.


static func validate(rules: Variant) -> bool:
	if not rules is Dictionary or int(rules.get("version", 0)) != 2: return false
	for key in ["curve_seconds", "curve_forward_m", "curve_side_m", "initial_angle_degrees", "start_speed_mps", "turn_speed_mps", "cruise_speed_mps", "acceleration_mps2", "curve_sweep_seconds", "length_samples", "close_target_fraction"]:
		if not (rules.get(key) is int or rules.get(key) is float) or not is_finite(float(rules[key])) or float(rules[key]) <= 0.0: return false
	return float(rules.initial_angle_degrees) < 90.0 and float(rules.cruise_speed_mps) > float(rules.turn_speed_mps) and float(rules.curve_sweep_seconds) <= float(rules.curve_seconds) and int(rules.length_samples) >= 8 and float(rules.close_target_fraction) < 0.5


static func build(origin: Vector2, target: Vector2, side: float, rules: Dictionary) -> Dictionary:
	var offset := target - origin
	var direction := offset.normalized() if offset.length_squared() > 0.00000001 else Vector2.UP
	var normal := Vector2(-direction.y, direction.x) * side
	var scale := minf(1.0, offset.length() * float(rules.close_target_fraction) / float(rules.curve_forward_m))
	var end := origin + direction * float(rules.curve_forward_m) * scale + normal * float(rules.curve_side_m) * scale
	var outgoing := (target - end).normalized() if target.distance_squared_to(end) > 0.00000001 else direction
	var start_axis := direction * cos(deg_to_rad(float(rules.initial_angle_degrees))) + normal * sin(deg_to_rad(float(rules.initial_angle_degrees)))
	var duration := float(rules.curve_seconds)
	var speed_scale := scale
	var points := PackedVector2Array([origin,
		origin + start_axis * float(rules.start_speed_mps) * speed_scale * duration / 3.0,
		end - outgoing * float(rules.turn_speed_mps) * speed_scale * duration / 3.0, end])
	var flight := {"version": 2, "target_pos": target, "controls": points, "direction": outgoing,
		"curve_seconds": duration, "turn_speed": float(rules.turn_speed_mps) * speed_scale,
		"cruise_speed": float(rules.cruise_speed_mps), "acceleration": float(rules.acceleration_mps2),
		"sweep_seconds": float(rules.curve_sweep_seconds), "curve_length": 0.0}
	var previous := origin
	for index in range(1, int(rules.length_samples) + 1):
		var point := position_at(flight, duration * float(index) / float(rules.length_samples))
		flight.curve_length = float(flight.curve_length) + previous.distance_to(point)
		previous = point
	return flight


static func position_at(flight: Dictionary, age: float) -> Vector2:
	var points: PackedVector2Array = flight.controls
	var duration := float(flight.curve_seconds)
	if age < duration:
		var u := clampf(age / duration, 0.0, 1.0)
		var v := 1.0 - u
		return points[0] * v * v * v + points[1] * 3.0 * v * v * u + points[2] * 3.0 * v * u * u + points[3] * u * u * u
	var t := maxf(0.0, age - duration)
	var acceleration_time := (float(flight.cruise_speed) - float(flight.turn_speed)) / float(flight.acceleration)
	var accelerating := minf(t, acceleration_time)
	var distance := float(flight.turn_speed) * accelerating + 0.5 * float(flight.acceleration) * accelerating * accelerating + maxf(0.0, t - acceleration_time) * float(flight.cruise_speed)
	return points[3] + Vector2(flight.direction) * distance


static func velocity_at(flight: Dictionary, age: float) -> Vector2:
	if age >= float(flight.curve_seconds):
		return Vector2(flight.direction) * minf(float(flight.cruise_speed), float(flight.turn_speed) + maxf(0.0, age - float(flight.curve_seconds)) * float(flight.acceleration))
	var p: PackedVector2Array = flight.controls
	var u := clampf(age / float(flight.curve_seconds), 0.0, 1.0)
	var v := 1.0 - u
	return ((p[1] - p[0]) * 3.0 * v * v + (p[2] - p[1]) * 6.0 * v * u + (p[3] - p[2]) * 3.0 * u * u) / float(flight.curve_seconds)


static func lifetime(flight: Dictionary, maximum_range: float) -> float:
	var distance := maxf(0.0, maximum_range - float(flight.curve_length))
	var v := float(flight.turn_speed)
	var top := float(flight.cruise_speed)
	var acceleration := float(flight.acceleration)
	var accelerating := (top - v) / acceleration
	var acceleration_distance := (v + top) * 0.5 * accelerating
	if distance <= acceleration_distance:
		return float(flight.curve_seconds) + (sqrt(v * v + 2.0 * acceleration * distance) - v) / acceleration
	return float(flight.curve_seconds) + accelerating + (distance - acceleration_distance) / top


static func age_at_segment_distance(flight: Dictionary, start: float, finish: float, distance: float) -> float:
	# Only used for a final, range-clipped short sweep. Monotonic on each of
	# the authoritative subdivisions; not a new collision or damage decision.
	var origin := position_at(flight, start)
	var low := start
	var high := finish
	for iteration in 24:
		var middle := (low + high) * 0.5
		if origin.distance_to(position_at(flight, middle)) < distance: low = middle
		else: high = middle
	return (low + high) * 0.5


static func trail(flight: Dictionary, age: float, seconds: float, interval: float, limit: int) -> PackedVector2Array:
	var points := PackedVector2Array([position_at(flight, age)])
	var cutoff := maxf(0.0, age - seconds)
	var step := maxf(interval, seconds / float(maxi(2, limit) - 1))
	var stamp := age - step
	while stamp > cutoff and points.size() < limit - 1:
		points.append(position_at(flight, stamp))
		stamp -= step
	if age > cutoff: points.append(position_at(flight, cutoff))
	return points
