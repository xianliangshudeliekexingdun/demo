extends RefCounted

const Meta = preload("res://scripts/core/meta_progression.gd")
var checks: int = 0
var failures: int = 0
var test_path: String
var fixture_paths: Array[String] = []

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("Meta progression: " + message)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001

func _store_fixture(path: String, value: Variant):
	check(path.begins_with(Meta.TEST_SAVE_ROOT) and not ".." in path, "fixture path is isolated")
	var file = FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "fixture opens")
	if file != null:
		file.store_string(value if value is String else JSON.stringify(value))
		file.close()
	if not fixture_paths.has(path):
		fixture_paths.append(path)

func run() -> int:
	test_path = Meta.TEST_SAVE_ROOT + "suite_%d.json" % Time.get_ticks_usec()
	var m = Meta.new(test_path)
	check(m.load_state().ok, "new isolated account loads")
	if not m.is_loaded():
		return failures + 1
	fixture_paths.append(test_path)
	var catalog = m.get_catalog()
	var initial = m.get_state()
	check(initial.dust == 0, "new account has zero dust")
	check(initial.levels.size() == 5, "five unique items")
	check(initial.equipped == {"catalyst": "", "gem": ""}, "new account has empty equipment")
	check(initial.free_claimed == {"catalyst": false, "gem": false}, "two independent free choices")
	check(initial.settlement_serial == 0, "no invented settlement")
	for level in initial.levels.values():
		check(level == 0, "new account items locked")
	check(m.get_items("catalyst").size() == 2 and m.get_items("gem").size() == 3, "all items listed")
	for kind in ["catalyst", "gem"]:
		for item in m.get_items(kind):
			check(item.free and item.can_unlock and item.cost == 0, "first choice is free: " + item.id)
			check(item.name == catalog["catalysts" if kind == "catalyst" else "gems"][item.id].name, "name from source: " + item.id)
	for item in m.get_items("catalyst"):
		check(item.effect_by_level == catalog.catalyst_weight_by_level, "weights from source: " + item.id)
		for i in range(item.related_spells.size()):
			check(item.related_spell_names[i] == catalog.spells[item.related_spells[i]].name, "related spell name from source")
	var external = m.get_catalog()
	external.player.health = -99
	external.gems.MG01.flat_by_level[0] = -99
	check(m.get_catalog().player.health == catalog.player.health, "catalog is a copy")
	check(m.get_item_status("gem", "MG01").flat_by_level[0] == catalog.gems.MG01.flat_by_level[0], "nested catalog arrays are copies")
	check(m.request_unlock("catalyst", "MC04").ok, "first catalyst chosen")
	check(m.get_state().equipped.catalyst == "MC04", "free catalyst auto equips")
	check(not m.get_state().free_claimed.gem, "catalyst choice does not consume gem choice")
	check(m.request_unlock("gem", "MG02").ok, "independent free gem chosen")
	check(m.get_state().equipped.gem == "MG02", "free gem auto equips")
	check(m.get_state().dust == 0, "free choice does not grant or consume dust")
	check(not m.get_item_status("catalyst", "MC05").free, "later unlock costs dust")
	check(m.get_item_status("catalyst", "MC05").cost == catalog.progression.unlock_cost, "unlock price from source")
	var before = m.get_state()
	var saved_before = FileAccess.get_file_as_string(test_path)
	check(not m.request_unlock("catalyst", "MC04").ok, "duplicate unlock rejected")
	check(not m.request_unlock("catalyst", "MC05").ok, "unaffordable unlock rejected")
	check(not m.request_upgrade("catalyst", "MC04").ok, "unaffordable upgrade rejected")
	check(not m.request_equip("gem", "MG01").ok, "locked item equip rejected")
	check(not m.request_equip("other", "MC04").ok, "unknown kind rejected")
	check(not m.request_unlock("gem", "MC04").ok, "wrong item kind rejected")
	check(m.get_state() == before and FileAccess.get_file_as_string(test_path) == saved_before, "rejected requests preserve memory and disk")
	check(m.request_equip("catalyst").ok, "unequip permitted")
	check(m.get_state().equipped.catalyst.is_empty(), "catalyst slot empty")
	check(m.request_equip("catalyst", "MC04").ok, "free re-equip permitted")
	check(m.get_state().dust == 0, "swaps are free")
	var stats = m.get_preview_stats()
	check(stats.health == catalog.player.health and stats.attack == catalog.player.attack, "shield gem only affects shield")
	check(stats.shield == catalog.player.shield + catalog.gems.MG02.flat_by_level[0], "gem bonus adds once")
	var started = m.begin_run()
	check(started.ok and started.snapshot.preview_only, "run snapshot is explicitly a preview")
	check(started.snapshot.player == stats, "snapshot uses actual prepared stats")
	started.snapshot.player.shield = -20
	started.snapshot.levels.MG02 = 3
	check(m.get_run_snapshot().player == stats and m.get_run_snapshot().levels.MG02 == 1, "snapshot returned by value")
	check(not m.request_equip("gem").ok and not m.request_upgrade("gem", "MG02").ok, "snapshot locks equipment and progression")
	check(not m.request_unlock("gem", "MG01").ok, "snapshot locks unlock")
	check(not m.begin_run().ok, "cannot start a second preview")
	check(not m.load_state().ok and m.is_loaded(), "load during preview rejected without disabling account")
	check(m.end_run().ok and not m.is_in_run(), "ending preview unlocks preparation")
	check(m.get_state().dust == 0 and m.get_state().settlement_serial == 0, "preview does not settle fictional rewards")
	check(m.request_equip("gem", "MG02").ok, "account works after preview")
	var reloaded = Meta.new(test_path)
	check(reloaded.load_state().ok and reloaded.get_state() == m.get_state(), "free choices and equipment survive disk reload")
	var fixture = m.get_state()
	fixture.dust = 100
	_store_fixture(test_path, fixture)
	check(m.load_state().ok, "earned-currency fixture loads")
	check(m.request_upgrade("catalyst", "MC04").ok, "level one upgrades")
	check(m.get_state().levels.MC04 == 2 and m.get_state().dust == 80, "first upgrade deducts twenty once")
	check(near(m.get_item_status("catalyst", "MC04").effect_value, catalog.catalyst_weight_by_level[1]), "level two uses total multiplier")
	check(m.request_upgrade("catalyst", "MC04").ok, "level two upgrades")
	check(m.get_state().levels.MC04 == 3 and m.get_state().dust == 40, "second upgrade deducts forty once")
	check(not m.request_upgrade("catalyst", "MC04").ok, "max level rejected")
	check(m.request_unlock("catalyst", "MC05").ok, "paid unlock succeeds")
	check(m.get_state().dust == 20 and m.get_state().levels.MC05 == 1, "paid unlock level and currency")
	check(m.get_state().equipped.catalyst == "MC04", "paid unlock preserves equipped item")
	check(not m.request_upgrade("gem", "MG02").ok, "legacy gem paid upgrade retired")
	check(m.request_draw_gems(1).ok, "gems use new shared dust draw")
	check(m.get_state().dust == 15 and m.get_state().levels.MG02 == 1, "draw spends five without changing inherited gem")
	check(not m.request_upgrade("gem", "MG02").ok and not m.request_unlock("gem", "MG03").ok, "cannot overspend shared balance")
	check(m.request_equip("catalyst", "MC05").ok and m.get_state().equipped.catalyst == "MC05", "swap to a paid unlock")
	reloaded = Meta.new(test_path)
	check(reloaded.load_state().ok and reloaded.get_state() == m.get_state(), "upgrades and spending survive disk reload")
	var copy = m.get_state()
	copy.dust = 9999
	copy.levels.MC03 = 3
	check(m.get_state().dust == 15 and not m.get_state().levels.has("MC03"), "external state mutation cannot grant progress")
	check(not m.request_unlock("catalyst", "MC01").ok and not m.request_unlock("catalyst", "MC03").ok, "removed temporary catalysts rejected")
	# Each gem's displayed stat comes from its current total tier, never summed tiers.
	for gem_id in catalog.gems:
		for level in range(1, int(catalog.progression.max_level) + 1):
			fixture = initial.duplicate(true)
			fixture.levels[gem_id] = level
			fixture.equipped.gem = gem_id
			fixture.free_claimed.gem = true
			fixture.version = Meta.PREVIOUS_SAVE_VERSION
			fixture.erase("gem_state")
			_store_fixture(test_path, fixture)
			check(m.load_state().ok, "gem tier fixture loads")
			stats = m.get_preview_stats()
			for stat in ["health", "shield", "attack"]:
				var expected = catalog.player[stat]
				if stat == catalog.gems[gem_id].stat:
					expected += catalog.gems[gem_id].flat_by_level[level - 1]
				check(stats[stat] == expected, "%s level %d only adds current %s tier" % [gem_id, level, stat])
	# Invalid old progress is visible as an error and stays byte for byte intact.
	var corruptions: Array = ["{invalid json", "[]"]
	for field in ["version", "dust", "levels", "equipped", "free_claimed", "settlement_serial"]:
		var invalid = initial.duplicate(true)
		invalid.erase(field)
		corruptions.append(invalid)
	for invalid_dust in [-1, 2.5, true, "20", 1.0e100]:
		var invalid = initial.duplicate(true)
		invalid.dust = invalid_dust
		corruptions.append(invalid)
	var invalid = initial.duplicate(true)
	invalid.levels.MC04 = 4
	corruptions.append(invalid)
	invalid = initial.duplicate(true)
	invalid.equipped.gem = "MG01"
	corruptions.append(invalid)
	invalid = initial.duplicate(true)
	invalid.free_claimed.catalyst = true
	corruptions.append(invalid)
	invalid = initial.duplicate(true)
	invalid.levels.UNKNOWN = 0
	corruptions.append(invalid)
	for corruption in corruptions:
		_store_fixture(test_path, corruption)
		var corrupt_bytes = FileAccess.get_file_as_string(test_path)
		check(not m.load_state().ok and not m.is_loaded(), "invalid save is rejected")
		check(not m.request_unlock("catalyst", "MC04").ok, "failed load prevents overwriting old progress")
		check(FileAccess.get_file_as_string(test_path) == corrupt_bytes, "corrupt progress preserved exactly")
	# A failed transaction must not consume a free choice or money in memory.
	_store_fixture(test_path, initial)
	check(m.load_state().ok, "restore valid fixture")
	var blocked_parent = test_path + ".blocked"
	_store_fixture(blocked_parent, "This file prevents creating a child save directory.")
	m.save_path = blocked_parent + "/save.json"
	before = m.get_state()
	check(not m.request_unlock("gem", "MG01").ok, "disk write failure is reported")
	check(m.get_state() == before and not m.get_state().free_claimed.gem, "failed save preserves free choice")
	m.save_path = test_path
	check(m.request_unlock("gem", "MG01").ok, "free choice remains available after save retry")
	fixture = m.get_state()
	fixture.dust = 20
	_store_fixture(test_path, fixture)
	check(m.load_state().ok, "paid transaction fixture loads")
	m.save_path = blocked_parent + "/save.json"
	before = m.get_state()
	check(not m.request_draw_gems(1).ok and m.get_state() == before, "failed save does not charge draw or advance RNG")
	m.save_path = test_path
	check(FileAccess.get_file_as_string(test_path) == JSON.stringify(fixture), "failed upgrade leaves last good disk save unchanged")
	check(m.request_draw_gems(1).ok and m.get_state().dust == 15, "retry commits draw exactly once")
	_playable_settlement_tests(m, initial, blocked_parent)
	_legacy_catalyst_migration_tests(Meta.new(test_path), test_path, initial)
	var protected_account = Meta.new()
	check(not protected_account.reset_for_tests().ok, "real player reset is forbidden")
	check(m.reset_for_tests().ok and m.get_state().dust == initial.dust and m.get_gems().is_empty(), "explicit reset restricted to test root; new RNG stream")
	for path in fixture_paths:
		for candidate_path in [path, path + ".tmp"]:
			if FileAccess.file_exists(candidate_path):
				check(DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate_path)) == OK, "isolated fixture cleaned")
	print("Meta progression: %d checks, %d failures" % [checks, failures])
	return failures

