extends SceneTree
## Explicit deterministic rule fixtures. Natural route evidence is separate.
const Route = preload("res://scripts/core/courtyard_route_run.gd")
const First = preload("res://scripts/core/first_room_run.gd")
const OUT = "res://build/qa/generic-items-implementation-20261018/rules.json"
var checks := 0
var failures: Array = []

class Fixture extends "res://scripts/core/courtyard_route_run.gd":
	func _reserve_batch(): pass
	func _update_spawn(_dt: float): pass
	func _update_enemies(_dt: float): pass
	func _check_clear(): pass
	func _update_spells(dt: float): _artifact_combat.update(self,dt)

func _initialize(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if not value:
		failures.append(label)
		push_error("Generic items: "+label)
func near(a: float,b: float) -> bool: return absf(a-b)<0.0001
func state(battle) -> Dictionary: return battle._artifact_combat.state_snapshot().generic
func stats(battle) -> Dictionary: return battle._artifact_combat.combat_stats(battle)
func grant(battle,id: String):
	check(not battle._artifact_combat.has_artifact(id),"fixture grants each ID once: "+id)
	battle._artifact_combat._owned.append(id)
	battle._artifact_combat.apply_acquisition(battle,id)
func advance(battle,seconds: float,move: Vector2=Vector2.ZERO):
	for frame in roundi(seconds*120.0): battle.step(1.0/120.0,move)
func actor(id: int=1,health: float=100000.0,elite: bool=false) -> Dictionary:
	return {"id":id,"type":"M01","type_id":"M01","health":health,"max_health":health,"pos":Vector2(0,2),"previous":Vector2(0,2),"radius":0.3,"elite":elite,"phase":"chase","push_resistance":0.0}
func context(cast_id: int=1,natural: bool=true,spell_id: String="F01",kind: String="bolt") -> Dictionary:
	return {"cast_id":cast_id,"natural":natural,"spell_id":spell_id,"kind":kind,"damage_scale":1.0,"field_bonus":0.0}
func fresh(ids: Array=["F01"]):
	var battle = Fixture.new()
	check(battle.configure({},20261017).ok,"fixture uses real current Route.configure")
	check(battle.choose_initial("F01"),"fixture real initial choice")
	battle.blocks.clear()
	battle.player.pos=Vector2.ZERO
	battle.player.previous=Vector2.ZERO
	battle.player.crit_rate=0.0
	battle.spells.clear()
	for id in ids:
		var spell: Dictionary=battle._new_spell(str(id))
		spell.remaining=1000.0
		battle.spells.append(spell)
	battle.actors=[actor()]
	return battle
func hurt(battle,amount: float,kind: String="direct") -> bool:
	battle.player.invulnerable=0.0
	return battle.damage_player(amount,kind)
func hit(battle,target: Dictionary,cast_id: int=1,coefficient: float=1.0,natural: bool=true) -> Dictionary:
	return battle.resolve_spell_hit(target,coefficient,context(cast_id,natural))
func shield(battle,amount: float) -> float:
	return battle._artifact_combat.restore_player_shield(battle,amount,"rule_fixture")

func run():
	catalog_and_rewards()
	attributes_and_contract()
	critical_and_cooldown()
	defense_and_hurt_order()
	movement_and_conditional_damage()
	recovery_and_reset()
	hunting()
	charge()
	cup()
	freezing()
	var output_path: String = OUT
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with("--qa-out=res://build/qa/") and not str(argument).contains(".."):
			output_path = str(argument).trim_prefix("--qa-out=").path_join("rules.json")
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	FileAccess.open(output_path,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"details":failures,"scope":"Authoritative fixtures for 24 ordinary generic entries and actual event APIs. 63 stored definitions include 56 ordinary active, four Boss-only seals and three archived. Not a natural inventory or human balance sample."},"\t"))
	print("GENERIC RULES: %d checks; %d failures" %[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func catalog_and_rewards():
	var b=fresh(["F01","F02","F03","F04","F05","F06","F07","F08","F09","F10","F11"])
	var items: Dictionary=b._artifact_combat._items
	check(items.size()==63,"63 stored entries including four Boss-only seals and three archived spirit")
	check(items.keys().filter(func(id): return items[id].scope=="generic" and not bool(items[id].get("boss_only", false))).size()==24,"24 ordinary generic entries")
	check(items.keys().filter(func(id): return items[id].scope=="fire").size()==16,"16 profession entries")
	check(items.keys().filter(func(id): return items[id].scope=="spirit" and not bool(items[id].get("active",true))).size()==3,"three spirit entries preserved inactive")
	check(items.P04.scope=="generic" and items.P05.scope=="generic","P04 P05 migrate same IDs")
	for tier_count in [["blue",10],["purple",10],["gold",4]]:
		check(items.keys().filter(func(id):return items[id].scope=="generic" and not bool(items[id].get("boss_only", false)) and items[id].rarity==tier_count[0]).size()==tier_count[1],"ordinary generic rarity distribution "+tier_count[0])
	check("GU07" not in b._artifact_combat.eligible_ids(b),"crit multiplier requires permanent10pct")
	grant(b,"GU06")
	check("GU07" not in b._artifact_combat.eligible_ids(b),"fixture0 plus8pct stays below10pct")
	b.player.crit_rate=0.1
	check("GU07" in b._artifact_combat.eligible_ids(b),"10pct exactly qualifies GU07")
	var unsupported=fresh(["F04"])
	check("GT01" not in unsupported._artifact_combat.eligible_ids(unsupported),"spirit alone does not provide player damage or recovery")
	grant(unsupported,"GU11")
	check("GT01" not in unsupported._artifact_combat.eligible_ids(unsupported),"recovery plus summons still lacks player damage")
	unsupported.spells.append(unsupported._new_spell("F01"))
	check("GT01" in unsupported._artifact_combat.eligible_ids(unsupported),"generic recovery and player damage qualify without F10")
	b.room_index=6
	var offered: Array=b._artifact_combat.sample_choices(b,b._rng)
	var rng_before: int=b._rng.state
	check(offered.size()==3 and offered.map(func(item):return item.id).size()==3,"existing chest produces three legal choices")
	check(b._artifact_combat.sample_choices(b,b._rng)==offered and b._rng.state==rng_before,"cached reopen cannot reroll")
	for item in offered: check(offered.filter(func(other):return other.id==item.id).size()==1,"unique offered ID "+str(item.id))
	check(not b._artifact_combat.choose("invented",b),"unoffered or unknown rejected")
	check(b._artifact_combat.choose(str(offered[0].id),b),"real cached offered item accepted")
	check(not b._artifact_combat.choose(str(offered[0].id),b),"unique holding and reward single claim")
	var original_owned: Array=b._artifact_combat.owned_snapshot()
	var copy: Array=b._artifact_combat.owned_snapshot()
	copy[0].values.name="mutated"
	check(b._artifact_combat.owned_snapshot()==original_owned,"owned snapshots are isolated copies")
	check(b._artifact_reward_rooms==[6,12,15,21,27,30,36,39,45,51,57,60] and b._reward_rooms.size()==52,"ordinary nodes preserved with four Boss books and final chest")
	var exhausted=fresh()
	exhausted.room_index=39
	exhausted._artifact_combat._owned.assign(exhausted._artifact_combat._items.keys())
	check(exhausted._artifact_combat.sample_choices(exhausted,exhausted._rng).is_empty(),"exhausted ordinary legal pool produces no duplicate")

func attributes_and_contract():
	for order in [["U01","GT03"],["GT03","U01"]]:
		var b=fresh()
		b.player.health=200.0
		b.player.shield=21.0
		for id in order: grant(b,id)
		check(near(b.player.max_health,304.0),"flat HP before20pct contract independent of order "+str(order))
		check(near(b.player.health,160.0),"contract scales current once and later flat does not heal "+str(order))
		check(b.hits==0 and b.damage_taken==0.0 and near(b.player.shield,21.0),"acquisition is not hurt/heal and never changes shields")
	var b=fresh()
	b.player.health=123.0
	b.player.shield=17.0
	for id in ["U01","U02","U03"]: grant(b,id)
	check(near(b.player.max_health,380) and near(b.player.health,123),"U01 preserves no free healing")
	check(near(b.player.max_shield,125) and near(b.player.shield,17),"U02 preserves no instant shielding")
	check(near(b.player.attack,115),"U03 remains flat attack15")
	grant(b,"GT03")
	check(near(stats(b).generic_damage_bonus,0.25),"contract25pct generic bonus")
	grant(b,"GT02")
	b.player.health=b.player.max_health*0.5
	check(stats(b).low_health_active and near(stats(b).defense,20) and near(stats(b).generic_damage_bonus,0.5),"half health inclusive, same bucket adds two25pct")
	b.player.health+=0.001
	check(not stats(b).low_health_active and near(stats(b).generic_damage_bonus,0.25),"low health bonus ends immediately above half")
	var normal=actor(2)
	var elite=actor(3,100000,true)
	grant(b,"GU13")
	var normal_hit=hit(b,normal,401)
	var elite_hit=hit(b,elite,402)
	check(near(normal_hit.damage,115*1.25) and near(elite_hit.damage,115*1.45),"elite20pct joins generic bucket only on elite target")

func critical_and_cooldown():
	var b=fresh()
	b.player.crit_rate=1.25
	grant(b,"GU06")
	check(near(b.player.crit_rate,1.33),"133pct crit retained without80pct cap")
	grant(b,"GU07")
	for index in 80:
		var result=hit(b,b.actors[0],1000+index)
		check(result.critical and near(result.damage,175.0),">100pct always one normal crit, no supercrit "+str(index))
	var independent=First.new()
	check(independent.configure({"player":{"crit_rate":1.25}},37).ok,"independent first room accepts uncapped crit")
	for index in 20: check(near(independent._roll_damage(1.0),150.0),"independent room guaranteed singlecrit "+str(index))
	var cd=fresh(["F01","F02","F08"])
	grant(cd,"GU05")
	cd._spell_combat.update(cd,1.0/120.0)
	check(near(cd.spells[0].cooldown,1.2*0.84),"three-fire10pct plusGU05sixpp equals16pct")
	check(near(cd.spells[0].windup,0.15),"CDR never changes windup")
	check(near(cd._base.limits.cooldown_reduction,0.6),"runtime source CDR hardcap60pct")
	# Explicit extreme-stat boundary, not an obtainable inventory claim.
	cd._base.fire_synergy.cooldown_reduction=0.9
	cd._spell_combat.update(cd,1.0/120.0)
	check(near(cd.spells[0].cooldown,0.48),"90pct+6pp obeys60pct actual cooldown cap")
	cd._base.spells.F01.cooldown=0.1
	cd._spell_combat.update(cd,1.0/120.0)
	check(near(cd.spells[0].cooldown,0.2),"cooldown0.2second floor remains")

func defense_and_hurt_order():
	var b=fresh()
	grant(b,"GU04")
	grant(b,"GU12")
	check(near(stats(b).defense,45),"15+30 defense adds once")
	check(hurt(b,100) and near(b.player.shield,100-100.0/1.45),"defense reduces before shield")
	check(near(b.player.invulnerable,0.6),"effective hurt grants original0.6 invulnerability")
	var shield_after: float=b.player.shield
	check(not b.damage_player(100) and near(b.player.shield,shield_after),"invulnerable hit cannot hurt or trigger")
	grant(b,"GU10")
	check(near(b._artifact_combat.incoming_damage_multiplier(b,"projectile"),(1.0/1.45)*0.82),"only projectile tag gets18pct after defense")
	for kind in ["mark","charge","lunge","direct"]: check(near(b._artifact_combat.incoming_damage_multiplier(b,kind),1.0/1.45),"nonprojectile cannot borrow GU10: "+kind)
	var projectile=fresh()
	grant(projectile,"GU10")
	projectile._enemy_combat.enemy_projectiles.append({"id":1,"source_id":9,"type_id":"M02","pos":Vector2(0,1),"previous":Vector2(0,1),"direction":Vector2(0,-1),"speed":30.0,"radius":0.1,"damage":30.0,"remaining":3.0,"range_remaining":12.0})
	projectile._enemy_combat._update_projectiles(projectile,0.1)
	check(near(projectile.player.shield,75.4),"actual EnemyCombat projectile path supplies projectile damage tag")
	grant(b,"GU18")
	grant(b,"GT02")
	b.player.health=100.0
	advance(b,0.75)
	check(near(stats(b).defense,85) and near(b._artifact_combat.incoming_damage_multiplier(b,"direct"),0.55),"all85DEF obeys combined45pct cap")
	check(near(b._artifact_combat.incoming_damage_multiplier(b,"projectile"),0.55),"projectile reduction shares45pct cap")
	var lethal=fresh()
	for id in ["GU14","GU16","GT04"]: grant(lethal,id)
	lethal.player.health=5.0
	lethal.player.shield=10.0
	check(hurt(lethal,100) and lethal.phase=="dead" and lethal.player.health==0.0,"death wins before break shield or restorative item")
	check(near(lethal.player.shield,0.0) and int(state(lethal).regen_remaining_ticks)==0,"lethal hit cannot schedule recovery or resurrect shield")

func movement_and_conditional_damage():
	var b=fresh()
	grant(b,"GU08")
	var initial: Vector2=b.player.pos
	advance(b,0.5,Vector2.RIGHT)
	check(near(b.player.pos.distance_to(initial),2.7),"GU08 actual movement speed5.4 only combat")
	b.phase="exit"
	initial=b.player.pos
	advance(b,0.5,Vector2.RIGHT)
	check(near(b.player.pos.distance_to(initial),2.5),"GU08 not applied during exit walk")
	b.phase="combat"
	grant(b,"GU18")
	advance(b,0.74)
	check(not stats(b).stationary_active,"standing delay not early")
	advance(b,0.01)
	check(stats(b).stationary_active and near(stats(b).generic_damage_bonus,0.12) and near(stats(b).defense,20),"GU18 actual0.75sec standstill gives both stats")
	advance(b,1.0/120.0,Vector2.RIGHT)
	check(not stats(b).stationary_active,"move input immediately ends stationary bonus")
	grant(b,"GU15")
	advance(b,6.0)
	check(stats(b).undamaged_active,"GU15 actual six combat seconds qualifies")
	check(hurt(b,1.0) and not stats(b).undamaged_active,"shield loss resets no-hurt state")
	advance(b,6.0)
	b.player.invulnerable=1.0
	check(not b.damage_player(1.0) and stats(b).undamaged_active,"invuln rejected contact does not reset no-hurt")
	var old=fresh(["F01","F09"])
	for id in ["GU08","GU16"]: grant(old,id)
	old.player.shield=1.0
	hurt(old,2.0)
	var wave: Dictionary = old._owned_spell("F09")
	wave.level = 3
	old._spell_combat._cast(old,wave,old.get_spell_stats(wave),old.actors[0],true,1.0)
	check(near(old._artifact_combat.move_speed_multiplier(old),1.33),"8+10+15 combat speed shares additive bucket")

func recovery_and_reset():
	var b=fresh()
	grant(b,"GU11")
	b.player.shield=50
	advance(b,5.99)
	check(near(b.player.shield,50),"GU11 does not heal before full6sec")
	advance(b,0.01)
	check(near(b.player.shield,55),"GU11 periodic actual5 shield")
	b.player.shield=100
	advance(b,6.0)
	b.player.shield=70
	advance(b,0.01)
	check(near(b.player.shield,70),"fullshield wasted tick not banked")
	var next=fresh()
	grant(next,"GU09")
	next.player.health=200
	next._artifact_combat.on_room_cleared(next)
	check(near(next.player.health,200),"GU09 does not retroheal acquired room")
	next._enter_room(2)
	next._artifact_combat.on_room_cleared(next)
	check(near(next.player.health,203),"GU09 nextroom once actual clear callback")
	next._artifact_combat.on_room_cleared(next)
	check(near(next.player.health,203),"duplicate clear callback never double heals")
	var regen=fresh()
	grant(regen,"GU14")
	regen.player.shield=0
	hurt(regen,80)
	check(near(regen.player.health,220) and int(state(regen).regen_remaining_ticks)==4 and near(state(regen).regen_per_tick,3),"GU14 cap12 fixes four delayed3point ticks")
	advance(regen,1.0)
	check(near(regen.player.health,223),"GU14 firsttick delayed one fullsecond")
	hurt(regen,20)
	advance(regen,3.0)
	check(near(regen.player.health,212) and int(state(regen).regen_remaining_ticks)==0,"new hurt cannot resnapshot or refresh pending heal")
	var broken=fresh()
	grant(broken,"GU16")
	broken.player.shield=10
	hurt(broken,20)
	check(near(broken.player.health,290) and near(broken.player.shield,35),"GU16 recovers35 after samehit10life overflow")
	check(near(broken._artifact_combat.move_speed_multiplier(broken),1.1),"GU16 grants10pct combat speed")
	hurt(broken,40)
	check(near(broken.player.health,285) and near(broken.player.shield,0),"second break same room cannot restore again")
	advance(broken,3.0)
	check(near(broken._artifact_combat.move_speed_multiplier(broken),1),"break movement bonus expires after3 combat seconds")
	broken._enter_room(2)
	broken.player.shield=1
	hurt(broken,2)
	check(near(broken.player.shield,35),"newroom resets firstbreak entitlement")
	var cancelled=fresh()
	grant(cancelled,"GU14")
	cancelled.player.shield=0
	hurt(cancelled,50)
	hurt(cancelled,1000)
	advance(cancelled,4)
	check(cancelled.phase=="dead" and near(cancelled.player.health,0),"GU14 death cancels pending heal")

func hunting():
	var b=fresh()
	grant(b,"GU17")
	var target=actor(2,1)
	b.damage_enemy(target,1,"F01")
	check(int(state(b).hunting_stacks)==1,"actual enemy death grants first stack")
	b.damage_enemy(target,5,"F01")
	b._artifact_combat.on_enemy_killed(b,target)
	check(int(state(b).hunting_stacks)==1,"dead actor duplicate paths cannot grant second stack")
	for id in [3,4,5]: b.damage_enemy(actor(id,1),1,"GT01")
	check(int(state(b).hunting_stacks)==1,"same instant AoE kills only one per second")
	advance(b,1.0)
	b._artifact_combat.on_enemy_killed(b,target)
	check(int(state(b).hunting_stacks)==1,"old dead ID still excluded afterICD")
	b.damage_enemy(actor(6,1),1,"GT01")
	check(int(state(b).hunting_stacks)==2,"fixed item kill can grant next valid stack")
	advance(b,1.0)
	b.damage_enemy(actor(7,1),1,"F04")
	check(int(state(b).hunting_stacks)==3 and near(stats(b).generic_damage_bonus,0.18),"summon kills count and3stackcap yields18pct")
	advance(b,5.99)
	check(int(state(b).hunting_stacks)==3,"validkill refreshes whole6sec group")
	advance(b,0.01)
	check(int(state(b).hunting_stacks)==0,"hunting expires wholegroup")

func charge():
	var b=fresh(["F01","F10"])
	grant(b,"GT01")
	b.player.shield=0
	check(near(shield(b,20),25) and near(state(b).charge,100),"GT0125pct restore and4per actual unit")
	shield(b,100)
	check(near(b.player.shield,100) and near(state(b).charge,200),"charge caps2xcurrentattack, overflowshield not counted")
	b.player.attack=50
	advance(b,1.0/120.0)
	check(near(state(b).charge,100),"charge immediately clamps when attack falls")
	b.player.attack=100
	b.player.crit_rate=1.2
	b.player.fire_bonus=1.0
	grant(b,"GT03")
	var hp_before: float=b.actors[0].health
	var result=hit(b,b.actors[0],700)
	check(near(result.damage,375) and near(hp_before-b.actors[0].health,475),"fixed100charge not multiplied again by attack/fire/generic/critical")
	check(near(state(b).charge,0) and near(state(b).charge_cooldown,2),"live actual release consumes store starts2secICD")
	check(b._artifact_combat._natural_casts==0 and b._artifact_combat._patches.is_empty(),"fixed release cannot synthesize cast or critical engraving events")
	b.player.shield=50
	shield(b,10)
	var stored: float=state(b).charge
	hit(b,b.actors[0],701)
	check(near(state(b).charge,stored),"firstcheck withinICD preserves store")
	advance(b,2.0)
	hit(b,b.actors[0],701)
	check(near(state(b).charge,stored),"samecast later multihit cannot release afterICD")
	hit(b,b.actors[0],702,1,false)
	check(near(state(b).charge,stored),"extra cast never consumes charge")
	hit(b,b.actors[0],703)
	check(near(state(b).charge,0),"next natural cast first hit releases")
	advance(b,2.0)
	hit(b,b.actors[0],704)
	b.player.shield=50
	shield(b,10)
	stored=state(b).charge
	hit(b,b.actors[0],704)
	check(near(state(b).charge,stored),"firstcheck emptybank cannot release later samecast")
	var first_dead=actor(80,1)
	hit(b,first_dead,705)
	check(near(state(b).charge,stored) and near(state(b).charge_cooldown,0),"parentkill firsttarget preservesstore noICD")
	hit(b,b.actors[0],705)
	check(near(state(b).charge,stored),"deadfirsttarget does not transfer check to secondtarget")
	b.resolve_spell_hit(b.actors[0],1,context(706,true,"F04","spirit"))
	check(near(state(b).charge,stored),"summonattack not a natural playerdamagespell")
	var restoration=fresh(["F01","F10"])
	grant(restoration,"GT01")
	restoration.player.shield=0
	check(restoration.cast_extra_spell("F10"),"real shieldspell can cast from legal engine")
	check(near(restoration.player.shield,37.5) and near(state(restoration).charge,150),"actualF10 restoration uses sameGT01 hook")
	restoration._enter_room(2)
	check(near(state(restoration).charge,0) and near(state(restoration).charge_cooldown,0) and state(restoration).charge_checked_casts.is_empty(),"crossroom clears charge/ICD/check keys")

func cup():
	var b=fresh()
	grant(b,"GT04")
	b.player.health=200
	hurt(b,59)
	check(near(b.player.health,200) and near(state(b).cup_progress,59),"actual59shieldloss stayspending")
	hurt(b,1)
	check(near(b.player.health,208) and near(state(b).cup_progress,0) and near(state(b).cup_cooldown,2),"actual60shieldloss yields8health once")
	b.player.shield=100
	hurt(b,100)
	check(near(b.player.health,208) and near(state(b).cup_progress,59),"ICD incomingloss retained only59")
	advance(b,2)
	check(near(b.player.health,208),"ICD expiry never auto grants heal")
	b.player.shield=1
	hurt(b,1)
	check(near(b.player.health,216) and near(state(b).cup_progress,0),"next real loss afterICD completes60")
	var full=fresh()
	grant(full,"GT04")
	hurt(full,60)
	check(near(full.player.health,300) and near(state(full).cup_progress,0) and near(state(full).cup_cooldown,2),"fullhealth still consumes threshold andICD")
	var big=fresh()
	grant(big,"GT04")
	big.player.max_shield=300
	big.player.shield=300
	big.player.health=100
	hurt(big,250)
	check(near(big.player.health,108) and near(state(big).cup_progress,59),"largehit triggers once keepsmaximum59")
	var guarded=fresh()
	for id in ["GT04","GU04"]: grant(guarded,id)
	guarded.player.health=200
	hurt(guarded,68)
	check(near(guarded.player.health,200) and state(guarded).cup_progress<60,"raw68 does not cross60 after defense")
	hurt(guarded,1)
	check(near(guarded.player.health,208),"cup uses60 actualshieldloss after defense acrosshits")
	big._enter_room(2)
	check(near(state(big).cup_progress,0) and near(state(big).cup_cooldown,0),"cup progress andICD reset eachroom")

func freezing():
	var b=fresh()
	for id in ["GU11","GU14","GU15","GU16","GU17","GU18","GT01","GT04"]: grant(b,id)
	b.player.shield=5
	hurt(b,10)
	b.damage_enemy(actor(90,1),1,"F01")
	advance(b,0.3)
	var before: Dictionary=state(b)
	b.set_paused(true)
	advance(b,0.7,Vector2.RIGHT)
	check(state(b)==before,"pause freezes every generic timer/store/stack")
	b.set_paused(false)
	for phase_name in ["pickup","reward","artifact","exit"]:
		b.phase=phase_name
		before=state(b)
		var clock: float=b.time
		advance(b,0.5)
		check(state(b)==before and near(b.time,clock+0.5),"noncombat "+phase_name+" freezes generic yet advances routeclock")
	b._enter_room(2)
	before=state(b)
	for key in ["stationary_elapsed","undamaged_elapsed","shield_elapsed","hunting_stacks","regen_remaining_ticks","charge","cup_progress"]:
		check(near(float(before[key]),0),"roomreset clears transient "+key)
