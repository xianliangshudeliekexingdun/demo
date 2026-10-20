extends RefCounted
const Combat = preload("res://scripts/core/route_enemy_combat.gd")
const First = preload("res://scripts/core/first_room_run.gd")
var checks: int = 0
var failures: int = 0
var cadence_measurements: Array = []

class RoomHarness extends "res://scripts/core/first_room_run.gd":
	var room_index: int = 1


func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		push_error("Enemy pressure: " + label)


func run() -> int:
	stages_and_preserved_shapes()
	actor_owns_its_room_spec()
	actual_frequency_and_projectiles()
	explicit_parameter_replay()
	measure_shot_cadence()
	print("Enemy pressure checks: %d; failures: %d" % [checks, failures])
	return failures


func fixture(room_id: int = 1) -> Dictionary:
	var battle := RoomHarness.new()
	check(battle.configure().ok, "baseline source configures")
	battle.room_index = room_id
	battle.phase = "combat"
	battle.blocks.clear()
	battle.player.pos = Vector2(5, 0)
	battle.player.previous = battle.player.pos
	var combat := Combat.new()
	check(combat.configure(battle._base, battle._runtime).ok, "room stage source configures")
	return {"battle": battle, "combat": combat}


func advance(f: Dictionary, seconds: float):
	for tick in int(round(seconds * 120.0)):
		f.battle.time += 1.0 / 120.0
		f.battle.player.invulnerable = maxf(0.0, float(f.battle.player.invulnerable) - 1.0 / 120.0)
		f.combat.update(f.battle, 1.0 / 120.0)


func stages_and_preserved_shapes():
	var f := fixture()
	for type_id in ["M01", "M02", "M03", "M04", "EL01", "EL02", "EL02_GUARD"]:
		var first: Dictionary = f.combat.type_spec(type_id)
		check(first == f.combat.type_spec(type_id, 2).merged({"stat_room": 1}, true), "second teaching room keeps baseline " + type_id)
		check(first == f.combat.type_spec(type_id, 3).merged({"stat_room": 1}, true), "third teaching room keeps baseline " + type_id)
		var previous: Dictionary = first
		for room_id in range(1, int(f.combat.get_runtime().stat_stages[-1].to)+1):
			var spec: Dictionary = f.combat.type_spec(type_id, room_id)
			if room_id % 15 == 0:
				check(not bool(spec.get("nonboss", false)) and not spec.has("barrage"), "Boss placeholder keeps legacy attack rules %s room %d" % [type_id, room_id])
				continue
			check(spec.radius == first.radius and spec.warning == first.warning, "room %d preserves footprint and readable warning %s" % [room_id, type_id])
			check(is_equal_approx(float(spec.damage), float(spec.base_damage) * float(spec.room_damage_multiplier)) and spec.damage >= previous.damage, "room %d applies monotonic damage growth after pattern base %s" % [room_id, type_id])
			check(spec.health >= previous.health and spec.move_speed >= previous.move_speed and spec.attack_cycle <= previous.attack_cycle, "room %d stage difficulty is monotonic %s" % [room_id, type_id])
			check(spec.attack_cycle + 0.000001 >= f.combat._full_attack_duration(spec), "room %d retains complete attack plus recovery %s" % [room_id, type_id])
			check(spec.move_speed < f.battle.player.move_speed, "room %d normal walking remains faster than enemy chase %s" % [room_id, type_id])
			previous = spec
		check(float(previous.health) > float(first.health) and float(previous.move_speed) > float(first.move_speed), "late rooms increase durability and movement " + type_id)
		if first.has("projectile_speed"):
			check(float(previous.projectile_speed) > float(first.projectile_speed), "late actual enemy projectile speed rises " + type_id)
	check(f.combat.type_spec("M01", 15).health / f.combat.type_spec("M01").health > f.combat.type_spec("EL01", 15).health / f.combat.type_spec("EL01").health, "normal durability does not merely reuse elite health multiplier")
	check(f.combat.type_spec("M01", 4).health > f.combat.type_spec("M01", 3).health, "first pressure starts after three teaching rooms")
	check(f.combat.type_spec("invalid", 1).is_empty() and f.combat.type_spec("M01", int(f.combat.get_runtime().stat_stages[-1].to)+1).is_empty(), "unsupported type or room does not silently receive a fallback stage")


