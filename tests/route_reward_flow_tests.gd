extends RefCounted
## Rule fixtures isolate reward contacts and clocks. Enemy damage is controlled
## only to arrange a clear; every reward/portal contact uses real movement.
## These fixtures are not claimed as a natural playthrough or rendered evidence.

const Route = preload("res://scripts/core/courtyard_route_run.gd")
const First = preload("res://scripts/core/first_room_run.gd")
var checks: int = 0
var failures: int = 0


func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		push_error("Route reward flow: " + label)


func near(a: float, b: float) -> bool:
	return absf(a-b) < 0.0001


func without_elapsed(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	result.erase("time")
	result.erase("room_time")
	return result


func advance(battle, seconds: float, direction: Vector2 = Vector2.ZERO):
	for _index in roundi(seconds*120.0):
		battle.step(1.0/120.0,direction)


func clear_fixture(room: int = 1):
	var battle = Route.new()
	check(battle.configure({},20261017).ok and battle.choose_initial("F01"), "reward boundary fixture configures")
	if room != 1:
		battle._enter_room(room)
	for _index in 120*60:
		if battle.phase != "combat": break
		battle.step(1.0/120.0)
		for actor in battle.actors:
			if actor.health > 0.0:
				battle.damage_enemy(actor,float(actor.health))
	check(battle.phase == "pickup", "clear leaves a physical pending reward in room " + str(room))
	return battle


func walk_to(battle, destination: Vector2, phase: String, limit: int = 120*30) -> bool:
	for _index in limit:
		if battle.phase != phase: return true
		if battle.player.pos.distance_to(destination) < 0.035: return true
		var waypoint: Vector2 = battle._chase_position(battle.player.pos,destination,1.0,battle.player.radius)
		battle.step(1.0/120.0,(waypoint-battle.player.pos).normalized())
	return false


func touch_reward(battle) -> bool:
	var pickup: Dictionary = battle.get_snapshot().get("reward_pickup", {})
	return not pickup.is_empty() and walk_to(battle,pickup.pos,"pickup") and battle.phase in ["reward","artifact"]


func take_first(battle) -> bool:
	if battle.phase == "reward" and not battle.reward_choices.is_empty():
		if battle.can_skip_spell_reward(): return battle.skip_spell_reward(battle.room_revision)
		if not battle.choose_reward(str(battle.reward_choices[0].id), battle.room_revision): return false
		if battle.pending_replacement.is_empty(): return battle.phase == "exit"
		# This is a controlled contact fixture, not the natural growth pilot.
		# Confirm a deterministic weakest-level slot if the first card is new.
		var selected_slot: int = 0
		for index in battle.spells.size():
			if int(battle.spells[index].level) < int(battle.spells[selected_slot].level): selected_slot = index
		return battle.confirm_spell_replacement(selected_slot, int(battle.pending_replacement.request_id), battle.room_revision)
	if battle.phase == "artifact":
		var choices: Array = battle.get_snapshot().get("artifact_choices", [])
		return not choices.is_empty() and battle.choose_artifact(str(choices[0].id))
	return false


func run() -> int:
	book_and_chest_contacts()
	clock_boundaries()
	swept_pickup_contact()
	no_bypass_or_duplicate()
	standalone_boundary()
	print("Route reward flow checks: %d; failures: %d" % [checks,failures])
	return failures


func book_and_chest_contacts():
	# Boss book+chest transactions have their separate dedicated rules suite.
	for room in [1,6,12,21]:
		var battle = clear_fixture(room)
		if battle.phase != "pickup": continue
		var before: Dictionary = battle.get_snapshot()
		var pickup: Dictionary = before.reward_pickup
		var kind: String = "spell" if room == 1 else "artifact"
		check(pickup.kind == kind and pickup.visible and not pickup.claimed and float(pickup.radius) > 0.0, "source book/chest kind and visible unclaimed footprint")
		check(battle._body_clear(pickup.pos,float(battle.player.radius)), "reward center is actually reachable")
		check(battle.portal.visible and not battle.portal.usable, "clear reveals gate but locks it behind physical reward")
		check(not battle.choose_reward("F01") and not battle.choose_artifact("U01"), "choice requests rejected before object contact")
		var altered: Dictionary = battle.get_snapshot()
		altered.reward_pickup.visible = false
		altered.reward_pickup.pos = Vector2(1000,1000)
		check(battle.get_snapshot().reward_pickup == pickup, "pickup snapshot is a deep read-only copy")
		check(touch_reward(battle), "real walking contact opens book/chest cards")
		var card: Dictionary = battle.get_snapshot()
		check(battle.phase == ("reward" if kind == "spell" else "artifact"), "correct card type follows physical contact")
		check(card.reward_choices == before.reward_choices and card.artifact_choices == before.artifact_choices, "walking and opening use same cached candidates")
		check(take_first(battle), "actual cached choice grants reward")
		var after: Dictionary = battle.get_snapshot()
		check(battle.phase == "exit" and battle.portal.usable and not after.reward_pickup.visible and after.reward_pickup.claimed, "claim consumes object and unlocks gate")
		if kind == "artifact":
			check(after.spells == before.spells and after.artifacts.size() == before.artifacts.size()+1, "artifact stays outside spell slots")


func clock_boundaries():
	var battle = clear_fixture()
	if battle.phase != "pickup": return
	var pickup: Dictionary = battle.get_snapshot()
	advance(battle,0.75)
	var waited: Dictionary = battle.get_snapshot()
	check(near(waited.time,pickup.time+0.75) and near(waited.room_time,pickup.room_time+0.75), "standing by book counts total and current-room time")
	check(near(waited.combat_time,pickup.combat_time) and waited.spells == pickup.spells and waited.actors == pickup.actors, "waiting pickup leaves combat clock cooldown and enemies frozen")
	battle.set_paused(true)
	var paused: Dictionary = battle.get_snapshot()
	advance(battle,1.0,Vector2.UP)
	check(battle.get_snapshot() == paused, "pause freezes total clock as well as pending reward")
	battle.set_paused(false)
	check(touch_reward(battle), "clock fixture physically takes book")
	var card: Dictionary = battle.get_snapshot()
	advance(battle,1.25,Vector2.RIGHT)
	var thought: Dictionary = battle.get_snapshot()
	check(near(thought.time,card.time+1.25) and near(thought.room_time,card.room_time+1.25), "card decision counts route and room elapsed time")
	check(without_elapsed(thought) == without_elapsed(card), "only elapsed clocks advance while choosing cards")
	battle.set_paused(true)
	paused = battle.get_snapshot()
	advance(battle,0.5)
	check(battle.get_snapshot() == paused, "manual pause during card freezes even elapsed clocks")
	battle.set_paused(false)
	check(take_first(battle), "clock fixture chooses offered spell")
	var exit_before: Dictionary = battle.get_snapshot()
	advance(battle,0.5)
	var exit_wait: Dictionary = battle.get_snapshot()
	check(near(exit_wait.time,exit_before.time+0.5) and near(exit_wait.combat_time,exit_before.combat_time), "standing at open gate counts total time without combat progression")
	check(exit_wait.spells == exit_before.spells and exit_wait.player.health == exit_before.player.health, "open-gate wait cannot cool spells or damage player")
	check(walk_to(battle,battle.portal.pos,"exit") and battle.room_index == 2, "clock fixture walks into next room")
	var next: Dictionary = battle.get_snapshot()
	check(next.time > exit_wait.time and near(next.room_time,0.0) and near(next.combat_time,exit_wait.combat_time), "cross-room movement counts route time and resets only room timer")
	advance(battle,0.25)
	check(near(battle.combat_time,next.combat_time+0.25) and near(battle.time,next.time+0.25), "new combat advances both clocks")
	var summary: Dictionary = battle.get_summary()
	check(near(summary.time,battle.time) and near(summary.combat_time,battle.combat_time) and summary.time > summary.combat_time, "summary distinguishes full route and combat time")


func swept_pickup_contact():
	var battle = clear_fixture()
	if battle.phase != "pickup": return
	var pickup: Dictionary = battle.get_snapshot().reward_pickup
	var direction: Vector2 = (battle.player.pos-pickup.pos).normalized()
	if direction.is_zero_approx(): direction = Vector2.DOWN
	var contact_radius: float = float(pickup.radius)+float(battle.player.radius)
	var start: Vector2 = pickup.pos+direction*(contact_radius+0.16)
	check(walk_to(battle,start,"pickup") and battle.phase == "pickup", "walks to just outside pickup without teleporting")
	if battle.phase != "pickup": return
	check(battle.player.pos.distance_to(pickup.pos) > contact_radius, "sweep boundary starts outside object footprint")
	# A private integration-boundary fixture crosses the entire footprint in one
	# update. It uses the configured speed and never changes player position/speed.
	var dt: float = (2.0*contact_radius+0.5)/float(battle.player.move_speed)
	battle._tick(dt,-direction)
	check(battle.phase == "reward", "continuous contact catches a stride whose endpoint passed the pickup")
	check(not battle.portal.usable and battle.room_index == 1, "swept object contact still cannot skip reward gate")


func no_bypass_or_duplicate():
	for room in [1,6]:
		var battle = clear_fixture(room)
		if battle.phase != "pickup": continue
		var before: Dictionary = battle.get_snapshot()
		for _repeat in 3:
			battle._check_clear()
		check(battle.get_snapshot() == before, "rechecking clear cannot duplicate pickup or reroll candidates")
		check(walk_to(battle,battle.portal.pos,"pickup"), "player can attempt to walk toward locked portal")
		check(battle.room_index == room and battle.phase in ["pickup","reward","artifact"] and not battle.portal.usable, "walking through gate before claim never changes room")
		if battle.phase == "pickup":
			check(touch_reward(battle), "gate bypass attempt must return to physical reward")
		check(take_first(battle), "claim remains possible after attempted bypass")
		var claimed: Dictionary = battle.get_snapshot()
		check(not battle.choose_reward("F01") and not battle.choose_artifact("U01"), "duplicate direct claim requests are idempotent")
		var former: Vector2 = before.reward_pickup.pos
		var away: Vector2 = former+Vector2(0.0,-2.0)
		check(walk_to(battle,away,"exit") and walk_to(battle,former,"exit"), "leaves and reenters former pickup by walking")
		var returned: Dictionary = battle.get_snapshot()
		check(returned.phase == "exit" and returned.spells == claimed.spells and returned.artifacts == claimed.artifacts and not returned.reward_pickup.visible, "reentering claimed footprint never reopens or repeats reward")


func standalone_boundary():
	var battle = First.new()
	check(battle.configure({},20261017).ok and battle.choose_initial("F01"), "independent first-room boundary configures")
	for _index in 120*30:
		if battle.phase != "combat": break
		battle.step(1.0/120.0)
		for actor in battle.actors:
			if actor.health > 0.0: battle.damage_enemy(actor,actor.health)
	check(battle.phase == "reward" and not battle.get_snapshot().has("reward_pickup"), "legacy independent first room retains direct last-reward contract")
