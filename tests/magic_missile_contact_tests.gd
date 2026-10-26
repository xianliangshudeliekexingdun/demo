extends RefCounted
## Differential collision regression against the pre-VFX implementation, plus
## the read-only delivery contract. No presentation, rendering or natural route.
const Combat = preload("res://scripts/core/route_enemy_combat.gd")
const First = preload("res://scripts/core/first_room_run.gd")
var checks := 0
var failures := 0

class OriginalCombat extends "res://scripts/core/route_enemy_combat.gd":
	# Frozen 48f98b4 projectile step, before the terminal-delivery journal.
	func _update_projectiles(run, dt: float) -> void:
		var retained: Array = []
		for projectile in enemy_projectiles:
			if run.phase != "combat":
				break
			var from: Vector2 = projectile.pos
			var speed_scale: float = run.enemy_projectile_speed_multiplier(from) if run.has_method("enemy_projectile_speed_multiplier") else 1.0
			var distance := minf(float(projectile.speed) * speed_scale * dt, float(projectile.range_remaining))
			var to: Vector2 = from + projectile.direction * distance
			var wall_time: float = run._first_block_contact(from, to, float(projectile.radius))
			var hit_time: float = run.segment_circle_time(from - run.player.previous, to - run.player.pos, Vector2.ZERO, float(projectile.radius) + float(run.player.radius))
			if hit_time != INF and hit_time < wall_time - 0.000001:
				run.damage_player(float(projectile.damage), "projectile")
				continue
			if wall_time != INF:
				continue
			projectile.previous = from
			projectile.pos = to
			projectile.remaining -= dt
			projectile.range_remaining -= distance
			if projectile.remaining > 0.000001 and projectile.range_remaining > 0.000001 and run._inside_floor(to, float(projectile.radius)):
				retained.append(projectile)
		enemy_projectiles = retained


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("Magic missile contact: " + label)


func fixture(original: bool = false) -> Dictionary:
	var run = First.new()
	check(run.configure().ok, "baseline source configures")
	run.phase = "combat"
	run.time = 10.0
	run.blocks.clear()
	run.actors.clear()
	run.effects.clear()
	run.player.pos = Vector2(3.0, 0.0)
	run.player.previous = run.player.pos
	run.player.invulnerable = 0.0
	var combat = OriginalCombat.new() if original else Combat.new()
	return {"run": run, "combat": combat}


func shot(id: int = 1) -> Dictionary:
	return {"id": id, "source_id": 1, "type_id": "M02", "pos": Vector2.ZERO,
		"previous": Vector2.ZERO, "direction": Vector2.RIGHT, "speed": 60.0,
		"radius": 0.2, "damage": 4.0, "remaining": 1.0, "range_remaining": 30.0}


func run() -> int:
	contacts()
	boundaries()
	parity()
	print("Magic missile contact checks: %d; failures: %d" % [checks, failures])
	return failures


func contacts() -> void:
	var f := fixture()
	f.combat.enemy_projectiles = [shot()]
	f.combat._update_projectiles(f.run, 0.1)
	var events: Array = f.combat.get_projectile_ends()
	check(events.size() == 1 and events[0].reason == "player", "swept player contact reported once")
	var event: Dictionary = events[0]
	var expected := 3.0 - float(f.run.player.radius) - 0.2
	check(absf(float(event.pos.x) - expected) < 0.00001, "event keeps exact swept center, not last observed frame")
	check(absf(float(event.contact_pos.x) - (3.0 - float(f.run.player.radius))) < 0.00001, "burst point lies on player contact surface")
	check(event.normal.is_equal_approx(Vector2.LEFT), "player contact normal faces back toward the shot")
	check(absf(float(event.time) - (9.9 + expected / 60.0)) < 0.00001, "event carries sub-tick contact time")
	check(event.damage_applied and f.run.damage_taken == 4.0, "original damage applied once")
	check(f.combat.enemy_projectiles.is_empty(), "original projectile removed once")
	var original_seq: int = f.run.event_seq
	f.combat.get_projectile_ends()
	check(f.run.event_seq == original_seq, "reading delivery journal does not emit gameplay effects")
	events[0].pos = Vector2(900, 900)
	check(f.combat.get_projectile_ends()[0].pos != Vector2(900, 900), "terminal snapshot is deeply isolated")
	f = fixture()
	f.run.player.invulnerable = 1.0
	f.combat.enemy_projectiles = [shot()]
	f.combat._update_projectiles(f.run, 0.1)
	event = f.combat.get_projectile_ends()[0]
	check(event.reason == "player" and not event.damage_applied and f.run.damage_taken == 0.0, "protected contact remains a real contact without adding damage")
	f = fixture()
	f.run.blocks = [{"center": Vector2(1.6, 0), "size": Vector2(0.4, 2.0)}]
	f.combat.enemy_projectiles = [shot()]
	f.combat._update_projectiles(f.run, 0.1)
	event = f.combat.get_projectile_ends()[0]
	check(event.reason == "wall" and f.run.damage_taken == 0, "nearer wall keeps precedence over player")
	check(event.pos.is_equal_approx(Vector2(1.2, 0)) and event.contact_pos.is_equal_approx(Vector2(1.4, 0)), "wall center and surface contact are distinct exact positions")
	check(event.normal.is_equal_approx(Vector2.LEFT), "wall normal points outward")
	f = fixture()
	var edge := 3.0 - float(f.run.player.radius)
	f.run.blocks = [{"center": Vector2(edge + 0.2, 0), "size": Vector2(0.4, 2.0)}]
	f.combat.enemy_projectiles = [shot()]
	f.combat._update_projectiles(f.run, 0.1)
	check(f.combat.get_projectile_ends()[0].reason == "wall" and f.run.damage_taken == 0, "exact wall/player tie retains original wall precedence")


