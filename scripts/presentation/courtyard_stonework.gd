extends RefCounted
## Presentation-only masonry kit. All dimensions supplied by the caller describe
## a visual footprint; no collision, actors, time, or gameplay state is created.

const FLOOR_TEXTURE := preload("res://assets/environment/courtyard_v2/painted_slate_albedo.png")

var _stone_surface: SurfaceTool
var _detail_surface: SurfaceTool
var _moss_surface: SurfaceTool
var _root: Node3D
var _stone_count := 0


static func build(parent: Node3D, width: float, depth: float) -> Dictionary:
	var builder := new()
	return builder._build(parent, width, depth)


static func build_cover(parent: Node3D, pos: Vector3, footprint: Vector2) -> Dictionary:
	var builder := new()
	return builder._build_cover(parent, pos, footprint)


func _build_cover(parent: Node3D, pos: Vector3, footprint: Vector2) -> Dictionary:
	_root = Node3D.new()
	_root.name = "AncientStoneCover"
	_root.position = pos
	parent.add_child(_root)
	_begin_surfaces()
	var stone := Color("606b84")
	# Alternating joints and a divided broken cap read as ancient masonry instead
	# of a closed chest. The visual width/depth stay inside the supplied footprint.
	_block(Vector3(0, 0.115, 0), Vector3(footprint.x, 0.23, footprint.y), 0.06, stone.darkened(0.15), 401)
	for section in range(2):
		var x := (float(section) - 0.5) * footprint.x * 0.5
		_block(Vector3(x, 0.365, 0), Vector3(footprint.x * 0.5 - 0.025, 0.25, footprint.y * 0.97), 0.055, stone, 411 + section)
		var z := (float(section) - 0.5) * footprint.y * 0.5
		_block(Vector3(0, 0.63, z), Vector3(footprint.x * 0.98, 0.25, footprint.y * 0.5 - 0.026), 0.06, stone, 421 + section)
	for section in range(2):
		var x := (float(section) - 0.5) * footprint.x * 0.5
		var height := 0.835 + _variation(section + 39) * 0.035
		_block(Vector3(x, height, 0), Vector3(footprint.x * 0.5 - 0.02, 0.16, footprint.y * 0.99), 0.065, stone.lightened(0.055).darkened(0.04), 431 + section)
		_top_crack(Vector3(x, height + 0.082, 0), Vector2(footprint.x * 0.4, footprint.y * 0.82), 441 + section)
	for side: float in [-1.0, 1.0]:
		_moss_patch(Vector3(side * footprint.x * 0.34, 0.026, footprint.y * 0.32), footprint * Vector2(0.11, 0.12), 451 + int(side))
	_finish_batch(_stone_surface, "CoverMasonry", _stone_material())
	_finish_batch(_detail_surface, "CoverHairlineCracks", _flat_material())
	_finish_batch(_moss_surface, "CoverBaseMoss", _flat_material())
	return {"root": _root, "mesh_count": 3, "stone_count": _stone_count}


func _begin_surfaces() -> void:
	_stone_surface = SurfaceTool.new()
	_stone_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_detail_surface = SurfaceTool.new()
	_detail_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_moss_surface = SurfaceTool.new()
	_moss_surface.begin(Mesh.PRIMITIVE_TRIANGLES)


