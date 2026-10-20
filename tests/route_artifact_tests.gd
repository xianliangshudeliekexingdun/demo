extends SceneTree
## Current retirement/pool suite. Pre-migration event fixtures below are retained
## as historical references; current spell events live in spell_growth_tests.gd.

const Artifacts = preload("res://scripts/core/route_artifacts.gd")
const SpellEngine = preload("res://scripts/core/route_spell_combat.gd")
var checks: int = 0
var failures: Array = []

class Harness extends "res://scripts/core/courtyard_route_run.gd":
	var engine
	var artifacts
	var hit_log: Array = []
	var cast_log: Array = []
	var extra_log: Array = []
	var force_critical: bool = false
	func _update_spawn(_dt: float):
		pass
	func _update_enemies(_dt: float):
		for actor in actors:
			actor.previous = actor.pos
	func _update_spells(dt: float):
		super._update_spells(dt)
	func _update_projectiles(_dt: float):
		pass
	func _update_spirit(_dt: float):
		pass
	func _check_clear():
		pass
	func resolve_spell_hit(actor: Dictionary, coefficient: float, context: Dictionary) -> Dictionary:
		var rate: float = float(player.crit_rate)
		if force_critical:
			player.crit_rate = 1.0
		var result: Dictionary = super.resolve_spell_hit(actor, coefficient, context)
		player.crit_rate = rate
		hit_log.append({"actor_id": actor.id, "coefficient": coefficient, "amount": float(result.damage), "actual": float(result.damage), "context": context.duplicate(true), "at": time})
		return result
	func on_spell_cast(spell: Dictionary, target: Dictionary, context: Dictionary):
		cast_log.append(context.duplicate(true))
		super.on_spell_cast(spell, target, context)
	func on_spell_area_expired(context: Dictionary, pos: Vector2):
		super.on_spell_area_expired(context, pos)
	func cast_extra_spell(id: String, target: Dictionary = {}, scale: float = 1.0):
		extra_log.append({"id": id, "target": target.duplicate(true), "scale": scale})
		return super.cast_extra_spell(id, target, scale)
	func artifact_refresh_spirits():
		engine.refresh_spirit_capacity(self)
	func artifact_spirit_count() -> int:
		return engine.spirits.size()
	func artifact_overlapping_spells(pos: Vector2, radius: float) -> Array:
		return engine.overlapping_spell_kinds(pos, radius)
	func artifact_spirit_sync(target: Dictionary, coefficient: float) -> bool:
		return engine.fire_spirit_sync(self, target, coefficient)


