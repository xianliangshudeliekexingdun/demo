extends SceneTree
## Native Main/UI exercise. Display fixtures are explicitly separate from live core.

const Main = preload("res://scripts/main.gd")
const Catalog = preload("res://scripts/ui/grimoire_catalog.gd")
const T = preload("res://scripts/ui/atelier_theme.gd")
const OUT = "res://build/qa/compact-choice-20261018/"
const SAVE = "user://tests/compact_choice_visual.json"
const PREFS = "user://tests/compact_choice_visual_display.cfg"
const LOGICAL = Vector2(1600, 900)
var game
var checks: int = 0
var failures: Array = []
var captures: Array = []
var records: Array = []
var production_before: Dictionary = {}
var initial_snapshot: Dictionary = {}
var account_before: Dictionary = {}
var save_before: String = ""
var fixture_tag: Label
var requests: Array = []


func _initialize():
	call_deferred("run")


func check(value: bool, label: String):
	checks += 1
	if not value:
		failures.append(label)
		push_error("Compact choice visual: " + label)


func frames(count: int = 2):
	for _frame in count:
		await process_frame


func wait(seconds: float):
	await create_timer(seconds).timeout
	await frames()


func mouse_to(logical: Vector2):
	var point: Vector2 = logical * Vector2(root.size) / LOGICAL
	Input.warp_mouse(point)
	var motion = InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await frames()


func click_at(logical: Vector2):
	await mouse_to(logical)
	var point: Vector2 = logical * Vector2(root.size) / LOGICAL
	for down in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame


func click_text(text: String) -> bool:
	var container: Control = game.room_ui.root if is_instance_valid(game.room_ui) else game.ui.page
	for button in container.find_children("*", "Button", true, false):
		if button.text == text and button.is_visible_in_tree() and not button.disabled:
			await click_at(button.get_global_rect().get_center())
			return true
	check(false, "visible real button: " + text)
	return false


func key(code: int):
	for down in [true, false]:
		var event = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame


func choices(action: String = "") -> Array:
	if not is_instance_valid(game.room_ui): return []
	return game.room_ui._choice_buttons.filter(func(button): return is_instance_valid(button) and button.is_visible_in_tree() and (action.is_empty() or button.get_meta("choice_action", "") == action))


func style(button: Button) -> Dictionary:
	var panel: StyleBox = button.get_parent().get_theme_stylebox("panel")
	return {"border": panel.border_color, "background": panel.bg_color, "width": panel.border_width_left} if panel is StyleBoxFlat else {}


func enabled() -> bool:
	var cards: Array = choices()
	return not cards.is_empty() and cards.all(func(button): return not button.disabled)


func snap(label: String, fixture: bool = false):
	await frames()
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	check(pixels.get_size() == root.size, "native screenshot resolution: " + label)
	check(pixels.save_png(OUT + label + ".png") == OK, "save native pixels: " + label)
	captures.append(label)
	records.append({"label": label, "fixture": fixture, "resolution": str(root.size), "phase": game.room_run.phase, "time": game.room_run.time, "combat_time": game.room_run.combat_time})


func check_card_geometry(action: String):
	var cards: Array = choices(action)
	check(cards.size() == 3, "three entire-card buttons for " + action)
	for button in cards:
		var card: Control = button.get_parent()
		check(button.text.is_empty(), "card has no separate selection button wording")
		check(not str(button.get_meta("choice_id", "")).is_empty(), "card carries its offered ID")
		check(card.size.x >= 250 and card.size.x <= 310 and card.size.y >= 380 and card.size.y <= 450, "compact card dimensions: " + str(card.size))
		check(button.position.distance_to(Vector2.ZERO) < 0.01 and button.size.distance_to(card.size) < 0.01, "button covers the complete card")
		check(Rect2(Vector2.ZERO, LOGICAL).encloses(card.get_global_rect()), "complete compact card stays on canvas")
	if cards.size() == 3:
		var union: Rect2 = cards[0].get_parent().get_global_rect()
		for button in cards.slice(1): union = union.merge(button.get_parent().get_global_rect())
		check(absf(union.get_center().x - 800.0) <= 1 and absf(union.get_center().y - 450.0) <= 55, "choice cards centered on player viewport")
		check(union.size.x <= 950, "three-choice group leaves visible courtyard around it")


