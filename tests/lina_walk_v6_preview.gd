extends SceneTree
## Isolated, self-exiting visual capture. Does not load battle state.
const OUT = "res://build/qa/lina-walk-v6/"
const FONT = preload("res://assets/fonts/NotoSansSC.ttf")

class Actor extends Node2D:
	var textures: Array
	var poses: Array
	var index: int = 0
	var canvas_size: float = 169.6
	func _draw():
		var p: Dictionary = poses[index]
		var b: Array = p.bounds
		var region := Rect2(float(b[0]),float(b[1]),float(b[2]),float(b[3]))
		var h: float = canvas_size * 0.92
		var scale_factor: float = h / region.size.y
		var dims := region.size * scale_factor
		draw_set_transform(Vector2.ZERO,0,Vector2(1,0.26))
		draw_circle(Vector2.ZERO,canvas_size*0.17,Color(0.04,0.05,0.06,0.28))
		draw_set_transform(Vector2.ZERO)
		draw_texture_rect_region(textures[index],Rect2(Vector2(-dims.x*0.5,-h),dims),region)

func _initialize(): call_deferred("run")
func label(stage: Node,text: String,pos: Vector2,size: int=18):
	var l=Label.new()
	l.text=text
	l.position=pos
	l.add_theme_font_override("font",FONT)
	l.add_theme_font_size_override("font_size",size)
	l.add_theme_color_override("font_color",Color("eee9df"))
	stage.add_child(l)
	return l
func panel(stage: Node,rect: Rect2,color: Color):
	var n=ColorRect.new()
	n.position=rect.position
	n.size=rect.size
	n.color=color
	stage.add_child(n)
func run():
	root.size=Vector2i(960,640)
	root.content_scale_size=Vector2i(960,640)
	DisplayServer.window_set_size(Vector2i(960,640))
	var manifest=JSON.parse_string(FileAccess.get_file_as_string(OUT+"atlas.json"))
	if manifest==null:
		push_error("Missing v6 preview inputs")
		quit(1)
		return
	var textures=[]
	for pose in manifest.poses:
		var img=Image.load_from_file(ProjectSettings.globalize_path(OUT+pose.file))
		if img==null:
			quit(1)
			return
		textures.append(ImageTexture.create_from_image(img))
	var stage=Node2D.new()
	root.add_child(stage)
	panel(stage,Rect2(0,0,960,640),Color("19272e"))
	label(stage,"莉奈 · 单方向步行试验",Vector2(30,18),28)
	label(stage,"4 张关键姿势 / 1 秒双步循环 / Godot 实际渲染",Vector2(31,61),17)
	panel(stage,Rect2(24,106,430,494),Color("293a43"))
	panel(stage,Rect2(472,106,464,284),Color("293a43"))
	panel(stage,Rect2(472,408,464,192),Color("293a43"))
	label(stage,"放大检查",Vector2(42,119),20)
	label(stage,"原版静态",Vector2(533,120),17)
	label(stage,"步行 · 169.6px 画布",Vector2(720,120),17)
	label(stage,"平移演示（非玩法接入）",Vector2(490,419),16)
	var actors=[]
	for config in [[Vector2(241,555),395.0],[Vector2(818,347),169.6],[Vector2(540,586),169.6]]:
		var a=Actor.new()
		a.textures=textures
		a.poses=manifest.poses
		a.position=config[0]
		a.canvas_size=config[1]
		stage.add_child(a)
		actors.append(a)
	var original=Sprite2D.new()
	original.texture=load("res://assets/characters/lina.png")
	original.scale=Vector2.ONE*169.6/512.0
	original.position=Vector2(593,347)-Vector2(.02,.455)*169.6
	stage.add_child(original)
	var counter=label(stage,"",Vector2(32,610),15)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT+"frames"))
	var failures=0
	for f in range(192):
		var pose_index: int = (f / 6) % 4
		for a in actors:
			a.index=pose_index
			a.queue_redraw()
		actors[2].position.x=540.0+float(f%96)*3.1
		counter.text="姿势 %d / 4   ·   试验预览，尚未替换正式角色" % (pose_index+1)
		await process_frame
		await RenderingServer.frame_post_draw
		var img=root.get_texture().get_image()
		if img.save_png(OUT+"frames/%04d.png" % f)!=OK: failures+=1
		if f%6==0 and f<24: img.save_png(OUT+"key-%02d.png" % pose_index)
	var file=FileAccess.open(OUT+"capture-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"completed":true,"frames":192,"fps":24,"poses":4,"failures":failures},"\t"))
	file.close()
	print("LINA_WALK_V6_COMPLETE failures=",failures)
	quit(1 if failures else 0)
