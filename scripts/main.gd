extends Node2D
const Meta=preload("res://scripts/core/meta_progression.gd")
const Suite=preload("res://scripts/ui/atelier_ui.gd")
const Catalog=preload("res://scripts/ui/grimoire_catalog.gd")
const FirstRoom=preload("res://scripts/core/first_room_run.gd")
const CourtyardRoute=preload("res://scripts/core/courtyard_route_run.gd")
const RoomView=preload("res://scripts/presentation/first_room_view.gd")
const RoomUI=preload("res://scripts/ui/first_room_ui.gd")
var meta
var ui
var screen="home"
var selected=""
var opening_spell="F01"
var route_school="fire"
var history:Array[String]=[]
var save_path="user://meta_progression_v1.json"
var load_error=""
var room_run
var room_view
var room_ui
var room_run_id=""
var room_accumulator=0.0
var room_release_gate=true
var room_result_reason=""
var room_settlement:Dictionary={}
var room_seed=-1
var room_map_trial=false
var preferences_path="user://display.cfg"
var visual_options={"view_hints":true,"damage_numbers":true,"reduced_motion":false}

func _ready():
	configure_input()
	Engine.max_fps=60
	if save_path=="user://meta_progression_v1.json": load_preferences()
	meta=Meta.new(save_path)
	var startup_notice=load_meta_state()
	var content=Catalog.load_catalog()
	if not content.ok: load_error="；".join(content.errors)
	ui=Suite.new()
	add_child(ui)
	ui.requested.connect(handle_request)
	refresh(startup_notice)

# A save from a newer build cannot be read here. Its bytes are kept, moved aside
# once, and a valid account is created instead of blocking every screen.
func load_meta_state() -> String:
	load_error=""
	var result=meta.load_state()
	if result.ok: return ""
	if not result.has("incompatible_version"):
		load_error=str(result.error)
		return ""
	var quarantine:Dictionary=meta.quarantine_incompatible_save()
	if not quarantine.ok:
		load_error=str(result.error)+str(quarantine.error)
		return ""
	var retry=meta.load_state()
	if not retry.ok:
		load_error=str(retry.error)
		return ""
	return "旧存档来自更新版本（%s），已备份为 %s，并新建了进度。" % [str(quarantine.version),str(quarantine.path).get_file()]

# The retained trial controllers use this input binding helper as well.
func configure_input():
	var bindings={"move_left":[KEY_A,KEY_LEFT],"move_right":[KEY_D,KEY_RIGHT],"move_up":[KEY_W,KEY_UP],"move_down":[KEY_S,KEY_DOWN],"pause":[KEY_ESCAPE],"fullscreen":[KEY_F11]}
	for action in bindings:
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		for key in bindings[action]:
			var event=InputEventKey.new()
			event.physical_keycode=key
			InputMap.action_add_event(action,event)
func refresh(message:String=""):
	ui.preferences=visual_options.duplicate(true)
	ui.route_school=route_school
	ui.render(screen,meta,Catalog,selected,message if load_error.is_empty() else load_error,opening_spell)
func navigate(next:String,remember:bool=true):
	if room_run!=null:
		return
	if screen=="gem" and next!=screen:
		ui.gem_tool=""
		ui.gem_salvage_ids.clear()
	if not load_error.is_empty() and next!="home" and next!="settings":
		refresh(load_error)
		return
	var entering_preview=next in Suite.PREVIEWS
	if entering_preview and not meta.is_in_run():
		var result=meta.begin_run()
		if not result.ok:
			refresh(str(result.error))
			return
	elif not entering_preview and meta.is_in_run(): meta.end_run()
	var return_to_prepare=next=="prepare" and screen in Suite.PREVIEWS
	if return_to_prepare:
		for i in range(history.size()-1,-1,-1):
			if history[i] in Suite.PREVIEWS or history[i]=="prepare": history.remove_at(i)
	if next=="home": history.clear()
	elif return_to_prepare: pass
	elif remember and next!=screen: history.append(screen)
	screen=next
	selected=""
	refresh()
