extends "res://tools/balance/route_pressure/run.gd"
## Bounded parameter experiment using the retained native replay entry point.
## Unlike accepted route45 scenarios this deliberately varies pre-spawn config.
const SENSITIVITY_OUT := "res://build/qa/route45-20261018/sensitivity.json"
var input_runtime: Dictionary = {}
var trials: Array = []
var source_hashes: Dictionary = {}

func _initialize():
	call_deferred("run_sensitivity")

func run_sensitivity():
	config = JSON.parse_string(FileAccess.get_file_as_string("res://tools/balance/route45/scenarios.json"))
	input_runtime = JSON.parse_string(FileAccess.get_file_as_string("res://data/route_enemy_runtime.json"))
	for path in ["res://tools/balance/route45/sensitivity.gd","res://tools/balance/route_pressure/run.gd","res://tools/balance/route45/scenarios.json","res://tests/route_rebalance_tests.gd","res://scripts/core/courtyard_route_run.gd","res://scripts/core/courtyard_route_catalog.gd","res://scripts/core/route_enemy_combat.gd","res://scripts/core/route_spell_combat.gd","res://scripts/core/route_artifacts.gd","res://data/courtyard_route.json","res://data/route_enemy_runtime.json"]:
		source_hashes[path] = FileAccess.get_sha256(path)
	for factor in [0.9,1.0,1.1]:
		enemy_override = input_runtime.duplicate(true)
		for stage in enemy_override.stat_stages:
			if int(stage.from) > 15:
				stage.normal.health = float(stage.normal.health)*factor
				stage.elite.health = float(stage.elite.health)*factor
		# Validate coverage with the exact owner-supplied count before the existing
		# replay loop injects this same derived config ahead of choose_initial.
		var probe = Route.new()
		var configured: Dictionary = probe.configure({},20261017)
		if configured.ok:
			configured = probe._enemy_combat.configure(probe._base,probe._runtime,enemy_override,probe.room_total)
		if not configured.ok:
			trials.append({"factor":factor,"override":enemy_override.duplicate(true),"error":configured.get("error", "invalid override")})
			_save_sensitivity()
			continue
		_run_one("F01",20261017,"ordinary","offense")
		var result: Dictionary = results.back().duplicate(true)
		var phase: String = str(result.get("phase","error"))
		var termination: String = phase if phase in ["complete","dead"] else "noncombat_or_offer_rejected"
		if phase == "combat":
			termination = "active_timeout" if float(result.get("active_seconds",0.0)) >= float(config.max_active_seconds) else "room_combat_timeout"
		result["termination"] = termination
		result["health_factor_rooms16to45"] = factor
		result["parameter_experiment"] = true
		result["owner_room_count_validation"] = probe.room_total
		trials.append({"factor":factor,"override":enemy_override.duplicate(true),"result":result})
		_save_sensitivity()
		print("SENSITIVITY factor%.2f %s r%d total%.2f combat%.2f taken%.1f" % [factor,result.get("phase","error"),int(result.get("room",0)),float(result.get("active_seconds",0)),float(result.get("combat_seconds",0)),float(result.get("taken",0))])
	var stable := _sources_stable()
	_save_sensitivity()
	print("SENSITIVITY: %d trials; canonical sources stable=%s; first-fifteen trajectories equal=%s" % [trials.size(),str(stable),str(_first_fifteen_equal())])
	quit(0 if stable and trials.size()==3 and _first_fifteen_equal() else 1)

func _save_sensitivity():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SENSITIVITY_OUT.get_base_dir()))
	var report := {"model_version":"route45-health-sensitivity-native-1","parameter_experiment":true,"engine":Engine.get_version_info(),"source_sha256":source_hashes,"source_stable":_sources_stable(),"base_runtime":input_runtime,"trials":trials,"first_fifteen_trajectories_equal":_first_fifteen_equal(),"contract":"Existing native route_pressure replay: actual 120 Hz Route.step, eight directions, ordinary 0.25 s / 4.5 m perception, F01 seed20261017 and actual offered rewards. Derived pre-spawn runtime only changes normal/elite health multipliers for stage.from > 15. No player/actor health, phase, positions, damage, spell levels, cooldowns or drops are edited after configure. All three points use this same runner; route45 selected baseline is not substituted because its movement memory/pickup sampling differs."}
	FileAccess.open(SENSITIVITY_OUT,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))

func _first_fifteen_equal() -> bool:
	if trials.size() < 2: return true
	if not trials[0].has("result"): return false
	var baseline: Array = trials[0].result.get("rooms",[]).slice(0,15)
	if baseline.size() != 15: return false
	for trial in trials.slice(1):
		if not trial.has("result") or trial.result.get("rooms",[]).slice(0,15) != baseline:
			return false
	return true

func _sources_stable() -> bool:
	for path in source_hashes:
		if FileAccess.get_sha256(path) != source_hashes[path]: return false
	return true
