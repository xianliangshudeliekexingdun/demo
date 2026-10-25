extends SubViewportContainer
## 主界面 3D 舞台：地下城入口、火把与莉奈待机。
## 纯展示层，只播放已批准的骨骼待机动作，不驱动任何规则状态。

const Motion=preload("res://scripts/presentation/lina_motion.gd")

var viewport:SubViewport
var actor:Node3D
var motion:Node3D
var camera:Camera3D
var torches:Array=[]
var flames:Array=[]
var _time:=0.0


func _ready():
	stretch=true
	clip_contents=true
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	viewport=SubViewport.new()
	viewport.size=Vector2i(1600,900)
	viewport.own_world_3d=true
	viewport.msaa_3d=Viewport.MSAA_4X
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	visibility_changed.connect(_on_visibility)
	_build()


func _on_visibility():
	if not is_instance_valid(viewport): return
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED


func _process(delta):
	var dt=clampf(delta,0.0,0.1)
	_time+=dt
	if is_instance_valid(motion):
		motion.advance_menu(dt)
	if is_instance_valid(camera):
		camera.h_offset=sin(_time*0.29)*0.022
		camera.v_offset=sin(_time*0.41)*0.016
	for i in range(torches.size()):
		var torch=torches[i]
		if is_instance_valid(torch):
			torch.light_energy=2.3+sin(_time*6.7+float(i)*1.9)*0.34+sin(_time*12.3+float(i))*0.14
	for i in range(flames.size()):
		var flame=flames[i]
		if is_instance_valid(flame):
			flame.scale=Vector3(1.0+sin(_time*7.3+float(i))*0.06,1.0+sin(_time*9.1+float(i)*2.1)*0.14,1.0)


func _build():
	var surroundings=WorldEnvironment.new()
	var env=Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("0b0908")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("66779c")
	env.ambient_light_energy=0.36
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	env.fog_enabled=true
	env.fog_light_color=Color("241d17")
	env.fog_density=0.030
	surroundings.environment=env
	viewport.add_child(surroundings)

	_dir_light(Vector3(-40,-32,0),Color("ffd6a2"),0.52,true)
	_dir_light(Vector3(-18,138,0),Color("6f86b8"),0.16,false)

	var dungeon=load("res://assets/environment/dungeon_gate/dungeon_gate.glb")
	if dungeon!=null:
		var stage=dungeon.instantiate()
		stage.name="DungeonGate"
		viewport.add_child(stage)

	_torch(Vector3(-2.30,1.02,-5.55),false)
	_torch(Vector3(2.30,1.02,-5.55),false)

	var depth=OmniLight3D.new()
	depth.position=Vector3(0.2,1.6,-8.6)
	depth.light_color=Color("6f9ec4")
	depth.light_energy=1.4
	depth.omni_range=8.0
	viewport.add_child(depth)

	var fill=OmniLight3D.new()
	fill.position=Vector3(2.4,2.2,1.4)
	fill.light_color=Color("c9a074")
	fill.light_energy=1.5
	fill.omni_range=9.0
	viewport.add_child(fill)

	actor=Node3D.new()
	actor.name="StageLina"
	actor.rotation_degrees.y=-90.0
	actor.position=Vector3(0.86,0.0,-0.15)
	actor.scale=Vector3(1.0,1.0,1.0)
	viewport.add_child(actor)
	motion=Motion.new()
	actor.add_child(motion)
	motion.set_menu_mode(true)

	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	camera.fov=38.0
	camera.near=0.05
	camera.far=40.0
	camera.position=Vector3(0.90,1.08,2.40)
	viewport.add_child(camera)
	camera.look_at(Vector3(-0.42,0.48,-1.20))
	camera.current=true


func _torch(pos:Vector3,with_stem:bool=true):
	var root=Node3D.new()
	root.position=pos
	viewport.add_child(root)

	if with_stem:
		var stem=MeshInstance3D.new()
		var stem_mesh=BoxMesh.new()
		stem_mesh.size=Vector3(0.06,0.38,0.06)
		stem.mesh=stem_mesh
		var dark=StandardMaterial3D.new()
		dark.albedo_color=Color("2a2119")
		dark.roughness=0.85
		stem.material_override=dark
		stem.position.y=-0.24
		root.add_child(stem)

	var flame=MeshInstance3D.new()
	var cone=CylinderMesh.new()
	cone.top_radius=0.010
	cone.bottom_radius=0.120
	cone.height=0.40
	cone.radial_segments=10
	flame.mesh=cone
	var glow=StandardMaterial3D.new()
	glow.albedo_color=Color("ff9a3c")
	glow.emission_enabled=true
	glow.emission=Color("ff7a2a")
	glow.emission_energy_multiplier=2.2
	glow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.material_override=glow
	flame.position.y=0.24
	root.add_child(flame)
	flames.append(flame)

	var core=MeshInstance3D.new()
	var core_mesh=SphereMesh.new()
	core_mesh.radius=0.038
	core_mesh.height=0.10
	core.mesh=core_mesh
	var hot=StandardMaterial3D.new()
	hot.albedo_color=Color("fff2cf")
	hot.emission_enabled=true
	hot.emission=Color("ffd08a")
	hot.emission_energy_multiplier=4.0
	hot.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	core.material_override=hot
	core.position.y=-0.02
	root.add_child(core)

	var light=OmniLight3D.new()
	light.light_color=Color("ffab63")
	light.light_energy=2.3
	light.omni_range=6.2
	light.omni_attenuation=1.4
	light.shadow_enabled=false
	light.position.y=0.05
	root.add_child(light)
	torches.append(light)


func _dir_light(angles:Vector3,tint:Color,energy:float,shadows:bool):
	var light=DirectionalLight3D.new()
	light.rotation_degrees=angles
	light.light_color=tint
	light.light_energy=energy
	light.shadow_enabled=shadows
	light.shadow_blur=1.8
	light.light_angular_distance=1.2
	light.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	viewport.add_child(light)
