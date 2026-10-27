extends SceneTree
## Legacy-shaped compatibility/contact + current headless visual checks.
## No screenshots, GPU composition, performance or visual acceptance.
const Fire = preload("res://scripts/presentation/route_fire_bolt_vfx.gd")
const View = preload("res://scripts/presentation/first_room_view.gd")
const Rules = preload("res://tests/formal_fire_tests.gd")
const Report = preload("res://tests/qa_report.gd")
const OUTPUT := "res://build/qa/fire-bolt-curve-v2-20261026/presentation-results.json"
var checks := 0
var failures: Array = []

class Projector extends RefCounted:
	var scale := 40.0
	var offset := Vector2(640, 360)
	func screen_position(pos: Vector2, height: float = 0.0) -> Vector2:
		return Vector2(pos.x * scale, -pos.y * scale * 0.65 - height * scale) + offset

# Only legacy-shaped projectiles use the frozen comparator. New curved shots
# are deliberately a changed rule and are covered by fire_bolt_curve_tests.
class CompatibilityCombat extends "res://scripts/core/route_spell_combat.gd":
	func _spawn_bolt(run, spell: Dictionary, stats: Dictionary, target: Dictionary, coefficient: float, context: Dictionary):
		var direction: Vector2 = (target.pos - run.player.pos).normalized()
		var speed: float = maxf(run.player.pos.distance_to(target.pos), float(run.player.radius)) / float(stats.travel_delay)
		var length := float(spell.range)
		run.projectiles.append({"id": run._next_projectile_id, "spell_id": "F01", "from": run.player.pos, "to": run._clip_motion(run.player.pos, direction * length, 0.0), "pos": run.player.pos, "direction": direction, "speed": speed, "travelled": 0.0, "range": length, "duration": length / speed, "remaining": length / speed, "radius": float(run._runtime.bolt_collision_radius), "blast_radius": float(stats.level.radius), "coefficient": coefficient, "context": context.duplicate(true)})
		run._next_projectile_id += 1

class LegacyCombat extends CompatibilityCombat:
	func _update_projectiles(run, dt: float):
		var retained: Array = []
		for projectile in run.projectiles:
			var from: Vector2 = projectile.pos
			var distance = minf(float(projectile.speed) * dt, float(projectile.range) - float(projectile.travelled))
			var to: Vector2 = from + projectile.direction * distance
			var earliest = run._first_block_contact(from, to, float(projectile.radius))
			var hit: Dictionary = {}
			for actor in run.actors:
				if actor.health <= 0.0: continue
				var contact: float = run.segment_circle_time(from - actor.previous, to - actor.pos, Vector2.ZERO, float(actor.radius) + float(projectile.radius))
				if contact < earliest - 0.000001 or (absf(contact - earliest) < 0.000001 and contact != INF and not hit.is_empty() and actor.id < hit.id):
					earliest = contact
					hit = actor
			if earliest != INF:
				var impact = from.lerp(to, clampf(earliest, 0.0, 1.0))
				if not hit.is_empty(): _area_hit(run, impact, float(projectile.blast_radius), float(projectile.coefficient), projectile.context, true)
				run._emit("bolt_hit", {"pos": impact, "radius": projectile.blast_radius, "spell_id": "F01", "blocked": hit.is_empty()}, float(runtime.effects.impact_lifetime))
				continue
			projectile.pos = to
			projectile.travelled += distance
			projectile.remaining = maxf(0.0, float(projectile.remaining) - dt)
			if projectile.travelled < projectile.range - 0.000001 and run._inside_floor(projectile.pos, float(projectile.radius)): retained.append(projectile)
		run.projectiles = retained


func _initialize() -> void: call_deferred("execute")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("F01 chain: " + label)


func fresh(level: int = 1, legacy: bool = false, compatibility: bool = false):
	var run = Rules.Fixture.new()
	check(run.configure({}, 20261026).ok and run.choose_initial("F01"), "real route starts for F01 fixture")
	if legacy or compatibility:
		run._spell_combat = LegacyCombat.new() if legacy else CompatibilityCombat.new()
		check(run._spell_combat.configure(run).ok, "baseline collision comparator configures")
	run._spawn_done = true
	run.spawn_warnings.clear()
	run.blocks.clear()
	run.player.pos = Vector2.ZERO
	run.player.previous = Vector2.ZERO
	run.player.crit_rate = 1.0 if level > 1 else 0.0
	run.spells.clear()
	var spell: Dictionary = run._new_spell("F01")
	spell.level = level
	run._refresh_spell(spell)
	spell.remaining = 9999.0
	run.spells.append(spell)
	var actor: Dictionary = run._enemy_combat.make_actor(run, "M01", Vector2(0, 3), 77)
	actor.health = 100000.0
	actor.max_health = actor.health
	run.actors = [actor]
	return run


