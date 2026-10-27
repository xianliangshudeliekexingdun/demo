extends SceneTree
## Current native rules. Prototype/Lua parity suites live in the external archive.
var failures = 0
var linked_checks: int = 0
var suite_results: Array = []

func _initialize():
	call_deferred("run")

func run():
	_run_suite(preload("res://tests/first_room_tests.gd"), "first_room")
	_run_suite(preload("res://tests/courtyard_route_tests.gd"), "courtyard_route")
	_run_suite(preload("res://tests/route_enemy_tests.gd"), "route_enemies")
	_run_suite(preload("res://tests/magic_missile_contact_tests.gd"), "magic_missile_contacts")
	_run_suite(preload("res://tests/route_enemy_pressure_tests.gd"), "route_enemy_pressure")
	_run_suite(preload("res://tests/nonboss_difficulty_tests.gd"), "nonboss_difficulty")
	_run_suite(preload("res://tests/enemy_damage_growth_tests.gd"), "enemy_damage_growth")
	_run_suite(preload("res://tests/route_boss_tests.gd"), "route_bosses")
	_run_suite(preload("res://tests/route_reward_flow_tests.gd"), "route_reward_flow")
	_run_suite(preload("res://tests/spell_growth_tests.gd"), "spell_growth")
	_run_suite(preload("res://tests/route_rebalance_tests.gd"), "route_rebalance")
	_run_suite(preload("res://tests/meta_progression_tests.gd"), "meta_progression")
	var result := {"checks": linked_checks, "failures": failures, "local_checks": 0, "local_failures": 0, "suites": suite_results, "scope": "current native shared and route rules; SceneTree spell/artifact suites run separately", "archived_suites": ["lua_parity", "build_trial", "build_upgrades", "fireball_trial"]}
	result["natural_routes_deferred"] = "--skip-natural-route" in OS.get_cmdline_user_args()
	_write_report("main_suite_results.json", result)
	print("Checks: %d; failures: %d" % [linked_checks, failures])
	quit(1 if failures else 0)

func _run_suite(script: Script, label: String):
	var suite = script.new()
	var found: int = int(suite.run())
	linked_checks += int(suite.checks)
	failures += found
	suite_results.append({"id": label, "checks": int(suite.checks), "failures": found})
	if label == "route_rebalance":
		var deferred := "--skip-natural-route" in OS.get_cmdline_user_args()
		_write_report("route_boundary_results.json" if deferred else "natural_route_results.json", {"checks": int(suite.checks), "failures": found, "metrics": suite.metrics, "natural_routes_deferred": deferred})

func _write_report(filename: String, result: Dictionary):
	var directory := "res://build/qa/current-main-suite"
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with("--qa-out="):
			var requested: String = str(argument).trim_prefix("--qa-out=")
			if requested.begins_with("res://build/qa/") and not requested.contains(".."):
				directory = requested
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory.path_join(filename), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