func _playable_settlement_tests(m, initial: Dictionary, blocked_parent: String):
	var legacy = initial.duplicate(true)
	legacy.erase("run_serial")
	legacy.erase("last_settlement")
	_store_fixture(test_path, legacy)
	var disk_before = FileAccess.get_file_as_string(test_path)
	check(m.load_state().ok, "old v1 preparation save still loads")
	check(m.get_state().run_serial == 0 and m.get_state().last_settlement.is_empty(), "legacy bookkeeping defaults are normalized")
	check(FileAccess.get_file_as_string(test_path) == disk_before, "loading a legacy save does not silently rewrite it")
	var before = m.get_state()
	m.save_path = blocked_parent + "/save.json"
	check(not m.begin_playable_run().ok, "playable start reports failed token save")
	check(not m.is_in_run() and m.get_state() == before, "failed playable start preserves preparation")
	m.save_path = test_path
	check(FileAccess.get_file_as_string(test_path) == disk_before, "failed token save keeps old disk bytes")
	var begun = m.begin_playable_run()
	check(begun.ok and not begun.snapshot.preview_only, "playable snapshot is explicitly real")
	check(begun.run_id == begun.snapshot.run_id and not begun.run_id.is_empty(), "playable snapshot carries its persistent token")
	check(m.get_state().run_serial == 1 and m.get_state().settlement_serial == 0 and m.get_state().dust == 0, "beginning records token without granting rewards")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(test_path))
	check(int(saved.run_serial) == 1 and int(saved.dust) == 0 and saved.last_settlement.is_empty(), "run token is on disk before battle")
	begun.snapshot.player.health = -999
	begun.snapshot.equipment.gem = "MG01"
	check(m.get_run_snapshot().player.health == m.get_catalog().player.health and m.get_run_snapshot().equipment.gem.is_empty(), "playable snapshot cannot be mutated externally")
	check(not m.begin_playable_run().ok and not m.begin_run().ok, "playable run excludes simultaneous real and preview starts")
	check(not m.request_unlock("gem", "MG01").ok and not m.request_equip("gem").ok, "playable run locks preparation")
	check(not m.load_state().ok and m.is_loaded(), "playable run blocks disk reload without disabling settlement")
	check(not m.end_run().ok and m.is_in_run(), "preview end cannot bypass real settlement")
	var token: String = begun.run_id
	before = m.get_state()
	disk_before = FileAccess.get_file_as_string(test_path)
	for invalid_rooms in [[1, 1], [2], [1, 3], [0], [-1], [true], [1.5], ["1"], [61], range(1, 62)]:
		check(not m.settle_playable_run(token, invalid_rooms).ok, "invalid clear ledger rejected: " + str(invalid_rooms))
		check(m.is_in_run() and m.get_state() == before and FileAccess.get_file_as_string(test_path) == disk_before, "invalid ledger preserves live run and save")
	check(not m.settle_playable_run("unissued-token", [1]).ok, "unissued token cannot grant dust")
	var result = m.settle_playable_run(token, [])
	check(result.ok and not result.already_settled and result.dust_earned == 0, "death or abandonment before first clear earns zero")
	check(not m.is_in_run() and m.get_state().dust == 0 and m.get_state().settlement_serial == 1, "zero-clear settlement still completes the run once")
	disk_before = FileAccess.get_file_as_string(test_path)
	result = m.settle_playable_run(token, [])
	check(result.ok and result.already_settled and FileAccess.get_file_as_string(test_path) == disk_before, "repeat zero-clear settlement is a read-only success")
	check(not m.settle_playable_run(token, [1]).ok, "settled ledger cannot be upgraded to invent a clear")
	var next = m.begin_playable_run()
	check(next.ok and next.run_id != token, "next run uses a distinct persisted token")
	var snapshot: Dictionary = m.get_run_snapshot()
	check(m.settle_playable_run(token, []).ok and m.get_run_snapshot() == snapshot, "retrying previous settlement does not close a newer run")
	result = m.settle_playable_run(next.run_id, [1])
	check(result.ok and result.dust_earned == 1 and result.cleared_rooms == [1], "first real room awards source early-stage dust")
	check(m.get_state().dust == 1 and m.get_state().settlement_serial == 2 and not m.is_in_run(), "cleared reward is retained when run ends")
	result.state.dust = 9999
	result.cleared_rooms.append(2)
	check(m.get_state().dust == 1 and m.get_state().last_settlement.cleared_rooms == [1], "settlement result cannot mutate credited ledger")
	var reloaded = Meta.new(test_path)
	check(reloaded.load_state().ok and reloaded.get_state() == m.get_state(), "settlement survives a process-style reload")
	disk_before = FileAccess.get_file_as_string(test_path)
	result = reloaded.settle_playable_run(next.run_id, [1])
	check(result.ok and result.already_settled and result.dust_earned == 1, "last settlement token is idempotent after reload")
	check(reloaded.get_state().dust == 1 and FileAccess.get_file_as_string(test_path) == disk_before, "reopened settlement cannot grant a second reward")
	check(m.begin_run().ok, "preview still starts after real settlement")
	check(not m.settle_playable_run("preview", [1]).ok and m.is_in_run(), "preview has no usable settlement token")
	check(m.end_run().ok and m.get_state().dust == 1, "preview remains rewardless after real settlement")
	# Simulate forced closure: a new object reads only the prior persistent account.
	var unfinished = m.begin_playable_run()
	check(unfinished.ok, "force-close fixture starts a real run")
	var after_close = Meta.new(test_path)
	check(after_close.load_state().ok and not after_close.is_in_run(), "unfinished run is not resumable after reload")
	check(after_close.get_state().dust == 1 and not after_close.settle_playable_run(unfinished.run_id, [1]).ok, "force close loses only uncredited run income")
	var fresh = after_close.begin_playable_run()
	check(fresh.ok and fresh.run_id != unfinished.run_id, "force close cannot reuse an unfinished token")
	check(after_close.settle_playable_run(fresh.run_id, []).ok, "new run works after forced closure")
	# Use the reloaded owner from now on, rather than the discarded process object.
	m = after_close
	var retry_run = m.begin_playable_run()
	check(retry_run.ok, "settlement save-failure fixture starts")
	before = m.get_state()
	snapshot = m.get_run_snapshot()
	disk_before = FileAccess.get_file_as_string(test_path)
	m.save_path = blocked_parent + "/save.json"
	check(not m.settle_playable_run(retry_run.run_id, [1]).ok, "failed settlement save is reported")
	check(m.get_state() == before and m.get_run_snapshot() == snapshot, "failed settlement keeps uncredited run available for retry")
	m.save_path = test_path
	check(FileAccess.get_file_as_string(test_path) == disk_before, "failed settlement preserves last good save")
	result = m.settle_playable_run(retry_run.run_id, [1])
	check(result.ok and result.dust_earned == 1 and m.get_state().dust == before.dust + 1, "settlement retry credits exactly one room once")
	check(m.settle_playable_run(retry_run.run_id, [1]).already_settled and m.get_state().dust == before.dust + 1, "post-retry duplicate cannot credit twice")
	# Specification anchors cover stage boundaries and the three source boss bonuses.
	for anchor in [[9, 9], [15, 20], [45, 90], [59, 132], [60, 150]]:
		_store_fixture(test_path, initial)
		check(m.load_state().ok, "stage payout fixture loads")
		begun = m.begin_playable_run()
		result = m.settle_playable_run(begun.run_id, range(1, anchor[0] + 1))
		check(result.ok and result.dust_earned == anchor[1] and m.get_state().dust == anchor[1], "source-derived clear payout matches %d-room specification" % anchor[0])
	var valid_settlement = m.get_state()
	var corruptions: Array = []
	for invalid_serial in [-1, 0.5, true, "1", 0]:
		var invalid = valid_settlement.duplicate(true)
		invalid.run_serial = invalid_serial
		corruptions.append(invalid)
	for field in ["run_id", "run_serial", "cleared_rooms", "dust_earned", "settlement_serial"]:
		var invalid = valid_settlement.duplicate(true)
		invalid.last_settlement.erase(field)
		corruptions.append(invalid)
	for pair in [["run_id", "forged"], ["dust_earned", 999], ["cleared_rooms", [1, 3]], ["settlement_serial", 2]]:
		var invalid = valid_settlement.duplicate(true)
		invalid.last_settlement[pair[0]] = pair[1]
		corruptions.append(invalid)
	var invalid = valid_settlement.duplicate(true)
	invalid.last_settlement = "invalid"
	corruptions.append(invalid)
	for corruption in corruptions:
		_store_fixture(test_path, corruption)
		disk_before = FileAccess.get_file_as_string(test_path)
		check(not m.load_state().ok and not m.is_loaded(), "invalid playable bookkeeping is rejected")
		check(FileAccess.get_file_as_string(test_path) == disk_before, "invalid playable save is preserved for recovery")
	_store_fixture(test_path, initial)
	check(m.load_state().ok, "playable suite restores a valid isolated account")

