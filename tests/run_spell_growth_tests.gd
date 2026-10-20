extends SceneTree
const Suite = preload("res://tests/spell_growth_tests.gd")
func _initialize(): call_deferred("execute")
func execute():
	var suite = Suite.new()
	var failed: int = suite.run()
	var path: String = "res://build/qa/spell-growth-implementation-20261020/growth-results.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify({"checks": suite.checks, "failures": failed, "details": suite.details, "scope": "bounded native core fixtures; no interactive play or natural route"}, "\t"))
	quit(1 if failed else 0)
