extends SceneTree
## Controlled production-icon gallery, explicitly not a natural inventory.
const T = preload("res://scripts/ui/atelier_theme.gd")
const Catalog = preload("res://scripts/ui/grimoire_catalog.gd")
const Icon = preload("res://scripts/ui/artifact_icon.gd")
const Main = preload("res://scripts/main.gd")
const OUT = "res://build/qa/formal-fire-implementation-20261018/materials/"
const SpellIcon = preload("res://scripts/ui/arcane_icon.gd")
const IDS = ["F11", "B11", "P06", "G04"]
const PATHS = {"F11":"f11_ignition_mark.png","B11":"b11_kindling_ring.png","P06":"p06_lingering_embers.png","G04":"g04_rekindling_signet.png"}
var checks := 0
var failures: Array = []
var assets: Array = []
var captures: Array = []
var page: Control
var game
var source_before: Dictionary={}

func _initialize():
	call_deferred("run")

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures.append(label)
		push_error("Formal fire materials: "+label)

func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	source_before=source_hashes()
	DisplayServer.window_set_size(Vector2i(1600,900))
	check(DisplayServer.get_name() != "headless", "real raster pixel inspection requires rendered window")
	var all: Array = Catalog.artifacts()
	check(all.size() == 40, "merged real catalog has forty unique entries")
	var ids_seen: Dictionary={}
	for item in all: ids_seen[str(item.id)]=true
	check(ids_seen.size()==40,"merged catalog never duplicates an ID during migration")
	check(all.filter(func(item): return str(item.get("scope",""))=="generic").size()==24,"catalog has twenty-four generic entries")
	check(all.filter(func(item): return str(item.get("scope",""))=="fire").size()==16,"catalog has sixteen fire profession entries")
	for batch in 1:
		if is_instance_valid(page): page.queue_free()
		await process_frame
		page = Control.new()
		page.size = Vector2(1600,900)
		page.theme = T.make_theme()
		root.add_child(page)
		var background := ColorRect.new()
		background.color = Color("101522")
		background.size = page.size
		page.add_child(background)
		T.label(page,"正式火系 · 新增法术与职业宝物图标",Rect2(48,24,1504,60),34,T.GOLD)
		T.label(page,"受控展示，非自然库存 · 正式图标控件 112px / 40px · 透明边缘、名称、品质与小图轮廓",Rect2(48,86,1504,40),22,T.MUTED)
		for index in range(IDS.size()):
			var id: String = IDS[index]
			var item: Dictionary = Catalog.describe_spell(id) if id=="F11" else Catalog.describe_artifact(id)
			check(not item.is_empty(), "real formal fire description "+id)
			if id!="F11": check(str(item.get("scope_name", ""))=="职业道具", "new career category " + id)
			check((SpellIcon.PAINTED if id=="F11" else Icon.PAINTED).has(id),"each new item has assigned production texture "+id)
			if not (SpellIcon.PAINTED if id=="F11" else Icon.PAINTED).has(id): continue
			var texture: Texture2D = (SpellIcon.PAINTED if id=="F11" else Icon.PAINTED)[id]
			check(texture.resource_path=="res://assets/ui/fire_formal_v1/"+PATHS[id],"production ID resolves expected approved image "+id)
			check(not assets.any(func(prior): return prior.path==texture.resource_path),"each new item has unique own source file "+id)
			var image: Image = texture.get_image()
			check(image != null and not image.is_empty(),"real source decodes "+id)
			if image == null or image.is_empty(): continue
			check(image.get_width()>=256 and image.get_height()>=256,"useful bitmap resolution "+id)
			check(image.detect_alpha()!=Image.ALPHA_NONE,"native alpha channel retained "+id)
			for corner in [Vector2i.ZERO,Vector2i(image.get_width()-1,0),Vector2i(0,image.get_height()-1),Vector2i(image.get_width()-1,image.get_height()-1)]:
				check(image.get_pixelv(corner).a<0.01,"transparent image corner %s %s" %[id,str(corner)])
			assets.append({"id":id,"name":item.name,"rarity":item.get("rarity", "spell"),"path":texture.resource_path,"dimensions":image.get_size(),"sha256":FileAccess.get_sha256(texture.resource_path)})
			var cell := index
			var origin := Vector2(48+cell*380,200)
			T.label(page,id+" · "+str(item.name),Rect2(origin,Vector2(288,46)),22,T.TEXT)
			T.label(page,("火系法术" if id=="F11" else str(item.get("rarity", ""))+" · 职业道具"),Rect2(origin+Vector2(0,48),Vector2(288,32)),18,T.MUTED)
			for pair in [[112.0,Vector2(12,104)],[40.0,Vector2(188,156)]]:
				if id=="F11":
					T.icon(page,id,Rect2(origin+pair[1],Vector2.ONE*float(pair[0])))
				else:
					var icon = Icon.new()
					icon.position = origin+pair[1]
					icon.size = Vector2.ONE*float(pair[0])
					icon.set_item(id,str(item.rarity))
					page.add_child(icon)
			T.label(page,"112 px                  40 px",Rect2(origin+Vector2(8,240),Vector2(276,36)),17,T.MUTED)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var label := "controlled-four-formal-fire-icons-%d" %(batch+1)
		if DisplayServer.get_name() != "headless":
			check(root.get_texture().get_image().save_png(OUT+label+".png")==OK,"save actual icon-control pixels "+label)
			captures.append(label)
	check(assets.size()==4,"all four new unique production icons rendered")
	await menu_catalog()
	check(source_hashes()==source_before,"production icon/catalog/UI source stable throughout native gallery and menu")
	FileAccess.open(OUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"details":failures,"assets":assets,"captures":captures,"source_sha256":source_before,"source_stable":source_hashes()==source_before,"scope":"Controlled native Godot production-icon matrix, not natural inventory. Actual Main catalog mouse selection and full detail text. 40-active-item catalog and four formal fire textures. Archived spirit IDs excluded from normal catalog. No gameplay effect claim from gallery."},"\t"))
	print("FORMAL FIRE MATERIALS: %d checks; %d failures" %[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func menu_catalog():
	if is_instance_valid(page): page.queue_free()
	await process_frame
	var protected: Dictionary={}
	for path in ["user://meta_progression_v1.json","user://display.cfg"]:
		protected[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	const TEST_SAVE="user://tests/formal_fire_catalog_visual.json"
	const TEST_PREFS="user://tests/formal_fire_catalog_visual.cfg"
	DirAccess.make_dir_recursive_absolute("user://tests")
	for path in [TEST_SAVE,TEST_SAVE+".tmp",TEST_SAVE+".bak",TEST_PREFS]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game=Main.new()
	game.save_path=TEST_SAVE
	game.preferences_path=TEST_PREFS
	root.add_child(game)
	game.set_process(false)
	await process_frame
	check(game.load_error.is_empty(),"actual Main loads merged catalog with isolated local account")
	var entry: Button=null
	for button in game.ui.page.find_children("*","Button",true,false):
		if button.text=="宝物图鉴": entry=button
	check(entry!=null,"actual home provides treasure catalog button")
	if entry!=null:
		await click_button(entry)
		for id in ["B11","P06","G04"]:
			var selected_button: Button=null
			for button in game.ui.page.find_children("*","Button",true,false):
				if str(button.get_meta("selection_id",""))==id: selected_button=button
			check(selected_button!=null,"actual scroll list contains current unique ID "+id)
			if selected_button==null: continue
			var scroll=game.ui.page.get_node_or_null("CatalogList")
			check(scroll!=null,"production catalog retains scroll list")
			if scroll!=null: scroll.ensure_control_visible(selected_button)
			await process_frame
			await process_frame
			await click_button(selected_button)
			check(game.selected==id,"real catalog mouse click selects "+id)
			var expected: Dictionary=Catalog.describe_artifact(id)
			var scope_name: String="职业道具"
			check(str(expected.get("scope_name",""))==scope_name,"actual selected category follows source scope "+id)
			var category_visible:=false
			for label in game.ui.page.find_children("*","Label",true,false):
				if label.is_visible_in_tree() and label.text.contains(scope_name): category_visible=true
			check(category_visible,"actual rendered detail shows category "+id)
			check(game.ui.detail_label.text.contains(str(expected.description)),"actual full rules text matches selected source "+id)
			await process_frame
			await RenderingServer.frame_post_draw
			var label: String="actual-catalog-"+id.to_lower()
			if DisplayServer.get_name()!="headless":
				check(root.get_texture().get_image().save_png(OUT+label+".png")==OK,"actual menu pixels "+label)
				captures.append(label)
		for selected_scope in ["generic","fire","all"]:
			var filter_button: Button=null
			for button in game.ui.page.find_children("*","Button",true,false):
				if str(button.get_meta("artifact_scope",""))==selected_scope: filter_button=button
			check(filter_button!=null,"actual catalog offers category filter "+selected_scope)
			if filter_button==null: continue
			await click_button(filter_button)
			var listed: Array=game.ui.page.find_children("*","Button",true,false).filter(func(button): return not str(button.get_meta("selection_id","")).is_empty())
			check(listed.size()=={"all":40,"generic":24,"fire":16}[selected_scope],"actual filter list count "+selected_scope)
			for button in listed:
				check(selected_scope=="all" or str(Catalog.describe_artifact(str(button.get_meta("selection_id",""))).scope)==selected_scope,"filtered row uses unique source category")
			await process_frame
			await RenderingServer.frame_post_draw
			var label: String="actual-catalog-filter-"+selected_scope
			if DisplayServer.get_name()!="headless":
				check(root.get_texture().get_image().save_png(OUT+label+".png")==OK,"actual category filter pixels "+label)
				captures.append(label)
		await spell_catalog_from_artifacts()
	game.queue_free()
	await process_frame
	for path in protected:
		check((FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent")==protected[path],"catalog QA preserves production account/preferences "+path)
	for path in [TEST_SAVE,TEST_SAVE+".tmp",TEST_SAVE+".bak",TEST_PREFS]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func spell_catalog_from_artifacts():
	var back: Button = null
	for button in game.ui.page.find_children("*","Button",true,false):
		if button.text == "‹  返回": back = button
	check(back != null, "real catalog back button exists")
	if back == null: return
	await click_button(back)
	var entry: Button = null
	for button in game.ui.page.find_children("*","Button",true,false):
		if button.text == "法术藏书": entry = button
	check(entry != null, "real home spell book exists")
	if entry == null: return
	await click_button(entry)
	var list: Array = game.ui.page.find_children("*","Button",true,false).filter(func(button):return not str(button.get_meta("selection_id", "")).is_empty())
	check(list.size() == 10, "normal spell catalog lists ten active formal fire spells")
	check(not list.any(func(button):return str(button.get_meta("selection_id", "")) == "F04"), "normal catalog excludes archived F04")
	var selected: Button = null
	for button in list:
		if str(button.get_meta("selection_id", "")) == "F11": selected = button
	check(selected != null, "real spell catalog contains F11")
	if selected == null: return
	game.ui.page.get_node("CatalogList").ensure_control_visible(selected)
	await process_frame
	await click_button(selected)
	check(game.selected == "F11" and game.ui.detail_label.text.contains(str(Catalog.describe_spell("F11").description)), "real mouse selects new formal spell source text")
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+"actual-catalog-f11.png")==OK, "native actual F11 catalog pixels")
	captures.append("actual-catalog-f11")

func click_button(button: Button):
	var point: Vector2=button.get_global_rect().get_center()*Vector2(root.size)/Vector2(1600,900)
	Input.warp_mouse(point)
	var motion:=InputEventMouseMotion.new()
	motion.position=point
	Input.parse_input_event(motion)
	await process_frame
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		Input.parse_input_event(event)
		await process_frame

func source_hashes() -> Dictionary:
	var result: Dictionary={}
	for path in ["res://tests/formal_fire_assets_visual.gd","res://scripts/ui/artifact_icon.gd","res://scripts/ui/arcane_icon.gd","res://scripts/main.gd","res://data/balance_candidates/first_run_v1.json","res://data/route_spell_runtime.json","res://scripts/ui/grimoire_catalog.gd","res://scripts/ui/atelier_ui.gd","res://data/generic_artifacts_v1.json","res://data/balance_candidates/fire_artifacts_v1.json"]:
		result[path]=FileAccess.get_sha256(path)
	for id in IDS:
		var path: String="res://assets/ui/fire_formal_v1/"+PATHS[id]
		result[path]=FileAccess.get_sha256(path)
	return result
