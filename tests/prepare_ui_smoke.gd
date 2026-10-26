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
const Catalog=preload("res://scripts/ui/grimoire_catalog.gd")
const RouteRun=preload("res://scripts/core/courtyard_route_run.gd")
const RoomDressing=preload("res://scripts/presentation/courtyard_room_dressing.gd")
const EnemyVisual=preload("res://scripts/presentation/route_enemy_visual.gd")
const OUTPUT="res://build/qa/battle-hud-preview-20261026"
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
	var report={"checks":checks,"failures":failures.size(),"details":failures,"scope":"Headless construction and text/rect reads of reachable menu screens, the current battle render environment, six room-dressing templates, and a real route snapshot refreshed into the combat HUD. Includes transparent spell-label backing checks plus material checks for Lina and route enemies. No screenshot, pixel readability, gameplay, natural route or performance evidence."}
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
	# Read-only eight-slot fixture verifies confirmed geometry and persistent names.
	var fixture: Dictionary = snapshot.duplicate(true)
	fixture.phase = "combat"
	fixture.spells = []
	var ids: Array = Catalog.load_catalog().base.spells.keys().filter(func(id): return Catalog.spell_name(str(id)).length() == 4).slice(0, 8)
	for index in range(8):
		var description: Dictionary = Catalog.describe_spell(str(ids[index]), 1)
		var spell: Dictionary = description.values.duplicate(true)
		spell.id = str(ids[index])
		spell.name = str(description.name)
		spell.level = int(description.level)
		spell.remaining = float(spell.get("cooldown", 1.0)) * (0.5 if index % 2 == 0 else 0.0)
		spell.cast_remaining = float(spell.get("windup", 0.5)) if index == 1 else 0.0
		fixture.spells.append(spell)
	hud.refresh(fixture)
	var legacy_titles: Array = hud.root.find_children("*", "Label", true, false).filter(func(node): return str(node.text).replace(" ", "").begins_with("法术构筑"))
	check(legacy_titles.is_empty(), "spell-construction heading and count are absent")
	for index in range(8):
		var slot: Control = hud.slots[index]
		var icon: Control = hud.slot_icons[index]
		var name_label: Label = hud.spell_labels[index]
		var level_label: Label = hud.cooldown_labels[index]
		check(slot.size == Vector2(84, 84), "spell slot is 84x84: " + str(index))
		check(slot.position == Vector2(432 + index * 94, 788), "spell slots keep one row at 94px pitch: " + str(index))
		check(icon.position == Vector2(15, 15) and icon.size == Vector2(54, 54), "spell icon uses confirmed inset and size: " + str(index))
		check((icon.position + icon.size * 0.5).distance_to(slot.size * 0.5) <= 2.0, "spell icon stays centered within 2px: " + str(index))
		check(name_label.visible and name_label.text == str(fixture.spells[index].name), "equipped spell name stays visible: " + str(index))
		check(is_equal_approx(name_label.size.x, 84) and name_label.size.y >= 20 and name_label.size.y <= 24 and is_equal_approx(name_label.position.y, slot.size.y), "name owns the row immediately below its slot: " + str(index))
		check(not name_label.clip_text and name_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "name row is centered without clipping: " + str(index))
		check(name_label.get_theme_stylebox("normal") is StyleBoxEmpty and level_label.get_theme_stylebox("normal") is StyleBoxEmpty, "name and level use transparent backings: " + str(index))
		check(name_label.get_theme_color("font_outline_color").a >= 0.8 and level_label.get_theme_color("font_outline_color").a >= 0.8 and name_label.get_theme_constant("outline_size") >= 2 and level_label.get_theme_constant("outline_size") >= 2, "name and level retain glyph-only contrast: " + str(index))
		check(str(name_label.text).length() == 4, "four-character name remains text-complete: " + str(index))
		var name_width: float = name_label.get_theme_font("font").get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		check(name_width <= name_label.size.x, "four-character name fits the 84px row: " + str(index))
		check(not Rect2(icon.position, icon.size).intersects(Rect2(level_label.position, level_label.size)), "level badge clears the icon body: " + str(index))
		check(level_label.visible and level_label.text == "%d级" % int(fixture.spells[index].level), "level badge remains visible and accurate: " + str(index))
		check(slot.get_global_rect().position.y + name_label.position.y + name_label.size.y <= 896.0, "slot and name row stay within the 900px logical canvas: " + str(index))
		var level_global := Rect2(slot.get_global_rect().position + level_label.position, level_label.size)
		check(not slot.get_global_rect().intersects(hud.artifact_bar.get_global_rect()) and not level_global.intersects(hud.artifact_bar.get_global_rect()), "spell slot and badge clear the artifact strip: " + str(index))
	var four_character_names: Array = Catalog.load_catalog().base.spells.keys().map(func(id): return Catalog.spell_name(str(id))).filter(func(name): return str(name).length() == 4)
	var name_font: Font = hud.spell_labels[0].get_theme_font("font")
	var widest_name: float = 0.0
	for display_name in four_character_names:
		widest_name = maxf(widest_name, name_font.get_string_size(str(display_name), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	check(not four_character_names.is_empty() and widest_name <= 84.0, "all existing four-character spell names fit an 84px row")
	fixture.spells = []
	hud.refresh(fixture)
	for index in range(8):
		check(hud.spell_labels[index].text.is_empty() and not hud.spell_labels[index].visible, "empty slot leaves no spell name behind: " + str(index))
	hud.free()
