extends RefCounted
## Meta progression and the v4 gem account. All saves stay under the isolated
## test root; no production account, UI or natural route is touched.
const Meta = preload("res://scripts/core/meta_progression.gd")
const Gems = preload("res://scripts/core/magic_gems.gd")
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file = FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "fixture opens")
	if file != null:
		file.store_string(value if value is String else JSON.stringify(value))
		file.close()
	if not fixture_paths.has(path):
		fixture_paths.append(path)

func _seed_state(seed_value: int = 20261022) -> String:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	return str(rng.state)

## One attribute line with the same value source the production library uses.
func _gem(lib, serial: int, rarity: String, stats: Array, core: String = "", tiers: Array = []) -> Dictionary:
	var affixes: Array = []
	var gold: bool = rarity == "gold"
	for index in stats.size():
		var tier: int = int(tiers[index]) if index < tiers.size() else 1
		affixes.append(lib.line(str(stats[index]), tier, not gold and index == 0))
	return {"id": "gem-%d" % serial, "serial": serial, "rarity": rarity, "affixes": affixes, "core": core, "locked": false, "origin": "draw"}

func _install(m, gems: Array, dust: int = 0, essence: int = 0, slots: Array = [], gold_misses: int = 0, rare_misses: int = 0, rng_state: String = "") -> Dictionary:
	var state: Dictionary = m.get_state()
	state.dust = dust
	state.settlement_serial = 0
	state.run_serial = 0
	state.last_settlement = {}
	state.gem_state.inventory = gems.duplicate(true)
	state.gem_state.slots = slots.duplicate() if slots.size() == 4 else ["", "", "", ""]
	state.gem_state.serial = gems.size()
	state.gem_state.draws = gems.size()
	state.gem_state.salvaged = 0
	state.gem_state.essence = essence
	state.gem_state.work_serial = 0
	state.gem_state.pending_reforge = {}
	state.gem_state.gold_misses = gold_misses
	state.gem_state.rare_misses = rare_misses
	state.gem_state.cumulative_cleared = 0
	state.gem_state.milestone_claimed = []
	if not rng_state.is_empty():
		state.gem_state.rng_state = rng_state
	_store_fixture(test_path, state)
	check(m.load_state().ok, "gem fixture loads " + m.error)
	return m.get_state()

func run() -> int:
	test_path = Meta.TEST_SAVE_ROOT + "suite_%d.json" % Time.get_ticks_usec()
	var m = Meta.new(test_path)
	check(m.load_state().ok, "new isolated account loads")
	if not m.is_loaded():
		return failures + 1
	fixture_paths.append(test_path)
	var catalog = m.get_catalog()
	var initial = m.get_state()
	_new_account(m, catalog, initial)
	_catalyst_progression(m, catalog)
	_draws_and_pity(m)
	_slots_and_effects(m)
	_reforge(m)
	_salvage(m)
	_snapshot_and_settlement(m)
	_persistence(m)
	_version_guard(m, initial)
	_corruptions(m, initial)
	_save_failures(m, initial)
	_reset(m)
	for path in fixture_paths:
		for candidate_path in [path, path + ".tmp"]:
			if FileAccess.file_exists(candidate_path):
				check(DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate_path)) == OK, "isolated fixture cleaned")
	print("Meta progression: %d checks, %d failures" % [checks, failures])
	return failures

func _new_account(m, catalog: Dictionary, initial: Dictionary):
	check(initial.dust == 0, "new account has zero dust")
	check(initial.levels.size() == 6 and initial.levels.size() == catalog.catalysts.size(), "new account lists exactly six catalysts")
	for item_id in catalog.catalysts:
		check(initial.levels.has(item_id) and int(initial.levels[item_id]) == 0, "new catalyst starts locked: " + str(item_id))
	check(initial.equipped == {"catalyst": ""}, "only the catalyst slot exists")
	check(initial.free_claimed == {"catalyst": false}, "only one free entitlement exists")
	check(initial.settlement_serial == 0 and initial.run_serial == 0, "no invented settlement")
	check(initial.gem_state.schema_version == 4 and m.gems.is_modern(initial.gem_state), "fresh gems use schema four")
	check(initial.gem_state.inventory.is_empty() and initial.gem_state.slots == ["", "", "", ""] and initial.gem_state.essence == 0, "fresh account owns no gems, four empty slots, zero essence")
	check(m.get_gems().is_empty(), "gem inventory accessor starts empty")
	check(m.get_items("catalyst").size() == 6 and m.get_items("gem").is_empty(), "all six catalysts listed and no inherited gems")
	for item in m.get_items("catalyst"):
		check(item.free and item.can_unlock and item.cost == 0, "first catalyst choice is free: " + str(item.id))
		check(item.name == catalog.catalysts[item.id].name, "catalyst name from source: " + str(item.id))
		check(item.effect_by_level == catalog.spell_sampling.catalyst_affinity_by_level, "priority from shared sampling source: " + str(item.id))
		for index in item.related_spells.size():
			check(item.related_spell_names[index] == catalog.spells[item.related_spells[index]].name, "related spell name from source")
	var external = m.get_catalog()
	external.player.health = -99
	check(m.get_catalog().player.health == catalog.player.health, "catalog is a copy")
	check(m.get_state().gem_state == initial.gem_state, "state copy cannot mutate the account")

