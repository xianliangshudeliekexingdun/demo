extends SceneTree
## Real Route regressions + read-only geometry/lifecycle. No pixels or GPU claims.
const Rain = preload("res://scripts/presentation/route_fire_rain_vfx.gd")
const View = preload("res://scripts/presentation/first_room_view.gd")
const Rules = preload("res://tests/formal_fire_tests.gd")
const Report = preload("res://tests/qa_report.gd")
const OUTPUT := "res://build/qa/fire-rain-vfx-20261027/targeted/results.json"
const STEP := 1.0 / 120.0
var checks := 0
var failures: Array = []
var baseline_cases := 0

class Projector extends RefCounted:
	var scale := 40.0
	var offset := Vector2(640, 360)
	func screen_position(pos: Vector2, height: float = 0.0) -> Vector2:
		return Vector2(pos.x * scale, -pos.y * scale * 0.65 - height * scale) + offset


func _initialize() -> void: call_deferred("execute")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("F03 chain: " + label)


func fresh(level: int = 1, seed: int = 20261027, baseline: Script = null):
	var run = Rules.Fixture.new()
	check(run.configure({}, seed).ok and run.choose_initial("F03"), "real F03 fixture configures")
	if baseline != null:
		run._spell_combat = baseline.new()
		check(run._spell_combat.configure(run).ok, "frozen pre-change combat configures")
	run._spawn_done = true
	run.spawn_warnings.clear()
	run.blocks.clear()
	run.player.pos = Vector2.ZERO
	run.player.previous = Vector2.ZERO
	run.player.crit_rate = 0.0
	run.spells.clear()
	add_spell(run, "F03", level)
	run.actors.clear()
	for index in 3:
		var actor: Dictionary = run._enemy_combat.make_actor(run, "M01", Vector2(float(index - 1), 3.0), 77 + index)
		actor.health = 100000.0
		actor.max_health = actor.health
		run.actors.append(actor)
	return run


func add_spell(run, id: String, level: int) -> void:
	var spell: Dictionary = run._new_spell(id)
	spell.level = level
	run._refresh_spell(spell)
	spell.remaining = 9999.0
	run.spells.append(spell)


func cast(run, slot: int = 0, natural: bool = true) -> void:
	var spell: Dictionary = run.spells[slot]
	run._spell_combat._cast(run, spell, run.get_spell_stats(spell), run.actors[1], natural, 1.0 if natural else 0.7)
	spell.remaining = 9999.0


func advance(run, seconds: float) -> void:
	for frame in roundi(seconds / STEP): run.step(STEP)


func execute() -> void:
	core_parity()
	var renderer = Rain.new()
	root.add_child(renderer)
	await process_frame
	check(renderer.is_available() and renderer.get_child_count() == 4, "four fixed drawing nodes")
	for shader: Shader in [Rain.BODY_SHADER, Rain.TRAIL_SHADER, Rain.SURFACE_SHADER]:
		check(not shader.get_shader_uniform_list().is_empty(), "local shader-language parsing: " + shader.resource_path)
	var projector := Projector.new()
	full_chains(renderer, projector)
	projection_pause_and_read_only(renderer, projector)
	overlapping_casts_and_ground_end(renderer, projector)
	cancellation_and_burn_ownership(renderer, projector)
	capacity(renderer, projector)
	await integration_and_preview()
	renderer.queue_free()
	await process_frame
	var result := {"checks": checks, "failures": failures.size(), "details": failures, "frozen_baseline_cases": baseline_cases,
		"scope": "Headless real-Route equivalence, actual fall/order/impact facts, level-three ground timing/center, burns, analytic world tails, pause, reduced motion, finite batches and native view/preview construction. No screenshots, rendered pixels, backend composition, performance, natural route or user visual acceptance."}
	if not Report.write_report(result, OUTPUT): failures.append("cannot write report")
	print("FIRE RAIN CHAIN checks=%d failures=%d baseline_cases=%d" % [checks, failures.size(), baseline_cases])
	quit(0 if failures.is_empty() else 1)


