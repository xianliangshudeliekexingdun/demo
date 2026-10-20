extends SceneTree
## Bounded native-core tuning model, explicitly outside the shipped game.
const Route = preload("res://scripts/core/courtyard_route_run.gd")
const ROOT = "res://tools/balance/spell_growth/"
var parameters: Dictionary
var rows: Array = []
var checks := 0
var failures: Array = []
var baseline := false
var gear := false
var output := "res://build/qa/spell-growth-implementation-20261020/model-current.json"
var school_filter := ""
var scale := 1.0

class Harness extends "res://scripts/core/courtyard_route_run.gd":
	var shield_recovered := 0.0
	func _reserve_batch(): pass
	func _update_spawn(_dt: float): pass
	func _check_clear(): pass
	func _update_enemies(dt: float):
		advance_ice_control(dt)
		for actor in actors: actor.previous = actor.pos
	func restore_player_shield(amount: float, source: String) -> float:
		var actual: float = super.restore_player_shield(amount, source)
		shield_recovered += actual
		return actual

func read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message)

func _initialize(): call_deferred("run")

func fixture(ids: Array, level: int, seed_value: int, pattern: String, extra: Dictionary = {}):
	var b = Harness.new()
	check(b.configure({"player": {"attack": parameters.attack, "crit_rate": float(extra.get("critical_rate", parameters.critical_rate))}}, seed_value).ok, "native source configures")
	if baseline:
		b._base.spells = read(ROOT + "baseline/first_run_v1.json").spells.duplicate(true)
		b._ice_source = read(ROOT + "baseline/ice_spells_v1.json")
		b._base.spells.merge(b._ice_source.spells.duplicate(true), true)
		b._base.ice_mechanics = b._ice_source.mechanics.duplicate(true)
		check(b._spell_combat.configure(b).ok, "frozen baseline spell configuration")
		if gear and not bool(extra.get("without_gear", false)):
			for file in ["fire_artifacts_v1.json", "ice_artifacts_v1.json"]:
				for id in read(ROOT + "baseline/" + file).items:
					var item: Dictionary = read(ROOT + "baseline/" + file).items[id]
					if str(item.get("scope", "")) in ["fire", "ice"] and bool(item.get("active", true)):
						b._artifact_combat._items[id] = item.duplicate(true)
						b._artifact_combat._owned.append(id)
	b.phase = "combat"
	b.actors.clear()
	b.spells.clear()
	b.blocks.clear()
	b.spawn_warnings.clear()
	b.player.attack = float(parameters.attack)
	b.player.fire_bonus = 0.0
	b.player.crit_multiplier = 2.0
	b.player.crit_rate = float(extra.get("critical_rate", parameters.critical_rate))
	b.player.pos = Vector2.ZERO
	b.player.previous = b.player.pos
	b.player.gem_cdr = float(extra.get("cdr", 0.0))
	for id in ids:
		var spell: Dictionary = b._new_spell(str(id))
		spell.level = level
		b._refresh_spell(spell)
		b.spells.append(spell)
	if scale != 1.0:
		for id in b._base.spells:
			for tier in b._base.spells[id].get("levels", []):
				for key in ["coefficient", "secondary", "outer", "aftershock", "shatter_coefficient", "shard_coefficient", "following_coefficient", "ground_coefficient"]:
					if tier.has(key): tier[key] = float(tier[key]) * scale
	for point in parameters.patterns[pattern]:
		var actor: Dictionary = b._enemy_combat.make_actor(b, "M01", Vector2(point[0], point[1]), b.actors.size() + 1, 59)
		actor.health = float(parameters.target_health)
		actor.max_health = actor.health
		b.actors.append(actor)
	return b

