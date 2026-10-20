extends SceneTree
## Controlled Main/UI request fixtures. Wallet and room are arranged explicitly;
## this checks dispatch/atomicity/account isolation, not natural acquisition.
const Main = preload("res://scripts/main.gd")
const OUT = "res://build/qa/route-shops-20261019/controller.json"
const SAVE = "user://tests/route_shop_controller.json"
var checks: int = 0
var failures: Array = []
var game


func _initialize(): call_deferred("run")


func check(value: bool, label: String):
	checks += 1
	if not value:
		failures.append(label)
		push_error("Shop controller: " + label)


func run():
	DirAccess.make_dir_recursive_absolute("user://tests")
	var production: Dictionary = {}
	for path in ["user://meta_progression_v1.json", "user://display.cfg"]:
		production[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	game = Main.new()
	game.save_path = SAVE
	game.preferences_path = "user://tests/route_shop_controller.cfg"
	game.room_seed = 20261019
	root.add_child(game)
	game.set_process(false)
	check(game.load_error.is_empty(), "actual Main loads with isolated account")
	var account: Dictionary = game.meta.get_state()
	game.start_courtyard_route()
	game._handle_room_request("room_initial", "F01")
	var battle = game.room_run
	# Explicit room/wallet fixture; every counter contact remains physical.
	battle._enter_room(9)
	battle._enter_shop()
	for tick in 2400:
		if battle.phase != "shop": break
		var destination: Vector2 = battle._shop.snapshot().interaction_pos
		var waypoint: Vector2 = battle._chase_position(battle.player.pos, destination, 1.0, battle.player.radius)
		battle.step(1.0 / 120.0, (waypoint - battle.player.pos).normalized())
	game._refresh_room(0.0)
	check(battle.phase == "shopping" and game.room_ui.last_modal == "shopping", "real core contact builds actual Main shop UI")
	var offer: Dictionary = battle.get_snapshot().shop.offers[0]
	var revision: int = battle.room_revision
	battle.gold = 1000
	battle.gold_earned = 1000
	for payload in [null, [], "buy", {}, {"room_revision": float(revision), "id": str(offer.id)}, {"room_revision": revision, "id": 42}, {"room_revision": revision - 1, "id": str(offer.id)}, {"room_revision": revision, "id": "INVALID"}]:
		var before: Dictionary = battle.get_snapshot()
		game._handle_room_request("room_shop_buy", payload)
		check(battle.get_snapshot() == before, "Main rejects malformed/stale/forged purchase request")
	game._handle_room_request("room_pause", "")
	var frozen: Dictionary = battle.get_snapshot()
	game._handle_room_request("room_shop_buy", {"room_revision": revision, "id": str(offer.id)})
	check(battle.get_snapshot() == frozen, "paused Main cannot buy through old shop UI")
	game._handle_room_request("room_resume", "")
	game._handle_room_request("room_shop_buy", {"room_revision": revision, "id": str(offer.id), "price": 0})
	check(battle.gold == 1000 - int(offer.price) and battle.gold_spent == int(offer.price), "Main ignores client price and pays canonical stock price")
	var paid: Dictionary = battle.get_snapshot()
	game._handle_room_request("room_shop_buy", {"room_revision": revision, "id": str(paid.shop.offers[1].id)})
	check(battle.get_snapshot() == paid, "Main dispatch cannot purchase a second item")
	for payload in [null, {}, {"room_revision": float(revision)}, {"room_revision": revision - 1}]:
		var before: Dictionary = battle.get_snapshot()
		game._handle_room_request("room_shop_close", payload)
		check(battle.get_snapshot() == before, "Main rejects malformed/stale close request")
	game._handle_room_request("room_shop_close", {"room_revision": revision})
	check(battle.phase == "shop" and game.room_release_gate and game.room_accumulator == 0.0, "valid close restores movement release gate")
	game._finish_room("abandon")
	check(game.room_settlement.get("ok", false) and game.meta.get_state().dust == account.dust and game.meta.get_state().settlement_serial == account.settlement_serial + 1 and not game.meta.is_in_run(), "shop itself earns no dust; real route token settles once")
	for path in production:
		check((FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent") == production[path], "real account/preferences untouched")
	game.queue_free()
	await process_frame
	for path in [SAVE, SAVE + ".tmp", SAVE + ".bak", "user://tests/route_shop_controller.cfg"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	FileAccess.open(OUT, FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures.size(), "details": failures, "scope": "Explicit Main room/wallet fixture; real counter contact and UI creation; malformed request, canonical price, quota and account isolation checks. Not natural playthrough evidence."}, "\t"))
	print("SHOP CONTROLLER: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
