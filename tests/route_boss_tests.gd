extends RefCounted
## Controlled headless rules. No natural route, rendering, or account writes.

const Route = preload("res://scripts/core/courtyard_route_run.gd")
const Catalog = preload("res://scripts/core/courtyard_route_catalog.gd")
var checks := 0
var failures := 0
var rows: Array = []


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("Boss: " + label)


func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func fixture(room: int = 60) -> Dictionary:
	var run = Route.new()
	check(run.configure({}, 711).ok and run.choose_initial("F01"), "route configures with Boss source")
	run._enter_room(room)
	run.spawn_warnings.clear()
	run._spawn_done = true
	run._batch_index = run._packs.size()
	run.blocks.clear()
	run.actors.clear()
	run.player.pos = Vector2(0, -4)
	run.player.previous = run.player.pos
	run.player.health = 100000.0
	run.player.max_health = 100000.0
	run.player.shield = 0.0
	var combat = run._enemy_combat
	var definition: Dictionary = combat.bosses.catalog.for_room(room)
	var actor: Dictionary = combat.make_actor(run, str(definition.id), Vector2.ZERO, 1, room)
	check(not actor.is_empty(), "authored Boss has actor spec at correct room")
	run.actors.append(actor)
	run._next_actor_id = 2
	return {"run": run, "combat": combat, "actor": actor}


func advance(f: Dictionary, seconds: float) -> void:
	for tick in roundi(seconds * 120.0):
		f.run.time += 1.0 / 120.0
		f.run.player.previous = f.run.player.pos
		f.run.player.invulnerable = maxf(0.0, float(f.run.player.invulnerable) - 1.0 / 120.0)
		f.combat.update(f.run, 1.0 / 120.0)


func begin(f: Dictionary, phase_index: int, key: String) -> Dictionary:
	var actor: Dictionary = f.actor
	actor.boss_phase_index = phase_index
	var stage: Dictionary = actor.combat_spec.definition.phases[phase_index]
	actor.boss_sequence_index = stage.sequence.find(key)
	actor.boss_action = {}
	actor.boss_ground = []
	actor.phase = "chase"
	actor.lock_remaining = 0.0
	actor.body_grace_remaining = 0.0
	actor.next_attack_at = 0.0
	f.combat.bosses._begin(f.combat, f.run, actor)
	return stage.patterns[key]


func run() -> int:
	catalog_and_spawn()
	projectile_patterns()
	capacity_and_charge()
	ground_hazards()
	phases_and_control()
	finite_summons()
	dual_rewards()
	print("Boss rules: %d checks; %d failures" % [checks, failures])
	return failures


func catalog_and_spawn() -> void:
	var catalog := Catalog.new()
	check(catalog.load_catalog().ok, "catalog validates all sixty rooms")
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/boss_nonboss_baseline.json"))
	var current: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Catalog.DATA_PATH))
	for room in range(1, 61):
		if room % 15 != 0:
			check(current.encounters_by_room[str(room)] == baseline.encounters[str(room)], "exact non-Boss encounter preserved %d" % room)
	var total := 0
	for room in catalog.get_rooms():
		for pack in room.encounter.packs:
			for count in pack.values(): total += int(count)
	check(total == 933, "929 non-Boss plus four Bosses; optional adds counted only on spawn")
	check(current.reward_rooms.size() == 52 and current.artifact_reward_rooms.size() == 12, "52 books and 12 chests")
	var run = Route.new()
	check(run.configure().ok and run.choose_initial("F01"), "spawn route configures")
	for index in 4:
		var room: int = [15, 30, 45, 60][index]
		run._enter_room(room)
		check(run._current_room.kind == "boss" and run._packs.size() == 1 and run._spawn_total == 1, "single real Boss encounter %d" % room)
		check(run.spawn_warnings.size() == 1 and run.spawn_warnings[0].pos == Vector2(0, 6) and near(run.spawn_warnings[0].duration, 1.5), "center forecourt full Boss preview")
		# Moving into the reserved location must invalidate activation and retry.
		run.player.pos = Vector2(0, 6)
		run._update_spawn(2.0)
		check(run.actors.is_empty() and not run._spawn_done, "never activate a Boss inside the player")
		run.player.pos = Vector2(0, -5)
		run._update_spawn(0.01)
		run._update_spawn(1.49)
		check(run.actors.is_empty(), "retry grants full new spawn warning")
		run._update_spawn(0.02)
		check(run.actors.size() == 1 and run._spawn_done, "single Boss activates once")
		var actor: Dictionary = run.actors[0]
		check(str(actor.type_id) == ["BOSS01", "BOSS04", "BOSS02", "BOSS03"][index] and near(actor.health, [24000, 48000, 80000, 130000][index]), "approved compatible ID and health")
		check(near(actor.lock_remaining, 0.8) and near(actor.push_resistance, 1.0), "appearance lock and full push resistance")
		run._update_spawn(10.0)
		check(run.actors.size() == 1, "completed pack cannot respawn")


