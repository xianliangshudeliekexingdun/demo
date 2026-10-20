extends SceneTree
## Production icon controls and actual Main catalog; the matrix is controlled
## asset inspection, not an inventory acquired through natural rewards.
const T = preload("res://scripts/ui/atelier_theme.gd")
const Catalog = preload("res://scripts/ui/grimoire_catalog.gd")
const Icon = preload("res://scripts/ui/artifact_icon.gd")
const SpellIcon = preload("res://scripts/ui/arcane_icon.gd")
const Main = preload("res://scripts/main.gd")
const SourceBinding = preload("res://tests/formal_ice_source_binding.gd")
const OUT = "res://build/qa/formal-ice-implementation-20261018/materials/"
const SPELL_IDS = ["I01","I02","I03","I04","I05","I06","I07","I08","I09","I10"]
const ITEM_IDS = ["IB01","IB02","IB03","IB04","IB05","IB06","IB07","IB08","IB09","IB10","IP01","IP02","IP03","IG01","IG02","IG03"]
const TEST_SAVE="user://tests/formal_ice_catalog_visual.json"
const TEST_PREFS="user://tests/formal_ice_catalog_visual.cfg"
var checks: int=0
var failures: Array=[]
var captures: Array=[]
var assets: Array=[]
var page: Control
var game
var before: Dictionary={}
var protected: Dictionary={}

func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks+=1
	if not ok:
		failures.append(label)
		push_error("Formal ice materials: "+label)
func sources() -> Dictionary:
	var result: Dictionary={}
	for path in ["res://tests/formal_ice_assets_visual.gd","res://scripts/main.gd","res://scripts/ui/atelier_ui.gd","res://scripts/ui/grimoire_catalog.gd","res://scripts/ui/arcane_icon.gd","res://scripts/ui/artifact_icon.gd","res://data/ice_spells_v1.json","res://data/ice_artifacts_v1.json","res://data/balance_candidates/first_run_v1.json","res://data/balance_candidates/fire_artifacts_v1.json","res://data/generic_artifacts_v1.json"]:
		result[path]=FileAccess.get_sha256(path)
	for id in SPELL_IDS+ITEM_IDS:
		var path: String="res://assets/ui/ice_formal_v1/"+id.to_lower()+".png"
		result[path]=FileAccess.get_sha256(path)
	result.merge(SourceBinding.capture(["res://tests/formal_ice_assets_visual.gd","res://scripts/main.gd","res://project.godot"]),true)
	return result
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	before=sources()
	check(DisplayServer.get_name()!="headless","native rendered display required")
	if DisplayServer.get_name()=="headless":
		finish()
		return
	DisplayServer.window_set_size(Vector2i(1600,900))
	var all: Array=Catalog.artifacts()
	check(all.size()==56,"normal catalog56 active treasures")
	for scope in ["generic","fire","ice"]:
		check(all.filter(func(item):return str(item.scope)==scope).size()=={"generic":24,"fire":16,"ice":16}[scope],"normal catalog actual scope count "+scope)
	check(not all.any(func(item):return str(item.id) in ["B04","P01","G02"]),"archived spirit not normal catalog")
	var ids: Array=SPELL_IDS+ITEM_IDS
	for batch in 4:
		if is_instance_valid(page): page.queue_free()
		await process_frame
		page=Control.new()
		page.size=Vector2(1600,900)
		page.theme=T.make_theme()
		root.add_child(page)
		var bg=ColorRect.new()
		bg.color=Color("101522")
		bg.size=page.size
		page.add_child(bg)
		T.label(page,"正式冰系 · 法术与职业宝物图标 %d / 4" % (batch+1),Rect2(48,20,1504,56),32,T.GOLD)
		T.label(page,"受控素材矩阵，非自然库存 · 生产控件112px / 40px · 原生透明边缘与小图识别",Rect2(48,80,1504,42),21,T.MUTED)
		for index in range(batch*8,mini(ids.size(),batch*8+8)):
			var id: String=str(ids[index])
			var is_spell: bool=id in SPELL_IDS
			var detail: Dictionary=Catalog.describe_spell(id) if is_spell else Catalog.describe_artifact(id)
			check(not detail.is_empty(),"real catalog description "+id)
			var painted: Dictionary=SpellIcon.PAINTED if is_spell else Icon.PAINTED
			check(painted.has(id),"production control binds unique painted ID "+id)
			if not painted.has(id): continue
			var texture: Texture2D=painted[id]
			var expected: String="res://assets/ui/ice_formal_v1/"+id.to_lower()+".png"
			check(texture.resource_path==expected,"expected approved path "+id)
			check(not assets.any(func(item):return item.path==expected),"unique material source "+id)
			var bitmap: Image=texture.get_image()
			check(bitmap!=null and not bitmap.is_empty(),"native image decodes "+id)
			if bitmap==null or bitmap.is_empty(): continue
			check(bitmap.get_width()>=256 and bitmap.get_height()>=256,"useful bitmap resolution "+id)
			check(bitmap.detect_alpha()!=Image.ALPHA_NONE,"native alpha preserved "+id)
			for corner in [Vector2i.ZERO,Vector2i(bitmap.get_width()-1,0),Vector2i(0,bitmap.get_height()-1),Vector2i(bitmap.get_width()-1,bitmap.get_height()-1)]:
				check(bitmap.get_pixelv(corner).a<0.01,"transparent native corner "+id+str(corner))
			assets.append({"id":id,"name":detail.name,"rarity":detail.get("rarity","spell"),"path":expected,"dimensions":bitmap.get_size(),"sha256":FileAccess.get_sha256(expected)})
			var cell: int=index%8
			var origin: Vector2=Vector2(48+(cell%4)*380,150+int(cell/4)*330)
			T.label(page,id+" · "+str(detail.name),Rect2(origin,Vector2(340,42)),21,T.TEXT)
			T.label(page,"冰系法术" if is_spell else str(detail.get("rarity",""))+" · 职业宝物",Rect2(origin+Vector2(0,44),Vector2(340,32)),18,T.MUTED)
			for pair in [[112.0,Vector2(10,92)],[40.0,Vector2(188,146)]]:
				if is_spell:
					T.icon(page,id,Rect2(origin+pair[1],Vector2.ONE*float(pair[0])))
				else:
					var icon=Icon.new()
					icon.position=origin+pair[1]
					icon.size=Vector2.ONE*float(pair[0])
					icon.set_item(id,str(detail.rarity))
					page.add_child(icon)
			T.label(page,"112 px                  40 px",Rect2(origin+Vector2(8,226),Vector2(320,32)),17,T.MUTED)
		await capture("controlled-ice-icons-page-%d" % (batch+1))
	check(assets.size()==26,"all26 distinct new production icons inspected")
	await actual_catalog()
	finish()
