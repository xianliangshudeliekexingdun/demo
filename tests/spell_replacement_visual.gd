extends SceneTree
## Genuine Main/UI/WASD test. No HP, actor, phase, position or snapshot mutations.

const Main = preload("res://scripts/main.gd")
const MovementPolicy = preload("res://tests/route_rebalance_tests.gd")
const SourceBinding = preload("res://tests/formal_ice_source_binding.gd")
const OUT = "res://build/qa/spell-replacement-20261018/visual/"
const SAVE = "user://tests/spell_replacement_visual.json"
const PREFS = "user://tests/spell_replacement_visual_display.cfg"
const LOGICAL = Vector2(1600, 900)
const SPELL_PREFERENCE = ["I07", "I10", "F06", "I05", "I08", "I09", "I01", "I02", "I03", "I04", "I06", "F01", "F02", "F03", "F05", "F07", "F08", "F09", "F10", "F11"]
var game
var checks: int = 0
var failures: Array = []
var captures: Array = []
var samples: Array = []
var rooms: Array = []
var transitions: Array = []
var focus_events: Array = []
var production_before: Dictionary = {}
var account_before: Dictionary = {}
var save_bytes_before: String = ""
var final_summary: Dictionary = {}
var observed_types: Dictionary = {}
var observed_spells: Dictionary = {}
var observed_dangers: Dictionary = {}
var observed_projectiles: int = 0
var max_actor_error: float = 0.0
var max_projection_error: float = 0.0
var over_cap_samples: int = 0
var projection_samples: int = 0
var premature_clear_samples: int = 0
var manual_steps: int = 0
var _pressed: Dictionary = {}
var _shot: Dictionary = {}
var _seed: int = 20261017
var _pilot = MovementPolicy.new()
var hover_records: Array = []
var pickup_records: Array = []
var initial_source_hashes: Dictionary = {}
var replacement_records: Array = []
var _replacement_exercised: bool = false
var _skip_exercised: bool = false
var new_ice_acquired: Array = []
var new_ice_combat_rooms: Array = []
var resource_telemetry: Dictionary = {"shield_loss":0.0,"health_loss":0.0,"combat_shield_restore":0.0,"item_health_restore":0.0,"charge_release":0.0,"events_by_item":{},"ice_events":{},"burn_damage":0.0,"detonation_damage":0.0}
var _last_telemetry_seq: int = 0


func _initialize():
	_pilot.direction_count = 8
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with("--seed="):
			_seed = int(str(argument).trim_prefix("--seed="))
	call_deferred("run")


func check(value: bool, label: String):
	checks += 1
	if not value:
		failures.append(label)
		push_error("Spell replacement visual: " + label)


func buttons() -> Array:
	if is_instance_valid(game.room_ui):
		return game.room_ui.root.find_children("*", "Button", true, false)
	return game.ui.page.find_children("*", "Button", true, false)


func choice_action(text: String) -> String:
	return {"选择法术": "room_initial", "领取奖励": "room_reward", "领取宝物": "room_artifact"}.get(text, "")


func matches_button(button: Button, text: String) -> bool:
	var action: String = choice_action(text)
	return str(button.get_meta("choice_action", "")) == action if not action.is_empty() else button.text == text


func wait_choice_reveal(text: String):
	if choice_action(text).is_empty(): return
	var deadline: int = Time.get_ticks_msec() + 900
	while visible_choices(text).is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame


func click(text: String, index: int = 0) -> bool:
	await wait_choice_reveal(text)
	var matches: Array = []
	for button in buttons():
		if matches_button(button, text) and button.is_visible_in_tree() and not button.disabled:
			matches.append(button)
	check(matches.size() > index, "actual visible button " + text)
	if matches.size() <= index:
		return false
	var point: Vector2 = matches[index].get_global_rect().get_center() * Vector2(root.size) / LOGICAL
	await mouse_to(point)
	for down in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	return true


func mouse_to(point: Vector2):
	Input.warp_mouse(point)
	var event = InputEventMouseMotion.new()
	event.position = point
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func visible_choices(text: String) -> Array:
	return buttons().filter(func(button): return matches_button(button, text) and button.is_visible_in_tree() and not button.disabled)


func choice_style(button: Button) -> Dictionary:
	var style: StyleBox = button.get_parent().get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		return {"border": style.border_color, "background": style.bg_color, "width": style.border_width_left}
	return {}


func hover_exercise(text: String, label: String):
	await wait_choice_reveal(text)
	var choices: Array = visible_choices(text)
	check(choices.size() > 0, "actual choice buttons for hover exercise")
	for button in choices:
		check(not button.has_focus(), "choice modal does not automatically focus a first card")
	await mouse_to(Vector2(800,112)*Vector2(root.size)/LOGICAL)
	var neutral: Array = []
	for button in choices:
		check(not button.is_hovered() and not button.has_focus(), "mouse outside whole reward cards leaves all cards neutral")
		neutral.append(choice_style(button))
	await snap(label+"-neutral")
	if choices.is_empty(): return
	var target: int = mini(1,choices.size()-1)
	var card: Control = choices[target].get_parent()
	await mouse_to((card.get_global_rect().position+Vector2(card.size.x*0.5,card.size.y*0.45))*Vector2(root.size)/LOGICAL)
	for index in choices.size():
		check(choices[index].is_hovered() == (index == target), "whole card body is the exact reward hit area")
	check(choice_style(choices[target]) != neutral[target], "card body hover changes its actual card style")
	await snap(label+"-card-body-hover")
	await mouse_to(choices[target].get_global_rect().get_center()*Vector2(root.size)/LOGICAL)
	for index in choices.size():
		check(choices[index].is_hovered() == (index == target), "only button under real mouse becomes hovered")
	check(choice_style(choices[target]) != neutral[target], "button hover changes its actual card style")
	await snap(label+"-button-hover")
	await mouse_to(Vector2(800,112)*Vector2(root.size)/LOGICAL)
	for index in choices.size():
		check(not choices[index].is_hovered() and not choices[index].has_focus() and choice_style(choices[index]) == neutral[index], "leaving whole card removes highlight and focus")
	await snap(label+"-mouse-away")
	hover_records.append({"label": label, "choices": choices.size(), "target": target, "neutral_styles": neutral})


