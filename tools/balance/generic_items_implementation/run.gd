extends SceneTree
## Persistent telemetry over the authoritative native core; no combat model copy.
const Route = preload("res://scripts/core/courtyard_route_run.gd")
const Policy = preload("res://tests/route_rebalance_tests.gd")
const Perception = preload("res://tools/balance/route_pressure/run.gd").Perception
const SCENARIOS := "res://tools/balance/generic_items_implementation/scenarios.json"
const OUT := "res://build/qa/generic-items-implementation-20261018/pressure/"
var config: Dictionary = {}
var rows: Array = []
var provenance: Dictionary = {}
var source_parameters: Dictionary = {}
var item_policy: String = "generic_first"

func _initialize():
	call_deferred("run")

func run():
	config = JSON.parse_string(FileAccess.get_file_as_string(SCENARIOS))
	for path in ["res://scripts/core/courtyard_route_run.gd", "res://scripts/core/courtyard_route_catalog.gd", "res://scripts/core/route_enemy_combat.gd", "res://scripts/core/route_spell_combat.gd", "res://scripts/core/route_artifacts.gd", "res://data/courtyard_route.json", "res://data/route_enemy_runtime.json", "res://tools/balance/generic_items_implementation/scenarios.json", "res://tools/balance/generic_items_implementation/run.gd", "res://tools/balance/route_pressure/run.gd", "res://tests/route_rebalance_tests.gd"]:
		provenance[path] = FileAccess.get_sha256(path)
	for path in ["res://scripts/core/first_room_run.gd", "res://scripts/core/route_generic_items.gd", "res://data/generic_artifacts_v1.json", "res://data/balance_candidates/fire_artifacts_v1.json", "res://data/balance_candidates/first_run_v1.json"]:
		if FileAccess.file_exists(path): provenance[path] = FileAccess.get_sha256(path)
	for path in ["res://data/courtyard_route.json","res://data/route_enemy_runtime.json", "res://data/generic_artifacts_v1.json", "res://data/balance_candidates/fire_artifacts_v1.json"]:
		source_parameters[path] = JSON.parse_string(FileAccess.get_file_as_string(path))
	var args: Array = OS.get_cmdline_user_args()
	var label := str(args[0]) if args.size() > 0 else "selected"
	var mode := str(args[1]) if args.size() > 1 else "quick"
	var policies: Array = config.item_preferences.keys() if mode == "paired" else [mode if config.item_preferences.has(mode) else "generic_first"]
	for selected_policy in policies:
		item_policy = str(selected_policy)
		_run_one("F01", int(config.seeds[0]), "ordinary", "offense")
		rows.back()["item_policy"] = item_policy
		_save(label, mode)
	_save(label, mode)
	print("ROUTE45 report %s: %d scenarios" % [label, rows.size()])
	quit(0)

