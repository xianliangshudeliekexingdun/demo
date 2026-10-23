extends "res://tests/formal_spirit_tests.gd"
## Shares only the deterministic fixture helpers. Cross-school runtime/gem/
## item integration assertions live here so school suites remain independent.

func execute():
	group("new_school_body_fracture_and_gt01", new_school_body_fracture_and_gt01)
	group("echo_cone_geometry_and_wind_path_budgets", echo_cone_geometry_and_wind_path_budgets)
	group("stride_body_and_support_permissions", stride_body_and_support_permissions)
	group("derived_permissions_and_source_multiplier", derived_permissions_and_source_multiplier)
	group("prerequisite_loss_and_release_snapshots", prerequisite_loss_and_release_snapshots)
	group("archived_f04_does_not_join_formal_spirit_resonance", archived_f04_does_not_join_formal_spirit_resonance)
	var hashes: Dictionary = {}
	for path in ["res://tests/six_school_integration_tests.gd", "res://tests/formal_spirit_tests.gd", "res://scripts/core/courtyard_route_run.gd", "res://scripts/core/route_spell_combat.gd", "res://scripts/core/route_generic_items.gd", "res://scripts/core/route_gem_combat.gd", "res://scripts/core/route_gem_echo.gd", "res://scripts/core/route_wind_combat.gd", "res://scripts/core/route_earth_combat.gd", "res://scripts/core/route_spirit_combat.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	var output: String = "res://build/qa/six-schools-implementation-20261021/integration"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	FileAccess.open(output + "/results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks,
		"failures": failures.size(), "details": failures, "groups": groups, "source_sha256": hashes,
		"scope": "Actual core controlled integration fixtures for wind/earth/spirit, generic items, release snapshots and gem permissions; no UI, natural route, performance or final balance validation."}, "\t"))
	print("SIX SCHOOL INTEGRATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func new_school_body_fracture_and_gt01():
	for row in [["W01", 120.0], ["R02", 160.0], ["S01", 110.0]]:
		var id: String = str(row[0])
		var base: float = float(row[1])
		var fractured = fresh([id], 1, "fracture")
		fractured.player.crit_rate = 2.0
		release(fractured, id)
		advance(fractured, 1.2)
		check(near(damage(fractured, id), base), "new school body critical converts to uncritical immediate " + id)
		check(near(damage(fractured, "gem_fracture"), base * 0.8), "new school one delayed fracture critical component " + id)
		check(fractured.natural_casts.size() == 1, "fracture never adds natural casts " + id)
		var charged = fresh([id, "S09"])
		grant(charged, "GT01")
		charged.player.shield -= 10.0
		release(charged, "S09")
		check(near(float(charged._artifact_combat.state_snapshot().generic.charge), 40.0), "cross-school shield charge actual40 " + id)
		release(charged, id)
		advance(charged, 0.5)
		check(near(damage(charged, "GT01"), 40.0), "cross-school natural direct releases once " + id)
		var extra = fresh([id, "S09"])
		grant(extra, "GT01")
		extra.player.shield -= 10.0
		release(extra, "S09")
		release(extra, id, false, 0.25)
		advance(extra, 0.5)
		check(near(damage(extra, id), base * 0.25) and damage(extra, "GT01") == 0.0, "quarter extra once and no GT01 permission " + id)

func echo_cone_geometry_and_wind_path_budgets():
	var cone = fresh(["W04"], 1, "echo")
	cone.actors = [enemy(1, Vector2(0, 1)), enemy(2, Vector2(0, -2)), enemy(3, Vector2(2.5, 0))]
	release(cone, "W04")
	check(damage(cone, "W04", 1) > 0.0 and damage(cone, "W04", 2) == 0.0, "scatter body only forward cone")
	advance(cone, 0.7)
	check(damage(cone, "gem_echo", 1) > 0.0, "scatter echo retains valid forward target")
	check(damage(cone, "gem_echo", 2) == 0.0 and damage(cone, "gem_echo", 3) == 0.0, "cone replay never expands to behind or side circle")
	var wall = fresh(["W04"], 1, "echo")
	wall.actors = [enemy(1, Vector2(0, 1)), enemy(2, Vector2(0, 2.5))]
	release(wall, "W04")
	wall.blocks = [{"center": Vector2(0, 2), "size": Vector2(4, 0.2)}]
	advance(wall, 0.7)
	check(damage(wall, "gem_echo", 2) == 0.0, "cone replay checks original origin-to-target wall")
	var path = fresh(["W08"], 1, "echo")
	path.actors = [enemy(1, Vector2.ZERO)]
	for index in range(8):
		path.gem_record_shape({"kind": "segments", "segments": [{"from": Vector2(-1, 0), "to": Vector2(1, 0), "width": 0.2}],
			"block": true, "wind_path": true, "cast_id": 10000 + index, "per_actor_cap": 3, "shared_cap": 3,
			"shared_window": 2.5, "hit_gate": 0.5}, 1.0,
			{"school": "wind", "spell_id": "W08", "kind": "area", "cast_id": 10000 + index, "natural": true, "damage_scale": 1.0})
		advance(path, 0.5)
		if index == 5: check(near(damage(path, "gem_echo"), 180.0), "fractional2.5s shared window does not truncate to2s")
	advance(path, 0.2)
	check(near(damage(path, "gem_echo"), 360.0), "wind-path echo shared window and gate allow finite six of eight separate casts")
	var one_cast = fresh(["W08"], 1, "echo")
	one_cast.actors = [enemy(1, Vector2.ZERO)]
	for _index in range(5):
		one_cast.gem_record_shape({"kind": "segments", "segments": [{"from": Vector2(-1, 0), "to": Vector2(1, 0), "width": 0.2}],
			"wind_path": true, "cast_id": 10020, "per_actor_cap": 2, "shared_cap": 99, "shared_window": 2.5, "hit_gate": 0.1}, 1.0,
			{"school": "wind", "spell_id": "W08", "kind": "area", "natural": true, "damage_scale": 1.0})
		advance(one_cast, 0.2)
	advance(one_cast, 0.7)
	check(near(damage(one_cast, "gem_echo"), 120.0), "separate segments of same cast retain total actor cap")

func stride_body_and_support_permissions():
	for id in ["W01", "R02", "S01"]:
		var battle = fresh([id], 1, "stride")
		battle._gem_combat.distance = 10.0
		battle.spells[0].remaining = 0.0
		for _index in range(12): battle.step(1.0 / 120.0, Vector2.RIGHT)
		check(battle.casts == 0 and damage(battle) == 0.0, "stride movement suspends natural damage cast " + id)
		advance(battle, 0.6)
		check(battle.casts == 1 and damage(battle) > 0.0, "stride stationary body resumes complete windup " + id)
		check(not battle.body_contexts.is_empty() and near(float(battle.body_contexts[0].gem_body_scale), 2.5), "stride body scale once at max path " + id)
	var support = fresh(["S02", "S05", "S07", "S09"], 1, "stride")
	support._gem_combat.distance = 10.0
	support._owned_spell("S02").remaining = 0.0
	for _index in range(60): support.step(1.0 / 120.0, Vector2.RIGHT)
	check(support.casts == 1 and school(support).units.size() == 1, "stride never suspends successful summon while moving")
	stop_natural(support)
	release(support, "S05")
	release(support, "S07")
	support.player.shield -= 10.0
	release(support, "S09")
	check(near(support._gem_combat.distance, 10.0), "summon command field and shield do not spend stride distance")
	advance(support, 1.2)
	check(not support.summon_contexts.is_empty() and near(float(support.summon_contexts[0].context.gem_body_scale), 1.0), "stride never multiplies pet body damage")

func derived_permissions_and_source_multiplier():
	for core in ["echo", "fracture", "coffin"]:
		var battle = fresh(["W01", "R02", "S01"], 1, core)
		battle.player.crit_rate = 2.0
		if core == "coffin": battle._spell_combat.ice.status.force_ready(battle, battle.actors[0], 4.0, {"school": "ice", "spell_id": "I08", "natural": true, "cast_id": 9000})
		for school_id in ["wind", "earth", "spirit"]:
			var actual: float = battle.resolve_school_derived_hit(battle.actors[0], 1.0, {"school": school_id,
				"spell_id": "fixture", "kind": "fixture_derived", "natural": true, "damage_scale": 0.25})
			check(near(actual, 25.0), "derived current school quarter once no crit " + school_id + " " + core)
		check(battle.body_contexts.is_empty() and battle._gem_combat.pending.is_empty() and battle._gem_combat.echo.pending.is_empty() and battle._gem_combat.reserves.is_empty(), "all derived schools skip body gem permission " + core)
	var pet = fresh(["S02", "S05"])
	release(pet, "S02", false, 0.25)
	advance(pet, 1.3)
	check(near(damage(pet, "summon"), 25.0), "pet birth quarter multiplier applies exactly once")
	release(pet, "S05", false, 0.5)
	advance(pet, 0.3)
	check(near(damage(pet, "spirit_command"), 30.0), "half command does not multiply by source pet quarter birth scale")
	var passive = fresh(["S02", "S10"], 3)
	release(passive, "S02")
	passive._owned_spell("S10").level = 1
	passive._refresh_spell(passive._owned_spell("S10"))
	advance(passive, 1.2)
	check(near(damage(passive, "summon"), 366.85), "old level3 pet reads current mastery15 instead of stale35")

func prerequisite_loss_and_release_snapshots():
	for pair in [["S05", "S02"], ["S07", "S03"], ["R06", "R03"]]:
		var support_id: String = str(pair[0])
		var source_id: String = str(pair[1])
		var battle = fresh([support_id, source_id])
		battle.spells = battle.spells.filter(func(spell): return str(spell.id) != source_id)
		check(support_id in battle.eligible_reward_ids(), "owned support retains upgrade eligibility after source replacement " + support_id)
		battle.spells[0].remaining = 0.0
		advance(battle, 0.6)
		check(battle.casts == 0 and damage(battle) == 0.0, "orphaned owned support waits for active source " + support_id)
		battle.spells.clear()
		check(support_id not in battle.eligible_reward_ids(), "unowned support cannot newly appear without source " + support_id)
	for row in [["W01", 240.0], ["R02", 320.0], ["S01", 220.0]]:
		var id: String = str(row[0])
		var snapshot = fresh([id])
		release(snapshot, id)
		snapshot._owned_spell(id).level = 3
		snapshot._refresh_spell(snapshot._owned_spell(id))
		stop_natural(snapshot)
		snapshot.player.attack = 200.0
		advance(snapshot, 0.5)
		check(near(damage(snapshot, id), float(row[1])), "inflight keeps old coefficient but reads current attack " + id)


func archived_f04_does_not_join_formal_spirit_resonance():
	var battle = fresh(["F04", "S01", "S02", "S03"])
	battle._refresh_reward_spell_parameters()
	var stats: Dictionary = battle.get_spell_stats(battle._owned_spell("F04"))
	var base_cd: float = float(stats.level.get("cooldown", stats.get("cooldown", 0.0)))
	check(near(float(battle._owned_spell("F04").cooldown), base_cd), "archived F04 keeps original cooldown after reward refresh")
	check(battle._spell_combat.spirit_school.spell_count(battle) == 3, "archived F04 is not a formal spirit type")
	battle.spells = battle.spells.filter(func(spell): return str(spell.id) != "S03")
	grant(battle, "GU05")
	battle._artifact_combat._generic._items.GU05.cooldown_reduction_add = 0.55
	check(battle._artifact_combat._has_uncapped_cooldown(battle), "archived F04 cannot create a third formal spirit type in cooldown eligibility")
	battle._refresh_reward_spell_parameters()
	check(near(float(battle._owned_spell("F04").cooldown), base_cd * 0.45), "archived F04 receives only generic cooldown reduction")
