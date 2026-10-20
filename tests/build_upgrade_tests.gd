extends RefCounted
const Config=preload("res://scripts/core/build_config.gd")
const Battle=preload("res://scripts/core/build_battle.gd")
const Catalog=preload("res://scripts/core/spell_catalog.gd")
const Stats=preload("res://scripts/core/spell_stats.gd")
const Effects=preload("res://scripts/core/build_effects.gd")
const Rewards=preload("res://scripts/core/build_rewards.gd")
var checks=0
var failures=0
var loader=Config.new()
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		push_error("Build upgrades: "+message)
func near(a: float,b: float) -> bool: return absf(a-b)<.0001
func fresh(ids: Array=[],count: int=0,run: bool=false): return Battle.new(loader.values,count,Catalog.IDS,loader.layout,1.5,ids,run)
func advance(b,seconds: float):
	for i in range(roundi(seconds*120)): b.step(Battle.STEP)
func cast(b,id: String,enhanced: bool=false):
	b.select_slot(b.slots.find(id))
	b.player.mana=100
	b.command("press")
	b.step(Battle.STEP)
	advance(b,b.stats().chant+Battle.STEP)
	if enhanced: advance(b,b.stats().extra_chant+Battle.STEP)
	b.command("release")
	b.step(Battle.STEP)
func dummy(b,pos: Vector2=Vector2(3,0),health: float=10000):
	b.spawn(1)
	var e=b.enemies[0]
	e.pos=pos
	e.health=health
	e.max_health=health
	e.state="recover"
	e.until=100000
	return e
func run() -> int:
	check(loader.load_all(),"configuration "+loader.error)
	if loader.values.is_empty(): return failures+1
	for spell in Catalog.IDS:
		var ids=Catalog.FUTURE_UPGRADES.filter(func(id): return Catalog.upgrade_spell(id)==spell)
		check(ids.size()==6,"six upgrades "+spell)
		check(ids.filter(func(id): return Catalog.tier(id)=="legendary").size()==1,"one legendary "+spell)
		check(ids.filter(func(id): return Catalog.tier(id)=="common").size()==3 and ids.filter(func(id): return Catalog.tier(id)=="rare").size()==2,"3 common and 2 rare "+spell)
		var reversed=ids.duplicate()
		reversed.reverse()
		var a=Stats.compute(loader.values,spell,ids)
		var c=Stats.compute(loader.values,spell,reversed)
		a.erase("owned")
		c.erase("owned")
		check(a==c,"order independent "+spell)
	for id in Catalog.FUTURE_UPGRADES:
		var b=fresh([id])
		var spell=Catalog.upgrade_spell(id)
		b.aim=Vector2(2,0)
		cast(b,spell,id=="molten")
		advance(b,.8)
		check(b.by_spell[spell].released==1 and b.owned==[id],"single upgrade release "+id)
		check(b.events.size()<30,"single upgrade event budget "+id)
	meteor_and_fireball()
	frost_checks()
	heal_checks()
	lamp_checks()
	combination_checks()
	reward_checks()
	flow_checks()
	record_checks()
	config_checks()
	print("Build upgrades: %d checks, %d failures" % [checks,failures])
	return failures
func meteor_and_fireball():
	var s=Stats.compute(loader.values,"meteor",["meteor_quick","meteor_wide","meteor_efficient"])
	check(near(s.chant,1.12) and near(s.radius,2.6) and near(s.cost,29),"meteor ordinary formulas")
	var b=fresh(["meteor_fragments","meteor_burn","meteor_storm"])
	var e=dummy(b)
	b.aim=e.pos
	cast(b,"meteor")
	check(b.meteors.size()==3,"three main meteor strikes")
	advance(b,2)
	check(b.events.filter(func(ev): return ev.kind=="blast" and ev.data.source_kind=="meteor_main").size()==3,"three main impacts")
	check(b.events.filter(func(ev): return ev.kind=="blast" and ev.data.source_kind=="meteor_fragment").size()==3,"one group of three fragments")
	check(b.burns.size()==1 and near(b.burns[0].damage,10),"one burn budget")
	check(near(b.damage_kinds.meteor_main,107.25),"three strikes at 55 percent")
	check(b.summary.released==1,"secondary effects never release")
	b=fresh(["quick_chant","efficient_cast","wide_blast","embers","echo","molten"])
	e=dummy(b)
	b.aim=e.pos
	cast(b,"fireball",true)
	check(b.bullets[0].stats.enhanced and near(b.bullets[0].stats.damage,66) and near(b.bullets[0].stats.cost,25),"molten existing formula")
	b.select_slot(2)
	advance(b,.9)
	check(near(b.damage_kinds.fireball_main,66) and near(b.damage_kinds.fireball_echo,33),"main and echo snapshots")
	check(b.burns.size()==1 and b.summary.released==1,"echo no recursive burn")
	b=fresh(["echo","embers"])
	e=dummy(b)
	b.aim=e.pos
	cast(b,"fireball")
	b.set_owned([])
	advance(b,.9)
	check(near(b.damage_kinds.fireball_echo,15) and b.burns.size()==1,"released upgrade snapshot survives later ownership change")
	b.set_owned(["echo","echo"])
	check(b.owned.is_empty(),"duplicate upgrades rejected")
