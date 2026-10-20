extends SceneTree
## Actual Main + UI + WASD, using the real automatic-spell simulation.
## This test never changes actors, health, damage, positions, phases or snapshots.

const Main = preload("res://scripts/main.gd")
const OUT := "res://build/qa/courtyard-route-20261017/visual/"
const SAVE := "user://tests/courtyard_route_visual.json"
const PREFS := "user://tests/courtyard_route_display.cfg"
const LOGICAL_SIZE := Vector2(1600, 900)
const EXPECTED_COUNTS := [2, 3, 4, 4, 5, 6, 4, 6, 7, 5, 7, 8, 6, 7, 9]
const REWARD_ROOMS := [1, 3, 6, 9, 12, 15]
const CAPTURE_ROOMS := [2, 3, 4, 6, 7, 8, 9, 11, 12, 15]

var game
var checks: int = 0
var failures: int = 0
var captures: Array[String] = []
var samples: Array = []
var rooms: Array = []
var transitions: Array = []
var focus_events: Array = []
var max_actor_error: float = 0.0
var max_projection_error: float = 0.0
var max_live: int = 0
var projection_samples: int = 0
var unsafe_player_samples: int = 0
var premature_clear_samples: int = 0
var over_cap_samples: int = 0
var navigation_samples: int = 0
var unsafe_navigation_samples: int = 0
var source_stat_mismatch_samples: int = 0
var manual_steps: int = 0
var cooldown_transition_samples: int = 0
var account_before: Dictionary = {}
var save_bytes_before: String = ""
var production_before: Dictionary = {}
var final_summary: Dictionary = {}
var _last_sample_room: int = 0
var _pressed: Dictionary = {}


func _initialize():
	call_deferred("run")


func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("Courtyard route visual: " + label)


func buttons() -> Array:
	if is_instance_valid(game.room_ui):
		return game.room_ui.root.find_children("*", "Button", true, false)
	return game.ui.page.find_children("*", "Button", true, false)


func click(text: String, index: int = 0) -> bool:
	var matches: Array = []
	for button in buttons():
		if button.text == text and button.is_visible_in_tree() and not button.disabled:
			matches.append(button)
	check(matches.size() > index, "actual visible UI button: " + text)
	if matches.size() <= index:
		return false
	var point: Vector2 = matches[index].get_global_rect().get_center() * Vector2(root.size) / LOGICAL_SIZE
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	return true


func key(code: int, down: bool):
	_pressed[code] = down
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	await process_frame


func alive_count() -> int:
	var alive: int = 0
	for enemy in game.room_run.actors:
		if enemy.health > 0.0:
			alive += 1
	return alive


func sample_live():
	if game.room_run == null or not is_instance_valid(game.room_view) or not is_instance_valid(game.room_view.actor):
		return
	var battle = game.room_run
	var view = game.room_view
	var point: Vector2 = battle.player.pos
	max_actor_error = maxf(max_actor_error, view.actor.position.distance_to(Vector3(point.x, 0, -point.y)))
	for height in [0.0, 0.055, 0.7, 1.45]:
		var expected: Vector2 = view.camera.unproject_position(Vector3(point.x, height, -point.y)) * view.size / LOGICAL_SIZE
		max_projection_error = maxf(max_projection_error, expected.distance_to(view.screen_position(point, height)))
	var safe := Rect2(100, 142, 1400, 590)
	if not safe.has_point(view.screen_position(point, 0.0)) or not safe.has_point(view.screen_position(point, 1.45)):
		unsafe_player_samples += 1
	projection_samples += 1
	var alive := alive_count()
	max_live = maxi(max_live, alive)
	if alive > int(battle._ordinary.spawn.alive_cap_by_normal_stat_stage[0]):
		over_cap_samples += 1
	if battle.phase in ["reward", "exit", "complete"] and battle._spawned_total != battle._spawn_total:
		premature_clear_samples += 1
	var original: Dictionary = battle._base.normal_stages[0].stats.M01
	for enemy in battle.actors:
		if enemy.type != "M01" or enemy.max_health != original.health or enemy.damage != original.damage or enemy.radius != battle._runtime.M01.radius:
			source_stat_mismatch_samples += 1
	if view.has_method("get_navigation_markers"):
		for marker in view.get_navigation_markers():
			navigation_samples += 1
			if not Rect2(105, 170, 1390, 540).grow(.1).has_point(marker.point):
				unsafe_navigation_samples += 1
	_last_sample_room = int(battle.room_index)


