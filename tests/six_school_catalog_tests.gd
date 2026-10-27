extends SceneTree
## Read-only headless catalog/source binding. No UI rendering or screenshots.
const Catalog = preload("res://scripts/ui/grimoire_catalog.gd")
const Icon = preload("res://scripts/ui/arcane_icon.gd")
const Atelier = preload("res://scripts/ui/atelier_ui.gd")
const Run = preload("res://scripts/core/courtyard_route_run.gd")
const SCHOOLS = ["fire", "ice", "lightning", "wind", "earth", "spirit"]
var checks: int = 0
var failures: Array = []
func _initialize(): call_deferred("execute")
func check(value: bool, label: String):
	checks += 1
	if not value:
		failures.append(label)
		push_error("Six school catalog: " + label)
func execute():
	var catalog: Dictionary = Catalog.load_catalog(true)
	check(bool(catalog.ok), "catalog loads six sources: " + str(catalog.errors))
	var spells: Array = Catalog.spells()
	check(spells.size() == 60, "sixty active formal spells")
	check(Atelier.SPELL_FILTERS == ["all"] + SCHOOLS, "all plus six school filters")
	var colors: Dictionary = {}
	var ids: Dictionary = {}
	var levels: int = 0
	for school in SCHOOLS:
		var filtered: Array = spells.filter(func(item): return str(item.school) == school)
		check(filtered.size() == 10, school + " ten spell filter")
		check(not Catalog.school_name(school).is_empty(), school + " player label")
		colors[Catalog.school_color(school).to_html()] = true
		var starters: Array = Catalog.starter_ids(school)
		check(starters.size() == 3, school + " three catalog starters")
		var run = Run.new()
		check(bool(run.configure({"route_school": school}, 20261021).get("ok", false)), school + " route configure")
		var route_starters: Array = run.initial_choices().map(func(item): return str(item.id))
		check(starters == route_starters, school + " catalog starters match production")
		for id in starters:
			var described: Dictionary = Catalog.describe_spell(str(id))
			check(bool(described.starter) and str(described.school) == school, str(id) + " starter identity")
		for item in filtered:
			var id: String = str(item.id)
			check(not ids.has(id), id + " globally unique active ID")
			ids[id] = true
			check(Icon.supports_spell(id), id + " explicit icon rather than fallback")
			for level in range(1, 4):
				levels += 1
				var described: Dictionary = Catalog.describe_spell(id, level)
				check(str(described.name) == str(run._base.spells[id].name), id + " name same source")
				check(int(described.level) == level and described.level_details.size() == 3, id + " level identity")
				for field in ["role", "summary", "description", "card_description", "boundary", "source_version"]:
					check(not str(described.get(field, "")).is_empty(), id + " level " + str(level) + " " + field)
				check(str(described.description) == str(described.level_details[level - 1]), id + " same per-level detail")
				check(not str(described.description).contains("：—") and not str(described.description).contains("—%"), id + " no missing runtime value")
				if level > 1: check(not str(described.upgrade_text).is_empty(), id + " upgrade outcome " + str(level))
				for key in run._base.spells[id].levels[level - 1]:
					check(described.values.has(key) and described.values[key] == run._base.spells[id].levels[level - 1][key], id + " level " + str(level) + " runtime " + str(key))
				if school != "fire": check(str(described.source_version) == str(run._base.spells[id].get("growth_version", catalog[school + "_source"].version)), id + " source version")
	check(colors.size() == 6, "six distinct school color tokens")
	check(levels == 180, "one hundred eighty levels described")
	check(not ids.has("F04"), "archived fire spirit stays out of formal active catalog")
	check(Icon.PROCEDURAL_SPELLS.size() == 40, "forty explicit programmatic icons incl lightning")
	check(str(Catalog.describe_spell("W09").kind) == "wind_guard", "wind curtain has defensive identity")
	check(str(Catalog.describe_spell("R06").boundary).contains("持有构造来源"), "construct consumer explains prerequisite")
	check(str(Catalog.describe_spell("S05").boundary).contains("持有召唤来源"), "command explains prerequisite")
	var result: Dictionary = {"version": "six-school-catalog-20261021", "checks": checks, "failed": failures.size(), "failures": failures, "active_spells": ids.size(), "levels": levels, "schools": SCHOOLS, "scope": "read-only source/catalog binding; no rendering, screenshot, natural route or pixel acceptance"}
	var out: String = "res://build/qa/six-schools-implementation-20261021/catalog"
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--qa-out="): out = str(arg).trim_prefix("--qa-out=")
	DirAccess.make_dir_recursive_absolute(out)
	var file = FileAccess.open(out + "/results.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(result, "  "))
	print("Six school catalog: %d checks / %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
