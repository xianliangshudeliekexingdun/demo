extends SceneTree
## Real Route equivalence and read-only F08 stages. Headless, never visual acceptance.
const Beam = preload("res://scripts/presentation/route_fire_beam_vfx.gd")
const View = preload("res://scripts/presentation/first_room_view.gd")
const Rules = preload("res://tests/formal_fire_tests.gd")
const Report = preload("res://tests/qa_report.gd")
const OUTPUT := "res://build/qa/fire-beam-vfx-20261027/targeted/results.json"
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
		push_error("F08 chain: " + label)


func fresh(level: int = 1, seed: int = 20261027, baseline: Script = null, old_growth: Script = null):
	var run = Rules.Fixture.new()
	check(run.configure({}, seed).ok and run.choose_initial("F08"), "real F08 fixture configures")
	if baseline != null:
		run._spell_combat = baseline.new()
		if old_growth != null: run._spell_combat.growth = old_growth.new()
		check(run._spell_combat.configure(run).ok, "frozen combat/growth configure")
	run._spawn_done = true
	run.spawn_warnings.clear()
	run.blocks.clear()
	run.player.pos = Vector2.ZERO
	run.player.previous = Vector2.ZERO
	run.player.crit_rate = 0.0
	run.spells.clear()
	add_spell(run, "F08", level)
	run.actors.clear()
	for index in 4:
		var pos := Vector2(0, 2.0 + float(index) * 2.0) if index < 3 else Vector2(2.6, 3)
		var actor: Dictionary = run._enemy_combat.make_actor(run, "M01", pos, 71 + index)
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
	run._spell_combat._cast(run, spell, run.get_spell_stats(spell), run.actors[0], natural, 1.0 if natural else 0.7)
	spell.remaining = 9999.0


func advance(run, seconds: float) -> void:
	for frame in roundi(seconds / STEP): run.step(STEP)


func execute() -> void:
	core_parity()
	var renderer = Beam.new()
	root.add_child(renderer)
	await process_frame
	check(renderer.is_available() and renderer.get_child_count() == 3, "three fixed draw nodes")
	for shader: Shader in [Beam.LINE_SHADER, Beam.SURFACE_SHADER, Beam.BODY_SHADER]:
		check(not shader.get_shader_uniform_list().is_empty(), "local shader-language parsing: " + shader.resource_path)
	var projector := Projector.new()
	main_and_pulse(renderer, projector)
	echo_identity_and_reselection(renderer, projector)
	projection_pause_burns_and_cleanup(renderer, projector)
	capacity(renderer, projector)
	await integration_and_preview()
	renderer.queue_free()
	await process_frame
	var report := {"checks": checks, "failures": failures.size(), "details": failures, "frozen_baseline_cases": baseline_cases,
		"scope": "Headless actual-Route equivalence, instantaneous lines and real hit targets, fixed pulse geometry/qualification, true native echo origin/parent/source and its own pulse, failed extra/reselection, released levels, bounded facts, whole-line reprojection, pause/reduced motion/burn lifecycle, capacity and view/controlled preview checks. No pixels, GPU composition, performance, interactive preview, natural route or user visual acceptance."}
	if not Report.write_report(report, OUTPUT): failures.append("cannot write report")
	print("FIRE BEAM CHAIN checks=%d failures=%d baseline_cases=%d" % [checks, failures.size(), baseline_cases])
	quit(0 if failures.is_empty() else 1)


