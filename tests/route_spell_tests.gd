extends SceneTree
## Native deterministic combat checks. No renderer, save file or account mutation.

const SpellEngine = preload("res://scripts/core/route_spell_combat.gd")
var checks: int = 0
var failures: Array = []

class Harness extends "res://scripts/core/courtyard_route_run.gd":
	var engine
	var hit_log: Array = []
	var emitted: Array = []
	var expired: Array = []
	var natural_casts: Array = []
	func _update_spawn(_dt: float):
		pass
	func _update_enemies(_dt: float):
		for actor in actors:
			actor.previous = actor.pos
	func _update_projectiles(_dt: float):
		pass
	func _update_spirit(_dt: float):
		pass
	func _update_spells(dt: float):
		super._update_spells(dt)
	func _check_clear():
		pass
	func resolve_spell_hit(actor: Dictionary, coefficient: float, context: Dictionary) -> Dictionary:
		var result: Dictionary = super.resolve_spell_hit(actor, coefficient, context)
		hit_log.append({"actor_id": actor.id, "coefficient": coefficient, "amount": float(result.damage), "context": context.duplicate(true), "at": time})
		return result
	func on_spell_cast(spell: Dictionary, target: Dictionary, context: Dictionary):
		natural_casts.append({"id": spell.id, "pos": target.pos, "context": context.duplicate(true)})
		super.on_spell_cast(spell, target, context)
	func on_spell_area_expired(context: Dictionary, pos: Vector2):
		expired.append({"context": context.duplicate(true), "pos": pos})
		super.on_spell_area_expired(context, pos)
	func _emit(kind: String, values: Dictionary, lifetime: float):
		emitted.append({"kind": kind, "values": values.duplicate(true), "at": time})
		super._emit(kind, values, lifetime)