func projectile_patterns() -> void:
	for room in [15, 30, 45, 60]:
		var prototype := fixture(room)
		var phases: Array = prototype.actor.combat_spec.definition.phases
		for phase_index in phases.size():
			for key in phases[phase_index].patterns:
				var p: Dictionary = phases[phase_index].patterns[key]
				if str(p.kind) not in ["fan", "ring", "sweep"]: continue
				var f := fixture(room)
				begin(f, phase_index, str(key))
				var locked: Vector2 = f.actor.attack_to
				var expected: int = (int(p.count) - int(p.get("omitted_adjacent_spokes", 0))) * int(p.get("volleys", 1))
				check(int(f.actor.reserved_projectiles) == expected, "entire action reserved before warning %s %s" % [room, key])
				f.run.player.pos = Vector2(5, -3)
				advance(f, float(p.warning) - 0.05)
				check(f.combat._next_projectile == 1 and f.actor.attack_to == locked, "full warning and locked direction %s %s" % [room, key])
				advance(f, 0.05)
				var first: int = 1 if str(p.kind) == "sweep" else int(p.count) - int(p.get("omitted_adjacent_spokes", 0))
				check(int(f.combat._next_projectile) - 1 == first, "exact first release count %s %s" % [room, key])
				var shots: Array = f.combat.get_projectiles()
				for shot in shots:
					check(near(shot.damage, p.damage) and near(shot.radius, p.radius) and shot.remaining <= 5.0 and shot.range_remaining <= 15.0, "projectile values and finite lifetime")
				if str(p.kind) == "fan" and shots.size() > 1:
					check(near(absf(rad_to_deg(shots[0].direction.angle_to(shots[1].direction))), 22.0), "fan keeps 22 degree spacing")
				if str(p.kind) == "ring":
					for shot in shots:
						check(absf(rad_to_deg(Vector2.UP.angle_to(shot.direction))) > 360.0 / float(p.count) * 1.9, "first gap faces warning-start player and omits three spokes")
					check(near(rad_to_deg(Vector2.UP.angle_to(f.actor.boss_gap)), 30.0), "emitted ring commits next gap")
					if int(p.volleys) == 2:
						advance(f, float(p.release_interval) - float(p.followup_warning) + 0.02)
						check(not f.actor.boss_action.warning.is_empty() and near(f.actor.boss_action.warning.duration, p.followup_warning), "second ring has its own full warning")
						advance(f, float(p.followup_warning) - 0.02)
						check(near(rad_to_deg(Vector2.UP.angle_to(f.actor.boss_gap)), 60.0), "second actual ring also rotates gap")
				elif str(p.kind) == "sweep":
					var angles: Array = f.actor.boss_action.angles.duplicate()
					advance(f, float(p.shot_interval) * (float(p.count) - 1.0))
					check(bool(f.actor.boss_sweep_reverse), "sweep alternates after release")
					begin(f, phase_index, str(key))
					angles.reverse()
					check(f.actor.boss_action.angles == angles, "next sweep uses opposite fixed order")
					# Cancel the newly arranged action; count below refers to first cast.
					f.actor.boss_action = {}
					f.actor.phase = "recover"
					f.actor.recovery_remaining = 99.0
					f.actor.reserved_projectiles = 0
				check(int(f.combat._next_projectile) - 1 == expected and int(f.actor.reserved_projectiles) == 0, "complete volley, no omitted capacity tails")
				rows.append({"room": room, "phase": phase_index, "action": key, "emitted": expected})
	# Warnings remain available inside the non-Boss curtain minimum distance.
	var melee := fixture(30)
	melee.run.player.pos = Vector2(0, -1.6)
	advance(melee, 1.0 / 120.0)
	check(melee.actor.phase == "warning", "Boss fans can start at safe melee distance")


