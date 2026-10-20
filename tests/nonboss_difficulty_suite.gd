extends SceneTree
## Explicit unit fixtures; never starts a scene or a natural playthrough.
const Suite = preload("res://tests/nonboss_difficulty_tests.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var suite := Suite.new()
	var failures: int = suite.run()
	var directory := "res://build/qa/nonboss-implementation-20261020"
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with("--qa-out=res://build/qa/") and not str(argument).contains(".."):
			directory = str(argument).trim_prefix("--qa-out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	FileAccess.open(directory.path_join("nonboss-rules.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": suite.checks, "failures": failures, "scope": "headless core unit fixtures; no rendering, interactive play or natural route"}, "\t"))
	quit(1 if failures else 0)
