extends SceneTree
## Production wind rules, isolated from AI/spawning/natural-route play.

const IDS = ["W01", "W02", "W03", "W04", "W05", "W06", "W07", "W08", "W09", "W10"]
var checks: int = 0
var failures: Array = []
var groups: Array = []

class Fixture extends "res://scripts/core/courtyard_route_run.gd":
	var hit_log: Array = []
	var contexts: Array = []
	var natural_casts: Array = []
	func _reserve_batch(): pass
	func _update_spawn(_dt: float): pass
	func _check_clear(): pass
	func _update_enemies(dt: float):
		advance_ice_control(dt)
		_spell_combat.wind.record_player_motion(self, player.previous, player.pos, dt)
		for actor in actors: actor.previous = actor.pos
	func damage_enemy(actor: Dictionary, amount: float, source: String = ""):
		var before: float = float(actor.health)
		super.damage_enemy(actor, amount, source)
		hit_log.append({"at": time, "actor": int(actor.id), "source": source, "amount": before - maxf(0.0, float(actor.health))})
	func resolve_spell_hit(actor: Dictionary, coefficient: float, context: Dictionary) -> Dictionary:
		var result: Dictionary = super.resolve_spell_hit(actor, coefficient, context)
		contexts.append(context.duplicate(true))
		return result
	func on_spell_cast(spell: Dictionary, target: Dictionary, context: Dictionary):
		natural_casts.append(context.duplicate(true))
		super.on_spell_cast(spell, target, context)


func _initialize(): call_deferred("execute")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error("Formal wind: " + label)
func near(a: float, b: float, tolerance: float = 0.003) -> bool: return absf(a - b) <= tolerance
func enemy(id: int = 1, pos: Vector2 = Vector2(0, 2), kind: String = "M01") -> Dictionary:
	return {"id": id, "type": kind, "type_id": kind, "pos": pos, "previous": pos, "health": 1000000.0, "max_health": 1000000.0, "radius": 0.3, "phase": "chase", "push_resistance": 0.0, "spell_slows": {}, "slow_remaining": 0.0, "slow_multiplier": 1.0}
func fresh(ids: Array = ["W01"], level: int = 1, core: String = ""):
	var run = Fixture.new()
	var configured: Dictionary = run.configure({"route_school": "wind", "gem_core": core}, 20261021)
	check(bool(configured.get("ok", false)), "wind production configure")
	if not bool(configured.get("ok", false)): return run
	check(run.choose_initial("W01"), "wind production initial choice")
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
func advance(run, seconds: float, move: Vector2 = Vector2.ZERO) -> void:
	for _tick in roundi(seconds * 120.0): run.step(1.0 / 120.0, move)
func release(run, id: String, natural: bool = true) -> void:
	var spell: Dictionary = run._owned_spell(id)
	var stats: Dictionary = run.get_spell_stats(spell)
	var target: Dictionary = run._spell_combat.legal_target(run, spell, stats)
	check(not target.is_empty(), "wind legal target " + id)
	if target.is_empty(): return
	spell.locked_pos = target.pos
	run._spell_combat._cast(run, spell, stats, target, natural, 1.0)
	stop_natural(run)
func damage(run, actor_id: int = -1) -> float:
	var result: float = 0.0
	for hit in run.hit_log:
		if actor_id < 0 or int(hit.actor) == actor_id: result += float(hit.amount)
	return result
func count_hits(run, actor_id: int = -1) -> int:
	var result: int = 0
	for hit in run.hit_log:
		if actor_id < 0 or int(hit.actor) == actor_id: result += 1
	return result
func incoming(run) -> void:
	run._enemy_combat.enemy_projectiles = [{"id": 1, "pos": Vector2(0, 4), "previous": Vector2(0, 4), "direction": Vector2(0, -1), "speed": 4.0, "radius": 0.1, "damage": 1.0, "remaining": 8.0, "range_remaining": 30.0, "source_id": 1}]


func data_and_smoke() -> void:
	var run = fresh()
	var wind = run._spell_combat.wind
	check(wind.source_spells.size() == 10, "exactly ten wind spells")
	for id in IDS:
		var source: Dictionary = wind.source_spells[id]
		check(str(source.school) == "wind", id + " school")
		check(source.levels.size() == 3, id + " three levels")
		for level in range(1, 4):
			check(source.levels[level - 1].has("cooldown"), id + " level cooldown")
			var battle = fresh([id], level)
			if id == "W09": incoming(battle)
			if id == "W10":
				check(battle._spell_combat.wind.legal_target(battle, battle.spells[0], battle.get_spell_stats(battle.spells[0])).is_empty(), "mastery has no active loop")
			else:
				release(battle, id)
				if id == "W08": advance(battle, 0.8, Vector2(0, 1))
				advance(battle, 4.0)
				check(id in ["W08", "W09"] or damage(battle) > 0.0, id + " actual level " + str(level) + " damage")
				check(battle.natural_casts.size() == 1, id + " one natural action")
	groups.append("data, thirty levels and independent starters")


