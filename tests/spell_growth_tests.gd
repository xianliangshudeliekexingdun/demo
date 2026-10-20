extends RefCounted
## Native core fixtures, no interactive scene, AI encounter or production save.
const Catalog = preload("res://scripts/ui/grimoire_catalog.gd")
const Growth = preload("res://scripts/core/route_spell_growth.gd")
var checks: int = 0
var failures: int = 0
var details: Array = []

class Harness extends "res://scripts/core/courtyard_route_run.gd":
	var extras: Array = []
	var hit_log: Array = []
	func _reserve_batch(): pass
	func _update_spawn(_dt: float): pass
	func _check_clear(): pass
	func _update_enemies(dt: float):
		advance_ice_control(dt)
		for actor in actors: actor.previous = actor.pos
	func cast_extra_spell(id: String, target: Dictionary = {}, scale: float = 1.0) -> bool:
		extras.append({"id": id, "scale": scale})
		return super.cast_extra_spell(id, target, scale)
	func damage_enemy(actor: Dictionary, amount: float, id: String = ""):
		var hp: float = float(actor.health)
		super.damage_enemy(actor, amount, id)
		hit_log.append({"id": id, "actor": actor.id, "amount": hp - float(actor.health)})


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		details.append(label)
		push_error("Spell growth: " + label)


func near(a: float, b: float, label: String) -> void:
	check(absf(a - b) < 0.001, "%s: actual %s expected %s" % [label, a, b])


func actor(id: int = 1, pos: Vector2 = Vector2(0, 2)) -> Dictionary:
	return {"id": id, "type_id": "M01", "health": 1000000.0, "max_health": 1000000.0, "radius": 0.3,
		"pos": pos, "previous": pos, "phase": "chase", "push_resistance": 0.0, "spell_slows": {}}


func fresh(ids: Array, level: int = 3):
	var b = Harness.new()
	check(b.configure({}, 20261020).ok, "real route configures")
	b.phase = "combat"
	b.blocks.clear()
	b.actors = [actor()]
	b.spells.clear()
	b.spawn_warnings.clear()
	b.player.pos = Vector2.ZERO
	b.player.previous = Vector2.ZERO
	b.player.attack = 100.0
	b.player.fire_bonus = 0.0
	b.player.crit_rate = 0.0
	b.player.crit_multiplier = 2.0
	for id in ids:
		var spell: Dictionary = b._new_spell(str(id))
		spell.level = level
		b._refresh_spell(spell)
		spell.remaining = 9999.0
		b.spells.append(spell)
	return b


func cast(b, id: String, natural: bool = true, scale: float = 1.0) -> void:
	var spell: Dictionary = b._owned_spell(id)
	spell.locked_pos = b.actors[0].pos
	b._spell_combat._cast(b, spell, b.get_spell_stats(spell), b.actors[0], natural, scale)
	spell.remaining = 9999.0


func advance(b, seconds: float) -> void:
	for tick in roundi(seconds * 120.0): b.step(1.0 / 120.0)


func context(b, id: String, cast_id: int, natural: bool = true) -> Dictionary:
	var spell: Dictionary = b._owned_spell(id)
	var level: Dictionary = b.get_spell_stats(spell).level
	return {"spell_id": id, "cast_id": cast_id, "natural": natural, "damage_scale": 1.0, "field_bonus": 0.0,
		"kind": "direct", "ice_direct": true, "school": "ice" if id.begins_with("I") else "fire",
		"spell_level": spell.level, "ice_level": level.duplicate(true), "growth_level": level.duplicate(true)}


func grant(b, id: String) -> void:
	b._artifact_combat._owned.append(id)
	b._artifact_combat.apply_acquisition(b, id)


