extends SceneTree
## Explicit shop transaction/contact fixtures; no claim of natural combat.
const Route = preload("res://scripts/core/courtyard_route_run.gd")
const Boundaries = preload("res://tests/courtyard_route_tests.gd")
const OUT = "res://build/qa/route60-20261020/shop-rules.json"
var checks: int = 0
var failures: Array = []
var helper = Boundaries.new()
var budgets: Array = []
var samples: Array = []


func _initialize():
	call_deferred("run")


func check(value: bool, message: String):
	checks += 1
	if not value:
		failures.append(message)
		push_error("Route shop: " + message)


func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func fresh(room: int = 9, school: String = "fire", seed_value: int = 20261019):
	var battle = Route.new()
	check(battle.configure({"route_school": school}, seed_value).ok, "configure actual shop route")
	check(battle.choose_initial("F01" if school == "fire" else "I01"), "select actual starter")
	if room != 1:
		battle._enter_room(room)
	return battle


func walk(battle, destination: Vector2, expected_phase: String) -> bool:
	for tick in 120 * 30:
		if battle.phase != expected_phase or battle.player.pos.distance_to(destination) < 0.025:
			return true
		var waypoint: Vector2 = battle._chase_position(battle.player.pos, destination, 1.0, battle.player.radius)
		battle.step(1.0 / 120.0, (waypoint - battle.player.pos).normalized())
	return false


func contact(battle) -> bool:
	return walk(battle, battle._shop.snapshot().interaction_pos, "shop") and battle.phase == "shopping"


func advance(battle, seconds: float, move: Vector2 = Vector2.ZERO):
	for tick in roundi(seconds * 120.0):
		battle.step(1.0 / 120.0, move)


