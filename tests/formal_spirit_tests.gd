extends SceneTree
## Production-core fixtures. Enemy movement/spawning/clear and natural reward
## randomness are isolated; all spell and damage transactions remain real.

const IDS = ["S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08", "S09", "S10"]
var checks: int = 0
var failures: Array = []
var groups: Array = []
var observations: Array = []

class Fixture extends "res://scripts/core/courtyard_route_run.gd":
	var hit_log: Array = []
	var natural_casts: Array = []
	var body_contexts: Array = []
	var summon_contexts: Array = []
	var extra_cdr: float = 0.0
	func _reserve_batch(): pass
	func _update_spawn(_dt: float): pass
	func _check_clear(): pass
	func _update_enemies(dt: float):
		_spell_combat.before_damage_tick(self, dt)
		for actor in actors: actor.previous = actor.pos
	func artifact_cooldown_reduction() -> float:
		return super.artifact_cooldown_reduction() + extra_cdr
	func damage_enemy(actor: Dictionary, amount: float, source: String = ""):
		var before: float = float(actor.get("health", 0.0))
		super.damage_enemy(actor, amount, source)
		hit_log.append({"at": time, "actor_id": int(actor.id), "source": source,
			"amount": before - maxf(0.0, float(actor.health))})
	func on_spell_cast(spell: Dictionary, target: Dictionary, context: Dictionary):
		natural_casts.append({"id": spell.id, "at": time, "context": context.duplicate(true)})
		super.on_spell_cast(spell, target, context)
	func resolve_spell_hit(actor: Dictionary, coefficient: float, context: Dictionary) -> Dictionary:
		body_contexts.append(context.duplicate(true))
		return super.resolve_spell_hit(actor, coefficient, context)
	func resolve_summon_hit(actor: Dictionary, coefficient: float, context: Dictionary = {}) -> float:
		summon_contexts.append({"at": time, "actor_id": int(actor.id), "coefficient": coefficient, "context": context.duplicate(true)})
		return super.resolve_summon_hit(actor, coefficient, context)

func _initialize(): call_deferred("execute")
func check(value: bool, label: String):
	checks += 1
	if not value:
		failures.append(label)
		push_error("Formal spirit: " + label)
func near(a: float, b: float, tolerance: float = 0.01) -> bool:
	return absf(a - b) <= tolerance
func enemy(id: int = 1, pos: Vector2 = Vector2(0, 2), health: float = 1000000.0, type: String = "M01") -> Dictionary:
	return {"id": id, "type": type, "type_id": type, "pos": pos, "previous": pos,
		"health": health, "max_health": health, "radius": 0.3, "phase": "chase", "push_resistance": 0.0,
		"spell_slows": {}, "slow_remaining": 0.0, "slow_multiplier": 1.0}
func stop_natural(battle):
	for spell in battle.spells:
		spell.remaining = 9999.0
		spell.cast_remaining = 0.0
func fresh(ids: Array = ["S01"], level: int = 1, core: String = ""):
	var battle = Fixture.new()
	var configured: Dictionary = battle.configure({"route_school": "spirit", "gem_core": core}, 20261021)
	check(bool(configured.get("ok", false)), "actual spirit route config")
	if not bool(configured.get("ok", false)): return battle
	check(battle.choose_initial("S01"), "actual spirit initial choice")
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
func advance(battle, duration: float):
	for _index in roundi(duration * 120.0): battle.step(1.0 / 120.0)
func school(battle): return battle._spell_combat.spirit_school
func release(battle, id: String, natural: bool = true, scale: float = 1.0):
	var spell: Dictionary = battle._owned_spell(id)
	var stats: Dictionary = battle.get_spell_stats(spell)
	var target: Dictionary = battle._spell_combat.legal_target(battle, spell, stats)
	check(not target.is_empty(), "legal actual release " + id)
	if target.is_empty(): return
	spell.locked_pos = target.pos
	battle._spell_combat._cast(battle, spell, stats, target, natural, scale)
	stop_natural(battle)
func damage(battle, source: String = "", actor_id: int = -1) -> float:
	var total: float = 0.0
	for hit in battle.hit_log:
		if (source.is_empty() or str(hit.source) == source) and (actor_id < 0 or int(hit.actor_id) == actor_id): total += float(hit.amount)
	return total
func grant(battle, id: String):
	battle._artifact_combat._owned.append(id)
	battle._artifact_combat.apply_acquisition(battle, id)
func group(id: String, work: Callable):
	var previous: int = checks
	var failed: int = failures.size()
	work.call()
	groups.append({"id": id, "checks": checks - previous, "failures": failures.size() - failed})
