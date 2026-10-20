extends RefCounted
## Controlled rule fixtures for design24; no natural route, scene or save.
const Combat = preload("res://scripts/core/route_enemy_combat.gd")
const First = preload("res://scripts/core/first_room_run.gd")
const Route = preload("res://scripts/core/courtyard_route_run.gd")
var checks := 0
var failures := 0

class Harness extends "res://scripts/core/first_room_run.gd":
	var room_index := 59
	var frozen := false
	func get_ice_control_state(_actor: Dictionary) -> Dictionary:
		return {"frozen": frozen}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("Damage growth: " + label)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001

func fixture(room: int = 59) -> Dictionary:
	var run := Harness.new()
	check(run.configure().ok, "source configures")
	run.room_index = room
	run.phase = "combat"
	run.blocks.clear()
	run.player.pos = Vector2(5, 0)
	run.player.previous = run.player.pos
	run.player.health = 100000.0
	run.player.shield = 0.0
	var combat := Combat.new()
	check(combat.configure(run._base, run._runtime, {}, 60).ok, "room factors configure")
	return {"run": run, "combat": combat}

func actor(f: Dictionary, id: String = "M02", uid: int = 1) -> Dictionary:
	var a: Dictionary = f.combat.make_actor(f.run, id, Vector2.ZERO, uid)
	f.run.actors.append(a)
	return a

func advance(f: Dictionary, seconds: float, fps: int = 120) -> void:
	for tick in roundi(seconds * fps):
		f.run.time += 1.0 / float(fps)
		f.run.player.invulnerable = maxf(0.0, float(f.run.player.invulnerable) - 1.0 / float(fps))
		f.combat.update(f.run, 1.0 / float(fps))

func run() -> int:
	growth_order_and_snapshots()
	actual_damage_transaction()
	locked_slow_trains()
	reversed_second_sweep()
	whole_reservation_and_spacing()
	boss_growth_and_summon_budget()
	print("Damage growth rules: %d checks; %d failures" % [checks, failures])
	return failures

func growth_order_and_snapshots() -> void:
	var f := fixture()
	var rooms := [1, 4, 6, 9, 14, 16, 21, 29, 31, 36, 44, 46, 51, 59]
	var damage := [1.0, 1.15, 1.3, 1.45, 1.6, 1.9, 2.2, 2.5, 2.8, 3.1, 3.4, 3.7, 4.0, 4.3]
	var body := [1.0, 1.1, 1.2, 1.3, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4, 2.6, 2.8, 3.0, 3.2]
	var base := {"M01": 30.0, "M02": 28.0, "M03": 38.0, "M04": 32.0, "M05": 18.0, "EL01": 40.0, "EL02": 38.0, "EL02_GUARD": 41.8}
	for i in rooms.size():
		for id in base:
			var s: Dictionary = f.combat.type_spec(id, rooms[i])
			check(near(s.damage, base[id] * damage[i]), "base plus one room factor %s/%d" % [id, rooms[i]])
			if id != "EL02_GUARD":
				var initial_body := 24.0 if str(id).begins_with("EL") else (18.0 if id == "M03" else 12.0)
				check(near(s.body_damage, initial_body * body[i]), "contact base replaces old final arrays %s/%d" % [id, rooms[i]])
		for id in ["M06", "M07"]:
			var s: Dictionary = f.combat.type_spec(id, rooms[i])
			if not bool(s.attack_disabled):
				check(near(s.damage, 16.0 * damage[i]), "new pattern damage scales after override " + id)
	for room in [1, 2, 3]:
		var s: Dictionary = f.combat.type_spec("M02", room)
		check(s.barrage.count == 1 and near(s.projectile_speed, 3.2) and near(s.damage, 28), "first three teaching rooms preserve slow single shot")
	var replay: Dictionary = f.combat.get_runtime()
	replay.stat_stages[-1].normal.damage = 2.0
	replay.stat_stages[-1].normal.body_damage = 1.5
	var probe := Combat.new()
	check(probe.configure(f.run._base, f.run._runtime, replay).ok, "alternate room damage knobs configure in memory")
	check(near(probe.type_spec("M02", 59).damage, 56.0) and near(probe.type_spec("M05", 59).damage, 36.0), "changing room knob reaches both pattern bases without legacy double multiplication")
	check(near(probe.type_spec("M02", 59).body_damage, 18.0), "body room knob multiplies twelve, not old twenty-four")
	check(near(f.combat.type_spec("M02", 59).damage, 120.4) and near(f.combat._types.M02.damage, 28), "replays and room cache never mutate shared base")
	replay.stat_stages[-1].normal.damage = -1.0
	check(not probe.configure(f.run._base, f.run._runtime, replay).ok, "invalid growth fails configuration")
	var a := actor(f)
	f.run.room_index = 4
	advance(f, 0.85)
	check(near(a.damage, 120.4) and near(f.combat.enemy_projectiles[0].damage, 120.4), "actor and released projectile keep birth-room damage")
	var copied: Dictionary = f.combat.type_spec("M02", 59)
	copied.damage = 1
	check(near(a.damage, 120.4) and near(f.combat.type_spec("M02", 59).damage, 120.4), "returned spec mutation cannot rewrite actor or catalog")

