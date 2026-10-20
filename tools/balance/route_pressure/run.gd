extends SceneTree
## Persistent native tuning harness. No model approximates damage or enemy AI.
const Route = preload("res://scripts/core/courtyard_route_run.gd")
const Policy = preload("res://tests/route_rebalance_tests.gd")
const SCENARIOS := "res://tools/balance/route_pressure/scenarios.json"
var config: Dictionary = {}
var results: Array = []
var runtime_snapshot: Dictionary = {}
var core_sha256: String = ""
var enemy_override: Dictionary = {}

class Perception extends RefCounted:
	var core
	var vision: float = 30.0
	var phase: String:
		get: return core.phase
	var time: float:
		get: return core.time
	var room_revision: int:
		get: return core.room_revision
	var player: Dictionary:
		get: return core.player
	var portal: Dictionary:
		get: return core.portal
	var actors: Array:
		get: return core.actors
	var room_size: Vector2:
		get: return core.room_size
	func get_snapshot() -> Dictionary:
		var state: Dictionary = core.get_snapshot()
		state.enemy_projectiles = state.get("enemy_projectiles", []).filter(func(projectile): return projectile.pos.distance_to(core.player.pos) <= vision)
		return state
	func move_body(from: Vector2, displacement: Vector2, radius: float) -> Vector2:
		return core.move_body(from, displacement, radius)
	func _chase_position(from: Vector2, target: Vector2, distance: float, radius: float) -> Vector2:
		return core._chase_position(from, target, distance, radius)
	func _first_block_contact(from: Vector2, to: Vector2, radius: float) -> float:
		return core._first_block_contact(from, to, radius)
	func segment_circle_time(from: Vector2, to: Vector2, center: Vector2, radius: float) -> float:
		return core.segment_circle_time(from, to, center, radius)


