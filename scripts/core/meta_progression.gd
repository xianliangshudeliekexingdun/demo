extends RefCounted
## Preparation progression. All values come from the approved JSON sources.
## UI requests operate on copies and become visible only after a successful save.

const META_PATH = "res://data/balance_candidates/meta_growth_v1.json"
const Gems = preload("res://scripts/core/magic_gems.gd")
const SAVE_VERSION = "meta-progression-4"
const FIXED_GEM_SAVE_VERSION = "meta-progression-3"
const PREVIOUS_SAVE_VERSION = "meta-progression-2"
const LEGACY_SAVE_VERSION = "meta-progression-1"
const LEGACY_CATALYST_IDS = ["MC01", "MC02", "MC03"]
const LEGACY_GEM_IDS = ["MG01", "MG02", "MG03"]
const DEFAULT_SAVE_PATH = "user://meta_progression_v1.json"
const TEST_SAVE_ROOT = "user://tests/meta_progression/"

var save_path: String
var error: String = ""
var _meta: Dictionary = {}
var _base: Dictionary = {}
var _ice_base: Dictionary = {}
var _economy: Dictionary = {}
var _state: Dictionary = {}
var _run_snapshot: Dictionary = {}
var _loaded: bool = false
var gems = Gems.new()

func _init(path: String = DEFAULT_SAVE_PATH):
	save_path = path

func load_state() -> Dictionary:
	if not _run_snapshot.is_empty():
		return _fail("本局结束前不能重新读取局外存档。")
	_loaded = false
	var result = _read_json(META_PATH)
	if not result.ok:
		return _fail(result.error)
	_meta = result.data
	if not _meta.get("base_parameters") is String:
		return _fail("局外参数缺少基础数据引用。")
	var base_path = META_PATH.get_base_dir().path_join(_meta.base_parameters)
	result = _read_json(base_path)
	if not result.ok:
		return _fail(result.error)
	_base = result.data
	if not _meta.get("economy_parameters") is String:
		return _fail("局外参数缺少阶段数据引用。")
	result = _read_json(META_PATH.get_base_dir().path_join(_meta.economy_parameters))
	if not result.ok:
		return _fail(result.error)
	_economy = result.data
	var ice_error = _load_ice_source()
	if not ice_error.is_empty():
		return _fail("局外参数错误：" + ice_error)
	var catalog_error = _validate_catalog()
	if not catalog_error.is_empty():
		return _fail("局外参数错误：" + catalog_error)
	if FileAccess.file_exists(save_path):
		result = _read_json(save_path)
		if not result.ok:
			return _fail("已有存档无法读取，进度未覆盖。" + result.error)
		var save_data: Dictionary = result.data
		var save_version = str(save_data.get("version", ""))
		if save_version == LEGACY_SAVE_VERSION:
			# The three temporary catalysts are gone. Merge their highest level
			# into the fire catalyst once, and refund only duplicate paid levels.
			# The legacy file stays byte-for-byte until the next committed change.
			save_data = _migrate_legacy_state(save_data)
			if save_data.is_empty():
				return _fail("已有存档损坏，进度未覆盖：旧触媒存档无法迁移。")
		elif save_version == PREVIOUS_SAVE_VERSION:
			save_data = _migrate_gem_state(save_data)
		elif save_version == FIXED_GEM_SAVE_VERSION:
			if not save_data.get("gem_state") is Dictionary: return _fail("已有宝石存档无法迁移，原文件未覆盖。")
			var migrated: Dictionary = gems.migrate_v3(save_data.get("gem_state", {}))
			if migrated.is_empty(): return _fail("已有宝石存档无法迁移，原文件未覆盖。")
			save_data["gem_state"] = migrated
			save_data.version = SAVE_VERSION
		elif save_version != SAVE_VERSION:
			return _fail("已有存档损坏，进度未覆盖：不支持的存档版本。")
		var state_error = _validate_state(save_data)
		if not state_error.is_empty():
			return _fail("已有存档损坏，进度未覆盖：" + state_error)
		_state = save_data.duplicate(true)
		_state.dust = int(_state.dust)
		_state.settlement_serial = int(_state.settlement_serial)
		# Existing v1 preparation saves did not yet have playable-run bookkeeping;
		# migrated saves keep their real values instead of resetting them.
		_state["run_serial"] = int(_state.get("run_serial", _state.settlement_serial))
		_state["last_settlement"] = _state.get("last_settlement", {}).duplicate(true)
		if not _state.last_settlement.is_empty():
			for field in ["run_serial", "dust_earned", "settlement_serial"]:
				_state.last_settlement[field] = int(_state.last_settlement[field])
			for index in range(_state.last_settlement.cleared_rooms.size()):
				_state.last_settlement.cleared_rooms[index] = int(_state.last_settlement.cleared_rooms[index])
		for item_id in _state.levels:
			_state.levels[item_id] = int(_state.levels[item_id])
		for field in ["serial", "draws", "gold_misses", "rare_misses", "essence", "salvaged", "work_serial"]:
			_state.gem_state[field] = int(_state.gem_state[field])
		for gem in _state.gem_state.inventory:
			gem.serial = int(gem.serial)
			for line in gem.affixes:
				if line.has("tier"): line.tier = int(line.tier)
		var pending: Dictionary = _state.gem_state.pending_reforge
		if not pending.is_empty():
			for field in ["token", "index", "cost"]: pending[field] = int(pending[field])
			if pending.mode == "affix":
				pending.old.tier = int(pending.old.tier)
				pending.candidate.tier = int(pending.candidate.tier)
	else:
		var initial_state = _new_state()
		result = _write_state(initial_state)
		if not result.ok:
			return _fail(result.error)
		_state = initial_state
	_loaded = true
	error = ""
	return {"ok": true, "error": "", "state": get_state()}