func handle_request(action:String,payload:String):
	if action.begins_with("gem_"):
		if room_run!=null or screen!="gem" or not load_error.is_empty():return
		_handle_gem_request(action,payload)
		return
	match action:
		"start_room": start_first_room()
		"start_route": start_courtyard_route()
		"route_school":
			if payload in ["fire","ice","lightning","wind","earth","spirit"]:
				route_school=payload
				refresh()
		"navigate": navigate(payload)
		"back":
			if screen=="gem" and not ui.gem_tool.is_empty():
				ui.gem_tool=""
				ui.gem_salvage_ids.clear()
				refresh()
				return
			if screen=="gem" and (not ui.gem_results.is_empty() or ui.gem_show_rules):
				ui.gem_results.clear()
				ui.gem_show_rules=false
				refresh()
				return
			if not history.is_empty(): navigate(history.pop_back(),false)
			elif screen!="home": navigate("home",false)
		"select":
			selected=payload
			refresh()
		"unlock","upgrade","equip":
			var kind="catalyst" if screen=="catalyst" else "gem"
			var result:Dictionary
			if action=="unlock": result=meta.request_unlock(kind,payload)
			elif action=="upgrade": result=meta.request_upgrade(kind,payload)
			else: result=meta.request_equip(kind,payload)
			selected=payload if not payload.is_empty() else selected
			refresh("已保存" if result.ok else str(result.error))
		"choose_preview":
			opening_spell=payload
			navigate("hud")
		"artifact_detail":
			navigate("artifacts")
			selected=payload
			refresh()
		"supply_preview": refresh("每店一次免费补给；当前为界面预览，生命与金币未变更。")
		"detail_level":
			var id=selected if not selected.is_empty() else "F01"
			if is_instance_valid(ui.detail_label): ui.detail_label.text=ui.spell_text(id,int(payload))
		"rotate":
			if is_instance_valid(ui.showcase): ui.showcase.set_yaw_degrees(ui.showcase.actor.rotation_degrees.y+float(payload))
		"fullscreen": toggle_fullscreen()
		"toggle_preference":
			if visual_options.has(payload):
				visual_options[payload]=not bool(visual_options[payload])
				save_preferences()
				if is_instance_valid(room_view):room_view.set_visual_options(visual_options)
				if is_instance_valid(room_ui):room_ui.set_visual_options(visual_options)
				refresh()
		"fps":
			Engine.max_fps=120 if Engine.max_fps==60 else 60
			save_preferences()
			refresh()
		"quit": get_tree().quit()

