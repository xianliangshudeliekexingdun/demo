extends SceneTree
## Real Main/UI/input exercise. No invented snapshot, core position or cast.
const Main = preload("res://scripts/main.gd")
const OUT = "res://build/qa/lina-game-motion-20261017/"
const SAVE = "user://tests/lina_motion_visual.json"
const PREFS = "user://tests/lina_motion_display.cfg"
var game
var checks := 0
var failures := 0
var captures: Array[String] = []
var states: Array = []
var combat_records: Array = []
var recording := false
var _frame_steps := 0
var _max_actor_error := 0.0

func _initialize():
	recording = "--record-motion" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("Lina motion visual: " + message)

func motion():
	if not is_instance_valid(game.room_view): return null
	return find_motion(game.room_view)

func find_motion(parent: Node):
	for node in parent.find_children("*", "Node3D", true, false):
		if node.has_method("get_debug_state") and node.name == "LinaMotion": return node
	return null

func pose(component = null) -> Array:
	var result: Array = []
	if component == null: component = motion()
	if component == null or component.skeleton == null: return result
	for bone in component.skeleton.get_bone_count():
		result.append(component.skeleton.get_bone_pose(bone))
	return result

func changed(a: Array, b: Array) -> bool:
	if a.size() != b.size() or a.is_empty(): return false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]): return true
	return false

func record_state(label: String):
	var component = motion()
	if component == null: return
	var detail: Dictionary = component.get_debug_state()
	detail["sample"] = label
	detail["phase"] = game.room_run.phase
	detail["core_time"] = game.room_run.time
	detail["core_position"] = game.room_run.player.pos
	states.append(detail)

func buttons() -> Array:
	if is_instance_valid(game.room_ui): return game.room_ui.root.find_children("*", "Button", true, false)
	return game.ui.page.find_children("*", "Button", true, false)

func click(text: String, index: int = 0):
	var found: Array = []
	for button in buttons():
		if button.text == text and button.is_visible_in_tree(): found.append(button)
	check(found.size() > index, "clickable " + text)
	if found.size() <= index: return
	var point: Vector2 = found[index].get_global_rect().get_center() * Vector2(root.size) / Vector2(1600, 900)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame

func key(code: int, down: bool):
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	await process_frame

func step():
	game._process(1.0 / 120.0)
	_frame_steps += 1
	if game.room_run != null:
		var point: Vector2 = game.room_run.player.pos
		var expected := Vector3(point.x, 0, -point.y)
		_max_actor_error = maxf(_max_actor_error, game.room_view.actor.position.distance_to(expected))
	if recording and _frame_steps % 4 == 0: await process_frame

func tick(seconds: float):
	for i in roundi(seconds * 120): await step()
	await process_frame

func snap(label: String):
	game._refresh_room(0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() != "headless":
		check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)
		captures.append(label)
	record_state(label)

