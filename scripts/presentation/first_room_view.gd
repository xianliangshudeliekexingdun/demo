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
const MagicMissileVFX := preload("res://scripts/presentation/route_magic_missile_vfx.gd")
const FireBoltVFX := preload("res://scripts/presentation/route_fire_bolt_vfx.gd")
const FireRainVFX := preload("res://scripts/presentation/route_fire_rain_vfx.gd")
const FireBeamVFX := preload("res://scripts/presentation/route_fire_beam_vfx.gd")
const FireBombVFX := preload("res://scripts/presentation/route_fire_bomb_vfx.gd")
const CYAN_FLAME := preload("res://assets/environment/courtyard_v2/cyan_flame.png")
const PORTAL_ENERGY := preload("res://assets/environment/courtyard_v2/portal_energy_soft.png")
const ROOM_PATH := "res://data/first_room_runtime.json"
const CAMERA_OFFSET := Vector3(0, 14.2, 16.8)
const CAMERA_AHEAD := 1.8
const CAMERA_RESPONSE := 7.0
const PLAYER_HIT_FLASH := 0.14
const ENEMY_BAR_HOLD := 3.0
const ENEMY_BAR_FADE := 0.35
const DAMAGE_NUMBER_LIFETIME := 0.72
const DAMAGE_NUMBER_LIMIT := 20
const WARNING_FADE_SECONDS := 0.08
const STAGE_Z_INDEX := 0
const COMBAT_OVERLAY_Z_INDEX := 1

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
var magic_missile_vfx: Node2D
var fire_bolt_vfx: Node2D
var fire_rain_vfx: Node2D
var fire_beam_vfx: Node2D
var fire_bomb_vfx: Node2D
var _stage: Node3D
var _overlay: Control
var _texture: TextureRect
var _state: Dictionary = {}
var _actor_nodes: Dictionary = {}
var _materials: Dictionary = {}
var _lina_materials: Array[StandardMaterial3D] = []
var _last_blocks := ""
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
var _last_visual_seq := -1
var _damage_numbers: Array = []
var _damage_history: Dictionary = {}
var _enemy_bar_state: Dictionary = {}
var _player_hit_until := -1.0
var _player_hit_health := false
var _player_hit_pos := Vector2.ZERO
var _danger_fades: Dictionary = {}
var _spawn_warning_fades: Dictionary = {}
var _active_danger_keys: Dictionary = {}
var _active_spawn_warning_keys: Dictionary = {}


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
	_texture.z_index = STAGE_Z_INDEX
	_texture.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	add_child(_texture)
	_overlay = Control.new()
	_overlay.name = "CombatReadability"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.z_index = COMBAT_OVERLAY_Z_INDEX
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	resized.connect(_layout_stage)
	_layout_stage()
	_build_world()
	fire_bolt_vfx = FireBoltVFX.new()
	# Same z as the stage, later sibling: above the stage image, below all
	# authoritative warnings and hostile missiles. No new global Glow.
	fire_bolt_vfx.z_index = STAGE_Z_INDEX
	add_child(fire_bolt_vfx)
	fire_rain_vfx = FireRainVFX.new()
	fire_rain_vfx.z_index = STAGE_Z_INDEX
	add_child(fire_rain_vfx)
	fire_beam_vfx = FireBeamVFX.new()
	fire_beam_vfx.z_index = STAGE_Z_INDEX
	add_child(fire_beam_vfx)
	fire_bomb_vfx = FireBombVFX.new()
	fire_bomb_vfx.z_index = STAGE_Z_INDEX
	add_child(fire_bomb_vfx)
	magic_missile_vfx = MagicMissileVFX.new()
	magic_missile_vfx.z_index = COMBAT_OVERLAY_Z_INDEX + 1
	add_child(magic_missile_vfx)
	if not _state.is_empty():
		sync(_state)


