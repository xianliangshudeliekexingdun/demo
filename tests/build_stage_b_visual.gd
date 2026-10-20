extends "res://tests/build_trial_visual.gd"
# Stage B UI integration and true rendered screenshots; exits by itself.
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	DisplayServer.window_set_size(Vector2i(1280,720))
	game=Main.new()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	await capture("stage-b-setup")
	for page in range(5):
		game.ui.upgrade_page=page
		game.ui.show_upgrades()
		check(game.ui.upgrade_checks.size()==6 and game.ui.upgrade_notes.size()==6,"six options page "+str(page))
		check(game.ui.upgrade_notes.all(func(note): return not note.text.is_empty()),"dynamic descriptions "+str(page))
		await capture("stage-b-upgrades-"+Catalog.IDS[page])
	game.ui.upgrade_page=0
	game.ui.show_upgrades()
	Input.warp_mouse(Vector2(645,264))
	await create_timer(.1).timeout
	await mouse(MOUSE_BUTTON_LEFT,true,Vector2(645,264))
	await mouse(MOUSE_BUTTON_LEFT,false,Vector2(645,264))
	check(game.ui.setup_owned.has("quick_chant"),"real upgrade checkbox toggles")
	for preset in ["frequency","control","sustain","all","none"]:
		game.ui.apply_preset(preset)
		var expected=30 if preset=="all" else (0 if preset=="none" else 8)
		check(game.ui.setup_owned.size()==expected,"preset budget "+preset)
		await capture("stage-b-preset-"+preset)
	game.ui.apply_preset("control")
	button_named(game.ui.overlay,"按设置重置").pressed.emit()
	check(game.battle.owned==game.build_loader.presets.control,"UI starts selected real build")
	var session=JSON.parse_string(FileAccess.get_file_as_string(game.records.path+".jsonl").get_slice("\n",0))
	check(session.metadata.upgrades==game.battle.owned and session.metadata.preset=="control" and session.metadata.hash==game.build_loader.config_hash,"preset UI and saved metadata agree")
	game.release_gate=false
	var b=game.battle
	for e in b.enemies:
		e.state="recover"
		e.until=10000
		e.health=1000
		e.max_health=1000
		e.pos=Vector2(e.id-2,1)
	cast(b,"frost")
	await capture("stage-b-freeze-exposure")
	b.aim=Vector2(0,1)
	cast(b,"meteor")
	advance(b,.7)
	await capture("stage-b-meteor-fragments")
	game.start_build(3,1.5,Catalog.IDS,Catalog.FUTURE_UPGRADES,false,"all")
	b=game.battle
	for e in b.enemies:
		e.state="recover"
		e.until=10000
		e.health=1000
		e.max_health=1000
		e.pos=Vector2(e.id-2,1)
	cast(b,"lamp")
	cast(b,"rejuvenation")
	cast(b,"frost")
	advance(b,.1)
	await capture("stage-b-full-effects")
	advance(b,1)
	b.aim=Vector2(0,1)
	b.select_slot(0)
	b.player.mana=100
	b.command("press")
	b.step(b.STEP)
	advance(b,b.stats().chant+b.stats().extra_chant+.1)
	check(b.phase=="ready_molten","molten stage distinct")
	await capture("stage-b-molten-ready")
	game.pause_trial()
	game.ui.setup_owned=[]
	game.resume()
	check(b.owned.size()==30,"continue ignores pending upgrades")
	game.menu()
	button_named(game.ui.overlay,"短流程 · 9场成长").pressed.emit()
	b=game.battle
	check(b.short_run and b.wave==1 and b.owned.is_empty(),"growth starts with zero upgrades")
	for e in b.enemies: e.health=0
	b.step(b.STEP)
	game._process(0)
	check(game.mode=="choice" and b.choices.size()==3,"real flow choice page")
	await capture("stage-b-choices")
	check(game.ui.choice_descriptions.all(func(label): return label.size.x<=284 and label.size.y<=112),"choice description remains inside card")
	var choices=b.choices.duplicate()
	await key(KEY_3)
	check(b.commands.is_empty() and b.choices==choices,"reward page digits never queue battle")
	Input.warp_mouse(Vector2(292,506))
	await create_timer(.1).timeout
	await mouse(MOUSE_BUTTON_LEFT,true,Vector2(292,506))
	await mouse(MOUSE_BUTTON_LEFT,false,Vector2(292,506))
	check(game.mode=="battle" and b.wave==2 and b.owned.size()==1 and game.release_gate,"real reward click starts next wave safely")
	game.pause_trial()
	check(button_named(game.ui.overlay,"按设置重置")==null,"flow pause cannot reconfigure build")
	await capture("stage-b-flow-pause")
	game.resume()
	DisplayServer.window_set_size(Vector2i(1600,1000))
	await create_timer(.3).timeout
	for wave in range(2,10):
		if wave==9:
			game.pause_trial()
			await capture("stage-b-final-build-pause")
			game.resume()
		for e in b.enemies: e.health=0
		b.step(b.STEP)
		game._process(0)
		if b.result=="choice":
			await capture("stage-b-choice-"+str(wave))
			game.ui.upgrade_chosen.emit(b.choices[0])
		else: break
	check(b.result=="success" and b.owned.size()==8 and game.mode=="result","complete nine battles eight upgrades")
	await capture("stage-b-success")
	game.ui.retry_requested.emit()
	check(game.battle.short_run and game.battle.wave==1 and game.battle.owned.is_empty(),"retry resets growth with same setup")
	game.battle.damage_player(1000)
	game._process(0)
	await capture("stage-b-failure")
	var f=FileAccess.open(OUT+"stage-b-visual-result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"completed":true,"checks":checks,"failures":failures,"phase":"B"},"\t"))
	print("BUILD_STAGE_B_VISUAL_COMPLETE checks=",checks," failures=",failures)
	game.sound.stop()
	game.sound.stream=null
	game.queue_free()
	await process_frame
	await create_timer(.15).timeout
	quit(failures)
