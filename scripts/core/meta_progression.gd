extends RefCounted
## Preparation progression. All values come from the approved JSON sources.
## UI requests operate on copies and become visible only after a successful save.

const META_PATH = "res://data/balance_candidates/meta_growth_v1.json"
const Gems = preload("res://scripts/core/magic_gems.gd")
const SpellSampling = preload("res://scripts/core/route_spell_sampling.gd")
const SAVE_VERSION = "meta-progression-7"
const SAVE_VERSION_TAG = "meta-progression-"
const DEFAULT_SAVE_PATH = "user://meta_progression_v1.json"
const TEST_SAVE_ROOT = "user://tests/meta_progression/"

var save_path: String
var error: String = ""
var incompatible_save_version: String = ""
var _meta: Dictionary = {}
var _base: Dictionary = {}
var _ice_base: Dictionary = {}
var _school_sources: Dictionary = {}
var _sampling: Dictionary = {}
var _economy: Dictionary = {}
var _state: Dictionary = {}
var _run_snapshot: Dictionary = {}
var _loaded: bool = false
var _display_limits: Dictionary = {}
var gems = Gems.new()

func _init(path: String = DEFAULT_SAVE_PATH):
	save_path = path

func load_state() -> Dictionary:
	if not _run_snapshot.is_empty():
		return _fail("本局结束前不能重新读取局外存档。")
	_loaded = false
	incompatible_save_version = ""
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
	var extra_error: String = _load_formal_school_sources()
	if not extra_error.is_empty(): return _fail("局外参数错误：" + extra_error)
	var catalog_error = _validate_catalog()
	if not catalog_error.is_empty():
		return _fail("局外参数错误：" + catalog_error)
	if FileAccess.file_exists(save_path):
		result = _read_json(save_path)
		if not result.ok:
			return _fail("已有存档无法读取，进度未覆盖。" + result.error)
		var save_data: Dictionary = result.data
		var save_version = str(save_data.get("version", ""))
		if save_version != SAVE_VERSION:
			# No compatibility path exists in this build. Any recognizable old
			# or newer archive is archived by the caller, never read or rewritten.
			if _save_version_rank(save_version) >= 0:
				return _fail("旧存档版本不兼容（%s），当前只支持 %s；原文件未覆盖。" % [save_version, SAVE_VERSION], save_version)
			return _fail("已有存档损坏，进度未覆盖：不支持的存档版本。")
		if not save_data.get("gem_state") is Dictionary: return _fail("已有宝石存档损坏，原文件未覆盖。")
		var state_error = _validate_state(save_data)
		if not state_error.is_empty():
			return _fail("已有存档损坏，进度未覆盖：" + state_error)
		_state = save_data.duplicate(true)
		_state.dust = int(_state.dust)
		_state.settlement_serial = int(_state.settlement_serial)
		_state["run_serial"] = int(_state.get("run_serial", _state.settlement_serial))
		_state["last_settlement"] = _state.get("last_settlement", {}).duplicate(true)
		if not _state.last_settlement.is_empty():
			for field in ["run_serial", "dust_earned", "settlement_serial"]:
				_state.last_settlement[field] = int(_state.last_settlement[field])
			if _state.last_settlement.has("essence_earned"): _state.last_settlement.essence_earned = int(_state.last_settlement.essence_earned)
			for index in range(_state.last_settlement.cleared_rooms.size()):
				_state.last_settlement.cleared_rooms[index] = int(_state.last_settlement.cleared_rooms[index])
		for item_id in _state.levels:
			_state.levels[item_id] = int(_state.levels[item_id])
		for field in ["serial", "draws", "gold_misses", "rare_misses", "essence", "salvaged", "work_serial", "cumulative_cleared"]:
			_state.gem_state[field] = int(_state.gem_state[field])
		for index in _state.gem_state.milestone_claimed.size():
			_state.gem_state.milestone_claimed[index] = int(_state.gem_state.milestone_claimed[index])
		for gem in _state.gem_state.inventory:
			gem.serial = int(gem.serial)
			for line in gem.affixes:
				if line.has("tier"): line.tier = int(line.tier)
		var pending: Dictionary = _state.gem_state.pending_reforge
		if not pending.is_empty():
			for field in ["token", "cost"]: pending[field] = int(pending[field])
			if pending.get("locks") is Array:
				# JSON numbers come back as floats; locks must stay integers so
				# a pending candidate still validates after a restart.
				var normalized: Array = []
				for lock in pending.locks:
					normalized.append(lock if lock is String else int(lock))
				pending.locks = normalized
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