func sync(snapshot: Dictionary, _delta: float = 0.0) -> void:
	_state = snapshot
	if not is_instance_valid(actor):
		return
	if snapshot.has("room_revision") and int(snapshot.room_revision) != _room_revision:
		_rebuild_room(snapshot)
	var player: Dictionary = _state.get("player", {})
	var now := float(_state.get("time", 0.0))
	_consume_visual_events(now)
	_sync_warning_fades(now)
	actor.position = _point(player.get("pos", Vector2.ZERO))
	_sync_camera(snapshot, _delta)
	var face: Vector2 = player.get("face", Vector2.DOWN)
	if face.length_squared() > 0.0001:
		# The source model looks along local +X. Rotation changes facing only.
		actor.rotation.y = atan2(face.y, face.x)
	motion.sync(snapshot, _delta)
	var flash := _player_hit_strength(now)
	var hit_tint := Color("ff8f7c") if _player_hit_health else Color("7fd7e8")
	for mat in _lina_materials:
		mat.albedo_color = Color.WHITE.lerp(hit_tint, 0.76 * flash) if flash > 0.0 else Color.WHITE
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
	spell_vfx.set_fire_bolt_override(fire_bolt_vfx.is_available() and snapshot.has("fire_bolt_ends"))
	spell_vfx.set_fire_rain_override(fire_rain_vfx.is_available() and snapshot.has("fire_rain_impacts"))
	spell_vfx.set_fire_beam_override(fire_beam_vfx.is_available() and snapshot.has("fire_beam_facts"))
	spell_vfx.set_fire_bomb_override(fire_bomb_vfx.is_available() and snapshot.has_all(["fire_bomb_facts", "fire_bomb_status_facts"]))
	spell_vfx.sync_snapshot(snapshot, camera, _visual_options)
	fire_bolt_vfx.sync_snapshot(snapshot, self, _visual_options)
	fire_rain_vfx.sync_snapshot(snapshot, self, _visual_options)
	fire_beam_vfx.sync_snapshot(snapshot, self, _visual_options)
	fire_bomb_vfx.sync_snapshot(snapshot, self, _visual_options)
	gem_vfx.sync_snapshot(snapshot, camera, _visual_options)
	magic_missile_vfx.sync_snapshot(snapshot, self, _visual_options)
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
	if is_instance_valid(fire_bolt_vfx) and not _state.is_empty():
		fire_bolt_vfx.sync_snapshot(_state, self, _visual_options)
	if is_instance_valid(fire_rain_vfx) and not _state.is_empty():
		fire_rain_vfx.sync_snapshot(_state, self, _visual_options)
	if is_instance_valid(fire_beam_vfx) and not _state.is_empty():
		fire_beam_vfx.sync_snapshot(_state, self, _visual_options)
	if is_instance_valid(fire_bomb_vfx) and not _state.is_empty():
		fire_bomb_vfx.sync_snapshot(_state, self, _visual_options)
	if is_instance_valid(magic_missile_vfx) and not _state.is_empty():
		magic_missile_vfx.sync_snapshot(_state, self, _visual_options)


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
	var result: Dictionary = spell_vfx.get_debug_state() if is_instance_valid(spell_vfx) else {}
	var fire := get_fire_bolt_debug_state()
	result["fire_bolt"] = fire
	if not result.has("coverage"): result["coverage"] = {}
	if not result.has("footprints"): result["footprints"] = []
	for key in fire.get("coverage", {}): result.coverage[key] = int(result.coverage.get(key, 0)) + int(fire.coverage[key])
	result.footprints.append_array(fire.get("footprints", []))
	var rain := get_fire_rain_debug_state()
	result["fire_rain"] = rain
	for key in rain.get("coverage", {}): result.coverage[key] = int(result.coverage.get(key, 0)) + int(rain.coverage[key])
	result.footprints.append_array(rain.get("footprints", []))
	var beam := get_fire_beam_debug_state()
	result["fire_beam"] = beam
	for key in beam.get("coverage", {}): result.coverage[key] = int(result.coverage.get(key, 0)) + int(beam.coverage[key])
	result.footprints.append_array(beam.get("footprints", []))
	var bomb := get_fire_bomb_debug_state()
	result["fire_bomb"] = bomb
	for key in bomb.get("coverage", {}): result.coverage[key] = int(result.coverage.get(key, 0)) + int(bomb.coverage[key])
	result.footprints.append_array(bomb.get("footprints", []))
	return result


