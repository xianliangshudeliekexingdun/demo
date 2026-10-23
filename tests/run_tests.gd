extends SceneTree
const Battle = preload("res://scripts/core/battle.gd")
const Clock = preload("res://scripts/core/battle_clock.gd")
var failures = 0
var checks = 0
var linked_checks: int = 0
var linked_failures: int = 0
var suite_results: Array = []

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func near(a: float, b: float) -> bool:
	return absf(a-b) < 0.0001

func _initialize():
	call_deferred("run")

func run():
	_run_suite(preload("res://tests/first_room_tests.gd"), "first_room")
	_run_suite(preload("res://tests/courtyard_route_tests.gd"), "courtyard_route")
	_run_suite(preload("res://tests/route_enemy_tests.gd"), "route_enemies")
	_run_suite(preload("res://tests/route_enemy_pressure_tests.gd"), "route_enemy_pressure")
	_run_suite(preload("res://tests/nonboss_difficulty_tests.gd"), "nonboss_difficulty")
	_run_suite(preload("res://tests/enemy_damage_growth_tests.gd"), "enemy_damage_growth")
	_run_suite(preload("res://tests/route_boss_tests.gd"), "route_bosses")
	_run_suite(preload("res://tests/route_reward_flow_tests.gd"), "route_reward_flow")
	_run_suite(preload("res://tests/spell_growth_tests.gd"), "spell_growth")
	_run_suite(preload("res://tests/route_rebalance_tests.gd"), "route_rebalance")
	_run_suite(preload("res://tests/meta_progression_tests.gd"), "meta_progression")
	_run_suite(preload("res://tests/build_trial_tests.gd"), "build_trial")
	_run_suite(preload("res://tests/build_upgrade_tests.gd"), "build_upgrades")
	_run_suite(preload("res://tests/fireball_trial_tests.gd"), "fireball_trial")
	var records = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lua_baseline.json"))
	for record in records:
		var b = Battle.new(record.ability)
		b.cfg.player_bounds = {"half_width":5.225,"min_z":-9.6,"max_z":9.6}
		b.cfg.arena_size = [10,20] # Original projectile cull: abs x > 6, abs z > 11.
		var points = [Vector2(-1,4),Vector2(1,4),Vector2(0,6)]
		for i in range(3):
			b.enemies[i].pos = points[i]
			b.enemies[i].previous = points[i]
		for frame in range(1,1201):
			var direction = Vector2.ZERO
			if record.moving:
				direction = [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP][int((frame-1)/180)%4]
				# Logical DOWN here is +z; source pattern moves -z in second phase.
				direction.y = -direction.y
			b.step(1.0/120,direction)
			if frame%30: continue
			var expected = record.frames[int(frame/30)-1]
			var tag = "%s moving=%s frame=%d" % [record.ability,record.moving,frame]
			check(near(b.player.pos.x,expected.x) and near(b.player.pos.y,expected.z),tag+" movement")
			check(b.player.health==expected.health and b.result==expected.result,tag+" health/result")
			check(b.target_id==expected.target and b.shots==expected.shots and b.hits==expected.hits and b.attack_hits==expected.attack_hits and b.kills==expected.kills and b.damage_dealt==expected.damage,tag+" counters")
			for i in range(3):
				var e = b.enemies[i]
				var old = expected.enemies[i]
				check(near(e.pos.x,old.x) and near(e.pos.y,old.z) and e.health==old.health and e.state==old.state,tag+" enemy "+str(i))
	print("Lua parity: 240 checkpoints checked")
	for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,1),Vector2(-1,1),Vector2(1,-1),Vector2(-1,-1)]:
		var b = Battle.new()
		b.move_player(direction,0.1)
		check(near(b.player.pos.length(),0.5),"eight-direction normalization")
		b.move_player(direction,100)
		check(absf(b.player.pos.x)<=8.5001 and b.player.pos.y<=1.1001 and b.player.pos.y>=-4.6501,"bounds (Vector2 float tolerance)")
	var b = Battle.new()
	for e in b.enemies:
		check(absf(e.pos.x)<10 and e.pos.y<5.625 and e.pos.y>-5.625,"spawn in arena")
	check(near(Battle.contact_time(Vector2(-10,0),Vector2(10,0),1),0.45),"swept high-speed contact")
	check(is_inf(Battle.contact_time(Vector2(-10,2),Vector2(10,2),1)),"swept miss")
	b.enemies[0].health=0
	b.pending.append({"target":b.enemies[0],"due":0})
	b.cooldown=1
	b.update_fireball(0.01)
	check(b.pending.is_empty() and b.shots==0,"dead pending target cancels")
	b.enemies[1].pos=Vector2(50,0)
	b.enemies[2].pos=Vector2(60,0)
	b.update_fireball(2)
	check(b.shots==0 and b.cooldown==0,"no target no cast")
	b = Battle.new()
	b.damage_player(15)
	b.damage_player(15)
	check(b.player.health==70 and b.hits==2,"independent hits: no invulnerability")
	for e in b.enemies: b.damage_enemy(e,999)
	b.step(0.01)
	check(b.result=="success" and b.bullets.is_empty(),"all dead win")
	var elapsed = b.elapsed
	b.step(10,Vector2.RIGHT)
	check(b.elapsed==elapsed,"resolved battle frozen")
	b=Battle.new("orbit")
	b.step(0.01)
	check(b.orbs.size()==1 and b.shots==0,"orbit only")
	check(near(b.orbs[0].pos.distance_to(b.player.pos),1.8),"orbit radius")
	for fps in [30,60,144]:
		b=Battle.new()
		var c=Clock.new()
		c.suspend(false)
		for frame in range(fps): c.advance(1.0/fps,b,Vector2.RIGHT)
		check(near(b.elapsed,1) and near(b.player.pos.x,5),"fixed step at "+str(fps))
		c.suspend(true)
		var frozen=b.elapsed
		c.advance(20,b,Vector2.RIGHT)
		check(b.elapsed==frozen,"pause discards time")
		c.suspend(false)
		c.advance(1.0/120,b,Vector2.ZERO)
		check(near(b.elapsed,frozen+1.0/120),"resume no catchup")
	b=Battle.new("orbit")
	check(b.elapsed==0 and b.hits==0 and b.orbs.is_empty() and b.effects.is_empty() and b.cooldown==0,"fresh retry state")
	combat_edges()
	var result := {"checks": checks + linked_checks, "failures": failures, "local_checks": checks, "local_failures": failures - linked_failures, "suites": suite_results, "scope": "main native rules including linked RefCounted route tests; SceneTree spell/artifact tests run separately"}
	result["natural_routes_deferred"] = "--skip-natural-route" in OS.get_cmdline_user_args()
	_write_report("main_suite_results.json", result)
	print("Checks: %d; failures: %d" % [checks + linked_checks,failures])
	quit(1 if failures else 0)