func get_gems() -> Array:
	return _state.get("gem_state", {}).get("inventory", []).duplicate(true)

func _gem_request_error() -> String:
	if not _loaded: return "存档尚未成功读取。"
	if is_in_run(): return "本局结束后可调整宝石。"
	if not _state.gem_state.pending_reforge.is_empty(): return "请先选择当前重洗结果。"
	return ""

## Four unrestricted slots. A gem may only occupy one slot; gold gems act only
## through their keystone and still count as ordinary equipped instances.
func request_equip_gem(slot: int, id: String = "") -> Dictionary:
	var invalid: String = _gem_request_error()
	if not invalid.is_empty(): return _fail(invalid)
	if slot<0 or slot>=int(gems.rules.slots): return _fail("未知宝石槽。")
	if not id.is_empty() and gems.find(_state.gem_state,id).is_empty(): return _fail("只能装备已持有的宝石。")
	var candidate: Dictionary = _state.duplicate(true)
	for index in int(gems.rules.slots):
		if candidate.gem_state.slots[index]==id: candidate.gem_state.slots[index] = ""
	candidate.gem_state.slots[slot] = id
	return _commit(candidate)

func request_draw_gems(count: int) -> Dictionary:
	var invalid: String = _gem_request_error()
	if not invalid.is_empty(): return _fail(invalid)
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
	var invalid: String = _gem_request_error()
	if not invalid.is_empty(): return _fail(invalid)
	if not _loaded or is_in_run(): return _fail("本局结束后可锁定宝石。")
	if not _state.gem_state.pending_reforge.is_empty(): return _fail("请先选择当前改良结果。")
	var candidate: Dictionary = _state.duplicate(true)
	for gem in candidate.gem_state.inventory:
		if gem.id == id:
			gem.locked = not bool(gem.locked)
			return _commit(candidate)
	return _fail("宝石已不存在。")

func request_salvage_gems(ids: Array) -> Dictionary:
	var invalid: String = _gem_request_error()
	if not invalid.is_empty(): return _fail(invalid)
	if not _loaded or is_in_run(): return _fail("本局结束后可分解宝石。")
	if not _state.gem_state.pending_reforge.is_empty(): return _fail("请先选择当前改良结果。")
	if ids.is_empty(): return _fail("没有可分解的宝石。")
	var seen: Array = []
	var gain: int = 0
	for id in ids:
		if not id is String or id in seen: return _fail("分解列表重复或无效。")
		var gem: Dictionary = gems.find(_state.gem_state, id)
		if gem.is_empty(): return _fail("未持有的宝石不能分解。")
		if bool(gem.locked) or id in _state.gem_state.slots: return _fail("已装备或锁定的宝石不能分解。")
		seen.append(id)
		gain += gems.salvage_yield(gem)
	var candidate: Dictionary = _state.duplicate(true)
	candidate.gem_state.inventory = candidate.gem_state.inventory.filter(func(gem): return gem.id not in seen)
	candidate.gem_state.essence += gain
	candidate.gem_state.salvaged += seen.size()
	var result: Dictionary = _commit(candidate)
	if result.ok: result["essence_gained"] = gain
	return result

func reforge_cost(id: String, locks: Array) -> int:
	var gem: Dictionary = gems.find(_state.gem_state, id)
	return -1 if gem.is_empty() else gems.reforge_cost(gem, locks)

