extends RefCounted
## Reusable deterministic movement-only pilot plus real continuous-route checks.
## It reads warnings/geometry and submits movement/actual reward choices only.
const Route = preload("res://scripts/core/courtyard_route_run.gd")
const First = preload("res://scripts/core/first_room_run.gd")
var checks: int = 0
var failures: int = 0
var metrics: Array = []
var direction_count: int = 16
var growth_order: Array = ["F01","F08","F07","F03","F11","F02","F10","F06","F05","F09"]
var last_growth_decision: Dictionary = {}
var _decision_room: int = -1
var _decision_time: float = -INF
var _heading: Vector2 = Vector2.ZERO

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		push_error("Route rebalance: "+label)

func reset_policy():
	_decision_room = -1
	_decision_time = -INF
	_heading = Vector2.ZERO

func choose_growth(battle) -> bool:
	if battle.phase != "reward": return false
	var rank: Array = growth_order + ["I01","I02","I03","I05","I10","I07","I08","I09","I06","I04"]
	last_growth_decision = {}
	# The pilot keeps a completed build when the actual full-slot offer is all
	# new. It still resolves all configured books through the public reward transaction.
	for owned_only in [true, false]:
		if not owned_only and battle.can_skip_spell_reward():
			last_growth_decision = {"action": "skip", "spell_id": ""}
			return battle.skip_spell_reward(battle.room_revision)
		for id in rank:
			if (not battle._owned_spell(str(id)).is_empty()) != owned_only: continue
			for choice in battle.reward_choices:
				if choice.id != id: continue
				if not battle.choose_reward(str(id), battle.room_revision): return false
				last_growth_decision = {"action": "upgrade" if owned_only else "learn", "spell_id": str(id)}
				if battle.pending_replacement.is_empty(): return battle.phase == "exit"
				var selected_slot: int = 0
				var worst_rank: int = -1
				for index in battle.spells.size():
					var current_rank: int = rank.find(str(battle.spells[index].id))
					if current_rank < 0: current_rank = rank.size()
					if current_rank > worst_rank:
						worst_rank = current_rank
						selected_slot = index
				last_growth_decision["action"] = "replace"
				last_growth_decision["old_spell_id"] = str(battle.spells[selected_slot].id)
				last_growth_decision["slot_index"] = selected_slot
				return battle.confirm_spell_replacement(selected_slot, int(battle.pending_replacement.request_id), battle.room_revision)
	return false

func choose_artifact(battle) -> bool:
	var choices: Array = battle.get_snapshot().get("artifact_choices",[])
	for preferred in ["U03","U02","U01","P01","B01","B07","P04","P05"]:
		for choice in choices:
			if str(choice.id) == preferred: return battle.choose_artifact(preferred)
	return not choices.is_empty() and battle.choose_artifact(str(choices[0].id))