func _catalyst_progression(m, catalog: Dictionary):
	check(m.request_unlock("catalyst", "MC04").ok, "first catalyst chosen")
	check(m.get_state().equipped.catalyst == "MC04", "free catalyst auto equips")
	check(m.get_state().free_claimed.catalyst and not m.get_state().free_claimed.has("gem"), "catalyst choice consumes only its own entitlement")
	check(m.get_state().dust == 0, "free choice does not grant or consume dust")
	check(not m.get_item_status("catalyst", "MC05").free, "later catalyst costs dust")
	check(m.get_item_status("catalyst", "MC05").cost == catalog.progression.unlock_cost, "paid unlock price from source")
	var before = m.get_state()
	var saved_before = FileAccess.get_file_as_string(test_path)
	check(not m.request_unlock("catalyst", "MC04").ok, "duplicate unlock rejected")
	check(not m.request_unlock("catalyst", "MC05").ok, "unaffordable unlock rejected")
	check(not m.request_unlock("catalyst", "MC01").ok, "removed catalyst id rejected")
	check(not m.request_unlock("gem", "MC04").ok, "gem kind is no longer an unlock target")
	check(not m.request_upgrade("gem", "MG01").ok, "inherited gems are gone")
	check(not m.request_equip("other", "MC04").ok, "unknown equipment kind rejected")
	check(m.get_state() == before and FileAccess.get_file_as_string(test_path) == saved_before, "rejected requests preserve memory and disk")
	check(m.request_equip("catalyst").ok and m.get_state().equipped.catalyst.is_empty(), "unequip permitted")
	check(m.request_equip("catalyst", "MC04").ok and m.get_state().equipped.catalyst == "MC04", "free re-equip permitted")
	var fixture = m.get_state()
	fixture.dust = 80
	_store_fixture(test_path, fixture)
	check(m.load_state().ok, "funded catalyst fixture loads")
	check(m.request_upgrade("catalyst", "MC04").ok and m.get_state().dust == 60 and m.get_state().levels.MC04 == 2, "second level costs twenty once")
	check(m.request_upgrade("catalyst", "MC04").ok and m.get_state().dust == 20 and m.get_state().levels.MC04 == 3, "third level costs forty once")
	check(not m.request_upgrade("catalyst", "MC04").ok, "catalyst level cap enforced")
	check(m.request_unlock("catalyst", "MC05").ok and m.get_state().dust == 0 and m.get_state().levels.MC05 == 1, "paid unlock spends exact price")
	check(m.get_state().equipped.catalyst == "MC04", "paid unlock preserves equipped catalyst")
	check(m.request_equip("catalyst", "MC05").ok, "swap to a paid unlock")
	var reloaded = Meta.new(test_path)
	check(reloaded.load_state().ok and reloaded.get_state() == m.get_state(), "catalyst progress survives disk reload")
	var blocked_parent = test_path + ".blocked"
	_store_fixture(blocked_parent, "This file prevents creating a child save directory.")
	m.save_path = blocked_parent + "/save.json"
	before = m.get_state()
	check(not m.request_upgrade("catalyst", "MC04").ok and m.get_state() == before, "failed save leaves catalyst progress unchanged")
	m.save_path = test_path

