extends Node3D
## Read-only, merged room identity kit. Geometry is supplied by the route catalog.
## North in core coordinates (+z) is world -Z. Tall masonry stays strictly beyond
## the four combat boundaries; only flush, non-interactive inlay/moss is inside.
## No lights, collision, particles, actors, gameplay clocks or rewards live here.

const SLATE := preload("res://assets/environment/courtyard_v2/painted_slate_albedo.png")
const FLOOR_Y := 0.039

var _stone: SurfaceTool
var _inlay: SurfaceTool
var _moss: SurfaceTool
var _half := Vector2.ZERO
var _bounds := AABB()
var _has_bounds := false
var _stone_count := 0
var _flat_count := 0
var _unsafe_vertices := 0
var _max_inside_height := 0.0
var _stone_tint := Color("59677b")
var _trim_tint := Color("776f59")
var _debug: Dictionary = {}


func build_room(room: Dictionary) -> Dictionary:
	name = "CourtyardRoomDressing"
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_stone_count = 0
	_flat_count = 0
	_unsafe_vertices = 0
	_max_inside_height = 0.0
	_has_bounds = false
	_stone = _surface()
	_inlay = _surface()
	_moss = _surface()
	var geometry: Dictionary = room.get("geometry", {})
	var floor_data: Dictionary = geometry.get("floor", {})
	if not floor_data.has("width") or not floor_data.has("depth"):
		_debug = {"room_id": room.get("room_id", 0), "mesh_count": 0, "error": "missing geometry.floor"}
		return _debug.duplicate(true)
	_half = Vector2(float(floor_data.width), float(floor_data.depth)) * 0.5
	var room_id := int(room.get("room_id", 0))
	var template_id := str(room.get("template_id", ""))
	# First-room art remains owned by the approved existing kit. This component
	# adds authored identity only to the newly commissioned route rooms.
	if room_id <= 1 or template_id.is_empty():
		_debug = {"room_id": room_id, "template_id": template_id, "mesh_count": 0,
			"stone_count": 0, "flat_count": 0, "unsafe_vertices": 0, "max_inside_height": 0.0}
		return _debug.duplicate(true)
	_stone_tint = Color("59677b")
	_trim_tint = Color("776f59")
	if room_id >= 10:
		_stone_tint = Color("566176")
		_trim_tint = Color("82745c")
	# Authoring identity now also carries a restrained palette: masonry stays cool,
	# while trim shifts warm or green so six templates are not only geometry.
	match template_id:
		"outer_court":
			_stone_tint = Color("58657c" if room_id < 10 else "556173")
			_trim_tint = Color("7a6f52" if room_id < 10 else "86795a")
		"processional_court":
			_stone_tint = Color("5b6480" if room_id < 10 else "57607b")
			_trim_tint = Color("836f4d" if room_id < 10 else "8d7856")
		"twin_pillars":
			_stone_tint = Color("59677b" if room_id < 10 else "556379")
			_trim_tint = Color("7d6f58" if room_id < 10 else "887a62")
		"long_colonnade":
			_stone_tint = Color("566179" if room_id < 10 else "525d75")
			_trim_tint = Color("776f59" if room_id < 10 else "827a63")
		"staggered_walls":
			_stone_tint = Color("5d6478" if room_id < 10 else "596074")
			_trim_tint = Color("6f6c52" if room_id < 10 else "7a775c")
		"broken_forecourt":
			_stone_tint = Color("555d72" if room_id < 10 else "51596e")
			_trim_tint = Color("8a7551" if room_id < 10 else "947f5b")
	match template_id:
		"outer_court":
			_outer_court()
		"processional_court":
			_processional_court()
		"twin_pillars":
			_twin_pillars(geometry)
		"long_colonnade":
			_long_colonnade(geometry)
		"staggered_walls":
			_staggered_walls(geometry)
		"broken_forecourt":
			_broken_forecourt(geometry)
		_:
			_debug = {"room_id": room_id, "template_id": template_id, "mesh_count": 0,
				"error": "unknown template"}
			return _debug.duplicate(true)
	var source_kind := str(room.get("source_kind", "normal"))
	var special_frame := source_kind in ["elite", "boss", "final_boss"] or room_id in [6, 12, 15]
	if special_frame:
		_destination_forecourt(room_id)
	_weathered_edges(room_id)
	_finish(_stone, "MergedRoomLandmarkMasonry", _stone_material())
	_finish(_inlay, "FlushRoomFloorInlay", _flat_material())
	_finish(_moss, "FlushRoomEdgeMoss", _flat_material())
	_debug = {"room_id": room_id, "template_id": template_id, "source_kind": source_kind,
		"mesh_count": get_child_count(), "stone_count": _stone_count, "flat_count": _flat_count,
		"unsafe_vertices": _unsafe_vertices, "max_inside_height": _max_inside_height,
		"destination_frame": special_frame, "aabb": _bounds, "room_half_size": _half}
	return _debug.duplicate(true)