func autoplay_direction(battle) -> Vector2:
	if battle.phase in ["pickup", "exit", "shop"]:
		var destination: Vector2 = battle.portal.pos
		if battle.phase == "pickup":
			var pickup: Dictionary = battle.get_snapshot().get("reward_pickup", {})
			if pickup.is_empty() or not bool(pickup.get("visible", false)):
				return Vector2.ZERO
			destination = pickup.pos
		var waypoint: Vector2 = battle._chase_position(battle.player.pos,destination,1.0,battle.player.radius)
		var exit_direction: Vector2 = (waypoint-battle.player.pos).normalized()
		return _snap_direction(exit_direction)
	if battle.phase != "combat": return Vector2.ZERO
	if _decision_room == battle.room_revision and float(battle.time)-_decision_time < 1.0/12.0:
		return _heading
	_decision_room = battle.room_revision
	_decision_time = float(battle.time)
	var origin: Vector2 = battle.player.pos
	var target: Dictionary = {}
	var closest: float = INF
	for enemy in battle.actors:
		if enemy.health <= 0: continue
		var distance: float = origin.distance_to(enemy.pos)
		if distance < closest:
			closest = distance
			target = enemy
	var intent: Vector2 = Vector2.ZERO
	if target.is_empty():
		intent = (battle.portal.pos-Vector2(0,5)-origin).normalized()
	else:
		var radial: Vector2 = (target.pos-origin).normalized()
		intent = radial*clampf((closest-5.2)*0.6,-1,1)+radial.orthogonal()*0.5
		if battle._first_block_contact(origin,target.pos,0.35) != INF:
			intent = (battle._chase_position(origin,target.pos,1.0,battle.player.radius)-origin).normalized()
	var choices: Array = [Vector2.ZERO]
	for index in direction_count: choices.append(Vector2.RIGHT.rotated(TAU*float(index)/float(direction_count)))
	var best: float = -INF
	var chosen: Vector2 = Vector2.ZERO
	var snapshot: Dictionary = battle.get_snapshot()
	for direction in choices:
		var position: Vector2 = battle.move_body(origin,direction*float(battle.player.move_speed)*0.5,battle.player.radius)
		var score: float = direction.dot(intent)*2.0+direction.dot(_heading)*0.15
		if target.is_empty():
			score -= position.distance_to(battle.portal.pos-Vector2(0,5))*0.6
		else:
			score -= absf(position.distance_to(target.pos)-5.2)*0.8
			if battle._first_block_contact(position,target.pos,0.35) == INF: score += 4.0
			else: score -= 6.0
		var edge: float = minf(battle.room_size.x*0.5-absf(position.x),battle.room_size.y*0.5-absf(position.y))
		if edge < 1.2: score -= (1.2-edge)*5
		if direction.length_squared() > 0.1 and position.distance_to(origin) < 0.5: score -= 8
		for enemy in battle.actors:
			if enemy.health <= 0: continue
			var distance: float = position.distance_to(enemy.pos)
			if distance < 2.2: score -= (2.2-distance)*4
			var danger: Dictionary = enemy.get("danger",{})
			if danger.is_empty(): continue
			if danger.kind == "circle":
				var clearance: float = position.distance_to(danger.pos)-float(danger.radius)-float(battle.player.radius)
				if clearance < 0.5: score -= (0.5-clearance)*45
			elif danger.kind == "lane":
				var reach: float = float(danger.radius)+float(battle.player.radius)+0.25
				if battle.segment_circle_time(danger.from,danger.to,position,reach) != INF: score -= 45
			elif danger.kind in ["ray","fan"]:
				var base_dir: Vector2 = (danger.to-danger.from).normalized()
				var angles: Array = danger.get("spread_degrees",[0.0])
				for angle in angles:
					var ray_to: Vector2 = danger.from+base_dir.rotated(deg_to_rad(float(angle)))*15
					if battle.segment_circle_time(danger.from,ray_to,position,float(battle.player.radius)+float(danger.radius)+0.12) != INF: score -= 9
		for projectile in snapshot.get("enemy_projectiles",[]):
			var projectile_to: Vector2 = projectile.pos+projectile.direction*float(projectile.speed)*0.65
			if battle.segment_circle_time(projectile.pos-origin,projectile_to-position,Vector2.ZERO,float(projectile.radius)+float(battle.player.radius)+0.08) != INF:
				score -= 60
		if score > best:
			best = score
			chosen = direction
	_heading = chosen
	return chosen

func _snap_direction(direction: Vector2) -> Vector2:
	if direction.length_squared() < 0.000001: return Vector2.ZERO
	return Vector2.RIGHT.rotated(roundf(direction.angle()/TAU*float(direction_count))*TAU/float(direction_count))

