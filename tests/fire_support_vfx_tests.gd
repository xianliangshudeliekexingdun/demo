extends SceneTree
## Original Route transactions/state plus read-only rendering. No pixel claims.
const Support = preload("res://scripts/presentation/route_fire_support_vfx.gd")
const View = preload("res://scripts/presentation/first_room_view.gd")
const Rules = preload("res://tests/formal_fire_tests.gd")
const Report = preload("res://tests/qa_report.gd")
const OUTPUT := "res://build/qa/current-visual-regressions/fire_support_vfx_tests/results.json"
const STEP := 1.0 / 120.0
var checks := 0
var failures: Array = []
var scenario_count := 0

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
		push_error("F10/F02 chain: " + label)


func add_spell(run, id: String, level: int) -> void:
	var spell: Dictionary = run._new_spell(id)
	spell.level = level
	run._refresh_spell(spell)
	spell.remaining = 9999.0
	run.spells.append(spell)


func fresh(id: String = "F10", level: int = 1):
	var run = Rules.Fixture.new()
	check(run.configure({}, 20261027).ok and run.choose_initial("F01"), "real Route fixture configures")
	run._spawn_done = true
	run.spawn_warnings.clear()
	run.blocks.clear()
	run.player.pos = Vector2.ZERO
	run.player.previous = Vector2.ZERO
	run.player.max_shield = 100.0
	run.player.shield = 0.0
	run.player.invulnerable = 0.0
	run.spells.clear()
	if not id.is_empty(): add_spell(run, id, level)
	run.actors.clear()
	var actor: Dictionary = run._enemy_combat.make_actor(run, "M01", Vector2(0, 3), 71)
	actor.health = 100000.0
	actor.max_health = actor.health
	run.actors.append(actor)
	scenario_count += 1
	run.room_revision = 100 + scenario_count
	return run


func advance(run, seconds: float) -> void:
	for frame in roundi(seconds / STEP): run.step(STEP)


func award_mastery(run) -> bool:
	run.phase = "reward"
	run.room_revision += 1
	run.reward_choices = [run._choice("F02")]
	return run.choose_reward("F02", run.room_revision)


func render(renderer, run, projector, options: Dictionary = {}) -> Dictionary:
	var snapshot: Dictionary = run.get_snapshot()
	var rng_before: int = run._rng.state
	var hooks := [run.damage_log.duplicate(true), run.cast_log.duplicate(true), run.emitted.duplicate(true)]
	renderer.sync_snapshot(snapshot, projector, options)
	check(run.get_snapshot() == snapshot and run._rng.state == rng_before and hooks == [run.damage_log, run.cast_log, run.emitted], "drawing never mutates whole original snapshot, hooks or RNG")
	return renderer.get_debug_state()


func guard_rules(renderer, projector) -> void:
	for level in range(1, 4):
		var run = fresh("F10", level)
		var health := float(run.player.health)
		run.spells[0].remaining = 0.0
		advance(run, 0.05)
		var windup := render(renderer, run, projector)
		check(windup.coverage.get("F10_cast", 0) == 1 and windup.restores.is_empty() and run.player.shield == 0.0, "original cast gathers before any real restoration")
		advance(run, 0.40)
		var debug := render(renderer, run, projector)
		check(is_equal_approx(run.player.shield, [30.0, 55.0, 70.0][level - 1]) and run.player.health == health and run.damage_log.is_empty(), "original level restores only its shield amount without health or damage changes")
		check(debug.restores.size() == 1 and debug.restores[0].amount == run.player.shield and debug.coverage.get("F10_guard", 0) == 1 and debug.mastery.is_empty(), "actual positive amount drives one open transient guard")
		check(not debug.sparks.is_empty() and debug.sparks.all(func(s): return s.source == "F10" and s.pos.distance_to(run.player.pos) < 0.9 and s.height < 1.8), "small inward sparks remain local and low")
		var transform: Transform2D = debug.transforms[0]
		projector.offset += Vector2(17, -11)
		projector.rotation += 0.08
		var moved := render(renderer, run, projector)
		check(moved.restores == debug.restores and moved.sparks == debug.sparks and moved.transforms[0] != transform, "whole support geometry reprojects from unchanged world positions")
		run.set_paused(true)
		advance(run, 0.1)
		check(render(renderer, run, projector) == moved, "pause freezes guard, sparks and restoration progress")
		run.set_paused(false)
		var reduced := render(renderer, run, projector, {"reduced_motion": true})
		check(reduced.restores == debug.restores and reduced.sparks.is_empty() and reduced.coverage.get("F10_guard", 0) == 1, "reduced motion preserves actual guard and disables decorative sparks")
		advance(run, 0.8)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(not renderer.visible and run.player.shield == [30.0, 55.0, 70.0][level - 1], "short feedback ends without consuming or timing out the real shield")
		var small = fresh("F10", level)
		small.player.shield = 95.0
		check(small.cast_extra_spell("F10"), "original extra shield cast succeeds")
		var clipped := render(renderer, small, projector)
		check(small.casts == 0 and small.player.shield == 100.0 and clipped.restores[0].amount == 5.0 and clipped.restores[0].strength < debug.restores[0].strength, "partial missing shield clips amount and visual strength, preserving extra counting")
		small.damage_player(101.0)
		var spent := render(renderer, small, projector)
		check(small.player.shield == 0.0 and spent.coverage.get("F10_guard", 0) == 0 and spent.coverage.get("F10_spent_flash", 0) == 1 and spent.sparks.is_empty(), "fully spent shield withdraws guard arcs without fabricating protection")
		var full = fresh("F10", level)
		full.player.shield = 100.0
		full.spells[0].remaining = 0.0
		advance(full, 0.8)
		check(full.casts == 0 and render(renderer, full, projector).restores.is_empty(), "full shield preserves original no-cast condition")
		var empty = fresh("F10", level)
		empty.actors.clear()
		empty.spells[0].remaining = 0.0
		advance(empty, 0.8)
		check(empty.casts == 0 and render(renderer, empty, projector).restores.is_empty(), "no live enemy preserves original no-cast condition")
	var zero = fresh()
	zero.player.shield = 100.0
	zero._spell_combat._cast(zero, zero.spells[0], zero.get_spell_stats(zero.spells[0]), {"id": -1, "pos": zero.player.pos}, false, 1.0)
	check(zero.effects.any(func(e): return e.kind == "shield_restore" and e.amount == 0.0) and render(renderer, zero, projector).restores.is_empty(), "original zero-return branch produces no false restoration feedback")
	var overlap = fresh()
	check(overlap.cast_extra_spell("F10") and overlap.cast_extra_spell("F10"), "two actual extra restores succeed")
	var overlapping := render(renderer, overlap, projector)
	check(overlapping.restores.size() == 2 and overlapping.coverage.get("F10_guard", 0) == 1 and overlap.player.shield == 60.0, "overlapping completed restores share one guard instead of stacked opaque shells")


