extends Control
## The first room is a read-only 3D stage for the meter-based simulation.
## sync() consumes a snapshot; no clocks, collision or damage are owned here.
## Existing Lina skeletal clips follow the same read-only combat snapshot.

const LOGICAL_SIZE := Vector2(1600, 900)
const LinaMotion := preload("res://scripts/presentation/lina_motion.gd")
const SLIME := preload("res://assets/characters/slime.png")
const FONT := preload("res://assets/fonts/NotoSansSC.ttf")
const Stonework := preload("res://scripts/presentation/courtyard_stonework.gd")
const Surroundings := preload("res://scripts/presentation/courtyard_surroundings.gd")
const RoomDressing := preload("res://scripts/presentation/courtyard_room_dressing.gd")
const EnemyVisual := preload("res://scripts/presentation/route_enemy_visual.gd")
const CombatOverlay := preload("res://scripts/presentation/route_combat_overlay.gd")
const RewardVisual := preload("res://scripts/presentation/route_reward_visual.gd")
const SpellVFX := preload("res://scripts/presentation/route_spell_vfx.gd")
const GemVFX := preload("res://scripts/presentation/route_gem_vfx.gd")
const CYAN_FLAME := preload("res://assets/environment/courtyard_v2/cyan_flame.png")
const PORTAL_ENERGY := preload("res://assets/environment/courtyard_v2/portal_energy_soft.png")
const ROOM_PATH := "res://data/first_room_runtime.json"
const CAMERA_OFFSET := Vector3(0, 14.2, 16.8)
const CAMERA_AHEAD := 1.8
const CAMERA_RESPONSE := 7.0

var room_viewport: SubViewport
var camera: Camera3D
var world: Node3D
var actor: Node3D
var motion: Node3D
var portal: Node3D
var spirit: Node3D
var reward_visual: Node3D
var _boss_chest_visual: Node3D
var spell_vfx: Node3D
var gem_vfx: Node3D
var _stage: Node3D
var _overlay: Control
var _texture: TextureRect
var _state: Dictionary = {}
var _actor_nodes: Dictionary = {}
var _materials: Dictionary = {}
var _lina_materials: Array[StandardMaterial3D] = []
var _last_blocks := ""
var _player_ring: MeshInstance3D
var _shield_ring: MeshInstance3D
var _readable_font: FontVariation
var _block_meshes: Dictionary = {}
var _blue_flames: Array[Node3D] = []
var _portal_material: ShaderMaterial
var _visual_options := {"damage_numbers": true, "reduced_motion": false}
var _room_size := Vector2.ZERO
var _camera_focus := Vector3.ZERO
var _camera_target := Vector3.ZERO
var _camera_initialized := false
var _camera_frozen := false
var _surroundings: Node3D
var _room_revision := -1


func _ready() -> void:
	_readable_font = FontVariation.new()
	_readable_font.base_font = FONT
	_readable_font.variation_opentype = {2003265652: 500.0}
	name = "FirstRoomView"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The controller is a Node2D. Anchors require a Control parent, so give the
	# battle stage its explicit logical size in that case as well as in probes.
	if get_parent() is Control:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		position = Vector2.ZERO
		size = LOGICAL_SIZE
	room_viewport = SubViewport.new()
	room_viewport.name = "FirstRoomViewport"
	room_viewport.size = Vector2i(LOGICAL_SIZE)
	room_viewport.own_world_3d = true
	room_viewport.gui_disable_input = true
	room_viewport.msaa_3d = Viewport.MSAA_4X
	room_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(room_viewport)
	_texture = TextureRect.new()
	_texture.name = "StageImage"
	_texture.texture = room_viewport.get_texture()
	_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	add_child(_texture)
	_overlay = Control.new()
	_overlay.name = "CombatReadability"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	resized.connect(_layout_stage)
	_layout_stage()
	_build_world()
	if not _state.is_empty():
		sync(_state)


func sync(snapshot: Dictionary, _delta: float = 0.0) -> void:
	_state = snapshot
	if not is_instance_valid(actor):
		return
	if snapshot.has("room_revision") and int(snapshot.room_revision) != _room_revision:
		_rebuild_room(snapshot)
	var player: Dictionary = _state.get("player", {})
	actor.position = _point(player.get("pos", Vector2.ZERO))
	_sync_camera(snapshot, _delta)
	var face: Vector2 = player.get("face", Vector2.DOWN)
	if face.length_squared() > 0.0001:
		# The source model looks along local +X. Rotation changes facing only.
		actor.rotation.y = atan2(face.y, face.x)
	motion.sync(snapshot, _delta)
	var hurt: bool = _state.get("phase", "") == "combat" and float(player.get("invulnerable", 0.0)) > 0.0
	for mat in _lina_materials:
		mat.albedo_color = Color(1.0, 0.58, 0.54) if hurt else Color.WHITE
	_player_ring.position = actor.position + Vector3(0, 0.025, 0)
	_shield_ring.position = actor.position + Vector3(0, 0.03, 0)
	_shield_ring.visible = float(player.get("shield", 0.0)) > 0.0
	_sync_blocks(_state.get("blocks", []))
	_sync_actors(_state.get("actors", []))
	var portal_state: Dictionary = _state.get("portal", {})
	portal.visible = bool(portal_state.get("visible", false))
	portal.position = _point(portal_state.get("pos", Vector2.ZERO))
	_sync_ambient_visuals(float(_state.get("time", 0.0)))
	var spirit_state: Dictionary = _state.get("spirit", {})
	spirit.visible = false # The source-driven flame spirit is batched with magic VFX.
	spirit.position = _point(spirit_state.get("pos", player.get("pos", Vector2.ZERO)), 1.0)
	var pickups: Array = _state.get("reward_pickups", [])
	reward_visual.sync_pickup(pickups[0] if pickups.size() == 2 else _state.get("reward_pickup", {}))
	_boss_chest_visual.sync_pickup(pickups[1] if pickups.size() == 2 else {})
	spell_vfx.sync_snapshot(snapshot, camera, _visual_options)
	gem_vfx.sync_snapshot(snapshot, camera, _visual_options)
	_overlay.queue_redraw()


