extends RefCounted
## Fast core fixtures only. No interactive session, rendering or natural route.

const Route = preload("res://scripts/core/courtyard_route_run.gd")
const Catalog = preload("res://scripts/core/courtyard_route_catalog.gd")
const Combat = preload("res://scripts/core/route_enemy_combat.gd")
var checks := 0
var failures := 0

class Harness extends "res://scripts/core/first_room_run.gd":
	var room_index := 1
	var frozen := false
	func get_ice_control_state(_actor: Dictionary) -> Dictionary:
		return {"frozen": frozen}


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("Nonboss: " + label)


func run() -> int:
	encounters_and_baseline()
	patterns_and_locks()
	reservation_and_interruptions()
	remaining_attack_boundaries()
	spawn_constraints()
	contact_rules()
	contact_damage_path()
	print("Nonboss checks: %d; failures: %d" % [checks, failures])
	return failures


func fixture(room_id: int = 59) -> Dictionary:
	var battle := Harness.new()
	check(battle.configure().ok, "standalone source loads for rule fixture")
	battle.phase = "combat"
	battle.room_index = room_id
	battle.blocks.clear()
	battle.actors.clear()
	battle.player.pos = Vector2(5, 0)
	battle.player.previous = battle.player.pos
	var combat := Combat.new()
	check(combat.configure(battle._base, battle._runtime, {}, 60).ok, "full route enemy rules load")
	return {"run": battle, "combat": combat}


func add_actor(f: Dictionary, type_id: String, id: int = 1, pos: Vector2 = Vector2.ZERO) -> Dictionary:
	var actor: Dictionary = f.combat.make_actor(f.run, type_id, pos, id)
	f.run.actors.append(actor)
	return actor


func advance(f: Dictionary, seconds: float, fps: int = 120) -> void:
	for tick in int(round(seconds * fps)):
		f.run.time += 1.0 / float(fps)
		f.run.player.invulnerable = maxf(0.0, float(f.run.player.invulnerable) - 1.0 / float(fps))
		f.combat.update(f.run, 1.0 / float(fps))


func encounters_and_baseline() -> void:
	var catalog := Catalog.new()
	check(catalog.load_catalog().ok, "authored route validates")
	var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/nonboss_previous_runtime.json"))
	var runtime: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Combat.DATA_PATH))
	var authored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Catalog.DATA_PATH))
	var retained: Array = runtime.stat_stages.duplicate(true)
	for stage in retained:
		for category in ["normal", "elite"]:
			stage[category].erase("damage")
			stage[category].erase("body_damage")
	check(retained == before.enemy_runtime.stat_stages, "original health/walk/cadence anchors remain exact; design24 adds damage factors")
	for id in before.enemy_runtime.types:
		check(runtime.types[id] == before.enemy_runtime.types[id], "legacy behavior definition unchanged " + str(id))
	check(runtime.north_spawn == before.enemy_runtime.north_spawn, "Boss north anchors retain original positions")
	for key in ["reward_rooms", "artifact_reward_rooms", "reward_pickup"]:
		if key == "reward_pickup":
			check(authored[key] == before[key], "original pickup geometry unchanged")
		else:
			check(authored[key].filter(func(room): return int(room) % 15 != 0) == before[key].filter(func(room): return int(room) % 15 != 0), "non-Boss reward nodes unchanged " + str(key))
	var f := fixture()
	var totals := [0, 0, 0, 0]
	var hp := [0.0, 0.0, 0.0, 0.0]
	var all_count := 0
	for room_id in range(1, 61):
		var room: Dictionary = catalog.get_room(room_id)
		var boss: bool = room_id % 15 == 0
		check(bool(room.nonboss) != boss, "correct non-Boss scope room %d" % room_id)
		if boss:
			check(authored.encounters_by_room[str(room_id)].kind == "boss" and authored.encounters_by_room[str(room_id)].packs.size() == 1, "approved Boss replaces only its placeholder %d" % room_id)
			check(room.geometry.spawn.north_band.size() == 10 and room.role_limits.is_empty(), "Boss limits and spawn geometry stay legacy")
			for id in before.enemy_runtime.types:
				var spec: Dictionary = f.combat.type_spec(str(id), room_id)
				check(not spec.has("barrage") and not spec.has("body_damage"), "historical ordinary specs on Boss rooms stay unchanged; authored adds explicitly use room59")
		else:
			var index := int((room_id - 1) / 15)
			check(room.geometry.spawn.north_band.size() == 15, "non-Boss has fifteen candidate anchors")
			check(int(room.alive_cap) == [6, 8, 10, 12][index], "four approved live caps")
			check(int(room.max_batches) == [2, 3, 3, 4][index], "four approved batch caps")
		for pack in room.encounter.packs:
			for id in pack:
				var count := int(pack[id])
				all_count += count
				if not boss:
					var index := int((room_id - 1) / 15)
					totals[index] += count
					hp[index] += float(f.combat.type_spec(str(id), room_id).health) * count
	check(totals == [104, 195, 266, 364] and all_count == 933, "929 unchanged non-Boss enemies plus four Bosses")
	for index in range(4):
		check(absf(float(hp[index]) - float([129026, 570614, 1029773, 1647859][index])) < 0.01, "same-room health compensation budget stage %d" % index)
	check(is_equal_approx(float(f.combat.type_spec("M05", 59).health), float(f.combat._types.M02.health) * 32.0 * 0.7), "new fan health uses original flower anchor once")
	check(is_equal_approx(float(f.combat.type_spec("M06", 59).health), float(f.combat.type_spec("M04", 59).health) * 0.7), "ring health uses same-room mark caster")