func mastery_rules(renderer, projector) -> void:
	var run = fresh("F01")
	check(award_mastery(run), "real reward transaction learns mastery")
	for level in range(1, 4):
		if level > 1: check(award_mastery(run), "real reward transaction upgrades mastery")
		advance(run, 0.10)
		var debug := render(renderer, run, projector)
		check(run.phase == "exit" and debug.mastery.size() == 1 and debug.mastery[0].level == level, "actual successful reward shows the resulting mastery level outside combat")
		check(is_equal_approx(run._spell_combat.fire_bonus(), [0.15, 0.30, 0.50][level - 1]) and is_equal_approx(run._spell_combat.crit_multiplier_bonus(), [0.0, 0.10, 0.25][level - 1]) and is_equal_approx(run._spell_combat.crit_rate_bonus(), [0.0, 0.08, 0.15][level - 1]), "original fire damage/critical damage/critical rate passive values remain exact")
		check(debug.coverage.get("F02_learn" if level == 1 else "F02_upgrade", 0) == 1 and not debug.sparks.is_empty(), "learning or upgrading receives a short seal and small local gathering")
		var boss_reward := run.get_snapshot()
		boss_reward.phase = "artifact"
		renderer.sync_snapshot(boss_reward, projector)
		check(renderer.get_debug_state().mastery == debug.mastery, "completed mastery reward remains visible during the subsequent Boss treasure choice")
		var reduced := render(renderer, run, projector, {"reduced_motion": true})
		check(reduced.mastery == debug.mastery and reduced.sparks.is_empty(), "reduced mastery feedback preserves actual level without decorative sparks")
		advance(run, 0.9)
		check(render(renderer, run, projector).mastery.is_empty() and not renderer.visible and not run._owned_spell("F02").is_empty(), "mastery remains owned after all feedback ends, with no permanent aura")
	var already = fresh("F02", 2)
	check(render(renderer, already, projector).mastery.is_empty() and not renderer.visible, "attaching to an already-owned passive invents no learning event")
	already.phase = "reward"
	already.reward_choices = [already._choice("F02")]
	already.set_paused(true)
	var events: int = already.event_seq
	check(not already.choose_reward("F02") and already.event_seq == events and render(renderer, already, projector).mastery.is_empty(), "rejected paused reward adds no feedback or gameplay event")
	var maximum = fresh("F02", 3)
	maximum.phase = "reward"
	maximum.room_revision += 1
	maximum.reward_choices = [{"id": "F02"}]
	check(not maximum.choose_reward("F02", maximum.room_revision) and render(renderer, maximum, projector).mastery.is_empty(), "max-level rejected stale request adds no mastery flash")
	var replacement = fresh("F01")
	for id in ["F03", "F08", "F07", "F09", "F05", "F06", "F11"]: add_spell(replacement, id, 1)
	check(replacement.spells.size() == int(replacement._base.limits.slots), "replacement fixture fills the actual runtime slot count")
	check(award_mastery(replacement) and not replacement.pending_replacement.is_empty(), "real full-inventory choice requests replacement")
	check(render(renderer, replacement, projector).mastery.is_empty(), "replacement request alone is not successful learning")
	var request: int = replacement.pending_replacement.request_id
	check(replacement.confirm_spell_replacement(0, request, replacement.room_revision), "real replacement confirmation learns mastery")
	check(render(renderer, replacement, projector).mastery.size() == 1 and replacement._owned_spell("F01").is_empty(), "confirmed replacement alone creates the actual mastery flash")