func gameplay(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			if key not in ["fire_rain_impacts", "drop_index", "release_pos"]: result[key] = gameplay(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(gameplay(item))
		return result
	return value


func core_parity() -> void:
	var path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline="): path = argument.trim_prefix("--baseline=")
	if path.is_empty(): return # Frozen source is a change-specific QA artifact, never a runtime dependency.
	var baseline: Script = load(path)
	check(baseline != null, "supplied pre-change baseline loads")
	if baseline == null: return
	for scenario in 18:
		var level := 1 + scenario % 3
		var actual = fresh(level, 20261027 + scenario)
		var reference = fresh(level, 20261027 + scenario, baseline)
		for run in [actual, reference]:
			if scenario % 6 == 1: run.blocks.append({"center": Vector2(1.2, 3.0), "size": Vector2(0.3, 1.8)})
			if scenario % 6 == 5:
				add_spell(run, "F01", 3)
				add_spell(run, "F06", 3)
				cast(run, 1)
				cast(run, 2)
			cast(run, 0, scenario % 6 != 4)
			if scenario % 6 == 2:
				for actor in run.actors:
					actor.pos.x += 4.0
					actor.previous = actor.pos
		for frame in 750:
			if frame == 96 and scenario % 6 == 3:
				cast(actual)
				cast(reference)
			actual.step(STEP)
			reference.step(STEP)
			if frame in [0, 35, 83, 275, 371, 432, 749]:
				var left: Dictionary = actual.get_snapshot()
				var right: Dictionary = reference.get_snapshot()
				for key in ["player", "actors", "spells", "effects", "spell_pending", "spell_zones", "spell_burns", "artifact_patches", "projectiles", "gems", "time", "combat_time", "phase"]:
					check(gameplay(left.get(key)) == gameplay(right.get(key)), "frozen actual Route parity case %d frame %d %s" % [scenario, frame, key])
				check(actual._rng.state == reference._rng.state, "gameplay RNG parity case %d frame %d" % [scenario, frame])
		check(actual.damage_log == reference.damage_log, "all real damage results preserve case %d" % scenario)
		baseline_cases += 1


func full_chains(renderer, projector) -> void:
	for level in range(1, 4):
		var run = fresh(level)
		run.room_revision = 10 + level
		run.spells[0].remaining = 0.0
		run.step(STEP)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(int(renderer.get_debug_state().coverage.get("F03_cast", 0)) == 1, "real chant appears at level %d" % level)
		advance(run, 0.4)
		var pending: Array = run._spell_combat.pending.duplicate(true)
		check(pending.size() == (6 if level == 1 else 8), "released actual count level %d" % level)
		if pending.is_empty(): continue
		var release_at := float(run._spell_combat.zones[0].born_at)
		var center: Vector2 = pending[0].center
		var last_at := float(pending[-1].at)
		for index in pending.size():
			check(pending[index].drop_index == index and pending[index].context.spell_level == level, "released identity and level %d:%d" % [level, index])
			check(is_equal_approx(float(pending[index].at), release_at + 0.3 + float(index) * 0.4), "existing fall schedule %d:%d" % [level, index])
			if index < (1 if level == 1 else 2): check(pending[index].pos == center, "fixed original center %d:%d" % [level, index])
		# Released level/geometry remain authoritative after the slot changes.
		run.spells[0].level = 1
		run.spells[0].remaining = 9999.0
		var unique_impacts: Dictionary = {}
		var unique_first: Dictionary = {}
		var saw_fall := false
		var saw_release := false
		var saw_burn := false
		var saw_ground := false
		var saw_cooling := false
		var birth_checked := false
		for frame in 1050:
			run.step(STEP)
			renderer.sync_snapshot(run.get_snapshot(), projector)
			var debug: Dictionary = renderer.get_debug_state()
			saw_fall = saw_fall or not debug.heads.is_empty()
			saw_release = saw_release or int(debug.coverage.get("F03_release", 0)) > 0
			saw_burn = saw_burn or not debug.burns.is_empty()
			saw_cooling = saw_cooling or int(debug.coverage.get("F03_cooling", 0)) > 0
			for footprint: Dictionary in debug.footprints:
				if footprint.kind == "rain_impact":
					unique_impacts[int(footprint.drop_index)] = true
					if footprint.first: unique_first[int(footprint.drop_index)] = true
					check(is_equal_approx(float(footprint.radius), 0.85) and int(footprint.spell_level) == level, "actual landing radius and released level")
					if int(footprint.drop_index) == 1: check(is_equal_approx(float(footprint.scale), 1.0), "second center fall never receives first emphasis")
				elif footprint.kind == "rain_ground":
					saw_ground = true
					check(level == 3 and float(run.time) >= last_at - 0.000001 and footprint.pos == center and is_equal_approx(float(footprint.radius), 2.2), "ground begins only after last fall at original center/radius")
					if not birth_checked:
						var zone: Dictionary = run._spell_combat.zones.filter(func(z): return z.kind == "rain_ground")[0]
						check(is_equal_approx(float(zone.tick_remaining), 0.5) and is_equal_approx(float(zone.age), 0.0), "ground birth waits its full existing interval")
						birth_checked = true
		check(saw_fall and saw_release and saw_burn, "complete release/fall/attached-burn chain level %d" % level)
		check(unique_impacts.size() == pending.size() and unique_first.size() == 1, "one real landing per scheduled fall and one emphasized first level %d" % level)
		check(saw_ground == (level == 3), "only level three has persistent ground")
		check(saw_cooling, "real natural completion cools at level %d" % level)
		check(not renderer.visible, "complete chain eventually returns to empty at level %d" % level)
		var journal: Array = run.get_snapshot().fire_rain_impacts
		check(journal.is_empty(), "completed falls have finite journal retention")
	var source = fresh(3)
	cast(source)
	advance(source, 0.31)
	var journal: Array = source.get_snapshot().fire_rain_impacts
	check(journal.size() == 1, "one completed first landing fact")
	journal[0].pos = Vector2(99, 99)
	check(source.get_snapshot().fire_rain_impacts[0].pos != journal[0].pos, "landing facts are deep copied")
	advance(source, 2.9) # Sample after the last direct fall, before ground ticks.
	var burn_expires := float(source._spell_combat.fire_status.burns[78].expires)
	advance(source, 0.6)
	check(is_equal_approx(float(source._spell_combat.fire_status.burns[78].expires), burn_expires), "level-three ground never refreshes attached burning")
	var saved_pending: Dictionary = pending_payload(source)
	var rng: int = source._rng.state
	for index in 300: source._spell_combat._note_rain_impact(source, saved_pending)
	check(source.get_snapshot().fire_rain_impacts.size() == 256 and source._rng.state == rng, "impact journal capacity is bounded and RNG free")
	source._spell_combat.stop_room()
	check(source.get_snapshot().fire_rain_impacts.is_empty(), "room stop clears landing facts")


func pending_payload(run) -> Dictionary:
	return {"pos": Vector2(0, 3), "center": Vector2(0, 3), "radius": 0.85, "at": float(run.time), "context": {"cast_id": 1, "spell_level": 3}, "stats": {"impact_delay": 0.3}, "last": false, "drop_index": 0}


func projection_pause_and_read_only(renderer, projector) -> void:
	var run = fresh(3)
	run.room_revision = 30
	cast(run)
	advance(run, 0.18)
	var snapshot: Dictionary = run.get_snapshot()
	var original: Dictionary = snapshot.duplicate(true)
	var rng: int = run._rng.state
	renderer.sync_snapshot(snapshot, projector)
	var before: Dictionary = renderer.get_debug_state()
	check(before.heads.size() == 1 and before.paths.size() == 1, "actual pending drop has head and continuous tail")
	if before.heads.is_empty(): return
	check(before.heads[0].axis.dot(Vector2.DOWN) > 0.99, "head points down and tail is above it")
	for frame_rate in [30, 60, 120]:
		for frame in 4: renderer.sync_snapshot(snapshot, projector)
		var repeated: Dictionary = renderer.get_debug_state()
		check(repeated.heads == before.heads and repeated.paths == before.paths, "same core progress is independent of render cadence %d" % frame_rate)
	run.set_paused(true)
	advance(run, 0.2)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	check(renderer.get_debug_state().heads == before.heads and renderer.get_debug_state().paths == before.paths, "pause freezes head and world tail")
	renderer.sync_snapshot(snapshot, projector, {"reduced_motion": true})
	check(renderer.get_debug_state().heads == before.heads and renderer.get_debug_state().paths == before.paths, "reduced motion retains real fall geometry and identity")
	projector.offset += Vector2(51, -23)
	projector.scale = 54.0
	renderer.sync_snapshot(snapshot, projector)
	var moved: Dictionary = renderer.get_debug_state()
	check(moved.paths == before.paths and moved.vertices != before.vertices, "camera/resolution change reprojects the full world tail")
	check(snapshot == original and run._rng.state == rng, "renderer cannot mutate source snapshot or gameplay RNG")
	projector.offset = Vector2(640, 360)
	projector.scale = 40.0
	var early_speed: float = renderer._height(0.1) - renderer._height(0.2)
	var late_speed: float = renderer._height(0.8) - renderer._height(0.9)
	check(late_speed > early_speed and is_equal_approx(float(renderer._height(1.0)), 0.04), "visual descent accelerates into the fixed landing point")
	var vanished: Dictionary = snapshot.duplicate(true)
	vanished.spell_pending.clear()
	renderer.sync_snapshot(vanished, projector)
	check(int(renderer.get_debug_state().coverage.get("F03_impact", 0)) == 0, "missing pending ID cannot invent a landing")
	var skipped = fresh(2)
	skipped.room_revision = 31
	cast(skipped)
	advance(skipped, 0.4)
	renderer.sync_snapshot(skipped.get_snapshot(), projector)
	check(int(renderer.get_debug_state().coverage.get("F03_impact", 0)) == 1, "actual impact journal survives a skipped rendering interval")


func cancellation_and_burn_ownership(renderer, projector) -> void:
	var run = fresh()
	run.room_revision = 40
	run._spell_combat.apply_burn(run, run.actors[1], "F03")
	advance(run, 0.5)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	check(renderer.get_debug_state().burns.size() == 1 and int(renderer.get_debug_state().coverage.get("F03_ignited", 0)) == 0, "mid-burn view attach cannot invent first ignition")
	run._spell_combat.apply_burn(run, run.actors[1], "F01")
	renderer.sync_snapshot(run.get_snapshot(), projector)
	check(renderer.get_debug_state().burns.is_empty() and renderer.get_debug_state().cooling.is_empty(), "source handoff neither double draws nor falsely extinguishes")
	run._spell_combat.apply_burn(run, run.actors[1], "F03")
	renderer.sync_snapshot(run.get_snapshot(), projector)
	run._spell_combat.detonate_burn(run, run.actors[1], 1.0)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	check(renderer.get_debug_state().burns.is_empty() and renderer.get_debug_state().cooling.is_empty(), "F07 fuel consumption is not natural extinction")
	var ground = fresh(3)
	ground.room_revision = 41
	cast(ground)
	advance(ground, 3.2)
	renderer.sync_snapshot(ground.get_snapshot(), projector)
	check(not renderer.get_debug_state().live_grounds.is_empty(), "live ground enters finite history")
	ground._spell_combat.stop_room()
	renderer.sync_snapshot(ground.get_snapshot(), projector)
	check(renderer.get_debug_state().live_grounds.is_empty() and renderer.get_debug_state().cooling.is_empty(), "early ground cancellation has no natural cooling or burst")
	ground.phase = "pickup"
	renderer.sync_snapshot(ground.get_snapshot(), projector)
	check(not renderer.visible and renderer.get_debug_state().vertices.is_empty(), "combat exit clears every batch")


func overlapping_casts_and_ground_end(renderer, projector) -> void:
	var run = fresh(1)
	run.room_revision = 35
	cast(run)
	run.spells[0].level = 3
	run.actors[1].pos = Vector2(2, 3)
	run.actors[1].previous = run.actors[1].pos
	cast(run)
	advance(run, 0.15)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	var heads: Array = renderer.get_debug_state().heads
	check(heads.size() == 2 and heads[0].cast_id != heads[1].cast_id and heads[0].scale < heads[1].scale, "overlapping casts preserve their individual released levels and first-head identities")
	advance(run, 0.15)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	var firsts: Array = renderer.get_debug_state().footprints.filter(func(f): return f.kind == "rain_impact" and f.first)
	check(firsts.size() == 2 and firsts[0].cast_id != firsts[1].cast_id, "simultaneous first impacts remain separate actual landings")
	advance(run, 2.8)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	var areas: Array = renderer.get_debug_state().footprints.filter(func(f): return f.kind == "rain_ground")
	check(areas.size() == 1 and areas[0].pos == Vector2(2, 3), "only the level-three cast creates its own original-center ground")
	if areas.is_empty(): return
	var zone_id := int(areas[0].zone_id)
	advance(run, 3.0)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	var debug: Dictionary = renderer.get_debug_state()
	check(debug.live_grounds.is_empty() and debug.cooling.has("zone:%d" % zone_id), "natural ground expiry removes the live perimeter and starts only cooling embers")
	check(int(debug.coverage.get("F03_impact", 0)) == 0, "ground expiry never invents a final explosion")
	advance(run, 0.3)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	check(not renderer.get_debug_state().cooling.has("zone:%d" % zone_id), "ground cooling history has a finite lifetime")


func capacity(renderer, projector) -> void:
	var run = fresh(3)
	run.room_revision = 50
	cast(run)
	advance(run, 0.15)
	var snapshot: Dictionary = run.get_snapshot()
	var template: Dictionary = snapshot.spell_pending[0].duplicate(true)
	snapshot.spell_pending.clear()
	snapshot.spell_zones.clear()
	for index in 128:
		var item := template.duplicate(true)
		item.context.cast_id = index + 1
		snapshot.spell_pending.append(item)
	renderer.sync_snapshot(snapshot, projector)
	var debug: Dictionary = renderer.get_debug_state()
	check(debug.heads.size() == 128 and debug.paths.size() == 128 and int(debug.overflow) == 0, "128 active falls retain all heads and paths within fixed capacities")
	check(debug.batch_nodes == 4 and debug.material_count == 3, "high fall counts allocate no extra nodes or materials")
	for index in 128: snapshot.spell_pending.append(template.duplicate(true))
	renderer.sync_snapshot(snapshot, projector, {"reduced_motion": true})
	check(renderer.get_debug_state().heads.size() == 128 and int(renderer.get_debug_state().overflow) >= 128, "excess decorative load is bounded without changing source state")


func integration_and_preview() -> void:
	var run = fresh(3)
	cast(run)
	advance(run, 0.16)
	var view = View.new()
	root.add_child(view)
	await process_frame
	view.sync(run.get_snapshot())
	check(view.get_fire_rain_debug_state().heads.size() == 1, "native battle view uses the new rain renderer")
	check(int(view.spell_vfx.get_debug_state().coverage.get("F03_rainfall", 0)) == 0, "legacy rain no longer double draws")
	check(view.fire_rain_vfx.z_index < view._overlay.z_index and view.fire_rain_vfx.z_index < view.magic_missile_vfx.z_index, "hostile warnings and missiles stay above friendly rain")
	var old: Dictionary = run.get_snapshot()
	old.erase("fire_rain_impacts")
	view.sync(old)
	check(not view.fire_rain_vfx.visible and int(view.spell_vfx.get_debug_state().coverage.get("F03_rainfall", 0)) == 1, "older snapshots preserve the legacy rain fallback")
	view.queue_free()
	await process_frame
	var scene: PackedScene = load("res://tests/previews/fire_rain_preview.tscn")
	var preview = scene.instantiate()
	root.add_child(preview)
	preview.set_process(false)
	await process_frame
	preview.set_process(false)
	check(preview._run != null and preview._view != null, "optional preview constructs without running an interactive game")
	for mode in 5:
		preview._mode = mode
		preview._reset()
		check(preview._run.spells[0].id == "F03" and preview._run.spells[0].level == mini(mode + 1, 3), "controlled preview mode %d configures real F03" % mode)
	preview.queue_free()
	await process_frame