func measure(ids: Array, level: int, seed_value: int, pattern: String, duration: float, extra: Dictionary = {}) -> Dictionary:
	var b = fixture(ids, level, seed_value, pattern, extra)
	# Passives are evaluated with one fixed first-level school attack.
	if ids == ["F02"] or ids == ["I10"]:
		b.spells.append(b._new_spell("F01" if ids == ["F02"] else "I01"))
	var armor := 0.0
	for tick in roundi(duration * 120.0):
		b.player.shield = maxf(0.0, float(b.player.shield) - 10.0 / 120.0)
		b.step(1.0 / 120.0)
		if b._spell_combat.ice.defense_bonus() > 0.0: armor += 1.0 / 120.0
	var damage: float = b.damage_dealt
	check(is_finite(damage) and damage >= 0.0 and b.phase == "combat" and b.time < duration + 0.01, "bounded native encounter")
	return {"ids": ids, "level": level, "seed": seed_value, "pattern": pattern, "duration": duration, "damage": damage,
		"dps": damage / duration, "casts": b.casts, "shield_recovered": b.shield_recovered, "armor_uptime": armor / duration,
		"conditions": extra, "scale": scale}

func run():
	parameters = read(ROOT + "scenarios.json")
	for arg in OS.get_cmdline_user_args():
		if arg == "--baseline": baseline = true
		elif arg == "--old-gear": gear = true
		elif str(arg).begins_with("--out=res://build/qa/"): output = str(arg).trim_prefix("--out=")
		elif str(arg).begins_with("--school="): school_filter = str(arg).trim_prefix("--school=")
		elif str(arg).begins_with("--scale="): scale = float(str(arg).trim_prefix("--scale="))
	# Hand-known single cast: 100 primary plus eight 25-point burn ticks.
	var known = fixture(["F01"], 1, 7, "single", {"without_gear": true})
	var spell: Dictionary = known.spells[0]
	known._spell_combat._cast(known, spell, known.get_spell_stats(spell), known.actors[0], true, 1.0)
	spell.remaining = 9999.0
	for tick in 540: known.step(1.0 / 120.0)
	print("Known cast damage: ", known.damage_dealt)
	check(absf(known.damage_dealt - (100.0 * scale + 200.0)) < 0.01, "known F01 single direct plus eight burn ticks")
	for school in ["fire", "ice"]:
		if not school_filter.is_empty() and school_filter != school: continue
		var source: Dictionary = known._base.spells
		for id in source:
			if str(source[id].get("school", "")) != school or not bool(source[id].get("active", true)): continue
			for pattern in parameters.patterns:
				for level in parameters.single_levels:
					rows.append(measure([id], int(level), int(parameters.seeds[0]), str(pattern), float(parameters.single_seconds)))
	if school_filter.is_empty():
		for name in parameters.builds:
			for level in parameters.build_levels:
				for pattern in parameters.patterns:
					for seed_value in parameters.seeds:
						var row := measure(parameters.builds[name], int(level), int(seed_value), str(pattern), float(parameters.build_seconds))
						row["build"] = name
						rows.append(row)
			for condition in parameters.extremes:
				var row := measure(parameters.builds[name], 3, int(parameters.seeds[0]), "group", float(parameters.build_seconds), condition)
				row["build"] = name
				rows.append(row)
	var result := {"model_version": parameters.model_version, "checks": checks, "failures": failures.size(), "details": failures,
		"baseline": baseline, "old_gear": gear, "parameters": parameters, "rows": rows, "scope": parameters.scope,
		"source_hashes": {}}
	for file in ["scripts/core/route_spell_combat.gd", "scripts/core/route_ice_combat.gd", "scripts/core/route_fire_status.gd", "data/balance_candidates/first_run_v1.json", "data/ice_spells_v1.json", "data/route_spell_growth.json", "scripts/core/route_spell_growth.gd", "scripts/core/route_ice_growth.gd", "scripts/core/courtyard_route_run.gd", "scripts/core/route_artifacts.gd"]:
		result.source_hashes[file] = FileAccess.get_sha256("res://" + file) if FileAccess.file_exists("res://" + file) else "absent"
	result["frozen_source_hashes"] = {}
	for file in ["first_run_v1.json", "ice_spells_v1.json", "fire_artifacts_v1.json", "ice_artifacts_v1.json"]:
		result.frozen_source_hashes[file] = FileAccess.get_sha256(ROOT + "baseline/" + file)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("SPELL GROWTH MODEL: %d checks; %d failures; %d scenarios" % [checks, failures.size(), rows.size()])
	quit(1 if not failures.is_empty() else 0)