func _legacy_state(levels: Dictionary, equipped: Dictionary, free_claimed: Dictionary, dust: int = 0, settlement_serial: int = 0, run_serial: int = 0, settlement: Dictionary = {}) -> Dictionary:
	return {
		"version": "meta-progression-1",
		"dust": dust,
		"levels": levels.duplicate(true),
		"equipped": equipped.duplicate(true),
		"free_claimed": free_claimed.duplicate(true),
		"settlement_serial": settlement_serial,
		"run_serial": run_serial,
		"last_settlement": settlement.duplicate(true),
	}

func _legacy_catalyst_migration_tests(m, test_path: String, initial: Dictionary):
	var levels = {"MC01": 1, "MC02": 0, "MC03": 0, "MG01": 0, "MG02": 0, "MG03": 1}
	var settlement = {"run_id": "local-run-2", "run_serial": 2, "cleared_rooms": [1], "dust_earned": 1, "settlement_serial": 1}
	var legacy = _legacy_state(levels, {"catalyst": "MC01", "gem": "MG03"}, {"catalyst": true, "gem": true}, 2, 1, 2, settlement)
	_store_fixture(test_path, legacy)
	var old_bytes = FileAccess.get_file_as_string(test_path)
	check(m.load_state().ok, "legacy catalyst save migrates in memory")
	check(FileAccess.get_file_as_string(test_path) == old_bytes, "legacy save is not rewritten on read")
	var state = m.get_state()
	check(state.version == Meta.SAVE_VERSION, "migrated state uses current save version")
	check(state.levels == {"MC04": 1, "MC05": 0, "MG01": 0, "MG02": 0, "MG03": 1}, "legacy fire level moves to MC04 and ice starts locked")
	check(state.equipped == {"catalyst": "MC04", "gem": "MG03"}, "legacy equipped catalyst becomes fire catalyst")
	check(state.free_claimed == {"catalyst": true, "gem": true}, "legacy free choice stays claimed")
	check(state.dust == 2 and state.run_serial == 2 and state.settlement_serial == 1, "legacy currency and run bookkeeping survive")
	check(state.last_settlement == settlement, "legacy settlement record survives")
	var fire = m.get_item_status("catalyst", "MC04")
	check(fire.name == "火法术触媒" and fire.level == 1 and fire.equipped, "migrated fire catalyst is usable")
	check(fire.related_spell_names.size() == 10, "fire catalyst lists all ten fire spells")
	var ice = m.get_item_status("catalyst", "MC05")
	check(ice.name == "冰法术触媒" and ice.level == 0 and not ice.free, "ice catalyst is present but costs dust")
	check(m.get_item_status("catalyst", "MC01").is_empty(), "removed catalyst id is unknown")
	check(m.request_equip("catalyst", "").ok, "migrated account can unequip")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(test_path))
	check(saved.version == Meta.SAVE_VERSION and int(saved.levels.MC04) == 1, "first committed change persists migration")
	var reopened = Meta.new(test_path)
	check(reopened.load_state().ok and reopened.get_state() == m.get_state(), "migrated progress survives reload")

	# Duplicate paid levels are refunded once; the highest level is inherited, not summed.
	levels = {"MC01": 1, "MC02": 2, "MC03": 1, "MG01": 0, "MG02": 0, "MG03": 0}
	legacy = _legacy_state(levels, {"catalyst": "MC02", "gem": ""}, {"catalyst": true, "gem": false})
	_store_fixture(test_path, legacy)
	check(m.load_state().ok, "legacy duplicate investment migrates")
	state = m.get_state()
	check(state.levels.MC04 == 2 and state.levels.MC05 == 0, "fire catalyst inherits only the highest legacy level")
	check(state.dust == 40, "duplicate paid catalyst levels are refunded")
	check(state.equipped.catalyst == "MC04", "legacy second catalyst also equips fire")
	check(m.get_item_status("catalyst", "MC04").level == 2, "inherited level stays visible")

	# A legacy account without a catalyst still gets the one free formal choice.
	levels = {"MC01": 0, "MC02": 0, "MC03": 0, "MG01": 0, "MG02": 0, "MG03": 0}
	legacy = _legacy_state(levels, {"catalyst": "", "gem": ""}, {"catalyst": false, "gem": false})
	_store_fixture(test_path, legacy)
	check(m.load_state().ok, "legacy empty catalyst state migrates")
	state = m.get_state()
	check(state.levels.MC04 == 0 and state.levels.MC05 == 0 and not state.free_claimed.catalyst, "empty legacy catalyst keeps the free choice available")
	check(m.get_item_status("catalyst", "MC04").free and m.get_item_status("catalyst", "MC05").free, "both formal catalysts share the unused free choice")

	# Invalid legacy data is rejected without overwriting the file.
	var corruptions: Array = []
	levels = {"MC01": 4, "MC02": 0, "MC03": 0, "MG01": 0, "MG02": 0, "MG03": 0}
	corruptions.append(_legacy_state(levels, {"catalyst": "MC01", "gem": ""}, {"catalyst": true, "gem": false}))
	levels = {"MC01": 0, "MC02": 0, "MC03": 0, "MG01": 0, "MG02": 0, "UNKNOWN": 0}
	corruptions.append(_legacy_state(levels, {"catalyst": "", "gem": ""}, {"catalyst": false, "gem": false}))
	var bad_settlement = settlement.duplicate(true)
	bad_settlement.dust_earned = 999
	levels = {"MC01": 1, "MC02": 0, "MC03": 0, "MG01": 0, "MG02": 0, "MG03": 0}
	corruptions.append(_legacy_state(levels, {"catalyst": "MC01", "gem": ""}, {"catalyst": true, "gem": false}, 0, 1, 2, bad_settlement))
	for corruption in corruptions:
		_store_fixture(test_path, corruption)
		var corrupt_bytes = FileAccess.get_file_as_string(test_path)
		check(not m.load_state().ok and not m.is_loaded(), "invalid legacy catalyst save is rejected")
		check(FileAccess.get_file_as_string(test_path) == corrupt_bytes, "invalid legacy save is preserved exactly")
	_store_fixture(test_path, {"version": "meta-progression-1", "levels": {}})
	check(not m.load_state().ok, "unmigratable legacy shape is rejected")
	_store_fixture(test_path, initial)
	check(m.load_state().ok, "migration suite restores a valid current account")

