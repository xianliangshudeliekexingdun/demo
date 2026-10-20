extends SceneTree
const Main=preload("res://scripts/trial_main.gd")
var game
var failures=0
func check(ok: bool,message: String):
	if not ok:
		failures+=1
		push_error(message)
const OUT="res://build/qa/fireball-trial/"
func _initialize(): call_deferred("run")
func capture(name: String):
	game.ui.refresh_trial(game.battle) if game.battle!=null else null
	game.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image()
	if image.save_png(OUT+name+".png")!=OK: failures+=1
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	game=Main.new()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	await capture("menu")
	game.start(0,false,[])
	game.release_gate=false
	var b=game.battle
	var motion=InputEventMouseMotion.new()
	motion.position=Vector2(768,360)
	Input.warp_mouse(motion.position)
	await create_timer(.1).timeout
	var local_point=game.view.get_global_transform_with_canvas().affine_inverse()*Vector2(768,360)
	check(game.ground_from_local(local_point).distance_to(Vector2(2,0))<0.0001,"1280 viewport coordinate maps to ground")
	var press=InputEventMouseButton.new()
	press.position=motion.position
	press.button_index=MOUSE_BUTTON_LEFT
	press.pressed=true
	Input.parse_input_event(press)
	await process_frame
	check("press" in b.commands,"real mouse press reaches command queue")
	b.commands.clear()
	press.pressed=false
	Input.parse_input_event(press)
	await process_frame
	b.commands.clear()
	b.aim=Vector2(3,0)
	b.queue("press")
	b.step(b.STEP)
	for i in range(55): b.step(b.STEP)
	await capture("chanting")
	b.queue("dodge")
	b.step(b.STEP)
	for i in range(24): b.step(b.STEP)
	check(b.phase=="chanting" and b.summary.auto_resumed==1,"held left auto continues visually")
	await capture("auto-resumed")
	game.start(0,false,[])
	b=game.battle
	b.aim=Vector2(3,0)
	b.queue("press")
	b.step(b.STEP)
	for i in range(55): b.step(b.STEP)
	b.queue("dodge")
	b.step(b.STEP)
	b.queue("release")
	for i in range(24): b.step(b.STEP)
	await capture("resume-window")
	b.queue("release")
	b.step(b.STEP)
	b.queue("press")
	b.step(b.STEP)
	for i in range(55): b.step(b.STEP)
	await capture("ready")
	game.pause_trial()
	var frozen=b.elapsed
	game._process(.1)
	check(b.elapsed==frozen and b.phase=="idle","controller pause freezes and clears")
	game.resume()
	game._input(press)
	check(b.commands.is_empty(),"resume gate blocks old release")
	game.release_gate=false
	b.queue("press")
	b.step(b.STEP)
	for i in range(100): b.step(b.STEP)
	b.queue("release")
	b.step(b.STEP)
	for i in range(23): b.step(b.STEP)
	await capture("flight")
	game.start(3,false,["molten","echo","embers"])
	b=game.battle
	for e in b.enemies:
		e.state="warning"
		e.aim=Vector2(0,-1)
		e.until=100
	b.aim=Vector2(2,1)
	b.queue("press")
	b.step(b.STEP)
	for i in range(170): b.step(b.STEP)
	await capture("molten-ready")
	b.queue("release")
	b.step(b.STEP)
	for i in range(57): b.step(b.STEP)
	await capture("embers-echo")
	game.pause_trial()
	await capture("free-settings")
	game.start(1,true,[])
	b=game.battle
	b.enemies[0].health=0
	b.step(b.STEP)
	game.ui.show_choices(b)
	await capture("choices")
	game.ui.show_battle()
	game.start(1,false,["wide_blast"])
	b=game.battle
	for e in b.enemies:
		e.state="recover"
		e.until=100
	b.aim=Vector2(2,1)
	b.queue("press")
	b.step(b.STEP)
	for i in range(100): b.step(b.STEP)
	DisplayServer.window_set_size(Vector2i(1600,1000))
	await create_timer(0.3).timeout
	# Native window contains 50px top/bottom letterbox around 1600x900 content.
	motion.position=Vector2(960,500)
	Input.warp_mouse(motion.position)
	await create_timer(.1).timeout
	# Check the content transform deterministically; native pointer can be moved by user.
	local_point=(root.get_final_transform()*game.view.get_global_transform_with_canvas()).affine_inverse()*Vector2(960,500)
	check(game.ground_from_local(local_point).distance_to(Vector2(2,0))<0.0001,"scaled viewport coordinate maps to same ground")
	await capture("letterbox-ready")
	Input.warp_mouse(Vector2(960,10))
	await create_timer(.1).timeout
	local_point=(root.get_final_transform()*game.view.get_global_transform_with_canvas()).affine_inverse()*Vector2(960,-40)
	check(not Rect2(0,150,1280,510).has_point(local_point),"letterbox coordinate rejected")
	game.tone(660)
	check(game.sound.stream!=null,"program audio stream valid")
	var viewport=root.get_texture().get_image().get_size()
	var f=FileAccess.open(OUT+"visual-result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"completed":true,"failures":failures,"window":DisplayServer.window_get_size(),"viewport":viewport},"\t"))
	print("FIREBALL_VISUAL_COMPLETE failures=",failures)
	game.sound.stop()
	game.sound.stream=null
	game.queue_free()
	await process_frame
	await create_timer(.15).timeout
	quit(failures)
