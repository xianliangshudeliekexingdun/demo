extends SceneTree
## Actual account transactions and Route fixtures. No copied combat simulator.
const Meta = preload("res://scripts/core/meta_progression.gd")
const Gems = preload("res://scripts/core/magic_gems.gd")
const OUT = "res://build/qa/magic-gems-v2-20261020/"
const SAVE = "user://tests/meta_progression/magic_gems.json"
var checks: int = 0
var failures: Array = []
var groups: Array = []
var cleanup: Array = []

class Fixture extends "res://scripts/core/courtyard_route_run.gd":
	var damage_log: Array = []
	func _reserve_batch(): pass
	func _update_spawn(_dt: float): pass
	func _update_enemies(dt: float): advance_ice_control(dt)
	func _check_clear(): pass
	func damage_enemy(actor: Dictionary, amount: float, source: String = ""):
		var before: float = float(actor.health)
		super.damage_enemy(actor, amount, source)
		damage_log.append({"source": source, "id": actor.id, "planned": amount, "actual": before-maxf(0.0, float(actor.health))})

func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures.append(label)
		push_error("Magic gems: " + label)
func near(a: float, b: float) -> bool: return absf(a-b) < 0.0001
func group(label: String, callable: Callable):
	var before: int = checks
	var old_fail: int = failures.size()
	callable.call()
	groups.append({"name": label, "checks": checks-before, "failures": failures.size()-old_fail})
func store_fixture(path: String, data: Dictionary):
	check(path.begins_with(Meta.TEST_SAVE_ROOT), "fixture path isolated")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(data))
	if path not in cleanup: cleanup.append(path)
func account(path: String = SAVE):
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var m = Meta.new(path)
	check(m.load_state().ok, "isolated account loads")
	cleanup.append(path)
	return m
func actor(id: int, pos: Vector2 = Vector2.ZERO, hp: float = 100000.0) -> Dictionary:
	return {"id": id, "type": "M01", "type_id": "M01", "pos": pos, "previous": pos,
		"health": hp, "max_health": hp, "radius": 0.3, "phase": "chase", "push_resistance": 0.0}
func fresh(core: String = "", count: int = 1):
	var b = Fixture.new()
	var snapshot: Dictionary = {"gem_core": core}
	if core == "aegis": snapshot.player = {"health": 195.0, "shield": 362.5}
	check(b.configure(snapshot, 20261019).ok and b.choose_initial("F01"), "real route configured " + core)
	b._spawn_done = true
	b.spawn_warnings.clear()
	b.spells.clear()
	b.blocks.clear()
	b.player.pos = Vector2.ZERO
	b.player.crit_rate = 0.0
	b.actors.clear()
	for index in count: b.actors.append(actor(index+1, Vector2(index*0.5, 2)))
	return b
func advance(b, seconds: float, direction: Vector2 = Vector2.ZERO):
	for index in roundi(seconds*120.0): b.step(1.0/120.0, direction)
func grant(b, id: String):
	b._artifact_combat._owned.append(id)
	b._artifact_combat.apply_acquisition(b, id)
func context(school: String, cast: int = 1, natural: bool = true) -> Dictionary:
	return {"school": school, "spell_id": "F01" if school == "fire" else "I01", "kind": "bolt" if school == "fire" else "direct", "cast_id": cast, "natural": natural, "damage_scale": 1.0, "field_bonus": 0.0}
func damage(b, source: String) -> float:
	var amount: float = 0.0
	for hit in b.damage_log:
		if str(hit.source) == source: amount += float(hit.actual)
	return amount
func ignite(b, index: int = 0): b._spell_combat.apply_burn(b, b.actors[index], "F01")
func ready(b, index: int = 0): b._spell_combat.ice.status.apply_frost(b, b.actors[index], 3, context("ice"))

