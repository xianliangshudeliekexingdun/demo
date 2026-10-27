extends SceneTree
## Real-Route equivalence is counted by scenario and whole-snapshot checkpoint.
## Headless geometry/logic checks do not establish pixel or performance quality.
const Wave = preload("res://scripts/presentation/route_fire_wave_vfx.gd")
const View = preload("res://scripts/presentation/first_room_view.gd")
const Rules = preload("res://tests/formal_fire_tests.gd")
const Report = preload("res://tests/qa_report.gd")
const OUTPUT := "res://build/qa/fire-wave-vfx-20261027/targeted/results.json"
const STEP := 1.0 / 120.0
var checks := 0
var failures: Array = []
var baseline_cases := 0
var snapshot_comparisons := 0
var baseline_assertions := 0

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
		push_error("F09 chain: " + label)


func add_spell(run, id: String, level: int) -> void:
	var spell: Dictionary = run._new_spell(id)
	spell.level = level
	run._refresh_spell(spell)
	spell.remaining = 9999.0
	run.spells.append(spell)


func fresh(level: int = 1, seed: int = 20261027, old_combat: Script = null, old_growth: Script = null):
	var run = Rules.Fixture.new()
	check(run.configure({}, seed).ok and run.choose_initial("F01"), "real Route fixture configures")
	if old_combat != null:
		run._spell_combat = old_combat.new()
		run._spell_combat.growth = old_growth.new()
		check(run._spell_combat.configure(run).ok, "frozen combat/growth configure")
	run._spawn_done = true
	run.spawn_warnings.clear()
	run.blocks.clear()
	run.player.pos = Vector2.ZERO
	run.player.previous = Vector2.ZERO
	run.player.crit_rate = 0.0
	run.spells.clear()
	add_spell(run, "F09", level)
	run.actors.clear()
	for index in 3:
		var pos := Vector2(0, 1) if index == 0 else Vector2(1.6 if index == 1 else 4.8, 0)
		var actor: Dictionary = run._enemy_combat.make_actor(run, "M01", pos, 71 + index)
		actor.health = 100000.0
		actor.max_health = actor.health
		run.actors.append(actor)
	return run


func cast(run, natural: bool = true, scale: float = 1.0, slot: int = 0) -> void:
	var spell: Dictionary = run.spells[slot]
	spell["locked_pos"] = run.actors[0].pos
	run._spell_combat._cast(run, spell, run.get_spell_stats(spell), run.actors[0], natural, scale)
	spell.remaining = 9999.0


func advance(run, seconds: float, move: Vector2 = Vector2.ZERO) -> void:
	for frame in roundi(seconds / STEP): run.step(STEP, move)