func patterns_and_locks() -> void:
	for index in range(4):
		for id in ["M02", "M05", "M06", "M07"]:
			if (id == "M06" and index == 0) or (id == "M07" and index < 2):
				continue
			var f := fixture([14, 29, 44, 59][index])
			var actor := add_actor(f, id)
			advance(f, 1.0 / 120.0)
			var spec: Dictionary = actor.combat_spec
			check(actor.phase == "warning" and f.combat.enemy_projectiles.is_empty(), "full windup starts before any shot " + id)
			var expected: int = {"M02": [2, 3, 4, 5], "M05": [3, 10, 14, 27], "M06": [0, 9, 26, 34], "M07": [0, 0, 9, 22]}[id][index]
			check(int(actor.reserved_projectiles) == expected, "whole volley reserved before warning " + id)
			var target: Vector2 = actor.attack_to
			if id != "M02":
				f.run.player.pos = Vector2(5, 4)
				f.run.player.previous = f.run.player.pos
			advance(f, float(spec.warning) - 0.05)
			check(actor.phase == "warning" and actor.attack_to == target, "warning locks actual pattern center " + id)
			advance(f, 0.05)
			var emitted := int(f.combat._next_projectile) - 1
			var first_count := int(spec.barrage.count) - int(spec.barrage.get("omitted_adjacent_spokes", 0))
			check(emitted == (first_count if id in ["M05", "M06"] else 1), "actual initial release count " + id)
			if id == "M05":
				var shots: Array = f.combat.get_projectiles()
				check(absf(rad_to_deg(shots[0].direction.angle_to(shots[1].direction))) > 21.99, "fan keeps twenty-two-degree spacing")
			if id == "M06":
				for shot in f.combat.get_projectiles():
					check(absf(rad_to_deg(Vector2.RIGHT.angle_to(shot.direction))) > 360.0 / float(spec.barrage.count) * 1.9, "ring omits three adjacent spokes facing locked player")
				check(absf(rad_to_deg(Vector2.RIGHT.angle_to(actor.ring_next_gap))) - 30.0 < 0.0001, "next emitted ring rotates gap thirty degrees")
			if id == "M02" and expected > 1:
				f.run.player.pos = Vector2(0, 5)
				f.run.player.previous = f.run.player.pos
				advance(f, 0.08)
				check(actor.danger.get("kind", "") == "ray" and actor.barrage_direction == Vector2.DOWN, "followup aimed shot relocks with its own warning")
			advance(f, f.combat._barrage.emission_duration(spec) + 0.02)
			check(int(f.combat._next_projectile) - 1 == expected and int(actor.reserved_projectiles) == 0 and actor.phase == "recover", "all subvolleys release the whole reservation " + id)
	var f := fixture(44)
	var sweep := add_actor(f, "M07")
	advance(f, 0.01)
	var forward: Array = sweep.barrage_angles.duplicate()
	advance(f, 2.3)
	sweep.phase = "chase"
	sweep.next_attack_at = 0.0
	advance(f, 0.01)
	var reverse: Array = forward.duplicate()
	reverse.reverse()
	check(sweep.barrage_angles == reverse, "sweep alternates direction on next volley")
	f = fixture()
	var near := add_actor(f, "M05", 1, Vector2(4, 0))
	advance(f, 0.1)
	check(near.phase == "chase" and near.pos.x < 4.0, "new curtain sources create casting distance before warning")