func run() -> int:
	qualification_and_slots()
	synergy_runtime_damage()
	north_spawn_revalidation()
	if "--skip-natural-route" in OS.get_cmdline_user_args():
		print("Route rebalance: natural routes deferred by explicit validation scope; boundary checks: %d; failures: %d" % [checks, failures])
		return failures
	var starter_probe = Route.new()
	check(starter_probe.configure().ok, "formal starter enumeration configures")
	for starter in starter_probe.initial_choices().map(func(choice): return choice.id):
		natural_route(str(starter),20261017)
	# A legitimate support/control-first selection path checks that new elite
	# health does not require an early bomb or a prescribed damage artifact.
	growth_order = ["F10","F02","F06","F09","F05","F11","F03","F08","F01","F07"]
	natural_route("F01",20261023)
	growth_order = ["F01","F08","F07","F03","F11","F02","F10","F06","F05","F09"]
	print("Route rebalance checks: %d; failures: %d" % [checks,failures])
	return failures

func qualification_and_slots():
	var battle = Route.new()
	check(battle.configure().ok,"mixed route configures")
	check(battle.choose_initial("F01"),"real starting choice")
	var eligible: Array = battle.eligible_reward_ids()
	check(eligible.size() == 57,"sixty spells minus three unmet construction/summon prerequisites")
	for id in ["F01","F02","F03","F05","F06","F07","F08","F09","F10","F11"]:
		check(id in eligible,"active fire spell eligible "+str(id))
	for id in ["I01","I02","I03","I04","I05","I06","I07","I08","I09","I10"]:
		check(id in eligible,"active ice spell eligible "+str(id))
	for id in ["L01","L02","L03","L04","L05","L06","L07","L08","L09","L10"]:
		check(id in eligible,"active lightning spell eligible "+str(id))
	for prefix in ["W", "R", "S"]:
		for number in range(1, 11):
			var id: String = "%s%02d" % [prefix, number]
			check(battle._base.spells.has(id) and (id in eligible) == (id not in ["R06", "S05", "S07"]), "six school source and initial prerequisite " + id)
	check("F04" not in eligible, "archived spirit excluded from formal normal pool")
	battle.spells.clear()
	for id in eligible.slice(0,8): battle.spells.append(battle._new_spell(id))
	eligible = battle.eligible_reward_ids()
	check(eligible.size() == 57,"full eight slots permit held upgrades and unowned replacement candidates")
	check(eligible.filter(func(id): return battle._owned_spell(str(id)).is_empty()).size() == 49,"forty-nine new candidates require replacement rather than a ninth slot")
	for spell in battle.spells:
		spell.level = 3
		battle._refresh_spell(spell)
	check(battle.eligible_reward_ids().size() == 49 and battle.eligible_reward_ids().all(func(id): return battle._owned_spell(str(id)).is_empty()),"eight maxed spells retain only forty-nine new replacement candidates")
	var original = First.new()
	check(original.configure().ok and original.initial_choices().size() == 3,"standalone first room stays independent")

func synergy_runtime_damage():
	# Unit fixture: deterministic crit-free hit packages test the actual runner
	# hook, rather than relying only on the spell component's isolated harness.
	var battle = Route.new()
	check(battle.configure().ok and battle.choose_initial("F01"),"actual damage hook fixture configures")
	battle.player.crit_rate = 0.0
	battle.spells.append(battle._new_spell("F03"))
	var actor: Dictionary = battle._enemy_combat.make_actor(battle,"M01",Vector2.ZERO,1)
	battle.actors.append(actor)
	var context := {"spell_id":"F01","cast_id":1,"natural":true,"kind":"direct","damage_scale":1.0,"field_bonus":0.0}
	var hit: Dictionary = battle.resolve_spell_hit(actor,1.0,context)
	check(near(float(hit.damage),float(battle.player.attack)),"two fire spells do not receive three-fire bonus")
	battle.spells.append(battle._new_spell("F08"))
	actor = battle._enemy_combat.make_actor(battle,"M01",Vector2.ZERO,2)
	battle.actors.append(actor)
	hit = battle.resolve_spell_hit(actor,1.0,context)
	check(near(float(hit.damage),float(battle.player.attack)*(1.0+float(battle._base.fire_synergy.fire_bonus))),"actual runner applies three-fire source bonus")
	battle.spells[1] = battle._new_spell("F02")
	actor = battle._enemy_combat.make_actor(battle,"M01",Vector2.ZERO,3)
	battle.actors.append(actor)
	hit = battle.resolve_spell_hit(actor,1.0,context)
	var mastery: float = float(battle._base.spells.F02.levels[0].fire_bonus)
	check(near(float(hit.damage),float(battle.player.attack)*(1.0+mastery+float(battle._base.fire_synergy.fire_bonus))),"mastery and three-fire bonuses add in same source group")

