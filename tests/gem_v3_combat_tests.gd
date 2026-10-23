extends RefCounted
## Native bounded fixtures for the approved core redesign. No natural route or rendering.
const OUT = "res://build/qa/gem-v3-implementation-20261022/common-combat/"
var checks: int = 0
var failures: Array = []
var groups: Array = []

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

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("Gem v3 combat: " + label)

func near(a: float, b: float) -> bool: return absf(a-b) < 0.0002
func group(label: String, action: Callable) -> void:
	var before: int = checks
	var old: int = failures.size()
	action.call()
	groups.append({"name": label, "checks": checks-before, "failures": failures.size()-old})

func actor(id: int, pos: Vector2, hp: float = 100000.0) -> Dictionary:
	return {"id": id, "type_id": "M01", "pos": pos, "previous": pos, "health": hp, "max_health": hp, "radius": 0.3, "phase": "chase", "push_resistance": 0.0}

func fresh(core: String = "", count: int = 1):
	var b = Fixture.new()
	var snapshot: Dictionary = {"gem_core": core}
	if core == "aegis": snapshot.player = {"health": 210.0, "shield": 298.0}
	check(b.configure(snapshot, 20261022).ok and b.choose_initial("F01"), "actual route configures " + core)
	b._spawn_done = true
	b.spawn_warnings.clear()
	b.spells.clear()
	b.blocks.clear()
	b.player.pos = Vector2.ZERO
	b.player.crit_rate = 0.0
	b.actors.clear()
	for index in count: b.actors.append(actor(index+1, Vector2(index*0.5, 2)))
	return b

func advance(b, seconds: float) -> void:
	for index in roundi(seconds*120.0): b.step(1.0/120.0, Vector2.ZERO)

func context(school: String = "fire", cast: int = 1, natural: bool = true) -> Dictionary:
	return {"school": school, "spell_id": "F01" if school == "fire" else "I01", "kind": "bolt" if school == "fire" else "direct", "cast_id": cast, "natural": natural, "damage_scale": 1.0, "field_bonus": 0.0}

func damage(b, source: String, id: int = -1) -> float:
	var result: float = 0.0
	for hit in b.damage_log:
		if str(hit.source) == source and (id < 0 or int(hit.id) == id): result += float(hit.actual)
	return result

func ready(b, index: int = 0) -> int:
	b._spell_combat.ice.status.force_ready(b, b.actors[index], 0.0)
	return int(b._spell_combat.ice.status.capture_ready(int(b.actors[index].id)).token)

func fire_cases() -> void:
	var b = fresh("inferno", 3)
	b._spell_combat.apply_burn(b, b.actors[0], "F01")
	advance(b, 2.0)
	check(near(damage(b,"burning"),100.0), "four real unchanged 25-point burn ticks")
	check(near(damage(b,"gem_inferno",1),60.0) and near(damage(b,"gem_inferno",2),21.0) and near(damage(b,"gem_inferno",3),21.0), "four ticks pay 60 primary and two 21 neighbors")
	check(b._gem_combat.embers[1].ticks == 0, "cycle resets tick count before payout")
	b = fresh("inferno")
	b._spell_combat.apply_burn(b,b.actors[0],"F01")
	b.resolve_spell_hit(b.actors[0],1.0,context("fire",7))
	b.resolve_spell_hit(b.actors[0],1.0,context("fire",7))
	check(near(b._gem_combat.embers[1].amount,15.0), "per cast per enemy natural body credit only once")
	var bomb: Dictionary = context("fire",8)
	bomb.spell_id = "F07"
	b.resolve_spell_hit(b.actors[0],1.0,bomb)
	check(near(b._gem_combat.embers[1].amount,15.0), "F07 body excluded from ember credit")
	b.resolve_spell_hit(b.actors[0],1.0,context("fire",9,false))
	check(near(b._gem_combat.embers[1].amount,15.0), "extra release excluded from ember credit")
	advance(b,.5)
	b._spell_combat.fire_status.detonate_burn(b,b.actors[0],1.0,true,10)
	check(b._gem_combat.embers.is_empty(), "consumption discards ember token and count")
	advance(b,3.0)
	check(near(damage(b,"gem_inferno"),0.0), "consumed reserve never receives future ticks")
	b = fresh("inferno")
	b._spell_combat.apply_burn(b,b.actors[0],"F01")
	b.resolve_spell_hit(b.actors[0],1.0,context())
	b.player.attack = 1000.0
	advance(b,2.0)
	check(near(damage(b,"gem_inferno"),300.0), "ember cap snapshots attack at accumulation start")
	b = fresh("inferno")
	b._spell_combat.apply_burn(b,b.actors[0],"F01")
	advance(b,.5)
	b.resolve_fixed_item_hit(b.actors[0],100000.0,"fixture")
	check(b._gem_combat.embers.is_empty() and near(damage(b,"gem_inferno"),0), "death clears unfinished embers without death burst")
	b = fresh("inferno")
	b._spell_combat.apply_burn(b,b.actors[0],"F01")
	for index in 3:
		advance(b,.4)
		b._spell_combat.apply_burn(b,b.actors[0],"F01")
	check(b._spell_combat.fire_status.burns[1].layers == 1, "refresh never restores retired burn stacking")
	advance(b,4.0)
	check(b._gem_combat.embers.is_empty(), "natural burn expiry discards unfinished final cycle")

