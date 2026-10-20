extends SceneTree
## Real window capture of the two formal fire/ice catalysts after legacy migration.
## The isolated fixture mirrors the old three-catalyst account shape; no player
## save, preference, combat state or account reward is written.

const Main = preload("res://scripts/main.gd")
const Meta = preload("res://scripts/core/meta_progression.gd")
const OUT = "res://build/qa/catalyst-ui-20261018/visual/"
const SAVE = "user://tests/catalyst_ui_visual.json"
const SAVE_OWNED = "user://tests/catalyst_ui_visual_owned.json"
var game
var checks: int = 0
var failures: int = 0
var captures: Array[String] = []

func _initialize():
	call_deferred("run")

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("Catalyst UI: " + message)

func button_named(title: String):
	for button in game.ui.page.find_children("*", "Button", true, false):
		if button.text == title:
			return button
	return null

func card_button(item_id: String):
	for button in game.ui.page.find_children("*", "Button", true, false):
		if str(button.get_meta("selection_id", "")) == item_id:
			return button
	return null

func labels_text() -> String:
	var parts: Array[String] = []
	for label in game.ui.page.find_children("*", "Label", true, false):
		parts.append(label.text)
	for button in game.ui.page.find_children("*", "Button", true, false):
		parts.append(button.text)
	return "\n".join(parts)

func click(button):
	check(button != null, "click target exists")
	if button == null:
		return
	var point = button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func snap(name: String):
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image.get_size() == Vector2i(1600, 900), "capture size " + name)
	check(image.save_png(OUT + name + ".png") == OK, "capture saved " + name)
	captures.append(name)

