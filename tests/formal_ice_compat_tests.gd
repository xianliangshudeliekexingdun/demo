extends SceneTree
## Fast preflight of existing shared-rule suites. Counts overlap run_tests.gd;
## this file never replaces the complete suite or its four natural routes.
const SUITES = [preload("res://tests/first_room_tests.gd"),preload("res://tests/courtyard_route_tests.gd"),preload("res://tests/route_enemy_tests.gd"),preload("res://tests/route_enemy_pressure_tests.gd"),preload("res://tests/route_reward_flow_tests.gd")]
func _initialize(): call_deferred("run")
func run():
	var checks: int=0
	var failures: int=0
	for script in SUITES:
		var suite=script.new()
		failures+=suite.run()
		checks+=suite.checks
	print("ICE SHARED PREFLIGHT: %d checks %d failures (overlaps main suite)" % [checks,failures])
	quit(0 if failures==0 else 1)