func is_loaded() -> bool:
	return _loaded

func _migrate_gem_state(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result.version = SAVE_VERSION
	var state: Dictionary = gems.fresh()
	var rng = RandomNumberGenerator.new()
	rng.seed = JSON.stringify(source, "", true).sha256_text().hash()
	state.rng_state = str(rng.state)
	for id in LEGACY_GEM_IDS:
		var level: int = int(source.get("levels", {}).get(id, 0))
		if level <= 0 or level > int(_meta.progression.max_level): continue
		_add_legacy_gem(state, str(id), level)
		if str(source.get("equipped", {}).get("gem", "")) == id: state.slots[0] = "gem-%d" % int(state.serial)
	result["gem_state"] = state
	return result

func _add_legacy_gem(state: Dictionary, id: String, level: int) -> String:
	state.serial = int(state.serial) + 1
	var source: Dictionary = _meta.gems[id]
	var uid: String = "gem-%d" % int(state.serial)
	state.inventory.append({"id": uid, "serial": int(state.serial), "rarity": "legacy", "core": "", "legacy_id": id,
		"legacy_name": source.name, "affixes": [{"stat": source.stat, "value": source.flat_by_level[level - 1]}], "locked": false})
	return uid

func claim_starter_gem(id: String) -> Dictionary:
	if not _loaded or is_in_run(): return _fail("本局结束后可领取宝石。")
	if not _state.gem_state.pending_reforge.is_empty(): return _fail("请先选择当前改良结果。")
	if not _meta.gems.has(id) or bool(_state.free_claimed.gem): return _fail("首次免费宝石已经领取，后续请使用魔尘抽取。")
	var candidate: Dictionary = _state.duplicate(true)
	candidate.levels[id] = 1
	candidate.free_claimed.gem = true
	var uid: String = _add_legacy_gem(candidate.gem_state, id, 1)
	var empty_slot: int = candidate.gem_state.slots.find("")
	if empty_slot >= 0: candidate.gem_state.slots[empty_slot] = uid
	var equipped_core: Dictionary = gems.find(candidate.gem_state, str(candidate.gem_state.slots[0]))
	candidate.equipped.gem = str(equipped_core.get("legacy_id", ""))
	var result: Dictionary = _commit(candidate)
	if result.ok: result["gem_id"] = uid
	return result

func get_gems() -> Array:
	return _state.get("gem_state", {}).get("inventory", []).duplicate(true)

func request_equip_gem(slot: int, id: String = "") -> Dictionary:
	if not _loaded or is_in_run(): return _fail("本局结束后可调整宝石。")
	if not _state.gem_state.pending_reforge.is_empty(): return _fail("请先选择当前改良结果。")
	if slot < 0 or slot >= int(gems.rules.slots): return _fail("未知宝石槽。")
	if not id.is_empty() and gems.find(_state.gem_state, id).is_empty(): return _fail("只能装备已经持有的宝石。")
	var candidate: Dictionary = _state.duplicate(true)
	# A held instance moves between slots; it can never supply attributes twice.
	for index in int(gems.rules.slots):
		if candidate.gem_state.slots[index] == id: candidate.gem_state.slots[index] = ""
	candidate.gem_state.slots[slot] = id
	var core: Dictionary = gems.find(candidate.gem_state, str(candidate.gem_state.slots[0]))
	candidate.equipped.gem = str(core.get("legacy_id", ""))
	return _commit(candidate)

func request_draw_gems(count: int) -> Dictionary:
	if not _loaded or is_in_run(): return _fail("本局结束后可抽取宝石。")
	if not _state.gem_state.pending_reforge.is_empty(): return _fail("请先选择当前改良结果。")
	if count not in [1, 10]: return _fail("只支持单次或十次抽取。")
	var cost: int = int(gems.rules.draw_cost) * count
	if int(_state.dust) < cost: return _fail("魔尘不足。")
	var candidate: Dictionary = _state.duplicate(true)
	var rng = RandomNumberGenerator.new()
	rng.state = int(candidate.gem_state.rng_state)
	var obtained: Array = []
	for index in count: obtained.append(gems.sample(candidate.gem_state, rng))
	candidate.gem_state.rng_state = str(rng.state)
	candidate.dust -= cost
	var result: Dictionary = _commit(candidate)
	if result.ok: result["gems"] = obtained
	return result

func request_lock_gem(id: String) -> Dictionary:
	if not _loaded or is_in_run(): return _fail("本局结束后可锁定宝石。")
	if not _state.gem_state.pending_reforge.is_empty(): return _fail("请先选择当前改良结果。")
	var candidate: Dictionary = _state.duplicate(true)
	for gem in candidate.gem_state.inventory:
		if gem.id == id:
			gem.locked = not bool(gem.locked)
			return _commit(candidate)
	return _fail("宝石已不存在。")

func request_salvage_gems(ids: Array) -> Dictionary:
	if not _loaded or is_in_run(): return _fail("本局结束后可分解宝石。")
	if not _state.gem_state.pending_reforge.is_empty(): return _fail("请先选择当前改良结果。")
	if ids.is_empty(): return _fail("没有可分解的宝石。")
	var seen: Array = []
	var gain: int = 0
	for id in ids:
		if not id is String or id in seen: return _fail("分解列表重复或无效。")
		var gem: Dictionary = gems.find(_state.gem_state, id)
		if gem.is_empty() or gem.has("legacy_id"): return _fail("传承宝石或未持有的宝石不能分解。")
		if bool(gem.locked) or id in _state.gem_state.slots: return _fail("已装备或锁定的宝石不能分解。")
		seen.append(id)
		gain += int(gems.rules.workshop.salvage_yields[gem.rarity])
	var candidate: Dictionary = _state.duplicate(true)
	candidate.gem_state.inventory = candidate.gem_state.inventory.filter(func(gem): return gem.id not in seen)
	candidate.gem_state.essence += gain
	candidate.gem_state.salvaged += seen.size()
	var result: Dictionary = _commit(candidate)
	if result.ok: result["essence_gained"] = gain
	return result

func request_reforge(id: String, mode: String, index: int = -1) -> Dictionary:
	if not _loaded or is_in_run(): return _fail("本局结束后可改良宝石。")
	if not _state.gem_state.pending_reforge.is_empty(): return _fail("请先选择当前改良结果。")
	var gem: Dictionary = gems.find(_state.gem_state, id)
	if gem.is_empty() or gem.has("legacy_id"): return _fail("传承宝石或未持有的宝石不能改良。")
	if bool(gem.locked): return _fail("请先解锁这枚宝石。")
	if mode not in ["affix", "core"]: return _fail("未知改良方式。")
	if mode == "core" and gem.rarity != "gold": return _fail("只有金色宝石可改良核心。")
	if mode == "affix" and (index < 0 or index >= gem.affixes.size()): return _fail("请选择要改良的词条。")
	var cost: int = int(gems.rules.workshop.core_cost) if mode == "core" else int(gems.rules.workshop.affix_costs[gem.rarity])
	if int(_state.gem_state.essence) < cost: return _fail("宝石精粹不足。")
	var candidate: Dictionary = _state.duplicate(true)
	var rng = RandomNumberGenerator.new()
	rng.state = int(candidate.gem_state.rng_state)
	var outcome: Variant = gems.roll_core(str(gem.core), rng) if mode == "core" else gems.roll_affix(gem, index, rng)
	candidate.gem_state.essence -= cost
	candidate.gem_state.work_serial += 1
	candidate.gem_state.rng_state = str(rng.state)
	candidate.gem_state.pending_reforge = {"gem_id": id, "mode": mode, "index": -1 if mode == "core" else index, "candidate": outcome,
		"old": gem.core if mode == "core" else gem.affixes[index].duplicate(true), "cost": cost, "token": int(candidate.gem_state.work_serial)}
	return _commit(candidate)

func resolve_reforge(token: int, adopt: bool) -> Dictionary:
	if not _loaded or is_in_run(): return _fail("本局结束后可选择改良结果。")
	var pending: Dictionary = _state.gem_state.pending_reforge
	if pending.is_empty() or int(pending.token) != token: return _fail("该改良结果已处理或已失效。")
	var candidate: Dictionary = _state.duplicate(true)
	if adopt:
		for gem in candidate.gem_state.inventory:
			if gem.id != pending.gem_id: continue
			if pending.mode == "core": gem.core = pending.candidate
			else: gem.affixes[int(pending.index)] = pending.candidate.duplicate(true)
	candidate.gem_state.pending_reforge = {}
	return _commit(candidate)

func is_in_run() -> bool:
	return not _run_snapshot.is_empty()

func get_state() -> Dictionary:
	return _state.duplicate(true)

func get_catalog() -> Dictionary:
	if _meta.is_empty() or _base.is_empty():
		return {}
	var catalog = _meta.duplicate(true)
	catalog["spells"] = _spell_catalog()
	catalog["player"] = _base.player.duplicate(true)
	return catalog

func get_items(kind: String) -> Array:
	var items: Array = []
	if not _valid_kind(kind) or _meta.is_empty():
		return items
	for item_id in _items(kind):
		items.append(get_item_status(kind, item_id))
	return items

func get_item_status(kind: String, item_id: String) -> Dictionary:
	if not _valid_kind(kind) or not _items(kind).has(item_id):
		return {}
	var item: Dictionary = _items(kind)[item_id].duplicate(true)
	var level = int(_state.get("levels", {}).get(item_id, 0))
	var free_choice = _loaded and level == 0 and not _state.free_claimed[kind]
	var max_level = int(_meta.progression.max_level)
	var upgrade_cost = int(_meta.progression.upgrade_cost_by_current_level.get(str(level), 0))
	var unlock_cost = 0 if free_choice else int(_meta.progression.unlock_cost)
	var cost = unlock_cost if level == 0 else upgrade_cost
	var available = _loaded and not is_in_run()
	var balance = int(_state.get("dust", 0))
	item.merge({
		"id": item_id, "kind": kind, "level": level, "max_level": max_level,
		"unlocked": level > 0,
		"equipped": _state.get("equipped", {}).get(kind, "") == item_id,
		"free": free_choice, "is_free_choice": free_choice,
		"unlock_cost": unlock_cost, "upgrade_cost": upgrade_cost, "cost": cost,
		"can_unlock": available and level == 0 and balance >= unlock_cost,
		"can_upgrade": available and level > 0 and level < max_level and balance >= upgrade_cost,
		"can_equip": available and level > 0,
		"blocked_reason": "本局结束后可调整装备。" if is_in_run() else (error if not _loaded else ""),
	}, true)
	if kind == "catalyst":
		item["effect_by_level"] = _meta.catalyst_weight_by_level.duplicate()
		item["related_spell_names"] = []
		var spells = _spell_catalog()
		for spell_id in item.related_spells:
			item.related_spell_names.append(spells[spell_id].name)
		item["effect_value"] = 1.0 if level == 0 else _meta.catalyst_weight_by_level[level - 1]
	else:
		item["effect_by_level"] = item.flat_by_level.duplicate()
		item["effect_value"] = 0 if level == 0 else item.flat_by_level[level - 1]
	item["next_effect_value"] = item.effect_by_level[level] if level < max_level else item.effect_value
	if kind == "gem":
		item.can_upgrade = false
		item.can_unlock = available and free_choice
		item.blocked_reason = "传承宝石保留原属性，后续通过魔尘抽取新宝石。"
	return item

func request_unlock(kind: String, item_id: String) -> Dictionary:
	var invalid = _request_error(kind, item_id)
	if not invalid.is_empty():
		return _fail(invalid)
	if kind == "gem":
		return claim_starter_gem(item_id)
	var status = get_item_status(kind, item_id)
	if status.unlocked:
		return _fail("该物品已经解锁。")
	if not status.can_unlock:
		return _fail("魔尘不足。")
	var candidate = _state.duplicate(true)
	candidate.dust -= status.unlock_cost
	candidate.levels[item_id] = int(_meta.progression.free_choice_level if status.free else _meta.progression.unlock_level)
	if status.free:
		candidate.free_claimed[kind] = true
		candidate.equipped[kind] = item_id
	return _commit(candidate)

func request_upgrade(kind: String, item_id: String) -> Dictionary:
	if kind == "gem": return _fail("旧版宝石已转为传承宝石，不再付费升级；新宝石通过抽取获得。")
	var invalid = _request_error(kind, item_id)
	if not invalid.is_empty():
		return _fail(invalid)
	var status = get_item_status(kind, item_id)
	if not status.unlocked:
		return _fail("请先解锁该物品。")
	if status.level >= status.max_level:
		return _fail("已达到最高等级。")
	if not status.can_upgrade:
		return _fail("魔尘不足。")
	var candidate = _state.duplicate(true)
	candidate.dust -= status.upgrade_cost
	candidate.levels[item_id] += 1
	return _commit(candidate)

func request_equip(kind: String, item_id: String = "") -> Dictionary:
	if kind == "gem":
		var id: String = item_id
		for gem in get_gems():
			if str(gem.get("legacy_id", "")) == item_id: id = str(gem.id)
		return request_equip_gem(0, id)
	if not _loaded:
		return _fail("存档尚未成功读取。")
	if is_in_run():
		return _fail("本局结束后可调整装备。")
	if not _valid_kind(kind):
		return _fail("未知装备类型。")
	if not item_id.is_empty() and (not _items(kind).has(item_id) or int(_state.levels[item_id]) == 0):
		return _fail("只能装备已经解锁的物品。")
	if _state.equipped[kind] == item_id:
		return {"ok": true, "error": "", "state": get_state()}
	var candidate = _state.duplicate(true)
	candidate.equipped[kind] = item_id
	return _commit(candidate)

func get_preview_stats() -> Dictionary:
	if _base.is_empty():
		return {}
	var stats: Dictionary = _base.player.duplicate(true)
	var bonuses: Dictionary = gems.totals(_state.gem_state)
	for key in bonuses: stats[key] = float(stats.get(key, 0.0)) + float(bonuses[key])
	if gems.core_id(_state.gem_state) == "aegis":
		var converted: float = float(stats.health) * float(gems.rules.cores.aegis.life_conversion)
		stats.health -= converted
		stats.shield += converted * float(gems.rules.cores.aegis.shield_per_life)
	return stats

func begin_run() -> Dictionary:
	if not _loaded:
		return _fail("存档尚未成功读取。")
	if is_in_run():
		return _fail("已经处于一局中。")
	_run_snapshot = _make_snapshot(true)
	error = ""
	return {"ok": true, "error": "", "snapshot": get_run_snapshot()}

func begin_playable_run(reward_scope: String = "legacy") -> Dictionary:
	if reward_scope not in ["legacy", "route45"]: return _fail("未知结算范围。")
	if not _loaded:
		return _fail("存档尚未成功读取。")
	if is_in_run():
		return _fail("已经处于一局中。")
	var candidate = _state.duplicate(true)
	candidate.run_serial += 1
	# Persist the serial before exposing a playable token. A forced close consumes
	# that token, never credits an unfinished run, and cannot reuse it next time.
	var result = _commit(candidate)
	if not result.ok:
		return result
	_run_snapshot = _make_snapshot(false)
	_run_snapshot["run_id"] = _run_id(int(_state.run_serial))
	_run_snapshot["reward_scope"] = reward_scope
	return {"ok": true, "error": "", "snapshot": get_run_snapshot(), "run_id": _run_snapshot.run_id}

func _make_snapshot(preview_only: bool) -> Dictionary:
	return {
		"equipment": _state.equipped.duplicate(true),
		"levels": _state.levels.duplicate(true),
		"player": get_preview_stats(),
		"meta_version": _meta.version,
		"preview_only": preview_only,
		"gem_slots": _state.gem_state.slots.duplicate(),
		"gem_bonuses": gems.totals(_state.gem_state),
		"gem_core": gems.core_id(_state.gem_state),
	}

func get_run_snapshot() -> Dictionary:
	return _run_snapshot.duplicate(true)

func end_run() -> Dictionary:
	# The interface preview has no actual room clears, so it cannot award currency.
	if is_in_run() and not _run_snapshot.preview_only:
		return _fail("实际试玩必须按核心清房结果结算后结束。")
	_run_snapshot.clear()
	error = ""
	return {"ok": true, "error": "", "state": get_state()}

func settle_playable_run(run_id: String, cleared_rooms: Array) -> Dictionary:
	# Only the controller supplies the core's authoritative clear ledger. There is
	# deliberately no dust amount, victory button, or UI-reported reward argument.
	if not _loaded:
		return _fail("存档尚未成功读取。")
	var invalid = _validate_cleared_rooms(cleared_rooms)
	if not invalid.is_empty():
		return _fail(invalid)
	var rooms: Array = []
	for room in cleared_rooms:
		rooms.append(int(room))
	var previous: Dictionary = _state.last_settlement
	if not previous.is_empty() and previous.run_id == run_id:
		if previous.cleared_rooms != rooms:
			return _fail("该局已经结算，清房记录与原结算不一致。")
		error = ""
		return _settlement_result(previous, true)
	if not is_in_run() or _run_snapshot.preview_only or _run_snapshot.run_id != run_id:
		return _fail("没有匹配的实际试玩记录，无法结算。")
	var candidate = _state.duplicate(true)
	var scope: String = str(_run_snapshot.get("reward_scope", "legacy"))
	# Keep the persisted route45 scope compatible; its room limit is data-owned.
	if scope == "route45" and rooms.size() > int(gems.rules.route_income.max_room): return _fail("清房超出当前路线范围。")
	var dust_earned = _dust_for_rooms(rooms, scope)
	candidate.dust += dust_earned
	candidate.settlement_serial += 1
	candidate.last_settlement = {
		"run_id": run_id, "run_serial": int(_state.run_serial),
		"cleared_rooms": rooms, "dust_earned": dust_earned,
		"settlement_serial": int(candidate.settlement_serial),
		"reward_scope": scope,
	}
	var result = _commit(candidate)
	if not result.ok:
		# Keep both snapshot and the uncredited ledger for an exact retry.
		return result
	_run_snapshot.clear()
	return _settlement_result(_state.last_settlement, false)

func _settlement_result(settlement: Dictionary, already_settled: bool) -> Dictionary:
	var result = settlement.duplicate(true)
	result.merge({"ok": true, "error": "", "state": get_state(), "already_settled": already_settled})
	return result

func _run_id(serial: int) -> String:
	return "local-run-%d" % serial

func _validate_cleared_rooms(rooms: Array) -> String:
	var max_room = int(_economy.stages[-1].to)
	if rooms.size() > max_room:
		return "清房记录超出本关范围。"
	for index in range(rooms.size()):
		if not _is_integer(rooms[index], 1) or rooms[index] != index + 1:
			return "清房记录必须从首房开始连续且不重复。"
	return ""

func _dust_for_rooms(rooms: Array, scope: String = "legacy") -> int:
	var amount = 0
	for room in rooms:
		if scope == "route45":
			amount += int(gems.rules.route_income.early_dust if int(room) <= int(gems.rules.route_income.early_end) else gems.rules.route_income.later_dust)
			continue
		for stage in _economy.stages:
			if room >= stage.from and room <= stage.to:
				amount += int(_meta.currency.room_dust_by_stage[stage.id])
				break
		for boss in _base.bosses:
			if boss.room == room:
				amount += int(_meta.currency.boss_bonus_by_id[boss.id])
	return amount

func reset_for_tests() -> Dictionary:
	# Never offer a reset of a real player's save through a UI action.
	if not save_path.begins_with(TEST_SAVE_ROOT) or ".." in save_path:
		return _fail("只能重置隔离测试存档。")
	_run_snapshot.clear()
	for path in [save_path, save_path + ".tmp"]:
		if FileAccess.file_exists(path):
			var result = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			if result != OK:
				return _fail("无法清理隔离测试存档。")
	_state.clear()
	return load_state()

func _commit(candidate: Dictionary) -> Dictionary:
	var result = _write_state(candidate)
	if not result.ok:
		return _fail(result.error)
	_state = candidate
	error = ""
	return {"ok": true, "error": "", "state": get_state()}

func _write_state(candidate: Dictionary) -> Dictionary:
	var invalid = _validate_state(candidate)
	if not invalid.is_empty():
		return {"ok": false, "error": "拒绝保存无效进度：" + invalid}
	var absolute_path = ProjectSettings.globalize_path(save_path)
	if DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir()) != OK:
		return {"ok": false, "error": "无法创建存档目录，进度未变更。"}
	var temporary_path = absolute_path + ".tmp"
	var serialized = JSON.stringify(candidate, "\t", true, true)
	var file = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "无法写入临时存档，进度未变更。"}
	file.store_string(serialized)
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK or FileAccess.get_file_as_string(temporary_path) != serialized:
		return {"ok": false, "error": "存档写入校验失败，进度未变更。"}
	# Replace only after flushing and readback. A failed rename leaves the old file intact.
	if DirAccess.rename_absolute(temporary_path, absolute_path) != OK:
		return {"ok": false, "error": "存档替换失败，进度未变更。"}
	return {"ok": true, "error": ""}

