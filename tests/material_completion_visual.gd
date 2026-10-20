extends SceneTree
## Material completion: genuine Main/UI/WASD, natural progression only.
## No HP, actor, phase, position, spell, numerical or snapshot mutations.

const Main = preload("res://scripts/main.gd")
const MovementPolicy = preload("res://tests/route_rebalance_tests.gd")
var OUT = "res://build/qa/material-completion-20261017/visual/route-offense/"
var SAVE = "user://tests/material_completion_visual_v1_offense.json"
var PREFS = "user://tests/material_completion_visual_v1_offense_display.cfg"
const LOGICAL = Vector2(1600, 900)
var SPELL_PREFERENCE = ["F03", "F07", "F06", "F05", "F04", "F08", "F02", "F10", "F09", "F01"]
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
var _profile: String = "offense"
var _starter_index: int = 0
var vfx_coverage: Dictionary = {}
var vfx_samples: Array = []
var vfx_max_quads: int = 0
var vfx_max_cores: int = 0
var vfx_limit_errors: int = 0
var vfx_clock_errors: int = 0
var vfx_stale_samples: int = 0
var vfx_revision_errors: int = 0
var friendly_danger_samples: int = 0
var player_hud_overlap_samples: int = 0
var material_icon_records: Array = []
var menu_captures: Array = []
var painted_flame_samples: int = 0
var painted_flame_errors: int = 0
var _final_renderer: bool = false


func _initialize():
	_pilot.direction_count = 8
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with("--seed="):
			_seed = int(str(argument).trim_prefix("--seed="))
	if "--utility" in OS.get_cmdline_user_args():
		_profile = "utility"
		_starter_index = 1
		SPELL_PREFERENCE = ["F09", "F10", "F02", "F05", "F06", "F03", "F07", "F08", "F04", "F01"]
		OUT = "res://build/qa/material-completion-20261017/visual/route-utility/"
		SAVE = "user://tests/material_completion_visual_v1_utility.json"
		PREFS = "user://tests/material_completion_visual_v1_utility_display.cfg"
	if "--menus-only" in OS.get_cmdline_user_args():
		_profile = "menus-only"
		OUT = "res://build/qa/material-completion-20261017/visual/menus-only/"
		SAVE = "user://tests/material_completion_visual_v1_menus_only.json"
		PREFS = "user://tests/material_completion_visual_v1_menus_only_display.cfg"
	if "--final" in OS.get_cmdline_user_args():
		_final_renderer = true
		_profile = "final-offense"
		OUT = "res://build/qa/material-completion-20261017/visual/final/route-offense/"
		SAVE = "user://tests/material_completion_visual_v1_final_offense.json"
		PREFS = "user://tests/material_completion_visual_v1_final_offense_display.cfg"
	call_deferred("run")


func check(value: bool, label: String):
	checks += 1
	if not value:
		failures.append(label)
		push_error("Material completion visual: " + label)


func buttons() -> Array:
	if is_instance_valid(game.room_ui):
		return game.room_ui.root.find_children("*", "Button", true, false)
	return game.ui.page.find_children("*", "Button", true, false)


func click(text: String, index: int = 0) -> bool:
	var matches: Array = []
	for button in buttons():
		if button.text == text and button.is_visible_in_tree() and not button.disabled:
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
	return buttons().filter(func(button): return button.text == text and button.is_visible_in_tree() and not button.disabled)


func choice_style(button: Button) -> Dictionary:
	var style: StyleBox = button.get_parent().get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		return {"border": style.border_color, "background": style.bg_color, "width": style.border_width_left}
	return {}