func lifecycle_and_integration(renderer, projector) -> void:
	var run = fresh()
	run.cast_extra_spell("F10")
	advance(run, 0.10)
	var snapshot: Dictionary = run.get_snapshot()
	var doubled := snapshot.duplicate(true)
	doubled.effects.clear()
	for index in 128:
		var effect: Dictionary = snapshot.effects.filter(func(e): return e.kind == "shield_restore")[0].duplicate(true)
		effect.seq = 1000 + index
		doubled.effects.append(effect)
	renderer.sync_snapshot(doubled, projector)
	check(renderer.get_debug_state().restores.size() == 64 and renderer.get_debug_state().overflow == 64 and renderer.get_child_count() == 3 and renderer.get_debug_state().material_count == 2, "bounded completed-event batches retain three fixed nodes and two materials")
	var other := snapshot.duplicate(true)
	for effect in other.effects:
		if effect.kind == "shield_restore": effect.spell_id = "I08"
	renderer.sync_snapshot(other, projector)
	check(not renderer.visible and renderer.get_debug_state().restores.is_empty(), "synthetic other-source restoration is not claimed by F10")
	var missing := snapshot.duplicate(true)
	missing.erase("effects")
	check(not renderer.supports_snapshot(missing), "missing source effects retain legacy capability")
	renderer.sync_snapshot(missing, projector)
	check(not renderer.visible and renderer.get_debug_state().footprints.is_empty(), "missing capability clears new feedback")
	var ended := snapshot.duplicate(true)
	ended.phase = "complete"
	renderer.sync_snapshot(ended, projector)
	check(not renderer.visible and renderer.get_debug_state().sparks.is_empty(), "combat lifecycle exit clears support decoration")
	var view = View.new()
	root.add_child(view)
	await process_frame
	view.sync(snapshot)
	check(view.get_fire_support_debug_state().restores.size() == 1 and view.spell_vfx.get_debug_state().coverage.get("shield_restore", 0) == 0, "formal view owns F10 while legacy avoids duplicates")
	view.sync(other)
	check(view.spell_vfx.get_debug_state().coverage.get("shield_restore", 0) == 1, "other shield sources retain their original rendering")
	var mastery = fresh("F02")
	view.sync(mastery.get_snapshot())
	check(view.spell_vfx.get_debug_state().coverage.get("F02_passive", 0) == 0 and not view.fire_support_vfx.visible, "owned passive is quiet and does not duplicate the old ground aura")
	var old := mastery.get_snapshot()
	old.erase("effects")
	view.sync(old)
	check(view.spell_vfx.get_debug_state().coverage.get("F02_passive", 0) == 1, "missing support capability preserves original passive fallback")
	view.queue_free()
	await process_frame


func execute() -> void:
	var renderer = Support.new()
	root.add_child(renderer)
	await process_frame
	check(renderer.is_available() and renderer.get_child_count() == 3, "support module configures with fixed native batches")
	for shader: Shader in [Support.SURFACE_SHADER, Support.BODY_SHADER]:
		check(not shader.get_shader_uniform_list().is_empty(), "shader-language parse: " + shader.resource_path)
	var projector := Projector.new()
	guard_rules(renderer, projector)
	mastery_rules(renderer, projector)
	await lifecycle_and_integration(renderer, projector)
	renderer.queue_free()
	await process_frame
	var result := {"checks": checks, "failures": failures.size(), "details": failures, "real_route_fixtures": scenario_count,
		"scope": "Original Route F10 cast/partial/full/no-enemy/extra/zero/spent/overlap restoration, F02 real learn/upgrade/replacement/rejection/passive parameters, whole-snapshot/hooks/RNG read-only checks, projection/pause/reduced/cleanup/fallback/bounds, production-view integration. Entire core and old data must remain byte-identical. No new frozen gameplay model, interactive launch, screenshots, pixels/GPU/performance, natural route, export, Git or user visual acceptance."}
	if not Report.write_report(result, OUTPUT): failures.append("cannot write report")
	print("FIRE SUPPORT CHAIN fixtures=%d assertions=%d failures=%d" % [scenario_count, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
