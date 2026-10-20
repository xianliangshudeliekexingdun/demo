extends SceneTree
## Real Main, original rules, actual UI choices and physical movement keys.
## No forged snapshot, teleported actor or posed delivery screenshot.
const Main = preload("res://scripts/main.gd")
const Meta = preload("res://scripts/core/meta_progression.gd")
const OUT = "res://build/qa/expanded-room-20261017/"
const SAVE = "user://tests/expanded_room_visual.json"
const PREFS = "user://tests/expanded_room_display.cfg"
const LOGICAL_SIZE = Vector2(1600, 900)
var game
var checks := 0
var failures := 0
var captures: Array[String] = []
var samples: Array = []
var combat_records: Array = []
var max_actor_error := 0.0
var max_projection_error := 0.0
var unsafe_samples := 0
var live_samples := 0
var navigation_samples := 0
var navigation_unsafe := 0
var resize_pause_events: Array = []
var recording := false
var frame_steps := 0

func _initialize():
	recording = "--record-expanded" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("Expanded room visual: " + message)

func buttons() -> Array:
	if is_instance_valid(game.room_ui):
		return game.room_ui.root.find_children("*", "Button", true, false)
	return game.ui.page.find_children("*", "Button", true, false)

func click(text: String, index: int = 0):
	var found: Array = []
	for button in buttons():
		if button.text == text and button.is_visible_in_tree(): found.append(button)
	check(found.size() > index, "clickable " + text)
	if found.size() <= index: return
	var point: Vector2 = found[index].get_global_rect().get_center() * Vector2(root.size) / LOGICAL_SIZE
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

func sample_live():
	if game.room_run == null: return
	var view = game.room_view
	var point: Vector2 = game.room_run.player.pos
	max_actor_error = maxf(max_actor_error, view.actor.position.distance_to(Vector3(point.x, 0, -point.y)))
	for height in [0.0, 0.055, 0.7, 1.45]:
		var expected: Vector2 = view.camera.unproject_position(Vector3(point.x, height, -point.y)) * view.size / LOGICAL_SIZE
		max_projection_error = maxf(max_projection_error, expected.distance_to(view.screen_position(point, height)))
	var foot: Vector2 = view.screen_position(point, 0.0)
	var head: Vector2 = view.screen_position(point, 1.45)
	# A following camera must keep Lina readable between top status and bottom slots.
	# It deliberately does not promise that every architecture vertex fits one screen.
	var safe := Rect2(100, 142, 1400, 590)
	if not safe.has_point(foot) or not safe.has_point(head): unsafe_samples += 1
	live_samples += 1
	if view.has_method("get_navigation_markers"):
		for marker in view.get_navigation_markers():
			navigation_samples += 1
			if not Rect2(105, 170, 1390, 540).grow(.1).has_point(marker.point): navigation_unsafe += 1

func step():
	game._process(1.0 / 120.0)
	sample_live()
	frame_steps += 1
	if recording and frame_steps % 4 == 0: await process_frame

func tick(seconds: float):
	for i in roundi(seconds * 120): await step()
	await process_frame

func record_sample(label: String):
	var detail := {"sample": label, "phase": game.room_run.phase, "paused": game.room_run.paused,
		"core_time": game.room_run.time, "player": game.room_run.player.pos,
		"camera_position": game.room_view.camera.position,
		"camera_transform": game.room_view.camera.transform,
		"player_screen_foot": game.room_view.screen_position(game.room_run.player.pos, 0.0),
		"player_screen_head": game.room_view.screen_position(game.room_run.player.pos, 1.45)}
	if game.room_view.has_method("get_camera_debug_state"):
		detail["follow_debug"] = game.room_view.get_camera_debug_state()
	if game.room_view.has_method("get_navigation_markers"):
		detail["navigation_markers"] = game.room_view.get_navigation_markers()
	samples.append(detail)

func snap(label: String, resolution: Vector2i):
	var was_paused: bool = game.room_run.paused
	DisplayServer.window_set_size(resolution)
	await process_frame
	await process_frame
	# Window resizing can genuinely transfer focus on Windows. Preserve the
	# production auto-pause protection and resume through its real UI only.
	if not was_paused and game.room_run.paused and game.room_result_reason.is_empty():
		resize_pause_events.append({"capture": label, "resolution": resolution, "phase": game.room_run.phase, "core_time": game.room_run.time})
		await click("继续试炼")
		for code in [KEY_A, KEY_D, KEY_W, KEY_S]: await key(code, false)
		game._process(0)
	game._refresh_room(0)
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.size == resolution, "actual viewport size " + str(resolution))
	if DisplayServer.get_name() != "headless":
		var image: Image = root.get_texture().get_image()
		check(image.get_size() == resolution and image.save_png(OUT + label + ".png") == OK, "actual Godot capture " + label)
		captures.append(label)
	record_sample(label)

