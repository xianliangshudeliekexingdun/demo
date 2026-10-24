extends SceneTree
## Real production rules with prescribed positions/actions, no natural route or rendering.

var checks: int = 0
var failures: Array = []
var observations: Array = []

class Fixture extends "res://scripts/core/courtyard_route_run.gd":
	var hit_log: Array = []
	var blocked_points: Array = []
	func _reserve_batch(): pass
	func _update_spawn(_dt: float): pass
	func _check_clear(): pass
	func _update_enemies(dt: float):
		_spell_combat.before_damage_tick(self, dt)
		_spell_combat.wind.record_player_motion(self, player.previous, player.pos, dt)
		for actor in actors: actor.previous = actor.pos
	func line_is_clear(from: Vector2, to: Vector2) -> bool:
		if to in blocked_points: return false
		return super.line_is_clear(from, to)
	func damage_enemy(actor: Dictionary, amount: float, source: String = ""):
		var before: float = float(actor.health)
		super.damage_enemy(actor, amount, source)
		hit_log.append({"at": time, "id": int(actor.id), "source": source, "amount": before - maxf(0.0, float(actor.health))})


func _initialize(): call_deferred("execute")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error("Gem school: " + label)
func near(a: float, b: float, tolerance: float = 0.01) -> bool: return absf(a - b) <= tolerance
func enemy(id: int = 1, pos: Vector2 = Vector2(0, 2)) -> Dictionary:
	return {"id": id, "type": "M01", "type_id": "M01", "pos": pos, "previous": pos,
		"health": 1000000.0, "max_health": 1000000.0, "radius": 0.3, "phase": "chase",
		"push_resistance": 0.0, "spell_slows": {}, "slow_remaining": 0.0, "slow_multiplier": 1.0}
func fresh(core: String, ids: Array, level: int = 1):
	var run = Fixture.new()
	var school: String = core if not core.is_empty() else "wind"
	var initial: String = {"lightning": "L01", "wind": "W01", "earth": "R03", "spirit": "S02"}.get(school, "W01")
	var result: Dictionary = run.configure({"route_school": school, "gem_core": core}, 20261022)
	check(bool(result.ok), "configure " + core)
	check(run.choose_initial(initial), "initial " + core)
	run._spawn_done = true
	run.spawn_warnings.clear()
	run.blocks.clear()
	run.player.pos = Vector2.ZERO
	run.player.previous = Vector2.ZERO
	run.player.attack = 100.0
	run.player.crit_rate = 0.0
	run.spells.clear()
	for id in ids:
		var spell: Dictionary = run._new_spell(str(id))
		spell.level = level
		run._refresh_spell(spell)
		run.spells.append(spell)
	run.actors = [enemy()]
	stop_natural(run)
	return run
func stop_natural(run) -> void:
	for spell in run.spells:
		spell.remaining = 9999.0
		spell.cast_remaining = 0.0
func advance(run, seconds: float, movement: Vector2 = Vector2.ZERO) -> void:
	for _tick in roundi(seconds * 120.0): run.step(1.0 / 120.0, movement)
func release(run, id: String, natural: bool = true) -> void:
	var spell: Dictionary = run._owned_spell(id)
	var stats: Dictionary = run.get_spell_stats(spell)
	var target: Dictionary = run._spell_combat.legal_target(run, spell, stats)
	check(not target.is_empty(), "legal release " + id)
	if target.is_empty(): return
	spell.locked_pos = target.pos
	run._spell_combat._cast(run, spell, stats, target, natural, 1.0)
	stop_natural(run)
func damage(run, source: String, actor_id: int = -1) -> float:
	var total: float = 0.0
	for hit in run.hit_log:
		if str(hit.source) == source and (actor_id < 0 or int(hit.id) == actor_id): total += float(hit.amount)
	return total
func core_state(run):
	var router = run._gem_combat.schools
	return router.sets.get(run.gem_core(), router)
func charge_lightning(run, values: Array = [100.0, 100.0, 100.0, 100.0]) -> void:
	var helper = core_state(run)
	for index in values.size():
		if index > 0: advance(run, 0.6)
		helper.lightning_hit(run, run.actors[0], float(values[index]), {"cast_id": 9000 + index, "natural": true}, true)