func source_and_pool() -> void:
	var b = fresh([])
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Growth.SOURCE))
	var historical: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance_candidates/first_run_v1.json")).spells
	historical.merge(JSON.parse_string(FileAccess.get_file_as_string("res://data/ice_spells_v1.json")).spells, true)
	check(source.spells.size() == 20 and source.retired_items.size() == 32, "20 spells and every 32-item allocation")
	Catalog.load_catalog(true)
	for legacy_id in ["F01", "F04", "F08", "F10"]:
		check(Catalog.describe_spell(legacy_id, 3, false).values.coefficient == historical[legacy_id].levels[2].coefficient if historical[legacy_id].levels[2].has("coefficient") else Catalog.describe_spell(legacy_id, 3, false).values.shield == historical[legacy_id].levels[2].shield, "historical single-room card remains bound to old levels " + legacy_id)
	for id in source.spells:
		check(source.spells[id].levels.size() == 3, id + " exactly three levels")
		for key in historical[id].levels[0]:
			check(source.spells[id].levels[0][key] == historical[id].levels[0][key], id + " retains level-one " + key)
		for level in range(1, 4):
			var spell: Dictionary = b._new_spell(id)
			spell.level = level
			var stats: Dictionary = b.get_spell_stats(spell)
			var ui: Dictionary = Catalog.describe_spell(id, level)
			check(stats.level == source.spells[id].levels[level - 1], id + " runtime reads canonical level")
			for key in stats.level:
				check(ui.values[key] == stats.level[key] and stats[key] == stats.level[key], id + " UI and root agree " + key)
			check(not ui.description.is_empty(), id + " full description")
			if level > 1:
				check(not ui.upgrade_text.is_empty() and ui.upgrade_text.split("\n").size() <= 5, id + " compact current upgrade text")
		b.spells.append({"id": id, "level": 3})
	for id in source.retired_items:
		check(not bool(b._artifact_combat._items[id].active), id + " inactive")
		check(not b._artifact_combat._eligible(b, b._artifact_combat._items[id]), id + " cannot qualify")
	var ordinary: Array = b._artifact_combat.eligible_ids(b)
	check(ordinary.size() == 24, "all mature spells qualify only 24 ordinary generic treasures")
	check(Catalog.artifacts().size() == 28, "grimoire 24 generic plus four Boss seals")
	for seed_value in 32:
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_value
		for offered in b._artifact_combat.sample_shop_choices(b, rng):
			check(str(offered.id) in ordinary, "shop samples only ordinary pool")
	b.room_index = 15
	b.boss_rewards = {"book_resolved": true}
	for id in ordinary: b._artifact_combat._owned.append(id)
	var seals: Array = b._artifact_combat.sample_boss_choices(b, RandomNumberGenerator.new())
	check(seals.size() == 1 and str(seals[0].id) == "BGT15", "empty eligible gold pool still grants Boss seal")
	var clean = fresh(["F01", "F02", "F08", "F10", "I01", "I08", "I09", "I10"])
	var stats_before: Dictionary = clean.get_spell_stats(clean.spells[0])
	var rate_before: float = clean._spell_combat.crit_rate_bonus()
	for id in source.retired_items:
		grant(clean, id)
		check(not clean._artifact_combat.has_artifact(id), id + " stale ownership cannot activate")
	check(clean._artifact_combat.owned_snapshot().is_empty(), "retired items hidden even with stale ownership")
	check(clean.get_spell_stats(clean.spells[0]) == stats_before, "old ownership cannot double-up spell stats")
	near(clean._artifact_combat.fire_damage_bonus(), 0.0, "old G01 adds no fire damage")
	near(clean._artifact_combat.fire_crit_rate_bonus(), 0.0, "old B02 adds no critical rate")
	near(clean._spell_combat.crit_rate_bonus(), rate_before, "new mastery survives retired inventory")
	var mastery = fresh(["F01", "F02"])
	check("GU07" in mastery._artifact_combat.eligible_ids(mastery), "level-three fire mastery qualifies critical-damage treasure")
	var fire_hit: Dictionary = mastery.resolve_spell_hit(mastery.actors[0], 1.0, context(mastery, "F01", 71))
	check(float(fire_hit.damage) >= 150.0, "fire mastery damage bucket applies")
	mastery.spells[0].id = "I01"
	near(mastery.resolve_spell_hit(mastery.actors[0], 1.0, context(mastery, "I01", 72)).damage, 100.0, "fire mastery does not amplify ice")
	check("GU07" not in mastery._artifact_combat.eligible_ids(mastery), "fire-only critical source needs actual fire offense")
	var invalid: Dictionary = source.duplicate(true)
	invalid.spells.F01.levels[1].coefficient = NAN
	check(not Growth.apply_source(historical, invalid).ok, "non-finite tuning rejected")