func pair(label: String):
	await snap(label + "-1280", Vector2i(1280, 720))
	await snap(label + "-1600", Vector2i(1600, 900))
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await process_frame

func walk_to_z(target: float, limit: int = 1800):
	var code := KEY_W if game.room_run.player.pos.y < target else KEY_S
	var direction := 1.0 if code == KEY_W else -1.0
	await key(code, true)
	var guard := 0
	while (target - game.room_run.player.pos.y) * direction > .025 and guard < limit and game.room_run.phase in ["combat", "exit"]:
		await step()
		guard += 1
	await key(code, false)
	check(guard < limit, "real WASD reaches z " + str(target))
	await tick(.25)

func walk_to_x(target: float, limit: int = 1800):
	var code := KEY_D if game.room_run.player.pos.x < target else KEY_A
	var direction := 1.0 if code == KEY_D else -1.0
	await key(code, true)
	var guard := 0
	while (target - game.room_run.player.pos.x) * direction > .025 and guard < limit and game.room_run.phase == "exit":
		await step()
		guard += 1
	await key(code, false)
	check(guard < limit, "real WASD reaches x " + str(target))
	await tick(.35)

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
	# Native window creation and the first stretch/layout pass are asynchronous.
	# Wait for a real drawn frame and focus this test window before mouse input.
	root.grab_focus()
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	check(root.size == Vector2i(1280, 720), "initial native viewport is ready before mouse input")
	await click("开始冒险     ›")
	if game.screen != "prepare":
		for i in 2: await process_frame
		await click("开始冒险     ›")
	check(game.screen == "prepare", "real home mouse click reaches preparation")
	await click("进入首房试玩    ›")
	check(game.room_run != null and game.room_run.phase == "choosing", "real preparation opens room")
	if game.room_run == null:
		await finish()
		return
	check(game.room_run.room_size == Vector2(18, 28), "current first room is 18 by 28 metres")
	check(game.room_run.player.pos == Vector2(0, -12.5), "entry starts at authored southern approach")
	check(game.room_run.portal.pos == Vector2(0, 13), "portal uses authored northern center")
	check(game.room_run.blocks.size() == 2 and game.room_run.blocks[0].center == Vector2(-5.25, 0) and game.room_run.blocks[1].center == Vector2(5.25, 0), "two original covers occupy wider authored spacing")
	check(game.room_view.camera.name == "FollowRoomCamera" and game.room_view.has_method("get_camera_debug_state"), "actual stage uses inspectable following perspective camera")
	check(game.room_view.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "perspective camera preserves room depth")
	check(game.room_view.world.find_children("*", "CollisionObject3D", true, false).is_empty() and game.room_view.world.find_children("*", "CollisionShape3D", true, false).is_empty(), "surroundings do not add physical collision or gameplay bodies")
	var surroundings = game.room_view.world.find_child("CourtyardSurroundings", true, false)
	check(surroundings != null, "outer ruins and entry approach are actually attached to the stage")
	if surroundings != null:
		var decoration_meshes: Array = surroundings.find_children("*", "MeshInstance3D", true, false)
		check(decoration_meshes.size() == 4, "outer ruins use four merged native geometry groups")
		for expected in ["ContinuousAncientGround", "MergedOuterMasonry", "OuterMossAndRootStains", "FadedOuterStoneInlay"]:
			check(surroundings.find_child(expected, true, false) != null, "actual surrounding mesh " + expected)
	var choice_state: Dictionary = game.room_run.get_snapshot()
	var choice_camera: Transform3D = game.room_view.camera.transform
	await tick(.3)
	check(game.room_run.get_snapshot() == choice_state and game.room_view.camera.transform.is_equal_approx(choice_camera), "choice freezes simulation and camera")
	await click("选择法术", 0)
	await tick(.04)
	var entry_camera: Vector3 = game.room_view.camera.position
	await pair("01-entrance-approach")
	await tick(.9)
	check(game.room_run.actors.size() == 2, "two original slimes spawn through actual warning")
	var combat_captured := false
	var guard := 0
	while game.room_run.phase == "combat" and guard < 4800:
		await step()
		guard += 1
		if game.room_run.casts > 0 and not combat_captured:
			combat_captured = true
			await pair("02-live-combat")
	check(combat_captured and game.room_run.casts > 0, "real automatic fireball produced combat capture")
	check(game.room_run.phase == "reward" and game.room_run.kills == 2, "true automatic combat clears two slimes")
	combat_records.append(game.room_run.get_summary())
	if game.room_run.phase != "reward":
		await finish()
		return
	check(game.room_run.clear_count == 1 and game.room_run.player.shield == game.room_run.player.max_shield, "clear ledger and shield restore remain intact")
	check(game.meta.get_state().dust == 0 and game.room_run.portal.visible and not game.room_run.portal.usable, "clear waits for real reward before using portal or settling")
	await click("领取奖励")
	check(game.room_run.phase == "exit" and game.room_run.portal.usable, "real reward unlocks portal")
	await tick(.02)
	check(game.room_view.has_method("get_navigation_markers"), "follow camera exposes read-only offscreen navigation")
	if game.room_view.has_method("get_navigation_markers"):
		var entry_markers: Array = game.room_view.get_navigation_markers()
		check(entry_markers.any(func(marker): return marker.kind == "portal"), "portal offscreen at entry receives an honest navigation marker")
		for marker in entry_markers:
			check(float(marker.distance) > 20 and not Rect2(Vector2.ZERO, LOGICAL_SIZE).has_point(marker.projected), "entry portal marker reports actual offscreen position and distance")
	var exit_time: float = game.room_run.time
	await walk_to_z(-5.5)
	var travel_camera: Vector3 = game.room_view.camera.position
	check(travel_camera.distance_to(entry_camera) > 3.0 and travel_camera.z < entry_camera.z - 3.0, "camera actually translates north with real player travel")
	await pair("03-southern-courtyard")
	await key(KEY_W, true)
	await tick(.18)
	await key(KEY_ESCAPE, true)
	await key(KEY_ESCAPE, false)
	check(game.room_run.paused, "Esc pauses live exit movement")
	var paused_snapshot: Dictionary = game.room_run.get_snapshot()
	var paused_camera: Transform3D = game.room_view.camera.transform
	await tick(.7)
	check(game.room_run.get_snapshot() == paused_snapshot and game.room_view.camera.transform.is_equal_approx(paused_camera), "pause freezes movement and following camera even while W held")
	await snap("04-paused-follow-camera-1280", Vector2i(1280, 720))
	await click("继续试炼")
	var before_gate: Vector2 = game.room_run.player.pos
	await tick(.15)
	check(game.room_run.player.pos == before_gate, "resume still requires releasing held W")
	await key(KEY_W, false)
	await tick(.02)
	await walk_to_z(0)
	await pair("05-central-battle-court")
	# Lateral camera response is tested by real movement along the clear central aisle.
	var center_camera: Vector3 = game.room_view.camera.position
	await key(KEY_D, true)
	await tick(.45)
	await key(KEY_D, false)
	await tick(.35)
	var side_camera: Vector3 = game.room_view.camera.position
	check(game.room_run.player.pos.x > 2 and side_camera.x > center_camera.x + .2, "camera also follows actual horizontal travel")
	await key(KEY_A, true)
	await tick(.45)
	await key(KEY_A, false)
	await tick(.35)
	check(absf(game.room_run.player.pos.x) < .05, "real return movement restores open central route")
	# Test close to the real boundaries, going around both physical covers.
	# Northward cross-room travel occurs below the portal trigger radius.
	var x_limit: float = game.room_run.room_size.x * .5 - game.room_run.player.radius - .02
	var z_limit: float = game.room_run.room_size.y * .5 - game.room_run.player.radius - .02
	await walk_to_z(-2)
	await walk_to_x(x_limit)
	check(game.room_view.camera.position.x > 4.5, "east wall movement reaches horizontal camera clamp")
	record_sample("east-wall-real-movement")
	await pair("05b-east-wall-navigation")
	await walk_to_z(-z_limit)
	record_sample("southeast-corner-real-movement")
	await walk_to_x(-x_limit)
	check(game.room_view.camera.position.x < -4.5, "west wall movement reaches horizontal camera clamp")
	record_sample("southwest-corner-real-movement")
	await walk_to_z(z_limit)
	record_sample("northwest-corner-real-movement")
	await walk_to_z(10.8)
	await walk_to_x(x_limit)
	await walk_to_z(z_limit)
	record_sample("northeast-corner-real-movement")
	await walk_to_z(6)
	await walk_to_x(0)
	check(absf(game.room_run.player.pos.x) < .05 and absf(game.room_view.camera.position.x) < .2, "real return to center restores camera after both wall clamps")
	await walk_to_z(6)
	await pair("06-northern-courtyard")
	await walk_to_z(10.8)
	await tick(.6)
	check(game.room_run.phase == "exit" and game.room_run.portal.usable, "portal approach stays playable before trigger")
	check(game.room_run.time == exit_time, "walking the longer room does not advance cleared combat timer")
	check(game.room_view.camera.position.distance_to(entry_camera) > 12, "long room is traversed through camera travel instead of one screen framing")
	await pair("07-open-portal-approach")
	var before_view: Dictionary = game.room_run.get_snapshot()
	for i in 12: game._refresh_room(0)
	check(game.room_run.get_snapshot() == before_view, "view refresh cannot mutate rules, clear or reward")
	await key(KEY_W, true)
	guard = 0
	while game.room_run.phase == "exit" and guard < 600:
		await step()
		guard += 1
	await key(KEY_W, false)
	check(game.room_run.phase == "complete" and game.room_settlement.get("ok", false), "walking into actual northern portal completes and settles")
	if game.room_run.phase != "complete":
		await finish()
		return
	check(game.meta.get_state().dust == 1 and not game.meta.is_in_run(), "one actual clear still credits exactly one dust")
	await snap("08-real-completion-1600", Vector2i(1600, 900))
	var reopened = Meta.new(SAVE)
	check(reopened.load_state().ok and reopened.get_state().dust == 1, "true settlement persists in isolated save")
	game._settle_room()
	check(game.meta.get_state().dust == 1, "repeated settlement stays idempotent")
	await click("返回准备")
	for starter in [1, 2]:
		await click("进入首房试玩    ›")
		await click("选择法术", starter)
		await tick(.02)
		guard = 0
		while game.room_run.phase == "combat" and guard < 4800:
			await step()
			guard += 1
		check(game.room_run.phase == "reward" and game.room_run.kills == 2 and game.room_run.casts > 0, "starter " + str(starter) + " clears expanded room through true automatic combat")
		combat_records.append(game.room_run.get_summary())
		await key(KEY_ESCAPE, true)
		await key(KEY_ESCAPE, false)
		await click("结束试玩")
		await click("返回准备")
	check(game.meta.get_state().dust == 3, "three actual starter clears settle three dust only")
	check(max_actor_error < .00001, "every displayed actor position matches true core metres")
	check(max_projection_error < .00001, "moving-camera overlay uses exactly the camera projection")
	check(unsafe_samples == 0 and live_samples > 1000, "Lina head and feet stay within HUD safe area throughout real traversal")
	check(navigation_samples > 0 and navigation_unsafe == 0, "offscreen navigation stays inside HUD-safe marker boundaries throughout real traversal")
	await finish()

func finish():
	for code in [KEY_A, KEY_D, KEY_W, KEY_S]: await key(code, false)
	var summary := {"checks": checks, "failures": failures, "captures": captures, "samples": samples,
		"combat_records": combat_records, "max_actor_position_error": max_actor_error,
		"max_overlay_projection_error": max_projection_error, "unsafe_player_screen_samples": unsafe_samples,
		"live_projection_samples": live_samples, "save_isolated": SAVE, "preferences_isolated": PREFS,
		"navigation_samples": navigation_samples, "unsafe_navigation_samples": navigation_unsafe,
		"resize_focus_pause_events": resize_pause_events,
		"capture_provenance": "Real Main, actual UI clicks, actual automatic combat and WASD movement; no forged snapshot, teleport, image generation or post-processing.",
		"recording": recording}
	FileAccess.open(OUT + ("movie-results.json" if recording else "results.json"), FileAccess.WRITE).store_string(JSON.stringify(summary, "\t"))
	if is_instance_valid(game): game.queue_free()
	await process_frame
	for path in [SAVE, SAVE + ".tmp", SAVE + ".bak", PREFS]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("EXPANDED ROOM VISUAL: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
