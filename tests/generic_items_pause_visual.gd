extends SceneTree
## Short actual Main flow for the pause attribute layout after its local fix.
const Main = preload("res://scripts/main.gd")
const OUT="res://build/qa/generic-items-implementation-20261018/pause-final/"
const SAVE="user://tests/generic_items_pause_visual.json"
const PREFS="user://tests/generic_items_pause_visual.cfg"
var checks:=0
var failures: Array=[]
var source_before: Dictionary={}
var production: Dictionary={}
var game
var captures: Array=[]

func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks+=1
	if not value:
		failures.append(label)
		push_error("Generic pause visual: "+label)
func sources() -> Dictionary:
	var result: Dictionary={}
	for path in ["res://scripts/main.gd","res://scripts/ui/first_room_ui.gd","res://scripts/ui/atelier_ui.gd","res://scripts/ui/grimoire_catalog.gd","res://scripts/core/courtyard_route_run.gd","res://scripts/core/route_artifacts.gd","res://scripts/core/route_generic_items.gd","res://data/generic_artifacts_v1.json","res://data/balance_candidates/first_run_v1.json","res://tests/generic_items_pause_visual.gd"]:
		result[path]=FileAccess.get_sha256(path)
	return result
func candidates(text: String, action: String="") -> Array:
	var parent=game.room_ui.root if is_instance_valid(game.room_ui) else game.ui.page
	return parent.find_children("*","Button",true,false).filter(func(button):return button.is_visible_in_tree() and not button.disabled and (str(button.get_meta("choice_action",""))==action if not action.is_empty() else button.text==text))
func click(text: String,action: String="") -> bool:
	var deadline: int=Time.get_ticks_msec()+1500
	while candidates(text,action).is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	var found: Array=candidates(text,action)
	check(not found.is_empty(),"actual enabled visible button "+text+action)
	if found.is_empty(): return false
	var point: Vector2=found[0].get_global_rect().get_center()*Vector2(root.size)/Vector2(1600,900)
	Input.warp_mouse(point)
	var motion:=InputEventMouseMotion.new()
	motion.position=point
	Input.parse_input_event(motion)
	await process_frame
	for down in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
		Input.parse_input_event(event)
		await process_frame
	return true
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	DirAccess.make_dir_recursive_absolute("user://tests")
	source_before=sources()
	for path in ["user://meta_progression_v1.json","user://display.cfg"]:
		production[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	for path in [SAVE,SAVE+".tmp",SAVE+".bak",PREFS]:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DisplayServer.window_set_size(Vector2i(1600,900))
	game=Main.new()
	game.save_path=SAVE
	game.preferences_path=PREFS
	game.room_seed=20261017
	root.add_child(game)
	game.set_process(false)
	root.grab_focus()
	await process_frame
	check(DisplayServer.get_name()!="headless","actual rendered Main required")
	check(game.load_error.is_empty(),"isolated actual Main loads")
	if await click("开始冒险     ›") and await click("进入60房路线    ›") and await click("initial","room_initial"):
		for tick in 120: game._process(1.0/120.0)
		if game.room_run.paused: await click("继续试炼")
		await click("暂停")
		check(game.room_run.paused,"actual UI pause freezes current real combat")
		var attributes=game.room_ui.root.find_child("PausedAttributes",true,false)
		check(attributes is Label and attributes.is_visible_in_tree(),"actual pause attribute label visible")
		if attributes is Label:
			check(attributes.get_line_count()==3,"attribute summary retains three intended lines")
			check(attributes.get_visible_line_count()==3,"all three actual text lines fit the label")
			check(attributes.text.contains("战斗移速") and attributes.text.contains("通用增伤") and attributes.text.contains("上限60%"),"third line and current60pct cap remain complete")
			check(game.room_ui.root.get_global_rect().encloses(attributes.get_global_rect()),"pause attributes stay within actual viewport")
			var continue_buttons: Array=candidates("继续试炼")
			check(not continue_buttons.is_empty() and not attributes.get_global_rect().intersects(continue_buttons[0].get_global_rect()),"all attribute rows leave clear gap before real continue button")
			var pause_descriptions: Array=game.room_ui.modal.find_children("*","Label",true,false).filter(func(label):return label.text.contains("暂停"))
			check(pause_descriptions.size()==1,"pause has one concise rendered explanation")
			for explanation in pause_descriptions:
				check(explanation.get_line_count()==1 and explanation.get_visible_line_count()==1,"pause explanation is fully visible on one line")
				check(not explanation.get_global_rect().intersects(attributes.get_global_rect()),"pause explanation does not overlap attributes")
		game._refresh_room(0.0)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		if DisplayServer.get_name()!="headless":
			check(root.get_texture().get_image().save_png(OUT+"actual-main-pause-all-three-attribute-lines.png")==OK,"save actual final pause pixels")
			captures.append("actual-main-pause-all-three-attribute-lines")
	game.queue_free()
	await process_frame
	for path in production:
		check((FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent")==production[path],"production save/preferences unchanged "+path)
	check(sources()==source_before,"final local pause source stable")
	FileAccess.open(OUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"details":failures,"captures":captures,"source_sha256":source_before,"source_stable":sources()==source_before,"scope":"Final pause layout only: actual Main UI starting choice, natural first-room step, actual pause click; no inventory, HP, actor, phase, damage or cooldown edits. Does not replace the separate full45 natural integration or imply a second full45 run after this local layout fix."},"\t"))
	for path in [SAVE,SAVE+".tmp",SAVE+".bak",PREFS]:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("GENERIC FINAL PAUSE: %d checks; %d failures" %[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