func _draws_and_pity(m):
	var seeded = _seed_state()
	var lib = m.gems
	_install(m, [], 100, 0, [], 0, 0, seeded)
	var one = m.request_draw_gems(1)
	check(one.ok and one.gems.size() == 1 and m.get_state().dust == 95, "single draw costs five and returns one gem")
	check(m.get_state().gem_state.inventory.size() == 1 and m.get_state().gem_state.draws == 1 and m.get_state().gem_state.serial == 1, "single draw records one instance")
	var ten = m.request_draw_gems(10)
	check(ten.ok and ten.gems.size() == 10 and m.get_state().dust == 45, "ten draw costs fifty and returns ten gems")
	check(m.get_state().gem_state.inventory.size() == 11 and m.get_state().gem_state.draws == 11 and m.get_state().gem_state.serial == 11, "ten draw keeps instance ledger")
	var rare_in_ten: bool = false
	for gem in ten.gems:
		rare_in_ten = rare_in_ten or str(gem.rarity) in ["purple", "gold"]
	check(rare_in_ten, "ten draw contains purple or better")
	for gem in ten.gems:
		check(str(gem.rarity) in lib.RARITIES, "draw rarity is known: " + str(gem.rarity))
		check(gem.affixes.size() == int(lib.rules.affix_counts[gem.rarity]), "draw affix count matches rarity: " + str(gem.id))
		var used: Array = []
		for index in gem.affixes.size():
			var affix: Dictionary = gem.affixes[index]
			check(affix.stat not in used, "draw attributes stay unique: " + str(gem.id))
			used.append(affix.stat)
			var gold: bool = str(gem.rarity) == "gold"
			check(affix.role == ("side" if gold else ("main" if index == 0 else "side")), "draw roles follow rarity: " + str(gem.id))
			var values: Array = lib.rules.affixes[affix.stat].tiers if gold or index > 0 else lib.rules.affixes[affix.stat].main_tiers
			check(affix.value == values[int(affix.tier) - 1], "draw value matches tier source: " + str(gem.id))
		if str(gem.rarity) == "gold":
			check(str(gem.core) in lib.rules.cores, "gold draw carries a known keystone")
		else:
			check(str(gem.core).is_empty(), "coloured draw carries no keystone")
	check(lib.validate(m.get_state().gem_state).is_empty(), "drawn account is valid")
	# Ten singles must equal one ten-draw with the same RNG stream.
	var singles_path = Meta.TEST_SAVE_ROOT + "singles_%d.json" % Time.get_ticks_usec()
	_install(m, [], 100, 0, [], 0, 0, seeded)
	_store_fixture(singles_path, m.get_state())
	var singles = Meta.new(singles_path)
	check(singles.load_state().ok, "same-RNG account loads")
	check(m.request_draw_gems(10).ok, "repeated ten draw commits")
	for index in 10:
		check(singles.request_draw_gems(1).ok, "single draw commits")
	check(singles.get_state() == m.get_state(), "ten single draws equal one ten draw including pity and RNG")
	# Invalid counts and balances never spend or advance.
	var before = m.get_state()
	var disk = FileAccess.get_file_as_string(test_path)
	for count in [0, 2, 9, 11, -1]:
		check(not m.request_draw_gems(count).ok, "unsupported draw count rejected: " + str(count))
	check(m.get_state() == before and FileAccess.get_file_as_string(test_path) == disk, "rejected draw preserves account and save")
	_install(m, [], 4, 0, [], 0, 0, seeded)
	before = m.get_state()
	check(not m.request_draw_gems(1).ok and m.get_state() == before, "insufficient dust draw rejected")
	# Purple pity: nine missing draws force the tenth.
	var streak: Array = []
	for index in 9:
		streak.append(_gem(lib, index + 1, "green", [["attack", "health", "shield", "defense", "crit_rate", "crit_multiplier", "cdr", "speed"][index % 8]], "", [1]))
	_install(m, streak, 100, 0, [], 0, 9, seeded)
	var pity = m.request_draw_gems(1)
	check(pity.ok and str(pity.gems[0].rarity) == "purple", "ninth purple miss forces the tenth purple")
	check(m.get_state().gem_state.rare_misses == 0 and m.get_state().gem_state.gold_misses == 1, "purple pity resets only on purple or better")
	# Gold hard pity: forty-nine missing draws force the fiftieth.
	var long_streak: Array = []
	for index in 49:
		long_streak.append(_gem(lib, index + 1, "green", [["attack", "health", "shield", "defense", "crit_rate", "crit_multiplier", "cdr", "speed"][index % 8]], "", [1]))
	_install(m, long_streak, 100, 0, [], 49, 0, seeded)
	var gold = m.request_draw_gems(1)
	check(gold.ok and str(gold.gems[0].rarity) == "gold", "forty-ninth gold miss forces the fiftieth gold")
	check(m.get_state().gem_state.gold_misses == 0 and m.get_state().gem_state.rare_misses == 0, "gold pity resets both counters")
	check(m.gems.validate(m.get_state().gem_state).is_empty(), "pity account stays valid")

func _slots_and_effects(m):
	var lib = m.gems
	var gems: Array = [
		_gem(lib, 1, "green", ["attack"], "", [1]),
		_gem(lib, 2, "blue", ["health", "shield"], "", [1, 1]),
		_gem(lib, 3, "purple", ["attack", "defense", "cdr"], "", [1, 1, 1]),
		_gem(lib, 4, "gold", ["speed", "crit_rate", "crit_multiplier"], "inferno", [1, 1, 1]),
	]
	_install(m, gems)
	for index in 4:
		check(m.request_equip_gem(index, "gem-%d" % (index + 1)).ok, "slot %d accepts a gem" % index)
	check(m.get_state().gem_state.slots == ["gem-1", "gem-2", "gem-3", "gem-4"], "four slots hold a mixed-quality loadout")
	check(m.request_equip_gem(1, "gem-1").ok, "same instance moved between slots")
	check(m.get_state().gem_state.slots == ["", "gem-1", "gem-3", "gem-4"], "moving clears the previous slot")
	check(m.request_equip_gem(1, "").ok and m.get_state().gem_state.slots[1].is_empty(), "slot can be emptied")
	var before = m.get_state()
	for slot in [-1, 4, 9]:
		check(not m.request_equip_gem(slot, "gem-2").ok, "invalid slot rejected: " + str(slot))
	check(not m.request_equip_gem(0, "gem-99").ok, "unknown gem cannot be equipped")
	check(m.get_state() == before, "rejected equipment preserves account")
	check(m.request_equip_gem(0, "gem-1").ok and m.request_equip_gem(1, "gem-2").ok, "restore two slots")
	check(m.request_equip_gem(2, "gem-3").ok and m.request_equip_gem(3, "gem-4").ok, "restore four slots")
	var totals: Dictionary = lib.totals(m.get_state().gem_state)
	check(totals.attack == 8.0 and totals.health == 20.0 and totals.shield == 4.0, "flat totals follow main/side tier sources")
	check(near(float(totals.defense), 2.0) and near(float(totals.cdr), 0.01) and near(float(totals.speed), 0.01), "secondary totals follow tier sources")
	var stats: Dictionary = m.get_preview_stats()
	check(stats.health == 320.0 and stats.shield == 104.0 and stats.attack == 108.0, "preview adds equipped totals once")
	# Duplicate keystones: only the earliest slot may act.
	var dup: Array = [
		_gem(lib, 1, "gold", ["attack", "health", "shield"], "inferno", [1, 2, 3]),
		_gem(lib, 2, "gold", ["attack", "health", "shield"], "inferno", [3, 2, 1]),
	]
	_install(m, dup, 0, 0, ["gem-1", "gem-2", "", ""])
	check(lib.active_effects(m.get_state().gem_state) == ["inferno"], "duplicate keystones act once")
	check(lib.first_effect(m.get_state().gem_state) == "inferno", "first effect follows slot order")
	check(lib.duplicate_effects(m.get_state().gem_state) == ["inferno"], "duplicate keystone reported")
	check(lib.totals(m.get_state().gem_state).attack == 6.0, "duplicate keystone still contributes attributes")
	check(m.request_equip_gem(2, "gem-1").ok, "later slot can hold a duplicate")
	check(m.get_state().gem_state.slots == ["", "gem-2", "gem-1", ""], "moved duplicate uses the earliest occupied slot")
	check(lib.first_effect(m.get_state().gem_state) == "inferno", "remaining duplicate still acts")
	check(m.request_equip_gem(1, "").ok, "remove the leading duplicate")
	check(lib.active_effects(m.get_state().gem_state) == ["inferno"], "the next copy takes over")
	var distinct: Array = [
		_gem(lib, 1, "gold", ["attack", "health", "shield"], "inferno", [1, 1, 1]),
		_gem(lib, 2, "gold", ["attack", "health", "shield"], "wind", [1, 1, 1]),
	]
	_install(m, distinct, 0, 0, ["gem-1", "gem-2", "", ""])
	check(lib.active_effects(m.get_state().gem_state) == ["inferno", "wind"], "distinct keystones both act")
	check(lib.duplicate_effects(m.get_state().gem_state).is_empty(), "distinct keystones are not duplicates")
	check(lib.first_effect(m.get_state().gem_state) == "inferno", "first effect is the lowest slot")
	var aegis: Array = [_gem(lib, 1, "gold", ["attack", "health", "shield"], "aegis", [1, 1, 1])]
	_install(m, aegis, 0, 0, ["gem-1", "", "", ""])
	var converted: Dictionary = m.get_preview_stats()
	check(near(float(converted.health), 217.0), "aegis converts thirty percent of current health")
	check(near(float(converted.shield), 308.6), "aegis converts life to shield at 2.2")