func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	DirAccess.make_dir_recursive_absolute("user://tests")
	for path in [SAVE, SAVE + ".tmp", SAVE + ".bak", PREFS]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	game = Main.new()
	game.save_path = SAVE
	game.preferences_path = PREFS
	game.room_seed = 20261017
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var menu_motion = find_motion(game.ui)
	check(menu_motion != null, "home showcase uses approved skeletal idle")
	if menu_motion != null:
		var menu_pose := pose(menu_motion)
		var menu_clock: float = menu_motion.get_debug_state().idle_time
		for i in 5: await process_frame
		check(changed(menu_pose, pose(menu_motion)) and menu_motion.get_debug_state().idle_time != menu_clock, "visible menu advances genuine idle bones")
	await click("开始冒险     ›")
	await click("进入首房试玩    ›")
	check(game.room_run != null and game.room_run.phase == "choosing", "real preparation starts first room")
	var component = motion()
	check(component != null, "real battle uses LinaMotion component")
	if component == null:
		await finish()
		return
	check(component.skeleton != null and component.skeleton.get_bone_count() == 35, "approved 35 bone skeleton is present")
	check(component.animation_player.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL and not component.animation_player.active, "automatic AnimationPlayer callbacks are disabled")
	check(component.get_debug_state().clip_names.size() == 7, "all seven approved original clips are loaded")
	var portraits: Array = []
	for node in game.room_ui.root.find_children("*", "TextureRect", true, false):
		if node.texture != null and node.name.to_lower().contains("portrait"): portraits.append(node)
	check(portraits.size() == 1, "vitals contain Lina portrait TextureRect")
	if portraits.size() == 1:
		check(portraits[0].texture.get_width() >= 128 and portraits[0].texture.get_height() >= 128, "portrait uses actual image texture")
		check(portraits[0].size == Vector2(58, 58) and portraits[0].get_parent().get_global_rect().encloses(portraits[0].get_global_rect()), "portrait stays within its actual HUD frame after texture assignment")
		var image: Image = portraits[0].texture.get_image()
		check(image != null and image.get_pixel(image.get_width() / 2, image.get_height() / 2).a > .5, "portrait subject occupies the center of the transparent texture")
	var frozen_choice: Dictionary = game.room_run.get_snapshot()
	var choice_pose := pose()
	await tick(.4)
	check(game.room_run.get_snapshot() == frozen_choice and not changed(choice_pose, pose()), "three choice page freezes gameplay and character pose")
	await snap("01-lina-portrait-choice")
	await click("选择法术", 0)
	await tick(.02)
	var idle_a := pose()
	await tick(.18)
	check(changed(idle_a, pose()) and component.get_debug_state().idle_time > 0, "idle breath uses real skeletal pose changes")
	await snap("02-idle")
	var model_transform: Transform3D = component.model.transform
	var directions := [{"key": KEY_W, "axis": 1, "sign": 1.0}, {"key": KEY_D, "axis": 0, "sign": 1.0}, {"key": KEY_S, "axis": 1, "sign": -1.0}, {"key": KEY_A, "axis": 0, "sign": -1.0}]
	for direction in directions:
		var before: Vector2 = game.room_run.player.pos
		await key(direction.key, true)
		var run_a := pose()
		await tick(.14)
		var after: Vector2 = game.room_run.player.pos
		check((after[direction.axis] - before[direction.axis]) * direction.sign > 0.01, "physical key moves core: " + OS.get_keycode_string(direction.key))
		check(component.get_debug_state().moving and component.get_debug_state().run_weight > 0.8 and changed(run_a, pose()), "moving core drives genuine run bones: " + OS.get_keycode_string(direction.key))
		check(component.model.transform.is_equal_approx(model_transform), "run cannot translate model root: " + OS.get_keycode_string(direction.key))
		if direction.key == KEY_D: await snap("03-running-right")
		await key(direction.key, false)
	await tick(.2)
	check(not component.get_debug_state().moving and component.get_debug_state().run_weight < .01, "release key blends back to idle")
	await key(KEY_ESCAPE, true)
	await key(KEY_ESCAPE, false)
	check(game.room_run.paused, "Esc pauses real game")
	var paused_core: Dictionary = game.room_run.get_snapshot()
	var paused_pose := pose()
	var paused_motion: Dictionary = component.get_debug_state()
	await tick(.6)
	for i in 3: await process_frame
	check(game.room_run.get_snapshot() == paused_core and not changed(paused_pose, pose()), "paused snapshot and every bone remain frozen")
	check(component.get_debug_state() == paused_motion, "paused animation clocks and blend weights remain frozen")
	await snap("04-paused-pose")
	await key(KEY_D, true)
	await click("继续")
	var before_gate: Vector2 = game.room_run.player.pos
	await tick(.1)
	check(game.room_run.player.pos == before_gate, "resume release gate still blocks held movement")
	await key(KEY_D, false)
	await tick(.01)
	var cast_seen := false
	var release_seen := false
	var cast_pose_changed := false
	var cast_start: Array = []
	for i in 3600:
		await step()
		var state: Dictionary = component.get_debug_state()
		if state.cast_clip in ["Lina_Cast_Enter_R", "Lina_Cast_Hold_R"] and state.cast_weight > .3:
			if not cast_seen:
				cast_seen = true
				cast_start = pose()
				await snap("05-actual-chant")
			elif changed(cast_start, pose()): cast_pose_changed = true
		if state.cast_clip == "Lina_Cast_Release_R" and not release_seen:
			release_seen = true
			await snap("06-actual-release")
		if game.room_run.phase != "combat": break
	check(cast_seen and cast_pose_changed, "actual core chant drives changing upper body cast pose")
	check(release_seen and game.room_run.casts > 0, "actual core release drives right hand release clip")
	check(game.room_run.phase == "reward" and game.room_run.kills == 2, "fireball starter still clears actual enemies")
	combat_records.append(game.room_run.get_summary())
	var reward_pose := pose()
	var reward_core: Dictionary = game.room_run.get_snapshot()
	await tick(.4)
	check(game.room_run.get_snapshot() == reward_core and not changed(reward_pose, pose()), "reward page freezes gameplay and character pose")
	await click("领取奖励")
	check(game.room_run.phase == "exit", "reward unlocks real portal phase")
	await tick(.02)
	var exit_clock: float = game.room_run.time
	var exit_a := pose()
	await tick(.15)
	check(game.room_run.time == exit_clock and changed(exit_a, pose()), "exit idle animates while combat timer remains stopped")
	await key(KEY_W, true)
	await tick(.14)
	check(component.get_debug_state().moving and component.get_debug_state().run_weight > .8 and game.room_run.time == exit_clock, "cleared room runs using actual exit movement without advancing combat clock")
	await snap("07-exit-running")
	var guard := 0
	while game.room_run.phase == "exit" and guard < 600:
		await step()
		guard += 1
	await key(KEY_W, false)
	check(game.room_run.phase == "complete" and game.room_settlement.get("ok", false), "real run walks through upper portal and settles")
	check(component.model.transform.is_equal_approx(model_transform) and _max_actor_error < .00001, "all visual poses preserve core position and model root transform")
	await snap("08-completed")
	await click("返回准备")
	for starter in [1, 2]:
		await click("进入首房试玩    ›")
		await click("选择法术", starter)
		await tick(.02)
		var next_component = motion()
		var seen := false
		for i in 3600:
			await step()
			var debug: Dictionary = next_component.get_debug_state()
			seen = seen or debug.cast_clip == "Lina_Cast_Release_R"
			if game.room_run.phase != "combat": break
		check(seen and game.room_run.casts > 0 and game.room_run.phase == "reward", "starter " + str(starter) + " uses real cast pose and clears actual enemies")
		combat_records.append(game.room_run.get_summary())
		await key(KEY_ESCAPE, true)
		await key(KEY_ESCAPE, false)
		await click("结束试玩")
		await click("返回准备")
	check(game.meta.get_state().dust == 3, "three true clears settle exactly three dust in isolated save")
	await finish()

func finish():
	var summary := {"checks": checks, "failures": failures, "captures": captures, "states": states, "combat_records": combat_records, "max_actor_position_error": _max_actor_error, "save_isolated": SAVE, "preferences_isolated": PREFS, "recording": recording}
	FileAccess.open(OUT + ("movie-results.json" if recording else "results.json"), FileAccess.WRITE).store_string(JSON.stringify(summary, "\t"))
	if is_instance_valid(game): game.queue_free()
	await process_frame
	for path in [SAVE, SAVE + ".tmp", SAVE + ".bak", PREFS]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("LINA MOTION VISUAL: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