func _save(label: String, mode: String):
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var file := FileAccess.open(OUT.path_join(label+".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"model_version":"generic-items-native-1", "engine":Engine.get_version_info(), "label":label, "mode":mode, "config":config, "source_sha256":provenance, "source_parameters":source_parameters,"source_stable":_source_stable(), "scenarios":rows, "stat_table":_stat_table()}, "\t"))
	file.close()

func _run_one(starter: String, seed_value: int, profile_name: String, growth: String):
	if not _source_stable():
		rows.append({"starter":starter,"seed":seed_value,"profile":profile_name,"error":"source_changed_during_batch"})
		return
	var battle = Route.new()
	var configured: Dictionary = battle.configure({}, seed_value)
	if not configured.ok or not battle.choose_initial(starter):
		rows.append({"starter":starter,"seed":seed_value,"profile":profile_name,"error":configured.get("error","initial choice rejected")})
		return
	var pilot = Policy.new()
	pilot.direction_count = 8
	pilot.growth_order = config.growth[growth].duplicate()
	var observer = Perception.new()
	observer.core = battle
	observer.vision = float(config.profiles[profile_name].projectile_vision_m)
	var interval := maxi(1, roundi(float(config.profiles[profile_name].decision_seconds)*120.0))
	var direction := Vector2.ZERO
	var frames := 0
	var previous_phase: String = battle.phase
	var current: Dictionary = _new_room(battle)
	var rooms: Array = []
	var choices: Array = []
	var termination := ""
	var last_progress_frame := 0
	var last_progress: String = ""
	var last_effect_seq: int = 0
	while battle.phase not in ["complete","dead"] and frames < roundi(float(config.max_active_seconds)*120.0):
		if battle.phase == "reward":
			var before_spells: Array = battle.spells.duplicate(true)
			var offer: Array = battle.reward_choices.duplicate(true)
			if not pilot.choose_growth(battle):
				termination = "offered_spell_rejected"
				break
			choices.append({"room":battle.room_index,"kind":"spell","time":battle.time,"offer":offer.map(func(item): return item.id),"before":before_spells.map(func(item): return {"id":item.id,"level":item.level}),"after":battle.spells.map(func(item): return {"id":item.id,"level":item.level})})
			continue
		if battle.phase == "artifact":
			var before_items: Array = battle.get_snapshot().artifacts
			var offer: Array = battle.artifact_choices.duplicate(true)
			if not choose_item(battle):
				termination = "offered_treasure_rejected"
				break
			choices.append({"room":battle.room_index,"kind":"treasure","time":battle.time,"offer":offer.map(func(item): return {"id":item.id,"rarity":item.rarity}),"before":before_items.map(func(item): return item.id),"after":battle.get_snapshot().artifacts.map(func(item): return item.id)})
			continue
		if frames % interval == 0 or battle.phase != previous_phase:
			direction = pilot.autoplay_direction(observer)
		previous_phase = battle.phase
		var phase_before: String = battle.phase
		battle.step(1.0/120.0,direction)
		for effect in battle.effects:
			if int(effect.get("seq",0))<=last_effect_seq: continue
			if effect.kind == "hurt":
				current.resources.shield_loss += float(effect.get("shield_damage",0.0))
				current.resources.health_loss += float(effect.get("health_damage",0.0))
			elif effect.kind in ["shield_restore","item_shield_restore"]:
				current.resources.combat_shield_restore += float(effect.get("amount",0.0))
				if float(effect.get("amount",0.0))<=0.0: current.resources.zero_restore_events+=1
			elif effect.kind == "item_health_restore":
				current.resources.item_health_restore += float(effect.get("amount",0.0))
				if float(effect.get("amount",0.0))<=0.0: current.resources.zero_restore_events+=1
			elif effect.kind == "item_charge_release":
				current.resources.charge_release += float(effect.get("amount",0.0))
		last_effect_seq=battle.event_seq
		frames += 1
		current.active_frames += 1
		if phase_before == "combat": current.combat_frames += 1
		var hostile: int = battle._enemy_combat.enemy_projectiles.size()
		current.peak_enemy_projectiles = maxi(current.peak_enemy_projectiles,hostile)
		var alive := 0
		for actor in battle.actors:
			if actor.health > 0.0: alive += 1
		current.peak_alive = maxi(current.peak_alive,alive)
		var progress := "%d:%s:%d" % [battle.room_index,battle.phase,battle.kills]
		if progress != last_progress:
			last_progress = progress
			last_progress_frame = frames
		if battle.room_index != int(current.room) or battle.phase in ["complete","dead"]:
			_finish_room(current,battle)
			rooms.append(current)
			if int(current.room) in [15,30,45] or battle.phase == "dead":
				print("ROUTE45 progress %s %s seed%d finished r%d active%.2f combat%.2f HP%.1f" % [profile_name,starter,seed_value,int(current.room),float(frames)/120.0,battle.combat_time,battle.player.health])
			if battle.phase not in ["complete","dead"]:
				current = _new_room(battle)
				pilot.reset_policy()
				previous_phase = ""
		if int(current.combat_frames) > roundi(float(config.max_room_combat_seconds)*120.0) and battle.phase == "combat":
			termination = "room_combat_timeout"
			break
		if frames-last_progress_frame > 120*60 and battle.phase != "combat":
			termination = "noncombat_no_progress"
			break
	if termination.is_empty(): termination = battle.phase if battle.phase in ["complete","dead"] else "active_timeout"
	if rooms.is_empty() or int(rooms.back().room) != battle.room_index:
		_finish_room(current,battle)
		rooms.append(current)
	var row := {"starter":starter,"seed":seed_value,"profile":profile_name,"growth":growth,"phase":battle.phase,"termination":termination,"room":battle.room_index,"room_total":battle.room_total,"clears":battle.clear_count,"kills":battle.kills,"active_seconds":float(frames)/120.0,"game_time":battle.time,"combat_seconds":battle.combat_time,"active_clock_delta":float(battle.time)-float(frames)/120.0,"taken":battle.damage_taken,"health":battle.player.health,"max_health":battle.player.max_health,"gold":battle.gold,"dust":battle.dust,"account_rewards":battle.get_summary().account_rewards,"artifacts":battle.get_snapshot().artifacts,"spells":battle.spells.map(func(item): return {"id":item.id,"level":item.level}),"rooms":rooms,"segments":_segments(rooms),"choices":choices,"last_pos":str(battle.player.pos)}
	rows.append(row)
	print("ROUTE45 %s %s seed%d %s r%d clears%d active%.2f combat%.2f taken%.1f HP%.1f treasures%d" % [profile_name,starter,seed_value,termination,battle.room_index,battle.clear_count,row.active_seconds,battle.combat_time,battle.damage_taken,battle.player.health,battle.get_snapshot().artifacts.size()])

func _new_room(battle) -> Dictionary:
	var definition: Dictionary = battle._current_room
	var composition: Dictionary = {}
	for pack in definition.encounter.packs:
		for id in pack: composition[id] = int(composition.get(id,0))+int(pack[id])
	return {"room":battle.room_index,"kind":definition.kind,"template":definition.template_id,"stage":battle._enemy_combat.type_spec("M02",battle.room_index).get("stat_stage_id",""),"composition":composition,"ranged_total":int(composition.get("M02",0))+int(composition.get("M04",0))+int(composition.get("EL02",0))+int(composition.get("EL02_GUARD",0)),"active_frames":0,"combat_frames":0,"taken_before":battle.damage_taken,"peak_enemy_projectiles":0,"peak_alive":0,"health_before":battle.player.health,"resources":{"shield_loss":0.0,"health_loss":0.0,"combat_shield_restore":0.0,"item_health_restore":0.0,"charge_release":0.0,"zero_restore_events":0},"spell_start":battle.spells.map(func(item): return {"id":item.id,"level":item.level}),"treasure_start":battle.get_snapshot().artifacts.map(func(item): return item.id)}

func _finish_room(row: Dictionary, battle):
	row["active_seconds"] = float(row.active_frames)/120.0
	row["combat_seconds"] = float(row.combat_frames)/120.0
	row["taken"] = float(battle.damage_taken)-float(row.taken_before)
	row["health_after"] = battle.player.health
	row["cleared"] = int(row.room) in battle.cleared_rooms
	row["phase_after"] = battle.phase
	row["spell_end"] = battle.spells.map(func(item): return {"id":item.id,"level":item.level})
	row["treasure_end"] = battle.get_snapshot().artifacts.map(func(item): return item.id)

func _segments(rooms: Array) -> Array:
	var result: Array = []
	for limits in [[1,15],[16,30],[31,45]]:
		var section := {"from":limits[0],"to":limits[1],"rooms_observed":0,"clears":0,"active_seconds":0.0,"combat_seconds":0.0,"taken":0.0,"peak_enemy_projectiles":0,"ranged_total":0}
		for row in rooms:
			if int(row.room) < int(limits[0]) or int(row.room) > int(limits[1]): continue
			section.rooms_observed += 1
			section.clears += 1 if row.cleared else 0
			section.active_seconds += float(row.active_seconds)
			section.combat_seconds += float(row.combat_seconds)
			section.taken += float(row.taken)
			section.peak_enemy_projectiles = maxi(section.peak_enemy_projectiles,int(row.peak_enemy_projectiles))
			section.ranged_total += int(row.ranged_total)
		result.append(section)
	return result

func _stat_table() -> Array:
	var battle = Route.new()
	if not battle.configure().ok: return []
	var result: Array = []
	for room in [1,4,6,9,12,15,16,21,26,30,31,36,41,45]:
		for id in ["M01","M02","M03","M04","EL01","EL02","EL02_GUARD"]:
			var spec: Dictionary = battle._enemy_combat.type_spec(id,room)
			var packets := ceili(float(spec.health)/float(battle.player.attack))
			result.append({"room":room,"type":id,"stage":spec.stat_stage_id,"health":spec.health,"damage":spec.damage,"move_speed":spec.move_speed,"projectile_speed":spec.get("projectile_speed",0.0),"warning":spec.warning,"attack_cycle":spec.attack_cycle,"complete_action_seconds":battle._enemy_combat._full_attack_duration(spec),"F01_level1_full_hit_packets":packets,"F01_level1_theoretical_seconds":float(battle._base.spells.F01.windup)+float(battle._base.spells.F01.travel_delay)+float(packets-1)*(float(battle._base.spells.F01.cooldown)+float(battle._base.spells.F01.windup))})
	return result

func _source_stable() -> bool:
	for path in provenance:
		if FileAccess.get_sha256(path) != provenance[path]: return false
	return true


func choose_item(battle) -> bool:
	var offered: Array = battle.artifact_choices
	for preferred in config.item_preferences[item_policy]:
		for item in offered:
			if str(item.id) == str(preferred): return battle.choose_artifact(str(preferred))
	return not offered.is_empty() and battle.choose_artifact(str(offered[0].id))