func transactions():
	var m = account()
	check(m.get_gems().is_empty() and m.get_state().gem_state.slots.size() == 4, "four empty slots, no invented random gems")
	check(m.claim_starter_gem("MG01").ok and near(m.get_preview_stats().health, 320), "free legacy entitlement preserved")
	check(not m.request_upgrade("gem", "MG01").ok, "paid legacy upgrades closed")
	var initial: Dictionary = m.get_state()
	initial.dust = 500
	store_fixture(SAVE, initial)
	check(m.load_state().ok, "funded fixture loads")
	var ten = m.request_draw_gems(10)
	check(ten.ok and ten.gems.size() == 10 and m.get_state().dust == 450, "ten commits ten instances and exact price")
	check(not m.get_state().gem_state.first_gold, "first ten include gold")
	var after: Dictionary = m.get_state()
	var m2 = account(SAVE + ".singles")
	store_fixture(m2.save_path, initial)
	check(m2.load_state().ok, "same RNG and pity fixture")
	for index in 10: check(m2.request_draw_gems(1).ok, "sequential single commits")
	check(m2.get_state() == after, "ten and ten singles exactly identical including RNG")
	var reload = Meta.new(SAVE)
	check(reload.load_state().ok and reload.get_state() == after, "restart retains all instances and pity")
	check(reload.request_draw_gems(1).gems == m2.request_draw_gems(1).gems, "same next result after restart")
	var id: String = str(ten.gems[0].id)
	check(m.request_equip_gem(1, id).ok and m.request_equip_gem(2, id).ok, "instance moves between slots")
	check(m.get_state().gem_state.slots[1] == "" and m.get_state().gem_state.slots[2] == id, "no duplicate stat source")
	var gold: Dictionary = {}
	for gem in ten.gems:
		if str(gem.rarity) == "gold": gold = gem
	check(not gold.is_empty(), "gold fixture was naturally sampled by production draw")
	check(m.request_equip_gem(3, str(gold.id)).ok and m.gems.core_id(m.get_state().gem_state).is_empty(), "sub-slot gold special inactive")
	check(m.request_equip_gem(0, str(gold.id)).ok and m.gems.core_id(m.get_state().gem_state) == gold.core, "core slot activates one gold effect")
	var run = m.begin_playable_run("route45")
	check(run.ok and run.snapshot.gem_core == gold.core, "real immutable core snapshot")
	var before: Dictionary = m.get_state()
	check(not m.request_draw_gems(1).ok and not m.request_equip_gem(1,id).ok and not m.claim_starter_gem("MG02").ok and m.get_state() == before, "all gem changes locked during run")
	check(m.settle_playable_run(run.run_id, []).ok, "empty real run settles zero")
	var blocked: String = SAVE + ".block"
	FileAccess.open(blocked, FileAccess.WRITE).store_string("block directory")
	cleanup.append(blocked)
	m.save_path = blocked + "/save.json"
	before = m.get_state()
	check(not m.request_draw_gems(10).ok and m.get_state() == before, "failed batch preserves dust instances counters and RNG")
	m.save_path = SAVE
	check(m.request_draw_gems(10).ok, "failed batch retry works")
	var bad: Dictionary = m.get_state()
	bad.gem_state.slots = [id,id,"",""]
	store_fixture(SAVE, bad)
	var bytes: String = FileAccess.get_file_as_string(SAVE)
	check(not Meta.new(SAVE).load_state().ok and FileAccess.get_file_as_string(SAVE) == bytes, "invalid duplicate equipment rejected without overwriting")
	var lib = Gems.new()
	for misses in range(30):
		var expected: float = 0.04 if misses < 20 else (1.0 if misses == 29 else 0.04+(misses-19)*0.08)
		check(near(lib.gold_probability({"gold_misses": misses, "first_gold":false}), expected), "exact soft/hard probability %d" % (misses+1))
	for seed_value in 24:
		var state: Dictionary = lib.fresh()
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_value
		var seen_gold: bool = false
		var gap: int = 0
		for index in 200:
			var gem: Dictionary = lib.sample(state,rng)
			gap = 0 if gem.rarity == "gold" else gap+1
			seen_gold = seen_gold or gem.rarity == "gold"
			check(gap < 30 and int(state.rare_misses) < 10 and (index < 9 or seen_gold), "guarantees under seed %d draw %d" % [seed_value,index])
	for anchor in [[0,0],[9,9],[15,15],[30,45],[45,75],[46,77],[54,93],[60,105]]:
		m = account(SAVE + ".income")
		run = m.begin_playable_run("route45")
		var receipt: Dictionary = m.settle_playable_run(run.run_id,range(1,int(anchor[0])+1))
		check(receipt.ok and receipt.dust_earned == anchor[1], "actual route income %d" % int(anchor[0]))
		check(m.settle_playable_run(run.run_id,range(1,int(anchor[0])+1)).already_settled and m.get_state().dust == anchor[1], "income idempotent")


