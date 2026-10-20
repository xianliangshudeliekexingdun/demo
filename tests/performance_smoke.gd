extends SceneTree
const Main=preload("res://scripts/main.gd")
func _initialize(): call_deferred("run")
func run():
	var isolated_save="user://tests/meta_progression/render_smoke_%d.json" % Time.get_ticks_usec()
	var game=Main.new()
	game.save_path=isolated_save
	root.add_child(game)
	await process_frame
	var failed=not game.load_error.is_empty()
	if failed: push_error("RENDER_SMOKE startup: "+game.load_error)
	var samples:Array=[]
	if not failed:
		for screen in ["home","catalyst","prepare"]:
			game.navigate(screen,false)
			await process_frame
			await process_frame
			var start=Time.get_ticks_usec()
			var frames=0
			while Time.get_ticks_usec()-start < 1000000:
				await process_frame
				frames+=1
			var seconds=(Time.get_ticks_usec()-start)/1000000.0
			samples.append({"screen":screen,"frames":frames,"seconds":seconds,"average_fps":frames/seconds})
	print("RENDER_SMOKE ",JSON.stringify({"samples":samples,"gpu":RenderingServer.get_video_adapter_name(),"startup_ok":not failed}))
	game.queue_free()
	await process_frame
	for suffix in ["",".tmp"]:
		if FileAccess.file_exists(isolated_save+suffix): DirAccess.remove_absolute(isolated_save+suffix)
	quit(1 if failed else 0)