func get_fire_bolt_debug_state() -> Dictionary:
	return fire_bolt_vfx.get_debug_state() if is_instance_valid(fire_bolt_vfx) else {}


func get_fire_rain_debug_state() -> Dictionary:
	return fire_rain_vfx.get_debug_state() if is_instance_valid(fire_rain_vfx) else {}


func get_fire_beam_debug_state() -> Dictionary:
	return fire_beam_vfx.get_debug_state() if is_instance_valid(fire_beam_vfx) else {}


func get_fire_bomb_debug_state() -> Dictionary:
	return fire_bomb_vfx.get_debug_state() if is_instance_valid(fire_bomb_vfx) else {}

func get_gem_vfx_debug_state() -> Dictionary:
	return gem_vfx.get_debug_state() if is_instance_valid(gem_vfx) else {}


func get_magic_missile_debug_state() -> Dictionary:
	return magic_missile_vfx.get_debug_state() if is_instance_valid(magic_missile_vfx) else {}


func get_damage_number_debug_state() -> Dictionary:
	return {"enabled": bool(_visual_options.damage_numbers), "count": _damage_numbers.size(),
		"records": _damage_numbers.duplicate(true), "lifetime": DAMAGE_NUMBER_LIFETIME, "limit": DAMAGE_NUMBER_LIMIT}


func _layout_stage() -> void:
	# Explicit child sizes also support callers adding the component to Node2D.
	if is_instance_valid(_texture):
		_texture.position = Vector2.ZERO
		_texture.size = size
	if is_instance_valid(_overlay):
		_overlay.position = Vector2.ZERO
		_overlay.size = size
		_overlay.queue_redraw()
	if is_instance_valid(magic_missile_vfx) and not _state.is_empty():
		magic_missile_vfx.sync_snapshot(_state, self, _visual_options)
	if is_instance_valid(fire_bolt_vfx) and not _state.is_empty():
		fire_bolt_vfx.sync_snapshot(_state, self, _visual_options)
	if is_instance_valid(fire_rain_vfx) and not _state.is_empty():
		fire_rain_vfx.sync_snapshot(_state, self, _visual_options)
	if is_instance_valid(fire_beam_vfx) and not _state.is_empty():
		fire_beam_vfx.sync_snapshot(_state, self, _visual_options)
	if is_instance_valid(fire_bomb_vfx) and not _state.is_empty():
		fire_bomb_vfx.sync_snapshot(_state, self, _visual_options)


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
	_reset_combat_feedback()
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
	env_node.name = "CourtyardRenderEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0d141f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("9aa9c4")
	env.ambient_light_energy = 0.30
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.25
	# Local emissive planes and real lights retain the dark surround in this
	# Compatibility viewport; the rendered A/B probe rejected global glow.
	env.glow_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	# Restrained distance haze separates remote ruins without washing the arena.
	# Danger footprints remain in the un-fogged readability overlay above it.
	env.fog_enabled = true
	env.fog_light_color = Color("182234")
	env.fog_light_energy = 0.75
	env.fog_density = 0.0045
	env_node.environment = env
	world.add_child(env_node)
	_light(Vector3(-55, -24, 0), Color("ffe0b8"), 0.78, true)
	_light(Vector3(-28, 140, 0), Color("7c9bca"), 0.16, false)
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
		_track_enemy_health(data, float(_state.get("time", 0.0)))
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
	for id in _enemy_bar_state.keys():
		if not live.has(id):
			_enemy_bar_state.erase(id)