func ice_cases() -> void:
	var b = fresh("coffin",3)
	var token: int = ready(b)
	b.resolve_spell_hit(b.actors[0],4.0,context())
	check(near(damage(b,"F01"),240.0) and near(b._gem_combat.reserves[1].amount,160.0), "old window stores 40 percent planned body")
	advance(b,2.5)
	check(near(damage(b,"gem_coffin",1),288.0) and near(damage(b,"gem_coffin",2),86.4) and near(damage(b,"gem_coffin",3),86.4), "natural terminal pays 1.8 primary with two thirty-percent neighbors")
	b._gem_combat.release_coffin(b,1,token,b.actors[0].pos)
	check(near(damage(b,"gem_coffin"),460.8), "terminal token cannot pay twice")
	b = fresh("coffin",3)
	token = ready(b)
	b.resolve_spell_hit(b.actors[0],4.0,context())
	b._spell_combat.ice.status.consume_ready(b,b.actors[0],token)
	check(near(damage(b,"gem_coffin"),0), "early release waits for parent transaction")
	advance(b,1.0/120.0)
	check(near(damage(b,"gem_coffin",1),232.0) and near(damage(b,"gem_coffin",2),69.6), "consumed token uses lower 1.45 multiplier")
	b = fresh("coffin",3)
	ready(b)
	b.resolve_spell_hit(b.actors[0],4.0,context())
	b.resolve_fixed_item_hit(b.actors[0],100000.0,"fixture")
	check(near(damage(b,"gem_coffin",1),0) and near(damage(b,"gem_coffin"),96.0), "death pays only two thirty-percent neighbors at 1.0")
	advance(b,3.0)
	check(near(damage(b,"gem_coffin"),96.0), "death and natural deadline cannot duplicate")
	b = fresh("coffin")
	ready(b)
	b.resolve_spell_hit(b.actors[0],1.0,context())
	b.player.attack = 1000
	b.resolve_spell_hit(b.actors[0],10.0,context("fire",2))
	check(near(b._gem_combat.reserves[1].amount,800.0) and near(damage(b,"F01"),9300.0), "capacity fixed at old attack and overflow remains immediate")
	b = fresh("coffin")
	b.resolve_spell_hit(b.actors[0],1.0,context())
	check(b._gem_combat.reserves.is_empty() and near(damage(b,"F01"),100), "no preexisting window gives no reserve")
	ready(b)
	b.resolve_fire_status_hit(b.actors[0],1.0,"burning")
	check(b._gem_combat.reserves.is_empty(), "status input never enters body storage")
	b = fresh("coffin",3)
	ready(b,0)
	ready(b,1)
	b.resolve_spell_hit(b.actors[0],4.0,context())
	b.resolve_spell_hit(b.actors[1],4.0,context("fire",2))
	b.actors[1].health = 20.0
	b.resolve_fixed_item_hit(b.actors[0],100000,"fixture")
	check(b._gem_combat.reserves.is_empty() and near(damage(b,"gem_coffin"),68.0), "core neighbor death clears reserves without recursive core payouts")
	advance(b,3.0)
	check(b._spell_combat.ice.status.capture_ready(2).is_empty(), "removed neighbor state stays absent through deadline iteration")
	b = fresh("coffin",3)
	ready(b,0)
	ready(b,1)
	b.resolve_spell_hit(b.actors[0],4.0,context())
	b.resolve_spell_hit(b.actors[1],4.0,context("fire",2))
	b.actors[1].health = 20.0
	advance(b,2.5)
	check(b._gem_combat.reserves.is_empty() and near(damage(b,"gem_coffin",2),20), "natural expiry may remove a later state safely without recursive release")