func _build(parent: Node3D, width: float, depth: float) -> Dictionary:
	_root = Node3D.new()
	_root.name = "PaintedCourtyardStonework"
	parent.add_child(_root)
	_begin_surfaces()
	var w := width * 0.5
	var d := depth * 0.5
	var slate := Color("637089")
	var base := Color("30394e")
	_block(Vector3(0, -0.25, 0), Vector3(width + 0.92, 0.48, depth + 0.82), 0.12, base, 5)
	var floor := _floor(width, depth)
	_contact_shade(width, depth)
	# Courses vary in length and elevation, with staggered seams. They are merged
	# into one mesh after assembly, preserving a shared material and low draw count.
	for side: float in [-1.0, 1.0]:
		for row in range(3):
			var start := -d - 0.22
			var section := 0
			while start < d + 0.22:
				var length: float = [1.36, 1.12, 1.74, 1.48, 1.27][(section + row * 2) % 5]
				if section == 0 and row % 2 == 1:
					length *= 0.52
				length = minf(length, d + 0.22 - start)
				var height := 0.405 + _variation(section + row * 13) * 0.035
				if row == 2 and (section + (1 if side < 0 else 0)) % 5 == 2:
					height *= 0.76
				var center := Vector3(side * (w + 0.21), 0.03 + float(row) * 0.42 + height * 0.5, start + length * 0.5)
				_block(center, Vector3(0.57, height, maxf(0.1, length - 0.032)), 0.065, slate, section + row * 21)
				start += length
				section += 1
		# Broad coping stones give the wall a readable broken silhouette.
		var cap_count := ceili((depth + 0.42) / 1.8)
		for section in range(cap_count):
			var length := (depth + 0.42) / float(cap_count)
			var z := -d - 0.21 + (float(section) + 0.5) * length
			var height := 1.32 + _variation(section + 7) * 0.14
			_block(Vector3(side * (w + 0.21), height, z), Vector3(0.69, 0.18, length - 0.04), 0.075, slate.lightened(0.1).darkened(0.12), section + 67)
			if section % 3 == 1:
				_top_crack(Vector3(side * (w + 0.21), height + 0.092, z), Vector2(0.53, length * 0.65), section + 41)
		var pier_count := maxi(4, ceili(depth / 5.0) + 1)
		for column in range(pier_count):
			var z := -d + float(column) * depth / float(pier_count - 1)
			_pier(Vector3(side * (w + 0.21), 0, z), 1.74 + _variation(column + 17) * 0.13, column + int(side) * 8)
		# Sparse chipped debris and tiny plants soften the architectural outline.
		for chip in range(4):
			var z := -d + 1.8 + float(chip) * (depth - 2.7) / 4.0
			_block(Vector3(side * (w + 0.57), 0.075, z), Vector3(0.25, 0.18, 0.38), 0.06, slate.darkened(0.13), chip + 107)
			_moss_patch(Vector3(side * (w - 0.21), 0.033, z + 0.17), Vector2(0.43, 0.31), chip + 18)
		for north in [true, false]:
			var z := -d - 0.18 if north else d + 0.18
			var low := 1.82
			var span := w + 0.36 - low
			var rows := 3 if north else 1
			for row in range(rows):
				var segments := ceili(span / (1.5 if row % 2 == 0 else 1.25))
				for section in range(segments):
					var length := span / float(segments)
					var x := side * (low + length * (float(section) + 0.5))
					var y := (0.22 + float(row) * 0.41) if north else 0.24
					var tint := slate.darkened(0.05) if not north else slate
					_block(Vector3(x, y, z), Vector3(length - 0.03, 0.39 if north else 0.45, 0.58), 0.06, tint, section + row * 19 + (0 if north else 101))
			var end_caps := ceili(span / 1.6)
			for section in range(end_caps):
				var length := span / float(end_caps)
				var cap_y := (1.31 if north else 0.56) + _variation(section + 41) * 0.045
				_block(Vector3(side * (low + length * (float(section) + 0.5)), cap_y, z), Vector3(length - 0.02, 0.17, 0.7), 0.065, slate.lightened(0.11).darkened(0.12), section + 19)
		_pier(Vector3(side * 1.92, 0, d + 0.20), 0.8, int(side) * 5)
	# Three shallow, substantial stones turn the top portal into an inhabited
	# threshold, rather than a glowing shape floating above a single flat plane.
	_block(Vector3(0, 0.032, -d + 0.72), Vector3(3.25, 0.1, 1.76), 0.07, slate.darkened(0.1), 77)
	for step in range(2):
		_block(Vector3(0, 0.035 + float(step) * 0.045, -d + 0.12 - float(step) * 0.32), Vector3(2.79 - float(step) * 0.1, 0.1, 0.37), 0.035, slate.lightened(0.08), step + 142)
	for section in range(3):
		_block(Vector3((float(section) - 1.0) * 0.94, 0.032, d - 0.57), Vector3(0.93, 0.1, 1.2), 0.055, slate.lightened(0.05), section + 176)
	var arch := _arch(d, slate)
	_processional_inlay(w, d)
	for side: float in [-1.0, 1.0]:
		for patch in range(4):
			_moss_patch(Vector3(side * (w - 0.08 - float(patch % 2) * 0.22), 0.029, -d + 0.5 + float(patch) * 1.3), Vector2(0.3, 0.37), patch + 50)
		_moss_patch(Vector3(side * 2.0, 0.095, -d + 0.15), Vector2(0.6, 0.25), 3 + int(side))
	var stone_material := _stone_material()
	_finish_batch(_stone_surface, "MergedBeveledMasonry", stone_material)
	_finish_batch(_detail_surface, "FineStoneCracks", _flat_material())
	_finish_batch(_moss_surface, "RestrainedMoss", _flat_material())
	return {"arch": arch, "floor": floor, "root": _root, "mesh_count": 5, "stone_count": _stone_count}


