extends Node3D
## Read-only setting beyond the combat perimeter. The supplied half-size comes
## from the room snapshot; none of this architecture owns collision or state.
## Core north (+Y) is world north (-Z), matching FirstRoomView._point().

const SLATE := preload("res://assets/environment/courtyard_v2/painted_slate_albedo.png")

var _stone: SurfaceTool
var _earth: SurfaceTool
var _moss: SurfaceTool
var _detail: SurfaceTool
var _stone_count := 0
var _bounds := AABB()
var _has_bounds := false


func build_room(half: Vector2) -> Dictionary:
	name = "CourtyardSurroundings"
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_stone_count = 0
	_has_bounds = false
	_stone = _surface()
	_earth = _surface()
	_moss = _surface()
	_detail = _surface()
	_ground(half)
	_entrance_approach(half.y)
	_side_ruins(half)
	_northern_remains(half.y)
	_finish(_earth, "ContinuousAncientGround", _earth_material())
	_finish(_stone, "MergedOuterMasonry", _stone_material())
	_finish(_moss, "OuterMossAndRootStains", _flat_material())
	_finish(_detail, "FadedOuterStoneInlay", _flat_material())
	return {"root": self, "mesh_count": get_child_count(), "stone_count": _stone_count, "aabb": _bounds}


func _surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	return surface


func _ground(half: Vector2) -> void:
	# Terrain continues underneath the room plinth. Broad low-contrast facets
	# replace a floating rectangular island without becoming a second arena.
	var extent := half + Vector2(19.0, 22.0)
	var cell := 3.0
	var columns := ceili(extent.x * 2.0 / cell)
	var rows := ceili(extent.y * 2.0 / cell)
	for row in range(rows):
		for column in range(columns):
			var x0 := -extent.x + float(column) * cell
			var z0 := -extent.y + float(row) * cell
			var x1 := minf(x0 + cell, extent.x)
			var z1 := minf(z0 + cell, extent.y)
			var a := Vector3(x0, _ground_height(x0, z0), z0)
			var b := Vector3(x0, _ground_height(x0, z1), z1)
			var c := Vector3(x1, _ground_height(x1, z1), z1)
			var d := Vector3(x1, _ground_height(x1, z0), z0)
			var tint := Color("25271f").lightened(_noise(column + row * 17) * 0.028)
			_quad(_earth, a, b, c, d, tint)
	# A worn apron emerges from the foundation, with staggered exposed blocks.
	for side: float in [-1.0, 1.0]:
		for i in range(10):
			var z := -half.y - 0.5 + float(i) * (half.y * 2.0 + 1.0) / 9.0
			_block(Vector3(side * (half.x + 0.62), -0.57, z), Vector3(0.62, 0.37, 1.45), 0.045, Color("3c4555"), 100 + i)


func _ground_height(x: float, z: float) -> float:
	return -0.72 + sin(x * 0.32 + z * 0.11) * cos(z * 0.27) * 0.065


