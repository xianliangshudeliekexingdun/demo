extends RefCounted
## Original procedural route enemies. This file only creates visible geometry.
## World position, collision, attack windows and damage remain owned by core.

const SLIME = preload("res://assets/characters/slime.png")
static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}


static func build(parent: Node3D, actor: Dictionary) -> Node3D:
	var root = Node3D.new()
	var type_id = str(actor.get("type_id", actor.get("type", "M01"))).to_upper()
	var elite = bool(actor.get("elite", false)) or type_id.begins_with("EL")
	root.name = "Enemy_%s_%s" % [type_id, actor.get("id", 0)]
	root.set_meta("source", "original_procedural_meshes_and_approved_slime")
	root.set_meta("type_id", type_id)
	root.set_meta("elite", elite)
	root.set_meta("last_health", float(actor.get("health", 0.0)))
	root.set_meta("hurt_until", -1.0)
	root.set_meta("radius", float(actor.radius))
	parent.add_child(root)
	var shape = Node3D.new()
	shape.name = "Shape"
	root.add_child(shape)
	match type_id:
		"BOSS01", "BOSS02", "BOSS03", "BOSS04":
			_boss(shape, type_id, float(actor.radius))
		"M01", "EL01":
			_slime(shape, float(actor.radius), elite)
		"M02", "EL02", "EL02_GUARD":
			_flower(shape, float(actor.radius), elite)
		"M05", "M06", "M07":
			_flower(shape, float(actor.radius), false, type_id)
		"M03":
			_charger(shape, float(actor.radius))
		"M04":
			_caster(shape, float(actor.radius))
		_:
			_slime(shape, float(actor.radius), elite)
	sync(root, actor, 0.0)
	return root


static func _boss(parent: Node3D, type_id: String, radius: float):
	var gold = _material("boss_gold", Color("e8be71"))
	var rune = _material("boss_rune", Color("eabae9"), true)
	match type_id:
		"BOSS01":
			_slime(parent, radius, false)
			_crown(parent, Vector3(0, radius * 2.68, 0), radius * 0.70)
			for side in [-1, 1]:
				var plate = _piece(parent, "GuardStoneMantle", "box", Vector3(side * radius * 0.77, radius * 0.95, -radius * 0.12), Vector3(radius * 0.42, radius * 1.1, radius * 0.70), _material("guard_stone", Color("85888a")))
				plate.rotation.z = side * -0.16
				_gem(parent, "GuardShoulderRune", Vector3(side * radius * 0.75, radius * 1.3, 0), Vector3(radius * 0.16, radius * 0.48, radius * 0.38), gold)
		"BOSS04":
			_flower(parent, radius, true)
			var petal = _material("boss_mother_petal", Color("c888ab"))
			for index in 12:
				var angle = float(index) * TAU / 12.0
				var leaf = _piece(parent, "MotherOuterPetal", "sphere", Vector3(sin(angle) * radius * 0.90, radius * 1.85, cos(angle) * radius * 0.90), Vector3(radius * 0.45, radius * 0.22, radius * 1.3), petal)
				leaf.rotation.y = angle
			_piece(parent, "MotherSporeHalo", "ring", Vector3(0, radius * 2.95, 0), Vector3.ONE * radius * 0.80, gold)
		"BOSS02":
			_caster(parent, radius)
			var halo = _piece(parent, "WardenRuneDisc", "ring", Vector3(0, radius * 2.0, -radius * 0.48), Vector3.ONE * radius * 1.15, gold)
			halo.rotation.x = PI * 0.5
			for index in 4:
				var angle = float(index) * TAU / 4.0
				_gem(parent, "WardenSeal", Vector3(sin(angle) * radius * 1.1, radius * (2.0 + cos(angle) * 1.1), -radius * 0.45), Vector3(radius * 0.23, radius * 0.38, radius * 0.10), rune)
		"BOSS03":
			var stone = _material("heart_stone", Color("5d667d"))
			var heart = _material("heart_core", Color("f0a6ba"), true)
			_gem(parent, "RelicHeart", Vector3(0, radius * 1.45, 0), Vector3(radius * 0.85, radius * 1.25, radius * 0.80), heart)
			for index in 6:
				var angle = float(index) * TAU / 6.0
				var shard = _gem(parent, "HeartStoneShard", Vector3(sin(angle) * radius * 0.75, radius * (1.3 + 0.22 * (index % 2)), cos(angle) * radius * 0.75), Vector3(radius * 0.40, radius * 1.45, radius * 0.42), stone)
				shard.rotation.z = sin(angle) * -0.3
			for index in 2:
				var ring = _piece(parent, "HeartOrbit", "ring", Vector3(0, radius * 1.4, 0), Vector3.ONE * radius * 1.0, gold if index == 0 else rune)
				ring.rotation = Vector3(0.6 if index == 0 else -0.6, 0, 0.4)