func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	DirAccess.make_dir_recursive_absolute("user://tests")
	for path in [SAVE, SAVE_OWNED]:
		for suffix in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	var legacy = {
		"version": "meta-progression-1",
		"dust": 2,
		"levels": {"MC01": 1, "MC02": 0, "MC03": 0, "MG01": 0, "MG02": 0, "MG03": 1},
		"equipped": {"catalyst": "MC01", "gem": "MG03"},
		"free_claimed": {"catalyst": true, "gem": true},
		"settlement_serial": 0,
		"run_serial": 0,
		"last_settlement": {},
	}
	var file = FileAccess.open(SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy, "\t"))
	file.close()
	DisplayServer.window_set_size(Vector2i(1600, 900))
	game = Main.new()
	game.save_path = SAVE
	root.add_child(game)
	await process_frame
	check(game.load_error.is_empty(), "legacy fixture loads without a blocking error")
	check(game.meta.get_state().version == Meta.SAVE_VERSION, "legacy fixture is migrated in memory")
	check(game.meta.get_state().levels == {"MC04": 1, "MC05": 0, "MG01": 0, "MG02": 0, "MG03": 1}, "fire level is inherited, ice stays locked")
	check(game.meta.get_state().equipped == {"catalyst": "MC04", "gem": "MG03"}, "fire catalyst is equipped")
	var fire = game.meta.get_item_status("catalyst", "MC04")
	var ice = game.meta.get_item_status("catalyst", "MC05")
	check(fire.name == "火法术触媒" and fire.level == 1 and fire.equipped, "fire catalyst status")
	check(ice.name == "冰法术触媒" and ice.level == 0 and not ice.can_unlock, "ice catalyst is visible but locked by dust")
	check(fire.related_spell_names.size() == 10 and ice.related_spell_names.size() == 10, "both catalysts relate to ten school spells")

	game.navigate("catalyst")
	await snap("01-catalysts-1600")
	var text = labels_text()
	check(text.contains("火法术触媒") and text.contains("冰法术触媒"), "both catalyst names are visible")
	check(not text.contains("爆焰触媒") and not text.contains("灵契触媒") and not text.contains("燎原触媒"), "removed catalysts are absent")
	check(game.ui.page.find_children("*", "Button", true, false).filter(func(button): return button.text == "查看与培养").size() == 2, "two catalyst cards")
	check(card_button("MC04") != null and card_button("MC05") != null, "both cards expose their real item id")

	await click(card_button("MC05"))
	await snap("02-ice-locked-1600")
	text = labels_text()
	check(game.selected == "MC05", "clicking the ice card selects it")
	check(text.contains("冰系全部 10 种法术（含三种起手）。"), "ice detail explains all ten ice spells")
	check(text.contains("解锁 · 20 魔尘"), "ice card keeps the source unlock price")
	check(not game.meta.get_item_status("catalyst", "MC05").can_unlock, "locked ice card cannot be purchased with two dust")

	await click(card_button("MC04"))
	await snap("03-fire-equipped-1600")
	text = labels_text()
	check(text.contains("火系全部 10 种法术（含三种起手）。"), "fire detail explains all ten fire spells")
	check(text.contains("等级 1 / 3 · 已装备"), "fire card shows its equipped level")
	check(button_named("升级 · 20 魔尘") != null and button_named("升级 · 20 魔尘").disabled, "upgrade stays disabled at two dust")

	game.navigate("prepare")
	await snap("04-prepare-1600")
	text = labels_text()
	check(text.contains("火法术触媒"), "prepare page shows the migrated fire catalyst")
	check(text.contains("触媒提升火／冰本系奖励权重"), "prepare copy mentions both schools")
	var migrated_version = game.meta.get_state().version
	game.queue_free()
	await process_frame

	# A funded current-format account proves the ice catalyst can be bought and equipped.
	var owned = {
		"version": Meta.SAVE_VERSION,
		"dust": 20,
		"levels": {"MC04": 1, "MC05": 0, "MG01": 0, "MG02": 0, "MG03": 0},
		"equipped": {"catalyst": "MC04", "gem": ""},
		"free_claimed": {"catalyst": true, "gem": false},
		"settlement_serial": 0,
		"run_serial": 0,
		"last_settlement": {},
	}
	file = FileAccess.open(SAVE_OWNED, FileAccess.WRITE)
	file.store_string(JSON.stringify(owned, "\t"))
	file.close()
	game = Main.new()
	game.save_path = SAVE_OWNED
	root.add_child(game)
	await process_frame
	check(game.load_error.is_empty(), "funded current account loads")
	game.navigate("catalyst")
	await snap("05-ice-available-1600")
	await click(card_button("MC05"))
	var unlock = button_named("解锁 · 20 魔尘")
	check(unlock != null and not unlock.disabled, "funded account can unlock ice catalyst")
	if unlock != null and not unlock.disabled:
		await click(unlock)
	check(game.meta.get_state().levels.MC05 == 1 and game.meta.get_state().dust == 0, "ice unlock spends exactly twenty dust")
	check(game.meta.get_state().equipped.catalyst == "MC04", "paid unlock keeps the current equipment")
	var equip = button_named("装备")
	check(equip != null and not equip.disabled, "unlocked ice catalyst can be equipped")
	if equip != null and not equip.disabled:
		await click(equip)
	check(game.meta.get_state().equipped.catalyst == "MC05", "ice catalyst becomes the equipped catalyst")
	game.refresh()
	await snap("06-ice-equipped-1600")
	check(labels_text().contains("等级 1 / 3 · 已装备"), "ice card shows the equipped level")
	game.navigate("prepare")
	await snap("07-prepare-ice-1600")
	check(labels_text().contains("冰法术触媒"), "prepare page shows the equipped ice catalyst")

	var report = {
		"checks": checks,
		"failures": failures,
		"captures": captures,
		"save_isolated": [SAVE, SAVE_OWNED],
		"migrated_version": migrated_version,
		"owned_version": game.meta.get_state().version,
		"renderer": RenderingServer.get_video_adapter_name(),
	}
	FileAccess.open(OUT + "results.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	game.queue_free()
	await process_frame
	for path in [SAVE, SAVE_OWNED]:
		for suffix in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("CATALYST UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