func hover_exercise(text: String, label: String):
	var choices: Array = visible_choices(text)
	check(choices.size() > 0, "actual choice buttons for hover exercise")
	for button in choices:
		check(not button.has_focus(), "choice modal does not automatically focus a first card")
	await mouse_to(Vector2(800,112)*Vector2(root.size)/LOGICAL)
	var neutral: Array = []
	for button in choices:
		check(not button.is_hovered() and not button.has_focus(), "mouse outside reward buttons leaves all cards neutral")
		neutral.append(choice_style(button))
	await snap(label+"-neutral")
	if choices.is_empty(): return
	var target: int = mini(1,choices.size()-1)
	var card: Control = choices[target].get_parent()
	await mouse_to((card.get_global_rect().position+Vector2(card.size.x*0.5,card.size.y*0.45))*Vector2(root.size)/LOGICAL)
	for index in choices.size():
		check(not choices[index].is_hovered() and choice_style(choices[index]) == neutral[index], "card body outside exact reward button stays neutral")
	await snap(label+"-card-body-neutral")
	await mouse_to(choices[target].get_global_rect().get_center()*Vector2(root.size)/LOGICAL)
	for index in choices.size():
		check(choices[index].is_hovered() == (index == target), "only button under real mouse becomes hovered")
	check(choice_style(choices[target]) != neutral[target], "button hover changes its actual card style")
	await snap(label+"-button-hover")
	await mouse_to(Vector2(800,112)*Vector2(root.size)/LOGICAL)
	for index in choices.size():
		check(not choices[index].is_hovered() and not choices[index].has_focus() and choice_style(choices[index]) == neutral[index], "leaving exact button removes highlight and focus")
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
		var pos: Vector2 = battle.player.pos
		max_actor_error = maxf(max_actor_error, game.room_view.actor.position.distance_to(Vector3(pos.x, 0.0, -pos.y)))
		for height in [0.0, 1.45]:
			var projected: Vector2 = game.room_view.camera.unproject_position(Vector3(pos.x, height, -pos.y)) * game.room_view.size / LOGICAL
			max_projection_error = maxf(max_projection_error, projected.distance_to(game.room_view.screen_position(pos, height)))
		projection_samples += 1
		observe_material_state()
		var alive: int = 0
		for actor in battle.actors:
			if actor.health > 0.0:
				alive += 1
				observed_types[str(actor.get("type_id", actor.get("type", "")))] = true
				var danger: Dictionary = actor.get("danger", {})
				if not danger.is_empty():
					observed_dangers[str(danger.get("kind", ""))] = true
		if alive > int(battle._ordinary.spawn.alive_cap_by_normal_stat_stage[0]):
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
	samples.append({"label": label, "room": snapshot.room_index, "phase": snapshot.phase, "health": snapshot.player.health, "time": snapshot.time, "combat_time": snapshot.get("combat_time", 0.0), "room_time": snapshot.get("room_time", 0.0), "reward_pickup": snapshot.get("reward_pickup", {}), "player": snapshot.player.pos, "spells": snapshot.spells, "artifacts": snapshot.get("artifacts", []), "types": observed_types.keys(), "projectiles": snapshot.get("enemy_projectiles", []).size(), "vfx": game.room_view.get_vfx_debug_state()})
	verify_material_icons(label)


func visible_world(point: Vector2) -> bool:
	return Rect2(105, 165, 1390, 560).has_point(game.room_view.screen_position(point, 0.6))


func capture_observed_combat():
	var battle = game.room_run
	var room: int = battle.room_index
	var snapshot: Dictionary = battle.get_snapshot()
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
	var vfx: Dictionary = game.room_view.get_vfx_debug_state()
	var coverage: Dictionary = vfx.get("coverage", {})
	if _final_renderer and int(vfx.get("quad_count", 0)) >= 60 and not _shot.has("painted_dense"):
		_shot.painted_dense = true
		await snap("vfx-natural-painted-flame-dense-combat")
	for kind in ["F01_bolt", "F02_passive", "F03_rainfall", "F04_spirit", "F05", "F06", "bomb_flight", "bomb_impact", "beam", "wave", "shield_restore"]:
		if coverage.has(kind) and not _shot.has("vfx_" + kind):
			_shot["vfx_" + kind] = true
			await snap("vfx-natural-" + str(kind).to_lower())
	if not _shot.has("danger_with_fire") and int(vfx.get("quad_count", 0)) > 0:
		for actor in battle.actors:
			if actor.health > 0 and not actor.get("danger", {}).is_empty() and visible_world(actor.pos):
				_shot.danger_with_fire = true
				await snap("vfx-natural-hostile-warning-over-friendly-fire")
				break
	if not snapshot.get("spell_zones", []).is_empty() and not _shot.has("fire_zones"):
		_shot.fire_zones = true
		await snap("07-expanded-fire-spell-zones")


func bot_direction() -> Vector2:
	return _pilot.autoplay_direction(game.room_run)


func choose_growth() -> bool:
	var battle = game.room_run
	var selected: int = -1
	# Acquire new real spell behaviors first; then strengthen carried spells.
	for wanted_new in [true, false]:
		for preferred in SPELL_PREFERENCE:
			for index in battle.reward_choices.size():
				var choice: Dictionary = battle.reward_choices[index]
				if choice.id == preferred and bool(choice.get("is_new", false)) == wanted_new:
					selected = index
					break
			if selected >= 0:
				break
		if selected >= 0:
			break
	check(selected >= 0, "real available growth choice exists")
	return await click("领取奖励", selected) if selected >= 0 else false


