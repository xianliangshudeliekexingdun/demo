extends RefCounted

const Run = preload("res://scripts/core/first_room_run.gd")
var checks = 0
var failures = 0

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("First room: " + label)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001

func fresh(spell_id: String = "F01", seed_value: int = 7):
	var run = Run.new()
	var result = run.configure({}, seed_value)
	check(result.ok, "configuration loads approved sources")
	check(run.choose_initial(spell_id), "initial legal choice " + spell_id)
	return run

func advance(run, seconds: float, move: Vector2 = Vector2.ZERO):
	for tick in int(round(seconds * 120.0)):
		run.step(1.0 / 120.0, move)

func activate(run):
	advance(run, 0.8)
	check(run.actors.size() == 2, "first pack activates exactly two M01")

func run() -> int:
	configuration_and_movement()
	expanded_room_geometry()
	spawn_and_pause()
	targeting_and_spells()
	enemy_attack_and_death()
	rewards_and_exit()
	for spell_id in Run.INITIAL_IDS:
		full_playable_flow(spell_id)
	print("First room checks: %d; failures: %d" % [checks, failures])
	return failures

func configuration_and_movement():
	var battle = Run.new()
	check(battle.configure().ok, "configure")
	check(battle.phase == "choosing" and battle.spells.is_empty(), "starts at initial choice")
	check(battle.initial_choices().map(func(choice): return choice.id) == ["F01", "F04", "F08"], "initial three fixed independent outputs")
	check(not battle.choose_initial("F10"), "helper spell cannot start")
	check(battle.room_size == Vector2(18, 28), "18 by 28 current playable room dimensions")
	check(battle.blocks.size() == 2 and battle.blocks[0].center == Vector2(-5.25, 0), "wider room retains two side covers")
	check(battle.player.pos == Vector2(0, -12.5), "bottom entry comes from playable room source")
	check(near(battle.player.health, 300) and near(battle.player.shield, 100), "new baseline health and shield")
	check(not battle.portal.visible and not battle.portal.usable, "portal hidden and locked")
	battle.step(1.0, Vector2.ONE)
	check(near(battle.time, 0.0) and battle.player.pos == Vector2(0, -12.5), "choice freezes move and time")
	check(battle.choose_initial("F01"), "start")
	check(not battle.choose_initial("F08"), "initial choice consumed once")
	advance(battle, 0.1, Vector2.ONE)
	check(near(battle.player.pos.distance_to(Vector2(0, -12.5)), 0.5), "normalized diagonal full movement speed")
	check(battle.move_body(Vector2.ZERO, Vector2(100,100), 0.3).is_equal_approx(Vector2(8.7,13.7)), "expanded floor clamp still bounds playable room")
	var wall_stop = battle.move_body(Vector2(-5.25, -2), Vector2(0,4), 0.3)
	check(near(wall_stop.y, -0.8), "cover blocks moving body without tunnelling")
	var slide = battle.move_body(Vector2(-5.95, -0.9), Vector2(0,2), 0.3)
	check(slide.y > 0.9 and battle._body_clear(slide, 0.3), "cover permits edge sliding")
	var snapshot = battle.get_snapshot()
	snapshot.player.health = 1
	snapshot.blocks.clear()
	check(battle.player.health == 300 and battle.blocks.size() == 2, "snapshot is independent deep copy")
	var with_gem = Run.new()
	check(with_gem.configure({"player": {"health": 360, "attack": 110}}).ok, "snapshot accepted")
	check(with_gem.player.max_health == 360 and with_gem.player.attack == 110 and with_gem.player.shield == 100, "gem snapshot applies once without replacing other source stats")
	for fps in [30, 60, 144]:
		var timed = fresh()
		for frame in fps:
			timed.step(1.0 / float(fps), Vector2.ZERO)
		check(near(timed.time, 1.0), "fixed time at %d fps" % fps)
	var hitch = fresh()
	hitch.step(10.0)
	check(near(hitch.time, 0.1), "hitch delta limited to 0.1")