static func sync(node: Node3D, actor: Dictionary, time: float):
	var previous_health = float(node.get_meta("last_health", actor.get("health", 0.0)))
	var current_health = float(actor.get("health", 0.0))
	if current_health < previous_health - 0.00001:
		node.set_meta("hurt_until", time + 0.12)
	node.set_meta("last_health", current_health)
	node.visible = current_health > 0.0
	var shape = node.get_node_or_null("Shape") as Node3D
	if shape == null:
		return
	# Facing uses actual travel or the current core attack vector, never a fake gait.
	var direction: Vector2 = actor.get("pos", Vector2.ZERO) - actor.get("previous", actor.get("pos", Vector2.ZERO))
	if str(actor.get("phase", "")) in ["warning", "lunge", "barrage", "charge", "ring_wait"]:
		direction = actor.get("attack_to", Vector2.ZERO) - actor.get("attack_from", Vector2.ZERO)
	if direction.length_squared() > 0.0000001:
		shape.rotation.y = atan2(direction.x, direction.y)
	var warning = str(actor.get("phase", "")) in ["warning", "lunge", "barrage", "active", "attack", "charge", "ring_wait"]
	var hurt = time < float(node.get_meta("hurt_until", -1.0))
	var tint = Color("ffd6bd") if hurt else (Color("ffb879") if warning else Color.WHITE)
	var approved = shape.get_node_or_null("ApprovedSlime") as Sprite3D
	if approved != null:
		approved.modulate = tint
	# A material overlay is a tint cue only; shared base materials stay immutable.
	var overlay: Material = _material("hurt_overlay", Color(1.0, 0.58, 0.36, 0.42), true) if hurt else (_material("warn_overlay", Color(1.0, 0.28, 0.08, 0.22), true) if warning else null)
	for child in shape.get_children():
		if child is MeshInstance3D:
			child.material_overlay = overlay


static func _slime(parent: Node3D, radius: float, elite: bool):
	var size = radius / 0.45
	var sprite = Sprite3D.new()
	sprite.name = "ApprovedSlime"
	sprite.texture = SLIME
	sprite.pixel_size = 0.0055 * size
	sprite.position.y = 0.62 * size
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	parent.add_child(sprite)
	if elite:
		_crown(parent, Vector3(0, 1.20 * size, 0), 0.28 * size)
		for sign_value in [-1, 1]:
			_gem(parent, "CrownSigil", Vector3(sign_value * radius * 0.52, radius * 1.1, -0.08), Vector3.ONE * radius * 0.16, _material("elite_rune", Color("ffdd80"), true))
static func _flower(parent: Node3D, radius: float, elite: bool, variant: String = ""):
	var stem = _material("flower_stem", Color("324f45"))
	var leaves = _material("flower_leaf", Color("568568"))
	var petal = _material("flower_elite_petal" if elite else "flower_petal", Color("c18c6f") if elite else Color("a76594"))
	var petal_alt = _material("flower_elite_tip" if elite else "flower_tip", Color("e2b38b") if elite else Color("d58dab"))
	if not variant.is_empty():
		var palettes = {"M05": [Color("cd8a45"), Color("efbd6d")], "M06": [Color("8c5ea1"), Color("d69dc8")], "M07": [Color("5d8a7b"), Color("b2c98a")]}
		petal = _material("flower_petal_" + variant, palettes[variant][0])
		petal_alt = _material("flower_tip_" + variant, palettes[variant][1])
	var core = _material("flower_core", Color("e4c871"))
	_piece(parent, "RootBulb", "sphere", Vector3(0, radius * 0.43, 0), Vector3(radius * 1.15, radius * 0.8, radius * 1.12), stem)
	_piece(parent, "Stem", "cylinder", Vector3(0, radius * 1.18, 0), Vector3(radius * 0.3, radius * 1.6, radius * 0.3), stem)
	for index in 4:
		var angle = index * TAU / 4.0 + PI / 4.0
		var leaf = _piece(parent, "Leaf%d" % index, "sphere", Vector3(sin(angle) * radius * 0.65, radius * 0.49, cos(angle) * radius * 0.65), Vector3(radius * 0.48, radius * 0.18, radius * 1.2), leaves)
		leaf.rotation.y = angle
		leaf.rotation.x = -0.22
	for index in 7:
		var angle = index * TAU / 7.0
		var bloom = _piece(parent, "Petal%d" % index, "sphere", Vector3(sin(angle) * radius * 0.68, radius * 2.12, cos(angle) * radius * 0.68), Vector3(radius * 0.72, radius * 0.32, radius * 1.03), petal if index % 2 == 0 else petal_alt)
		bloom.rotation.y = angle
		bloom.rotation.x = 0.16
	_piece(parent, "SporeCore", "sphere", Vector3(0, radius * 2.2, 0), Vector3(radius * 0.92, radius * 0.68, radius * 0.92), core)
	var eye = _material("flower_eyes", Color("281b35"))
	for side in [-1, 1]:
		_piece(parent, "SporeEye", "sphere", Vector3(side * radius * 0.18, radius * 2.24, radius * 0.40), Vector3(radius * 0.12, radius * 0.19, radius * 0.10), eye)
	_piece(parent, "SporeMouth", "sphere", Vector3(0, radius * 2.02, radius * 0.39), Vector3(radius * 0.16, radius * 0.17, radius * 0.11), eye)
	if elite:
		_crown(parent, Vector3(0, radius * 2.66, 0), radius * 0.44)
	if variant == "M05":
		for index in 5:
			var angle = (index - 2) * 0.38
			var spike = _piece(parent, "FanCrest", "cone", Vector3(sin(angle) * radius * 0.7, radius * (2.88 + cos(angle) * 0.3), 0), Vector3(radius * 0.2, radius * 0.65, radius * 0.2), petal_alt)
			spike.rotation.z = -angle
	elif variant == "M06":
		var halo = _piece(parent, "RingCrest", "ring", Vector3(0, radius * 2.9, 0), Vector3.ONE * radius * 0.62, petal_alt)
		halo.rotation.x = PI * 0.5
	elif variant == "M07":
		for side in [-1, 1]:
			var fin = _piece(parent, "SweepFin", "cone", Vector3(side * radius * 0.85, radius * 2.55, 0), Vector3(radius * 0.32, radius * 1.35, radius * 0.25), petal_alt)
			fin.rotation.z = side * -0.72