func frost_checks():
	var b=fresh(["frost_wide","frost_duration","frost_efficient","frost_freeze","frost_exposure","frost_field"])
	check(near(b.stats().cost,18),"initial active is fireball unaffected")
	b.select_slot(2)
	check(near(b.stats().radius,3.1) and near(b.stats().slow_duration,4) and near(b.stats().cost,18),"frost ordinary formulas")
	var e=dummy(b,Vector2(2,0))
	e.state="warning"
	e.until=b.elapsed+100
	cast(b,"frost")
	var pos=e.pos
	var due=e.until
	var lock=e.freeze_lockout
	advance(b,.3)
	check(e.pos==pos and near(e.until,due+.3) and e.state=="warning","freeze pauses warning")
	Effects.nova(b,b.stats(),99)
	check(e.freeze_lockout==lock,"freeze lockout not refreshed")
	advance(b,.4)
	check(e.freeze_until<b.elapsed and near(b.freeze_seconds,.6),"freeze bounded actual seconds")
	var exposure_end=e.exposure_until
	var field_pos=b.fields[0].pos
	b.player.pos=Vector2(-5,-4)
	advance(b,.5)
	check(b.fields[0].pos==field_pos and e.exposure_until==exposure_end,"field fixed and no exposure refresh")
	e.pos=Vector2(3,0)
	var hp=e.health
	b.hit_enemy(e,10,1,"meteor_main")
	check(near(hp-e.health,12),"exposure reads direct hit")
	hp=e.health
	b.hit_enemy(e,10,1,"burn")
	b.hit_enemy(e,10,1,"lamp_basic")
	check(near(hp-e.health,20),"burn and summon do not gain exposure")
	e.exposure_until=b.elapsed
	hp=e.health
	b.hit_enemy(e,10,1,"fireball_echo")
	check(near(hp-e.health,10),"exposure expires exactly")
	b=fresh(["frost_freeze"])
	e=dummy(b,Vector2(1,0))
	e.state="attack"
	e.start=e.pos
	e.aim=Vector2.RIGHT
	e.until=.2
	e.freeze_until=.6
	advance(b,.5)
	check(e.pos==Vector2(1,0) and near(e.until,.7),"freeze holds attack position and remaining time")
	advance(b,.15)
	check(e.pos.x>1 and e.pos.x<3.4 and e.state=="attack","thaw resumes attack rather than jumping")
	b=fresh(["frost_freeze"])
	e=dummy(b,Vector2.ZERO)
	e.state="attack"
	e.start=e.pos
	e.aim=Vector2.RIGHT
	e.until=.2
	e.freeze_until=.6
	advance(b,.5)
	check(b.player.health==100 and not e.hit,"frozen touching enemy cannot hit")
	b=fresh()
	e=dummy(b)
	Effects.slow(b,e,4,.8,"long")
	Effects.slow(b,e,.5,.4,"short")
	advance(b,.6)
	check(near(e.slow_multiplier,.8) and e.slow_until>b.elapsed,"weaker long slow survives short expiry")