## Pays first, then stores one candidate. Locked effects or attributes keep
## their exact line; the rest are rerolled inside the single transaction.
func request_reroll_gem(id: String, locks: Array = []) -> Dictionary:
	var invalid: String = _gem_request_error()
	if not invalid.is_empty(): return _fail(invalid)
	var gem: Dictionary = gems.find(_state.gem_state, id)
	if gem.is_empty(): return _fail("宝石已不存在。")
	if locks.size() > int(gems.rules.reforge.max_locks): return _fail("最多锁定%d项。" % int(gems.rules.reforge.max_locks))
	var unique_locks: Array = []
	for lock in locks:
		if lock in unique_locks: return _fail("锁定项重复。")
		unique_locks.append(lock)
	if gems.lock_count(gem, locks) != locks.size() or locks.size() >= gems.lockable_count(gem): return _fail("锁定项无效或没有可重洗的内容。")
	var cost: int = gems.reforge_cost(gem, locks)
	if int(_state.gem_state.essence) < cost: return _fail("宝石精粹不足。")
	var candidate: Dictionary = _state.duplicate(true)
	var rng = RandomNumberGenerator.new()
	rng.state = int(candidate.gem_state.rng_state)
	var outcome: Dictionary = gems.roll_gem(gem, locks, rng)
	candidate.gem_state.essence -= cost
	candidate.gem_state.work_serial += 1
	candidate.gem_state.rng_state = str(rng.state)
	candidate.gem_state.pending_reforge = {"gem_id":id, "mode":"reroll", "locks":locks.duplicate(), "candidate":{"core":outcome.core, "affixes":outcome.affixes}, "old":{"core":gem.core, "affixes":gem.affixes.duplicate(true)}, "cost":cost, "token":int(candidate.gem_state.work_serial)}
	var result: Dictionary = _commit(candidate)
	if result.ok: result["candidate"] = candidate.gem_state.pending_reforge.duplicate(true)
	return result

func resolve_reforge(token: int, adopt: bool) -> Dictionary:
	if not _loaded or is_in_run(): return _fail("本局结束后可选择重洗结果。")
	var pending: Dictionary = _state.gem_state.pending_reforge
	if pending.is_empty() or int(pending.token) != token: return _fail("该重洗结果已处理或已失效。")
	var candidate: Dictionary = _state.duplicate(true)
	if adopt:
		for gem in candidate.gem_state.inventory:
			if gem.id != pending.gem_id: continue
			gem.core = str(pending.candidate.core)
			gem.affixes = pending.candidate.affixes.duplicate(true)
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
	catalog["spell_sampling"] = _sampling.duplicate(true)
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
		item["effect_kind"] = "school_priority"
		item["effect_by_level"] = _sampling.catalyst_affinity_by_level.duplicate()
		item["related_spell_names"] = []
		var spells = _spell_catalog()
		for spell_id in item.related_spells:
			item.related_spell_names.append(spells[spell_id].name)
		item["effect_value"] = 0.0 if level == 0 else _sampling.catalyst_affinity_by_level[level - 1]
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
		return _fail("宝石槽已改为独立装备，请到宝石页操作。")
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
	if kind == "gem": return _fail("宝石不再通过触媒升级，请使用精粹重洗。")
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
		return request_equip_gem(1, id)
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
	if "aegis" in gems.active_effects(_state.gem_state):
		var converted: float = float(stats.health) * float(gems.rules.cores.aegis.life_conversion)
		stats.health -= converted
		stats.shield += converted * float(gems.rules.cores.aegis.shield_per_life)
	return stats