func workshop():
	var m=account(SAVE+".work")
	var state:Dictionary=m.get_state()
	state.dust=1000
	state.gem_state.essence=200
	store_fixture(m.save_path,state)
	check(m.load_state().ok and m.request_draw_gems(50).ok==false,"only allowed draw counts")
	check(m.request_draw_gems(10).ok,"workshop draws real gold")
	var all:Array=m.get_gems()
	var gold:Dictionary={}
	var disposable:Dictionary={}
	for gem in all:
		if gem.rarity=="gold":gold=gem
		else:disposable=gem
	check(not gold.is_empty() and not disposable.is_empty(),"production draw supplies fixtures")
	var id:String=str(disposable.id)
	check(m.request_equip_gem(1,id).ok and not m.request_salvage_gems([id]).ok,"equipped salvage blocked")
	check(m.request_equip_gem(1,"").ok and m.request_lock_gem(id).ok and not m.request_salvage_gems([id]).ok,"locked salvage blocked")
	check(not m.request_reforge(id,"affix",0).ok and m.request_lock_gem(id).ok,"locked reforge blocked, unlock works")
	var before:Dictionary=m.get_state()
	check(not m.request_salvage_gems([id,"missing"]).ok and m.get_state()==before,"batch prevalidation is atomic")
	check(not m.request_salvage_gems([id,id]).ok and m.get_state()==before,"duplicate salvage rejected")
	var income:int=int(m.gems.rules.workshop.salvage_yields[disposable.rarity])
	check(m.request_salvage_gems([id]).ok and int(m.get_state().gem_state.essence)==int(before.gem_state.essence)+income,"quality exact essence yield")
	check(m.get_state().gem_state.draws==before.gem_state.draws and m.get_state().gem_state.gold_misses==before.gem_state.gold_misses and m.get_state().dust==before.dust,"salvage changes neither dust nor pity")
	check(m.get_state().gem_state.serial==before.gem_state.serial and int(m.get_state().gem_state.salvaged)==1,"monotonic identities survive salvage")
	check(not m.request_salvage_gems([id]).ok,"double salvage gives no reward")
	id=str(gold.id)
	check(m.request_equip_gem(0,id).ok,"equipped core can reforge")
	before=m.get_state()
	var old:Dictionary=m.gems.find(before.gem_state,id)
	check(m.request_reforge(id,"affix",1).ok,"selected line generates candidate")
	var pending:Dictionary=m.get_state().gem_state.pending_reforge
	check(int(pending.cost)==3 and int(m.get_state().gem_state.essence)==int(before.gem_state.essence)-3 and m.gems.find(m.get_state().gem_state,id)==old,"cost saved before adoption, old gem unchanged")
	var reload=Meta.new(m.save_path)
	check(reload.load_state().ok and reload.get_state()==m.get_state(),"candidate persists exactly across restart")
	var held:Dictionary=reload.get_state()
	check(not reload.request_draw_gems(1).ok and not reload.request_equip_gem(1,id).ok and not reload.request_reforge(id,"core").ok and not reload.claim_starter_gem("MG01").ok and reload.get_state()==held,"pending candidate blocks unrelated gem mutations")
	check(not reload.resolve_reforge(int(pending.token)+1,true).ok and reload.get_state()==held,"stale candidate token rejected")
	check(reload.resolve_reforge(int(pending.token),false).ok and reload.gems.find(reload.get_state().gem_state,id)==old,"keep old does not refund committed cost")
	check(not reload.resolve_reforge(int(pending.token),true).ok,"candidate cannot resolve twice")
	check(reload.request_reforge(id,"core").ok,"core reforge works")
	pending=reload.get_state().gem_state.pending_reforge
	check(pending.candidate!=old.core and reload.gems.rules.cores.has(pending.candidate),"current core excluded")
	var kept_rng:String=reload.get_state().gem_state.rng_state
	check(reload.resolve_reforge(int(pending.token),true).ok,"adopt candidate")
	var changed:Dictionary=reload.gems.find(reload.get_state().gem_state,id)
	check(changed.core==pending.candidate and changed.affixes==old.affixes and reload.get_state().gem_state.slots[0]==id,"core change preserves three lines and slot")
	check(reload.get_state().gem_state.rng_state==kept_rng,"adoption consumes no further random result")
	var rng=RandomNumberGenerator.new()
	rng.seed=90
	var tiers_seen:Dictionary={}
	for index in 200:
		var candidate:Dictionary=reload.gems.roll_affix(old,1,rng)
		check(candidate!=old.affixes[1] and candidate.stat not in [old.affixes[0].stat,old.affixes[2].stat],"ordinary reforge never duplicates kept lines or exact old result")
		tiers_seen[int(candidate.tier)]=true
	check(tiers_seen.size()==3,"all three tiers reachable")
	for tier in 3:
		check(reload.gems.rules.tier_weights[tier]>0,"tier reachable regardless of quality")
	var blocked:String=SAVE+".work.block"
	FileAccess.open(blocked,FileAccess.WRITE).store_string("block")
	cleanup.append(blocked)
	reload.save_path=blocked+"/save"
	before=reload.get_state()
	check(not reload.request_reforge(id,"affix",0).ok and reload.get_state()==before,"failed reforge saves no fee candidate or RNG")
	reload.save_path=m.save_path
	check(reload.request_reforge(id,"affix",0).ok,"failed reforge retry")
	pending=reload.get_state().gem_state.pending_reforge
	var old_lines:Array=changed.affixes.duplicate(true)
	check(reload.resolve_reforge(int(pending.token),true).ok,"adopt ordinary candidate")
	changed=reload.gems.find(reload.get_state().gem_state,id)
	check(changed.affixes[0]==pending.candidate and changed.affixes[1]==old_lines[1] and changed.affixes[2]==old_lines[2],"only selected line changes")
	check(Meta.new(m.save_path).load_state().ok,"salvaged and reforged save validates after restart")

