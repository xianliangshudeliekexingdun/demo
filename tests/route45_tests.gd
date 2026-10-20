extends SceneTree
## Explicit rule fixtures, not a natural playthrough. Legacy filename retained; fixtures now cover the active 60-room route.
const Route = preload("res://scripts/core/courtyard_route_run.gd")
const Catalog = preload("res://scripts/core/courtyard_route_catalog.gd")
const Boundaries = preload("res://tests/courtyard_route_tests.gd")
const OUT := "res://build/qa/route60-20261020/route-rules.json"
var checks := 0
var failures: Array = []
var composition: Array = []
var reward_rows: Array = []
var helper = Boundaries.new()

func _initialize():
	call_deferred("run")

func check(value: bool, message: String):
	checks += 1
	if not value:
		failures.append(message)
		push_error("Route45: "+message)

func run():
	preserved_teaching_and_rewards()
	boss_replaces_placeholder_sources()
	configuration_and_pressure()
	rewards_and_exhaustion()
	late_clocks_and_account()
	checks += helper.checks
	for index in helper.failures: failures.append("shared boundary helper failure "+str(index))
	var output: String=OUT
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with("--qa-out=res://build/qa/") and not str(argument).contains(".."):
			output=str(argument).trim_prefix("--qa-out=").path_join("route45-rules.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"details":failures,"composition":composition,"rewards":reward_rows,"scope":"Explicit rule fixtures for route60, source preservation, stage pressure/caps, cached actual rewards/exhaustion, late clocks and local ledger; not natural gameplay evidence."},"\t"))
	print("ROUTE45 RULES: %d checks; %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func preserved_teaching_and_rewards():
	var prior: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/route15_baseline.json"))
	var route: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/courtyard_route.json"))
	var enemy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/route_enemy_runtime.json"))
	var total := 0
	for room in range(1,16):
		if room <= 3:
			check(route.encounters_by_room[str(room)].packs == prior.encounters[str(room)].packs, "first three preserve exact teaching packs "+str(room))
		for pack in route.encounters_by_room[str(room)].packs:
			for id in pack: total += int(pack[id])
	check(total == 105,"first fifteen use unchanged 104 non-Boss enemies and one Boss")
	check(route.reward_rooms.filter(func(room): return int(room)<15) == prior.spell_rooms,"first fifteen preserve ordinary books and add the Boss book")
	check(route.artifact_reward_rooms.filter(func(room): return int(room)<=15) == prior.treasure_rooms,"first fifteen preserve three treasure chests")
	for key in prior.enemy_runtime:
		if key in ["version","scope","stat_stages","types","stage_rules"]: continue
		check(enemy.get(key) == prior.enemy_runtime[key],"first-fifteen shared enemy behavior preserved: "+str(key))
	for id in prior.enemy_runtime.types:
		check(enemy.types[id] == prior.enemy_runtime.types[id], "legacy enemy definition preserved: " + str(id))
	for index in prior.enemy_runtime.stat_stages.size():
		check(without_damage_growth(enemy.stat_stages[index]) == prior.enemy_runtime.stat_stages[index],"first fifteen preserve health/walk/cadence stage before new damage growth "+str(index))

func without_damage_growth(stage: Dictionary) -> Dictionary:
	var result := stage.duplicate(true)
	for category in ["normal", "elite"]:
		result[category].erase("damage")
		result[category].erase("body_damage")
	return result

func boss_replaces_placeholder_sources():
	var prior: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/route45_baseline.json"))
	var route: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/courtyard_route.json"))
	var enemy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/route_enemy_runtime.json"))
	for room in [15, 30, 45]:
		check(route.encounters_by_room[str(room)].kind == "boss" and route.encounters_by_room[str(room)].packs.size() == 1, "Boss replaces the explicitly approved milestone placeholder "+str(room))
	check(route.reward_rooms.filter(func(room): return int(room)<=45 and int(room)%15!=0) == prior.spell_rooms, "first forty-five ordinary spell nodes preserved")
	check(route.artifact_reward_rooms.filter(func(room): return int(room)<=45) == prior.treasure_rooms, "first forty-five chest nodes preserved")
	check(route.encounter_limits.stages.slice(0,prior.encounter_limits.stages.size()) == prior.encounter_limits.stages, "first forty-five capacity stages preserved")
	for index in prior.difficulty_bands.size():
		check(int(route.difficulty_bands[index].from) == int(prior.difficulty_bands[index].from) and int(route.difficulty_bands[index].to) == int(prior.difficulty_bands[index].to), "fifteen-room stage boundaries preserved")
	check(enemy.stat_stages.slice(0,prior.enemy_runtime.stat_stages.size()).map(without_damage_growth) == prior.enemy_runtime.stat_stages, "first forty-five health/movement/cadence preserved; damage growth added separately")

func configuration_and_pressure():
	var catalog = Catalog.new()
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/courtyard_route.json"))
	check(catalog.load_catalog().ok,"catalog validates actual 60-room data")
	check(catalog.get_active_room_count() == 60,"exactly sixty playable rooms")
	var battle = helper.fresh()
	var stages: Array = battle._enemy_combat.get_runtime().stat_stages
	check(int(stages[-1].to) == 60,"combat specs cover sixty rooms")
	var previous_to := 0
	for stage in stages:
		check(int(stage.from) == previous_to+1 and int(stage.to) >= int(stage.from),"enemy stages continuous: "+str(stage.id))
		previous_to = int(stage.to)
	var ranged_by_segment := [0,0,0,0]
	var total_by_segment := [0,0,0,0]
	for room in range(1,61):
		var authored: Dictionary = catalog.get_room(room)
		check(authored.active and authored.room_id == room and authored.kind in ["normal","elite","elite_guard","boss"],"real active type and numbering "+str(room))
		check(authored.terminal == (room==60),"only actual last room terminal "+str(room))
		battle._enter_room(room)
		var snap: Dictionary = battle.get_snapshot()
		var cap: int = int(snap.get("alive_cap",0))
		check(cap > 0,"room exposes actual alive cap "+str(room))
		var limits: Dictionary = catalog.get_encounter_limits(room)
		check(cap == int(limits.alive_cap) and authored.encounter.packs.size() <= int(limits.max_batches),"actual room uses its authored capacity and batch stage "+str(room))
		check(bool(snap.shop_after) == (int(room) in battle._shop.nodes(60)) and str(snap.spike_profile)=="off","actual shops follow configured nodes; spikes remain off "+str(room))
		var types: Dictionary = {}
		var count := 0
		var ranged := 0
		for pack in authored.encounter.packs:
			var pack_total := 0
			for id in pack:
				pack_total += int(pack[id])
				types[id] = int(types.get(id,0))+int(pack[id])
				check(not battle._enemy_combat.type_spec(str(id),room).is_empty(),"every authored enemy has current-room combat spec")
				if str(id) in ["M02","M04","M05","M06","M07","EL02","EL02_GUARD"]: ranged += int(pack[id])
			check(pack_total <= cap,"whole authored pack fits stage cap "+str(room))
			count += pack_total
		var segment := mini(3,(room-1)/15)
		ranged_by_segment[segment] += ranged
		total_by_segment[segment] += count
		composition.append({"room":room,"kind":authored.kind,"cap":cap,"total":count,"ranged":ranged,"types":types,"stat_stage":battle._enemy_combat.type_spec("M02",room).stat_stage_id})
	check(total_by_segment == [105, 196, 267, 365],"all-room audit matches unchanged non-Boss rosters plus four Bosses")
	check(ranged_by_segment[1] > ranged_by_segment[0] and ranged_by_segment[2] > ranged_by_segment[1] and ranged_by_segment[3] > ranged_by_segment[2],"each fifteen-room segment increases actual ranged roster")
	check(total_by_segment[1] > total_by_segment[0] and total_by_segment[2] > total_by_segment[1] and total_by_segment[3] > total_by_segment[2],"each later segment increases actual encounter density")
	for type_id in ["M01","M02","M03","M04","EL01","EL02","EL02_GUARD"]:
		var early: Dictionary = battle._enemy_combat.type_spec(type_id,15)
		var middle: Dictionary = battle._enemy_combat.type_spec(type_id,30)
		var later: Dictionary = battle._enemy_combat.type_spec(type_id,45)
		check(middle.health > early.health and later.health > middle.health,"durability increases in both new difficulties: "+type_id)
		check(middle.move_speed >= early.move_speed and later.move_speed >= middle.move_speed,"chase pressure does not regress: "+type_id)
		check(middle.attack_cycle <= early.attack_cycle and later.attack_cycle <= middle.attack_cycle,"attack cadence does not regress: "+type_id)
		for spec in [middle,later]:
			check(spec.warning == early.warning and spec.radius == early.radius,"later pressure preserves telegraph and footprint: "+type_id)
			check(spec.attack_cycle+0.000001 >= battle._enemy_combat._full_attack_duration(spec),"late attack includes full warning action recovery: "+type_id)
			check(spec.move_speed < battle.player.move_speed,"player can outrun ordinary walking: "+type_id)

func rewards_and_exhaustion():
	var battle = helper.fresh()
	# Broad legal loadout is an explicit eligibility fixture, acquired naturally
	# only in the separate native pressure/visual runs.
	battle.spells.clear()
	for id in ["F01","F11","F03","F06","F08","F10","F07","F02"]:
		battle.spells.append(battle._new_spell(id))
	check(battle._artifact_reward_rooms.size() == 12,"twelve real treasure chest nodes")
	check(battle._reward_rooms.size() == 52,"fifty-two spell book nodes")
	for room in battle._artifact_reward_rooms:
		battle._enter_room(int(room))
		var gold_available: bool = battle._artifact_combat.eligible_ids(battle).any(func(id): return battle._artifact_combat._items[id].rarity == "gold")
		helper.clear_fixture(battle)
		check(battle.phase == "pickup" and helper.touch_reward(battle),"real late chest contact opens treasure "+str(room))
		if int(room)%15 == 0:
			check(battle.phase == "reward" and helper.choose_growth(battle), "Boss book resolved before chest")
			check(helper.touch_reward(battle) and battle.phase == "artifact", "then contact unlocked Boss gold chest")
		var offer: Array = battle.artifact_choices.duplicate(true)
		var offered_ids: Array = offer.map(func(item): return item.id)
		check(not offer.is_empty() and offer.size() <= 3,"legal reduced-or-full offer "+str(room))
		for item in offer:
			check(offered_ids.count(item.id)==1 and not battle._artifact_combat.has_artifact(str(item.id)),"treasure offer unique and excludes held item")
		if int(room) < 15:
			for item in offer: check(item.rarity != "gold","first fifteen still exclude gold treasure")
		if int(room)%15 == 0:
			for item in offer: check(item.rarity == "gold", "every Boss offer is exclusively gold")
		check(helper.choose_artifact(battle),"actual offered treasure granted "+str(room))
		reward_rows.append({"room":room,"offer":offer.map(func(item): return {"id":item.id,"rarity":item.rarity}),"owned":battle.get_snapshot().artifacts.map(func(item): return item.id)})
	check(battle.get_snapshot().artifacts.size() == 12,"twelve distinct treasure claims persist without spell-slot cost")
	var fallback = helper.fresh()
	fallback._artifact_combat._owned.assign(fallback._artifact_combat._items.keys().filter(func(id):return fallback._artifact_combat._items[id].rarity=="gold" and not bool(fallback._artifact_combat._items[id].get("boss_only", false))))
	fallback._enter_room(45)
	helper.clear_fixture(fallback)
	check(fallback.phase == "pickup" and helper.touch_reward(fallback),"gold-exhausted final chest still opens legal candidates")
	check(helper.choose_growth(fallback) and helper.touch_reward(fallback), "gold-exhausted Boss still resolves its book first")
	check(fallback.artifact_choices.size() == 1 and fallback.artifact_choices[0].id == "BGT45" and fallback.artifact_choices[0].rarity == "gold","empty gold pool has its unique Boss gold seal")
	var maxed = helper.fresh()
	maxed.spells.clear()
	for id in maxed.eligible_reward_ids().slice(0,8):
		var spell: Dictionary = maxed._new_spell(str(id))
		spell.level = int(maxed._base.limits.spell_level)
		maxed._refresh_spell(spell)
		maxed.spells.append(spell)
	for room in [16,29,31,44,46,54,59]:
		maxed._enter_room(room)
		helper.clear_fixture(maxed)
		check(maxed.eligible_reward_ids().size() == 12 and maxed.phase == "pickup" and not maxed.portal.usable,"maxed eight slots retain a physical replacement book "+str(room))
		check(helper.touch_reward(maxed) and maxed.reward_choices.size() == 3 and maxed.can_skip_spell_reward(),"all-new late cards allow an explicit preserve-build choice "+str(room))
		var preserved: Array = maxed.spells.duplicate(true)
		check(maxed.skip_spell_reward(maxed.room_revision) and maxed.phase == "exit" and maxed.portal.usable and maxed.spells == preserved,"explicitly declining new spells preserves maxed build and opens gate "+str(room))
		check(helper.use_portal(maxed),"resolved book still permits real portal contact "+str(room))
	var exhausted = helper.fresh()
	exhausted._artifact_combat._owned.assign(exhausted._artifact_combat._items.keys().filter(func(id): return not bool(exhausted._artifact_combat._items[id].get("boss_only", false))))
	for room in [21,30,45,60]:
		exhausted._enter_room(room)
		helper.clear_fixture(exhausted)
		if int(room)%15 == 0:
			check(helper.touch_reward(exhausted) and helper.choose_growth(exhausted), "exhausted ordinary pool still has Boss book")
			check(helper.touch_reward(exhausted) and helper.choose_artifact(exhausted), "Boss seal preserves gold guarantee on full ordinary collection")
		check(exhausted.artifact_choices.is_empty() and exhausted.phase == "exit" and exhausted.portal.usable,"resolved or exhausted treasure pool opens gate "+str(room))
		check(helper.use_portal(exhausted),"empty treasure pool permits actual exit "+str(room))
	check(exhausted.phase == "complete" and exhausted.room_index == 60,"only final portal completes exhausted route fixture")

func late_clocks_and_account():
	for room in [16,30,31,45,46,54,57,60]:
		var battle = helper.room_fixture(room)
		var start: Dictionary = battle.get_snapshot()
		helper.advance(battle,0.2)
		check(helper.near(battle.time,start.time+0.2) and helper.near(battle.combat_time,start.combat_time+0.2),"late combat advances dual clocks "+str(room))
		helper.clear_fixture(battle)
		if battle.phase == "pickup":
			check(helper.touch_reward(battle),"clock fixture reaches actual late reward")
			var card: Dictionary = battle.get_snapshot()
			helper.advance(battle,0.5,Vector2.RIGHT)
			check(helper.without_elapsed(battle.get_snapshot()) == helper.without_elapsed(card) and helper.near(battle.time,card.time+0.5),"late choice freezes rules and counts total "+str(room))
			check(helper.choose_artifact(battle) if battle.phase=="artifact" else helper.choose_growth(battle),"late clock fixture claims real reward")
			if battle.phase == "pickup":
				check(helper.touch_reward(battle) and helper.choose_artifact(battle), "late Boss clock fixture also resolves gold chest")
		battle.set_paused(true)
		var paused: Dictionary = battle.get_snapshot()
		helper.advance(battle,0.5)
		check(battle.get_snapshot() == paused,"late pause freezes both clocks "+str(room))
		battle.set_paused(false)
		var before: Dictionary = battle.get_snapshot()
		check(helper.use_portal(battle),"late real portal contact "+str(room))
		check(battle.time > before.time and helper.near(battle.combat_time,before.combat_time),"late exit counts only total clock "+str(room))
		check(battle.dust == 0 and not battle.get_summary().account_rewards and battle.get_summary().preview_only,"late route never credits local account "+str(room))