func blades_and_return() -> void:
	var run = fresh(["W01"], 1)
	run.actors.clear()
	for i in range(1, 8): run.actors.append(enemy(i, Vector2(0, float(i))))
	release(run, "W01")
	advance(run, 1.0)
	check(near(damage(run, 1), 120.0) and near(damage(run, 2), 96.0) and near(damage(run, 3), 76.8), "wind blade collision-order falloff")
	check(count_hits(run) == 3, "wind blade target cap")
	run = fresh(["W01"], 3)
	run.actors.clear()
	for i in range(1, 8): run.actors.append(enemy(i, Vector2(0, float(i))))
	release(run, "W01")
	advance(run, 1.0)
	check(count_hits(run) == 6 and near(damage(run), 990.0), "third wind blade six distinct equal hits")
	for level in [1, 2, 3]:
		run = fresh(["W02"], level)
		release(run, "W02")
		advance(run, 2.6)
		var expected: float = [190.0, 250.0, 300.0][level - 1]
		check(near(damage(run), expected) and count_hits(run) == 2, "wind ring two true legs level " + str(level))
	run = fresh(["W02"], 3)
	release(run, "W02")
	advance(run, 0.7)
	check(not run._spell_combat.wind.projectiles.is_empty(), "ring returns after range")
	var locked: Vector2 = run._spell_combat.wind.projectiles[0].return_to
	advance(run, 0.15, Vector2(1, 0))
	check(run._spell_combat.wind.projectiles.is_empty() or run._spell_combat.wind.projectiles[0].return_to == locked, "ring return destination never follows later movement")
	groups.append("finite physical blade and one-lock return")


func arrow_and_wings() -> void:
	for distance in [3.0, 5.0]:
		var run = fresh(["W03"], 3)
		run.actors = [enemy(1, Vector2(0, distance))]
		release(run, "W03")
		advance(run, 1.2)
		check(near(damage(run), 190.0 if distance < 4.0 else 256.5), "wind arrow actual flown path " + str(distance))
	var run = fresh(["W03"], 2)
	release(run, "W03")
	run.actors[0].pos = Vector2(5, -2)
	advance(run, 0.2)
	if not run._spell_combat.wind.projectiles.is_empty():
		check(float(run._spell_combat.wind.projectiles[0].turned) <= deg_to_rad(24.0) + 0.001, "arrow turn rate finite")
	for level in [1, 2, 3]:
		run = fresh(["W07"], level)
		run.actors = [enemy(1, Vector2(0, 3))]
		release(run, "W07")
		advance(run, 1.0)
		check(count_hits(run) == (3 if level == 3 else 2), "same cast actual double wing and one cross " + str(level))
		check(near(damage(run), [210.0, 280.0, 390.0][level - 1]), "wing coefficients " + str(level))
	groups.append("bounded steering, path reward and same-cast double wing")


func scatter_vortex_vacuum() -> void:
	for kind in ["M01", "EL01", "EL02_GUARD"]:
		var run = fresh(["W04"], 3)
		run.actors = [enemy(1, Vector2(0, 2), kind)]
		release(run, "W04")
		var expected: float = 2.5 * ({"M01": 1.0, "EL01": 0.35, "EL02_GUARD": 0.0}[kind])
		check(near(run.actors[0].pos.y - 2.0, expected), "wind control distance once " + kind)
		check(near(run._spell_combat.wind.movement_multiplier(run.actors[0]), 1.0 - ({"M01": 0.3, "EL01": 0.25, "EL02_GUARD": 0.15}[kind])), "wind shared slow cap " + kind)
		check(near(damage(run), 130.0), "fixed enemies retain wind damage " + kind)
	for level in [1, 2, 3]:
		var run = fresh(["W05"], level)
		release(run, "W05")
		advance(run, 0.49)
		check(count_hits(run) == 0, "vortex first tick waits .5")
		advance(run, 3.1)
		check(count_hits(run) == (6 if level == 3 else 4), "vortex includes exact expiry tick " + str(level))
		check(near(damage(run), [100.0, 140.0, 210.0][level - 1]), "vortex finite damage " + str(level))
	var run = fresh(["W05"], 3)
	release(run, "W05")
	advance(run, 0.5)
	release(run, "W05", false)
	check(run._spell_combat.wind.zones.size() == 1, "vortex extra replaces unique object")
	advance(run, 3.1)
	check(count_hits(run) == 7, "vortex replacement does not bank canceled ticks")
	run = fresh(["W06"], 3)
	release(run, "W06")
	advance(run, 0.24)
	check(count_hits(run) == 0, "vacuum has actual delay")
	advance(run, 0.4)
	check(count_hits(run) == 2 and near(damage(run), 620.0), "vacuum center bonus and one followup")
	check(run.contexts.size() == 1, "vacuum followup avoids direct on_hit")
	groups.append("control resistance, unique vortex and derived vacuum")