func boundaries() -> void:
	for reason in ["lifetime", "range", "floor"]:
		var f := fixture()
		f.run.player.pos = Vector2(0, 5)
		f.run.player.previous = f.run.player.pos
		var projectile := shot()
		projectile.speed = 1.0
		if reason == "lifetime": projectile.remaining = 0.01
		if reason == "range": projectile.range_remaining = 0.01
		if reason == "floor": projectile.pos = Vector2(f.run.room_size.x * 0.5, 0)
		f.combat.enemy_projectiles = [projectile]
		f.combat._update_projectiles(f.run, 0.1)
		check(f.combat.get_projectile_ends().size() == 1 and f.combat.get_projectile_ends()[0].reason == "expired", reason + " termination never becomes a collision")
		f.run.time += 0.6
		f.combat._update_projectiles(f.run, 0.1)
		check(f.combat.get_projectile_ends().is_empty(), "old delivery facts expire: " + reason)
	var f := fixture()
	f.run.player.pos = Vector2(0, 5)
	f.run.player.previous = f.run.player.pos
	for id in Combat.PROJECTILE_END_LIMIT + 1:
		var projectile := shot(id)
		projectile.speed = 0.1
		projectile.remaining = 0.001
		f.combat.enemy_projectiles.append(projectile)
	f.combat._update_projectiles(f.run, 0.01)
	check(f.combat.get_projectile_ends().size() == Combat.PROJECTILE_END_LIMIT, "delivery storage stays bounded")
	check(f.combat.get_projectile_ends()[-1].projectile_id == Combat.PROJECTILE_END_LIMIT, "bound keeps newest terminal facts")
	f.combat.clear()
	check(f.combat.get_projectile_ends().is_empty(), "room clear resets delivery journal")


func parity() -> void:
	var current := fixture()
	var old := fixture(true)
	for case_id in 256:
		var angle := float(case_id % 16) * TAU / 16.0
		var projectile := shot(case_id + 1)
		projectile.pos = Vector2(float(case_id % 7) - 3.0, float(case_id % 5) - 2.0)
		projectile.direction = Vector2.from_angle(angle)
		projectile.speed = [2.0, 8.0, 60.0, 120.0][case_id % 4]
		projectile.remaining = [0.001, 0.05, 0.8][case_id % 3]
		projectile.range_remaining = [0.01, 0.5, 30.0][case_id % 3]
		for f in [current, old]:
			f.run.phase = "combat"
			f.run.player.health = f.run.player.max_health
			f.run.player.pos = Vector2(1, 0)
			f.run.player.previous = Vector2(-0.5, 0.4) if case_id % 2 == 0 else f.run.player.pos
			f.run.player.invulnerable = 1.0 if case_id % 5 == 0 else 0.0
			f.run.blocks = [{"center": Vector2(0, 1), "size": Vector2(0.6, 2.0)}] if case_id % 3 == 0 else []
			f.combat.enemy_projectiles = [projectile.duplicate(true)]
			f.combat._update_projectiles(f.run, [1.0 / 120.0, 0.1][case_id % 2])
		check(current.run.get_snapshot() == old.run.get_snapshot(), "unchanged damage, effects, counters and world snapshot: case %d" % case_id)
		check(current.combat.enemy_projectiles == old.combat.enemy_projectiles, "unchanged motion, culling and lifetime: case %d" % case_id)