func run():
	flow_and_receipts()
	recovery_and_contract()
	fixed_stock_and_boundaries()
	income_and_progress()
	check(helper.failures == 0, "shared contact helpers pass")
	var result := {"checks": checks, "failures": failures.size(), "details": failures,
		"budgets": budgets, "samples": samples,
		"scope": "Controlled real-core shop/portal transactions; seeded eligible stock, once-only supply, currency conservation, actual elite income, clocks and stale request checks. Not player balance acceptance."}
	var output := OUT
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--qa-out=res://build/qa/") and not str(arg).contains(".."):
			output = str(arg).trim_prefix("--qa-out=").path_join("shop-rules.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("ROUTE SHOP RULES: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func flow_and_receipts():
	var battle = fresh()
	helper.clear_fixture(battle)
	check(battle.phase == "pickup" and not battle.buy_shop_item("U01", battle.room_revision), "shop cannot bypass room reward")
	check(helper.touch_reward(battle) and helper.choose_growth(battle), "finish actual ninth room book before shop")
	var before: Dictionary = battle.get_snapshot()
	check(walk(battle, battle.portal.pos, "exit") and battle.phase == "shop", "actual ninth portal enters independent shop")
	var entered: Dictionary = battle.get_snapshot()
	check(entered.in_shop and entered.room_index == 9 and entered.room_total == 60 and entered.encounter_kind == "shop", "shop retains battle numbering")
	check(battle.clear_count == before.clear_count and battle.kills == before.kills and battle.gold == before.gold, "shop entry is not a combat clear or free currency")
	check(entered.actors.is_empty() and entered.spawn_warnings.is_empty() and entered.spell_zones.is_empty(), "shop clears combat objects")
	check(battle.player.health == before.player.health and not entered.shop.supply_claimed, "passing through does not claim counter supply")
	check(contact(battle), "walking into actual counter footprint opens shop")
	var opened: Dictionary = battle.get_snapshot()
	check(opened.shop.supply_claimed and opened.shop.offers.size() == 3 and opened.shop.offers[0].rarity == "blue", "first shop grants supply and legal blue guarantee")
	check(battle.spells == before.spells and battle.artifact_claimed_rooms == before.artifact_claimed_rooms, "shop supply preserves spells and free chest ledger")
	var clock: float = battle.time
	var combat_clock: float = battle.combat_time
	var position: Vector2 = battle.player.pos
	var inventory: Array = battle.spells.duplicate(true)
	advance(battle, 0.5, Vector2.RIGHT)
	check(near(battle.time, clock + 0.5) and near(battle.combat_time, combat_clock) and battle.player.pos == position and battle.spells == inventory, "shopping advances only total clock")
	var frozen: Dictionary = battle.get_snapshot()
	battle.set_paused(true)
	advance(battle, 1.0, Vector2.RIGHT)
	check(battle.get_snapshot() == frozen.merged({"paused": true}, true), "pause freezes shop clock and state")
	check(not battle.buy_shop_item(str(opened.shop.offers[0].id), battle.room_revision) and not battle.close_shop(battle.room_revision), "paused shop rejects mutations")
	battle.set_paused(false)
	var id: String = str(opened.shop.offers[0].id)
	var poor: Dictionary = battle.get_snapshot()
	check(not battle.buy_shop_item(id, battle.room_revision) and battle.get_snapshot() == poor, "insufficient funds is atomic")
	# Explicit wallet fixture; natural income is tested independently below.
	battle.gold = 66
	battle.gold_earned = 66
	var revision: int = battle.room_revision
	check(not battle.buy_shop_item("INVALID", revision) and not battle.buy_shop_item(id, revision - 1), "forged SKU and stale room revision rejected")
	var owned: int = battle.get_snapshot().artifacts.size()
	check(battle.buy_shop_item(id, revision), "pay exact authoritative price for offered item")
	check(battle.gold == 6 and battle.gold_spent == 60 and battle.get_snapshot().artifacts.size() == owned + 1, "purchase deducts sixty once and grants exactly one item")
	check(battle.gold_earned == battle.gold + battle.gold_spent and battle.get_snapshot().shop.purchased_id == id, "wallet and shop receipt conserve currency")
	check(not battle.buy_shop_item(id, revision) and not battle.buy_shop_item(str(opened.shop.offers[1].id), revision), "repeat and second-item purchase rejected")
	var stock: Array = battle.get_snapshot().shop.offers
	var state: int = battle._rng.state
	var health: float = battle.player.health
	var maximum: float = battle.player.max_health
	check(battle.close_shop(revision), "close returns to physical shop")
	advance(battle, 0.5)
	check(battle.phase == "shop", "closing while standing at counter does not reopen immediately")
	check(walk(battle, battle._shop.snapshot().interaction_pos + Vector2(0, -2.5), "shop") and contact(battle), "leave and reenter counter to reopen same visit")
	check(battle._rng.state == state and battle.get_snapshot().shop.offers == stock and near(battle.player.health, health) and near(battle.player.max_health, maximum), "reopen preserves stock/RNG and grants no second recovery")
	check(not battle.buy_shop_item(str(stock[1].id), revision), "reopen does not reset purchase quota")
	check(battle.close_shop(revision) and walk(battle, battle.portal.pos, "shop"), "walk from counter to onward portal")
	check(battle.room_index == 10 and battle.phase == "combat" and not battle.get_snapshot().in_shop, "shop exits into actual tenth combat")
	check(not battle.buy_shop_item(id, revision) and not battle.close_shop(revision), "old shop request cannot act after transition")
	check(battle.player.health == health and battle.player.max_health == maximum and battle.spells == inventory, "shop exit preserves health and every spell cooldown")


func recovery_and_contract():
	for contract in [false, true]:
		var battle = fresh()
		if contract:
			battle._artifact_combat._owned.append("GT03")
			battle._artifact_combat.apply_acquisition(battle, "GT03")
		battle.player.health = float(battle.player.max_health) * 0.5
		var health: float = battle.player.health
		var maximum: float = battle.player.max_health
		battle._enter_shop()
		check(contact(battle), "actual shop recovery contact with contract=" + str(contract))
		var factor: float = float(battle._artifact_combat._items.GT03.maximum_health_multiplier) if contract else 1.0
		var gain: float = float(battle._base.recovery.shop_max_health_gain) * factor
		check(near(battle.player.max_health, maximum + gain), "shop flat health remains in contract pool")
		check(near(battle.player.health, health + (maximum + gain) * float(battle._base.recovery.shop_fraction)), "recovery uses new maximum once; health growth itself does not heal")
		check(battle.gold == 0 and battle.gold_spent == 0, "recovery is free with empty wallet")
	var passed = fresh()
	passed._enter_shop()
	var before: Dictionary = passed.get_snapshot()
	check(walk(passed, passed.portal.pos, "shop") and passed.room_index == 10, "central path can bypass counter and continue without spending")
	check(passed.player.max_health == before.player.max_health and passed.player.health == before.player.health and not passed._shop.summary()[0].supply_claimed, "bypassing counter forfeits this shop supply")


func fixed_stock_and_boundaries():
	for school in ["fire", "ice"]:
		for room in [9, 24, 33, 42, 54]:
			for seed_value in range(20261019, 20261031):
				var battle = fresh(room, school, seed_value)
				battle._enter_shop()
				var random_before: int = battle._rng.state
				for repeat in 4:
					battle.get_snapshot()
				check(battle._rng.state == random_before, "shop snapshot never draws stock")
				check(contact(battle), "seeded fire/ice stock opens")
				var shop: Dictionary = battle.get_snapshot().shop
				var ids: Array = []
				var eligible: Array = battle._artifact_combat.eligible_ids(battle)
				for offer in shop.offers:
					check(offer.id in eligible and offer.id not in ids and int(offer.price) == int(battle._economy.prices[offer.rarity]), "stock is unique eligible and correctly priced")
					check(not (room == 9 and offer.rarity == "gold"), "first-stage zero gold weight remains excluded")
					ids.append(offer.id)
				check(ids.size() <= 3 and (room != 9 or shop.offers[0].rarity == "blue"), "shop respects slot limit and first blue guarantee")
				if seed_value == 20261019:
					samples.append({"school": school, "room": room, "offers": shop.offers})
	var empty = fresh()
	empty._artifact_combat._owned.assign(empty._artifact_combat._items.keys())
	empty._enter_shop()
	check(contact(empty) and empty.get_snapshot().shop.offers.is_empty() and empty.get_snapshot().shop.supply_claimed, "exhausted shop still supplies recovery without fake stock")
	check(empty.close_shop(empty.room_revision) and walk(empty, empty.portal.pos, "shop") and empty.room_index == 10, "empty shop cannot soft lock route")
	var fallback = fresh()
	fallback._artifact_combat._owned.assign(fallback._artifact_combat._items.keys().filter(func(id): return fallback._artifact_combat._items[id].rarity == "blue"))
	fallback._enter_shop()
	check(contact(fallback) and fallback.get_snapshot().shop.offers[0].rarity == "purple", "exhausted first-shop blue guarantee uses legal positive highest tier")


func income_and_progress():
	var battle = fresh(1)
	check(battle._shop.nodes(60) == [9,24,33,42,54], "five active nodes derived from approved full route")
	for room in range(1, 61):
		battle._enter_room(room)
		helper.clear_fixture(battle)
		var balance: int = battle.gold
		battle._check_clear()
		check(battle.gold == balance and battle.gold_earned == balance, "room clear income commits once")
		if room in [9, 24, 33, 42, 54]:
			budgets.append({"after_room": room, "without_spending": balance})
	check(budgets.map(func(row): return int(row.without_spending)) == [66,218,330,442,606], "Boss conversion preserves milestone income and all five shop budgets")
	check(battle.gold == 726 and battle.dust == 0 and battle.get_summary().account_rewards == false, "60 actual clears earn 726 local gold and no account currency")
	var preview = fresh(9)
	var nodes: Array = preview.get_snapshot().room_progress
	check(nodes[0].kind == "normal" and nodes[1].kind == "shop" and int(nodes[2].room_id) == 10, "lookahead inserts shop after actual combat node")
	preview._enter_shop()
	nodes = preview.get_snapshot().room_progress
	check(nodes[0].kind == "shop" and nodes[0].state == "current" and int(nodes[1].room_id) == 10, "shop is current independent progress node")
	var terminal = fresh(60)
	check(terminal.get_snapshot().room_progress.map(func(node): return int(node.room_id)) == [58,59,60], "final progress retains last three actual rooms")
