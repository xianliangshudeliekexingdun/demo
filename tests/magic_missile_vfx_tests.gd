extends SceneTree
## Structural/lifecycle checks only. No rendered pixels, screenshots, natural
## gameplay or performance evidence is produced by this headless test.
const Missiles = preload("res://scripts/presentation/route_magic_missile_vfx.gd")
const RoomView = preload("res://scripts/presentation/first_room_view.gd")
const Route = preload("res://scripts/core/courtyard_route_run.gd")
const Report = preload("res://tests/qa_report.gd")
const OUTPUT := "res://build/qa/magic-missile-energy-v2-20261026/presentation-results.json"
var checks := 0
var failures: Array = []

class Projector extends RefCounted:
	var scale := 40.0
	var offset := Vector2(640, 360)
	func screen_position(pos: Vector2, height: float = 0.0) -> Vector2:
		return Vector2(pos.x * scale, -pos.y * scale * 0.65 - height * scale) + offset


func _initialize() -> void:
	call_deferred("execute")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("Magic missile VFX: " + label)


func snapshot(now: float, shots: Array = [], ends: Array = [], revision: int = 1) -> Dictionary:
	return {"time": now, "phase": "combat", "room_revision": revision,
		"enemy_projectiles": shots, "enemy_projectile_ends": ends}


func shot(id: int, pos: Vector2) -> Dictionary:
	return {"id": id, "pos": pos, "previous": pos - Vector2(0.05, 0),
		"direction": Vector2.RIGHT, "radius": 0.2, "speed": 6.0}


func ended(id: int, seq: int, reason: String, now: float) -> Dictionary:
	return {"projectile_id": id, "seq": seq, "reason": reason, "time": now,
		"from_time": now - 1.0 / 120.0, "pos": Vector2(1, 0), "from": Vector2(0.95, 0),
		"contact_pos": Vector2(1.2, 0), "normal": Vector2.LEFT,
		"direction": Vector2.RIGHT, "radius": 0.2, "damage_applied": reason == "player"}


