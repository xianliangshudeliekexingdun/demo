extends SceneTree
const Main=preload("res://scripts/main.gd")
const Meta=preload("res://scripts/core/meta_progression.gd")
const OUT="res://build/qa/catalyst-ui-20261018/menu/"
const SAVE="user://tests/menu_suite_visual.json"
var game
var failures=0
var checks=0
var captures:Array[String]=[]
func _initialize(): call_deferred("run")
func check(ok:bool,message:String):
	checks+=1
	if not ok:
		failures+=1
		push_error("UI suite: "+message)
func button_named(title:String):
	for b in game.ui.page.find_children("*","Button",true,false):
		if b.text==title: return b
	return null
func click(title:String):
	var b=button_named(title)
	check(b!=null,"button exists: "+title)
	if b==null: return
	var window_scale=Vector2(root.size)/Vector2(1600,900)
	var p=b.get_global_rect().get_center()*window_scale
	var motion=InputEventMouseMotion.new()
	motion.position=p
	Input.parse_input_event(motion)
	await process_frame
	for pressed in [true,false]:
		var e=InputEventMouseButton.new()
		e.position=p
		e.button_index=MOUSE_BUTTON_LEFT
		e.pressed=pressed
		Input.parse_input_event(e)
		await process_frame
func snap(name:String):
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img=root.get_texture().get_image()
	check(img.save_png(OUT+name+".png")==OK,"capture "+name)
	captures.append(name)
	for b in game.ui.page.find_children("*","Button",true,false):
		# Scroll contents may extend beyond the viewport; the enclosing container clips them.
		if b.get_parent() is VBoxContainer: continue
		check(b.get_global_rect().end.x<=1601 and b.get_global_rect().end.y<=900,"button within logical viewport: "+b.text)
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	DirAccess.make_dir_recursive_absolute("user://tests")
	for suffix in ["",".tmp",".bak"]:
		if FileAccess.file_exists(SAVE+suffix): DirAccess.remove_absolute(SAVE+suffix)
	DisplayServer.window_set_size(Vector2i(1280,720))
	game=Main.new()
	game.save_path=SAVE
	root.add_child(game)
	await process_frame
	check(game.load_error.is_empty(),"catalog and isolated save loaded")
	check(button_named("五法术构筑试验")==null,"old menu removed")
	await snap("01-home-1280")
	await click("法术触媒")
	check(game.screen=="catalyst","real mouse opens catalysts")
	await snap("02-catalysts-new")
	await click("免费领取并装备")
	check(game.meta.get_state().equipped.catalyst=="MC04","free catalyst transaction")
	await snap("03-catalysts-owned")
	await click("魔力宝石")
	check(game.screen=="gem","tab opens gems")
	await click("免费领取并装备")
	check(game.meta.get_state().equipped.gem=="MG01","independent free gem")
	await snap("04-gems-owned")
	var reopened=Meta.new(SAVE)
	check(reopened.load_state().ok and reopened.get_state()==game.meta.get_state(),"UI mutations persist to disk")
	game.navigate("prepare")
	await snap("05-prepare")
	await click("查看界面预览")
	check(game.screen=="opening","prepare opens marked preview")
	await snap("06-opening")
	await click("选用并预览")
	check(game.screen=="hud","opening choice navigates HUD")
	check(game.meta.is_in_run() and game.meta.get_run_snapshot().preview_only,"preview freezes equipment snapshot")
	check(not game.meta.request_equip("gem","").ok,"preview cannot change equipment")
	await snap("07-hud")
	var before=game.meta.get_state()
	for next in ["reward","chest","shop","pause","result","spells","artifacts","settings"]:
		game.navigate(next)
		await snap("08-"+next)
	check(not game.meta.is_in_run(),"leaving preview releases equipment lock")
	var fps=Engine.max_fps
	await click("%d 帧 / 秒 · 点击切换"%fps)
	check(Engine.max_fps!=fps,"frame cap changes actual engine setting")
	await click("%d 帧 / 秒 · 点击切换"%Engine.max_fps)
	check(Engine.max_fps==fps,"frame cap restores")
	var previous_mode=DisplayServer.window_get_mode()
	await click("切换全屏 / 窗口")
	check(DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN,"display button enters actual fullscreen")
	await click("切换全屏 / 窗口")
	check(DisplayServer.window_get_mode()==previous_mode,"display button restores actual window mode")
	DisplayServer.window_set_size(Vector2i(1280,720))
	await process_frame
	game.navigate("spells")
	await click("三级")
	check(game.ui.detail_label.text==game.ui.spell_text("F01",3),"spell level detail updates")
	check(before==game.meta.get_state(),"all previews leave progression untouched")
	game.navigate("artifacts")
	await process_frame
	await process_frame
	var list=game.ui.page.get_node("CatalogList")
	check(list.follow_focus,"catalog follows keyboard focus")
	var buttons=list.find_children("*","Button",true,false)
	var final_id=str(buttons.back().get_meta("selection_id",""))
	buttons.back().grab_focus()
	await process_frame
	await process_frame
	check(list.scroll_vertical>0,"keyboard focus scrolls to final artifact")
	for pressed in [true,false]:
		var key=InputEventKey.new()
		key.keycode=KEY_ENTER
		key.pressed=pressed
		Input.parse_input_event(key)
		await process_frame
	await process_frame
	check(not final_id.is_empty() and game.selected==final_id,"keyboard selects final artifact")
	check(game.ui.page.get_node("CatalogList").scroll_vertical>0,"selection retains catalog scroll")
	await snap("08-artifacts-scrolled")
	game.navigate("pause")
	await process_frame
	await click("返回准备")
	check(game.screen=="prepare" and not game.meta.is_in_run(),"pause returns to preparation and unlocks equipment")
	check(not game.history.any(func(s):return s in ["opening","hud","reward","chest","shop","pause","result"]),"return preparation keeps no preview history")
	game.navigate("home")
	check(game.history.is_empty(),"return home clears navigation history")
	DisplayServer.window_set_size(Vector2i(1600,900))
	await snap("09-home-1600")
	game.navigate("gem")
	await snap("10-gems-1600")
	var report={"checks":checks,"failures":failures,"captures":captures,"save_isolated":SAVE,"renderer":RenderingServer.get_video_adapter_name()}
	FileAccess.open(OUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	game.queue_free()
	await process_frame
	for suffix in ["",".tmp",".bak"]:
		if FileAccess.file_exists(SAVE+suffix): DirAccess.remove_absolute(SAVE+suffix)
	print("UI SUITE: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