## Read-only breakdown for the preparation screen. "bonus" is the net change the
## equipped gems make, so aegis conversions stay visible instead of hidden in the
## final number. Caps come from the same data files the combat layer loads.
func get_stat_breakdown() -> Array:
	if _base.is_empty(): return []
	var base: Dictionary = _base.get("player", {})
	var final_stats: Dictionary = get_preview_stats()
	var limits: Dictionary = _stat_display_limits()
	var effects: Array = gems.active_effects(_state.gem_state)
	var aegis_note: String = "含血晶屏障转换" if "aegis" in effects else ""
	var rows: Array = []
	rows.append(_stat_row("attack", "攻击力", "flat", base, final_stats, 0.0, ""))
	rows.append(_stat_row("health", "生命上限", "flat", base, final_stats, 0.0, aegis_note))
	rows.append(_stat_row("shield", "护盾上限", "flat", base, final_stats, 0.0, aegis_note))
	var defense_row: Dictionary = _stat_row("defense", "防御", "flat", base, final_stats, 0.0, "")
	var coefficient: float = float(limits.get("defense_coefficient", 0.0))
	var reduction_cap: float = float(limits.get("maximum_damage_reduction", 0.0))
	var defense: float = maxf(0.0, float(defense_row.final))
	if coefficient > 0.0:
		var reduction: float = defense / (coefficient + defense) if defense > 0.0 else 0.0
		var shown: float = minf(reduction, reduction_cap) if reduction_cap > 0.0 else reduction
		defense_row["cap_label"] = "减伤 " + _stat_percent(shown)
		defense_row["tooltip"] = "防御 %s · 实际减伤 %s%s" % [_stat_number(defense), _stat_percent(shown), ("（综合减伤上限 %s）" % _stat_percent(reduction_cap)) if reduction_cap > 0.0 else ""]
	rows.append(defense_row)
	rows.append(_stat_row("crit_rate", "暴击率", "percent", base, final_stats, 1.0, ""))
	rows.append(_stat_row("crit_multiplier", "暴击伤害", "multiplier", base, final_stats, 0.0, ""))
	rows.append(_stat_row("cdr", "冷却缩减", "percent", base, final_stats, float(limits.get("cooldown_reduction", 0.0)), ""))
	rows.append(_stat_row("speed", "战斗移速", "percent", base, final_stats, float(limits.get("move_speed_cap", 0.0)), ""))
	return rows

func _stat_row(key: String, label: String, unit: String, base: Dictionary, final_stats: Dictionary, cap: float, note: String) -> Dictionary:
	var base_value: float = float(base.get(key, 0.0))
	var final_value: float = float(final_stats.get(key, base_value))
	var at_cap: bool = cap > 0.0 and final_value >= cap - 0.0001
	return {
		"key": key, "label": label, "unit": unit,
		"base": base_value, "bonus": final_value - base_value, "final": final_value,
		"cap": cap, "at_cap": at_cap, "note": note,
		"cap_label": ("已达上限" if at_cap else "上限 " + _stat_percent(cap)) if cap > 0.0 else "",
		"tooltip": "",
	}

func _stat_display_limits() -> Dictionary:
	if not _display_limits.is_empty(): return _display_limits
	var rules: Dictionary = {}
	var read: Dictionary = _read_json("res://data/generic_artifacts_v1.json")
	if bool(read.get("ok", false)) and read.get("data", {}) is Dictionary:
		rules = read.data.get("rules", {})
	var limits: Dictionary = _base.get("limits", {})
	_display_limits = {
		"defense_coefficient": float(rules.get("defense_coefficient", 0.0)),
		"maximum_damage_reduction": float(rules.get("maximum_damage_reduction", 0.0)),
		"move_speed_cap": float(rules.get("combat_move_speed_bonus_cap", 0.0)),
		"cooldown_reduction": float(limits.get("cooldown_reduction", 0.0)),
	}
	return _display_limits

static func _stat_number(value: float) -> String:
	return str(int(roundf(value))) if is_equal_approx(value, roundf(value)) else String.num(value, 1)

