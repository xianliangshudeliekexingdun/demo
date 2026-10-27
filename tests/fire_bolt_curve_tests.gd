extends SceneTree
## Approved v2 flight rules: real curved sweeps, acceleration and size grades.
## Deterministic native fixtures only. Never renders or opens gameplay.
const Motion = preload("res://scripts/core/route_fire_bolt_motion.gd")
const Fire = preload("res://scripts/presentation/route_fire_bolt_vfx.gd")
const Rules = preload("res://tests/formal_fire_tests.gd")
const OUTPUT := "res://build/qa/fire-bolt-curve-v2-20261026/curve-results.json"
const Report = preload("res://tests/qa_report.gd")
var checks := 0
var failures: Array = []
var examples: Array = []

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
		push_error("F01 curved flight: " + label)


func near(a: float, b: float, label: String, tolerance: float = 0.00001) -> void:
	check(absf(a - b) <= tolerance, label)


func fresh(level: int = 1, distance: float = 3.0):
	var run = Rules.Fixture.new()
	check(run.configure({}, 20261026).ok and run.choose_initial("F01"), "actual route enters F01 fixture")
	run._spawn_done = true
	run.spawn_warnings.clear()
	run.blocks.clear()
	run.spells.clear()
	run.player.pos = Vector2.ZERO
	run.player.previous = Vector2.ZERO
	run.player.attack = 100.0
	run.player.crit_rate = 0.0
	var spell: Dictionary = run._new_spell("F01")
	spell.level = level
	run._refresh_spell(spell)
	spell.remaining = 9999.0
	run.spells.append(spell)
	var target: Dictionary = run._enemy_combat.make_actor(run, "M01", Vector2(0, distance), 77)
	target.health = 100000.0
	target.max_health = target.health
	run.actors = [target]
	return run


func cast(run) -> void:
	var spell: Dictionary = run.spells[0]
	run._spell_combat._cast(run, spell, run.get_spell_stats(spell), run.actors[0], true, 1.0)
	spell.remaining = 9999.0


func advance(run, seconds: float) -> void:
	for tick in roundi(seconds * 120.0): run.step(1.0 / 120.0)


