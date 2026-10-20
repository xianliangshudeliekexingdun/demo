extends SceneTree
## Separate materials audit. These labeled gallery pixels are not game screenshots.
## Each cell contains the production icon Control at 108px and 40px.

const T = preload("res://scripts/ui/atelier_theme.gd")
const Catalog = preload("res://scripts/ui/grimoire_catalog.gd")
const SPELL_IDS = ["F01", "F02", "F03", "F04", "F05", "F06", "F07", "F08", "F09", "F10"]
const ARTIFACT_IDS = ["B01", "B02", "B03", "B04", "B05", "B06", "B07", "B08", "B09", "B10", "P01", "P02", "P03", "P04", "P05", "G01", "G02", "G03", "U01", "U02", "U03"]
const META_IDS = ["MC04", "MC05", "MG01", "MG02", "MG03"]
const OUT = "res://build/qa/catalyst-ui-20261018/materials/"
var checks: int = 0
var failures: Array = []
var assets: Array = []
var captures: Array = []
var page: Control
var paths: Dictionary = {}
var _audit_only: bool = false


func _initialize():
	_audit_only = "--audit-only" in OS.get_cmdline_user_args()
	call_deferred("run")


func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures.append(message)
		push_error("Material asset audit: " + message)


func add_text(text: String, rect: Rect2, px: int, color: Color = T.TEXT):
	return T.label(page, text, rect, px, color)


func asset_name(id: String) -> String:
	if id.begins_with("F"):
		return str(Catalog.describe_spell(id, 1).get("name", id))
	if id.begins_with("MC") or id.begins_with("MG"):
		var meta: Dictionary = Catalog.load_catalog().get("meta", {})
		var items: Dictionary = meta.get("catalysts" if id.begins_with("MC") else "gems", {})
		return str(items.get(id, {}).get("name", id))
	return str(Catalog.describe_artifact(id).get("name", id))


func audit_texture(id: String, texture: Texture2D, kind: String):
	check(texture != null, "painted production texture exists " + id)
	if texture == null:
		return
	var image: Image = texture.get_image()
	check(image != null and not image.is_empty(), "production texture decodes " + id)
	if image == null or image.is_empty():
		return
	check(image.get_width() == image.get_height() and image.get_width() >= 256, "square source of useful resolution " + id)
	if kind == "spells":
		check(image.get_format() in [Image.FORMAT_RGB8, Image.FORMAT_RGBA8], "spell retains its real RGB/RGBA painted format " + id)
	else:
		check(image.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_RGBAF, Image.FORMAT_RGBAH], "production item retains alpha channel " + id)
	var corners: Array = [Vector2i.ZERO, Vector2i(image.get_width()-1, 0), Vector2i(0, image.get_height()-1), Vector2i(image.get_width()-1, image.get_height()-1)]
	for corner in corners:
		if kind == "spells":
			var ink: Color = image.get_pixelv(corner)
			check(maxf(ink.r, maxf(ink.g, ink.b)) < 0.20, "intentional dark-indigo spell corner %s %s" % [id, str(corner)])
		else:
			check(image.get_pixelv(corner).a < 0.01, "native transparent image corner %s %s" % [id, str(corner)])
	var empty: int = 0
	var solid: int = 0
	var bright: int = 0
	for y in range(0, image.get_height(), maxi(1, image.get_height()/32)):
		for x in range(0, image.get_width(), maxi(1, image.get_width()/32)):
			var alpha: float = image.get_pixel(x, y).a
			if alpha < 0.01: empty += 1
			if alpha > 0.8: solid += 1
			var pixel: Color = image.get_pixel(x, y)
			if maxf(pixel.r, maxf(pixel.g, pixel.b)) > 0.4: bright += 1
	if kind == "spells":
		check(bright > 0 and solid > 0, "dark painted spell has visible fire silhouette " + id)
	else:
		check(empty > 0 and solid > 0, "source has transparent margin and visible painted body " + id)
	check(not paths.has(texture.resource_path), "each item has its own final asset " + id)
	paths[texture.resource_path] = id
	assets.append({"id": id, "kind": kind, "name": asset_name(id), "path": texture.resource_path, "dimensions": image.get_size(), "format": image.get_format(), "sampled_transparent": empty, "sampled_solid": solid, "sampled_bright": bright, "background_policy": "intentional dark-indigo painted spell" if kind == "spells" else "native transparent object", "sha256": FileAccess.get_sha256(texture.resource_path)})