func _reforge(m):
	var lib = m.gems
	var purple: Array = [_gem(lib, 1, "purple", ["attack", "health", "shield"], "", [2, 3, 1])]
	_install(m, purple, 0, 200, [], 0, 0, _seed_state())
	var id = "gem-1"
	check(m.reforge_cost(id, []) == 20 and m.reforge_cost(id, [0]) == 35, "reforge cost starts at twenty plus fifteen per lock")
	check(m.reforge_cost(id, [0, 1]) == 50 and m.reforge_cost(id, [0, 1, 2]) == 65, "reforge cost grows linearly with locks")
	check(m.reforge_cost("missing", []) == -1, "missing gem has no reforge price")
	check(not m.request_reroll_gem(id, [0, 1, 2]).ok, "cannot lock every attribute")
	check(not m.request_reroll_gem(id, [0, 1, 2, 3]).ok, "more than three locks rejected")
	check(not m.request_reroll_gem(id, [3]).ok, "attribute index out of range rejected")
	check(not m.request_reroll_gem(id, ["core"]).ok, "coloured gem cannot lock a keystone")
	check(not m.request_reroll_gem("missing", []).ok, "missing gem cannot be rerolled")
	var before = m.get_state()
	check(not m.request_reroll_gem(id, [0, 1, 2, 0]).ok and m.get_state() == before, "invalid lock list preserves account")
	# Insufficient essence is rejected before paying.
	_install(m, purple, 0, 34, [], 0, 0, _seed_state())
	check(not m.request_reroll_gem(id, [0]).ok and m.get_state().gem_state.essence == 34, "insufficient essence rejected without paying")
	# Gold has no main line, so every part (keystone plus three equal
	# attributes) can be freely locked or rerolled inside one candidate.
	var gold: Array = [_gem(lib, 1, "gold", ["attack", "health", "shield"], "inferno", [1, 2, 3])]
	_install(m, gold, 0, 200, [], 0, 0, _seed_state())
	check(not m.request_reroll_gem(id, ["core", 0, 1, 2]).ok, "gold rejects four locks")
	var two_locks = m.request_reroll_gem(id, [0, 1])
	check(two_locks.ok and m.get_state().gem_state.essence == 150, "two locked attributes cost fifty once")
	var pending: Dictionary = m.get_state().gem_state.pending_reforge
	check(pending.gem_id == id and pending.mode == "reroll" and pending.cost == 50 and pending.locks == [0, 1], "pending candidate records source, cost and locks")
	check(pending.old.affixes == lib.find(m.get_state().gem_state, id).affixes, "pending candidate keeps the exact original")
	check(pending.candidate.affixes[0] == pending.old.affixes[0] and pending.candidate.affixes[1] == pending.old.affixes[1], "locked attributes are unchanged in the candidate")
	check(pending.candidate.affixes != pending.old.affixes, "at least one unlocked attribute is rerolled")
	check(str(pending.candidate.core) in lib.rules.cores, "candidate carries a known keystone")
	check(lib.validate(m.get_state().gem_state).is_empty(), "paid pending candidate is a valid save")
	check(not m.request_draw_gems(1).ok and not m.request_lock_gem(id).ok and not m.request_salvage_gems([id]).ok and not m.request_equip_gem(0, id).ok, "unresolved candidate blocks every other gem action")
	check(not m.request_reroll_gem(id, []).ok, "unresolved candidate blocks another reroll")
	check(m.get_state().gem_state.pending_reforge == pending, "blocked actions do not disturb the candidate")
	check(not m.resolve_reforge(int(pending.token) + 1, true).ok, "unknown token rejected")
	check(m.resolve_reforge(int(pending.token), true).ok, "adopt commits the candidate once")
	check(m.get_state().gem_state.pending_reforge.is_empty(), "adoption clears the candidate")
	var adopted: Dictionary = lib.find(m.get_state().gem_state, id)
	check(adopted.affixes == pending.candidate.affixes, "adopted attributes match the candidate")
	check(adopted.affixes[0] == pending.old.affixes[0] and adopted.affixes[1] == pending.old.affixes[1], "adoption never changes a locked line")
	check(not m.resolve_reforge(int(pending.token), false).ok, "consumed token cannot repeat")
	var reloaded = Meta.new(test_path)
	check(reloaded.load_state().ok and reloaded.get_state() == m.get_state(), "adopted account survives disk reload")
	m = reloaded
	# A locked keystone survives while all three attributes change.
	var current_core: String = lib.effect_of(lib.find(m.get_state().gem_state, id))
	var core_lock = m.request_reroll_gem(id, ["core"])
	check(core_lock.ok and int(core_lock.candidate.cost) == 35 and m.get_state().gem_state.essence == 115, "keystone lock costs one step")
	check(core_lock.candidate.candidate.core == current_core, "locked keystone candidate keeps the effect")
	var core_pending: Dictionary = m.get_state().gem_state.pending_reforge
	check(m.resolve_reforge(int(core_pending.token), true).ok, "locked keystone adoption commits")
	check(lib.effect_of(lib.find(m.get_state().gem_state, id)) == current_core, "locked keystone is unchanged")
	# Full reroll changes the keystone and keeps the candidate valid.
	var free_core = m.request_reroll_gem(id, [])
	check(free_core.ok and int(free_core.candidate.cost) == 20 and m.get_state().gem_state.essence == 95, "unlocked keystone rerolls at base price")
	check(free_core.candidate.candidate.core != current_core, "unlocked keystone candidate changes effect")
	var free_pending: Dictionary = m.get_state().gem_state.pending_reforge
	check(m.resolve_reforge(int(free_pending.token), true).ok, "unlocked keystone adoption commits")
	check(lib.effect_of(lib.find(m.get_state().gem_state, id)) != current_core, "unlocked keystone is replaced")
	# Three locks are allowed on gold and leave only the keystone random.
	var three_locks = m.request_reroll_gem(id, [0, 1, 2])
	check(three_locks.ok and int(three_locks.candidate.cost) == 65 and m.get_state().gem_state.essence == 30, "three locks are the maximum and cost sixty-five")
	check(three_locks.candidate.candidate.affixes == lib.find(m.get_state().gem_state, id).affixes, "three-lock candidate keeps every attribute")
	var three_pending: Dictionary = m.get_state().gem_state.pending_reforge
	check(m.resolve_reforge(int(three_pending.token), true).ok, "three-lock adoption commits")
	# Keeping the old result charges once and changes nothing.
	var keep = m.request_reroll_gem(id, [])
	check(keep.ok and m.get_state().gem_state.essence == 10, "final reroll charges again")
	var keep_pending: Dictionary = m.get_state().gem_state.pending_reforge
	check(m.resolve_reforge(int(keep_pending.token), false).ok, "keep-old commits")
	check(lib.find(m.get_state().gem_state, id).affixes == keep_pending.old.affixes, "keep-old preserves every attribute")
	check(m.get_state().gem_state.essence == 10, "keep-old grants no refund")
	check(lib.validate(m.get_state().gem_state).is_empty(), "rerolled gold account is valid")