func get_debug_state() -> Dictionary:
	return _debug.duplicate(true)


func _outer_court() -> void:
	# Broad octagonal court with one distant surviving gate corner. Keep the
	# central floor open so a later colonnade reads as a clear structural change.
	_polygon_band(Vector2.ZERO, Vector2(3.6, 4.4), 8, 0.065, _trim_tint.darkened(0.18))
	for side: float in [-1.0, 1.0]:
		_pier(Vector3(side * (_half.x + 1.45), -0.66, -_half.y * 0.58), 2.3 if side < 0 else 1.4, 0.88, 10 + int(side))
		_pier(Vector3(side * (_half.x + 2.9), -0.66, _half.y * 0.38), 1.15, 0.72, 20 + int(side))
		_broken_beam(Vector3(side * (_half.x + 2.0), -0.35, _half.y * 0.18), 2.6, false, 25 + int(side))
		_floor_line(Vector2(side * (_half.x - 1.5), -_half.y + 2.2), Vector2(side * (_half.x - 1.5), _half.y - 2.6), 0.07, Color("4b5661"))
	_threshold_mosaic(_half.y - 2.2, 3, 3.5)


func _processional_court() -> void:
	# Remains of an arrival gate frame the road OUTSIDE the southern limit;
	# repeated broad transverse floor joints establish the long processional axis.
	var south := _half.y + 1.35
	_gate_frame(south, 3.4, 2.75, true, 100)
	for course in range(7):
		var z := -_half.y + 3.1 + float(course) * ((_half.y * 2.0 - 6.2) / 6.0)
		_floor_line(Vector2(-3.5, z), Vector2(3.5, z), 0.08, _trim_tint.darkened(0.08))
		for side: float in [-1.0, 1.0]:
			_floor_line(Vector2(side * 3.5, z), Vector2(side * 3.5, z + 0.8), 0.10, _trim_tint.darkened(0.15))
	for side: float in [-1.0, 1.0]:
		_pier(Vector3(side * (_half.x + 1.5), -0.66, -_half.y + 2.9), 2.9, 1.0, 130 + int(side))
		_pier(Vector3(side * (_half.x + 1.5), -0.66, _half.y * 0.2), 1.6, 0.85, 140 + int(side))
		_floor_line(Vector2(side * 3.6, -_half.y + 2.4), Vector2(side * 3.6, _half.y - 1.8), 0.05, Color("64695f"))


func _twin_pillars(geometry: Dictionary) -> void:
	# Two distinct aligned pairs are echoed beyond the walls. The collars are
	# flush and follow the REAL block footprints instead of inventing collision.
	_block_collars(geometry, false)
	for side: float in [-1.0, 1.0]:
		for z: float in [-4.0, 4.0]:
			_pier(Vector3(side * (_half.x + 1.65), -0.66, z), 3.1 if z < 0 else 2.5, 0.94, 200 + int(side * 7 + z))
			var outer := side * (_half.x + 3.4)
			_pier(Vector3(outer, -0.66, z), 1.2 if z < 0 else 1.8, 0.75, 220 + int(side * 7 + z))
		_floor_line(Vector2(side * 3.0, -_half.y + 2.0), Vector2(side * 3.0, _half.y - 2.0), 0.055, _trim_tint.darkened(0.18))
	_polygon_band(Vector2.ZERO, Vector2(2.1, 2.1), 4, 0.075, _trim_tint)
	_threshold_mosaic(-_half.y + 2.7, 5, 4.0)