func reservation_and_interruptions() -> void:
	var f := fixture()
	var actor := add_actor(f, "M07")
	var total := int(actor.combat_spec.projectile_cap)
	var size := int(f.combat._barrage.volley_size(actor.combat_spec))
	var occupied := total - size + 1
	for index in range(occupied):
		f.combat.enemy_projectiles.append({"id": index + 100, "source_id": -1, "type_id": "M02", "pos": Vector2(-7, -5), "previous": Vector2(-7, -5), "direction": Vector2.RIGHT, "speed": 0.0, "radius": 0.16, "damage": 1.0, "remaining": 5.0, "range_remaining": 15.0})
	advance(f, 0.01)
	check(actor.phase == "chase" and actor.danger.is_empty() and int(actor.reserved_projectiles) == 0, "capacity rejection starts no misleading warning")
	check(f.combat.enemy_projectiles.size() == occupied and actor.next_attack_at > f.run.time, "capacity rejection retains bullets and schedules retry")
	f.combat.enemy_projectiles.resize(total - size)
	advance(f, 0.27)
	check(actor.phase == "warning" and int(actor.reserved_projectiles) == size, "retry reserves both complete sweeps at exact remaining capacity")
	actor.health = 0.0
	advance(f, 0.02)
	check(int(actor.reserved_projectiles) == 0 and actor.danger.is_empty() and f.combat.enemy_projectiles.size() == total - size, "source death cancels pending shots and preserves released bullets")
	f = fixture()
	actor = add_actor(f, "M07")
	advance(f, 1.08)
	check(actor.phase == "barrage" and int(actor.reserved_projectiles) == 21, "first double-sweep shot leaves twenty-one pending")
	var bullet: Dictionary = f.combat.enemy_projectiles[0]
	var old_pos: Vector2 = bullet.pos
	var remaining := float(actor.barrage_shot_remaining)
	f.run.frozen = true
	advance(f, 0.1)
	check(float(actor.barrage_shot_remaining) == remaining and bullet.pos != old_pos and int(f.combat._next_projectile) == 2, "freeze pauses pending sequence while released bullet moves")
	f.run.frozen = false
	f.combat.interrupt_by_push(actor, Vector2(-1, 0))
	advance(f, 0.2)
	check(actor.phase == "recover" and int(actor.reserved_projectiles) == 0 and int(f.combat._next_projectile) == 2, "push cancels pending sweep without erasing released shot")
	f = fixture()
	actor = add_actor(f, "M06")
	advance(f, 0.2)
	remaining = float(actor.warning_remaining)
	f.run.frozen = true
	advance(f, 0.5)
	check(float(actor.warning_remaining) == remaining and f.combat.enemy_projectiles.is_empty(), "freeze preserves warning time and its reservation")
	f.run.frozen = false
	var other := add_actor(f, "M05", 2, Vector2(0, -2))
	advance(f, 0.01)
	check(other.phase == "warning", "curtain spacing uses combat time even while first source is frozen")
	var frozen: Dictionary = other.duplicate(true)
	f.run.paused = true
	f.combat.update(f.run, 10.0)
	check(other == frozen, "pause never advances pending warnings")
	f.run.paused = false
	f.run.phase = "reward"
	f.combat.update(f.run, 10.0)
	check(other == frozen, "reward selection never advances pending warnings")
	f = fixture()
	actor = add_actor(f, "M05")
	other = add_actor(f, "M06", 2, Vector2(0, -2))
	advance(f, 0.01)
	check(actor.phase == "warning" and other.phase == "chase", "curtains cannot begin on same frame")
	advance(f, 0.23)
	check(other.phase == "chase", "curtain start spacing holds below quarter second")
	advance(f, 0.03)
	check(other.phase == "warning", "curtain start is released after quarter second")


