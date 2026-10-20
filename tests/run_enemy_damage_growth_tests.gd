extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var suite = preload("res://tests/enemy_damage_growth_tests.gd").new()
	var failures: int = suite.run()
	var output := "res://build/qa/enemy-pressure-20261020/damage-growth-rules.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify({"checks": suite.checks, "failures": failures, "scope": "Controlled core rules, no natural route, rendering, performance, account or export."}, "\t"))
	quit(1 if failures else 0)