func _long_colonnade(geometry: Dictionary) -> void:
	_block_collars(geometry, true)
	# The surviving gallery lintels run north/south beyond both side walls.
	# They never cross the player's view or create a fake roof in the arena.
	for side: float in [-1.0, 1.0]:
		var x := side * (_half.x + 1.8)
		for bay in range(4):
			var z := -10.5 + float(bay) * 7.0
			var height := 3.25 if (bay + (1 if side > 0 else 0)) % 3 != 1 else 1.85
			_pier(Vector3(x, -0.66, z), height, 0.84, 300 + bay * 13 + int(side))
			if bay < 3 and height > 2.5:
				_block(Vector3(x, 2.35, z + 2.35), Vector3(0.74, 0.39, 4.85), _stone_tint.darkened(0.10), 350 + bay)
		_floor_line(Vector2(side * 3.4, -_half.y + 2.3), Vector2(side * 3.4, _half.y - 2.2), 0.11, _trim_tint.darkened(0.08))
		_floor_line(Vector2(side * 3.58, -_half.y + 2.3), Vector2(side * 3.58, _half.y - 2.2), 0.035, _trim_tint.darkened(0.12))
	for z: float in [-10.5, -3.5, 3.5, 10.5]:
		_floor_line(Vector2(-3.4, z), Vector2(3.4, z), 0.035, Color("4b5862"))
	_threshold_mosaic(_half.y - 3.3, 7, 4.0)


func _staggered_walls(geometry: Dictionary) -> void:
	_block_collars(geometry, false)
	# Surviving side wings alternate with the real cover; they remain outside
	# the boundaries. Floor bands share that broken, offset rhythm.
	for side: float in [-1.0, 1.0]:
		var z := side * -5.2
		_wall_wing(Vector3(side * (_half.x + 2.3), -0.66, z), 3.5, 2.0, 400 + int(side))
		_pier(Vector3(side * (_half.x + 1.4), -0.66, -z + 2.2), 2.0, 0.8, 430 + int(side))
		for offset: float in [-1.05, 1.05]:
			var target_z := z + offset
			_floor_line(Vector2(side * 3.0, target_z), Vector2(side * (_half.x - 1.3), target_z), 0.075, _trim_tint.darkened(0.10))
		_floor_line(Vector2(side * 3.0, z - 1.05), Vector2(side * 3.0, z + 1.05), 0.075, _trim_tint.darkened(0.10))
	_polygon_band(Vector2(0.0, 0.0), Vector2(1.5, 1.1), 4, 0.055, Color("717260"))
	_threshold_mosaic(_half.y - 2.7, 3, 2.7)


func _broken_forecourt(geometry: Dictionary) -> void:
	_block_collars(geometry, true)
	# Four former courts are suggested by surviving L corners; the combat
	# court itself remains one continuous plane with a broken central roundel.
	for side: float in [-1.0, 1.0]:
		for end: float in [-1.0, 1.0]:
			var z := end * _half.y * 0.54
			var base := Vector3(side * (_half.x + 2.0), -0.66, z)
			_pier(base, 2.2 if side * end > 0 else 1.35, 0.94, 500 + int(side * 13 + end * 7))
			_wall_wing(base + Vector3(side * 1.6, 0, 0.65), 2.5, 1.4, 530 + int(side * end))
			_broken_beam(base + Vector3(side * 0.6, 0.20, end * 1.5), 1.9, false, 560 + int(side * end))
	_polygon_band(Vector2.ZERO, Vector2(4.3, 4.3), 12, 0.085, _trim_tint.darkened(0.05), true)
	_polygon_band(Vector2.ZERO, Vector2(1.4, 1.4), 4, 0.065, _trim_tint.darkened(0.05))
	for side: float in [-1.0, 1.0]:
		_floor_line(Vector2(side * 2.5, -_half.y + 3.0), Vector2(side * 2.5, -5.2), 0.06, _trim_tint.darkened(0.20))
		_floor_line(Vector2(side * 2.5, 5.2), Vector2(side * 2.5, _half.y - 3.0), 0.06, _trim_tint.darkened(0.20))