func spawn_constraints() -> void:
	var battle := Route.new()
	check(battle.configure().ok and battle.choose_initial("F01"), "route configures for spawn boundary fixture")
	for room_id in range(1, 61):
		if room_id % 15 == 0:
			continue
		battle._enter_room(room_id)
		var valid := 0
		for point in battle._runtime.room.spawn.north_band:
			if battle._body_clear(Vector2(point[0], point[1]), 0.78 + float(battle._spatial.spawn.static_clearance)):
				valid += 1
		check(valid >= 12, "unchanged geometry offers at least twelve statically valid elite-sized slots room %d" % room_id)
	battle._enter_room(18)
	battle.spawn_warnings.clear()
	battle._packs = [{"M06": 1}, {"M06": 1, "M01": 3}]
	battle._batch_index = 1
	battle._spawn_done = false
	var survivor: Dictionary = battle._enemy_combat.make_actor(battle, "M06", Vector2(-4, 0), 400)
	battle.actors = [survivor]
	var shield := float(battle.player.shield)
	battle._reserve_batch()
	check(battle.spawn_warnings.is_empty(), "role cap includes survivor and queues whole next pack")
	survivor.health = 0.0
	battle._reserve_batch()
	check(battle.spawn_warnings.size() == 4 and is_equal_approx(float(battle.spawn_warnings[0].remaining), 0.8), "whole queued pack gets full warning after role frees")
	check(float(battle.player.shield) == shield, "wave reservation never restores player shield")
	var warning_pos: Vector2 = battle.spawn_warnings[0].pos
	battle.player.pos = warning_pos
	battle.player.previous = warning_pos
	battle._update_spawn(0.8)
	check(battle.actors.size() == 1 and battle._batch_index == 1, "activation rechecks player distance and consumes no partial pack")
	check(not battle.spawn_warnings.is_empty() and float(battle.spawn_warnings[0].remaining) == 0.8, "unsafe preview restarts with full warning")