func crystal_echo_cases() -> void:
	var b = fresh("fracture",3)
	b.player.crit_rate = 2.0
	b.player.crit_multiplier = 2.0
	b.resolve_spell_hit(b.actors[0],1.0,context())
	check(near(damage(b,"F01"),100), "critical base stays immediate without overcap extra layers")
	advance(b,.175)
	check(near(damage(b,"gem_fracture"),0), "first crystal not early")
	advance(b,.01)
	check(near(damage(b,"gem_fracture"),180), "first crystal receives 1.8 critical extra")
	advance(b,.25)
	check(near(damage(b,"gem_fracture"),315) and b._gem_combat.pending.is_empty(), "two finite nonrepeating links 90 and 45")
	b = fresh("fracture")
	b.player.crit_rate = 1
	b.player.crit_multiplier = 2
	b.resolve_spell_hit(b.actors[0],1.0,context())
	advance(b,1.0)
	check(near(damage(b,"gem_fracture"),180), "solo receives no unused-neighbor compensation")
	b = fresh("fracture",3)
	b.player.crit_rate = 1
	b.player.crit_multiplier = 2
	b.resolve_spell_hit(b.actors[0],1.0,context())
	advance(b,.19)
	b.resolve_fixed_item_hit(b.actors[1],100000,"fixture")
	advance(b,.5)
	check(near(damage(b,"gem_fracture"),180), "dead later link ends chain without retarget")
	b = fresh("echo")
	var c: Dictionary = context()
	c.kind = "beam"
	c.spell_id = "F08"
	b._spell_combat._beam(b,Vector2.ZERO,Vector2(0,3),.2,1.0,c,true)
	check(near(damage(b,"F08"),80), "legal replay body immediately scales to eighty percent")
	var rng_state: int = b._rng.state
	advance(b,.6)
	check(near(damage(b,"gem_echo"),65) and b._rng.state == rng_state, "noncritical sixty-five-percent replay has no RNG")
	check(b._spell_combat.fire_status.burns.is_empty(), "replay never copies ignition")
	b = fresh("echo")
	b._spell_combat._beam(b,Vector2.ZERO,Vector2(0,3),.2,1.0,c.duplicate(true),true)
	b.actors[0].pos = Vector2(10,10)
	advance(b,.6)
	check(near(damage(b,"gem_echo"),0), "replay rechecks actual shape and may miss")
	b = fresh("echo")
	b.player.gem_cdr = .2
	var spell: Dictionary = b._new_spell("F01")
	b.spells.append(spell)
	b._refresh_reward_spell_parameters()
	var actual_stats: Dictionary = b.get_spell_stats(spell)
	check(near(spell.cooldown,float(actual_stats.level.get("cooldown",actual_stats.get("cooldown",0.0)))*.8), "echo preserves ordinary cooldown reduction")
	b.spells.clear()
	var plain: Dictionary = context()
	b.resolve_spell_hit(b.actors[0],1.0,plain)
	check(near(damage(b,"F01"),100), "unqualified geometry has no hidden immediate tax")
	b.gem_record_shape({"kind":"area","pos":b.actors[0].pos,"radius":1.0},1.0,context("fire",3,false))
	check(b._gem_combat.echo.pending.is_empty(), "extra casts cannot record replay")

func life_cases() -> void:
	var b = fresh("sacrifice")
	advance(b,30)
	check(near(b.player.health,210) and near(b.player.shield,100) and near(b.damage_taken,0), "one percent drain bypasses shield and hurt events")
	b.resolve_spell_hit(b.actors[0],1.0,context())
	check(near(damage(b,"F01"),130), "seventy percent health gives thirty percent independent body gain")
	b.resolve_fixed_item_hit(b.actors[0],100,"fixture_fixed")
	check(near(damage(b,"fixture_fixed"),100), "fixed item damage does not receive missing-life multiplier")
	advance(b,40)
	check(near(b.player.health,105), "drain stops at thirty-five percent")
	b.player.health = 30
	b.resolve_spell_hit(b.actors[0],1.0,context("fire",2))
	check(near(damage(b,"F01"),320), "enemy-caused deeper missing life remains real")
	b.player.shield = 0
	b.damage_player(100000)
	check(b.phase == "dead", "drain floor never prevents enemy death")
	b = fresh("aegis")
	check(near(b.player.max_health,210) and near(b.player.max_shield,298) and near(b._gem_combat.raw_health,300), "aegis converts thirty percent at 2.2 once")
	b.player.health = 105
	b.player.shield = 149
	b._artifact_combat._owned.append("GT03")
	b._artifact_combat.apply_acquisition(b,"GT03")
	check(near(b.player.health/b.player.max_health,.5) and near(b.player.shield/b.player.max_shield,.5), "cap changes preserve both fractions")
	check(near(b.player.max_health,b._gem_combat.raw_health*.7) and near(b.player.max_shield,b._gem_combat.raw_shield+b._gem_combat.raw_health*.3*2.2), "cap changes recompute from unconverted bases")
	var hp: float = b.player.health
	var shield: float = b.player.shield
	b._artifact_combat._generic._restore_health(b,8,"GT04")
	check(near(b.player.health,hp) and near(b.player.shield,shield+8), "combat healing becomes actual shield one to one")
	b.player.shield = b.player.max_shield
	b._artifact_combat._generic._restore_health(b,8,"GT04")
	check(near(b.player.shield,b.player.max_shield), "full shield discards overflow")
	b._artifact_combat._generic._restore_health(b,3,"GU09")
	check(near(b.player.health,hp+3), "clear restoration still restores health")