func set_visual_options(options: Dictionary) -> void:
	for option in ["damage_numbers", "reduced_motion"]:
		if options.has(option):
			_visual_options[option] = bool(options[option])
	if is_instance_valid(actor):
		_sync_ambient_visuals(float(_state.get("time", 0.0)))
	if is_instance_valid(_overlay):
		_overlay.queue_redraw()
	if is_instance_valid(spell_vfx) and not _state.is_empty():
		spell_vfx.sync_snapshot(_state, camera, _visual_options)
	if is_instance_valid(gem_vfx) and not _state.is_empty():
		gem_vfx.sync_snapshot(_state, camera, _visual_options)


func _sync_ambient_visuals(time: float) -> void:
	# Core supplies the clock; route reward decisions keep it moving, pauses stop it.
	var visual_time := 0.0 if bool(_visual_options.reduced_motion) else time
	if _portal_material:
		_portal_material.set_shader_parameter("core_time", visual_time)
	for i in range(_blue_flames.size()):
		var flame := _blue_flames[i]
		flame.scale.y = 1.0 + sin(visual_time * 2.3 + float(i) * 1.1) * 0.055 if not bool(_visual_options.reduced_motion) else 1.0


func get_room_viewport() -> SubViewport:
	return room_viewport


func get_vfx_debug_state() -> Dictionary:
	return spell_vfx.get_debug_state() if is_instance_valid(spell_vfx) else {}

func get_gem_vfx_debug_state() -> Dictionary:
	return gem_vfx.get_debug_state() if is_instance_valid(gem_vfx) else {}


func _layout_stage() -> void:
	# Explicit child sizes also support callers adding the component to Node2D.
	if is_instance_valid(_texture):
		_texture.position = Vector2.ZERO
		_texture.size = size
	if is_instance_valid(_overlay):
		_overlay.position = Vector2.ZERO
		_overlay.size = size
		_overlay.queue_redraw()


func screen_position(pos: Vector2, height: float = 0.0) -> Vector2:
	if not is_instance_valid(camera):
		return Vector2.ZERO
	return camera.unproject_position(_point(pos, height)) * size / LOGICAL_SIZE


func get_camera_debug_state() -> Dictionary:
	return {"focus": _camera_focus, "target": _camera_target,
		"position": camera.position if is_instance_valid(camera) else Vector3.ZERO,
		"frozen": _camera_frozen, "room_size": _room_size}


func get_navigation_markers() -> Array:
	var markers: Array = []
	if _state.is_empty() or not is_instance_valid(camera):
		return markers
	var scale_factor := size.x / LOGICAL_SIZE.x
	var safe := Rect2(Vector2(105, 170) * scale_factor, Vector2(1390, 540) * scale_factor)
	var player_pos: Vector2 = _state.get("player", {}).get("pos", Vector2.ZERO)
	var origin := screen_position(player_pos, 0.7)
	var targets: Array = []
	if str(_state.get("phase", "")) == "combat":
		for enemy in _state.get("actors", []):
			if float(enemy.health) > 0.0:
				targets.append({"kind": "enemy", "pos": enemy.pos})
		for warning in _state.get("spawn_warnings", []):
			targets.append({"kind": "spawn", "pos": warning.pos})
	var gate: Dictionary = _state.get("portal", {})
	var pickup: Dictionary = _state.get("reward_pickup", {})
	if str(_state.get("phase", "")) == "pickup" and bool(pickup.get("visible", false)) and not bool(pickup.get("claimed", false)):
		targets.append({"kind": "artifact_pickup" if pickup.get("kind", "spell") == "artifact" else "spell_pickup", "pos": pickup.pos})
	if str(_state.get("phase", "")) in ["exit", "shop"] and bool(gate.get("usable", false)):
		targets.append({"kind": "portal", "pos": gate.pos})
	if str(_state.get("phase", "")) == "shop" and not _state.get("shop", {}).is_empty():
		targets.append({"kind": "shop", "pos": _state.shop.interaction_pos})
	for target in targets:
		var projected := screen_position(target.pos, 0.6)
		var behind := camera.is_position_behind(_point(target.pos, 0.6))
		if safe.has_point(projected) and not behind:
			continue
		var direction := (projected - origin).normalized()
		if behind:
			direction = -direction
		if direction.is_zero_approx():
			direction = Vector2.UP
		var center := safe.get_center()
		var half := safe.size * 0.5
		var ratio := minf(half.x / maxf(absf(direction.x), 0.001), half.y / maxf(absf(direction.y), 0.001))
		markers.append({"kind": target.kind, "point": center + direction * ratio,
			"projected": projected, "direction": direction, "distance": player_pos.distance_to(target.pos)})
	return markers