static func _charger(parent: Node3D, radius: float):
	var hide = _material("charger_hide", Color("444453"))
	var stone = _material("charger_armor", Color("8e8b86"))
	var dark_stone = _material("charger_armor_dark", Color("696b72"))
	var horn = _material("charger_horn", Color("cabd99"))
	_piece(parent, "LowBody", "sphere", Vector3(0, radius * 0.90, 0), Vector3(radius * 1.72, radius * 1.15, radius * 2.1), hide)
	for side in [-1, 1]:
		for end in [-1, 1]:
			_piece(parent, "Leg", "cylinder", Vector3(side * radius * 0.64, radius * 0.4, end * radius * 0.68), Vector3(radius * 0.39, radius * 0.8, radius * 0.42), hide)
			_piece(parent, "StoneFoot", "box", Vector3(side * radius * 0.65, radius * 0.14, end * radius * 0.68), Vector3(radius * 0.52, radius * 0.3, radius * 0.66), dark_stone)
		for index in 3:
			var plate = _piece(parent, "RockPlate", "box", Vector3(side * radius * 0.49, radius * 1.43, (index - 1) * radius * 0.61), Vector3(radius * 0.88, radius * 0.38, radius * 0.71), stone if index % 2 == 0 else dark_stone)
			plate.rotation.z = side * -0.27
	_piece(parent, "ArmoredHead", "sphere", Vector3(0, radius * 0.98, radius * 1.02), Vector3(radius * 1.21, radius * 0.94, radius * 1.01), dark_stone)
	for side in [-1, 1]:
		var spike = _piece(parent, "ForwardHorn", "cone", Vector3(side * radius * 0.34, radius * 1.28, radius * 1.45), Vector3(radius * 0.32, radius * 1.0, radius * 0.32), horn)
		spike.rotation.x = 1.04
		_piece(parent, "AmberEye", "sphere", Vector3(side * radius * 0.38, radius * 1.10, radius * 1.45), Vector3(radius * 0.15, radius * 0.12, radius * 0.10), _material("charger_eye", Color("ffb85c"), true))