func _salvage(m):
	var lib = m.gems
	var gems: Array = [
		_gem(lib, 1, "green", ["attack"], "", [1]),
		_gem(lib, 2, "blue", ["health", "shield"], "", [1, 1]),
		_gem(lib, 3, "purple", ["attack", "defense", "cdr"], "", [1, 1, 1]),
		_gem(lib, 4, "gold", ["speed", "crit_rate", "crit_multiplier"], "inferno", [1, 1, 1]),
	]
	_install(m, gems, 0, 0, ["gem-1", "", "", ""])
	var before = m.get_state()
	check(not m.request_salvage_gems([]).ok, "empty salvage list rejected")
	check(not m.request_salvage_gems(["gem-1"]).ok and m.get_state() == before, "equipped gem cannot be salvaged")
	check(not m.request_salvage_gems(["gem-1", "gem-1"]).ok, "duplicate salvage entry rejected")
	check(not m.request_salvage_gems(["gem-99"]).ok, "unowned gem cannot be salvaged")
	check(not m.request_salvage_gems(["gem-2", "gem-2"]).ok and m.get_state() == before, "repeated ids fail without partial salvage")
	var green = m.request_salvage_gems(["gem-2"])
	check(green.ok and green.essence_gained == 3 and m.get_state().gem_state.essence == 3, "blue salvage yields three essence")
	check(m.get_state().gem_state.salvaged == 1 and m.get_state().gem_state.inventory.size() == 3, "salvage records one removed instance")
	check(m.get_state().gem_state.serial == 4 and m.get_state().gem_state.draws == 4, "salvage keeps instance and draw ledgers")
	check(lib.validate(m.get_state().gem_state).is_empty(), "salvaged account stays valid")
	check(m.request_lock_gem("gem-3").ok, "third gem locked")
	check(not m.request_salvage_gems(["gem-3"]).ok, "locked gem cannot be salvaged")
	check(m.request_lock_gem("gem-3").ok and m.request_salvage_gems(["gem-3"]).essence_gained == 10, "unlock then purple yields ten")
	check(m.request_salvage_gems(["gem-4"]).essence_gained == 10, "gold yields ten essence")
	check(m.get_state().gem_state.essence == 23 and m.get_state().gem_state.salvaged == 3, "salvage ledger accumulates exactly")
	check(m.request_equip_gem(0, "").ok and m.request_salvage_gems(["gem-1"]).essence_gained == 1, "green yields one after unequipping")
	check(m.get_state().gem_state.essence == 24 and m.get_state().gem_state.inventory.is_empty(), "all four qualities yield green1 blue3 purple10 gold10")
	check(lib.validate(m.get_state().gem_state).is_empty(), "fully salvaged account is valid")
	var pair: Array = [
		_gem(lib, 1, "green", ["attack"], "", [1]),
		_gem(lib, 2, "green", ["health"], "", [1]),
		_gem(lib, 3, "blue", ["shield", "speed"], "", [1, 2]),
	]
	_install(m, pair, 0, 50, [], 0, 0, _seed_state())
	var batch = m.request_salvage_gems(["gem-1", "gem-2"])
	check(batch.ok and batch.essence_gained == 2 and m.get_state().gem_state.essence == 52, "batch salvage sums per-gem yields")
	check(m.get_state().gem_state.pending_reforge.is_empty(), "salvage leaves no pending candidate")
	var guard: Array = [
		_gem(lib, 1, "green", ["attack"], "", [1]),
		_gem(lib, 2, "gold", ["attack", "health", "shield"], "inferno", [1, 1, 1]),
	]
	_install(m, guard, 0, 40, [], 0, 0, _seed_state())
	check(m.request_reroll_gem("gem-2", ["core"]).ok, "reroll opens a candidate for salvage protection")
	check(not m.request_salvage_gems(["gem-1"]).ok, "candidate blocks salvage")
	var token: int = int(m.get_state().gem_state.pending_reforge.token)
	check(m.resolve_reforge(token, false).ok, "discard the protection fixture candidate")
	check(m.request_lock_gem("gem-1").ok and not m.request_salvage_gems(["gem-1"]).ok, "lock still protects salvage after resolving")
	var reopened = Meta.new(test_path)
	check(reopened.load_state().ok and reopened.get_state() == m.get_state(), "salvage results survive reload")