func _initialize():
	config = JSON.parse_string(FileAccess.get_file_as_string(SCENARIOS))
	runtime_snapshot = JSON.parse_string(FileAccess.get_file_as_string("res://data/route_enemy_runtime.json"))
	core_sha256 = FileAccess.get_sha256("res://scripts/core/courtyard_route_run.gd")
	var args: Array = OS.get_cmdline_user_args()
	var label := str(args[0]) if not args.is_empty() else "selected"
	var mode := str(args[1]) if args.size() > 1 else "quick"
	if args.size() > 2 and str(args[2]) == "baseline":
		enemy_override = JSON.parse_string(FileAccess.get_file_as_string("res://build/qa/route-pressure-20261017/baseline_enemy_runtime.json"))
		var teaching: Dictionary = runtime_snapshot.stat_stages[0].duplicate(true)
		teaching.id = "replayed_baseline_all_rooms"
		teaching.to = 15
		enemy_override["stat_stages"] = [teaching]
		runtime_snapshot = enemy_override.duplicate(true)
	var comprehensive := mode == "full" or mode.begins_with("profile:")
	var profiles: Array = ["precise", "ordinary", "short_view"] if mode == "full" else ([mode.get_slice(":", 1)] if mode.begins_with("profile:") else ([mode] if config.profiles.has(mode) else ["ordinary"]))
	var seeds: Array = config.seeds if comprehensive else [config.seeds[0]]
	for profile in profiles:
		for seed_value in seeds:
			for starter in config.starters:
				_run_one(str(starter), int(seed_value), str(profile), "offense")
	if mode in ["full", "profile:ordinary"]:
		_run_one("F01", int(config.seeds[1]), "ordinary", "defense")
	var report := {"model_version": "native-route-pressure-1", "config_version": config.version, "model_contract": config.model_contract,
		"enemy_runtime": runtime_snapshot,
		"target_active_seconds": config.target_active_seconds, "label": label, "mode": mode, "core_sha256": core_sha256, "scenarios": results, "stat_table": _stat_table()}
	var directory := "res://build/qa/route-pressure-20261017"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory.path_join(label + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Native route-pressure report: %s; scenarios %d" % [label, results.size()])
	quit(0)


func _run_one(starter: String, seed_value: int, profile_name: String, growth_name: String):
	var run = Route.new()
	var configured: Dictionary = run.configure({}, seed_value)
	if configured.ok and not enemy_override.is_empty():
		configured = run._enemy_combat.configure(run._base, run._runtime, enemy_override)
	if not configured.ok or not run.choose_initial(starter):
		results.append({"starter": starter, "seed": seed_value, "profile": profile_name, "error": configured.get("error", "initial choice rejected")})
		return
	var pilot = Policy.new()
	pilot.direction_count = 8
	pilot.growth_order = config.growth[growth_name].duplicate()
	var observer := Perception.new()
	observer.core = run
	observer.vision = float(config.profiles[profile_name].projectile_vision_m)
	var interval := maxi(1, roundi(float(config.profiles[profile_name].decision_seconds) * 120.0))
	var direction := Vector2.ZERO
	var frames := 0
	var combat_frames := 0
	var movement_frames := 0
	var last_room: int = run.room_index
	var room_start_combat := 0
	var room_start_damage := 0.0
	var room_rows: Array = []
	var seen_events: Dictionary = {}
	var attacks: Dictionary = {}
	var warning_times: Dictionary = {}
	var observed_actors: Dictionary = {}
	var defeated_actors: Array = []
	var previous_phase: String = run.phase
	while run.phase not in ["complete", "dead"] and frames < int(float(config.max_active_seconds) * 120.0):
		if run.phase == "reward":
			if not pilot.choose_growth(run): break
			continue
		if run.phase == "artifact":
			if not pilot.choose_artifact(run): break
			continue
		if run.phase == "pickup":
			var snapshot: Dictionary = run.get_snapshot()
			var reward: Dictionary = snapshot.get("reward_pickup", {})
			if reward.is_empty(): break
			var destination: Vector2 = reward.get("pos", run.portal.pos)
			var waypoint: Vector2 = run._chase_position(run.player.pos, destination, 1.0, run.player.radius)
			direction = _snap(waypoint - run.player.pos)
		elif frames % interval == 0 or run.phase != previous_phase or run.room_index != last_room:
			direction = pilot.autoplay_direction(observer)
		previous_phase = run.phase
		if run.phase == "combat": combat_frames += 1
		else: movement_frames += 1
		run.step(1.0 / 120.0, direction)
		frames += 1
		for effect in run.effects:
			if effect.kind == "enemy_warning" and not seen_events.has(effect.seq):
				seen_events[effect.seq] = true
				var type_id := str(effect.get("type_id", "unknown"))
				attacks[type_id] = int(attacks.get(type_id, 0)) + 1
				var actor_key := str(effect.get("actor_id", "unknown"))
				if not warning_times.has(actor_key): warning_times[actor_key] = []
				warning_times[actor_key].append(float(frames) / 120.0)
		for enemy in run.actors:
			var actor_key := str(enemy.id)
			if not observed_actors.has(actor_key):
				observed_actors[actor_key] = {"id": actor_key, "type": enemy.type_id, "room": run.room_index, "spawn_at": float(frames) / 120.0, "max_health": enemy.max_health, "done": false}
			if enemy.health <= 0.0 and not observed_actors[actor_key].done:
				var defeated: Dictionary = observed_actors[actor_key].duplicate(true)
				defeated["spawn_to_defeat_seconds"] = float(frames) / 120.0 - float(defeated.spawn_at)
				defeated_actors.append(defeated)
				observed_actors[actor_key].done = true
		if run.phase in ["pickup", "reward", "artifact", "exit"] and previous_phase == "combat":
			room_rows.append({"room": run.room_index, "combat_seconds": float(combat_frames - room_start_combat) / 120.0, "taken": float(run.damage_taken) - room_start_damage, "health": run.player.health, "shield": run.player.shield, "spells": run.spells.map(func(spell): return {"id": spell.id, "level": spell.level})})
		if run.room_index != last_room:
			last_room = run.room_index
			room_start_combat = combat_frames
			room_start_damage = float(run.damage_taken)
		if float(combat_frames - room_start_combat) / 120.0 > float(config.max_room_combat_seconds): break
	var row := {"starter": starter, "seed": seed_value, "profile": profile_name, "growth": growth_name, "phase": run.phase,
		"room": run.room_index, "clears": run.clear_count, "active_seconds": float(frames) / 120.0,
		"combat_seconds": float(combat_frames) / 120.0, "traversal_pickup_seconds": float(movement_frames) / 120.0,
		"taken": run.damage_taken, "health": run.player.health, "max_health": run.player.max_health, "kills": run.kills,
		"artifacts": run.get_snapshot().get("artifacts", []).map(func(item): return item.id), "attacks": attacks,
		"rooms": room_rows, "last_pos": str(run.player.pos), "warning_times_by_actor": warning_times, "defeated_actors": defeated_actors,
		"game_time": run.time, "game_combat_time": run.get("combat_time"), "active_clock_delta": float(run.time) - float(frames) / 120.0}
	results.append(row)
	print("%s %s %s seed%d %s r%d active%.2f combat%.2f taken%.1f HP%.1f" % [profile_name, starter, growth_name, seed_value, run.phase, run.room_index, row.active_seconds, row.combat_seconds, float(run.damage_taken), float(run.player.health)])


func _snap(direction: Vector2) -> Vector2:
	if direction.length_squared() < 0.000001:
		return Vector2.ZERO
	return Vector2.RIGHT.rotated(roundf(direction.angle() / TAU * 8.0) * TAU / 8.0)


func _stat_table() -> Array:
	var run = Route.new()
	if not run.configure().ok: return []
	if not enemy_override.is_empty() and not run._enemy_combat.configure(run._base, run._runtime, enemy_override).ok: return []
	var rows: Array = []
	for room_id in [1, 4, 6, 9, 12, 15]:
		for type_id in ["M01", "M02", "M03", "M04", "EL01", "EL02", "EL02_GUARD"]:
			var spec: Dictionary = run._enemy_combat.type_spec(type_id, room_id)
			rows.append({"room": room_id, "type": type_id, "stage": spec.get("stat_stage_id", "baseline"), "health": spec.health, "damage": spec.damage, "walk_speed": spec.move_speed, "projectile_speed": spec.get("projectile_speed", 0.0), "attack_cycle": spec.attack_cycle, "warning": spec.warning, "radius": spec.radius, "reference_F01_level1_packets": ceili(float(spec.health) / float(run.player.attack)), "reference_F01_level1_full_hit_seconds": float(run._base.spells.F01.windup) + float(run._base.spells.F01.travel_delay) + float(ceili(float(spec.health) / float(run.player.attack)) - 1) * (float(run._base.spells.F01.cooldown) + float(run._base.spells.F01.windup))})
	return rows