func _sync_camera(snapshot: Dictionary, delta: float) -> void:
	if not is_instance_valid(camera):
		return
	var dimensions: Vector2 = snapshot.get("room_size", _room_size)
	var half := dimensions * 0.5
	var pos: Vector3 = actor.position
	# Keep a little of the road behind Lina and a longer view toward the north.
	# Near the perimeter the focus stops gently while Lina can keep moving.
	_camera_target = Vector3(clampf(pos.x, -half.x + 4.0, half.x - 4.0), 0.3,
		clampf(pos.z - CAMERA_AHEAD, -half.y + 4.0, half.y - 4.0))
	_camera_frozen = bool(snapshot.get("paused", false)) or str(snapshot.get("phase", "")) not in ["combat", "pickup", "exit"]
	if not _camera_initialized:
		_camera_focus = _camera_target
		_camera_initialized = true
	elif not _camera_frozen and delta > 0.0:
		# Frame-rate independent damping. It never writes core position or time.
		_camera_focus = _camera_focus.lerp(_camera_target, 1.0 - exp(-CAMERA_RESPONSE * minf(delta, 0.1)))
	camera.position = _camera_focus + CAMERA_OFFSET
	camera.look_at(_camera_focus)


func _point(pos: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(pos.x, height, -pos.y)


func _rebuild_room(snapshot: Dictionary) -> void:
	_room_revision = int(snapshot.room_revision)
	for child in _stage.get_children():
		_stage.remove_child(child)
		child.queue_free()
	_blue_flames.clear()
	_build_room(snapshot.room_geometry)
	if bool(snapshot.get("in_shop", false)):
		_build_shop_counter(snapshot.get("shop", {}))
	else:
		var dressing := RoomDressing.new()
		_stage.add_child(dressing)
		dressing.build_room({"room_id": int(snapshot.room_index), "name": str(snapshot.room_name),
			"template_id": str(snapshot.template_id), "source_kind": str(snapshot.source_kind),
			"geometry": snapshot.room_geometry})
	_camera_initialized = false
	_last_blocks = ""
	# A portal transition is a new position sample, not a very fast running step.
	motion.set_menu_mode(false)


func _build_shop_counter(shop: Dictionary) -> void:
	var stand := Node3D.new()
	stand.name = "ShopCounter"
	_stage.add_child(stand)
	stand.position = _point(shop.get("counter_pos", Vector2.ZERO))
	var wood := _mat("shop_dark_wood", Color("40394a"))
	var cloth := _mat("shop_cloth", Color("36506a"))
	var brass := _mat("shop_brass", Color("c6a66c"))
	var light := _mat("shop_crystal", Color("9ce4e9"), true)
	_box(stand, Vector3(0, 0.7, 0), Vector3(4.0, 1.4, 1.2), wood)
	_box(stand, Vector3(0, 1.43, 0), Vector3(4.25, 0.12, 1.4), brass)
	_box(stand, Vector3(0, 1.51, 0), Vector3(3.95, 0.035, 1.2), cloth)
	for side in [-1.0, 1.0]:
		_box(stand, Vector3(side * 1.95, 2.38, 0.35), Vector3(0.1, 1.85, 0.1), brass)
	_box(stand, Vector3(0, 3.3, 0.1), Vector3(4.5, 0.12, 1.7), cloth)
	for index in range(3):
		var x: float = float(index - 1) * 1.1
		_ring(stand, Vector3(x, 1.54, 0), 0.24, 0.29, Color("c6a66c"))
		var crystal := _box(stand, Vector3(x, 1.82, 0), Vector3(0.24, 0.42, 0.24), light)
		crystal.rotation_degrees.z = 12.0
	var sign := Label3D.new()
	sign.name = "ShopCounterSign"
	sign.text = "旅 途 商 店\n靠近柜台 · 补给与宝物"
	sign.font = FONT
	sign.font_size = 42
	sign.outline_size = 6
	sign.pixel_size = 0.006
	sign.position = Vector3(0, 0.8, 0.72)
	sign.modulate = Color("f2d49a")
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	stand.add_child(sign)


func _build_world() -> void:
	world = Node3D.new()
	world.name = "CourtyardStage"
	room_viewport.add_child(world)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("101620")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a1aecb")
	env.ambient_light_energy = 0.23
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.25
	# Local emissive planes and real lights retain the dark surround in this
	# Compatibility viewport; the rendered A/B probe rejected global glow.
	env.glow_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env_node.environment = env
	world.add_child(env_node)
	_light(Vector3(-55, -24, 0), Color("d8dded"), 0.72, true)
	_light(Vector3(-28, 140, 0), Color("6d8bb8"), 0.11, false)
	_stage = Node3D.new()
	_stage.name = "Architecture"
	world.add_child(_stage)
	_build_room()
	actor = Node3D.new()
	actor.name = "LinaActor"
	world.add_child(actor)
	motion = LinaMotion.new()
	motion.scale = Vector3.ONE * 1.75
	actor.add_child(motion)
	_prepare_model(motion)
	_player_ring = _ring(world, Vector3.ZERO, 0.34, 0.37, Color("ffd389"))
	_shield_ring = _ring(world, Vector3.ZERO, 0.41, 0.43, Color("82d4e7"))
	portal = Node3D.new()
	portal.name = "ClearPortal"
	world.add_child(portal)
	_build_portal()
	portal.visible = false
	spirit = Node3D.new()
	spirit.name = "FlameSpirit"
	world.add_child(spirit)
	_sphere(spirit, Vector3.ZERO, Vector3(0.28, 0.4, 0.28), _mat("spirit", Color("ffd88f"), true))
	_ring(spirit, Vector3.ZERO, 0.18, 0.22, Color("f2a65d"))
	spirit.visible = false
	reward_visual = RewardVisual.new()
	reward_visual.name = "GateRewardPickup"
	reward_visual.visible = false
	world.add_child(reward_visual)
	_boss_chest_visual = RewardVisual.new()
	_boss_chest_visual.name = "BossGoldChest"
	_boss_chest_visual.visible = false
	world.add_child(_boss_chest_visual)
	spell_vfx = SpellVFX.new()
	world.add_child(spell_vfx)
	gem_vfx = GemVFX.new()
	world.add_child(gem_vfx)
	camera = Camera3D.new()
	camera.name = "FollowRoomCamera"
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = 34.0
	camera.near = 0.1
	camera.far = 100.0
	camera.position = CAMERA_OFFSET
	world.add_child(camera)
	camera.look_at(Vector3(0, 0.3, 0))
	camera.current = true


func _build_room(geometry: Dictionary = {}) -> void:
	if geometry.is_empty():
		var runtime = JSON.parse_string(FileAccess.get_file_as_string(ROOM_PATH))
		if not runtime is Dictionary or not runtime.get("room", {}).has("floor"):
			push_error("First room presentation cannot load floor metrics")
			return
		geometry = runtime.room
	var width := float(geometry.floor.width)
	var depth := float(geometry.floor.depth)
	_room_size = Vector2(width, depth)
	_surroundings = Surroundings.new()
	_stage.add_child(_surroundings)
	_surroundings.build_room(_room_size * 0.5)
	Stonework.build(_stage, width, depth)
	for side in [-1.0, 1.0]:
		for fraction in [0.12, 0.38, 0.65, 0.9]:
			_brazier(Vector3(side * (width * 0.5 - 0.13), 0, -depth * 0.5 + depth * fraction), 1.42, false)
		_brazier(Vector3(side * 1.99, 0, -depth * 0.5 + 0.3), 0.98, true)
		_brazier(Vector3(side * 1.99, 0, depth * 0.5 + 0.25), 0.88, true)
	var gold := _mat("entrance_gold", Color("b69b68"))
	_diamond(_stage, Vector3(0, 0.094, depth * 0.5 - 0.56), 0.21, 0.018, gold)


func _brazier(pos: Vector3, height: float, local_light: bool) -> void:
	var basalt := _mat("brazier_basalt", Color("39435b"))
	var metal := _mat("brazier_metal", Color("a19065"))
	_stone(_stage, pos + Vector3(0, 0.1, 0), Vector3(0.55, 0.19, 0.55), basalt, 0.035)
	_stone(_stage, pos + Vector3(0, height * 0.44, 0), Vector3(0.34, height * 0.84, 0.34), basalt, 0.035)
	_stone(_stage, pos + Vector3(0, height - 0.08, 0), Vector3(0.55, 0.18, 0.55), metal, 0.05)
	_stone(_stage, pos + Vector3(0, height + 0.014, 0), Vector3(0.42, 0.025, 0.42), _mat("brazier_well", Color("264659")), 0.025)
	var glyph := _box(_stage, pos + Vector3(0, height * 0.43, 0.176), Vector3(0.12, 0.12, 0.022), metal)
	glyph.rotation.z = PI * 0.25
	var flame := Node3D.new()
	flame.position = pos + Vector3(0, height + 0.025, 0)
	_stage.add_child(flame)
	var body := Sprite3D.new()
	body.name = "PaintedCyanFlame"
	body.texture = CYAN_FLAME
	body.pixel_size = 0.00052
	body.position.y = 0.27
	body.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	body.shaded = false
	body.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	flame.add_child(body)
	_floor_glow(_stage, pos + Vector3(0, 0.065, 0), Vector2(2.0, 2.0), Color("3ed4ed"), 0.15)
	_blue_flames.append(flame)
	if local_light:
		var glow := OmniLight3D.new()
		glow.position = pos + Vector3(0, height + 0.3, 0)
		glow.light_color = Color("51cfec")
		glow.light_energy = 0.85
		glow.omni_range = 2.5
		glow.omni_attenuation = 1.8
		_stage.add_child(glow)


func _build_portal() -> void:
	# The aperture, light spill and landing seal share the cleared-state parent.
	var gold := Color("f0d58a")
	_floor_glow(portal, Vector3(0, 0.13, 0.04), Vector2(5.6, 5.6), Color("3ed4ed"), 0.24)
	_ring(portal, Vector3(0, 0.142, 0.02), 1.16, 1.19, gold)
	_ring(portal, Vector3(0, 0.145, 0.02), 0.94, 0.955, gold)
	_ring(portal, Vector3(0, 0.148, 0.02), 0.73, 0.745, Color("87e7eb"))
	_diamond(portal, Vector3(0, 0.154, 0.02), 0.36, 0.022, _mat("portal_gold", gold, true))
	for i in range(12):
		var angle := float(i) * TAU / 12.0
		var mark := _box(portal, Vector3(cos(angle) * 1.07, 0.15, 0.02 + sin(angle) * 1.07), Vector3(0.035, 0.018, 0.14), _mat("portal_gold", gold, true))
		mark.rotation.y = -angle
		if i % 3 == 0:
			_diamond(portal, Vector3(cos(angle) * 1.29, 0.15, 0.02 + sin(angle) * 1.29), 0.105, 0.016, _mat("portal_gold", gold, true))
	var aperture := MeshInstance3D.new()
	aperture.name = "PaintedPortalAperture"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.58, 3.03)
	aperture.mesh = mesh
	aperture.position = Vector3(0, 1.43, -0.68)
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D portal_tex : source_color, filter_linear_mipmap;
uniform float core_time = 0.0;
void fragment() {
	vec2 p = UV - vec2(0.5);
	float radial = length(p);
	vec2 uv = UV + vec2(sin(p.y * 17.0 + core_time * 0.9), cos(p.x * 16.0 - core_time * 0.8)) * 0.002 * smoothstep(0.1, 0.45, radial);
	vec4 painted = texture(portal_tex, uv);
	if (painted.a < 0.015) { discard; }
	float light_value = max(max(painted.r, painted.g), painted.b);
	ALBEDO = painted.rgb;
	EMISSION = painted.rgb * smoothstep(0.48, 0.96, light_value) * 1.55;
	ALPHA = painted.a;
}
"""
	_portal_material = ShaderMaterial.new()
	_portal_material.shader = shader
	_portal_material.set_shader_parameter("portal_tex", PORTAL_ENERGY)
	aperture.material_override = _portal_material
	portal.add_child(aperture)
	var halo := _floor_glow(portal, Vector3(0, 1.45, -0.6), Vector2(3.6, 4.25), Color("3cc9e9"), 0.18)
	halo.rotation_degrees.x = 90
	# Floating inset crystals connect the visual energy to the stone construction.
	for side in [-1.0, 1.0]:
		var ornament := _box(portal, Vector3(side * 1.19, 1.17, -0.6), Vector3(0.15, 0.15, 0.07), _mat("portal_gold", gold, true))
		ornament.rotation.z = PI * 0.25
	var crest := _box(portal, Vector3(0, 3.07, -0.62), Vector3(0.29, 0.33, 0.09), _mat("portal_gold", gold, true))
	crest.rotation.z = PI * 0.25
	var crystal := _box(portal, Vector3(0, 3.07, -0.55), Vector3(0.17, 0.22, 0.07), _mat("portal_crystal", Color("8deaff"), true))
	crystal.rotation.z = PI * 0.25
	var glow := OmniLight3D.new()
	glow.name = "PortalStoneLight"
	glow.position = Vector3(0, 1.08, 0.14)
	glow.light_color = Color("50d9ef")
	glow.light_energy = 2.0
	glow.omni_range = 5.0
	glow.omni_attenuation = 1.45
	portal.add_child(glow)


func _floor_glow(parent: Node3D, pos: Vector3, dimensions: Vector2, tint: Color, opacity: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "SoftLocalLightSpill"
	var mesh := PlaneMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	node.position = pos
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add;
uniform vec4 tint : source_color = vec4(0.2, 0.8, 1.0, 1.0);
uniform float opacity = 0.2;
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float falloff = pow(max(0.0, 1.0 - r), 2.4);
	ALBEDO = tint.rgb;
	ALPHA = falloff * opacity;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("opacity", opacity)
	node.material_override = material
	parent.add_child(node)
	return node


func _diamond(parent: Node3D, pos: Vector3, radius: float, thickness: float, material: Material) -> void:
	for i in range(4):
		var angle := PI * 0.25 + float(i) * PI * 0.5
		var segment := _box(parent, pos + Vector3(cos(angle) * radius * 0.5, 0, sin(angle) * radius * 0.5), Vector3(radius * 0.71, 0.018, thickness), material)
		segment.rotation.y = -angle - PI * 0.5


func _stone(parent: Node3D, pos: Vector3, dimensions: Vector3, material: Material, bevel: float = 0.04) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _block_mesh(dimensions, bevel)
	node.position = pos
	node.material_override = material
	parent.add_child(node)
	return node


func _block_mesh(dimensions: Vector3, bevel: float) -> ArrayMesh:
	var signature := str(dimensions) + ":" + str(bevel)
	if _block_meshes.has(signature):
		return _block_meshes[signature]
	var x := dimensions.x * 0.5
	var y := dimensions.y * 0.5
	var z := dimensions.z * 0.5
	var b := minf(bevel, minf(x, minf(y, z)) * 0.7)
	var outline := [Vector2(-x + b, -z), Vector2(x - b, -z), Vector2(x, -z + b), Vector2(x, z - b), Vector2(x - b, z), Vector2(-x + b, z), Vector2(-x, z - b), Vector2(-x, -z + b)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for i in range(8):
		var j := (i + 1) % 8
		var a: Vector2 = outline[i]
		var c: Vector2 = outline[j]
		var inner_a := Vector2(a.x * (x - b) / x, a.y * (z - b) / z)
		var inner_c := Vector2(c.x * (x - b) / x, c.y * (z - b) / z)
		var bottom_a := Vector3(a.x, -y, a.y)
		var bottom_c := Vector3(c.x, -y, c.y)
		var side_a := Vector3(a.x, y - b, a.y)
		var side_c := Vector3(c.x, y - b, c.y)
		var top_a := Vector3(inner_a.x, y, inner_a.y)
		var top_c := Vector3(inner_c.x, y, inner_c.y)
		_mesh_face(st, bottom_a, side_a, side_c, bottom_c)
		_mesh_face(st, side_a, top_a, top_c, side_c)
		st.add_vertex(Vector3(0, y, 0))
		st.add_vertex(top_c)
		st.add_vertex(top_a)
		st.add_vertex(Vector3(0, -y, 0))
		st.add_vertex(bottom_a)
		st.add_vertex(bottom_c)
	st.generate_normals()
	var mesh := st.commit()
	_block_meshes[signature] = mesh
	return mesh


func _mesh_face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for vertex in [a, b, c, a, c, d]:
		st.add_vertex(vertex)


func _sync_blocks(blocks: Array) -> void:
	var signature := str(blocks)
	if signature == _last_blocks:
		return
	_last_blocks = signature
	var old := world.get_node_or_null("SolidCover")
	if old:
		world.remove_child(old)
		old.queue_free()
	var cover := Node3D.new()
	cover.name = "SolidCover"
	world.add_child(cover)
	for block in blocks:
		var p := _point(block.center)
		var dimensions: Vector2 = block.size
		Stonework.build_cover(cover, p, dimensions)


func _sync_actors(actors: Array) -> void:
	var live: Dictionary = {}
	for data in actors:
		var id: int = int(data.id)
		live[id] = true
		if not _actor_nodes.has(id):
			if data.has("type_id"):
				_actor_nodes[id] = EnemyVisual.build(world, data)
				_actor_nodes[id].set_meta("route_enemy", true)
				_actor_nodes[id].position = _point(data.pos)
				continue
			var root := Node3D.new()
			root.name = "Slime%d" % id
			world.add_child(root)
			var sprite := Sprite3D.new()
			sprite.name = "ApprovedSlime"
			sprite.texture = SLIME
			sprite.pixel_size = 0.0055
			sprite.position.y = 0.62
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sprite.shaded = false
			sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			root.add_child(sprite)
			_ring(root, Vector3(0, 0.022, 0), float(data.radius) * 0.88, float(data.radius), Color("78bbc0"))
			_actor_nodes[id] = root
		var actor_node: Node3D = _actor_nodes[id]
		actor_node.position = _point(data.pos)
		actor_node.visible = float(data.health) > 0.0
		if actor_node.get_meta("route_enemy", false):
			EnemyVisual.sync(actor_node, data, float(_state.get("time", 0.0)))
			continue
		var image_node := actor_node.get_node("ApprovedSlime") as Sprite3D
		image_node.modulate = Color("ffb18b") if data.phase in ["warning", "attack", "lunge"] else Color.WHITE
	for id in _actor_nodes.keys():
		if not live.has(id):
			_actor_nodes[id].queue_free()
			_actor_nodes.erase(id)


func _prepare_model(node: Node) -> void:
	if node is AnimationPlayer:
		node.stop()
		node.active = false
	if node is MeshInstance3D:
		for i in range(node.mesh.get_surface_count()):
			var source = node.get_active_material(i)
			if source is StandardMaterial3D:
				var copy := source.duplicate() as StandardMaterial3D
				node.set_surface_override_material(i, copy)
				_lina_materials.append(copy)
	for child in node.get_children():
		_prepare_model(child)


func _light(angles: Vector3, tint: Color, energy: float, shadows: bool) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = angles
	light.light_color = tint
	light.light_energy = energy
	light.shadow_enabled = shadows
	light.shadow_blur = 2.0
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	world.add_child(light)


func _mat(id: String, tint: Color, unlit: bool = false) -> StandardMaterial3D:
	if _materials.has(id):
		return _materials[id]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = 0.92
	if unlit:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if tint.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials[id] = m
	return m


func _box(parent: Node3D, pos: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	node.position = pos
	node.material_override = material
	parent.add_child(node)
	return node


func _sphere(parent: Node3D, pos: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 16
	mesh.rings = 8
	node.mesh = mesh
	node.scale = dimensions
	node.position = pos
	node.material_override = material
	parent.add_child(node)
	return node


func _ring(parent: Node3D, pos: Vector3, inner: float, outer: float, tint: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 64
	mesh.ring_segments = 8
	node.mesh = mesh
	node.position = pos
	node.material_override = _mat("ring_" + tint.to_html(), tint, true)
	parent.add_child(node)
	return node


func _draw_overlay() -> void:
	if _state.is_empty() or not is_instance_valid(camera):
		return
	var scale_factor := size.x / LOGICAL_SIZE.x
	var time: float = float(_state.get("time", 0.0))
	CombatOverlay.draw(self, _state)
	# Directional warnings use the exact attack segment; visuals never predict hits.
	for enemy in _state.get("actors", []):
		if float(enemy.health) <= 0.0:
			continue
		if not enemy.has("type_id") and enemy.phase in ["warning", "attack", "lunge"]:
			var start: Vector2 = enemy.get("attack_from", enemy.pos)
			var end: Vector2 = enemy.get("attack_to", enemy.pos)
			var radius: float = float(enemy.get("danger_radius", enemy.radius))
			_draw_path(start, end, radius, Color(1, 0.28, 0.2, 0.15), Color("ff8c70"))
			var arrow := screen_position(end, 0.055)
			var direction := (arrow - screen_position(start, 0.055)).normalized()
			var normal := Vector2(-direction.y, direction.x)
			_overlay.draw_polyline(PackedVector2Array([arrow - direction * 13 * scale_factor + normal * 7 * scale_factor, arrow, arrow - direction * 13 * scale_factor - normal * 7 * scale_factor]), Color("ffe5bb"), 2 * scale_factor, true)
		var health := clampf(float(enemy.health) / maxf(1.0, float(enemy.max_health)), 0, 1)
		var elite := bool(enemy.get("elite", false))
		var p := screen_position(enemy.pos, 2.2 if elite else 1.65)
		_overlay.draw_line(p + Vector2(-24, 0) * scale_factor, p + Vector2(24, 0) * scale_factor, Color("102632"), 6 * scale_factor)
		_overlay.draw_line(p + Vector2(-23, 0) * scale_factor, p + Vector2(-23 + 46 * health, 0) * scale_factor, Color("edbd72") if elite else Color("9ee3c5"), 3 * scale_factor)
		if elite:
			_center_text(str(enemy.get("name", "精英")), p - Vector2(0, 12 * scale_factor), 16, Color("f5cf86"))
	for warning in _state.get("spawn_warnings", []):
		var progress := 1.0 - float(warning.get("remaining", 0.0)) / maxf(0.01, float(warning.get("duration", 1.0)))
		_ground_ring(warning.pos, float(warning.get("radius", 0.5)), Color(0.9, 0.69, 0.4, 0.1 + progress * 0.12), Color("e7bd7c"), 2.0)
		_ground_ring(warning.pos, float(warning.get("radius", 0.5)) * (1.25 - progress * 0.25), Color.TRANSPARENT, Color(0.9, 0.69, 0.4, 0.45), 1.0)
	var player: Dictionary = _state.get("player", {})
	for spell in _state.get("spells", []):
		if float(spell.get("cast_remaining", 0.0)) > 0:
			var id: String = str(spell.get("id", ""))
			var cast_tint := Color({"L":"c5b3ff", "I":"8bd9ed", "W":"a4e4cf", "R":"d7b580", "S":"e6b7e5"}.get(id.left(1), "f8cf8a"))
			_ground_ring(player.get("pos", Vector2.ZERO), 0.64, Color(cast_tint, 0.07), cast_tint, 2.0)
	for effect in _state.get("effects", []):
		_draw_effect(effect)
	_draw_reward_pickup()
	var gate: Dictionary = _state.get("portal", {})
	if bool(gate.get("visible", false)):
		var gate_pos: Vector2 = gate.get("pos", Vector2(0, 6))
		var pulse := 1.0 if bool(_visual_options.reduced_motion) else 1.0 + sin(time * 2.5) * 0.025
		_ground_ring(gate_pos, 1.03 * pulse, Color.TRANSPARENT, Color(0.5, 0.95, 1, 0.35), 1.8)
	for marker in get_navigation_markers():
		_draw_navigation_marker(marker)


func _draw_navigation_marker(marker: Dictionary) -> void:
	var sf := size.x / LOGICAL_SIZE.x
	var p: Vector2 = marker.point
	var direction: Vector2 = marker.direction
	var normal := Vector2(-direction.y, direction.x)
	var tint := Color("89e9f3") if marker.kind == "portal" else Color("f2bd7b")
	_overlay.draw_circle(p, 17 * sf, Color(0.035, 0.065, 0.09, 0.88))
	_overlay.draw_polyline(PackedVector2Array([p - direction * 8 * sf + normal * 7 * sf,
		p + direction * 6 * sf, p - direction * 8 * sf - normal * 7 * sf]), tint, 2.3 * sf, true)
	var label := "传送门" if marker.kind == "portal" else ("商店" if marker.kind == "shop" else "宝物箱" if marker.kind == "artifact_pickup" else "法术书" if marker.kind == "spell_pickup" else "敌人" if marker.kind == "enemy" else "即将出现")
	var text_pos := p - direction * 36 * sf
	_center_text("%s  %.0fm" % [label, float(marker.distance)], text_pos + Vector2(0, 6 * sf), 16, tint)


func _draw_reward_pickup() -> void:
	var pickups: Array = _state.get("reward_pickups", [])
	if pickups.is_empty():
		pickups = [_state.get("reward_pickup", {})]
	for pickup in pickups:
		_draw_pickup_label(pickup)


func _draw_pickup_label(pickup: Dictionary) -> void:
	if not bool(pickup.get("visible", false)) or bool(pickup.get("claimed", false)):
		return
	var pos: Vector2 = pickup.get("pos", Vector2.ZERO)
	if camera.is_position_behind(_point(pos, 1.25)):
		return
	var p := screen_position(pos, 1.25)
	var sf := size.x / LOGICAL_SIZE.x
	if not Rect2(Vector2(120, 145) * sf, Vector2(1360, 580) * sf).has_point(p):
		return
	var text := "靠近开启宝物箱" if pickup.get("kind", "spell") == "artifact" else "靠近领取法术书"
	if bool(pickup.get("gold_only", false)):
		text = "先领法术书解封" if bool(pickup.get("locked", false)) else "靠近开启必金宝箱"
	_center_text(text, p, 18, Color("f2cd8a"))


func _draw_effect(effect: Dictionary) -> void:
	if GemVFX.handles_effect(str(effect.get("kind", ""))):
		return
	if is_instance_valid(spell_vfx) and spell_vfx.handles_effect(str(effect.get("kind", ""))):
		return
	# Choice screens freeze the simulation. Old attack events may still exist in
	# the snapshot, but must not appear as an active attack after the room clears.
	if _state.get("scope", "") == "early_route_map_trial" and _state.get("phase", "") != "combat" and effect.get("kind", "") not in ["clear", "reward", "artifact_acquired"]:
		return
	if CombatOverlay.draw_effect(self, effect):
		return
	var life: float = float(effect.get("life", 0.0))
	var max_life: float = maxf(0.01, float(effect.get("max_life", 0.3)))
	var alpha := clampf(life / max_life, 0, 1)
	var progress := 1.0 - alpha
	var pos: Vector2 = effect.get("pos", Vector2.ZERO)
	var p := screen_position(pos, 0.6)
	var scale_factor := size.x / LOGICAL_SIZE.x
	match str(effect.get("kind", "")):
		"beam", "spirit_bolt":
			var a := screen_position(effect.get("from", pos), 0.7)
			var b := screen_position(effect.get("to", pos), 0.7)
			var tint := Color("ffb373") if effect.kind == "beam" else Color("ffe7a7")
			_overlay.draw_line(a, b, Color(tint, alpha * 0.2), 19 * scale_factor, true)
			_overlay.draw_line(a, b, Color(tint, alpha * 0.75), 8 * scale_factor, true)
			_overlay.draw_line(a, b, Color(1, 0.96, 0.8, alpha), 2.5 * scale_factor, true)
		"bolt_hit":
			var radius: float = float(effect.get("radius", 0.8))
			_ground_ring(pos, radius * (0.65 + progress * 0.35), Color(1, 0.44, 0.12, alpha * 0.14), Color(1, 0.75, 0.4, alpha), 2.5)
			_glow(p, (13 + progress * 13) * scale_factor, Color(1, 0.59, 0.24, alpha))
		"cast":
			_ground_ring(pos, 0.5 + progress * 0.24, Color.TRANSPARENT, Color(1, 0.79, 0.47, alpha * 0.8), 2)
		"hurt", "damage":
			var amount: float = float(effect.get("amount", 0.0))
			var color := Color("ffbca0") if effect.kind == "hurt" else Color("fff0cd")
			if amount > 0 and bool(_visual_options.damage_numbers):
				_center_text("%d" % int(round(amount)), p - Vector2(0, (45 + progress * 22) * scale_factor), 20, Color(color, alpha))
		"death":
			var slime := true
			for enemy in _state.get("actors", []):
				if int(enemy.id) == int(effect.get("actor_id", -1)):
					slime = str(enemy.get("type_id", "M01")) in ["M01", "EL01"]
					break
			if slime:
				var faded := Rect2(screen_position(pos, 0) - Vector2(43, 83) * scale_factor, Vector2(86, 86) * scale_factor)
				_overlay.draw_texture_rect(SLIME, faded, false, Color(0.68, 0.92, 0.87, alpha * 0.65))
			_ground_ring(pos, 0.4 + progress * 0.5, Color.TRANSPARENT, Color(0.53, 0.85, 0.8, alpha * 0.6), 2)
		"clear", "reward":
			_ground_ring(pos, 0.55 + progress * 1.0, Color.TRANSPARENT, Color(0.65, 0.9, 0.81, alpha * 0.8), 2)
		"spawn":
			_ground_ring(pos, 0.5 + progress * 0.25, Color.TRANSPARENT, Color(0.95, 0.74, 0.46, alpha), 2)


func _draw_path(start: Vector2, end: Vector2, radius: float, fill: Color, line: Color) -> void:
	var direction := (end - start).normalized()
	if direction.length_squared() < 0.01:
		_ground_ring(end, radius, fill, line, 2)
		return
	var normal := Vector2(-direction.y, direction.x) * radius
	var points := PackedVector2Array([screen_position(start - normal, 0.04), screen_position(end - normal, 0.04), screen_position(end + normal, 0.04), screen_position(start + normal, 0.04)])
	_overlay.draw_colored_polygon(points, fill)
	_overlay.draw_line(points[0], points[1], line, 1.5 * size.x / LOGICAL_SIZE.x, true)
	_overlay.draw_line(points[3], points[2], line, 1.5 * size.x / LOGICAL_SIZE.x, true)
	_ground_ring(end, radius, fill, line, 2)


func _ground_ring(pos: Vector2, radius: float, fill: Color, line: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in range(65):
		var angle := TAU * float(i) / 64
		points.append(screen_position(pos + Vector2(cos(angle), sin(angle)) * radius, 0.045))
	if fill.a > 0:
		_overlay.draw_colored_polygon(points, fill)
	_overlay.draw_polyline(points, line, width * size.x / LOGICAL_SIZE.x, true)


func _glow(pos: Vector2, radius: float, color: Color) -> void:
	_overlay.draw_circle(pos, radius * 1.8, Color(color, color.a * 0.09))
	_overlay.draw_circle(pos, radius * 1.25, Color(color, color.a * 0.20))
	_overlay.draw_circle(pos, radius * 0.72, color)
	_overlay.draw_circle(pos, radius * 0.30, Color(1, 0.96, 0.78, color.a))


func _center_text(text: String, pos: Vector2, font_size: int, tint: Color) -> void:
	var actual_size := maxi(9, int(font_size * size.x / LOGICAL_SIZE.x))
	var width := _readable_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, actual_size).x
	var origin := pos - Vector2(width * 0.5, 0)
	_overlay.draw_string_outline(_readable_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, actual_size, 4, Color(0.03, 0.08, 0.11, tint.a))
	_overlay.draw_string(_readable_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, actual_size, tint)
