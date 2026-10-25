extends SceneTree
## Headless construction check for the preparation screen after the second UI
## pass. It builds real screens through the controller and reads control text,
## rects and metadata only. No screenshot, pixel, gameplay, natural route or
## performance measurement.
const UI=preload("res://scripts/ui/atelier_ui.gd")
const Meta=preload("res://scripts/core/meta_progression.gd")
const Controller=preload("res://scripts/main.gd")
const RoomView=preload("res://scripts/presentation/first_room_view.gd")
const RoomUI=preload("res://scripts/ui/first_room_ui.gd")
const RouteRun=preload("res://scripts/core/courtyard_route_run.gd")
const RoomDressing=preload("res://scripts/presentation/courtyard_room_dressing.gd")
const EnemyVisual=preload("res://scripts/presentation/route_enemy_visual.gd")
const OUTPUT="res://build/qa/combat-presentation-20261025"
var checks:int=0
var failures:Array=[]
var account
var ui
var controller
var account_path:String=""

func _initialize():call_deferred("execute")
func check(ok:bool,label:String):
	checks+=1
	if not ok:
		failures.append(label)
		push_error("Prepare UI: "+label)

func buttons()->Array:
	return ui.page.find_children("*","Button",true,false)
func labels()->String:
	var lines:PackedStringArray=[]
	for node in ui.page.find_children("*","Label",true,false):lines.append(node.text)
	return "\n".join(lines)
func by_action(action:String,payload:String="")->Button:
	for b in buttons():
		if str(b.get_meta("ui_action",""))==action and str(b.get_meta("ui_payload",""))==payload:return b
	return null

