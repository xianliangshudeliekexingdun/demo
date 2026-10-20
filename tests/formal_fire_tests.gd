extends SceneTree
## Authoritative implementation fixtures. These call actual Route damage/hooks.
## AI/spawn/clear are isolated, never replaced by a copied combat formula.

const Route = preload("res://scripts/core/courtyard_route_run.gd")
const First = preload("res://scripts/core/first_room_run.gd")
const OUT = "res://build/qa/spell-growth-implementation-20261020/formal-fire"
const FIRE_IDS = ["F01", "F02", "F03", "F05", "F06", "F07", "F08", "F09", "F10", "F11"]
var checks: int = 0
var failures: Array = []
var groups: Array = []
var before_sources: Dictionary = {}

class Fixture extends "res://scripts/core/courtyard_route_run.gd":
	var damage_log: Array = []
	var context_log: Array = []
	var cast_log: Array = []
	var extra_log: Array = []
	var emitted: Array = []
	var extra_cdr: float = 0.0
	func _reserve_batch(): pass
	func _update_spawn(_dt: float): pass
	func _update_enemies(_dt: float):
		for enemy in actors:
			enemy.previous = enemy.pos
	func _check_clear(): pass
	func artifact_cooldown_reduction() -> float:
		return super.artifact_cooldown_reduction() + extra_cdr
	func damage_enemy(enemy: Dictionary, amount: float, spell_id: String = ""):
		var before: float = float(enemy.get("health", 0.0))
		super.damage_enemy(enemy, amount, spell_id)
		damage_log.append({"at": time, "actor_id": enemy.get("id", -1), "source": spell_id,
			"amount": maxf(0.0, before - float(enemy.get("health", 0.0)))})
	func resolve_spell_hit(enemy: Dictionary, coefficient: float, context: Dictionary) -> Dictionary:
		var result: Dictionary = super.resolve_spell_hit(enemy, coefficient, context)
		context_log.append({"at": time, "actor_id": enemy.get("id", -1), "coefficient": coefficient,
			"context": context.duplicate(true), "result": result.duplicate(true)})
		return result
	func on_spell_cast(spell: Dictionary, target: Dictionary, context: Dictionary):
		cast_log.append({"at": time, "id": spell.id, "context": context.duplicate(true)})
		super.on_spell_cast(spell, target, context)
	func cast_extra_spell(id: String, target: Dictionary = {}, scale: float = 1.0) -> bool:
		extra_log.append({"id": id, "target": target.duplicate(true), "scale": scale})
		return super.cast_extra_spell(id, target, scale)
	func _emit(kind: String, values: Dictionary, lifetime: float):
		emitted.append({"kind": kind, "at": time, "values": values.duplicate(true)})
		super._emit(kind, values, lifetime)


func _initialize(): call_deferred("execute")

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures.append(label)
		push_error("Formal fire: " + label)

func near(a: float, b: float, tolerance: float = 0.0001) -> bool:
	return absf(a - b) < tolerance

func actor(id: int = 1, pos: Vector2 = Vector2(0, 2), health: float = 1000000.0) -> Dictionary:
	return {"id": id, "type": "M01", "type_id": "M01", "pos": pos, "previous": pos,
		"health": health, "max_health": health, "radius": 0.3, "phase": "chase", "push_resistance": 0.0}

func fresh(ids: Array = ["F01"], level: int = 1):
	var battle = Fixture.new()
	check(battle.configure({}, 20261018).ok, "fixture calls real Route.configure")
	check(battle.choose_initial("F01"), "fixture enters combat via real start")
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
	battle.actors = [actor()]
	stop_natural(battle)
	return battle

func stop_natural(battle):
	for spell in battle.spells:
		spell.remaining = 9999.0
		spell.cast_remaining = 0.0

func grant(battle, id: String):
	check(not battle._artifact_combat.has_artifact(id), "fixture unique grant " + id)
	battle._artifact_combat._owned.append(id)
	battle._artifact_combat.apply_acquisition(battle, id)

func ticks(battle, count: int):
	for _index in count:
		battle.step(1.0 / 120.0)

func advance(battle, seconds: float): ticks(battle, roundi(seconds * 120.0))

func burn(battle, id: int = 1) -> Dictionary:
	for value in battle.get_snapshot().get("spell_burns", []):
		if int(value.actor_id) == id:
			return value
	return {}

func burned_ids(battle) -> Array:
	var result: Array = []
	for value in battle.get_snapshot().get("spell_burns", []): result.append(int(value.actor_id))
	result.sort()
	return result

func reapply_pending(battle) -> Array:
	return battle.get_snapshot().get("fire_reignite_pending", [])

func ignite(battle, enemy: Dictionary = {}) -> bool:
	if enemy.is_empty(): enemy = battle.actors[0]
	return battle._spell_combat.apply_burn(battle, enemy, "rule_fixture")

func detonate(battle, multiplier: float = 1.0, natural: bool = false, id: int = 1) -> float:
	for enemy in battle.actors:
		if int(enemy.id) == id:
			return battle._spell_combat.detonate_burn(battle, enemy, multiplier, natural, 90210)
	return 0.0

func release_once(battle, id: String, natural: bool = true, scale: float = 1.0):
	var spell: Dictionary = battle._owned_spell(id)
	var stats: Dictionary = battle.get_spell_stats(spell)
	var target: Dictionary = battle._spell_combat.legal_target(battle, spell, stats)
	check(not target.is_empty(), "controlled release has legal target " + id)
	if target.is_empty(): return
	spell.locked_pos = target.pos
	battle._spell_combat._cast(battle, spell, stats, target, natural, scale)
	stop_natural(battle)