func echo_area_cases() -> void:
	var b = fresh("echo")
	var spell: Dictionary = b._new_spell("F05")
	var stats: Dictionary = b.get_spell_stats(spell)
	for index in 2: b._spell_combat._cast(b,spell,stats,b.actors[0],true,1.0)
	for zone in b._spell_combat.zones:
		zone.pos = b.actors[0].pos
		zone.speed = 0.0
	advance(b,float(stats.interval))
	check(near(damage(b,"F05"),32), "overlapping same-spell areas share the original body gate")
	b._spell_combat.zones.clear()
	advance(b,.6)
	check(near(damage(b,"gem_echo"),26), "overlapping replay geometries share one same-spell hit")
	b = fresh("echo")
	for index in 2: b._spell_combat._cast(b,spell,stats,b.actors[0],true,1.0)
	for index in b._spell_combat.zones.size():
		var zone: Dictionary = b._spell_combat.zones[index]
		zone.pos = b.actors[0].pos
		zone.speed = 0.0
		zone.coefficient = .4 if index==0 else .8
	advance(b,float(stats.interval))
	b._spell_combat.zones.clear()
	advance(b,.6)
	check(near(damage(b,"F05"),64) and near(damage(b,"gem_echo"),52), "strongest overlapping source wins for both body and replay")
	b = fresh("echo")
	var c: Dictionary = context()
	c.kind = "beam"
	c.spell_id = "F08"
	for id in ["F05","F06"]:
		var ctx: Dictionary = {"natural":true,"school":"fire","kind":"field" if id=="F06" else "vortex","spell_id":id,"growth_level":{"overlap_fire_vulnerability":.15}}
		var z: Dictionary = b._spell_combat._zone("field" if id=="F06" else "rain_ground",id,b.actors[0].pos,1.0,2.0,0.0,0.0,ctx)
		z.terminal = false
		b._spell_combat.zones.append(z)
	b._spell_combat._beam(b,Vector2.ZERO,Vector2(0,3),.2,1.0,c,true)
	advance(b,.6)
	check(near(damage(b,"F08"),92) and near(damage(b,"gem_echo"),74.75), "fire vulnerability applies once to both eligible body and replay")

func boundaries() -> void:
	for core in ["inferno","coffin","lightning","wind","earth","spirit","fracture","echo","sacrifice","aegis"]:
		var b = fresh(core)
		check(b.gem_core() == core, "ten runtime core IDs " + core)
		b.set_paused(true)
		var state: Dictionary = b._gem_combat.snapshot()
		advance(b,1)
		check(b._gem_combat.snapshot() == state, "pause freezes core " + core)
		b.set_paused(false)
		b.phase = "pickup"
		advance(b,1)
		check(b._gem_combat.snapshot() == state, "safe phase freezes core " + core)
		b.phase = "combat"
		b._gem_combat.pending.append({"kind":"crystal","at":1.0})
		b._stop_combat()
		check(b._gem_combat.pending.is_empty() and b._gem_combat.reserves.is_empty() and b._gem_combat.embers.is_empty(), "room termination clears temporary resources " + core)

func run() -> int:
	group("fire_real_burn_tokens", fire_cases)
	group("ice_window_termination", ice_cases)
	group("critical_and_finite_replay", crystal_echo_cases)
	group("life_and_fixed_damage", life_cases)
	group("persistent_replay_shared_gate", echo_area_cases)
	group("phase_and_room_boundaries", boundaries)
	DirAccess.make_dir_recursive_absolute(OUT)
	var result: Dictionary = {"checks":checks,"failures":failures,"groups":groups,"native_core":true,"interactive":false,"natural_route":false,"pixel_validation":false}
	FileAccess.open(OUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("Gem v3 common combat: %d checks, %d failures" % [checks,failures.size()])
	return failures.size()
