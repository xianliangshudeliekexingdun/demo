extends SceneTree
## Six-school catalyst transactions and strict legacy migration; isolated saves only.
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
	v4_migration_and_corruption()
	v3_and_v2_migration()
	shared_sampling_validation()
	for path in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var out: String = "res://build/qa/six-school-sampling-20261021/meta"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	FileAccess.open(out + "/results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures.size(), "details": failures,
		"includes_existing_meta_checks": existing.checks, "source_sha256": {"meta": FileAccess.get_sha256(Meta.META_PATH), "sampling": FileAccess.get_sha256("res://data/route_spell_sampling.json"), "implementation": FileAccess.get_sha256("res://scripts/core/meta_progression.gd")},
		"scope": "Native six catalyst catalog/transactions, complete v1-v4 migration and corruption preservation in isolated test saves. No real account writes, combat, pixels or final economic balance."}, "\t"))
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
		check(m.get_state().dust == 0 and m.get_state().free_claimed.catalyst and not m.get_state().free_claimed.gem, "one catalyst entitlement independent of gems " + id)
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

func v4_migration_and_corruption():
	var m = account()
	check(m.request_unlock("catalyst", "MC05").ok and m.claim_starter_gem("MG02").ok, "v4 real entitlements prepared")
	var funding: Dictionary = m.get_state()
	funding.dust = 500
	funding.gem_state.essence = 1000
	store_fixture(m.save_path, funding)
	check(m.load_state().ok and m.request_upgrade("catalyst", "MC05").ok, "v4 upgrade state prepared")
	var drawn: Dictionary = m.request_draw_gems(10)
	check(drawn.ok and drawn.gems.size() == 10, "v4 RNG/pity/instances prepared")
	check(m.request_lock_gem(str(drawn.gems[0].id)).ok, "v4 gem lock prepared")
	check(m.request_equip_gem(1, str(drawn.gems[0].id)).ok, "v4 equipped random instance prepared")
	check(m.request_reforge(str(drawn.gems[1].id), "affix", 0).ok, "v4 pending candidate prepared")
	var old: Dictionary = m.get_state()
	old.version = Meta.TWO_CATALYST_SAVE_VERSION
	for id in Meta.NEW_CATALYST_IDS: old.levels.erase(id)
	store_fixture(m.save_path, old)
	var bytes: String = FileAccess.get_file_as_string(m.save_path)
	var migrated = Meta.new(m.save_path)
	check(migrated.load_state().ok, "complete genuine v4 item shape migrates")
	var state: Dictionary = migrated.get_state()
	check(state.version == Meta.SAVE_VERSION and state.levels.size() == 9, "v4 upgrades to explicit v5")
	check(state.gem_state == old.gem_state, "v4 RNG pity locks equipment essence and pending candidate byte-equivalent data")
	for field in ["dust", "equipped", "free_claimed", "run_serial", "settlement_serial", "last_settlement"]: check(state[field] == old[field], "v4 preserves " + field)
	for id in Meta.TWO_CATALYST_LEVEL_IDS: check(state.levels[id] == old.levels[id], "v4 preserves level " + id)
	for id in Meta.NEW_CATALYST_IDS: check(state.levels[id] == 0 and not migrated.get_item_status("catalyst", id).free, "new school locked without another free choice " + id)
	check(FileAccess.get_file_as_string(m.save_path) == bytes, "v4 read never rewrites original bytes")
	check(migrated.resolve_reforge(int(state.gem_state.pending_reforge.token), false).ok, "next authorized transaction can commit migrated save")
	check(JSON.parse_string(FileAccess.get_file_as_string(m.save_path)).version == Meta.SAVE_VERSION, "successful transaction writes v5")
	var invalids: Array = []
	for id in Meta.TWO_CATALYST_LEVEL_IDS:
		var bad: Dictionary = old.duplicate(true)
		bad.levels.erase(id)
		invalids.append(bad)
	for field in ["dust", "free_claimed", "equipped", "gem_state"]:
		var bad: Dictionary = old.duplicate(true)
		bad.erase(field)
		invalids.append(bad)
	var bad: Dictionary = old.duplicate(true)
	bad.levels.MC06 = 0
	invalids.append(bad)
	bad = old.duplicate(true)
	bad.levels.MC05 = 1.5
	invalids.append(bad)
	bad = old.duplicate(true)
	bad.equipped.catalyst = "MC06"
	invalids.append(bad)
	bad = old.duplicate(true)
	bad.levels.UNKNOWN = 0
	invalids.append(bad)
	bad = state.duplicate(true)
	bad.levels.erase("MC06")
	invalids.append(bad)
	for invalid in invalids:
		store_fixture(m.save_path, invalid)
		bytes = FileAccess.get_file_as_string(m.save_path)
		var broken = Meta.new(m.save_path)
		check(not broken.load_state().ok and not broken.is_loaded(), "malformed old/new schema is rejected")
		check(FileAccess.get_file_as_string(m.save_path) == bytes, "malformed schema stays byte-identical")

func v3_and_v2_migration():
	for version in [Meta.PREVIOUS_SAVE_VERSION, Meta.FIXED_GEM_SAVE_VERSION]:
		var m = account()
		var old: Dictionary = m.get_state()
		old.version = version
		for id in Meta.NEW_CATALYST_IDS: old.levels.erase(id)
		if version == Meta.PREVIOUS_SAVE_VERSION: old.erase("gem_state")
		else:
			for key in ["essence", "salvaged", "work_serial", "pending_reforge"]: old.gem_state.erase(key)
		store_fixture(m.save_path, old)
		var bytes: String = FileAccess.get_file_as_string(m.save_path)
		check(m.load_state().ok, "complete old two catalyst schema migrates " + version)
		check(m.get_state().version == Meta.SAVE_VERSION and m.get_state().levels.size() == 9, "older migration reaches v5 " + version)
		check(m.get_state().dust == 0 and not m.get_state().free_claimed.catalyst, "older unused entitlement preserved " + version)
		check(FileAccess.get_file_as_string(m.save_path) == bytes, "older migration read remains non-writing " + version)


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
