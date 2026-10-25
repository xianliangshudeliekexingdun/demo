extends RefCounted
## v4 gem economy: draw, equip, reforge and salvage with isolated accounts only.
const Meta = preload("res://scripts/core/meta_progression.gd")
const Gems = preload("res://scripts/core/magic_gems.gd")
const ROOT = "user://tests/meta_progression/gem_v3/"
const OUT = "res://build/qa/gem-v3-implementation-20261022/economy/"
var checks: int = 0
var failures: Array = []
var paths: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("Gem v3 economy: " + label)

func save(path: String, value: Dictionary) -> void:
	assert(path.begins_with(ROOT) and ".." not in path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file = FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "isolated fixture opens")
	if file != null:
		file.store_string(JSON.stringify(value))
		file.close()
	if path not in paths: paths.append(path)

func seed_state(seed_value: int = 20261022) -> String:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	return str(rng.state)

func line(lib, stat: String, tier: int, main: bool) -> Dictionary:
	return lib.line(stat, tier, main)

func gem(lib, serial: int, rarity: String, stats: Array, core: String = "", tiers: Array = []) -> Dictionary:
	var affixes: Array = []
	var gold: bool = rarity == "gold"
	for index in stats.size():
		var tier: int = int(tiers[index]) if index < tiers.size() else 1
		affixes.append(lib.line(str(stats[index]), tier, not gold and index == 0))
	return {"id": "gem-%d" % serial, "serial": serial, "rarity": rarity, "affixes": affixes, "core": core, "locked": false, "origin": "draw"}

func account(name: String):
	var path: String = ROOT + name + ".json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if path not in paths: paths.append(path)
	var meta = Meta.new(path)
	check(meta.load_state().ok, "isolated account loads " + name)
	var seeded: Dictionary = meta.get_state()
	seeded.gem_state.rng_state = seed_state()
	save(path, seeded)
	check(meta.load_state().ok, "fixed-seed fixture reloads " + name)
	return meta

func funded(meta, dust: int = 1000, essence: int = 1000) -> void:
	var state: Dictionary = meta.get_state()
	state.dust = dust
	state.gem_state.essence = essence
	save(meta.save_path, state)
	check(meta.load_state().ok, "funded fixture reloads")

func install(meta, gems: Array, dust: int = 0, essence: int = 0, slots: Array = [], gold_misses: int = 0, rare_misses: int = 0) -> Dictionary:
	var state: Dictionary = meta.get_state()
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
	save(meta.save_path, state)
	check(meta.load_state().ok, "gem fixture reloads " + meta.error)
	return meta.get_state()