func _new_state() -> Dictionary:
	var levels: Dictionary = {}
	for item_id in _meta.catalysts:
		levels[item_id] = 0
	for item_id in _meta.gems:
		levels[item_id] = 0
	return {
		"version": SAVE_VERSION,
		"dust": int(_meta.currency.initial),
		"levels": levels,
		"equipped": {"catalyst": "", "gem": ""},
		"free_claimed": {"catalyst": false, "gem": false},
		"settlement_serial": 0,
		"run_serial": 0,
		"last_settlement": {},
		"gem_state": gems.fresh(),
	}

func _request_error(kind: String, item_id: String) -> String:
	if not _loaded:
		return "存档尚未成功读取。"
	if is_in_run():
		return "本局结束后可调整装备。"
	if not _valid_kind(kind) or not _items(kind).has(item_id):
		return "未知装备。"
	return ""

func _valid_kind(kind: String) -> bool:
	return kind in ["catalyst", "gem"]

func _items(kind: String) -> Dictionary:
	return _meta.get("catalysts" if kind == "catalyst" else "gems", {})

func _fail(message: String) -> Dictionary:
	error = message
	return {"ok": false, "error": message}

func _read_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "无法读取文件：" + path}
	var content = file.get_as_text()
	file.close()
	var parser = JSON.new()
	if parser.parse(content) != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "JSON内容无效：" + path}
	return {"ok": true, "data": parser.data}