func migration():
	var m=account(SAVE+".migration")
	var state:Dictionary=m.get_state()
	state.version="meta-progression-3"
	state.dust=123
	var old_rules:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://build/qa/magic-gems-v2-20261020/before/data/magic_gems_v1.json"))
	var gs:Dictionary=state.gem_state
	for key in ["essence","salvaged","work_serial","pending_reforge"]:gs.erase(key)
	var index:int=0
	for old_core in old_rules.cores:
		index+=1
		var lines:Array=[]
		for stat in ["attack","health","cdr"]:lines.append({"stat":stat,"value":old_rules.affixes[stat].gold})
		gs.inventory.append({"id":"gem-%d"%index,"serial":index,"rarity":"gold","affixes":lines,"core":old_core})
	gs.serial=index
	gs.draws=index
	gs.first_gold=false
	gs.slots=["gem-1","gem-2","gem-3","gem-4"]
	store_fixture(m.save_path,state)
	var bytes:String=FileAccess.get_file_as_string(m.save_path)
	check(m.load_state().ok and m.get_state().version==Meta.SAVE_VERSION,"v3 fixed instances migrate to v4")
	check(m.get_state().dust==123 and m.get_gems().size()==8 and m.get_state().gem_state.slots==gs.slots,"migration keeps account dust IDs and slots")
	for gem in m.get_gems():
		check(m.gems.rules.cores.has(gem.core) and not old_rules.cores.has(gem.core),"old core directly becomes new core")
		for line in gem.affixes:check(line.tier==3,"v3 old gold attributes retain exact values as tier III")
	check(FileAccess.get_file_as_string(m.save_path)==bytes,"read migration does not overwrite file until commit")
	var aegis_id:String=""
	for gem in m.get_gems():
		if gem.core=="aegis":aegis_id=str(gem.id)
	check(m.request_equip_gem(0,aegis_id).ok,"actual migrated aegis equips")
	var totals:Dictionary=m.gems.totals(m.get_state().gem_state)
	var raw_health:float=float(m.get_catalog().player.health)+float(totals.health)
	var raw_shield:float=float(m.get_catalog().player.shield)+float(totals.shield)
	var preview:Dictionary=m.get_preview_stats()
	check(near(preview.health,raw_health*0.65) and near(preview.shield,raw_shield+raw_health*0.35*2.5),"real equipped ordinary lines enter cap conversion once")
	var account_run:Dictionary=m.begin_run()
	var route=Fixture.new()
	check(account_run.ok and route.configure(account_run.snapshot,12).ok,"real prepared aegis snapshot configures route")
	check(near(route.player.max_health,preview.health) and near(route.player.max_shield,preview.shield) and near(route._gem_combat.raw_health,raw_health),"account preview and battle caps match without double conversion")
	check(m.end_run().ok,"preview run ends without income")
	check(m.request_lock_gem("gem-1").ok,"first new transaction writes new schema")
	var reload=Meta.new(m.save_path)
	check(reload.load_state().ok and reload.get_state()==m.get_state(),"v4 migration only once")
	var bad:Dictionary=state.duplicate(true)
	bad.gem_state.inventory[0].core="unknown"
	store_fixture(m.save_path,bad)
	bytes=FileAccess.get_file_as_string(m.save_path)
	check(not Meta.new(m.save_path).load_state().ok and FileAccess.get_file_as_string(m.save_path)==bytes,"invalid old core rejected with file preserved")

