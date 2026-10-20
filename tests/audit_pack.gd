extends SceneTree
var entries: Array[String] = []
func scan(path: String):
	var d=DirAccess.open(path)
	if not d: return
	for f in d.get_files(): entries.append(path.path_join(f))
	for child in d.get_directories(): scan(path.path_join(child))
func _initialize():
	scan("res://")
	entries.sort()
	var bad=[]
	for path in entries:
		if path.contains("/tests/") or path.contains("/build/") or path.contains("/docs/") or path.ends_with(".exe") or path.contains("taptap"):
			bad.append(path)
	print("PACK_FILES ",JSON.stringify(entries))
	print("PACK_AUDIT forbidden=",bad)
	quit(0 if bad.is_empty() else 1)