static func _stat_percent(value: float) -> String:
	var percent: float = value * 100.0
	return (_stat_number(percent) + "%")

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
		"stat_breakdown": get_stat_breakdown(),
		"meta_version": _meta.version,
		"preview_only": preview_only,
		"gem_slots": _state.gem_state.slots.duplicate(),
		"gem_bonuses": gems.totals(_state.gem_state),
		"gem_core": gems.first_effect(_state.gem_state),
		"gem_cores": gems.active_effects(_state.gem_state),
		"gem_effects": gems.active_effects(_state.gem_state).size(),
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
	var essence_earned: int = 0
	if gems.is_modern(candidate.gem_state):
		candidate.gem_state.cumulative_cleared += rooms.size()
		for milestone in gems.rules.milestone_essence:
			if int(candidate.gem_state.cumulative_cleared)>=int(milestone.cleared) and int(milestone.cleared) not in candidate.gem_state.milestone_claimed:
				candidate.gem_state.milestone_claimed.append(int(milestone.cleared))
				essence_earned += int(milestone.essence)
		candidate.gem_state.essence += essence_earned
	candidate.settlement_serial += 1
	candidate.last_settlement = {
		"run_id": run_id, "run_serial": int(_state.run_serial),
		"cleared_rooms": rooms, "dust_earned": dust_earned, "essence_earned": essence_earned,
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
	return {
		"version": SAVE_VERSION,
		"dust": int(_meta.currency.initial),
		"levels": levels,
		"equipped": {"catalyst": ""},
		"free_claimed": {"catalyst": false},
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
	return kind == "catalyst"

func _items(kind: String) -> Dictionary:
	return _meta.catalysts if kind == "catalyst" else {}

func _fail(message: String, incompatible_version: String = "") -> Dictionary:
	error = message
	if incompatible_version.is_empty():
		return {"ok": false, "error": message}
	incompatible_save_version = incompatible_version
	return {"ok": false, "error": message, "incompatible_version": incompatible_version}

func _save_version_rank(value: String) -> int:
	if not value.begins_with(SAVE_VERSION_TAG):
		return -1
	var suffix: String = value.trim_prefix(SAVE_VERSION_TAG)
	return int(suffix) if suffix.is_valid_int() else -1

## Moves a save written by a newer build aside so this build can start a valid
## account. The original bytes are kept verbatim; nothing is overwritten.
func quarantine_incompatible_save() -> Dictionary:
	if incompatible_save_version.is_empty():
		return {"ok": false, "error": "当前没有待隔离的更新版本存档。"}
	if not FileAccess.file_exists(save_path):
		return {"ok": false, "error": "存档文件已不存在，无需隔离。"}
	var absolute: String = ProjectSettings.globalize_path(save_path)
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace("-", "").replace(":", "").replace(" ", "-")
	var target: String = "%s.%s.bak-%s" % [absolute, incompatible_save_version, stamp]
	if DirAccess.rename_absolute(absolute, target) != OK:
		return {"ok": false, "error": "无法隔离更新版本存档，进度未覆盖。"}
	var version: String = incompatible_save_version
	incompatible_save_version = ""
	return {"ok": true, "error": "", "path": target, "version": version}

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
	for source in _school_sources.values():
		spells.merge(source.spells.duplicate(true), true)
	return spells

func _catalyst_id_for_school(school: String) -> String:
	for item_id in _meta.catalysts:
		if str(_meta.catalysts[item_id].get("school", "")) == school:
			return str(item_id)
	return ""

func _legacy_catalyst_cost(level: int) -> int:
	var prices: Dictionary = _meta.legacy_catalyst_refund_costs
	var cost = 0
	if level >= 1:
		cost += int(prices.unlock_cost)
	for current in range(1, level):
		cost += int(prices.upgrade_cost_by_current_level.get(str(current), 0))
	return cost

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
	var legacy_prices: Variant = _meta.get("legacy_catalyst_refund_costs")
	if not legacy_prices is Dictionary or not _is_integer(legacy_prices.get("unlock_cost")) or not legacy_prices.get("upgrade_cost_by_current_level") is Dictionary: return "旧触媒退款价格无效。"
	for current in range(1, int(progression.max_level)):
		if not _is_integer(legacy_prices.upgrade_cost_by_current_level.get(str(current))): return "旧触媒退款升级价格无效。"
	if _meta.catalysts.is_empty():
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
		if item.related_spells.size() != 10:
			return "触媒需要完整十术：" + item_id
		var seen_spells: Dictionary = {}
		for spell_id in item.related_spells:
			if not spell_id is String or seen_spells.has(spell_id): return "触媒关联法术重复或无效：" + str(item_id)
			seen_spells[spell_id] = true
			if not spells.has(spell_id) or not spells[spell_id].get("name") is String:
				return "触媒关联法术不存在：" + str(spell_id)
			if str(spells[spell_id].get("school", "")) != school:
				return "触媒关联法术学派不一致：" + str(spell_id)
			if not bool(spells[spell_id].get("active", true)):
				return "触媒关联法术未启用：" + str(spell_id)
		for spell_id in spells:
			if str(spells[spell_id].get("school", "")) == school and bool(spells[spell_id].get("active", true)) and str(spell_id) != "F04" and not seen_spells.has(spell_id):
				return "触媒遗漏本系法术：" + str(spell_id)
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
	if candidate.levels.size() != _meta.catalysts.size():
		return "物品等级数量不匹配。"
	if candidate.equipped.size() != 1 or candidate.free_claimed.size() != 1:
		return "装备或免费领取状态数量不匹配。"
	for kind in ["catalyst"]:
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
	var gem_error: String = gems.validate(candidate.get("gem_state"))
	if not gem_error.is_empty(): return gem_error
	if not settlement.is_empty() and settlement.has("essence_earned"):
		if not _is_integer(settlement.essence_earned): return "最近结算精粹无效。"
		var expected_essence: int = 0
		var after: int = int(candidate.gem_state.get("cumulative_cleared",0))
		var before: int = after-settlement.cleared_rooms.size()
		for milestone in gems.rules.milestone_essence:
			if before<int(milestone.cleared) and after>=int(milestone.cleared): expected_essence += int(milestone.essence)
		if int(settlement.essence_earned)!=expected_essence: return "最近结算精粹与里程凭证不匹配。"
	return ""


func _load_formal_school_sources() -> String:
	_school_sources.clear()
	_sampling.clear()
	var paths: Variant = _meta.get("formal_school_parameters")
	if not paths is Dictionary or paths.size() != 4: return "缺少正式四系法术引用。"
	var known: Dictionary = _base.get("spells", {}).duplicate(true)
	known.merge(_ice_base.get("spells", {}), true)
	for school in ["lightning", "wind", "earth", "spirit"]:
		if not paths.get(school) is String or str(paths[school]).is_empty(): return "缺少法术引用：" + school
		var path: String = str(paths[school])
		if not path.begins_with("res://"): path = META_PATH.get_base_dir().path_join(path)
		var loaded: Dictionary = _read_json(path)
		if not loaded.ok: return str(loaded.error)
		if not loaded.data.get("spells") is Dictionary or loaded.data.spells.size() != 10: return "正式法术引用无效：" + school
		for id in loaded.data.spells:
			if known.has(id) or str(loaded.data.spells[id].get("school", "")) != school: return "正式法术ID重复或学派错误：" + str(id)
			known[id] = true
		_school_sources[school] = loaded.data.duplicate(true)
	var sampling_path: Variant = _meta.get("spell_sampling_parameters")
	if not sampling_path is String or str(sampling_path).is_empty(): return "缺少六系抽取参数引用。"
	var sampling_read: Dictionary = _read_json(str(sampling_path))
	if not sampling_read.ok: return str(sampling_read.error)
	_sampling = sampling_read.data.duplicate(true)
	var sampling_validation: Dictionary = SpellSampling.new().configure(_sampling)
	if not sampling_validation.ok: return str(sampling_validation.error)
	if not _sampling.get("version") is String or not _sampling.get("catalyst_affinity_by_level") is Array or _sampling.catalyst_affinity_by_level.size() != int(_meta.progression.max_level): return "六系触媒倾向等级数量无效。"
	var previous: float = -1.0
	for affinity in _sampling.catalyst_affinity_by_level:
		if not (affinity is int or affinity is float) or not is_finite(float(affinity)) or float(affinity) < 0.0 or float(affinity) >= 1.0 or float(affinity) <= previous: return "六系触媒倾向必须逐级提高且小于100%。"
		previous = float(affinity)
	return ""