func _is_integer(value: Variant, minimum: int = 0) -> bool:
	# JSON numbers must stay exactly representable across save/read cycles.
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= 9007199254740991 and float(value) == floor(float(value))

func _load_ice_source() -> String:
	if not _meta.get("ice_parameters") is String or str(_meta.ice_parameters).is_empty():
		return "缺少冰系法术引用。"
	var path = str(_meta.ice_parameters)
	if not path.begins_with("res://"):
		path = META_PATH.get_base_dir().path_join(path)
	var result = _read_json(path)
	if not result.ok:
		return result.error
	if not result.data.get("spells") is Dictionary:
		return "冰系法术源缺少 spells。"
	_ice_base = result.data
	return ""

func _spell_catalog() -> Dictionary:
	var spells: Dictionary = {}
	if _base.get("spells") is Dictionary:
		spells = _base.spells.duplicate(true)
	if _ice_base.get("spells") is Dictionary:
		spells.merge(_ice_base.spells.duplicate(true), true)
	return spells

func _catalyst_id_for_school(school: String) -> String:
	for item_id in _meta.catalysts:
		if str(_meta.catalysts[item_id].get("school", "")) == school:
			return str(item_id)
	return ""

func _legacy_catalyst_cost(level: int) -> int:
	var cost = 0
	if level >= 1:
		cost += int(_meta.progression.unlock_cost)
	for current in range(1, level):
		cost += int(_meta.progression.upgrade_cost_by_current_level.get(str(current), 0))
	return cost