func check_text_fit(label: String):
	for card_button in choices():
		for paragraph in card_button.get_parent().find_children("*", "Label", true, false):
			if paragraph.text.is_empty() or not paragraph.is_visible_in_tree(): continue
			check(paragraph.get_line_count() <= paragraph.get_visible_line_count(), "%s %s visible prose fits [lines=%d visible=%d h=%.1f line_h=%d]: %s" % [label, str(card_button.get_meta("choice_id")), paragraph.get_line_count(), paragraph.get_visible_line_count(), paragraph.size.y, paragraph.get_line_height(), paragraph.text.left(28)])


func check_progress(expected: Array, label: String, expected_rooms: Array = [], expected_kinds: Array = []):
	var progress: Control = game.room_ui.route_progress
	check(is_instance_valid(progress) and progress.is_visible_in_tree(), "three-room route HUD is visible: " + label)
	if not is_instance_valid(progress): return
	var nodes: Array = progress.find_children("*", "Control", true, false).filter(func(node): return node.has_meta("state"))
	check(nodes.size() == 3, "route HUD contains exactly three room nodes: " + label)
	var states: Array = []
	var room_ids: Array = []
	var room_kinds: Array = []
	for node in nodes:
		states.append(str(node.get_meta("state")))
		room_ids.append(int(node.get_meta("room_id", -1)))
		room_kinds.append(str(node.get_meta("room_kind", "")))
	check(states == expected, "three-room state mapping %s: %s" % [label, str(states)])
	if not expected_rooms.is_empty(): check(room_ids == expected_rooms, "authored room numbers: " + label)
	if not expected_kinds.is_empty(): check(room_kinds == expected_kinds, "authored room types: " + label)
	check(not game.room_ui.room_index_label.text.is_empty(), "small room counter remains visible: " + label)


func hover_and_keyboard():
	var cards: Array = choices("room_initial")
	if cards.size() != 3: return
	await mouse_to(Vector2(800, 155))
	var neutral: Array = []
	for button in cards:
		check(not button.has_focus(), "opening has no automatic card focus: " + str(button.get_meta("choice_id")))
		check(not button.is_hovered(), "opening has no automatic card hover: " + str(button.get_meta("choice_id")))
		neutral.append(style(button))
	await snap("04-starter-neutral-1600")
	var card: Control = cards[1].get_parent()
	for fraction in [Vector2(0.1, 0.12), Vector2(0.5, 0.5), Vector2(0.9, 0.9)]:
		await mouse_to(card.get_global_rect().position + card.size * fraction)
		for index in cards.size():
			check(cards[index].is_hovered() == (index == 1), "whole card pointer hit area, including icon and description")
		check(style(cards[1]) != neutral[1], "whole card hover changes actual card border")
		check(style(cards[1]).border.is_equal_approx(T.CYAN), "pointer feedback uses cyan card edge")
	await snap("05-starter-whole-card-hover")
	await mouse_to(Vector2(800, 155))
	await wait(0.08)
	for index in cards.size(): check(not cards[index].is_hovered() and style(cards[index]) == neutral[index], "leaving card restores neutral border")
	await key(KEY_TAB)
	var focus = root.gui_get_focus_owner()
	check(focus in cards, "Tab focuses an actual choice card: " + str(focus))
	check(game.room_ui._choice_keyboard, "Tab starts independent keyboard card feedback")
	if focus in cards:
		var focus_style: StyleBox = focus.get_theme_stylebox("focus")
		check(focus_style is StyleBoxFlat and focus_style.border_width_bottom > 0, "keyboard choice uses a visible underline")
		check(style(focus).border.is_equal_approx(T.GOLD), "keyboard feedback uses gold card edge")
	await key(KEY_RIGHT)
	check(root.gui_get_focus_owner() in cards, "right arrow navigates choice cards")
	await snap("06-starter-keyboard")
	await mouse_to(Vector2(800, 155))
	check(not game.room_ui._choice_keyboard and root.gui_get_focus_owner() == null, "mouse returns keyboard feedback to neutral")