func expanded_room_geometry():
	var battle = Run.new()
	check(battle.configure().ok, "expanded geometry configures")
	check(battle.portal.pos == Vector2(0, 13), "portal position comes from current room source")
	check(battle.player.pos.distance_to(battle.portal.pos) / battle.player.move_speed > 5.0, "entry to portal travel now exceeds five seconds at source speed")
	check(battle.line_is_clear(battle.player.pos, battle.portal.pos), "central entry to portal route stays open")
	for block in battle.blocks:
		check(battle._body_clear(block.center + Vector2(0, -1.0), battle.player.radius), "cover approach fits player")
		check(block.size == Vector2.ONE, "cover footprint is retained during room expansion")
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var stopped: Vector2 = battle.move_body(Vector2(0, -3), direction * 100.0, battle.player.radius)
		check(battle._inside_floor(stopped, battle.player.radius), "every wall still limits movement")
		check(not battle._inside_floor(stopped + direction * 0.01, battle.player.radius), "scenic exterior is outside playable floor")
	# The first enemies are intentionally near the entrance rather than distributed
	# over the expanded empty north half. All starters must acquire real enemies
	# promptly with source range/speed and the existing preview, without fixtures.
	for spell_id in Run.INITIAL_IDS:
		for seed_value in [1, 7, 29, 73, 97]:
			var opening = fresh(spell_id, seed_value)
			var previews: Array = opening.spawn_warnings.duplicate(true)
			for warning in previews:
				check(opening._body_clear(warning.pos, float(opening._spatial.spawn.normal_footprint_radius) + float(opening._spatial.spawn.static_clearance)), "expanded first pack has safe floor and cover clearance")
				check(warning.pos.y < 0, "first teaching pack stays in entrance combat area")
			advance(opening, 3.0)
			check(opening.casts > 0, "%s seed %d acquires and casts within three seconds while stationary" % [spell_id, seed_value])

func spawn_and_pause():
	var battle = fresh()
	check(battle.spawn_warnings.size() == 2 and battle.actors.is_empty(), "whole first pack preview")
	for warning in battle.spawn_warnings:
		check(near(warning.remaining, 0.8), "ordinary preview source duration")
		check(warning.pos.distance_to(battle.player.pos) >= 3.0, "spawn safe distance")
		check(battle._body_clear(warning.pos, 0.6), "spawn footprint plus clearance")
	check(battle.spawn_warnings[0].pos.x * battle.spawn_warnings[1].pos.x < 0.0, "first pack balances sides")
	advance(battle, 0.4)
	var state = battle.get_snapshot()
	battle.set_paused(true)
	advance(battle, 5.0, Vector2.ONE)
	check(near(battle.time, state.time) and battle.player.pos == state.player.pos, "pause freezes time and player")
	check(near(battle.spawn_warnings[0].remaining, state.spawn_warnings[0].remaining), "pause freezes spawn preview")
	battle.set_paused(false)
	advance(battle, 0.4)
	check(battle.actors.size() == 2, "resume no lost or duplicated pack")
	for actor in battle.actors:
		check(actor.lock_remaining > 0.48 and actor.phase == "chase", "appearance attack lock source half second")
	var recheck = fresh()
	advance(recheck, 0.79)
	var old_preview = recheck.spawn_warnings.duplicate(true)
	recheck.player.pos = old_preview[0].pos
	advance(recheck, 0.02)
	check(recheck.actors.is_empty() and recheck.spawn_warnings.size() == 2, "unsafe activation replaces whole batch")
	for warning in recheck.spawn_warnings:
		check(warning.pos.distance_to(recheck.player.pos) >= 3.0 and warning.remaining > 0.78, "replacement gets full preview and safety")
	advance(recheck, 0.8)
	check(recheck.actors.size() == 2, "reselected pack preserves exact quantity")