func capacity_and_charge() -> void:
	var f := fixture(30)
	var p := begin(f, 1, "double_ring")
	f.actor.boss_action = {}
	f.actor.reserved_projectiles = 0
	f.actor.phase = "chase"
	f.actor.boss_sequence_index = 1
	for index in 63:
		f.combat.enemy_projectiles.append({"id": 1000 + index, "source_id": -1, "type_id": "M02", "pos": Vector2(-7, -5), "previous": Vector2(-7, -5), "direction": Vector2.RIGHT, "speed": 0.0, "radius": 0.16, "damage": 1.0, "remaining": 5.0, "range_remaining": 15.0})
	f.combat.bosses._begin(f.combat, f.run, f.actor)
	check(f.actor.boss_action.is_empty() and int(f.actor.reserved_projectiles) == 0 and f.actor.next_attack_at > f.run.time, "reject incomplete double-ring capacity before any warning")
	f.combat.enemy_projectiles.pop_back()
	f.actor.boss_sequence_index = 1
	f.combat.bosses._begin(f.combat, f.run, f.actor)
	check(int(f.actor.reserved_projectiles) == 34 and not f.actor.boss_action.is_empty(), "exact 96 capacity reserves both 17-shot rings")
	f = fixture(15)
	p = begin(f, 0, "charge")
	f.run.player.pos = Vector2(4, -4)
	advance(f, float(p.warning))
	check(f.actor.phase == "charge" and f.actor.attack_to == Vector2(0, -7) and not f.actor.body_contact_enabled, "charge locks seven-metre lane and disables body contact")
	advance(f, float(p.duration))
	check(near(f.actor.pos.y, -7.0) and f.actor.phase == "recover" and near(f.actor.recovery_remaining, p.recovery), "charge ends with full stationary recovery")
	var position: Vector2 = f.actor.pos
	advance(f, float(p.recovery) - 0.05)
	check(f.actor.pos == position and f.actor.phase == "recover", "recovery is a reachable stationary damage window")
	f = fixture(15)
	f.actor.pos = Vector2(0, -12)
	f.actor.previous = f.actor.pos
	f.run.player.pos = Vector2(0, -13)
	begin(f, 0, "charge")
	check(f.actor.attack_to.y >= -13.000001, "charge clips to floor with actual Boss radius")
	# Contact uses the common accepted-hit interval and direct-damage path.
	f = fixture(15)
	f.run.player.pos = Vector2(0, -0.5)
	f.actor.lock_remaining = 0.0
	f.actor.body_grace_remaining = 0.0
	f.actor.phase = "recover"
	f.actor.recovery_remaining = 10.0
	var health: float = f.run.player.health
	advance(f, 1.0 / 120.0)
	check(near(health - f.run.player.health, 37.5), "Boss physical overlap applies room15 dedicated factor once")
	advance(f, 0.7)
	check(near(health - f.run.player.health, 37.5), "body interval is shared and exceeds normal hurt invulnerability")
	advance(f, 0.11)
	check(near(health - f.run.player.health, 75.0), "persistent contact hits again only after interval")