func _snapshot_and_settlement(m):
	var lib = m.gems
	var loadout: Array = [
		_gem(lib, 1, "green", ["attack"], "", [1]),
		_gem(lib, 2, "purple", ["health", "defense", "cdr"], "", [2, 1, 3]),
		_gem(lib, 3, "gold", ["speed", "crit_rate", "crit_multiplier"], "inferno", [1, 2, 3]),
	]
	_install(m, loadout, 0, 0, ["gem-1", "gem-2", "gem-3", ""], 0, 0, _seed_state())
	var expected_totals: Dictionary = lib.totals(m.get_state().gem_state)
	var stats: Dictionary = m.get_preview_stats()
	var started = m.begin_run()
	check(started.ok and started.snapshot.preview_only, "run snapshot is explicitly a preview")
	check(started.snapshot.player == stats, "snapshot uses actual prepared stats")
	check(started.snapshot.gem_slots == ["gem-1", "gem-2", "gem-3", ""], "snapshot freezes four slot references")
	check(started.snapshot.gem_bonuses == expected_totals, "snapshot carries equipped totals")
	check(started.snapshot.gem_core == "inferno" and started.snapshot.gem_cores == ["inferno"], "snapshot carries the first active effect")
	check(int(started.snapshot.gem_effects) == 1, "snapshot counts active effects instead of equipped copies")
	check(started.snapshot.levels.size() == 6 and not started.snapshot.equipment.has("gem"), "snapshot keeps six catalyst levels and no gem equipment key")
	started.snapshot.player.health = -20
	started.snapshot.gem_cores.append("wind")
	check(m.get_run_snapshot().player == stats and m.get_run_snapshot().gem_cores == ["inferno"], "snapshot returned by value")
	var before = m.get_state()
	check(not m.request_equip_gem(3, "gem-2").ok and not m.request_draw_gems(1).ok and not m.request_reroll_gem("gem-2", [0]).ok and not m.request_salvage_gems(["gem-1"]).ok, "run locks every gem transaction")
	check(not m.request_lock_gem("gem-1").ok and m.get_state() == before, "run lock request leaves account unchanged")
	check(m.end_run().ok and not m.is_in_run(), "ending preview unlocks preparation")
	check(m.get_state().gem_state.cumulative_cleared == 0 and m.get_state().gem_state.essence == 0, "preview never progresses gem milestones")
	_install(m, [], 0, 0, [], 0, 0, _seed_state())
	var run = m.begin_playable_run("route45")
	check(run.ok and run.snapshot.gem_core == "" and run.snapshot.gem_effects == 0, "empty loadout has no active effect")
	var rooms: Array = []
	for index in 15: rooms.append(index + 1)
	var settled = m.settle_playable_run(run.run_id, rooms)
	check(settled.ok and settled.essence_earned == 12, "first clear milestone grants twelve essence")
	check(m.get_state().gem_state.cumulative_cleared == 15 and m.get_state().gem_state.milestone_claimed == [15], "milestone receipt stored once")
	check(m.get_state().gem_state.essence == 12 and m.get_state().dust == 15, "settlement credits essence and route dust")
	check(m.settle_playable_run(run.run_id, rooms).already_settled and m.get_state().gem_state.essence == 12, "repeat settlement is read-only")
	var second = m.begin_playable_run("route45")
	var more: Array = []
	for index in 15: more.append(index + 1)
	var settled_again = m.settle_playable_run(second.run_id, more)
	check(settled_again.ok and settled_again.essence_earned == 12 and m.get_state().gem_state.essence == 24, "second milestone grants another twelve")
	check(m.get_state().gem_state.cumulative_cleared == 30 and m.get_state().gem_state.milestone_claimed == [15, 30], "both milestone thresholds recorded")
	check(lib.validate(m.get_state().gem_state).is_empty(), "settled gem account stays valid")

