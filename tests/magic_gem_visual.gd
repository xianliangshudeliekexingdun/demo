extends SceneTree
## Native production Main/UI, isolated funded draw account and natural first-room
## combat. Funded draws are explicitly not evidence of natural dust acquisition.
const Main = preload("res://scripts/main.gd")
const Meta = preload("res://scripts/core/meta_progression.gd")
const OUT = "res://build/qa/magic-gems-v2-20261020/visual/"
const SAVE = "user://tests/meta_progression/magic_gem_visual.json"
var game
var checks: int = 0
var failures: Array = []
var captures: Array = []
var production: Dictionary = {}
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures.append(label)
		push_error("Gem visual: " + label)
func button(text: String):
	for b in game.ui.page.find_children("*", "Button", true, false):
		if b.text == text: return b
	return null
func click(b):
	check(b != null and not b.disabled, "real mouse target exists")
	if b == null or b.disabled: return
	await process_frame
	await process_frame
	var point: Vector2 = b.get_global_rect().get_center()
	for pressed in [true,false]:
		var event = InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
func capture(label: String, audit: bool = true):
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+label+".png") == OK,"native screenshot "+label)
	captures.append(label)
	if not audit:return
	for text in game.ui.page.find_children("*","Label",true,false):
		if not text.is_visible_in_tree():continue
		check(text.get_line_count()<=text.get_visible_line_count(),"all lines fit "+text.text)
		if text.autowrap_mode==TextServer.AUTOWRAP_OFF:
			var font:Font=text.get_theme_font("font")
			check(font.get_string_size(text.text,HORIZONTAL_ALIGNMENT_LEFT,-1,text.get_theme_font_size("font_size")).x<=text.size.x+1.0,"single-line label fits "+text.text)
	for b in game.ui.page.find_children("*","Button",true,false):
		if not b.is_visible_in_tree():continue
		var font:Font=b.get_theme_font("font")
		check(font.get_string_size(b.text,HORIZONTAL_ALIGNMENT_LEFT,-1,b.get_theme_font_size("font_size")).x<=b.size.x-12,"button label fits "+b.text)
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	check(DisplayServer.get_name()!="headless","native pixels required")
	for path in ["user://meta_progression_v1.json","user://display.cfg"]:production[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	DisplayServer.window_set_size(Vector2i(1600,900))
	game=Main.new()
	game.save_path=SAVE
	game.preferences_path="user://tests/meta_progression/magic_gem_visual.cfg"
	if FileAccess.file_exists(SAVE):DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	root.add_child(game)
	game.set_process(false)
	check(game.load_error.is_empty(),"production Main loads isolated account")
	game.navigate("gem")
	await capture("01-empty-starter-1600")
	await click(button("生机宝石 · 免费领取"))
	# Funding is a declared UI fixture. All subsequent gem instances are sampled
	# and committed through the production draw service, with real pity and RNG.
	var funded:Dictionary=game.meta.get_state()
	funded.dust=5000
	check(game.meta._write_state(funded).ok and game.meta.load_state().ok,"declared funded UI fixture")
	game.refresh()
	await click(button("连续十次 · 50魔尘"))
	check(game.ui.gem_results.size()==10 and game.meta.get_state().dust==4950,"real button draws exactly ten")
	await capture("02-ten-results-1600")
	await click(button("查看背包"))
	var owned:Dictionary={}
	for batch in 100:
		for gem in game.meta.get_gems():
			if gem.rarity=="gold":owned[gem.core]=gem
		if owned.size()==8:break
		check(game.meta.request_draw_gems(10).ok,"production samples funded display matrix")
	check(owned.size()==8,"all eight core descriptions use real sampled instances")
	var selected_id:String=""
	for core in game.meta.gems.rules.cores:
		if not owned.has(core):continue
		selected_id=str(owned[core].id)
		game.handle_request("gem_select",selected_id)
		game.handle_request("gem_equip","0:"+selected_id)
		await capture("03-core-"+str(core)+"-1600")
	var index:int=1
	for gem in game.meta.get_gems():
		if index>=4:break
		if str(gem.id)!=selected_id and gem.rarity in ["purple","gold"]:
			game.handle_request("gem_equip","%d:%s"%[index,gem.id])
			index+=1

	# Real UI transactions: lock, batch preview, cost-before-choice, navigation.
	var protected_gem:Dictionary={}
	for gem in game.meta.get_gems():
		if gem.rarity in ["green","blue"] and gem.id not in game.meta.get_state().gem_state.slots:
			protected_gem=gem
			break
	game.handle_request("gem_lock",str(protected_gem.id))
	var before_batch:Dictionary=game.meta.get_state()
	await click(button("分解闲置绿蓝"))
	await capture("04a-salvage-batch-1600")
	check(str(protected_gem.id) not in game.ui.gem_salvage_ids,"locked green excluded from batch preview")
	var confirm=null
	for candidate in game.ui.page.find_children("*","Button",true,false):
		if candidate.text.begins_with("确认分解"):confirm=candidate
	await click(confirm)
	check(game.meta.gems.find(game.meta.get_state().gem_state,str(protected_gem.id)).locked,"locked item survives batch")
	check(game.meta.get_state().gem_state.gold_misses==before_batch.gem_state.gold_misses and game.meta.get_state().gem_state.draws==before_batch.gem_state.draws,"batch does not change draw pity")
	game.handle_request("gem_select",selected_id)
	await click(button("改良"))
	await capture("04b-reforge-three-lines-1600")
	await click(button("改良此条 · 3精粹"))
	var pending:Dictionary=game.meta.get_state().gem_state.pending_reforge
	check(not pending.is_empty(),"real reforge button generates saved candidate")
	await capture("04c-affix-old-new-1600")
	await click(button("保留原结果"))
	check(game.meta.get_state().gem_state.pending_reforge.is_empty(),"old result button resolves candidate")
	await click(button("重洗核心 · 60精粹"))
	pending=game.meta.get_state().gem_state.pending_reforge
	await capture("04d-core-old-new-1600")
	var held:Dictionary=pending.duplicate(true)
	game.handle_request("back","")
	game.navigate("gem")
	check(game.meta.get_state().gem_state.pending_reforge==held,"leave and return preserves pending choice")
	await click(button("采用新结果"))
	check(game.meta.gems.find(game.meta.get_state().gem_state,selected_id).core==held.candidate,"new result applies once")
	game.handle_request("gem_tool","")
	game.handle_request("gem_select",str(owned.reactor.id))
	await click(button("分解"))
	await capture("04e-gold-salvage-preview-1600")
	await click(button("返回宝石"))
	game.handle_request("gem_rules","")
	await capture("04-probabilities-1600")
	await click(button("分解与改良"))
	await capture("04f-workshop-rules-1600")
	game.handle_request("back","")
	DisplayServer.window_set_size(Vector2i(1280,720))
	game.refresh()
	await capture("05-four-slots-1280")
	game.handle_request("gem_select",selected_id)
	game.handle_request("gem_tool","reforge")
	await capture("05a-reforge-1280")
	game.handle_request("back","")
	game.handle_request("gem_rules","")
	await capture("06-probabilities-1280")
	game.handle_request("back","")
	game.ui.gem_rules_section="draw"
	game.handle_request("gem_draw","1")
	await capture("07-single-result-1280")
	game.handle_request("back","")
	check(game.screen=="gem" and game.ui.gem_results.is_empty(),"back closes result before leaving workshop")
	# Keyboard focus uses production native buttons, including pagination.
	var next=button("›")
	if next!=null and not next.disabled:
		await process_frame
		await process_frame
		next.grab_focus()
		var event=InputEventKey.new()
		event.keycode=KEY_ENTER
		event.physical_keycode=KEY_ENTER
		event.pressed=true
		Input.parse_input_event(event)
		await process_frame
		event=InputEventKey.new()
		event.keycode=KEY_ENTER
		event.physical_keycode=KEY_ENTER
		event.pressed=false
		Input.parse_input_event(event)
		await process_frame
		check(game.ui.gem_page==1,"keyboard activates pagination")
	game.handle_request("gem_equip","0:"+str(owned.sacrifice.id))
	game.navigate("prepare")
	await capture("08-preparation-1280")
	var before:int=int(game.meta.get_state().dust)
	game.start_courtyard_route()
	game._handle_room_request("room_initial","F01")
	check(game.room_run.gem_core()=="sacrifice" and game.room_run.get_snapshot().account_rewards,"real route has core and account settlement token")
	for tick in 12000:
		game.room_run.step(1.0/120.0)
		if game.room_run.clear_count>0:break
		if tick==360:
			game._refresh_room(0)
			await capture("09-natural-first-room-core-1280",false)
	check(game.room_run.cleared_rooms==[1],"production combat naturally clears first room")
	game._finish_room("abandon")
	check(game.room_settlement.get("ok",false) and game.room_settlement.dust_earned==1 and game.meta.get_state().dust==before+1,"natural clear credits exactly one magic dust")
	await capture("10-real-settlement-1280",false)
	game._handle_room_request("room_return","")
	check(game.room_run==null and game.screen=="prepare", "settled run returns to preparation")
	game.navigate("gem")
	await capture("11-return-to-workshop-1280")
	game.navigate("catalyst")
	await capture("12-catalyst-compatibility-1280")
	for path in production:check((FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent")==production[path],"real account and display preferences unchanged")
	var report:Dictionary={"checks":checks,"failures":failures.size(),"details":failures,"captures":captures,"scope":"Native production Main/UI; explicitly funded draw matrix; first-room combat and one-dust settlement are natural, no health/wallet injection during combat."}
	FileAccess.open(OUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	game.queue_free()
	await process_frame
	for suffix in ["", ".tmp"]:
		if FileAccess.file_exists(SAVE+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE+suffix))
	print("GEM VISUAL: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