func sacrifice_and_aegis():
	var b=fresh("sacrifice")
	advance(b,30.0)
	check(near(b.player.health,165.0) and near(b.player.shield,100.0) and near(b.damage_taken,0),"sacrifice drains health only without hurt side effects")
	b.resolve_spell_hit(b.actors[0],1.0,context("fire"))
	check(near(damage(b,"F01"),145.0),"missing life is independent multiplier")
	advance(b,40.0)
	check(near(b.player.health,30.0),"self drain stops at ten percent")
	b.set_paused(true)
	advance(b,10.0)
	check(near(b.player.health,30.0) and near(b._gem_combat.clock,70.0),"pause freezes drain and core clock")
	b.set_paused(false)
	b.player.health=15.0
	b.resolve_spell_hit(b.actors[0],1.0,context("fire",2))
	check(near(damage(b,"F01"),340.0),"enemy-caused subfloor health can exceed ninety percent damage bonus")
	b.player.shield=0.0
	b.damage_player(100000)
	check(b.phase=="dead","sacrifice does not prevent lethal enemy damage")
	b=fresh("aegis")
	check(near(b.player.max_health,195.0) and near(b.player.max_shield,362.5),"life converts once to larger shield pool")
	b.player.health=97.5
	b.player.shield=181.25
	grant(b,"GT03")
	check(near(b.player.health/b.player.max_health,0.5) and near(b.player.shield/b.player.max_shield,0.5),"permanent cap modifiers preserve resource fractions")
	check(near(b.player.max_health,b._gem_combat.raw_health*0.65) and near(b.player.max_shield,b._gem_combat.raw_shield+b._gem_combat.raw_health*0.35*2.5),"post-contract caps convert exactly once")
	grant(b,"GT01")
	var previous:float=float(b.player.health)
	b._artifact_combat._generic._restore_health(b,8.0,"GT04")
	check(near(b.player.health,previous) and near(b._artifact_combat.state_snapshot().generic.charge,40.0),"combat healing becomes actual shield and GT01 charge once")
	b.player.shield=b.player.max_shield
	b._artifact_combat._generic._restore_health(b,8.0,"GT04")
	check(near(b._artifact_combat.state_snapshot().generic.charge,40.0),"full shield no fake actual restoration")
	b._artifact_combat._generic._restore_health(b,3.0,"GU09")
	check(near(b.player.health,previous+3.0),"clear healing still heals life")

func inferno():
	var b=fresh("inferno")
	ignite(b)
	ignite(b)
	check(b._spell_combat.fire_status.burns[1].layers==1,"same instant cannot add layers")
	for index in 5:
		advance(b,0.4)
		ignite(b)
	check(b._spell_combat.fire_status.burns[1].layers==6,"six layers after five legal gains")
	var fire=b._spell_combat.fire_status
	var expected:float=fire.future_coefficient(b,b.actors[0])*100.0
	var before:float=damage(b,"burning")
	advance(b,4.0)
	check(near(damage(b,"burning")-before,expected),"fuel projection includes actual future decay and terminal tick")
	check(not fire.has_burn(b,b.actors[0]),"shared burn expires")
	b=fresh("inferno")
	for index in 6:
		ignite(b)
		if index<5:advance(b,0.4)
	fire=b._spell_combat.fire_status
	expected=fire.future_coefficient(b,b.actors[0])*100.0*1.5
	before=damage(b,"burning")
	check(near(fire.detonate_burn(b,b.actors[0],1.5,true,7),expected) and not fire.has_burn(b,b.actors[0]),"detonation consumes only actual projected fuel")
	advance(b,4.0)
	check(near(damage(b,"burning"),before),"consumed burn produces no later ticks")
	b=fresh("inferno")
	var bomb: Dictionary = b._new_spell("F07")
	bomb.level = 3
	b.spells.append(bomb)
	var tier: Dictionary = b.get_spell_stats(bomb).level
	ignite(b)
	var request: Dictionary = {"detonate":true,"detonation_multiplier":tier.detonation_multiplier,"natural":true,"cast_id":8,"spell_id":"F07","kind":"bomb","school":"fire","growth_level":tier,"damage_scale":1.0,"field_bonus":0.0}
	check(b._spell_combat._hit(b,b.actors[0],1.0,request)>0,"level-three bomb qualified natural detonation")
	advance(b,0.5)
	check(b._spell_combat.fire_status.burns.get(1,{}).get("layers",0)==1,"level-three bomb returns one fresh inferno layer")
	check(b._spell_combat.fire_status.reignite_pending.is_empty(),"no recursive detonation")