func run() -> int:
	rules_and_creation()
	sampling_and_pity()
	draw_economy()
	equipment_economy()
	reforge_economy()
	salvage_economy()
	milestone_economy()
	regression_economy()
	for path in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var result: Dictionary = {"checks":checks, "failures":failures.size(), "failed_cases":failures,
		"scope":"v4 draw/equip/reforge/salvage account economy with isolated fixtures; no UI, combat, pixels or real account"}
	result["source_sha256"] = {}
	for path in ["data/magic_gems_v1.json", "scripts/core/magic_gems.gd", "scripts/core/meta_progression.gd", "tests/gem_v3_economy_tests.gd"]:
		result.source_sha256[path] = FileAccess.get_sha256("res://" + path)
	var file = FileAccess.open(OUT + "results.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	print("GEM_V3_ECONOMY " + JSON.stringify({"checks":checks, "failures":failures.size(), "failed_cases":failures}))
	return checks if failures.is_empty() else -failures.size()

func rules_and_creation() -> void:
	var lib = Gems.new()
	check(int(lib.rules.slots) == 4, "four gem slots from runtime data")
	check(int(lib.rules.draw_cost) == 5, "draw costs five dust")
	check(int(lib.rules.base_weights.green) == 50 and int(lib.rules.base_weights.blue) == 33 and int(lib.rules.base_weights.purple) == 15 and int(lib.rules.gold_weight) == 2, "rarity weights are 50/33/15/2")
	check(int(lib.rules.pity.purple_or_better) == 10 and int(lib.rules.pity.gold) == 50, "purple and gold pity are ten and fifty")
	check(int(lib.rules.affix_counts.green) == 1 and int(lib.rules.affix_counts.blue) == 2 and int(lib.rules.affix_counts.purple) == 3 and int(lib.rules.affix_counts.gold) == 3, "affix counts are one, two, three and three")
	check(int(lib.rules.reforge.base) == 20 and int(lib.rules.reforge.per_lock) == 15 and int(lib.rules.reforge.max_locks) == 3, "reforge pricing is 20 plus 15 per lock with three locks")
	check(int(lib.rules.salvage_yields.green) == 1 and int(lib.rules.salvage_yields.blue) == 3 and int(lib.rules.salvage_yields.purple) == 10 and int(lib.rules.salvage_yields.gold) == 10, "salvage yields are 1/3/10/10")
	check(lib.rules.affixes.size() == 8 and lib.rules.cores.size() == 10, "eight attributes and ten keystones from data")
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var state: Dictionary = lib.fresh()
	var gold: Dictionary = lib.create(state, "gold", "attack", rng, false, "craft")
	check(gold.rarity == "gold" and str(gold.core) in lib.rules.cores, "created gold carries one known keystone")
	check(gold.affixes.size() == 3, "created gold has three attributes")
	for affix in gold.affixes:
		check(affix.role == "side", "gold attributes have no main role")
		check(affix.value == lib.rules.affixes[affix.stat].tiers[int(affix.tier) - 1], "gold attributes use side tiers")
	check(gold.affixes[0].stat != gold.affixes[1].stat and gold.affixes[1].stat != gold.affixes[2].stat and gold.affixes[0].stat != gold.affixes[2].stat, "gold attributes stay unique")
	for rarity in ["green", "blue", "purple"]:
		var gem_state: Dictionary = lib.fresh()
		var created: Dictionary = lib.create(gem_state, rarity, "health", rng, false, "craft")
		check(created.rarity == rarity and created.affixes.size() == int(lib.rules.affix_counts[rarity]), "created quality has its affix count: " + rarity)
		check(str(created.core).is_empty(), "coloured creation carries no keystone: " + rarity)
		check(created.affixes[0].role == "main" and created.affixes[0].stat == "health", "chosen main stat is first: " + rarity)
		check(created.affixes[0].value == lib.rules.affixes.health.main_tiers[0], "main line uses main tier source: " + rarity)
		for index in range(1, created.affixes.size()):
			check(created.affixes[index].role == "side" and created.affixes[index].value == lib.rules.affixes[created.affixes[index].stat].tiers[int(created.affixes[index].tier) - 1], "side line uses side tier source: " + rarity)
	check(lib.rules.affixes.attack.tiers != lib.rules.affixes.attack.main_tiers, "main and side tier tables are distinct")
	var random_state: Dictionary = lib.fresh()
	var random_gold: Dictionary = lib.create(random_state, "gold", "", rng, true, "craft")
	for affix in random_gold.affixes:
		check(int(affix.tier) in [1, 2, 3] and affix.value == lib.rules.affixes[affix.stat].tiers[int(affix.tier) - 1], "random tiers still follow the side table")
	state.draws = state.serial
	random_state.draws = random_state.serial
	check(lib.validate(state).is_empty(), "directly created gold is a valid record")
	check(lib.validate(random_state).is_empty(), "directly created random gold is a valid record")
	check(lib.title({}) == "空槽", "empty slot title is explicit")
	var text_state: Dictionary = lib.fresh()
	var text_gold: Dictionary = lib.create(text_state, "gold", "", rng, false, "craft")
	var text_purple: Dictionary = lib.create(text_state, "purple", "health", rng, false, "craft")
	check(lib.title(text_gold).ends_with("宝石") and lib.title(text_gold).begins_with(str(lib.rules.cores[text_gold.core].name)), "gold title names its keystone")
	check(lib.title(text_purple).begins_with("紫色"), "coloured title names its quality")
	check(lib.affix_text(text_gold).find("主 · ") < 0 and lib.affix_text(text_purple).find("主 · ") >= 0, "affix text exposes main role only for coloured gems")
	check(lib.lockable_count(text_gold) == 4 and lib.lockable_count(text_purple) == 3, "lockable parts follow quality")
	check(lib.effect_of(text_gold) == str(text_gold.core) and lib.effect_of(text_purple).is_empty(), "only gold exposes a keystone effect")
	check(lib.salvage_value(text_purple) == lib.salvage_yield(text_purple) and lib.salvage_value(text_purple) == 10, "salvage accessors agree")

func sampling_and_pity() -> void:
	var lib = Gems.new()
	var state: Dictionary = lib.fresh()
	var rng = RandomNumberGenerator.new()
	rng.seed = 11
	var counts: Dictionary = {"green": 0, "blue": 0, "purple": 0, "gold": 0}
	var purple_gap: int = 0
	var gold_gap: int = 0
	for index in 500:
		var drawn: Dictionary = lib.sample(state, rng)
		var rarity: String = str(drawn.rarity)
		counts[rarity] = int(counts[rarity]) + 1
		purple_gap = 0 if rarity in ["purple", "gold"] else purple_gap + 1
		gold_gap = 0 if rarity == "gold" else gold_gap + 1
		check(purple_gap < 10, "no ten-draw streak without purple or better")
		check(gold_gap < 50, "no fifty-draw streak without gold")
		var used: Array = []
		for affix in drawn.affixes:
			check(affix.stat not in used, "sampled attributes stay unique")
			used.append(affix.stat)
	check(int(counts.green) > int(counts.blue) and int(counts.blue) > int(counts.purple) and int(counts.purple) > int(counts.gold), "common qualities outnumber rarer ones")
	check(int(counts.purple) >= 10 and int(counts.gold) >= 1, "pity keeps purple and gold reachable")
	var total: int = 0
	for key in counts: total += int(counts[key])
	check(total == 500, "sample ledger counts every draw")
	var forced_purple: Dictionary = lib.fresh()
	forced_purple.rare_misses = 9
	forced_purple.draws = 9
	var purple: Dictionary = lib.sample(forced_purple, rng)
	check(purple.rarity == "purple" and int(forced_purple.rare_misses) == 0 and int(forced_purple.gold_misses) == 1, "ninth purple miss forces purple and advances gold pity")
	var forced_gold: Dictionary = lib.fresh()
	forced_gold.gold_misses = 49
	forced_gold.rare_misses = 4
	forced_gold.draws = 49
	var gold: Dictionary = lib.sample(forced_gold, rng)
	check(gold.rarity == "gold" and int(forced_gold.gold_misses) == 0 and int(forced_gold.rare_misses) == 0, "forty-ninth gold miss forces gold and resets both counters")
	var streak: Dictionary = lib.fresh()
	var streak_rare: bool = false
	for index in 10:
		var gem: Dictionary = lib.sample(streak, rng)
		streak_rare = streak_rare or gem.rarity in ["purple", "gold"]
	check(streak_rare, "fresh ten draw contains purple or better")
	check(lib.validate(streak).is_empty(), "sampling account stays valid")

func draw_economy() -> void:
	var meta = account("draws")
	funded(meta, 100, 0)
	var before: Dictionary = meta.get_state()
	var one: Dictionary = meta.request_draw_gems(1)
	check(one.ok and one.gems.size() == 1 and int(meta.get_state().dust) == 95, "single draw spends exactly five")
	check(meta.get_state().gem_state.inventory.size() == 1 and int(meta.get_state().gem_state.draws) == 1 and int(meta.get_state().gem_state.serial) == 1, "single draw records one instance")
	var ten: Dictionary = meta.request_draw_gems(10)
	check(ten.ok and ten.gems.size() == 10 and int(meta.get_state().dust) == 45, "ten draw spends exactly fifty")
	check(meta.get_state().gem_state.inventory.size() == 11 and int(meta.get_state().gem_state.draws) == 11, "ten draw records ten instances")
	check(str(ten.gems[-1].rarity) in ["purple", "gold"], "ten draw guarantees purple or better")
	check(meta.gems.validate(meta.get_state().gem_state).is_empty(), "drawn account is valid")
	install(meta, [], 100, 0)
	var singles_path: String = ROOT + "draw_singles.json"
	save(singles_path, meta.get_state())
	var singles = Meta.new(singles_path)
	check(singles.load_state().ok, "same-RNG singles account loads")
	check(meta.request_draw_gems(10).ok, "ten draw commits")
	for index in 10: check(singles.request_draw_gems(1).ok, "single draw commits")
	check(singles.get_state() == meta.get_state(), "ten singles equal one ten draw including pity and RNG")
	before = meta.get_state()
	var disk: String = FileAccess.get_file_as_string(meta.save_path)
	for count in [0, 2, 3, 9, 11, -1]:
		check(not meta.request_draw_gems(count).ok, "unsupported draw count rejected " + str(count))
	check(meta.get_state() == before and FileAccess.get_file_as_string(meta.save_path) == disk, "rejected draws preserve account and disk")
	install(meta, [], 4, 0)
	check(not meta.request_draw_gems(1).ok and int(meta.get_state().dust) == 4, "insufficient dust rejected without spending")
	var gold_stone: Array = [gem(meta.gems, 1, "gold", ["attack", "health", "shield"], "inferno", [1, 1, 1])]
	install(meta, gold_stone, 100, 100, ["gem-1", "", "", ""])
	check(meta.request_reroll_gem("gem-1", ["core"]).ok, "reroll candidate opened")
	before = meta.get_state()
	check(not meta.request_draw_gems(1).ok and meta.get_state() == before, "unresolved candidate blocks a draw")
	var token: int = int(meta.get_state().gem_state.pending_reforge.token)
	check(meta.resolve_reforge(token, false).ok, "candidate discarded")
	check(meta.request_draw_gems(1).ok, "draw works again after resolving")
	var blocked: String = ROOT + "blocked_draw"
	var blocker = FileAccess.open(blocked, FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker.close()
	paths.append(blocked)
	install(meta, [], 100, 0)
	var fixture: Dictionary = meta.get_state()
	meta.save_path = blocked + "/save.json"
	var memory: Dictionary = meta.get_state()
	check(not meta.request_draw_gems(1).ok and meta.get_state() == memory, "failed save does not charge or advance RNG")
	meta.save_path = ROOT + "draws.json"
	check(meta.request_draw_gems(1).ok and int(meta.get_state().dust) == 95, "draw retry commits once")
	check(int(meta.get_state().gem_state.draws) == 1, "failed attempt left no phantom instance")

func equipment_economy() -> void:
	var meta = account("equipment")
	var lib = meta.gems
	var loadout: Array = [
		gem(lib, 1, "green", ["attack"], "", [1]),
		gem(lib, 2, "blue", ["health", "shield"], "", [1, 1]),
		gem(lib, 3, "purple", ["attack", "defense", "cdr"], "", [1, 1, 1]),
		gem(lib, 4, "gold", ["speed", "crit_rate", "crit_multiplier"], "inferno", [1, 1, 1]),
	]
	install(meta, loadout)
	for index in 4:
		check(meta.request_equip_gem(index, "gem-%d" % (index + 1)).ok, "slot " + str(index) + " equips")
	check(meta.get_state().gem_state.slots == ["gem-1", "gem-2", "gem-3", "gem-4"], "all four slots can hold different qualities")
	var totals: Dictionary = lib.totals(meta.get_state().gem_state)
	check(totals.attack == 8.0 and totals.health == 20.0 and totals.shield == 4.0, "equipped flat totals match tier sources")
	check(near(float(totals.defense), 2.0) and near(float(totals.cdr), 0.01), "secondary totals match tier sources")
	var stats: Dictionary = meta.get_preview_stats()
	check(stats.health == 320.0 and stats.shield == 104.0 and stats.attack == 108.0, "preview stats add equipped totals once")
	var breakdown: Array = meta.get_stat_breakdown()
	check(breakdown.size() == 8, "breakdown covers the eight display stats")
	var rows: Dictionary = {}
	for row in breakdown: rows[str(row.key)] = row
	check(rows.size() == 8 and near(float(rows.attack.base), 100.0) and near(float(rows.attack.bonus), 8.0) and near(float(rows.attack.final), 108.0), "breakdown keeps base, gem and final apart")
	check(near(float(rows.cdr.bonus), 0.01) and near(float(rows.cdr.cap), 0.6) and str(rows.cdr.cap_label) == "上限 60%", "cooldown row reports the sourced cap")
	check(str(rows.defense.cap_label).begins_with("减伤") and near(float(rows.crit_rate.base), 0.05) and near(float(rows.crit_rate.cap), 1.0), "defence and crit rows carry their own limits")
	check(meta.request_equip_gem(1, "gem-1").ok, "same instance can be moved")
	check(meta.get_state().gem_state.slots == ["", "gem-1", "gem-3", "gem-4"], "moving clears the previous slot")
	check(meta.request_equip_gem(2, "gem-1").ok and meta.get_state().gem_state.slots[1].is_empty(), "same instance never occupies two slots")
	var before: Dictionary = meta.get_state()
	for slot in [-1, 4, 99]:
		check(not meta.request_equip_gem(slot, "gem-2").ok, "invalid slot rejected " + str(slot))
	check(not meta.request_equip_gem(0, "gem-99").ok and meta.get_state() == before, "unowned gem cannot be equipped")
	check(meta.request_equip_gem(0, "gem-1").ok and meta.request_equip_gem(1, "gem-2").ok, "restore slots")
	check(meta.request_equip_gem(2, "gem-3").ok and meta.request_equip_gem(3, "gem-4").ok, "restore four slots")
	var duplicate: Array = [
		gem(lib, 1, "gold", ["attack", "health", "shield"], "inferno", [1, 2, 3]),
		gem(lib, 2, "gold", ["attack", "health", "shield"], "inferno", [3, 2, 1]),
		gem(lib, 3, "gold", ["attack", "health", "shield"], "wind", [1, 1, 1]),
	]
	install(meta, duplicate, 0, 0, ["gem-1", "gem-2", "gem-3", ""])
	check(lib.active_effects(meta.get_state().gem_state) == ["inferno", "wind"], "one copy per keystone acts")
	check(lib.first_effect(meta.get_state().gem_state) == "inferno", "the lowest slot decides the first effect")
	check(lib.duplicate_effects(meta.get_state().gem_state) == ["inferno"], "duplicate keystone is reported")
	check(lib.totals(meta.get_state().gem_state).attack == 8.0, "inactive duplicates still contribute attributes")
	check(meta.request_equip_gem(3, "gem-1").ok and lib.first_effect(meta.get_state().gem_state) == "inferno", "moving the leading copy keeps one active effect")
	var snapshot = meta.begin_run()
	check(snapshot.ok and snapshot.snapshot.gem_core == "inferno" and int(snapshot.snapshot.gem_effects) == 2, "run snapshot counts distinct active effects")
	check(snapshot.snapshot.gem_cores == ["inferno", "wind"] and snapshot.snapshot.gem_slots.size() == 4, "run snapshot freezes slots and effect list")
	check(snapshot.snapshot.stat_breakdown.size() == 8, "run snapshot carries the prepared stat breakdown")
	before = meta.get_state()
	check(not meta.request_equip_gem(0, "").ok and not meta.request_draw_gems(1).ok and not meta.request_salvage_gems(["gem-3"]).ok, "run blocks equipment, draw and salvage")
	check(meta.get_state() == before, "blocked run actions preserve account")
	check(meta.end_run().ok, "preview ends")
	var aegis: Array = [gem(lib, 1, "gold", ["attack", "health", "shield"], "aegis", [1, 1, 1])]
	install(meta, aegis, 0, 0, ["gem-1", "", "", ""])
	var converted: Dictionary = meta.get_preview_stats()
	check(near(float(converted.health), 217.0) and near(float(converted.shield), 308.6), "aegis converts thirty percent of life into shield")
	var aegis_rows: Dictionary = {}
	for row in meta.get_stat_breakdown(): aegis_rows[str(row.key)] = row
	check(float(aegis_rows.health.bonus) < 0.0 and float(aegis_rows.shield.bonus) > 0.0, "aegis conversion stays visible instead of hiding in the final value")

func reforge_economy() -> void:
	var meta = account("reforge")
	var lib = meta.gems
	var purple: Array = [gem(lib, 1, "purple", ["attack", "health", "shield"], "", [2, 3, 1])]
	install(meta, purple, 0, 200)
	check(meta.reforge_cost("gem-1", []) == 20 and meta.reforge_cost("gem-1", [0]) == 35 and meta.reforge_cost("gem-1", [0, 1]) == 50, "cost starts at twenty and grows by fifteen per lock")
	check(meta.reforge_cost("gem-1", [0, 1, 2]) == 65 and meta.reforge_cost("missing", []) == -1, "three locks cost sixty-five and unknown gems have no price")
	check(not meta.request_reroll_gem("gem-1", [0, 1, 2]).ok, "cannot lock every attribute")
	check(not meta.request_reroll_gem("gem-1", [0, 1, 2, 3]).ok, "more than three locks rejected")
	check(not meta.request_reroll_gem("gem-1", [3]).ok, "attribute index out of range rejected")
	check(not meta.request_reroll_gem("gem-1", ["core"]).ok, "coloured gem cannot lock a keystone")
	check(not meta.request_reroll_gem("missing", []).ok, "missing gem cannot be rerolled")
	install(meta, purple, 0, 34)
	check(not meta.request_reroll_gem("gem-1", [0]).ok and int(meta.get_state().gem_state.essence) == 34, "insufficient essence rejected before paying")
	# Gold has no main line, so all four parts are legitimate lock targets.
	var gold: Array = [gem(lib, 1, "gold", ["attack", "health", "shield"], "inferno", [1, 2, 3])]
	install(meta, gold, 0, 200)
	check(not meta.request_reroll_gem("gem-1", ["core", 0, 1, 2]).ok, "four locks are rejected")
	var two: Dictionary = meta.request_reroll_gem("gem-1", [0, 1])
	check(two.ok and int(meta.get_state().gem_state.essence) == 150 and int(two.candidate.cost) == 50, "two locks cost fifty once")
	var pending: Dictionary = meta.get_state().gem_state.pending_reforge
	check(pending.locks == [0, 1] and pending.candidate.affixes.size() == 3, "candidate records its locks")
	check(pending.candidate.affixes[0] == pending.old.affixes[0] and pending.candidate.affixes[1] == pending.old.affixes[1], "locked attributes never change")
	check(pending.candidate.affixes != pending.old.affixes, "at least one unlocked attribute is rerolled")
	check(lib.validate(meta.get_state().gem_state).is_empty(), "pending candidate is a valid record")
	var before: Dictionary = meta.get_state()
	check(not meta.request_draw_gems(1).ok and not meta.request_lock_gem("gem-1").ok and not meta.request_salvage_gems(["gem-1"]).ok and not meta.request_equip_gem(0, "gem-1").ok, "pending candidate blocks other transactions")
	check(not meta.request_reroll_gem("gem-1", []).ok and meta.get_state() == before, "pending candidate blocks a second reroll")
	var token: int = int(pending.token)
	check(not meta.resolve_reforge(token + 1, true).ok, "unknown token rejected")
	check(meta.resolve_reforge(token, true).ok, "adopt commits once")
	check(meta.get_state().gem_state.pending_reforge.is_empty(), "adoption clears the candidate")
	var adopted: Dictionary = lib.find(meta.get_state().gem_state, "gem-1")
	check(adopted.affixes == pending.candidate.affixes, "adopted attributes equal the candidate")
	check(not meta.resolve_reforge(token, false).ok, "token cannot be reused")
	var reloaded = Meta.new(meta.save_path)
	check(reloaded.load_state().ok and reloaded.get_state() == meta.get_state(), "adopted account persists")
	meta = reloaded
	var current_core: String = lib.effect_of(lib.find(meta.get_state().gem_state, "gem-1"))
	var core: Dictionary = meta.request_reroll_gem("gem-1", ["core"])
	check(core.ok and int(meta.get_state().gem_state.essence) == 115 and core.candidate.candidate.core == current_core, "locked keystone survives at one lock cost")
	var core_token: int = int(meta.get_state().gem_state.pending_reforge.token)
	check(meta.resolve_reforge(core_token, true).ok and lib.effect_of(lib.find(meta.get_state().gem_state, "gem-1")) == current_core, "locked keystone adoption keeps the effect")
	var free: Dictionary = meta.request_reroll_gem("gem-1", [])
	check(free.ok and int(meta.get_state().gem_state.essence) == 95 and free.candidate.candidate.core != current_core, "unlocked keystone changes at base cost")
	var free_token: int = int(meta.get_state().gem_state.pending_reforge.token)
	check(meta.resolve_reforge(free_token, true).ok and lib.effect_of(lib.find(meta.get_state().gem_state, "gem-1")) != current_core, "unlocked keystone adoption replaces the effect")
	var three: Dictionary = meta.request_reroll_gem("gem-1", [0, 1, 2])
	check(three.ok and int(meta.get_state().gem_state.essence) == 30 and int(three.candidate.cost) == 65, "three locks are the maximum")
	check(three.candidate.candidate.affixes == lib.find(meta.get_state().gem_state, "gem-1").affixes, "three-lock candidate keeps every attribute")
	var three_token: int = int(meta.get_state().gem_state.pending_reforge.token)
	check(meta.resolve_reforge(three_token, true).ok, "three-lock adoption commits")
	var keep: Dictionary = meta.request_reroll_gem("gem-1", [])
	check(keep.ok and int(meta.get_state().gem_state.essence) == 10, "final reroll charges again")
	var keep_token: int = int(meta.get_state().gem_state.pending_reforge.token)
	var old_affixes: Array = meta.get_state().gem_state.pending_reforge.old.affixes
	check(meta.resolve_reforge(keep_token, false).ok, "keep-old commits")
	check(lib.find(meta.get_state().gem_state, "gem-1").affixes == old_affixes and int(meta.get_state().gem_state.essence) == 10, "keep-old changes nothing and refunds nothing")
	check(lib.validate(meta.get_state().gem_state).is_empty(), "rerolled account is valid")
	var blocked: String = ROOT + "blocked_reforge"
	var blocker = FileAccess.open(blocked, FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker.close()
	paths.append(blocked)
	install(meta, gold, 0, 100)
	meta.save_path = blocked + "/save.json"
	before = meta.get_state()
	check(not meta.request_reroll_gem("gem-1", ["core"]).ok and meta.get_state() == before, "failed save does not charge a reroll")
	meta.save_path = ROOT + "reforge.json"
	check(meta.request_reroll_gem("gem-1", ["core"]).ok and int(meta.get_state().gem_state.essence) == 65, "reroll retry charges once")

func salvage_economy() -> void:
	var meta = account("salvage")
	var lib = meta.gems
	var gems: Array = [
		gem(lib, 1, "green", ["attack"], "", [1]),
		gem(lib, 2, "blue", ["health", "shield"], "", [1, 1]),
		gem(lib, 3, "purple", ["attack", "defense", "cdr"], "", [1, 1, 1]),
		gem(lib, 4, "gold", ["speed", "crit_rate", "crit_multiplier"], "inferno", [1, 1, 1]),
	]
	install(meta, gems, 0, 0, ["gem-1", "", "", ""])
	var before: Dictionary = meta.get_state()
	check(not meta.request_salvage_gems([]).ok, "empty salvage rejected")
	check(not meta.request_salvage_gems(["gem-1"]).ok and meta.get_state() == before, "equipped gem protected")
	check(not meta.request_salvage_gems(["gem-2", "gem-2"]).ok and meta.get_state() == before, "duplicate entry rejected")
	check(not meta.request_salvage_gems(["gem-99"]).ok, "unowned gem rejected")
	check(meta.request_salvage_gems(["gem-2"]).essence_gained == 3 and int(meta.get_state().gem_state.essence) == 3, "blue yields three")
	check(meta.request_lock_gem("gem-3").ok and not meta.request_salvage_gems(["gem-3"]).ok, "locked gem protected")
	check(meta.request_lock_gem("gem-3").ok and meta.request_salvage_gems(["gem-3"]).essence_gained == 10, "purple yields ten once unlocked")
	check(meta.request_salvage_gems(["gem-4"]).essence_gained == 10 and int(meta.get_state().gem_state.essence) == 23, "gold yields ten")
	check(meta.request_equip_gem(0, "").ok and meta.request_salvage_gems(["gem-1"]).essence_gained == 1, "green yields one after unequipping")
	check(int(meta.get_state().gem_state.essence) == 24 and meta.get_state().gem_state.inventory.is_empty(), "all qualities yield 1/3/10/10")
	check(int(meta.get_state().gem_state.salvaged) == 4 and int(meta.get_state().gem_state.serial) == 4, "salvage ledger counts removed instances")
	check(lib.validate(meta.get_state().gem_state).is_empty(), "fully salvaged account is valid")
	var pair: Array = [
		gem(lib, 1, "green", ["attack"], "", [1]),
		gem(lib, 2, "green", ["health"], "", [1]),
		gem(lib, 3, "green", ["shield"], "", [1]),
	]
	install(meta, pair, 0, 7)
	var batch: Dictionary = meta.request_salvage_gems(["gem-1", "gem-2"])
	check(batch.ok and batch.essence_gained == 2 and int(meta.get_state().gem_state.essence) == 9, "batch salvage sums yields")
	check(meta.request_salvage_gems(["gem-3"]).essence_gained == 1 and int(meta.get_state().gem_state.essence) == 10, "last salvage completes the batch")
	var guard: Array = [
		gem(lib, 1, "green", ["attack"], "", [1]),
		gem(lib, 2, "gold", ["attack", "health", "shield"], "wind", [1, 1, 1]),
	]
	install(meta, guard, 0, 40)
	check(meta.request_reroll_gem("gem-2", ["core"]).ok, "reroll candidate opened")
	check(not meta.request_salvage_gems(["gem-1"]).ok, "candidate protects salvage")
	var token: int = int(meta.get_state().gem_state.pending_reforge.token)
	check(meta.resolve_reforge(token, false).ok, "candidate discarded")
	check(meta.request_salvage_gems(["gem-1"]).essence_gained == 1, "salvage works after resolving")
	var reopened = Meta.new(meta.save_path)
	check(reopened.load_state().ok and reopened.get_state() == meta.get_state(), "salvage survives reload")

func milestone_economy() -> void:
	var meta = account("milestones")
	var first = meta.begin_playable_run("route45")
	check(first.ok, "first route45 run starts")
	var rooms: Array = []
	for index in 15: rooms.append(index + 1)
	var settled: Dictionary = meta.settle_playable_run(first.run_id, rooms)
	check(settled.ok and int(settled.essence_earned) == 12, "fifteen cleared rooms grant twelve essence")
	check(int(meta.get_state().gem_state.cumulative_cleared) == 15 and int(meta.get_state().gem_state.essence) == 12, "cumulative clears and essence credited")
	check(int(meta.get_state().gem_state.milestone_claimed[0]) == 15 and meta.get_state().gem_state.milestone_claimed.size() == 1, "milestone receipt stored once")
	check(int(meta.get_state().dust) == 15, "route45 dust follows the early-room rate")
	var before: Dictionary = meta.get_state()
	check(meta.settle_playable_run(first.run_id, rooms).already_settled and meta.get_state() == before, "repeat settlement is read-only")
	var second = meta.begin_playable_run("route45")
	var settled_again: Dictionary = meta.settle_playable_run(second.run_id, rooms)
	check(settled_again.ok and int(settled_again.essence_earned) == 12 and int(meta.get_state().gem_state.essence) == 24, "second milestone grants another twelve")
	check(int(meta.get_state().gem_state.cumulative_cleared) == 30 and meta.get_state().gem_state.milestone_claimed.size() == 2, "both milestone thresholds claimed")
	var preview_before: Dictionary = meta.get_preview_stats()
	check(meta.begin_run().ok and meta.end_run().ok, "preview run starts and ends")
	check(int(meta.get_state().gem_state.cumulative_cleared) == 30 and int(meta.get_state().gem_state.essence) == 24, "preview never progresses milestones")
	check(meta.get_preview_stats() == preview_before, "preview leaves prepared stats unchanged")
	var failed = account("milestone_failed")
	var run = failed.begin_playable_run("route45")
	var blocked: String = ROOT + "blocked_milestone"
	var blocker = FileAccess.open(blocked, FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker.close()
	paths.append(blocked)
	var memory: Dictionary = failed.get_state()
	failed.save_path = blocked + "/save.json"
	check(not failed.settle_playable_run(run.run_id, rooms).ok and failed.get_state() == memory and failed.is_in_run(), "failed settlement keeps the run uncredited")
	failed.save_path = ROOT + "milestone_failed.json"
	check(failed.settle_playable_run(run.run_id, rooms).essence_earned == 12 and int(failed.get_state().gem_state.essence) == 12, "settlement retry credits exactly once")

func regression_economy() -> void:
	# A coloured gem keeps its doubled main line through a reroll.
	var meta = account("regression")
	var lib = meta.gems
	var purple: Array = [gem(lib, 1, "purple", ["attack", "health", "shield"], "", [2, 1, 1])]
	install(meta, purple, 0, 200)
	var locked_main: Dictionary = meta.request_reroll_gem("gem-1", [0])
	check(locked_main.ok, "coloured gem rerolls while locking its main attribute")
	var pending_main: Dictionary = meta.get_state().gem_state.pending_reforge
	check(pending_main.candidate.affixes[0] == pending_main.old.affixes[0], "locked main stays identical")
	check(str(pending_main.candidate.affixes[0].role) == "main", "main role survives a reroll")
	check(meta.resolve_reforge(int(pending_main.token), true).ok, "coloured reroll adopts")
	var adopted: Dictionary = lib.find(meta.get_state().gem_state, "gem-1")
	check(str(adopted.affixes[0].role) == "main", "adopted main keeps its role")
	check(int(adopted.affixes[0].value) == int(lib.rules.affixes[adopted.affixes[0].stat].main_tiers[int(adopted.affixes[0].tier)-1]), "adopted main keeps the doubled value")
	check(lib.validate(meta.get_state().gem_state).is_empty(), "rerolled coloured gem is a valid record")

	# Integer locks must survive a restart before the candidate resolves.
	var gold: Array = [gem(lib, 1, "gold", ["attack", "health", "shield"], "inferno", [1, 2, 3])]
	install(meta, gold, 0, 200)
	check(meta.request_reroll_gem("gem-1", [0]).ok, "gold reroll with one integer lock")
	var reopened = Meta.new(meta.save_path)
	check(reopened.load_state().ok, "pending candidate reloads with an integer lock")
	var stored: Dictionary = reopened.get_state().gem_state.pending_reforge
	check(stored.locks == [0] and stored.locks[0] is int, "stored lock is still an integer")
	check(reopened.resolve_reforge(int(stored.token), true).ok, "reloaded candidate can be adopted")
	check(lib.validate(reopened.get_state().gem_state).is_empty(), "adopted reloaded candidate is valid")

	# A claimed milestone must not make the save unreadable on reload.
	var climbed = account("milestone_reload")
	var run = climbed.begin_playable_run("route45")
	var rooms: Array = []
	for room in range(1, 16): rooms.append(room)
	check(climbed.settle_playable_run(run.run_id, rooms).ok, "fifteen rooms settle")
	check(climbed.get_state().gem_state.milestone_claimed.size() == 1, "milestone receipt written")
	var again = Meta.new(climbed.save_path)
	check(again.load_state().ok, "save with a claimed milestone reloads")
	check(int(again.get_state().gem_state.essence) == 12 and again.get_state().gem_state.milestone_claimed.size() == 1, "claimed milestone survives reload")

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001