func lightning_rules() -> void:
	var run = fresh("lightning", ["L04", "L08", "L09"], 3)
	var helper = core_state(run)
	check(run._gem_combat.core == "lightning", "actual lightning core is configured")
	var lightning = run._spell_combat.lightning
	lightning.status.apply(run, run.actors[0], 10.0)
	release(run, "L04")
	check(helper.lightning_charges == 1, "real natural body checks old conductive before refresh")
	var first: float = helper.lightning_stored
	check(first > 0.0, "real natural body contributes actual damage")
	lightning._direct_hit(run, run.actors[0], 1.0, {"cast_id": 444, "natural": true, "spell_id": "L04", "school": "lightning", "kind": "direct", "lightning_level": run.get_spell_stats(run._owned_spell("L04")).level})
	check(helper.lightning_charges == 1, "global .6 gate blocks different same-time cast")
	advance(run, 0.6)
	lightning._direct_hit(run, run.actors[0], 1.0, {"cast_id": 445, "natural": false, "spell_id": "L04", "school": "lightning", "kind": "direct", "lightning_level": run.get_spell_stats(run._owned_spell("L04")).level})
	check(helper.lightning_charges == 1, "extra release cannot charge")
	helper.clear()
	helper.lightning_hit(run, run.actors[0], 100.0, {"cast_id": 700, "natural": true}, false)
	helper.lightning_hit(run, run.actors[0], 100.0, {"cast_id": 700, "natural": true}, true)
	check(helper.lightning_charges == 0, "later hit cannot repair unmarked first effective hit")
	charge_lightning(run)
	check(helper.lightning_charges == 4 and near(helper.lightning_stored, 160.0), "four hand hits stock160")
	run.actors = [enemy(1), enemy(2, Vector2(1, 2)), enemy(3, Vector2(-1, 2)), enemy(4, Vector2(2, 2))]
	for actor in run.actors: lightning.status.apply(run, actor, 10.0)
	lightning.status.apply_vulnerability(run.actors[0], 0.1, 10.0)
	release(run, "L08")
	check(helper.lightning_charges == 0 and helper.lightning_pending.size() == 1, "next natural cast spends full charges once")
	check(not lightning.status.has_conductive(2) and not lightning.status.has_conductive(3), "two consumed neighbor marks removed before network capture")
	check(lightning.status.has_conductive(4), "unused fourth old mark preserved")
	check(near(lightning.status.target_vulnerability(run.actors[0]), 0.1), "conductive consumption preserves independent vulnerability")
	var captured_members: Array = []
	for item in lightning.pending:
		if str(item.kind) == "network": captured_members.append_array(item.get("members", []))
	check(captured_members.is_empty(), "L08 captures no consumed old component (empty future probe is harmless)")
	advance(run, 0.15)
	check(near(damage(run, "gem_lightning", 1), 160.0) and near(damage(run, "gem_lightning", 2), 48.0), "stored strike not multiplied by vulnerability twice")
	check(near(damage(run, "gem_lightning"), 256.0), "finite main plus two neighbors total256")
	check(helper.lightning_charges == 0, "discharge cast cannot refill its own loop")
	run = fresh("lightning", ["L04"])
	helper = core_state(run)
	charge_lightning(run, [10000.0, 10000.0, 10000.0, 10000.0])
	check(near(helper.lightning_stored, 800.0), "lightning stock capped at first-cycle attack8")
	advance(run, 5.9)
	check(helper.lightning_charges == 4, "full stock lasts below idle6")
	advance(run, 0.1)
	check(helper.lightning_charges == 0 and near(helper.lightning_stored, 0.0), "full stock expires at6 without refreshing")
	run = fresh("lightning", ["L04"])
	helper = core_state(run)
	charge_lightning(run)
	lightning = run._spell_combat.lightning
	lightning.status.apply(run, run.actors[0], 10.0)
	release(run, "L04")
	run.actors[0].pos += Vector2(1, 0)
	advance(run, 0.15)
	check(near(damage(run, "gem_lightning"), 0.0), "locked lightning landing misses a moved target without retargeting")
	run = fresh("lightning", ["L07"], 3)
	helper = core_state(run)
	charge_lightning(run)
	lightning = run._spell_combat.lightning
	lightning.status.apply(run, run.actors[0], 20.0)
	# Mature old mark is removed at release, before the delayed original judgment.
	lightning.status.states[1].since = lightning.status.clock - 2.0
	release(run, "L07")
	check(not lightning.status.has_conductive(1), "L07 old conductivity consumed before original judgment")
	advance(run, 0.25)
	check(near(damage(run, "lightning_conditional"), 0.0) and near(damage(run, "lightning_mature_arc"), 0.0), "discharge L07 loses consumed condition and mature arcs")
	check(helper.lightning_charges == 0, "L07 discharge body cannot refill")
	run = fresh("lightning", ["L05"], 3)
	release(run, "L05")
	advance(run, 5.0)
	check(core_state(run).lightning_charges == 0, "one cloud's later conductive waves cannot repair its unmarked first hit")
	run = fresh("lightning", ["L04"])
	run._artifact_combat._owned.append("GT01")
	run._artifact_combat.apply_acquisition(run, "GT01")
	run.player.shield = 0.0
	run.restore_player_shield(20.0, "fixture")
	run._spell_combat.lightning.status.apply(run, run.actors[0], 10.0)
	release(run, "L04")
	check(damage(run, "GT01") > 0.0, "natural lightning actually releases existing GT01 charge")
	check(near(core_state(run).lightning_stored, damage(run, "L04") * 0.4), "lightning stock excludes GT01 on-hit damage from same transaction")
	observations.append({"core": "lightning", "finite_hand_total": 256.0, "stock_cap": 800.0})


