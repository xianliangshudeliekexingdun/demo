extends SceneTree
## Isolated integration coverage for display-only options. No rendered window is
## needed; production preferences, progression, and combat clocks stay untouched.
const Main=preload("res://scripts/main.gd")
const ROOT="user://tests/visual_preferences/"
const PREF=ROOT+"display.cfg"
const LEGACY=ROOT+"legacy.cfg"
const PARTIAL=ROOT+"partial.cfg"
const KEYS=["view_hints","damage_numbers","reduced_motion"]
const TOOLTIPS={
	"view_hints":"操作与流程提示：点击切换",
	"damage_numbers":"伤害数字：点击切换",
	"reduced_motion":"减少动态效果：点击切换",
}
var checks=0
var failures=0
var games:Array=[]

func _initialize():call_deferred("run")
func check(ok:bool,message:String):
	checks+=1
	if not ok:
		failures+=1
		push_error("Visual preferences: "+message)
func fingerprint(path:String)->String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
func fresh(name:String,preferences:String=PREF):
	var game=Main.new()
	game.save_path=ROOT+name+".json"
	game.preferences_path=preferences
	root.add_child(game)
	game.set_process(false)
	games.append(game)
	check(game.load_error.is_empty(),name+" loads isolated progression")
	return game
func preference_button(game,key:String):
	for button in game.ui.page.find_children("*","Button",true,false):
		if button.tooltip_text==TOOLTIPS[key]:return button
	return null
func config_matches(options:Dictionary)->bool:
	var cfg=ConfigFile.new()
	if cfg.load(PREF)!=OK:return false
	for key in KEYS:
		if cfg.get_value("visual",key,null)!=options[key]:return false
	return true
func clean_files():
	# These are named fixtures; cleanup never traverses the user's save directory.
	for name in ["display.cfg","legacy.cfg","partial.cfg","primary.json","reopened.json","legacy.json","partial.json","missing.json"]:
		for suffix in ["",".tmp",".bak"]:
			var path=ROOT+name+suffix
			if FileAccess.file_exists(path):DirAccess.remove_absolute(path)

