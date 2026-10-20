extends SubViewportContainer
## Read-only menu display using Lina's existing genuine skeletal idle clip.
## Recommended UI rect: 560 x 600. Drag horizontally to inspect the actual model.
## API: set_yaw_degrees(), reset_view(), set_interactive(), get_portrait_viewport().

const Motion := preload("res://scripts/presentation/lina_motion.gd")
const DEFAULT_YAW_DEGREES := -90.0

var interactive := true
var portrait_viewport: SubViewport
var actor: Node3D
var motion: Node3D
var camera: Camera3D
var _dragging := false


func _ready() -> void:
	stretch = true
	clip_contents = true
	set_interactive(interactive)
	portrait_viewport = SubViewport.new()
	portrait_viewport.name = "LinaPortraitViewport"
	portrait_viewport.size = Vector2i(maxi(2, int(size.x)), maxi(2, int(size.y)))
	portrait_viewport.own_world_3d = true
	portrait_viewport.transparent_bg = true
	portrait_viewport.gui_disable_input = true
	portrait_viewport.msaa_3d = Viewport.MSAA_4X
	portrait_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(portrait_viewport)
	_build_world()
	gui_input.connect(_on_gui_input)
	visibility_changed.connect(_on_visibility_changed)
	resized.connect(_request_redraw)


func _build_world() -> void:
	var world := Node3D.new()
	world.name = "PortraitWorld"
	portrait_viewport.add_child(world)
	var surroundings := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a5b2cf")
	environment.ambient_light_energy = 0.40
	surroundings.environment = environment
	world.add_child(surroundings)
	_add_light(world, Vector3(-35.0, -28.0, 0.0), Color("ffedcd"), 0.65, true)
	_add_light(world, Vector3(-20.0, 150.0, 0.0), Color("7ccedc"), 0.25, false)
	_add_light(world, Vector3(-15.0, 65.0, 0.0), Color("c0b2df"), 0.10, false)
	_build_plinth(world)
	actor = Node3D.new()
	actor.name = "LinaActor"
	actor.rotation_degrees.y = DEFAULT_YAW_DEGREES
	world.add_child(actor)
	motion = Motion.new()
	actor.add_child(motion)
	motion.set_menu_mode(true)
	camera = Camera3D.new()
	camera.name = "PortraitCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.20
	camera.near = 0.05
	camera.far = 10.0
	camera.position = Vector3(1.35, 0.82, 2.8)
	world.add_child(camera)
	camera.look_at(Vector3(0.0, 0.46, 0.0))
	camera.current = true


func _add_light(world: Node3D, angles: Vector3, tint: Color, energy: float, shadows: bool) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = angles
	light.light_color = tint
	light.light_energy = energy
	light.shadow_enabled = shadows
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	world.add_child(light)


func _build_plinth(world: Node3D) -> void:
	var base := MeshInstance3D.new()
	base.name = "ObsidianPlinth"
	var shape := CylinderMesh.new()
	shape.top_radius = 0.31
	shape.bottom_radius = 0.33
	shape.height = 0.035
	shape.radial_segments = 96
	base.mesh = shape
	base.position.y = -0.025
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("182337")
	stone.roughness = 0.85
	base.material_override = stone
	world.add_child(base)
	var trim := MeshInstance3D.new()
	trim.name = "AntiqueGoldRim"
	var rim := TorusMesh.new()
	rim.inner_radius = 0.300
	rim.outer_radius = 0.308
	rim.rings = 64
	rim.ring_segments = 12
	trim.mesh = rim
	trim.position.y = -0.004
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("ac8954")
	metal.metallic = 0.25
	metal.roughness = 0.55
	trim.material_override = metal
	world.add_child(trim)


func _process(delta: float) -> void:
	if is_instance_valid(motion) and is_visible_in_tree():
		motion.advance_menu(delta)


func set_yaw_degrees(value: float) -> void:
	if is_instance_valid(actor):
		actor.rotation_degrees.y = wrapf(value, -180.0, 180.0)
		_request_redraw()


func reset_view() -> void:
	set_yaw_degrees(DEFAULT_YAW_DEGREES)


func set_interactive(value: bool) -> void:
	interactive = value
	_dragging = false
	mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	tooltip_text = "按住鼠标左右拖动，查看莉奈的 3D 模型" if value else ""


func get_portrait_viewport() -> SubViewport:
	return portrait_viewport


func _on_visibility_changed() -> void:
	_dragging = false
	if is_visible_in_tree():
		_request_redraw()
	elif is_instance_valid(portrait_viewport):
		portrait_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _request_redraw() -> void:
	if is_instance_valid(portrait_viewport):
		portrait_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED


func _on_gui_input(event: InputEvent) -> void:
	if not interactive or not is_instance_valid(actor):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.double_click:
			reset_view()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_dragging = false
			return
		set_yaw_degrees(actor.rotation_degrees.y + event.relative.x * 0.45)
		accept_event()