func _prepare_model(node: Node) -> void:
	if node is AnimationPlayer:
		node.stop()
		node.active = false
	if node is MeshInstance3D:
		for i in range(node.mesh.get_surface_count()):
			var source = node.get_active_material(i)
			if source is StandardMaterial3D:
				var copy := source.duplicate() as StandardMaterial3D
				# The approved model keeps its textures and clips. Slightly tighter
				# specular response separates Lina from the surrounding matte stone.
				copy.roughness = minf(copy.roughness, 0.82)
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
	m.roughness = 0.90
	if not unlit and (id.contains("gold") or id.contains("brass") or id.contains("metal")):
		m.metallic = 0.45
		m.roughness = 0.58
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
	var player: Dictionary = _state.get("player", {})
	# Fixed order: friendly ground/state, enemy ground warnings, health bars,
	# damage numbers/feedback, world labels, then hostile projectiles. The HUD stays above.
	CombatOverlay.draw_friendly_ground(self, _state)
	_draw_player_status_arc(player)
	for effect in _state.get("effects", []):
		_draw_effect(effect)
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
	CombatOverlay.draw_spawn_warnings(self, _state)
	CombatOverlay.draw_enemy_warnings(self, _state)
	_draw_enemy_health_bars(time)
	_draw_damage_numbers(time)
	_draw_player_hit_feedback(time)
	_draw_reward_pickup()
	var gate: Dictionary = _state.get("portal", {})
	if bool(gate.get("visible", false)):
		var gate_pos: Vector2 = gate.get("pos", Vector2(0, 6))
		var pulse := 1.0 if bool(_visual_options.reduced_motion) else 1.0 + sin(time * 2.5) * 0.025
		_ground_ring(gate_pos, 1.03 * pulse, Color.TRANSPARENT, Color(0.5, 0.95, 1, 0.35), 1.8)
	for marker in get_navigation_markers():
		_draw_navigation_marker(marker)
	CombatOverlay.draw_enemy_projectiles(self, _state)


func _draw_player_status_arc(player: Dictionary) -> void:
	var pos: Vector2 = player.get("pos", Vector2.ZERO)
	var cast := _primary_cast_visual()
	if not cast.is_empty():
		var progress := float(cast.get("progress", 0.0))
		var tint: Color = cast.get("tint", Color("f8cf8a"))
		_ground_arc(pos, 0.60, -PI * 0.5, TAU * maxf(0.025, progress), Color(tint, 0.82), 2.1)
		return
	var shield := float(player.get("shield", 0.0))
	if shield > 0.0:
		var ratio := clampf(shield / maxf(1.0, float(player.get("max_shield", 1.0))), 0.0, 1.0)
		# One low-brightness segmented status arc replaces the old full shield ring.
		_ground_arc(pos, 0.52, -PI * 0.5, TAU * (0.18 + ratio * 0.10), Color(0.50, 0.88, 1.0, 0.34), 1.35, 4)


func _primary_cast_visual() -> Dictionary:
	var result: Dictionary = {}
	var best_progress := -1.0
	for spell in _state.get("spells", []):
		var remaining := float(spell.get("cast_remaining", 0.0))
		if remaining <= 0.0:
			continue
		var windup := maxf(0.001, float(spell.get("windup", remaining)))
		var progress := clampf(1.0 - remaining / windup, 0.0, 1.0)
		if progress <= best_progress:
			continue
		best_progress = progress
		var id := str(spell.get("id", ""))
		result = {"progress": progress, "tint": Color({"L":"c5b3ff", "I":"8bd9ed", "W":"a4e4cf", "R":"d7b580", "S":"e6b7e5"}.get(id.left(1), "f8cf8a"))}
	return result


