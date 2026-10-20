extends SceneTree
## Read-only isolated current-core measurement, not a route or encounter simulation.
## Static infinite-health anchors, no AI/spawn/walls, zero crit for coefficient fidelity.

const SOURCE_PATHS = [
	"data/balance_candidates/first_run_v1.json", "data/first_room_runtime.json",
	"data/route_spell_runtime.json", "data/route_artifact_runtime.json",
	"data/balance_candidates/fire_artifacts_v1.json", "data/generic_artifacts_v1.json",
	"scripts/core/first_room_run.gd", "scripts/core/courtyard_route_run.gd",
	"scripts/core/route_spell_combat.gd", "scripts/core/route_artifacts.gd",
	"scripts/core/route_generic_items.gd"]
const RETAINED_IDS = ["F01", "F02", "F03", "F05", "F06", "F07", "F08", "F09", "F10"]
const OUT = "D:/demo/build/qa/formal-fire-20261018"
var checks: int = 0
var failures: Array = []

class Fixture extends "res://scripts/core/courtyard_route_run.gd":
	var additional_cdr: float = 0.0
	var hit_log: Array = []
	var cast_log: Array = []
	var shield_total: float = 0.0
	func artifact_cooldown_reduction() -> float:
		return super.artifact_cooldown_reduction() + additional_cdr
	func resolve_spell_hit(actor: Dictionary, coefficient: float, context: Dictionary) -> Dictionary:
		var result: Dictionary = super.resolve_spell_hit(actor, coefficient, context)
		hit_log.append({"at": time, "spell_id": context.get("spell_id", ""), "coefficient": coefficient,
			"kind": context.get("kind", ""), "natural": context.get("natural", false),
			"cast_id": context.get("cast_id", -1), "actor_id": actor.id, "damage": result.damage})
		return result
	func on_spell_cast(spell: Dictionary, target: Dictionary, context: Dictionary):
		cast_log.append({"at": time, "spell_id": spell.id, "natural": context.natural})
		super.on_spell_cast(spell, target, context)
	func restore_player_shield(amount: float, source: String) -> float:
		var restored: float = super.restore_player_shield(amount, source)
		shield_total += restored
		return restored


func _initialize():
	call_deferred("execute")


func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures.append(label)


func hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in SOURCE_PATHS:
		result[path] = FileAccess.get_sha256("res://" + path)
	return result


func fixture(id: String, level: int, reduction: float, scene: String) -> Fixture:
	var run = Fixture.new()
	check(run.configure({}, 20261018).ok, "configure current Route " + id)
	run.phase = "combat"
	run.time = 0.0
	run.blocks.clear()
	run.player.pos = Vector2.ZERO
	run.player.previous = Vector2.ZERO
	run.player.crit_rate = 0.0
	run.player.shield = 0.0
	run.additional_cdr = reduction
	run.spells.clear()
	var spell: Dictionary = run._new_spell(id)
	spell.level = level
	run._refresh_spell(spell)
	run.spells.append(spell)
	run.actors.clear()
	var points = [Vector2(0.0, 2.0)]
	if scene == "dense_six_anchors":
		points = [Vector2(0.0, 2.0), Vector2(0.15, 2.0), Vector2(-0.15, 2.0),
			Vector2(0.0, 1.85), Vector2(0.1, 2.15), Vector2(-0.1, 2.15)]
	for index in points.size():
		var pos: Vector2 = points[index]
		run.actors.append({"id": index + 1, "type": "M01", "pos": pos, "previous": pos,
			"anchor": pos, "health": 1000000000.0, "max_health": 1000000000.0,
			"radius": 0.3, "phase": "chase", "push_resistance": 0.0})
	return run