func choose_artifact() -> bool:
	var battle = game.room_run
	var before: Dictionary = battle.get_snapshot()
	var offered: Array = before.get("artifact_choices", [])
	check(offered.size() > 0 and offered.size() <= 3, "source eligible elite artifact offer")
	await tick(0.3)
	var thought: Dictionary = battle.get_snapshot()
	check(without_elapsed(thought) == without_elapsed(before) and absf(float(thought.time)-float(before.time)-0.3)<0.0001, "artifact decision advances only total clock while combat and offer stay frozen")
	if battle.room_index == 6:
		await hover_exercise("领取神器", "room-06-artifact")
	else:
		await mouse_to(Vector2(800,112)*Vector2(root.size)/LOGICAL)
	await snap("room-%02d-real-artifact-three-choice" % battle.room_index)
	var index: int = 0
	for preferred in ["U01", "U02", "U03", "B04", "P01", "P04", "P05", "B01", "B08"]:
		var found: bool = false
		for candidate in offered.size():
			if offered[candidate].id == preferred:
				index = candidate
				found = true
				break
		if found:
			break
	var acquired: String = str(offered[index].id) if not offered.is_empty() else ""
	if not await click("领取神器", index):
		return false
	var after: Dictionary = battle.get_snapshot()
	check(after.phase == "exit" and after.artifacts.size() == before.artifacts.size() + 1, "real artifact card grants one run-local item and opens gate")
	check(after.artifacts.back().id == acquired and after.spells == before.spells, "artifact card owns selected item without consuming spell slot")
	await snap("room-%02d-artifact-inventory-and-open-gate" % battle.room_index)
	check(game.room_view.get_vfx_debug_state().get("coverage", {}).has("artifact_acquired"), "actual acquisition has new source-driven VFX")
	return true


func walk_pickup() -> bool:
	await release_movement()
	var battle = game.room_run
	var before: Dictionary = battle.get_snapshot()
	var pickup: Dictionary = before.get("reward_pickup", {})
	check(battle.phase == "pickup" and not pickup.is_empty() and pickup.visible and not battle.portal.usable, "clear leaves real book/chest and locked portal")
	check(visible_choices("领取奖励").is_empty() and visible_choices("领取神器").is_empty(), "cards stay hidden until actual reward contact")
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
		if not captured and battle.player.pos.distance_to(pickup.pos)<3.5 and battle.room_index in [1,6,12,15]:
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
	var visual_before: Dictionary = game.room_view.get_vfx_debug_state()
	await tick(0.4)
	check(game.room_view.get_vfx_debug_state() == visual_before, "pause freezes VFX clock, geometry and batch contents")
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
	for room in range(1, 16):
		var battle = game.room_run
		check(battle.room_index == room and battle.phase == "combat", "real continuous portal reaches room " + str(room))
		if battle.room_index != room or battle.phase != "combat":
			return false
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
			if room in [2, 4, 9]:
				await mouse_to(Vector2(800,112)*Vector2(root.size)/LOGICAL)
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
		if room < 15:
			var after: Dictionary = battle.get_snapshot()
			check(after.room_index == room + 1 and after.room_revision == before.room_revision + 1, "portal consumes one room transition")
			check(after.player.health == before.player.health and after.spells == before.spells and after.artifacts == before.artifacts, "portal preserves health upgrades cooldowns and artifacts")
			check(after.time>before.time and after.combat_time == before.combat_time and absf(float(after.room_time))<0.0001, "exit travel counts total time while combat clock freezes and next room clock resets")
			transitions.append({"from": room, "to": after.room_index, "health": after.player.health, "artifacts": after.artifacts, "spells": after.spells})
		else:
			check(battle.phase == "complete" and game.room_settlement.get("ok", false), "fifteenth real portal completes route")
	return true


