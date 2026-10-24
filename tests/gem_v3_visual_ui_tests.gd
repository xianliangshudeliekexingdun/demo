extends SceneTree
## Headless structure and account checks for the v4 gem page. No pixel capture,
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
var account_path:String
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
	gem_routes()
	stage.free()
	if is_instance_valid(ui):ui.free()
	if is_instance_valid(controller):controller.free()
	if not account_path.is_empty() and FileAccess.file_exists(account_path):DirAccess.remove_absolute(ProjectSettings.globalize_path(account_path))
	var hashes:Dictionary={}
	for path in ["res://tests/gem_v3_visual_ui_tests.gd","res://scripts/core/meta_progression.gd","res://scripts/core/magic_gems.gd","res://scripts/core/route_gem_combat.gd","res://scripts/core/route_gem_echo.gd","res://scripts/ui/gem_icon.gd","res://scripts/ui/gem_workshop.gd","res://scripts/ui/atelier_ui.gd","res://scripts/ui/first_room_ui.gd","res://scripts/main.gd","res://scripts/presentation/route_gem_vfx.gd","res://scripts/presentation/route_spell_vfx.gd","res://scripts/presentation/first_room_view.gd","res://data/magic_gems_v1.json"]:hashes[path]=FileAccess.get_sha256(path)
	FileAccess.open(OUTPUT+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"details":failures,"samples":samples,"source_sha256":hashes,"account_rng_seed":20261022,"scope":"Original engine headless actual draw-source and MultiMesh-write primitive capture, Node3D/Control construction and real isolated-account gem page requests. No screenshot, pixel readability, gameplay, natural route or performance evidence.","corrections":["Dummy headless RenderingServer returns empty MultiMesh.buffer and zero instance transforms. Geometry/color determinism is checked by intercepting actual production set_instance_transform/color calls, not by comparing unavailable native readback."]},"\t"))
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

func seed_extra_gems() -> String:
	var state:Dictionary=account.get_state()
	var lib=account.gems
	var extras:Array=[
		{"rarity":"gold","stats":["attack","health","shield"],"core":"inferno","tiers":[1,2,3]},
		{"rarity":"green","stats":["speed"],"core":"","tiers":[1]},
		{"rarity":"blue","stats":["defense","crit_rate"],"core":"","tiers":[1,2]},
	]
	var gold_id:String=""
	for entry in extras:
		var serial:int=int(state.gem_state.serial)+1
		var affixes:Array=[]
		for index in entry.stats.size():
			affixes.append(lib.line(str(entry.stats[index]),int(entry.tiers[index]),entry.rarity!="gold" and index==0))
		state.gem_state.serial=serial
		state.gem_state.draws=serial
		state.gem_state.inventory.append({"id":"gem-%d"%serial,"serial":serial,"rarity":entry.rarity,"affixes":affixes,"core":entry.core,"locked":false,"origin":"draw"})
		if entry.rarity=="gold":gold_id="gem-%d"%serial
	FileAccess.open(account_path,FileAccess.WRITE).store_string(JSON.stringify(state))
	check(account.load_state().ok,"seeded gold fixture loads "+account.error)
	return gold_id

