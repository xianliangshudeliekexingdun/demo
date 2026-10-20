extends Node3D
## Original book / chest geometry. Presence and pickup belong exclusively to core.

var _kind: String = ""
var _radius: float = -1.0
var _materials: Dictionary = {}
var _gold_only: bool = false
var _locked: bool = false


func sync_pickup(pickup: Dictionary):
	visible = bool(pickup.get("visible", false)) and not bool(pickup.get("claimed", false))
	if not visible:
		return
	var pos: Vector2 = pickup.get("pos", Vector2.ZERO)
	position = Vector3(pos.x, 0.0, -pos.y)
	var kind = str(pickup.get("kind", "spell"))
	var radius = float(pickup.get("radius", 0.8))
	if kind != _kind or not is_equal_approx(radius, _radius) or _gold_only != bool(pickup.get("gold_only", false)) or _locked != bool(pickup.get("locked", false)):
		_kind = kind
		_radius = radius
		_gold_only = bool(pickup.get("gold_only", false))
		_locked = bool(pickup.get("locked", false))
		_rebuild()


func _rebuild():
	for child in get_children():
		remove_child(child)
		child.queue_free()
	name = "GateRewardPickup"
	set_meta("source", "original_procedural_book_or_chest")
	set_meta("kind", _kind)
	var ring = MeshInstance3D.new()
	ring.name = "PickupFootRing"
	var torus = TorusMesh.new()
	torus.inner_radius = _radius * 0.96
	torus.outer_radius = _radius
	torus.rings = 48
	torus.ring_segments = 6
	ring.mesh = torus
	ring.position.y = 0.03
	ring.scale.y = 0.3
	ring.material_override = _mat("warm_ring", Color("e0b86d"), true)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	if _kind == "artifact":
		_chest()
	else:
		_book()


func _book():
	var stone = _mat("pedestal", Color("636272"))
	var cover = _mat("book_cover", Color("6d517d"))
	var pages = _mat("book_pages", Color("d7ccb3"))
	var gold = _mat("old_gold", Color("c5a366"))
	var altar = CylinderMesh.new()
	altar.top_radius = 0.40
	altar.bottom_radius = 0.46
	altar.height = 0.24
	altar.radial_segments = 8
	_piece("BookStand", altar, Vector3(0, 0.12, 0), Vector3.ONE, stone)
	var book = Node3D.new()
	book.name = "SpellBook"
	book.position = Vector3(0, 0.53, 0)
	book.rotation_degrees = Vector3(-18, 12, 0)
	add_child(book)
	_box(book, "LowerCover", Vector3(0, -0.09, 0), Vector3(0.83, 0.07, 1.02), cover)
	_box(book, "VisiblePages", Vector3(0.018, -0.015, 0), Vector3(0.73, 0.12, 0.92), pages)
	_box(book, "TopCover", Vector3(0, 0.075, 0), Vector3(0.83, 0.06, 1.02), cover)
	_box(book, "BookSpine", Vector3(-0.395, -0.015, 0), Vector3(0.07, 0.22, 1.02), gold)
	for side in [-1, 1]:
		_box(book, "CoverEdge", Vector3(side * 0.34, 0.113, 0), Vector3(0.018, 0.018, 0.82), gold)
		_box(book, "CoverEdge", Vector3(0, 0.113, side * 0.41), Vector3(0.69, 0.018, 0.018), gold)
	var sigil = _gem_mesh()
	var rune = MeshInstance3D.new()
	rune.name = "BookGoldSigil"
	rune.mesh = sigil
	rune.position = Vector3(0.02, 0.14, 0)
	rune.scale = Vector3(0.25, 0.05, 0.42)
	rune.material_override = _mat("book_rune", Color("f4d697"), true)
	book.add_child(rune)
	_box(book, "Bookmark", Vector3(0.21, 0.107, 0.50), Vector3(0.09, 0.01, 0.24), _mat("bookmark", Color("b77c70")))