func capture(label: String):
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+label+".png")==OK,"actual Godot raster capture "+label)
	captures.append(label)
func click_button(button: Button):
	var point: Vector2=button.get_global_rect().get_center()*Vector2(root.size)/Vector2(1600,900)
	Input.warp_mouse(point)
	var motion=InputEventMouseMotion.new()
	motion.position=point
	Input.parse_input_event(motion)
	await process_frame
	for pressed in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		Input.parse_input_event(event)
		await process_frame
func text_button(text: String) -> Button:
	for button in game.ui.page.find_children("*","Button",true,false):
		if button.text==text: return button
	return null
func select_catalog_id(id: String, is_spell: bool):
	var button: Button=null
	for candidate in game.ui.page.find_children("*","Button",true,false):
		if str(candidate.get_meta("selection_id",""))==id: button=candidate
	check(button!=null,"real Main list exposes "+id)
	if button==null: return
	var scroll=game.ui.page.get_node_or_null("CatalogList")
	check(scroll!=null,"real catalog scroll container")
	if scroll!=null: scroll.ensure_control_visible(button)
	await process_frame
	await process_frame
	await click_button(button)
	var detail: Dictionary=Catalog.describe_spell(id) if is_spell else Catalog.describe_artifact(id)
	check(game.selected==id and game.ui.detail_label.text.contains(str(detail.description)),"actual mouse selects full production description "+id)
	await capture("actual-catalog-"+id.to_lower())
func actual_catalog():
	if is_instance_valid(page): page.queue_free()
	await process_frame
	for path in ["user://meta_progression_v1.json","user://display.cfg"]: protected[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	DirAccess.make_dir_recursive_absolute("user://tests")
	for path in [TEST_SAVE,TEST_SAVE+".tmp",TEST_SAVE+".bak",TEST_PREFS]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game=Main.new()
	game.save_path=TEST_SAVE
	game.preferences_path=TEST_PREFS
	root.add_child(game)
	game.set_process(false)
	await process_frame
	check(game.load_error.is_empty(),"actual Main loads isolated account")
	var treasures: Button=text_button("宝物图鉴")
	check(treasures!=null,"actual Main treasure catalog entry")
	if treasures!=null:
		await click_button(treasures)
		for id in ["IB07","IP02","IG02","IG03"]: await select_catalog_id(id,false)
		for scope in ["generic","fire","ice","all"]:
			var filter: Button=null
			for button in game.ui.page.find_children("*","Button",true,false):
				if str(button.get_meta("artifact_scope",""))==scope: filter=button
			check(filter!=null,"real category filter "+scope)
			if filter==null: continue
			await click_button(filter)
			var listed: Array=game.ui.page.find_children("*","Button",true,false).filter(func(button):return not str(button.get_meta("selection_id","")).is_empty())
			check(listed.size()=={"all":56,"generic":24,"fire":16,"ice":16}[scope],"actual filtered list count "+scope)
			for button in listed:
				check(scope=="all" or str(Catalog.describe_artifact(str(button.get_meta("selection_id",""))).scope)==scope,"actual filtered row source category")
			await capture("actual-treasure-filter-"+scope)
	var back: Button=text_button("‹  返回")
	check(back!=null,"actual catalog back navigation")
	if back!=null: await click_button(back)
	var spells: Button=text_button("法术藏书")
	check(spells!=null,"actual Main spell catalog entry")
	if spells!=null:
		await click_button(spells)
		var listed: Array=game.ui.page.find_children("*","Button",true,false).filter(func(button):return not str(button.get_meta("selection_id","")).is_empty())
		check(listed.size()==20,"normal spell catalog20 active fire/ice, not archived F04")
		check(not listed.any(func(button):return str(button.get_meta("selection_id",""))=="F04"),"archive excluded from normal spell list")
		for id in ["I01","I05","I07","I09","I10"]: await select_catalog_id(id,true)
	game.queue_free()
	await process_frame
	for path in protected: check((FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent")==protected[path],"production account/preferences unchanged "+path)
	for path in [TEST_SAVE,TEST_SAVE+".tmp",TEST_SAVE+".bak",TEST_PREFS]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
func finish():
	check(sources()==before,"production material/catalog sources fixed throughout inspection")
	FileAccess.open(OUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"details":failures,"assets":assets,"captures":captures,"source_sha256":before,"source_stable":sources()==before,"scope":"Native Godot production-icon controlled matrix and actual Main catalog mouse navigation. Twenty-six icons at112/40px, twenty active spells and56 active treasures. No natural inventory, gameplay balance, player acceptance or account progression claim."},"\t"))
	print("FORMAL ICE MATERIALS checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
