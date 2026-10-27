extends SceneTree
## Auto-exiting, real-Route checks. Geometry assertions are not pixel acceptance.
const Bomb = preload("res://scripts/presentation/route_fire_bomb_vfx.gd")
const View = preload("res://scripts/presentation/first_room_view.gd")
const Rules = preload("res://tests/formal_fire_tests.gd")
const Report = preload("res://tests/qa_report.gd")
const OUTPUT := "res://build/qa/fire-bomb-vfx-20261027/targeted/results.json"
const STEP := 1.0 / 120.0
var checks := 0
var failures: Array = []
var baseline_cases := 0

class Projector extends RefCounted:
	var scale := 40.0
	var offset := Vector2(640, 360)
	var rotation := 0.0
	func screen_position(pos: Vector2, height: float = 0.0) -> Vector2:
		return Vector2(pos.x * scale, -pos.y * scale * 0.65 - height * scale).rotated(rotation) + offset


func _initialize() -> void: call_deferred("execute")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("F07 chain: " + label)


func add_spell(run, id: String, level: int) -> void:
	var spell: Dictionary = run._new_spell(id)
	spell.level = level
	run._refresh_spell(spell)
	spell.remaining = 9999.0
	run.spells.append(spell)


func fresh(level: int = 1, seed: int = 20261027, old_combat: Script = null, old_status: Script = null):
	var run = Rules.Fixture.new()
	check(run.configure({}, seed).ok and run.choose_initial("F01"), "real Route fixture enters combat")
	if old_combat != null:
		run._spell_combat = old_combat.new()
		check(run._spell_combat.configure(run).ok, "frozen combat configures")
		run._spell_combat.fire_status = old_status.new()
		run._spell_combat.fire_status.configure(run._spell_combat.runtime.fire.burning)
	run._spawn_done = true
	run.spawn_warnings.clear()
	run.blocks.clear()
	run.player.pos = Vector2.ZERO
	run.player.previous = Vector2.ZERO
	run.player.crit_rate = 0.0
	run.spells.clear()
	add_spell(run, "F07", level)
	run.actors.clear()
	for index in 3:
		var actor: Dictionary = run._enemy_combat.make_actor(run, "M01", Vector2([0.0, 1.9, 4.9][index], 2.0), 71 + index)
		actor.health = 100000.0
		actor.max_health = actor.health
		run.actors.append(actor)
	return run


func cast(run, natural: bool = true, slot: int = 0, target_index: int = 0) -> void:
	var spell: Dictionary = run.spells[slot]
	spell["locked_pos"] = run.actors[target_index].pos
	run._spell_combat._cast(run, spell, run.get_spell_stats(spell), run.actors[target_index], natural, 1.0 if natural else 0.7)
	spell.remaining = 9999.0


func advance(run, seconds: float) -> void:
	for frame in roundi(seconds / STEP): run.step(STEP)


func phases(run, phase: String) -> Array:
	return run.get_snapshot().fire_bomb_facts.filter(func(f): return str(f.phase) == phase)


func status_phases(run, phase: String) -> Array:
	return run.get_snapshot().fire_bomb_status_facts.filter(func(f): return str(f.phase) == phase)


