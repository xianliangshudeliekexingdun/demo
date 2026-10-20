extends RefCounted

const Combat = preload("res://scripts/core/route_enemy_combat.gd")
const First = preload("res://scripts/core/first_room_run.gd")
const Catalog = preload("res://scripts/core/courtyard_route_catalog.gd")
var checks: int = 0
var failures: int = 0


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("Route enemies: " + label)


func fresh() -> Dictionary:
	var run = First.new()
	check(run.configure().ok, "original baseline configures")
	run.phase = "combat"
	run.blocks.clear()
	run.actors.clear()
	run.player.pos = Vector2(2, 0)
	run.player.previous = run.player.pos
	var combat = Combat.new()
	check(combat.configure(run._base, run._runtime).ok, "enemy extension configures")
	return {"run": run, "combat": combat}


func tick(fixture: Dictionary, seconds: float, movement: Vector2 = Vector2.ZERO) -> void:
	var run = fixture.run
	for index in int(round(seconds * 120.0)):
		run.time += 1.0 / 120.0
		run.player.previous = run.player.pos
		run.player.pos = run.move_body(run.player.pos, movement * run.player.move_speed / 120.0, run.player.radius)
		run.player.invulnerable = maxf(0.0, run.player.invulnerable - 1.0 / 120.0)
		fixture.combat.update(run, 1.0 / 120.0)


func actor(fixture: Dictionary, type_id: String, pos: Vector2 = Vector2.ZERO) -> Dictionary:
	var result: Dictionary = fixture.combat.make_actor(fixture.run, type_id, pos, fixture.run.actors.size() + 1)
	fixture.run.actors.append(result)
	return result


func run() -> int:
	source_and_route()
	lunge_rules()
	shooter_rules()
	mark_rules()
	elite_rules()
	heavy_spacing_and_pause()
	slow_and_push()
	print("Route enemy checks: %d; failures: %d" % [checks, failures])
	return failures


func source_and_route() -> void:
	var f := fresh()
	for type_id in ["M01", "M02", "M03", "M04", "EL01", "EL02", "EL02_GUARD"]:
		var spec: Dictionary = f.combat.type_spec(type_id)
		check(not spec.is_empty(), "configured type " + type_id)
		check(spec.health > 0 and spec.damage > 0 and spec.warning >= 0.65, "readable nonzero type " + type_id)
	check(f.combat.type_spec("M01").health == f.run._base.normal_stages[0].stats.M01.health, "M01 health remains original")
	check(f.combat.type_spec("M02").damage == f.run._base.normal_stages[0].stats.M02.damage, "M02 damage uses original early source")
	check(f.combat.type_spec("EL01").health == f.run._base.elites[0].health, "EL01 health comes from first source elite")
	check(f.combat.type_spec("EL02").health == f.run._base.elites[1].health, "EL02 health comes from first source elite")
	check(f.combat.type_spec("M03").health < f.run._base.normal_stages[1].stats.M03.health, "M03 uses explicit early stats rather than later-stage health")
	check(f.combat.type_spec("M04").damage < f.run._base.normal_stages[1].stats.M04.damage, "M04 uses explicit early damage rather than later stage")
	var copied: Dictionary = f.combat.type_spec("M01")
	copied.health = 1
	check(f.combat.type_spec("M01").health != 1, "type specifications are deep copied")
	var catalog = Catalog.new()
	check(catalog.load_catalog().ok, "mixed route validates")
	var total := 0
	var types: Dictionary = {}
	for room_id in range(1, 16):
		var room: Dictionary = catalog.get_room(room_id)
		check(room.geometry.spawn.north_band.size() == (15 if bool(room.nonboss) else 10), "north band authored per room %d" % room_id)
		for point in room.geometry.spawn.north_band:
			check(float(point[1]) > 0 and float(point[1]) < float(room.geometry.portal_center[1]), "all spawn points belong to north forecourt")
		for pack in room.encounter.packs:
			var amount := 0
			for type_id in pack:
				amount += int(pack[type_id])
				types[type_id] = true
			check(amount <= int(room.alive_cap), "authored pack respects cap")
			total += amount
	check(total == 105 and types.size() == 7, "approved early roster has 104 non-Boss actors and one Boss")
	check(catalog.get_room(6).kind == "elite" and catalog.get_room(12).kind == "elite", "dedicated elite rooms retained")
	check(catalog.get_room(9).kind == "normal", "normal room identity is retained")
	check(catalog.get_room(15).kind == "boss" and int(catalog.get_room(15).encounter.packs[0].get("BOSS01", 0)) == 1, "real first Boss replaces elite guard placeholder")
	var authored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/courtyard_route.json"))
	var treasure_nodes: Array = catalog.get_summary().artifact_reward_rooms
	check(treasure_nodes == authored.artifact_reward_rooms.map(func(room_id): return int(room_id)), "treasure reward nodes follow current authored route")
	check(treasure_nodes.filter(func(room_id): return int(room_id) <= 15) == [6, 12, 15], "original first fifteen preserve three treasure reward nodes")