func actual_damage_transaction() -> void:
	var f := fixture()
	actor(f)
	f.run.player.health = 300.0
	f.run.player.shield = 100.0
	advance(f, 1.2)
	check(near(f.run.damage_taken, 120.4) and near(f.run.player.shield, 0) and near(f.run.player.health, 279.6), "fast enemy bullet actually applies scaled damage shield first")
	check(float(f.run.player.invulnerable) > 0, "scaled projectile retains common hurt protection")
	var run := Route.new()
	check(run.configure().ok and run.choose_initial("F01"), "real route damage hook configures")
	run._enter_room(59)
	run.actors.clear()
	run.spawn_warnings.clear()
	run.blocks.clear()
	run.player.pos = Vector2(5, 0)
	run.player.previous = run.player.pos
	for id in ["GU10", "GU12"]:
		run._artifact_combat._owned.append(id)
		run._artifact_combat.apply_acquisition(run, id)
	f = {"run": run, "combat": run._enemy_combat}
	actor(f)
	var multiplier: float = run._artifact_combat.incoming_damage_multiplier(run, "projectile")
	advance(f, 1.2)
	check(near(run.damage_taken, 120.4 * multiplier), "room growth precedes existing projectile defense transaction")
	f = fixture()
	actor(f)
	advance(f, 0.5)
	f.run.player.pos = Vector2(5, 4)
	f.run.player.previous = f.run.player.pos
	advance(f, 0.7)
	check(near(f.run.damage_taken, 0), "ordinary movement still avoids locked fast first shot")

func locked_slow_trains() -> void:
	for id in ["M05", "M06"]:
		var f := fixture()
		var a := actor(f, id)
		advance(f, 1.0 / 120.0)
		var s: Dictionary = a.combat_spec
		var direction: Vector2 = a.barrage_direction
		var angles: Array = a.barrage_angles.duplicate()
		advance(f, float(s.warning))
		var first := int(f.combat._next_projectile) - 1
		var next_gap: Vector2 = a.get("ring_next_gap", Vector2.ZERO)
		check(first == (9 if id == "M05" else 17), "first release is one subvolley " + id)
		f.run.player.pos = Vector2(-3, 5)
		f.run.player.previous = f.run.player.pos
		var wait := float(a.barrage_shot_remaining)
		f.run.frozen = true
		advance(f, 0.5)
		check(near(a.barrage_shot_remaining, wait) and int(f.combat._next_projectile) - 1 == first, "frozen source preserves whole train waiting " + id)
		f.run.frozen = false
		advance(f, wait - 0.04)
		check(a.danger.get("kind", "") == ("fan" if id == "M05" else "ring") and int(f.combat._next_projectile) - 1 == first, "second subvolley has pre-release warning " + id)
		check(a.barrage_direction == direction and a.barrage_angles == angles, "all slow subvolleys keep locked lanes and gap " + id)
		advance(f, 0.05)
		check(int(f.combat._next_projectile) - 1 == first * 2, "second whole subvolley emits " + id)
		if id == "M06":
			check(a.ring_next_gap == next_gap, "second ring cannot rotate and close first gap")
		else:
			advance(f, 0.55)
			check(int(f.combat._next_projectile) - 1 == 27, "third slow fan emits from same source")
		check(a.phase == "recover" and int(a.reserved_projectiles) == 0, "complete slow train enters full recovery " + id)
		check(f.combat.enemy_projectiles.any(func(p): return p.source_id == a.id), "released slow bullets continue through recovery")

