extends SceneTree
## Controlled read-only snapshots rendered by production FirstRoomUI, not natural stock.
const RoomUI=preload("res://scripts/ui/first_room_ui.gd")
const Route=preload("res://scripts/core/courtyard_route_run.gd")
const Catalog=preload("res://scripts/ui/grimoire_catalog.gd")
const T=preload("res://scripts/ui/atelier_theme.gd")
const Sources=preload("res://tests/formal_ice_source_binding.gd")
const OUT="res://build/qa/spell-replacement-20261018/cards/"
const IDS=["IB01","IB02","IB03","IB04","IB05","IB06","IB07","IB08","IB09","IB10","IP01","IP02","IP03","IG01","IG02","IG03"]
var checks: int=0
var failures: Array=[]
var captures: Array=[]
var layouts: Array=[]
var before: Dictionary={}
var ui
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error("Replacement cards: "+label)
func sources()->Dictionary:
	var result: Dictionary=Sources.capture(["res://tests/spell_replacement_cards_visual.gd","res://scripts/main.gd","res://project.godot"])
	for id in IDS+["I01","I02","I03"]:
		var path: String="res://assets/ui/ice_formal_v1/"+id.to_lower()+".png"
		result[path]=FileAccess.get_sha256(path)
	return result
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	before=sources()
	check(DisplayServer.get_name()!="headless","native rendered cards required")
	if DisplayServer.get_name()=="headless":finish();return
	DisplayServer.window_set_size(Vector2i(1600,900))
	var background=ColorRect.new()
	background.color=Color("131a28")
	background.size=Vector2(1600,900)
	root.add_child(background)
	ui=RoomUI.new()
	root.add_child(ui)
	await process_frame
	ui.set_visual_options({"reduced_motion":true})
	var annotation=CanvasLayer.new()
	annotation.layer=21
	root.add_child(annotation)
	var notice=Control.new()
	annotation.add_child(notice)
	T.label(notice,"受控生产卡牌检查 · 16冰系职业宝物 / 起手摘要 · 非自然库存",Rect2(40,115,1520,40),23,T.GOLD)
	var b=Route.new()
	check(b.configure({"route_school":"ice"},20261018).ok,"real Route creates display fixture")
	var snapshot: Dictionary=b.get_snapshot()
	snapshot.phase="artifact"
	for page in range(6):
		snapshot.artifact_choices=[]
		for index in range(page*3,mini(IDS.size(),page*3+3)):
			var description: Dictionary=Catalog.describe_artifact(str(IDS[index]))
			snapshot.artifact_choices.append({"id":str(IDS[index]),"name":description.name,"rarity":description.rarity})
		ui.last_modal=""
		ui.refresh(snapshot)
		await process_frame
		await process_frame
		for card in ui._choice_cards:
			check(card.reveal_complete,"controlled card is fully revealed")
			var texts: Array=[]
			for label in card.face.find_children("*","Label",true,false):
				var rect: Rect2=label.get_rect()
				var font_size: int=label.get_theme_font_size("font_size")
				var required: float=label.get_theme_font("font").get_height(font_size)*label.get_line_count()
				check(rect.end.y<=432.01,"all card label bounds inside face: "+str(label.text))
				if rect.position.y>=350:check(rect.end.y<=414.01,"requirement remains above ornate card bottom safe edge")
				if rect.position.y>=204:
					check(required<=rect.size.y+1,"body/requirement complete line height fits: "+str(label.text))
				texts.append({"text":label.text,"lines":label.get_line_count(),"rect":rect,"required_height":required})
			layouts.append({"id":card.hit.get_meta("choice_id"),"texts":texts})
		await capture("controlled-ice-career-cards-%d"%(page+1))
	snapshot=b.get_snapshot()
	ui.last_modal=""
	ui.refresh(snapshot)
	await process_frame
	await capture("controlled-final-ice-starters-summary")
	check(ui._choice_cards.size()==3,"three formal ice starter cards")
	for id in ["I01","I02"]:
		check(str(Catalog.describe_spell(id).get("summary","")).length()<40,"ice starter summary stays a compact sentence "+id)
	finish()
func capture(label: String):
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+label+".png")==OK,"save genuine production UI pixels "+label)
	captures.append(label)
func finish():
	check(sources()==before,"controlled card sources stable")
	FileAccess.open(OUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"details":failures,"captures":captures,"layouts":layouts,"source_sha256":before,"source_stable":sources()==before,"scope":"Explicit read-only display fixture using actual FirstRoomUI/Catalog/ChoiceCard;16 profession cards and formal ice starter summary. Not natural offer/inventory or a combat test."},"\t"))
	print("REPLACEMENT CARD PIXELS checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