func measure(id: String, level: int, reduction: float, scene: String, item_ids: Array = []) -> Array:
	var run = fixture(id, level, reduction, scene)
	for item_id in item_ids:
		run._artifact_combat._owned.append(item_id)
		run._artifact_combat.apply_acquisition(run, item_id)
	var rows: Array = []
	for tick in 7200:
		run.time = float(tick + 1) / 120.0
		# Controlled anchors/sink deliberately cancel knockback and keep shield deficit.
		# This quantifies a potential, not damage dealt or restoration during real movement.
		for actor in run.actors:
			actor.pos = actor.anchor
			actor.previous = actor.pos
		run.player.shield = 0.0
		run._artifact_combat.before_combat_tick(run, 1.0 / 120.0, Vector2.ZERO)
		run._update_spells(1.0 / 120.0)
		run.effects.clear()
		if tick in [3599, 7199]:
			var times: Array = []
			for cast in run.cast_log:
				times.append(cast.at)
			rows.append({"spell_id": id, "level": level, "scene": scene, "horizon": run.time,
				"extra_cdr_override": reduction, "items": item_ids, "cast_count": run.casts, "hit_count": run.hits,
				"g03_bursts": run._artifact_combat._end_casts.size(),
				"damage_zero_crit": run.damage_dealt, "damage_per_second_zero_crit": run.damage_dealt / run.time,
				"shield_potential": run.shield_total, "casts_at": times, "first_hit": run.hit_log[0].at if not run.hit_log.is_empty() else null,
				"current_stats": run.get_spell_stats(run.spells[0]), "effective_cd": run.spells[0].cooldown,
				"hit_log": run.hit_log.duplicate(true)})
	check(run.phase == "combat" and run.kills == 0, "no fixture enemy dies " + id)
	check(run.spells.size() == 1, "single ownership excludes three-fire synergy " + id)
	if id == "F02":
		check(run.casts == 0 and run.hits == 0, "passive no casts/damage")
	if id == "F10":
		check(run.hits == 0 and run.shield_total > 0.0, "shield only, actual restore wrapper")
	if id in ["F01", "F07", "F08"]:
		var first: Array = run.hit_log.filter(func(row): return int(row.cast_id) == 1 and int(row.actor_id) == 1)
		var sum: float = 0.0
		for row in first:
			sum += float(row.damage)
		var expected: Dictionary = {"F01": [100.0, 135.0, 210.0], "F07": [500.0, 650.0, 800.0], "F08": [160.0, 220.0, 330.0]}
		check(absf(sum - float(expected[id][level - 1])) < 0.001, "hand-check first-cast budget " + id)
	return rows


func execute():
	var before: Dictionary = hashes()
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance_candidates/first_run_v1.json"))
	var cases: Array = []
	for id in RETAINED_IDS:
		for level in range(1, 4):
			for reduction in [0.0, 0.6]:
				for scene in ["single_static_anchor", "dense_six_anchors"]:
					cases.append_array(measure(id, level, reduction, scene))
	for level in range(1, 4):
		for reduction in [0.0, 0.6]:
			cases.append_array(measure("F06", level, reduction, "single_static_anchor", ["G03"]))
	var after: Dictionary = hashes()
	check(before == after, "all current runtime/data sources unchanged")
	var result = {"model_version": "formal-fire-current-core-bridge-v1", "engine": Engine.get_version_info(),
		"source_hashes_before": before, "source_hashes_after": after, "source_stable": before == after,
		"checks": checks, "failures": failures, "player_defaults": base.player, "limits": base.limits,
		"fire_synergy": base.fire_synergy, "retained_current_spell_ids": RETAINED_IDS,
		"cases": cases, "scope": "actual current Route/Spell/Artifact core APIs, static anchored isolated fixtures; no runtime proposal implemented",
		"omissions": ["No full step/AI/route/spawns, walls or survival", "No human accuracy or movement", "No targets die, no overkill",
			"Zero critical rate for formula checking, real default 5% preserved separately", "60% CDR is an explicit fixture override, not a currently obtainable equipment assertion",
			"Each ID alone; no three-fire synergy", "Shield deficit artificially reset every tick; potential only", "Anchors reset push every tick", "Rain uses one fixed seed; not population expectation"]}
	DirAccess.make_dir_recursive_absolute(OUT)
	var file = FileAccess.open(OUT + "/runtime_baseline.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	print("FORMAL_FIRE_BASELINE cases=", cases.size(), " checks=", checks, " failures=", failures.size())
	for failure in failures:
		print("FAIL ", failure)
	quit(0 if failures.is_empty() else 1)
