extends SceneTree
## Real Route comparison: scenario pairs/checkpoints are reported separately.
## Headless geometry/logic checks never establish pixels or performance.
const Field = preload("res://scripts/presentation/route_fire_field_vfx.gd")
const View = preload("res://scripts/presentation/first_room_view.gd")
const Rules = preload("res://tests/formal_fire_tests.gd")
const Report = preload("res://tests/qa_report.gd")
const OUTPUT := "res://build/qa/fire-field-runes-v2-20261027/chain/results.json"
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
		push_error("F06 chain: " + label)


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
	add_spell(run, "F06", level)
	run.actors.clear()
	for index in 3:
		var actor: Dictionary = run._enemy_combat.make_actor(run, "M01", Vector2(0, [1.4, 3.7, 6.2][index]), 71 + index)
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


func facts(run, phase: String) -> Array:
	return run.get_snapshot().fire_field_facts.filter(func(f): return str(f.phase) == phase)


func gameplay(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			if key not in ["fire_field_facts", "fire_field_state"]: result[key] = gameplay(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(gameplay(item))
		return result
	return value


func core_parity() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline="): path = arg.trim_prefix("--baseline=")
	if path.is_empty(): return
	var old_combat: Script = load(path)
	check(old_combat != null, "frozen combat and growth load")
	if old_combat == null: return
	for level in range(1, 4):
		for mode in 12:
			var case_id := (level - 1) * 12 + mode
			var actual = fresh(level, 20261027 + case_id)
			var reference = fresh(level, 20261027 + case_id, old_combat)
			for run in [actual, reference]:
				if mode == 9: run.actors[0].health = 1.0
				cast(run, mode != 1, 0.0 if mode == 2 else 0.7 if mode == 1 else 1.0)
				if mode in [5, 6]:
					add_spell(run, "F05", 3)
					cast(run, mode == 5, 1.0, 1)
				if mode == 7: run.spells[0].level = 1
				if mode == 10:
					for id in ["F01", "F03", "F08", "F07", "F09", "F05"]: add_spell(run, id, 3)
					for slot in range(1, 7): cast(run, true, 1.0, slot)
			for frame in 900:
				for run in [actual, reference]:
					if mode == 3 and frame == 96:
						run.player.pos = Vector2(5.5, 0)
						run.player.previous = run.player.pos
					if mode == 3 and frame == 384:
						run.player.pos = Vector2.ZERO
						run.player.previous = Vector2.ZERO
					if mode == 4 and frame == 120:
						run.player.pos = Vector2(-2, 0)
						run.player.previous = run.player.pos
						cast(run, false, 0.7)
					if mode == 8 and frame == 10: run.set_paused(true)
					if mode == 8 and frame == 40: run.set_paused(false)
					if mode == 11 and frame == 216:
						for actor in run.actors:
							actor.pos += Vector2(8, 0)
							actor.previous = actor.pos
					run.step(STEP)
				if frame in [0, 58, 59, 119, 238, 239, 359, 479, 719, 899]:
					check(gameplay(actual.get_snapshot()) == gameplay(reference.get_snapshot()), "frozen whole snapshot %d/%d/%d" % [level, mode, frame])
					check(actual._rng.state == reference._rng.state, "original RNG %d/%d/%d" % [level, mode, frame])
					snapshot_comparisons += 1
			for key in ["damage_log", "context_log", "cast_log", "extra_log", "emitted"]:
				check(actual.get(key) == reference.get(key), "original hooks/events %d/%d %s" % [level, mode, key])
			baseline_cases += 1


func rules_and_lifecycle(renderer, projector) -> void:
	for level in range(1, 4):
		var chant = fresh(level)
		chant.room_revision = 10 + level
		chant.spells[0].remaining = 0.0
		chant.step(STEP)
		renderer.sync_snapshot(chant.get_snapshot(), projector)
		check(renderer.get_debug_state().coverage.get("F06_cast", 0) == 1 and renderer.get_debug_state().fields.is_empty(), "original windup precedes field birth")
		advance(chant, 0.35)
		check(chant.get_snapshot().spell_zones.size() == 1, "real windup releases the field")
		var run = fresh(level)
		run.room_revision = 20 + level
		cast(run)
		var snapshot: Dictionary = run.get_snapshot()
		var zone: Dictionary = snapshot.spell_zones[0]
		var radius := float(zone.radius)
		check(zone.pos == Vector2.ZERO and is_equal_approx(radius, [2.2, 3.1, 3.6][level - 1]) and zone.context.field_bonus == 0.0, "true origin/radius and no recursive field self-amplification")
		check(facts(run, "release").size() == 1 and facts(run, "hit").is_empty(), "release observation adds no birth hit")
		renderer.sync_snapshot(snapshot, projector)
		check(renderer.get_debug_state().fields.size() == 1 and renderer.get_debug_state().coverage.get("F06_bonus", 0) == 1, "full fixed field and actual inside bonus appear at release")
		advance(run, 0.49)
		check(facts(run, "hit").is_empty() and run.damage_dealt == 0.0, "first original full tick interval preserved")
		advance(run, 0.01)
		check(facts(run, "hit").any(func(f): return f.contact.actor_id == 71 and f.contact.damage > 0.0), "actual selected contact produces a factual hit")
		var burn: Dictionary = run._spell_combat.fire_status.burns[71].duplicate(true)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(renderer.get_debug_state().coverage.get("F06_hit", 0) > 0 and renderer.get_debug_state().burns.has(71), "true hit and source-owned ignition displayed")
		var copy: Dictionary = run.get_snapshot()
		copy.fire_field_facts[-1].contact.pos = Vector2(99, 99)
		copy.fire_field_state.attack_bonus = 99.0
		copy.fire_field_state.matured_casts.append("fake")
		check(run.get_snapshot().fire_field_facts[-1].contact.pos != Vector2(99, 99) and run.get_snapshot().fire_field_state.attack_bonus != 99.0 and not run._spell_combat.growth._matured.has("fake"), "nested facts and observed state do not alias rule storage")
		advance(run, 0.5)
		check(is_equal_approx(run._spell_combat.fire_status.burns[71].expires, burn.expires), "repeated field ticks do not refresh once-per-cast burn")
		run.player.pos = Vector2(5.5, 0)
		run.player.previous = run.player.pos
		advance(run, 1.0)
		var state: Dictionary = run.get_snapshot().fire_field_state
		check(not state.inside and (state.attack_bonus > 0.0) == (level == 3), "only actual L3 grace grants an outside bonus")
		check(run.get_snapshot().spell_zones[0].pos == Vector2.ZERO, "field center never follows the moving player")
		renderer.sync_snapshot(run.get_snapshot(), projector)
		if level == 3:
			var mature: Array = facts(run, "mature")
			check(mature.size() == 1 and is_equal_approx(float(mature[0].time), 2.0) and is_equal_approx(float(mature[0].radius), 2.4) and mature[0].radius < radius, "one true maturity at original age and its smaller independent radius")
			check(renderer.get_debug_state().coverage.get("F06_mature", 0) == 1 and renderer.get_debug_state().fields[0].charge == 0.0, "actual maturity burst ends charging but preserves the field")
			check(is_equal_approx(run._spell_combat.fire_status.burns[71].expires, burn.expires), "maturity does not add ignition or refresh the original burn")
		else:
			check(facts(run, "mature").is_empty() and renderer.get_debug_state().coverage.get("F06_mature", 0) == 0, "lower levels never invent maturity")
		advance(run, 0.6)
		check(run.get_snapshot().field_attack_bonus == 0.0, "outside grace expires on original clock")
		run.player.pos = Vector2.ZERO
		run.player.previous = Vector2.ZERO
		advance(run, 0.1)
		run.spells[0].level = 1
		advance(run, (4.0 if level == 1 else 6.0) - 2.7)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(run.get_snapshot().spell_zones.is_empty() and facts(run, "end").size() == 1 and renderer.get_debug_state().fields.is_empty(), "released level controls true expiry; no decorative active boundary remains")
		check((run.get_snapshot().field_attack_bonus > 0.0) == (level == 3) and renderer.get_debug_state().coverage.get("F06_grace", 0) == (1 if level == 3 else 0), "real L3 grace can outlive the expired field")
		advance(run, 1.6)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(run.get_snapshot().field_attack_bonus == 0.0 and not renderer.visible, "bonus and finite visual remnants fully end")


func source_edges(renderer, projector) -> void:
	var run = fresh(3)
	cast(run)
	add_spell(run, "F05", 3)
	cast(run, true, 1.0, 1)
	var state: Dictionary = run.get_snapshot().fire_field_state
	check(state.vulnerable.size() == 1 and state.vulnerable[0].actor_id == 71 and is_equal_approx(state.vulnerable[0].bonus, 0.2), "actual natural distinct-kind overlap grants the original vulnerability")
	renderer.sync_snapshot(run.get_snapshot(), projector)
	check(renderer.get_debug_state().coverage.get("F06_overlap", 0) == 1 and renderer.get_debug_state().footprints.any(func(f): return f.kind == "field_overlap" and f.actor_id == 71), "qualified overlap is displayed only on the actual affected target")
	state.vulnerable[0].bonus = 99.0
	check(is_equal_approx(run.get_snapshot().fire_field_state.vulnerable[0].bonus, 0.2), "overlap observer is deeply independent")
	var vortex: Dictionary = run._spell_combat.zones.filter(func(z): return z.spell_id == "F05")[0]
	vortex.context.natural = false
	check(run.get_snapshot().fire_field_state.vulnerable.is_empty(), "extra other-kind area does not fake natural overlap")
	renderer.sync_snapshot(run.get_snapshot(), projector)
	check(renderer.get_debug_state().coverage.get("F06_overlap", 0) == 0, "overlap hint is removed as soon as its actual qualification disappears")
	vortex.context.natural = true
	cast(run, false, 0.7)
	check(run.get_snapshot().fire_field_state.vulnerable.is_empty() and run.get_snapshot().spell_zones.filter(func(z): return z.spell_id == "F06").size() == 1, "extra F06 replaces old field and does not grant natural overlap")
	advance(run, 2.1)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	check(facts(run, "mature").is_empty() and renderer.get_debug_state().fields[0].charge == 0.0, "extra field neither charges nor matures")
	var replace = fresh(3)
	cast(replace)
	advance(replace, 1.0)
	replace.player.pos = Vector2(-2, 0)
	replace.player.previous = replace.player.pos
	cast(replace, false, 0.7)
	check(facts(replace, "replace").size() == 1 and facts(replace, "end").is_empty() and replace.get_snapshot().spell_zones[0].pos == Vector2(-2, 0), "replacement is distinguished from true natural end and changes the origin")
	advance(replace, 2.0)
	check(facts(replace, "mature").is_empty(), "replaced old natural field never matures later")
	var zero = fresh(3)
	cast(zero, true, 0.0)
	advance(zero, 0.5)
	renderer.sync_snapshot(zero.get_snapshot(), projector)
	check(facts(zero, "hit").size() > 0 and renderer.get_debug_state().coverage.get("F06_hit", 0) == 0 and renderer.get_debug_state().burns.is_empty(), "zero actual damage logs facts without false hit flash or ignition")
	var lethal = fresh(3)
	lethal.actors.resize(1)
	lethal.actors[0].health = 1.0
	cast(lethal)
	advance(lethal, 0.5)
	renderer.sync_snapshot(lethal.get_snapshot(), projector)
	check(renderer.get_debug_state().coverage.get("F06_hit", 0) == 1 and renderer.get_debug_state().burns.is_empty(), "lethal real hit has no persistent corpse burn")


func projection_cleanup_capacity(renderer, projector) -> void:
	var run = fresh(3)
	run.room_revision = 70
	cast(run)
	advance(run, 1.0)
	var snapshot: Dictionary = run.get_snapshot()
	var rng_before: int = run._rng.state
	renderer.sync_snapshot(snapshot, projector)
	var original: Dictionary = renderer.get_debug_state()
	var transform: Transform2D = original.ground_transforms[0]
	projector.offset += Vector2(97, -23)
	projector.rotation = 0.31
	projector.scale = 54.0
	renderer.sync_snapshot(snapshot, projector)
	check(renderer.get_debug_state().fields == original.fields and renderer.get_debug_state().flames == original.flames and renderer.get_debug_state().ground_transforms[0] != transform, "entire field and world flames reproject with the camera")
	check(run.get_snapshot() == snapshot and run._rng.state == rng_before, "rendering is read-only for simulation/RNG")
	var paused: Dictionary = renderer.get_debug_state()
	run.set_paused(true)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	check(renderer.get_debug_state() == paused, "pause freezes rune charge, flames, contacts and source status")
	renderer.sync_snapshot(snapshot, projector, {"reduced_motion": true})
	check(renderer.get_debug_state().fields == original.fields and renderer.get_debug_state().flames.size() < original.flames.size(), "reduced motion preserves radius/charge/status with fewer decorative tongues")
	var capacity := snapshot.duplicate(true)
	capacity.spell_zones.clear()
	for index in 128:
		var zone: Dictionary = snapshot.spell_zones[0].duplicate(true)
		zone.id = 1000 + index
		capacity.spell_zones.append(zone)
	renderer.sync_snapshot(capacity, projector)
	check(renderer.get_debug_state().fields.size() == 64 and renderer.get_debug_state().overflow == 64 and renderer.get_child_count() == 3 and renderer.get_debug_state().material_count == 2, "finite 64-field structure with fixed nodes/materials")
	var missing := snapshot.duplicate(true)
	missing.spell_zones.clear()
	missing.fire_field_facts.clear()
	missing.spell_burns.clear()
	missing.effects.clear()
	missing.fire_field_state = {}
	renderer.sync_snapshot(missing, projector)
	check(not renderer.visible and renderer.get_debug_state().coverage.get("F06_end", 0) == 0, "unrecorded cancellation never invents natural end/maturity")
	missing.phase = "complete"
	renderer.sync_snapshot(missing, projector)
	check(renderer.get_debug_state().footprints.is_empty() and renderer.get_debug_state().burns.is_empty(), "leaving combat clears all local state")
	var bounded = fresh(3)
	for index in 300: cast(bounded, false, 0.7)
	check(bounded.get_snapshot().fire_field_facts.size() == 512 and bounded.get_snapshot().spell_zones.size() == 1, "fact retention is bounded without changing replacement rules")
	bounded._stop_combat()
	check(bounded.get_snapshot().fire_field_facts.is_empty(), "room stop clears the observational journal")


func decorative_motion(renderer, projector) -> void:
	var previous_count := 0
	for level in range(1, 4):
		var run = fresh(level)
		run.room_revision = 90 + level
		cast(run)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		var born: Dictionary = renderer.get_debug_state()
		check(born.visual_revision == 2 and born.fields[0].rune_reveal == 0.0 and born.ground_instances > 0, "v2 exposes true whole boundary before decorative glyph reveal")
		advance(run, 0.12)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(renderer.get_debug_state().fields[0].rune_reveal > 0.0 and renderer.get_debug_state().fields[0].rune_reveal < 1.0, "interior glyph reveal follows real field age")
		advance(run, 0.68)
		var snapshot: Dictionary = run.get_snapshot()
		var rng_before: int = run._rng.state
		renderer.sync_snapshot(snapshot, projector)
		var first: Dictionary = renderer.get_debug_state()
		check(first.fields[0].rune_reveal == 1.0 and first.embers.size() > previous_count and first.embers.size() < 32, "fully revealed field has a small level-scaled ember population")
		previous_count = first.embers.size()
		var zone: Dictionary = snapshot.spell_zones[0]
		check(first.embers.all(func(e): return e.phase == "field" and e.pos.distance_to(zone.pos) + e.radius < float(zone.radius) and e.height > 0.0 and e.height < 1.0), "rising field embers stay within true world footprint and low decorative height")
		check(first.flames.all(func(f): return f.pos.distance_to(zone.pos) + f.width < float(zone.radius) and f.height < 0.8), "clustered low flames leave the real boundary readable")
		var heights: Array = []
		var cycles: Array = []
		for ember: Dictionary in first.embers:
			if not heights.has(snappedf(float(ember.height), 0.01)): heights.append(snappedf(float(ember.height), 0.01))
			if not cycles.has(snappedf(float(ember.cycle), 0.01)): cycles.append(snappedf(float(ember.cycle), 0.01))
		check(heights.size() >= 4 and cycles.size() >= 4 and first.embers.any(func(e): return e.alpha > 0.1), "embers have staggered ages, lift, cycle and a visible alpha envelope")
		renderer.sync_snapshot(snapshot, projector)
		check(renderer.get_debug_state() == first and run.get_snapshot() == snapshot and run._rng.state == rng_before, "repeat rendering is deterministic and cannot advance gameplay or RNG")
		advance(run, 0.13)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		var second: Dictionary = renderer.get_debug_state()
		check(second.fields[0].pos == first.fields[0].pos and second.fields[0].radius == first.fields[0].radius and second.ground_transforms[0] == first.ground_transforms[0], "glyph ground plane remains fixed while time advances")
		check(second.embers[0].pos != first.embers[0].pos and second.embers[0].height != first.embers[0].height and second.flames != first.flames, "embers curve upward and low fire clusters breathe on the game clock")
		check(second.flames[0].anchor == first.flames[0].anchor, "small flames breathe around fixed rune anchors")
		var before_transform: Transform2D = second.ember_transforms[0]
		projector.offset += Vector2(13, -7)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(renderer.get_debug_state().embers == second.embers and renderer.get_debug_state().ember_transforms[0] != before_transform, "entire ember path reprojects from unchanged world coordinates")
		var full: Dictionary = renderer.get_debug_state()
		renderer.sync_snapshot(run.get_snapshot(), projector, {"reduced_motion": true})
		var reduced: Dictionary = renderer.get_debug_state()
		check(reduced.embers.is_empty() and reduced.fields == full.fields and reduced.flames.size() < full.flames.size(), "reduced motion removes drifting decoration while preserving field and true charge")
	var mature = fresh(3)
	mature.room_revision = 98
	cast(mature)
	advance(mature, 2.16)
	renderer.sync_snapshot(mature.get_snapshot(), projector)
	var burst: Array = renderer.get_debug_state().embers.filter(func(e): return e.phase == "mature")
	var fact: Dictionary = facts(mature, "mature")[0]
	check(not burst.is_empty() and burst.all(func(e): return e.cast_id == fact.cast_id and e.pos.distance_to(fact.pos) < float(fact.radius)), "maturity embers belong only to the actual once-per-cast fact and its smaller radius")
	advance(mature, 0.60)
	renderer.sync_snapshot(mature.get_snapshot(), projector)
	check(renderer.get_debug_state().embers.all(func(e): return e.phase == "field"), "maturity decoration fully ends while the actual field persists")
	var ended: Dictionary = mature.get_snapshot()
	ended.phase = "complete"
	renderer.sync_snapshot(ended, projector)
	check(renderer.get_debug_state().embers.is_empty() and renderer.get_debug_state().ember_transforms.is_empty(), "combat exit clears every ember and its submitted geometry")


func integration_and_preview() -> void:
	var run = fresh(3)
	cast(run)
	advance(run, 2.0)
	var view = View.new()
	root.add_child(view)
	await process_frame
	await process_frame
	view.sync(run.get_snapshot())
	check(view.get_fire_field_debug_state().fields.size() == 1 and view.get_fire_field_debug_state().coverage.get("F06_mature", 0) == 1, "formal view owns field and true maturity")
	check(view.spell_vfx.get_debug_state().coverage.get("F06", 0) == 0, "new capability disables only duplicate legacy F06")
	var old := run.get_snapshot()
	old.erase("fire_field_facts")
	old.erase("fire_field_state")
	view.sync(old)
	check(view.spell_vfx.get_debug_state().coverage.get("F06", 0) == 1 and view.get_fire_field_debug_state().fields.is_empty(), "old snapshots retain legacy field rendering")
	view.queue_free()
	await process_frame
	var preview = load("res://tests/previews/fire_field_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	preview.set_process(false)
	for mode in 9:
		preview._mode = mode
		preview._paused = false
		preview._reset()
		for frame in 408: preview._advance(STEP)
		preview._view.sync(preview._run.get_snapshot())
		check(preview._run.get_snapshot().spell_zones.any(func(z): return z.spell_id == "F06") and preview._view.get_fire_field_debug_state().fields.size() == 1, "controlled preview mode %d uses real field" % mode)
		if mode in [5, 6]: check(preview._run.get_snapshot().fire_field_facts.all(func(f): return f.phase != "mature"), "extra/replaced preview does not fake maturity")
		if mode == 7:
			for frame in 444: preview._advance(STEP)
			check(preview._run.get_snapshot().spell_zones.is_empty() and preview._run.get_snapshot().field_attack_bonus > 0.0, "expiry preview reaches true post-field grace")
	preview.queue_free()
	await process_frame


func execute() -> void:
	core_parity()
	baseline_assertions = checks
	var renderer = Field.new()
	root.add_child(renderer)
	await process_frame
	check(renderer.is_available() and renderer.get_child_count() == 3, "three fixed native draw nodes")
	for shader: Shader in [Field.SURFACE_SHADER, Field.BODY_SHADER]:
		check(not shader.get_shader_uniform_list().is_empty(), "local shader-language parse: " + shader.resource_path)
	var projector := Projector.new()
	rules_and_lifecycle(renderer, projector)
	source_edges(renderer, projector)
	projection_cleanup_capacity(renderer, projector)
	decorative_motion(renderer, projector)
	await integration_and_preview()
	renderer.queue_free()
	await process_frame
	var result := {"checks": checks, "failures": failures.size(), "details": failures, "frozen_baseline_cases": baseline_cases,
		"whole_snapshot_comparisons": snapshot_comparisons, "baseline_assertions": baseline_assertions, "non_baseline_assertions": checks - baseline_assertions,
		"scenario_matrix": "3 levels x natural, extra, zero damage, leave/reenter, replacement, natural overlap, extra overlap, release-level retention, pause, lethal, mixed six approved spells, targets leaving maturity.",
		"scope": "Real Route fixed-field origin/radius/ticks/once-per-cast burn, actual bonus/grace and natural distinct-kind vulnerability, original one-shot maturity/smaller radius, replacement/end, projection/pause/reduced/clear, finite structure and nine headless preview fixtures. V2 fixed glyph plane/reveal, staggered low flame clusters and rising curved world-space embers, independent maturity decoration and reduced motion. Frozen combat/growth parity only with --baseline. No interactive launch, screenshots, pixels/GPU composition/performance, natural route, export, Git or F06 visual acceptance."}
	if not Report.write_report(result, OUTPUT): failures.append("cannot write report")
	print("FIRE FIELD CHAIN scenarios=%d snapshot_comparisons=%d assertions=%d failures=%d" % [baseline_cases, snapshot_comparisons, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


