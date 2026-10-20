extends SceneTree
const POSE = preload("res://scripts/presentation/lina_keypose_preview.gd")
const ORIGINAL = preload("res://assets/characters/lina.png")
const FONT = preload("res://assets/fonts/NotoSansSC.ttf")
const TITLES = ["01  落脚","02  下沉","03  经过","04  蹬地 · 待修"]
const OUTPUT = "res://build/qa/lina-keyposes-v3/"
var failures = 0

func _initialize(): call_deferred("run")

func rect(parent: Node, bounds: Rect2, color: Color):
	var c=ColorRect.new()
	c.position=bounds.position
	c.size=bounds.size
	c.color=color
	parent.add_child(c)

func label(parent: Node, text: String, pos: Vector2, size: int, color=Color("e8e1d4")) -> Label:
	var l=Label.new()
	l.position=pos
	l.text=text
	l.add_theme_font_override("font",FONT)
	l.add_theme_font_size_override("font_size",size)
	l.add_theme_color_override("font_color",color)
	parent.add_child(l)
	return l

func pose_at(parent: Node, pos: Vector2, index: int, scale_factor: float):
	var p=POSE.new()
	p.position=pos
	p.pose=index
	p.magnify=scale_factor
	parent.add_child(p)
	return p

func run():
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i(1280,720)
	DisplayServer.window_set_size(Vector2i(1280,720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT+"frames"))
	var stage=Node2D.new()
	root.add_child(stage)
	rect(stage,Rect2(0,0,1280,720),Color("17272e"))
	label(stage,"莉奈 / 行走关键姿势 v3",Vector2(32,20),28)
	label(stage,"整身姿势检查 · 四张覆盖半步 · 非完整行走循环",Vector2(33,62),17,Color("afc1c2"))
	for i in range(4):
		var x=24+i*312
		rect(stage,Rect2(x,104,296,338),Color("283c43"))
		label(stage,TITLES[i],Vector2(x+16,112),19)
		rect(stage,Rect2(x+24,420,248,1),Color("769292"))
		pose_at(stage,Vector2(x+162,420),i,0.44)
	rect(stage,Rect2(24,457,1232,241),Color("21353a"))
	label(stage,"原图 / 实际尺寸",Vector2(46,473),16)
	var original=Sprite2D.new()
	original.texture=ORIGINAL
	original.scale=Vector2.ONE*169.6/512
	original.position=Vector2(159,685)-Vector2(0.02,0.455)*169.6
	stage.add_child(original)
	label(stage,"关键姿势低速切换 / 实际尺寸",Vector2(336,473),16)
	var animated=pose_at(stage,Vector2(469,685),0,0.26)
	var phase=label(stage,"",Vector2(647,518),23)
	label(stage,"先看支撑关系和重心；暂不补帧。\n第 4 张蹬地脚跟、步幅仍需调整。",Vector2(648,567),18,Color("c1cecb"))
	var result={"completed":false,"frames":120,"fps":20}
	var file=FileAccess.open(OUTPUT+"result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	for frame in range(120):
		var index=mini(frame/25,3)
		animated.pose=index
		animated.queue_redraw()
		phase.text=TITLES[index]+(" / 末帧停留" if frame>=100 else "")
		await process_frame
		await RenderingServer.frame_post_draw
		var img=root.get_texture().get_image()
		if img.save_png(OUTPUT+"frames/%04d.png" % frame)!=OK: failures+=1
		if frame in [0,25,50,75]: img.save_png(OUTPUT+"pose-%d.png" % index)
	result.completed=true
	result.failures=failures
	file=FileAccess.open(OUTPUT+"result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("KEYPOSE_PREVIEW failures=",failures)
	quit(1 if failures else 0)