func _migrate_legacy_state(candidate: Dictionary) -> Dictionary:
	# The three temporary catalysts (MC01-MC03) are removed. Keep the highest
	# invested level once on the fire catalyst, equip fire if the old catalyst
	# was equipped, and refund only duplicate paid levels. The old file is not
	# rewritten here; the migration becomes persistent on the next save.
	if candidate.get("version") != LEGACY_SAVE_VERSION:
		return {}
	if not _is_integer(candidate.get("dust")) or not _is_integer(candidate.get("settlement_serial")):
		return {}
	var levels: Variant = candidate.get("levels")
	if not levels is Dictionary or levels.size() != LEGACY_CATALYST_IDS.size() + LEGACY_GEM_IDS.size():
		return {}
	for item_id in LEGACY_CATALYST_IDS + LEGACY_GEM_IDS:
		if not levels.has(item_id) or not _is_integer(levels[item_id]) or int(levels[item_id]) > int(_meta.progression.max_level):
			return {}
	var equipped: Variant = candidate.get("equipped")
	var free_claimed: Variant = candidate.get("free_claimed")
	if not equipped is Dictionary or not free_claimed is Dictionary:
		return {}
	if equipped.size() != 2 or free_claimed.size() != 2:
		return {}
	var old_catalyst = equipped.get("catalyst")
	var old_gem = equipped.get("gem")
	if not old_catalyst is String or not old_gem is String:
		return {}
	if not old_catalyst.is_empty() and not LEGACY_CATALYST_IDS.has(old_catalyst):
		return {}
	if not old_gem.is_empty() and not LEGACY_GEM_IDS.has(old_gem):
		return {}
	if not free_claimed.get("catalyst") is bool or not free_claimed.get("gem") is bool:
		return {}
	var run_serial: Variant = candidate.get("run_serial", candidate.settlement_serial)
	if not _is_integer(run_serial) or int(run_serial) < int(candidate.settlement_serial):
		return {}
	var settlement: Variant = candidate.get("last_settlement", {})
	if not settlement is Dictionary:
		return {}
	var fire_level = 0
	var inherited_id = ""
	for item_id in LEGACY_CATALYST_IDS:
		var level = int(levels[item_id])
		if level > fire_level:
			fire_level = level
			inherited_id = str(item_id)
	var fire_id = _catalyst_id_for_school("fire")
	var ice_id = _catalyst_id_for_school("ice")
	if fire_id.is_empty() or ice_id.is_empty():
		return {}
	var refund = 0
	for item_id in LEGACY_CATALYST_IDS:
		if str(item_id) == inherited_id:
			continue
		refund += _legacy_catalyst_cost(int(levels[item_id]))
	var migrated_levels: Dictionary = {}
	migrated_levels[fire_id] = fire_level
	migrated_levels[ice_id] = 0
	for item_id in LEGACY_GEM_IDS:
		migrated_levels[item_id] = int(levels[item_id])
	var migrated: Dictionary = {
		"version": SAVE_VERSION,
		"dust": int(candidate.dust) + refund,
		"levels": migrated_levels,
		"equipped": {
			"catalyst": fire_id if not old_catalyst.is_empty() and int(levels.get(old_catalyst, 0)) > 0 else "",
			"gem": old_gem,
		},
		"free_claimed": {"catalyst": fire_level > 0, "gem": bool(free_claimed.gem)},
		"settlement_serial": int(candidate.settlement_serial),
		"run_serial": int(run_serial),
		"last_settlement": settlement.duplicate(true),
	}
	if not migrated.last_settlement.is_empty():
		for field in ["run_serial", "dust_earned", "settlement_serial"]:
			if not _is_integer(migrated.last_settlement.get(field), 1):
				return {}
			migrated.last_settlement[field] = int(migrated.last_settlement[field])
		if not migrated.last_settlement.get("cleared_rooms") is Array:
			return {}
		for index in range(migrated.last_settlement.cleared_rooms.size()):
			if not _is_integer(migrated.last_settlement.cleared_rooms[index], 1):
				return {}
			migrated.last_settlement.cleared_rooms[index] = int(migrated.last_settlement.cleared_rooms[index])
	migrated = _migrate_gem_state(migrated)
	var invalid = _validate_state(migrated)
	if not invalid.is_empty():
		return {}
	return migrated