func fixture(snapshot: Dictionary, label: String):
	# Only presentation receives these dictionaries; real Main/core remains untouched.
	if is_instance_valid(fixture_tag): fixture_tag.queue_free()
	game.room_ui._clear_modal()
	game.room_ui.last_modal = ""
	game.room_ui.refresh(snapshot)
	await wait(0.75)
	fixture_tag = T.label(game.room_ui.modal if is_instance_valid(game.room_ui.modal) else game.room_ui.root, "受控展示样例 · 非真实流程进度", Rect2(480, 865, 640, 26), 15, T.GOLD)
	fixture_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	await mouse_to(Vector2(100, 600))
	check_text_fit(label)
	check(game.room_run.get_snapshot() == initial_snapshot, "display fixture leaves genuine core unchanged: " + label)


func fixture_matrix():
	var ids: Array = Catalog.load_catalog().base.spells.keys()
	for level in range(1, 4):
		for offset in range(0, ids.size(), 3):
			var state: Dictionary = initial_snapshot.duplicate(true)
			state.phase = "reward"
			state.reward_choices = []
			for id in ids.slice(offset, mini(offset + 3, ids.size())):
				state.reward_choices.append({"id": id, "next_level": level, "is_new": level == 1})
			var label: String = "fixture-spells-lv%d-%02d" % [level, offset + 1]
			await fixture(state, label)
			check(choices("room_reward").size() == state.reward_choices.size(), "fixture reward IDs retain original action")
			await snap(label, true)
	var artifacts: Array = Catalog.load_catalog().artifact_source.items.keys()
	for offset in range(0, artifacts.size(), 3):
		var state: Dictionary = initial_snapshot.duplicate(true)
		state.phase = "artifact"
		state.artifact_choices = []
		for id in artifacts.slice(offset, mini(offset + 3, artifacts.size())):
			state.artifact_choices.append(Catalog.describe_artifact(str(id)))
		var label: String = "fixture-artifacts-%02d" % (offset + 1)
		await fixture(state, label)
		check(choices("room_artifact").size() == state.artifact_choices.size(), "fixture artifact IDs retain original action")
		await snap(label, true)
	var route_source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/courtyard_route.json"))
	var route_fixtures: Array = []
	var active_total: int = int(route_source.active_room_count)
	for room in [1,4,6,14,15,16,30,31,active_total-1,active_total]:
		var start_room: int = mini(room,maxi(1,active_total-2))
		var node_ids: Array = []
		var kinds: Array = []
		var states: Array = []
		for id in range(start_room,start_room+3):
			node_ids.append(id)
			kinds.append(str(route_source.encounters_by_room[str(id)].kind))
			states.append("done" if id<room else "current" if id==room else "pending")
		route_fixtures.append({"room":room,"ids":node_ids,"kinds":kinds,"states":states})
	route_fixtures.append({"room":active_total,"phase":"complete","ids":[active_total-2,active_total-1,active_total],"kinds":[str(route_source.encounters_by_room[str(active_total-2)].kind),str(route_source.encounters_by_room[str(active_total-1)].kind),str(route_source.encounters_by_room[str(active_total)].kind)],"states":["done","done","done"]})
	for definition in route_fixtures:
		var state: Dictionary = initial_snapshot.duplicate(true)
		state.phase = str(definition.get("phase", "combat"))
		state.room_index = int(definition.room)
		state.encounter_kind = str(route_source.encounters_by_room[str(state.room_index)].kind)
		var label: String = "room-%02d-%s" % [state.room_index, state.phase]
		await fixture(state, label)
		check_progress(definition.states, label, definition.ids, definition.kinds)
		await snap("fixture-route-" + label, true)
		# The same room map survives clear, pickup, reward selection and exit.
		if state.phase == "combat":
			for phase in ["pickup", "exit"]:
				state.phase = phase
				game.room_ui.refresh(state)
				check_progress(definition.states, label + "-" + phase, definition.ids, definition.kinds)
	# Click genuine controls against display-only offers. Main rejects a reward or
	# artifact request during the true choosing phase, so these cannot grant items.
	for action in ["room_reward", "room_artifact"]:
		var state: Dictionary = initial_snapshot.duplicate(true)
		state.phase = "reward" if action == "room_reward" else "artifact"
		state.reward_choices = [{"id": "F03", "next_level": 1}]
		state.artifact_choices = [Catalog.describe_artifact("B01")]
		await fixture(state, "action-" + action)
		var offered: Array = choices(action)
		check(offered.size() == 1, "controlled offer exposes expected original action: " + action)
		if offered.size() == 1:
			var id: String = str(offered[0].get_meta("choice_id"))
			await click_at(offered[0].get_global_rect().get_center())
			check(not requests.is_empty() and requests.back() == {"action": action, "id": id}, "actual whole-card click emits original reward action: " + action)
			check(game.room_run.get_snapshot() == initial_snapshot, "core rejects controlled out-of-phase offer without mutation: " + action)