func context(id: String = "F01", cast_id: int = 1, natural: bool = true, kind: String = "bolt") -> Dictionary:
	return {"spell_id": id, "cast_id": cast_id, "natural": natural, "kind": kind,
		"damage_scale": 1.0, "field_bonus": 0.0}

func source_damage(battle, id: String) -> float:
	var total: float = 0.0
	for hit in battle.damage_log:
		if hit.source == id: total += float(hit.amount)
	return total

func source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in ["res://tests/formal_fire_tests.gd", "res://scripts/core/first_room_run.gd", "res://scripts/core/courtyard_route_run.gd", "res://scripts/core/route_spell_combat.gd", "res://scripts/core/route_artifacts.gd", "res://scripts/core/route_generic_items.gd", "res://data/balance_candidates/first_run_v1.json", "res://data/balance_candidates/fire_artifacts_v1.json", "res://data/generic_artifacts_v1.json", "res://data/route_spell_runtime.json", "res://data/route_artifact_runtime.json"]:
		result[path] = FileAccess.get_sha256(path)
	var status_path: String = "res://scripts/core/route_fire_status.gd"
	if FileAccess.file_exists(status_path): result[status_path] = FileAccess.get_sha256(status_path)
	return result

func group(label: String, callable: Callable):
	var count_before: int = checks
	var failed_before: int = failures.size()
	callable.call()
	groups.append({"id": label, "checks": checks - count_before, "failures": failures.size() - failed_before})