func _destination_forecourt(room_id: int) -> void:
	# Ceremonial architecture only. There is no monster statue, boss seal,
	# altar interaction, new hazard or promise of an implemented special enemy.
	var north := -_half.y - 2.2
	_gate_frame(north, 4.7 if room_id == 15 else 4.1, 3.1 if room_id == 15 else 2.7, room_id != 12, 650 + room_id)
	for side: float in [-1.0, 1.0]:
		_pier(Vector3(side * 4.7, -0.66, north - 1.8), 1.7 if room_id == 15 else 1.2, 0.85, 700 + int(side))
		# Foundation edges all remain outside the northern boundary.
		_block(Vector3(side * 3.8, -0.47, north - 0.5), Vector3(1.4, 0.3, 3.2), _stone_tint.darkened(0.22), 730 + int(side))
	for band in range(3):
		var z := -_half.y + 2.5 + float(band) * 0.42
		_floor_line(Vector2(-2.5, z), Vector2(2.5, z), 0.06, _trim_tint.darkened(0.08))


func _block_collars(geometry: Dictionary, double_band: bool) -> void:
	for block_data: Dictionary in geometry.get("blocks", []):
		var center: Array = block_data.get("center", [])
		var size_data: Array = block_data.get("size", [])
		if center.size() != 2 or size_data.size() != 2:
			continue
		var pos := Vector2(float(center[0]), -float(center[1]))
		var radius := Vector2(float(size_data[0]), float(size_data[1])) * 0.5 + Vector2.ONE * 0.20
		_rect_band(pos, radius, 0.055, Color("4e5b64"))
		if double_band:
			_rect_band(pos, radius + Vector2.ONE * 0.14, 0.035, _trim_tint.darkened(0.15))


func _threshold_mosaic(z: float, diamonds: int, width: float) -> void:
	for i in range(diamonds):
		var x := (float(i) / float(maxi(1, diamonds - 1)) - 0.5) * width
		_polygon_band(Vector2(x, z), Vector2.ONE * 0.23, 4, 0.045, _trim_tint.darkened(0.06))


func _gate_frame(z: float, half_span: float, height: float, partial_lintel: bool, seed_value: int) -> void:
	for side: float in [-1.0, 1.0]:
		_pier(Vector3(side * half_span, -0.66, z), height, 1.0, seed_value + int(side))
	# A southern horizontal beam would conceal too much of the entry camera;
	# preserve two broken shoulders rather than a complete roof across Lina.
	var top := height - 0.62
	var beam_length := 1.9 if partial_lintel else 2.65
	for side: float in [-1.0, 1.0]:
		_block(Vector3(side * (half_span - beam_length * 0.35), top, z), Vector3(beam_length, 0.42, 0.76), _stone_tint, seed_value + 8 + int(side))
		_block(Vector3(side * half_span, top + 0.30, z), Vector3(1.22, 0.20, 1.0), _stone_tint.lightened(0.03), seed_value + 16 + int(side))


func _wall_wing(base: Vector3, width: float, height: float, seed_value: int) -> void:
	var rows := ceili(height / 0.39)
	for row in range(rows):
		for section in range(3):
			if row == rows - 1 and section == seed_value % 3:
				continue
			var span := width / 3.0
			var x := (float(section) - 1.0) * span + (0.10 if row % 2 else 0.0)
			_block(base + Vector3(x, 0.20 + float(row) * 0.39, 0), Vector3(span - 0.035, 0.36, 0.62), _stone_tint.darkened(0.13), seed_value + row * 7 + section)