func _floor(width: float, depth: float) -> MeshInstance3D:
	var floor := MeshInstance3D.new()
	floor.name = "HandPaintedSlateFloor"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(width, depth)
	floor.mesh = mesh
	floor.position.y = 0.015
	var shader := Shader.new()
	shader.code = """shader_type spatial;
uniform sampler2D slate : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 floor_size;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * floor_size;
	vec3 stone = texture(slate, UV * floor_size / 6.0).rgb;
	// Large-scale weathering separates the worn route from damp wall margins.
	float weather = sin(p.x * 0.48 + sin(p.y * 0.31)) * cos(p.y * 0.39 - p.x * 0.13);
	float wall = smoothstep(floor_size.x * 0.5 - 2.1, floor_size.x * 0.5, abs(p.x));
	float route = 1.0 - smoothstep(1.3, 3.8, abs(p.x + sin(p.y * 0.27) * 0.28));
	vec3 tint = mix(vec3(0.69, 0.75, 0.79), vec3(0.82, 0.83, 0.88), route * 0.68);
	tint *= 1.0 + weather * 0.075;
	tint = mix(tint, vec3(0.48, 0.57, 0.55), wall * (0.24 + weather * 0.09));
	ALBEDO = stone * tint;
	ROUGHNESS = 0.96;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("slate", FLOOR_TEXTURE)
	material.set_shader_parameter("floor_size", Vector2(width, depth))
	floor.material_override = material
	_root.add_child(floor)
	return floor


func _processional_inlay(half_width: float, half_depth: float) -> void:
	# Broken, desaturated inlay marks arrival / central court / portal approach.
	# It is flush floor detail, never an obstacle or an interactive rule marker.
	var bronze := Color("77715d")
	for side: float in [-1.0, 1.0]:
		_line(Vector3(side * (half_width - 0.9), 0.034, -half_depth + 1.3), Vector3(side * (half_width - 0.9), 0.034, half_depth - 1.1), Vector3.UP, 0.025, Color("424e59"))
		for segment in range(ceili((half_depth * 2.0 - 4.2) / 2.25)):
			var z := -half_depth + 2.2 + float(segment) * 2.25
			if segment % 5 == 3:
				continue
			_line(Vector3(side * 2.4, 0.033, z), Vector3(side * 2.4, 0.033, minf(z + 1.65, half_depth - 2.0)), Vector3.UP, 0.028, bronze.darkened(0.12))
	for z: float in [-half_depth + 3.7, 0.0, half_depth - 3.0]:
		var radius := 0.96 if is_zero_approx(z) else 0.50
		for side in range(4):
			var a := float(side) * PI * 0.5
			var b := float(side + 1) * PI * 0.5
			_line(Vector3(cos(a) * radius, 0.035, z + sin(a) * radius), Vector3(cos(b) * radius, 0.035, z + sin(b) * radius), Vector3.UP, 0.045, bronze)


func _contact_shade(width: float, depth: float) -> void:
	var node := MeshInstance3D.new()
	node.name = "WallFootContactShade"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(width, depth)
	node.mesh = mesh
	node.position.y = 0.025
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec2 floor_size = vec2(1.0);
void fragment() {
	vec2 edge = min(UV, vec2(1.0) - UV) * floor_size;
	float distance_to_wall = min(edge.x, edge.y);
	float shade = 1.0 - smoothstep(0.0, 0.85, distance_to_wall);
	ALBEDO = vec3(0.018, 0.026, 0.043);
	ALPHA = shade * 0.43;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("floor_size", Vector2(width, depth))
	node.material_override = material
	_root.add_child(node)


func _pier(pos: Vector3, height: float, seed_value: int) -> void:
	var tint := Color("69738e")
	_block(pos + Vector3(0, 0.135, 0), Vector3(0.94, 0.27, 0.9), 0.075, tint.darkened(0.14), seed_value)
	for course in range(3):
		var h := (height - 0.38) / 3.0
		_block(pos + Vector3(0, 0.27 + (float(course) + 0.5) * h, 0), Vector3(0.69, h - 0.025, 0.69), 0.065, tint, seed_value + course * 11)
	_block(pos + Vector3(0, height, 0), Vector3(0.91, 0.2, 0.9), 0.09, tint.lightened(0.11).darkened(0.12), seed_value + 7)
	_top_crack(pos + Vector3(0, height + 0.102, 0), Vector2(0.76, 0.72), seed_value + 29)
	var diamond := PackedVector3Array([Vector3(0, height - 0.05, 0.455), Vector3(-0.19, height - 0.26, 0.455), Vector3(0, height - 0.47, 0.455), Vector3(0.19, height - 0.26, 0.455)])
	for i in range(4):
		_line(pos + diamond[i], pos + diamond[(i + 1) % 4], Vector3.FORWARD, 0.016, Color("424b64"))


func _arch(half_depth: float, slate: Color) -> Node3D:
	var marker := Node3D.new()
	marker.name = "StoneArchAnchor"
	marker.position = Vector3(0, 0, -half_depth)
	_root.add_child(marker)
	for side: float in [-1.0, 1.0]:
		_block(Vector3(side * 1.36, 0.13, -half_depth - 0.04), Vector3(0.7, 0.25, 0.91), 0.07, slate.lightened(0.08), 301 + int(side))
		for row in range(3):
			_block(Vector3(side * 1.36, 0.42 + float(row) * 0.355, -half_depth - 0.1), Vector3(0.53, 0.35, 0.67), 0.055, slate.lightened(0.08), row + 310)
		_block(Vector3(side * 1.36, 1.21, -half_depth - 0.08), Vector3(0.66, 0.19, 0.8), 0.05, slate.lightened(0.14), 317)
	# Wedge-shaped voussoirs meet edge to edge around a continuous opening.
	for segment in range(11):
		var angle_a := float(segment) * PI / 11.0 + 0.012
		var angle_b := float(segment + 1) * PI / 11.0 - 0.012
		var outline := PackedVector2Array([
			Vector2(cos(angle_a) * 1.61, 1.2 + sin(angle_a) * 1.98),
			Vector2(cos(angle_b) * 1.61, 1.2 + sin(angle_b) * 1.98),
			Vector2(cos(angle_b) * 1.095, 1.2 + sin(angle_b) * 1.55),
			Vector2(cos(angle_a) * 1.095, 1.2 + sin(angle_a) * 1.55)
		])
		var tint := slate.lightened(0.10 + _variation(segment + 87) * 0.06)
		_arch_prism(outline, -half_depth - 0.39, -half_depth + 0.31, tint)
	return marker


func _arch_prism(outline: PackedVector2Array, back_z: float, front_z: float, tint: Color) -> void:
	var center := Vector2.ZERO
	for point in outline:
		center += point
	center /= float(outline.size())
	var front := PackedVector3Array()
	var shoulder := PackedVector3Array()
	var back := PackedVector3Array()
	for point in outline:
		var inset := point.lerp(center, 0.095)
		front.append(Vector3(inset.x, inset.y, front_z))
		shoulder.append(Vector3(point.x, point.y, front_z - 0.065))
		back.append(Vector3(point.x, point.y, back_z))
	for i in range(4):
		var next := (i + 1) % 4
		_quad(_stone_surface, shoulder[i], front[i], front[next], shoulder[next], tint.lightened(0.08))
		_quad(_stone_surface, back[i], shoulder[i], shoulder[next], back[next], tint.darkened(0.19))
	_quad(_stone_surface, front[0], front[1], front[2], front[3], tint)
	_quad(_stone_surface, back[3], back[2], back[1], back[0], tint.darkened(0.22))
	_stone_count += 1


func _block(pos: Vector3, dimensions: Vector3, bevel: float, color: Color, seed_value: int) -> void:
	var x := dimensions.x * 0.5
	var y := dimensions.y * 0.5
	var z := dimensions.z * 0.5
	var b := minf(bevel, minf(x, minf(y, z)) * 0.7)
	var tint := color.lightened(_variation(seed_value) * 0.09)
	var b0 := b * (1.0 + _variation(seed_value + 11) * 0.6)
	var b1 := b * (1.0 + _variation(seed_value + 17) * 0.6)
	var b2 := b * (1.0 + _variation(seed_value + 23) * 0.6)
	var b3 := b * (1.0 + _variation(seed_value + 29) * 0.6)
	var outline := PackedVector2Array([Vector2(-x + b0, -z), Vector2(x - b1, -z), Vector2(x, -z + b1), Vector2(x, z - b2), Vector2(x - b2, z), Vector2(-x + b3, z), Vector2(-x, z - b3), Vector2(-x, -z + b0)])
	for i in range(8):
		var next := (i + 1) % 8
		var a := outline[i]
		var c := outline[next]
		var inner_a := Vector2(a.x * (x - b * 0.75) / x, a.y * (z - b * 0.75) / z)
		var inner_c := Vector2(c.x * (x - b * 0.75) / x, c.y * (z - b * 0.75) / z)
		var bottom_a := pos + Vector3(a.x, -y, a.y)
		var bottom_c := pos + Vector3(c.x, -y, c.y)
		var side_a := pos + Vector3(a.x, y - b, a.y)
		var side_c := pos + Vector3(c.x, y - b, c.y)
		var top_a := pos + Vector3(inner_a.x, y, inner_a.y)
		var top_c := pos + Vector3(inner_c.x, y, inner_c.y)
		_quad(_stone_surface, bottom_a, side_a, side_c, bottom_c, tint.darkened(0.12))
		_quad(_stone_surface, side_a, top_a, top_c, side_c, tint.lightened(0.11))
		_triangle(_stone_surface, pos + Vector3(0, y, 0), top_c, top_a, tint.lightened(0.045))
		_triangle(_stone_surface, pos + Vector3(0, -y, 0), bottom_a, bottom_c, tint.darkened(0.3))
	_stone_count += 1


func _top_crack(pos: Vector3, dimensions: Vector2, seed_value: int) -> void:
	var offset := _variation(seed_value)
	var p := pos + Vector3(-dimensions.x * 0.42, 0, dimensions.y * offset * 0.3)
	var joint := pos + Vector3(-dimensions.x * 0.06, 0, -dimensions.y * 0.08)
	var end := pos + Vector3(dimensions.x * 0.32, 0, dimensions.y * 0.29)
	_line(p, joint, Vector3.UP, 0.011, Color("384158"))
	_line(joint, end, Vector3.UP, 0.012, Color("384158"))
	_line(joint, pos + Vector3(dimensions.x * 0.12, 0, -dimensions.y * 0.38), Vector3.UP, 0.009, Color("414a61"))


func _line(a: Vector3, b: Vector3, normal: Vector3, thickness: float, tint: Color) -> void:
	var side := (b - a).cross(normal).normalized() * thickness * 0.5
	_quad(_detail_surface, a - side, a + side, b + side, b - side, tint)


func _moss_patch(pos: Vector3, size: Vector2, seed_value: int) -> void:
	var tint := Color("334543").lightened(_variation(seed_value) * 0.045)
	for i in range(9):
		var a := TAU * float(i) / 9.0
		var b := TAU * float(i + 1) / 9.0
		var r_a := 0.78 + _variation(i + seed_value * 3) * 0.3
		var r_b := 0.78 + _variation(i + 1 + seed_value * 3) * 0.3
		_triangle(_moss_surface, pos, pos + Vector3(cos(b) * size.x * r_b, 0, sin(b) * size.y * r_b), pos + Vector3(cos(a) * size.x * r_a, 0, sin(a) * size.y * r_a), tint)


func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for vertex in [a, b, c]:
		st.set_color(color)
		st.add_vertex(vertex)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_triangle(st, a, b, c, color)
	_triangle(st, a, c, d, color)


func _finish_batch(st: SurfaceTool, node_name: String, material: Material) -> void:
	st.generate_normals()
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = st.commit()
	node.material_override = material
	_root.add_child(node)


func _stone_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
varying vec3 stone_position;
void vertex() { stone_position = VERTEX; }
void fragment() {
	float grain = sin(stone_position.x * 21.3 + stone_position.y * 7.7 + sin(stone_position.z * 16.1)) * sin(stone_position.z * 28.7 + stone_position.y * 12.4);
	float wash = sin(stone_position.x * 4.1 + stone_position.z * 2.7 + stone_position.y * 3.3);
	ALBEDO = COLOR.rgb * (1.0 + grain * 0.022 + wash * 0.035);
	ROUGHNESS = 0.96;
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


func _variation(seed_value: int) -> float:
	return sin(float(seed_value) * 12.9898 + 4.1414) * 0.5