func run():
	DirAccess.make_dir_recursive_absolute(OUT)
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
	await menu_material_review()
	account_before = game.meta.get_state()
	save_bytes_before = FileAccess.get_file_as_string(SAVE)
	if _profile == "menus-only":
		await finish()
		return
	if not await click("开始冒险     ›"):
		await finish()
		return
	check(game.screen == "prepare", "real home button reaches preparation")
	await click("进入前期路线    ›")
	check(game.room_run != null and game.room_run.phase == "choosing", "actual preparation starts new mixed route")
	if game.room_run == null:
		await finish()
		return
	await hover_exercise("选择法术", "00-actual-three-starter-choice")
	var frozen: Dictionary = game.room_run.get_snapshot()
	await tick(0.3)
	check(game.room_run.get_snapshot() == frozen, "initial choice freezes rule and animation clock")
	await click("选择法术", _starter_index)
	await release_movement()
	var completed: bool = await traverse()
	check(completed, "actual Main UI and WASD complete all fifteen mixed rooms")
	if completed:
		final_summary = game.room_run.get_summary()
		check(final_summary.get("artifacts", []).size() == 3, "all three elite reward rooms grant exactly three items")
		check(transitions.size() == 14, "all fourteen transitions physically traversed")
		check(pickup_records.size()==15 and final_summary.time>final_summary.combat_time, "every room physically collects its object and summary distinguishes route/combat clocks")
		check(not game.meta.is_in_run() and game.meta.get_state() == account_before and FileAccess.get_file_as_string(SAVE) == save_bytes_before, "completed route leaves isolated account byte-identical")
		await snap("15-real-route-completion-with-artifacts")
	check(max_actor_error < 0.00001 and max_projection_error < 0.00001 and projection_samples > 1000, "actual actor follows core and projection helper matches Camera3D calculation")
	check(over_cap_samples == 0 and premature_clear_samples == 0, "actual encounters respect cap and clear every batch")
	check(observed_types.has("M02") and observed_types.has("M03") and observed_types.has("M04") and observed_types.has("EL01") and observed_types.has("EL02"), "real route displays multiple ordinary and elite types")
	check(observed_spells.size() >= 5, "actual growth acquires varied usable fire spells")
	check(observed_projectiles >= 3, "actual elite fan spawns multiple simulated projectiles")
	for required in ["north_spawn", "charge", "mark", "normal_elite", "fan_warning", "fan_projectiles", "fire_zones", "pause"]:
		check(_shot.has(required), "required observed native screenshot: " + required)
	check(vfx_max_quads > 0 and vfx_max_cores > 0, "native natural combat exercises both new VFX batches")
	check(vfx_limit_errors == 0 and vfx_revision_errors == 0, "VFX stays in fixed batches and current room revision")
	check(vfx_clock_errors == 0, "VFX reads combat_time through battle, pickup, cards and exit")
	check(vfx_stale_samples == 0, "no old combat flame remains after clear or in new room")
	check(friendly_danger_samples > 0 and _shot.has("danger_with_fire"), "actual hostile warning stays visible alongside friendly flame")
	check(player_hud_overlap_samples == 0, "followed Lina head stays clear of top-level HUD panels")
	if _final_renderer:
		check(painted_flame_samples > 1000 and painted_flame_errors == 0, "final actual Main uses bound painted flame texture in every sampled phase")
	await finish()


