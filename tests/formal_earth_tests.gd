extends SceneTree
## Production route fixtures, without renderer, AI, save, spawn or natural route.
const IDS = ["R01", "R02", "R03", "R04", "R05", "R06", "R07", "R08", "R09", "R10"]
var checks: int = 0
var failures: Array = []
var groups: Array = []
var observations: Array = []

class Fixture extends "res://scripts/core/courtyard_route_run.gd":
	var hit_log: Array = []
	var contexts: Array = []
	var derived_log: Array = []
	var natural_log: Array = []
	var extra_cdr: float = 0.0
	func _reserve_batch(): pass
	func _update_spawn(_dt: float): pass
	func _check_clear(): pass
	func _update_enemies(dt: float):
		_spell_combat.before_damage_tick(self, dt)
		_spell_combat.earth.after_player_motion(self)
		for actor in actors: actor.previous = actor.pos
	func artifact_cooldown_reduction() -> float:
		return super.artifact_cooldown_reduction() + extra_cdr
	func damage_enemy(actor: Dictionary, amount: float, source: String = ""):
		var before: float = float(actor.get("health", 0.0))
		super.damage_enemy(actor, amount, source)
		hit_log.append({"at": time, "actor_id": int(actor.id), "source": source, "amount": before - maxf(0.0, float(actor.health))})
	func resolve_spell_hit(actor: Dictionary, coefficient: float, context: Dictionary) -> Dictionary:
		contexts.append(context.duplicate(true))
		return super.resolve_spell_hit(actor, coefficient, context)
	func resolve_school_derived_hit(actor: Dictionary, coefficient: float, context: Dictionary = {}) -> float:
		derived_log.append(context.duplicate(true))
		return super.resolve_school_derived_hit(actor, coefficient, context)
	func on_spell_cast(spell: Dictionary, target: Dictionary, context: Dictionary):
		natural_log.append(context.duplicate(true))
		super.on_spell_cast(spell, target, context)

func _initialize(): call_deferred("execute")
func check(value: bool, label: String):
	checks += 1
	if not value:
		failures.append(label)
		push_error("Formal earth: " + label)
func near(a: float, b: float, epsilon: float = 0.01) -> bool: return absf(a - b) <= epsilon
func enemy(id: int = 1, point: Vector2 = Vector2(0, 2), health: float = 1000000.0) -> Dictionary:
	return {"id": id, "type": "M01", "type_id": "M01", "pos": point, "previous": point, "radius": 0.3,
		"health": health, "max_health": health, "phase": "chase", "spell_slows": {}, "slow_remaining": 0.0, "slow_multiplier": 1.0}
func stop_natural(battle):
	for spell in battle.spells:
		spell.remaining = 9999.0
		spell.cast_remaining = 0.0
func fresh(ids: Array = ["R01"], level: int = 1, core: String = ""):
	var battle = Fixture.new()
	var result: Dictionary = battle.configure({"route_school": "earth", "gem_core": core}, 20261021)
	check(bool(result.get("ok", false)), "actual earth route configured")
	if not bool(result.get("ok", false)): return battle
	check(battle.choose_initial("R01"), "earth starter selected")
	battle.blocks.clear()
	battle._spawn_done = true
	battle.spawn_warnings.clear()
	battle.player.pos = Vector2.ZERO
	battle.player.previous = Vector2.ZERO
	battle.player.crit_rate = 0.0
	battle.player.max_shield = 200.0
	battle.player.shield = 0.0
	battle.spells.clear()
	for id in ids:
		var spell: Dictionary = battle._new_spell(str(id))
		spell.level = level
		battle._refresh_spell(spell)
		battle.spells.append(spell)
	battle.actors = [enemy()]
	stop_natural(battle)
	return battle
func advance(battle, duration: float):
	for _tick in roundi(duration * 120.0): battle.step(1.0 / 120.0)
func release(battle, id: String, natural: bool = true, scale: float = 1.0) -> bool:
	var spell: Dictionary = battle._owned_spell(id)
	var stats: Dictionary = battle.get_spell_stats(spell)
	var target: Dictionary = battle._spell_combat.legal_target(battle, spell, stats)
	if target.is_empty(): return false
	spell.locked_pos = target.pos
	battle._spell_combat._cast(battle, spell, stats, target, natural, scale)
	stop_natural(battle)
	return true