func without_elapsed(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	result.erase("time")
	result.erase("room_time")
	return result


func key(code: int, down: bool):
	_pressed[code] = down
	var event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	await process_frame


func direction_keys(direction: Vector2):
	var desired: Dictionary = {KEY_A: direction.x < -0.2, KEY_D: direction.x > 0.2, KEY_W: direction.y > 0.2, KEY_S: direction.y < -0.2}
	for code in desired:
		if bool(_pressed.get(code, false)) != bool(desired[code]):
			await key(code, bool(desired[code]))


func release_movement():
	await direction_keys(Vector2.ZERO)
	if game.room_run != null:
		game._process(0.0)


func resume_focus(label: String):
	if game.room_run == null or not game.room_run.paused or not game.room_result_reason.is_empty():
		return
	focus_events.append({"label": label, "room": game.room_run.room_index, "phase": game.room_run.phase, "time": game.room_run.time})
	await click("继续试炼")
	await release_movement()


func step():
	game._process(1.0 / 120.0)
	manual_steps += 1
	if game.room_run != null and is_instance_valid(game.room_view):
		var battle = game.room_run
		for effect in battle.effects:
			if int(effect.get("seq",0)) <= _last_telemetry_seq: continue
			if effect.kind == "hurt":
				resource_telemetry.shield_loss += float(effect.get("shield_damage",0.0))
				resource_telemetry.health_loss += float(effect.get("health_damage",0.0))
			elif effect.kind in ["shield_restore","item_shield_restore"]:
				resource_telemetry.combat_shield_restore += float(effect.get("amount",0.0))
			elif effect.kind == "item_health_restore":
				resource_telemetry.item_health_restore += float(effect.get("amount",0.0))
			elif effect.kind == "item_charge_release":
				resource_telemetry.charge_release += float(effect.get("amount",0.0))
			if str(effect.kind).begins_with("ice_"):
				resource_telemetry.ice_events[str(effect.kind)] = int(resource_telemetry.ice_events.get(str(effect.kind), 0)) + 1
			if effect.kind == "damage" and str(effect.get("spell_id", "")) in ["burning", "detonation"]:
				resource_telemetry["burn_damage" if effect.spell_id == "burning" else "detonation_damage"] += float(effect.get("amount", 0.0))
			var item_id: String = str(effect.get("artifact_id",""))
			if not item_id.is_empty():
				resource_telemetry.events_by_item[item_id] = int(resource_telemetry.events_by_item.get(item_id,0))+1
		_last_telemetry_seq = battle.event_seq
		var pos: Vector2 = battle.player.pos
		max_actor_error = maxf(max_actor_error, game.room_view.actor.position.distance_to(Vector3(pos.x, 0.0, -pos.y)))
		for height in [0.0, 1.45]:
			var projected: Vector2 = game.room_view.camera.unproject_position(Vector3(pos.x, height, -pos.y)) * game.room_view.size / LOGICAL
			max_projection_error = maxf(max_projection_error, projected.distance_to(game.room_view.screen_position(pos, height)))
		projection_samples += 1
		var alive: int = 0
		for actor in battle.actors:
			if actor.health > 0.0:
				alive += 1
				observed_types[str(actor.get("type_id", actor.get("type", "")))] = true
				var danger: Dictionary = actor.get("danger", {})
				if not danger.is_empty():
					observed_dangers[str(danger.get("kind", ""))] = true
		if alive > int(battle.get_snapshot().get("alive_cap", 0)):
			over_cap_samples += 1
		if battle.phase in ["pickup", "reward", "artifact", "exit", "complete"] and battle._spawned_total != battle._spawn_total:
			premature_clear_samples += 1
		for spell in battle.spells:
			observed_spells[str(spell.id)] = true
		observed_projectiles = maxi(observed_projectiles, battle.get_snapshot().get("enemy_projectiles", []).size())
	if manual_steps % 120 == 0:
		await process_frame


func tick(seconds: float):
	for _index in roundi(seconds * 120.0):
		await step()
	await process_frame


func snap(label: String):
	game._refresh_room(0.0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.size == Vector2i(1600, 900), "native capture resolution " + label)
	if DisplayServer.get_name() != "headless":
		var image: Image = root.get_texture().get_image()
		check(image.get_size() == Vector2i(1600, 900) and image.save_png(OUT + label + ".png") == OK, "save genuine Main pixels " + label)
		captures.append(label)
	var snapshot: Dictionary = game.room_run.get_snapshot()
	var band: Dictionary = snapshot.get("difficulty_band", {})
	check(not band.is_empty() and game.room_ui.room_index_label.text.contains(str(band.get("name",""))), "natural HUD displays actual difficulty band: "+label)
	for text_node in game.room_ui.root.find_children("*", "Label", true, false):
		if text_node.is_visible_in_tree():
			check(not text_node.text.contains("神器"), "visible route text uses treasure terminology: "+label)
	for text_node in game.room_view.find_children("*", "Label3D", true, false):
		if text_node.visible:
			check(not text_node.text.contains("神器"), "visible courtyard text uses treasure terminology: "+label)
	for index in game.room_ui.slots.size():
		var socket: TextureRect = game.room_ui.slots[index].get_node("SpellSlotBackground")
		check(socket.texture.resource_path == "res://assets/ui/frames_v1/spell_slot.tres", "natural HUD retains generated spell-slot material: "+label)
		if index < snapshot.spells.size():
			check(game.room_ui.slot_icons[index].spell_id == str(snapshot.spells[index].id), "natural slot icon follows actual carried spell: "+label)
	for action in ["选择法术","领取奖励","领取宝物"]:
		for button in visible_choices(action):
			var card = button.get_parent()
			check(card.face_background.texture.resource_path == "res://assets/ui/frames_v1/reward_card_front.tres" and card.back_background.texture.resource_path == "res://assets/ui/frames_v1/reward_card_back.tres", "natural offered card binds approved generated front/back: "+label)
			var offered: Array = snapshot.artifact_choices if action=="领取宝物" else (snapshot.reward_choices if action=="领取奖励" else game.room_run.initial_choices())
			check(offered.any(func(item): return str(item.id)==str(button.get_meta("choice_id",""))), "rendered card ID is genuinely offered: "+label)
	var route_nodes: Array = game.room_ui.route_progress.steps
	var current_nodes: Array = route_nodes.filter(func(node): return node.get_meta("state", "") == "current")
	check(route_nodes.size() == 3 and current_nodes.size() == (0 if snapshot.phase == "complete" else 1), "real authored room route has three nodes and correct current count: " + label)
	if not current_nodes.is_empty():
		check(int(current_nodes[0].get_meta("room_id", -1)) == int(snapshot.room_index) and str(current_nodes[0].get_meta("room_kind", "")) == str(snapshot.encounter_kind), "real route node matches current room and encounter kind: " + label)
	samples.append({"label": label, "room": snapshot.room_index, "phase": snapshot.phase, "health": snapshot.player.health, "time": snapshot.time, "combat_time": snapshot.get("combat_time", 0.0), "room_time": snapshot.get("room_time", 0.0), "reward_pickup": snapshot.get("reward_pickup", {}), "player": snapshot.player.pos, "spells": snapshot.spells, "artifacts": snapshot.get("artifacts", []), "types": observed_types.keys(), "projectiles": snapshot.get("enemy_projectiles", []).size(), "vfx":game.room_view.get_vfx_debug_state()})


func visible_world(point: Vector2) -> bool:
	return Rect2(105, 165, 1390, 560).has_point(game.room_view.screen_position(point, 0.6))


func capture_observed_combat():
	var battle = game.room_run
	var room: int = battle.room_index
	var snapshot: Dictionary = battle.get_snapshot()
	if not snapshot.get("ice_states", []).is_empty() and not _shot.has("natural_ice"):
		_shot.natural_ice = true
		await snap("09-natural-frost-state")
	for event_kind in ["ice_window", "ice_shatter", "ice_thawed"]:
		if not _shot.has(event_kind) and battle.effects.any(func(effect): return str(effect.kind) == event_kind):
			_shot[event_kind] = true
			await snap("natural-" + event_kind)
	if not _shot.has("north_spawn"):
		for warning in battle.spawn_warnings:
			if visible_world(warning.pos):
				_shot.north_spawn = true
				await snap("01-north-portal-spawn-warning")
				break
	for actor in battle.actors:
		if actor.health <= 0.0 or not visible_world(actor.pos):
			continue
		var type_id: String = str(actor.get("type_id", ""))
		var danger: Dictionary = actor.get("danger", {})
		if room in [5, 9, 14] and actor.get("elite", false) and not _shot.has("normal_elite"):
			_shot.normal_elite = true
			await snap("03-ordinary-room-%02d-mixed-elite" % room)
		if type_id == "M03" and not danger.is_empty() and not _shot.has("charge"):
			_shot.charge = true
			await snap("02-rockbeast-charge-warning")
		if type_id == "M04" and not danger.is_empty() and not _shot.has("mark"):
			_shot.mark = true
			await snap("04-warlock-mark-warning")
		if type_id.begins_with("EL02") and not danger.is_empty() and not _shot.has("fan_warning"):
			_shot.fan_warning = true
			await snap("05-elite-flower-fan-warning")
	if room >= 16:
		var label: String = "ranged-middle" if room<=30 else "ranged-later"
		var shots: Array = snapshot.get("enemy_projectiles", [])
		if shots.size() >= 3 and not _shot.has(label):
			for projectile in shots:
				if visible_world(projectile.pos):
					_shot[label] = true
					await snap("room-%02d-natural-%s-enemy-projectiles" % [room,label])
					break
	if room in [16,21,30,31,39,44,45] and not _shot.has("pressure-"+str(room)):
		var alive: int = battle.actors.filter(func(actor): return actor.health > 0.0).size()
		if alive >= 4 and snapshot.get("enemy_projectiles", []).size() >= 3:
			for projectile in snapshot.get("enemy_projectiles", []):
				if visible_world(projectile.pos):
					_shot["pressure-"+str(room)] = true
					await snap("room-%02d-natural-ranged-pressure-combat" % room)
					break
	var elite_projectiles: Array = snapshot.get("enemy_projectiles", []).filter(func(projectile): return str(projectile.get("type_id", "")).begins_with("EL02"))
	if elite_projectiles.size() >= 3 and not _shot.has("fan_projectiles"):
		for projectile in elite_projectiles:
			var source_separation: float = 0.0
			var source_radius: float = INF
			for actor in battle.actors:
				if actor.id == projectile.source_id:
					source_separation = actor.pos.distance_to(projectile.pos)
					source_radius = float(actor.radius)
			# Wait for real flight to separate the fan into distinguishable pixels.
			if visible_world(projectile.pos) and source_separation >= source_radius * 2.5:
				_shot.fan_projectiles = true
				await snap("06-elite-flower-live-projectiles")
				break
	if not snapshot.get("ice_zones", []).is_empty() and not _shot.has("ice_zones"):
		_shot.ice_zones = true
		await snap("07-natural-ice-domain-or-storm")


func bot_direction() -> Vector2:
	return _pilot.autoplay_direction(game.room_run)


func ui_button(node_name: String) -> Button:
	for button in buttons():
		if str(button.name)==node_name and button.is_visible_in_tree():return button
	return null

func press_button(node_name: String)->bool:
	var button: Button=ui_button(node_name)
	check(button!=null and not button.disabled,"actual usable button "+node_name)
	if button==null or button.disabled:return false
	var point: Vector2=button.get_global_rect().get_center()*Vector2(root.size)/LOGICAL
	await mouse_to(point)
	for pressed in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		Input.parse_input_event(event)
		await process_frame
	return true

func tap(code: int, shift: bool=false):
	for pressed in [true,false]:
		var event=InputEventKey.new()
		event.keycode=code
		event.physical_keycode=code
		event.pressed=pressed
		event.shift_pressed=shift
		Input.parse_input_event(event)
		await process_frame

func worst_slot()->int:
	var worst: int=0
	var rank: int=-1
	for index in game.room_run.spells.size():
		var candidate: int=SPELL_PREFERENCE.find(str(game.room_run.spells[index].id))
		if candidate>rank:rank=candidate;worst=index
	return worst

func malformed_requests():
	var b=game.room_run
	var before: Dictionary=b.get_snapshot()
	var pending: Dictionary=b.pending_replacement
	var token: int=int(pending.request_id)
	var rev: int=b.room_revision
	for payload in [null,[],"0",{}, {"slot_index":0,"request_id":token},{"slot_index":0.0,"request_id":token,"room_revision":rev},{"slot_index":0,"request_id":float(token),"room_revision":rev},{"slot_index":0,"request_id":token,"room_revision":float(rev)},{"slot_index":null,"request_id":token,"room_revision":rev}]:
		game._handle_room_request("room_replace",payload)
		check(b.get_snapshot()==before,"actual Main rejects malformed replacement payload without coercing/removing old spell")
	for payload in [null,{}, {"request_id":float(token),"room_revision":rev},{"request_id":token,"room_revision":float(rev)}]:
		game._handle_room_request("room_replace_cancel",payload)
		check(b.get_snapshot()==before,"actual Main rejects malformed cancellation payload")

func replacement_exercise(selected: int)->bool:
	var b=game.room_run
	var cards: Array=b.reward_choices.duplicate(true)
	var old: Array=b.spells.duplicate(true)
	var rng: int=b._rng.state
	var id: String=str(cards[selected].id)
	await click("领取奖励",selected)
	check(not b.pending_replacement.is_empty() and b.phase=="reward","actual card click opens pending replacement page")
	if b.pending_replacement.is_empty():return false
	var token: int=int(b.pending_replacement.request_id)
	check(ui_button("ConfirmSpellReplacement").disabled,"confirmation disabled before selecting old slot")
	check(buttons().filter(func(button):return button.has_meta("replacement_slot_index") and str(button.name).begins_with("ReplaceSpellSlot")).size()==8,"actual replacement page displays exactly eight selectable existing slots")
	await snap("replacement-01-eight-natural-slots-unselected")
	malformed_requests()
	var before: Dictionary=b.get_snapshot()
	await tick(.3)
	check(without_elapsed(b.get_snapshot())==without_elapsed(before) and absf(b.time-float(before.time)-.3)<.0001,"replacement decision advances route time while combat and all inventories stay frozen")
	await mouse_to(Vector2(350,180))
	await tap(KEY_RIGHT)
	var focused: Control=root.gui_get_focus_owner()
	check(focused is Button and focused.has_meta("replacement_slot_index"),"direction key focuses a genuine replacement slot")
	await tap(KEY_TAB)
	var next_focus: Control=root.gui_get_focus_owner()
	await tap(KEY_TAB,true)
	check(root.gui_get_focus_owner()==focused and next_focus!=focused,"Shift+Tab reverses actual Tab focus")
	await tap(KEY_ENTER)
	check(not b.pending_replacement.is_empty() and b.spells==old and not ui_button("ConfirmSpellReplacement").disabled,"keyboard Enter selects old slot without consuming spell")
	await snap("replacement-02-keyboard-slot-selection")
	await tap(KEY_ESCAPE)
	await wait_choice_reveal("领取奖励")
	check(b.pending_replacement.is_empty() and b.reward_choices==cards and b.spells==old and b._rng.state==rng and not b.portal.usable,"Escape returns identical three cards with no RNG/old-spell change")
	await snap("replacement-03-escape-original-three")
	await click("领取奖励",selected)
	check(int(b.pending_replacement.request_id)>token,"reopened UI binds a fresh request")
	var slot: int=worst_slot()
	await press_button("ReplaceSpellSlot"+str(slot))
	check(b.spells==old and int(ui_button("ConfirmSpellReplacement").get_meta("replacement_slot_index",-1))==slot,"mouse selects intended old slot but does not replace immediately")
	await snap("replacement-04-mouse-slot-confirm-ready")
	await press_button("PauseSpellReplacement")
	check(b.paused,"actual replacement pause button opens pause page")
	var paused: Dictionary=b.get_snapshot()
	await tick(.3)
	check(b.get_snapshot()==paused,"paused replacement freezes total and combat time")
	await snap("replacement-05-paused-pending")
	await click("继续试炼")
	check(not b.paused and not b.pending_replacement.is_empty() and int(ui_button("ConfirmSpellReplacement").get_meta("replacement_slot_index",-1))==slot,"resume returns same pending and selected slot")
	await snap("replacement-06-resumed-selection")
	await press_button("ConfirmSpellReplacement")
	check(b.phase=="exit" and b.pending_replacement.is_empty() and b.spells.size()==8 and str(b.spells[slot].id)==id and int(b.spells[slot].level)==1,"actual confirm replaces exactly selected slot with new level1")
	check(float(b.spells[slot].remaining)==0 and float(b.spells[slot].cast_remaining)==0,"actual new spell has no inherited cooldown")
	for index in range(8):
		if index!=slot:check(b.spells[index].id==old[index].id and b.spells[index].level==old[index].level and b.spells[index].remaining==old[index].remaining,"actual unselected slots preserved")
	await snap("replacement-07-confirmed-natural-inventory")
	replacement_records.append({"mode":"actual_mouse_keyboard_confirm","room":b.room_index,"new_spell":id,"slot":slot,"old_spell":old[slot],"new":b.spells[slot].duplicate(true),"original_cards":cards})
	_replacement_exercised=true
	return b.phase=="exit"

func skip_exercise(selected: int)->bool:
	var b=game.room_run
	var old: Array=b.spells.duplicate(true)
	var cards: Array=b.reward_choices.duplicate(true)
	var rng: int=b._rng.state
	await click("领取奖励",selected)
	check(not b.pending_replacement.is_empty(),"all-new offer can first inspect replacement")
	await press_button("CancelSpellReplacement")
	await wait_choice_reveal("领取奖励")
	check(b.pending_replacement.is_empty() and b.reward_choices==cards and b.spells==old and b._rng.state==rng,"real back button returns same all-new cards")
	await snap("replacement-08-all-new-cancel-and-skip")
	var skip: Button=ui_button("SkipSpellReward")
	check(skip!=null and not skip.disabled,"approved full/all-new skip is visible only after reveal")
	var unchanged: Dictionary=b.get_snapshot()
	for payload in [null,{}, {"room_revision":float(b.room_revision)},{"room_revision":null},{"room_revision":"1"}]:
		game._handle_room_request("room_reward_skip",payload)
		check(b.get_snapshot()==unchanged,"actual Main rejects malformed skip request")
	await press_button("SkipSpellReward")
	check(b.phase=="exit" and b.portal.usable and b.spells==old and b._rng.state==rng and b.reward_choices.is_empty(),"actual skip consumes node while preserving build and RNG")
	await snap("replacement-09-skipped-build-preserved")
	replacement_records.append({"mode":"actual_cancel_then_skip","room":b.room_index,"spells":old,"original_cards":cards})
	_skip_exercised=true
	return b.phase=="exit"

func choose_growth() -> bool:
	var b=game.room_run
	var selected: int=-1
	var full: bool=b.spells.size()==8
	# Establish real varied inventory; exercise one intentional replacement.
	# Thereafter prefer owned upgrades, and preserve build on all-new offers.
	for wanted_new in ([false,true] if full and _replacement_exercised else [true,false]):
		for id in SPELL_PREFERENCE:
			for index in b.reward_choices.size():
				if str(b.reward_choices[index].id)==id and bool(b.reward_choices[index].is_new)==wanted_new:selected=index;break
			if selected>=0:break
		if selected>=0:break
	check(selected>=0,"real offered growth candidate available")
	if selected<0:return false
	if full and bool(b.reward_choices[selected].is_new):
		if not _replacement_exercised:return await replacement_exercise(selected)
		if b.get_snapshot().get("can_skip_spell_reward",false):
			if not _skip_exercised:return await skip_exercise(selected)
			var old: Array=b.spells.duplicate(true)
			await wait_choice_reveal("领取奖励")
			await press_button("SkipSpellReward")
			check(b.phase=="exit" and b.spells==old,"later all-new offer legally skipped with current build intact")
			return b.phase=="exit"
		await click("领取奖励",selected)
		await press_button("ReplaceSpellSlot"+str(worst_slot()))
		await press_button("ConfirmSpellReplacement")
		return b.phase=="exit"
	if str(b.reward_choices[selected].id).begins_with("I") and not _shot.has("ice_card"):
		await wait_choice_reveal("领取奖励")
		_shot.ice_card=true
		await snap("natural-offered-ice-real-card-before-selection")
	return await click("领取奖励",selected)


func choose_artifact() -> bool:
	var battle = game.room_run
	var before: Dictionary = battle.get_snapshot()
	var offered: Array = before.get("artifact_choices", [])
	check(offered.size() > 0 and offered.size() <= 3, "source eligible elite artifact offer")
	await tick(0.3)
	var thought: Dictionary = battle.get_snapshot()
	check(without_elapsed(thought) == without_elapsed(before) and absf(float(thought.time)-float(before.time)-0.3)<0.0001, "artifact decision advances only total clock while combat and offer stay frozen")
	if battle.room_index == 6:
		await hover_exercise("领取宝物", "room-06-artifact")
	else:
		await mouse_to(Vector2(800,112)*Vector2(root.size)/LOGICAL)
	await wait_choice_reveal("领取宝物")
	await snap("room-%02d-real-artifact-three-choice" % battle.room_index)
	var index: int = 0
	for preferred in ["IG02", "IG03", "IG01", "IP01", "IP02", "IP03", "IB07", "IB05", "IB08", "IB09", "IB01", "IB02", "IB03", "IB04", "IB06", "IB10", "P04", "P05", "U03", "GU11", "GT01", "GU05", "GU06", "GU07", "U02", "U01"]:
		var found: bool = false
		for candidate in offered.size():
			if offered[candidate].id == preferred:
				index = candidate
				found = true
				break
		if found:
			break
	var acquired: String = str(offered[index].id) if not offered.is_empty() else ""
	if not await click("领取宝物", index):
		return false
	var after: Dictionary = battle.get_snapshot()
	check(after.phase == "exit" and after.artifacts.size() == before.artifacts.size() + 1, "real artifact card grants one run-local item and opens gate")
	check(after.artifacts.back().id == acquired and after.spells == before.spells, "artifact card owns selected item without consuming spell slot")
	if acquired.begins_with("IB") or acquired.begins_with("IP") or acquired.begins_with("IG"):
		new_ice_acquired.append({"room":battle.room_index,"id":acquired,"offered":offered})
	await snap("room-%02d-artifact-inventory-and-open-gate" % battle.room_index)
	return true


func walk_pickup() -> bool:
	await release_movement()
	var battle = game.room_run
	var before: Dictionary = battle.get_snapshot()
	var pickup: Dictionary = before.get("reward_pickup", {})
	check(battle.phase == "pickup" and not pickup.is_empty() and pickup.visible and not battle.portal.usable, "clear leaves real book/chest and locked portal")
	check(visible_choices("领取奖励").is_empty() and visible_choices("领取宝物").is_empty(), "cards stay hidden until actual reward contact")
	if pickup.is_empty(): return false
	if battle.room_index == 1:
		var label_before: String = game.room_ui.timer_label.text
		await tick(1.1)
		check(game.room_ui.timer_label.text != label_before, "HUD total timer visibly advances while waiting for book")
		check(absf(battle.time-float(before.time)-1.1)<0.0001 and battle.get_snapshot().combat_time == before.combat_time and battle.spells == before.spells, "waiting pickup advances elapsed timer without cooling spells")
	var guard: int = 0
	var captured: bool = false
	while battle.phase == "pickup" and guard < 120*30:
		if battle.paused:
			await resume_focus("reward object walk")
		if not captured and battle.player.pos.distance_to(pickup.pos)<3.5 and battle.room_index in [1,6,12,15,21,30,31,39,45]:
			captured = true
			await snap("room-%02d-physical-%s-before-contact" % [battle.room_index,pickup.kind])
		await direction_keys(_pilot.autoplay_direction(battle))
		for _tick in 12:
			await step()
			guard += 1
			if battle.phase != "pickup": break
	await release_movement()
	var after: Dictionary = battle.get_snapshot()
	check(guard<120*30 and battle.phase in ["reward","artifact"], "real held WASD contact opens required cards")
	check(after.player.pos.distance_to(pickup.pos)<=float(pickup.radius)+float(battle.player.radius)+0.05, "card opened at actual pickup footprint")
	check(after.reward_pickup.claimed and not after.reward_pickup.visible and after.combat_time == before.combat_time and after.time >= before.time, "contact consumes object while only total travel time advances")
	pickup_records.append({"room":battle.room_index,"kind":pickup.kind,"pickup":pickup.pos,"before":before.player.pos,"contact":after.player.pos,"time_before":before.time,"time_after":after.time,"combat_before":before.combat_time,"combat_after":after.combat_time})
	return guard<120*30 and battle.phase in ["reward","artifact"]


func pause_exercise() -> bool:
	if game.room_run.phase != "combat":
		return false
	await direction_keys(Vector2(0.0, 1.0))
	await tick(0.12)
	if game.room_run.phase != "combat":
		return false
	await key(KEY_ESCAPE, true)
	await key(KEY_ESCAPE, false)
	check(game.room_run.paused, "real Esc pauses mixed combat")
	var before: Dictionary = game.room_run.get_snapshot()
	await tick(0.4)
	check(game.room_run.get_snapshot() == before, "pause freezes enemies projectiles spells and artifact timers")
	await snap("08-mixed-combat-paused")
	await click("继续试炼")
	var pos: Vector2 = game.room_run.player.pos
	await tick(0.12)
	check(game.room_run.player.pos == pos, "pause resume requires releasing held movement")
	await release_movement()
	return true


func walk_exit() -> bool:
	await release_movement()
	var battle = game.room_run
	var room: int = battle.room_index
	if room == 1:
		var waited: Dictionary = battle.get_snapshot()
		var label_before: String = game.room_ui.timer_label.text
		await tick(1.1)
		check(absf(battle.time-float(waited.time)-1.1)<0.0001 and battle.combat_time == waited.combat_time and battle.spells == waited.spells, "standing at open gate advances only elapsed route clock")
		check(game.room_ui.timer_label.text != label_before, "HUD timer visibly advances after reward claim")
	var guard: int = 0
	while battle.room_index == room and battle.phase == "exit" and guard < 1800:
		if battle.paused:
			await resume_focus("portal walk")
		var direction: Vector2 = _pilot.autoplay_direction(battle)
		await direction_keys(direction)
		for _tick in 12:
			await step()
			guard += 1
			if battle.room_index != room or battle.phase != "exit":
				break
	await release_movement()
	check(guard < 1800, "actual WASD contact reaches portal after room " + str(room))
	return guard < 1800


func traverse() -> bool:
	for room in range(1, game.room_run.room_total+1):
		var battle = game.room_run
		check(battle.room_index == room and battle.phase == "combat", "real continuous portal reaches room " + str(room))
		if not new_ice_acquired.is_empty() and room > int(new_ice_acquired[0].room):
			new_ice_combat_rooms.append(room)
		if battle.room_index != room or battle.phase != "combat":
			return false
		if room in [15,16,20,21,29,30,31,39,44,45]:
			await snap("room-%02d-natural-entry-and-route-nodes" % room)
		var guard: int = 0
		while battle.phase == "combat" and guard < 120 * 240:
			if battle.paused:
				await resume_focus("mixed battle")
			await direction_keys(bot_direction())
			for _tick in 18:
				await step()
				guard += 1
				if battle.phase != "combat":
					break
			await capture_observed_combat()
			if room in [4, 5, 6] and guard > 360 and not _shot.has("pause"):
				if await pause_exercise():
					_shot.pause = true
		await release_movement()
		check(battle.phase in ["pickup", "exit"] and battle.player.health > 0.0, "mixed encounter naturally clears room " + str(room))
		rooms.append(battle.get_summary())
		if room % 5 == 0: print("FORMAL MAIN progress room%d phase%s health%.1f time%.2f spells%s treasures%s" % [room,battle.phase,battle.player.health,battle.time,str(battle.spells.map(func(value):return value.id)),str(battle.get_snapshot().artifacts.map(func(value):return value.id))])
		if battle.phase not in ["pickup", "exit"]:
			await snap("failed-room-%02d" % room)
			return false
		check(battle.clear_count == room and battle.cleared_rooms == range(1, room + 1), "real clear ledger contains room " + str(room))
		if battle.phase == "pickup" and not await walk_pickup():
			return false
		if battle.phase == "reward":
			var frozen: Dictionary = battle.get_snapshot()
			await tick(0.3)
			var thought: Dictionary = battle.get_snapshot()
			check(without_elapsed(thought) == without_elapsed(frozen) and absf(float(thought.time)-float(frozen.time)-0.3)<0.0001, "real spell decision counts total time while rules freeze")
			if room == 1:
				await hover_exercise("领取奖励", "room-01-spell")
			if room in [2,4,9,16,20,29,31,39,44]:
				await mouse_to(Vector2(800,112)*Vector2(root.size)/LOGICAL)
				await wait_choice_reveal("领取奖励")
				await snap("room-%02d-expanded-spell-three-choice" % room)
			if not await choose_growth():
				return false
		elif battle.phase == "artifact":
			if not await choose_artifact():
				return false
		check(battle.phase == "exit" and battle.portal.usable, "room rewards unlock usable exit " + str(room))
		var before: Dictionary = battle.get_snapshot()
		if not await walk_exit():
			return false
		if room < battle.room_total:
			var after: Dictionary = battle.get_snapshot()
			check(after.room_index == room + 1 and after.room_revision == before.room_revision + 1, "portal consumes one room transition")
			check(after.player.health == before.player.health and after.spells == before.spells and after.artifacts == before.artifacts, "portal preserves health upgrades cooldowns and artifacts")
			check(after.time>before.time and after.combat_time == before.combat_time and absf(float(after.room_time))<0.0001, "exit travel counts total time while combat clock freezes and next room clock resets")
			transitions.append({"from": room, "to": after.room_index, "health": after.player.health, "artifacts": after.artifacts, "spells": after.spells})
		else:
			check(battle.phase == "complete" and game.room_settlement.get("ok", false), "forty-fifth real portal completes route")
	return true


func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	initial_source_hashes = source_hashes()
	# Remove only PNGs declared by this harness's own prior result manifest.
	if FileAccess.file_exists(OUT + "results.json"):
		var previous: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUT + "results.json"))
		if previous is Dictionary:
			for label in previous.get("captures", []):
				var filename: String = str(label)
				if not filename.contains("/") and not filename.contains("\\") and not filename.contains(".."):
					var path: String = ProjectSettings.globalize_path(OUT + filename + ".png")
					if FileAccess.file_exists(path):
						DirAccess.remove_absolute(path)
	DirAccess.make_dir_recursive_absolute("user://tests")
	for path in [SAVE, SAVE + ".tmp", SAVE + ".bak", PREFS]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for path in ["user://meta_progression_v1.json", "user://display.cfg"]:
		production_before[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	DisplayServer.window_set_size(Vector2i(1600, 900))
	game = Main.new()
	game.save_path = SAVE
	game.preferences_path = PREFS
	game.room_seed = _seed
	root.add_child(game)
	game.set_process(false)
	root.grab_focus()
	for _frame in 3:
		await process_frame
	check(DisplayServer.get_name() != "headless", "visual QA requires native rendered display")
	if DisplayServer.get_name() == "headless":
		await finish()
		return
	check(game.load_error.is_empty(), "real Main loads with isolated account")
	account_before = game.meta.get_state()
	save_bytes_before = FileAccess.get_file_as_string(SAVE)
	if not await click("开始冒险     ›"):
		await finish()
		return
	check(game.screen == "prepare", "real home button reaches preparation")
	check(await click("冰系试炼"), "actual preparation ice-school selector clicked")
	check(game.route_school == "ice", "Main stores requested local ice school")
	await click("进入60房路线    ›")
	check(game.room_run != null and game.room_run.phase == "choosing", "actual preparation starts new mixed route")
	if game.room_run == null:
		await finish()
		return
	await hover_exercise("选择法术", "00-actual-three-starter-choice")
	var frozen: Dictionary = game.room_run.get_snapshot()
	await tick(0.3)
	check(game.room_run.get_snapshot() == frozen, "initial choice freezes rule and animation clock")
	check(game.room_run.initial_choices().map(func(item):return item.id) == ["I01","I02","I03"], "actual ice starter set follows chosen school")
	await click("选择法术", 2)
	await release_movement()
	var completed: bool = await traverse()
	check(completed, "actual Main UI and WASD complete all forty-five rooms")
	if completed:
		final_summary = game.room_run.get_summary()
		check(final_summary.get("artifacts", []).size() == 9, "all nine treasure rooms grant exactly nine items")
		check(transitions.size() == 44, "all forty-four transitions physically traversed")
		check(not new_ice_acquired.is_empty() and not new_ice_combat_rooms.is_empty(), "actual cached offers grant newly added ice profession items carried into later real combat")
		check(pickup_records.size()>=32 and final_summary.time>final_summary.combat_time, "every nonempty reward physically collected; capped spell pool skips without softlock")
		check(not game.meta.is_in_run() and game.meta.get_state() == account_before and FileAccess.get_file_as_string(SAVE) == save_bytes_before, "completed route leaves isolated account byte-identical")
		await snap("45-real-route-completion-with-nine-treasures")
	check(max_actor_error < 0.00001 and max_projection_error < 0.00001 and projection_samples > 1000, "actual actor follows core and projection helper matches Camera3D calculation")
	check(over_cap_samples == 0 and premature_clear_samples == 0, "actual encounters respect cap and clear every batch")
	check(observed_types.has("M02") and observed_types.has("M03") and observed_types.has("M04") and observed_types.has("EL01") and observed_types.has("EL02"), "real route displays multiple ordinary and elite types")
	check(observed_spells.keys().filter(func(id):return str(id).begins_with("I")).size() >= 3 and resource_telemetry.ice_events.get("ice_frost",0)>0, "actual ice spells acquired from real offers and apply frost in later combat")
	check(observed_spells.size() >= 5, "actual growth acquires varied usable mixed spells")
	check(observed_projectiles >= 3, "actual elite fan spawns multiple simulated projectiles")
	for required in ["north_spawn", "natural_ice", "ice_zones", "pause", "ranged-middle", "ranged-later"]:
		check(_shot.has(required), "required observed native screenshot: " + required)
	check(_replacement_exercised and _skip_exercised,"natural route actually exercises confirm and cancel-to-skip UI")
	await finish()


func finish():
	await release_movement()
	check(source_hashes() == initial_source_hashes, "native visual source and material hashes stay fixed throughout the run")
	for path in production_before:
		var after: String = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
		check(after == production_before[path], "production account/preferences untouched: " + path)
	var result = {"replacement_records":replacement_records,"checks": checks, "failures": failures.size(), "details": failures, "seed": _seed, "captures": captures, "samples": samples, "rooms": rooms, "transitions": transitions, "pickup_records":pickup_records, "hover_records":hover_records, "final_summary": final_summary, "new_ice_acquired":new_ice_acquired,"new_ice_combat_rooms":new_ice_combat_rooms,"resource_telemetry":resource_telemetry, "observed_types": observed_types.keys(), "observed_spells": observed_spells.keys(), "observed_dangers": observed_dangers.keys(), "maximum_enemy_projectiles": observed_projectiles, "source_sha256": initial_source_hashes, "source_stable": source_hashes()==initial_source_hashes, "engine": Engine.get_version_info(), "max_actor_error": max_actor_error, "max_projection_error": max_projection_error, "projection_samples": projection_samples, "over_cap_samples": over_cap_samples, "premature_clear_samples": premature_clear_samples, "focus_events": focus_events, "production_before": production_before, "provenance": "Native Godot Main pixels; real UI mouse enter/leave/clicks and held eight-direction WASD collect every book/chest, automatic spells and natural enemy damage. Total time includes pickup, card decisions and exit; combat_time only combat. No player/actor health, position, phase, damage, cooldown or snapshot edits. Saves/preferences isolated; no user game process touched."}
	FileAccess.open(OUT + "results.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	for path in [SAVE, SAVE + ".tmp", SAVE + ".bak", PREFS]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SPELL REPLACEMENT VISUAL: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in ["res://tests/spell_replacement_visual.gd","res://tests/route_rebalance_tests.gd","res://data/courtyard_route.json","res://data/route_enemy_runtime.json","res://scripts/core/courtyard_route_run.gd","res://scripts/core/courtyard_route_catalog.gd","res://scripts/core/route_enemy_combat.gd","res://scripts/core/route_spell_combat.gd","res://scripts/core/route_fire_status.gd","res://scripts/core/route_ice_status.gd","res://scripts/core/route_ice_combat.gd","res://scripts/core/route_ice_artifacts.gd","res://data/ice_spells_v1.json","res://data/ice_artifacts_v1.json","res://scripts/core/route_artifacts.gd","res://scripts/core/route_generic_items.gd","res://data/generic_artifacts_v1.json","res://scripts/ui/artifact_icon.gd","res://scripts/ui/arcane_icon.gd","res://scripts/presentation/route_spell_vfx.gd","res://scripts/ui/grimoire_catalog.gd","res://scripts/presentation/first_room_view.gd","res://assets/ui/frames_v1/reward_card_front.png","res://assets/ui/frames_v1/reward_card_back.png","res://assets/ui/frames_v1/spell_slot.png","res://scripts/ui/choice_card.gd","res://scripts/ui/first_room_ui.gd","res://scripts/ui/atelier_ui.gd"]:
		result[path] = FileAccess.get_sha256(path)
	for path in ["res://scripts/core/first_room_run.gd","res://data/balance_candidates/first_run_v1.json","res://data/balance_candidates/fire_artifacts_v1.json","res://data/route_artifact_runtime.json","res://data/route_spell_runtime.json","res://data/first_room_runtime.json"]:
		result[path] = FileAccess.get_sha256(path)
	for id in ["GU04","GU05","GU06","GU07","GU08","GU09","GU10","GU11","GU12","GU13","GU14","GU15","GU16","GU17","GU18","GT01","GT02","GT03","GT04"]:
		var path: String="res://assets/ui/generic_items_v1/"+str(id).to_lower()+".png"
		result[path] = FileAccess.get_sha256(path)
	for filename in ["f11_ignition_mark.png", "b11_kindling_ring.png", "p06_lingering_embers.png", "g04_rekindling_signet.png"]:
		var path: String = "res://assets/ui/fire_formal_v1/"+filename
		result[path] = FileAccess.get_sha256(path)
	for id in ["I01","I02","I03","I04","I05","I06","I07","I08","I09","I10","IB01","IB02","IB03","IB04","IB05","IB06","IB07","IB08","IB09","IB10","IP01","IP02","IP03","IG01","IG02","IG03"]:
		var path: String="res://assets/ui/ice_formal_v1/"+id.to_lower()+".png"
		result[path]=FileAccess.get_sha256(path)
	result.merge(SourceBinding.capture(["res://tests/spell_replacement_visual.gd","res://scripts/main.gd","res://project.godot"]),true)
	return result