static func _caster(parent: Node3D, radius: float):
	var robe = _material("caster_robe", Color("64507e"))
	var cloth = _material("caster_cloth_dark", Color("3d344f"))
	var gold = _material("caster_gold", Color("c9ab6d"))
	var void_mat = _material("caster_void", Color("202332"))
	var blue = _material("caster_orb", Color("b285ef"), true)
	_piece(parent, "RobeSkirt", "cone", Vector3(0, radius * 1.22, 0), Vector3(radius * 1.48, radius * 2.35, radius * 1.45), robe)
	_piece(parent, "Shoulders", "sphere", Vector3(0, radius * 2.06, 0), Vector3(radius * 1.18, radius * 0.7, radius * 0.86), robe)
	_piece(parent, "Hood", "sphere", Vector3(0, radius * 2.68, 0), Vector3(radius * 1.05, radius * 1.12, radius * 0.96), cloth)
	_piece(parent, "HoodShadow", "sphere", Vector3(0, radius * 2.60, radius * 0.39), Vector3(radius * 0.73, radius * 0.75, radius * 0.25), void_mat)
	for side in [-1, 1]:
		_piece(parent, "VioletEye", "sphere", Vector3(side * radius * 0.18, radius * 2.68, radius * 0.53), Vector3(radius * 0.11, radius * 0.08, radius * 0.06), blue)
		var sleeve = _piece(parent, "Sleeve", "cone", Vector3(side * radius * 0.78, radius * 1.92, radius * 0.13), Vector3(radius * 0.56, radius * 0.88, radius * 0.56), robe)
		sleeve.rotation.z = side * 0.6
	_gem(parent, "RobeSigil", Vector3(0, radius * 1.36, radius * 0.48), Vector3(radius * 0.34, radius * 0.53, radius * 0.09), gold)
	_piece(parent, "StaffShaft", "cylinder", Vector3(radius * 1.02, radius * 1.65, radius * 0.1), Vector3(radius * 0.12, radius * 3.22, radius * 0.12), gold)
	_gem(parent, "StaffOrb", Vector3(radius * 1.02, radius * 3.37, radius * 0.1), Vector3.ONE * radius * 0.50, blue)
	var halo = _piece(parent, "OrbCradle", "ring", Vector3(radius * 1.02, radius * 3.37, radius * 0.1), Vector3.ONE * radius * 0.38, gold)
	halo.rotation.x = PI * 0.5
static func _crown(parent: Node3D, pos: Vector3, radius: float):
	var gold = _material("elite_gold", Color("dfbf72"))
	var band = _piece(parent, "EliteCrownBand", "ring", pos, Vector3.ONE * radius, gold)
	band.scale.y *= 1.5
	for index in 5:
		var angle = index * TAU / 5.0
		_piece(parent, "EliteCrownPoint", "cone", pos + Vector3(sin(angle) * radius * 0.83, radius * 0.53, cos(angle) * radius * 0.83), Vector3(radius * 0.48, radius * 1.4, radius * 0.48), gold)
	_gem(parent, "EliteCrownJewel", pos + Vector3(0, radius * 0.34, radius * 0.96), Vector3(radius * 0.33, radius * 0.53, radius * 0.2), _material("crown_jewel", Color("e39a68"), true))


static func _gem(parent: Node3D, name: String, pos: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	return _piece(parent, name, "gem", pos, dimensions, material)


static func _piece(parent: Node3D, name: String, shape: String, pos: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.name = name
	node.mesh = _mesh(shape)
	node.position = pos
	node.scale = dimensions
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(node)
	return node


static func _mesh(shape: String) -> Mesh:
	if _meshes.has(shape):
		return _meshes[shape]
	var mesh: Mesh
	match shape:
		"sphere":
			var value = SphereMesh.new()
			value.radius = 0.5
			value.height = 1.0
			value.radial_segments = 10
			value.rings = 4
			mesh = value
		"box":
			var value = BoxMesh.new()
			value.size = Vector3.ONE
			mesh = value
		"ring":
			var value = TorusMesh.new()
			value.inner_radius = 0.89
			value.outer_radius = 1.0
			value.rings = 16
			value.ring_segments = 4
			mesh = value
		"cone", "cylinder":
			var value = CylinderMesh.new()
			value.height = 1.0
			value.bottom_radius = 0.5
			value.top_radius = 0.0 if shape == "cone" else 0.5
			value.radial_segments = 8
			value.rings = 1
			mesh = value
		_:
			var vertices = PackedVector3Array([Vector3(0, 0.5, 0), Vector3(0.5, 0, 0), Vector3(0, 0, 0.5), Vector3(-0.5, 0, 0), Vector3(0, 0, -0.5), Vector3(0, -0.5, 0)])
			var faces = [[0, 2, 1], [0, 3, 2], [0, 4, 3], [0, 1, 4], [5, 1, 2], [5, 2, 3], [5, 3, 4], [5, 4, 1]]
			var builder = SurfaceTool.new()
			builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			for face in faces:
				for index in face:
					builder.add_vertex(vertices[index])
			builder.generate_normals()
			mesh = builder.commit()
	_meshes[shape] = mesh
	return mesh


static func _material(id: String, color: Color, unlit: bool = false) -> StandardMaterial3D:
	if _materials.has(id):
		return _materials[id]
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	var id_lower := id.to_lower()
	if not unlit:
		if id_lower.contains("gold") or id_lower.contains("crown") or id_lower.contains("horn") or id_lower.contains("armor") or id_lower.contains("staff"):
			# Metal trim and armour catch the warm key; bodies stay matte.
			material.metallic = 0.38
			material.roughness = 0.62
		elif id_lower.contains("robe") or id_lower.contains("cloth") or id_lower.contains("petal") or id_lower.contains("leaf") or id_lower.contains("hide"):
			material.roughness = 0.96
		else:
			material.roughness = 0.86
	if unlit:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[id] = material
	return material