func cast(run) -> void:
	var spell: Dictionary = run.spells[0]
	run._spell_combat._cast(run, spell, run.get_spell_stats(spell), run.actors[0], true, 1.0)
	spell.remaining = 9999.0


func execute() -> void:
	core_parity()
	contact_facts()
	var renderer = Fire.new()
	root.add_child(renderer)
	await process_frame
	check(renderer.is_available() and renderer.get_child_count() == 4, "real renderer uses four fixed nodes")
	for shader: Shader in [Fire.BODY_SHADER, Fire.TRAIL_SHADER, Fire.SURFACE_SHADER]:
		check(not shader.get_shader_uniform_list().is_empty(), "shader-language compile: " + shader.resource_path)
	var quad: Array = renderer._bodies.multimesh.mesh.get_mesh_arrays()
	var vertices: PackedVector3Array = quad[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = quad[Mesh.ARRAY_TEX_UV]
	for index in vertices.size(): check(signf(vertices[index].x) == signf(uvs[index].x - 0.5), "real engine UV points the flame front forward")
	var projector := Projector.new()
	path_pause_projection(renderer, projector)
	terminal_lifecycle(renderer, projector)
	burn_and_patch(renderer, projector)
	capacity(renderer, projector)
	await integration_and_preview()
	renderer.queue_free()
	await process_frame
	var report := {"checks": checks, "failures": failures.size(), "details": failures,
		"scope": "Old-loop comparison ONLY for explicitly legacy-shaped shots; current curved native shots use the separate curve suite. Terminal facts, world trails, live burn/patch ownership, pause/reduced motion, finite batches and view/preview construction. Headless only; no pixels, GPU composition, performance, natural route or visual acceptance."}
	if not Report.write_report(report, OUTPUT):
		failures.append("QA report could not be written")
	print("FIRE BOLT CHAIN checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func core_parity() -> void:
	for case in 36:
		var actual = fresh(1 + case % 3, false, true)
		var reference = fresh(1 + case % 3, true)
		for run in [actual, reference]:
			run.actors[0].pos = Vector2(float(case % 3) * 0.2, 1.0 + float(case % 7) * 0.7)
			run.actors[0].previous = run.actors[0].pos
			cast(run)
			if case % 4 == 1: run.blocks.append({"center": Vector2(0, 0.55), "size": Vector2(1.3, 0.15)})
			elif case % 4 == 2:
				run.actors[0].pos.x += 4.0
				run.actors[0].previous = run.actors[0].pos
			elif case % 4 == 3:
				var second: Dictionary = run.actors[0].duplicate(true)
				second.id = 20
				run.actors.append(second)
		for frame in 96:
			actual.step(1.0 / 120.0)
			reference.step(1.0 / 120.0)
		var left: Dictionary = actual.get_snapshot()
		var right: Dictionary = reference.get_snapshot()
		for key in ["player", "actors", "projectiles", "effects", "spells", "spell_burns", "artifact_patches", "spell_zones", "spell_pending"]:
			check(left.get(key) == right.get(key), "old-loop gameplay parity case %d: %s" % [case, key])
		check(actual._rng.state == reference._rng.state, "journal cannot consume gameplay RNG case %d" % case)


func contact_facts() -> void:
	for mode in ["enemy", "wall", "expired"]:
		var run = fresh()
		cast(run)
		if mode == "wall": run.blocks = [{"center": Vector2(0, 1), "size": Vector2(1.5, 0.2)}]
		elif mode == "expired":
			run.actors[0].pos = Vector2(4, 3)
			run.actors[0].previous = run.actors[0].pos
		for frame in 80:
			run.step(1.0 / 120.0)
			if not run.get_snapshot().fire_bolt_ends.is_empty(): break
		var events: Array = run.get_snapshot().fire_bolt_ends
		check(events.size() == 1 and events[0].reason == mode, "real F01 branch records exactly one " + mode)
		if events.is_empty(): continue
		var event: Dictionary = events[0]
		check(float(event.time) <= float(run.time) + 0.000001 and float(event.time) >= float(run.time) - 1.0 / 120.0 - 0.000001, "contact time is within the actual motion substep: " + mode)
		check(event.pos.is_finite() and event.contact_pos.is_finite() and event.normal.is_normalized(), "contact facts have finite point and normal: " + mode)
		if mode == "wall": check(absf(float(event.contact_pos.y) - 0.9) < 0.00001 and run.actors[0].health == 100000.0, "wall contact uses surface and cannot deal an area hit")
		if mode == "enemy": check(event.actor_id == 77 and run.actors[0].health < 100000.0, "enemy impact refers to the actual damaged actor")
		if mode == "expired": check(not run.effects.any(func(e): return e.kind == "bolt_hit"), "natural expiration creates no gameplay impact")
		events[0].pos = Vector2(99, 99)
		check(run.get_snapshot().fire_bolt_ends[0].pos != events[0].pos, "contact journal snapshot is a deep copy")
		run._spell_combat.stop_room()
		check(run.get_snapshot().fire_bolt_ends.is_empty(), "room cleanup clears F01 facts")
	var capped = fresh()
	cast(capped)
	var source: Dictionary = capped.projectiles[0].duplicate(true)
	var before: int = capped._rng.state
	for index in 280: capped._spell_combat._note_bolt_end(capped, source, Vector2.ZERO, Vector2.UP, 1.0, 0.1, "expired")
	check(capped.get_snapshot().fire_bolt_ends.size() <= 256 and capped._rng.state == before, "presentation journal stays bounded and RNG-free")


func snapshot(now: float, shots: Array = [], ends: Array = [], revision: int = 1) -> Dictionary:
	return {"phase": "combat", "time": now, "room_revision": revision, "projectiles": shots, "fire_bolt_ends": ends, "actors": [], "spell_burns": [], "artifact_patches": [], "effects": []}


func shot(id: int, pos: Vector2, speed: float = 30.0) -> Dictionary:
	return {"id": id, "spell_id": "F01", "pos": pos, "from": Vector2.ZERO, "direction": Vector2.RIGHT, "radius": 0.15, "speed": speed, "travelled": pos.length()}


func ended(reason: String, now: float, id: int = 1) -> Dictionary:
	return {"seq": id, "projectile_id": id, "reason": reason, "pos": Vector2(3, 0), "contact_pos": Vector2(3.15, 0), "normal": Vector2.LEFT, "origin": Vector2.ZERO, "from": Vector2(2.8, 0), "direction": Vector2.RIGHT, "radius": 0.15, "blast_radius": 1.3, "speed": 30.0, "travelled": 3.0, "time": now}


func path_pause_projection(renderer, projector) -> void:
	for fps in [30, 60, 144]:
		for speed in [3.0, 30.0, 60.0]:
			for frame in range(1, int(fps * 0.4) + 1):
				var now: float = float(frame) / fps
				renderer.sync_snapshot(snapshot(now, [shot(1, Vector2(now * speed, 0), speed)], [], fps), projector)
			var state: Dictionary = renderer.get_debug_state()
			var path: PackedVector2Array = state.paths[0].world_path
			var length := 0.0
			for index in range(1, path.size()): length += path[index - 1].distance_to(path[index])
			var expected := minf(speed * float(renderer._config.history_seconds), minf(0.15 * float(renderer._config.head_scale_by_level[0]) * float(renderer._config.tail_max_radii), float(renderer._config.tail_max_m)))
			check(absf(length - expected) < 0.025, "tail history/cap stable at %dfps %.1fm/s" % [fps, speed])
			check(state.indices.size() % 3 == 0 and state.vertices.size() == state.uvs.size(), "continuous ribbon topology is valid")
			check(state.paths[0].samples <= int(renderer._config.history_points), "history records remain bounded")
	var source := snapshot(2.0, [shot(1, Vector2(2, 0))], [], 100)
	var original := source.duplicate(true)
	renderer.sync_snapshot(source, projector)
	source.time = 2.05
	source.projectiles[0].pos = Vector2(3.5, 0)
	source.projectiles[0].travelled = 3.5
	original = source.duplicate(true)
	renderer.sync_snapshot(source, projector)
	check(source == original, "renderer cannot mutate any snapshot dictionary")
	var before: Dictionary = renderer.get_debug_state()
	source.paused = true
	for repeat in 5: renderer.sync_snapshot(source, projector)
	check(renderer.get_debug_state() == before, "repeated frozen snapshot leaves all geometry and clocks unchanged")
	projector.offset += Vector2(63, 21)
	renderer.sync_snapshot(source, projector)
	var after: Dictionary = renderer.get_debug_state()
	check(before.paths == after.paths, "camera movement cannot change world trails")
	var translated := true
	for index in before.vertices.size(): translated = translated and after.vertices[index].is_equal_approx(before.vertices[index] + Vector3(63, 21, 0))
	check(translated, "camera movement reprojects the entire tail with its head")
	renderer.sync_snapshot(source, projector, {"reduced_motion": true})
	check(renderer.get_debug_state().head_ids == before.head_ids and renderer.get_debug_state().paths == before.paths, "reduced motion retains projectile identity and path")
	for mat in [renderer._body_material, renderer._trail_material, renderer._surface_material]: check(mat.get_shader_parameter("reduced_motion") == true and mat.get_shader_parameter("core_time") == source.time, "all materials use the paused source time and reduced option")
	projector.offset = Vector2(640, 360)


func terminal_lifecycle(renderer, projector) -> void:
	for reason in ["enemy", "wall", "expired", "missing"]:
		var revision := 200 + ["enemy", "wall", "expired", "missing"].find(reason)
		renderer.sync_snapshot(snapshot(3.0, [shot(1, Vector2(2, 0))], [], revision), projector)
		var events: Array = [] if reason == "missing" else [ended(reason, 3.02)]
		var source := snapshot(3.04, [], events, revision)
		renderer.sync_snapshot(source, projector)
		var state: Dictionary = renderer.get_debug_state()
		check(state.heads == 0 and state.paths.size() == 1, "ended head leaves a fading world trail: " + reason)
		check(state.coverage.has("bolt_hit") == (reason == "enemy"), "only real enemy contact creates area blast: " + reason)
		check(state.coverage.has("bolt_blocked") == (reason == "wall"), "only a real wall contact creates wall scatter: " + reason)
		for repeat in 3: renderer.sync_snapshot(source, projector)
		check(renderer.get_debug_state() == state, "terminal facts deduplicate on repeated sync: " + reason)
		source.time = 3.6
		renderer.sync_snapshot(source, projector)
		check(not renderer.visible and renderer.get_debug_state().paths.is_empty(), "terminal chain completely cleans up: " + reason)
	renderer.sync_snapshot(snapshot(4.04, [], [ended("enemy", 4.0)], 300), projector)
	check(renderer.get_debug_state().coverage.has("bolt_hit") and renderer.get_debug_state().paths[0].world_path.size() >= 2, "a high-speed shot born/ended between frames still has a real contact and tail")
	var clean := snapshot(4.05, [], [], 300)
	clean.phase = "pickup"
	renderer.sync_snapshot(clean, projector)
	check(not renderer.visible and renderer.get_debug_state().impacts.is_empty(), "leaving combat clears all decoration immediately")


func burn_and_patch(renderer, projector) -> void:
	var source := snapshot(5.0, [], [], 400)
	source.actors = [{"id": 5, "pos": Vector2(1, 2), "radius": 0.4, "health": 100.0}]
	source.spell_burns = [{"actor_id": 5, "token": 9, "remaining": 3.0, "source": "F01"}]
	source.artifact_patches = [{"pos": Vector2(2, 1), "radius": 1.6, "remaining": 2.5, "context": {"spell_id": "F01", "cast_id": 7}}]
	var original := source.duplicate(true)
	renderer.sync_snapshot(source, projector)
	var state: Dictionary = renderer.get_debug_state()
	check(source == original and state.coverage.has("burning") and state.coverage.has("artifact_patch"), "actual F01-source burn and growth patch render without mutation")
	check(not state.coverage.has("fire_ignited"), "view attached midway through a burn cannot invent an ignition")
	check(state.footprints.any(func(p): return p.kind == "artifact_patch" and p.radius == 1.6), "critical fire footprint uses the authoritative radius")
	source.time = 5.3
	source.actors[0].pos += Vector2(0.8, 0.3)
	renderer.sync_snapshot(source, projector)
	check(renderer.get_debug_state().footprints.any(func(p): return p.kind == "burning" and p.pos == source.actors[0].pos), "burn tongues follow the actual moving actor")
	check(not renderer.get_debug_state().coverage.has("fire_ignited"), "persistent burn does not replay its initial ignition")
	source.spell_burns[0].source = "F03"
	renderer.sync_snapshot(source, projector)
	check(not renderer.get_debug_state().coverage.has("burning") and not renderer.get_debug_state().coverage.has("extinguish"), "a refresh by another spell hands ownership back without false extinction")
	source.spell_burns[0].source = "F01"
	source.spell_burns[0].token = 10
	source.effects = [{"kind": "fire_ignited", "source": "F01", "actor_id": 5, "max_life": 0.5, "life": 0.5}]
	renderer.sync_snapshot(source, projector)
	check(renderer.get_debug_state().coverage.has("fire_ignited"), "a genuine fresh ignition fact creates the one-off flare")
	source.time = 5.8
	source.spell_burns.clear()
	source.artifact_patches.clear()
	renderer.sync_snapshot(source, projector)
	check(renderer.get_debug_state().coverage.has("extinguish") and not renderer.get_debug_state().coverage.has("artifact_patch"), "expired burn cools while ended critical patch loses its active footprint")
	source.time = 6.2
	renderer.sync_snapshot(source, projector)
	check(not renderer.visible, "burn and patch chain leaves no persistent fire")
	source.time = 6.3
	source.spell_burns = [{"actor_id": 5, "token": 11, "remaining": 3.0, "source": "F01"}]
	renderer.sync_snapshot(source, projector)
	source.time = 6.4
	source.spell_burns.clear()
	source.effects = [{"kind": "fire_detonation", "actor_id": 5}]
	renderer.sync_snapshot(source, projector)
	check(not renderer.get_debug_state().coverage.has("extinguish"), "burn consumption by F07 does not fake a natural extinction")


func capacity(renderer, projector) -> void:
	var shots: Array = []
	var ends: Array = []
	for id in 128:
		shots.append(shot(id + 1, Vector2(2, 0)))
		ends.append(ended("enemy", 7.02, id + 1))
	renderer.sync_snapshot(snapshot(7.0, shots, [], 500), projector)
	check(renderer.get_debug_state().heads == 128 and renderer.get_debug_state().overflow == 0, "128 live F01 heads keep their identity in finite shared batches")
	renderer.sync_snapshot(snapshot(7.04, [], ends, 500), projector)
	check(renderer.get_debug_state().coverage.get("bolt_hit", 0) == 128 and renderer.get_debug_state().overflow == 0, "simultaneous source contacts retain their real impact feedback")
	check(renderer.get_child_count() == 4, "capacity does not allocate per-shot nodes")


func integration_and_preview() -> void:
	var run = fresh(3)
	cast(run)
	for frame in 4: run.step(1.0 / 120.0)
	var source: Dictionary = run.get_snapshot()
	var original := source.duplicate(true)
	var view = View.new()
	root.add_child(view)
	await process_frame
	view.sync(source)
	check(view.get_fire_bolt_debug_state().heads == source.projectiles.size(), "actual battle view consumes the real F01 shots")
	check(view.fire_bolt_vfx.z_index < view._overlay.z_index and view.fire_bolt_vfx.z_index < view.magic_missile_vfx.z_index, "friendly fire stays below warnings and accepted hostile missiles")
	check(not view.spell_vfx.get_debug_state().coverage.has("F01_bolt"), "legacy F01 body is suppressed without a duplicate")
	view.set_visual_options({"reduced_motion": true})
	check(view.fire_bolt_vfx._body_material.get_shader_parameter("reduced_motion") == true, "display option updates F01 immediately even with no advancing tick")
	check(source == original, "complete battle view leaves its source unchanged")
	view.queue_free()
	await process_frame
	var scene: PackedScene = load("res://tests/previews/fire_bolt_preview.tscn")
	var preview = scene.instantiate()
	root.add_child(preview)
	preview.set_process(false)
	await process_frame
	for mode in 5:
		preview._mode = mode
		preview._reset()
		var seen: Dictionary = {}
		for frame in 168:
			preview._advance(1.0 / 120.0)
			if frame % 2 == 0:
				preview._view.sync(preview._run.get_snapshot())
				seen.merge(preview._view.get_fire_bolt_debug_state().coverage)
		for stage in ["cast", "release", "F01_bolt"]:
			check(seen.has(stage), "actual preview mode %d contains stage %s" % [mode, stage])
		if mode < 3:
			for stage in ["bolt_hit", "fire_ignited", "burning"]: check(seen.has(stage), "actual complete chain mode %d contains stage %s" % [mode, stage])
		if mode in [1, 2]: check(seen.has("artifact_patch"), "critical patch reaches the production renderer")
		var ends: Array = preview._run.get_snapshot().fire_bolt_ends
		check(not ends.is_empty(), "controlled preview mode %d reaches a real terminal branch" % mode)
		if not ends.is_empty():
			check(ends[0].reason == ("wall" if mode == 3 else "expired" if mode == 4 else "enemy"), "preview mode %d uses source collision facts" % mode)
		if mode == 2: check(ends.size() == 2, "level-three preview uses the real delayed second bolt")
		if mode in [1, 2]: check(not preview._run.get_snapshot().artifact_patches.is_empty(), "critical preview obtains its patch through real damage")
	preview.queue_free()
	await process_frame