func gem_routes():
	account_path=Meta.TEST_SAVE_ROOT+"gem_ui_%d.json"%Time.get_ticks_usec()
	if FileAccess.file_exists(account_path):DirAccess.remove_absolute(ProjectSettings.globalize_path(account_path))
	account=Meta.new(account_path)
	check(account.load_state().ok,"isolated account loads")
	var rng=RandomNumberGenerator.new()
	rng.seed=20261022
	account._state.gem_state.rng_state=str(rng.state)
	account._state.dust=1000
	account._state.gem_state.essence=1000
	controller=Controller.new()
	controller.save_path=account_path
	controller.preferences_path=OUTPUT+"/temporary-display.cfg"
	controller.meta=account
	controller.screen="gem"
	ui=UI.new()
	root.add_child(ui)
	controller.ui=ui
	ui.requested.connect(controller.handle_request)
	var before:Dictionary=account.get_state()
	controller.refresh()
	check(ui.page.find_children("*","Button",true,false).size()>10,"gem page constructed")
	check(account.get_state()==before,"building the gem page consumes no account state")
	press("gem_draw","10")
	check(ui.gem_results.size()==10,"ten draw results reachable through controller")
	var results_state:Dictionary=account.get_state()
	press("gem_results_close","")
	check(ui.gem_results.is_empty(),"results close returns to the gem page")
	check(account.get_state()==results_state,"closing results does not mutate the account")
	var drawn:String=str(controller.selected)
	check(not drawn.is_empty(),"draw selects the newest gem")
	press("gem_select",drawn)
	press("gem_equip","0:"+drawn)
	check(account.get_state().gem_state.slots[0]==drawn,"equipment action reaches the account in slot zero")
	press("gem_equip","1:"+drawn)
	check(account.get_state().gem_state.slots[0].is_empty() and account.get_state().gem_state.slots[1]==drawn,"moving through the UI never duplicates a slot reference")
	press("gem_equip","1:")
	check(account.get_state().gem_state.slots[1].is_empty(),"unequip button clears the slot")
	var gold_id:String=seed_extra_gems()
	controller.refresh()
	var inventory_size:int=account.get_state().gem_state.inventory.size()
	check(inventory_size>=7,"inventory spans more than one page")
	press("gem_page","1")
	check(ui.gem_page==1,"next page action updates the page index")
	press("gem_page","0")
	check(ui.gem_page==0,"previous page action returns to the first page")
	press("gem_select",gold_id)
	var gold:Dictionary=account.gems.find(account.get_state().gem_state,gold_id)
	check(gold.rarity=="gold" and gold.affixes.size()==3,"gold fixture selected")
	press("gem_tool","reforge")
	check(ui.gem_tool=="reforge","reforge tool opens")
	check(button("gem_reroll","")!=null and button("gem_reroll","").size.y>=44,"reforge confirmation is a full-size action")
	press("gem_reroll_toggle","0")
	check(ui.gem_reroll_locks==[0],"attribute lock toggled in the UI")
	check(str(button("gem_reroll_toggle","0").text).begins_with("已固定"),"locked attribute is visibly marked")
	var old_affixes:Array=account.gems.find(account.get_state().gem_state,gold_id).affixes
	var essence_before:int=int(account.get_state().gem_state.essence)
	press("gem_reroll","")
	var pending:Dictionary=account.get_state().gem_state.pending_reforge
	check(not pending.is_empty() and int(pending.cost)==35,"reforge charges base plus one lock")
	check(int(account.get_state().gem_state.essence)==essence_before-35,"reforge fee reaches the account")
	check(pending.old.affixes==old_affixes and pending.candidate.affixes[0]==old_affixes[0],"locked attribute survives in the candidate")
	press("gem_resolve","%d:new"%int(pending.token))
	check(account.get_state().gem_state.pending_reforge.is_empty(),"adopting the candidate clears the comparison")
	var adopted:Dictionary=account.gems.find(account.get_state().gem_state,gold_id)
	check(adopted.affixes==pending.candidate.affixes and adopted.affixes[0]==old_affixes[0],"adopted result keeps the locked line")
	press("gem_tool","reforge")
	press("gem_reroll","")
	var keep_pending:Dictionary=account.get_state().gem_state.pending_reforge
	check(not keep_pending.is_empty(),"second reforge opens a comparison")
	var keep_old:Array=keep_pending.old.affixes
	press("gem_resolve","%d:old"%int(keep_pending.token))
	check(account.get_state().gem_state.pending_reforge.is_empty() and account.gems.find(account.get_state().gem_state,gold_id).affixes==keep_old,"keep-old restores the exact previous result")
	press("gem_lock",gold_id)
	check(bool(account.gems.find(account.get_state().gem_state,gold_id).locked),"lock action reaches the account")
	check(button("gem_tool","reforge").disabled,"locked gem cannot open reforge")
	check(button("gem_single_preview","").disabled,"locked gem cannot be salvaged")
	press("gem_lock",gold_id)
	check(not bool(account.gems.find(account.get_state().gem_state,gold_id).locked),"lock action toggles back")
	var rules_state:Dictionary=account.get_state()
	press("gem_rules","")
	check(ui.gem_show_rules,"rules action opens the rules page")
	controller.handle_request("gem_rules_section","work")
	check(ui.gem_rules_section=="work","rules section action is accepted")
	var labels:PackedStringArray=[]
	for l in ui.page.find_children("*","Label",true,false):labels.append(l.text)
	check("\n".join(labels).contains("金色宝石＝一个特殊效果＋三条属性"),"rules explain the gold model")
	check("\n".join(labels).contains("每固定一项"),"rules explain per-lock pricing")
	check(account.get_state()==rules_state,"reading rules does not mutate the account")
	press("gem_rules_close","")
	check(not ui.gem_show_rules,"rules close returns to the gem page")
	var blue_id:String=""
	var inventory_copy:Array=account.get_state().gem_state.inventory.duplicate(true)
	inventory_copy.reverse()
	for gem in inventory_copy:
		if gem.rarity=="blue" and not bool(gem.locked) and gem.id not in account.get_state().gem_state.slots:blue_id=str(gem.id);break
	check(not blue_id.is_empty(),"single salvage has an eligible blue gem")
	if not blue_id.is_empty():
		press("gem_select",blue_id)
		press("gem_single_preview","")
		check(ui.gem_salvage_ids==[blue_id],"single preview targets the selected gem")
		var essence_single:int=int(account.get_state().gem_state.essence)
		press("gem_salvage_confirm","")
		check(int(account.get_state().gem_state.essence)==essence_single+3,"single blue salvage adds three essence")
		check(account.gems.find(account.get_state().gem_state,blue_id).is_empty(),"single salvage removes the gem")
	press("gem_batch_preview","")
	check(ui.gem_tool=="salvage" and not ui.gem_salvage_ids.is_empty(),"batch preview selects idle green and blue gems")
	check(button("gem_salvage_confirm","").size.y>=44,"salvage confirmation is a full-size action")
	var essence_after_single:int=int(account.get_state().gem_state.essence)
	var batch_count:int=ui.gem_salvage_ids.size()
	press("gem_salvage_confirm","")
	check(int(account.get_state().gem_state.essence)>essence_after_single,"batch salvage commits real essence")
	check(account.get_state().gem_state.inventory.size()==inventory_size-1-batch_count,"salvage removes exactly the previewed gems")
	check(ui.gem_tool.is_empty() and ui.selected.is_empty(),"salvage confirmation clears the tool and selection")
	for b in ui.page.find_children("*","Button",true,false):
		if str(b.get_meta("ui_action","")).begins_with("gem_"):
			check(b.size.x>=40 and b.size.y>=40,"gem action has a usable size "+str(b.text))
			var focus=b.get_theme_stylebox("focus")
			check(focus!=null and focus.get_border_width(SIDE_LEFT)>=2,"visible keyboard focus "+str(b.text))
	samples.append({"ui":"draw/page/equip/reforge-lock/adopt/keep/lock/rules/batch-salvage/single-salvage","account_path":account_path,"real_account_accessed":false})