func paths_mastery_guard() -> void:
	var run = fresh(["W08"], 3)
	run.actors = [enemy(1, Vector2(0, 0.9))]
	release(run, "W08")
	advance(run, 0.6, Vector2(0, 1))
	advance(run, 2.0)
	check(count_hits(run) == 4 and near(damage(run), 240.0), "path same enemy cast budget and shared gate")
	release(run, "W08", false)
	check(run._spell_combat.wind.path_segments.is_empty(), "path extra removes every old segment")
	advance(run, 0.4, Vector2(0, -1))
	advance(run, 1.0)
	check(count_hits(run) == 4, "path replacement cannot reset shared six second history")
	run = fresh(["W08"], 1)
	release(run, "W08")
	advance(run, 1.0)
	check(run._spell_combat.wind.path_segments.is_empty() and count_hits(run) == 0, "stationary path never creates damage")
	run = fresh(["W10"], 3)
	check(near(run._spell_combat.wind.school_bonus(run), 0.0), "mastery stationary inactive")
	advance(run, 0.3, Vector2(1, 0))
	check(run._spell_combat.wind.school_bonus(run) >= 0.349, "mastery actual movement active")
	advance(run, 1.1)
	check(run._spell_combat.wind.school_bonus(run) >= 0.349, "mastery grace after rolling condition loss")
	advance(run, 0.6)
	check(near(run._spell_combat.wind.school_bonus(run), 0.0), "mastery grace expires")
	run = fresh(["W01", "W02", "W10"], 3)
	check(near(run._spell_combat.wind.school_bonus(run), 0.15) and near(run._spell_combat.wind.cooldown_bonus(run), 0.1), "distinct wind resonance")
	run = fresh(["W09"], 3)
	var stats: Dictionary = run.get_spell_stats(run.spells[0])
	check(run._spell_combat.wind.legal_target(run, run.spells[0], stats).is_empty(), "guard waits without incoming projectile")
	incoming(run)
	release(run, "W09")
	var zone: Dictionary = run._spell_combat.wind.zones[0]
	check(near(run._spell_combat.wind.projectile_speed_multiplier(run, zone.pos), 0.5), "guard slows only inside fixed strip")
	check(near(run._spell_combat.wind.projectile_speed_multiplier(run, Vector2(3, -2)), 1.0), "guard outside full speed")
	var speed: float = float(run._enemy_combat.enemy_projectiles[0].speed)
	advance(run, 0.1, Vector2(1, 0))
	check(run._spell_combat.wind.zones[0].pos == zone.pos, "guard never follows player")
	check(near(run._enemy_combat.enemy_projectiles[0].speed, speed), "guard does not mutate stored original projectile speed")
	check(count_hits(run) == 0, "guard has no enemy damage")
	groups.append("real motion, finite shared paths, mastery grace and projectile-only guard")


func lifecycle_and_echo() -> void:
	var run = fresh(["W01", "W05", "W08"], 3)
	release(run, "W05")
	release(run, "W08")
	advance(run, 0.2, Vector2(1, 0))
	var snapshot: Dictionary = run._spell_combat.wind.get_snapshot(run)
	var at: float = run._spell_combat.wind.clock
	run.paused = true
	advance(run, 2.0)
	check(near(run._spell_combat.wind.clock, at), "pause freezes wind clock")
	check(run._spell_combat.wind.get_snapshot(run) == snapshot, "pause preserves all wind objects")
	run.paused = false
	run._spell_combat.wind.stop_room()
	var cleared: Dictionary = run._spell_combat.wind.get_snapshot(run)
	for key in ["wind_projectiles", "wind_zones", "wind_pending", "wind_path_segments", "wind_states"]: check(cleared[key].is_empty(), "room stop clears " + key)
	check(cleared.wind_recording.is_empty() and near(cleared.wind_recent_path, 0.0), "room stop clears path ledgers")
	run = fresh(["W01"], 1, "echo")
	run.actors = [enemy(1, Vector2(0, 2)), enemy(2, Vector2(0, 3)), enemy(3, Vector2(0, 4))]
	release(run, "W01")
	advance(run, 1.0)
	check(damage(run) > 292.8, "wind echo uses production path geometry")
	check(run.natural_casts.size() == 1, "echo never adds a natural wind action")
	groups.append("pause, room cleanup and production echo compatibility")


func execute() -> void:
	data_and_smoke()
	blades_and_return()
	arrow_and_wings()
	scatter_vortex_vacuum()
	paths_mastery_guard()
	lifecycle_and_echo()
	var result: Dictionary = {"version": "formal-wind-implementation-20261021", "checks": checks, "failed": failures.size(), "failures": failures, "groups": groups, "scope": "production core controlled fixtures; no interactive/natural route/performance/export"}
	var out: String = "res://build/qa/formal-schools-current/wind"
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--qa-out=res://build/qa/") and not str(arg).contains(".."):
			out = str(arg).trim_prefix("--qa-out=")
	DirAccess.make_dir_recursive_absolute(out)
	var file = FileAccess.open(out + "/results.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(result, "  "))
	print("Formal wind: %d checks / %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