func wind_rules() -> void:
	var run = fresh("wind", ["W01"])
	var helper = core_state(run)
	release(run, "W01")
	check(near(helper.wind_flow_until, 2.5), "real natural wind release opens2.5 flow")
	advance(run, 0.9, Vector2.RIGHT)
	check(helper.wind_layers == 3, "4.5m real voluntary motion reaches three stacks")
	check(near(helper.wind_distance, 0.0), "full wind stack cannot bank excess route")
	release(run, "W01")
	check(helper.wind_layers == 3, "wind natural release does not consume stacks")
	check(near(float(run._spell_combat.wind.projectiles.back().radius), float(run.get_spell_stats(run._owned_spell("W01")).level.width) * 0.5 * 1.12), "wind release snapshots selected damage width")
	var flow: float = helper.wind_flow_until
	release(run, "W01", false)
	check(near(helper.wind_flow_until, flow), "extra wind does not refresh flow")
	check(near(float(run._spell_combat.wind.projectiles.back().context.damage_scale), 1.0), "extra wind does not inherit core body multiplier")
	advance(run, 0.5)
	check(helper.wind_layers == 2, "stationary .5 seconds loses first layer")
	advance(run, 1.0)
	check(helper.wind_layers == 0, "stationary next two .5 ticks lose remaining layers")
	var no_core = fresh("", ["W04"])
	run = fresh("wind", ["W04"])
	helper = core_state(run)
	helper.wind_layers = 3
	release(no_core, "W04")
	release(run, "W04")
	check(near(damage(run, "W04") / damage(no_core, "W04"), 1.36), "actual three-layer natural body gains36pct")
	for id in ["W01", "W02", "W03", "W04", "W05", "W06", "W07", "W08", "W09"]:
		var source: Dictionary = run._spell_combat.wind.source_spells[id].levels[0].duplicate(true)
		var before: Dictionary = source.duplicate(true)
		var context: Dictionary = {"natural": true, "damage_scale": 1.0}
		helper.wind_cast(run, id, source, context)
		if id in ["W01", "W02", "W03", "W07"]: check(near(source.width, float(before.width) * 1.12), id + " only hit width increased")
		elif id in ["W06", "W08"]: check(near(source.radius, float(before.radius) * 1.12), id + " only main radius increased")
		else: check(source == before, id + " control/guard geometry unchanged")
		for key in ["range", "out_length", "max_path", "center_radius", "total_length", "target_cap", "duration", "followup_coefficient"]:
			if before.has(key): check(source[key] == before[key], id + " retains " + key)
	run = fresh("wind", ["W01"])
	release(run, "W01")
	advance(run, 0.3)
	check(core_state(run).wind_layers == 0, "no movement grants no wind stacks")
	run._spell_combat.wind.record_player_motion(run, Vector2.ZERO, Vector2.ZERO, 0.1)
	check(near(core_state(run).wind_distance, 0.0), "wall/zero route cannot charge wind")
	run = fresh("wind", ["W08"], 3)
	helper = core_state(run)
	helper.wind_layers = 3
	release(run, "W08")
	var path = run._spell_combat.wind
	var unmodified: Dictionary = run.get_spell_stats(run._owned_spell("W08")).level
	advance(run, 0.2, Vector2.RIGHT)
	check(not path.path_segments.is_empty(), "W08 records actual postcollision short segments")
	if not path.path_segments.is_empty():
		check(near(float(path.path_segments[0].radius), float(unmodified.radius) * 1.12), "actual W08 damage segment radius snapshots core widening")
	check(float(path.recording.length) <= float(unmodified.total_length) and near(float(path.recording.context.wind_level.total_length), float(unmodified.total_length)), "W08 route recording budget is unchanged")
	check(int(path.recording.context.wind_level.shared_hit_cap) == int(unmodified.shared_hit_cap) and int(path.recording.context.wind_level.cast_hit_cap) == int(unmodified.cast_hit_cap), "W08 per-actor/shared finite hit budgets are unchanged")
	var body = fresh("wind", ["W06"], 3)
	var plain = fresh("", ["W06"], 3)
	core_state(body).wind_layers = 3
	body.actors.append(enemy(2, Vector2(2.3, 2)))
	release(body, "W06")
	release(plain, "W06")
	advance(body, 0.5)
	advance(plain, 0.5)
	check(near(damage(body, "wind_followup", 1), damage(plain, "wind_followup", 1)), "wind layers do not amplify W06 conditional followup")
	check(damage(body, "W06", 2) > 0.0 and near(damage(body, "wind_followup", 2), 0.0), "W06 widened main blast does not widen followup geometry")
	observations.append({"core": "wind", "max_body_multiplier": 1.36, "geometry_multiplier": 1.12})