func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	# Remove only prior PNGs named by this harness's own capture manifest.
	if FileAccess.file_exists(OUT + "results.json"):
		var previous: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUT + "results.json"))
		if previous is Dictionary:
			for capture in previous.get("captures", []):
				var name: String = str(capture)
				if not name.contains("/") and not name.contains("\\") and not name.contains(".."):
					if FileAccess.file_exists(OUT + name + ".png"): DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT + name + ".png"))
	DirAccess.make_dir_recursive_absolute("user://tests")
	for path in [SAVE, SAVE + ".tmp", SAVE + ".bak", PREFS]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for path in ["user://meta_progression_v1.json", "user://display.cfg"]:
		production_before[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	DisplayServer.window_set_size(Vector2i(1600, 900))
	game = Main.new()
	game.save_path = SAVE
	game.preferences_path = PREFS
	game.room_seed = 20261018
	root.add_child(game)
	game.set_process(false)
	root.grab_focus()
	await frames(3)
	check(DisplayServer.get_name() != "headless", "native rendering required")
	check(game.load_error.is_empty(), "real Main loads with isolated test account")
	if DisplayServer.get_name() == "headless" or not game.load_error.is_empty():
		await finish()
		return
	account_before = game.meta.get_state()
	save_before = FileAccess.get_file_as_string(SAVE)
	await click_text("开始冒险     ›")
	check(game.screen == "prepare", "genuine home reaches preparation")
	await click_text("进入60房路线    ›")
	check(game.room_run != null and game.room_run.phase == "choosing", "genuine preparation opens route initial choice")
	if game.room_run == null:
		await finish()
		return
	initial_snapshot = game.room_run.get_snapshot()
	game.room_ui.requested.connect(func(action: String, id: String): requests.append({"action": action, "id": id}))
	var entrance_started: int = Time.get_ticks_msec()
	var entry: Array = choices("room_initial")
	check(entry.size() == 3 and entry.all(func(button): return button.disabled), "flip entrance blocks every card")
	for code in [KEY_TAB, KEY_RIGHT, KEY_ENTER]:
		await key(code)
		var focus_owner = root.gui_get_focus_owner()
		check(focus_owner == null or focus_owner in entry, "flip navigation/confirmation cannot escape into HUD")
		check(not game.room_run.paused and game.room_run.get_snapshot() == initial_snapshot, "flip navigation/confirmation cannot pause or choose a spell")
	await snap("01-starter-entrance")
	await click_at(Vector2(800, 440))
	check(game.room_run.get_snapshot() == initial_snapshot, "clicking a face-down card cannot select or advance the core")
	await mouse_to(Vector2(800, 155))
	await wait(0.06)
	check(enabled() or choices().all(func(button): return button.disabled), "staggered flip never unlocks cards individually")
	await snap("02-starter-revealed")
	while not enabled() and Time.get_ticks_msec() - entrance_started < 1200:
		check(choices().all(func(button): return button.disabled), "frame-by-frame entrance lock is uniform")
		await process_frame
	check(enabled(), "all cards unlock after entrance with screenshot readback overhead")
	check(game.room_run.get_snapshot() == initial_snapshot, "initial animation leaves all core values unchanged")
	check_card_geometry("room_initial")
	check_progress(["current", "pending", "pending"], "initial", [1, 2, 3], ["normal", "normal", "normal"])
	await snap("03-starter-fronts-1600")
	await hover_and_keyboard()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await frames(4)
	check_card_geometry("room_initial")
	await mouse_to(Vector2(800, 155))
	await snap("07-starter-fronts-1280")
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await frames(4)
	# Rebuild an actual initial modal by pausing and resuming while it is flipping.
	await key(KEY_ESCAPE)
	check(game.room_run.paused and game.room_ui.last_modal == "pause", "Esc interrupts choice into genuine pause")
	await click_text("继续试炼")
	var old_cards: Array = choices()
	check(old_cards.size() == 3 and old_cards.all(func(button): return button.disabled), "resume creates a fresh protected flip")
	await key(KEY_ESCAPE)
	await wait(0.8)
	check(game.room_run.paused and choices().is_empty(), "closing in-progress flip leaves no stale active choice")
	check(old_cards.all(func(button): return not is_instance_valid(button)), "closed flip releases former card nodes")
	await snap("08-paused-entrance-cleanup")
	# Time a fresh reveal without synchronous screenshots or extra input in flight.
	await click_text("继续试炼")
	var timed_start: int = Time.get_ticks_msec()
	while not enabled() and Time.get_ticks_msec() - timed_start < 650:
		check(choices().all(func(button): return button.disabled), "timed flip never partially unlocks")
		await process_frame
	check(enabled(), "uncaptured genuine entrance fully reveals within 0.65 seconds")
	records.append({"label": "timed-uninterrupted-entrance", "elapsed_ms_after_button_release": Time.get_ticks_msec() - timed_start, "fixture": false})
	await key(KEY_ESCAPE)
	# Preference is changed in memory only, without saving user settings.
	game.visual_options.reduced_motion = true
	game.room_ui.set_visual_options(game.visual_options)
	await click_text("继续试炼")
	check(enabled(), "reduced motion shows fully selectable cards immediately")
	for button in choices(): check(button.get_parent().scale.is_equal_approx(Vector2.ONE), "reduced motion has no flipped scale")
	check(game.room_run.get_snapshot() == initial_snapshot, "pause/resume and reduced motion preserve starting core")
	await snap("09-starter-reduced-motion")
	await fixture_matrix()
	if is_instance_valid(fixture_tag): fixture_tag.queue_free()
	game.room_ui.last_modal = ""
	game.room_ui.refresh(initial_snapshot)
	await frames()
	var selected: Array = choices("room_initial")
	if selected.size() == 3:
		var target: Button = selected[1]
		var expected_id: String = str(target.get_meta("choice_id"))
		var card: Control = target.get_parent()
		# Click the icon/body near the top, away from the old lower selection button.
		await click_at(card.get_global_rect().position + Vector2(card.size.x * 0.5, card.size.y * 0.24))
		check(game.room_run.phase == "combat" and game.room_run.spells.size() == 1 and game.room_run.spells[0].id == expected_id, "whole-card body click emits original initial action and learns offered spell")
		check(game.room_ui.last_modal == "" and choices().is_empty(), "successful whole-card choice closes modal")
		await snap("10-actual-whole-card-choice-combat")
		await key(KEY_ESCAPE)
		await click_text("结束试玩")
		await click_text("再次试玩")
		check(game.room_run.phase == "choosing" and enabled(), "genuine retry opens immediately with reduced motion")
		await mouse_to(Vector2(800, 155))
		await key(KEY_TAB)
		var focused = root.gui_get_focus_owner()
		check(focused in choices("room_initial"), "keyboard has an actual retry card selected")
		if focused in choices("room_initial"):
			var chosen_id: String = str(focused.get_meta("choice_id"))
			await key(KEY_ENTER)
			check(game.room_run.phase == "combat" and game.room_run.spells.size() == 1 and game.room_run.spells[0].id == chosen_id, "Enter confirms keyboard card through genuine Main/core")
			await snap("11-actual-keyboard-choice-combat")
	check(game.meta.get_state() == account_before and FileAccess.get_file_as_string(SAVE) == save_before, "route UI leaves isolated account byte-identical")
	await finish()


func finish():
	for path in production_before:
		var after: String = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
		check(after == production_before[path], "production account/preferences untouched: " + path)
	var result: Dictionary = {"checks": checks, "failures": failures.size(), "details": failures, "captures": captures, "records": records, "requests": requests, "production_before": production_before, "provenance": "Native Godot real Main; menu navigation, timed card flips, pointer hover and body click, keyboard navigation and Enter confirmation, resize, pause/resume and reduced motion. Core never advanced during initial tests. All spell/level, artifact and authored room-route matrices are explicitly labeled controlled presentation fixtures, not naturally earned rewards or route completion; their out-of-phase clicks are checked for correct UI actions and core rejection. Room-node types and numbers come from authored data and the current room snapshot, not in-room phases or invented shops. Isolated save/preferences only; no export or remote actions."}
	FileAccess.open(OUT + "results.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	for path in [SAVE, SAVE + ".tmp", SAVE + ".bak", PREFS]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("COMPACT CHOICE VISUAL: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