func _handle_gem_request(action:String,payload:String):
	var result:Dictionary={"ok":true}
	var changed:bool=false
	match action:
		"gem_tab":
			if payload not in ["cores","attributes","craft"]:return
			ui.gem_tab=payload
			ui.gem_page=0
		"gem_select":
			selected=payload
			ui.gem_tab="cores" if payload.begins_with("core:") else "attributes"
		"gem_tool":ui.gem_tool=payload if payload in ["reforge","salvage","retype"] else ""
		"gem_main_stat":
			if not meta.gems.rules.affixes.has(payload):return
			ui.gem_main_stat=payload
		"gem_craft_rarity":
			if payload not in ["green","blue","purple"]:return
			ui.gem_craft_rarity=payload
		"gem_core_unlock":
			result=meta.request_unlock_core(payload)
			if result.ok:selected="core:"+payload
			changed=true
		"gem_core_equip":
			result=meta.request_equip_core(payload)
			if result.ok:selected="core:"+payload
			changed=true
		"gem_attribute_starter":
			result=meta.claim_starter_attribute(payload)
			if result.ok:
				selected=str(result.get("gem_id",result.get("gem",{}).get("id","")))
			changed=true
		"gem_craft":
			var parts=payload.split(":",true,1)
			if parts.size()!=2:return
			result=meta.request_craft_gem(parts[0],parts[1])
			if result.ok:
				selected=str(result.get("gem_id",result.get("gem",{}).get("id","")))
				ui.gem_tab="attributes"
			changed=true
		"gem_upgrade":
			result=meta.request_upgrade_gem(selected)
			changed=true
		"gem_raise":
			if not payload.is_valid_int():return
			result=meta.request_raise_gem_affix(selected,int(payload))
			changed=true
		"gem_convert":
			result=meta.request_convert_gem(selected,payload)
			changed=true
		"gem_retype_open":
			if not payload.is_valid_int() or int(payload)<=0:return
			ui.gem_line_index=int(payload)
			ui.gem_tool="retype"
		"gem_retype_stat":
			if not meta.gems.rules.affixes.has(payload):return
			ui.gem_retype_stat=payload
		"gem_retype":
			var parts=payload.split(":",true,1)
			if parts.size()!=2 or not parts[0].is_valid_int():return
			result=meta.request_retype_gem(selected,int(parts[0]),parts[1])
			if result.ok:ui.gem_tool="reforge"
			changed=true
		"gem_lock":
			result=meta.request_lock_gem(payload)
			changed=true
		"gem_batch_preview":
			ui.gem_salvage_ids.clear()
			var state:Dictionary=meta.get_state().gem_state
			for gem in state.inventory:
				if gem.rarity in ["green","blue"] and not bool(gem.locked) and gem.id not in state.slots:ui.gem_salvage_ids.append(gem.id)
			ui.gem_tool="salvage"
		"gem_single_preview":
			ui.gem_salvage_ids=[selected]
			ui.gem_tool="salvage"
		"gem_salvage_confirm":
			result=meta.request_salvage_gems(ui.gem_salvage_ids)
			if result.ok:
				selected=""
				ui.gem_tool=""
				ui.gem_salvage_ids.clear()
			changed=true
		"gem_reforge":
			if not payload.is_valid_int() or int(payload)<=0:return
			result=meta.request_reforge(selected,"affix",int(payload))
			if result.ok:ui.gem_tool=""
			changed=true
		"gem_resolve":
			var parts=payload.split(":",true,1)
			if parts.size()!=2 or not parts[0].is_valid_int() or parts[1] not in ["old","new"]:return
			result=meta.resolve_reforge(int(parts[0]),parts[1]=="new")
			if result.ok:ui.gem_tool="reforge"
			changed=true
		"gem_page":
			if not payload.is_valid_int():return
			ui.gem_page=maxi(0,int(payload))
		"gem_rules":ui.gem_show_rules=true
		"gem_rules_section":ui.gem_rules_section=payload if payload in ["draw","work"] else "draw"
		"gem_rules_close":ui.gem_show_rules=false
		"gem_results_close":
			ui.gem_results.clear()
			ui.gem_tab="attributes"
		"gem_draw":
			if not ui.gem_results.is_empty() or ui.gem_show_rules or payload not in ["1","10"]:return
			result=meta.request_draw_gems(int(payload))
			if result.ok:
				ui.gem_results=result.gems.duplicate(true)
				selected=str(result.gems[-1].id)
				ui.gem_page=0
			changed=true
		"gem_equip":
			var parts=payload.split(":",true,1)
			if parts.size()!=2 or not parts[0].is_valid_int():return
			result=meta.request_equip_gem(int(parts[0]),parts[1])
			changed=true
		_:return
	refresh(("分解完成，获得%d宝石精粹"%int(result.essence_gained)) if result.ok and result.has("essence_gained") else ("已保存" if result.ok and changed else str(result.get("error",""))))
func _unhandled_input(event):
	if event is InputEventKey and event.echo:return
	if event.is_action_pressed("fullscreen"):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		if room_run!=null:
			if room_result_reason.is_empty():
				_handle_room_request("room_resume" if room_run.paused else "room_pause","")
		else: handle_request("back","")
		get_viewport().set_input_as_handled()

func start_first_room():
	_start_room(false)