func _validate_catalog() -> String:
	for key in ["version", "currency", "progression", "equipment", "catalyst_weight_by_level", "catalyst_schools", "catalysts", "gems"]:
		if not _meta.has(key):
			return "缺少字段 " + key
	for key in ["currency", "progression", "equipment", "catalysts", "gems"]:
		if not _meta[key] is Dictionary:
			return "字段类型无效：" + key
	if not _base.get("player") is Dictionary or not _base.get("spells") is Dictionary:
		return "基础参数缺少角色或法术。"
	if not _ice_base.get("spells") is Dictionary:
		return "冰系法术源缺少 spells。"
	if not _meta.get("catalyst_schools") is Array or _meta.catalyst_schools.is_empty():
		return "触媒学派列表无效。"
	var supported_schools: Array = []
	for school in _meta.catalyst_schools:
		if not school is String or str(school).is_empty() or supported_schools.has(school):
			return "触媒学派列表无效。"
		supported_schools.append(str(school))
	for stat in ["health", "shield", "attack"]:
		if not _is_integer(_base.player.get(stat), 1):
			return "基础属性无效：" + stat
	if not _is_integer(_meta.currency.get("initial")):
		return "初始魔尘无效。"
	var reward_error = _validate_reward_catalog()
	if not reward_error.is_empty():
		return reward_error
	var progression: Dictionary = _meta.progression
	if not _is_integer(progression.get("max_level"), 1) or not _is_integer(progression.get("unlock_cost")):
		return "等级或解锁费用无效。"
	if not _is_integer(progression.get("free_choice_level"), 1) or not _is_integer(progression.get("unlock_level"), 1):
		return "初始解锁等级无效。"
	if progression.free_choice_level > progression.max_level or progression.unlock_level > progression.max_level:
		return "初始等级超过上限。"
	if not progression.get("first_choice_free_per_kind", false):
		return "本版需要按类型首次免费领取。"
	if not progression.get("upgrade_cost_by_current_level") is Dictionary:
		return "升级费用表无效。"
	for level in range(1, int(progression.max_level)):
		if not _is_integer(progression.upgrade_cost_by_current_level.get(str(level))):
			return "缺少合法升级费用。"
	if not _meta.catalyst_weight_by_level is Array or _meta.catalyst_weight_by_level.size() != int(progression.max_level):
		return "触媒等级权重数量无效。"
	for weight in _meta.catalyst_weight_by_level:
		if not (weight is int or weight is float) or not is_finite(float(weight)) or weight <= 0:
			return "触媒权重无效。"
	if _meta.catalysts.is_empty() or _meta.gems.is_empty():
		return "物品图鉴为空。"
	var spells: Dictionary = _spell_catalog()
	var seen_schools: Array = []
	for item_id in _meta.catalysts:
		if _meta.gems.has(item_id):
			return "触媒与宝石ID重复。"
		var item = _meta.catalysts[item_id]
		if not item is Dictionary or not item.get("name") is String or not item.get("related_spells") is Array or not item.get("school") is String:
			return "触媒条目无效：" + item_id
		var school = str(item.school)
		if not supported_schools.has(school):
			return "触媒学派未开放：" + school
		if seen_schools.has(school):
			return "同一学派触媒重复：" + school
		seen_schools.append(school)
		if item.related_spells.is_empty():
			return "触媒关联法术为空：" + item_id
		for spell_id in item.related_spells:
			if not spells.has(spell_id) or not spells[spell_id].get("name") is String:
				return "触媒关联法术不存在：" + str(spell_id)
			if str(spells[spell_id].get("school", "")) != school:
				return "触媒关联法术学派不一致：" + str(spell_id)
			if not bool(spells[spell_id].get("active", true)):
				return "触媒关联法术未启用：" + str(spell_id)
	for school in supported_schools:
		if not seen_schools.has(school):
			return "缺少 " + school + " 学派触媒。"
	for item_id in _meta.gems:
		var item = _meta.gems[item_id]
		if not item is Dictionary or not item.get("name") is String or item.get("stat") not in ["health", "shield", "attack"]:
			return "宝石条目无效：" + item_id
		if not item.get("flat_by_level") is Array or item.flat_by_level.size() != int(progression.max_level):
			return "宝石等级数量无效：" + item_id
		for bonus in item.flat_by_level:
			if not _is_integer(bonus):
				return "宝石属性无效：" + item_id
	return ""

