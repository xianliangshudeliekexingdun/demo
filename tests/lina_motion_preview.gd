extends SceneTree
## Self-exiting deterministic preview. No interactive game is started.
const RIG = preload("res://scripts/presentation/lina_motion_prototype.gd")
const ORIGINAL = preload("res://assets/characters/lina.png")
const GROUND = preload("res://assets/environment/ground.png")
const FONT = preload("res://assets/fonts/NotoSansSC.ttf")
var rigs: Array = []
var progress: Label
var output = "res://build/qa/lina-motion-v2/"
var failures = 0

func _initialize(): call_deferred("run")

func label(parent: Node, text: String, at: Vector2, size: int, color = Color("e6e1d4")) -> Label:
	var item = Label.new()
	item.text = text
	item.position = at
	item.add_theme_font_override("font",FONT)
	item.add_theme_font_size_override("font_size",size)
	item.add_theme_color_override("font_color",color)
	parent.add_child(item)
	return item

func panel(parent: Node, rect: Rect2, color: Color):
	var p = ColorRect.new()
	p.position=rect.position
	p.size=rect.size
	p.color=color
	parent.add_child(p)

func add_rig(parent: Node, at: Vector2, magnify: float):
	var actor=RIG.new()
	actor.position=at
	actor.scale=Vector2.ONE*magnify
	parent.add_child(actor)
	rigs.append(actor)

func run():
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i(1280,720)
	DisplayServer.window_set_size(Vector2i(1280,720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output+"frames"))
	var stage=Node2D.new()
	root.add_child(stage)
	panel(stage,Rect2(0,0,1280,720),Color("17272e"))
	label(stage,"莉奈 / 动作小样 02",Vector2(40,24),30)
	label(stage,"单一斜正面 · 分层实验 · 非正式角色替换",Vector2(42,72),16,Color("a6babd"))
	panel(stage,Rect2(32,117,370,390),Color("263a40"))
	panel(stage,Rect2(414,117,410,390),Color("263a40"))
	panel(stage,Rect2(836,117,412,390),Color("263a40"))
	label(stage,"原角色 / 静态基线",Vector2(54,132),19)
	label(stage,"待机 / 2 倍检查",Vector2(438,132),19)
	label(stage,"移动 / 2 倍检查",Vector2(860,132),19)
	var original=Sprite2D.new()
	original.texture=ORIGINAL
	original.scale=Vector2.ONE*(169.6*2/512)
	original.position=Vector2(211,462)-Vector2(0.02,0.455)*339.2
	stage.add_child(original)
	add_rig(stage,Vector2(621,464),2)
	add_rig(stage,Vector2(1041,464),2)
	var ground=TextureRect.new()
	var atlas=AtlasTexture.new()
	atlas.atlas=GROUND
	atlas.region=Rect2(0,620,720,110)
	ground.texture=atlas
	ground.position=Vector2(32,520)
	ground.size=Vector2(1216,186)
	stage.add_child(ground)
	label(stage,"游戏原尺寸 · 待机 → 移动 → 停步",Vector2(52,531),17,Color("243239"))
	# Ground contact shadows stay on the ground independently of the body.
	var shadow_script=GDScript.new()
	shadow_script.source_code="extends Node2D\nfunc _draw():\n\tdraw_set_transform(Vector2.ZERO,0,Vector2(1,0.28))\n\tfor i in range(12): draw_circle(Vector2.ZERO,33.5*(1-i*0.042),Color(0.14,0.12,0.11,0.034),true,-1,true)\n"
	if shadow_script.reload()!=OK: quit(1); return
	var contact=Node2D.new()
	contact.set_script(shadow_script)
	stage.add_child(contact)
	add_rig(stage,Vector2(410,690),1)
	progress=label(stage,"",Vector2(880,671),15,Color("243239"))
	var frames=240
	var manifest={"frames":frames,"fps":30,"size":[1280,720],"completed":false}
	var max_stance_drift=0.0
	for step in range(11):
		var t0=0.04+step*0.025
		rigs[1].sample(t0,true)
		var p0=rigs[1].foot_at(0)+Vector2(t0*55,0)
		rigs[1].sample(t0+0.01,true)
		var p1=rigs[1].foot_at(0)+Vector2((t0+0.01)*55,0)
		max_stance_drift=maxf(max_stance_drift,p0.distance_to(p1))
	if max_stance_drift>0.001: failures+=1
	print("STANCE_DRIFT_PX=",max_stance_drift)
	for i in range(frames):
		var t=float(i)/30.0
		rigs[0].sample(t,false)
		rigs[1].sample(t,true)
		var walk_time=clampf(t-2.0,0,4.0)
		var moving=t>=2.0 and t<6.0
		var blend=minf(smoothstep(0.0,0.2,walk_time),1.0-smoothstep(3.8,4.0,walk_time))
		rigs[2].position=Vector2(410+walk_time*55,682)
		rigs[2].sample(walk_time if moving else t,moving,blend)
		contact.position=rigs[2].position
		progress.text="%.1f 秒 / %s" % [t,"移动" if moving else "待机"]
		await process_frame
		await RenderingServer.frame_post_draw
		var frame=root.get_texture().get_image()
		if frame.save_png(output+"frames/%04d.png" % i)!=OK: failures+=1
		if i in [0,3,6,9,12,18,24,60,66,83,85,95,120,174,179,180,239]:
			frame.save_png(output+"pose-%03d.png" % i)
	manifest.completed=true
	manifest.failures=failures
	manifest.max_stance_drift_px=max_stance_drift
	var record=FileAccess.open(output+"result.json",FileAccess.WRITE)
	record.store_string(JSON.stringify(manifest,"\t"))
	record.close()
	print("LINA_PREVIEW frames=",frames," failures=",failures)
	quit(1 if failures else 0)
