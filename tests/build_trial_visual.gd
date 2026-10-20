extends SceneTree
const Main=preload("res://scripts/build_trial_main.gd")
const MenuMain=preload("res://scripts/main.gd")
const Catalog=preload("res://scripts/core/spell_catalog.gd")
const OUT="res://build/qa/build-trial/"
var game
var failures=0
var checks=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		push_error("Build visual: "+message)
func _initialize():
	# Inherited Stage B tests still exercise the original 1280 × 720 trial UI.
	root.content_scale_size=Vector2i(1280,720)
	call_deferred("run")
func capture(name: String):
	if game!=null:
		if game.battle!=null: game.ui.refresh_build(game.battle)
		game.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+name+".png")==OK,"capture "+name)
func advance(b,seconds: float):
	for i in range(roundi(seconds*120)): b.step(b.STEP)
func cast(b,id: String):
	b.select_slot(b.slots.find(id))
	b.command("press")
	b.step(b.STEP)
	advance(b,b.stats().chant+b.STEP)
	b.command("release")
	b.step(b.STEP)
func mouse(button: int,on: bool,point: Vector2):
	var e=InputEventMouseButton.new()
	e.position=point
	e.button_index=button
	e.pressed=on
	Input.parse_input_event(e)
	await process_frame
func key(code: int):
	var e=InputEventKey.new()
	e.keycode=code
	e.pressed=true
	Input.parse_input_event(e)
	await process_frame
	e.pressed=false
	Input.parse_input_event(e)
	await process_frame
