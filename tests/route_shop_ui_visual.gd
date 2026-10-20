extends SceneTree
## Controlled display matrix for every active treasure, affordability and
## purchase states. It is not a natural stock/acquisition playthrough.
const ShopUI = preload("res://scripts/ui/route_shop_ui.gd")
const T = preload("res://scripts/ui/atelier_theme.gd")
const Route = preload("res://scripts/core/courtyard_route_run.gd")
const OUT = "res://build/qa/route-shops-20261019/ui-matrix/"
var checks: int = 0
var failures: Array = []
var captures: Array = []
var line_rows: Array = []
var holder: Control
var audit_only: bool = false


func _initialize():
	audit_only = "--audit-only" in OS.get_cmdline_user_args()
	call_deferred("run")


func check(value: bool, label: String):
	checks += 1
	if not value:
		failures.append(label)
		push_error("Shop UI matrix: " + label)


func capture(label: String):
	await process_frame
	await process_frame
	if audit_only:
		return
	await RenderingServer.frame_post_draw
	var path: String = OUT + label + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, "save native shop matrix " + label)
	captures.append(label)


func mount(snapshot: Dictionary):
	if is_instance_valid(holder):
		holder.queue_free()
		await process_frame
	holder = Control.new()
	holder.size = Vector2(1600, 900)
	holder.theme = T.make_theme()
	root.add_child(holder)
	var dim = ColorRect.new()
	dim.color = Color("101522")
	dim.size = Vector2(1600, 900)
	holder.add_child(dim)
	var ui = ShopUI.new()
	holder.add_child(ui)
	ui.build(snapshot)
	await process_frame
	await process_frame
	for label in holder.find_children("*", "Label", true, false):
		if not label.is_visible_in_tree():
			continue
		var line_count: int = label.get_line_count()
		var visible_lines: int = label.get_visible_line_count()
		check(line_count <= visible_lines, "all rendered shop prose fits: " + label.text)
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			var font: Font = label.get_theme_font("font")
			var size: Vector2 = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size"))
			check(size.x <= label.size.x + 1.0, "single-line shop title fits: " + label.text)
		line_rows.append({"text": label.text, "lines": line_count, "visible_lines": visible_lines, "rect": label.get_global_rect()})
	return ui


func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	check(audit_only or DisplayServer.get_name() != "headless", "pixel QA requires native display")
	var battle = Route.new()
	check(battle.configure().ok, "production catalog loads")
	var items: Array = []
	for id in battle._artifact_combat._items:
		if bool(battle._artifact_combat._items[id].get("active", true)):
			var item: Dictionary = battle._artifact_combat._describe(str(id))
			item["price"] = int(battle._economy.prices[item.rarity])
			items.append(item)
	check(items.size() == 56, "matrix uses every actual active treasure")
	var snapshot := {"room_revision": 19, "gold": 286,
		"shop": {"after_room": 24, "max_health_gain": 20, "health_restored": 76,
			"purchased_id": "", "offers": []}}
	for dimensions in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		if audit_only:
			root.size = dimensions
		else:
			DisplayServer.window_set_size(dimensions)
		root.content_scale_size = Vector2i(1600, 900)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		for index in range(0, items.size(), 3):
			snapshot.shop.offers = items.slice(index, mini(index + 3, items.size()))
			await mount(snapshot)
			await capture("all-items-%02d-%d" % [index / 3, dimensions.x])
	# Affordability and purchased states use the same three real catalog entries.
	snapshot.shop.offers = items.slice(0, 3)
	snapshot.gold = 0
	var ui = await mount(snapshot)
	check(ui._buy_buttons.all(func(button): return button.disabled and button.text.contains("金币不足")), "zero wallet shows visible reason and disables purchases")
	check(ui._close.has_focus(), "keyboard focus starts on a safe exit")
	await capture("zero-wallet-1280")
	snapshot.gold = 226
	snapshot.shop.purchased_id = items[0].id
	ui = await mount(snapshot)
	check(ui._buy_buttons.all(func(button): return button.disabled) and ui._buy_buttons[0].text.contains("已购买"), "receipt and remaining quota are visibly distinct")
	await capture("purchase-quota-1280")
	snapshot.shop.offers = []
	snapshot.shop.purchased_id = ""
	ui = await mount(snapshot)
	check(ui._buy_buttons.is_empty() and not ui._close.disabled, "exhausted pool leaves accessible exit")
	await capture("empty-stock-1280")
	FileAccess.open(OUT + ("audit.json" if audit_only else "results.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"details":failures,"captures":captures,"text_geometry":line_rows,"scope":"Controlled real Godot ShopUI matrix for all 56 active IDs at both resolutions, zero wallet, purchased and exhausted states. No natural acquisition claim."}, "\t"))
	print("SHOP UI MATRIX: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