func step():
	game._process(1.0 / 120.0)
	sample_live()
	manual_steps += 1
	# Render regularly so this remains a real responsive Godot application while
	# fixed-step combat is exercised faster than real time.
	if manual_steps % 240 == 0:
		await process_frame


func tick(seconds: float):
	for index in roundi(seconds * 120.0):
		await step()
	await process_frame


func resume_external_focus(label: String):
	if game.room_run == null or not game.room_run.paused or not game.room_result_reason.is_empty():
		return
	var held: Array = []
	for code in _pressed:
		if bool(_pressed[code]):
			held.append(code)
	focus_events.append({"where": label, "room": game.room_run.room_index,
		"phase": game.room_run.phase, "time": game.room_run.time})
	await click("继续试炼")
	for code in [KEY_A, KEY_D, KEY_W, KEY_S]:
		await key(code, false)
	game._process(0)
	for code in held:
		await key(code, true)


func record_sample(label: String):
	if game.room_run == null:
		return
	var battle = game.room_run
	var snapshot: Dictionary = battle.get_snapshot()
	samples.append({"sample": label, "room": battle.room_index,
		"revision": battle.room_revision, "phase": battle.phase,
		"player": battle.player.pos, "health": battle.player.health,
		"core_time": battle.time, "room_time": battle.room_time,
		"room_name": snapshot.room_name, "template_id": snapshot.template_id,
		"source_kind": snapshot.source_kind, "room_size": snapshot.room_size,
		"alive": alive_count(), "spawn_total": snapshot.spawn_total,
		"spawned_total": snapshot.spawned_total, "batch_index": snapshot.batch_index,
		"camera": game.room_view.get_camera_debug_state(),
		"spells": battle.spells.duplicate(true)})


func snap(label: String, resolution := Vector2i(1600, 900), stage_only: bool = false):
	var was_paused: bool = game.room_run.paused if game.room_run != null else false
	DisplayServer.window_set_size(resolution)
	await process_frame
	await process_frame
	if game.room_run != null and not was_paused and game.room_run.paused:
		await resume_external_focus("capture-resize: " + label)
	if game.room_run != null:
		game._refresh_room(0)
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.size == resolution, "real native screenshot resolution " + label)
	if DisplayServer.get_name() != "headless":
		var image: Image = root.get_texture().get_image()
		check(image.get_size() == resolution and image.save_png(OUT + label + ".png") == OK, "save genuine Main screenshot " + label)
		captures.append(label)
		if stage_only and game.room_run != null:
			var stage_image: Image = game.room_view.get_room_viewport().get_texture().get_image()
			check(stage_image.save_png(OUT + label + "-stage.png") == OK, "save native 3D SubViewport " + label)
			captures.append(label + "-stage")
	record_sample(label)


func choose_reward() -> bool:
	var selected_index: int = -1
	for preferred in ["F01", "F08", "F04"]:
		for index in game.room_run.reward_choices.size():
			if game.room_run.reward_choices[index].id == preferred:
				selected_index = index
				break
		if selected_index >= 0:
			break
	check(selected_index >= 0, "real reward offers an implemented usable spell")
	if selected_index < 0:
		return false
	return await click("领取奖励", selected_index)


func walk_to_z(target: float, room_id: int, limit: int = 2400) -> bool:
	var battle = game.room_run
	var code := KEY_W if battle.player.pos.y < target else KEY_S
	var sign_direction := 1.0 if code == KEY_W else -1.0
	await key(code, true)
	var steps: int = 0
	while game.room_run.room_index == room_id and game.room_run.phase == "exit" and (target - game.room_run.player.pos.y) * sign_direction > .025 and steps < limit:
		if game.room_run.paused:
			await resume_external_focus("walk room %d" % room_id)
		await step()
		steps += 1
	await key(code, false)
	check(steps < limit, "real WASD reaches room %d z %.2f" % [room_id, target])
	return steps < limit


func walk_to_x(target: float, room_id: int, limit: int = 1800) -> bool:
	var code := KEY_D if game.room_run.player.pos.x < target else KEY_A
	var sign_direction := 1.0 if code == KEY_D else -1.0
	await key(code, true)
	var steps: int = 0
	while game.room_run.room_index == room_id and game.room_run.phase == "exit" and (target - game.room_run.player.pos.x) * sign_direction > .025 and steps < limit:
		if game.room_run.paused:
			await resume_external_focus("lateral room %d" % room_id)
		await step()
		steps += 1
	await key(code, false)
	check(steps < limit, "real WASD reaches room %d x %.2f" % [room_id, target])
	await tick(.35)
	return steps < limit