func button_named(node: Node,title: String):
	if node is Button and node.text==title: return node
	for child in node.get_children():
		var found=button_named(child,title)
		if found!=null: return found
	return null
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	DisplayServer.window_set_size(Vector2i(1280,720))
	root.content_scale_size=Vector2i(1600,900)
	var menu_save="user://tests/meta_progression/build_visual_%d.json" % Time.get_ticks_usec()
	var original=MenuMain.new()
	original.save_path=menu_save
	root.add_child(original)
	await process_frame
	check(original.load_error.is_empty(),"new menu catalog and isolated save loaded")
	check(button_named(original,"火球战斗试验")==null and button_named(original,"五法术构筑试验")==null,"old trial entries removed")
	check(button_named(original,"火球术       直线飞行 · 范围爆炸")==null,"old automatic entry removed")
	check(button_named(original,"开始冒险     ›")!=null and button_named(original,"法术触媒")!=null and button_named(original,"魔力宝石")!=null,"new adventure and equipment entries")
	await capture("main-menu")
	original.queue_free()
	await process_frame
	for suffix in ["",".tmp"]:
		if FileAccess.file_exists(menu_save+suffix): DirAccess.remove_absolute(menu_save+suffix)
	var legacy_base=preload("res://scripts/ui/game_ui.gd").new()
	root.add_child(legacy_base)
	await process_frame
	check(legacy_base.overlay==null and not legacy_base.hud.visible,"legacy base no longer constructs menu")
	legacy_base.queue_free()
	await process_frame
	root.content_scale_size=Vector2i(1280,720)
	game=Main.new()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	await capture("setup")
	game.ui.slot_selects[0].select(2)
	game.ui.slot_selects[0].item_selected.emit(2)
	check(game.ui.setup_slots[0]=="frost" and game.ui.setup_slots[2]=="fireball","setup swaps without duplicate")
	await capture("reordered-setup")
	game.ui.show_setup(0,1.5,Catalog.IDS,false)
	Input.warp_mouse(Vector2(295,644))
	await create_timer(.15).timeout
	await mouse(MOUSE_BUTTON_LEFT,true,Vector2(295,644))
	await mouse(MOUSE_BUTTON_LEFT,false,Vector2(295,644))
	check(game.mode=="battle" and game.battle!=null,"real UI click starts trial")
	if game.battle==null:
		quit(1)
		return
	game.release_gate=false
	check(game.ui.slots_ui[0].icon.size==Vector2(34,34),"icon remains within its slot")
	var b=game.battle
	Input.warp_mouse(Vector2(768,360))
	await create_timer(.1).timeout
	await key(KEY_2)
	check(b.commands.any(func(c): return c.kind=="slot" and c.value==1),"real number key queued")
	b.step(b.STEP)
	check(b.active_spell()=="meteor","number key switches spell")
	await mouse(MOUSE_BUTTON_WHEEL_UP,true,Vector2(768,360))
	b.step(b.STEP)
	check(b.active_spell()=="fireball","real wheel switches backward")
	await mouse(MOUSE_BUTTON_LEFT,true,Vector2(768,360))
	check(b.commands.any(func(c): return c.kind=="press"),"real mouse press queued")
	b.step(b.STEP)
	b.aim=Vector2(2,0)
	advance(b,.45)
	await capture("fireball-chant")
	b.command("dodge")
	b.step(b.STEP)
	advance(b,.2)
	check(b.phase=="chanting" and b.summary.auto_resumed==1,"auto resume remains available")
	await capture("auto-resume")
	advance(b,.5)
	await capture("fireball-ready")
	Input.warp_mouse(Vector2(768,360))
	await create_timer(.1).timeout
	await mouse(MOUSE_BUTTON_LEFT,false,Vector2(768,360))
	check(b.commands.any(func(c): return c.kind=="release"),"real release in valid game area queued")
	b.step(b.STEP)
	check(b.bullets.size()==1,"real mouse release casts")
	advance(b,.2)
	await capture("fireball-flight")
	game.start_build(3,1.5,Catalog.IDS)
	game.release_gate=false
	b=game.battle
	for e in b.enemies:
		e.state="recover"
		e.until=100
	b.aim=Vector2(3,1)
	cast(b,"meteor")
	advance(b,.3)
	await capture("meteor-fall")
	advance(b,.4)
	await capture("meteor-impact")
	game.start_build(3,1.5,Catalog.IDS)
	b=game.battle
	for e in b.enemies:
		e.state="warning"
		e.until=100
		e.aim=Vector2(0,-1)
	b.enemies[0].pos=Vector2(-1.5,1)
	b.enemies[1].pos=Vector2(0,2)
	b.enemies[2].pos=Vector2(1.5,1)
	cast(b,"frost")
	await capture("frost-slow")
	b.player.health=55
	b.player.mana=100
	cast(b,"rejuvenation")
	advance(b,1.1)
	cast(b,"lamp")
	advance(b,1.3)
	await capture("heal-and-lamp")
	check(b.heal_total>0 and b.by_spell.lamp.damage>0,"healing and summon actual results")
	check(game.ui.slots_ui[4].shade.visible and not game.ui.slots_ui[4].timer.text.is_empty(),"lamp cooldown shown in actual HUD")
	b.command("press")
	b.step(b.STEP)
	game._process(0)
	check(game.ui.message.text.contains("冷却中") and b.phase=="idle","cooldown refusal has distinct feedback")
	await capture("cooldown-blocked")
	b.command("release")
	b.step(b.STEP)
	b.select_slot(1)
	b.player.mana=100
	cast(b,"meteor")
	game._process(0)
	await capture("multiple-cooldowns")
	game.pause_trial()
	var frozen=b.elapsed
	game.ui.setup_slots.reverse()
	game.resume()
	check(b.slots==Catalog.IDS,"continue ignores pending setup")
	game._input(InputEventMouseButton.new())
	check(b.commands.is_empty() and b.elapsed==frozen,"resume gate keeps simulation/input safe")
	game.pause_trial()
	await capture("pause-settings")
	game.resume()
	game.release_gate=false
	advance(b,b.cooldown_remaining("meteor")+.1)
	b.player.mana=0
	b.select_slot(1)
	b.command("press")
	b.step(b.STEP)
	game._process(0)
	check(game.ui.message.text.contains("法力不足"),"insufficient mana visible")
	await capture("mana-low")
	game.pause_trial()
	await key(KEY_5)
	check(b.commands.is_empty(),"menu digit cannot queue spell switch")
	game.resume()
	b.player.mana=100
	advance(b,b.cooldown_remaining("meteor")+.1)
	b.select_slot(1)
	b.aim=Vector2(2,0)
	b.command("press")
	b.step(b.STEP)
	advance(b,1.5)
	game._process(0)
	DisplayServer.window_set_size(Vector2i(1600,1000))
	await create_timer(.3).timeout
	var local=(root.get_final_transform()*game.view.get_global_transform_with_canvas()).affine_inverse()*Vector2(960,500)
	check(game.ground_from_local(local).distance_to(Vector2(2,0))<.0001,"scaled mouse transform")
	await capture("letterbox-ready")
	var outside=(root.get_final_transform()*game.view.get_global_transform_with_canvas()).affine_inverse()*Vector2(960,-40)
	check(not Rect2(0,150,1280,510).has_point(outside),"letterbox rejected")
	b.damage_player(1000)
	game._process(0)
	await capture("result")
	check(game.mode=="result","failure result shown")
	game.menu()
	game.ui.show_setup(3,1.5,Catalog.IDS,false,"测试错误：meteor.mana_cost 超过法力上限，保留上次有效参数。")
	await capture("config-error")
	game.tone(660)
	check(game.sound.stream!=null,"ready audio valid")
	var f=FileAccess.open(OUT+"visual-result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"completed":true,"checks":checks,"failures":failures,"phase":"A","window":str(DisplayServer.window_get_size()),"viewport":str(root.get_texture().get_image().get_size())},"\t"))
	print("BUILD_VISUAL_COMPLETE checks=",checks," failures=",failures)
	game.sound.stop()
	game.sound.stream=null
	game.queue_free()
	await process_frame
	await create_timer(.15).timeout
	quit(failures)