func execute():
	group("entry_prerequisites_and_growth", entry_prerequisites_and_growth)
	group("ten_spells_three_levels", ten_spells_three_levels)
	group("independent_starters_and_capacities", independent_starters_and_capacities)
	group("normal_timing_path_and_lifetime", normal_timing_path_and_lifetime)
	group("commands_recall_and_fields", commands_recall_and_fields)
	group("mark_and_slow_scope", mark_and_slow_scope)
	group("generic_items_and_gems", generic_items_and_gems)
	group("pause_cleanup_and_snapshots", pause_cleanup_and_snapshots)
	var hashes: Dictionary = {}
	for path in ["res://tests/formal_spirit_tests.gd", "res://data/spirit_spells_v1.json", "res://scripts/core/route_spirit_combat.gd", "res://scripts/core/route_spirit_navigation.gd", "res://scripts/core/courtyard_route_run.gd", "res://scripts/core/route_spell_combat.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	var output: String = "res://build/qa/formal-schools-current/spirit"
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--qa-out=res://build/qa/") and not str(arg).contains(".."):
			output = str(arg).trim_prefix("--qa-out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	FileAccess.open(output + "/results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures.size(),
		"details": failures, "groups": groups, "observations": observations, "source_sha256": hashes,
		"scope": "Production-core controlled fixtures; no renderer, screenshot, interactive play, full route, natural reward distribution, performance or final balance claim."}, "\t"))
	print("FORMAL SPIRIT RULES checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func entry_prerequisites_and_growth():
	var battle = fresh()
	check(battle.initial_choices().map(func(item): return str(item.id)) == ["S01", "S02", "S03"], "three independent spirit starters")
	var eligible: Array = battle.eligible_reward_ids()
	check("S05" not in eligible and "S07" not in eligible, "command and field need owned source")
	for id in ["S01", "S02", "S03", "S04", "S06", "S08", "S09", "S10"]: check(id in eligible, "source independent eligible " + id)
	var summoned = fresh(["S02"])
	check("S05" in summoned.eligible_reward_ids() and "S07" in summoned.eligible_reward_ids(), "owned summon admits both supporting spells")
	check("F04" not in eligible and "F04" not in battle.initial_choices().map(func(item): return str(item.id)), "legacy F04 never restored")
	for id in ["B04", "P01", "G02", "SB01", "SP01", "SG01"]:
		check(id not in battle._artifact_combat.eligible_ids(battle), "profession source not restored as treasure " + id)
	for id in IDS:
		check(battle._base.spells[id].levels.size() == 3, "three complete levels " + id)
	var empty = fresh(["S05", "S07"])
	for spell in empty.spells: spell.remaining = 0.0
	advance(empty, 2.0)
	check(empty.casts == 0 and empty.hit_log.is_empty(), "support waits without active pet")
	var resonance = fresh(["S01", "S02", "S10"], 3)
	check(near(school(resonance).school_bonus(resonance), 0.5) and near(school(resonance).cooldown_bonus(resonance), 0.1), "mastery35 and resonance15 same bucket")

func ten_spells_three_levels():
	for level in range(1, 4):
		for id in IDS:
			var ids: Array = [id]
			if id in ["S05", "S07"]: ids.append("S02")
			var battle = fresh(ids, level)
			if id == "S10":
				advance(battle, 1.0)
				check(battle.casts == 0 and battle.hit_log.is_empty(), "mastery passive has no cast L" + str(level))
				check(near(school(battle).school_bonus(battle), [0.15, 0.25, 0.35][level - 1]), "mastery exact bucket L" + str(level))
				continue
			if id in ["S05", "S07"]:
				release(battle, "S02")
				for unit in school(battle).units: unit.next_at = 9999.0
			if id == "S09": battle.player.shield = float(battle.player.max_shield) - 10.0
			release(battle, id)
			advance(battle, 1.4 if id in ["S02", "S03", "S04"] else 0.3)
			check(battle.natural_casts.filter(func(item): return str(item.id) == id).size() == 1, "exactly one natural action " + id + " L" + str(level))
			match id:
				"S01": check(near(damage(battle), [110.0, 150.0, 150.0][level - 1]), "single-target bolt base L" + str(level))
				"S02", "S03", "S04": check(damage(battle, "summon") > 0.0 and battle.body_contexts.is_empty(), "pure summon has real separate attacks " + id + " L" + str(level))
				"S05": check(near(damage(battle, "spirit_command"), [60.0, 106.25, 275.0][level - 1]), "finite per-source command budget L" + str(level))
				"S06": check(near(damage(battle), [200.0, 260.0, 260.0][level - 1]), "recall no-pet baseline L" + str(level))
				"S07": check(school(battle).fields.size() == 1 and damage(battle) == 0.0, "field creates no damage or new pet L" + str(level))
				"S08": check(near(damage(battle), [120.0, 165.0, 165.0][level - 1]), "chain baseline L" + str(level))
				"S09": check(near(float(battle.player.shield), float(battle.player.max_shield)) and damage(battle) == 0.0 and school(battle).units.is_empty(), "shield exact missing10 no fake attack unit L" + str(level))

func independent_starters_and_capacities():
	for id in ["S01", "S02", "S03"]:
		var battle = fresh([id])
		battle.actors = [enemy(1, Vector2(0, 2), 180.0)]
		battle.spells[0].remaining = 0.0
		advance(battle, 6.0)
		check(not battle.hit_log.is_empty() and float(battle.hit_log[0].at) <= 2.0, "starter first hit within2s " + id)
		check(float(battle.actors[0].health) <= 0.0, "starter independently defeats180hp within6s " + id)
		observations.append({"case": "single_starter180hp", "id": id, "first_hit": battle.hit_log[0].at if not battle.hit_log.is_empty() else -1.0, "hits": battle.hit_log.size()})
	var capacity = fresh(["S02", "S03", "S04"], 3)
	for id in ["S02", "S03", "S04"]: release(capacity, id)
	check(school(capacity).units.size() == 4, "ranged2 melee1 hawk1 total4")
	var original_expiry: float = float(school(capacity).units[0].expires)
	check(not capacity.cast_extra_spell("S02"), "full capacity rejects P04-style extra")
	check(near(float(school(capacity).units[0].expires), original_expiry), "full capacity never refreshes life")
	capacity._owned_spell("S02").remaining = 0.0
	advance(capacity, 0.5)
	check(near(float(capacity._owned_spell("S02").cast_remaining), 0.0), "full capacity does not start empty windup")
	school(capacity).units.remove_at(0)
	advance(capacity, 0.3)
	check(school(capacity).units.size() == 3, "vacancy still requires complete0.35s windup")
	advance(capacity, 0.1)
	check(school(capacity).units.size() == 4, "one remaining vacancy fills one of two-summon deployment")
	var previous_hits: int = capacity.hit_log.size()
	capacity.extra_cdr = 0.6
	advance(capacity, 0.2)
	check(school(capacity).units.size() <= 4 and capacity.hit_log.size() - previous_hits <= 4, "CDR never bursts pet attack timers or capacity")

func normal_timing_path_and_lifetime():
	var ranged = fresh(["S02"])
	release(ranged, "S02")
	advance(ranged, 12.0)
	check(ranged.summon_contexts.size() == 9 and school(ranged).units.is_empty(), "baseline ranged12s nine finite planned attacks")
	var exact = fresh(["S02"])
	release(exact, "S02")
	school(exact).units[0].expires = 1.25
	advance(exact, 1.25)
	check(exact.summon_contexts.size() == 1 and school(exact).units.is_empty(), "same-time final normal hit precedes unregister")
	var wall = fresh(["S03"])
	wall.actors = [enemy(1, Vector2(0, 4))]
	release(wall, "S03")
	wall.blocks = [{"center": Vector2(0, 2), "size": Vector2(2.0, 0.5)}]
	advance(wall, 0.2)
	check(wall.hit_log.is_empty(), "melee cannot hit from range or through wall")
	advance(wall, 1.3)
	check(damage(wall, "summon") > 0.0 and school(wall).units[0].pos.distance_to(wall.actors[0].pos) <= 1.00001, "melee pursues legal obstacle path then attacks within actual1m")
	var lost = fresh(["S02"])
	release(lost, "S02")
	advance(lost, 1.1)
	lost.actors[0].pos = Vector2(20, 20)
	advance(lost, 2.0)
	lost.actors[0].pos = Vector2(0, 2)
	advance(lost, 0.1)
	check(lost.hit_log.is_empty(), "reacquired target must finish fresh0.15s window")
	advance(lost, 0.1)
	check(lost.summon_contexts.size() == 1, "lost-time attacks never catch up")
	var leash = fresh(["S03"])
	release(leash, "S03")
	school(leash).units[0].pos = Vector2(15, 0)
	advance(leash, 1.0 / 120.0)
	check(school(leash).units[0].pos.distance_to(leash.player.pos) < 1.0 and leash.hit_log.is_empty(), "leash recovery safe point with no relocation damage")

func commands_recall_and_fields():
	var commands = fresh(["S02", "S05"])
	release(commands, "S02")
	var planned: float = float(school(commands).units[0].next_at)
	release(commands, "S05")
	advance(commands, 0.21)
	check(near(float(school(commands).units[0].next_at), planned) and near(damage(commands, "spirit_command"), 60.0), "command independent from normal timer")
	var recall = fresh(["S02", "S05", "S06"])
	release(recall, "S02")
	school(recall).units[0].expires = 5.0
	school(recall).units[0].next_at = 9999.0
	release(recall, "S05")
	release(recall, "S06")
	check(school(recall).units.is_empty(), "recall unregisters source before bonus damage")
	advance(recall, 0.3)
	check(near(damage(recall, "spirit_command"), 0.0) and near(damage(recall, "S06"), 552.0), "consumed pending command cancels and recall gets one resonance-scaled bonus")
	release(recall, "S06")
	check(near(damage(recall, "S06"), 782.0), "second recall cannot consume same unit again")
	var fresh_pet = fresh(["S02", "S06"])
	release(fresh_pet, "S02")
	release(fresh_pet, "S06")
	check(school(fresh_pet).units.size() == 1 and near(damage(fresh_pet, "S06"), 200.0), "fresh pet above6sec not consumed")
	var field = fresh(["S02", "S07"], 3)
	release(field, "S02")
	var due: float = float(school(field).units[0].next_at)
	release(field, "S07")
	check(near(float(school(field).units[0].extension_used), 6.0) and near(float(school(field).units[0].next_at), due), "field3 grants finite6sec budget without changing existing first attack")
	release(field, "S07")
	check(near(float(school(field).units[0].extension_used), 6.0) and school(field).fields.size() == 1, "replacement field no repeated lifetime or second field")
	school(field).units.remove_at(0)
	release(field, "S02")
	var newborn: Dictionary = school(field).units[-1]
	check(near(float(newborn.next_at) - school(field).clock, 0.85), "only newborn in field gets first-delay reduction")
	var blocked = fresh(["S03", "S07"])
	release(blocked, "S03")
	school(blocked).units[0].pos = Vector2(0, 2)
	blocked.blocks = [{"center": Vector2(0, 1), "size": Vector2(2, 0.25)}]
	release(blocked, "S07")
	check(near(float(school(blocked).units[0].extension_used), 0.0), "field does not grant through wall")
	blocked.blocks.clear()
	advance(blocked, 1.0 / 120.0)
	check(near(float(school(blocked).units[0].extension_used), 2.0), "wall rejection did not consume first field coverage eligibility")

func mark_and_slow_scope():
	var bolt = fresh(["S01"], 3)
	bolt.actors = [enemy(1, Vector2(0, 2)), enemy(2, Vector2(0, 3)), enemy(3, Vector2(0, 4)), enemy(4, Vector2(0, 5))]
	release(bolt, "S01")
	advance(bolt, 0.5)
	check(bolt.body_contexts.size() == 3 and int(school(bolt).mark.actor_id) == 1 and damage(bolt, "S01", 4) == 0.0, "bolt3 finite pierce first main is only mark source")
	var dead = fresh(["S01"])
	dead.actors[0].health = 50.0
	release(dead, "S01")
	advance(dead, 0.2)
	check(school(dead).mark.is_empty(), "killed main never leaves corpse mark")
	var normal = fresh(["S02", "S10"], 3)
	release(normal, "S02")
	school(normal)._apply_mark(normal, normal.actors[0], 4.0)
	advance(normal, 1.2)
	check(normal.summon_contexts.size() == 2 and near(damage(normal, "summon"), 494.45), "mastery35 and normal mark20 add inside same bucket")
	for type in ["M01", "EL01", "EL02_GUARD"]:
		var slowed = fresh(["S08"], 3)
		slowed.actors = [enemy(1, Vector2(0, 2), 1000000.0, type), enemy(2, Vector2(0, 3))]
		school(slowed)._apply_mark(slowed, slowed.actors[0], 4.0)
		release(slowed, "S08")
		var expected: float = {"M01": 0.4, "EL01": 0.25, "EL02_GUARD": 0.15}[type]
		check(near(float(slowed.actors[0].spell_slows.S08.amount), expected), "strongest slow target-class cap " + type)
		check(int(school(slowed).mark.actor_id) == 1 and not slowed.actors[1].spell_slows.is_empty(), "chain secondary slow never transfers mark " + type)
	var fallback = fresh(["S02"])
	fallback.actors = [enemy(1, Vector2(0, 2)), enemy(2, Vector2(0, 5))]
	release(fallback, "S02")
	school(fallback)._apply_mark(fallback, fallback.actors[1], 4.0)
	fallback.blocks = [{"center": Vector2(0, 4), "size": Vector2(4, 0.5)}]
	advance(fallback, 1.3)
	check(damage(fallback, "summon", 1) > 0.0 and damage(fallback, "summon", 2) == 0.0, "blocked mark falls back to reachable target")

func generic_items_and_gems():
	var pet = fresh(["S02", "S09"])
	check("GT01" not in pet._artifact_combat.eligible_ids(pet), "summon plus shield lacks player-body source for GT01")
	var body = fresh(["S01", "S09"])
	check("GT01" in body._artifact_combat.eligible_ids(body), "direct body plus shield qualifies GT01")
	grant(body, "GT01")
	body.player.shield = float(body.player.max_shield) - 10.0
	release(body, "S09")
	check(near(float(body._artifact_combat.state_snapshot().generic.charge), 40.0), "actual missing10 shield charges40")
	release(body, "S01")
	advance(body, 0.2)
	check(near(damage(body, "GT01"), 40.0), "one natural body hit releases stored charge")
	var sequence = fresh(["S02", "S05"], 3)
	grant(sequence, "P04")
	release(sequence, "S02")
	for unit in school(sequence).units: unit.next_at = 9999.0
	release(sequence, "S05")
	release(sequence, "S05")
	advance(sequence, 0.3)
	check(sequence.casts == 3 and sequence.natural_casts.size() == 3, "natural command actions advance P04 once each")
	check(near(damage(sequence, "spirit_command"), 825.0), "third action adds exactly one command; no per-source recursion")
	for core in ["fracture", "coffin", "echo"]:
		var separated = fresh(["S02"], 1, core)
		separated.player.crit_rate = 2.0
		if core == "coffin": separated._spell_combat.ice.status.force_ready(separated, separated.actors[0], 2.0, {"school": "ice", "spell_id": "I08", "natural": true, "cast_id": 9900})
		release(separated, "S02")
		advance(separated, 1.5)
		check(separated.body_contexts.is_empty() and near(damage(separated, "summon"), 150.0), "pet crit uses actual attack and skips body pipeline " + core)
		check(damage(separated, "gem_fracture") == 0.0 and damage(separated, "gem_echo") == 0.0 and separated._gem_combat.reserves.is_empty(), "pet never creates gem body derivatives " + core)
	var no_crit = fresh(["S02", "S05"])
	no_crit.player.crit_rate = 2.0
	release(no_crit, "S02")
	for unit in school(no_crit).units: unit.next_at = 9999.0
	release(no_crit, "S05")
	advance(no_crit, 0.3)
	check(near(damage(no_crit, "spirit_command"), 60.0), "command remains noncritical at200percent crit rate")

func pause_cleanup_and_snapshots():
	var paused = fresh(["S02", "S05"])
	release(paused, "S02")
	release(paused, "S05")
	var deadline: float = float(school(paused).units[0].expires)
	paused.set_paused(true)
	advance(paused, 2.0)
	check(near(school(paused).clock, 0.0) and near(float(school(paused).units[0].expires), deadline) and damage(paused) == 0.0, "pause freezes lifetime command and damage")
	paused.set_paused(false)
	advance(paused, 0.3)
	check(near(damage(paused, "spirit_command"), 60.0), "resume resolves command exactly once")
	var snapshot = fresh(["S02"])
	release(snapshot, "S02", false, 0.25)
	snapshot._owned_spell("S02").level = 3
	snapshot._refresh_spell(snapshot._owned_spell("S02"))
	stop_natural(snapshot)
	snapshot.player.attack = 200.0
	advance(snapshot, 1.3)
	check(near(damage(snapshot, "summon"), 50.0) and near(float(school(snapshot).units[0].level.duration), 12.0), "old pet holds level1 and quarter birth multiplier but reads current200 attack")
	var detached = school(snapshot).get_snapshot(snapshot)
	detached.spirit_units[0].expires = 9999.0
	check(not near(float(school(snapshot).units[0].expires), 9999.0), "presentation snapshot cannot change rules")
	snapshot.spells.clear()
	advance(snapshot, 1.3)
	check(snapshot.summon_contexts.size() == 2 and near(snapshot.summon_contexts[-1].coefficient, 1.0), "replaced source leaves finite old summon snapshot intact")
	school(snapshot)._apply_mark(snapshot, snapshot.actors[0], 4.0)
	snapshot._stop_combat()
	check(school(snapshot).units.is_empty() and school(snapshot).mark.is_empty() and school(snapshot).pending.is_empty() and school(snapshot).fields.is_empty() and school(snapshot).projectiles.is_empty(), "stop room clears every spirit temporary state")