func fire_transactions() -> void:
	var b = fresh(["F01"], 1)
	cast(b, "F01")
	advance(b, 4.5)
	near(b.damage_dealt, 300.0, "known one primary plus eight burn ticks")
	b = fresh(["F01"])
	b.player.crit_rate = 1.0
	b.actors.append(actor(2, Vector2(0.4, 2)))
	cast(b, "F01")
	advance(b, 0.4)
	check(b._spell_combat.growth.patches.size() == 1, "one critical patch across explosion neighbors and secondary")
	cast(b, "F01", false)
	advance(b, 0.4)
	check(b._spell_combat.growth.patches.size() == 1, "extra bolt never creates patch")
	var snapshot: Dictionary = b.get_snapshot()
	check(snapshot.artifact_patches.size() == 1, "renderer receives growth patch")
	b.spells.clear()
	advance(b, 4.0)
	check(b._spell_combat.growth.patches.is_empty(), "released patch finishes after slot replacement")
	b = fresh(["F01"])
	b.player.crit_rate = 1.0
	var ctx: Dictionary = context(b, "F01", 17)
	b._spell_combat.growth.on_hit(b, b.actors[0], ctx, {"damage": 1.0, "critical": true})
	ctx["gem_body_scale"] = 2.0
	ctx["field_bonus"] = 0.2
	ctx.cast_id = 18
	b._spell_combat.growth.on_hit(b, b.actors[0], ctx, {"damage": 1.0, "critical": true})
	b.player.crit_rate = 0.0
	advance(b, 0.5)
	near(b.damage_dealt, 40.0, "overlapping critical patches share one hit gate without copied body/field multipliers")
	b = fresh(["F08"])
	for count in 6: cast(b, "F08")
	check(b.extras.size() == 2 and b.casts == 6, "two local echoes from six natural releases")
	near(b.extras[0].scale, 0.7, "echo strength")
	cast(b, "F08", false)
	check(b.extras.size() == 2, "extra echo does not recurse")
	cast(b, "F08")
	b.spells.clear()
	var new_beam: Dictionary = b._new_spell("F08")
	new_beam.level = 3
	b.spells.append(new_beam)
	cast(b, "F08")
	cast(b, "F08")
	check(b.extras.size() == 2, "newly learned beam does not inherit removed spell's partial echo count")
	b._stop_combat()
	check(b._spell_combat.growth._echo_count == 0 and b._spell_combat.growth.patches.is_empty(), "room stop clears growth state")
	b = fresh(["F07"])
	b._spell_combat.apply_burn(b, b.actors[0], "F01")
	ctx = context(b, "F07", 20)
	ctx.merge({"detonate": true, "detonation_multiplier": 1.5}, true)
	b._spell_combat._hit(b, b.actors[0], 1.0, ctx)
	near(b.damage_dealt, 800.0, "direct 100 plus remaining fuel 200 times 3.5")
	check(b._spell_combat.fire_status.reignite_pending.size() == 1 and not b._spell_combat.has_burn(b, b.actors[0]), "old fuel consumed once; one delayed reignite")
	b.spells.clear()
	advance(b, 0.5)
	check(b._spell_combat.has_burn(b, b.actors[0]), "released reignite survives replacement")
	ctx.cast_id = 21
	b._spell_combat._hit(b, b.actors[0], 1.0, ctx)
	check(b._spell_combat.fire_status.reignite_pending.is_empty(), "reignite per-actor shared cooldown")
	b = fresh(["F07"])
	b._spell_combat.apply_burn(b, b.actors[0])
	ctx = context(b, "F07", 23, false)
	ctx.merge({"detonate": true, "detonation_multiplier": 1.5}, true)
	b._spell_combat._hit(b, b.actors[0], 1.0, ctx)
	near(b.damage_dealt, 400.0, "extra bomb uses base multiplier without natural plus-two")
	check(b._spell_combat.fire_status.reignite_pending.is_empty(), "extra bomb cannot schedule natural reignite")
	b = fresh(["F07"])
	cast(b, "F07")
	advance(b, 1.1)
	check(b._spell_combat.fire_status.burns.is_empty() and b._spell_combat.fire_status.reignite_pending.is_empty(), "bomb without fuel cannot ignite or recurse")
	b = fresh(["F06"])
	cast(b, "F06")
	advance(b, 2.1)
	check(b._spell_combat.growth._matured.size() == 1, "one natural mature field burst")
	advance(b, 2.0)
	check(b._spell_combat.growth._matured.size() == 1, "later field ticks cannot burst twice")
	b = fresh(["F06"])
	ctx = context(b, "F06", 36)
	ctx["gem_body_scale"] = 2.0
	ctx["field_bonus"] = 0.2
	b._spell_combat.growth.on_area_matured(b, ctx, b.actors[0].pos, 2.0)
	near(b.damage_dealt, 400.0, "mature field is derived damage without copied body or own field snapshot")
	b = fresh(["F06", "F03"])
	cast(b, "F06")
	cast(b, "F03")
	advance(b, 0.4)
	near(b._spell_combat.growth.fire_vulnerability(b, b.actors[0]), 0.2, "overlapping distinct natural zones expose one fire vulnerability")
	var hp: float = b.actors[0].health
	b.resolve_fire_status_hit(b.actors[0], 1.0, "burning", {})
	near(hp - b.actors[0].health, 144.0, "fire vulnerability applies to status with field attack")
	b._spell_combat.zones[1].context.natural = false
	near(b._spell_combat.growth.fire_vulnerability(b, b.actors[0]), 0.0, "extra area cannot meet natural overlap requirement")
	b = fresh(["F09"])
	cast(b, "F09")
	near(b._artifact_combat.move_speed_multiplier(b), 1.15, "actual wave hit grants movement speed")
	advance(b, 2.1)
	near(b._artifact_combat.move_speed_multiplier(b), 1.0, "wave movement speed expires")
	b = fresh(["F11"])
	b._spell_combat.apply_burn(b, b.actors[0])
	check(b._spell_combat.fire_status.future_ticks(b, b.actors[0]) == 12, "held brand extends shared burn to twelve ticks")
	var next_tick: float = b._spell_combat.fire_status.burns[1].next_tick
	b.spells.clear()
	b._spell_combat.apply_burn(b, b.actors[0])
	near(b._spell_combat.fire_status.burns[1].next_tick, next_tick, "burn refresh never resets next tick")
	check(b._spell_combat.fire_status.future_ticks(b, b.actors[0]) == 12, "short refresh does not erase released long burn")
	advance(b, 6.1)
	near(b.damage_dealt, 300.0, "one shared twelve-tick burn, no parallel copies")