func pause_exercise():
	await key(KEY_W, true)
	await tick(.15)
	await key(KEY_ESCAPE, true)
	await key(KEY_ESCAPE, false)
	check(game.room_run.paused, "Esc pauses actual route with W held")
	var frozen: Dictionary = game.room_run.get_snapshot()
	var camera: Transform3D = game.room_view.camera.transform
	await tick(.7)
	check(game.room_run.get_snapshot() == frozen and game.room_view.camera.transform.is_equal_approx(camera), "route pause freezes rules, pose drive and follow camera")
	await snap("05-room-04-paused-1280", Vector2i(1280, 720))
	await click("继续试炼")
	var before: Vector2 = game.room_run.player.pos
	await tick(.15)
	check(game.room_run.player.pos == before, "resume release gate blocks held W")
	await key(KEY_W, false)
	await tick(.02)


func compare_transition(before: Dictionary, room_id: int):
	var battle = game.room_run
	var after: Dictionary = battle.get_snapshot()
	check(battle.room_index == room_id + 1 and battle.room_revision == int(before.room_revision) + 1 and battle.phase == "combat", "portal advances exactly one real room after %d" % room_id)
	check(battle.player.health == before.player.health and battle.player.shield == before.player.shield, "health and shield persist through room %d portal" % room_id)
	check(battle.spells == before.spells, "learned spells, levels and real remaining cooldown persist after room %d" % room_id)
	check(battle.time == before.time and battle.kills == before.kills and battle.clear_count == before.clear_count, "portal preserves global time and actual counters after room %d" % room_id)
	check(absf(battle.room_time) < .00001 and battle.actors.is_empty() and battle.projectiles.is_empty() and not battle.spirit.active, "room %d only resets room transients" % (room_id + 1))
	check(not battle.portal.visible and not battle.portal.usable, "new room %d portal starts locked" % (room_id + 1))
	var geometry: Dictionary = after.room_geometry
	check(battle.player.pos == Vector2(geometry.entry_player_center[0], geometry.entry_player_center[1]), "room %d uses authored new entrance" % (room_id + 1))
	var debug: Dictionary = game.room_view.get_camera_debug_state()
	check(debug.focus.distance_to(debug.target) < .00001 and debug.room_size == battle.room_size, "camera immediately resets to new room %d entrance without cross-map glide" % (room_id + 1))
	for spell in before.spells:
		if float(spell.remaining) > 0.0:
			cooldown_transition_samples += 1
	transitions.append({"from": room_id, "to": battle.room_index,
		"before_health": before.player.health, "after_health": battle.player.health,
		"before_spells": before.spells, "after_spells": battle.spells.duplicate(true),
		"camera": debug, "new_entry": battle.player.pos})


