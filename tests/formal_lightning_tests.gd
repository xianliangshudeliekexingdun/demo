extends SceneTree
## Actual lightning route fixtures. AI/spawn/clear are isolated; no save, renderer
## or natural inventory. Damage goes through the production core pipeline.

const IDS = ["L01", "L02", "L03", "L04", "L05", "L06", "L07", "L08", "L09", "L10"]
var checks: int = 0
var failures: Array = []
var groups: Array = []
var observations: Array = []

class Fixture extends "res://scripts/core/courtyard_route_run.gd":
	var hit_log: Array = []
	var natural_casts: Array = []
	var contexts: Array = []
	var extra_cdr: float = 0.0
	func _reserve_batch(): pass
	func _update_spawn(_dt: float): pass
	func _check_clear(): pass
	func _update_enemies(dt: float):
		_spell_combat.before_damage_tick(self, dt)
		for enemy in actors: enemy.previous = enemy.pos
	func artifact_cooldown_reduction() -> float:
		return super.artifact_cooldown_reduction() + extra_cdr
	func damage_enemy(enemy: Dictionary, amount: float, source: String = ""):
		var before: float = float(enemy.get("health", 0.0))
		super.damage_enemy(enemy, amount, source)
		hit_log.append({"at": time, "actor_id": int(enemy.get("id", -1)), "source": source,
			"amount": maxf(0.0, before - maxf(0.0, float(enemy.get("health", 0.0))))})
	func on_spell_cast(spell: Dictionary, target: Dictionary, context: Dictionary):
		natural_casts.append({"id": spell.id, "context": context.duplicate(true), "at": time})
		super.on_spell_cast(spell, target, context)
	func resolve_spell_hit(actor: Dictionary, coefficient: float, context: Dictionary) -> Dictionary:
		var result: Dictionary = super.resolve_spell_hit(actor, coefficient, context)
		contexts.append({"at": time, "actor_id": int(actor.id), "coefficient": coefficient,
			"context": context.duplicate(true), "result": result.duplicate(true)})
		return result

func _initialize(): call_deferred("execute")
func check(value: bool, label: String):
	checks += 1
	if not value:
		failures.append(label)
		push_error("Formal lightning: " + label)
func near(a: float, b: float, tolerance: float = 0.001) -> bool:
	return absf(a - b) <= tolerance
func enemy(id: int = 1, pos: Vector2 = Vector2(0, 2), health: float = 1000000.0) -> Dictionary:
	return {"id": id, "type": "M01", "type_id": "M01", "pos": pos, "previous": pos,
		"health": health, "max_health": health, "radius": 0.3, "phase": "chase", "push_resistance": 0.0,
		"spell_slows": {}, "slow_remaining": 0.0, "slow_multiplier": 1.0}
func stop_natural(battle):
	for spell in battle.spells:
		spell.remaining = 9999.0
		spell.cast_remaining = 0.0
func fresh(ids: Array = ["L01"], level: int = 1, core: String = ""):
	var battle = Fixture.new()
	var configured: Dictionary = battle.configure({"route_school": "lightning", "gem_core": core}, 20261021)
	check(bool(configured.get("ok", false)), "actual lightning route config")
	if not bool(configured.get("ok", false)): return battle
	check(battle.choose_initial("L01"), "actual lightning starter")
	battle._spawn_done = true
	battle.spawn_warnings.clear()
	battle.blocks.clear()
	battle.player.pos = Vector2.ZERO
	battle.player.previous = Vector2.ZERO
	battle.player.crit_rate = 0.0
	battle.spells.clear()
	for id in ids:
		var spell: Dictionary = battle._new_spell(str(id))
		spell.level = level
		battle._refresh_spell(spell)
		battle.spells.append(spell)
	battle.actors = [enemy()]
	stop_natural(battle)
	return battle
func advance(battle, seconds: float):
	for _tick in roundi(seconds * 120.0): battle.step(1.0 / 120.0)
func release(battle, id: String, natural: bool = true, scale: float = 1.0):
	var spell: Dictionary = battle._owned_spell(id)
	var stats: Dictionary = battle.get_spell_stats(spell)
	var target: Dictionary = battle._spell_combat.legal_target(battle, spell, stats)
	check(not target.is_empty(), "actual legal target " + id)
	if target.is_empty(): return
	spell.locked_pos = target.pos
	battle._spell_combat._cast(battle, spell, stats, target, natural, scale)
	stop_natural(battle)