func _ground_arc(pos: Vector2, radius: float, start_angle: float, arc_length: float, color: Color, width: float, dashes: int = 0) -> void:
	if radius <= 0.0 or arc_length <= 0.0001:
		return
	var sf := size.x / LOGICAL_SIZE.x
	if dashes <= 0:
		var points := PackedVector2Array()
		var segments := maxi(4, int(ceil(absf(arc_length) / TAU * 48.0)))
		for index in segments + 1:
			var angle := start_angle + arc_length * float(index) / float(segments)
			points.append(screen_position(pos + Vector2.from_angle(angle) * radius, 0.045))
		_overlay.draw_polyline(points, color, width * sf, true)
		return
	var count := maxi(1, dashes)
	for dash in count:
		var dash_start := start_angle + arc_length * float(dash) / float(count)
		var dash_end := start_angle + arc_length * (float(dash) + 0.55) / float(count)
		var points := PackedVector2Array()
		for index in 5:
			var angle := lerpf(dash_start, dash_end, float(index) / 4.0)
			points.append(screen_position(pos + Vector2.from_angle(angle) * radius, 0.045))
		_overlay.draw_polyline(points, color, width * sf, true)


func _player_hit_strength(time: float) -> float:
	if time >= _player_hit_until:
		return 0.0
	var remaining := maxf(0.0, _player_hit_until - time)
	var elapsed := PLAYER_HIT_FLASH - remaining
	var fade := clampf(remaining / PLAYER_HIT_FLASH, 0.0, 1.0)
	if bool(_visual_options.reduced_motion):
		return 0.92 * fade
	return (0.62 + 0.38 * (0.5 + 0.5 * cos(elapsed * TAU / 0.07))) * fade


func _draw_player_hit_feedback(time: float) -> void:
	var strength := _player_hit_strength(time)
	if strength <= 0.0:
		return
	var sf := size.x / LOGICAL_SIZE.x
	var player: Dictionary = _state.get("player", {})
	var p := screen_position(player.get("pos", _player_hit_pos), 1.0)
	var color := Color(1.0, 0.50, 0.43, strength) if _player_hit_health else Color(0.47, 0.86, 1.0, strength)
	if _player_hit_health:
		# Warm slashes read as life loss; they never form a persistent ground ring.
		_overlay.draw_line(p + Vector2(-18, -18) * sf, p + Vector2(-7, -7) * sf, color, 2.4 * sf, true)
		_overlay.draw_line(p + Vector2(18, -14) * sf, p + Vector2(8, -4) * sf, color, 2.0 * sf, true)
		_overlay.draw_line(p + Vector2(1, 18) * sf, p + Vector2(7, 8) * sf, Color(color, color.a * 0.72), 1.8 * sf, true)
	else:
		# Cool shield shards distinguish absorbed damage from real health loss.
		for offset in [Vector2(-21, -5), Vector2(20, -8), Vector2(-15, 11), Vector2(16, 12)]:
			var center: Vector2 = p + offset * sf
			_overlay.draw_polyline(PackedVector2Array([center + Vector2(0, -4) * sf, center + Vector2(4, 0) * sf, center + Vector2(0, 4) * sf, center + Vector2(-4, 0) * sf]), color, 1.7 * sf, true)


func _consume_visual_events(time: float) -> void:
	var effects: Array = _state.get("effects", [])
	var max_seq := -1
	for effect in effects:
		max_seq = maxi(max_seq, int(effect.get("seq", -1)))
	if max_seq < _last_visual_seq:
		_last_visual_seq = -1
	for effect in effects:
		var seq := int(effect.get("seq", -1))
		if seq <= _last_visual_seq:
			continue
		match str(effect.get("kind", "")):
			"damage":
				_collect_damage_number(effect, time)
			"hurt":
				_note_player_hit(effect, time)
		_last_visual_seq = maxi(_last_visual_seq, seq)
	_prune_damage_numbers(time)


func _note_player_hit(effect: Dictionary, time: float) -> void:
	_player_hit_until = time + PLAYER_HIT_FLASH
	_player_hit_health = float(effect.get("health_damage", 0.0)) > 0.0
	_player_hit_pos = effect.get("pos", _state.get("player", {}).get("pos", Vector2.ZERO))