func start_courtyard_route():
	_start_room(true)

func _start_room(map_trial:bool):
	if not load_error.is_empty():
		refresh(load_error)
		return
	if room_run!=null:return
	if meta.is_in_run():
		var end_result=meta.end_run()
		if not end_result.ok:
			refresh(str(end_result.error))
			return
	var result=meta.begin_playable_run("route45" if map_trial else "legacy")
	if not result.ok:
		refresh(str(result.error))
		return
	room_map_trial=map_trial
	room_run_id=str(result.get("run_id",""))
	room_run=CourtyardRoute.new() if map_trial else FirstRoom.new()
	var actual_seed=room_seed if room_seed>=0 else int(Time.get_unix_time_from_system()*1000)+Time.get_ticks_usec()
	var run_snapshot:Dictionary=result.snapshot.duplicate(true)
	if map_trial:run_snapshot["route_school"]=route_school
	var configured=room_run.configure(run_snapshot,actual_seed)
	if not configured.ok:
		var cleanup=meta.settle_playable_run(room_run_id,[])
		room_run=null
		room_map_trial=false
		room_run_id=""
		refresh(str(configured.error) if cleanup.ok else str(cleanup.error))
		return
	room_accumulator=0
	room_release_gate=true
	room_result_reason=""
	room_settlement={}
	screen="playable"
	ui.root.hide()
	room_view=RoomView.new()
	add_child(room_view)
	room_view.position=Vector2.ZERO
	room_view.size=Vector2(1600,900)
	room_ui=RoomUI.new()
	add_child(room_ui)
	room_view.set_visual_options(visual_options)
	room_ui.set_visual_options(visual_options)
	room_ui.requested.connect(_handle_room_request)
	_refresh_room(0)

func _process(delta):
	if room_run==null or not is_instance_valid(room_view):return
	if room_result_reason.is_empty():
		var move=Input.get_vector("move_left","move_right","move_down","move_up")
		if room_release_gate:
			if move.is_zero_approx():room_release_gate=false
			move=Vector2.ZERO
		var active_phases=["combat","pickup","reward","artifact","exit","shop","shopping"] if room_map_trial else ["combat","exit"]
		if not room_run.paused and room_run.phase in active_phases:
			room_accumulator+=minf(delta,.1)
			while room_accumulator>=1.0/120:
				var before_room=int(room_run.room_revision) if room_map_trial else 0
				room_run.step(1.0/120,move if room_run.phase in ["combat","pickup","exit","shop"] else Vector2.ZERO)
				room_accumulator-=1.0/120
				if room_map_trial and int(room_run.room_revision)!=before_room:
					room_release_gate=true
					room_accumulator=0
					break
				if room_run.phase in ["complete","dead"]:break
		else:room_accumulator=0
		if room_run.phase in ["complete","dead"]:_finish_room(room_run.phase)
	_refresh_room(delta)

func _refresh_room(delta:float):
	if room_run==null:return
	var snapshot=room_run.get_snapshot()
	room_view.sync(snapshot,delta)
	room_ui.refresh(snapshot)

