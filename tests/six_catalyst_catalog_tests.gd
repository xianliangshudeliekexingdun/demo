extends SceneTree
## Source and control geometry checks only. No rendered frames, screenshots or gameplay.
const Catalog=preload("res://scripts/ui/grimoire_catalog.gd")
const Atelier=preload("res://scripts/ui/atelier_ui.gd")
const Icon=preload("res://scripts/ui/arcane_icon.gd")
const EquipmentIcon=preload("res://scripts/ui/equipment_icon.gd")
const Meta=preload("res://scripts/core/meta_progression.gd")
const IDS=["MC04","MC05","MC06","MC07","MC08","MC09"]
const SCHOOLS=["fire","ice","lightning","wind","earth","spirit"]
const SAVE="user://tests/meta_progression/six_catalyst_catalog_only.json"
var checks:int=0
var failures:Array=[]

func _initialize(): call_deferred("execute")

func check(value:bool,label:String):
	checks+=1
	if not value:
		failures.append(label)
		push_error("Six catalyst catalog: "+label)

func execute():
	DirAccess.make_dir_recursive_absolute(SAVE.get_base_dir())
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(SAVE)
	var meta=Meta.new(SAVE)
	var loaded:Dictionary=meta.load_state()
	check(bool(loaded.get("ok",false)),"isolated test account loads: "+str(loaded.get("error","")))
	if bool(loaded.get("ok",false)):
		var items:Array=meta.get_items("catalyst")
		var spec:Dictionary=meta.get_catalog().get("spell_sampling",{})
		check(items.size()==6,"six visible catalyst choices")
		check(spec.get("catalyst_affinity_by_level",[]).size()==3,"three priority ranks from shared sampling source")
		check(Icon.PROCEDURAL_CATALYSTS==["MC06","MC07","MC08","MC09"],"four new catalysts use explicit procedural glyphs")
		check(EquipmentIcon.PAINTED.has("MC04") and EquipmentIcon.PAINTED.has("MC05"),"approved fire/ice images retained")
		for index in IDS.size():
			var id:String=IDS[index]
			var status:Dictionary=meta.get_item_status("catalyst",id)
			check(str(status.get("school",""))==SCHOOLS[index],id+" school source")
			check(str(status.get("effect_kind",""))=="school_priority",id+" effect has priority identity")
			check(status.get("effect_by_level",[])==spec.get("catalyst_affinity_by_level",[]),id+" priority from source, no legacy multiplier")
			check(status.get("related_spells",[]).size()==10,id+" ten related spells")
			check(Icon.CATALYST_SCHOOLS.get(id,"")==SCHOOLS[index],id+" icon school routing")
			var detail:String=Catalog.catalyst_description(SCHOOLS[index],10,spec)
			check(detail.contains("起手独立选择") and detail.contains("不是固定单卡概率"),id+" explains independent start and conditional odds")
			check(detail.contains("不保证必出") and detail.contains("前置先过滤"),id+" explains eligibility and no guarantee")
			check(detail.contains("权重×2"),id+" explains learned-spell upgrade weight")
			check(detail.contains("均衡混学可卸下触媒"),id+" explains concentration tradeoff")
			var font:Font=Atelier.T.make_theme().default_font
			check(font.get_multiline_string_size(detail,HORIZONTAL_ALIGNMENT_LEFT,492,19).y<=210.0,id+" detail fits reserved text height")
			for level in range(1,4):
				var reference:String=Catalog.catalyst_reference_text(spec,level)
				var strength:float=float(spec.catalyst_affinity_by_level[level-1])
				var expected:float=1.0/6.0+5.0/6.0*strength
				check(reference.contains(Catalog._percent(strength)),id+" priority rank "+str(level))
				check(reference.contains(Catalog._percent(expected)) and reference.contains("均合法且同权"),id+" conditional first-card reference "+str(level))
				check(reference.contains("不是必出") and reference.contains("实际概率"),id+" no fixed-odds/guarantee claim "+str(level))
		for level in range(0,4):
			for id in IDS: meta._state.levels[id]=level
			meta._state.free_claimed.catalyst=level>0
			meta._state.equipped.catalyst="MC06" if level>0 else ""
			var before:Dictionary=meta.get_state()
			var ui=Atelier.new()
			ui.page=Control.new()
			ui.meta=meta
			ui.catalog=Catalog.new()
			ui.selected="MC06"
			ui._catalyst_cards(items)
			var cards:Array=ui.page.get_children()
			check(cards.size()==6,"six constructed cards rank "+str(level))
			var previous:Array=[]
			for i in cards.size():
				var card:Control=cards[i]
				var rect:Rect2=Rect2(card.position,card.size)
				check(Rect2(54,330,876,450).encloses(rect),"card inside reserved area "+str(i))
				for old in previous: check(not old.intersects(rect),"distinct card rectangles "+str(i))
				previous.append(rect)
				var found_button:bool=false
				var found_icon:bool=false
				for node in card.get_children():
					if node is Button:
						found_button=true
						check(node.size.x>=44 and node.size.y>=44,"inspect target size "+str(i))
						check(Rect2(Vector2.ZERO,card.size).encloses(Rect2(node.position,node.size)),"inspect contained "+str(i))
						check(str(node.get_meta("selection_id",""))==IDS[i],"keyboard/focus selection identity "+str(i))
						check(not node.tooltip_text.is_empty(),"inspect offers probability context "+str(i))
					elif node is Icon:
						found_icon=true
						check(IDS[i] in Icon.PROCEDURAL_CATALYSTS and node.spell_id==IDS[i],"programmatic catalyst identity "+str(i))
					elif node is EquipmentIcon:
						found_icon=true
						check(IDS[i] in ["MC04","MC05"] and node.item_id==IDS[i],"painted catalyst identity "+str(i))
				check(found_button and found_icon,"card has named action and correct icon "+str(i))
			check(meta.get_state()==before,"UI card construction leaves account untouched rank "+str(level))
			ui.page.free()
			ui.free()
		meta=null
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(SAVE)
	var output:String="res://build/qa/six-school-sampling-20261021/catalog"
	DirAccess.make_dir_recursive_absolute(output)
	var hashes:Dictionary={}
	for path in ["res://scripts/ui/atelier_ui.gd","res://scripts/ui/grimoire_catalog.gd","res://scripts/ui/arcane_icon.gd","res://tests/six_catalyst_catalog_tests.gd","res://data/route_spell_sampling.json"]:
		hashes[path]=FileAccess.get_sha256(path)
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"details":failures,"source_sha256":hashes,"scope":"Headless catalog and detached Control geometry/source identity only; no rendered frames, pixel readability, performance, natural route or real account changes."},"  "))
	print("SIX CATALYST CATALOG checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