func targeting_and_spells():
	var battle = fresh()
	activate(battle)
	var cover_x: float = battle.blocks[0].center.x
	battle.player.pos = Vector2(cover_x - 1.5, 0)
	battle.actors[0].pos = Vector2(cover_x + 1.5, 0)
	battle.actors[1].pos = Vector2(cover_x - 1.5, 4)
	check(battle.nearest_target(battle.player.pos, 8).id == battle.actors[1].id, "hidden nearest is skipped for visible target")
	check(battle.nearest_target(battle.player.pos, 8, false).id == battle.actors[0].id, "non-direct selector can choose across cover")
	check(not battle.line_is_clear(Vector2(cover_x - 1.5, 0), Vector2(cover_x + 1.5,0)), "direct cover ray blocked")
	check(battle.line_is_clear(Vector2(cover_x - 1.5, -2), Vector2(cover_x + 1.5,-2)), "clear ray works")
	battle.actors[0].pos = Vector2(cover_x + 1.5,0.6)
	battle.actors[1].pos = Vector2(5,6)
	check(battle.nearest_target(Vector2(cover_x - 1.5,0.6),8,true,0.15).is_empty(), "direct selection includes projectile collision width near cover edge")
	battle.player.pos = Vector2.ZERO
	battle.actors[0].pos = Vector2(-1,3)
	battle.actors[1].pos = Vector2(1,3)
	check(battle.nearest_target(Vector2.ZERO,8).id == battle.actors[0].id, "equal target stable actor id")
	for actor in battle.actors:
		actor.pos = Vector2(0, 6)
		actor.previous = actor.pos
	battle.player.pos = Vector2(0,-6)
	battle.spells[0].remaining = 0.0
	battle.spells[0].cast_remaining = 0.0
	battle._update_spells(0.1)
	check(battle.casts == 0 and battle.spells[0].remaining == 0 and battle.spells[0].cast_remaining == 0, "no legal target stays ready")
	battle.actors[0].pos = Vector2(0,-3)
	battle._update_spells(0.01)
	check(battle.spells[0].cast_remaining > 0, "legal target begins independent windup")
	battle.actors[0].health = 0
	battle._update_spells(0.3)
	check(battle.casts == 0 and battle.spells[0].remaining == 0, "lost final target cancels without cooldown")
	battle.actors[1].pos = Vector2(0,-2)
	battle.actors[1].previous = battle.actors[1].pos
	battle.spells[0].cast_remaining = 0.1
	battle._update_spells(0.1)
	check(battle.casts == 1 and battle.spells[0].target_id == battle.actors[1].id and battle.spells[0].remaining > 0, "windup reselects surviving legal target on release")
	# F01 ray is locked, collides at the first enemy, and cannot jump through cover.
	var bolt = fresh()
	activate(bolt)
	bolt.player.pos = Vector2(cover_x - 1.5,0)
	bolt.actors[0].pos = Vector2(cover_x + 1.5,0)
	bolt.actors[1].pos = Vector2(0,6)
	for enemy in bolt.actors:
		enemy.previous = enemy.pos
	bolt._release_spell(bolt.spells[0], bolt.actors[0])
	bolt._update_projectiles(0.5)
	check(bolt.actors[0].health == 180 and bolt.projectiles.is_empty(), "bolt stopped at solid cover")
	bolt.player.pos = Vector2.ZERO
	bolt.actors[0].pos = Vector2(0,2)
	bolt.actors[1].pos = Vector2(0,4)
	for enemy in bolt.actors:
		enemy.previous = enemy.pos
	bolt._release_spell(bolt.spells[0], bolt.actors[0])
	bolt._update_projectiles(0.3)
	check(bolt.actors[0].health < 180 and bolt.actors[1].health == 180, "nonpiercing bolt hits first swept target once")
	var relative_bolt = fresh()
	activate(relative_bolt)
	relative_bolt.projectiles.clear()
	relative_bolt.actors[0].pos = Vector2(1,2)
	relative_bolt.actors[0].previous = Vector2(-1,2)
	relative_bolt.actors[1].pos = Vector2(5,5)
	relative_bolt.actors[1].previous = Vector2(5,5)
	relative_bolt.projectiles.append({"id":1,"spell_id":"F01","from":Vector2.ZERO,"to":Vector2(0,8),"pos":Vector2.ZERO,"direction":Vector2(0,1),"speed":40.0,"travelled":0.0,"range":8.0,"duration":0.2,"remaining":0.2,"radius":0.15,"blast_radius":0.8,"damage":100.0})
	relative_bolt._update_projectiles(0.1)
	check(relative_bolt.projectiles.is_empty(), "moving target crossing bolt path is swept relatively")
	check(relative_bolt.actors[0].health == 80, "relative swept hit applies actual damage")
	# F08 hits a line of enemies, clips at the cover, and uses its approved coefficient.
	var beam = fresh("F08")
	activate(beam)
	beam.player.pos = Vector2.ZERO
	beam.actors[0].pos = Vector2(0,2)
	beam.actors[1].pos = Vector2(0,4)
	beam._release_spell(beam.spells[0], beam.actors[0])
	check(beam.actors[0].health <= 20 and beam.actors[1].health <= 20, "beam pierces both enemies at 1.6 attack coefficient")
	var spirit_run = fresh("F04")
	activate(spirit_run)
	spirit_run.player.pos = Vector2.ZERO
	spirit_run.actors[0].pos = Vector2(0,2)
	spirit_run.actors[1].pos = Vector2(0,4)
	spirit_run._release_spell(spirit_run.spells[0], spirit_run.actors[0])
	check(spirit_run.spirit.active and near(spirit_run.spirit.attack_remaining, 1.25), "summon first shot waits full interval")
	var casts_before: int = spirit_run.casts
	spirit_run._update_spirit(1.24)
	check(spirit_run.damage_dealt == 0, "spirit does not hit early")
	spirit_run._update_spirit(0.01)
	check(spirit_run.damage_dealt >= 100 and spirit_run.actors[1].health == 180, "spirit first shot nonpiercing coefficient")
	check(spirit_run.casts == casts_before, "summon attacks do not become natural casts")
	spirit_run.spells[0].remaining = 0
	spirit_run._update_spells(1)
	check(spirit_run.casts == casts_before and spirit_run.spells[0].cast_remaining == 0, "active spirit cannot be resummoned")
	var frozen = spirit_run.get_snapshot()
	spirit_run.set_paused(true)
	advance(spirit_run, 3)
	check(spirit_run.spirit == frozen.spirit and spirit_run.spells == frozen.spells, "pause freezes spirit and independent cooldown")

