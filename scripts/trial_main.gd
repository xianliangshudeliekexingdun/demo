extends Node2D
const Config=preload("res://scripts/core/trial_config.gd")
const Battle=preload("res://scripts/core/trial_battle.gd")
const Records=preload("res://scripts/core/trial_records.gd")
const View=preload("res://scripts/presentation/trial_view.gd")
const UI=preload("res://scripts/ui/trial_ui.gd")
var loader=Config.new()
var battle
var records
var view
var ui
var mode="menu"
var release_gate=true
var sound: AudioStreamPlayer
var event_cursor=0
func _ready():
	var input_setup=preload("res://scripts/main.gd").new()
	input_setup.configure_input()
	input_setup.free()
	view=View.new()
	add_child(view)
	ui=UI.new()
	add_child(ui)
	sound=AudioStreamPlayer.new()
	add_child(sound)
	ui.start_requested.connect(start)
	ui.pause_requested.connect(pause_trial)
	ui.resume_requested.connect(resume)
	ui.menu_requested.connect(menu)
	ui.reload_requested.connect(reload)
	ui.upgrade_chosen.connect(func(id):
		battle.choose(id)
		mode="battle"
		release_gate=true
		ui.show_battle())
	reload(-1,[])
func finish_record():
	if battle!=null and records!=null: records.finish(battle)
func start(count: int,run: bool,ids: Array):
	if loader.values.is_empty(): return
	finish_record()
	battle=Battle.new(loader.values,count,run)
	battle.set_owned(ids)
	records=Records.new(loader.values)
	view.trial=battle
	mode="battle"
	release_gate=true
	event_cursor=0
	ui.show_battle()
	ui.refresh_trial(battle)
func menu():
	finish_record()
	battle=null
	view.trial=null
	mode="menu"
	ui.show_trial_menu(loader.error)
	view.queue_redraw()
func reload(count: int,ids: Array):
	if mode=="battle" or (battle!=null and battle.short_run and mode!="menu"): return
	if loader.load_table():
		ui.cfg=loader.values
		if count>=0: start(count,false,ids)
		else: menu()
	else:
		ui.cfg=loader.values
		menu()
func pause_trial():
	if mode!="battle": return
	battle.pause()
	mode="pause"
	ui.show_trial_pause(battle)
	release_gate=true
func resume():
	if battle==null:
		menu()
		return
	battle.paused=false
	mode="battle"
	release_gate=true
	ui.show_battle()
func _notification(what):
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and mode=="battle": pause_trial()
func aim_point() -> Vector2:
	return ground_from_local(view.get_local_mouse_position())
static func ground_from_local(point: Vector2) -> Vector2:
	return Vector2((point.x-640)/64.0,(360-point.y)/64.0)
func pointer_valid() -> bool:
	var p=view.get_local_mouse_position()
	return Rect2(0,150,1280,510).has_point(p)
func _input(event):
	if mode=="battle" and not release_gate and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		battle.queue("release" if pointer_valid() else "cancel")
func _unhandled_input(event):
	if event.is_action_pressed("fullscreen"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event.is_action_pressed("pause"):
		if mode=="battle": pause_trial()
		elif mode=="pause": resume()
	elif mode=="battle" and not release_gate and pointer_valid() and event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_LEFT: battle.queue("press")
		elif event.button_index==MOUSE_BUTTON_RIGHT: battle.queue("dodge")
func tone(frequency: float):
	var data=PackedByteArray()
	var samples=6000
	data.resize(samples*2)
	for i in range(samples):
		var sample=int(sin(TAU*frequency*i/24000.0)*(1-float(i)/samples)*9000)
		data.encode_s16(i*2,sample)
	var stream=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=24000
	stream.data=data
	sound.stream=stream
	sound.play()
func _process(dt):
	if mode!="battle": return
	var direction=Input.get_vector("move_left","move_right","move_down","move_up")
	if release_gate:
		if direction.is_zero_approx() and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT): release_gate=false
		direction=Vector2.ZERO
	battle.advance(dt,direction,aim_point())
	while event_cursor<battle.events.size():
		var kind=battle.events[event_cursor].kind
		event_cursor+=1
		if kind=="ready": tone(660)
		elif kind=="molten_ready": tone(990)
		elif kind=="resumed":
			tone(880)
			ui.notify("接续成功")
		elif kind=="mana_low": ui.notify("法力不足")
	records.flush(battle)
	ui.refresh_trial(battle)
	view.queue_redraw()
	if battle.result=="choice":
		mode="choice"
		ui.show_choices(battle)
	elif battle.result in ["success","failure","config_error"]:
		mode="result"
		finish_record()
		ui.show_trial_result(battle)
func _exit_tree(): finish_record()