func execute() -> void:
	var renderer = Missiles.new()
	root.add_child(renderer)
	await process_frame
	var projector := Projector.new()
	check(renderer.is_available(), "canonical visual config constructs the real renderer")
	check(renderer.get_child_count() == 4, "four shared batch/mesh nodes, no per-shot nodes")
	check(renderer.get_debug_state().visual_revision == 2, "energy revision uses its current canonical config")
	check(renderer._halos.get_index() > renderer._heads.get_index(), "foreground energy cannot be covered by the head surface")
	var quad: Array = renderer._heads.multimesh.mesh.get_mesh_arrays()
	var quad_vertices: PackedVector3Array = quad[Mesh.ARRAY_VERTEX]
	var quad_uvs: PackedVector2Array = quad[Mesh.ARRAY_TEX_UV]
	var forward_matches_uv := true
	for index in quad_vertices.size():
		forward_matches_uv = forward_matches_uv and signf(quad_vertices[index].x) == signf(quad_uvs[index].x - 0.5)
	check(forward_matches_uv, "engine quad UVs map the concentrated front to the source flight direction")
	for shader: Shader in [Missiles.HEAD_SHADER, Missiles.TRAIL_SHADER, Missiles.ENERGY_SHADER]:
		check(not shader.get_shader_uniform_list().is_empty(), "shader language parser exposes uniforms: " + shader.resource_path)
	check(renderer._head_material.get_shader_parameter("shell_color") is Color, "data palette binds to head material")
	check(renderer._trail_material.get_shader_parameter("tail_alpha") == renderer._config.tail_alpha, "trail alpha uses the canonical visual data")
	immutability_and_pause(renderer, projector)
	paths_and_projection(renderer, projector)
	terminal_lifecycle(renderer, projector)
	capacity(renderer, projector)
	await integration()
	await preview_construction()
	renderer.queue_free()
	await process_frame
	var report := {"checks": checks, "failures": failures.size(), "details": failures,
		"scope": "Headless renderer construction, shader-language uniforms, snapshot isolation, world-space history, pause/reduced-motion, contact deduplication, lifecycle, 320-projectile capacity and real view integration. No actual GPU composition, pixels, screenshot, animation-appearance, performance, natural-route or user visual acceptance."}
	if not Report.write_report(report, OUTPUT):
		failures.append("QA report could not be written")
	print("MAGIC MISSILE VFX checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func immutability_and_pause(renderer, projector) -> void:
	var source := snapshot(1.0, [shot(1, Vector2.ZERO)])
	var original := source.duplicate(true)
	renderer.sync_snapshot(source, projector)
	check(source == original, "sync never changes supplied projectile dictionaries")
	check(renderer.get_debug_state().head_ids == PackedInt64Array([1]), "source ID becomes exactly one visible head")
	source = snapshot(1.05, [shot(1, Vector2(0.3, 0))])
	renderer.sync_snapshot(source, projector)
	var before: Dictionary = renderer.get_debug_state()
	check(not before.vertices.is_empty() and before.indices.size() > 0, "real movement creates a continuous ribbon mesh")
	for repeat in 5:
		source["paused"] = true
		renderer.sync_snapshot(source, projector)
	var after: Dictionary = renderer.get_debug_state()
	check(before.vertices == after.vertices and before.uvs == after.uvs, "same paused snapshot keeps identical ribbon geometry")
	check(before.paths == after.paths and before.clock == after.clock, "pause does not add samples or advance ages")
	check(renderer._head_material.get_shader_parameter("core_time") == source.time, "shader animation receives snapshot time")
	renderer.sync_snapshot(source, projector, {"reduced_motion": true})
	after = renderer.get_debug_state()
	check(after.heads == before.heads and after.vertices == before.vertices, "reduced motion keeps heads and real path information")
	check(renderer._head_material.get_shader_parameter("reduced_motion") == true and renderer._trail_material.get_shader_parameter("reduced_motion") == true and renderer._energy_material.get_shader_parameter("reduced_motion") == true, "all three animated materials stop their decorative flow")
	check(renderer._energy_material.get_shader_parameter("core_time") == source.time, "foreground energy also receives the frozen snapshot clock")
	check(renderer.get_child_count() == 4, "repeat and option sync do not allocate new nodes")


func paths_and_projection(renderer, projector) -> void:
	for fps in [30, 60, 144]:
		for speed in [3.2, 6.0, 12.0]:
			for frame in range(int(fps * 0.45) + 1):
				var now := float(frame) / float(fps)
				var source := shot(7, Vector2(now * speed, 0))
				source.speed = speed
				renderer.sync_snapshot(snapshot(now, [source], [], fps), projector)
			var state: Dictionary = renderer.get_debug_state()
			var path: PackedVector2Array = state.paths[0].world_path
			var tag := "%d fps %.1f m/s" % [fps, speed]
			check(path.size() >= 2 and path[0].is_equal_approx(Vector2(float(int(fps * 0.45)) / fps * speed, 0)), "ribbon starts at source endpoint: " + tag)
			var length := 0.0
			var on_path := true
			for index in range(1, path.size()):
				length += path[index - 1].distance_to(path[index])
				on_path = on_path and path[index].y == 0 and path[index].x <= path[index - 1].x
			check(on_path, "history follows real traveled path: " + tag)
			var expected := minf(speed * float(renderer._config.history_seconds), minf(0.2 * float(renderer._config.tail_max_radii), float(renderer._config.tail_max_m)))
			check(absf(length - expected) < 0.02, "configured tail duration and cap agree across frame rates: " + tag)
			check(int(state.paths[0].samples) <= int(renderer._config.history_points), "history storage stays bounded: " + tag)
			check(state.vertices.size() == state.uvs.size() and state.indices.size() % 3 == 0, "valid ribbon topology: " + tag)
			var finite := true
			for vertex: Vector3 in state.vertices:
				finite = finite and vertex.is_finite()
			for index in state.indices:
				finite = finite and index >= 0 and index < state.vertices.size()
			check(finite, "finite geometry and index bounds: " + tag)
	var source := snapshot(2.0, [shot(7, Vector2(2, 1))], [], 99)
	renderer.sync_snapshot(source, projector)
	source.time = 2.06
	source.enemy_projectiles[0].pos = Vector2(2.4, 1.1)
	renderer.sync_snapshot(source, projector)
	var before: Dictionary = renderer.get_debug_state()
	projector.offset += Vector2(73, 29)
	renderer.sync_snapshot(source, projector)
	var after: Dictionary = renderer.get_debug_state()
	check(before.paths == after.paths, "camera translation cannot alter world-space trail history")
	var translated := true
	for index in before.vertices.size():
		translated = translated and after.vertices[index].is_equal_approx(before.vertices[index] + Vector3(73, 29, 0))
	check(translated, "camera movement reprojects the complete ribbon with no detached tail")
	projector.scale = 32.0
	renderer.sync_snapshot(source, projector)
	check(renderer.get_debug_state().paths == after.paths, "resolution change preserves the source path")
	projector.scale = 40.0
	projector.offset = Vector2(640, 360)


func terminal_lifecycle(renderer, projector) -> void:
	for reason in ["player", "wall", "expired", "missing"]:
		var revision := 200 + ["player", "wall", "expired", "missing"].find(reason)
		renderer.sync_snapshot(snapshot(3.0, [shot(1, Vector2.ZERO)], [], revision), projector)
		renderer.sync_snapshot(snapshot(3.1, [shot(1, Vector2(0.6, 0))], [], revision), projector)
		var events: Array = [] if reason == "missing" else [ended(1, 1, reason, 3.15)]
		var source := snapshot(3.16, [], events, revision)
		renderer.sync_snapshot(source, projector)
		var count := 1 if reason in ["player", "wall"] else 0
		check(renderer.get_debug_state().heads == 0, "terminal head is gone: " + reason)
		check(renderer.get_debug_state().impact_instances == count, "only confirmed collision creates an impact: " + reason)
		var before: Dictionary = renderer.get_debug_state()
		for repeat in 4:
			renderer.sync_snapshot(source, projector)
		check(renderer.get_debug_state().impacts.size() == count, "terminal facts never replay on repeated snapshots: " + reason)
		check(renderer.get_debug_state().vertices == before.vertices, "frozen terminal fade stays stable: " + reason)
		source.time = 3.5
		renderer.sync_snapshot(source, projector)
		check(not renderer.visible and renderer.get_debug_state().paths.is_empty(), "trails and bursts finish without persistent nodes: " + reason)
	var event := ended(42, 3, "wall", 4.0)
	renderer.sync_snapshot(snapshot(4.02, [], [event], 300), projector)
	check(renderer.get_debug_state().impact_instances == 1, "a shot born and ended between view frames still uses its real contact")
	var source := snapshot(4.02, [], [event], 300)
	source.phase = "pickup"
	renderer.sync_snapshot(source, projector)
	check(not renderer.visible and renderer.get_debug_state().impacts.is_empty(), "leaving combat clears all old effects immediately")
	renderer.sync_snapshot(snapshot(4.02, [shot(42, Vector2(8, 0))], [], 301), projector)
	check(renderer.get_debug_state().paths.size() == 1 and renderer.get_debug_state().impacts.is_empty(), "room revision isolates reused projectile IDs")


func capacity(renderer, projector) -> void:
	var shots: Array = []
	for id in 320:
		shots.append(shot(id, Vector2(float(id % 20) * 0.4, float(id / 20) * 0.4)))
	for frame in 12:
		for projectile: Dictionary in shots:
			projectile.pos.x += 0.05
		renderer.sync_snapshot(snapshot(5.0 + frame / 60.0, shots, [], 400), projector)
	var state: Dictionary = renderer.get_debug_state()
	check(state.heads == 320 and state.overflow == 0, "all 320 authoritative live projectiles retain their heads")
	check(state.paths.size() == 320 and renderer.get_child_count() == 4, "capacity uses fixed nodes and per-shot path records")
	var events: Array = []
	for id in 320:
		events.append(ended(id, id + 1, "wall", 5.2))
	renderer.sync_snapshot(snapshot(5.21, [], events, 400), projector)
	check(renderer.get_debug_state().impact_instances == 320, "a complete 320-shot terminal burst is not truncated")
	renderer.sync_snapshot(snapshot(5.5, [], events, 400), projector)
	check(not renderer.visible and renderer.get_debug_state().paths.is_empty(), "capacity terminal histories fully clean up")
	check(renderer.get_child_count() == 4, "cleanup returns to the same fixed renderer nodes")


func integration() -> void:
	var run := Route.new()
	check(run.configure({}, 144).ok, "real route configures for view integration")
	run.phase = "combat"
	var actor: Dictionary = run._enemy_combat.make_actor(run, "M02", Vector2(-2, 0), 901)
	run._enemy_combat._emit_projectile(actor, actor.combat_spec, Vector2.RIGHT)
	var source: Dictionary = run.get_snapshot()
	check(source.has("enemy_projectile_ends"), "real route exposes the independent contact journal")
	var original := source.duplicate(true)
	var view = RoomView.new()
	view.size = Vector2(1280, 720)
	root.add_child(view)
	await process_frame
	view.sync(source)
	check(view.get_magic_missile_debug_state().heads == 1, "real combat view consumes the source projectile")
	check(view.magic_missile_vfx.z_index > view._overlay.z_index, "missile batch draws above warnings, health bars and world labels")
	check(source == original, "complete view integration keeps the snapshot unchanged")
	view.queue_free()
	await process_frame


func preview_construction() -> void:
	var scene: PackedScene = load("res://tests/previews/magic_missile_preview.tscn")
	check(scene != null, "optional preview scene loads without becoming a game entry")
	var preview = scene.instantiate()
	check(preview.has_method("_advance"), "preview scene has its valid simulation controller")
	if not preview.has_method("_advance"):
		preview.free()
		return
	root.add_child(preview)
	preview.set_process(false)
	await process_frame
	for tick in 1200:
		preview._advance(1.0 / 120.0)
		var journal: Array = preview._run._enemy_combat.get_projectile_ends()
		if not journal.is_empty() and journal[-1].reason == "player":
			break
	preview._refresh()
	var ends: Array = preview._run._enemy_combat.get_projectile_ends()
	check(not ends.is_empty() and ends[-1].reason == "player", "single-shot preview reaches real player contact with source specs")
	preview._mode = 1
	preview._reset()
	for tick in 120:
		preview._advance(1.0 / 120.0)
		if preview._run._enemy_combat.enemy_projectiles.size() == 4:
			break
	preview._refresh()
	check(preview._view.get_magic_missile_debug_state().heads == 4, "crossing preview drives four real source projectiles")
	preview._mode = 2
	preview._reset()
	for tick in 120:
		preview._advance(1.0 / 120.0)
		if preview._run._enemy_combat.enemy_projectiles.size() == 64:
			break
	preview._refresh()
	check(preview._view.get_magic_missile_debug_state().heads == 64, "dense preview retains all 64 source projectiles")
	preview.queue_free()
	await process_frame