func lunge_rules() -> void:
	var f := fresh()
	var a := actor(f, "M03")
	tick(f, 1.0 / 120.0)
	check(a.phase == "warning" and a.danger.kind == "lane", "charge begins with lane warning")
	var locked: Vector2 = a.attack_to
	f.run.player.pos = Vector2(2, 4)
	tick(f, 0.5)
	check(a.attack_to == locked and f.run.damage_taken == 0, "locked charge never follows player during warning")
	tick(f, 1.5)
	check(f.run.damage_taken == 0 and a.phase == "recover", "ordinary lateral movement avoids charge")
	f = fresh()
	a = actor(f, "M03")
	f.run.player.pos = Vector2(3, 0)
	f.run.player.previous = f.run.player.pos
	tick(f, 2.0)
	check(f.run.damage_taken == a.damage, "charge hits once only")
	f = fresh()
	f.run.blocks = [{"center": Vector2(2, 0), "size": Vector2(0.4, 3)}]
	a = actor(f, "M03")
	f.run.player.pos = Vector2(1, 0)
	f.run.player.previous = f.run.player.pos
	tick(f, 1.0 / 120.0)
	check(a.attack_to.x < 1.2, "charge destination clipped before solid wall")
	tick(f, 2.0)
	check(a.pos.x < 1.2 and a.phase == "recover", "charge stops at wall and recovers")
	f = fresh()
	a = actor(f, "M01")
	a.next_attack_at = 10
	tick(f, 0.5)
	check(f.run.damage_taken == 0, "body contact waits for actual circle overlap")


func shooter_rules() -> void:
	var f := fresh()
	f.run.player.pos = Vector2(5, 0)
	f.run.player.previous = f.run.player.pos
	var a := actor(f, "M02")
	tick(f, 0.4)
	check(a.phase == "warning" and f.combat.enemy_projectiles.is_empty(), "flower gives full windup before projectile")
	f.run.player.pos = Vector2(5, 4)
	tick(f, 0.5)
	check(f.combat.enemy_projectiles.size() == 1, "ordinary flower releases exactly one spore")
	check(f.combat.enemy_projectiles[0].direction == Vector2.RIGHT, "spore direction locked before player moves")
	tick(f, 2.0)
	check(f.run.damage_taken == 0, "side movement avoids locked spore")
	f = fresh()
	f.run.player.pos = Vector2(4, 0)
	f.run.player.previous = f.run.player.pos
	a = actor(f, "M02")
	tick(f, 2.5)
	check(f.run.damage_taken == a.damage, "single spore applies source damage once")
	f = fresh()
	f.run.player.pos = Vector2(3, 0)
	f.run.player.previous = f.run.player.pos
	a = actor(f, "M02")
	tick(f, 0.9)
	f.run.blocks = [{"center": Vector2(1.5, 0), "size": Vector2(0.4, 3)}]
	tick(f, 2.0)
	check(f.run.damage_taken == 0 and f.combat.enemy_projectiles.is_empty(), "solid cover consumes projectile before player contact")
	f = fresh()
	f.run.player.pos = Vector2(1, 0)
	f.run.player.previous = f.run.player.pos
	a = actor(f, "M02")
	f.combat.enemy_projectiles = [{"id": 1, "source_id": a.id, "type_id": "M02", "pos": Vector2.ZERO, "previous": Vector2.ZERO, "direction": Vector2.RIGHT, "speed": 100.0, "radius": 0.18, "damage": a.damage, "remaining": 5.0, "range_remaining": 15.0}]
	a.next_attack_at = 100
	f.combat.update(f.run, 0.1)
	check(f.run.damage_taken == a.damage, "projectile swept collision cannot tunnel across player")
	f = fresh()
	a = actor(f, "M02")
	tick(f, 0.2)
	a.health = 0
	tick(f, 1.0)
	check(f.combat.enemy_projectiles.is_empty(), "dead warning shooter cannot release")