func execute():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Meta.TEST_SAVE_ROOT))
	account_path=Meta.TEST_SAVE_ROOT+"prepare_ui_%d.json"%Time.get_ticks_usec()
	if FileAccess.file_exists(account_path):DirAccess.remove_absolute(ProjectSettings.globalize_path(account_path))
	account=Meta.new(account_path)
	check(account.load_state().ok,"isolated account loads")
	controller=Controller.new()
	controller.save_path=account_path
	controller.preferences_path=OUTPUT+"/temporary-display.cfg"
	controller.meta=account
	ui=UI.new()
	root.add_child(ui)
	controller.ui=ui
	ui.requested.connect(controller.handle_request)
	controller.screen="prepare"
	var before:Dictionary=account.get_state()
	controller.refresh()
	check(account.get_state()==before,"building preparation consumes no account state")
	preparation_copy()
	preparation_geometry()
	reachable_screens()
	render_baseline()
	room_dressing_baseline()
	combat_hud_baseline()
	if is_instance_valid(ui):ui.free()
	if is_instance_valid(controller):controller.free()
	if not account_path.is_empty() and FileAccess.file_exists(account_path):DirAccess.remove_absolute(ProjectSettings.globalize_path(account_path))
	var report={"checks":checks,"failures":failures.size(),"details":failures,"scope":"Headless construction and text/rect reads of reachable menu screens, the current battle render environment, six room-dressing templates, and a real route snapshot refreshed into the combat HUD. Includes material checks for Lina and route enemies. No screenshot, pixel readability, gameplay, natural route or performance evidence."}
	FileAccess.open(OUTPUT+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("PREPARE UI SMOKE checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func preparation_copy():
	var text:=labels()
	check(text.contains("本局学派"),"school band keeps its heading")
	check(text.contains("出发装备 · 4 槽"),"gem section heading")
	check(text.contains("属性总览"),"stat section heading")
	check(buttons().any(func(b):return str(b.text).contains("宝石工坊")),"in-panel workshop link")
	check(text.contains("预计通关 +"),"route income summary")
	check(not text.contains("全系列"),"internal school wording removed")
	check(not text.contains("18 个"),"implementation count removed")
	check(not text.contains("起手"),"opening-hand jargon removed")
	check(not text.contains("基础 ＋ 宝石 ＝ 最终"),"duplicated stat legend removed")
	check(not text.contains("无属性贡献"),"empty-slot filler removed")
	check(not text.contains("界面预览"),"preview copy removed")
	check(not text.contains("首房"),"legacy first-room copy removed")
	check(not text.contains("点击槽位进入工坊"),"inline slot hint removed")
	var cta:Button=by_action("start_route")
	check(cta!=null and cta.text=="出发    ›","primary action reads 出发")
	check(by_action("start_room")==null,"legacy first-room entry removed")
	var preview_actions=buttons().filter(func(b):return str(b.get_meta("ui_action",""))=="navigate" and str(b.get_meta("ui_payload","")) in ["opening","hud","reward","chest","shop","pause","result"])
	check(preview_actions.is_empty(),"preview entries removed")
	check(by_action("open_codex","gear")!=null,"catalyst switch stays reachable")
	check(by_action("navigate","gem")!=null,"workshop entry stays reachable")

func preparation_geometry():
	var slots=buttons().filter(func(b):return str(b.tooltip_text).begins_with("打开宝石工坊"))
	check(slots.size()==4,"four gem slots stay focusable")
	for b in slots:check(b.size.x>=300.0 and b.size.y>=80.0,"gem slot target is readable")
	var grid_labels=["攻击力","生命上限","护盾上限","防御","暴击率","暴击伤害","冷却缩减","战斗移速"]
	var text:=labels()
	for name in grid_labels:check(text.contains(name),"stat row "+name)
	var cta:Button=by_action("start_route")
	var cta_rect:=Rect2(cta.position,cta.size)
	check(Rect2(0,0,1600,900).encloses(cta_rect),"primary action inside the canvas")
	check(is_equal_approx(cta_rect.end.x,1544.0),"primary action keeps the right margin")
	check(cta_rect.size.y>=56.0,"primary action is a full-size target")
	var panel:Panel=null
	for node in ui.page.find_children("*","Panel",true,false):
		if node.size.is_equal_approx(Vector2(808,566)):panel=node
	check(panel!=null,"right panel keeps its reserved rect")
	if panel!=null:
		check(panel.position.y+panel.size.y<=cta_rect.position.y,"panel clears the action row")
		check(panel.position.y>=182.0,"panel starts below the page rule")
	var arrows=buttons().filter(func(b):return str(b.get_meta("ui_action",""))=="rotate")
	check(arrows.size()==2,"portrait keeps both rotate controls")
	if arrows.size()==2:
		var name_label=ui.page.find_children("*","Label",true,false).filter(func(l):return l.text=="莉奈")
		check(not name_label.is_empty(),"character name stays visible")
		if not name_label.is_empty():
			var name_rect:Rect2=name_label[0].get_global_rect()
			for b in arrows:check(not b.get_global_rect().intersects(name_rect),"rotate control clears the name row")

func reachable_screens():
	for next in ["home","prepare","catalyst","gem","codex","spells","artifacts","settings"]:
		controller.navigate(next)
		check(ui.screen==next,"screen builds "+next)
		check(ui.page.get_child_count()>0,"screen draws content "+next)
	controller.navigate("prepare")
	var text:=labels()
	check(text.contains("出发装备 · 4 槽"),"returning to preparation keeps the new block")

func render_baseline():
	var room=RoomView.new()
	root.add_child(room)
	var environment_nodes:Array=room.world.find_children("*","WorldEnvironment",true,false)
	check(environment_nodes.size()==1,"battle stage has one explicit render environment")
	if environment_nodes.size()==1:
		var environment:Environment=environment_nodes[0].environment
		check(environment.tonemap_mode==Environment.TONE_MAPPER_FILMIC,"battle uses the filmic art-direction baseline")
		check(environment.fog_enabled and environment.fog_density>0.0 and environment.fog_density<=0.006,"distance haze stays restrained")
		check(not environment.glow_enabled,"global glow remains disabled for combat readability")
	var directional_lights:Array=room.world.find_children("*","DirectionalLight3D",true,false)
	check(directional_lights.size()==2,"battle retains one key and one fill light")
	var shadow_light_count:int=0
	var warm_key_count:int=0
	for light in directional_lights:
		if light.shadow_enabled:shadow_light_count+=1
		if light.light_color.r>light.light_color.b:warm_key_count+=1
	check(shadow_light_count==1 and warm_key_count==1,"one warm shadowed key and one cool fill establish the lighting hierarchy")
	check(is_equal_approx(room.camera.fov,34.0),"render pass leaves the gameplay camera unchanged")
	var gold=room._materials.get("entrance_gold",null)
	check(gold!=null and gold.metallic>0.0 and gold.roughness<0.7,"metal trim is distinct from rough masonry")
	var lina_material=room._lina_materials[0] if not room._lina_materials.is_empty() else null
	check(lina_material!=null,"Lina model exposes prepared surface materials")
	if lina_material!=null:
		check(lina_material.roughness<=0.82,"Lina keeps a tighter specular response than raw masonry")
	var enemy_metal=EnemyVisual._material("boss_gold",Color("e8be71"))
	var enemy_cloth=EnemyVisual._material("caster_robe",Color("64507e"))
	check(enemy_metal.metallic>0.0 and enemy_metal.roughness<0.7,"enemy metal trim is separated from matte bodies")
	check(enemy_cloth.roughness>0.9,"enemy cloth stays matte against metal trim")
	room.free()

func room_dressing_baseline():
	for template in ["outer_court","processional_court","twin_pillars","long_colonnade","staggered_walls","broken_forecourt"]:
		var dressing=RoomDressing.new()
		root.add_child(dressing)
		var debug:Dictionary=dressing.build_room({"room_id":5,"template_id":template,"source_kind":"normal",
			"geometry":{"floor":{"width":20.0,"depth":24.0},"blocks":[]}})
		check(int(debug.get("mesh_count",0))>0,"room dressing builds "+template)
		check(int(debug.get("flat_count",0))>0,"room dressing keeps flush floor identity "+template)
		check(int(debug.get("unsafe_vertices",1))==0,"no tall geometry enters the arena "+template)
		check(float(debug.get("max_inside_height",1.0))<=0.06,"inside geometry stays flush "+template)
		dressing.free()

func combat_hud_baseline():
	var run=RouteRun.new()
	check(run.configure({},20261017).ok and run.choose_initial("F01"),"HUD baseline uses a real configured route")
	run.step(1.0/120.0,Vector2.ZERO)
	var snapshot:Dictionary=run.get_snapshot()
	check(str(snapshot.get("phase",""))=="combat","real route snapshot enters combat")
	var hud=RoomUI.new()
	root.add_child(hud)
	hud.set_visual_options({"view_hints":true,"damage_numbers":true,"reduced_motion":false})
	hud.refresh(snapshot)
	check(hud.health_label.text.contains("莉奈") and hud.health_label.text.contains("生命"),"vitals keep the readable life line")
	check(hud.health_bar.size.y>=12 and hud.shield_bar.size.y>=8,"life and shield bars stay thick enough to read")
	check(hud.spell_labels[0].text==str(snapshot.get("spells",[{}])[0].get("name","")),"first slot shows the real equipped spell")
	check(hud.enemies_label.position.y>=100.0,"route HUD places the alive count below the room header")
	check(not hud.artifact_bar.visible,"empty artifact strip stays hidden")
	check(hud._loadout_line.visible==bool(hud.preferences.get("view_hints",true)) or hud._loadout_line.text.is_empty(),"low-frequency loadout summary follows the hint setting")
	hud.free()