func total(battle, actor_id: int = -1, source: String = "") -> float:
	var value: float = 0.0
	for hit in battle.hit_log:
		if (actor_id < 0 or int(hit.actor_id) == actor_id) and (source.is_empty() or str(hit.source) == source): value += float(hit.amount)
	return value
func module(battle): return battle._spell_combat.earth
func complete_module_state(battle) -> Dictionary:
	var state: Dictionary = {}
	for property in module(battle).get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
		var value: Variant = module(battle).get(str(property.name))
		state[str(property.name)] = value.duplicate(true) if value is Array or value is Dictionary else value
	return state
func source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in ["res://data/earth_spells_v1.json", "res://scripts/core/route_earth_combat.gd", "res://tests/formal_earth_tests.gd", "res://scripts/core/route_spell_combat.gd", "res://scripts/core/courtyard_route_run.gd"]: result[path] = FileAccess.get_sha256(path)
	return result
func group(id: String, callback: Callable):
	var before: int = checks
	var failed: int = failures.size()
	callback.call()
	groups.append({"id": id, "checks": checks - before, "failures": failures.size() - failed})
func execute():
	group("entry_and_thirty_levels", entry_and_thirty_levels)
	group("bounded_geometry_and_lock", bounded_geometry_and_lock)
	group("construction_capacity_and_termination", construction_capacity_and_termination)
	group("consume_and_echo_identity", consume_and_echo_identity)
	group("guard_shield_and_control", guard_shield_and_control)
	group("pause_cleanup_snapshot_and_mixed", pause_cleanup_snapshot_and_mixed)
	group("starter_envelopes", starter_envelopes)
	group("starter_cdr_sensitivity", starter_cdr_sensitivity)
	var output: String = "res://build/qa/formal-schools-current/earth"
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--qa-out=res://build/qa/") and not str(arg).contains(".."):
			output = str(arg).trim_prefix("--qa-out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	FileAccess.open(output + "/results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures.size(), "details": failures, "groups": groups, "observations": observations, "source_sha256": source_hashes(), "scope": "Actual route earth isolated fixtures. No AI/spawn/clear, renderer, save, interactive launch, full route, performance or final balance approval."}, "\t"))
	print("FORMAL EARTH RULES checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func entry_and_thirty_levels():
	var entry = fresh()
	check(entry.initial_choices().map(func(item): return str(item.id)) == ["R01", "R02", "R03"], "three independent earth starters")
	check("R06" not in entry.eligible_reward_ids(), "R06 not offered without actual source spell")
	var ready = fresh(["R03"])
	check("R06" in ready.eligible_reward_ids(), "R03 ownership unlocks R06 candidate")
	check("R10" in ready.eligible_reward_ids(), "earth passive remains selectable")
	for old in ["RB01", "RP01", "RG01"]: check(old not in ready._artifact_combat.eligible_ids(ready), "retired profession remains absent " + old)
	var expected: Dictionary = {"R01": [150.0, 200.0, 200.0], "R02": [160.0, 220.0, 220.0], "R03": [220.0, 300.0, 420.0], "R04": [360.0, 640.0, 720.0], "R06": [350.0, 575.0, 725.0], "R07": [120.0, 160.0, 160.0], "R08": [500.0, 650.0, 650.0]}
	for level in range(1, 4):
		for id in IDS:
			var battle = fresh([id, "R03"] if id == "R06" else [id], level)
			var stats: Dictionary = battle.get_spell_stats(battle._owned_spell(id))
			check(stats.level.has("cooldown"), "%s level%d runtime level has cooldown" % [id, level])
			if id == "R10":
				check(near(module(battle).school_bonus(battle), [.15, .25, .35][level - 1]), "mastery full level value " + str(level))
				continue
			if id == "R06":
				check(release(battle, "R03"), "R06 fixture source cast")
				advance(battle, 1.0)
				battle.hit_log.clear()
			check(release(battle, id), "%s level%d legal release" % [id, level])
			advance(battle, 8.0 if id == "R04" else 1.5)
			if expected.has(id): check(near(total(battle), expected[id][level - 1]), "%s level%d isolated full result %.3f" % [id, level, total(battle)])
			elif id == "R05": check(near(float(battle.player.shield), [35.0, 50.0, 65.0][level - 1]), "fixed shield level " + str(level))
			elif id == "R09": check(near(module(battle).defense_bonus(battle), [20.0, 30.0, 45.0][level - 1]), "stele defense level " + str(level))

func bounded_geometry_and_lock():
	var shards = fresh(["R01"], 3)
	shards.actors = [enemy(1, Vector2(0, 2)), enemy(2, Vector2(0, 3.1)), enemy(3, Vector2(0, 4.1)), enemy(4, Vector2(2.5, 1))]
	release(shards, "R01")
	advance(shards, 1.0)
	check(near(total(shards, 1), 200.0), "main target excluded from every shard")
	check(near(total(shards, 2), 65.0) and near(total(shards, 3), 65.0), "level3 shard pierce and cast-wide dedup")
	check(near(total(shards, 4), 0.0), "out of fan target not hit")
	var lethal = fresh(["R01"])
	lethal.actors = [enemy(1, Vector2(0, 2), 100), enemy(2, Vector2(0, 3))]
	release(lethal, "R01")
	advance(lethal, 1.0)
	check(near(total(lethal, 2), 50.0), "effective lethal main still produces shards")
	var wave = fresh(["R02"], 3)
	wave.actors = [enemy(1, Vector2(0, 1)), enemy(2, Vector2(0, 3)), enemy(3, Vector2(0, 6))]
	release(wave, "R02")
	advance(wave, 0.08)
	check(near(total(wave, 2), 0.0), "wave cannot hit far enemy before arrival")
	advance(wave, .8)
	check(near(total(wave, 1), 220.0) and near(total(wave, 2), 320.0) and near(total(wave, 3), 0.0), "actual near outer and beyond radius wave geometry")
	var locked = fresh(["R03"], 3)
	var spell: Dictionary = locked.spells[0]
	spell.target_id = 1
	spell.locked_pos = Vector2(0, 2)
	locked.actors[0].pos = Vector2(6, 2)
	var fixed: Dictionary = module(locked).finish_target(locked, spell, locked.get_spell_stats(spell))
	check(fixed.pos == Vector2(0, 2), "windup completion preserves original landing")
	locked._spell_combat._cast(locked, spell, locked.get_spell_stats(spell), fixed, true, 1.0)
	stop_natural(locked)
	advance(locked, .4)
	check(near(total(locked), 0.0) and module(locked).constructs.size() == 1, "missed landing still creates support at actual point")

func construction_capacity_and_termination():
	var battle = fresh(["R03", "R04", "R09"], 1)
	release(battle, "R04")
	release(battle, "R09")
	release(battle, "R03")
	advance(battle, .4)
	check(module(battle).constructs.size() == 3, "three distinct nonblocking constructs")
	for construct in module(battle).constructs:
		check(not construct.blocking and not construct.targetable and not construct.has("health"), "construct never becomes blocking enemy actor")
	var ids: Array = module(battle).constructs.map(func(item): return int(item.id))
	release(battle, "R04", false, .5)
	check(module(battle).constructs.size() == 3, "extra replacement keeps total cap")
	check(module(battle).terminations.size() == 1 and module(battle).terminations[0].reason == "replacement", "replacement has one exclusive termination")
	check(module(battle).constructs.filter(func(item): return str(item.spell_id) == "R04").size() == 1, "one pillar per source")
	check(module(battle).constructs.filter(func(item): return str(item.spell_id) == "R04")[0].id not in ids, "replacement creates new source identity")
	var end = fresh(["R04"])
	release(end, "R04")
	advance(end, 6.0)
	check(near(total(end), 360.0) and module(end).constructs.is_empty(), "due last pulse precedes natural expiry")
	check(module(end).terminations.size() == 1 and module(end).terminations[0].reason == "natural_expiry", "expiry terminates once without bonus explosion")
	var fast = fresh(["R04"], 3)
	fast.extra_cdr = .6
	fast.spells[0].remaining = 0.0
	advance(fast, 8.0)
	check(module(fast).constructs.size() == 1 and module(fast).terminations.size() == 1, "CDR recasts replace pillar and do not copy its pending lifetime")
	observations.append({"id": "R04_high_cdr_replacement", "seconds": 8, "damage": total(fast), "terminations": module(fast).terminations.duplicate(true), "meaning": "Finite replacement loss is declared earth cost; unlike lightning cloud, old pillar does not persist."})

func consume_and_echo_identity():
	var waiting = fresh(["R06", "R03"])
	waiting.spells[0].remaining = 0.0
	advance(waiting, 1.0)
	check(waiting.natural_log.is_empty() and near(waiting.spells[0].remaining, 0.0), "empty construction waits without cooldown or successful cast")
	release(waiting, "R03")
	advance(waiting, .35)
	var count: int = waiting.natural_log.size()
	waiting.spells[0].remaining = 0.0
	advance(waiting, .1)
	check(float(waiting.spells[0].cast_remaining) > .2 and waiting.natural_log.size() == count, "new source still requires complete collapse windup")
	advance(waiting, .3)
	check(waiting.natural_log.size() == count + 1 and module(waiting).constructs.is_empty(), "successful collapse consumes exactly one after full windup")
	var battle = fresh(["R03", "R06"], 3)
	release(battle, "R03")
	advance(battle, .35)
	check(release(battle, "R06"), "collapse has actual source")
	check(module(battle).constructs.is_empty() and near(total(battle, -1, "R06"), 0.0), "source is removed before delayed neighbor damage")
	check(not battle._spell_combat.cast_extra(battle, "R06"), "extra cannot steal already consumed source")
	advance(battle, 1.0)
	check(module(battle).terminations.size() == 1 and module(battle).terminations[0].reason == "consumption", "consume cannot also expire or replace")
	check(near(total(battle, -1, "R03"), 420.0), "R03 predetermined followup survives support consumption")
	check(near(total(battle, -1, "R06"), 575.0) and near(total(battle, -1, "earth_derived"), 150.0), "consumed source main and finite derived aftershock")
	for context in battle.derived_log: check(not context.natural and not context.earth_direct and context.can_crit, "derived echo can crit without direct natural callback")
	var echo = fresh(["R04", "R07"], 3)
	release(echo, "R04")
	release(echo, "R07")
	var old: int = int(module(echo).constructs[0].id)
	release(echo, "R04", false)
	advance(echo, .6)
	check(module(echo)._construct(old).is_empty() and echo.derived_log.is_empty(), "replacement cancels only original source echo and never transfers it")
	var critical = fresh(["R04", "R07"], 1)
	critical.player.crit_rate = 2.0
	release(critical, "R04")
	release(critical, "R07")
	advance(critical, .3)
	check(near(total(critical, -1, "earth_derived"), 150.0), "earth echo follows explicit may-crit rule even above 100 percent")
	var two = fresh(["R03", "R04", "R07"], 3)
	release(two, "R04")
	release(two, "R03")
	advance(two, .35)
	release(two, "R07")
	# First source is pillar at the same point, second is later support. Only second survives.
	release(two, "R04", false)
	advance(two, .6)
	check(two.derived_log.size() == 1 and near(total(two, -1, "earth_derived"), 80.5), "one of two selected source echoes cancels without canceling the other")
	var expired = fresh(["R04", "R06", "R07"], 1)
	release(expired, "R04")
	advance(expired, 5.9)
	release(expired, "R07")
	advance(expired, .1)
	check(module(expired).constructs.is_empty() and not release(expired, "R06"), "expiry-equal source cannot be consumed after its last pulse")
	advance(expired, .3)
	check(expired.derived_log.is_empty(), "natural expiry cancels later source-dependent echo")
	var defense = fresh(["R06", "R09"], 3)
	release(defense, "R09")
	check(near(module(defense).defense_bonus(defense), 45.0), "stele is real defense before consumption")
	release(defense, "R06")
	check(near(module(defense).defense_bonus(defense), 0.0), "consumption removes defense immediately without exit grace")
	var outside = fresh(["R03", "R06"], 1)
	release(outside, "R03")
	advance(outside, .35)
	outside.player.pos = Vector2(10, 2)
	check(not release(outside, "R06"), "construct beyond nine meters is not consumable")
	outside.player.pos = Vector2.ZERO
	outside.actors[0].pos = Vector2(6, 2)
	check(not release(outside, "R06"), "source with no actual shock-circle enemy waits")

func guard_shield_and_control():
	var shield = fresh(["R05"], 3)
	shield.player.shield = 181.0
	release(shield, "R05", false, 5.0)
	check(near(float(shield.player.shield), 200.0), "extra damage scale never amplifies fixed restore or overflow")
	check(not release(shield, "R05"), "full shield cancels release")
	var charged = fresh(["R04", "R05"], 3)
	check("GT01" in charged._artifact_combat.eligible_ids(charged), "actual shield restore plus damage qualifies common GT01")
	charged._artifact_combat._owned.append("GT01")
	charged._artifact_combat.apply_acquisition(charged, "GT01")
	charged.player.shield = float(charged.player.max_shield) - 19.0
	release(charged, "R05")
	check(near(float(charged._artifact_combat.state_snapshot().generic.charge), 76.0), "GT01 charges only actual19 restored rather than amplified request")
	release(charged, "R04")
	check(near(total(charged, -1, "GT01"), 76.0), "natural pillar first effective pulse releases common charge once")
	charged.player.shield = float(charged.player.max_shield) - 10.0
	charged.restore_player_shield(10.0, "R05")
	charged._artifact_combat._generic._charge_cooldown = 0.0
	advance(charged, .8)
	check(near(float(charged._artifact_combat.state_snapshot().generic.charge), 40.0) and near(total(charged, -1, "GT01"), 76.0), "later pillar pulse cannot recheck the same natural cast token")
	var ward = fresh(["R09", "R10"], 3)
	ward.player.shield = 1.0
	release(ward, "R09")
	check(near(module(ward).defense_bonus(ward), 60.0), "stele plus real shield mastery share defense bucket")
	ward.player.shield = 0.0
	check(near(module(ward).defense_bonus(ward), 45.0), "mastery defense vanishes at zero shield")
	ward.player.pos = Vector2(5, 0)
	module(ward).after_player_motion(ward)
	check(near(module(ward).defense_bonus(ward), 45.0), "exit grace applies before the first post-movement incoming hit")
	advance(ward, .1)
	check(near(module(ward).defense_bonus(ward), 45.0), "actual movement exit starts one grace")
	advance(ward, 1.5)
	check(near(module(ward).defense_bonus(ward), 0.0), "grace expires without refresh from lingering outside")
	ward.player.pos = Vector2.ZERO
	advance(ward, .01)
	ward.blocks = [{"center": Vector2(1, 0), "size": Vector2(.5, 4)}]
	ward.player.pos = Vector2(2, 0)
	advance(ward, .01)
	check(near(module(ward).defense_bonus(ward), 0.0), "wall disconnect does not grant movement grace")
	var slam = fresh(["R08"])
	slam.actors = [enemy(1, Vector2(0, 2)), enemy(2, Vector2(.5, 2)), enemy(3, Vector2(-.5, 2)), enemy(4, Vector2(0, 2.5))]
	slam.actors[1].type_id = "EL01"
	slam.actors[2].boss = true
	slam.actors[2].combat_spec = {"definition": {"phases": []}}
	slam.actors[2].boss_phase_index = 0
	slam.actors[3].uninterruptible = true
	release(slam, "R08")
	advance(slam, .71)
	check(module(slam).actor_stunned(slam.actors[0]) and module(slam).actor_stunned(slam.actors[1]), "normal and elite receive hard control")
	check(not module(slam).actor_stunned(slam.actors[2]) and not module(slam).actor_stunned(slam.actors[3]), "Boss and uninterruptible reject hard control but still take damage")
	check(near(total(slam, 3), 500.0) and near(total(slam, 4), 500.0), "hard-control rejection never prevents main damage")
	advance(slam, .13)
	check(module(slam).actor_stunned(slam.actors[0]) and not module(slam).actor_stunned(slam.actors[1]), "elite duration multiplied once by 0.35")

func pause_cleanup_snapshot_and_mixed():
	var battle = fresh(["R04", "R07"], 3)
	release(battle, "R04")
	release(battle, "R07")
	var snapshot: Dictionary = module(battle).get_snapshot(battle)
	battle.paused = true
	var old: float = module(battle).clock
	advance(battle, 2.0)
	check(near(module(battle).clock, old) and battle.derived_log.is_empty(), "pause freezes constructs and pending echoes")
	battle.paused = false
	battle._owned_spell("R04").level = 1
	advance(battle, .9)
	check(near(total(battle, -1, "R04"), 160.0), "existing pillar keeps released level3 coefficient and pulse phase")
	check(snapshot.earth_constructs.size() == 1 and snapshot.earth_constructs[0].context.earth_level.tick == .8, "snapshot is detached from mutable live state")
	var ward = fresh(["R09"], 3)
	release(ward, "R09")
	ward.player.pos = Vector2(5, 0)
	var before_query: Dictionary = complete_module_state(ward)
	for _query in range(12):
		module(ward).get_snapshot(ward)
		ward.get_snapshot()
		module(ward).defense_bonus(ward)
	check(complete_module_state(ward) == before_query, "repeated module/full snapshots and defense queries never mutate any module property")
	check(float(module(ward).constructs[0].grace_until) == -INF, "queries cannot observe movement as a new exit transaction")
	module(ward).after_player_motion(ward)
	var exit_deadline: float = float(module(ward).constructs[0].grace_until)
	var after_exit: Dictionary = complete_module_state(ward)
	for _query in range(12):
		ward.get_snapshot()
		module(ward).get_snapshot(ward)
		module(ward).defense_bonus(ward)
	check(complete_module_state(ward) == after_exit and near(float(module(ward).constructs[0].grace_until), exit_deadline), "repeated snapshot queries cannot create, extend or shorten actual exit grace")
	advance(ward, 1.4)
	for _query in range(12): ward.get_snapshot()
	check(near(float(module(ward).constructs[0].grace_until), exit_deadline) and near(module(ward).defense_bonus(ward), 45.0), "query frequency never changes the movement exit deadline")
	advance(ward, .11)
	check(near(module(ward).defense_bonus(ward), 0.0), "exit grace expires at the original rule deadline regardless of reads")
	module(battle).stop_room()
	check(module(battle).constructs.is_empty() and module(battle).pending.is_empty() and module(battle).projectiles.is_empty() and module(battle).waves.is_empty(), "room cleanup clears every transient earth object")
	var mixed = fresh(["R01", "R09", "R10", "F01", "L01"], 3)
	check(module(mixed).spell_count(mixed) == 3 and near(module(mixed).school_bonus(mixed), .5) and near(module(mixed).cooldown_bonus(mixed), .1), "distinct earth spells count once and passive plus resonance add")
	check(mixed._spell_combat.spirits.is_empty() and not module(mixed).is_earth_spell("F04"), "construction never counts as legacy summon or restores old F04")
	var echo = fresh(["R01"], 3, "echo")
	release(echo, "R01")
	advance(echo, .15)
	check(echo._gem_combat.echo.pending.size() <= 1, "one finite actual projectile contact does not record infinite coverage")

func starter_envelopes():
	for id in ["R01", "R02", "R03"]:
		var battle = fresh([id])
		battle.actors = [enemy(1, Vector2(0, 2), 180.0)]
		battle.spells[0].remaining = 0.0
		advance(battle, 6.0)
		check(float(battle.actors[0].health) <= 0.0, "isolated180 starter TTK under6 " + id)
		check(not battle.hit_log.is_empty() and float(battle.hit_log[0].at) <= 2.0, "starter first effective hit under2 " + id)
		observations.append({"id": id, "first_hit": battle.hit_log[0].at if not battle.hit_log.is_empty() else -1, "ttk": battle.hit_log[-1].at if not battle.hit_log.is_empty() else -1, "context": "one stationary visible180health target, attack100, no crit, natural windup/CD"})

func starter_cdr_sensitivity():
	for id in ["R01", "R02", "R03"]:
		for population in [1, 6]:
			var previous: float = -1.0
			for cdr in [0.0, .3, .6]:
				var battle = fresh([id], 3)
				battle.extra_cdr = cdr
				battle.actors = [enemy(1, Vector2(0, 3))]
				if population == 6:
					var points: Array = [Vector2(-.9, 4.2), Vector2(0, 4.2), Vector2(.9, 4.2), Vector2(0, 5.1), Vector2(.5, 3.6)] if id == "R01" else [Vector2(-.4, 3), Vector2(.4, 3), Vector2(0, 3.4), Vector2(-.3, 2.6), Vector2(.3, 2.6)]
					for index in points.size(): battle.actors.append(enemy(index + 2, points[index]))
				battle.spells[0].remaining = 0.0
				advance(battle, 30.0)
				var result: float = total(battle)
				check(result >= previous - .01, "%s CDR%.1f does not lower isolated/declared-cluster30sec damage" % [id, cdr])
				previous = result
				check(module(battle).constructs.size() <= 1, "starter sweep never duplicates support source")
				observations.append({"id": id, "level": 3, "seconds": 30, "cdr": cdr, "targets": population, "damage": result, "natural_casts": battle.natural_log.size(), "model": "actual core, stationary visible geometry, no criticals/AI/spawn; six-target reachable envelope, not natural average"})