func north_spawn_revalidation():
	var battle = Route.new()
	check(battle.configure().ok and battle.choose_initial("F01"),"spawn fixture configures")
	battle._enter_room(6)
	var warnings: Array = battle.get_snapshot().spawn_warnings
	check(warnings.size() == battle._pack_count(battle._packs[0]) and warnings[0].pos.y > 0,"whole elite pack reserves north with full preview")
	var pos: Vector2 = warnings[0].pos
	battle.player.pos = pos
	battle.player.previous = pos
	for tick in 98: battle.step(1.0/120.0)
	check(battle.actors.is_empty(),"walking into preview cannot activate damaging elite on player")
	check(not battle.spawn_warnings.is_empty() and battle.spawn_warnings[0].remaining > 0,"unsafe batch re-reserves with new full warning")
	check(battle.clear_count == 0 and not battle.portal.usable,"postponed spawn never counts as clear")
	for warning in battle.spawn_warnings:
		check(warning.pos.y > 0 and warning.pos.distance_to(battle.player.pos) >= float(battle._ordinary.spawn.safe_player_distance),"replacement stays north and safe")
	var frozen: Dictionary = battle.get_snapshot()
	battle.set_paused(true)
	for tick in 120: battle.step(1.0/120.0,Vector2.UP)
	check(battle.get_snapshot() == frozen.merged({"paused":true},true),"paused north batch remains frozen")

