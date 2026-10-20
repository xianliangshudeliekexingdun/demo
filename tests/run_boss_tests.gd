extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var suite = preload("res://tests/route_boss_tests.gd").new()
	var failures: int = suite.run()
	var output := "res://build/qa/boss-implementation-20261020/boss-rules.json"
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--qa-out=res://build/qa/") and not str(arg).contains(".."):
			output = str(arg).trim_prefix("--qa-out=").path_join("boss-rules.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify({"checks": suite.checks, "failures": failures, "patterns": suite.rows, "scope": "Controlled headless Boss rules only; no natural gameplay, rendering, screenshots, export or account save."}, "\t"))
	quit(1 if failures else 0)