func actor_owns_its_room_spec():
	var f := fixture(15)
	var enemy: Dictionary = f.combat.make_actor(f.battle, "M03", Vector2.ZERO, 1)
	var expected: Dictionary = f.combat.type_spec("M03", 15)
	check(enemy.max_health == expected.health and enemy.stat_room == 15, "actor defaults to actual route room")
	f.battle.actors.append(enemy)
	f.battle.room_index = 1
	advance(f, 0.1)
	check(enemy.max_health == expected.health and enemy.combat_spec == expected, "an existing actor retains fixed birth-stage stats")
	var independent: Dictionary = f.combat.make_actor(f.battle, "M03", Vector2.ZERO, 2)
	check(independent.max_health == f.combat.type_spec("M03", 1).health, "new actor reads new room rather than stale component state")
	var explicit: Dictionary = f.combat.make_actor(f.battle, "M03", Vector2.ZERO, 3, 12)
	check(explicit.max_health == f.combat.type_spec("M03", 12).health, "explicit room override supports isolated probes")
	var copied: Dictionary = f.combat.type_spec("M03", 15)
	copied.health = 1.0
	check(enemy.combat_spec.health == expected.health and f.combat.type_spec("M03", 15).health == expected.health, "returned spec copies cannot corrupt cached or active stats")
	var early_f := fixture(1)
	var late_f := fixture(15)
	var early: Dictionary = early_f.combat.make_actor(early_f.battle, "M01", Vector2.ZERO, 1)
	var late: Dictionary = late_f.combat.make_actor(late_f.battle, "M01", Vector2.ZERO, 1)
	early.next_attack_at = 1000
	late.next_attack_at = 1000
	early_f.battle.actors = [early]
	late_f.battle.actors = [late]
	advance(early_f, 0.2)
	advance(late_f, 0.2)
	check(late.pos.length() > early.pos.length(), "actual chase displacement uses late movement speed")


func actual_frequency_and_projectiles():
	var counts: Array = []
	for room_id in [1, 15]:
		var f := fixture(room_id)
		var enemy: Dictionary = f.combat.make_actor(f.battle, "M02", Vector2.ZERO, 1)
		f.battle.actors = [enemy]
		advance(f, 0.7)
		check(enemy.phase == "warning" and f.combat.enemy_projectiles.is_empty(), "higher room does not skip readable flower windup")
		advance(f, 0.2)
		check(not f.combat.enemy_projectiles.is_empty(), "flower emits real projectile after warning")
		check(f.combat.enemy_projectiles[0].speed == f.combat.type_spec("M02", room_id).projectile_speed, "actual emitted spore uses room-specific speed")
		advance(f, 9.1)
		var count := 0
		for effect in f.battle.effects:
			if effect.kind == "enemy_warning": count += 1
		counts.append(count)
	check(int(counts[1]) > int(counts[0]), "late source attack cycle produces more actual warnings in equal time")


func explicit_parameter_replay():
	var f := fixture()
	var before := FileAccess.get_sha256(Combat.DATA_PATH)
	var replay: Dictionary = f.combat.get_runtime()
	var teaching: Dictionary = replay.stat_stages[0].duplicate(true)
	teaching.to = int(f.combat.get_runtime().stat_stages[-1].to)
	replay.stat_stages = [teaching]
	var probe := Combat.new()
	check(probe.configure(f.battle._base, f.battle._runtime, replay).ok, "explicit baseline configuration replays without touching canonical data")
	for type_id in ["M01", "M02", "M03", "M04", "EL01", "EL02", "EL02_GUARD"]:
		var baseline: Dictionary = f.combat.type_spec(type_id, 1)
		var last: Dictionary = probe.type_spec(type_id, 15)
		var raw: Dictionary = probe._types[type_id]
		check(last.health == raw.health and last.move_speed == raw.move_speed and last.attack_cycle == maxf(float(raw.attack_cycle), probe._full_attack_duration(raw)), "explicit baseline preserves Boss placeholder source " + type_id)
	check(FileAccess.get_sha256(Combat.DATA_PATH) == before, "offline parameter replay never rewrites game data")
	replay.stat_stages[0].from = 2
	check(not probe.configure(f.battle._base, f.battle._runtime, replay).ok, "gapped explicit stage configuration is rejected")


func measure_shot_cadence():
	for room_id in [1, 4, 7, 9, 15]:
		for type_id in ["M02", "EL02"]:
			var f := fixture(room_id)
			var enemy: Dictionary = f.combat.make_actor(f.battle, type_id, Vector2.ZERO, 1)
			f.battle.actors = [enemy]
			var observed_seq := 0
			var shots: Array = []
			for tick in 1200:
				advance(f, 1.0 / 120.0)
				for effect in f.battle.effects:
					if int(effect.seq) <= observed_seq: continue
					observed_seq = int(effect.seq)
					if effect.kind == "enemy_shot": shots.append(float(f.battle.time))
			var intervals: Array = []
			for index in range(1, shots.size()): intervals.append(float(shots[index]) - float(shots[index - 1]))
			var spec: Dictionary = f.combat.type_spec(type_id, room_id)
			check(not intervals.is_empty(), "real emitted projectile cadence observed")
			for interval in intervals:
				check(absf(float(interval) - float(spec.attack_cycle)) < 3.0 / 120.0, "real shot interval agrees with configured full-cycle cadence")
			cadence_measurements.append({"room": room_id, "type": type_id, "warning": spec.warning, "projectile_speed": spec.projectile_speed, "configured_cycle": spec.attack_cycle, "shot_times": shots, "observed_intervals": intervals})
