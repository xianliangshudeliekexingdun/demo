extends RefCounted
## Unit fixtures isolate boundaries; natural playable routes are verified separately.
const Route = preload("res://scripts/core/courtyard_route_run.gd")
const First = preload("res://scripts/core/first_room_run.gd")
const Catalog = preload("res://scripts/core/courtyard_route_catalog.gd")
const Meta = preload("res://scripts/core/meta_progression.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		push_error("Courtyard route: " + label)

func near(a: float, b: float) -> bool:
	return absf(a-b) < 0.0001

func without_elapsed(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	result.erase("time")
	result.erase("room_time")
	return result

func advance(battle, seconds: float, move: Vector2 = Vector2.ZERO):
	for tick in int(round(seconds*120.0)):
		battle.step(1.0/120.0, move)

func fresh(spell_id: String = "F01", seed_value: int = 31):
	var battle = Route.new()
	check(battle.configure({}, seed_value).ok, "route configures")
	check(battle.choose_initial(spell_id), "actual starter accepted")
	return battle

func room_fixture(room_id: int):
	var battle = fresh()
	battle._enter_room(room_id)
	return battle

func alive_count(battle) -> int:
	var result := 0
	for enemy in battle.actors:
		if enemy.health > 0.0: result += 1
	return result

func pack_count(pack: Dictionary) -> int:
	var result := 0
	for type_id in pack: result += int(pack[type_id])
	return result

func clear_fixture(battle):
	for guard in 1500:
		if battle.phase != "combat": return
		battle.step(1.0/120.0)
		for enemy in battle.actors:
			if enemy.health > 0.0: battle.damage_enemy(enemy, enemy.health)

func choose_growth(battle) -> bool:
	if battle.phase != "reward": return false
	var rank: Array = ["F01", "F08", "F07", "F03", "F11", "F02", "F10", "F06", "F05", "F09", "I01", "I02", "I03", "I05", "I10", "I07", "I08", "I09", "I06", "I04"]
	for id in battle.eligible_reward_ids():
		if id not in rank: rank.append(id)
	# Resolve every actual book: upgrade held spells first; preserve a full
	# loadout via the explicit skip only when every offered spell is new.
	for owned_only in [true, false]:
		if not owned_only and battle.can_skip_spell_reward():
			return battle.skip_spell_reward(battle.room_revision)
		for preferred in rank:
			if (not battle._owned_spell(preferred).is_empty()) != owned_only: continue
			for choice in battle.reward_choices:
				if choice.id != preferred: continue
				if not battle.choose_reward(preferred, battle.room_revision): return false
				if battle.pending_replacement.is_empty(): return battle.phase == "exit" or (battle.phase == "pickup" and bool(battle.boss_rewards.get("book_resolved", false)))
				var selected_slot: int = 0
				var worst_rank: int = -1
				for index in battle.spells.size():
					var current_rank: int = rank.find(str(battle.spells[index].id))
					if current_rank < 0: current_rank = rank.size()
					if current_rank > worst_rank:
						worst_rank = current_rank
						selected_slot = index
				return battle.confirm_spell_replacement(selected_slot, int(battle.pending_replacement.request_id), battle.room_revision)
	return false

func choose_artifact(battle) -> bool:
	var choices: Array = battle.get_snapshot().get("artifact_choices", [])
	return not choices.is_empty() and battle.choose_artifact(str(choices[0].id))

func touch_reward(battle) -> bool:
	for guard in 120*30:
		if battle.phase != "pickup":
			return battle.phase in ["reward", "artifact"]
		var pickup: Dictionary = battle.get_snapshot().get("reward_pickup", {})
		if pickup.is_empty(): return false
		var waypoint: Vector2 = battle._chase_position(battle.player.pos,pickup.pos,1.0,battle.player.radius)
		battle.step(1.0/120.0,(waypoint-battle.player.pos).normalized())
	return false

func use_portal(battle) -> bool:
	var room: int = battle.room_index
	for guard in 120*30:
		if battle.room_index != room or battle.phase == "complete": return true
		if battle.phase not in ["exit", "shop"]: return false
		var waypoint: Vector2 = battle._chase_position(battle.player.pos,battle.portal.pos,1.0,battle.player.radius)
		battle.step(1.0/120.0,(waypoint-battle.player.pos).normalized())
	return false

func run() -> int:
	configuration_and_sources()
	geometry_and_snapshots()
	batch_boundaries()
	transition_preserves_state()
	reward_and_clear_boundaries()
	account_boundary()
	print("Courtyard route checks: %d; failures: %d" % [checks, failures])
	return failures

func configuration_and_sources():
	var battle = Route.new()
	check(battle.configure().ok, "default configures")
	if not battle.error.is_empty(): return
	check(battle.room_index == 1 and battle.room_total == battle._route_catalog.get_active_room_count() and battle.room_revision == 1, "starts first of authored active route")
	check(battle.phase == "choosing" and battle.clear_count == 0 and battle.cleared_rooms.is_empty(), "choice is not clear")
	check(battle.initial_choices().map(func(choice): return choice.id) == ["F01", "F03", "F08"], "formal fire starters replace archived spirit in Route only")
	check(not battle.choose_initial("F10"), "support not silently added as starter")
	check(battle.eligible_reward_ids().size() == 57, "sixty implemented spells minus three unmet source prerequisites")
	var standalone = First.new()
	check(standalone.configure().ok, "original single room configures")
	check(battle.player == standalone.player, "baseline player attributes unchanged")
	var original_base: Dictionary=battle._base.duplicate(true)
	original_base.erase("ice_mechanics")
	original_base.erase("lightning_mechanics")
	for school in ["wind", "earth", "spirit"]: original_base.erase(school + "_mechanics")
	for id in original_base.spells.keys():
		if str(original_base.spells[id].get("school", "")) in ["wind", "earth"] or str(id).begins_with("S"): original_base.spells.erase(id)
	for id in ["I01","I02","I03","I04","I05","I06","I07","I08","I09","I10"]: original_base.spells.erase(id)
	for id in ["L01","L02","L03","L04","L05","L06","L07","L08","L09","L10"]: original_base.spells.erase(id)
	for id in original_base.spells:
		original_base.spells[id].erase("growth_version")
		original_base.spells[id].levels = standalone._base.spells[id].levels.duplicate(true)
	check(original_base == standalone._base and battle._ordinary == standalone._ordinary and battle._meta == standalone._meta and battle._economy == standalone._economy, "formal growth changes spell levels only; historical player, room, economy and meta values stay intact")
	check(battle._runtime.M01 == standalone._runtime.M01 and battle._runtime.bolt_collision_radius == standalone._runtime.bolt_collision_radius, "original movement and bolt data untouched")
	check(not battle.get_summary().account_rewards and battle.get_summary().preview_only, "route excludes account rewards")
	check(battle.dust == 0 and battle.gold == int(battle._economy.currency.initial), "no invented initial currency")
	var summary: Dictionary = battle.get_summary()
	summary.cleared_rooms.append(42)
	check(battle.cleared_rooms.is_empty(), "summary ledger independent")
	for fps in [30,60,144]:
		var timed = fresh()
		for frame in fps: timed.step(1.0/float(fps))
		check(near(timed.time,1) and near(timed.room_time,1), "same fixed simulation at %d FPS" % fps)

func geometry_and_snapshots():
	var catalog = Catalog.new()
	check(catalog.load_catalog().ok, "catalogue loads")
	var battle = fresh()
	var total := 0
	for room_id in range(1,battle.room_total+1):
		battle._enter_room(room_id)
		var authored: Dictionary = catalog.get_room(room_id)
		var geometry: Dictionary = authored.geometry
		check(battle.room_size == Vector2(geometry.floor.width,geometry.floor.depth), "authored dimensions %d" % room_id)
		check(battle.player.pos == Vector2(geometry.entry_player_center[0],geometry.entry_player_center[1]) and battle.player.previous == battle.player.pos, "real entry %d" % room_id)
		check(battle.portal.pos == Vector2(geometry.portal_center[0],geometry.portal_center[1]), "portal aligns %d" % room_id)
		check(battle.blocks.size() == geometry.blocks.size(), "physical covers align %d" % room_id)
		check(battle.line_is_clear(battle.player.pos,battle.portal.pos), "central route open %d" % room_id)
		check(battle._body_clear(battle.player.pos,battle.player.radius) and battle._body_clear(battle.portal.pos,battle.player.radius), "walkable endpoints %d" % room_id)
		for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			check(battle._inside_floor(battle.move_body(battle.player.pos,direction*100,battle.player.radius),battle.player.radius), "physical perimeter %d" % room_id)
		var snap: Dictionary = battle.get_snapshot()
		check(snap.room_geometry == geometry and snap.template_id == authored.template_id, "same source snapshot geometry %d" % room_id)
		var count := 0
		for pack in authored.encounter.packs: count += pack_count(pack)
		total += count
		if room_id == 15: check(total == 105, "first fifteen use unchanged 104 non-Boss and one Boss")
		check(snap.spawn_total == count and snap.spawned_total == 0 and snap.batch_count == authored.encounter.packs.size(), "dictionary packs counted %d" % room_id)
		check(not snap.spawn_warnings.is_empty(), "north reservation exists %d" % room_id)
		for warning in snap.spawn_warnings:
			check(warning.pos.y > 0 and warning.pos.y < battle.portal.pos.y, "preview by north door %d" % room_id)
			check(warning.remaining > 0 and not battle.portal.usable, "spawn light is not usable portal")
		snap.room_geometry.blocks.clear()
		snap.blocks.clear()
		check(not battle.get_snapshot().room_geometry.blocks.is_empty() and not battle.blocks.is_empty(), "snapshot immutable %d" % room_id)
	check(total > 0 and battle.cleared_rooms.is_empty(), "finite authored mixed total and no fixture clears")

func batch_boundaries():
	var battle = room_fixture(5)
	var packs: Array = battle._packs.duplicate(true)
	var first_count := pack_count(packs[0])
	var second_count := pack_count(packs[1])
	check(packs.size() == 2 and first_count == 3 and second_count == 4, "non-Boss fan teaching has mixed plus reinforcement packs")
	advance(battle,float(battle._ordinary.spawn.preview_seconds))
	check(battle.actors.size() == first_count and battle._batch_index == 1 and not battle._spawn_done, "first batch not whole clear")
	check(battle.actors.map(func(enemy): return enemy.type_id).has("M05"), "genuine fan source in teaching pack")
	for enemy in battle.actors:
		check(enemy.health == enemy.max_health and enemy.radius > 0 and enemy.damage > 0, "genuine actor specs")
	var last_id: int = battle.actors.back().id
	advance(battle,0.02)
	check(alive_count(battle) == 3 and battle.spawn_warnings.is_empty(), "3+4 exceeds cap and queues whole pack")
	check(battle.clear_count == 0 and not battle.portal.visible, "pending pack prevents clear")
	for enemy in battle.actors:
		if enemy.health > 0:
			battle.damage_enemy(enemy,enemy.health)
			break
	var shield: float = battle.player.shield
	var cd: float = battle.spells[0].remaining
	advance(battle,1.0/120.0)
	check(battle.spawn_warnings.size() == second_count and battle.actors.size() == first_count, "whole pack reserves only when allowed")
	check(battle.player.shield == shield and battle.spells[0].remaining <= cd, "no refill or cooldown reset between batches")
	var state: Dictionary = battle.get_snapshot()
	battle.set_paused(true)
	advance(battle,2,Vector2.UP)
	check(battle.get_snapshot() == state.merged({"paused":true},true), "pause freezes warnings actors projectiles and clocks")
	battle.set_paused(false)
	advance(battle,float(battle._ordinary.spawn.preview_seconds))
	check(battle.actors.size() == first_count+second_count and battle._spawn_done and battle._batch_index == 2, "all packs activate once")
	check(alive_count(battle) <= int(battle._current_room.alive_cap), "actual non-Boss live hard cap retained")
	check(battle.actors.back().id > last_id and battle._spawned_total == battle._spawn_total, "unique ids and exact total")
	clear_fixture(battle)
	check(battle.phase == "pickup" and battle.get_snapshot().reward_pickup.kind == "spell" and battle.clear_count == 1 and battle.cleared_rooms == [5], "ordinary clear places physical spell book")
	var gold: int = battle.gold
	battle._check_clear()
	check(battle.gold == gold and battle.clear_count == 1, "clear cannot duplicate rewards")

func transition_preserves_state():
	var battle = fresh()
	clear_fixture(battle)
	check(battle.phase == "pickup" and touch_reward(battle) and choose_growth(battle), "first clear physically picks up book then accepts growth")
	var inventory: Array = battle.spells.duplicate(true)
	battle.player.health -= 17
	battle.spells[0].remaining = 0.73
	var before: Dictionary = battle.get_summary()
	var revision: int = battle.room_revision
	check(use_portal(battle), "actual movement reaches portal without teleport")
	check(battle.room_index == 2 and battle.room_revision == revision+1 and battle.phase == "combat", "actual portal advances one room")
	check(battle.player.health == before.health and battle.player.shield == battle.player.max_shield, "health and clear shield persist")
	check(battle.spells.size() == inventory.size() and battle.spells[0].level == inventory[0].level and near(battle.spells[0].remaining,0.73), "inventory level and cooldown persist")
	check(battle.kills == before.kills and battle.damage_dealt == before.damage_dealt and battle.casts == before.casts and battle.time > before.time and near(battle.combat_time,before.combat_time), "whole-route counters retained while total exit travel is counted")
	check(near(battle.room_time,0) and battle.actors.is_empty() and battle.projectiles.is_empty() and battle.get_snapshot().get("enemy_projectiles",[]).is_empty() and not battle.spirit.active and battle.effects.is_empty(), "transient combat objects cleared")
	check(not battle.portal.visible and not battle.portal.usable and battle.cleared_rooms == [1], "new portal locked with no invented clear")
	advance(battle,0.1,Vector2(0,1))
	check(battle.room_index == 2 and battle.room_revision == revision+1, "held move cannot skip new room")
	check(battle.spells[0].remaining < 0.73 and battle.spells[0].remaining > 0.62, "new combat resumes cooldown")
	var frozen: Dictionary = battle.get_snapshot()
	battle.set_paused(true)
	advance(battle,5,Vector2.UP)
	check(near(battle.time,frozen.time) and near(battle.room_time,frozen.room_time) and battle.player.pos == frozen.player.pos, "pause no catch-up")

func reward_and_clear_boundaries():
	var battle = fresh()
	var expected_gold: int = int(battle._economy.currency.initial)
	var claimed_count := 0
	for room_id in range(1,battle.room_total+1):
		battle._enter_room(room_id)
		clear_fixture(battle)
		check(battle.clear_count == room_id and battle.cleared_rooms == range(1,room_id+1), "one sequential ledger clear %d" % room_id)
		for stage in battle._economy.stages:
			if room_id >= int(stage.from) and room_id <= int(stage.to):
				expected_gold += int(stage.clear_gold)
				if str(battle._current_room.encounter.kind) in ["elite", "elite_guard", "boss"]:
					expected_gold += int(stage.elite_bonus)
		while battle.phase == "pickup":
			var artifact_room: bool = str(battle.reward_pickup.kind) == "artifact"
			check(battle.phase == "pickup" and battle.get_snapshot().reward_pickup.visible, "nonempty reward creates real pending pickup")
			check(not choose_growth(battle) and not choose_artifact(battle), "UI cannot bypass walking to reward")
			var waiting: Dictionary = battle.get_snapshot()
			advance(battle,0.5)
			check(near(battle.time, float(waiting.time)+0.5) and near(battle.combat_time,waiting.combat_time) and battle.spells == waiting.spells, "waiting reward advances only total timer")
			check(touch_reward(battle), "physical reward contact opens cards")
			check((battle.phase == "artifact") == artifact_room and (battle.phase == "reward") == (not artifact_room), "source growth or treasure gate %d" % room_id)
			check(not battle.portal.usable, "nonempty required reward cannot be bypassed")
			var frozen: Dictionary = battle.get_snapshot()
			advance(battle,3,Vector2.RIGHT)
			check(without_elapsed(battle.get_snapshot()) == without_elapsed(frozen) and near(battle.time,float(frozen.time)+3), "card freezes rules while total selection time advances")
			if artifact_room:
				var choices: Array = battle.get_snapshot().get("artifact_choices",[])
				check(not choices.is_empty() and choices.size() <= 3 and battle.reward_choices.is_empty(), "treasure has one to three legal items")
				check(not battle.choose_artifact("invalid"), "invalid treasure rejected")
				check(choose_artifact(battle), "offered treasure accepted")
				claimed_count += 1
				check(not battle.choose_artifact(str(choices[0].id)), "treasure cannot be claimed twice")
				check(battle.get_snapshot().artifacts.size() == claimed_count, "inventory only grows on actual claim")
			else:
				for choice in battle.reward_choices: check(battle._base.spells.has(choice.id), "real implemented spell offer")
				check(choose_growth(battle), "real offered spell selected")
		check(battle.phase == "exit" and battle.portal.visible and battle.portal.usable, "claimed or exhausted reward opens exit")
		if room_id == 15:
			check(battle.kills == 105 and claimed_count == 3, "first fifteen use approved encounter count and preserve three treasure claims")
			check(battle.gold == expected_gold, "first fifteen use actual elite income without boss bonus")
	check(battle.gold == expected_gold and battle.dust == 0, "authored stage clear and elite gold with zero account dust")

	var exhausted = fresh()
	exhausted.spells.clear()
	for spell_id in exhausted.eligible_reward_ids().slice(0,8):
		var spell: Dictionary = exhausted._new_spell(spell_id)
		spell.level = int(exhausted._base.limits.spell_level)
		exhausted._refresh_spell(spell)
		exhausted.spells.append(spell)
	check(exhausted.eligible_reward_ids().size() == 49, "eight maxed slots retain forty-nine currently qualified unowned replacement candidates")
	clear_fixture(exhausted)
	check(exhausted.phase == "pickup" and not exhausted.portal.usable and exhausted.reward_choices.size() == 3, "maxed loadout still places the real three-card book")
	check(touch_reward(exhausted), "replacement fixture physically opens the maxed-loadout book")
	var replacement_id: String = str(exhausted.reward_choices[0].id)
	check(exhausted.choose_reward(replacement_id, exhausted.room_revision) and exhausted.phase == "reward" and not exhausted.pending_replacement.is_empty(), "new reward waits for a specified old slot")
	check(exhausted.confirm_spell_replacement(7, int(exhausted.pending_replacement.get("request_id", -1)), exhausted.room_revision), "explicit maxed fixture confirms replacement of slot eight")
	check(exhausted.phase == "exit" and exhausted.portal.usable and exhausted.spells.size() == 8 and exhausted.spells[7].id == replacement_id and exhausted.spells[7].level == 1, "specified slot becomes the new level-one spell without a ninth slot")
	var dead = fresh()
	dead.damage_player(dead.player.health+dead.player.shield)
	var time_before: float = dead.time
	advance(dead,2,Vector2.UP)
	check(dead.phase == "dead" and dead.cleared_rooms.is_empty() and dead.room_index == 1 and near(dead.time,time_before), "death cannot spawn use portal or clear")

func account_boundary():
	var path: String = Meta.TEST_SAVE_ROOT+"route_boundary_%d.json" % Time.get_ticks_usec()
	var meta = Meta.new(path)
	check(meta.load_state().ok, "isolated account loads")
	var initial: Dictionary = meta.get_state()
	var bytes: String = FileAccess.get_file_as_string(path)
	var started: Dictionary = meta.begin_run()
	check(started.ok and started.snapshot.preview_only, "route equipment lock is non-account run")
	var battle = Route.new()
	check(battle.configure(started.snapshot,29).ok and battle.choose_initial("F01"), "actual prepared equipment accepted")
	clear_fixture(battle)
	check(battle.cleared_rooms == [1] and not meta.settle_playable_run("map-trial",battle.cleared_rooms).ok, "real clear cannot credit non-account run")
	check(meta.end_run().ok and not meta.is_in_run(), "exit releases equipment lock")
	check(meta.get_state() == initial and FileAccess.get_file_as_string(path) == bytes, "account dust serial saved bytes unchanged")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
