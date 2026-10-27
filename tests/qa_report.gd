extends RefCounted
## Standalone checks must also work before any historical QA directory exists.
static func write_report(report: Dictionary, default_path: String) -> bool:
	var directory := default_path.get_base_dir()
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with("--qa-out="):
			var requested: String = str(argument).trim_prefix("--qa-out=")
			if requested.begins_with("res://build/qa/") and not requested.contains(".."):
				directory = requested
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory.path_join(default_path.get_file())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write QA report: " + path)
		return false
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	return true