func finish():
	await release_movement()
	for path in production_before:
		var after: String = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
		check(after == production_before[path], "production account/preferences untouched: " + path)
	var result = {"final_renderer": _final_renderer, "painted_flame_samples": painted_flame_samples, "painted_flame_errors": painted_flame_errors, "renderer_source_sha256": {"vfx": FileAccess.get_sha256("res://scripts/presentation/route_spell_vfx.gd"), "shader": FileAccess.get_sha256("res://scripts/presentation/procedural_fire.gdshader"), "flame_texture": FileAccess.get_sha256("res://assets/vfx/fire_v2/flame_tongue.png")}, "profile": _profile, "vfx_coverage": vfx_coverage.keys(), "vfx_samples": vfx_samples, "vfx_max_quads": vfx_max_quads, "vfx_max_cores": vfx_max_cores, "vfx_limit_errors": vfx_limit_errors, "vfx_clock_errors": vfx_clock_errors, "vfx_stale_samples": vfx_stale_samples, "vfx_revision_errors": vfx_revision_errors, "friendly_danger_samples": friendly_danger_samples, "player_hud_overlap_samples": player_hud_overlap_samples, "material_icon_records": material_icon_records, "menu_captures": menu_captures, "checks": checks, "failures": failures.size(), "details": failures, "seed": _seed, "captures": captures, "samples": samples, "rooms": rooms, "transitions": transitions, "pickup_records":pickup_records, "hover_records":hover_records, "final_summary": final_summary, "observed_types": observed_types.keys(), "observed_spells": observed_spells.keys(), "observed_dangers": observed_dangers.keys(), "maximum_enemy_projectiles": observed_projectiles, "max_actor_error": max_actor_error, "max_projection_error": max_projection_error, "projection_samples": projection_samples, "over_cap_samples": over_cap_samples, "premature_clear_samples": premature_clear_samples, "focus_events": focus_events, "production_before": production_before, "provenance": "Native Godot Main pixels; real UI mouse enter/leave/clicks and held eight-direction WASD collect every book/chest, automatic spells and natural enemy damage. Total time includes pickup, card decisions and exit; combat_time only combat. No player/actor health, position, phase, damage, cooldown or snapshot edits. Saves/preferences isolated; no user game process touched."}
	FileAccess.open(OUT + "results.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	for path in [SAVE, SAVE + ".tmp", SAVE + ".bak", PREFS]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("MATERIAL COMPLETION VISUAL: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func observe_material_state():
	var battle = game.room_run
	var debug: Dictionary = game.room_view.get_vfx_debug_state()
	if debug.is_empty():
		vfx_limit_errors += 1
		return
	var quads: int = int(debug.get("quad_count", 0))
	var cores: int = int(debug.get("core_count", 0))
	vfx_max_quads = maxi(vfx_max_quads, quads)
	vfx_max_cores = maxi(vfx_max_cores, cores)
	if int(debug.get("batch_count", 0)) != 2 or int(debug.get("material_count", 0)) != 2 or quads > int(debug.get("quad_limit", 0)) or cores > int(debug.get("core_limit", 0)):
		vfx_limit_errors += 1
	if absf(float(debug.get("clock", -1)) - float(battle.combat_time)) > 0.00001:
		vfx_clock_errors += 1
	if int(debug.get("revision", -1)) != int(battle.room_revision):
		vfx_revision_errors += 1
	var coverage: Dictionary = debug.get("coverage", {})
	if _final_renderer:
		painted_flame_samples += 1
		if not bool(debug.get("painted_flame_bound", false)):
			painted_flame_errors += 1
	for kind in coverage:
		vfx_coverage[str(kind)] = true
		if battle.phase != "combat" and kind != "artifact_acquired":
			vfx_stale_samples += 1
	if battle.phase in ["choosing", "pickup", "reward", "artifact"] and (quads > 0 or cores > 0):
		vfx_stale_samples += 1
	if battle.phase == "combat" and quads > 0:
		for actor in battle.actors:
			if actor.health > 0 and not actor.get("danger", {}).is_empty() and visible_world(actor.pos):
				friendly_danger_samples += 1
				break
	var head: Vector2 = game.room_view.screen_position(battle.player.pos, 1.8)
	if battle.phase == "combat":
		for panel in [Rect2(32, 22, 430, 78), Rect2(540, 14, 520, 88), Rect2(1208, 22, 248, 78), Rect2(1472, 29, 96, 60)]:
			if panel.has_point(head):
				player_hud_overlap_samples += 1
	if manual_steps % 120 == 0:
		vfx_samples.append({"room": battle.room_index, "phase": battle.phase, "time": battle.time, "combat_time": battle.combat_time, "quads": quads, "cores": cores, "coverage": coverage.keys(), "player_head_screen": head})


func icon_records(node: Node) -> Array:
	var records: Array = []
	var script: Script = node.get_script()
	if script != null and script.resource_path.get_file() in ["arcane_icon.gd", "artifact_icon.gd", "equipment_icon.gd"]:
		var kind: String = script.resource_path.get_file()
		var id: String = str(node.get("spell_id")) if kind == "arcane_icon.gd" else str(node.get("item_id"))
		if id != "empty" and not id.is_empty():
			var mapping: Dictionary = script.get_script_constant_map().get("PAINTED", {})
			records.append({"kind": kind, "id": id, "size": node.size, "painted": mapping.has(id), "resource_path": mapping[id].resource_path if mapping.has(id) else ""})
	for child in node.get_children():
		records.append_array(icon_records(child))
	return records


func verify_material_icons(label: String):
	var records: Array = icon_records(game.room_ui.root)
	var ids: Array = records.map(func(record): return str(record.id))
	for record in records:
		check(record.painted, "actual route UI uses painted ID " + str(record.id))
		check(record.size.x > 0 and record.size.y > 0 and record.size.x <= 160 and record.size.y <= 160, "route icon stays within intended slot " + str(record.id))
	var snapshot: Dictionary = game.room_run.get_snapshot()
	for spell in snapshot.spells:
		check(str(spell.id) in ids, "actual HUD owns matching spell icon " + str(spell.id))
	for artifact in snapshot.get("artifacts", []):
		check(str(artifact.id) in ids, "actual inventory owns matching artifact icon " + str(artifact.id))
	if snapshot.phase == "artifact":
		for choice in snapshot.get("artifact_choices", []):
			check(str(choice.id) in ids, "actual offered artifact has matching icon " + str(choice.id))
	elif snapshot.phase == "reward":
		for choice in snapshot.get("reward_choices", []):
			check(str(choice.id) in ids, "actual offered spell has matching icon " + str(choice.id))
	material_icon_records.append({"label": label, "records": records})


func menu_snap(label: String):
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image.get_size() == Vector2i(1600, 900) and image.save_png(OUT + label + ".png") == OK, "save real material menu " + label)
	captures.append(label)
	var records: Array = icon_records(game.ui.page)
	for record in records:
		check(record.painted, "actual menu uses painted " + str(record.id))
	var ids: Array = records.map(func(record): return str(record.id))
	var expected: Array = []
	if game.screen == "catalyst": expected = ["MC04", "MC05"]
	elif game.screen == "gem": expected = ["MG01", "MG02", "MG03"]
	elif game.screen == "spells":
		for spell in game.Catalog.spells(): expected.append(str(spell.id))
	elif game.screen == "artifacts":
		for artifact in game.Catalog.artifacts(): expected.append(str(artifact.id))
	elif game.screen == "prepare":
		for id in game.meta.get_state().get("equipped", {}).values():
			if not str(id).is_empty(): expected.append(str(id))
	elif game.screen in ["chest", "shop"]:
		for artifact in game.Catalog.artifacts().slice(0, 3): expected.append(str(artifact.id))
	elif game.screen == "opening": expected = ["F01", "F04", "F08"]
	elif game.screen == "reward": expected = ["F01", "F03", "F10"]
	for id in expected:
		check(str(id) in ids, "actual " + game.screen + " contains production icon " + str(id))
	menu_captures.append({"label": label, "screen": game.screen, "records": records})