func gameplay(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			if key not in ["fire_bomb_facts", "fire_bomb_status_facts"]: result[key] = gameplay(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(gameplay(item))
		return result
	return value


func core_parity() -> void:
	var paths: Dictionary = {}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline-combat="): paths.combat = argument.trim_prefix("--baseline-combat=")
		if argument.begins_with("--baseline-status="): paths.status = argument.trim_prefix("--baseline-status=")
	if not paths.has_all(["combat", "status"]): return
	var old_combat: Script = load(paths.combat)
	var old_status: Script = load(paths.status)
	check(old_combat != null and old_status != null, "both independent frozen sources load")
	if old_combat == null or old_status == null: return
	for scenario in 36:
		var level := 1 + scenario % 3
		var mode := scenario % 12
		var actual = fresh(level, 20261027 + scenario)
		var reference = fresh(level, 20261027 + scenario, old_combat, old_status)
		for run in [actual, reference]:
			if mode not in [0, 10]:
				for index in 2: run._spell_combat.apply_burn(run, run.actors[index], "F11")
			if mode == 3: run.actors[0].health = 1.0
			if mode == 6: run.blocks.append({"center": Vector2(0, 1), "size": Vector2(3, 0.4)})
			if mode == 7:
				for id in ["F01", "F03", "F08"]: add_spell(run, id, 3)
				for slot in range(1, 4): cast(run, true, slot)
			if mode == 8:
				run.player.crit_rate = 0.65
				run.player.crit_multiplier = 2.0
			if mode == 10:
				run.spells[0].remaining = 0.0
				run.step(STEP)
				run.actors[0].pos = Vector2(5, 2)
				run.actors[0].previous = run.actors[0].pos
			else: cast(run, mode != 2)
			if mode == 1:
				cast(run, false)
				cast(run, false, 0, 1)
			if mode == 9: run.spells[0].level = 1
		for frame in 300:
			for run in [actual, reference]:
				if mode == 4 and frame == 25:
					run.actors[0].pos = Vector2(7, 2)
					run.actors[0].previous = run.actors[0].pos
				if mode == 5 and frame == 70: run.damage_enemy(run.actors[0], 9999999.0, "fixture")
				if mode == 11 and frame == 20: run.set_paused(true)
				if mode == 11 and frame == 45: run.set_paused(false)
				if mode == 8 and frame == 80:
					run._spell_combat.apply_burn(run, run.actors[0], "F11")
					cast(run)
				run.step(STEP)
			if frame in [0, 23, 53, 70, 113, 126, 181, 299]:
				var left: Dictionary = gameplay(actual.get_snapshot())
				var right: Dictionary = gameplay(reference.get_snapshot())
				for key in left: check(left[key] == right.get(key), "full frozen snapshot case %d frame %d key %s" % [scenario, frame, key])
				check(actual._rng.state == reference._rng.state, "unchanged gameplay RNG %d/%d" % [scenario, frame])
		for key in ["damage_log", "context_log", "cast_log", "extra_log", "emitted"]:
			check(actual.get(key) == reference.get(key), "unchanged real hook/event %d %s" % [scenario, key])
		baseline_cases += 1


func stages_and_fuel(renderer, projector) -> void:
	for level in range(1, 4):
		var run = fresh(level)
		run.room_revision = 10 + level
		run.spells[0].remaining = 0.0
		run.step(STEP)
		var locked: Vector2 = run.spells[0].locked_pos
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(renderer.get_debug_state().coverage.get("F07_cast", 0) == 1 and renderer.get_debug_state().heads.is_empty(), "chant before any flight L%d" % level)
		run.actors[0].pos = Vector2(5.5, 2)
		run.actors[0].previous = run.actors[0].pos
		run.player.pos = Vector2(-1, -1)
		run.player.previous = run.player.pos
		advance(run, 0.65)
		run.spells[0].remaining = 9999.0
		check(phases(run, "flight").size() == 1, "one release after original chant")
		if phases(run, "flight").is_empty(): continue
		var flight: Dictionary = phases(run, "flight")[0]
		check(flight.pos == locked and flight.from == run.player.pos and is_equal_approx(float(flight.flight_seconds), 0.45), "chant-locked aim with actual release origin and delay")
		advance(run, 0.225)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		var mid: Dictionary = renderer.get_debug_state()
		check(mid.heads.size() == 1 and mid.paths.size() == 1, "one molten head plus continuous world tail")
		if not mid.heads.is_empty(): check(float(mid.heads[0].world.y) > 2.5 and mid.heads[0].to == locked, "arc rises above both endpoints and never follows moved target")
		var snapshot: Dictionary = run.get_snapshot()
		snapshot.fire_bomb_facts[0].pos = Vector2(99, 99)
		check(phases(run, "flight")[0].pos == locked, "journal copies are isolated")
		run.spells[0].level = 1
		advance(run, 0.225)
		var impacts: Array = phases(run, "impact")
		check(impacts.size() == 1 and impacts[0].pos == locked and impacts[0].spell_level == level, "real impact keeps released level and locked point")
		if impacts.is_empty(): continue
		var impact: Dictionary = impacts[0]
		check(is_equal_approx(float(impact.time) - float(flight.time), 0.45) and impact.hits.size() == 1 and impact.hits[0].actor_id == 72 and not impact.hits[0].center, "actual outer hit only, dodged target has no invented hit")
		renderer.sync_snapshot(run.get_snapshot(), projector)
		var debug: Dictionary = renderer.get_debug_state()
		check(debug.heads.is_empty() and debug.paths.size() == 1 and debug.ground_instances == 2, "impact replaces head with inner/outer surfaces and a fading tail")
		var centers: Array = debug.footprints.filter(func(f): return f.kind == "bomb_center")
		check(centers.size() == 1 and is_equal_approx(float(centers[0].radius), [0.9, 1.2, 1.3][level - 1]), "inner footprint follows actual level radius")
		check(run.get_snapshot().spell_burns.is_empty() and status_phases(run, "detonation").is_empty(), "no fuel means no ignition, detonation or fabricated reignite")
		advance(run, 0.6)
		var shocks: Array = phases(run, "aftershock")
		check(shocks.size() == (1 if level == 3 else 0), "only released L3 has aftershock after downgrade")
		if not shocks.is_empty():
			check(is_equal_approx(float(shocks[0].time) - float(impact.time), 0.6) and shocks[0].pos == locked and shocks[0].radius == impact.radius, "aftershock uses original position/radius and exact delay")
			renderer.sync_snapshot(run.get_snapshot(), projector)
			check(renderer.get_debug_state().coverage.get("F07_aftershock", 0) == 1 and renderer.get_debug_state().ground_instances == 1, "aftershock is a weaker independent low wave")
	for natural in [true, false]:
		var run = fresh(3)
		run._spell_combat.apply_burn(run, run.actors[0], "F11")
		cast(run, natural)
		advance(run, 0.45)
		var dets: Array = status_phases(run, "detonation")
		check(dets.size() == 1 and dets[0].actor_id == 71 and dets[0].amount > 0.0 and dets[0].future_ticks > 0, "only actual fueled actor discharges")
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(renderer.get_debug_state().footprints.filter(func(f): return f.kind == "fuel_detonation").size() == 1, "fuel feedback stays target-local")
		advance(run, 0.49)
		check(status_phases(run, "reignite").is_empty(), "no early delayed flame")
		advance(run, 0.01)
		check(status_phases(run, "reignite").size() == (1 if natural else 0), "only qualified natural L3 actually reignites")
		renderer.sync_snapshot(run.get_snapshot(), projector)
		if natural:
			check(renderer.get_debug_state().coverage.get("F07_reignite", 0) == 1 and renderer.get_debug_state().coverage.get("F07_ignited", 0) == 0 and renderer.get_debug_state().burns.has(71), "successful reapply owns attached flame without duplicate ignition pop")
			var re: Dictionary = status_phases(run, "reignite")[0]
			check(is_equal_approx(float(re.time) - float(dets[0].time), 0.5), "reignite observes actual half-second delay")
			cast(run)
			advance(run, 0.45)
			check(run.get_snapshot().fire_reignite_pending.is_empty(), "two-second target cooldown still prevents an early second reapply")
	for death in ["main", "fuel", "pending"]:
		var run = fresh(3)
		run._spell_combat.apply_burn(run, run.actors[0], "F11")
		if death == "main": run.actors[0].health = 1.0
		if death == "fuel": run.actors[0].health = 1000.0
		cast(run)
		advance(run, 0.45)
		if death == "pending": run.damage_enemy(run.actors[0], 9999999.0, "fixture")
		check(status_phases(run, "detonation").size() == (0 if death == "main" else 1), "only surviving main-hit fuel can detonate: " + death)
		advance(run, 0.5)
		check(status_phases(run, "reignite").is_empty(), "dead actor cannot show successful reignite: " + death)


func projection_lifecycle_and_capacity(renderer, projector) -> void:
	var run = fresh(3)
	run.room_revision = 30
	cast(run)
	var flight: Dictionary = phases(run, "flight")[0]
	var begin: Vector3 = renderer._point_at(flight, 0.0)
	var end: Vector3 = renderer._point_at(flight, 0.45)
	check(Vector2(begin.x, begin.z).is_equal_approx(flight.from) and Vector2(end.x, end.z).is_equal_approx(flight.pos) and is_equal_approx(begin.y, 0.72) and is_equal_approx(end.y, 0.06), "analytic arc has exact released endpoints")
	advance(run, 0.2)
	var snapshot: Dictionary = run.get_snapshot()
	renderer.sync_snapshot(snapshot, projector)
	var before: Dictionary = renderer.get_debug_state()
	renderer.sync_snapshot(snapshot, projector)
	check(renderer.get_debug_state() == before, "paused same-time sync is stable without frame-sampled tail")
	projector.rotation = 0.31
	projector.scale = 53.0
	projector.offset += Vector2(81, -37)
	renderer.sync_snapshot(snapshot, projector)
	var moved: Dictionary = renderer.get_debug_state()
	check(moved.paths[0].world == before.paths[0].world and moved.vertices != before.vertices and moved.heads[0].screen != before.heads[0].screen, "every world tail point reprojects with the camera")
	check(float(moved.paths[0].length) <= 2.10001 and moved.paths[0].world.size() <= 16, "tail stays short and bounded")
	renderer.sync_snapshot(snapshot, projector, {"reduced_motion": true})
	check(renderer.get_debug_state().heads == moved.heads and renderer.get_debug_state().paths == moved.paths, "reduced motion preserves real flights and their world geometry")
	var absent: Dictionary = snapshot.duplicate(true)
	absent.spell_pending.clear()
	absent.effects.clear()
	renderer.sync_snapshot(absent, projector)
	check(not renderer.visible and renderer.get_debug_state().coverage.get("F07_impact", 0) == 0, "disappearing pending never fabricates an impact")
	absent.erase("fire_bomb_status_facts")
	renderer.sync_snapshot(absent, projector)
	check(not renderer.visible, "incomplete snapshot capability clears new chain")
	var lifecycle = fresh()
	lifecycle.room_revision = 31
	lifecycle._spell_combat.apply_burn(lifecycle, lifecycle.actors[0], "F07")
	renderer.sync_snapshot(lifecycle.get_snapshot(), projector)
	lifecycle.actors[0].pos += Vector2(1, 0)
	lifecycle.actors[0].previous = lifecycle.actors[0].pos
	renderer.sync_snapshot(lifecycle.get_snapshot(), projector)
	check(renderer.get_debug_state().burns[71].pos == lifecycle.actors[0].pos, "actual attached F07 burning follows living actor")
	lifecycle._spell_combat.apply_burn(lifecycle, lifecycle.actors[0], "F03")
	renderer.sync_snapshot(lifecycle.get_snapshot(), projector)
	check(renderer.get_debug_state().burns.is_empty() and renderer.get_debug_state().cooling.is_empty(), "source handoff has no false extinction")
	lifecycle._spell_combat.apply_burn(lifecycle, lifecycle.actors[0], "F07")
	renderer.sync_snapshot(lifecycle.get_snapshot(), projector)
	advance(lifecycle, 4.0)
	renderer.sync_snapshot(lifecycle.get_snapshot(), projector)
	check(renderer.get_debug_state().cooling.size() == 1, "only actual natural expiry emits cooling embers")
	advance(lifecycle, 0.3)
	renderer.sync_snapshot(lifecycle.get_snapshot(), projector)
	check(not renderer.visible, "finite cooling returns to empty")
	absent = snapshot.duplicate(true)
	absent.room_revision += 9
	absent.phase = "pickup"
	renderer.sync_snapshot(absent, projector)
	check(not renderer.visible and renderer.get_debug_state().burns.is_empty() and renderer.get_debug_state().paths.is_empty(), "room/phase clear drops all retained geometry")
	absent = snapshot.duplicate(true)
	absent.time = -1.0
	renderer.sync_snapshot(absent, projector)
	check(not renderer.visible, "time rollback never shows future events")
	var template: Dictionary = snapshot.fire_bomb_facts[0].duplicate(true)
	snapshot.effects.clear()
	snapshot.fire_bomb_facts.clear()
	snapshot.spell_pending.clear()
	for index in 256:
		var fact := template.duplicate(true)
		fact.seq = index + 1
		fact.cast_id = index + 1
		snapshot.fire_bomb_facts.append(fact)
		snapshot.spell_pending.append({"kind": "bomb", "context": {"spell_id": "F07", "cast_id": index + 1}})
	renderer.sync_snapshot(snapshot, projector)
	var capacity: Dictionary = renderer.get_debug_state()
	check(capacity.heads.size() == 128 and capacity.paths.size() == 128 and capacity.overflow == 128, "visual flight capacity is bounded independently of gameplay")
	check(capacity.batch_nodes == 4 and capacity.material_count == 3 and snapshot.fire_bomb_facts.size() == 256, "high counts create no nodes/materials and never remove core facts")
	for index in 600: cast(run, false)
	check(run.get_snapshot().fire_bomb_facts.size() == 512, "core observation journal has fixed retention capacity")
	run._stop_combat()
	check(run.get_snapshot().fire_bomb_facts.is_empty() and run.get_snapshot().fire_bomb_status_facts.is_empty(), "core clear resets both observation journals")


func integration_and_preview() -> void:
	var run = fresh(3)
	run._spell_combat.apply_burn(run, run.actors[0], "F11")
	cast(run)
	advance(run, 0.45)
	var view = View.new()
	root.add_child(view)
	await process_frame
	view.sync(run.get_snapshot())
	var legacy: Dictionary = view.spell_vfx.get_debug_state()
	check(view.get_fire_bomb_debug_state().coverage.get("F07_impact", 0) == 1 and legacy.coverage.get("bomb_impact", 0) == 0 and legacy.coverage.get("fire_detonation", 0) == 0, "native view draws F07 main/fuel once")
	check(view.fire_bomb_vfx.z_index < view._overlay.z_index and view.fire_bomb_vfx.z_index < view.magic_missile_vfx.z_index, "hostile warnings/missiles stay above friendly explosion")
	var mixed: Dictionary = run.get_snapshot()
	var unrelated: Dictionary = mixed.effects.filter(func(e): return e.kind == "fire_detonation")[0].duplicate(true)
	unrelated.cast_id = -999
	mixed.effects.append(unrelated)
	view.sync(mixed)
	check(view.spell_vfx.get_debug_state().coverage.get("fire_detonation", 0) == 1, "unrelated fuel detonation retains legacy presentation")
	mixed.erase("fire_bomb_facts")
	view.sync(mixed)
	check(not view.fire_bomb_vfx.visible and view.spell_vfx.get_debug_state().coverage.get("bomb_impact", 0) == 1 and view.spell_vfx.get_debug_state().coverage.get("fire_detonation", 0) == 2, "old snapshot falls back to complete original rendering")
	view.queue_free()
	await process_frame
	var scene: PackedScene = load("res://tests/previews/fire_bomb_preview.tscn")
	var preview = scene.instantiate()
	root.add_child(preview)
	preview.set_process(false)
	await process_frame
	preview.set_process(false)
	for mode in 9:
		preview._mode = mode
		preview._reset()
		check(preview._run.spells[0].id == "F07" and preview._run.spells[0].level == mini(mode + 1, 3), "preview mode uses real F07 level %d" % mode)
		for frame in 260: preview._advance(STEP)
		var facts: Array = preview._run.get_snapshot().fire_bomb_facts
		check(facts.any(func(f): return f.phase == "impact"), "preview mode reaches real main %d" % mode)
		if mode == 3: check(not preview._run.get_snapshot().spell_burns.filter(func(b): return b.source == "F07").is_empty(), "fuel preview reaches actual delayed F07 reapply")
		if mode == 4: check(facts.filter(func(f): return f.phase == "impact")[0].pos != preview._run.actors[0].pos, "moving preview demonstrates original lock point")
		if mode == 5: check(preview._run.actors[0].health <= 0.0 and not preview._run.get_snapshot().fire_bomb_status_facts.any(func(f): return f.actor_id == 901), "lethal preview does not invent corpse fuel feedback")
		if mode == 6: check(preview._run.get_snapshot().fire_bomb_status_facts.any(func(f): return f.phase == "detonation") and not preview._run.get_snapshot().fire_bomb_status_facts.any(func(f): return f.phase == "reignite"), "extra preview has real fuel discharge without natural reapply")
		if mode == 7: check(facts.filter(func(f): return f.phase == "impact").size() == 3, "overlap preview launches three distinct real casts")
	preview.queue_free()
	await process_frame


func execute() -> void:
	core_parity()
	var renderer = Bomb.new()
	root.add_child(renderer)
	await process_frame
	check(renderer.is_available() and renderer.get_child_count() == 4, "four fixed draw nodes initialize")
	for shader: Shader in [Bomb.BODY_SHADER, Bomb.SURFACE_SHADER, Bomb.TRAIL_SHADER]:
		check(not shader.get_shader_uniform_list().is_empty(), "local shader-language parse: " + shader.resource_path)
	var projector := Projector.new()
	stages_and_fuel(renderer, projector)
	projection_lifecycle_and_capacity(renderer, projector)
	await integration_and_preview()
	renderer.queue_free()
	await process_frame
	var report := {"checks": checks, "failures": failures.size(), "details": failures, "frozen_baseline_cases": baseline_cases,
		"scope": "Headless real-Route frozen combat+burn parity, unchanged snapshots/hooks/events/RNG, original chant lock/flight/inner-outer damage/aftershock and actual fuel/reapply/death/cooldown, analytic world arc/tail reprojection/pause/reduced motion, source burn lifecycle, bounded facts/draw nodes, native-view exact legacy handoff and all nine controlled preview fixture paths. No interactive preview, pixels, GPU composition, natural route, performance, export or user visual acceptance."}
	if not Report.write_report(report, OUTPUT): failures.append("cannot write report")
	print("FIRE BOMB CHAIN checks=%d failures=%d baseline_cases=%d" % [checks, failures.size(), baseline_cases])
	quit(0 if failures.is_empty() else 1)