func _entrance_approach(depth: float) -> void:
	var stone := Color("555e71")
	# Six shallow treads connect the existing threshold to the lower old road.
	# The last tread meets the road; there is no isolated stair-shaped plinth.
	for step in range(6):
		var z := depth + 0.42 + float(step) * 0.38
		var top := 0.015 - float(step) * 0.105
		var height := top + 0.79
		for section in range(3):
			_block(Vector3((float(section) - 1.0) * 1.14, top - height * 0.5, z), Vector3(1.12, height, 0.41), 0.045, stone, 200 + step * 3 + section)
	# Continue the same paving down an old approach instead of ending at black.
	for course in range(14):
		var z := depth + 2.7 + float(course) * 0.93
		var drift := -maxf(0.0, float(course) - 6.0) * 0.13
		for section in range(3):
			var stagger := 0.15 if course % 2 == 1 else 0.0
			var x := (float(section) - 1.0) * 1.10 + drift + stagger
			var top := -0.56 + _noise(course * 3 + section) * 0.018
			_block(Vector3(x, top - 0.075, z), Vector3(1.075, 0.15, 0.89), 0.04, stone.darkened(0.10 + float(course) * 0.007), 250 + course * 3 + section)
	# Low parapet fragments frame the arrival without concealing Lina's feet.
	for side: float in [-1.0, 1.0]:
		for section in range(4):
			var z := depth + 1.65 + float(section) * 1.25
			var top := -0.10 - float(section) * 0.075
			var height := top + 0.79
			_block(Vector3(side * 2.08, top - height * 0.5, z), Vector3(0.48, height, 1.19), 0.06, stone.darkened(0.20), 301 + section)
		_pier(Vector3(side * 2.16, -0.78, depth + 5.75), 1.22 if side < 0 else 0.84, 320 + int(side))
		_moss_patch(Vector3(side * 1.87, -0.54, depth + 3.5), Vector2(0.28, 0.76), 33 + int(side))
		for chip in range(3):
			_block(Vector3(side * (2.68 + float(chip) * 0.34), -0.65, depth + 4.2 + float(chip) * 0.62), Vector3(0.46, 0.20, 0.34), 0.055, stone.darkened(0.28), 340 + chip)
	# Subtle inlay belongs to the historical road, not to an interactive marker.
	_line(Vector3(-0.33, -0.545, depth + 3.0), Vector3(0.33, -0.545, depth + 3.0), 0.022, Color("69614b"))


func _side_ruins(half: Vector2) -> void:
	var slate := Color("454f63")
	for side: float in [-1.0, 1.0]:
		# Narrow galleries run parallel to the courtyard. Their architecture stays
		# beyond the solid boundary; the arena retains its clear silhouette.
		var gallery_x := side * (half.x + 2.20)
		for course in range(ceili((half.y * 2.0 + 3.0) / 1.15)):
			var z := -half.y - 1.0 + float(course) * 1.15
			for strip in range(2):
				var seed_value := 400 + course * 2 + strip + int(side) * 23
				if (course + strip * 2 + (3 if side > 0 else 0)) % 9 in [2, 3]:
					continue
				var x := gallery_x + (float(strip) - 0.5) * 1.12 + _noise(seed_value) * 0.06
				var tilt := Vector3(_noise(seed_value + 4) * 0.06, _noise(seed_value + 9) * 0.11, _noise(seed_value + 7) * 0.04)
				_block(Vector3(x, -0.635 + _noise(seed_value) * 0.04, z), Vector3(1.05, 0.32, 1.07), 0.035, slate.darkened(0.18 + absf(_noise(seed_value)) * 0.13), seed_value, tilt)
		# Uneven interrupted bays, rather than a solid second wall or tall boxes.
		for bay in range(6):
			var ratio: float = [-0.91, -0.57, -0.13, 0.19, 0.62, 0.88][bay]
			var z := ratio * half.y + (0.46 * sin(float(bay) * 2.4) if side > 0 else 0.0)
			var outer_x := side * (half.x + 3.75 + _noise(bay * 11 + int(side)) * 0.55)
			var height: float = [1.45, 0.73, 1.15, 0.52, 1.78, 0.94][(bay + (2 if side > 0 else 0)) % 6]
			if bay != (2 if side > 0 else 4):
				_pier(Vector3(outer_x, -0.78, z), height, 500 + bay * 11 + int(side))
			if bay % 3 != 1:
				_wall_fragment(Vector3(outer_x + side * 0.09, -0.78, z + 0.9), 1.6 + absf(_noise(bay + 5)) * 1.6, 2 if bay % 2 == 0 else 1, false, 550 + bay + int(side) * 9)
			else:
				_rubble_cluster(Vector3(outer_x - side * 0.45, -0.68, z + 0.7), 570 + bay + int(side) * 13, 1.05)
			if bay % 2 == 0:
				_moss_patch(Vector3(outer_x - side * 0.32, -0.586, z + 0.2), Vector2(0.55, 0.75), 58 + bay)
		# One collapsed roof beam in each gallery gives damage a readable cause.
		_block(Vector3(side * (half.x + 2.35), -0.40, half.y * (0.39 if side > 0 else -0.44)), Vector3(2.02, 0.27, 0.52), 0.075, slate.darkened(0.19), 610 + int(side))
		for debris in range(3):
			var z: float = half.y * [-0.71, 0.12, 0.74][debris] + (1.1 if side > 0 else -0.45)
			var x := side * (half.x + 4.8 + _noise(debris + int(side)) * 1.25)
			_rubble_cluster(Vector3(x, -0.70, z), 650 + debris * 17 + int(side) * 23, 0.85)
		# Faint remote foundations imply other ruined rooms without adding routes.
		var remote_x := side * (half.x + 7.1)
		for fragment in range(3):
			var z: float = [-0.68, 0.07, 0.81][fragment] * half.y + _noise(fragment + int(side)) * 1.8
			_wall_fragment(Vector3(remote_x, -0.78, z), 3.5, 1 + fragment % 2, false, 700 + fragment)
			_wall_fragment(Vector3(remote_x + side * 1.6, -0.78, z - 1.65), 3.0, 1, true, 740 + fragment)