func mark_rules() -> void:
	var f := fresh()
	var a := actor(f, "M04")
	tick(f, 0.2)
	check(a.phase == "warning" and a.danger.kind == "circle", "caster marks delayed circle")
	var locked: Vector2 = a.attack_to
	tick(f, 1.5, Vector2.UP)
	check(a.attack_to == locked and f.run.damage_taken == 0, "mark stays fixed and walking avoids detonation")
	f = fresh()
	a = actor(f, "M04")
	tick(f, 1.5)
	check(f.run.damage_taken == a.damage, "stationary player hit by mark only once")
	f = fresh()
	a = actor(f, "M04")
	tick(f, 1.12)
	f.run.player.invulnerable = 0
	f.run.damage_taken = 0
	a.attack_hit = false
	f.run.player.previous = a.attack_to + Vector2(-3, 0)
	f.run.player.pos = a.attack_to + Vector2(3, 0)
	f.combat.update(f.run, 1.0 / 120.0)
	check(f.run.damage_taken == a.damage, "active mark uses swept player path")


func elite_rules() -> void:
	var f := fresh()
	var a := actor(f, "EL01")
	tick(f, 1.24)
	check(a.phase == "warning" and a.lunges_remaining == 1, "crown slime independently warns second jump")
	var second_target: Vector2 = a.attack_to
	f.run.player.pos += Vector2(0, 4)
	tick(f, 0.4)
	check(a.phase == "warning" and a.attack_to == second_target, "second jump locks own direction with full warning")
	tick(f, 0.9)
	check(a.phase == "recover" and a.lunges_remaining == 0, "two jumps finish with recovery")
	f = fresh()
	f.run.player.pos = Vector2(5, 0)
	f.run.player.previous = f.run.player.pos
	a = actor(f, "EL02")
	tick(f, 1.0)
	check(f.combat.enemy_projectiles.size() == 5 and a.phase == "recover", "elite flower releases five separated fan spores")
	var directions: Array = f.combat.enemy_projectiles.map(func(projectile): return projectile.direction)
	for index in range(1, directions.size()):
		check(absf(rad_to_deg(directions[index - 1].angle_to(directions[index]))) >= 15.9, "fan has consistent visible gaps")
	var midpoint := Vector2.RIGHT.rotated(deg_to_rad(8)) * 5.0
	var gap_clear := true
	for direction in directions:
		if f.run.segment_circle_time(Vector2.ZERO, direction * 10, midpoint, 0.18 + f.run.player.radius) != INF:
			gap_clear = false
	check(gap_clear, "ordinary player body fits fan gap five metres from flower")


func heavy_spacing_and_pause() -> void:
	var f := fresh()
	var charge := actor(f, "M03")
	var caster := actor(f, "M04", Vector2(-1, 0))
	tick(f, 1.0 / 120.0)
	check(charge.phase == "warning" and caster.phase == "chase", "heavy windups cannot begin simultaneously")
	tick(f, 0.59)
	check(caster.phase == "chase", "heavy windup separation maintained below threshold")
	tick(f, 0.02)
	check(caster.phase == "warning", "heavy windup allowed after source separation")
	var before: Dictionary = caster.duplicate(true)
	f.run.paused = true
	f.combat.update(f.run, 1.0)
	check(caster == before, "pause freezes enemy warning and movement")
	f.run.paused = false
	f.run.phase = "reward"
	f.combat.update(f.run, 1.0)
	check(caster == before, "reward never advances enemy simulation")
	f.combat.clear()
	check(f.combat.enemy_projectiles.is_empty(), "room cleanup removes hostile projectiles")


func slow_and_push() -> void:
	var f := fresh()
	var a := actor(f, "M01")
	a.next_attack_at = 100
	a.spell_slows = {"long_weak": {"amount": 0.2, "until": 4.0}, "short_strong": {"amount": 0.6, "until": 0.5}}
	tick(f, 0.2)
	check(is_equal_approx(a.slow_multiplier, 0.4), "strongest active slow wins")
	tick(f, 0.4)
	check(is_equal_approx(a.slow_multiplier, 0.8), "short strong ending restores still-active weak slow")
	tick(f, 3.5)
	check(a.slow_multiplier == 1.0 and a.spell_slows.is_empty(), "all slow sources expire independently")
	f = fresh()
	a = actor(f, "M03")
	tick(f, 1.05)
	check(a.phase == "lunge", "push fixture reaches actual charge")
	var pushed := Vector2(-3, -2)
	f.combat.interrupt_by_push(a, pushed)
	tick(f, 0.2)
	check(a.phase == "recover" and a.pos == pushed and a.danger.is_empty(), "wave push interrupts motion without snapping back to locked charge")