func reactor_and_coffin():
	var b=fresh("reactor",6)
	ignite(b)
	ready(b)
	b.gem_after_spell_status(b.actors[0],context("ice"))
	check(near(damage(b,"gem_reactor"),1768.0),"reaction consumes eight burn ticks, main and four bounded neighbors")
	check(not b._spell_combat.has_burn(b,b.actors[0]) and b._spell_combat.ice.status.capture_ready(1).is_empty(),"reaction consumes both states once")
	ignite(b,1)
	ready(b,1)
	b.gem_after_spell_status(b.actors[1],context("fire",2))
	check(near(damage(b,"gem_reactor"),1768.0),"shared reaction cooldown")
	advance(b,1.5)
	check(near(damage(b,"gem_reactor"),1768.0),"no automatic proc on expiry")
	b.gem_after_spell_status(b.actors[1],context("ice",3))
	check(damage(b,"gem_reactor")>1768.0,"next legal hit triggers later reaction")
	b=fresh("coffin",6)
	ready(b)
	b.resolve_spell_hit(b.actors[0],1.0,context("fire"))
	check(near(damage(b,"F01"),65.0) and near(b._gem_combat.reserves[1].amount,35.0),"coffin defers thirty five percent of body")
	advance(b,2.5)
	check(near(damage(b,"gem_coffin"),262.5) and b._gem_combat.reserves.is_empty(),"natural expiry releases once to five bounded targets")
	advance(b,1.0)
	check(near(damage(b,"gem_coffin"),262.5),"expired token cannot pay twice")
	b=fresh("coffin",2)
	ready(b)
	b.resolve_spell_hit(b.actors[0],100.0,context("fire"))
	check(near(b._gem_combat.reserves[1].amount,800.0) and near(damage(b,"F01"),9200.0),"stored attack cap returns excess to immediate body")
	var token:int=int(b._spell_combat.ice.status.capture_ready(1).token)
	b._spell_combat.ice.status.consume_ready(b,b.actors[0],token)
	check(near(damage(b,"gem_coffin"),0.0),"legal consumption queues after parent hit")
	advance(b,1.0/120.0)
	check(near(damage(b,"gem_coffin"),2400.0),"consumption releases one reserve next fixed step")
	b=fresh("coffin",2)
	ready(b)
	b.resolve_spell_hit(b.actors[0],1.0,context("fire"))
	b.damage_enemy(b.actors[0],100000.0,"fixture")
	check(near(damage(b,"gem_coffin"),52.5) and b._gem_combat.reserves.is_empty(),"death releases once and excludes dead primary")
	advance(b,3.0)
	check(near(damage(b,"gem_coffin"),52.5),"death and natural expiry never duplicate")
	b=fresh("coffin",2)
	ready(b)
	b.resolve_spell_hit(b.actors[0],1.0,context("fire"))
	var spell:Dictionary=b._new_spell("I07")
	b._spell_combat._cast(b,spell,b._spell_combat.stats_for(spell),b.actors[0],true,1.0)
	check(near(damage(b,"ice_shatter"),200.0) and near(damage(b,"gem_coffin"),0.0),"actual I07 finishes original shatter before coffin release")
	advance(b,1.0/120.0)
	check(near(damage(b,"gem_coffin"),210.0) and b._gem_combat.reserves.is_empty(),"actual I07 adds its base body then consumes one legal token and one stored pool")