func gameplay(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			if key != "fire_beam_facts": result[key] = gameplay(value[key])
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
		if argument.begins_with("--baseline-growth="): paths.growth = argument.trim_prefix("--baseline-growth=")
	if not paths.has_all(["combat", "growth"]): return # Change-specific frozen sources remain QA artifacts.
	var baseline: Script = load(paths.combat)
	var old_growth: Script = load(paths.growth)
	check(baseline != null and old_growth != null, "both frozen sources load")
	if baseline == null or old_growth == null: return
	for scenario in 30:
		var level := 1 + scenario % 3
		var actual = fresh(level, 20261027 + scenario, null, null)
		var reference = fresh(level, 20261027 + scenario, baseline, old_growth)
		var mode := scenario % 10
		for run in [actual, reference]:
			if mode == 1: run.blocks.append({"center": Vector2(0, 3.5), "size": Vector2(3.0, 0.4)})
			if mode in [2, 4, 9]:
				cast(run)
				advance(run, 0.5)
				cast(run)
				advance(run, 0.5)
			if mode == 4: run.actors[0].health = 1.0
			if mode == 9:
				run.actors.resize(1)
				run.actors[0].health = 1.0
			if mode == 8:
				add_spell(run, "F01", 3)
				add_spell(run, "F03", 3)
				cast(run, 1)
				cast(run, 2)
			if mode == 5:
				run.actors[0].pos = Vector2.ZERO
				run.actors[0].previous = Vector2.ZERO
			cast(run, 0, mode != 3)
			if mode == 7: run.spells[0].level = 1
			if mode == 6:
				run.player.pos = Vector2(3, -1)
				run.player.previous = run.player.pos
				run.actors[1].pos.x = 3.0
				run.actors[1].previous = run.actors[1].pos
		for frame in 180:
			if frame == 10 and mode == 6:
				actual.set_paused(true)
				reference.set_paused(true)
			elif frame == 40 and mode == 6:
				actual.set_paused(false)
				reference.set_paused(false)
			actual.step(STEP)
			reference.step(STEP)
			if frame in [0, 11, 23, 35, 70, 179]:
				var left: Dictionary = actual.get_snapshot()
				var right: Dictionary = reference.get_snapshot()
				for key in ["player", "actors", "spells", "effects", "spell_pending", "spell_zones", "spell_burns", "artifact_patches", "projectiles", "gems", "time", "combat_time", "phase"]:
					check(gameplay(left.get(key)) == gameplay(right.get(key)), "frozen actual Route parity case %d frame %d %s" % [scenario, frame, key])
				check(actual._rng.state == reference._rng.state, "gameplay RNG parity case %d frame %d" % [scenario, frame])
		for key in ["damage_log", "context_log", "cast_log", "extra_log", "emitted"]:
			check(actual.get(key) == reference.get(key), "unchanged real hooks/events %d %s" % [scenario, key])
		baseline_cases += 1


func main_and_pulse(renderer, projector) -> void:
	for level in range(1, 4):
		var run = fresh(level)
		run.room_revision = 10 + level
		run.spells[0].remaining = 0.0
		run.step(STEP)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(int(renderer.get_debug_state().coverage.get("F08_cast", 0)) == 1, "real short chant appears")
		advance(run, 0.2)
		run.spells[0].remaining = 9999.0
		var snapshot: Dictionary = run.get_snapshot()
		var facts: Array = snapshot.fire_beam_facts
		check(facts.size() == 1 and facts[0].phase == "main" and facts[0].source == "natural", "actual main exists on the release frame level %d" % level)
		if facts.is_empty(): continue
		var fact: Dictionary = facts[0]
		check(fact.hits.size() == 3 and fact.hits.all(func(h): return h.damage > 0.0), "only the three actually struck on-line enemies have feedback")
		check(is_equal_approx(float(fact.half_width) * 2.0, [0.5, 0.6, 0.7][level - 1]), "released real full width")
		renderer.sync_snapshot(snapshot, projector)
		var debug: Dictionary = renderer.get_debug_state()
		check(debug.groups.size() == 1 and debug.vertices.size() == 4 and debug.uvs[0].x == 0.0 and debug.uvs[2].x == 1.0, "whole ray appears immediately without a moving attack head")
		check(is_equal_approx(Vector2(debug.groups[0].world_corners[0]).distance_to(debug.groups[0].world_corners[1]), float(fact.half_width) * 2.0), "render corners preserve the full actual width")
		facts[0].hits[0].pos = Vector2(99, 99)
		check(run.get_snapshot().fire_beam_facts[0].hits[0].pos != facts[0].hits[0].pos, "nested hit facts are deep copied")
		var burn_expires := float(run._spell_combat.fire_status.burns[71].expires)
		var origin: Vector2 = fact.from
		var end: Vector2 = fact.to
		run.spells[0].level = 1
		run.player.pos = Vector2(3, -1)
		run.player.previous = run.player.pos
		run.actors[1].pos.x = 3.0
		run.actors[1].previous = run.actors[1].pos
		run.actors[3].pos = Vector2(0, 3)
		run.actors[3].previous = run.actors[3].pos
		advance(run, 0.1)
		check(run.get_snapshot().fire_beam_facts.size() == 1, "no premature pulse")
		advance(run, 0.1)
		var pulses: Array = run.get_snapshot().fire_beam_facts.filter(func(f): return f.phase == "pulse")
		check(pulses.size() == (1 if level == 3 else 0), "only released level three has its original pulse")
		if not pulses.is_empty():
			var pulse: Dictionary = pulses[0]
			check(is_equal_approx(float(pulse.time) - float(fact.time), 0.2) and pulse.from == origin and pulse.to == end and pulse.half_width == fact.half_width and pulse.spell_level == 3, "pulse keeps original time/geometry/level after movement and downgrade")
			var ids: Array = pulse.hits.map(func(h): return int(h.actor_id))
			check(ids.has(74) and not ids.has(72), "pulse rechecks actual targets in the original line")
			check(not pulse.ignite and not run._spell_combat.fire_status.burns.has(74) and is_equal_approx(float(run._spell_combat.fire_status.burns[71].expires), burn_expires), "pulse neither ignites a new entrant nor refreshes old burning")
			renderer.sync_snapshot(run.get_snapshot(), projector)
			var hit_ids: Array = renderer.get_debug_state().footprints.filter(func(f): return f.kind == "beam_hit" and f.phase == "pulse").map(func(f): return int(f.actor_id))
			check(hit_ids.has(74) and not hit_ids.has(72), "pulse hit flashes follow real hit results")
	var wall = fresh(3)
	wall.blocks.append({"center": Vector2(0, 3.5), "size": Vector2(3.0, 0.4)})
	cast(wall)
	advance(wall, 0.21)
	for fact: Dictionary in wall.get_snapshot().fire_beam_facts:
		check(Vector2(fact.to).y < 3.5 and not fact.hits.any(func(h): return h.actor_id == 72 or h.actor_id == 73), "main and pulse preserve solid-cover clipping")
	var zero = fresh(3)
	zero.room_revision = 18
	zero.actors[0].pos = Vector2.ZERO
	zero.actors[0].previous = Vector2.ZERO
	cast(zero)
	renderer.sync_snapshot(zero.get_snapshot(), projector)
	check(renderer.get_debug_state().vertices.is_empty() and zero.get_snapshot().fire_beam_facts[0].hits.size() == 1, "zero-length actual hit has local feedback without invalid line geometry")


func prepare_third(run) -> void:
	cast(run)
	advance(run, 0.5)
	cast(run)
	advance(run, 0.5)


func echo_identity_and_reselection(renderer, projector) -> void:
	var run = fresh(3)
	run.room_revision = 20
	prepare_third(run)
	cast(run)
	var recent: Array = run.get_snapshot().fire_beam_facts.filter(func(f): return absf(float(f.time) - float(run.time)) < 0.000001)
	check(recent.size() == 2 and run.casts == 3 and run.extra_log.size() == 1, "third natural release produces the actual immediate native echo")
	if recent.size() != 2: return
	check(recent[0].source == "natural" and recent[1].source == "echo" and recent[1].parent_cast_id == recent[0].cast_id and recent[0].time == recent[1].time, "native echo identity and parent come from its real branch")
	renderer.sync_snapshot(run.get_snapshot(), projector)
	var debug: Dictionary = renderer.get_debug_state()
	check(debug.beams.size() == 2 and debug.groups.size() == 1 and debug.groups[0].mode == 6 and debug.groups[0].seqs.size() == 2, "same-line same-time pair uses bounded two-stream composition without delay or widening")
	advance(run, 0.2)
	var pulse_facts: Array = run.get_snapshot().fire_beam_facts.filter(func(f): return absf(float(f.time) - float(run.time)) < 0.000001 and f.phase == "pulse")
	check(pulse_facts.size() == 2 and pulse_facts[0].time == pulse_facts[1].time and not pulse_facts[0].ignite and not pulse_facts[1].ignite, "native echo has its own simultaneous scheduled pulse")
	renderer.sync_snapshot(run.get_snapshot(), projector)
	check(renderer.get_debug_state().groups.any(func(g): return g.mode == 7), "paired pulse has its own two-stream contraction")
	advance(run, 0.3)
	var casts_before := int(run.casts)
	check(run.cast_extra_spell("F08", run.actors[0], 0.7), "generic additional cast still works at echo-like scale")
	var last: Dictionary = run.get_snapshot().fire_beam_facts[-1]
	check(last.source == "extra" and last.parent_cast_id == -1 and run.casts == casts_before and run.extra_log.size() == 2, "damage scale cannot falsely identify an extra as native echo or count a natural cast")
	var changed = fresh(3)
	changed.room_revision = 21
	prepare_third(changed)
	changed.actors[0].health = 1.0
	cast(changed)
	renderer.sync_snapshot(changed.get_snapshot(), projector)
	debug = renderer.get_debug_state()
	check(debug.beams.size() == 2 and debug.groups.size() == 2 and debug.beams[0].to != debug.beams[1].to, "a killed original target permits the existing real echo retarget without fake same-line grouping")
	var none = fresh(3)
	none.room_revision = 22
	none.actors.resize(1)
	prepare_third(none)
	none.actors[0].health = 1.0
	cast(none)
	renderer.sync_snapshot(none.get_snapshot(), projector)
	check(renderer.get_debug_state().beams.size() == 1 and not renderer.get_debug_state().beams.any(func(f): return f.source == "echo"), "failed legal extra cannot invent an echo line")
	check(none._spell_combat._next_beam_echo_parent == -1, "failed extra clears one-use visual source marker")
	advance(run, 1.5)
	check(run.get_snapshot().fire_beam_facts.is_empty(), "beam journal has finite retention")
	var rng: int = run._rng.state
	var context := {"cast_id": 999, "natural": true, "spell_level": 3, "ignite": false}
	for index in 280: run._spell_combat._note_beam_fact(run, Vector2.ZERO, Vector2(0, 3), 0.35, context, "pulse", [])
	check(run.get_snapshot().fire_beam_facts.size() == 256 and run._rng.state == rng, "beam journal is bounded and RNG free")
	run._spell_combat.stop_room()
	check(run.get_snapshot().fire_beam_facts.is_empty() and run._spell_combat._beam_visual_sources.is_empty(), "room stop clears complete source bookkeeping")


func projection_pause_burns_and_cleanup(renderer, projector) -> void:
	var run = fresh(3)
	run.room_revision = 30
	cast(run)
	var snapshot: Dictionary = run.get_snapshot()
	var original: Dictionary = snapshot.duplicate(true)
	var rng: int = run._rng.state
	renderer.sync_snapshot(snapshot, projector)
	var before: Dictionary = renderer.get_debug_state()
	for frame_rate in [30, 60, 120]:
		for frame in 4: renderer.sync_snapshot(snapshot, projector)
		check(renderer.get_debug_state().groups == before.groups and renderer.get_debug_state().vertices == before.vertices, "same actual instant is independent of rendering cadence %d" % frame_rate)
	run.set_paused(true)
	advance(run, 0.4)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	check(renderer.get_debug_state().vertices == before.vertices, "pause freezes the full beam and its contraction")
	renderer.sync_snapshot(snapshot, projector, {"reduced_motion": true})
	check(renderer.get_debug_state().vertices == before.vertices and renderer.get_debug_state().beams == before.beams, "reduced motion retains complete real line and all stages")
	projector.rotation = 0.3
	projector.scale = 53.0
	projector.offset += Vector2(37, -19)
	renderer.sync_snapshot(snapshot, projector)
	check(renderer.get_debug_state().groups == before.groups and renderer.get_debug_state().vertices != before.vertices, "all four real world corners reproject together")
	check(snapshot == original and run._rng.state == rng, "renderer cannot mutate snapshot or RNG")
	projector.rotation = 0.0
	projector.scale = 40.0
	projector.offset = Vector2(640, 360)
	run.set_paused(false)
	run._spell_combat.apply_burn(run, run.actors[0], "F03")
	renderer.sync_snapshot(run.get_snapshot(), projector)
	check(not renderer.get_debug_state().burns.has(71) and renderer.get_debug_state().cooling.is_empty(), "source handoff avoids duplicate attached flames and false extinction")
	run._spell_combat.apply_burn(run, run.actors[0], "F08")
	renderer.sync_snapshot(run.get_snapshot(), projector)
	run._spell_combat.detonate_burn(run, run.actors[0], 1.0)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	check(not renderer.get_debug_state().burns.has(71) and renderer.get_debug_state().cooling.is_empty(), "consuming F08 fuel is not a natural cooling event")
	advance(run, 4.5)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	advance(run, 0.3)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	check(not renderer.visible, "full line/burn/cooling lifecycle returns to empty")
	var absent: Dictionary = original.duplicate(true)
	absent.fire_beam_facts.clear()
	absent.spell_burns.clear()
	absent.effects.clear()
	absent.room_revision += 1
	renderer.sync_snapshot(absent, projector)
	check(not renderer.visible and renderer.get_debug_state().vertices.is_empty(), "missing beam facts never infer an attack")
	absent.phase = "pickup"
	renderer.sync_snapshot(absent, projector)
	check(renderer.get_debug_state().cooling.is_empty(), "combat exit clears all history")


func capacity(renderer, projector) -> void:
	var run = fresh()
	run.room_revision = 40
	cast(run)
	var snapshot: Dictionary = run.get_snapshot()
	var template: Dictionary = snapshot.fire_beam_facts[0].duplicate(true)
	snapshot.fire_beam_facts.clear()
	snapshot.effects.clear()
	snapshot.spell_burns.clear()
	for index in 128:
		var fact := template.duplicate(true)
		fact.seq = index + 1
		fact.cast_id = index + 1
		fact.hits.clear()
		snapshot.fire_beam_facts.append(fact)
	renderer.sync_snapshot(snapshot, projector)
	var debug: Dictionary = renderer.get_debug_state()
	check(debug.groups.size() == 128 and debug.vertices.size() == 512 and int(debug.overflow) == 0, "128 actual-line shapes fit the bounded batch")
	check(debug.batch_nodes == 3 and debug.material_count == 3, "high line counts allocate no additional nodes or materials")
	for index in 128:
		var fact := template.duplicate(true)
		fact.seq = index + 129
		fact.cast_id = index + 129
		fact.hits.clear()
		snapshot.fire_beam_facts.append(fact)
	renderer.sync_snapshot(snapshot, projector)
	check(renderer.get_debug_state().groups.size() == 128 and int(renderer.get_debug_state().overflow) == 128, "excess decorative geometry is bounded without gameplay mutation")


func integration_and_preview() -> void:
	var run = fresh(3)
	cast(run)
	var view = View.new()
	root.add_child(view)
	await process_frame
	view.sync(run.get_snapshot())
	check(view.get_fire_beam_debug_state().groups.size() == 1 and int(view.spell_vfx.get_debug_state().coverage.get("beam", 0)) == 0, "native battle view routes F08 exactly once")
	check(view.fire_beam_vfx.z_index < view._overlay.z_index and view.fire_beam_vfx.z_index < view.magic_missile_vfx.z_index, "hostile warnings and missiles remain above friendly beams")
	var old: Dictionary = run.get_snapshot()
	old.erase("fire_beam_facts")
	view.sync(old)
	check(not view.fire_beam_vfx.visible and int(view.spell_vfx.get_debug_state().coverage.get("beam", 0)) == 1, "old snapshots preserve legacy beam rendering")
	view.queue_free()
	await process_frame
	var scene: PackedScene = load("res://tests/previews/fire_beam_preview.tscn")
	var preview = scene.instantiate()
	root.add_child(preview)
	preview.set_process(false)
	await process_frame
	preview.set_process(false)
	for mode in 7:
		preview._mode = mode
		preview._reset()
		check(preview._run.spells[0].id == "F08" and preview._run.spells[0].level == mini(mode + 1, 3), "controlled preview mode %d uses the real F08" % mode)
	for mode in [3, 6]:
		preview._mode = mode
		preview._reset()
		for frame in 600: preview._advance(STEP)
		var facts: Array = preview._run.get_snapshot().fire_beam_facts.filter(func(f): return f.phase == "main")
		check(preview._releases == 3 and facts.any(func(f): return f.source == "echo"), "preview reaches three natural releases and the actual echo mode %d" % mode)
		if mode == 6 and facts.size() >= 2: check(facts[-1].to != facts[-2].to, "controlled preview death yields actual retargeted echo")
	preview.queue_free()
	await process_frame