func run():
	var original_fps=Engine.max_fps
	var production_preferences=fingerprint("user://display.cfg")
	var production_progress=fingerprint("user://meta_progression_v1.json")
	DirAccess.make_dir_recursive_absolute(ROOT)
	clean_files()
	var game=fresh("primary")
	var defaults=game.visual_options.duplicate(true)
	check(defaults=={"view_hints":true,"damage_numbers":true,"reduced_motion":false},"new controller has documented display defaults")
	game.load_preferences()
	check(game.visual_options==defaults and not FileAccess.file_exists(PREF),"missing preference file preserves defaults without writing")
	game.navigate("settings")
	var ledger=game.meta.get_state()
	var ledger_file=fingerprint(game.save_path)
	for key in KEYS:
		var before=game.visual_options.duplicate(true)
		var button=preference_button(game,key)
		check(button!=null,"actual settings button found by meaning: "+key)
		if button==null:continue
		button.pressed.emit()
		await process_frame
		check(game.visual_options[key]==not before[key],"settings button toggles "+key)
		for other in KEYS:
			if other!=key:check(game.visual_options[other]==before[other],key+" leaves "+other+" unchanged")
		check(game.ui.preferences==game.visual_options,"menu receives current "+key)
		check(config_matches(game.visual_options),"all display fields persist together after "+key)
		check(game.meta.get_state()==ledger and fingerprint(game.save_path)==ledger_file,"display setting does not write progression: "+key)
	var stored=game.visual_options.duplicate(true)
	var preferences_hash=fingerprint(PREF)
	game.handle_request("toggle_preference","unknown_setting")
	check(game.visual_options==stored and fingerprint(PREF)==preferences_hash,"unknown preference is ignored without rewriting disk")
	var reopened=fresh("reopened")
	reopened.load_preferences()
	reopened.refresh()
	check(reopened.visual_options==stored,"new controller reloads all three persisted options")
	check(reopened.ui.preferences==stored,"reloaded settings reach menu UI")
	check(reopened.meta.get_state()==ledger,"display reload leaves isolated progression at initial state")

	# Changing presentation options inside a frozen real run must not advance a
	# clock, alter an offer, reroll a seed, or touch the account/run snapshot.
	game.room_seed=719
	game.start_first_room()
	check(game.room_run!=null and game.room_view!=null and game.room_ui!=null,"real first-room view and UI instantiated")
	if game.room_run!=null:
		check(game.room_run.choose_initial("F01"),"real run can choose its initial spell")
		for tick in range(30):game.room_run.step(1.0/120.0,Vector2.ZERO)
		game._refresh_room(0)
		var core_snapshot=game.room_run.get_snapshot()
		var run_snapshot=game.meta.get_run_snapshot()
		var active_ledger=game.meta.get_state()
		var active_file=fingerprint(game.save_path)
		for key in KEYS:
			game.handle_request("toggle_preference",key)
			game._refresh_room(0)
			await process_frame
			check(game.room_ui.preferences==game.visual_options,"running HUD receives "+key)
			check(game.room_view._visual_options.damage_numbers==game.visual_options.damage_numbers and game.room_view._visual_options.reduced_motion==game.visual_options.reduced_motion,"running room view receives render settings after "+key)
			check(game.room_run.get_snapshot()==core_snapshot,"toggle preserves entire combat state and pending choices: "+key)
			check(game.meta.get_run_snapshot()==run_snapshot and game.meta.get_state()==active_ledger and fingerprint(game.save_path)==active_file,"toggle preserves run equipment and progression file: "+key)
			check(game.room_ui.detail.visible==game.visual_options.view_hints,"context hint visibility follows setting after "+key)
			for hint in game.room_ui.hint_nodes:check(hint.visible==game.visual_options.view_hints,"movement hint visibility follows setting after "+key)
		game.handle_request("toggle_preference","reduced_motion")
		if not game.visual_options.reduced_motion:game.handle_request("toggle_preference","reduced_motion")
		game._refresh_room(0)
		check(not game.room_view._blue_flames.is_empty(),"room contains actual ambient flame nodes")
		for flame in game.room_view._blue_flames:check(is_equal_approx(flame.scale.y,1.0),"reduced motion freezes actual flame breathing")
		check(is_zero_approx(float(game.room_view._portal_material.get_shader_parameter("core_time"))),"reduced motion freezes portal visual clock")
		game.handle_request("toggle_preference","reduced_motion")
		game._refresh_room(0)
		check(is_equal_approx(float(game.room_view._portal_material.get_shader_parameter("core_time")),float(core_snapshot.time)),"reenabling ambient effects resumes visual clock at unchanged simulation time")
		check(game.room_run.get_snapshot()==core_snapshot and game.meta.get_state()==active_ledger,"ambient option probes leave rules and account unchanged")
		game._destroy_room()

	var legacy_cfg=ConfigFile.new()
	legacy_cfg.set_value("display","fps",120)
	legacy_cfg.set_value("display","fullscreen",false)
	check(legacy_cfg.save(LEGACY)==OK,"create old display-only preference fixture")
	var old=fresh("legacy",LEGACY)
	var legacy_defaults=old.visual_options.duplicate(true)
	old.load_preferences()
	old.refresh()
	check(Engine.max_fps==120,"legacy frame cap remains functional")
	check(old.visual_options==legacy_defaults and old.ui.preferences==legacy_defaults,"legacy file without visual section keeps all three defaults")
	old.save_preferences()
	var migrated=ConfigFile.new()
	check(migrated.load(LEGACY)==OK,"legacy preference file remains readable after save")
	for key in KEYS:check(migrated.get_value("visual",key,null)==legacy_defaults[key],"legacy save adds missing field: "+key)
	var partial_cfg=ConfigFile.new()
	partial_cfg.set_value("display","fps",33)
	partial_cfg.set_value("visual","view_hints",false)
	partial_cfg.set_value("visual","unrecognized",true)
	check(partial_cfg.save(PARTIAL)==OK,"create partial preference fixture")
	var partial=fresh("partial",PARTIAL)
	partial.load_preferences()
	check(partial.visual_options=={"view_hints":false,"damage_numbers":true,"reduced_motion":false},"partial visual section keeps defaults for missing fields and ignores unknown fields")
	check(Engine.max_fps==60,"unsupported old frame cap normalizes to supported cap")
	for instance in games:instance.queue_free()
	await process_frame
	clean_files()
	Engine.max_fps=original_fps
	check(fingerprint("user://display.cfg")==production_preferences,"production display preferences remain byte-identical")
	check(fingerprint("user://meta_progression_v1.json")==production_progress,"production progression remains byte-identical")
	print("VISUAL PREFERENCES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
