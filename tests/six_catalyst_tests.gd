extends SceneTree
## Six-school catalyst transactions plus v4 gem account shape; isolated saves only.
const Meta = preload("res://scripts/core/meta_progression.gd")
const ExistingSuite = preload("res://tests/meta_progression_tests.gd")
const IDS = ["MC04", "MC05", "MC06", "MC07", "MC08", "MC09"]
const SCHOOLS = ["fire", "ice", "lightning", "wind", "earth", "spirit"]
var checks: int = 0
var failures: Array = []
var paths: Array = []
var serial: int = 0
var root_path: String

class SamplingFixture extends "res://scripts/core/meta_progression.gd":
	var sampling_override: Dictionary = {}
	func _read_json(path: String) -> Dictionary:
		if path == "res://data/route_spell_sampling.json" and not sampling_override.is_empty():
			return {"ok": true, "data": sampling_override.duplicate(true)}
		return super._read_json(path)

func _initialize(): call_deferred("execute")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures.append(label)
		push_error("Six catalysts: " + label)
func near(a: float, b: float) -> bool: return absf(a - b) < 0.00001
func account():
	serial += 1
	var path: String = root_path + "_%d.json" % serial
	paths.append(path)
	var m = Meta.new(path)
	check(m.load_state().ok, "isolated account configures")
	return m
func store_fixture(path: String, state: Dictionary):
	check(path.begins_with(Meta.TEST_SAVE_ROOT) and not path.contains(".."), "fixture constrained to isolated save root")
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(state))