func _initialize():
	var suite = preload("res://tests/spell_growth_tests.gd").new()
	suite.source_and_pool()
	checks = suite.checks
	failures = suite.details.duplicate()
	var result = {"checks": checks, "failures": failures.size(), "details": failures, "scope": "63 stored definitions: 24 ordinary generic, four Boss-only seals, 35 archived including 32 retired professions. Canonical spell/UI agreement, live capabilities, shop and Boss sampling, stale ownership cannot duplicate growth."}
	var out: String = "res://build/qa/spell-growth-implementation-20261020/treasures"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-out="):
			out = arg.trim_prefix("--qa-out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var file = FileAccess.open(out.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)


func _check(value: bool, label: String):
	checks += 1
	if not value:
		failures.append(label)
		push_error("Route artifacts: " + label)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _fresh(ids: Array = ["F01"], level: int = 1):
	var run = Harness.new()
	_check(run.configure({}, 617).ok, "base config")
	run.artifacts = run._artifact_combat
	_check(run.artifacts != null, "actual route artifact engine configured")
	run.engine = run._spell_combat
	_check(run.engine != null, "actual route spell engine configured")
	run.room_index = 6
	run.phase = "combat"
	run._spawn_done = true
	run.spawn_warnings.clear()
	run.blocks.clear()
	run.player.pos = Vector2.ZERO
	run.player.previous = run.player.pos
	run.player.crit_rate = 0.0
	run.spells.clear()
	for id in ids:
		var spell = run._new_spell(id)
		spell.level = level
		run._refresh_spell(spell)
		run.spells.append(spell)
	run.actors = [_actor(1, Vector2(0.0, 2.0))]
	return run


func _actor(id: int, pos: Vector2) -> Dictionary:
	return {"id": id, "type": "M01", "pos": pos, "previous": pos, "health": 100000.0, "max_health": 100000.0, "radius": 0.3, "phase": "chase", "push_resistance": 0.0}


func _grant(run, id: String):
	# A fixture isolates an artifact; actual offers/choice are checked separately.
	run.artifacts._owned.append(id)
	run.artifacts.apply_acquisition(run, id)


func _advance(run, duration: float):
	for _step in int(round(duration * 120.0)):
		run.step(1.0 / 120.0)


func _context(id: String, cast_id: int, natural: bool = true, kind: String = "bolt") -> Dictionary:
	return {"cast_id": cast_id, "natural": natural, "spell_id": id, "kind": kind, "damage_scale": 1.0, "field_bonus": 0.0}


func _stop_natural(run):
	for spell in run.spells:
		spell.remaining = 9999.0
		spell.cast_remaining = 0.0


func _sampling_and_eligibility():
	var run = _fresh()
	var ids: Array = run.artifacts.eligible_ids(run)
	_check(ids == ["B01", "P02", "P04", "P05", "P06", "U01", "U02", "U03", "GU04", "GU05", "GU06", "GU08", "GU09", "GU10", "GU11", "GU12", "GU13", "GU14", "GU15", "GU16", "GU17", "GU18", "GT02", "GT03", "GT04"], "one bolt admits its approved igniter item and legal generic effects, excluding crit threshold and recovery conversion")
	run.room_index = 5
	_check(run.artifacts.sample_choices(run, run._rng).is_empty(), "mixed elite in normal room gives no duplicate chest")
	run.room_index = 6
	var offer: Array = run.artifacts.sample_choices(run, run._rng)
	var rng_state: int = run._rng.state
	_check(offer.size() == 3, "elite clear receives three actual candidates")
	_check(run.artifacts.sample_choices(run, run._rng) == offer and run._rng.state == rng_state, "reopening reward does not reroll or consume random stream")
	var unique: Dictionary = {}
	for choice in offer:
		unique[choice.id] = true
		_check(choice.rarity != "gold", "early gold zero stays excluded")
	_check(unique.size() == offer.size(), "offer is without replacement")
	_check(not run.artifacts.choose("G01", run), "unoffered choice rejected")
	_check(run.artifacts.choose(str(offer[0].id), run), "offered choice acquired")
	_check(not run.artifacts.choose(str(offer[1].id), run), "one artifact per elite reward room")
	_check(run.artifacts.sample_choices(run, run._rng).is_empty(), "claimed reward cannot be reopened")
	_check(run.spells.size() == 1, "artifact occupies no spell slot")
	var owned: Array = run.artifacts.owned_snapshot()
	owned[0].values.name = "mutated"
	_check(run.artifacts.owned_snapshot()[0].values.name != "mutated", "inventory snapshots are deep copies")
	run.room_index = 12
	for candidate in run.artifacts.sample_choices(run, run._rng):
		_check(candidate.id != offer[0].id, "owned artifact excluded from later chest")
	run.room_index = 15
	_check(run.artifacts.sample_choices(run, run._rng).is_empty(), "Boss gold cannot sample before book is resolved")
	run.boss_rewards = {"book_resolved": true, "chest_resolved": false}
	_check(run.artifacts.sample_choices(run, run._rng).all(func(item): return str(item.rarity) == "gold"), "room fifteen now uses approved pure gold reward")
	var all = _fresh(["F01", "F02", "F03", "F04", "F05", "F06", "F07", "F08", "F09", "F10", "F11"], 3)
	all.player.crit_rate = 0.1
	_check(all.artifacts._items.size() == 63 and all.artifacts.eligible_ids(all).size() == 40, "Boss seals do not change 40 ordinary eligible generic/fire candidates")
	_check("B04" not in all.artifacts.eligible_ids(all) and "P01" not in all.artifacts.eligible_ids(all) and "G02" not in all.artifacts.eligible_ids(all), "three archived spirit effects cannot appear as formal fire rewards")
	var rain = _fresh(["F03"])
	_check("G03" not in rain.artifacts.eligible_ids(rain), "low level rain is not persistent enough for world core")
	rain.spells[0].level = 3
	_check("G03" in rain.artifacts.eligible_ids(rain), "third level rain unlocks world core")
	var one_area = _fresh(["F03", "F03"])
	_check("P03" not in one_area.artifacts.eligible_ids(one_area), "duplicate spell entries cannot count as distinct areas")
	var blue: int = 0
	var purple: int = 0
	for seed_value in 2000:
		all.artifacts._offers.clear()
		all._rng.seed = seed_value
		var sample: Array = all.artifacts.sample_choices(all, all._rng)
		if sample[0].rarity == "blue": blue += 1
		if sample[0].rarity == "purple": purple += 1
	_check(blue + purple == 2000 and absf(float(purple) / 2000.0 - 0.25) < 0.035, "first-slot source tier sampling is near 75/25 for 2000 deterministic seeds")
	print("Artifact first tier samples blue=%d purple=%d" % [blue, purple])
	var remaining: Array = all.artifacts.eligible_ids(all)
	all.artifacts._owned.clear()
	all.artifacts._owned.append_array(remaining)
	all.artifacts._offers.clear()
	_check(all.artifacts.sample_choices(all, all._rng).is_empty(), "exhausted legal pool skips without invented money")


func _static_artifacts():
	for level in range(1, 4):
		var run = _fresh(["F01", "F03", "F04", "F05", "F06", "F07", "F08", "F10"], level)
		var source = run._base.duplicate(true)
		for id in ["B01", "B03", "B04", "B05", "B06", "B07", "B08", "B10", "P01"]:
			_grant(run, id)
		_check(_near(run.get_spell_stats(run._owned_spell("F01")).level.radius, float(source.spells.F01.levels[level - 1].radius) * 1.3), "B01 radius applies at level " + str(level))
		var rain: Dictionary = run.get_spell_stats(run._owned_spell("F03"))
		_check(rain.fixed_center_drops == 2 and _near(rain.first_drop_damage_multiplier, 1.5) and rain.level.drops == source.spells.F03.levels[level - 1].drops, "B03 fixes second drop and amplifies only the first without adding drops")
		var spirit: Dictionary = run.get_spell_stats(run._owned_spell("F04"))
		_check(_near(spirit.duration, 16.0) and spirit.count == 2 and _near(spirit.normal_laser_damage_multiplier, 1.1), "B04/P01 duration count and independent normal damage")
		_check(_near(run.get_spell_stats(run._owned_spell("F05")).first_hit_slow, 0.25), "B05 carries real first hit slow")
		_check(_near(run.get_spell_stats(run._owned_spell("F06")).level.radius, float(source.spells.F06.levels[level - 1].radius) * 1.3), "B06 field radius enlarged")
		var bomb: Dictionary = run.get_spell_stats(run._owned_spell("F07"))
		_check(_near(bomb.main_center_damage_multiplier, 1.15) and _near(bomb.main_center_crit_multiplier_add, 0.5), "B07 retains center-only fields")
		_check(_near(run.get_spell_stats(run._owned_spell("F08")).width, 0.7), "B08 player beam widened")
		_check(_near(run.get_spell_stats(run._owned_spell("F10")).level.shield, float(source.spells.F10.levels[level - 1].shield) + 15.0), "B10 shield gain at current level")
		_check(run._base == source, "all static items preserve approved source dictionary")
	var stats = _fresh(["F02"])
	stats.player.health = 123.0
	stats.player.shield = 17.0
	for id in ["U01", "U02", "U03", "B02", "G01"]:
		_grant(stats, id)
	_check(_near(stats.player.max_health, 380.0) and _near(stats.player.health, 123.0), "U01 adds health cap without healing")
	_check(_near(stats.player.max_shield, 125.0) and _near(stats.player.shield, 17.0), "U02 adds shield cap without immediate refill")
	_check(_near(stats.player.attack, 115.0) and _near(stats.player.crit_rate, 0.0) and _near(stats.player.fire_bonus, 0.0), "U03 grows attack while scoped B02/G01 preserve shared player fields")
	_check(_near(stats.artifacts.fire_crit_rate_bonus(), 0.15) and _near(stats.artifacts.fire_damage_bonus(), 0.15), "B02/G01 retain approved fire-only source bonuses")
	_check(stats.artifacts.defense_bonuses() == {"health_max_add": 80.0, "shield_max_add": 25.0}, "defense preview agrees with actual source values")


func _actual_spell_changes():
	var bomb = _fresh(["F07"])
	bomb.force_critical = true
	_grant(bomb, "B07")
	bomb.actors = [_actor(1, Vector2(0, 2)), _actor(2, Vector2(1.7, 2))]
	_check(bomb.engine.cast_extra(bomb, "F07", bomb.actors[0]), "real B07 bomb launches")
	_stop_natural(bomb)
	_advance(bomb, 0.6)
	var inner: Dictionary = bomb.hit_log.filter(func(hit): return hit.actor_id == 1)[0]
	var outer: Dictionary = bomb.hit_log.filter(func(hit): return hit.actor_id == 2)[0]
	_check(_near(inner.amount, 1150.0), "B07 center damage 100*5*1.15*(1.5+.5) applied exactly once")
	_check(_near(outer.amount, 375.0), "B07 outer damage ignores center bonuses")
	var rain = _fresh(["F03"])
	_grant(rain, "B03")
	rain.engine.cast_extra(rain, "F03", rain.actors[0])
	_stop_natural(rain)
	_advance(rain, 0.31)
	_check(not rain.hit_log.is_empty() and _near(rain.hit_log[0].amount, 150.0), "B03 real first fixed drop is 150 damage")
	_advance(rain, 0.4)
	_check(rain.hit_log.size() >= 2 and _near(rain.hit_log[1].amount, 60.0), "B03 fixed second drop remains 60 damage")
	var shield = _fresh(["F10"])
	_grant(shield, "B10")
	shield.player.shield = 10.0
	shield.engine.cast_extra(shield, "F10")
	_check(_near(shield.player.shield, 55.0), "B10 actual shield recovery +15")
	shield.player.shield = 95.0
	shield.engine.cast_extra(shield, "F10")
	_check(_near(shield.player.shield, 100.0), "B10 recovery capped at maximum shield")
	var spirit = _fresh(["F04"])
	_grant(spirit, "B04")
	spirit.engine.cast_extra(spirit, "F04", spirit.actors[0])
	_stop_natural(spirit)
	_advance(spirit, 0.4)
	var previous: float = float(spirit.engine.spirits[0].attack_remaining)
	_grant(spirit, "P01")
	_check(spirit.engine.spirits.size() == 2, "P01 immediately fills missing spirit slot")
	_check(_near(float(spirit.engine.spirits[0].attack_remaining), previous), "P01 keeps old spirit cadence")
	_check(_near(float(spirit.engine.spirits[1].attack_remaining), 1.25), "P01 new spirit waits full interval")
	_advance(spirit, 1.0)
	_check(not spirit.hit_log.is_empty() and _near(spirit.hit_log[0].coefficient, 1.1), "B04 actual normal laser coefficient boosted")
	var vortex = _fresh(["F05"])
	_grant(vortex, "B05")
	vortex.engine.cast_extra(vortex, "F05", vortex.actors[0])
	_stop_natural(vortex)
	_advance(vortex, 1.0)
	var slows: Dictionary = vortex.actors[0].get("spell_slows", {})
	_check(not slows.is_empty(), "B05 real vortex writes slow source")
	if not slows.is_empty():
		var until: float = float(slows.values()[0].until)
		_advance(vortex, 0.5)
		_check(_near(float(slows.values()[0].until), until), "B05 same vortex does not refresh first-hit slow")
	var wave = _fresh(["F09"])
	_grant(wave, "B09")
	wave.engine.cast_extra(wave, "F09", wave.actors[0])
	_check(_near(wave.artifacts.move_speed_multiplier(), 1.15), "B09 actual extra wave hit grants speed")
	_stop_natural(wave)
	_advance(wave, 2.01)
	_check(_near(wave.artifacts.move_speed_multiplier(), 1.0), "B09 speed expires normally")
	var widened = _fresh(["F08"])
	_grant(widened, "B08")
	widened.actors.append(_actor(2, Vector2(0.6, 2.0)))
	widened.engine.cast_extra(widened, "F08", widened.actors[0])
	_check(widened.hit_log.size() == 2, "B08 enlarged real beam reaches enemy outside original width")
	var field = _fresh(["F06"])
	_grant(field, "B06")
	field.engine.cast_extra(field, "F06", field.actors[0])
	field.player.pos = Vector2(2.7, 0.0)
	_check(_near(field.engine.field_attack_bonus(), 0.2), "B06 enlarged circle keeps real player attack buff outside old radius")
	var ring = _fresh(["F01"])
	_grant(ring, "B01")
	ring.actors.append(_actor(2, Vector2(1.2, 1.6)))
	ring.engine.cast_extra(ring, "F01", ring.actors[0])
	_stop_natural(ring)
	_advance(ring, 0.2)
	_check(ring.hit_log.size() == 2, "B01 real splash reaches enemy outside original radius")


func _event_artifacts():
	var book = _fresh(["F01", "F10", "F02"])
	_grant(book, "P04")
	_stop_natural(book)
	for index in 3:
		book.artifacts.on_cast(book, book.spells[0], book.actors[0], _context("F01", index + 1))
	_check(book.extra_log.size() == 1 and book.extra_log[0].id == "F01", "P04 third natural cast selects only useful active spell")
	_check(book.spells[0].remaining == 9999.0 and book.casts == 0, "P04 extra preserves natural cooldown and natural cast count")
	book.artifacts.on_cast(book, book.spells[0], book.actors[0], _context("F01", 4, false))
	_check(book.artifacts._natural_casts == 3 and book.extra_log.size() == 1, "P04 extra cannot count or recurse")
	book.actors.clear()
	for index in 3:
		book.artifacts.on_cast(book, book.spells[0], {}, _context("F01", index + 10))
	_check(book.extra_log.size() == 1 and book.artifacts._natural_casts == 6, "P04 no target cycle is skipped rather than banked")
	var spring = _fresh(["F01", "F02", "F10"])
	_grant(spring, "P05")
	spring.spells[0].remaining = 8.0
	spring.spells[1].remaining = 7.0
	spring.spells[2].remaining = 0.0
	spring.artifacts.update(spring, 7.99)
	_check(_near(spring.spells[0].remaining, 8.0), "P05 waits full eight seconds")
	spring.paused = true
	spring.artifacts.update(spring, 10.0)
	_check(_near(spring.artifacts._spring_elapsed, 7.99), "P05 paused timer freezes")
	spring.paused = false
	spring.artifacts.update(spring, 0.01)
	_check(_near(spring.spells[0].remaining, 4.0) and _near(spring.spells[1].remaining, 7.0) and _near(spring.spells[2].remaining, 0.0), "P05 halves only current active cooldowns")
	spring.artifacts.reset_room()
	_check(_near(spring.artifacts._spring_elapsed, 0.0) and spring.artifacts.has_artifact("P05"), "new room restarts artifact clocks but preserves ownership")
	var crown = _fresh(["F01", "F04", "F10"])
	_grant(crown, "G01")
	_stop_natural(crown)
	for id in ["F01", "F04", "F10", "F01", "F01"]:
		crown.artifacts.on_cast(crown, crown._owned_spell(id), crown.actors[0], _context(id, crown.cast_log.size() + crown.extra_log.size() + 1))
	_check(crown.extra_log.size() == 1 and crown.extra_log[0].id == "F01" and _near(crown.extra_log[0].scale, 0.7), "G01 only counts three offensive casts and repeats same spell at seventy percent")
	var king = _fresh(["F04", "F08"], 3)
	_grant(king, "G02")
	_grant(king, "B04")
	king.engine.cast_extra(king, "F04", king.actors[0])
	_stop_natural(king)
	var previous: float = king.engine.spirits[0].attack_remaining
	king.artifacts.on_cast(king, king.spells[1], king.actors[0], _context("F08", 101))
	_check(king.hit_log.size() == 1 and _near(king.hit_log[0].coefficient, 2.5), "G02 actual sync coefficient excludes B04 normal laser multiplier")
	_check(_near(king.engine.spirits[0].attack_remaining, previous), "G02 sync does not reset normal laser cadence")
	king.artifacts.on_cast(king, king.spells[1], king.actors[0], _context("F08", 102))
	_check(king.hit_log.size() == 1, "G02 all spirits share two second internal cooldown")
	king.artifacts.update(king, 2.0)
	king.artifacts.on_cast(king, king.spells[1], king.actors[0], _context("F08", 103))
	_check(king.hit_log.size() == 2, "G02 sync becomes available after full cooldown")


func _area_artifacts():
	var patch = _fresh(["F08"])
	_grant(patch, "P02")
	_stop_natural(patch)
	var ctx = _context("F08", 30, true, "beam")
	patch.artifacts.on_hit(patch, patch.actors[0], ctx, {"critical": true, "damage": 1.0})
	patch.artifacts.on_hit(patch, patch.actors[0], ctx, {"critical": true, "damage": 1.0})
	_check(patch.artifacts._patches.size() == 1, "P02 one patch per natural cast despite multihit")
	patch.artifacts.on_hit(patch, patch.actors[0], _context("F08", 31, false, "beam"), {"critical": true})
	_check(patch.artifacts._patches.size() == 1, "P02 extra cast cannot generate new patch")
	patch.artifacts.on_hit(patch, patch.actors[0], _context("F08", 32, true, "beam"), {"critical": true})
	_advance(patch, 0.5)
	_check(patch.hit_log.size() == 1 and _near(patch.hit_log[0].coefficient, 0.4), "P02 overlapping patches share enemy tick rate")
	patch.paused = true
	var life: float = patch.artifacts._patches[0].remaining
	patch.artifacts.update(patch, 2.0)
	_check(_near(patch.artifacts._patches[0].remaining, life), "P02 paused ground does not age")
	patch.paused = false
	_advance(patch, 2.5)
	_check(patch.hit_log.size() == 6 and patch.artifacts._patches.is_empty(), "P02 source interval gives six hits over three seconds")
	var resonance = _fresh(["F03", "F06"])
	_grant(resonance, "P03")
	_stop_natural(resonance)
	resonance.engine.cast_extra(resonance, "F06", resonance.actors[0])
	resonance.engine.cast_extra(resonance, "F03", resonance.actors[0])
	_advance(resonance, 0.31)
	var overlap: Dictionary = resonance.artifacts.modify_damage_context(resonance, resonance.actors[0], {"spell_id": "F01", "school": "fire"})
	_check(_near(overlap.damage_multiplier, 1.2), "P03 distinct fire rain and field overlap adds twenty percent")
	resonance.actors[0].pos = Vector2(8, 8)
	_check(_near(resonance.artifacts.modify_damage_context(resonance, resonance.actors[0], {"spell_id": "F01", "school": "fire"}).damage_multiplier, 1.0), "P03 vulnerability ends immediately on leaving overlap")
	var world = _fresh(["F06"])
	_grant(world, "G03")
	_stop_natural(world)
	world.engine.cast_extra(world, "F06", world.actors[0])
	_advance(world, 4.0)
	_check(world.hit_log.filter(func(hit): return hit.context.get("artifact_id", "") == "G03").is_empty(), "G03 extra field expiry cannot proc")
	world.engine.stop_room()
	world.spells[0].remaining = 0.0
	_advance(world, 0.4)
	_stop_natural(world)
	_advance(world, 4.0)
	var explosions: Array = world.hit_log.filter(func(hit): return hit.context.get("artifact_id", "") == "G03")
	_check(explosions.size() == 1 and _near(explosions[0].coefficient, 4.0), "G03 real natural field survives two seconds and bursts once at four hundred percent")
	var expiry_ctx = _context("F06", 333, true, "area")
	world.artifacts.on_area_expired(world, expiry_ctx, world.actors[0].pos)
	var before: int = world.hit_log.size()
	world.artifacts.on_area_expired(world, expiry_ctx, world.actors[0].pos)
	_check(world.hit_log.size() == before, "G03 no longer responds to expiration callbacks")
	world.artifacts.on_area_matured(world, expiry_ctx, world.actors[0].pos, 2.0)
	before = world.hit_log.size()
	world.artifacts.on_area_matured(world, expiry_ctx, world.actors[0].pos, 2.0)
	_check(world.hit_log.size() == before, "G03 same matured natural cast cannot explode twice")
	world.engine.stop_room()
	world.artifacts.reset_room()
	_check(world.artifacts._patches.is_empty() and world.artifacts._natural_casts == 0, "room cleanup clears event carryover")


func _combination_boundaries():
	var run = _fresh(["F01", "F02", "F03", "F04", "F05", "F06", "F07", "F08"], 3)
	for id in run.artifacts._items:
		_grant(run, id)
	run.force_critical = true
	run.actors = [_actor(1, Vector2(0, 2)), _actor(2, Vector2(0.5, 3))]
	_advance(run, 20.0)
	_check(run.casts > 10 and run.casts < 200, "all-source event combination advances finite natural casts")
	_check(run.extra_log.size() > 0 and run.extra_log.size() < run.casts, "extra spell combination remains bounded by natural events")
	_check(run.artifacts._natural_casts == run.casts, "eventful extras and spirits never increase artifact natural counter")
	_check(run.engine.spirits.size() <= 2, "all artifacts preserve legal spirit cap")
	_check(run.spells.size() == 8, "all artifacts preserve eight-spell cap")
	var fields: Array = run.engine.zones.filter(func(zone): return zone.kind == "field")
	_check(fields.size() <= 1, "echo and sequence keep field replacement singleton")
	var patches: Dictionary = {}
	for patch in run.artifacts._patches:
		patches[patch.cast_id] = true
	_check(patches.size() == run.artifacts._patches.size(), "all-source combo keeps one engraving per original cast")
	for hit in run.hit_log:
		_check(is_finite(hit.amount) and float(hit.amount) >= 0.0, "combined damage stays finite and nonnegative")
	var paused: Dictionary = run.artifacts.state_snapshot()
	run.paused = true
	run.step(5.0)
	_check(run.artifacts.state_snapshot() == paused, "combined artifact clocks and grounds freeze on real pause")
	var wave = _fresh(["F09"])
	_grant(wave, "B09")
	wave.actors[0].pos = Vector2(0, 7)
	wave.engine.cast_extra(wave, "F09")
	_check(_near(wave.artifacts.move_speed_multiplier(), 1.0), "B09 no valid wave hit gives no speed")
	var patch = _fresh(["F03"])
	_grant(patch, "P02")
	for kind in ["area", "spirit", "artifact"]:
		patch.artifacts.on_hit(patch, patch.actors[0], _context("F03", 999, true, kind), {"critical": true})
	_check(patch.artifacts._patches.is_empty(), "P02 persistent ticks and artifact damage never engrave")
	var replacement = _fresh(["F06"])
	_grant(replacement, "G03")
	_advance(replacement, 0.4)
	_stop_natural(replacement)
	_advance(replacement, 1.5)
	replacement.engine.cast_extra(replacement, "F06", replacement.actors[0])
	_advance(replacement, 4.1)
	_check(replacement.hit_log.filter(func(hit): return hit.context.get("artifact_id", "") == "G03").is_empty(), "G03 replaced natural field cannot explode later")