func remaining_attack_boundaries() -> void:
	var f := fixture()
	var elite := add_actor(f, "EL01")
	f.run.player.pos = Vector2(2, 0)
	f.run.player.previous = f.run.player.pos
	advance(f, 1.1)
	check(elite.phase == "lunge", "chain spacing fixture reaches first elite lunge")
	# A different heavy attack has just started; a second lunge must wait too.
	f.combat._last_heavy_warning = float(f.run.time)
	advance(f, 0.2)
	check(elite.phase == "chain_wait" and elite.danger.is_empty(), "second lunge obeys shared heavy-warning gate")
	advance(f, 0.39)
	check(elite.phase == "chain_wait", "waiting chain cannot shorten another heavy start interval")
	advance(f, 0.03)
	check(elite.phase == "warning" and float(elite.warning_remaining) > 0.7, "second lunge receives its full warning after gate frees")
	f = fixture()
	var first := stationary_body(f, "EL02", 7)
	stationary_body(f, "EL02", 2)
	advance(f, 0.01)
	var contacts: Array = f.run.effects.filter(func(effect): return effect.kind == "enemy_contact")
	check(contacts.size() == 1 and int(contacts[0].actor_id) == 2, "equal body damage uses stable smallest actor id")
	var ready := float(f.combat._contact_ready_at)
	var clock_before := float(f.combat._combat_clock)
	f.run.paused = true
	f.combat.update(f.run, 5.0)
	f.run.paused = false
	f.run.phase = "reward"
	f.combat.update(f.run, 5.0)
	check(float(f.combat._contact_ready_at) == ready and float(f.combat._combat_clock) == clock_before, "pause and choices freeze shared contact clock")
	f.run.phase = "combat"
	first.health = 0.0
	f.run.actors[1].health = 0.0
	advance(f, 0.6)
	check(is_equal_approx(float(f.run.damage_taken), 76.8), "dead bodies cannot produce new contact damage")
	f = fixture()
	var shooter := add_actor(f, "M05")
	shooter.next_attack_at = 1000.0
	f.combat._emit_projectile(shooter, shooter.combat_spec, Vector2.RIGHT)
	var shot: Dictionary = f.combat.enemy_projectiles[0]
	shot.speed = 1.0
	shot.remaining = 0.02
	advance(f, 0.03)
	check(f.combat.enemy_projectiles.is_empty(), "released hostile bullet expires on lifetime")
	f.combat._emit_projectile(shooter, shooter.combat_spec, Vector2.LEFT)
	shot = f.combat.enemy_projectiles[0]
	shot.range_remaining = 0.01
	advance(f, 0.02)
	check(f.combat.enemy_projectiles.is_empty(), "released hostile bullet expires on range")


func stationary_body(f: Dictionary, type_id: String = "M02", id: int = 1) -> Dictionary:
	var actor := add_actor(f, type_id, id, f.run.player.pos + Vector2(0.1, 0))
	actor.combat_spec.move_speed = 0.0
	actor.next_attack_at = 1000.0
	actor.body_grace_remaining = 0.0
	return actor