func ground_hazards() -> void:
	var f := fixture(45)
	var p := begin(f, 1, "cross_line")
	var group: Dictionary = f.actor.boss_ground[0]
	check(group.shapes.size() == 2 and near(group.shapes[0].radius, 0.6), "cross has two locked full-width line shapes")
	var locked: Array = group.shapes.duplicate(true)
	var health: float = f.run.player.health
	advance(f, float(p.warning) - 0.05)
	check(near(f.run.player.health, health) and group.shapes == locked, "ground warning cannot hurt or track player")
	advance(f, 0.1)
	check(near(health - f.run.player.health, 108.0) and bool(group.hit), "cross center accepts one room-scaled hit for entire group")
	advance(f, 1.0)
	check(near(health - f.run.player.health, 108.0), "cross cannot tick twice after hurt protection ends")
	advance(f, 0.2)
	check(f.actor.boss_ground.is_empty() and f.actor.phase == "recover", "line expires and leaves recovery")
	f = fixture(30)
	p = begin(f, 1, "marks")
	var first: Vector2 = f.actor.boss_ground[0].shapes[0].pos
	f.run.player.pos = Vector2(3, -4)
	advance(f, float(p.mark_interval))
	check(f.actor.boss_ground.size() == 2 and f.actor.boss_ground[0].shapes[0].pos == first and f.actor.boss_ground[1].shapes[0].pos == f.run.player.pos, "successive marks lock separately every 0.7 seconds")
	f.run.player.pos = Vector2(-3, -4)
	advance(f, float(p.mark_interval))
	check(int(f.actor.boss_action.mark_index) == 3, "second phase emits exactly three sequential marks")
	advance(f, float(p.warning) + float(p.active))
	check(f.actor.boss_ground.is_empty() and f.actor.phase == "recover", "last mark expires before main-action recovery")


func phases_and_control() -> void:
	for room in [15, 30, 45, 60]:
		var f := fixture(room)
		var ice = f.run._spell_combat.ice.status
		check(ice.category(f.actor) == "fixed_strong" and near(ice.control_coefficient(f.actor), 0.0), "explicit Boss ice class %d" % room)
		check(ice.force_ready(f.run, f.actor, 9.0) and not ice.is_frozen(1) and not ice.capture_ready(1).is_empty(), "Boss keeps brittle window without hard freeze")
		ice.apply_short_slow(f.run, f.actor, 0.9, 5.0, "boss_test")
		check(near(ice.slow_amount(f.actor), 0.15), "Boss slow capped at fifteen percent")
		if room == 15:
			f.run.damage_enemy(f.actor, 18000.0)
			check(int(f.actor.boss_phase_index) == 0 and near(f.combat.bosses.grace_remaining, 0.0), "first Boss has exactly one phase")
			continue
		begin(f, 0, "fan" if room != 45 else "sweep")
		f.run.spells[0].remaining = 0.72
		var health: float = f.run.player.health
		f.run.player.shield = 27.0
		f.combat.enemy_projectiles.append({"id": 123})
		f.run.damage_enemy(f.actor, float(f.actor.max_health) * 0.75)
		var final_phase: int = f.actor.combat_spec.definition.phases.size() - 1
		check(int(f.actor.boss_phase_index) == final_phase and f.actor.boss_action.is_empty() and f.actor.boss_ground.is_empty() and f.combat.enemy_projectiles.is_empty(), "burst selects destination phase and clears hostile state once")
		check(near(f.actor.health, float(f.actor.max_health) * 0.25) and near(f.run.player.health, health) and near(f.run.player.shield, 27.0) and near(f.run.spells[0].remaining, 0.72), "transition preserves actual health shield and spell cooldown")
		check(not ice.capture_ready(1).is_empty(), "phase change preserves ice window")
		var remaining: float = f.combat.bosses.grace_remaining
		f.run.set_paused(true)
		var paused: Dictionary = f.run.get_snapshot()
		f.run.step(0.1, Vector2.RIGHT)
		check(f.run.get_snapshot() == paused and near(f.combat.bosses.grace_remaining, remaining), "pause freezes Boss transition and all rule clocks")
		f.run.set_paused(false)
		advance(f, remaining - 0.05)
		check(f.actor.boss_action.is_empty() and not f.actor.body_contact_enabled, "no new Boss attack or contact during transition grace")
		var before: float = f.actor.health
		f.run.damage_enemy(f.actor, 100.0)
		check(near(f.actor.health, before - 100.0), "Boss remains damageable during transition")
		advance(f, 0.07)
		check(f.combat.bosses.grace_remaining <= 0.0 and f.actor.phase == "warning" and f.actor.warning_remaining >= 1.1 - 0.02, "new phase resumes with full warning")
		f.run.damage_enemy(f.actor, 1000000.0)
		check(bool(f.actor.boss_defeated) and f.actor.health <= 0.0 and near(f.combat.bosses.grace_remaining, 0.0), "lethal burst takes precedence without HP gate")