func _chest():
	var wood = _mat("gold_chest_body", Color("977038")) if _gold_only else _mat("chest_wood", Color("4f415b"))
	var lid = _mat("gold_chest_lid", Color("d3a54f")) if _gold_only else _mat("chest_lid", Color("6f5b7c"))
	var gold = _mat("chest_trim", Color("c9a768"))
	for x in [-0.39, 0.39]:
		for z in [-0.25, 0.25]:
			_box(self, "ChestFoot", Vector3(x, 0.08, z), Vector3(0.14, 0.16, 0.14), gold)
	_box(self, "ChestBody", Vector3(0, 0.34, 0), Vector3(1.10, 0.44, 0.74), wood)
	_piece("VaultedLid", _lid_mesh(), Vector3(0, 0.56, 0), Vector3.ONE, lid)
	for x in [-0.39, 0.39]:
		_box(self, "ChestFrontBand", Vector3(x, 0.35, 0.378), Vector3(0.07, 0.43, 0.024), gold)
		_box(self, "ChestBackBand", Vector3(x, 0.35, -0.378), Vector3(0.07, 0.43, 0.024), gold)
		_piece("VaultGoldBand", _lid_mesh(), Vector3(x, 0.562, 0), Vector3(0.065, 1.014, 1.018), gold)
	_box(self, "ChestRim", Vector3(0, 0.565, 0.39), Vector3(1.12, 0.045, 0.03), gold)
	_box(self, "ChestLock", Vector3(0, 0.49, 0.412), Vector3(0.19, 0.24, 0.065), gold)
	_piece("ChestLockGem", _gem_mesh(), Vector3(0, 0.5, 0.455), Vector3(0.1, 0.15, 0.06), _mat("lock_gem", Color("a9e3e5"), true))
	if _locked:
		_box(self, "BookSealBand", Vector3(0, 0.35, 0.42), Vector3(0.9, 0.09, 0.06), _mat("book_seal", Color("9885b8"), true))


func _piece(part_name: String, mesh: Mesh, pos: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.name = part_name
	node.mesh = mesh
	node.position = pos
	node.scale = dimensions
	node.material_override = material
	add_child(node)
	return node


func _box(parent: Node3D, part_name: String, pos: Vector3, dimensions: Vector3, material: Material):
	var node = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = dimensions
	node.name = part_name
	node.mesh = mesh
	node.position = pos
	node.material_override = material
	parent.add_child(node)


func _lid_mesh() -> ArrayMesh:
	var outline = [Vector2(-0.39, 0), Vector2(-0.39, 0.13), Vector2(-0.26, 0.28), Vector2(0.26, 0.28), Vector2(0.39, 0.13), Vector2(0.39, 0)]
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(1, outline.size() - 1):
		for x in [-0.56, 0.56]:
			var face = [0, index + 1, index] if x < 0 else [0, index, index + 1]
			for at in face:
				surface.add_vertex(Vector3(x, outline[at].y, outline[at].x))
	for index in outline.size():
		var a: Vector2 = outline[index]
		var b: Vector2 = outline[(index + 1) % outline.size()]
		for vertex in [Vector3(-0.56, a.y, a.x), Vector3(0.56, b.y, b.x), Vector3(0.56, a.y, a.x), Vector3(-0.56, a.y, a.x), Vector3(-0.56, b.y, b.x), Vector3(0.56, b.y, b.x)]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	return surface.commit()


func _gem_mesh() -> ArrayMesh:
	var vertices = [Vector3(0, 0.5, 0), Vector3(0.5, 0, 0), Vector3(0, 0, 0.5), Vector3(-0.5, 0, 0), Vector3(0, 0, -0.5), Vector3(0, -0.5, 0)]
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in [[0, 2, 1], [0, 3, 2], [0, 4, 3], [0, 1, 4], [5, 1, 2], [5, 2, 3], [5, 3, 4], [5, 4, 1]]:
		for at in face:
			surface.add_vertex(vertices[at])
	surface.generate_normals()
	return surface.commit()


func _mat(id: String, tint: Color, unlit: bool = false) -> StandardMaterial3D:
	if _materials.has(id):
		return _materials[id]
	var material = StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.85
	if unlit:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials[id] = material
	return material