func _validate_reward_catalog() -> String:
	if not _economy.get("stages") is Array or _economy.stages.is_empty():
		return "缺少魔尘对应的房间阶段。"
	if not _meta.currency.get("room_dust_by_stage") is Dictionary or not _meta.currency.get("boss_bonus_by_id") is Dictionary:
		return "魔尘收益表无效。"
	var expected_room = 1
	var stage_ids: Array = []
	for stage in _economy.stages:
		if not stage is Dictionary or not stage.get("id") is String or stage.id.is_empty() or stage_ids.has(stage.id):
			return "魔尘房间阶段ID无效。"
		if not _is_integer(stage.get("from"), 1) or not _is_integer(stage.get("to"), 1) or stage.from != expected_room or stage.to < stage.from:
			return "魔尘房间阶段必须连续。"
		if not _is_integer(_meta.currency.room_dust_by_stage.get(stage.id)):
			return "缺少合法阶段魔尘收益。"
		stage_ids.append(stage.id)
		expected_room = int(stage.to) + 1
	if not _base.get("bosses") is Array:
		return "缺少魔尘对应的首领节点。"
	var boss_ids: Array = []
	var boss_rooms: Array = []
	for boss in _base.bosses:
		if not boss is Dictionary or not boss.get("id") is String or boss.id.is_empty() or boss_ids.has(boss.id):
			return "魔尘首领ID无效。"
		if not _is_integer(boss.get("room"), 1) or boss.room >= expected_room or boss_rooms.has(boss.room):
			return "魔尘首领房号无效。"
		if not _is_integer(_meta.currency.boss_bonus_by_id.get(boss.id)):
			return "缺少合法首领魔尘奖励。"
		boss_ids.append(boss.id)
		boss_rooms.append(boss.room)
	return ""

