extends SceneTree
func _initialize(): call_deferred("run")
func run():
	var suite = preload("res://tests/gem_v3_combat_tests.gd").new()
	quit(1 if suite.run() > 0 else 0)