func _run_suite(script: Script, label: String):
	var suite = script.new()
	var found: int = int(suite.run())
	linked_checks += int(suite.checks)
	linked_failures += found
	failures += found
	suite_results.append({"id": label, "checks": int(suite.checks), "failures": found})
	if label == "route_rebalance":
		var deferred := "--skip-natural-route" in OS.get_cmdline_user_args()
		_write_report("route_boundary_results.json" if deferred else "natural_route_results.json", {"checks": int(suite.checks), "failures": found, "metrics": suite.metrics, "natural_routes_deferred": deferred})

func _write_report(filename: String, result: Dictionary):
	var directory := "res://build/qa/current-main-suite"
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with("--qa-out="):
			var requested: String = str(argument).trim_prefix("--qa-out=")
			if requested.begins_with("res://build/qa/") and not requested.contains(".."):
				directory = requested
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory.path_join(filename), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()

func combat_edges():
	var b=Battle.new()
	for i in range(3):
		b.enemies[i].pos=Vector2(0,2+i*1.2)
		b.enemies[i].previous=b.enemies[i].pos
	b.bullets.append({"id":1,"pos":Vector2.ZERO,"velocity":Vector2(0,90),"age":0.0})
	b.update_bullets(0.1)
	check(b.enemies[0].health==18 and b.enemies[1].health==30 and b.enemies[2].health==30,"first swept hit and explosion radius: no piercing")
	b.update_bullets(0.1)
	check(b.enemies[0].health==18 and b.attack_hits==1,"removed bullet never damages twice")
	b=Battle.new()
	b.enemies[0].pos=Vector2(0,2)
	b.enemies[1].pos=Vector2(0.4,2)
	b.enemies[2].pos=Vector2(5,5)
	for e in b.enemies: e.previous=e.pos
	b.bullets.append({"id":1,"pos":Vector2.ZERO,"velocity":Vector2(0,90),"age":0.0})
	b.update_bullets(0.1)
	check(b.enemies[0].health==18 and b.enemies[1].health==18 and b.enemies[2].health==30,"AOE hits each victim once")
	b=Battle.new("lightning")
	for i in range(3): b.enemies[i].pos=Vector2(i,2)
	b.update_arcane(0.01)
	check(b.attack_hits==2 and b.enemies[0].health==20 and b.enemies[1].health==20 and b.enemies[2].health==30,"lightning two unique targets")
	check(b.effects[0].pos==b.enemies[0].pos and b.effects[1].pos==b.enemies[1].pos,"lightning displayed endpoints match victims")
	b.update_arcane(0.2)
	check(b.attack_hits==2,"lightning interval")
	b=Battle.new("lightning")
	b.enemies[0].pos=Vector2(0,2)
	b.enemies[1].pos=Vector2(4,2)
	b.enemies[2].pos=Vector2(8,2)
	b.update_arcane(0.01)
	check(b.attack_hits==1,"lightning chain distance")
	b=Battle.new("orbit")
	b.enemies[0].pos=Vector2(1.8,0)
	b.enemies[1].pos=Vector2(9,9)
	b.enemies[2].pos=Vector2(9,9)
	b.update_arcane(0)
	check(b.enemies[0].health==22,"orb contact")
	b.elapsed=0.1
	b.enemies[0].pos=Vector2(cos(0.28),sin(0.28))*1.8
	b.update_arcane(0)
	check(b.enemies[0].health==22,"orb same-target cooldown")
	b.elapsed=0.5
	b.enemies[0].pos=Vector2(cos(1.4),sin(1.4))*1.8
	b.update_arcane(0)
	check(b.enemies[0].health==14,"orb cooldown expiry")
	b.enemies[0].pos=Vector2(8,8)
	b.elapsed=1
	b.update_arcane(0)
	check(b.enemies[0].health==14,"orb out of contact")
	b=Battle.new()
	var e=b.enemies[0]
	e.state="attack"
	e.attack=Vector2.ZERO
	b.damage_enemy(e,30)
	b.step(0.01)
	check(b.player.health==100,"dead attacker canceled")