func _collect_damage_number(effect: Dictionary, time: float) -> void:
	var amount := maxf(0.0, float(effect.get("amount", 0.0)))
	if amount <= 0.0:
		return
	var target_key := _damage_target_key(effect)
	var dot := _is_dot_source(str(effect.get("spell_id", "")))
	var critical := _damage_is_critical(effect, target_key, amount, dot)
	var actor_id := int(effect.get("actor_id", -1))
	var pos: Vector2 = effect.get("pos", Vector2.ZERO)
	# Each core damage event owns one visible number. Never aggregate by target:
	# two real hits may legitimately land close together and must stay distinct.
	_damage_numbers.append({"seq": int(effect.get("seq", -1)), "actor_id": actor_id, "pos": pos,
		"amount": amount, "first_time": time, "last_time": time, "critical": critical, "dot": dot})
	while _damage_numbers.size() > DAMAGE_NUMBER_LIMIT:
		var oldest := 0
		for index in range(1, _damage_numbers.size()):
			if float(_damage_numbers[index].get("last_time", INF)) < float(_damage_numbers[oldest].get("last_time", INF)):
				oldest = index
		_damage_numbers.remove_at(oldest)


func _damage_target_key(effect: Dictionary) -> String:
	if effect.has("actor_id"):
		return "id:%d" % int(effect.get("actor_id", -1))
	var pos: Vector2 = effect.get("pos", Vector2.ZERO)
	return "pos:%d:%d" % [roundi(pos.x * 5.0), roundi(pos.y * 5.0)]


func _damage_is_critical(effect: Dictionary, target_key: String, amount: float, dot: bool) -> bool:
	if dot:
		return false
	for key in ["critical", "is_crit", "crit"]:
		if effect.has(key):
			return bool(effect.get(key, false))
	# The current core event omits the critical bit. Keep a conservative visual
	# fallback scoped to the same target and spell, without changing any damage.
	var history_key := target_key + "|" + str(effect.get("spell_id", ""))
	var history: Array = _damage_history.get(history_key, [])
	var critical := false
	if history.size() >= 2:
		var ordered := history.duplicate()
		ordered.sort()
		var median := float(ordered[int(ordered.size() / 2)])
		critical = amount > maxf(1.0, median * 1.45)
	history.append(amount)
	while history.size() > 6:
		history.pop_front()
	_damage_history[history_key] = history
	return critical


func _is_dot_source(spell_id: String) -> bool:
	var source := spell_id.to_lower()
	return source.contains("burn") or source.contains("dot") or source.contains("tick") or source.contains("inferno")


func _prune_damage_numbers(time: float) -> void:
	var live: Array = []
	for record in _damage_numbers:
		if time - float(record.get("last_time", -INF)) < DAMAGE_NUMBER_LIFETIME:
			live.append(record)
	_damage_numbers = live


func _draw_damage_numbers(time: float) -> void:
	if not bool(_visual_options.damage_numbers):
		return
	var sf := size.x / LOGICAL_SIZE.x
	for record in _damage_numbers:
		var age := time - float(record.get("last_time", time))
		if age < 0.0 or age >= DAMAGE_NUMBER_LIFETIME:
			continue
		var alpha := clampf(1.0 - age / DAMAGE_NUMBER_LIFETIME, 0.0, 1.0)
		var actor := _actor_by_id(int(record.get("actor_id", -1)))
		var pos: Vector2 = actor.get("pos", record.get("pos", Vector2.ZERO))
		var height := 1.72
		if not actor.is_empty():
			height = 2.35 if bool(actor.get("elite", false)) else (3.0 if bool(actor.get("boss", false)) or str(actor.get("type_id", "")).begins_with("BOSS") else 1.72)
		var p := screen_position(pos, height)
		var drift := (10.0 + 34.0 * clampf(age / DAMAGE_NUMBER_LIFETIME, 0.0, 1.0)) * sf
		var text := "%d" % int(round(float(record.get("amount", 0.0))))
		if bool(record.get("dot", false)):
			_center_text(text, p + Vector2(17, -3) * sf - Vector2(0, drift), 13, Color(0.92, 0.69, 0.43, alpha * 0.86))
		elif bool(record.get("critical", false)):
			_center_text(text, p - Vector2(0, drift), 28, Color(1.0, 0.92, 0.65, alpha))
			_overlay.draw_line(p + Vector2(-17, -5) * sf - Vector2(0, drift), p + Vector2(-11, -11) * sf - Vector2(0, drift), Color(1.0, 0.97, 0.78, alpha * 0.9), 1.6 * sf, true)
		else:
			_center_text(text, p - Vector2(0, drift), 20, Color(1.0, 0.94, 0.80, alpha))