func reversed_second_sweep() -> void:
	var f := fixture()
	var a := actor(f, "M07")
	advance(f, 1.0 / 120.0)
	var original: Array = a.barrage_angles.duplicate()
	advance(f, 2.2)
	check(int(f.combat._next_projectile) - 1 == 11 and a.danger.is_empty(), "first sweep finishes then leaves a gap before second warning")
	advance(f, 0.21)
	var reverse: Array = original.duplicate()
	reverse.reverse()
	check(a.danger.get("kind", "") == "sweep" and int(a.danger.get("volley_index", -1)) == 1 and a.barrage_angles == reverse, "second sweep warns reversed fixed order")
	check(float(a.danger.remaining) > 0.58 and int(f.combat._next_projectile) - 1 == 11, "second sweep has its full warning before any second-round bullet")
	var remaining := float(a.barrage_shot_remaining)
	f.run.frozen = true
	advance(f, 0.25)
	check(near(a.barrage_shot_remaining, remaining) and int(a.reserved_projectiles) == 11, "freeze pauses second-sweep warning and reserves all eleven")
	f.run.frozen = false
	advance(f, 0.55)
	check(int(f.combat._next_projectile) - 1 == 11, "resuming cannot skip the remaining followup warning")
	advance(f, 1.3)
	check(int(f.combat._next_projectile) - 1 == 22 and a.phase == "recover", "second fast sweep completes without restarting early")
	for fps in [30, 60, 120]:
		f = fixture()
		a = actor(f, "M07")
		advance(f, 4.7, fps)
		check(int(f.combat._next_projectile) - 1 == 22 and int(a.reserved_projectiles) == 0, "all double-sweep bullets at update chunk %d" % fps)
	for id in ["M05", "M06", "M07"]:
		f = fixture()
		a = actor(f, id)
		advance(f, 1.08)
		var emitted := int(f.combat._next_projectile)
		f.combat.interrupt_by_push(a, Vector2(-1, 0))
		advance(f, 0.4)
		check(int(f.combat._next_projectile) == emitted and int(a.reserved_projectiles) == 0 and a.danger.is_empty(), "push cancels all remaining subvolleys " + id)

func whole_reservation_and_spacing() -> void:
	var f := fixture()
	var a := actor(f, "M02", 1)
	var b := actor(f, "M02", 2)
	b.pos = Vector2(0, 1)
	advance(f, 0.01)
	check(a.phase == "warning" and b.phase == "chase", "fast sources cannot start warnings together")
	advance(f, 0.33)
	check(b.phase == "chase", "fast source waits full .35 spacing")
	advance(f, 0.04)
	check(b.phase == "warning" and float(b.warning_remaining) > 0.77, "staggered source still receives complete warning")
	f = fixture()
	a = actor(f, "M06", 1)
	b = actor(f, "M05", 2)
	b.pos = Vector2(0, -1)
	a.combat_spec.projectile_cap = 60
	b.combat_spec.projectile_cap = 60
	advance(f, 0.01)
	f.run.frozen = true
	advance(f, 0.4)
	f.run.frozen = false
	advance(f, 0.01)
	check(int(a.reserved_projectiles) == 34 and b.phase == "chase" and int(b.reserved_projectiles) == 0, "frozen ring reservation blocks twenty-seven-shot fan as a whole")
	a.health = 0
	advance(f, 0.3)
	check(b.phase == "warning" and int(b.reserved_projectiles) == 27, "dead source frees complete reservation for waiting train")
	for room in [14, 29, 44, 59]:
		f = fixture(room)
		a = actor(f, "M02")
		f.run.player.pos = Vector2(2, 0)
		f.run.player.previous = f.run.player.pos
		advance(f, 0.01)
		check(a.phase == "chase" and a.pos.x < 0, "fast point source creates minimum casting distance at room %d" % room)

func boss_growth_and_summon_budget() -> void:
	var f := fixture()
	for room in [15, 30, 45, 60]:
		var definition: Dictionary = f.combat.bosses.catalog.for_room(room)
		var s: Dictionary = f.combat.type_spec(str(definition.id), room)
		var factor: float = {15: 1.25, 30: 1.5, 45: 1.8, 60: 2.2}[room]
		check(near(s.body_damage, float(definition.body_damage) * factor), "Boss body uses its dedicated factor once %d" % room)
		for i in definition.phases.size():
			for key in definition.phases[i].patterns:
				var raw: Dictionary = definition.phases[i].patterns[key]
				var resolved: Dictionary = s.definition.phases[i].patterns[key]
				check(near(resolved.damage, float(raw.damage) * factor) and near(resolved.base_damage, raw.damage), "Boss skill base and dedicated growth %d/%s" % [room, key])
	var boss: Dictionary = f.combat.make_actor(f.run, "BOSS03", Vector2(0, 6), 1, 60)
	var add := actor(f, "M02", 2)
	f.run.actors.append(boss)
	check(near(add.damage, 120.4) and near(add.combat_spec.room_damage_multiplier, 4.3), "final summons use room59 growth without Boss factor")
	f.combat.enemy_projectiles.resize(188)
	check(not f.combat._barrage.reserve(f.combat, f.run, add, add.combat_spec) and int(add.reserved_projectiles) == 0, "ordinary summon cannot exceed Boss room shared cap")
	f.combat.enemy_projectiles.resize(187)
	check(f.combat._barrage.reserve(f.combat, f.run, add, add.combat_spec) and int(add.reserved_projectiles) == 5, "summon reserves full five at exact shared Boss capacity")
	check(f.combat.configure(f.run._base, f.run._runtime, {}, 60).ok and near(f.combat.type_spec("BOSS03", 60).body_damage, 105.6), "reconfiguration never compounds Boss base growth")