func enemy_attack_and_death():
	var battle = fresh()
	activate(battle)
	battle.spells.clear()
	battle.player.pos = Vector2.ZERO
	battle.actors[0].pos = Vector2(0,2)
	battle.actors[0].lock_remaining = 0
	battle.actors[1].health = 0
	advance(battle, 1.0 / 120.0)
	var actor: Dictionary = battle.actors[0]
	check(actor.phase == "warning" and near(actor.warning_remaining, 0.65), "M01 starts approved warning")
	var target: Vector2 = actor.attack_to
	advance(battle, 0.4, Vector2.RIGHT)
	check(actor.attack_to == target, "warning direction and endpoint lock")
	advance(battle, 0.6)
	check(near(battle.player.shield,100) and near(battle.player.health,300), "ordinary side movement avoids lunge")
	check(battle.damage_player(120), "effective player damage")
	check(near(battle.player.shield,0) and near(battle.player.health,280), "damage consumes shield before health")
	check(not battle.damage_player(30) and near(battle.player.health,280), "shared hurt invulnerability")
	advance(battle, 0.6)
	check(battle.damage_player(30) and near(battle.player.health,250), "invulnerability expires")
	var stationary = fresh()
	activate(stationary)
	stationary.spells.clear()
	stationary.player.pos = Vector2.ZERO
	stationary.actors[0].pos = Vector2(0,2)
	stationary.actors[0].lock_remaining = 0
	stationary.actors[1].health = 0
	advance(stationary, 1.0)
	check(near(stationary.player.shield,70) and near(stationary.player.health,300), "real M01 swept lunge deals source damage once")
	advance(stationary, 0.5)
	check(near(stationary.player.shield,70), "overlap and recovery do not cause contact damage")
	var lethal = fresh()
	activate(lethal)
	lethal.damage_player(9999)
	check(lethal.phase == "dead" and lethal.player.health == 0, "lethal damage terminal")
	check(lethal.clear_count == 0 and lethal.gold == 0 and lethal.dust == 0, "death before clear gives no rewards")
	check(lethal.reward_choices.is_empty() and not lethal.portal.visible, "death no reward or portal")
	var elapsed: float = lethal.time
	advance(lethal, 5, Vector2.ONE)
	check(lethal.time == elapsed and lethal.projectiles.is_empty() and not lethal.spirit.active, "dead simulation stopped")
	check(lethal.get_summary().cleared_rooms.is_empty(), "no cleared-room ledger on failed first room")
	check(near(Run.segment_circle_time(Vector2(-10,0),Vector2(10,0),Vector2.ZERO,0.8),0.46), "relative sweep catches high speed")
	check(Run.segment_circle_time(Vector2(-10,2),Vector2(10,2),Vector2.ZERO,0.8) == INF, "relative sweep misses safely")
	var route = fresh()
	var cover_x: float = route.blocks[0].center.x
	var pos = Vector2(cover_x - 1.5,0)
	for tick in 600:
		pos = route._chase_position(pos, Vector2(cover_x + 1.5,0), 2.35 / 120.0,0.45)
	check(pos.distance_to(Vector2(cover_x + 1.5,0)) < 0.1, "M01 navigates around side cover")