func traverse_route() -> bool:
	var expected_kills: int = 0
	for room_id in range(1, 16):
		var battle = game.room_run
		check(battle.room_index == room_id and battle.phase == "combat", "real portal path reaches combat room %d" % room_id)
		if battle.room_index != room_id or battle.phase != "combat":
			return false
		var snapshot: Dictionary = battle.get_snapshot()
		check(snapshot.spawn_total == EXPECTED_COUNTS[room_id - 1] and snapshot.room_total == 15, "room %d HUD state uses configured count and fifteen-map scope" % room_id)
		check(not snapshot.account_rewards and snapshot.preview_only and snapshot.spike_profile == "off" and not snapshot.shop_after, "map trial remains separate from unimplemented combat and account content")
		if room_id == 2:
			await snap("02-room-02-entry-1280", Vector2i(1280, 720))
		var guard: int = 0
		while battle.phase == "combat" and guard < 120 * 90:
			if battle.paused:
				await resume_external_focus("combat room %d" % room_id)
			await step()
			guard += 1
		check(battle.phase in ["reward", "exit"] and battle.player.health > 0.0, "automatic combat naturally clears room %d" % room_id)
		if battle.phase not in ["reward", "exit"]:
			return false
		expected_kills += EXPECTED_COUNTS[room_id - 1]
		check(battle.kills == expected_kills and battle._spawned_total == battle._spawn_total, "room %d defeats every configured batch" % room_id)
		check(battle.clear_count == room_id and battle.cleared_rooms == range(1, room_id + 1), "room %d writes actual sequential clear ledger once" % room_id)
		check((battle.phase == "reward") == (room_id in REWARD_ROOMS), "room %d reward cadence is exact" % room_id)
		rooms.append(battle.get_summary())
		if battle.phase == "reward":
			var frozen: Dictionary = battle.get_snapshot()
			await tick(.3)
			check(battle.get_snapshot() == frozen, "room %d real growth page freezes rules and cooldown" % room_id)
			if not await choose_reward():
				return false
		await tick(.02)
		check(battle.phase == "exit" and battle.portal.visible and battle.portal.usable, "room %d opens usable portal after actual required reward" % room_id)
		if room_id == 4:
			await pause_exercise()
		var frozen_time: float = battle.time
		# All authored maps keep their central aisle open. Real keys traverse it;
		# the test never teleports the player to compose a screenshot.
		if room_id in CAPTURE_ROOMS:
			if not await walk_to_z(0.0, room_id):
				return false
			await tick(.45)
			await snap("room-%02d-%s-center-1600" % [room_id, snapshot.template_id], Vector2i(1600, 900), room_id in [7, 8, 11])
			if room_id in [4, 12]:
				await snap("room-%02d-center-1280" % room_id, Vector2i(1280, 720))
			if room_id == 11:
				var east_limit: float = battle.room_size.x * .5 - battle.player.radius - .04
				await walk_to_x(east_limit, room_id)
				check(game.room_view.camera.position.x > 6.0, "22-metre court follows actual movement to its wider side wall")
				await snap("room-11-wide-east-ruins-1280", Vector2i(1280, 720))
				await walk_to_x(0.0, room_id)
		var approach: float = battle.portal.pos.y - float(battle.portal.radius) - 1.2
		if not await walk_to_z(approach, room_id):
			return false
		await tick(.35)
		if room_id in [6, 9, 12, 15]:
			await snap("room-%02d-open-portal-1600" % room_id, Vector2i(1600, 900))
		check(battle.time == frozen_time, "walking cleared map %d does not advance combat clocks" % room_id)
		var before: Dictionary = battle.get_snapshot()
		var original_core: Dictionary = before.duplicate(true)
		for index in 4:
			game._refresh_room(0)
		check(battle.get_snapshot() == original_core, "display refresh cannot mutate room %d core" % room_id)
		await key(KEY_W, true)
		guard = 0
		while battle.room_index == room_id and battle.phase == "exit" and guard < 600:
			if battle.paused:
				await resume_external_focus("portal room %d" % room_id)
			await step()
			guard += 1
		await key(KEY_W, false)
		check(guard < 600, "physical portal contact occurs in room %d" % room_id)
		if room_id < 15:
			compare_transition(before, room_id)
			if battle.room_index != room_id + 1:
				return false
			# A refresh/held input cannot consume a second room transition.
			game._refresh_room(0)
			check(battle.room_index == room_id + 1 and battle.room_revision == room_id + 1, "room transition cannot repeat from UI refresh")
		else:
			check(battle.phase == "complete" and game.room_settlement.get("ok", false), "actual fifteenth portal completes local map trial")
	return true