func mark(battle, id: int, duration: float = 20.0):
	for actor in battle.actors:
		if int(actor.id) == id:
			battle._spell_combat.lightning._apply_conductive(battle, actor, duration)
func sum_damage(battle, actor_id: int = -1) -> float:
	var total: float = 0.0
	for hit in battle.hit_log:
		if actor_id < 0 or int(hit.actor_id) == actor_id: total += float(hit.amount)
	return total
func source_damage(battle, source: String, actor_id: int = -1) -> float:
	var total: float = 0.0
	for hit in battle.hit_log:
		if str(hit.source) == source and (actor_id < 0 or int(hit.actor_id) == actor_id): total += float(hit.amount)
	return total
func grant(battle, id: String):
	battle._artifact_combat._owned.append(id)
	battle._artifact_combat.apply_acquisition(battle, id)
func lightning_context(cast_id: int = 9901) -> Dictionary:
	return {"school": "lightning", "spell_id": "L01", "kind": "direct", "cast_id": cast_id,
		"natural": true, "damage_scale": 1.0, "field_bonus": 0.0}
func source_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	for path in ["res://tests/formal_lightning_tests.gd", "res://data/lightning_spells_v1.json",
		"res://scripts/core/courtyard_route_run.gd", "res://scripts/core/route_spell_combat.gd",
		"res://scripts/core/route_lightning_combat.gd", "res://scripts/core/route_lightning_status.gd",
		"res://scripts/core/route_gem_combat.gd", "res://scripts/core/route_gem_echo.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes
func group(id: String, callable: Callable):
	var before: int = checks
	var failed: int = failures.size()
	callable.call()
	groups.append({"id": id, "checks": checks - before, "failures": failures.size() - failed})
func execute():
	group("entry_and_growth", entry_and_growth)
	group("ten_spells_three_levels", ten_spells_three_levels)
	group("chain_and_network", chain_and_network)
	group("judgment_and_shield", judgment_and_shield)
	group("mastery_scope", mastery_scope)
	group("cloud_clock_and_refresh", cloud_clock_and_refresh)
	group("generic_items_and_gem_core_compatibility", generic_items_and_gem_core_compatibility)
	group("pause_cleanup_and_release_snapshot", pause_cleanup_and_release_snapshot)
	var output: String = "res://build/qa/formal-schools-current/lightning"
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--qa-out=res://build/qa/") and not str(arg).contains(".."):
			output = str(arg).trim_prefix("--qa-out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	FileAccess.open(output + "/results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks,
		"failures": failures.size(), "details": failures, "groups": groups, "observations": observations,
		"source_sha256": source_hashes(),
		"scope": "Actual route lightning controlled fixtures: no enemy AI/spawn/clear, renderer, save, natural inventory, full route or final balance claim."}, "\t"))
	print("FORMAL LIGHTNING RULES checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func entry_and_growth():
	var battle = fresh()
	check(battle.initial_choices().map(func(item): return str(item.id)) == ["L01", "L02", "L03"], "lightning three actual starters")
	var eligible: Array = battle.eligible_reward_ids()
	check(eligible.size() == 57, "sixty spells minus three unmet source prerequisites")
	for id in IDS: check(id in eligible, "lightning eligible " + id)
	for id in ["LB01", "LP01", "LG01"]:
		check(id not in battle._artifact_combat.eligible_ids(battle), "old lightning profession source never becomes treasure " + id)
	var fire = Fixture.new()
	check(fire.configure({}, 20261021).ok and fire.initial_choices().map(func(item): return str(item.id)) == ["F01", "F03", "F08"], "fire entry preserved")
	var ice = Fixture.new()
	check(ice.configure({"route_school": "ice"}, 20261021).ok and ice.initial_choices().map(func(item): return str(item.id)) == ["I01", "I02", "I03"], "ice entry preserved")
	check(near(battle.reward_weight("L01"), battle.reward_weight("L02") * float(battle._spell_sampling.rules.owned_upgrade_weight)), "current sampling gives owned L01 the source-defined upgrade weight")
	var fire_equipped = Fixture.new()
	check(fire_equipped.configure({"route_school": "lightning", "equipment": {"catalyst": "MC04"}, "levels": {"MC04": 3}}, 20261021).ok, "old catalyst works with lightning start")
	check(fire_equipped.reward_weight("F01") > fire_equipped.reward_weight("L01"), "current catalyst priority favors legal fire spells over unowned lightning")

func ten_spells_three_levels():
	var expected: Dictionary = {"L01": [100.0, 160.0, 210.0], "L02": [220.0, 319.0, 432.0],
		"L03": [140.0, 180.0, 220.0], "L04": [80.0, 110.0, 140.0],
		"L05": [270.0, 360.0, 516.0], "L06": [120.0, 160.0, 240.0],
		"L07": [480.0, 620.0, 720.0], "L08": [160.0, 210.0, 260.0]}
	for level in range(1, 4):
		for id in IDS:
			var battle = fresh([id], level)
			if id == "L10":
				advance(battle, 2.0)
				check(battle.casts == 0 and battle.hit_log.is_empty(), "passive no attacks or natural count L" + str(level))
				check(near(battle._spell_combat.lightning.school_bonus(battle), [0.1, 0.18, 0.25][level - 1]), "mastery school bucket L" + str(level))
				continue
			if id == "L09": battle.player.shield = float(battle.player.max_shield) - 10.0
			release(battle, id)
			advance(battle, 5.4 if id == "L05" else 0.6)
			check(battle.casts == 1 and battle.natural_casts.size() == 1, "one natural event " + id + " L" + str(level))
			if id == "L09":
				check(near(float(battle.player.shield), float(battle.player.max_shield)) and near(sum_damage(battle), 0.0), "actual missing10 restored no damage L" + str(level))
			else:
				check(near(sum_damage(battle), expected[id][level - 1], 0.01), "standalone full event budget " + id + " L" + str(level))
			advance(battle, 9.0)
			check(battle._spell_combat.lightning.pending.is_empty() and battle._spell_combat.lightning.projectiles.is_empty(), "bounded pending and projectile lifetime " + id)

func chain_and_network():
	var chain = fresh(["L03"], 3)
	chain.actors.clear()
	for index in 6: chain.actors.append(enemy(index + 1, Vector2(0, 2.0 + index * 0.5)))
	release(chain, "L03")
	advance(chain, 0.5)
	check(near(sum_damage(chain), 815.898875, 0.01), "level3 finite five-target chain geometric sum")
	check(chain.hit_log.size() == 5 and sum_damage(chain, 6) == 0.0, "chain no revisit no sixth tail arc")
	var separated = fresh(["L03"], 3)
	separated.actors = [enemy(1, Vector2(0, 2)), enemy(2, Vector2(0, 6.8))]
	release(separated, "L03")
	advance(separated, 0.5)
	check(near(sum_damage(separated), 220.0), "unmarked chain cannot bridge4.8m")
	var wall = fresh(["L03"], 3)
	wall.actors = [enemy(1, Vector2(0, 2)), enemy(2, Vector2(0, 4))]
	wall.blocks = [{"center": Vector2(0, 3), "size": Vector2(3, 0.5)}]
	release(wall, "L03")
	advance(wall, 0.5)
	check(sum_damage(wall, 2) == 0.0, "chain checks actual per-edge obstacle")
	for natural in [false, true]:
		var net = fresh(["L08"], 3)
		net.actors.clear()
		for index in 6:
			net.actors.append(enemy(index + 1, Vector2(0, 2.0 + index * 0.5)))
		for id in range(1, 7): mark(net, id)
		release(net, "L08", natural)
		advance(net, 1.2)
		check(near(sum_damage(net), 1700.0 if natural else 1340.0, 0.01), "natural vs extra network finite overload " + str(natural))
		check(net.hit_log.size() == 6, "network each actor once " + str(natural))
	var three = fresh(["L08"], 3)
	three.actors = [enemy(1, Vector2(0, 2)), enemy(2, Vector2(0, 2.5)), enemy(3, Vector2(0, 3))]
	for id in range(1, 4): mark(three, id)
	release(three, "L08")
	advance(three, 0.6)
	check(near(sum_damage(three), 890.0), "three-node overload boosts only two existing edges")
	var bare = fresh(["L08"], 3)
	bare.actors = [enemy(1, Vector2(0, 2)), enemy(2, Vector2(0, 2.5)), enemy(3, Vector2(0, 3))]
	release(bare, "L08")
	advance(bare, 0.6)
	check(near(sum_damage(bare), 260.0), "network new marks cannot join this old-network cast")
	for id in ["L03", "L08"]:
		var expires = fresh([id], 3)
		expires.actors = [enemy(1, Vector2(0, 2)), enemy(2, Vector2(0, 6))]
		mark(expires, 1)
		mark(expires, 2, 0.04)
		release(expires, id)
		advance(expires, 0.3)
		check(sum_damage(expires, 1) > 0.0 and near(sum_damage(expires, 2), 0.0), "delayed actual edge rechecks endpoint conductive expiry " + id)

func judgment_and_shield():
	var mature = fresh(["L07"], 3)
	mature.actors = [enemy(1, Vector2(0, 2)), enemy(2, Vector2(0, 2.5)), enemy(3, Vector2(0, 3))]
	for id in range(1, 4): mark(mature, id)
	advance(mature, 1.6)
	release(mature, "L07")
	advance(mature, 0.4)
	check(near(sum_damage(mature), 1320.0) and near(sum_damage(mature, 1), 960.0), "mature judgment finite two-neighbor upper bound")
	var killed = fresh(["L07"], 3)
	killed.actors = [enemy(1, Vector2(0, 2), 500), enemy(2, Vector2(0, 2.5), 400), enemy(3, Vector2(0, 3), 400)]
	for id in range(1, 4): mark(killed, id)
	advance(killed, 1.6)
	release(killed, "L07")
	advance(killed, 0.4)
	check(near(sum_damage(killed, 2), 0.0) and near(sum_damage(killed, 3), 0.0), "killed main never releases mature neighbor arcs")
	check(not killed._spell_combat.lightning.status.has_conductive(1), "dead main has no refreshed mark")
	var full = fresh(["L09"], 3)
	full.spells[0].remaining = 0.0
	advance(full, 1.0)
	check(full.casts == 0 and not full._spell_combat.lightning.status.has_conductive(1), "full shield no cast no phantom mark")
	var absent = fresh(["L09"], 3)
	absent.player.shield = 0.0
	absent.actors.clear()
	absent.spells[0].remaining = 0.0
	advance(absent, 1.0)
	check(absent.casts == 0, "shield restore requires actual living enemy")

func mastery_scope():
	var battle = fresh(["L03", "L04", "L10"], 3)
	check(near(battle._spell_combat.lightning.school_bonus(battle), 0.35), "mastery plus three-school resonance same additive bucket")
	var stats: Dictionary = battle.get_spell_stats(battle._owned_spell("L04"))
	check(near(float(stats.level.spread_range), 3.5), "mastery never expands imprint spread range")
	mark(battle, 1, 4.0)
	advance(battle, 5.4)
	check(battle._spell_combat.lightning.status.has_conductive(1), "mastery3 extends new ordinary mark to5.5s")
	advance(battle, 0.2)
	check(not battle._spell_combat.lightning.status.has_conductive(1), "mastery mark still expires")
	var extended = fresh(["L03", "L10"], 3)
	extended.actors = [enemy(1, Vector2(0, 2)), enemy(2, Vector2(0, 6.8))]
	mark(extended, 1)
	mark(extended, 2)
	release(extended, "L03")
	advance(extended, 0.4)
	check(sum_damage(extended, 2) > 0.0, "mastery3 joins two old marks across4.8m")
	var raw = fresh(["L03", "L10"], 3)
	raw.actors = [enemy(1, Vector2(0, 2)), enemy(2, Vector2(0, 6.8))]
	release(raw, "L03")
	advance(raw, 0.4)
	check(sum_damage(raw, 2) == 0.0, "mastery does not expand unmarked3.5m connection")

func cloud_clock_and_refresh():
	var clock = fresh(["L05"], 3)
	release(clock, "L05")
	advance(clock, 0.3)
	release(clock, "L05")
	advance(clock, 0.15)
	check(clock.hit_log.size() == 1, "later cloud never delays or duplicates old first0.4s strike")
	check(clock._spell_combat.lightning.zones.size() == 2, "two finite casts retain two independent clouds")
	advance(clock, 1.4)
	check(clock.hit_log.size() == 3, "old and new cloud waves both retain original finite schedule")
	var mixed = fresh(["L05"], 3)
	release(mixed, "L05")
	advance(mixed, 0.2)
	release(mixed, "L05", false, 0.25)
	advance(mixed, 0.25)
	check(near(sum_damage(mixed), 120.0), "weak extra does not overwrite active natural cloud")
	var natural_only = fresh(["L05"], 3)
	release(natural_only, "L05")
	advance(natural_only, 5.4)
	advance(mixed, 4.95)
	check(sum_damage(mixed) + 0.001 >= sum_damage(natural_only), "mixed cloud probe never suppresses natural-only fixed-position budget")
	var seen: Dictionary = {}
	for hit in mixed.contexts:
		var cast_id: int = int(hit.context.cast_id)
		var cast_hits: Array = seen.get(cast_id, [])
		if not cast_hits.is_empty():
			check(float(hit.at) - float(cast_hits[-1]) >= 1.4 - 1.0 / 120.0, "one cast same actor receives at most one hit per scheduled wave")
		cast_hits.append(float(hit.at))
		seen[cast_id] = cast_hits
	for id in seen: check(seen[id].size() <= 4, "each cloud retains at most four finite waves")
	var previous: float = -1.0
	for reduction in [0.0, 0.3, 0.45, 0.5, 0.55, 0.6]:
		var sample = fresh(["L05"], 3)
		sample.extra_cdr = reduction
		sample.spells[0].remaining = 0.0
		advance(sample, 60.0)
		var damage: float = sum_damage(sample)
		check(damage + 0.001 >= previous, "cloud higher CDR no lower60s actual budget " + str(reduction))
		previous = damage
		observations.append({"case": "actual_cloud60s", "cdr": reduction, "damage": damage, "casts": sample.casts, "hits": sample.hit_log.size()})

func pause_cleanup_and_release_snapshot():
	var pending = fresh(["L03"], 3)
	pending.actors = [enemy(1, Vector2(0, 2)), enemy(2, Vector2(0, 3))]
	release(pending, "L03")
	var before_damage: float = sum_damage(pending)
	var before_time: float = pending.time
	pending.set_paused(true)
	advance(pending, 1.0)
	check(near(pending.time, before_time) and near(sum_damage(pending), before_damage), "pause freezes delayed lightning edges")
	pending.set_paused(false)
	advance(pending, 0.2)
	check(sum_damage(pending, 2) > 0.0, "resume resolves one pending edge")
	var snapshot = fresh(["L03"], 1)
	snapshot.actors = [enemy(1, Vector2(0, 2)), enemy(2, Vector2(0, 3))]
	release(snapshot, "L03")
	snapshot.spells[0].level = 3
	snapshot._refresh_spell(snapshot.spells[0])
	stop_natural(snapshot)
	advance(snapshot, 0.3)
	check(near(sum_damage(snapshot, 2), 105.0), "released chain retains old level coefficient and decay after upgrade")
	var stopped = fresh(["L05", "L03"], 3)
	release(stopped, "L05")
	release(stopped, "L03")
	mark(stopped, 1)
	stopped._stop_combat()
	check(stopped._spell_combat.lightning.zones.is_empty() and stopped._spell_combat.lightning.pending.is_empty() and stopped._spell_combat.lightning.projectiles.is_empty(), "clear removes zones pending and projectiles")
	check(not stopped._spell_combat.lightning.status.has_conductive(1), "clear removes conductive state")

func generic_items_and_gem_core_compatibility():
	var only_shield = fresh(["L09"], 3)
	check("GT01" not in only_shield._artifact_combat.eligible_ids(only_shield), "shield alone lacks actual lightning damage source for GT01")
	var charged = fresh(["L09", "L01"], 3)
	check("GT01" in charged._artifact_combat.eligible_ids(charged), "lightning restore plus damage qualifies GT01")
	grant(charged, "GT01")
	charged.player.shield = float(charged.player.max_shield) - 10.0
	release(charged, "L09")
	check(near(float(charged._artifact_combat.state_snapshot().generic.charge), 40.0), "GT01 charges four times actual missing10 only")
	release(charged, "L01")
	advance(charged, 0.3)
	check(near(source_damage(charged, "GT01"), 40.0), "natural lightning direct releases one fixed charge")
	var sequence = fresh(["L01"], 1)
	grant(sequence, "P04")
	for _cast in 3: release(sequence, "L01")
	advance(sequence, 0.3)
	check(sequence.casts == 3 and sequence.natural_casts.size() == 3, "P04 lightning extra never increments natural count or recurses")
	check(sequence.contexts.size() == 4 and sequence.contexts.filter(func(hit): return not bool(hit.context.natural)).size() == 1, "three natural releases yield exactly one real lightning extra")
	var fractured = fresh(["L01"], 1, "fracture")
	fractured.player.crit_rate = 2.0
	fractured.resolve_spell_hit(fractured.actors[0], 1.0, lightning_context())
	check(near(source_damage(fractured, "L01"), 100.0), "lightning direct body feeds fracture critical plan")
	var pending_count: int = fractured._gem_combat.pending.size()
	fractured.resolve_lightning_derived_hit(fractured.actors[0], 1.0, {"kind": "lightning_test_derived"})
	check(fractured._gem_combat.pending.size() == pending_count, "lightning noncritical derived damage never creates fracture body")
	advance(fractured, 0.2)
	check(near(source_damage(fractured, "gem_fracture"), 90.0), "lightning critical extra50 becomes one delayed1.8x crystal")
	var coffin = fresh(["L01"], 1, "coffin")
	coffin._spell_combat.ice.status.force_ready(coffin, coffin.actors[0], 1.2, {"school": "ice", "spell_id": "I08", "natural": true, "cast_id": 9200})
	coffin.resolve_spell_hit(coffin.actors[0], 1.0, lightning_context())
	check(near(source_damage(coffin, "L01"), 60.0) and near(float(coffin._gem_combat.reserves[1].amount), 40.0), "lightning direct body participates in40pct coffin reserve")
	coffin.resolve_lightning_derived_hit(coffin.actors[0], 1.0, {"kind": "lightning_test_derived"})
	check(near(float(coffin._gem_combat.reserves[1].amount), 40.0), "lightning derived damage never enters coffin reserve")
	var circle = fresh(["L06", "L10"], 1, "echo")
	circle.actors = [enemy(1, Vector2(0, 2)), enemy(2, Vector2(5, 0))]
	release(circle, "L06")
	circle.actors[0].pos = Vector2(10, 10)
	circle.actors[0].previous = circle.actors[0].pos
	circle.actors[1].pos = Vector2(0, 1)
	circle.actors[1].previous = circle.actors[1].pos
	advance(circle, 0.65)
	check(near(source_damage(circle, "gem_echo", 2), 85.8), "L06 echo replays65pct original circle for new entrant with lightning mastery bucket")
	check(near(source_damage(circle, "gem_echo", 1), 0.0), "circle echo does not chase original departed actor")
	for main_survives in [false, true]:
		var lance = fresh(["L02"], 3, "echo")
		lance.actors = [enemy(1, Vector2(0, 2)), enemy(2, Vector2(0, 4), 2000000.0), enemy(3, Vector2(0, 5)), enemy(4, Vector2(0, 6))]
		release(lance, "L02")
		if not main_survives: lance.actors[1].health = 0.0
		advance(lance, 0.65)
		check(near(source_damage(lance, "gem_echo", 1), 78.0), "line first contact keeps secondary coefficient " + str(main_survives))
		check(near(source_damage(lance, "gem_echo", 2), 234.0 if main_survives else 0.0), "echo primary identity preserved when line-first differs or dies " + str(main_survives))
		check(near(source_damage(lance, "gem_echo", 3), 78.0) and near(source_damage(lance, "gem_echo", 4), 0.0), "dead or live primary never returns unused main allowance to third secondary " + str(main_survives))
