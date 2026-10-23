extends SceneTree
## Automatic headless structural/immutable-state verification. No pixel capture,
## visible game, natural route, frame-time or performance measurement.
const Icon=preload("res://scripts/ui/gem_icon.gd")
const VFX=preload("res://scripts/presentation/route_gem_vfx.gd")
const UI=preload("res://scripts/ui/atelier_ui.gd")
const Meta=preload("res://scripts/core/meta_progression.gd")
const Controller=preload("res://scripts/main.gd")
const Catalog=preload("res://scripts/ui/grimoire_catalog.gd")
const HUD=preload("res://scripts/ui/first_room_ui.gd")
const OUTPUT="res://build/qa/gem-v3-implementation-20261022/ui-vfx"
var checks:int=0
var failures:Array=[]
var samples:Array=[]
var account
var ui
var controller
var renderer
const RECORDERS="""
var captured:Array=[]
func _capture_draw_colored_polygon(points:PackedVector2Array,color:Color):captured.append({"kind":"polygon","points":points,"color":color})
func _capture_draw_polyline(points:PackedVector2Array,color:Color,width:float=-1,antialiased:bool=false):captured.append({"kind":"line","points":points,"color":color,"width":width})
func _capture_draw_circle(center:Vector2,radius:float,color:Color):captured.append({"kind":"circle","center":center,"radius":radius,"color":color})
"""
const VFX_RECORDERS="""
var captured_transforms:Dictionary={}
var captured_colors:Dictionary={}
func capture_transform(index:int,transform:Transform3D):captured_transforms[index]=transform
func capture_color(index:int,color:Color):captured_colors[index]=color
"""

func _initialize():call_deferred("execute")
func check(ok:bool,label:String):
	checks+=1
	if not ok:
		failures.append(label)
		push_error("Gem V3 UI/VFX: "+label)

