extends SceneTree
const Catalog = preload("res://scripts/ui/grimoire_catalog.gd")
func _initialize():
	var source = JSON.parse_string(FileAccess.get_file_as_string("res://data/route_spell_growth.json"))
	var rows: Array = []
	for id in source.spells:
		var row: Dictionary = {"id": id, "name": Catalog.spell_name(id), "levels": []}
		for level in range(1, 4): row.levels.append(Catalog.describe_spell(id, level))
		rows.append(row)
	FileAccess.open("res://build/qa/spell-growth-implementation-20261020/catalog.json", FileAccess.WRITE).store_string(JSON.stringify(rows, "\t"))
	quit()
