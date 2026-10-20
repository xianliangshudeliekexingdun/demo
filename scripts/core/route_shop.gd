extends RefCounted
## Route-only shops. Stock and recovery are committed once on real counter
## contact; snapshots, UI reopening and failed purchases never roll or grant.

var config: Dictionary = {}
var _economy: Dictionary = {}
var _recovery: Dictionary = {}
var _visits: Dictionary = {}
var _active_after: int = 0
var _armed: bool = true


func configure(base: Dictionary, economy: Dictionary) -> Dictionary:
	var source = JSON.parse_string(FileAccess.get_file_as_string("res://data/route_shop_runtime.json"))
	if not source is Dictionary or not source.get("geometry") is Dictionary:
		return {"ok": false, "error": "商店空间数据无效。"}
	config = source.duplicate(true)
	_economy = economy.duplicate(true)
	_recovery = base.get("recovery", {}).duplicate(true)
	for key in ["shop_after", "shop_max_health_gain", "shop_fraction"]:
		if not _recovery.has(key):
			return {"ok": false, "error": "商店补给源缺少字段：" + key}
	for rarity in ["blue", "purple", "gold"]:
		var price: float = float(_economy.get("prices", {}).get(rarity, -1))
		if not is_finite(price) or price <= 0.0 or price != floorf(price):
			return {"ok": false, "error": "商店价格必须为正整数。"}
	if float(config.get("interaction_radius", 0.0)) <= 0.0:
		return {"ok": false, "error": "商店互动半径无效。"}
	_visits.clear()
	_active_after = 0
	return {"ok": true, "error": ""}


func nodes(room_total: int) -> Array:
	var result: Array = []
	for room in _recovery.shop_after:
		if int(room) < room_total:
			result.append(int(room))
	return result


func enter(after_room: int) -> void:
	_active_after = after_room
	_armed = true
	if not _visits.has(after_room):
		_visits[after_room] = {"after_room": after_room, "supply_claimed": false,
			"offers": [], "purchased_id": "", "spent": 0,
			"max_health_gain": 0.0, "health_restored": 0.0}


func leave() -> void:
	_active_after = 0


func try_contact(run, from: Vector2, to: Vector2) -> void:
	if run.phase != "shop" or run.paused or _active_after <= 0:
		return
	var center := Vector2(config.interaction_center[0], config.interaction_center[1])
	var radius: float = float(config.interaction_radius) + float(run.player.radius)
	if not _armed:
		if to.distance_to(center) > radius + float(config.rearm_clearance):
			_armed = true
		return
	if run.segment_circle_time(from, to, center, radius) == INF:
		return
	_armed = false
	var visit: Dictionary = _visits[_active_after]
	if not bool(visit.supply_claimed):
		var old_max: float = float(run.player.max_health)
		run._artifact_combat.increase_max_health(run, float(_recovery.shop_max_health_gain))
		visit.max_health_gain = float(run.player.max_health) - old_max
		var restored: float = minf(float(run.player.max_health) * float(_recovery.shop_fraction), maxf(0.0, float(run.player.max_health) - float(run.player.health)))
		run.player.health += restored
		visit.health_restored = restored
		visit.supply_claimed = true
		visit.offers = run._artifact_combat.sample_shop_choices(run, run._rng)
		for offer in visit.offers:
			offer["price"] = int(_economy.prices[str(offer.rarity)])
		run._emit("shop_supply", {"pos": run.player.pos, "after_room": _active_after, "health_restored": restored, "max_health_gain": visit.max_health_gain}, 0.8)
	run.phase = "shopping"
	run._accumulator = 0.0


func buy(run, id: String) -> bool:
	if run.phase != "shopping" or run.paused or float(run.player.health) <= 0.0 or _active_after <= 0:
		return false
	var visit: Dictionary = _visits[_active_after]
	if not bool(visit.supply_claimed) or not str(visit.purchased_id).is_empty():
		return false
	var offered: Dictionary = {}
	for offer in visit.offers:
		if str(offer.id) == id:
			offered = offer
			break
	if offered.is_empty() or int(run.gold) < int(offered.price):
		return false
	if not run._artifact_combat.acquire_shop_item(id, run, visit.offers):
		return false
	run.gold -= int(offered.price)
	run.gold_spent += int(offered.price)
	visit.spent = int(offered.price)
	visit.purchased_id = id
	run._refresh_reward_spell_parameters()
	run._emit("artifact_acquired", {"pos": run.player.pos, "artifact_id": id, "source": "shop", "price": offered.price}, 0.8)
	return true


func close(run) -> bool:
	if run.phase != "shopping" or run.paused or _active_after <= 0:
		return false
	run.phase = "shop"
	run._accumulator = 0.0
	_armed = false
	return true


func snapshot() -> Dictionary:
	if _active_after <= 0:
		return {}
	var result: Dictionary = _visits[_active_after].duplicate(true)
	result["counter_pos"] = Vector2(config.counter_center[0], config.counter_center[1])
	result["interaction_pos"] = Vector2(config.interaction_center[0], config.interaction_center[1])
	result["interaction_radius"] = float(config.interaction_radius)
	result["max_purchases"] = int(_economy.shop.max_purchases_per_visit)
	return result


func summary() -> Array:
	return _visits.values().duplicate(true)