func _northern_remains(depth: float) -> void:
	var slate := Color("47576a")
	# The portal has architecture behind it: a short processional causeway and
	# the surviving corners of a former chamber. Its value stays below the gate.
	for course in range(9):
		for section in range(3):
			var seed_value := 800 + course * 3 + section
			if course > 3 and ((course + section * 2) % 5 == 1 or (course > 6 and section != 1)):
				continue
			var x := (float(section) - 1.0) * 1.12 + _noise(seed_value) * (0.06 + float(course) * 0.03)
			var z := -depth - 0.8 - float(course) * 1.08 + _noise(seed_value + 8) * 0.08
			var subsidence := maxf(0.0, float(course) - 2.0) * 0.025
			var tilt := Vector3(_noise(seed_value + 11) * 0.055, _noise(seed_value + 13) * 0.14, _noise(seed_value + 17) * 0.035)
			_block(Vector3(x, -0.54 - subsidence, z), Vector3(1.06, 0.46, 1.01), 0.055, slate.darkened(0.04 + float(course) * 0.04), seed_value, tilt)
	for side: float in [-1.0, 1.0]:
		_pier(Vector3(side * 2.52, -0.78, -depth - 3.75), 1.68 if side < 0 else 1.13, 850 + int(side))
		_wall_fragment(Vector3(side * 3.08, -0.78, -depth - 6.65), 3.7, 2 if side < 0 else 1, false, 870 + int(side))
		_wall_fragment(Vector3(side * 3.25, -0.78, -depth - 8.7), 2.50, 2, true, 890 + int(side))
		_moss_patch(Vector3(side * 1.92, -0.57, -depth - 4.8), Vector2(0.55, 0.90), 91 + int(side))
		for chip in range(4):
			_block(Vector3(side * (3.8 + float(chip) * 0.45), -0.65, -depth - 7.8 + float(chip % 2) * 0.65), Vector3(0.53, 0.20, 0.44), 0.05, slate.darkened(0.22), 910 + chip)
	# A broken cross lintel rests on the earth, rather than a second hero arch.
	_block(Vector3(-1.40, -0.54, -depth - 10.60), Vector3(2.80, 0.38, 0.72), 0.09, slate.darkened(0.29), 950, Vector3(0.07, -0.22, 0.025))
	_rubble_cluster(Vector3(1.15, -0.72, -depth - 8.1), 970, 1.05)