func heal_checks():
	var b=fresh(["heal_amount","heal_quick","heal_efficient","heal_immediate","heal_shield","heal_spring"])
	b.player.health=90
	cast(b,"rejuvenation")
	check(near(b.stats().chant,.6) and near(b.stats().cost,21),"heal ordinary formulas")
	check(near(b.player.health,100) and near(b.shield_total(),2.8),"39 budget immediate 15.6 heals 10 and shields 2.8")
	advance(b,5.1)
	check(near(b.heal_total,10) and near(b.overheal_total,29) and b.shield_total()<=15,"immediate plus ongoing conserved")
	b=fresh(["heal_shield"])
	cast(b,"rejuvenation")
	advance(b,5.1)
	check(near(b.shield_total(),15),"overheal cap 15")
	b.command("press")
	b.step(Battle.STEP)
	b.damage_player(10)
	check(b.phase=="idle" and b.left_gate and near(b.player.health,100) and near(b.shield_absorbed,10),"full shield hit cancels cast")
	b=fresh()
	Effects.add_shield(b,"rejuvenation",10,15,2,1)
	Effects.add_shield(b,"lamp",8,8,1,2)
	b.damage_player(12)
	check(not b.shields.has("lamp") and near(b.shields.rejuvenation.amount,6),"earliest shield absorbs first")
	advance(b,2)
	check(near(b.shield_total(),0),"shield expiry")
	b=fresh(["heal_spring"])
	b.player.health=10
	cast(b,"rejuvenation")
	b.damage_player(20)
	check(near(b.player.health,1) and b.fatal_used and b.healing.is_empty(),"fatal saves one health and consumes heal")
	b.damage_player(20)
	check(b.result=="playing","fatal immunity")
	advance(b,.51)
	var s=Stats.compute(b.cfg,"rejuvenation",b.owned)
	Effects.rejuvenation(b,s,99)
	b.damage_player(20)
	check(b.result=="failure" and b.player.health==0,"only once per battle even refreshed")
	b=fresh(["heal_spring"])
	b.player.health=1
	cast(b,"rejuvenation")
	b.elapsed=b.healing.until
	b.damage_player(1000)
	check(b.result=="failure" and not b.fatal_used,"fatal protection absent at exact heal end")
func lamp_checks():
	var b=fresh(["lamp_duration","lamp_damage","lamp_range","lamp_sync","lamp_guard","lamp_twin"])
	var e=dummy(b,Vector2(3,0))
	cast(b,"lamp")
	check(near(b.stats().duration,16) and near(b.stats().damage,10.8) and near(b.stats().range,6.5),"lamp ordinary formulas")
	b.aim=e.pos
	cast(b,"meteor")
	check(near(b.damage_kinds.lamp_sync,12),"sync plus twin only one hit")
	advance(b,1)
	check(b.events.filter(func(ev): return ev.kind=="damage" and ev.data.source_kind=="lamp_sync").size()==1,"meteor impacts never retrigger sync")
	advance(b,2)
	check(b.shield_total()<=8 and b.shields.has("lamp"),"guard one source capped")
	var ready=b.sync_ready_at
	Effects.lamp(b,Stats.compute(b.cfg,"lamp",b.owned),99)
	check(b.sync_ready_at==ready,"replacement preserves sync gate")
	b.sync_ready_at=b.elapsed+1
	var damage=b.summary.damage
	Effects.sync(b,e.pos,100)
	check(near(b.summary.damage,damage),"sync inside interval blocked")
	b.sync_ready_at=0
	e.pos=Vector2(9,9)
	Effects.sync(b,Vector2.ZERO,101)
	check(b.sync_ready_at==0,"no sync target doesn't consume qualification")
	b=fresh(["lamp_twin"])
	e=dummy(b)
	cast(b,"lamp")
	b.aim=e.pos
	cast(b,"fireball")
	check(near(b.damage_kinds.lamp_sync,12),"twin grants sync without rare")