func execute() -> void:
	geometry_and_validation()
	actual_flight_and_lock()
	curved_wall_and_interceptor()
	continuous_moving_target_and_range()
	damage_levels_and_cleanup()
	await visual_integration()
	var report := {"checks": checks, "failures": failures.size(), "details": failures, "examples": examples,
		"scope": "User-authorized native F01 curved launch/acceleration, fixed target, continuous wall/enemy/relative-motion collision, real range/terminal time, level budgets and released visual grades, real world-trail reconstruction and pause/reduced motion. No pixels, GPU composition, performance, natural route, save or user visual acceptance."}
	if not Report.write_report(report, OUTPUT):
		failures.append("QA report could not be written")
	print("FIRE BOLT CURVE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func geometry_and_validation() -> void:
	var run = fresh()
	var rules: Dictionary = run._spell_combat.runtime.fire.bolt_flight
	check(Motion.validate(rules), "canonical flight data validates")
	for key in ["curve_seconds", "acceleration_mps2", "cruise_speed_mps", "length_samples"]:
		var invalid := rules.duplicate(true)
		invalid[key] = 0.0
		check(not Motion.validate(invalid), "invalid physical parameter rejected: " + key)
	var invalid := rules.duplicate(true)
	invalid.start_speed_mps = NAN
	check(not Motion.validate(invalid), "non-finite motion data rejected")
	for bearing in 8:
		for distance in [0.2, 1.0, 3.0, 8.0]:
			var target := Vector2.from_angle(TAU * float(bearing) / 8.0) * float(distance)
			var f := Motion.build(Vector2.ZERO, target, 1.0, rules)
			var end := Motion.position_at(f, float(f.curve_seconds))
			check(Motion.position_at(f, 0.0).is_zero_approx(), "all headings begin at the real caster position")
			check(Motion.velocity_at(f, 0.0).is_finite() and Motion.velocity_at(f, float(f.curve_seconds)).is_finite(), "close/far flight has finite endpoint velocities")
			check(Motion.velocity_at(f, float(f.curve_seconds) - 0.0000001).is_equal_approx(Motion.velocity_at(f, float(f.curve_seconds))), "turn-to-straight junction has continuous velocity")
			check((target - end).normalized().is_equal_approx(f.direction), "outgoing line points to the released target")
			var previous := float(f.turn_speed)
			for sample in 8:
				var velocity := Motion.velocity_at(f, float(f.curve_seconds) + float(sample) * 0.04)
				check(velocity.length() >= previous - 0.00001 and velocity.length() <= float(f.cruise_speed) + 0.00001, "post-turn speed increases to a finite cap")
				previous = velocity.length()


func actual_flight_and_lock() -> void:
	var run = fresh()
	var rng: int = run._rng.state
	cast(run)
	check(run._rng.state == rng, "side selection consumes no gameplay RNG")
	var p: Dictionary = run.projectiles[0]
	var flight: Dictionary = p.flight.duplicate(true)
	var original_target: Vector2 = run.actors[0].pos
	advance(run, 0.1)
	check(not run.projectiles.is_empty() and float(run.projectiles[0].speed) < 8.0, "slow side-out phase remains a visible real projectile")
	check(absf(float(run.projectiles[0].pos.x)) > 0.10 and run.actors[0].health == 100000.0, "slow arc has actual lateral displacement before any hit")
	run.actors[0].pos = Vector2(4, 3)
	run.actors[0].previous = run.actors[0].pos
	advance(run, 0.16)
	check(not run.projectiles.is_empty() and run.projectiles[0].speed > 15.0, "the real projectile accelerates strongly after turning")
	check(run.projectiles[0].flight.target_pos == original_target and run.projectiles[0].flight == flight, "moving target cannot steer or rewrite released trajectory")
	advance(run, 0.4)
	var events: Array = run.get_snapshot().fire_bolt_ends
	check(events.size() == 1 and events[0].reason == "expired" and run.actors[0].health == 100000.0, "dodged fixed trajectory expires without a false hit")
	if not events.is_empty():
		near(float(events[0].travelled), 8.0, "range is consumed by actual traveled path", 0.00001)
		check(float(events[0].time) > 0.4 and float(events[0].time) < 0.6, "full-range flight has the approved staged timing")
		examples.append({"kind": "range_end", "age": events[0].age, "time": events[0].time, "travelled": events[0].travelled, "pos": events[0].pos})
	var standard = fresh()
	cast(standard)
	advance(standard, 0.6)
	var impact: Dictionary = standard.get_snapshot().fire_bolt_ends[0]
	check(impact.reason == "enemy" and float(impact.time) > 0.22 and float(impact.time) < 0.4, "ordinary-distance contact follows the slow turn then fast impact")
	examples.append({"kind": "3m_enemy_contact", "time": impact.time, "age": impact.age, "pos": impact.pos})


func curved_wall_and_interceptor() -> void:
	var wall = fresh()
	cast(wall)
	var along: Vector2 = Motion.position_at(wall.projectiles[0].flight, 0.15)
	check(absf(along.x) > 0.2, "fixture obstacle lies away from the old straight path")
	wall.blocks = [{"center": along, "size": Vector2(0.02, 0.02)}]
	check(not wall._spell_combat.legal_target(wall, wall.spells[0]).is_empty(), "side obstacle leaves the original direct targeting line clear")
	advance(wall, 0.6)
	var facts: Array = wall.get_snapshot().fire_bolt_ends
	check(facts.size() == 1 and facts[0].reason == "wall", "actual curved sweep collides with the side obstacle")
	check(wall.actors[0].health == 100000.0 and wall.get_snapshot().spell_burns.is_empty(), "wall scatter cannot deal a hidden area hit or ignite the target")
	var intercepted = fresh()
	cast(intercepted)
	var actor: Dictionary = intercepted.actors[0].duplicate(true)
	actor.id = 88
	actor.radius = 0.01
	actor.pos = Motion.position_at(intercepted.projectiles[0].flight, 0.15)
	actor.previous = actor.pos
	intercepted.actors.append(actor)
	advance(intercepted, 0.6)
	facts = intercepted.get_snapshot().fire_bolt_ends
	check(facts.size() == 1 and facts[0].actor_id == 88, "first enemy on the curved path consumes the nonpiercing shot")
	check(actor.health < 100000.0 and intercepted.actors[0].health == 100000.0, "curved collision applies exactly the real local explosion")


func continuous_moving_target_and_range() -> void:
	var run = fresh()
	cast(run)
	var p: Dictionary = run.projectiles[0]
	p.age = 0.38
	p.pos = Motion.position_at(p.flight, p.age)
	p.range = 30.0
	p.travelled = 5.0
	var direction: Vector2 = p.flight.direction
	var normal := Vector2(-direction.y, direction.x)
	var center: Vector2 = p.pos + direction * 1.6
	run.actors[0].previous = center - normal * 2.0
	run.actors[0].pos = center + normal * 2.0
	run.time = 0.48
	run._spell_combat._update_projectiles(run, 0.1)
	var ends: Array = run.get_snapshot().fire_bolt_ends
	check(ends.size() == 1 and ends[0].reason == "enemy", "fast flight sweeps moving enemies across all relative substeps")
	if not ends.is_empty():
		check(float(ends[0].time) >= 0.38 and float(ends[0].time) <= 0.48, "moving hit records its actual substep time")
		check(ends[0].normal.is_normalized(), "moving hit records a valid contact surface normal")
	var close = fresh(1, 0.1)
	cast(close)
	advance(close, 0.03)
	check(close.get_snapshot().fire_bolt_ends.size() == 1, "already-touching target can consume the real shot during launch")
	var coincident = fresh(1, 0.0)
	cast(coincident)
	advance(coincident, 0.03)
	var coincident_ends: Array = coincident.get_snapshot().fire_bolt_ends
	check(coincident_ends.size() == 1 and coincident_ends[0].normal.is_normalized(), "zero-distance launch still records a finite unit contact normal")
	for fps in [30, 60, 144]:
		var stable = fresh()
		cast(stable)
		for frame in fps: stable.step(1.0 / float(fps))
		var event: Dictionary = stable.get_snapshot().fire_bolt_ends[0]
		near(float(event.time), 0.0 if examples.is_empty() else float(examples[1].time), "fixed-step contact time is stable across caller frame rates", 0.00001)


func damage_levels_and_cleanup() -> void:
	for level in range(1, 4):
		var run = fresh(level)
		cast(run)
		var source: Dictionary = run.projectiles[0].duplicate(true)
		advance(run, 0.6)
		var count := 2 if level == 3 else 1
		check(run.get_snapshot().fire_bolt_ends.size() == count, "level %d retains its actual bolt count" % level)
		near(100000.0 - float(run.actors[0].health), [100.0, 145.0, 250.0][level - 1], "unchanged direct damage budget at level %d" % level, 0.001)
		near(float(source.radius), 0.15, "visible growth does not enlarge collision at level %d" % level)
		near(float(source.blast_radius), [0.8, 1.15, 1.3][level - 1], "original explosion radius retained at level %d" % level)
		if level == 3:
			var ends: Array = run.get_snapshot().fire_bolt_ends
			check(float(ends[1].born_at) - float(ends[0].born_at) >= 0.18 - 0.00001, "second bolt retains its original independent release delay")
		var critical = fresh(level)
		critical.player.crit_rate = 1.0
		cast(critical)
		advance(critical, 0.6)
		check(critical.get_snapshot().artifact_patches.size() == (0 if level == 1 else 1), "only qualified natural critical creates one growth patch")
	var frozen = fresh(3)
	cast(frozen)
	advance(frozen, 0.1)
	var before: Dictionary = frozen.get_snapshot()
	frozen.set_paused(true)
	advance(frozen, 0.5)
	check(frozen.get_snapshot().projectiles == before.projectiles, "pause freezes actual curved flight and acceleration")
	frozen._stop_combat()
	check(frozen.projectiles.is_empty() and frozen.get_snapshot().fire_bolt_ends.is_empty(), "room stop removes live curves and their old facts")


func visual_integration() -> void:
	var renderer = Fire.new()
	root.add_child(renderer)
	await process_frame
	var projector := Projector.new()
	for level in range(1, 4):
		var run = fresh(level)
		cast(run)
		run.spells[0].level = 1 # Released size must not follow later slot changes.
		advance(run, 0.1)
		var source: Dictionary = run.get_snapshot()
		var original := source.duplicate(true)
		renderer.sync_snapshot(source, projector)
		var state: Dictionary = renderer.get_debug_state()
		check(source == original and state.heads == 1 and state.paths[0].curved, "actual curved source drives one read-only head and path")
		near(float(state.paths[0].visual_scale), [1.5, 1.8, 2.1][level - 1], "released level owns the visible size")
		var path: PackedVector2Array = state.paths[0].world_path
		check(path[0].is_equal_approx(source.projectiles[0].pos), "trail begins at the exact authoritative curved head")
		var contains_arc := false
		for point: Vector2 in path: contains_arc = contains_arc or absf(point.x) > 0.1
		check(contains_arc, "world trail contains the real side arc")
		var before := state.duplicate(true)
		projector.offset += Vector2(17, 23)
		renderer.sync_snapshot(source, projector)
		check(renderer.get_debug_state().paths == before.paths, "camera projection cannot straighten the stored arc")
		renderer.sync_snapshot(source, projector, {"reduced_motion": true})
		check(renderer.get_debug_state().paths == before.paths and source == original, "reduced motion preserves real curved travel")
		projector.offset = Vector2(640, 360)
		if level == 1:
			var previous := float(state.paths[0].speed_fraction)
			advance(run, 0.15)
			renderer.sync_snapshot(run.get_snapshot(), projector)
			check(renderer.get_debug_state().paths[0].speed_fraction > previous, "accelerating source increases its visible flame stretch")
	renderer.queue_free()
	await process_frame