func _wall_fragment(base: Vector3, length: float, rows: int, east_west: bool, seed_value: int) -> void:
	for row in range(rows):
		var sections := 3 if row % 2 == 0 else 4
		for section in range(sections):
			if row > 0 and section == sections - 1 and seed_value % 2 == 0:
				continue
			var span := length / float(sections)
			var offset := (float(section) + 0.5) * span - length * 0.5 + float(row) * 0.16
			var center := base + Vector3(offset if east_west else 0.0, 0.18 + float(row) * 0.37, 0.0 if east_west else offset)
			var size := Vector3(span - 0.025, 0.34, 0.43) if east_west else Vector3(0.43, 0.34, span - 0.025)
			var tilt := Vector3(0.025 * _noise(seed_value + section), _noise(seed_value + section * 7) * 0.09, 0.035 * _noise(seed_value + row))
			_block(center, size, 0.06, Color("414b58"), seed_value + section + row * 13, tilt)


func _rubble_cluster(center: Vector3, seed_value: int, scale_factor: float) -> void:
	# Debris settles in irregular groups around a failed bay instead of one
	# identical stone at every interval. Most of each block is buried in soil.
	for piece in range(5):
		var a := float(piece) * 2.11 + float(seed_value) * 0.17
		var radius := (0.22 + float(piece % 3) * 0.31) * scale_factor
		var offset := Vector3(cos(a) * radius, 0, sin(a) * radius)
		var size := Vector3(0.35 + absf(_noise(seed_value + piece)) * 0.67, 0.22 + float(piece % 2) * 0.13, 0.31 + absf(_noise(seed_value + piece * 3)) * 0.39) * scale_factor
		var tilt := Vector3(_noise(seed_value + piece * 5) * 0.38, a, _noise(seed_value + piece * 7) * 0.29)
		_block(center + offset + Vector3(0, 0.02 + size.y * 0.15, 0), size, 0.06, Color("424b54").darkened(absf(_noise(seed_value + piece)) * 0.20), seed_value + piece, tilt)


func _pier(base: Vector3, height: float, seed_value: int) -> void:
	var tint := Color("4b566a")
	_block(base + Vector3(0, 0.09, 0), Vector3(0.88, 0.18, 0.88), 0.065, tint.darkened(0.13), seed_value)
	var rows := maxi(1, ceili((height - 0.36) / 0.36))
	var course_height := (height - 0.20) / float(rows)
	for course in range(rows):
		_block(base + Vector3(0, 0.18 + (float(course) + 0.5) * course_height, 0), Vector3(0.56, course_height - 0.025, 0.59), 0.05, tint, seed_value + course * 7)
	if height > 1.3:
		_block(base + Vector3(0, height + 0.04, 0), Vector3(0.79, 0.17, 0.82), 0.065, tint.lightened(0.035), seed_value + 19)


func _block(pos: Vector3, dimensions: Vector3, bevel: float, tint: Color, seed_value: int, tilt: Vector3 = Vector3.ZERO) -> void:
	var x := dimensions.x * 0.5
	var y := dimensions.y * 0.5
	var z := dimensions.z * 0.5
	var b := minf(bevel, minf(x, minf(y, z)) * 0.70)
	var color := tint.lightened(_noise(seed_value) * 0.045)
	var local_basis := Basis.from_euler(tilt)
	var outline := PackedVector2Array([Vector2(-x + b, -z), Vector2(x - b, -z), Vector2(x, -z + b), Vector2(x, z - b), Vector2(x - b, z), Vector2(-x + b, z), Vector2(-x, z - b), Vector2(-x, -z + b)])
	for i in range(8):
		var j := (i + 1) % 8
		var a := outline[i]
		var c := outline[j]
		var inset_a := Vector2(a.x * (x - b * 0.65) / x, a.y * (z - b * 0.65) / z)
		var inset_c := Vector2(c.x * (x - b * 0.65) / x, c.y * (z - b * 0.65) / z)
		var bottom_a := pos + local_basis * Vector3(a.x, -y, a.y)
		var bottom_c := pos + local_basis * Vector3(c.x, -y, c.y)
		var shoulder_a := pos + local_basis * Vector3(a.x, y - b, a.y)
		var shoulder_c := pos + local_basis * Vector3(c.x, y - b, c.y)
		var top_a := pos + local_basis * Vector3(inset_a.x, y, inset_a.y)
		var top_c := pos + local_basis * Vector3(inset_c.x, y, inset_c.y)
		_quad(_stone, bottom_a, shoulder_a, shoulder_c, bottom_c, color.darkened(0.12))
		_quad(_stone, shoulder_a, top_a, top_c, shoulder_c, color.lightened(0.065))
		_triangle(_stone, pos + local_basis * Vector3(0, y, 0), top_c, top_a, color)
		_triangle(_stone, pos + local_basis * Vector3(0, -y, 0), bottom_a, bottom_c, color.darkened(0.26))
	_stone_count += 1