func finite_summons() -> void:
	var f := fixture(60)
	f.run.damage_enemy(f.actor, float(f.actor.max_health) * 0.75)
	check(f.actor.summon_opportunities.size() == 2, "skipped phase retains both finite summon opportunities")
	advance(f, 2.0)
	f.actor.phase = "recover"
	f.actor.recovery_remaining = 3.0
	f.combat.bosses._try_summon(f.combat, f.run, f.actor)
	check(f.combat.bosses.summon_warnings.size() == 2, "whole M01 M02 group previews during recovery")
	var warning: Dictionary = f.combat.bosses.summon_warnings[0]
	f.run.player.pos = warning.pos
	advance(f, 1.0)
	check(int(f.actor.summon_groups) == 0 and f.actor.summon_opportunities.size() == 2, "unsafe appearance consumes no group opportunity")
	f.run.player.pos = Vector2(0, -4)
	advance(f, 1.1)
	check(int(f.actor.summon_groups) == 1 and f.combat.bosses._alive_adds(f.run, f.actor) == 2, "safe retry spawns entire first group once")
	var adds: Array = f.run.actors.filter(func(actor): return actor.get("summoned_by", -1) == 1)
	check(adds.size() == 2 and near(adds[0].max_health + adds[1].max_health, 8128.0) and adds.all(func(actor): return int(actor.stat_room) == 59 and float(actor.lock_remaining) > 0.0), "summons explicitly use room59 stats and appearance lock")
	f.actor.phase = "recover"
	f.actor.recovery_remaining = 10.0
	advance(f, 1.1)
	check(int(f.actor.summon_groups) == 1 and f.actor.summon_opportunities.size() == 1, "living adds defer final opportunity")
	for add in adds: f.run.damage_enemy(add, float(add.health))
	f.actor.phase = "recover"
	f.actor.recovery_remaining = 10.0
	advance(f, 1.1)
	check(int(f.actor.summon_groups) == 2 and f.combat.bosses._alive_adds(f.run, f.actor) == 2 and f.actor.summon_opportunities.is_empty(), "cleared first group allows final group at next recovery")
	var kills: int = f.run.kills
	f.run.damage_enemy(f.actor, float(f.actor.health))
	check(f.combat.bosses._alive_adds(f.run, f.actor) == 0 and f.run.kills == kills + 1 and f.combat.bosses.summon_warnings.is_empty(), "Boss death despawns adds without farming kills or cleanup wave")
	f.run._check_clear()
	check(f.run.phase == "pickup" and f.run.cleared_rooms == [60], "living adds do not delay Boss victory rewards")
	# Transition while adds warn must cancel and later restart their full warning.
	f = fixture(60)
	var add: Dictionary = f.combat.make_actor(f.run, "M02", Vector2(5, -4), 2, 59)
	add["summoned_by"] = 1
	f.run.actors.append(add)
	advance(f, 0.1)
	check(add.phase == "warning", "summoned flower warns normally")
	f.run.damage_enemy(f.actor, float(f.actor.max_health) * 0.4)
	check(add.phase == "chase" and add.danger.is_empty() and int(add.reserved_projectiles) == 0, "transition cancels pending add attack")
	advance(f, 2.01)
	check(add.phase == "warning" and float(add.warning_remaining) >= float(add.combat_spec.warning) - 0.02, "add restarts full warning after grace")


func touch(run, pickup: Dictionary) -> void:
	run.player.pos = pickup.pos
	run.player.previous = run.player.pos
	run._try_pickup(run.player.pos, run.player.pos)