func execute():
	before_sources = source_hashes()
	var probe = fresh()
	var api_ready: bool = probe._spell_combat.has_method("apply_burn") and probe._spell_combat.has_method("detonate_burn") and probe._spell_combat.has_method("before_damage_tick")
	check(api_ready, "formal fire public implementation APIs present")
	if api_ready:
		group("source_validation", source_validation)
		group("ignition_components", ignition_components)
		group("readiness_and_shield", readiness_and_shield)
		group("current_growth_transactions", current_growth_transactions)
	check(source_hashes() == before_sources, "rule sources unchanged throughout implementation checks")
	var output: String=OUT
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with("--qa-out=res://build/qa/") and not str(argument).contains(".."):
			output=str(argument).trim_prefix("--qa-out=")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output + "/rules.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures.size(), "details": failures, "groups": groups, "source_hashes": before_sources, "source_stable": source_hashes() == before_sources, "scope": "Actual Route/Spell/Artifact APIs under explicit deterministic fixtures, AI/spawn/clear isolated; no copied damage formula, no save or natural-inventory assertion."}, "\t"))
	print("FORMAL FIRE RULES checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func current_growth_transactions():
	var suite = preload("res://tests/spell_growth_tests.gd").new()
	suite.fire_transactions()
	checks += suite.checks
	for issue in suite.details: failures.append(issue)

# Pre-migration profession fixtures below are historical references; obsolete
# ownership and level-number assertions are replaced by the current growth suite.
func source_validation():
	var b = fresh()
	var engine = b._spell_combat
	var original: Dictionary = engine.runtime.fire.duplicate(true)
	check(engine.validate_fire_source(b, original).is_empty(), "actual frozen fire source validates")
	check(b.get_snapshot().initial_choices == b.initial_choices(), "Route snapshot starters come from actual configured source")
	for missing in ["spell_ids", "initial_ids", "burning"]:
		var copy: Dictionary = original.duplicate(true)
		copy.erase(missing)
		check(not engine.validate_fire_source(b, copy).is_empty(), "fire schema rejects absent " + missing)
	for key in ["duration", "interval", "coefficient", "maximum_ticks"]:
		for bad in [0.0, -1.0, INF, NAN, "invalid"]:
			var copy: Dictionary = original.duplicate(true)
			copy.burning[key] = bad
			check(not engine.validate_fire_source(b, copy).is_empty(), "fire schema rejects invalid numeric " + key + ":" + str(bad))
	for ids in [["F01"], ["F01", "F01", "F03", "F05", "F06", "F07", "F08", "F09", "F10", "F11"], ["F01", "F02", "F03", "F04", "F06", "F07", "F08", "F09", "F10", "F11"], ["BAD", "F02", "F03", "F05", "F06", "F07", "F08", "F09", "F10", "F11"]]:
		var copy: Dictionary = original.duplicate(true)
		copy.spell_ids = ids
		check(not engine.validate_fire_source(b, copy).is_empty(), "fire schema rejects nonformal/duplicate IDs")
	for ids in [["F01"], ["F01", "F01", "F08"], ["F01", "F02", "F08"], ["F01", "F04", "F08"]]:
		var copy: Dictionary = original.duplicate(true)
		copy.initial_ids = ids
		check(not engine.validate_fire_source(b, copy).is_empty(), "fire schema rejects illegal starter IDs")
	for count in [7, 8.5, 9]:
		var copy: Dictionary = original.duplicate(true)
		copy.burning.maximum_ticks = count
		check(not engine.validate_fire_source(b, copy).is_empty(), "fire schema rejects inconsistent/fractional tick plan")
	check(original == engine.runtime.fire, "validation mutation probes only copied source")

func catalog_qualification():
	var b = fresh()
	check(b.initial_choices().map(func(value): return value.id) == ["F01", "F03", "F08"], "formal Route three starters")
	var first = First.new()
	check(first.configure().ok and first.initial_choices().map(func(value): return value.id) == ["F01", "F04", "F08"], "independent FirstRoom preserves historical starters")
	check("F11" not in first.eligible_reward_ids(), "independent FirstRoom does not sample unsupported new brand")
	var eligible: Array = b.eligible_reward_ids()
	check(eligible.size() == 20 and "F04" not in eligible and "F11" in eligible, "normal Route twenty mixed IDs exclude archived spirit and retain all ten fire")
	for id in FIRE_IDS: check(id in eligible, "formal active ID " + id)
	check(b._base.spells.F04.school == "spirit" and not b._base.spells.F04.active, "F04 retained as archived spirit definition")
	var items: Dictionary = b._artifact_combat._items
	check(items.size() == 59, "59 stored artifact IDs including spirit archive")
	check(items.keys().filter(func(id): return items[id].scope == "generic").size() == 24, "24 generic items retained")
	check(items.keys().filter(func(id): return items[id].scope == "fire").size() == 16, "16 formal fire profession entries")
	check(items.keys().filter(func(id): return items[id].scope == "spirit").size() == 3, "three spirit artifacts retained")
	for id in ["B04", "P01", "G02"]:
		check(not bool(items[id].active) and id not in b._artifact_combat.eligible_ids(b), "archived profession not normal pool " + id)
	check("P06" in b._artifact_combat.eligible_ids(b) and "G04" not in b._artifact_combat.eligible_ids(b), "one igniter grants P06 but no bomb gold")
	var bomb_only = fresh(["F07"])
	check("G04" not in bomb_only._artifact_combat.eligible_ids(bomb_only) and "P06" not in bomb_only._artifact_combat.eligible_ids(bomb_only), "bomb alone cannot supply ignition requirements")
	bomb_only.spells.append(bomb_only._new_spell("F11"))
	check("G04" in bomb_only._artifact_combat.eligible_ids(bomb_only) and "B11" in bomb_only._artifact_combat.eligible_ids(bomb_only), "brand plus bomb qualifies new profession")
	var all = fresh(FIRE_IDS, 3)
	all.player.crit_rate = 0.1
	check(all._artifact_combat.eligible_ids(all).size() == 40, "all active 24generic+16fire legal with explicit full fixture")
	all.room_index = 45
	var offered: Array = all._artifact_combat.sample_choices(all, all._rng)
	var rng_state: int = all._rng.state
	check(offered.size() == 3 and offered[0].rarity == "gold", "45 chest actual gold guarantee")
	check(all._artifact_combat.sample_choices(all, all._rng) == offered and rng_state == all._rng.state, "new active pool still cached without RNG mutation")
	for candidate in offered:
		check(offered.filter(func(value): return value.id == candidate.id).size() == 1, "formal chest unique " + str(candidate.id))
		check(candidate.id not in ["B04", "P01", "G02"], "no inactive spirit chest")

func shared_burn_clock():
	for with_ember in [false, true]:
		var b = fresh()
		if with_ember: grant(b, "P06")
		check(ignite(b), "first burn applied")
		var first: Dictionary = burn(b)
		var duration: float = 6.0 if with_ember else 4.0
		var count: int = 12 if with_ember else 8
		check(near(first.get("next_tick", -99), 0.5) and near(first.get("expires", -99), duration) and int(first.get("maximum_ticks", -1)) == count, "burn explicit first/expiry/max plan")
		check(near(b.damage_dealt, 0.0), "ignition no immediate damage")
		b.player.crit_rate = 1.8
		b.player.crit_multiplier = 9.0
		ticks(b, 59)
		check(near(b.damage_dealt, 0.0), "no burn before .5")
		ticks(b, 1)
		check(near(b.damage_dealt, 25.0), "burn .25A does not crit above100pct")
		advance(b, duration - 0.5)
		check(near(b.damage_dealt, count * 25.0), "exact finite burn tick budget " + str(count))
		check(burn(b).is_empty(), "burn final tick then cleanup")
		advance(b, 2.0)
		check(near(b.damage_dealt, count * 25.0), "no overdue or dead burn tail")
	var refresh = fresh()
	ignite(refresh)
	ticks(refresh, 59)
	var old_next: float = float(burn(refresh).get("next_tick", -99))
	ignite(refresh)
	check(near(float(burn(refresh).get("next_tick", -99)), old_next), "refresh retains existing next tick")
	check(near(float(burn(refresh).get("expires", -99)), refresh.time + 4.0), "refresh only extends expiry")
	ticks(refresh, 1)
	check(near(refresh.damage_dealt, 25.0) and burned_ids(refresh) == [1], "frequent refresh neither defers nor stacks")
	for _index in 20:
		ignite(refresh)
		ticks(refresh, 3)
	check(burned_ids(refresh).size() == 1, "many sources remain one shared state")
	var mirror: Array = refresh.get_snapshot().spell_burns
	mirror[0].expires = -1.0
	check(float(burn(refresh).expires) > refresh.time, "burn snapshots deep copied")
	var none = fresh(["F07", "F11"])
	check(near(detonate(none), 0.0), "N0 no derived damage")
	ignite(none)
	advance(none, 0.2)
	check(near(detonate(none), 200.0), ".2 elapsed still eight future planned ticks")
	check(not none._spell_combat.has_burn(none, none.actors[0]), "detonation consumes existing state")
	advance(none, 5.0)
	check(near(none.damage_dealt, 200.0), "consumed queued ticks cannot pay again")
	var last = fresh(["F07", "F11"])
	grant(last, "G04")
	ignite(last)
	ticks(last, 426) # 3.55; bomb arrives at exactly4.0.
	release_once(last, "F07")
	ticks(last, 54)
	check(near(last.damage_dealt, 700.0), "existing final burn tick precedes same-time natural G04 bomb")
	check(reapply_pending(last).is_empty(), "zero inventory at exact expiry cannot arrange refuel")
	var later_ember = fresh()
	ignite(later_ember)
	grant(later_ember, "P06")
	check(near(float(burn(later_ember).expires), 4.0) and int(burn(later_ember).maximum_ticks) == 8, "P06 does not retroactively extend existing burn")
	advance(later_ember, 0.2)
	ignite(later_ember)
	check(near(float(burn(later_ember).expires), 6.2) and near(float(burn(later_ember).next_tick), 0.5) and int(burn(later_ember).maximum_ticks) == 12, "new P06 refresh uses6s but keeps old next tick")

func dynamic_damage_scope():
	var b = fresh()
	ignite(b)
	advance(b, 0.5)
	b.player.attack = 200.0
	advance(b, 0.5)
	check(near(b.damage_dealt, 25.0 + 50.0), "burn reads current attack per tick")
	b.player.fire_bonus = 0.2
	advance(b, 0.5)
	check(near(b.damage_dealt, 25.0 + 50.0 + 60.0), "burn reads current fire bucket once")
	var field = fresh(["F06"])
	release_once(field, "F06")
	advance(field, 0.5)
	check(near(source_damage(field, "F06"), 40.0), "field own direct excludes own20pct")
	var before: float = field.damage_dealt
	advance(field, 0.5)
	check(near(field.damage_dealt - before, 70.0), "next field40 plus dynamic burn30 exactly once")
	var scoped = fresh(["F01", "F04", "F08"])
	var result: Dictionary = scoped.resolve_spell_hit(scoped.actors[0], 1.0, context())
	check(near(result.damage, 100.0), "archived F04 does not count toward three-fire")
	scoped.spells.append(scoped._new_spell("F02"))
	scoped.spells.back().level = 3
	result = scoped.resolve_spell_hit(scoped.actors[0], 1.0, context())
	check(near(result.damage, 150.0), "mastery35 plus actual three-fire15 additive")
	result = scoped.resolve_spell_hit(scoped.actors[0], 1.0, context("F04", 2, false, "spirit"))
	check(near(result.damage, 100.0), "F04 excludes fire mastery and resonance damage")
	grant(scoped, "GU05")
	ticks(scoped, 1)
	check(near(scoped._owned_spell("F01").cooldown, 1.2 * 0.84), "fire gets generic6 plus fire resonance10CDR")
	check(near(scoped._owned_spell("F04").cooldown, 12.0 * 0.94), "spirit gets generic6 but not fire10CDR")
	var plain = fresh(["F04"])
	var career = fresh(["F04", "F01", "F02", "F08"], 3)
	grant(career, "B02")
	grant(career, "G01")
	plain.player.crit_rate = 0.85
	career.player.crit_rate = 0.85
	plain._rng.seed = 789
	career._rng.seed = 789
	for index in 128:
		var left: Dictionary = plain.resolve_spell_hit(plain.actors[0], 1.0, context("F04", index, false, "spirit"))
		var right: Dictionary = career.resolve_spell_hit(career.actors[0], 1.0, context("F04", index, false, "spirit"))
		check(left == right, "archived spirit ignores fire crit/damage benefits exact RNG sample " + str(index))
	var capped = fresh(["F01", "F02", "F08"])
	capped.extra_cdr = 0.9
	ticks(capped, 1)
	check(near(capped.spells[0].cooldown, 1.2 * 0.4), "total CDR caps60")
	for rate in [1.0, 1.8]:
		var crit = fresh()
		crit.player.crit_rate = rate
		result = crit.resolve_spell_hit(crit.actors[0], 1.0, context())
		check(result.critical and near(result.damage, 150.0), "crit100plus no supercritical " + str(rate))
	var duplicate = fresh(["F01", "F01", "F04"])
	result = duplicate.resolve_spell_hit(duplicate.actors[0], 1.0, context())
	check(near(result.damage, 100.0) and duplicate._spell_combat.fire_spell_count(duplicate) == 1, "resonance counts distinct active fire IDs")
	var overlap = fresh(["F01", "F03", "F06"])
	grant(overlap, "P03")
	var marker: Dictionary = overlap._spell_combat._zone("rain", "F03", Vector2(0, 2), 2.2, 4.0, 0.0, 0.0, context("F03"))
	var field_marker: Dictionary = overlap._spell_combat._zone("field", "F06", Vector2.ZERO, 2.2, 4.0, 0.0, 0.0, context("F06"))
	field_marker.merge({"attack_bonus": 0.2, "grace": 0.0}, true)
	overlap._spell_combat.zones = [marker, field_marker]
	ignite(overlap)
	advance(overlap, 0.5)
	check(near(overlap.damage_dealt, 25.0 * 1.15 * 1.2 * 1.2), "shared burn applies synergy/field/P03 exactly once")
	var duplicate_marker: Dictionary = overlap._spell_combat._zone("rain_ground", "F03", Vector2(0, 2), 2.2, 3.0, 0.0, 0.0, context("F03"))
	overlap._spell_combat.zones.append(duplicate_marker)
	var before_overlap: float = overlap.damage_dealt
	advance(overlap, 0.5)
	check(near(overlap.damage_dealt - before_overlap, 25.0 * 1.15 * 1.2 * 1.2), "same F03 rain and ground cannot multiply vulnerability again")
	var grace = fresh(["F06", "F01"], 3)
	release_once(grace, "F06")
	ticks(grace, 1) # establish1.5s grace while inside, then leave without input
	ignite(grace)
	grace.player.pos = Vector2(4, 0)
	grace.player.previous = grace.player.pos
	grace.set_paused(true)
	advance(grace, 1.0)
	check(near(grace._spell_combat.field_grace, 1.5) and near(source_damage(grace, "burning"), 0.0), "pause freezes field grace and burn clock together")
	grace.set_paused(false)
	ticks(grace, 179)
	var grace_context: Dictionary = context()
	grace_context.field_bonus = grace._spell_combat.field_attack_bonus()
	var before_expiry: Dictionary = grace.resolve_spell_hit(grace.actors[0], 1.0, grace_context)
	check(near(before_expiry.damage, 120.0), "direct still gets field before full1.5s departure")
	ticks(grace, 1)
	var grace_burns: Array = grace.damage_log.filter(func(hit): return hit.source == "burning")
	check(grace_burns.size() == 3 and near(float(grace_burns.back().amount), 25.0), "burn at exact1.5s departure loses field in same tick as direct")
	grace_context.field_bonus = grace._spell_combat.field_attack_bonus()
	var after_expiry: Dictionary = grace.resolve_spell_hit(grace.actors[0], 1.0, grace_context)
	check(near(after_expiry.damage, 100.0), "direct and burn agree after grace expiry")

func ignition_components():
	for id in ["F01", "F03", "F05", "F06", "F08", "F09", "F11"]:
		var b = fresh([id])
		release_once(b, id, false, 0.7)
		advance(b, 0.7)
		check(not burn(b).is_empty(), "actual extra component ignites " + id)
		check(b.casts == 0 and b._artifact_combat._natural_casts == 0, "extra mechanism no natural counter " + id)
	for id in ["F07", "F04", "F02", "F10"]:
		var b = fresh([id])
		if id == "F10": b.player.shield = 0.0
		if id != "F02": release_once(b, id, false)
		advance(b, 1.5)
		check(burned_ids(b).is_empty(), "non-igniter never burns " + id)
	var beam = fresh(["F08"], 3)
	release_once(beam, "F08")
	var expiry: float = float(burn(beam).get("expires", -99))
	advance(beam, 0.21)
	check(near(float(burn(beam).get("expires", -99)), expiry), "beam pulse does not refresh ignition")
	var bolt = fresh(["F01"], 3)
	release_once(bolt, "F01")
	advance(bolt, 0.16)
	var first_expiry: float = float(burn(bolt).get("expires", -99))
	advance(bolt, 0.2)
	check(float(burn(bolt).get("expires", -99)) > first_expiry, "secondary bolt has real ignition qualification")
	for id in ["F05", "F06"]:
		var area = fresh([id], 3)
		release_once(area, id)
		advance(area, 0.5)
		var after_first: Dictionary = burn(area)
		advance(area, 0.5)
		check(near(float(burn(area).get("expires", -99)), float(after_first.get("expires", -98))), "area only first effective hit per cast/actor ignites " + id)
	var rain = fresh(["F03"], 3)
	release_once(rain, "F03")
	advance(rain, 3.2)
	var after_drops: float = float(burn(rain).get("expires", -99))
	advance(rain, 1.0)
	check(near(float(burn(rain).get("expires", -99)), after_drops), "rain ground never refreshes shared burning")
	var ground = fresh(["F03"], 3)
	release_once(ground, "F03")
	advance(ground, 3.1)
	check(ground.context_log.filter(func(hit): return hit.context.kind == "area").is_empty(), "newly born ground cannot tick on its birth frame")
	advance(ground, 0.49)
	check(ground.context_log.filter(func(hit): return hit.context.kind == "area").is_empty(), "ground waits full .5 from birth")
	ticks(ground, 1)
	var ground_hits: Array = ground.context_log.filter(func(hit): return hit.context.kind == "area")
	check(ground_hits.size() == 1 and near(float(ground_hits[0].at), 3.6), "ground first tick actual .5 after last drop")

func brand_propagation():
	var positions: Array = [Vector2(0, 2), Vector2(3, 2), Vector2(-3, 2), Vector2(0, 5), Vector2(2.5, 4.4), Vector2(-2.5, 4.4), Vector2(0, 6), Vector2(5.5, 2)]
	for level in range(1, 4):
		var b = fresh(["F11"], level)
		b.actors.clear()
		for index in positions.size(): b.actors.append(actor(index + 1, positions[index]))
		release_once(b, "F11")
		check(burned_ids(b).size() == level + 2, "brand main plus bounded propagation L" + str(level))
		check(burned_ids(b) == ([1, 2, 3] if level == 1 else ([1, 2, 3, 4] if level == 2 else [1, 2, 3, 4, 5])), "distance ties use stable actor ID L" + str(level))
		check(near(b.damage_dealt, 80.0 if level == 1 else 100.0), "propagation carries no immediate damage")
	var enlarged = fresh(["F11"], 3)
	grant(enlarged, "B11")
	enlarged.actors.clear()
	for index in positions.size(): enlarged.actors.append(actor(index + 1, positions[index]))
	release_once(enlarged, "F11")
	check(burned_ids(enlarged) == [1, 2, 3, 4, 5, 6, 7], "B11 plus2 bounded by6 neighbors and excludes out of radius")
	var filtered = fresh(["F11"])
	filtered.actors = [actor(1, positions[0]), actor(2, positions[1]), actor(3, positions[2]), actor(4, positions[3])]
	ignite(filtered, filtered.actors[1])
	advance(filtered, 0.2)
	var unrefreshed: Dictionary = burn(filtered, 2)
	release_once(filtered, "F11")
	check(burned_ids(filtered) == [1, 2, 3, 4], "existing burn does not take propagation quota")
	check(burn(filtered, 2) == unrefreshed, "already-burning neighbor is not refreshed")
	var walls = fresh(["F11"])
	walls.actors = [actor(1, positions[0]), actor(2, positions[1]), actor(3, positions[2]), actor(4, positions[3])]
	walls.blocks = [{"center": Vector2(1.5, 2), "size": Vector2(0.3, 1.0)}]
	release_once(walls, "F11")
	check(burned_ids(walls) == [1, 3, 4], "propagation checks actual line-of-sight from hit position")
	var chain = fresh(["F11"])
	chain.actors = [actor(1, Vector2(0, 2)), actor(2, Vector2(2.8, 2)), actor(3, Vector2(5.6, 2))]
	release_once(chain, "F11")
	check(burned_ids(chain) == [1, 2], "propagated neighbor never chains a second generation")
	advance(chain, 4.1)
	check(burn(chain, 3).is_empty() and chain.casts == 1, "burn expiry/death never recursively spreads")
	for by_charge in [false, true]:
		var killed = fresh(["F11"])
		killed.actors = [actor(1, Vector2(0, 2), 150.0 if by_charge else 70.0), actor(2, Vector2(2.8, 2)), actor(3, Vector2(-2.8, 2))]
		if by_charge:
			grant(killed, "GT01")
			grant(killed, "GU11")
			killed.player.shield = 0.0
			killed.restore_player_shield(50.0, "rule_fixture")
		release_once(killed, "F11")
		check(float(killed.actors[0].health) <= 0.0 and burned_ids(killed) == [2, 3], "valid brand primary kill still propagates " + str(by_charge))

func bomb_and_reignite():
	for level in range(1, 4):
		for extended in [false, true]:
			var b = fresh(["F07", "F11"], level)
			if extended: grant(b, "P06")
			ignite(b)
			var expected: float = (300.0 if extended else 200.0) * [1.0, 1.25, 1.5][level - 1]
			check(near(detonate(b, [1.0, 1.25, 1.5][level - 1]), expected), "full future detonation budget L" + str(level) + " ember=" + str(extended))
	var no_burn = fresh(["F07", "F11"])
	grant(no_burn, "G04")
	check(near(detonate(no_burn, 1.0, true), 0.0) and reapply_pending(no_burn).is_empty(), "G04 cannot create first burn from N0")
	var natural = fresh(["F07", "F11"])
	grant(natural, "G04")
	ignite(natural)
	check(near(detonate(natural, 1.0, true), 600.0), "G04 natural adds2 to ordinary multiplier")
	check(reapply_pending(natural).size() == 1 and burn(natural).is_empty(), "successful consumption arranges one delayed refuel")
	ticks(natural, 59)
	check(burn(natural).is_empty() and near(natural.damage_dealt, 600.0), "no early reapply or instant delayed damage")
	ticks(natural, 1)
	check(not burn(natural).is_empty() and near(natural.damage_dealt, 600.0), "reapply at full.5 does not immediately hurt")
	check(near(float(burn(natural).get("next_tick", -99)), 1.0), "reapply waits another full interval")
	var throttle = fresh(["F07", "F11"])
	grant(throttle, "G04")
	ignite(throttle)
	detonate(throttle, 1.0, true)
	advance(throttle, 0.2)
	ignite(throttle)
	detonate(throttle, 1.0, true)
	check(reapply_pending(throttle).size() == 1, "G04 per-target2s limits scheduling, not duplicate refuels")
	advance(throttle, 1.8)
	ignite(throttle)
	detonate(throttle, 1.0, true)
	check(reapply_pending(throttle).size() == 1, "G04 can arrange next after full2s")
	var preserve_next = fresh(["F07", "F11"])
	grant(preserve_next, "G04")
	grant(preserve_next, "P06")
	ignite(preserve_next)
	detonate(preserve_next, 1.0, true)
	advance(preserve_next, 0.2)
	ignite(preserve_next)
	advance(preserve_next, 0.3)
	check(near(float(burn(preserve_next).next_tick), 0.7) and near(float(burn(preserve_next).expires), 6.5), "P06 delayed refuel refreshes existing burn to6s without restarting next tick")
	var extra = fresh(["F07", "F11"])
	grant(extra, "G04")
	ignite(extra)
	check(near(detonate(extra, 1.0, false), 200.0) and reapply_pending(extra).is_empty(), "extra F07 neither gold multiplier nor refuel")
	var actual = fresh(["F07", "F11"])
	grant(actual, "G04")
	ignite(actual)
	release_once(actual, "F07")
	advance(actual, 0.45)
	check(near(actual.damage_dealt, 1100.0), "actual F07 main500 then full G04 detonation600")
	check(reapply_pending(actual).size() == 1, "actual natural bomb schedules once")
	var scaled = fresh(["F07", "F11"])
	grant(scaled, "G04")
	ignite(scaled)
	release_once(scaled, "F07", false, 0.7)
	advance(scaled, 0.45)
	check(near(scaled.damage_dealt, 350.0 + 200.0), "extra .7 scales main only, ordinary detonation is not .7")
	var already_killed = fresh(["F07", "F11"])
	grant(already_killed, "G04")
	already_killed.actors[0].health = 400.0
	ignite(already_killed)
	release_once(already_killed, "F07")
	advance(already_killed, 0.45)
	check(near(already_killed.damage_dealt, 400.0) and reapply_pending(already_killed).is_empty(), "parent main kills without corpse detonation")
	var charge_kill = fresh(["F07", "F11"])
	for id in ["G04", "GT01", "GU11"]: grant(charge_kill, id)
	charge_kill.actors[0].health = 600.0
	charge_kill.player.shield = 0.0
	charge_kill.restore_player_shield(50.0, "rule_fixture")
	ignite(charge_kill)
	release_once(charge_kill, "F07")
	advance(charge_kill, 0.45)
	check(near(charge_kill.damage_dealt, 600.0) and reapply_pending(charge_kill).is_empty(), "GT01 first-hit kill precedes detonation and G04")
	var canceled = fresh(["F07", "F11"])
	grant(canceled, "G04")
	ignite(canceled)
	detonate(canceled, 1.0, true)
	canceled.damage_enemy(canceled.actors[0], 99999999.0, "rule_fixture")
	advance(canceled, 1.0)
	check(burn(canceled).is_empty() and reapply_pending(canceled).is_empty(), "death cancels delayed reapply")
	var aftershock = fresh(["F07", "F11"], 3)
	release_once(aftershock, "F07")
	advance(aftershock, 0.6)
	ignite(aftershock)
	advance(aftershock, 0.45)
	check(not burn(aftershock).is_empty(), "third-level aftershock never consumes new burn")

func same_time_reignite_priority():
	var b = fresh(["F07", "F11"])
	grant(b, "G04")
	ignite(b)
	detonate(b, 1.0, true)
	advance(b, 0.05)
	release_once(b, "F07", false)
	advance(b, 0.45)
	check(near(source_damage(b, "detonation"), 600.0), "same-time extra bomb hits before delayed refuel: no new detonation")
	check(b.emitted.filter(func(event): return event.kind == "fire_detonation").size() == 1, "one original detonation event at impact/refuel tie")
	check(not burn(b).is_empty() and near(float(burn(b).get("next_tick", -99)), 1.0) and near(float(burn(b).get("expires", -99)), 4.5), "delayed refuel remains intact after same-time extra bomb")
	check(reapply_pending(b).is_empty(), "same-time refuel consumed pending once")
	var killed = fresh(["F07", "F11"])
	grant(killed, "G04")
	ignite(killed)
	detonate(killed, 1.0, true)
	killed.actors[0].health = 400.0
	advance(killed, 0.05)
	release_once(killed, "F07", false)
	advance(killed, 0.45)
	check(killed.actors[0].health <= 0.0 and burn(killed).is_empty() and reapply_pending(killed).is_empty(), "same-time direct lethal hit prevents delayed refuel")
	check(killed.emitted.filter(func(event): return event.kind == "fire_reignited").is_empty(), "no misleading refuel event for same-time killed actor")
	var natural = fresh(["F07", "F11"])
	grant(natural, "G04")
	ignite(natural)
	detonate(natural, 1.0, true)
	advance(natural, 0.25)
	natural._owned_spell("F11").cast_remaining = 0.25
	natural._owned_spell("F11").locked_pos = natural.actors[0].pos
	advance(natural, 0.25)
	check(natural.cast_log.any(func(event): return event.id == "F11" and near(float(event.at), 0.5)), "natural new F11 releases on refuel tie")
	check(near(float(burn(natural).get("next_tick", -99)), 1.0) and near(float(burn(natural).get("expires", -99)), 4.5), "new natural ignition after delayed refuel preserves its next tick")
	check(near(source_damage(natural, "burning"), 0.0), "refuel/new-ignition tie adds no immediate burn tick")

func profession_events():
	var rain = fresh(["F03"])
	grant(rain, "B03")
	release_once(rain, "F03")
	advance(rain, 0.3)
	check(near(source_damage(rain, "F03"), 150.0), "B03 actual first fixed100x1.5")
	advance(rain, 0.4)
	check(near(source_damage(rain, "F03"), 210.0), "second fixed stays60 not90")
	check(rain._base.spells.F03.levels[0].drops == 6, "B03 no extra seventh drop")
	var g03 = fresh(["F06"], 3)
	grant(g03, "G03")
	release_once(g03, "F06")
	advance(g03, 1.5)
	var before_count: int = g03.damage_log.filter(func(hit): return hit.source == "G03").size()
	check(before_count == 0, "age2 G03 no early trigger")
	advance(g03, 0.5)
	check(g03.damage_log.filter(func(hit): return hit.source == "G03").size() == 1, "natural area age2 triggers once")
	check(near(source_damage(g03, "G03"), 400.0), "G03 does not inherit current field20pct attack snapshot")
	advance(g03, 5.0)
	check(g03.damage_log.filter(func(hit): return hit.source == "G03").size() == 1, "area expiry not a second G03 trigger")
	var replace = fresh(["F06"], 3)
	grant(replace, "G03")
	release_once(replace, "F06")
	advance(replace, 1.0)
	release_once(replace, "F06", false)
	advance(replace, 1.1)
	check(replace.damage_log.filter(func(hit): return hit.source == "G03").is_empty(), "premature replacement cancels old and extra cannot G03")
	var same = fresh(["F06"], 3)
	grant(same, "G03")
	release_once(same, "F06")
	ticks(same, 203) # next tick begins .3s windup at1.7; releases exactly2.0
	same.spells[0].remaining = 0.0
	advance(same, 0.31)
	stop_natural(same)
	check(same.damage_log.filter(func(hit): return hit.source == "G03").size() == 1, "old area mature event precedes same-time new field replacement")
	var pressure = fresh(["F06"], 3)
	grant(pressure, "G03")
	pressure.extra_cdr = 0.6
	pressure.spells[0].remaining = 0.0
	advance(pressure, 60.0)
	check(pressure.damage_log.filter(func(hit): return hit.source == "G03").size() == 17, "actual sixty-second highCDR field age2 triggers17")
	var derived = fresh(["F01"])
	grant(derived, "P02")
	derived.player.crit_rate = 1.0
	ignite(derived)
	advance(derived, 4.1)
	check(derived._artifact_combat._patches.is_empty() and derived._artifact_combat._natural_casts == 0, "burn ticks no P02 or natural chain")
	var chain = fresh(["F01", "F02", "F08"])
	grant(chain, "P04")
	grant(chain, "G01")
	for index in 3:
		chain._artifact_combat.on_cast(chain, chain.spells[0], chain.actors[0], context("F01", index))
	check(chain.extra_log.size() == 2 and chain._artifact_combat._natural_casts == 3, "P04 and G01 exactly one extra each, no recursive accounting")
	var no_legal = fresh(["F09", "F02", "F10"])
	grant(no_legal, "P04")
	no_legal.actors[0].pos = Vector2(0, 2.4)
	for index in 3: no_legal._artifact_combat.on_cast(no_legal, no_legal.spells[0], no_legal.actors[0], context("F09", index, true, "wave"))
	check(no_legal.extra_log.is_empty() and no_legal._artifact_combat._natural_casts == 3, "P04 shared legality excludes F09L1 out of2m and full shield")
	var dot_kill = fresh()
	grant(dot_kill, "GU17")
	dot_kill.actors = [actor(1, Vector2(0, 2), 25.0), actor(2, Vector2(5, 5))]
	ignite(dot_kill)
	advance(dot_kill, 1.5)
	check(dot_kill.kills == 1 and int(dot_kill._artifact_combat.state_snapshot().generic.hunting_stacks) == 1, "shared burn actual kill grants GU17 once without recursive death count")

func readiness_and_shield():
	var b = fresh(["F10"], 3)
	grant(b, "B10")
	grant(b, "GT01")
	b.spells[0].remaining = 0.0
	advance(b, 1.0)
	check(b.casts == 0 and near(b.spells[0].cast_remaining, 0.0), "full shield never begins windup")
	b.player.shield = 80.0
	ticks(b, 1)
	check(b.spells[0].cast_remaining > 0.3 and b.casts == 0, "deficit starts full.35 windup")
	advance(b, 0.2)
	check(b.casts == 0 and near(b.player.shield, 80.0), "no restore before full windup")
	advance(b, 0.15)
	check(b.casts == 1 and near(b.player.shield, 100.0), "actual restore capped by20 deficit")
	check(near(float(b._artifact_combat.state_snapshot().generic.charge), 80.0), "GT01 stores actual20x4 not request75")
	var cancel = fresh(["F10"])
	cancel.player.shield = 0.0
	cancel.spells[0].remaining = 0.0
	ticks(cancel, 1)
	cancel.player.shield = 100.0
	advance(cancel, 0.36)
	check(cancel.casts == 0 and near(cancel.spells[0].remaining, 0.0), "full at completion cancels no CD or natural event")
	var wait_target = fresh(["F11"])
	wait_target.spells[0].remaining = 0.0
	wait_target.actors[0].pos = Vector2(15, 0)
	advance(wait_target, 1.0)
	check(wait_target.casts == 0, "brand waits without a legal target")
	wait_target.actors[0].pos = Vector2(0, 2)
	ticks(wait_target, 1)
	check(wait_target.casts == 0 and wait_target.spells[0].cast_remaining > 0.2, "new legal target still requires full brand windup")
	advance(wait_target, 0.25)
	check(wait_target.casts == 1, "brand releases only after fresh windup")

func freeze_cleanup():
	var b = fresh(["F07", "F11"])
	grant(b, "G04")
	ignite(b)
	detonate(b, 1.0, true)
	ignite(b)
	var state_before: Array = b.get_snapshot().spell_burns
	var pending_before: Array = reapply_pending(b)
	var health_before: float = float(b.actors[0].health)
	b.set_paused(true)
	advance(b, 1.0)
	check(b.get_snapshot().spell_burns == state_before and reapply_pending(b) == pending_before and near(float(b.actors[0].health), health_before), "pause freezes burn/reapply state and damage")
	b.set_paused(false)
	b.phase = "reward"
	advance(b, 1.0)
	check(b.get_snapshot().spell_burns == state_before and reapply_pending(b) == pending_before and near(float(b.actors[0].health), health_before), "choice advances route time only, not burn/reapply remaining")
	b._stop_combat()
	check(b.get_snapshot().spell_burns.is_empty() and reapply_pending(b).is_empty(), "clear removes burn and delayed reapply")
	b._enter_room(2)
	check(b.get_snapshot().spell_burns.is_empty() and reapply_pending(b).is_empty() and b._artifact_combat.has_artifact("G04"), "new room state resets while ownership remains")
	var lethal = fresh(["F07", "F11"])
	grant(lethal, "G04")
	ignite(lethal)
	detonate(lethal, 1.0, true)
	lethal.player.shield = 0.0
	lethal.damage_player(999999.0)
	advance(lethal, 2.0)
	check(lethal.phase == "dead" and lethal.get_snapshot().spell_burns.is_empty() and reapply_pending(lethal).is_empty(), "player death cancels all delayed fire state")