func _persistence(m):
	var lib = m.gems
	var loadout: Array = [
		_gem(lib, 1, "green", ["attack"], "", [2]),
		_gem(lib, 2, "blue", ["health", "shield"], "", [1, 3]),
		_gem(lib, 3, "gold", ["speed", "crit_rate", "crit_multiplier"], "wind", [3, 1, 2]),
	]
	_install(m, loadout, 100, 42, ["gem-1", "", "gem-3", ""], 2, 2, _seed_state())
	check(m.request_lock_gem("gem-2").ok, "lock a held gem before saving")
	var state: Dictionary = m.get_state()
	state.gem_state.essence = 54
	_store_fixture(test_path, state)
	check(m.load_state().ok, "full gem fixture loads " + m.error)
	var saved: Dictionary = m.get_state()
	check(saved.gem_state.inventory.size() == 3 and saved.gem_state.slots == ["gem-1", "", "gem-3", ""], "inventory and slots survive reload")
	check(saved.gem_state.essence == 54 and saved.gem_state.gold_misses == 2 and saved.gem_state.rare_misses == 2, "currency and pity counters survive reload")
	check(saved.gem_state.inventory[1].locked, "lock flag survives reload")
	var reloaded = Meta.new(test_path)
	check(reloaded.load_state().ok and reloaded.get_state() == saved, "whole gem account round-trips through disk")
	check(reloaded.gems.totals(reloaded.get_state().gem_state) == lib.totals(saved.gem_state), "totals are identical after reload")
	var changed = reloaded.request_draw_gems(10)
	check(changed.ok and reloaded.get_state().gem_state.inventory.size() == 13, "transactions continue after reload")
	var reopened = Meta.new(test_path)
	check(reopened.load_state().ok and reopened.get_state() == reloaded.get_state(), "post-reload transaction persists")

func _version_guard(m, initial: Dictionary):
	_store_fixture(test_path, initial)
	check(m.load_state().ok, "version guard starts from a valid account")
	for version in ["meta-progression-6", "meta-progression-1", "meta-progression-8"]:
		var old = initial.duplicate(true)
		old.version = version
		_store_fixture(test_path, old)
		var bytes = FileAccess.get_file_as_string(test_path)
		var account = Meta.new(test_path)
		var result = account.load_state()
		check(not result.ok and not account.is_loaded(), "non-current version rejected: " + version)
		check(result.has("incompatible_version") and str(result.incompatible_version) == version, "version gap identified: " + version)
		check(not str(result.error).contains("损坏"), "version gap is not corruption: " + version)
		check(str(result.error).contains("不兼容") and str(result.error).contains(Meta.SAVE_VERSION), "error names both versions: " + version)
		check(FileAccess.get_file_as_string(test_path) == bytes, "rejected version keeps original bytes: " + version)
	var unparsable = initial.duplicate(true)
	unparsable.version = "meta-progression-x"
	_store_fixture(test_path, unparsable)
	var unparsable_bytes = FileAccess.get_file_as_string(test_path)
	var broken = Meta.new(test_path)
	var broken_result = broken.load_state()
	check(not broken_result.ok and not broken_result.has("incompatible_version"), "unparsable version stays a corruption error")
	check(str(broken_result.error).contains("损坏"), "unparsable version keeps corruption wording")
	check(FileAccess.get_file_as_string(test_path) == unparsable_bytes, "unparsable version is preserved")
	# Quarantine and rebuild: old bytes move aside, a fresh account starts.
	var older = initial.duplicate(true)
	older.version = "meta-progression-6"
	_store_fixture(test_path, older)
	var older_bytes = FileAccess.get_file_as_string(test_path)
	var quarantined_account = Meta.new(test_path)
	var failed = quarantined_account.load_state()
	check(not failed.ok and failed.has("incompatible_version"), "quarantine fixture reports its gap")
	var quarantined = quarantined_account.quarantine_incompatible_save()
	check(quarantined.ok and FileAccess.file_exists(str(quarantined.get("path", ""))), "quarantine moves the old save aside")
	check(quarantined.ok and FileAccess.get_file_as_string(str(quarantined.path)) == older_bytes, "quarantined bytes are unchanged")
	check(not FileAccess.file_exists(test_path), "original path is released only after quarantine")
	if quarantined.ok:
		fixture_paths.append(str(quarantined.path))
	var rebuilt = quarantined_account.load_state()
	check(rebuilt.ok and quarantined_account.is_loaded(), "a valid account starts after quarantine")
	var fresh = quarantined_account.get_state()
	check(fresh.dust == 0 and fresh.levels.size() == 6 and fresh.gem_state.inventory.is_empty(), "rebuilt account has six catalysts and no gems")
	check(fresh.gem_state.slots == ["", "", "", ""] and fresh.gem_state.essence == 0, "rebuilt account has four empty slots")
	_store_fixture(test_path, initial)
	check(m.load_state().ok, "version guard restores a valid account")