func contact_rules() -> void:
	for fps in [30, 60, 120]:
		var f := fixture()
		stationary_body(f)
		advance(f, 1.7, fps)
		check(is_equal_approx(float(f.run.damage_taken), 115.2), "global contact interval is stable across frame rates %d" % fps)
	var f := fixture()
	var small := stationary_body(f, "M02", 1)
	var heavy := stationary_body(f, "M03", 2)
	var elite := stationary_body(f, "EL02", 3)
	advance(f, 0.01)
	check(is_equal_approx(float(f.run.damage_taken), 76.8), "overlapping bodies apply only highest eligible direct damage")
	var contacts: Array = f.run.effects.filter(func(effect): return effect.kind == "enemy_contact")
	check(contacts.size() == 1 and int(contacts[0].actor_id) == int(elite.id), "contact event identifies selected body")
	elite.health = 0.0
	heavy.health = 0.0
	small.pos += Vector2(3, 0)
	advance(f, 0.3)
	small.pos = f.run.player.pos
	advance(f, 0.3)
	check(is_equal_approx(float(f.run.damage_taken), 76.8), "changing bodies or reentering overlap cannot bypass shared cooldown")
	advance(f, 0.22)
	check(is_equal_approx(float(f.run.damage_taken), 115.2), "next eligible contact occurs after full shared interval")
	f = fixture()
	small = stationary_body(f)
	f.run.player.invulnerable = 1.0
	advance(f, 0.1)
	check(float(f.run.damage_taken) == 0.0 and float(f.combat._contact_ready_at) == 0.0, "rejected invulnerable hit consumes no contact interval")
	f.run.player.invulnerable = 0.0
	advance(f, 0.01)
	check(is_equal_approx(float(f.run.damage_taken), 38.4), "first accepted body hit begins interval")
	f = fixture()
	small = stationary_body(f)
	small.body_grace_remaining = 0.5
	advance(f, 0.49)
	check(float(f.run.damage_taken) == 0.0, "new body honors appearance grace")
	advance(f, 0.02)
	check(is_equal_approx(float(f.run.damage_taken), 38.4), "contact becomes live after appearance grace")
	f = fixture()
	small = stationary_body(f)
	f.run.frozen = true
	advance(f, 0.8)
	check(float(f.run.damage_taken) == 0.0 and not small.body_contact_enabled, "frozen body deals no contact damage")
	f.run.frozen = false
	small.spell_slows = {"unit": {"amount": 0.9, "until": 10.0}}
	advance(f, 0.01)
	check(is_equal_approx(float(f.run.damage_taken), 38.4), "slow alone does not disable contact")
	f = fixture()
	small = stationary_body(f)
	small.pos = Vector2.ZERO
	f.run.player.previous = Vector2(-3, 0)
	f.run.player.pos = Vector2(3, 0)
	f.combat.update(f.run, 0.01)
	check(is_equal_approx(float(f.run.damage_taken), 38.4), "relative swept circles catch player crossing a body")
	f = fixture()
	small = stationary_body(f)
	f.combat.enemy_projectiles = [{"id": 1, "source_id": 2, "type_id": "M02", "pos": f.run.player.pos - Vector2(1, 0), "previous": f.run.player.pos - Vector2(1, 0), "direction": Vector2.RIGHT, "speed": 100.0, "radius": 0.18, "damage": 33.0, "remaining": 5.0, "range_remaining": 15.0}]
	f.combat.update(f.run, 0.02)
	check(float(f.run.damage_taken) == 33.0 and float(f.combat._contact_ready_at) == 0.0, "projectile resolves before body and rejected contact consumes no interval")
	f = fixture(15)
	stationary_body(f)
	advance(f, 1.0)
	check(float(f.run.damage_taken) == 0.0, "Boss placeholders are excluded from contact changes")
	f = fixture()
	var charge := stationary_body(f, "M03")
	charge.phase = "lunge"
	charge.attack_from = f.run.player.pos - Vector2(1, 0)
	charge.pos = charge.attack_from
	charge.attack_to = f.run.player.pos + Vector2(1, 0)
	f.combat.update(f.run, 0.35)
	check(float(f.run.damage_taken) == float(charge.damage) and not charge.body_contact_enabled, "active charge uses only its attack damage")


func contact_damage_path() -> void:
	var battle := Route.new()
	check(battle.configure().ok and battle.choose_initial("F01"), "actual route damage hook configures")
	battle._enter_room(59)
	battle.blocks.clear()
	battle.actors.clear()
	battle.spawn_warnings.clear()
	battle.player.pos = Vector2.ZERO
	battle.player.previous = Vector2.ZERO
	for id in ["GU10", "GU12"]:
		battle._artifact_combat._owned.append(id)
		battle._artifact_combat.apply_acquisition(battle, id)
	var f := {"run": battle, "combat": battle._enemy_combat}
	stationary_body(f)
	var multiplier := float(battle._artifact_combat.incoming_damage_multiplier(battle, "direct"))
	var projectile_multiplier := float(battle._artifact_combat.incoming_damage_multiplier(battle, "projectile"))
	var shield := float(battle.player.shield)
	var health := float(battle.player.health)
	battle._enemy_combat.update(battle, 0.01)
	check(multiplier > projectile_multiplier and is_equal_approx(shield - float(battle.player.shield), 38.4 * multiplier), "body uses defense and shield without projectile-only reduction")
	check(float(battle.player.health) == health, "shield absorbs body hit through existing player damage transaction")
	battle._enemy_combat.clear()
	battle.player.invulnerable = 0.0
	battle.player.shield = 0.0
	battle.player.health = 1.0
	battle._artifact_combat._owned.append("GU14")
	battle._artifact_combat.apply_acquisition(battle, "GU14")
	battle._enemy_combat.update(battle, 0.01)
	check(battle.phase == "dead" and float(battle.player.health) <= 0.0, "lethal contact resolves death before item recovery")
