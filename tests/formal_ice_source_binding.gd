extends RefCounted
## Fingerprint explicit existing res:// dependencies, including renderer/shader
## preloads. Dynamic per-ID paths remain explicitly added by each QA harness.
static func capture(entries: Array) -> Dictionary:
	var pending: Array=entries.duplicate()
	var result: Dictionary={}
	var pattern=RegEx.new()
	pattern.compile("res://[^"+String.chr(34)+String.chr(39)+"\\s]+")
	while not pending.is_empty():
		var path: String=str(pending.pop_back())
		if result.has(path) or path.begins_with("res://build/") or not FileAccess.file_exists(path): continue
		result[path]=FileAccess.get_sha256(path)
		if path.get_extension() in ["gd","json","tscn","tres","gdshader","godot"]:
			var source: String=FileAccess.get_file_as_string(path)
			for match in pattern.search_all(source):
				var dependency: String=match.get_string()
				if not result.has(dependency): pending.append(dependency)
	return result