func rewards_and_exit():
	var battle = fresh()
	activate(battle)
	battle.player.shield = 5
	battle.player.health = 257
	for actor in battle.actors:
		battle.damage_enemy(actor,999)
	advance(battle,1.0 / 120.0)
	check(battle.phase == "reward" and battle.clear_count == 1, "all configured enemies clear once")
	check(battle.gold == 6 and battle.dust == 1, "source clear gold and pending dust")
	check(battle.player.shield == 100 and battle.player.health == 257, "clear restores shield and keeps health")
	check(battle.reward_choices.size() == 3, "weighted growth offers three")
	var ids = battle.reward_choices.map(func(choice): return choice.id)
	check(ids.size() == 3 and ids[0] != ids[1] and ids[0] != ids[2] and ids[1] != ids[2], "same offer unique")
	check(battle.portal.visible and not battle.portal.usable, "clear portal visible but locked until reward")
	var elapsed: float = battle.time
	var remaining: float = battle.spells[0].remaining
	advance(battle, 5, Vector2.UP)
	check(battle.time == elapsed and battle.spells[0].remaining == remaining, "reward stops all combat time and cooldown")
	check(battle.gold == 6 and battle.dust == 1 and battle.clear_count == 1, "clear rewards idempotent")
	check(not battle.choose_reward("bad"), "unoffered reward rejected")
	var selected: String = battle.reward_choices[0].id
	check(battle.choose_reward(selected), "legal reward consumes once")
	check(battle.phase == "exit" and battle.portal.usable, "reward unlocks walking exit")
	check(not battle.choose_reward(selected), "second click cannot duplicate reward")
	check(battle.get_summary().cleared_rooms == [1], "clear ledger exposes room one once")
	advance(battle, 0.1)
	check(battle.phase == "exit" and battle.time == elapsed, "exit waiting does not finish or run combat")
	battle.player.pos = battle.portal.pos
	advance(battle, 0.1)
	check(battle.phase == "exit", "standing at exit does not replace walk trigger")
	advance(battle, 1.0 / 120.0,Vector2.RIGHT)
	check(battle.phase == "complete" and battle.get_summary().result == "success", "walk into enabled upper portal completes")
	# Eligibility filtering happens before catalyst weights and selection.
	var filter = fresh()
	filter.spells[0].level = 3
	check("F01" not in filter.eligible_reward_ids(), "max level filtered")
	for spell_id in ["F02","F03","F04","F05","F06","F07","F08"]:
		filter.spells.append(filter._new_spell(spell_id))
	check(filter.spells.size() == 8 and "F09" not in filter.eligible_reward_ids() and "F10" not in filter.eligible_reward_ids(), "eight full slots filter new spells")
	check("F04" in filter.eligible_reward_ids(), "full slots permit owned upgrades")
	filter._equipment = {"equipment":{"catalyst":"MC04"},"levels":{"MC04":3}}
	check(near(filter.reward_weight("F08"),2.0) and near(filter.reward_weight("F04"),1.0), "equipped catalyst applies approved related weight")
	check(filter.initial_choices().all(func(choice): return near(choice.weight,1.0)), "catalyst never changes initial offer weights")
	for spell in filter.spells:
		spell.level = 3
	check(filter.eligible_reward_ids().is_empty() and filter._sample_rewards().is_empty(), "exhausted legal pool stays empty")

func full_playable_flow(spell_id: String):
	for seed_value in [1,7,29]:
		var battle = fresh(spell_id,seed_value)
		# Real movement and real AI/casts. The same modest route introduces enemies
		# to range, then keeps normal movement available during locked attacks.
		for tick in 7200:
			if battle.phase != "combat":
				break
			var direction = Vector2.ZERO
			if battle.time < 0.8:
				direction = Vector2(0,1)
			else:
				direction = Vector2(cos(battle.time * 1.1),sin(battle.time * 1.1)) * 0.6
			battle.step(1.0 / 120.0,direction)
		check(battle.phase == "reward", "%s seed %d clears through real combat" % [spell_id,seed_value])
		check(battle.kills == 2 and battle.casts > 0 and battle.damage_dealt == 360, "%s combat ledger real kills and finite damage" % spell_id)
		check(battle.player.health > 0, "%s starter survives teaching room" % spell_id)
		if battle.phase != "reward":
			continue
		battle.choose_reward(battle.reward_choices[0].id)
		for tick in 1200:
			if battle.phase != "exit":
				break
			var direction: Vector2 = (battle.portal.pos - battle.player.pos).normalized()
			battle.step(1.0 / 120.0,direction)
		check(battle.phase == "complete", "%s real walk to upper portal completes" % spell_id)