func execute():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	icon_geometry()
	var stage=Node3D.new()
	root.add_child(stage)
	var source:String=FileAccess.get_file_as_string("res://scripts/presentation/route_gem_vfx.gd")
	source=source.replace("_lines.multimesh.set_instance_transform(","capture_transform(").replace("_lines.multimesh.set_instance_color(","capture_color(")
	var script=GDScript.new()
	script.source_code=source+VFX_RECORDERS
	check(script.reload()==OK,"intercepted production MultiMesh write source parses")
	renderer=script.new()
	stage.add_child(renderer)
	visual_boundaries()
	workshop_routes()
	stage.free()
	if is_instance_valid(ui):ui.free()
	if is_instance_valid(controller):controller.free()
	var hashes:Dictionary={}
	for path in ["res://tests/gem_v3_visual_ui_tests.gd","res://scripts/core/meta_progression.gd","res://scripts/core/magic_gems.gd","res://scripts/core/route_gem_combat.gd","res://scripts/core/route_gem_echo.gd","res://scripts/ui/gem_icon.gd","res://scripts/ui/gem_workshop.gd","res://scripts/ui/gem_workshop_actions.gd","res://scripts/ui/atelier_ui.gd","res://scripts/ui/first_room_ui.gd","res://scripts/main.gd","res://scripts/presentation/route_gem_vfx.gd","res://scripts/presentation/route_spell_vfx.gd","res://scripts/presentation/first_room_view.gd","res://data/magic_gems_v1.json"]:hashes[path]=FileAccess.get_sha256(path)
	FileAccess.open(OUTPUT+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"details":failures,"samples":samples,"source_sha256":hashes,"account_rng_seed":20261022,"scope":"Original engine headless actual draw-source and MultiMesh-write primitive capture, Node3D/Control construction and real temporary-account requests, bounded immutable controlled-snapshot VFX. No screenshot, pixel readability, gameplay, natural route or performance evidence.","corrections":["Dummy headless RenderingServer returns empty MultiMesh.buffer and zero instance transforms. Geometry/color determinism is checked by intercepting actual production set_instance_transform/color calls, not by comparing unavailable native readback."]},"\t"))
	print("GEM V3 VISUAL UI checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func icon_geometry():
	var source:String=FileAccess.get_file_as_string("res://scripts/ui/gem_icon.gd")
	for method in ["draw_colored_polygon","draw_polyline","draw_circle"]:source=source.replace(method+"(","_capture_"+method+"(")
	var script=GDScript.new()
	script.source_code=source+RECORDERS
	check(script.reload()==OK,"intercepted production icon parses")
	var icon=script.new()
	var ids:Array=[]
	for id in Icon.CORE_IDS:ids.append("core:"+id)
	for id in Icon.STAT_IDS:ids.append("stat:"+id)
	check(ids.size()==18,"ten core and eight stat identities")
	for side in [32,44,64,96]:
		var fingerprints:Dictionary={}
		for id in ids:
			icon.item_id=id
			icon.rarity="gold" if str(id).begins_with("core:") else "purple"
			icon.tier=3
			icon.size=Vector2.ONE*side
			icon.captured.clear()
			icon._draw()
			var commands:Array=icon.captured.duplicate(true)
			var geometry:Array=[]
			for command in commands:
				var bounds:Rect2
				if command.kind=="circle":bounds=Rect2(command.center-Vector2.ONE*command.radius,Vector2.ONE*command.radius*2)
				else:
					bounds=Rect2(command.points[0],Vector2.ZERO)
					for p in command.points:bounds=bounds.expand(p)
					if command.kind=="line":bounds=bounds.grow(float(command.width)*.5)
					else:check(not Geometry2D.triangulate_polygon(command.points).is_empty(),"polygon triangulates "+id)
				check(bounds.position.x>=0 and bounds.position.y>=0 and bounds.end.x<=side+.001 and bounds.end.y<=side+.001,"icon geometry within control "+id+" @"+str(side))
				var shape:Dictionary=command.duplicate(true)
				shape.erase("color")
				geometry.append(shape)
			var fingerprint:String=str(geometry).sha256_text()
			check(not fingerprints.has(fingerprint),"distinct geometry regardless of tint "+id)
			fingerprints[fingerprint]=id
			icon.captured.clear()
			icon._draw()
			check(icon.captured==commands,"deterministic icon "+id)
			samples.append({"id":id,"size":side,"primitives":commands.size(),"geometry_sha256":fingerprint})
		check(fingerprints.size()==18,"all eighteen shapes unique @"+str(side))
	icon.free()

func base_snapshot(core:String)->Dictionary:
	return {"phase":"combat","room_revision":7,"combat_time":2.0,"player":{"pos":Vector2.ZERO,"face":Vector2.UP,"health":150.0,"max_health":300.0,"shield":60.0,"max_shield":100.0},"gems":{"core":core,"clock":2.0,"pending_count":2,"coffin_reserves":{1:{"amount":80.0,"cap":800.0,"pos":Vector2(1,1),"token":1}},"embers":{1:{"amount":50.0,"ticks":3,"cap":300.0,"pos":Vector2(1,1),"token":1}},"schools":{"lightning_charges":4,"lightning_stored":100.0,"wind_layers":3,"wind_flow_until":4.0,"earth_anchor_id":9,"earth_anchor_pos":Vector2(1,1),"earth_progress":1.0,"earth_mature":true,"spirit_points":3}},"effects":[]}

func inspect_snapshot(snapshot:Dictionary,label:String,reduced:bool=false)->Dictionary:
	var before:Dictionary=snapshot.duplicate(true)
	renderer.captured_transforms.clear()
	renderer.captured_colors.clear()
	renderer.sync_snapshot(snapshot,null,{"reduced_motion":reduced})
	var first:Dictionary=renderer.get_debug_state()
	var transforms:Dictionary=renderer.captured_transforms.duplicate(true)
	var colors:Dictionary=renderer.captured_colors.duplicate(true)
	check(snapshot==before,"input immutable "+label)
	check(int(first.line_count)<=VFX.LINE_LIMIT,"line limit "+label)
	check(int(first.line_count)==renderer._lines.multimesh.visible_instance_count,"visible count matches "+label)
	check(transforms.size()==int(first.line_count) and colors.size()==int(first.line_count),"each visible line writes one transform and color "+label)
	for _repeat in 3:
		renderer.captured_transforms.clear()
		renderer.captured_colors.clear()
		renderer.sync_snapshot(snapshot,null,{"reduced_motion":reduced})
	check(renderer.get_debug_state()==first,"repeat does not advance state or clock "+label)
	check(renderer.captured_transforms==transforms and renderer.captured_colors==colors,"repeat preserves actual submitted geometry/colors "+label)
	check(snapshot==before,"repeat leaves snapshot immutable "+label)
	samples.append({"vfx":label,"lines":first.line_count,"coverage":first.coverage,"reduced":reduced,"submitted_geometry_sha256":str(transforms).sha256_text(),"submitted_color_sha256":str(colors).sha256_text()})
	return first

func visual_boundaries():
	for core in Icon.CORE_IDS:
		var snapshot:Dictionary=base_snapshot(core)
		var state:Dictionary=inspect_snapshot(snapshot,core)
		check(int(state.line_count)>0,"each activated core has source-dependent feedback "+core)
		var reduced:Dictionary=inspect_snapshot(snapshot,core+" reduced",true)
		check(int(reduced.line_count)<=int(state.line_count),"reduced motion geometry bounded "+core)
	for core in ["inferno","coffin"]:
		var snapshot:Dictionary=base_snapshot(core)
		renderer.captured_transforms.clear()
		renderer.sync_snapshot(snapshot,null,{})
		var old_transform:Transform3D=renderer.captured_transforms[0]
		snapshot.actors=[{"id":1,"health":100,"pos":Vector2(3,4)}]
		renderer.captured_transforms.clear()
		renderer.sync_snapshot(snapshot,null,{})
		check(renderer.captured_transforms[0]!=old_transform,"stock marker follows current live actor rather than old hit position "+core)
	var effects:Dictionary={"gem_inferno":{},"gem_coffin":{"reason":"natural"},"gem_lightning":{"phase":"preview","targets":[{"actor_id":1,"pos":Vector2(1,1),"amount":100}]},"gem_earth":{},"gem_spirit":{"targets":[{"actor_id":1,"pos":Vector2(1,1),"amount":100}]},"gem_wind":{},"gem_fracture":{"from":Vector2.ZERO,"to":Vector2(1,1)},"gem_echo":{"kind_shape":"segment","from":Vector2.ZERO,"to":Vector2(1,1),"width":.2}}
	for kind in effects:
		var snapshot:Dictionary=base_snapshot("")
		var effect:Dictionary=effects[kind].duplicate(true)
		effect.merge({"kind":kind,"pos":Vector2.ZERO,"radius":2.0,"life":.3,"max_life":.5})
		snapshot.effects=[effect]
		var state:Dictionary=inspect_snapshot(snapshot,kind)
		check(state.coverage.has(kind),"actual event identity handled "+kind)
	var stress:Dictionary=base_snapshot("")
	for _index in 1000:stress.effects.append({"kind":"gem_fracture","from":Vector2.ZERO,"to":Vector2(2,2),"life":.3,"max_life":.5})
	check(int(inspect_snapshot(stress,"finite capacity guard").line_count)==VFX.LINE_LIMIT,"large supplied event set stops at hard capacity")
	var stock_heavy:Dictionary=base_snapshot("inferno")
	for index in 200:stock_heavy.gems.embers[index]={"amount":100,"ticks":3,"pos":Vector2.ZERO,"cap":300}
	stock_heavy.effects=[{"kind":"gem_inferno","pos":Vector2.ZERO,"radius":2.0,"life":.3,"max_life":.5}]
	var stocked:Dictionary=inspect_snapshot(stock_heavy,"persistent markers reserve space for real payout")
	check(int(stocked.line_count)>VFX.LINE_LIMIT-256 and stocked.coverage.has("gem_inferno"),"payout has visible budget after dense stock markers")
	stress.phase="pickup"
	check(int(inspect_snapshot(stress,"room cleared").line_count)==0,"noncombat no residual geometry")
	var hud=HUD.new()
	for core in Icon.CORE_IDS:
		var snapshot:Dictionary=base_snapshot(core)
		var before:Dictionary=snapshot.duplicate(true)
		check(not hud.gem_status_text(snapshot).is_empty(),"HUD status supports "+core)
		check(snapshot==before,"HUD status read only "+core)
	hud.free()

func button(action:String,payload:String=""):
	for b in ui.page.find_children("*","Button",true,false):
		if str(b.get_meta("ui_action",""))==action and str(b.get_meta("ui_payload",""))==payload:return b
	return null

func press(action:String,payload:String=""):
	var b=button(action,payload)
	check(b!=null,"reachable button "+action+" "+payload)
	if b==null:return
	check(not b.disabled,"enabled button "+action+" "+payload)
	if not b.disabled:b.pressed.emit()

func workshop_routes():
	var path:String=OUTPUT+"/temporary-account.json"
	if FileAccess.file_exists(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	account=Meta.new(path)
	check(account.load_state().ok,"isolated account loads")
	var rng=RandomNumberGenerator.new()
	rng.seed=20261022
	account._state.gem_state.rng_state=str(rng.state)
	account._state.dust=1000
	account._state.gem_state.essence=1000
	controller=Controller.new()
	controller.save_path=Meta.TEST_SAVE_ROOT+"gem-v3-ui-controller.json"
	controller.preferences_path=OUTPUT+"/temporary-display.cfg"
	controller.meta=account
	controller.screen="gem"
	ui=UI.new()
	root.add_child(ui)
	controller.ui=ui
	ui.requested.connect(controller.handle_request)
	controller.refresh()
	var before:Dictionary=account.get_state()
	check(ui.page.find_children("*","Button",true,false).size()>10,"core catalog constructed")
	check(account.get_state()==before,"building core catalog consumes no account state")
	press("gem_core_unlock","inferno")
	check(account.get_state().gem_state.slots[0]=="core:inferno","core free unlock reaches actual equipment")
	check(int(account.get_state().dust)==1000,"first core is free")
	press("gem_select","core:wind")
	press("gem_core_unlock","wind")
	check(int(account.get_state().dust)==1000-int(account.gems.rules.core_unlock_cost),"second core charges runtime data cost")
	press("gem_core_equip","wind")
	check(account.get_state().gem_state.slots[0]=="core:wind","paid core can be equipped through actual request")
	press("gem_tab","craft")
	for stat in ["attack","cdr","shield"]:
		press("gem_main_stat",stat)
		press("gem_attribute_starter",stat)
	check(int(account.get_state().gem_state.starter_attributes_claimed)==3,"all three self-chosen starter stones reachable")
	press("gem_main_stat","health")
	press("gem_craft_rarity","blue")
	press("gem_craft","blue:health")
	var id:String=controller.selected
	check(account.gems.find(account.get_state().gem_state,id).affixes[0].stat=="health","craft honors chosen main")
	press("gem_equip","1:"+id)
	press("gem_tool","reforge")
	press("gem_raise","0")
	press("gem_upgrade","")
	var upgraded:Dictionary=account.gems.find(account.get_state().gem_state,id)
	check(upgraded.rarity=="purple" and int(upgraded.affixes[0].tier)==2,"upgrade preserves previous main tier")
	press("gem_retype_open","1")
	var stat:String=ui.gem_retype_stat
	press("gem_retype","1:"+stat)
	check(account.gems.find(account.get_state().gem_state,id).affixes[1].stat==stat,"direct retype reached selected legal type")
	press("gem_reforge","1")
	var pending:Dictionary=account.get_state().gem_state.pending_reforge
	check(not pending.is_empty(),"random retype opens persistent paid comparison")
	if not pending.is_empty():press("gem_resolve","%d:old"%int(pending.token))
	press("gem_tool","")
	press("gem_lock",id)
	press("gem_tool","reforge")
	check(button("gem_raise","0").disabled,"locked stone cannot raise through UI")
	press("gem_tool","")
	press("gem_rules","")
	press("gem_rules_section","work")
	var labels:PackedStringArray=[]
	for l in ui.page.find_children("*","Label",true,false):labels.append(l.text)
	check("\n".join(labels).contains("100%成功"),"rules explain deterministic growth")
	press("gem_rules_close","")
	press("gem_tab","attributes")
	press("gem_draw","10")
	check(ui.gem_results.size()==10,"ten draw results reachable through controller")
	press("gem_results_close","")
	check(ui.gem_tab=="attributes","results return to correct tab")
	press("gem_batch_preview","")
	var essence_before:int=int(account.get_state().gem_state.essence)
	press("gem_salvage_confirm","")
	check(int(account.get_state().gem_state.essence)>essence_before,"batch salvage preview confirmation commits real essence")
	for b in ui.page.find_children("*","Button",true,false):
		if str(b.get_meta("ui_action","")).begins_with("gem_"):
			check(b.size.x>=44 and b.size.y>=44,"gem action minimum 44px "+str(b.text))
			check(b.get_theme_stylebox("focus").get_border_width(SIDE_LEFT)>=2,"visible keyboard focus "+str(b.text))
	samples.append({"ui":"core/free/paid/starter/craft/equip/upgrade/tier/direct/random/locked/rules/draw paths","account_path":path,"real_account_accessed":false})
	legacy_pending_and_conversion()

func legacy_pending_and_conversion():
	var state:Dictionary=account.get_state()
	state.version=Meta.EIGHT_CORE_SAVE_VERSION
	var affixes:Array=[]
	for stat in ["attack","health","shield"]:
		var line:Dictionary=account.gems.line(stat,1,false)
		line.erase("role")
		affixes.append(line)
	var gem:Dictionary={"id":"gem-1","serial":1,"rarity":"gold","core":"inferno","affixes":affixes,"locked":false}
	state.gem_state={"inventory":[gem],"slots":["","","",""],"serial":1,"draws":1,"gold_misses":0,"rare_misses":0,"first_gold":false,"rng_state":"1234567","essence":17,"salvaged":0,"work_serial":1,"pending_reforge":{"gem_id":"gem-1","mode":"core","index":-1,"old":"inferno","candidate":"reactor","cost":account.gems.rules.legacy_workshop.core_cost,"token":1}}
	FileAccess.open(account.save_path,FileAccess.WRITE).store_string(JSON.stringify(state))
	check(account.load_state().ok,"old paid pending fixture loads without automatic migration")
	controller.selected="gem-1"
	ui.gem_tab="attributes"
	controller.refresh()
	var text:PackedStringArray=[]
	for label in ui.page.find_children("*","Label",true,false):text.append(label.text)
	check("\n".join(text).contains("旧机制："),"old paid core candidate displays old mechanism")
	check("\n".join(text).contains(str(account.gems.rules.legacy_cores.inferno.name)),"old core name preserved in comparison")
	press("gem_resolve","1:new")
	check(account.gems.is_modern(account.get_state().gem_state),"resolve old result before migration")
	check(account.get_state().gem_state.inventory[0].rarity=="transition","old attribute asset preserved after choosing")
	press("gem_main_stat","health")
	var before:Dictionary=account.get_state()
	check(button("gem_convert","health")!=null,"explicit conversion confirmation is reachable")
	check(account.get_state()==before,"conversion preview does not mutate account")
	press("gem_convert","health")
	var converted:Dictionary=account.gems.find(account.get_state().gem_state,"gem-1")
	check(converted.rarity=="purple" and converted.affixes[0].stat=="health","voluntary conversion selects existing main")
	check(int(account.get_state().gem_state.essence)==17,"old paid comparison and free conversion do not charge again")
