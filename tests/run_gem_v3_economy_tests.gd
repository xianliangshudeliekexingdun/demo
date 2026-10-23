extends SceneTree
const Suite = preload("res://tests/gem_v3_economy_tests.gd")
func _initialize(): call_deferred("run")
func run():
	var suite = Suite.new()
	var count: int = suite.run()
	quit(0 if count>=0 else 1)