func fracture_and_echo():
	var b=fresh("fracture",3)
	b.player.crit_rate=2.0
	b.resolve_spell_hit(b.actors[0],1.0,context("fire"))
	check(near(damage(b,"F01"),100.0) and near(damage(b,"gem_fracture"),0.0),"critical extra damage delayed; overcap crit no supercrit")
	advance(b,0.175)
	check(near(damage(b,"gem_fracture"),0.0),"crystal not early")
	advance(b,0.01)
	check(near(damage(b,"gem_fracture"),80.0),"first crystal strengthened extra")
	advance(b,0.25)
	check(near(damage(b,"gem_fracture"),156.8) and b._gem_combat.pending.is_empty(),"two bounded nonrepeating bounces")
	b=fresh("fracture")
	b.player.crit_rate=1.0
	b.resolve_spell_hit(b.actors[0],1.0,context("fire"))
	advance(b,1.0)
	check(near(damage(b,"gem_fracture"),80.0),"isolated target receives crystal without discarded base")
	b=fresh("echo",2)
	b.player.gem_cdr=0.2
	var spell:Dictionary=b._new_spell("F01")
	b.spells.append(spell)
	b._refresh_reward_spell_parameters()
	check(near(spell.cooldown,1.2),"echo removes global cooldown shortening")
	b.spells.clear()
	var state_before:int=b._rng.state
	b.gem_record_shape({"kind":"area","pos":b.actors[0].pos,"radius":0.5,"block":true},1.0,context("fire"))
	check(b._rng.state==state_before,"record does not draw critical RNG")
	b.actors[0].pos=Vector2(20,20)
	b.actors[1].pos=Vector2(0,2)
	advance(b,0.65)
	check(near(damage(b,"gem_echo"),120.0) and b._spell_combat.fire_status.burns.is_empty(),"echo actual geometry hits replacement entrant without status")
	check(b._rng.state==state_before,"replay does not roll RNG")
	var harmful:Array=["F01","F03","F05","F06","F07","F09","F11","I01","I02","I03","I04","I05","I06","I07","I08"]
	for id in harmful:
		b=fresh("echo",2)
		for target in b.actors:target.push_resistance=1.0
		spell=b._new_spell(id)
		var stats:Dictionary=b._spell_combat.stats_for(spell)
		b._spell_combat._cast(b,spell,stats,b.actors[0],true,1.0)
		advance(b,5.0)
		check(damage(b,"gem_echo")>0.0,"production spell body replays "+id)
	b=fresh("echo")
	ready(b)
	spell=b._new_spell("I07")
	b._spell_combat._cast(b,spell,b._spell_combat.stats_for(spell),b.actors[0],true,1.0)
	advance(b,0.65)
	check(near(damage(b,"gem_echo"),60.0) and near(damage(b,"ice_shatter"),200.0) and b._spell_combat.ice.status.capture_ready(1).is_empty(),"echo repeats I07 base body but never repeats consumed shatter stock")

func stride():
	var b=fresh("stride")
	var spell:Dictionary=b._new_spell("F01")
	spell.cast_remaining=0.1
	spell.remaining=0.2
	b.spells.append(spell)
	advance(b,0.2,Vector2.RIGHT)
	check(near(spell.cast_remaining,0.1) and near(spell.remaining,0.0) and b._gem_combat.distance>0.9,"actual movement holds windup while cooldown advances")
	advance(b,0.2)
	check(b.casts==1 and near(b._gem_combat.distance,0.0),"stop resumes and first completed spell consumes bank")
	b=fresh("stride")
	advance(b,1.0,Vector2.RIGHT)
	advance(b,1.0,Vector2.LEFT)
	check(near(b._gem_combat.distance,10.0),"two seconds of actual travel fully charges")
	var stats:Dictionary=b._spell_combat.stats_for(b._new_spell("F09"))
	var radius:float=float(stats.level.radius)
	var prepared:Dictionary=b._gem_combat.prepare_cast(stats,true)
	check(near(prepared.body_scale,2.5) and near(prepared.stats.level.radius,radius*1.35) and near(b._gem_combat.distance,0.0),"full charge strengthens one body and geometry")
	check(near(b._gem_combat.prepare_cast(stats,true).body_scale,1.0),"no stored second free cast")
	b._gem_combat.distance=4.0
	b._gem_combat.reset_room()
	check(near(b._gem_combat.distance,0.0),"clear resets charge")
	b.player.previous=b.player.pos
	b._gem_combat.before_spells(b)
	check(not b._gem_combat.moving and near(b._gem_combat.distance,0.0),"wall with no actual displacement cannot charge")