func combination_checks():
	var b=fresh()
	var e=dummy(b)
	b.cast_sources[1]="fireball"
	b.cast_sources[2]="meteor"
	Effects.add_burn(b,e.pos,2,3,8,1)
	Effects.add_burn(b,e.pos,2,3,10,2)
	advance(b,1)
	check(near(b.damage_kinds.burn,10) and near(b.by_spell.meteor.damage,10),"overlap chooses highest due damage and source")
	b=fresh()
	e=dummy(b)
	Effects.add_burn(b,e.pos,2,3,8,1)
	advance(b,.5)
	Effects.add_burn(b,e.pos,2,3,10,2)
	advance(b,1.1)
	check(near(b.damage_kinds.burn,8),"staggered region cannot bypass shared interval")
	advance(b,.5)
	check(near(b.damage_kinds.burn,16),"next existing region ticks at shared cadence")
	b=fresh()
	e=dummy(b,Vector2.ZERO,5)
	b.hit_enemy(e,100,1,"meteor_fragment")
	check(near(b.summary.damage,5),"overkill excluded")
	for mask in range(64):
		var ids=[]
		for i in range(6):
			if mask&(1<<i): ids.append(Catalog.FUTURE_UPGRADES[i])
		var old=preload("res://scripts/core/fireball_stats.gd").compute(loader.values,ids,true)
		var adapted=Stats.compute(loader.values,"fireball",ids,true)
		for key in old: check(adapted[key]==old[key],"enhanced old formula parity %d %s" % [mask,key])
	b=fresh(Catalog.FUTURE_UPGRADES)
	e=dummy(b,Vector2(2,0))
	for id in Catalog.IDS: b.cfg[id+".cooldown"]=0
	b.aim=e.pos
	for cycle in range(3):
		for spell in ["lamp","frost","rejuvenation","fireball","meteor"]:
			cast(b,spell,spell=="fireball")
			check(b.meteors.size()<=6 and b.fields.size()<=2 and b.burns.size()<=6,"all upgrades bounded queues")
	advance(b,20)
	check(b.bullets.is_empty() and b.meteors.is_empty() and b.fields.is_empty() and b.burns.is_empty() and b.lamp.is_empty(),"all effects eventually terminate")
	check(b.summary.released==15 and b.events.size()<400,"all upgrades bounded nonrecursive event tree")
	check(b.damage_kinds.get("lamp_sync",0)>0 and b.damage_kinds.get("burn",0)>0,"full build actually exercises cross-spell effects")
func reward_checks():
	var rng=RandomNumberGenerator.new()
	for seed in range(100):
		rng.seed=seed
		var r=Rewards.draw(loader.values,Catalog.IDS,["quick_chant"],rng)
		check(r.error.is_empty() and r.ids.size()==3 and Catalog.valid_upgrades(r.ids),"unique legal rewards %d" % seed)
		check(r.ids.any(func(id): return Catalog.upgrade_spell(id)=="fireball") and r.ids.any(func(id): return Catalog.upgrade_spell(id)!="fireball"),"trained coverage and breadth %d" % seed)
		rng.seed=seed
		check(Rewards.draw(loader.values,Catalog.IDS,["quick_chant"],rng).ids==r.ids,"same seed choices %d" % seed)
	rng.seed=1
	var held=Catalog.FUTURE_UPGRADES.duplicate()
	held.erase("lamp_twin")
	held.erase("meteor_storm")
	var r=Rewards.draw(loader.values,Catalog.IDS,held,rng)
	check(r.ids.size()==2 and r.error.is_empty(),"small pool no duplicate fillers")
	r=Rewards.draw(loader.values,Catalog.IDS,Catalog.FUTURE_UPGRADES,rng)
	check(r.ids.is_empty() and r.error.is_empty(),"exhausted pool explicit skip")
	var c=loader.values.duplicate()
	for tier in ["common","rare","legendary"]: c["build."+tier+"_weight"]=0
	r=Rewards.draw(c,Catalog.IDS,[],rng)
	check(not r.error.is_empty(),"zero weight error terminates")
	c["build.common_weight"]=1
	r=Rewards.draw(c,Catalog.IDS,[],rng)
	check(r.ids.all(func(id): return Catalog.tier(id)=="common"),"zero rare tiers excluded")
	held=Catalog.FUTURE_UPGRADES.filter(func(id): return Catalog.upgrade_spell(id)=="fireball")
	r=Rewards.draw(loader.values,Catalog.IDS,held,rng)
	check(r.ids.size()==3 and r.ids.all(func(id): return Catalog.upgrade_spell(id)!="fireball"),"exhausted trained spell constraint lifted")