func _initialize():
	for id in ["F01", "F03", "F04", "F05", "F06", "F07", "F08", "F09", "F10", "F11"]:
		for level in range(1, 4):
			_check_level(id, level)
	_check_passive_synergy()
	_check_secondary_and_aoe()
	_check_freeze_and_cleanup()
	_check_field_grace_and_replacement()
	_check_spirits()
	_check_shield_boundaries()
	_check_wall_and_extra()
	_check_same_source_overlap()
	var result = {"checks": checks, "failures": failures.size(), "details": failures, "scope": "formal ten fire spells plus archived F04; actual route damage/status pipeline; updated three-level direct/mature budgets separated from live burning, all three levels and boundaries"}
	var out: String = "res://build/qa/six-schools-implementation-20261021/spells"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-out="):
			out = arg.trim_prefix("--qa-out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var file = FileAccess.open(out.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)


func _new_run(id: String = "F01", level: int = 1):
	var run = Harness.new()
	var configured: Dictionary = run.configure({}, 441)
	_check(configured.ok, "base config")
	run.engine = run._spell_combat
	_check(run.engine != null, "actual route spell engine configured")
	run.phase = "combat"
	run._spawn_done = true
	run.spawn_warnings.clear()
	run.blocks.clear()
	run.player.pos = Vector2.ZERO
	run.player.previous = run.player.pos
	run.player.crit_rate = 0.0
	run.spells = [run._new_spell(id)]
	run.spells[0].level = level
	run._refresh_spell(run.spells[0])
	run.actors = [_actor(1, Vector2(0, 2))]
	return run


func _actor(id: int, pos: Vector2) -> Dictionary:
	return {"id": id, "type": "M01", "pos": pos, "previous": pos, "health": 100000.0, "max_health": 100000.0, "radius": 0.3, "phase": "chase", "push_resistance": 0.0}


func _advance(run, duration: float):
	for _step in int(ceil(duration * 120.0)):
		run.step(1.0 / 120.0)


func _first_cast(run):
	for _step in 240:
		run.step(1.0 / 120.0)
		if run.casts > 0:
			run.spells[0].remaining = 1000.0
			return


func _count_events(run, kind: String) -> int:
	return run.emitted.filter(func(item): return item.kind == kind).size()


func _direct_damage(run) -> float:
	var result: float = 0.0
	for hit in run.hit_log:
		result += float(hit.amount)
	return result


func _check_level(id: String, level: int):
	var run = _new_run(id, level)
	if id == "F10":
		run.player.shield = 0.0
	_first_cast(run)
	_check(run.casts == 1, "%s L%d naturally casts" % [id, level])
	_advance(run, 14.5)
	_check(run.casts == 1, "%s L%d no duplicate natural release" % [id, level])
	_check(run.natural_casts.size() == 1, "%s L%d one natural event" % [id, level])
	_check(run.engine.pending.is_empty(), "%s L%d pending bounded" % [id, level])
	_check(run.engine.zones.is_empty(), "%s L%d area expiry" % [id, level])
	_check(run.projectiles.is_empty(), "%s L%d projectiles expire" % [id, level])
	if id == "F10":
		_check(is_equal_approx(run.player.shield, [30.0, 55.0, 70.0][level-1]), "F10 level shield budget")
		_check(is_equal_approx(run.player.health, run.player.max_health), "F10 never changes health")
		_check(run.hit_log.is_empty(), "F10 does not damage")
	elif id == "F01":
		var expected = [100.0, 145.0, 250.0][level - 1]
		_check(is_equal_approx(_direct_damage(run), expected), "F01 L%d primary plus secondary budget %.1f actual %.1f" % [level, expected, _direct_damage(run)])
		_check(run.damage_dealt > _direct_damage(run), "F01 approved burning remains active beyond raw direct budget")
		_check(run.hit_log.size() == (2 if level == 3 else 1), "F01 independent level3 second bolt")
	elif id == "F08":
		var expected = [160.0, 240.0, 420.0][level - 1]
		_check(is_equal_approx(_direct_damage(run), expected), "F08 L%d primary plus pulse budget" % level)
		_check(run.damage_dealt > _direct_damage(run), "F08 main beam applies live noncritical burning")
		_check(run.hit_log.size() == (2 if level == 3 else 1), "F08 independent level3 pulse")
	elif id == "F03":
		_check(_count_events(run, "rain_impact") == (6 if level == 1 else 8), "F03 exact source drop count")
		_check(run.damage_dealt > 0.0, "F03 real damage")
		_check(run.expired.size() == (1 if level == 3 else 0), "F03 only level3 ground naturally expires")
	elif id == "F04":
		_check(run.hit_log.size() == (9 if level == 1 else 10), "F04 first full interval and finite attacks")
		_check(run.engine.spirits.is_empty() and not run.spirit.active, "F04 source lifetime")
	elif id == "F05":
		_check(run.damage_dealt > 0.0, "F05 moving-zone damage")
		_check(run.expired.size() == 1, "F05 exactly one natural terminal")
		_check(run.expired[0].pos.y <= 7.00001 and run.expired[0].pos.y > 6.9, "F05 movement length separate from level3 end hold")
	elif id == "F06":
		_check(run.hit_log.size() == [8, 12, 13][level-1], "F06 waits interval and includes final tick")
		_check(is_equal_approx(_direct_damage(run), [320.0, 600.0, 1120.0][level-1]), "F06 raw area has no self-buff recursion")
		_check(run.damage_dealt > _direct_damage(run), "F06 live burn is a separate current-attribute damage source")
	elif id == "F07":
		_check(is_equal_approx(run.damage_dealt, [500.0, 756.0, 1100.0][level - 1]), "F07 center plus level3 aftershock budget")
	elif id == "F09":
		_check(is_equal_approx(_direct_damage(run), [60.0, 90.0, 120.0][level-1]), "F09 upgraded raw wave budget")
		_check(run.damage_dealt > _direct_damage(run), "F09 successful wave applies shared burning after its direct damage")
		_check(is_equal_approx(run.actors[0].pos.y, [3.5, 4.2, 4.5][level-1]), "F09 actual push")
		_check(run.actors[0].has("spell_slows") == (level == 3), "F09 slow begins at level3")
	elif id == "F11":
		_check(is_equal_approx(_direct_damage(run), [80.0, 110.0, 140.0][level-1]), "F11 level source direct budget")
		_check(run.hit_log.size() == 1 and run.damage_dealt > _direct_damage(run), "F11 standalone brand damages and applies nonrecursive shared burning")


func _check_passive_synergy():
	for level in range(1, 4):
		var run = _new_run("F02", level)
		_advance(run, 1.0)
		_check(run.casts == 0 and run.hit_log.is_empty(), "F02 never casts or attacks")
		_check(is_equal_approx(run.engine.fire_bonus(), [0.15, 0.30, 0.50][level - 1]), "F02 source fire bonus")
		_check(is_equal_approx(run.engine.crit_multiplier_bonus(), [0.0, 0.10, 0.25][level-1]), "F02 source crit DAMAGE bonus")
	var run = _new_run("F01")
	run.spells.append(run._new_spell("F02"))
	run.spells.append(run._new_spell("F10"))
	_first_cast(run)
	_advance(run, 0.3)
	_check(is_equal_approx(run.spells[0].cooldown, 1.08), "three distinct fire activates cooldown reduction")
	_check(is_equal_approx(run.damage_dealt, 130.0), "mastery and synergy are additive fire bonuses")


func _check_secondary_and_aoe():
	var run = _new_run("F08", 3)
	run.actors.append(_actor(2, Vector2(0, 4)))
	_first_cast(run)
	_check(run.hit_log.size() == 2, "F08 first beam pierces two")
	var start = run.time
	_advance(run, 0.1)
	_check(run.hit_log.size() == 2, "F08 no premature pulse")
	run.player.pos.x = 3.0
	_advance(run, 0.12)
	_check(run.hit_log.size() == 4, "F08 pulse keeps original origin/direction after movement")
	_check(run.hit_log[2].at - start >= 0.2 - 0.00001, "F08 exact secondary delay")
	var bomb = _new_run("F07", 3)
	bomb.actors.append(_actor(2, Vector2(1.9, 2)))
	_first_cast(bomb)
	_advance(bomb, 0.46)
	_check(is_equal_approx(bomb.actors[0].health, 99080.0), "F07 center high damage")
	_check(is_equal_approx(bomb.actors[1].health, 99600.0), "F07 outer lower damage")
	_advance(bomb, 0.61)
	_check(is_equal_approx(bomb.actors[0].health, 98900.0) and is_equal_approx(bomb.actors[1].health, 99420.0), "F07 aftershock equal weak ring damage")
	var priority = _new_run("F07")
	priority.actors[0].health = 1000.0
	priority.actors.append(_actor(2, Vector2(3, 4)))
	_advance(priority, 0.01)
	_check(priority.spells[0].target_id == 2, "F07 prioritizes current highest HP")


func _check_freeze_and_cleanup():
	var run = _new_run("F08", 3)
	_first_cast(run)
	var pending_before = run.engine.pending.duplicate(true)
	var time_before = run.time
	run.set_paused(true)
	_advance(run, 3.0)
	_check(is_equal_approx(run.time, time_before) and run.engine.pending == pending_before, "pause freezes pending pulse")
	run.set_paused(false)
	_advance(run, 0.21)
	_check(run.hit_log.size() == 2, "resume has one pulse without catch-up")
	var field = _new_run("F06", 3)
	_first_cast(field)
	field.engine.stop_room()
	_check(field.engine.zones.is_empty() and field.engine.pending.is_empty() and field.engine.spirits.is_empty(), "room stop removes all combat effects")
	_check(field.expired.is_empty(), "early room cleanup cannot trigger terminal explosion")


func _check_field_grace_and_replacement():
	var run = _new_run("F06", 3)
	_first_cast(run)
	_advance(run, 0.1)
	_check(is_equal_approx(run.engine.field_attack_bonus(), 0.2), "field gives source attack buff inside")
	run.player.pos = Vector2(7, 0)
	_advance(run, 1.0)
	_check(is_equal_approx(run.engine.field_attack_bonus(), 0.2), "level3 grace after leaving")
	_advance(run, 0.6)
	_check(is_zero_approx(run.engine.field_attack_bonus()), "level3 grace expires")
	run.player.pos = Vector2.ZERO
	_check(run.engine.cast_extra(run, "F06"), "extra field valid")
	_check(run.engine.zones.size() == 1, "replacement still one field")
	_check(run.expired.is_empty(), "replacement not natural expiry")


func _check_spirits():
	var run = _new_run("F04", 3)
	_first_cast(run)
	_advance(run, 0.5)
	var remaining = run.engine.spirits[0].remaining
	var attack = run.engine.spirits[0].attack_remaining
	_check(not run.engine.cast_extra(run, "F04"), "full summon cannot refresh")
	_check(is_equal_approx(run.engine.spirits[0].remaining, remaining) and is_equal_approx(run.engine.spirits[0].attack_remaining, attack), "invalid extra summon preserves timers")
	var count = run.hit_log.size()
	_check(run.engine.fire_spirit_sync(run, run.actors[0], 1.2), "spirit sync real beam")
	_check(run.hit_log.size() == count + 1, "sync causes genuine damage")
	_check(is_equal_approx(run.engine.spirits[0].attack_remaining, attack), "sync does not reset normal interval")


func _check_shield_boundaries():
	var run = _new_run("F10", 3)
	_advance(run, 2.0)
	_check(run.casts == 0 and is_zero_approx(run.spells[0].remaining), "full shield remains ready")
	run.player.health = 120.0
	run.player.shield = 90.0
	_first_cast(run)
	_check(is_equal_approx(run.player.shield, 100.0) and is_equal_approx(run.player.health, 120.0), "shield caps without healing injured health")
	var cancel = _new_run("F10")
	cancel.player.shield = 0.0
	_advance(cancel, 0.1)
	cancel.player.shield = cancel.player.max_shield
	_advance(cancel, 0.5)
	_check(cancel.casts == 0 and is_zero_approx(cancel.spells[0].remaining), "shield rechecks at release and cancels free")
	cancel.player.shield = 0.0
	cancel.actors.clear()
	_advance(cancel, 1.0)
	_check(cancel.casts == 0, "shield requires living enemy")


func _check_wall_and_extra():
	var run = _new_run("F08", 3)
	run.actors = [_actor(1, Vector2(0, 2)), _actor(2, Vector2(0, 5))]
	run.blocks.append({"center": Vector2(0, 3.5), "size": Vector2(3, 0.5)})
	_first_cast(run)
	_advance(run, 0.3)
	_check(run.actors[1].health == 100000.0, "beam and pulse cannot cross solid cover")
	var extra = _new_run("F08", 3)
	extra.spells[0].remaining = 5.0
	_check(extra.engine.cast_extra(extra, "F08", {}, 0.5), "extra casts while natural CD running")
	_check(extra.casts == 0 and extra.natural_casts.is_empty() and is_equal_approx(extra.spells[0].remaining, 5.0), "extra does not alter natural count or CD")
	_advance(extra, 0.3)
	_check(is_equal_approx(_direct_damage(extra), 210.0), "extra includes level3 pulse at scale")
	var wave = _new_run("F09", 3)
	wave.player.pos = Vector2(8.4, 0)
	wave.actors[0].pos = Vector2(8.6, 0)
	wave.actors[0].previous = wave.actors[0].pos
	_first_cast(wave)
	_check(wave._body_clear(wave.actors[0].pos, 0.3), "wave push remains on valid floor")
	var immune = _new_run("F09", 3)
	immune.actors[0].push_resistance = 1.0
	_first_cast(immune)
	_check(immune.actors[0].pos == Vector2(0, 2) and immune.damage_dealt == 120.0, "push immune enemy still takes damage")


func _check_same_source_overlap():
	var run = _new_run("F05", 2)
	var context = {"cast_id": 1, "natural": true, "spell_id": "F05", "kind": "vortex", "damage_scale": 1.0, "field_bonus": 0.0}
	run.spells[0].remaining = 1000.0
	var first = run.engine._zone("rain_ground", "F05", Vector2(0, 2), 2.0, 2.0, 0.5, 0.6, context)
	var second = first.duplicate(true)
	second.tick_remaining = 0.7
	run.engine.zones = [first, second]
	_advance(run, 2.0)
	_check(run.hit_log.size() == 4, "same-source offset zones cannot increase tick frequency")
	_check(is_equal_approx(run.damage_dealt, 240.0), "same-source overlap bounded damage budget")


func _check(condition: bool, message: String):
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)