func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	DirAccess.make_dir_recursive_absolute("user://tests")
	for path in [SAVE, SAVE + ".tmp", SAVE + ".bak", PREFS]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for path in ["user://meta_progression_v1.json", "user://display.cfg"]:
		production_before[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	DisplayServer.window_set_size(Vector2i(1280, 720))
	game = Main.new()
	game.save_path = SAVE
	game.preferences_path = PREFS
	game.room_seed = 83
	root.add_child(game)
	game.set_process(false)
	root.grab_focus()
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	check(game.load_error.is_empty(), "actual Main and isolated account initialize")
	account_before = game.meta.get_state()
	save_bytes_before = FileAccess.get_file_as_string(SAVE)
	await click("开始冒险     ›")
	if game.screen != "prepare":
		for frame in 2:
			await process_frame
		await click("开始冒险     ›")
	check(game.screen == "prepare", "real home click reaches preparation")
	await click("进入前期路线    ›")
	check(game.room_run != null and game.room_run.has_method("_route_metadata") and game.room_run.phase == "choosing", "actual preparation button starts fifteen-room map trial")
	if game.room_run == null or not game.room_run.has_method("_route_metadata"):
		await finish()
		return
	check(game.meta.is_in_run() and game.meta.get_run_snapshot().preview_only, "map trial locks equipment using non-account run")
	await snap("01-actual-route-start-1280", Vector2i(1280, 720))
	await click("选择法术", 0)
	await tick(.02)
	var completed: bool = await traverse_route()
	check(completed, "continuous UI-driven fifteen-map traversal completes")
	if completed:
		final_summary = game.room_run.get_summary()
		check(final_summary.cleared_rooms == range(1, 16) and final_summary.clear_count == 15, "final ledger contains all fifteen actual clears")
		check(final_summary.kills == 83 and absf(float(final_summary.damage_dealt) - 14940.0) < .0001, "all 83 original-health M01 die to actual implemented spells")
		check(final_summary.dust == 0 and not final_summary.account_rewards and final_summary.preview_only, "no invented dust or boss rewards enter account")
		check(not game.meta.is_in_run() and game.meta.get_state() == account_before and FileAccess.get_file_as_string(SAVE) == save_bytes_before, "natural route completion leaves isolated account state and bytes unchanged")
		await snap("16-actual-fifteen-room-completion-1600", Vector2i(1600, 900))
		await click("返回准备")
		await click("进入前期路线    ›")
		await click("选择法术", 0)
		await tick(.02)
		var guard: int = 0
		while game.room_run.phase == "combat" and guard < 120 * 90:
			if game.room_run.paused:
				await resume_external_focus("abandon exercise")
			await step()
			guard += 1
		check(game.room_run.clear_count == 1, "abandon exercise first earns one true local clear")
		await key(KEY_ESCAPE, true)
		await key(KEY_ESCAPE, false)
		await click("结束试玩")
		check(game.room_settlement.get("ok", false) and not game.meta.is_in_run(), "abandon actual route releases equipment lock")
		check(game.meta.get_state() == account_before and FileAccess.get_file_as_string(SAVE) == save_bytes_before, "abandon after actual clear still cannot award account currency")
	check(max_actor_error < .00001 and projection_samples > 1000, "actual actor tracks core position across fifteen camera/geometry revisions")
	check(max_projection_error < .00001, "moving room overlay exactly follows native Camera3D projection")
	check(unsafe_player_samples == 0, "Lina head and feet stay in HUD safe area during actual traversal")
	check(over_cap_samples == 0 and max_live <= 5, "all actual reinforcement activations respect original alive cap")
	check(premature_clear_samples == 0, "no map clears while a configured batch remains pending")
	check(source_stat_mismatch_samples == 0, "every displayed M01 retains original health damage and radius")
	check(navigation_samples > 0 and unsafe_navigation_samples == 0, "actual offscreen directions stay inside HUD-safe bounds")
	check(transitions.size() == 14 and cooldown_transition_samples > 0, "all fourteen real transitions preserve nonzero real cooldown samples")
	await finish()


func finish():
	for code in [KEY_A, KEY_D, KEY_W, KEY_S]:
		await key(code, false)
	for path in production_before:
		var after: String = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
		check(after == production_before[path], "production account/preferences untouched: " + path)
	var result := {"checks": checks, "failures": failures, "captures": captures,
		"rooms": rooms, "transitions": transitions, "samples": samples,
		"final_summary": final_summary, "focus_events": focus_events,
		"max_actor_position_error": max_actor_error, "max_overlay_projection_error": max_projection_error,
		"projection_samples": projection_samples, "unsafe_player_samples": unsafe_player_samples,
		"maximum_alive_enemies": max_live, "over_cap_samples": over_cap_samples,
		"premature_clear_samples": premature_clear_samples, "source_stat_mismatch_samples": source_stat_mismatch_samples,
		"navigation_samples": navigation_samples, "unsafe_navigation_samples": unsafe_navigation_samples,
		"cooldown_transition_samples": cooldown_transition_samples,
		"save_isolated": SAVE, "preferences_isolated": PREFS,
		"production_before": production_before,
		"capture_provenance": "Native Godot Main and SubViewport pixels; actual UI clicks, automatic spells and physical WASD portal traversal. No snapshot, actor position, HP, damage or phase changes, generated delivery images, composites or post-processing."}
	FileAccess.open(OUT + "results.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	for path in [SAVE, SAVE + ".tmp", SAVE + ".bak", PREFS]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("COURTYARD ROUTE VISUAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
