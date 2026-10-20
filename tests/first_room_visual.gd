extends SceneTree
const Main=preload("res://scripts/main.gd")
const Meta=preload("res://scripts/core/meta_progression.gd")
const OUT="res://build/qa/courtyard-route-20261017/regression/first-room/"
const SAVE="user://tests/first_room_visual.json"
var game
var checks=0
var failures=0
var captures:Array[String]=[]
var combat_records:Array=[]
func _initialize():call_deferred("run")
func check(ok:bool,message:String):
	checks+=1
	if not ok:
		failures+=1
		push_error("First room visual: "+message)
func buttons()->Array:
	var nodes:Array=[]
	if is_instance_valid(game.room_ui):nodes=game.room_ui.root.find_children("*","Button",true,false)
	else:nodes=game.ui.page.find_children("*","Button",true,false)
	return nodes
func click(text:String,index:int=0):
	var found:Array=[]
	for b in buttons():
		if b.text==text and b.is_visible_in_tree():found.append(b)
	check(found.size()>index,"clickable "+text)
	if found.size()<=index:return
	var b=found[index]
	var p=b.get_global_rect().get_center()*Vector2(root.size)/Vector2(1600,900)
	for down in [true,false]:
		var e=InputEventMouseButton.new()
		e.position=p
		e.button_index=MOUSE_BUTTON_LEFT
		e.pressed=down
		Input.parse_input_event(e)
		await process_frame
func key(code:int,down:bool):
	var e=InputEventKey.new()
	e.keycode=code
	e.physical_keycode=code
	e.pressed=down
	Input.parse_input_event(e)
	await process_frame
func tick(seconds:float):
	for i in range(roundi(seconds*120)):game._process(1.0/120)
	await process_frame