func natural_route(starter: String, seed_value: int) -> Dictionary:
	reset_policy()
	direction_count = 8
	var battle = Route.new()
	var configured: Dictionary = battle.configure({},seed_value)
	check(configured.ok and battle.choose_initial(starter),"natural route starts "+starter)
	if not configured.ok: return {}
	var report := {"starter":starter,"seed":seed_value,"growth_order":growth_order.duplicate(),"reward_rank_order":growth_order + ["I01","I02","I03","I05","I10","I07","I08","I09","I06","I04"],"reward_policy":"held upgrades first by rank; then new spells by rank; full/all-new books explicitly skipped; replacement fallback chooses lowest-ranked held spell, earliest slot breaks ties; all configured actual books resolved","spell_rewards":[],"policy":"eight-direction WASD warning-aware kiting; actual sampled rewards, no HP/phase cheats","rooms":[]}
	var expected_kills := 0
	var enemy_types: Dictionary = {}
	var artifact_rooms: Array = []
	for room_id in range(1,battle.room_total+1):
		check(battle.room_index == room_id and battle.phase == "combat","actual portal reached %s room %d" % [starter,room_id])
		var before_time: float = battle.time
		var before_combat: float = float(battle.get_snapshot().get("combat_time", battle.time))
		var before_damage: float = battle.damage_taken
		var observed_spawned := 0
		expected_kills += battle._spawn_total
		for tick in 120*180:
			if battle.phase != "combat": break
			battle.step(1.0/120.0,autoplay_direction(battle))
			if tick % 120 == 0 or int(battle._spawned_total) != observed_spawned:
				for enemy in battle.actors: enemy_types[str(enemy.type_id)] = true
				observed_spawned = int(battle._spawned_total)
		var row := {"room":room_id,"phase":battle.phase,"seconds":battle.time-before_time,"combat_seconds":float(battle.get_snapshot().get("combat_time", battle.time))-before_combat,"damage_taken":battle.damage_taken-before_damage,"health":battle.player.health,"shield":battle.player.shield,"kills":battle.kills,"spells":battle.spells.map(func(spell): return {"id":spell.id,"level":spell.level})}
		report.rooms.append(row)
		check(battle.phase in ["pickup","exit"] and battle.player.health > 0,"naturally clears %s room %d" % [starter,room_id])
		if battle.phase not in ["pickup","exit"]: break
		check(battle.kills == expected_kills and battle._spawned_total == battle._spawn_total,"every real actor defeated %s room %d" % [starter,room_id])
		check(battle.clear_count == room_id and battle.cleared_rooms == range(1,room_id+1),"actual monotonic clear ledger")
		if battle.phase == "pickup":
			var pickup_before: Dictionary = battle.get_snapshot()
			check(not battle.portal.usable and pickup_before.reward_pickup.visible, "physical pickup gates the visible portal")
			for tick in 120*30:
				if battle.phase != "pickup": break
				battle.step(1.0/120.0,autoplay_direction(battle))
			check(battle.phase in ["reward","artifact"], "walking reaches real reward object")
			check(float(battle.get_snapshot().combat_time) == float(pickup_before.combat_time) and battle.time >= float(pickup_before.time), "pickup travel advances total time but freezes combat clock")
		if room_id in battle._artifact_reward_rooms:
			check(battle.phase == "artifact" and battle.get_snapshot().artifact_choices.size() > 0 and battle.get_snapshot().artifact_choices.size() <= 3,"real dedicated elite artifact gate after chest contact")
		if battle.phase == "reward":
			var offered_ids: Array = battle.reward_choices.map(func(choice): return str(choice.id))
			check(choose_growth(battle),"actual offered growth or legal preserve-build skip selected")
			var decision: Dictionary = last_growth_decision.duplicate(true)
			decision["room"] = room_id
			decision["offered_ids"] = offered_ids
			report.spell_rewards.append(decision)
		if battle.phase == "artifact":
			check(choose_artifact(battle),"actual offered artifact selected")
			artifact_rooms.append(room_id)
		check(battle.spells.size() <= 8,"route never exceeds eight slots")
		if room_id == 15:
			check(battle.kills == 77 and artifact_rooms == [6,12,15],"unchanged first-fifteen enemy and treasure baseline")
		var before_exit: Dictionary = battle.get_snapshot()
		var health_before_exit: float = battle.player.health
		for tick in 120*20:
			if battle.room_index != room_id or battle.phase == "complete": break
			battle.step(1.0/120.0,autoplay_direction(battle))
		check(battle.time > float(before_exit.time) and near(float(battle.get_snapshot().combat_time), float(before_exit.combat_time)) and battle.player.health == health_before_exit,"exit travel advances total clock while combat clock and health stay frozen")
		check(battle.room_index != room_id or battle.phase == "complete","pilot follows physical route to portal")
		if battle.room_index == room_id and battle.phase != "complete": break
	report["result"] = battle.phase
	report["summary"] = battle.get_summary()
	report["enemy_types"] = enemy_types.keys()
	report["artifact_rooms"] = artifact_rooms
	report["last_player_pos"] = str(battle.player.pos)
	report["last_actors"] = battle.actors.map(func(enemy): return {"id":enemy.type_id,"pos":str(enemy.pos),"phase":enemy.phase,"health":enemy.health})
	metrics.append(report)
	check(battle.phase == "complete" and battle.clear_count == battle.room_total and battle.room_index == battle.room_total,"natural route completes "+starter)
	check(report.spell_rewards.size() == battle._reward_rooms.size(),"natural pilot explicitly resolves all configured real spell books")
	check(battle.kills == expected_kills and enemy_types.size() == 7,"natural route encounters real mixed roster")
	check(artifact_rooms == battle._artifact_reward_rooms and battle.get_snapshot().get("artifacts",[]).size() == battle._artifact_reward_rooms.size(),"all real acquired treasure items persist to completion")
	check(not battle.get_summary().account_rewards and battle.dust == 0,"natural complete route remains local non-account trial")
	return report

func near(a: float,b: float) -> bool:
	return absf(a-b) < 0.0001