func menu_material_review():
	await menu_snap("menu-00-real-home")
	await click("法术触媒")
	check(game.screen == "catalyst", "actual home navigation opens catalyst materials")
	await menu_snap("menu-01-two-painted-catalysts")
	await click("免费领取并装备")
	check(game.meta.get_state().get("equipped", {}).get("catalyst", "") == "MC04", "isolated account equips actual free catalyst")
	await click("魔力宝石")
	await menu_snap("menu-02-three-painted-gems")
	await click("免费领取并装备")
	await click("‹  返回")
	# Return navigation can retain the previous equipment tab in history.
	while game.screen != "home":
		if not await click("‹  返回"): return
	await click("法术藏书")
	await menu_snap("menu-03-ten-spell-painted-list")
	await click("‹  返回")
	await click("神器图鉴")
	await menu_snap("menu-04-artifact-painted-list")
	for id in ["P01", "G02", "U03"]:
		var selected_button: Button = null
		for button in buttons():
			if str(button.get_meta("selection_id", "")) == id:
				selected_button = button
				break
		check(selected_button != null, "real artifact catalog has " + id)
		if selected_button != null:
			var scroll = game.ui.page.get_node_or_null("CatalogList")
			if scroll != null: scroll.ensure_control_visible(selected_button)
			await process_frame
			await process_frame
			await click(selected_button.text)
			await menu_snap("menu-artifact-detail-" + id.to_lower())
	await click("‹  返回")
	await click("开始冒险     ›")
	await menu_snap("menu-05-equipped-painted-preparation")
	await click("查看界面预览")
	await menu_snap("menu-06-painted-opening-preview")
	for page in [{"button": "法术奖励", "label": "menu-07-painted-spell-reward-preview"}, {"button": "神器箱", "label": "menu-08-painted-artifact-chest-preview"}, {"button": "商店", "label": "menu-09-painted-shop-preview"}]:
		await click(str(page.button))
		await menu_snap(str(page.label))
	await click("‹  返回")
	# The route harness starts from the same real home button as the user.
	while game.screen != "home":
		if not await click("‹  返回"): return