func dual_rewards() -> void:
	for index in 4:
		var room: int = [15, 30, 45, 60][index]
		var f := fixture(room)
		var run = f.run
		var gold: int = run.gold
		run.damage_enemy(f.actor, float(f.actor.health))
		run._check_clear()
		check(run.phase == "pickup" and run.reward_pickups.size() == 2 and not run.portal.usable and run.artifact_choices.is_empty(), "book plus locked gold chest appear together %d" % room)
		check(near(run.reward_pickups[0].pos.x, -1.2) and near(run.reward_pickups[1].pos.x, 1.2) and bool(run.reward_pickups[1].locked), "two separated north forecourt pickups")
		touch(run, run.reward_pickups[1])
		check(run.phase == "pickup" and run.artifact_choices.is_empty() and not run._artifact_combat._offers.has(room), "locked chest neither opens nor samples before book")
		touch(run, run.reward_pickups[0])
		check(run.phase == "reward" and not run.reward_choices.is_empty(), "physical book contact opens usual spell choices")
		check(run.choose_reward(str(run.reward_choices[0].id), run.room_revision), "choose legal book reward")
		check(run.phase == "pickup" and bool(run.boss_rewards.book_resolved) and not run.portal.usable and not bool(run.reward_pickups[1].locked), "book resolves to pending gold chest")
		var offer: Array = run.artifact_choices.duplicate(true)
		check(not offer.is_empty() and offer.size() <= 3 and offer.all(func(item): return str(item.rarity) == "gold"), "every Boss candidate is gold including room15")
		var rng_state: int = run._rng.state
		check(run._artifact_combat.sample_boss_choices(run, run._rng) == offer and run._rng.state == rng_state, "Boss offer is cached without RNG reroll")
		touch(run, run.reward_pickups[1])
		check(run.phase == "artifact" and run.choose_artifact(str(offer[0].id)), "gold chest physically opens and grants chosen item")
		check(run.phase == "exit" and run.portal.usable and bool(run.boss_rewards.chest_resolved), "portal opens only after both rights resolve")
		check(not run.choose_artifact(str(offer[0].id)) and not run.choose_reward("F01"), "reward rights are idempotent")
		run._check_clear()
		check(run.cleared_rooms == [room] and run.gold == gold + [18, 28, 28, 40][index] and near(run.player.shield, run.player.max_shield), "clear income and full shield preserved once")
		if room == 60:
			run.player.pos = run.portal.pos - Vector2(0, 0.01)
			run.step(1.0 / 120.0, Vector2.DOWN)
			check(run.phase == "complete" and run.room_index == 60 and not run.portal.usable, "final real portal contact completes after both rewards; no room61")
	# Replacement cancellation must preserve cards and keep the gold chest locked.
	var f := fixture(45)
	var run = f.run
	run.spells.clear()
	for id in run.eligible_reward_ids().slice(0, 8):
		var spell: Dictionary = run._new_spell(str(id))
		spell.level = 3
		run._refresh_spell(spell)
		run.spells.append(spell)
	run.damage_enemy(f.actor, float(f.actor.health))
	run._check_clear()
	touch(run, run.reward_pickups[0])
	var cards: Array = run.reward_choices.duplicate(true)
	check(run.can_skip_spell_reward() and run.choose_reward(str(cards[0].id)), "full maxed loadout still offers new level-one replacements")
	var request: int = int(run.pending_replacement.request_id)
	check(not bool(run.boss_rewards.book_resolved) and run.artifact_choices.is_empty(), "replacement request alone does not resolve book")
	check(run.cancel_spell_replacement(request) and run.reward_choices == cards and not bool(run.boss_rewards.book_resolved), "replacement Esc returns exact cards without unlocking gold")
	check(run.skip_spell_reward() and bool(run.boss_rewards.book_resolved) and run.phase == "pickup", "legal all-new skip resolves only book right")
	# All ordinary gold owned: the stage seal remains gold and outside normal pools.
	for room in [15, 30, 45, 60]:
		f = fixture(room)
		run = f.run
		var items: Dictionary = run._artifact_combat._items
		run._artifact_combat._owned.assign(items.keys().filter(func(id): return str(items[id].rarity) == "gold" and not bool(items[id].get("boss_only", false)) and str(id) != "GT03"))
		# Acquiring the max-life contract must pass through its real acquisition
		# hook; directly pretending it is owned would leave an invalid life pool.
		run._artifact_combat._owned.append("GT03")
		run._artifact_combat.apply_acquisition(run, "GT03")
		run.damage_enemy(f.actor, float(f.actor.health))
		run._check_clear()
		touch(run, run.reward_pickups[0])
		check(run.choose_reward(str(run.reward_choices[0].id)), "fallback fixture resolves book first")
		var seal := "BGT%d" % room
		check(run.artifact_choices.size() == 1 and str(run.artifact_choices[0].id) == seal and str(run.artifact_choices[0].rarity) == "gold", "empty gold pool uses only this room's gold seal")
		touch(run, run.reward_pickups[1])
		var health: float = run.player.health
		var maximum: float = run.player.max_health
		var bonus: float = run._artifact_combat.combat_stats(run).generic_damage_bonus
		check(run.choose_artifact(seal) and near(run.player.health, health) and near(run.player.max_health, maximum + 50.0 * float(items.GT03.maximum_health_multiplier)), "seal grants max life without immediate healing and follows existing life contract")
		check(near(run._artifact_combat.combat_stats(run).generic_damage_bonus, bonus + 0.15), "seal grants fifteen percent regular damage")
		check(run._artifact_combat.eligible_ids(run).all(func(id): return not str(id).begins_with("BGT")), "seals never enter ordinary chest or shop eligibility")
	# One remaining eligible gold must be shown alone, never filled by other tiers.
	f = fixture(30)
	run = f.run
	var gold_ids: Array = run._artifact_combat.eligible_ids(run).filter(func(id): return str(run._artifact_combat._items[id].rarity) == "gold")
	check(not gold_ids.is_empty(), "baseline loadout has generic eligible gold")
	run._artifact_combat._owned.assign(gold_ids.slice(1))
	run.boss_rewards = {"book_resolved": true, "chest_resolved": false}
	var offer: Array = run._artifact_combat.sample_boss_choices(run, run._rng)
	check(offer.size() == 1 and offer[0].id == gold_ids[0], "reduced gold pool has no lower-rarity filler or seal")
	f = fixture(30)
	run = f.run
	gold_ids = run._artifact_combat.eligible_ids(run).filter(func(id): return str(run._artifact_combat._items[id].rarity) == "gold")
	run._artifact_combat._owned.assign(gold_ids.slice(2))
	run.boss_rewards = {"book_resolved": true, "chest_resolved": false}
	offer = run._artifact_combat.sample_boss_choices(run, run._rng)
	check(offer.size() == 2 and offer.all(func(item): return str(item.rarity) == "gold" and not str(item.id).begins_with("BGT")), "two remaining gold entries stay two, without filler")
	# An interrupted final double ring loses its reserved tail at death.
	f = fixture(60)
	begin(f, 2, "double_ring")
	advance(f, 1.3)
	check(int(f.actor.reserved_projectiles) == 21 and int(f.combat._next_projectile) - 1 == 21, "first final ring retains second ring's full reservation")
	f.run.damage_enemy(f.actor, float(f.actor.health))
	advance(f, 2.0)
	check(f.combat.enemy_projectiles.is_empty() and int(f.actor.reserved_projectiles) == 0 and int(f.combat._next_projectile) - 1 == 21, "Boss death clears released shots and cancels the reserved second ring")
	# The existing shield-conversion core still converts the cap increase once,
	# while the new seal's explicit no-refill rule also holds for this build.
	var converted = Route.new()
	check(converted.configure({"gem_core": "aegis", "player": {"health": 195.0, "shield": 362.5}}).ok, "real converted-life snapshot configures")
	converted.player.health = 100.0
	converted.player.shield = 80.0
	converted._artifact_combat._owned.append("BGT15")
	converted._artifact_combat.apply_acquisition(converted, "BGT15")
	check(near(converted.player.max_health, 227.5) and near(converted.player.max_shield, 406.25), "seal flat life converts exactly once through existing core")
	check(near(converted.player.health, 100.0) and near(converted.player.shield, 80.0), "seal never refills current life or shield with conversion core")