func _handle_room_request(action:String,payload):
	if room_run==null:return
	match action:
		"room_initial":
			if room_run.choose_initial(payload):
				room_release_gate=true
				room_accumulator=0
		"room_reward":
			if payload is Dictionary and not _room_request_integers(payload,["room_revision"]):return
			if not payload is Dictionary and not payload is String:return
			var spell_id=str(payload.get("spell_id",payload.get("id",""))) if payload is Dictionary else str(payload)
			var revision=int(payload.get("room_revision",-1)) if payload is Dictionary else -1
			var accepted=room_run.choose_reward(spell_id,revision) if room_map_trial else room_run.choose_reward(spell_id)
			if accepted:
				room_release_gate=true
				room_accumulator=0
		"room_replace":
			if room_map_trial and _room_request_integers(payload,["slot_index","request_id","room_revision"]) and room_run.confirm_spell_replacement(payload.slot_index,payload.request_id,payload.room_revision):
				room_release_gate=true
				room_accumulator=0
		"room_replace_cancel":
			if room_map_trial and _room_request_integers(payload,["request_id","room_revision"]) and room_run.cancel_spell_replacement(payload.request_id,payload.room_revision):
				room_release_gate=true
				room_accumulator=0
		"room_reward_skip":
			if room_map_trial and _room_request_integers(payload,["room_revision"]) and room_run.skip_spell_reward(payload.room_revision):
				room_release_gate=true
				room_accumulator=0
		"room_artifact":
			if room_map_trial and room_run.choose_artifact(payload):
				room_release_gate=true
				room_accumulator=0
		"room_shop_buy":
			if room_map_trial and _room_request_integers(payload,["room_revision"]) and payload.get("id") is String and room_run.buy_shop_item(payload.id,payload.room_revision):
				room_release_gate=true
				room_accumulator=0
		"room_shop_close":
			if room_map_trial and _room_request_integers(payload,["room_revision"]) and room_run.close_shop(payload.room_revision):
				room_release_gate=true
				room_accumulator=0
		"room_pause":
			if room_result_reason.is_empty():
				room_run.set_paused(true)
				room_accumulator=0
		"room_resume":
			room_run.set_paused(false)
			room_release_gate=true
			room_accumulator=0
		"room_end":_finish_room("abandon")
		"room_save_retry":_settle_room()
		"room_retry":
			if room_settlement.get("ok",false):
				var retry_map_trial=room_map_trial
				_destroy_room()
				_start_room(retry_map_trial)
		"room_return":
			if room_settlement.get("ok",false):
				_destroy_room()
				history.clear()
				navigate("prepare",false)
	_refresh_room(0)

func _room_request_integers(payload,keys:Array)->bool:
	if not payload is Dictionary:return false
	for key in keys:
		if not payload.get(key) is int:return false
	return true

func _finish_room(reason:String):
	if not room_result_reason.is_empty():return
	room_result_reason=reason
	room_run.set_paused(true)
	room_accumulator=0
	room_ui.refresh(room_run.get_snapshot())
	_settle_room()

func _settle_room():
	if room_run==null or room_settlement.get("ok",false):return
	var summary=room_run.get_summary()
	room_settlement=meta.settle_playable_run(room_run_id,summary.get("cleared_rooms",[]))
	room_ui.show_result(summary,room_settlement,room_result_reason)

func _destroy_room():
	if is_instance_valid(room_view):
		remove_child(room_view)
		room_view.queue_free()
	if is_instance_valid(room_ui):
		remove_child(room_ui)
		room_ui.queue_free()
	room_run=null
	room_view=null
	room_ui=null
	room_run_id=""
	room_map_trial=false
	room_result_reason=""
	room_settlement={}
	room_accumulator=0
	ui.root.show()

func _notification(what):
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and room_run!=null and room_result_reason.is_empty():
		if room_run.phase in (["combat","pickup","reward","artifact","exit","shop","shopping"] if room_map_trial else ["combat","exit"]):
			room_run.set_paused(true)
			room_accumulator=0
func toggle_fullscreen():
	var full=DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	save_preferences()
func load_preferences():
	var cfg=ConfigFile.new()
	if cfg.load(preferences_path)!=OK: return
	Engine.max_fps=120 if int(cfg.get_value("display","fps",60))==120 else 60
	if bool(cfg.get_value("display","fullscreen",false)): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	for key in visual_options:
		visual_options[key]=bool(cfg.get_value("visual",key,visual_options[key]))
func save_preferences():
	if save_path!="user://meta_progression_v1.json" and preferences_path=="user://display.cfg": return
	var cfg=ConfigFile.new()
	cfg.set_value("display","fps",Engine.max_fps)
	cfg.set_value("display","fullscreen",DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN)
	for key in visual_options:cfg.set_value("visual",key,visual_options[key])
	cfg.save(preferences_path)