func _corruptions(m, initial: Dictionary):
	var lib = m.gems
	var base = _install(m, [
		_gem(lib, 1, "purple", ["attack", "health", "shield"], "", [1, 2, 3]),
		_gem(lib, 2, "gold", ["attack", "health", "shield"], "inferno", [3, 2, 1]),
	], 12, 8, ["gem-1", "", "", ""], 0, 0, _seed_state())
	var corruptions: Array = ["{invalid json", "[]"]
	for field in ["version", "dust", "levels", "equipped", "free_claimed", "settlement_serial", "gem_state"]:
		var invalid = base.duplicate(true)
		invalid.erase(field)
		corruptions.append(invalid)
	for bad_dust in [-1, 2.5, true, "20", 1.0e100]:
		var invalid = base.duplicate(true)
		invalid.dust = bad_dust
		corruptions.append(invalid)
	var invalid = base.duplicate(true)
	invalid.levels.MC04 = 4
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.levels.erase("MC09")
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.levels.UNKNOWN = 0
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.levels.MC04 = 0.5
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.equipped.catalyst = "MC01"
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.free_claimed.catalyst = true
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.equipped.extra = ""
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.gem_state.schema_version = 3
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.gem_state.slots = ["", "", ""]
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.gem_state.slots[1] = "gem-99"
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.gem_state.slots[0] = "gem-2"
	invalid.gem_state.slots[1] = "gem-2"
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.gem_state.inventory[0].affixes[0].value = 999
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.gem_state.inventory[0].affixes[0].role = "side"
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.gem_state.inventory[1].core = "unknown"
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.gem_state.inventory[0].core = "inferno"
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.gem_state.inventory[1].affixes[1].role = "main"
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.gem_state.draws = 3
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.gem_state.salvaged = 1
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.gem_state.pending_reforge = {"gem_id": "gem-1", "mode": "affix", "token": 0, "locks": [], "cost": 20, "old": {}, "candidate": {}}
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.gem_state.rng_state = "not-a-number"
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.gem_state.gold_misses = 50
	corruptions.append(invalid)
	invalid = base.duplicate(true)
	invalid.gem_state.cumulative_cleared = 15
	corruptions.append(invalid)
	for corruption in corruptions:
		_store_fixture(test_path, corruption)
		var bytes = FileAccess.get_file_as_string(test_path)
		check(not m.load_state().ok and not m.is_loaded(), "invalid save is rejected")
		check(not m.request_unlock("catalyst", "MC06").ok, "failed load prevents overwriting old progress")
		check(FileAccess.get_file_as_string(test_path) == bytes, "invalid progress is preserved exactly")
	_store_fixture(test_path, base)
	check(m.load_state().ok, "corruption suite restores a valid account")

func _save_failures(m, initial: Dictionary):
	_install(m, [], 0, 0, [], 0, 0, _seed_state())
	var blocked_parent = test_path + ".blocked"
	_store_fixture(blocked_parent, "This file prevents creating a child save directory.")
	m.save_path = blocked_parent + "/save.json"
	var before = m.get_state()
	check(not m.request_unlock("catalyst", "MC04").ok, "disk write failure is reported")
	check(m.get_state() == before and not m.get_state().free_claimed.catalyst, "failed save preserves the free choice")
	m.save_path = test_path
	check(m.request_unlock("catalyst", "MC04").ok, "free choice remains available after save retry")
	var funded = m.get_state()
	funded.dust = 20
	_store_fixture(test_path, funded)
	check(m.load_state().ok, "funded draw fixture loads")
	m.save_path = blocked_parent + "/save.json"
	before = m.get_state()
	check(not m.request_draw_gems(1).ok and m.get_state() == before, "failed save does not charge a draw or advance RNG")
	m.save_path = test_path
	check(FileAccess.get_file_as_string(test_path) == JSON.stringify(funded), "failed draw leaves the last good save unchanged")
	check(m.request_draw_gems(1).ok and m.get_state().dust == 15, "draw retry commits exactly once")
	var gem: Array = [_gem(m.gems, 1, "gold", ["attack", "health", "shield"], "inferno", [1, 1, 1])]
	_install(m, gem, 0, 40, [], 0, 0, _seed_state())
	before = m.get_state()
	m.save_path = blocked_parent + "/save.json"
	check(not m.request_reroll_gem("gem-1", ["core"]).ok and m.get_state() == before, "failed save does not charge a reroll")
	m.save_path = test_path
	check(m.request_reroll_gem("gem-1", ["core"]).ok and m.get_state().gem_state.essence == 5, "reroll retry charges once")
	var token: int = int(m.get_state().gem_state.pending_reforge.token)
	check(m.resolve_reforge(token, false).ok, "failed-save suite cleans its candidate")
	_store_fixture(test_path, initial)
	check(m.load_state().ok, "save-failure suite restores a valid account")

func _reset(m):
	var protected_account = Meta.new()
	check(not protected_account.reset_for_tests().ok, "real player reset is forbidden")
	_store_fixture(test_path, m.get_state())
	check(m.reset_for_tests().ok, "explicit reset restricted to the test root")
	var state = m.get_state()
	check(state.dust == 0 and state.gem_state.inventory.is_empty() and state.gem_state.slots == ["", "", "", ""], "reset clears gems and currencies")
	check(state.levels.size() == 6 and not state.free_claimed.catalyst and state.equipped.catalyst.is_empty(), "reset returns a fresh catalyst account")