func _actor_by_id(actor_id: int) -> Dictionary:
	if actor_id < 0:
		return {}
	for actor in _state.get("actors", []):
		if int(actor.get("id", -1)) == actor_id and float(actor.get("health", 0.0)) > 0.0:
			return actor
	return {}


func _track_enemy_health(enemy: Dictionary, time: float) -> void:
	var id := int(enemy.get("id", -1))
	if id < 0:
		return
	var health := float(enemy.get("health", 0.0))
	var maximum := maxf(1.0, float(enemy.get("max_health", 1.0)))
	var state: Dictionary = _enemy_bar_state.get(id, {})
	var is_new := state.is_empty()
	if is_new:
		state = {"last_health": health, "show_until": -INF}
	if health < float(state.get("last_health", health)) - 0.00001:
		state["show_until"] = time + ENEMY_BAR_HOLD
	elif is_new and health < maximum - 0.00001:
		state["show_until"] = time + ENEMY_BAR_HOLD
	state["last_health"] = health
	_enemy_bar_state[id] = state


func _draw_enemy_health_bars(time: float) -> void:
	var sf := size.x / LOGICAL_SIZE.x
	for enemy in _state.get("actors", []):
		var health := float(enemy.get("health", 0.0))
		if health <= 0.0:
			continue
		var type_id := str(enemy.get("type_id", ""))
		if bool(enemy.get("boss", false)) or type_id.begins_with("BOSS"):
			continue
		var maximum := maxf(1.0, float(enemy.get("max_health", 1.0)))
		var ratio := clampf(health / maximum, 0.0, 1.0)
		var elite := bool(enemy.get("elite", false)) or type_id.begins_with("EL")
		var alpha := 1.0
		if not elite:
			if ratio >= 0.99999:
				continue
			var state: Dictionary = _enemy_bar_state.get(int(enemy.get("id", -1)), {})
			var show_until := float(state.get("show_until", -INF))
			if time > show_until + ENEMY_BAR_FADE:
				continue
			if time > show_until:
				alpha = clampf(1.0 - (time - show_until) / ENEMY_BAR_FADE, 0.0, 1.0)
		var p := screen_position(enemy.get("pos", Vector2.ZERO), 2.18 if elite else 1.62)
		_draw_enemy_health_bar(p, ratio, elite, alpha, str(enemy.get("name", "精英")), sf)


func _draw_enemy_health_bar(p: Vector2, ratio: float, elite: bool, alpha: float, title: String, sf: float) -> void:
	var bar_size := Vector2(52, 5) * sf
	var rect := Rect2(p - bar_size * 0.5, bar_size)
	_overlay.draw_rect(rect, Color(0.025, 0.040, 0.055, 0.94 * alpha), true)
	var inner := rect.grow(-maxf(1.0, sf))
	if ratio > 0.0 and inner.size.x > 0.0:
		_overlay.draw_rect(Rect2(inner.position, Vector2(inner.size.x * ratio, inner.size.y)), Color("edbd72") if elite else Color("9ee3c5"), true)
	_overlay.draw_rect(rect, Color(0.76, 0.84, 0.86, 0.42 * alpha), false, maxf(1.0, sf), true)
	if elite:
		_center_text(title, p - Vector2(0, 12 * sf), 15, Color(0.96, 0.82, 0.53, alpha))


