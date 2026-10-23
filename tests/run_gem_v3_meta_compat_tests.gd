extends SceneTree
const Suite = preload("res://tests/meta_progression_tests.gd")
func _initialize(): call_deferred("run")
func run():
	var suite = Suite.new()
	var failures: int = suite.run()
	print("META_COMPAT "+JSON.stringify({"checks":suite.checks,"failures":failures}))
	quit(0 if failures==0 else 1)