func earth_rules() -> void:
	var run = fresh("earth", ["R03"])
	var helper = core_state(run)
	release(run, "R03")
	advance(run, 0.3)
	check(not helper.earth_anchor.is_empty(), "R03 real postfall source can be anchored")
	check(near(helper.earth_dwell, 0.0), "new source selection does not count pre-existence tick")
	advance(run, 1.5 - 1.0 / 120.0)
	check(near(damage(run, "gem_earth"), 0.0), "earth has no premature maturation pulse")
	advance(run, 1.0 / 120.0)
	check(near(damage(run, "gem_earth"), 200.0), "earth mature first pulse is200 at attack100")
	check(helper.earth_mature, "earth maturity is real snapshot state")
	for hit in run.hit_log:
		if str(hit.source) == "gem_earth": check(near(hit.at, 1.8), ".3 released fall plus1.5 dwell first pulse1.8; natural windup adds.35")
	var anchor_id: int = int(helper.earth_anchor.id)
	var earth = run._spell_combat.earth
	var construct: Dictionary = earth._construct(anchor_id)
	earth._end_construct(run, construct, "consumption")
	check(helper.earth_anchor.is_empty() and not helper.earth_mature, "consuming source clears anchor immediately without exit grace")
	var before: float = damage(run, "gem_earth")
	advance(run, 3.2)
	check(near(damage(run, "gem_earth"), before), "removed source cannot issue a final or refunded pulse")
	run = fresh("earth", ["R04", "R09"])
	helper = core_state(run)
	release(run, "R04")
	release(run, "R09")
	advance(run, 1.5 + 1.0 / 120.0)
	check(helper.earth_mature, "one of two real sources matures")
	check(near(damage(run, "gem_earth"), 200.0), "multiple constructs do not multiply core pulses")
	run.player.pos = Vector2(0, -4)
	advance(run, 0.4)
	check(not helper.earth_anchor.is_empty(), "short leave keeps same source")
	run.player.pos = Vector2.ZERO
	advance(run, 0.1)
	check(helper.earth_mature, "return inside .5 preserves maturity")
	run.player.pos = Vector2(0, -4)
	advance(run, 0.51)
	check(helper.earth_anchor.is_empty(), "leave beyond .5 clears source")
	run = fresh("earth", ["R04"])
	release(run, "R04")
	advance(run, 1.5 + 1.0 / 120.0)
	helper = core_state(run)
	var point: Vector2 = helper.earth_anchor.pos
	run.actors = [enemy(1, point), enemy(2, point + Vector2(.4, 0)), enemy(3, point + Vector2(-.4, 0)), enemy(4, point + Vector2(0, .4)), enemy(5, point + Vector2(0, -.4)), enemy(6, point + Vector2(4, 0))]
	run.blocked_points = [run.actors[4].pos]
	run.hit_log.clear()
	advance(run, 3.0)
	check(near(damage(run, "gem_earth"), 800.0), "earth pulse has finite max4 actual targets")
	check(near(damage(run, "gem_earth", 5), 0.0) and near(damage(run, "gem_earth", 6), 0.0), "earth respects wall and radius")
	run = fresh("earth", ["R04", "R06"])
	release(run, "R04")
	advance(run, 1.5)
	helper = core_state(run)
	check(not helper.earth_mature, "source is one fixed tick before maturity")
	release(run, "R06")
	advance(run, 1.0 / 120.0)
	check(helper.earth_anchor.is_empty() and near(damage(run, "gem_earth"), 0.0), "R06 consumption at maturity boundary cancels source before queued tick")
	run = fresh("earth", ["R01"])
	advance(run, 2.0)
	check(core_state(run).earth_anchor.is_empty() and near(damage(run, "gem_earth"), 0.0), "earth core never manufactures a source for R01-only start")
	observations.append({"core": "earth", "first_R03_pulse_after_release": 1.8, "natural_windup": 0.35, "pulse": 200.0})