func snap(name:String):
	game._refresh_room(0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img=root.get_texture().get_image()
	check(img.save_png(OUT+name+".png")==OK,"capture "+name)
	captures.append(name)
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	DirAccess.make_dir_recursive_absolute("user://tests")
	for suffix in ["",".tmp",".bak"]:
		if FileAccess.file_exists(SAVE+suffix):DirAccess.remove_absolute(SAVE+suffix)
	DisplayServer.window_set_size(Vector2i(1280,720))
	game=Main.new()
	game.save_path=SAVE
	game.room_seed=20261017
	root.add_child(game)
	game.set_process(false)
	await process_frame
	await click("开始冒险     ›")
	check(game.screen=="prepare","home opens preparation")
	await click("进入首房试玩    ›")
	check(game.room_run!=null and game.room_run.phase=="choosing","actual room starts from preparation")
	check(not game.meta.get_run_snapshot().preview_only,"playable run uses real snapshot")
	check(game.room_ui.health_bar.size.y<=12 and game.room_ui.shield_bar.size.y<=12,"resource bars keep intended HUD height")
	check(game.room_ui.slot_bars[0].size.y<=7,"cooldown bars remain inside slots")
	await snap("01-initial-choice")
	var initial_buttons=game.room_ui.modal.find_children("*","Button",true,false)
	check(root.gui_get_focus_owner()==null,"initial choice has no automatic keyboard focus")
	for i in range(3):
		await key(KEY_TAB,true)
		await key(KEY_TAB,false)
		check(root.gui_get_focus_owner()==initial_buttons[i],"first Tab activates navigation then stays inside three choice buttons")
	await key(KEY_TAB,true)
	await key(KEY_TAB,false)
	check(root.gui_get_focus_owner()==initial_buttons[0],"Tab wraps inside three choices")
	await key(KEY_RIGHT,true)
	await key(KEY_RIGHT,false)
	check(root.gui_get_focus_owner()==initial_buttons[1],"arrow changes focused spell")
	await key(KEY_LEFT,true)
	await key(KEY_LEFT,false)
	check(root.gui_get_focus_owner()==initial_buttons[0],"left arrow returns to first spell")
	await key(KEY_ENTER,true)
	await key(KEY_ENTER,false)
	check(game.room_run.phase=="combat","initial choice starts actual combat")
	await tick(.2)
	await snap("02-spawn-warning")
	await tick(.65)
	check(game.room_run.actors.size()==2,"two authored enemies spawn")
	await snap("03-combat")
	var z:float=game.room_run.player.pos.y
	await key(KEY_W,true)
	await tick(.15)
	await key(KEY_W,false)
	check(game.room_run.player.pos.y>z,"real W key moves toward upper exit")
	await key(KEY_ESCAPE,true)
	await key(KEY_ESCAPE,false)
	check(game.room_run.paused,"Esc pauses actual simulation")
	var frozen=game.room_run.get_snapshot()
	await tick(3)
	check(game.room_run.get_snapshot()==frozen,"pause freezes all simulation state")
	await snap("04-pause")
	await key(KEY_D,true)
	await click("继续试炼")
	var before:Vector2=game.room_run.player.pos
	await tick(.2)
	check(game.room_run.player.pos==before,"held movement blocked on resume")
	await key(KEY_D,false)
	await tick(.01)
	# Deterministic stationary play uses the actual automatic spell, enemy AI and damage.
	var warned=false
	var cast_seen=false
	for i in range(2400):
		game._process(1.0/120)
		if game.room_run.phase!="combat":break
		for actor in game.room_run.actors:
			if actor.get("phase","")=="warning" and not warned:
				warned=true
				await snap("05-enemy-telegraph")
		if game.room_run.casts>0 and not cast_seen:
			cast_seen=true
			await snap("06-automatic-spell")
	check(game.room_run.phase=="reward","true automatic combat clears first room")
	combat_records.append(game.room_run.get_summary())
	check(game.room_run.clear_count==1 and game.room_run.kills==2,"clear ledger derives from actual kills")
	check(game.room_run.player.shield==game.room_run.player.max_shield,"clear restores shield")
	check(game.meta.get_state().dust==0,"clear dust remains unsettled before exit")
	check(game.room_run.portal.visible and not game.room_run.portal.usable,"portal visible but gated by reward")
	await snap("07-clear-reward")
	await click("领取奖励")
	check(game.room_run.phase=="exit" and game.room_run.portal.usable,"reward opens exit")
	await tick(1)
	await snap("08-open-portal")
	DisplayServer.window_set_size(Vector2i(1600,900))
	await snap("08-open-portal-1600")
	check(game.room_view.size==Vector2(1600,900),"3D stage keeps full logical size at larger window")
	DisplayServer.window_set_size(Vector2i(1280,720))
	await process_frame
	var guard=0
	# The straight middle route is open. Hold the real movement key; no teleport.
	await key(KEY_W,true)
	while game.room_run.phase=="exit" and guard<600:
		game._process(1.0/120)
		guard+=1
	for code in [KEY_A,KEY_D,KEY_W,KEY_S]:await key(code,false)
	check(game.room_run.phase=="complete","walking into portal completes demo")
	check(game.room_settlement.get("ok",false) and game.meta.get_state().dust==1,"real first room credits exactly one dust")
	check(not game.meta.is_in_run(),"completion releases progression lock")
	await snap("09-complete")
	var reopen=Meta.new(SAVE)
	check(reopen.load_state().ok and reopen.get_state().dust==1,"real reward persists to disk")
	game._settle_room()
	check(game.meta.get_state().dust==1,"repeated settlement cannot credit twice")
	await click("返回准备")
	check(game.room_run==null and game.screen=="prepare","result returns to preparation")
	# Unfinished abandonment must not invent a clear or add dust.
	await click("进入首房试玩    ›")
	await click("选择法术",2)
	await tick(.3)
	await click("暂停")
	await click("结束试玩")
	check(game.room_settlement.get("dust_earned",-1)==0 and game.meta.get_state().dust==1,"uncleared abandonment gives no dust")
	await snap("10-abandon")
	await click("返回准备")
	await click("进入首房试玩    ›")
	await click("选择法术",1)
	await tick(.01)
	var spirit_captured=false
	for i in range(2400):
		game._process(1.0/120)
		if game.room_run.spirit.active and not spirit_captured:
			spirit_captured=true
			await snap("11-spirit-summoned")
		if game.room_run.phase!="combat":break
	check(spirit_captured and game.room_run.phase=="reward","spirit starter summons and completes actual combat")
	combat_records.append(game.room_run.get_summary())
	check(game.room_ui.timer_label.text.contains("%02d:%02d"%[int(game.room_run.time)/60,int(game.room_run.time)%60]),"spirit clear timer matches actual battle time")
	await snap("12-spirit-clear")
	# End an already cleared room through the pause menu: the clear still counts once.
	await key(KEY_ESCAPE,true)
	await key(KEY_ESCAPE,false)
	await click("结束试玩")
	check(game.room_settlement.get("dust_earned",-1)==1 and game.meta.get_state().dust==2,"abandoning after actual clear preserves one earned dust")
	await click("返回准备")
	await click("进入首房试玩    ›")
	await click("选择法术",2)
	await tick(.01)
	var beam_captured=false
	for i in range(2400):
		game._process(1.0/120)
		for effect in game.room_run.effects:
			if effect.kind=="beam" and not beam_captured:
				beam_captured=true
				await snap("13-beam-cast")
		if game.room_run.phase!="combat":break
	check(beam_captured and game.room_run.phase=="reward","beam starter renders and completes actual combat")
	combat_records.append(game.room_run.get_summary())
	await key(KEY_ESCAPE,true)
	await key(KEY_ESCAPE,false)
	await click("结束试玩")
	await click("返回准备")
	await click("进入首房试玩    ›")
	await click("选择法术")
	# A controlled fatal hit is a result/saving boundary fixture, not the combat proof.
	game.room_run.damage_player(10000)
	game._process(1.0/120)
	check(game.room_result_reason=="dead" and game.room_settlement.get("dust_earned",-1)==0,"death ends uncleared run without rewards")
	await snap("14-death-result")
	var summary={"checks":checks,"failures":failures,"captures":captures,"combat_records":combat_records,"enemy_telegraph_captured":warned,"automatic_spell_captured":cast_seen,"save_isolated":SAVE}
	FileAccess.open(OUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify(summary,"\t"))
	game.queue_free()
	await process_frame
	for suffix in ["",".tmp",".bak"]:
		if FileAccess.file_exists(SAVE+suffix):DirAccess.remove_absolute(SAVE+suffix)
	print("FIRST ROOM VISUAL: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