func gameplay(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			if key not in ["fire_wave_facts", "fire_wave_speed"]: result[key] = gameplay(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(gameplay(item))
		return result
	return value


func core_parity() -> void:
	var paths: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline-combat="): paths.combat = arg.trim_prefix("--baseline-combat=")
		if arg.begins_with("--baseline-growth="): paths.growth = arg.trim_prefix("--baseline-growth=")
	if not paths.has_all(["combat", "growth"]): return
	var old_combat: Script = load(paths.combat)
	var old_growth: Script = load(paths.growth)
	check(old_combat != null and old_growth != null, "both frozen sources load")
	if old_combat == null or old_growth == null: return
	for level in range(1, 4):
		for mode in 12:
			var case_id := (level - 1) * 12 + mode
			var actual = fresh(level, 20261027 + case_id)
			var reference = fresh(level, 20261027 + case_id, old_combat, old_growth)
			for run in [actual, reference]:
				if mode == 3: run.blocks.append({"center": Vector2(2.8, 0), "size": Vector2(0.4, 3.0)})
				if mode in [4, 5, 9]:
					for actor in run.actors: actor.push_resistance = 1.0 if mode == 4 else 0.6 if mode == 5 else 0.95
				if mode == 7: run.actors[0].health = 1.0
				if mode == 8:
					for id in ["F01", "F03", "F08", "F07"]: add_spell(run, id, 3)
					for slot in range(1, 5): cast(run, true, 1.0, slot)
				if mode == 6:
					run.spells[0].remaining = 0.0
					run.step(STEP)
					run.player.pos = Vector2(0.3, 0)
					run.player.previous = run.player.pos
				else: cast(run, mode != 1, 0.0 if mode == 2 else 0.7 if mode == 1 else 1.0)
				if mode == 9:
					cast(run, false, 0.7)
					cast(run, false, 0.7)
				if mode == 10: run.spells[0].level = 1
			for frame in 300:
				for run in [actual, reference]:
					if mode == 11 and frame == 10: run.set_paused(true)
					if mode == 11 and frame == 40: run.set_paused(false)
					run.step(STEP, Vector2.RIGHT if mode == 10 and frame > 20 else Vector2.ZERO)
				if frame in [0, 10, 23, 53, 119, 181, 240, 299]:
					check(gameplay(actual.get_snapshot()) == gameplay(reference.get_snapshot()), "whole frozen snapshot level %d mode %d frame %d" % [level, mode, frame])
					check(actual._rng.state == reference._rng.state, "unchanged RNG level %d mode %d frame %d" % [level, mode, frame])
					snapshot_comparisons += 1
			for key in ["damage_log", "context_log", "cast_log", "extra_log", "emitted"]:
				check(actual.get(key) == reference.get(key), "unchanged real hook/event level %d mode %d %s" % [level, mode, key])
			baseline_cases += 1


func release_and_statuses(renderer, projector) -> void:
	for level in range(1, 4):
		var run = fresh(level)
		run.room_revision = 10 + level
		run.spells[0].remaining = 0.0
		run.step(STEP)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(renderer.get_debug_state().coverage.get("F09_cast", 0) == 1 and renderer.get_debug_state().waves.is_empty(), "chant precedes all damage/waves")
		run.player.pos = Vector2(0.2, 0)
		run.player.previous = run.player.pos
		advance(run, 0.2)
		run.spells[0].remaining = 9999.0
		var snapshot: Dictionary = run.get_snapshot()
		check(snapshot.fire_wave_facts.size() == 1, "one completed actual wave")
		if snapshot.fire_wave_facts.is_empty(): continue
		var fact: Dictionary = snapshot.fire_wave_facts[0]
		check(fact.pos == run.player.pos and fact.spell_level == level and is_equal_approx(float(fact.radius), [2.0, 2.8, 3.1][level - 1]), "actual release origin and level radius")
		check(fact.hits.size() == 2 and fact.hits.all(func(h): return h.damage > 0.0 and h.from != h.to), "both in-range targets hit and pushed on release frame")
		check(run.actors[2].health == run.actors[2].max_health and not run._spell_combat.has_burn(run, run.actors[2]), "outside target is neither hit nor ignited")
		renderer.sync_snapshot(snapshot, projector)
		var debug: Dictionary = renderer.get_debug_state()
		check(debug.waves.size() == 1 and debug.coverage.get("F09_hit", 0) == 2 and debug.strips.size() == 2, "whole wave and actual local hits/push traces appear immediately")
		check(debug.coverage.get("F09_speed", 0) == (0 if level == 1 else 1) and debug.coverage.get("F09_slow", 0) == (2 if level == 3 else 0), "only current actual level statuses appear")
		check(debug.burns.size() == 2 and debug.burns[71].pos == run.actors[0].pos, "source-owned burning follows post-push target")
		for hit: Dictionary in fact.hits:
			check(debug.strips.any(func(s): return s.actor_id == hit.actor_id and s.from == hit.from and s.to == hit.to), "push trace uses both real endpoints")
		if fact.hits.is_empty(): continue
		snapshot.fire_wave_facts[0].hits[0].to = Vector2(99, 99)
		check(run.get_snapshot().fire_wave_facts[0].hits[0].to != Vector2(99, 99), "nested hit facts are deep copied")
		var original: Vector2 = fact.pos
		advance(run, 0.05, Vector2.RIGHT)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(renderer.get_debug_state().waves[0].pos == original and run.player.pos != original, "decorative wave stays at release position after player moves")
		if level > 1:
			var speed: Array = renderer.get_debug_state().footprints.filter(func(f): return f.kind == "wave_speed")
			check(speed.size() == 1 and speed[0].pos == run.player.pos and speed[0].moving, "active speed feedback follows real movement")
		advance(run, 2.0)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(renderer.get_debug_state().waves.is_empty() and renderer.get_debug_state().coverage.get("F09_speed", 0) == 0 and renderer.get_debug_state().coverage.get("F09_slow", 0) == 0, "wave and source status cues end at their own lifetimes")
	for natural in [true, false]:
		for scale in [0.0, 0.7]:
			var run = fresh(3)
			cast(run, natural, scale)
			renderer.sync_snapshot(run.get_snapshot(), projector)
			var debug: Dictionary = renderer.get_debug_state()
			check(debug.waves.size() == 1 and debug.coverage.get("F09_hit", 0) == (2 if scale > 0.0 else 0), "zero-effective-damage release still has only its actual wave")
			check(debug.coverage.get("F09_speed", 0) == (1 if natural and scale > 0.0 else 0), "only natural effective hit grants speed, never extra or zero-damage release")
			if scale == 0.0:
				check(debug.strips.size() == 2 and debug.coverage.get("F09_slow", 0) == 2 and debug.burns.is_empty(), "zero damage preserves original push/slow feedback without invented ignition")
	var zero = fresh(3)
	zero.actors[0].pos = Vector2.ZERO
	zero.actors[0].previous = Vector2.ZERO
	zero.actors[1].push_resistance = 1.0
	zero.actors[0].health = 1.0
	cast(zero)
	var hits: Array = zero.get_snapshot().fire_wave_facts[0].hits
	check(hits[0].to.y > 0.0 and not hits[0].alive_after, "original zero-direction fallback and lethal-hit result are preserved")
	renderer.sync_snapshot(zero.get_snapshot(), projector)
	check(not renderer.get_debug_state().strips.any(func(s): return s.actor_id == 72) and not renderer.get_debug_state().burns.has(71), "fully resistant target has no fictitious displacement; dead target has no attached burn")
	var wall = fresh(3)
	wall.blocks.append({"center": Vector2(2.8, 0), "size": Vector2(0.4, 3.0)})
	cast(wall)
	renderer.sync_snapshot(wall.get_snapshot(), projector)
	var pushed: Dictionary = wall.get_snapshot().fire_wave_facts[0].hits.filter(func(h): return h.actor_id == 72)[0]
	check(pushed.from.distance_to(pushed.to) < 2.5 and renderer.get_debug_state().strips.any(func(s): return s.actor_id == 72 and s.to == pushed.to), "wall-clipped actual displacement limits the trace")
	var canceled = fresh()
	canceled.spells[0].remaining = 0.0
	canceled.step(STEP)
	for actor in canceled.actors: actor.pos = Vector2(7, 5)
	advance(canceled, 0.2)
	check(canceled.get_snapshot().fire_wave_facts.is_empty() and canceled.casts == 0, "no legal finish target cancels rather than invents a wave")


func projection_lifecycle_and_capacity(renderer, projector) -> void:
	var run = fresh(3)
	run.room_revision = 30
	cast(run)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	var before: Dictionary = renderer.get_debug_state()
	run.set_paused(true)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	check(renderer.get_debug_state() == before and not run.get_snapshot().fire_wave_speed.is_empty(), "pause preserves geometry and granted speed state")
	projector.rotation = 0.38
	projector.scale = 57.0
	projector.offset += Vector2(83, -31)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	var moved: Dictionary = renderer.get_debug_state()
	check(moved.strips == before.strips and moved.vertices != before.vertices and moved.waves == before.waves, "world displacement and full-area geometry reproject with camera")
	renderer.sync_snapshot(run.get_snapshot(), projector, {"reduced_motion": true})
	check(renderer.get_debug_state().waves == moved.waves and renderer.get_debug_state().strips == moved.strips, "reduced motion retains true area, identities and displacement")
	run.set_paused(false)
	var missing: Dictionary = run.get_snapshot()
	missing.fire_wave_facts.clear()
	missing.fire_wave_speed.clear()
	missing.spell_burns.clear()
	missing.effects.clear()
	for actor in missing.actors: actor.spell_slows = {}
	missing.room_revision += 1
	renderer.sync_snapshot(missing, projector)
	check(not renderer.visible, "no factual release/status never infers a wave from other effects")
	missing = run.get_snapshot()
	missing.erase("fire_wave_speed")
	renderer.sync_snapshot(missing, projector)
	check(not renderer.visible, "incomplete snapshot capability leaves new renderer empty")
	var lifecycle = fresh()
	lifecycle.room_revision = 31
	lifecycle._spell_combat.apply_burn(lifecycle, lifecycle.actors[0], "F09")
	renderer.sync_snapshot(lifecycle.get_snapshot(), projector)
	lifecycle._spell_combat.apply_burn(lifecycle, lifecycle.actors[0], "F03")
	renderer.sync_snapshot(lifecycle.get_snapshot(), projector)
	check(renderer.get_debug_state().burns.is_empty() and renderer.get_debug_state().cooling.is_empty(), "source handoff has no false extinction")
	lifecycle._spell_combat.apply_burn(lifecycle, lifecycle.actors[0], "F09")
	renderer.sync_snapshot(lifecycle.get_snapshot(), projector)
	lifecycle._spell_combat.detonate_burn(lifecycle, lifecycle.actors[0], 1.0)
	renderer.sync_snapshot(lifecycle.get_snapshot(), projector)
	check(renderer.get_debug_state().burns.is_empty() and renderer.get_debug_state().cooling.is_empty(), "consumed fuel has no natural cooling")
	lifecycle._spell_combat.apply_burn(lifecycle, lifecycle.actors[0], "F09")
	renderer.sync_snapshot(lifecycle.get_snapshot(), projector)
	advance(lifecycle, 4.0)
	renderer.sync_snapshot(lifecycle.get_snapshot(), projector)
	check(renderer.get_debug_state().cooling.size() == 1, "actual natural expiry gets finite cooling")
	advance(lifecycle, 0.3)
	renderer.sync_snapshot(lifecycle.get_snapshot(), projector)
	check(not renderer.visible, "all transient drawing returns to empty")
	var sample: Dictionary = run.get_snapshot()
	sample.effects.clear()
	sample.spell_burns.clear()
	sample.fire_wave_speed.clear()
	for actor in sample.actors: actor.spell_slows = {}
	var template: Dictionary = sample.fire_wave_facts[0].duplicate(true)
	template.hits.clear()
	sample.fire_wave_facts.clear()
	for index in 256:
		var fact := template.duplicate(true)
		fact.seq = index + 1
		fact.cast_id = index + 1
		sample.fire_wave_facts.append(fact)
	renderer.sync_snapshot(sample, projector)
	var debug: Dictionary = renderer.get_debug_state()
	check(debug.waves.size() == 128 and debug.overflow == 128 and debug.batch_nodes == 4 and debug.material_count == 3, "wave decoration has fixed capacity/node/material bounds")
	check(sample.fire_wave_facts.size() == 256, "capacity never mutates factual attacks")
	for index in 300: cast(run, false)
	check(run.get_snapshot().fire_wave_facts.size() == 256, "read-only core journal is bounded")
	run._stop_combat()
	check(run.get_snapshot().fire_wave_facts.is_empty() and run.get_snapshot().fire_wave_speed.is_empty(), "core clear resets observations and existing granted status")
	sample.phase = "pickup"
	renderer.sync_snapshot(sample, projector)
	check(not renderer.visible and renderer.get_debug_state().strips.is_empty(), "phase/room clear removes retained visuals")
	sample.phase = "combat"
	sample.time = -1.0
	renderer.sync_snapshot(sample, projector)
	check(not renderer.visible, "clock rollback does not show future attacks")


func integration_and_preview() -> void:
	var run = fresh(3)
	cast(run)
	var view = View.new()
	root.add_child(view)
	await process_frame
	view.sync(run.get_snapshot())
	check(view.get_fire_wave_debug_state().waves.size() == 1 and view.spell_vfx.get_debug_state().coverage.get("wave", 0) == 0, "native view routes F09 once")
	check(view.fire_wave_vfx.z_index < view._overlay.z_index and view.fire_wave_vfx.z_index < view.magic_missile_vfx.z_index, "hostile warnings/missiles stay above friendly fire")
	var old: Dictionary = run.get_snapshot()
	old.erase("fire_wave_facts")
	view.sync(old)
	check(not view.fire_wave_vfx.visible and view.spell_vfx.get_debug_state().coverage.get("wave", 0) == 1, "old snapshots retain original wave drawing")
	view.queue_free()
	await process_frame
	var scene: PackedScene = load("res://tests/previews/fire_wave_preview.tscn")
	var preview = scene.instantiate()
	root.add_child(preview)
	preview.set_process(false)
	await process_frame
	preview.set_process(false)
	for mode in 9:
		preview._mode = mode
		preview._reset()
		check(preview._run.spells[0].id == "F09" and preview._run.spells[0].level == mini(mode + 1, 3), "preview uses actual spell level mode %d" % mode)
		for frame in 132: preview._advance(STEP)
		var snapshot: Dictionary = preview._run.get_snapshot()
		check(snapshot.fire_wave_facts.size() == (0 if mode == 7 else 3 if mode == 8 else 1), "preview reaches actual release/cancel count mode %d" % mode)
		if mode == 5: check(snapshot.fire_wave_speed.is_empty(), "extra-only preview never gains natural speed")
		if mode == 6: check(preview._run.player.pos != snapshot.fire_wave_facts[0].pos and not snapshot.fire_wave_speed.is_empty(), "moving preview follows real movement after fixed-origin release")
	preview.queue_free()
	await process_frame


func execute() -> void:
	core_parity()
	baseline_assertions = checks
	var renderer = Wave.new()
	root.add_child(renderer)
	await process_frame
	check(renderer.is_available() and renderer.get_child_count() == 4, "four fixed draw nodes initialize")
	for shader: Shader in [Wave.SURFACE_SHADER, Wave.BODY_SHADER, Wave.TRAIL_SHADER]:
		check(not shader.get_shader_uniform_list().is_empty(), "local shader-language parse: " + shader.resource_path)
	var projector := Projector.new()
	release_and_statuses(renderer, projector)
	projection_lifecycle_and_capacity(renderer, projector)
	await integration_and_preview()
	renderer.queue_free()
	await process_frame
	var result := {"checks": checks, "failures": failures.size(), "details": failures,
		"frozen_baseline_cases": baseline_cases, "whole_snapshot_comparisons": snapshot_comparisons,
		"baseline_assertions": baseline_assertions, "non_baseline_assertions": checks - baseline_assertions,
		"scenario_matrix": "Three actual released levels by 12 independent setups: natural, extra, zero-effective hit, wall, full resistance, partial resistance, chant movement, lethal hit, mixed four approved spells, overlap, released-level change/movement, pause.",
		"scope": "Headless real-Route parity of original complete snapshots/hooks/events/RNG, actual instant wave/hit/push results, true natural speed/source slow/burn, analytic projected geometry and pause/reduced/source lifecycle, finite structure, native fallback and nine controlled preview fixture paths. No interactive preview, pixels/GPU composition, performance, natural route, export or user visual approval."}
	if not Report.write_report(result, OUTPUT): failures.append("cannot write report")
	print("FIRE WAVE CHAIN scenarios=%d snapshot_comparisons=%d assertions=%d failures=%d" % [baseline_cases, snapshot_comparisons, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