func pet_action(run, unit: Dictionary) -> void:
	unit.attack_id = int(unit.attack_id) + 1
	unit.pos = Vector2.ZERO
	run._spell_combat.spirit_school._attack(run, unit, run.actors[0])


func spirit_rules() -> void:
	var run = fresh("spirit", ["S02"])
	var helper = core_state(run)
	release(run, "S02")
	var unit: Dictionary = run._spell_combat.spirit_school.units[0]
	for index in 3:
		pet_action(run, unit)
		check(helper.spirit_points == index + 1, "single-family action charges once " + str(index))
	check(near(damage(run, "gem_spirit"), 0.0), "third action fills but does not yet pay")
	var base: float = damage(run, "summon") / 3.0
	pet_action(run, unit)
	check(helper.spirit_points == 0, "fourth action spends and does not refill")
	check(near(damage(run, "gem_spirit"), base * 1.2), "actual single-pet payoff120pct noncritical plan")
	check(helper.spirit_last_family == "S02", "pay action still updates last family")
	run = fresh("spirit", ["S02", "S03", "S05"], 3)
	run.actors = [enemy(1, Vector2(0, 1)), enemy(2, Vector2(.1, 1))]
	helper = core_state(run)
	release(run, "S02")
	release(run, "S03")
	var spirit = run._spell_combat.spirit_school
	var ranged: Dictionary = spirit.units[0]
	var sword: Dictionary = {}
	for item in spirit.units:
		if str(item.spell_id) == "S03": sword = item
	pet_action(run, ranged)
	check(helper.spirit_points == 1, "piercing normal with multiple victims charges one action")
	pet_action(run, sword)
	check(helper.spirit_points == 3, "different family adds extra one point")
	helper.spirit_action(run, "S02", [{"actor": run.actors[0], "base": 100.0, "actual": 0.0}])
	check(helper.spirit_points == 3, "missed ready action does not consume")
	run.player.crit_rate = 1.0
	run.player.crit_multiplier = 3.0
	pet_action(run, sword)
	check(helper.spirit_points == 0, "ready multivictim action pays once and no refill")
	check(damage(run, "gem_spirit") > 0.0, "ready action adds real finite hits")
	var raw: float = float(run.player.attack) * float(sword.level.coefficient) * (1.0 + spirit.school_bonus(run))
	check(near(damage(run, "gem_spirit", 1), raw * 1.2), "core extra ignores normal body's3x crit")
	for item in spirit.units: item.next_at = 9999.0; item.windup_target_id = -1
	helper.spirit_points = 2
	release(run, "S05")
	advance(run, 0.6)
	check(helper.spirit_points == 2, "command damage does not charge or spend")
	advance(run, 2.4)
	check(helper.spirit_points == 0 and helper.spirit_last_family.is_empty(), "3s without successful normal clears all spirit progress")
	run = fresh("spirit", ["S02", "S06"])
	release(run, "S02")
	helper = core_state(run)
	helper.spirit_points = 3
	helper.spirit_last_family = "S02"
	run._spell_combat.spirit_school.units[0].expires = run._spell_combat.spirit_school.clock + 0.1
	release(run, "S06")
	check(helper.spirit_points == 0 and helper.spirit_last_family.is_empty(), "consumption of last pet immediately clears concerto")
	observations.append({"core": "spirit", "single_pet_cycle": "three charge, next payoff", "noncritical_bonus_fraction": 1.2})