func boundaries():
	var m=account(SAVE+".boundaries")
	var state:Dictionary=m.get_state()
	state.dust=1000
	state.gem_state.essence=1000
	store_fixture(m.save_path,state)
	check(m.load_state().ok,"quality workshop fixture")
	for index in 5:check(m.request_draw_gems(10).ok,"real quality sample batch")
	var qualities:Dictionary={}
	for gem in m.get_gems():qualities[gem.rarity]=gem
	check(qualities.size()==4,"four sampled qualities")
	for rarity in qualities:
		var gem:Dictionary=qualities[rarity]
		var prior:Dictionary=m.get_state()
		check(m.request_reforge(str(gem.id),"affix",0).ok,"ordinary quality reforge "+rarity)
		var pending:Dictionary=m.get_state().gem_state.pending_reforge
		check(int(pending.cost)==int(m.gems.rules.workshop.affix_costs[rarity]),"exact quality fee "+rarity)
		check(m.resolve_reforge(int(pending.token),true).ok,"quality outcome adoption "+rarity)
		var current:Dictionary=m.gems.find(m.get_state().gem_state,str(gem.id))
		check(current.affixes.size()==int(m.gems.rules.affix_counts[rarity]),"reforge never changes quantity or quality "+rarity)
		prior=m.get_state()
		var gain:int=int(m.gems.rules.workshop.salvage_yields[rarity])
		check(m.request_salvage_gems([str(gem.id)]).ok and int(m.get_state().gem_state.essence)==int(prior.gem_state.essence)+gain,"exact salvage yield "+rarity)
	var gold:Dictionary={}
	for gem in m.get_gems():
		if gem.rarity=="gold":gold=gem
	check(m.request_equip_gem(0,str(gold.id)).ok and m.request_reforge(str(gold.id),"core").ok,"pending run fixture")
	var pending:Dictionary=m.get_state().gem_state.pending_reforge
	var run_result:Dictionary=m.begin_playable_run("route45")
	state=m.get_state()
	check(run_result.ok and run_result.snapshot.gem_core==gold.core,"pending candidate does not enter run snapshot")
	check(not m.resolve_reforge(int(pending.token),true).ok and not m.request_lock_gem(str(gold.id)).ok and not m.request_salvage_gems([str(gold.id)]).ok and m.get_state()==state,"run locks all workshop writes")
	check(m.settle_playable_run(run_result.run_id,[]).ok and m.resolve_reforge(int(pending.token),false).ok,"pending choice resumes after run")
	var b=fresh("echo")
	b.player.gem_cdr=2.0
	b.gem_record_shape({"kind":"area","pos":b.actors[0].pos,"radius":1.0},1.0,context("fire"))
	b.phase="pickup"
	advance(b,2.0)
	check(near(b._gem_combat.clock,0.0) and near(damage(b,"gem_echo"),0.0),"safe-phase route time cannot advance core queue")
	b.phase="combat"
	advance(b,0.65)
	check(near(damage(b,"gem_echo"),240.0),"echo conversion honors existing sixty percent cap")
	b=fresh("coffin")
	ready(b)
	ignite(b)
	advance(b,0.5)
	check(b._gem_combat.reserves.is_empty(),"status damage cannot feed coffin")
	b=fresh("echo")
	b.gem_record_shape({"kind":"area","pos":b.actors[0].pos,"radius":1.0},1.0,context("fire",1,false))
	check(b._gem_combat.echo.pending.is_empty(),"additional P04-style casts cannot create echo")
	b._gem_combat.echo.record(b,{"kind":"area","pos":b.actors[0].pos,"radius":1.0},1.0,context("fire"))
	b._stop_combat()
	check(b._gem_combat.echo.pending.is_empty(),"room end clears delayed geometry")

func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	group("account_draw_equipment_income",transactions)
	group("workshop_transactions",workshop)
	group("v3_direct_core_migration",migration)
	group("sacrifice_aegis",sacrifice_and_aegis)
	group("inferno",inferno)
	group("reactor_coffin",reactor_and_coffin)
	group("fracture_echo",fracture_and_echo)
	group("stride",stride)
	group("quality_and_phase_boundaries",boundaries)
	var legacy=preload("res://tests/meta_progression_tests.gd").new()
	check(legacy.run()==0,"existing account catalyst and settlement regression")
	checks+=legacy.checks
	for path in cleanup:
		for suffix in ["",".tmp"]:
			if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	FileAccess.open(OUT+"rules.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"details":failures,"groups":groups,"scope":"Production Godot account transactions, fixed-seed draws and explicit combat fixtures. No natural acquisition or final balance claim."},"\t"))
	print("MAGIC GEMS V2: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