func execute():
	root_path = Meta.TEST_SAVE_ROOT + "six_catalysts_%d" % Time.get_ticks_usec()
	var existing = ExistingSuite.new()
	var prior_failures: int = existing.run()
	checks += existing.checks
	if prior_failures > 0: failures.append("existing meta suite failed: %d" % prior_failures)
	catalog_and_transactions()
	gem_transactions_and_corruption()
	shared_sampling_validation()
	for path in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var out: String = "res://build/qa/six-school-sampling-20261021/meta"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	FileAccess.open(out + "/results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures.size(), "details": failures,
		"includes_existing_meta_checks": existing.checks, "source_sha256": {"meta": FileAccess.get_sha256(Meta.META_PATH), "sampling": FileAccess.get_sha256("res://data/route_spell_sampling.json"), "implementation": FileAccess.get_sha256("res://scripts/core/meta_progression.gd")},
		"scope": "Native six catalyst catalog/transactions and v4 gem account transactions plus malformed-current-schema preservation in isolated test saves. No migration, real account writes, combat, pixels or final economic balance."}, "\t"))
	print("SIX CATALYSTS checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func catalog_and_transactions():
	for index in IDS.size():
		var id: String = IDS[index]
		var m = account()
		var catalog: Dictionary = m.get_catalog()
		check(catalog.catalysts.size() == 6 and catalog.catalyst_schools == SCHOOLS, "six complete catalyst schools")
		var all_ids: Dictionary = {}
		for school_id in IDS:
			var item: Dictionary = m.get_item_status("catalyst", school_id)
			check(item.related_spells.size() == 10 and item.related_spell_names.size() == 10, "complete ten spell linkage " + school_id)
			check(item.effect_kind == "school_priority" and item.effect_by_level == catalog.spell_sampling.catalyst_affinity_by_level, "shared affinity values " + school_id)
			check(item.effect_value == 0.0 and item.free, "locked item reports no equipped priority " + school_id)
			for spell_id in item.related_spells:
				check(not all_ids.has(spell_id) and str(catalog.spells[spell_id].school) == str(item.school) and spell_id != "F04", "sixty unique formal related spells " + spell_id)
				all_ids[spell_id] = true
		check(all_ids.size() == 60, "formal sixty covered once")
		check(m.request_unlock("catalyst", id).ok and m.get_state().equipped.catalyst == id, "free first choice any school " + id)
		check(m.get_state().dust == 0 and m.get_state().free_claimed.catalyst and m.get_state().free_claimed.size() == 1, "one catalyst entitlement independent of gems " + id)
		for other_id in IDS:
			if other_id != id: check(not m.get_item_status("catalyst", other_id).free and not m.request_unlock("catalyst", other_id).ok, "later schools cost dust " + other_id)
		var funded: Dictionary = m.get_state()
		funded.dust = 80
		store_fixture(m.save_path, funded)
		check(m.load_state().ok, "funded isolated transaction loads")
		check(near(float(m.get_item_status("catalyst", id).effect_value), float(catalog.spell_sampling.catalyst_affinity_by_level[0])), "rank one current affinity " + id)
		check(m.request_upgrade("catalyst", id).ok and m.get_state().dust == 60, "rank two costs twenty " + id)
		check(near(float(m.get_item_status("catalyst", id).effect_value), float(catalog.spell_sampling.catalyst_affinity_by_level[1])), "rank two current affinity " + id)
		check(m.request_upgrade("catalyst", id).ok and m.get_state().dust == 20, "rank three costs forty " + id)
		check(near(float(m.get_item_status("catalyst", id).effect_value), float(catalog.spell_sampling.catalyst_affinity_by_level[2])), "rank three current affinity " + id)
		var second: String = IDS[(index + 1) % IDS.size()]
		check(m.request_unlock("catalyst", second).ok and m.get_state().dust == 0 and m.get_state().levels[second] == 1, "paid school costs twenty " + second)
		var begun: Dictionary = m.begin_playable_run("route45")
		check(begun.ok and begun.snapshot.equipment.catalyst == id and begun.snapshot.levels[id] == 3, "departure snapshot locks correct catalyst " + id)
		var before: Dictionary = m.get_state()
		check(not m.request_equip("catalyst", second).ok and not m.request_upgrade("catalyst", second).ok and m.get_state() == before, "no mid-run changes " + id)
		check(m.settle_playable_run(begun.run_id, []).ok, "empty isolated run settles without income")
		check(m.request_equip("catalyst", second).ok and m.request_equip("catalyst", "").ok, "outside run free swap and unequip " + id)
		var reloaded = Meta.new(m.save_path)
		check(reloaded.load_state().ok and reloaded.get_state() == m.get_state(), "six school transactions survive reload " + id)

func gem_transactions_and_corruption():
	var m = account()
	check(m.request_unlock("catalyst", "MC05").ok, "free catalyst prepared")
	var funding: Dictionary = m.get_state()
	funding.dust = 500
	funding.gem_state.essence = 1000
	store_fixture(m.save_path, funding)
	check(m.load_state().ok, "funded gem account loads")
	check(m.request_upgrade("catalyst", "MC05").ok, "catalyst upgrade prepared")
	var drawn: Dictionary = m.request_draw_gems(10)
	check(drawn.ok and drawn.gems.size() == 10, "ten gems drawn through the account")
	check(m.get_state().gem_state.inventory.size() == 10 and int(m.get_state().dust) == 430, "draw ledger and balance follow the transaction")
	var first: String = str(drawn.gems[0].id)
	check(m.request_lock_gem(first).ok and bool(m.gems.find(m.get_state().gem_state, first).locked), "gem lock toggled")
	check(m.request_equip_gem(1, first).ok and m.get_state().gem_state.slots[1] == first, "instance equipped into slot one")
	check(not m.request_salvage_gems([first]).ok, "equipped gem is salvage protected")
	var state: Dictionary = m.get_state()
	var lib = m.gems
	var gold_serial: int = int(state.gem_state.serial) + 1
	state.gem_state.serial = gold_serial
	state.gem_state.draws = gold_serial
	var affixes: Array = [lib.line("attack", 1, false), lib.line("health", 2, false), lib.line("shield", 3, false)]
	state.gem_state.inventory.append({"id": "gem-%d" % gold_serial, "serial": gold_serial, "rarity": "gold", "affixes": affixes, "core": "inferno", "locked": false, "origin": "draw"})
	store_fixture(m.save_path, state)
	check(m.load_state().ok, "valid gold fixture loads " + m.error)
	var gold_id: String = "gem-%d" % gold_serial
	var reroll: Dictionary = m.request_reroll_gem(gold_id, ["core"])
	check(reroll.ok and int(m.get_state().gem_state.essence) == 965, "gold reroll charges base plus one lock")
	var token: int = int(m.get_state().gem_state.pending_reforge.token)
	check(m.resolve_reforge(token, false).ok and m.get_state().gem_state.pending_reforge.is_empty(), "reroll candidate resolved without adopting")
	var salvage_id: String = ""
	for gem in m.get_state().gem_state.inventory:
		if gem.rarity in ["green", "blue"] and not bool(gem.locked) and gem.id not in m.get_state().gem_state.slots:
			salvage_id = str(gem.id)
			break
	check(not salvage_id.is_empty(), "an idle coloured gem is available")
	if not salvage_id.is_empty():
		var salvaged: Dictionary = m.request_salvage_gems([salvage_id])
		check(salvaged.ok and int(salvaged.essence_gained) in [1, 3], "idle gem salvages for its quality yield")
	check(lib.validate(m.get_state().gem_state).is_empty(), "transaction account stays valid")
	var reloaded = Meta.new(m.save_path)
	check(reloaded.load_state().ok and reloaded.get_state() == m.get_state(), "gem transactions survive reload")
	var valid: Dictionary = m.get_state()
	var invalid: Dictionary = valid.duplicate(true)
	invalid.gem_state.pending_reforge = {"gem_id": str(drawn.gems[2].id), "mode": "affix", "token": 0, "locks": [], "cost": 20, "old": {}, "candidate": {}}
	var invalids: Array = []
	invalids.append(invalid)
	for field in ["dust", "free_claimed", "equipped", "gem_state"]:
		var bad: Dictionary = valid.duplicate(true)
		bad.erase(field)
		invalids.append(bad)
	var bad: Dictionary = valid.duplicate(true)
	bad.levels.erase("MC06")
	invalids.append(bad)
	bad = valid.duplicate(true)
	bad.levels.MC05 = 1.5
	invalids.append(bad)
	bad = valid.duplicate(true)
	bad.equipped.catalyst = "MC06"
	invalids.append(bad)
	bad = valid.duplicate(true)
	bad.levels.UNKNOWN = 0
	invalids.append(bad)
	bad = valid.duplicate(true)
	bad.gem_state.slots = ["", "", ""]
	invalids.append(bad)
	bad = valid.duplicate(true)
	bad.gem_state.slots[0] = str(drawn.gems[0].id)
	bad.gem_state.slots[1] = str(drawn.gems[0].id)
	invalids.append(bad)
	bad = valid.duplicate(true)
	bad.gem_state.draws = int(bad.gem_state.draws) + 1
	invalids.append(bad)
	bad = valid.duplicate(true)
	bad.gem_state.inventory[-1].core = "unknown"
	invalids.append(bad)
	bad = valid.duplicate(true)
	var coloured_index: int = 0
	for index in bad.gem_state.inventory.size():
		if str(bad.gem_state.inventory[index].rarity) != "gold":
			coloured_index = index
			break
	bad.gem_state.inventory[coloured_index].affixes[0].role = "side"
	invalids.append(bad)
	bad = valid.duplicate(true)
	bad.gem_state.cumulative_cleared = 15
	invalids.append(bad)
	for broken_save in invalids:
		store_fixture(m.save_path, broken_save)
		var bytes: String = FileAccess.get_file_as_string(m.save_path)
		var broken = Meta.new(m.save_path)
		check(not broken.load_state().ok and not broken.is_loaded(), "malformed current schema is rejected")
		check(FileAccess.get_file_as_string(m.save_path) == bytes, "malformed schema stays byte-identical")
	store_fixture(m.save_path, valid)
	check(Meta.new(m.save_path).load_state().ok, "valid account restored after malformed fixtures")

func shared_sampling_validation():
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/route_spell_sampling.json"))
	var cases: Array = []
	for row in [["method", "old_weight"], ["owned_upgrade_weight", 0.0], ["owned_upgrade_weight", -1.0], ["baseline_spell_weight", "1"], ["offer_size", 4], ["unique_within_offer", false], ["eligibility_before_weighting", false], ["affects_initial_offer", true], ["affects_artifact_quality", true], ["new_or_upgrade_quota", true], ["reroll", true], ["pity", true]]:
		var value: Dictionary = raw.duplicate(true)
		value[row[0]] = row[1]
		cases.append(value)
	var equal_affinity: Dictionary = raw.duplicate(true)
	equal_affinity.catalyst_affinity_by_level = [0.28, 0.28, 0.52]
	cases.append(equal_affinity)
	for source in cases:
		serial += 1
		var path: String = root_path + "_invalid_sampling_%d.json" % serial
		paths.append(path)
		var account_fixture = SamplingFixture.new(path)
		account_fixture.sampling_override = source
		check(not account_fixture.load_state().ok and not account_fixture.is_loaded(), "meta refuses invalid shared sampling rules")
		check(not FileAccess.file_exists(path), "invalid shared sampling rules never create a save")