func _validate_state(candidate: Dictionary) -> String:
	if candidate.get("version") != SAVE_VERSION:
		return "不支持的存档版本。"
	if not _is_integer(candidate.get("dust")) or not _is_integer(candidate.get("settlement_serial")):
		return "魔尘或结算序号无效。"
	# Both keys are optional only for saves created before playable runs existed.
	var run_serial: Variant = candidate.get("run_serial", candidate.settlement_serial)
	if not _is_integer(run_serial) or run_serial < candidate.settlement_serial:
		return "实际试玩序号无效。"
	var settlement: Variant = candidate.get("last_settlement", {})
	if not settlement is Dictionary:
		return "最近结算记录无效。"
	if not settlement.is_empty():
		if not _is_integer(settlement.get("run_serial"), 1) or settlement.run_serial > run_serial:
			return "最近结算试玩序号无效。"
		if not settlement.get("run_id") is String or settlement.run_id != _run_id(int(settlement.run_serial)):
			return "最近结算标识无效。"
		if not _is_integer(settlement.get("settlement_serial"), 1) or settlement.settlement_serial != candidate.settlement_serial:
			return "最近结算序号不匹配。"
		if not settlement.get("cleared_rooms") is Array or not _validate_cleared_rooms(settlement.cleared_rooms).is_empty():
			return "最近结算清房记录无效。"
		var scope: String = str(settlement.get("reward_scope", "legacy"))
		if scope not in ["legacy", "route45"] or (scope == "route45" and settlement.cleared_rooms.size() > int(gems.rules.route_income.max_room)): return "最近结算范围无效。"
		if not _is_integer(settlement.get("dust_earned")) or settlement.dust_earned != _dust_for_rooms(settlement.cleared_rooms, scope):
			return "最近结算收益与参数不匹配。"
	for field in ["levels", "equipped", "free_claimed"]:
		if not candidate.get(field) is Dictionary:
			return "缺少有效的 " + field
	if candidate.levels.size() != _meta.catalysts.size() + _meta.gems.size():
		return "物品等级数量不匹配。"
	if candidate.equipped.size() != 2 or candidate.free_claimed.size() != 2:
		return "装备或免费领取状态数量不匹配。"
	for kind in ["catalyst", "gem"]:
		if not candidate.equipped.get(kind) is String or not candidate.free_claimed.get(kind) is bool:
			return "装备或免费领取状态无效。"
		var any_owned = false
		for item_id in _items(kind):
			var level = candidate.levels.get(item_id)
			if not _is_integer(level) or level > int(_meta.progression.max_level):
				return "无效物品等级：" + item_id
			any_owned = any_owned or level > 0
		if any_owned != candidate.free_claimed[kind]:
			return "免费领取状态与已解锁物品不一致。"
		var equipped_id: String = candidate.equipped[kind]
		if not equipped_id.is_empty() and (not _items(kind).has(equipped_id) or int(candidate.levels[equipped_id]) == 0):
			return "装备引用未解锁物品。"
	return gems.validate(candidate.get("gem_state"), _meta.gems, candidate.levels)