func _sync_warning_fades(time: float) -> void:
	var current_danger: Dictionary = {}
	for actor in _state.get("actors", []):
		if not actor.has("type_id") or float(actor.get("health", 0.0)) <= 0.0:
			continue
		var danger: Dictionary = actor.get("danger", {})
		if not danger.is_empty():
			current_danger[_danger_key(actor, danger, "single")] = danger.duplicate(true)
		var dangers: Array = actor.get("dangers", [])
		for index in dangers.size():
			current_danger[_danger_key(actor, dangers[index], str(index))] = dangers[index].duplicate(true)
	for key in _active_danger_keys.keys():
		if not current_danger.has(key):
			_danger_fades[key] = {"danger": _active_danger_keys[key].duplicate(true), "until": time + WARNING_FADE_SECONDS}
	_active_danger_keys = current_danger
	for key in current_danger.keys():
		_danger_fades.erase(key)
	for key in _danger_fades.keys():
		var entry: Dictionary = _danger_fades[key]
		var remaining := float(entry.get("until", time)) - time
		if remaining <= 0.0:
			_danger_fades.erase(key)
		else:
			entry["remaining"] = remaining
			_danger_fades[key] = entry

	var current_spawn: Dictionary = {}
	for warning in _state.get("spawn_warnings", []):
		current_spawn[_spawn_warning_key(warning)] = warning.duplicate(true)
	for key in _active_spawn_warning_keys.keys():
		if not current_spawn.has(key):
			_spawn_warning_fades[key] = {"warning": _active_spawn_warning_keys[key].duplicate(true), "until": time + WARNING_FADE_SECONDS}
	_active_spawn_warning_keys = current_spawn
	for key in current_spawn.keys():
		_spawn_warning_fades.erase(key)
	for key in _spawn_warning_fades.keys():
		var entry: Dictionary = _spawn_warning_fades[key]
		var remaining := float(entry.get("until", time)) - time
		if remaining <= 0.0:
			_spawn_warning_fades.erase(key)
		else:
			entry["remaining"] = remaining
			_spawn_warning_fades[key] = entry


func _danger_key(actor: Dictionary, danger: Dictionary, suffix: String) -> String:
	return "%s|%s|%s|%s|%s|%s|%s|%s" % [str(actor.get("id", -1)), suffix, str(danger.get("kind", "")), str(danger.get("pos", Vector2.ZERO)), str(danger.get("from", Vector2.ZERO)), str(danger.get("to", Vector2.ZERO)), str(danger.get("spread_degrees", [])), str(danger.get("shot_index", 0))]


func _spawn_warning_key(warning: Dictionary) -> String:
	return "spawn|%s|%s" % [str(warning.get("pos", Vector2.ZERO)), str(warning.get("radius", 0.0))]


func _reset_combat_feedback() -> void:
	_last_visual_seq = -1
	_damage_numbers.clear()
	_damage_history.clear()
	_enemy_bar_state.clear()
	_player_hit_until = -1.0
	_player_hit_health = false
	_player_hit_pos = Vector2.ZERO
	_danger_fades.clear()
	_spawn_warning_fades.clear()
	_active_danger_keys.clear()
	_active_spawn_warning_keys.clear()


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
	if str(effect.get("kind", "")) in ["hurt", "damage"]:
		# Player hit feedback and aggregated damage numbers are presentation-only
		# layers owned by _draw_overlay.
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
			_ground_arc(pos, 0.52 + progress * 0.20, -PI * 0.5, TAU * clampf(progress, 0.0, 1.0), Color(1.0, 0.79, 0.47, alpha * 0.8), 2.0)
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
