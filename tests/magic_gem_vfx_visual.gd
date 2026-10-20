extends SceneTree
## Explicit production Route actor/status fixtures for new core short effects.
## These screenshots are presentation evidence, not naturally acquired builds.
const Main = preload("res://scripts/main.gd")
const OUT = "res://build/qa/magic-gems-v2-20261020/vfx/"
const SAVE = "user://tests/meta_progression/magic_gem_vfx.json"
var game
var checks: int = 0
var failures: Array = []
var captures: Array = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks+=1
	if not ok:
		failures.append(label)
		push_error(label)
func context(school: String, cast: int) -> Dictionary:
	return {"school":school,"spell_id":"F01" if school=="fire" else "I01","kind":"direct","natural":true,"cast_id":cast,"damage_scale":1.0,"field_bonus":0.0}
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	game=Main.new()
	game.save_path=SAVE
	game.preferences_path="user://tests/meta_progression/magic_gem_vfx.cfg"
	root.add_child(game)
	game.set_process(false)
	DisplayServer.window_set_size(Vector2i(1280,720))
	check(game.load_error.is_empty() and DisplayServer.get_name()!="headless","isolated Main uses actual native renderer")
	for core in ["fracture","coffin","reactor","echo","echo_segment"]:
		game.start_courtyard_route()
		game._handle_room_request("room_initial","F01")
		var b=game.room_run
		b._gem_combat.configure(b,{"gem_core":"echo" if core=="echo_segment" else core}) # Explicit visual fixture, never presented as inventory.
		b.player.crit_rate=1.0 if core=="fracture" else 0.0
		b.spells.clear()
		b.spawn_warnings.clear()
		b.actors.clear()
		b.blocks.clear()
		b._spawn_done=true
		for index in 4:
			var pos:Vector2=b.player.pos+Vector2((index-1)*0.8,2.0)
			b.actors.append({"id":index+1,"type":"M01","type_id":"M01","pos":pos,"previous":pos,"health":10000.0,"max_health":10000.0,"radius":0.3,"phase":"chase","push_resistance":0.0})
		if core=="fracture":
			b.resolve_spell_hit(b.actors[1],0.1,context("fire",1))
			b._gem_combat.advance(0.18,b)
		elif core.begins_with("echo"):
			var shape:Dictionary={"kind":"area","pos":b.actors[1].pos,"radius":2.0,"block":true} if core=="echo" else {"kind":"segment","from":b.player.pos,"to":b.actors[1].pos+Vector2(0,2),"width":0.5}
			b.gem_record_shape(shape,1.0,context("fire",1))
			b._gem_combat.advance(0.65,b)
		elif core=="coffin":
			b._spell_combat.ice.status.apply_frost(b,b.actors[1],3,context("ice",1))
			b.resolve_spell_hit(b.actors[1],1.0,context("fire",2))
			b._spell_combat.ice.status.advance(b,2.5)
		else:
			b._spell_combat.apply_burn(b,b.actors[1],"F01")
			b._spell_combat.ice.status.apply_frost(b,b.actors[1],3,context("ice",1))
			b.gem_after_spell_status(b.actors[1],context("ice",2))
		check(b.effects.any(func(e):return str(e.kind)=="gem_"+("echo" if core=="echo_segment" else core)),"actual core emits "+core)
		game._refresh_room(0.0)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path:String=core+"-1280.png"
		check(root.get_texture().get_image().save_png(OUT+path)==OK,"native core screenshot "+core)
		captures.append(path)
		check(b.damage_dealt>0.0,"core fixture used actual damage path")
		game._finish_room("abandon")
		game._handle_room_request("room_return","")
		await process_frame
	var result:Dictionary={"checks":checks,"failures":failures.size(),"details":failures,"captures":captures,"scope":"Explicit actual Main/Route actor and core fixtures. Status expiry advanced by its production API; not a natural build or combat run."}
	FileAccess.open(OUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	game.queue_free()
	await process_frame
	if FileAccess.file_exists(SAVE):DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("GEM VFX: %d checks; %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
