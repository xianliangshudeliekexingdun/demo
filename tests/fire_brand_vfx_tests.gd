extends SceneTree
## Real Route comparison: scenario pairs/checkpoints are reported separately.
## Headless geometry/logic checks never establish pixels or performance.
const Brand = preload("res://scripts/presentation/route_fire_brand_vfx.gd")
const View = preload("res://scripts/presentation/first_room_view.gd")
const Rules = preload("res://tests/formal_fire_tests.gd")
const Report = preload("res://tests/qa_report.gd")
const OUTPUT := "res://build/qa/fire-brand-vfx-20261027/chain/results.json"
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
		push_error("F11 chain: " + label)


func add_spell(run, id: String, level: int) -> void:
	var spell: Dictionary = run._new_spell(id)
	spell.level = level
	run._refresh_spell(spell)
	spell.remaining = 9999.0
	run.spells.append(spell)


func fresh(level: int = 1, seed: int = 20261027, old_combat: Script = null):
	var run = Rules.Fixture.new()
	check(run.configure({}, seed).ok and run.choose_initial("F01"), "real Route fixture configures")
	if old_combat != null:
		run._spell_combat = old_combat.new()
		check(run._spell_combat.configure(run).ok, "task-frozen combat configures")
	run._spawn_done = true
	run.spawn_warnings.clear()
	run.blocks.clear()
	run.player.pos = Vector2.ZERO
	run.player.previous = Vector2.ZERO
	run.player.crit_rate = 0.0
	run.spells.clear()
	add_spell(run, "F11", level)
	run.actors.clear()
	var positions := [Vector2(0, 2), Vector2(1, 2.8), Vector2(-1, 2.8), Vector2(1.8, 3.8), Vector2(-1.8, 3.8), Vector2(0, 4.6), Vector2(2.5, 4.6), Vector2(-2.5, 4.6), Vector2(0, 6.8)]
	for index in positions.size():
		var actor: Dictionary = run._enemy_combat.make_actor(run, "M01", positions[index], 71 + index)
		actor.health = 100000.0
		actor.max_health = actor.health
		run.actors.append(actor)
	return run


func cast(run, natural: bool = true, scale: float = 1.0, slot: int = 0) -> void:
	var spell: Dictionary = run.spells[slot]
	spell["locked_pos"] = run.actors[0].pos
	run._spell_combat._cast(run, spell, run.get_spell_stats(spell), run.actors[0], natural, scale)
	spell.remaining = 9999.0


func advance(run, seconds: float) -> void:
	for frame in roundi(seconds / STEP): run.step(STEP)


func spreads(run) -> Array:
	return run.get_snapshot().effects.filter(func(e): return e.kind == "fire_spread" and e.spell_id == "F11")


