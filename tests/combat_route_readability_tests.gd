extends SceneTree
## Headless structure checks for the read-only attack preview geometry. This does
## not render, take screenshots, measure pixels, or exercise combat rules.

const Overlay = preload("res://scripts/presentation/route_combat_overlay.gd")
const OUTPUT = "res://build/qa/battle-hud-preview-20261026/attack-preview-results.json"

class DrawRecorder:
	extends RefCounted
	var calls: Array = []

	func draw_line(from: Vector2, to: Vector2, color: Color, width: float, antialiased: bool = true) -> void:
		calls.append({"kind": "line", "points": PackedVector2Array([from, to]), "color": color, "width": width, "antialiased": antialiased})

	func draw_polyline(points: PackedVector2Array, color: Color, width: float, antialiased: bool = true) -> void:
		calls.append({"kind": "polyline", "points": points.duplicate(), "color": color, "width": width, "antialiased": antialiased})

	func draw_colored_polygon(points: PackedVector2Array, color: Color) -> void:
		calls.append({"kind": "polygon", "points": points.duplicate(), "color": color, "width": 0.0, "antialiased": true})

class FakeView:
	extends RefCounted
	var size := Vector2(1280.0, 720.0)
	var camera = null
	var _overlay = DrawRecorder.new()

	func screen_position(pos: Vector2, height: float = 0.0) -> Vector2:
		return Vector2(520.0 + pos.x * 90.0, 340.0 - pos.y * 70.0 - height * 20.0)

var checks := 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("execute")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("Combat route readability: " + label)

func execute() -> void:
	var initial := _capture(1.0, false, "lane")
	var middle := _capture(0.5, false, "lane")
	var final := _capture(0.15, false, "lane")
	var active := _capture(0.0, true, "lane")
	var circle := _capture(1.0, false, "circle")

	var initial_fill := _max_polygon_alpha(initial)
	var middle_fill := _max_polygon_alpha(middle)
	var final_fill := _max_polygon_alpha(final)
	var active_fill := _max_polygon_alpha(active)
	check(initial_fill > 0.0, "initial warning keeps a visible footprint fill")
	check(middle_fill > initial_fill, "warning fill strengthens continuously")
	check(final_fill > middle_fill, "final warning is clearer than the opening frame")
	check(active_fill > final_fill, "active danger is clearer than final warning")

	var initial_outline := _largest_polyline(initial)
	var final_outline := _largest_polyline(final)
	check(not initial_outline.is_empty() and initial_outline.points.size() >= 10, "lane boundary is one continuous closed outline")
	check(_is_closed(initial_outline), "lane outline closes at its starting edge")
	check(not final_outline.is_empty() and final_outline.points.size() >= 10, "final lane keeps the same continuous closed outline")
	check(_is_closed(final_outline), "final lane outline has no seam")
	check(is_finite(float(initial_outline.get("width", 0.0))) and float(initial_outline.width) > 0.0, "continuous lane outline has a positive finite width")
	check(_max_shadow_ratio(initial) <= 1.60, "dark separation remains a narrow edge rather than a heavy red block")
	check(_line_alpha(initial_outline) >= 0.70, "initial warning outline is readable")
	check(_line_alpha(final_outline) > _line_alpha(initial_outline), "final warning outline strengthens")
	var tint: Color = initial_outline.get("color", Color.TRANSPARENT)
	check(tint.r > 0.65 and tint.g > 0.35 and tint.b > 0.35, "warning uses the softer rose palette")

	var circle_outline := _largest_polyline(circle)
	check(_max_polygon_alpha(circle) > 0.0, "circle warning is filled from the first frame")
	check(circle_outline.points.size() >= 45 and _is_closed(circle_outline), "circle warning uses one continuous closed outline")
	check(is_equal_approx(float(Overlay.WARNING_FADE_SECONDS), 0.08), "warning fade remains 80ms")

	var report = {
		"date": "2026-10-26",
		"checks": checks,
		"failures": failures.size(),
		"details": failures,
		"scope": "Headless draw-call structure only: continuous closed attack-preview outlines, progressive fill, softer rose palette, and 80ms fade constant. No screenshot, pixel readability, gameplay, natural route, performance, or rule evidence.",
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var file = FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("COMBAT ROUTE READABILITY checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _capture(remaining: float, active: bool, kind: String) -> Array:
	var view = FakeView.new()
	var danger := {
		"kind": kind,
		"from": Vector2.ZERO,
		"to": Vector2(2.0, 0.35),
		"pos": Vector2(2.0, 0.35),
		"radius": 0.5,
		"remaining": remaining,
		"duration": 1.0,
		"active": active,
	}
	Overlay._danger(view, danger)
	return view._overlay.calls

func _max_polygon_alpha(calls: Array) -> float:
	var maximum := 0.0
	for call in calls:
		if str(call.get("kind", "")) == "polygon":
			maximum = maxf(maximum, float(call.color.a))
	return maximum

func _largest_polyline(calls: Array) -> Dictionary:
	var candidates: Array = []
	var point_count := -1
	for call in calls:
		if str(call.get("kind", "")) != "polyline":
			continue
		var points: PackedVector2Array = call.points
		if points.size() > point_count:
			point_count = points.size()
			candidates = [call]
		elif points.size() == point_count:
			candidates.append(call)
	var primary: Dictionary = {}
	var brightness := -1.0
	for call in candidates:
		var color: Color = call.color
		var value := color.r + color.g + color.b
		if value > brightness:
			brightness = value
			primary = call
	return primary

func _is_closed(call: Dictionary) -> bool:
	if call.is_empty():
		return false
	var points: PackedVector2Array = call.points
	return points.size() >= 3 and points[0].distance_squared_to(points[points.size() - 1]) < 0.01

func _line_alpha(call: Dictionary) -> float:
	return float(call.get("color", Color.TRANSPARENT).a) if not call.is_empty() else 0.0

func _max_shadow_ratio(calls: Array) -> float:
	var widths: Array[float] = []
	for call in calls:
		if str(call.get("kind", "")) == "polyline":
			widths.append(float(call.width))
	if widths.size() < 2:
		return 1.0
	widths.sort()
	var primary := widths[widths.size() - 2]
	return widths[-1] / maxf(0.001, primary)