func lifecycle_rules() -> void:
	for core in ["lightning", "wind", "earth", "spirit"]:
		var id: String = {"lightning": "L04", "wind": "W01", "earth": "R03", "spirit": "S02"}[core]
		var run = fresh(core, [id])
		release(run, id)
		advance(run, 0.2)
		var before: Dictionary = core_state(run).snapshot()
		run.set_paused(true)
		advance(run, 1.0, Vector2.RIGHT)
		check(before == core_state(run).snapshot(), core + " paused state frozen")
		run.set_paused(false)
		run._stop_combat()
		var helper = core_state(run)
		check(helper.clock == 0.0 and helper.lightning_pending.is_empty() and helper.lightning_charges == 0 and helper.wind_layers == 0 and helper.earth_anchor.is_empty() and helper.spirit_points == 0, core + " room teardown clears temporal state")


func execute() -> void:
	lightning_rules()
	wind_rules()
	earth_rules()
	spirit_rules()
	lifecycle_rules()
	var output: String = "res://build/qa/gem-v3-implementation-20261022/schools"
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--qa-out=res://build/qa/") and not str(arg).contains(".."):
			output = str(arg).trim_prefix("--qa-out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var file = FileAccess.open(output + "/results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures.size(), "failure_messages": failures,
		"observations": observations, "source_sha256": source_hashes(), "scope": "production core; prescribed positions/actions; no natural route, visual, performance or human playtest"}, "\t"))
	file.close()
	print("GEM_V3_SCHOOL_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)


func source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in ["res://tests/gem_v3_school_tests.gd", "res://scripts/core/route_gem_schools.gd",
		"res://scripts/core/route_lightning_combat.gd", "res://scripts/core/route_lightning_status.gd",
		"res://scripts/core/route_wind_combat.gd", "res://scripts/core/route_earth_combat.gd",
		"res://scripts/core/route_spirit_combat.gd", "res://scripts/core/courtyard_route_run.gd",
		"res://scripts/core/route_gem_combat.gd", "res://data/magic_gems_v1.json",
		"res://data/lightning_spells_v1.json", "res://data/wind_spells_v1.json",
		"res://data/earth_spells_v1.json", "res://data/spirit_spells_v1.json",
		"res://data/generic_artifacts_v1.json", "res://data/balance_candidates/first_run_v1.json"]:
		result[path] = FileAccess.get_sha256(path)
	return result