func gameplay(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			if key not in ["fire_brand_facts"]: result[key] = gameplay(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(gameplay(item))
		return result
	return value


func setup_case(run, mode: int) -> void:
	if mode == 3: run.actors[0].health = 1.0
	if mode == 4: run.blocks.append({"center": Vector2(0.5, 2.4), "size": Vector2(0.16, 0.55)})
	if mode in [5, 9]:
		for index in [1, 2]: run._spell_combat.apply_burn(run, run.actors[index], "F01")
	if mode == 6:
		for index in range(1, run.actors.size()):
			run.actors[index].pos += Vector2(8, 0)
			run.actors[index].previous = run.actors[index].pos
	cast(run, mode != 1, 0.0 if mode == 2 else 0.7 if mode == 1 else 1.0)
	if mode == 11:
		for id in ["F01", "F03", "F08", "F07", "F09", "F05", "F06"]: add_spell(run, id, 3)
		for slot in range(1, 8): cast(run, true, 1.0, slot)


func core_parity() -> void:
	var path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline="): path = argument.trim_prefix("--baseline=")
	if path.is_empty(): return
	var old_combat: Script = load(path)
	check(old_combat != null, "current task frozen combat loads")
	if old_combat == null: return
	for level in range(1, 4):
		for mode in 12:
			var actual = fresh(level, 20261027 + level * 20 + mode)
			var reference = fresh(level, 20261027 + level * 20 + mode, old_combat)
			for run in [actual, reference]: setup_case(run, mode)
			for frame in 900:
				for run in [actual, reference]:
					if mode == 7 and frame == 12:
						run.actors[0].pos += Vector2(0.8, 0.1)
						run.actors[0].previous = run.actors[0].pos
					if mode == 8 and frame == 12: run.set_paused(true)
					if mode == 8 and frame == 36: run.set_paused(false)
					if mode == 9 and frame == 60: run.spells[0].level = 1
					if mode == 10 and frame == 24: run._spell_combat.apply_burn(run, run.actors[1], "F01")
					if mode == 10 and frame == 48: run._spell_combat.detonate_burn(run, run.actors[2], 1.0)
					run.step(STEP)
				if frame in [0, 11, 23, 59, 119, 239, 359, 479, 719, 899]:
					check(gameplay(actual.get_snapshot()) == gameplay(reference.get_snapshot()), "whole original snapshot %d/%d/%d" % [level, mode, frame])
					check(actual._rng.state == reference._rng.state, "original RNG %d/%d/%d" % [level, mode, frame])
					snapshot_comparisons += 1
			for key in ["damage_log", "context_log", "cast_log", "extra_log", "emitted"]:
				check(actual.get(key) == reference.get(key), "original hooks/events %d/%d %s" % [level, mode, key])
			baseline_cases += 1


func rules_and_visuals(renderer, projector) -> void:
	for level in range(1, 4):
		var chant = fresh(level)
		chant.room_revision = 10 + level
		chant.spells[0].remaining = 0.0
		chant.step(STEP)
		renderer.sync_snapshot(chant.get_snapshot(), projector)
		check(renderer.get_debug_state().coverage.get("F11_cast", 0) == 1 and chant.get_snapshot().fire_brand_facts.is_empty(), "original windup precedes instantaneous brand")
		advance(chant, 0.30)
		check(chant.get_snapshot().fire_brand_facts.size() == 1, "real windup releases exactly one original brand")
		var run = fresh(level)
		run.room_revision = 20 + level
		cast(run)
		var snapshot: Dictionary = run.get_snapshot()
		var fact: Dictionary = snapshot.fire_brand_facts[0]
		var links: Array = spreads(run)
		check(links.size() == [2, 4, 6][level - 1] and fact.contact.damage > 0.0, "original level cap selects successful one-round neighbors")
		check(run.damage_log.size() == 1 and run.damage_log[0].actor_id == 71 and snapshot.spell_zones.is_empty() and run._spell_combat.pending.is_empty(), "only primary takes direct damage; no delayed strike or persistent zone")
		check(links[0].actor_id == 72 and links[1].actor_id == 73, "equal-distance neighbors retain original actor-id ordering")
		check(links.all(func(e): return e.from == fact.contact.pos and is_equal_approx(e.max_life, e.life)), "all actual links originate at primary at the same original time without recursive hops")
		check(snapshot.spell_burns.size() == links.size() + 1, "primary and successful neighbors each hold one original burn")
		renderer.sync_snapshot(snapshot, projector)
		var debug: Dictionary = renderer.get_debug_state()
		check(debug.marks.size() == 1 and debug.links.size() == links.size() and debug.burns.size() == links.size() + 1, "true seal, whole links and actual ignition appear in one frame")
		check(debug.links.all(func(e): return e.progress == 0.0 and e.points[0].pos == e.from and e.points[-1].pos == e.to and is_equal_approx(e.time, fact.time)), "complete world-space curves reach every destination immediately")
		var copy: Dictionary = run.get_snapshot()
		copy.fire_brand_facts[0].contact.pos = Vector2(99, 99)
		check(run.get_snapshot().fire_brand_facts[0].contact.pos == Vector2(0, 2), "contact snapshots do not alias original records")
		var rng_before: int = run._rng.state
		renderer.sync_snapshot(snapshot, projector)
		check(run.get_snapshot() == snapshot and run._rng.state == rng_before and renderer.get_debug_state() == debug, "repeated drawing cannot mutate simulation, events or RNG")
		var transform: Transform2D = debug.link_transforms[0]
		projector.offset += Vector2(23, -17)
		projector.rotation += 0.10
		renderer.sync_snapshot(snapshot, projector)
		check(renderer.get_debug_state().links == debug.links and renderer.get_debug_state().link_transforms[0] != transform, "entire world curve reprojects through a changed camera")
		var before_pause: Dictionary = renderer.get_debug_state()
		run.set_paused(true)
		advance(run, 0.1)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(renderer.get_debug_state() == before_pause, "pause freezes all marks, links and burns")
		run.set_paused(false)
		renderer.sync_snapshot(snapshot, projector, {"reduced_motion": true})
		var reduced: Dictionary = renderer.get_debug_state()
		check(reduced.marks == debug.marks and reduced.links.size() == debug.links.size() and reduced.link_transforms.size() < debug.link_transforms.size() and reduced.burns == debug.burns, "reduced motion preserves real targets/statuses with a simpler complete curve")
		advance(run, 0.40)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(renderer.get_debug_state().marks.is_empty() and renderer.get_debug_state().links.is_empty() and not renderer.get_debug_state().burns.is_empty(), "short marks/links end without ending the true burn")
		var expires := float(run._spell_combat.fire_status.burns[71].expires)
		advance(run, expires - float(run.time) - 0.01)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		advance(run, 0.02)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(renderer.get_debug_state().burns.is_empty() and not renderer.get_debug_state().cooling.is_empty(), "actual natural expiry leaves only finite cooling")
		advance(run, 0.40)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(not renderer.visible and renderer.get_debug_state().cooling.is_empty(), "all burn remnants fully clear")


func edge_cases(renderer, projector) -> void:
	for mode in [2, 3, 4, 5, 6]:
		var run = fresh(3)
		run.room_revision = 40 + mode
		setup_case(run, mode)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		var debug: Dictionary = renderer.get_debug_state()
		if mode == 2: check(debug.marks.is_empty() and debug.links.is_empty() and debug.burns.is_empty(), "zero effective damage invents no seal, spread or ignition")
		if mode == 3: check(debug.marks.size() == 1 and debug.links.size() == 6 and not debug.burns.has(71), "lethal primary still spreads by original rule and never has corpse flames")
		if mode == 4: check(debug.links.all(func(e): return e.actor_id != 72) and debug.links.size() > 0, "wall-blocked neighbor has no invented link")
		if mode == 5: check(debug.links.all(func(e): return e.actor_id not in [72, 73]) and not debug.burns.has(72) and not debug.burns.has(73), "already-burning neighbors keep their original source and are skipped")
		if mode == 6: check(debug.marks.size() == 1 and debug.links.is_empty() and debug.burns.size() == 1, "no eligible neighbor produces only the actual primary effect")
	var extra = fresh(3)
	extra.room_revision = 50
	cast(extra, false, 0.7)
	renderer.sync_snapshot(extra.get_snapshot(), projector)
	check(not renderer.get_debug_state().marks[0].natural and renderer.get_debug_state().links.size() == 6 and extra.casts == 0, "extra brand keeps original spread and does not count as natural casting")
	var source = fresh(3)
	source.room_revision = 51
	cast(source)
	renderer.sync_snapshot(source.get_snapshot(), projector)
	var token: int = source._spell_combat.fire_status.burns[72].token
	source._spell_combat.apply_burn(source, source.actors[1], "F01")
	source._spell_combat.detonate_burn(source, source.actors[2], 1.0)
	source.actors[0].pos += Vector2(1, 0)
	source.actors[0].previous = source.actors[0].pos
	advance(source, 0.02)
	renderer.sync_snapshot(source.get_snapshot(), projector)
	var debug: Dictionary = renderer.get_debug_state()
	check(not debug.burns.has(72) and not debug.burns.has(73) and source._spell_combat.fire_status.burns[72].token == token and debug.cooling.is_empty(), "source handoff and consumption do not fabricate cooling or extra burn tokens")
	check(debug.burns[71].pos == source.actors[0].pos and debug.links[0].from != source.actors[0].pos, "burn follows moving target while short connection retains the actual cast geometry")
	var global_burn = fresh(3)
	global_burn._spell_combat.apply_burn(global_burn, global_burn.actors[0], "F01")
	var expiry: float = global_burn._spell_combat.fire_status.burns[71].expires
	global_burn.spells[0].level = 1
	check(expiry == 6.0 and global_burn._spell_combat.fire_status.burns[71].expires == expiry, "held L3 brand extends actual global burn without retroactively shortening an existing burn")
	var capacity: Dictionary = source.get_snapshot()
	capacity.effects = []
	for index in 256:
		capacity.effects.append({"seq": index, "kind": "fire_spread", "spell_id": "F11", "from": Vector2(0, 2), "to": Vector2(1, 3), "actor_id": 72, "max_life": 0.5, "life": 0.5})
	renderer.sync_snapshot(capacity, projector)
	check(renderer.get_debug_state().links.size() == 128 and renderer.get_debug_state().overflow == 128 and renderer.get_child_count() == 3, "finite link capacity has fixed native nodes and bounded geometry")
	var bounded = fresh(3)
	for index in 300: cast(bounded, false, 0.0)
	check(bounded.get_snapshot().fire_brand_facts.size() == 256, "primary contact journal is bounded")
	advance(bounded, 1.1)
	check(bounded.get_snapshot().fire_brand_facts.is_empty(), "contact journal expires on original game time")
	cast(bounded)
	bounded._stop_combat()
	check(bounded.get_snapshot().fire_brand_facts.is_empty(), "room stop clears observational contacts")
	var absent := source.get_snapshot()
	absent.erase("fire_brand_facts")
	renderer.sync_snapshot(absent, projector)
	check(not renderer.visible and renderer.get_debug_state().links.is_empty() and renderer.get_debug_state().burns.is_empty(), "missing capability clears new renderer for legacy fallback")


func integration_and_preview() -> void:
	var run = fresh(3)
	cast(run)
	var view = View.new()
	root.add_child(view)
	await process_frame
	view.sync(run.get_snapshot())
	check(view.get_fire_brand_debug_state().marks.size() == 1 and view.get_fire_brand_debug_state().links.size() == 6, "formal view owns the complete brand chain")
	check(view.spell_vfx.get_debug_state().coverage.get("fire_brand", 0) == 0, "available new capability suppresses duplicate legacy F11")
	var old := run.get_snapshot()
	old.erase("fire_brand_facts")
	view.sync(old)
	check(view.get_fire_brand_debug_state().marks.is_empty() and view.spell_vfx.get_debug_state().coverage.get("fire_brand", 0) > 0, "older snapshots retain original F11 rendering")
	view.queue_free()
	await process_frame
	var preview = load("res://tests/previews/fire_brand_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	preview.set_process(false)
	for mode in 9:
		preview._mode = mode
		preview._paused = false
		preview._reset()
		for frame in 113: preview._advance(STEP)
		preview._view.sync(preview._run.get_snapshot())
		check(preview._view.get_fire_brand_debug_state().marks.size() == 1, "preview %d uses a real primary contact" % mode)
		if mode == 7: check(preview._view.get_fire_brand_debug_state().links.is_empty(), "no-neighbor preview draws no invented branch")
		if mode == 8:
			for frame in 26: preview._advance(STEP)
			preview._view.sync(preview._run.get_snapshot())
			check(not preview._view.get_fire_brand_debug_state().burns.has(802), "moving/handoff preview uses actual source ownership")
	preview.queue_free()
	await process_frame


func execute() -> void:
	core_parity()
	baseline_assertions = checks
	var renderer = Brand.new()
	root.add_child(renderer)
	await process_frame
	check(renderer.is_available() and renderer.get_child_count() == 3, "three fixed draw nodes and a valid presentation config")
	for shader: Shader in [Brand.SURFACE_SHADER, Brand.BODY_SHADER]:
		check(not shader.get_shader_uniform_list().is_empty(), "shader language parses: " + shader.resource_path)
	var projector := Projector.new()
	rules_and_visuals(renderer, projector)
	edge_cases(renderer, projector)
	await integration_and_preview()
	renderer.queue_free()
	await process_frame
	var result := {"checks": checks, "failures": failures.size(), "details": failures, "frozen_baseline_cases": baseline_cases,
		"whole_snapshot_comparisons": snapshot_comparisons, "baseline_assertions": baseline_assertions, "non_baseline_assertions": checks - baseline_assertions,
		"scenario_matrix": "3 levels x natural, extra, zero effective damage, lethal primary, blocked neighbor, pre-existing burns, no neighbors, moving primary, pause, global burn/released retention, source handoff/consumption, mixed seven accepted spells.",
		"scope": "Real Route single primary hit and original one-round successful spread, actual global burns/source lifecycle, true cast geometry/same-time endpoints, finite fixed batches, pause/reduced motion/reprojection/legacy fallback, nine headless preview fixtures. Frozen whole-snapshot/hooks/RNG parity only with --baseline. No interactive launch, screenshots, pixels/GPU/performance, natural route, export, Git or user visual acceptance."}
	if not Report.write_report(result, OUTPUT): failures.append("cannot write report")
	print("FIRE BRAND CHAIN scenarios=%d snapshots=%d assertions=%d failures=%d" % [baseline_cases, snapshot_comparisons, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