func _moss_patch(pos: Vector3, dimensions: Vector2, seed_value: int) -> void:
	var tint := Color("2b393a")
	pos.y = _ground_height(pos.x, pos.z) + 0.012
	for i in range(9):
		var a := TAU * float(i) / 9.0
		var b := TAU * float(i + 1) / 9.0
		var ra := 0.8 + _noise(i + seed_value * 3) * 0.3
		var rb := 0.8 + _noise(i + 1 + seed_value * 3) * 0.3
		_triangle(_moss, pos, pos + Vector3(cos(b) * dimensions.x * rb, 0, sin(b) * dimensions.y * rb), pos + Vector3(cos(a) * dimensions.x * ra, 0, sin(a) * dimensions.y * ra), tint)


func _line(a: Vector3, b: Vector3, thickness: float, tint: Color) -> void:
	var side := (b - a).cross(Vector3.UP).normalized() * thickness * 0.5
	_quad(_detail, a - side, a + side, b + side, b - side, tint)


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	for vertex: Vector3 in [a, b, c]:
		surface.set_color(tint)
		surface.add_vertex(vertex)
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
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = surface.commit()
	node.material_override = material
	add_child(node)


func _stone_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D approved_slate : source_color, filter_linear_mipmap_anisotropic;
varying vec3 stone_position;
void vertex() { stone_position = VERTEX; }
void fragment() {
	vec3 tex = texture(approved_slate, stone_position.xz * 0.16).rgb;
	float grain = sin(stone_position.x * 21.3 + stone_position.y * 7.7 + sin(stone_position.z * 16.1)) * sin(stone_position.z * 28.7 + stone_position.y * 12.4);
	float wash = sin(stone_position.x * 4.1 + stone_position.z * 2.7 + stone_position.y * 3.3);
	ALBEDO = COLOR.rgb * (1.0 + grain * 0.018 + wash * 0.030) * mix(vec3(1.0), tex * 1.7, 0.12);
	ROUGHNESS = 0.97;
	SPECULAR = 0.22;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("approved_slate", SLATE)
	return material


func _earth_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
varying vec3 ground_position;
void vertex() { ground_position = VERTEX; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float soil_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
void fragment() {
	vec2 p = ground_position.xz;
	float broad = soil_noise(p * 0.16 + vec2(7.3, 2.4));
	float broken = soil_noise(p * 0.51 + broad * 2.4);
	float fine = soil_noise(p * 4.7);
	float grain = sin(p.x * 8.7 + sin(p.y * 12.1)) * cos(p.y * 16.4);
	vec3 soil = mix(vec3(0.72, 0.61, 0.48), vec3(0.48, 0.65, 0.51), smoothstep(0.42, 0.73, broad));
	ALBEDO = COLOR.rgb * soil * (0.76 + broad * 0.27 + broken * 0.23 + fine * 0.08 + grain * 0.022);
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _flat_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	return material


func _noise(seed_value: int) -> float:
	return sin(float(seed_value) * 12.9898 + 4.1414) * 0.5