func gallery(kind: String, title: String, ids: Array, script_path: String, label: String):
	if is_instance_valid(page):
		root.remove_child(page)
		page.queue_free()
	page = Control.new()
	page.size = Vector2(1600, 900)
	page.theme = T.make_theme()
	root.add_child(page)
	var backdrop = ColorRect.new()
	backdrop.color = Color("101522")
	backdrop.size = page.size
	page.add_child(backdrop)
	add_text("素材核对 · " + title, Rect2(48, 26, 1504, 54), 34, T.GOLD)
	add_text("非游戏截图 · 每格为正式图标控件 108px / 40px · 深浅底检查透明边缘与小图轮廓", Rect2(48, 84, 1504, 36), 20, T.MUTED)
	check(ResourceLoader.exists(script_path), "production icon script exists " + script_path)
	if not ResourceLoader.exists(script_path):
		return
	var icon_script: Script = load(script_path)
	var mapping: Dictionary = icon_script.get_script_constant_map().get("PAINTED", {})
	# Historical subset gallery: formal F11 and the 26 ice assets have their own
	# dedicated audits; this file keeps the original ten-fire / 21-artifact sample.
	check(mapping.size() >= ids.size(), "painted mapping covers requested audit IDs " + kind)
	for index in ids.size():
		var id: String = str(ids[index])
		var origin = Vector2(48 + (index % 7)*214, 154 + (index/7)*226)
		var cell = T.panel(page, Rect2(origin, Vector2(202, 208)))
		cell.add_theme_stylebox_override("panel", T.box(Color("181e30"), T.LINE, 1, 5))
		T.label(cell, id, Rect2(10, 5, 174, 27), 19, T.GOLD)
		var light = ColorRect.new()
		light.position = Vector2(130, 56)
		light.size = Vector2(58, 58)
		light.color = Color("465064")
		cell.add_child(light)
		check(mapping.has(id), "painted production ID coverage " + id)
		if mapping.has(id):
			audit_texture(id, mapping[id], kind)
		for side in [108, 40]:
			var icon: Control = icon_script.new()
			if kind == "spells":
				icon.spell_id = id
			else:
				icon.set_item(id)
			icon.position = Vector2(8, 39) if side == 108 else Vector2(139, 65)
			icon.size = Vector2.ONE*side
			cell.add_child(icon)
			check(icon.size == Vector2.ONE*side, "actual production Control respects %dpx %s" % [side, id])
			check(str(icon.get("spell_id") if kind == "spells" else icon.get("item_id")) == id, "production Control receives real ID %s at %dpx" % [id, side])
		T.label(cell, "108px", Rect2(13, 151, 98, 23), 15, T.MUTED)
		T.label(cell, "40px", Rect2(135, 119, 58, 23), 15, T.MUTED)
		T.label(cell, asset_name(id), Rect2(10, 177, 184, 25), 17, T.TEXT)
	add_text("十火深靛底绘画 · 二十六件神器与装备原生透明 · ID 与图鉴数据逐项对应", Rect2(48, 849, 1504, 30), 18, T.MUTED)
	await process_frame
	await process_frame
	if not _audit_only:
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		check(image.get_size() == Vector2i(1600, 900), "native gallery size " + label)
		check(image.save_png(OUT + label + ".png") == OK, "save labeled actual Control gallery " + label)
		captures.append(label)


func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	check(_audit_only or DisplayServer.get_name() != "headless", "native display required for pixels unless audit-only")
	if not _audit_only and DisplayServer.get_name() == "headless":
		finish()
		return
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await gallery("spells", "十火法术", SPELL_IDS, "res://scripts/ui/arcane_icon.gd", "01-spells-40-and-108")
	await gallery("artifacts", "二十一件神器", ARTIFACT_IDS, "res://scripts/ui/artifact_icon.gd", "02-artifacts-40-and-108")
	await gallery("equipment", "法术触媒与魔力宝石", META_IDS, "res://scripts/ui/equipment_icon.gd", "03-equipment-40-and-108")
	check(assets.size() == 36 and paths.size() == 36, "all 36 intended icons have distinct painted resources")
	finish()


func finish():
	var report = {"checks": checks, "failures": failures.size(), "details": failures, "audit_only": _audit_only, "captures": captures, "assets": assets, "initial_audit_correction": "First-run results preserved in first-run-transparency-assumption.json. The initial test incorrectly required alpha for spells; approved design intentionally retains four old RGB dark-indigo spell images and matches six new RGB images. Alpha/corner-transparency applies only to 26 artifact/equipment assets in this historical sample after the fire/ice catalyst switch; formal F11 and ice assets are audited separately. No source pixels changed.", "provenance": "Labeled material-check gallery, not game screenshots. Production ArcaneIcon, ArtifactIcon, EquipmentIcon Controls rendered at 40px and 108px. No game state, save, preferences, reward construction or combat simulation."}
	FileAccess.open(OUT + ("audit-only.json" if _audit_only else "results.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MATERIAL ASSET AUDIT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