func _broken_beam(base: Vector3, length: float, across: bool, seed_value: int) -> void:
	var dimensions := Vector3(length, 0.35, 0.66) if across else Vector3(0.66, 0.35, length)
	_block(base, dimensions, _stone_tint.darkened(0.18), seed_value)


func _pier(base: Vector3, height: float, width: float, seed_value: int) -> void:
	_block(base + Vector3(0, 0.10, 0), Vector3(width * 1.25, 0.20, width * 1.25), _stone_tint.darkened(0.10), seed_value)
	var courses := maxi(1, ceili((height - 0.38) / 0.42))
	var rise := (height - 0.22) / float(courses)
	for row in range(courses):
		_block(base + Vector3(0, 0.22 + (float(row) + 0.5) * rise, 0), Vector3(width * 0.79, rise - 0.025, width * 0.84), _stone_tint, seed_value + row * 3)
	_block(base + Vector3(0, height + 0.035, 0), Vector3(width * 1.14, 0.19, width * 1.18), _stone_tint.lightened(0.045), seed_value + 31)
	# Shallow dark panel and subdued trim are baked into this stone batch.
	var panel_y := base.y + height * 0.58
	var z := base.z + width * 0.425
	_quad(_stone, Vector3(base.x - width * 0.20, panel_y - 0.24, z), Vector3(base.x - width * 0.20, panel_y + 0.24, z), Vector3(base.x + width * 0.20, panel_y + 0.24, z), Vector3(base.x + width * 0.20, panel_y - 0.24, z), _stone_tint.darkened(0.26))


func _weathered_edges(room_id: int) -> void:
	# Flush, sparse perimeter staining supports the architecture without
	# competing with living enemies, warning circles or the bright cyan portal.
	for side: float in [-1.0, 1.0]:
		for patch in range(5):
			var z := -_half.y + 2.1 + float(patch) * ((_half.y * 2.0 - 4.2) / 4.0)
			var x := side * (_half.x - 0.43 - float((patch + room_id) % 2) * 0.24)
			var extent := Vector2(0.30, 0.66 + float((patch + room_id) % 3) * 0.11)
			_moss_patch(Vector2(x, z), extent, room_id * 13 + patch + int(side))


func _moss_patch(center: Vector2, extent: Vector2, seed_value: int) -> void:
	var tint := Color("30433e")
	var pos := Vector3(center.x, FLOOR_Y + 0.001, center.y)
	for segment in range(9):
		var a := float(segment) * TAU / 9.0
		var b := float(segment + 1) * TAU / 9.0
		var ra := 0.81 + _noise(seed_value + segment) * 0.18
		var rb := 0.81 + _noise(seed_value + segment + 1) * 0.18
		_triangle(_moss, pos, pos + Vector3(cos(b) * extent.x * rb, 0, sin(b) * extent.y * rb), pos + Vector3(cos(a) * extent.x * ra, 0, sin(a) * extent.y * ra), tint)
	_flat_count += 1


func _polygon_band(center: Vector2, radius: Vector2, sides: int, thickness: float, tint: Color, broken: bool = false) -> void:
	for segment in range(sides):
		if broken and segment % 4 == 1:
			continue
		var a := float(segment) * TAU / float(sides)
		var b := float(segment + 1) * TAU / float(sides)
		_floor_line(center + Vector2(cos(a), sin(a)) * radius, center + Vector2(cos(b), sin(b)) * radius, thickness, tint)


func _rect_band(center: Vector2, half_size: Vector2, thickness: float, tint: Color) -> void:
	var points := [center + Vector2(-half_size.x, -half_size.y), center + Vector2(half_size.x, -half_size.y), center + Vector2(half_size.x, half_size.y), center + Vector2(-half_size.x, half_size.y)]
	for i in range(4):
		_floor_line(points[i], points[(i + 1) % 4], thickness, tint)