func ice_transactions() -> void:
	var b = fresh(["I02"])
	var ice = b._spell_combat.ice
	ice.apply_frost(b, b.actors[0], 1)
	ice._hit(b, b.actors[0], 1.0, context(b, "I02", 10), 1)
	check(not ice.status.capture_ready(1).is_empty(), "I02 first natural direct turns one old frost into ready window")
	b = fresh(["I03"])
	ice = b._spell_combat.ice
	var ctx: Dictionary = context(b, "I03", 11)
	ice._hit(b, b.actors[0], 1.0, ctx, 1)
	ice._hit(b, b.actors[0], 1.0, ctx, 1)
	check(int(ice.status.state_for(1).stacks) == 2, "first hit without pre-frost consumes the extra-frost check")
	b = fresh(["I03"])
	ice = b._spell_combat.ice
	ice.apply_frost(b, b.actors[0], 1)
	ctx = context(b, "I03", 12)
	ctx.growth_primary = false
	ice._hit(b, b.actors[0], 1.0, ctx, 0)
	check(int(ice.status.state_for(1).stacks) == 1, "star followup cannot supply first-primary frost")
	b = fresh(["I06"])
	ice = b._spell_combat.ice
	cast(b, "I06")
	advance(b, 1.5)
	check(not ice.status.capture_ready(1).is_empty(), "storm second qualified frost creates ready window by effective wave three")
	check(ice.growth._second_checks.size() == 1, "storm extra frost once per actor and cast")
	b = fresh(["I07"])
	ice = b._spell_combat.ice
	b.actors.append(actor(2, Vector2(0.5, 2)))
	b.actors.append(actor(3, Vector2(-0.5, 2)))
	ice.status.force_ready(b, b.actors[0], 1.5)
	cast(b, "I07")
	near(b.actors[0].max_health - b.actors[0].health, 776.0, "I07 primary 200 plus old-token shatter 360 times 1.6")
	for index in [1, 2]:
		near(b.actors[index].max_health - b.actors[index].health, 140.0, "neighbor shard base damage")
		check(int(ice.status.state_for(index + 1).stacks) == 1, "natural fragment frost only on surviving neighbor")
	check(int(ice.status.state_for(1).stacks) == 1 and not ice.status.state_for(1).ready, "enhanced natural shatter retains one ordinary frost")
	cast(b, "I07")
	near(b.actors[0].max_health - b.actors[0].health, 976.0, "consumed token cannot shatter again")
	ice.status.force_ready(b, b.actors[0], 1.5)
	cast(b, "I07", false)
	near(b.actors[0].max_health - b.actors[0].health, 1536.0, "extra shatter has upgraded base but no natural multiplier")
	b = fresh(["I08"], 2)
	ice = b._spell_combat.ice
	b.player.shield = b.player.max_shield - 100.0
	ctx = context(b, "I08", 50)
	var shield: float = b.player.shield
	ice.status.force_ready(b, b.actors[0], 1.5, ctx)
	near(b.player.shield - shield, 15.0, "I08 level two restores actual shield without armor prerequisite")
	ice.status.force_ready(b, b.actors[0], 1.5, ctx)
	near(b.player.shield - shield, 15.0, "existing window neither renews nor restores")
	b.actors.append(actor(2, Vector2(1, 2)))
	ctx.cast_id = 51
	ice.status.force_ready(b, b.actors[1], 1.5, ctx)
	near(b.player.shield - shield, 15.0, "four second shield restore shared across actors")
	check("GT01" in b._artifact_combat.eligible_ids(b), "I08 level two qualifies generic shield charge")
	advance(b, 4.1)
	b.player.shield = b.player.max_shield - 3.0
	ctx.cast_id = 52
	ice.status.force_ready(b, b.actors[0], 1.5, ctx)
	near(b.player.shield, b.player.max_shield, "window restore clamps to real shield deficit")
	b = fresh(["I08"])
	grant(b, "GT01")
	b.player.shield = b.player.max_shield - 10.0
	cast(b, "I08")
	advance(b, 0.25)
	near(b.player.shield, b.player.max_shield, "upgraded prison uses generic recovery amplifier and real deficit")
	near(b._artifact_combat.state_snapshot().generic.charge, 40.0, "shield charge counts ten actual restored points only")
	b = fresh(["I08"])
	grant(b, "GT01")
	b.player.shield = 0.0
	cast(b, "I08", false)
	advance(b, 0.25)
	near(b.player.shield, 0.0, "extra prison creates no natural shield restore")
	near(b._artifact_combat.state_snapshot().generic.charge, 0.0, "extra prison creates no shield charge")
	b = fresh(["I08"])
	ice = b._spell_combat.ice
	b.actors[0].type_id = "BOSS01"
	b.actors[0].ice_control_coefficient = 0.0
	b.player.shield = 0.0
	cast(b, "I08")
	advance(b, 0.25)
	near(b.actors[0].max_health - b.actors[0].health, 480.0, "immune Boss receives upgraded prison bonus damage")
	check(not ice.status.is_frozen(1) and not ice.status.capture_ready(1).is_empty(), "Boss receives brittle window without hard freeze")
	near(b.player.shield, 25.0, "Boss new window pays one shield restore")
	b = fresh(["I09"])
	ice = b._spell_combat.ice
	cast(b, "I09")
	near(ice.defense_bonus(), 45.0, "new armor defense")
	b.spells.clear()
	b.damage_player(10.0)
	check(int(ice.status.state_for(1).stacks) == 2, "released armor retaliation survives slot replacement")
	b.player.invulnerable = 0.0
	b.damage_player(10.0)
	check(int(ice.status.state_for(1).stacks) == 2, "retaliation respects shared cooldown")
	b = fresh(["I10"])
	ice = b._spell_combat.ice
	ice.apply_frost(b, b.actors[0], 1)
	near(ice.status.state_for(1).remaining, 6.0, "held ice mastery ordinary frost duration")
	ice.status.force_ready(b, b.actors[0], 1.5)
	near(ice.status.state_for(1).window_remaining, 3.0, "only existing level-three half-second ready-window extension")
	near(ice.status.state_for(1).freeze_remaining, 1.5, "ordinary frost upgrade never lengthens hard freeze")
	var time: float = ice.status.clock
	b.paused = true
	advance(b, 2.0)
	near(ice.status.clock, time, "pause freezes growth combat deadlines")
	b.paused = false
	b._stop_combat()
	check(ice.growth.armor_context.is_empty() and ice.growth._restore_casts.is_empty() and ice.status.states.is_empty(), "room stop clears ice growth and status")


func run() -> int:
	source_and_pool()
	fire_transactions()
	ice_transactions()
	print("Spell growth rules: %d checks; %d failures" % [checks, failures])
	return failures