func flow_checks():
	var a=fresh([],0,true)
	var b=fresh([],0,true)
	var history=[]
	for wave in range(1,10):
		check(a.wave==wave and a.enemy_count==int(loader.layout.waves[wave-1].count),"flow wave content %d" % wave)
		a.player.health=77
		a.player.mana=3
		for e in a.enemies: e.health=0
		for e in b.enemies: e.health=0
		a.step(Battle.STEP)
		b.step(Battle.STEP)
		if wave==9:
			check(a.result=="success" and a.choice_history.size()==8,"last battle no reward")
			break
		check(a.result=="choice" and a.choices==b.choices,"flow reproducible rewards %d" % wave)
		var choices=a.choices.duplicate()
		var time=a.elapsed
		advance(a,1)
		check(a.elapsed==time and a.choices==choices,"choice freezes simulation and never rerolls")
		var invalid="invalid"
		a.choose(invalid)
		check(a.result=="choice" and a.wave==wave,"invalid reward rejected")
		a.fatal_used=true
		a.sync_ready_at=100
		a.spell_ready_at.fireball=100
		a.dodge_until=100
		Effects.add_shield(a,"lamp",4,8,4,99)
		Effects.lamp(a,Stats.compute(a.cfg,"lamp",a.owned),99)
		Effects.rejuvenation(a,Stats.compute(a.cfg,"rejuvenation",a.owned),98)
		Effects.meteor(a,Vector2.ZERO,Stats.compute(a.cfg,"meteor",a.owned),97)
		a.bullets.append({"id":96})
		a.echoes.append({"id":95})
		a.burns.append({"id":94})
		a.fields.append({"id":93})
		var selected=a.choices[0]
		a.choose(selected)
		b.choose(selected)
		history.append(selected)
		check(near(a.player.health,77) and near(a.player.mana,100) and a.owned==history,"retain health/upgrades restore mana")
		check(a.shield_total()==0 and a.lamp.is_empty() and not a.fatal_used and a.sync_ready_at==-INF and a.dodge_until==-INF and a.cooldown_remaining("fireball")==0,"wave resets transient abilities and gates")
		check(a.bullets.is_empty() and a.echoes.is_empty() and a.burns.is_empty() and a.fields.is_empty() and a.meteors.is_empty() and a.healing.is_empty(),"all queued old effects cleared at wave boundary")
	check(a.choice_history==b.choice_history,"full path reproducible")
	var retry=fresh([],0,true)
	check(retry.wave==1 and retry.owned.is_empty() and near(retry.player.health,100),"retry starts growth from scratch")
	retry.damage_player(1000)
	check(retry.result=="failure","flow death immediate")
	var c=loader.values.duplicate()
	for tier in ["common","rare","legendary"]: c["build."+tier+"_weight"]=0
	var bad=Battle.new(c,0,Catalog.IDS,loader.layout,1.5,[],true)
	for e in bad.enemies: e.health=0
	bad.step(Battle.STEP)
	check(bad.result=="config_error" and not bad.reward_error.is_empty(),"bad rewards terminate entire flow")
func record_checks():
	var b=fresh(["lamp_sync","heal_shield"])
	var e=dummy(b)
	cast(b,"lamp")
	b.aim=e.pos
	cast(b,"fireball")
	advance(b,1.5)
	cast(b,"rejuvenation")
	advance(b,1.1)
	b.damage_player(5)
	var records=preload("res://scripts/core/build_records.gd").new(loader.values,{"preset":"test","hash":loader.config_hash},"res://build/qa/build-trial/stage-b-test-sessions")
	records.finish(b)
	var sum=0.0
	var healing=0.0
	var absorbed=0.0
	for event in b.events:
		if event.kind=="damage": sum+=event.data.amount
		if event.kind=="heal": healing+=event.data.amount
		if event.kind=="shield_absorb": absorbed+=event.data.amount
	var report=JSON.parse_string(FileAccess.get_file_as_string(records.path+"-summary.json"))
	check(near(report.damage,sum) and near(report.heal,healing) and near(report.shield_absorbed,absorbed),"event totals reconcile summary")
	check(report.damage_by_kind.has("lamp_sync") and report.damage_by_kind.has("lamp_basic"),"summon contributions separate")
func config_checks():
	var raw=FileAccess.get_file_as_string("res://data/build_trial.csv")
	var hash_before=loader.config_hash
	var path="res://build/qa/build-trial/fixtures/stage-b.csv"
	var f=FileAccess.open(path,FileAccess.WRITE)
	f.store_string(raw.replace("build_upgrade.frost_freeze.freeze_lockout,4", "build_upgrade.frost_freeze.freeze_lockout,0.1"))
	f.close()
	check(not loader.load_all(Config.Base.PATH,path) and loader.config_hash==hash_before,"invalid freeze relationship rejected atomically")
	f=FileAccess.open(path,FileAccess.WRITE)
	f.store_string(raw.replace("build_upgrade.heal_spring.retained_health,1", "build_upgrade.heal_spring.retained_health,101"))
	f.close()
	check(not loader.load_all(Config.Base.PATH,path) and loader.config_hash==hash_before,"retained health out of range rejected")
	check(loader.load_all(),"restore config after boundary tests")