func _floor_line(a: Vector2, b: Vector2, thickness: float, tint: Color) -> void:
	var direction := (b - a).normalized()
	var perpendicular := Vector2(-direction.y, direction.x) * thickness * 0.5
	var points := [a - perpendicular, a + perpendicular, b + perpendicular, b - perpendicular]
	_quad(_inlay, Vector3(points[0].x, FLOOR_Y, points[0].y), Vector3(points[1].x, FLOOR_Y, points[1].y), Vector3(points[2].x, FLOOR_Y, points[2].y), Vector3(points[3].x, FLOOR_Y, points[3].y), tint)
	_flat_count += 1


func _block(pos: Vector3, dimensions: Vector3, tint: Color, seed_value: int) -> void:
	var x := dimensions.x * 0.5
	var y := dimensions.y * 0.5
	var z := dimensions.z * 0.5
	var bevel := minf(0.065, minf(x, minf(y, z)) * 0.60)
	var color := tint.lightened(_noise(seed_value) * 0.035)
	var outline := PackedVector2Array([Vector2(-x + bevel, -z), Vector2(x - bevel, -z), Vector2(x, -z + bevel), Vector2(x, z - bevel), Vector2(x - bevel, z), Vector2(-x + bevel, z), Vector2(-x, z - bevel), Vector2(-x, -z + bevel)])
	for i in range(8):
		var j := (i + 1) % 8
		var a := outline[i]
		var b := outline[j]
		var inset_a := a * Vector2((x - bevel * 0.65) / x, (z - bevel * 0.65) / z)
		var inset_b := b * Vector2((x - bevel * 0.65) / x, (z - bevel * 0.65) / z)
		var low_a := pos + Vector3(a.x, -y, a.y)
		var low_b := pos + Vector3(b.x, -y, b.y)
		var shoulder_a := pos + Vector3(a.x, y - bevel, a.y)
		var shoulder_b := pos + Vector3(b.x, y - bevel, b.y)
		var top_a := pos + Vector3(inset_a.x, y, inset_a.y)
		var top_b := pos + Vector3(inset_b.x, y, inset_b.y)
		_quad(_stone, low_a, shoulder_a, shoulder_b, low_b, color.darkened(0.12))
		_quad(_stone, shoulder_a, top_a, top_b, shoulder_b, color.lightened(0.04))
		_triangle(_stone, pos + Vector3(0, y, 0), top_b, top_a, color)
		_triangle(_stone, pos + Vector3(0, -y, 0), low_a, low_b, color.darkened(0.20))
	_stone_count += 1


func _surface() -> SurfaceTool:
	var result := SurfaceTool.new()
	result.begin(Mesh.PRIMITIVE_TRIANGLES)
	return result


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	for vertex: Vector3 in [a, b, c]:
		surface.set_color(tint)
		surface.add_vertex(vertex)
		if absf(vertex.x) < _half.x and absf(vertex.z) < _half.y:
			_max_inside_height = maxf(_max_inside_height, vertex.y)
			if vertex.y > 0.06:
				_unsafe_vertices += 1
		if not _has_bounds:
			_bounds = AABB(vertex, Vector3.ZERO)
			_has_bounds = true
		else:
			_bounds = _bounds.expand(vertex)


func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, tint: Color) -> void:
	_triangle(surface, a, b, c, tint)
	_triangle(surface, a, c, d, tint)


func _finish(surface: SurfaceTool, node_name: String, material: Material) -> void:
	surface.generate_normals()
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = surface.commit()
	instance.material_override = material
	if node_name != "MergedRoomLandmarkMasonry":
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _stone_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D approved_slate : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 stone_position;
void vertex() { stone_position = VERTEX; }
void fragment() {
    vec3 tex = texture(approved_slate, stone_position.xz * 0.16).rgb;
    float weather = sin(stone_position.x * 3.1 + stone_position.z * 1.7 + stone_position.y * 3.3);
    ALBEDO = COLOR.rgb * (1.0 + weather * 0.026) * mix(vec3(1.0), tex * 1.7, 0.15);
    ROUGHNESS = 0.96;
    SPECULAR = 0.28;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("approved_slate", SLATE)
	return material


func _flat_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	return material


func _noise(seed_value: int) -> float:
	return sin(float(seed_value) * 12.9898 + 4.1414) * 0.5
