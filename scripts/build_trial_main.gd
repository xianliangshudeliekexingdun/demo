extends "res://scripts/trial_main.gd"
const BuildConfig=preload("res://scripts/core/build_config.gd")
const BuildBattle=preload("res://scripts/core/build_battle.gd")
const BuildRecords=preload("res://scripts/core/build_records.gd")
const BuildView=preload("res://scripts/presentation/build_view.gd")
const BuildUI=preload("res://scripts/ui/build_ui.gd")
const Catalog=preload("res://scripts/core/spell_catalog.gd")
var build_loader=BuildConfig.new()
var setup_count=3
var setup_multiplier=1.5
var setup_slots: Array=Catalog.IDS.duplicate()
var record_warned=false
var setup_owned: Array=[]
var setup_run=false
var setup_preset="none"
func _ready():
	var input_setup=preload("res://scripts/main.gd").new()
	input_setup.configure_input()
	input_setup.free()
	view=BuildView.new()
	add_child(view)
	ui=BuildUI.new()
	add_child(ui)
	sound=AudioStreamPlayer.new()
	add_child(sound)
	ui.start_requested.connect(func(count,multiplier,slots): start_build(count,multiplier,slots,ui.setup_owned,false,ui.preset_name))
	ui.flow_requested.connect(func(slots): start_build(0,1.5,slots,[],true,"growth"))
	ui.retry_requested.connect(func(): start_build(setup_count,setup_multiplier,setup_slots,setup_owned,setup_run,setup_preset))
	ui.upgrade_chosen.connect(func(id):
		battle.choose(id)
		if battle.result=="playing":
			mode="battle"
			release_gate=true
			ui.show_battle())
	ui.reload_requested.connect(reload_build)
	ui.pause_requested.connect(pause_trial)
	ui.resume_requested.connect(resume)
	ui.menu_requested.connect(menu)
	build_loader.load_all()
	ui.cfg=build_loader.values
	if not build_loader.layout.is_empty():
		setup_count=int(build_loader.layout.free_default_count)
		setup_multiplier=build_loader.layout.free_default_health_multiplier
	menu()
func start_build(count: int,multiplier: float,slots: Array,ids: Array=[],run: bool=false,preset: String="none"):
	if build_loader.values.is_empty() or not Catalog.valid_upgrades(ids) or not Catalog.valid_loadout(slots) or count<0 or count>6 or not is_finite(multiplier) or multiplier<.1 or multiplier>10:
		ui.notify("配置无效，无法开始")
		return
	finish_record()
	setup_count=count
	setup_multiplier=multiplier
	setup_slots=slots.duplicate()
	setup_owned=[] if run else ids.duplicate()
	setup_run=run
	setup_preset=preset
	battle=BuildBattle.new(build_loader.values,count,slots,build_loader.layout,multiplier,setup_owned,run)
	records=BuildRecords.new(build_loader.values,{"phase":"B","hash":build_loader.config_hash,"seed":build_loader.values["build.seed"],"slots":slots,"count":count,"health_multiplier":multiplier,"layout":build_loader.layout,"upgrades":setup_owned,"preset":setup_preset,"short_run":run})
	record_warned=false
	view.trial=battle
	mode="battle"
	release_gate=true
	event_cursor=0
	ui.show_battle()
	ui.refresh_build(battle)
func menu():
	finish_record()
	battle=null
	view.trial=null
	mode="menu"
	ui.cfg=build_loader.values
	ui.presets=build_loader.presets
	ui.wave_count=build_loader.layout.waves.size() if not build_loader.layout.is_empty() else 0
	ui.setup_owned=setup_owned.duplicate()
	ui.preset_name=setup_preset if not setup_run else "none"
	ui.show_setup(setup_count,setup_multiplier,setup_slots,false,build_loader.error)
	view.queue_redraw()
func reload_build(count: int,multiplier: float,slots: Array):
	if mode=="battle" or (battle!=null and battle.short_run and mode!="menu"): return
	if build_loader.load_all():
		ui.cfg=build_loader.values
		start_build(count,multiplier,slots,ui.setup_owned,false,ui.preset_name)
	else:
		ui.cfg=build_loader.values
		ui.show_setup(count,multiplier,slots,battle!=null,build_loader.error)
func pause_trial():
	if mode!="battle": return
	battle.pause()
	mode="pause"
	release_gate=true
	if battle.short_run: ui.show_flow_pause(battle)
	else:
		ui.setup_owned=battle.owned.duplicate()
		ui.preset_name=setup_preset
		ui.show_setup(battle.enemy_count,battle.health_multiplier,battle.slots,true)
func _input(event):
	if mode=="battle" and not release_gate and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		battle.command("release" if pointer_valid() else "cancel")
func _unhandled_input(event):
	if event.is_action_pressed("fullscreen"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event.is_action_pressed("pause"):
		if mode=="battle": pause_trial()
		elif mode=="pause": resume()
	elif mode=="battle" and not release_gate:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode>=KEY_1 and event.keycode<=KEY_5:
			battle.command("slot",event.keycode-KEY_1)
		elif event is InputEventMouseButton and event.pressed and pointer_valid():
			match event.button_index:
				MOUSE_BUTTON_LEFT: battle.command("press")
				MOUSE_BUTTON_RIGHT: battle.command("dodge")
				MOUSE_BUTTON_WHEEL_UP: battle.command("wheel",-1)
				MOUSE_BUTTON_WHEEL_DOWN: battle.command("wheel",1)
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
		elif kind in ["chant_started","selected"]: ui.clear_notice()
		elif kind=="resumed":
			tone(880)
			ui.notify("接续成功")
		elif kind=="mana_low": ui.notify("法力不足：当前 %.1f / 需要 %.0f" % [battle.player.mana,battle.stats().cost])
		elif kind=="cooldown_blocked": ui.notify("%s冷却中 · 剩余 %.1f秒" % [Catalog.TITLES[battle.events[event_cursor-1].data.spell],battle.events[event_cursor-1].data.remaining])
	records.flush(battle)
	if not records.error.is_empty() and not record_warned:
		ui.notify(records.error)
		record_warned=true
	ui.refresh_build(battle)
	view.queue_redraw()
	if battle.result=="choice":
		mode="choice"
		release_gate=true
		ui.show_build_choices(battle)
	elif battle.result in ["failure","success","config_error"]:
		mode="result"
		finish_record()
		ui.show_build_result(battle)
