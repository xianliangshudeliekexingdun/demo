extends RefCounted
const Config=preload("res://scripts/core/build_config.gd")
const Battle=preload("res://scripts/core/build_battle.gd")
const Catalog=preload("res://scripts/core/spell_catalog.gd")
const SpellStats=preload("res://scripts/core/spell_stats.gd")
const OldStats=preload("res://scripts/core/fireball_stats.gd")
const Records=preload("res://scripts/core/build_records.gd")
var checks=0
var failures=0
var loader
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		push_error("Build trial: "+message)
func near(a: float,b: float) -> bool: return absf(a-b)<.0001
func fresh(count: int=0): return Battle.new(loader.values,count,Catalog.IDS,loader.layout,1.5)
func advance(b,seconds: float,point: Vector2=Vector2(3,0)):
	for i in range(roundi(seconds*120)): b.advance(Battle.STEP,Vector2.ZERO,point)
func cast(b,id: String):
	b.select_slot(b.slots.find(id))
	b.command("press")
	advance(b,Battle.STEP)
	advance(b,b.stats().chant+Battle.STEP)
	b.command("release")
	advance(b,Battle.STEP)
func fixture(path: String,text: String):
	var f=FileAccess.open(path,FileAccess.WRITE)
	f.store_string(text)
func run() -> int:
	loader=Config.new()
	check(loader.load_all(),"default tables valid: "+loader.error)
	if loader.values.is_empty(): return failures+1
	check(Catalog.valid_loadout(Catalog.IDS),"five distinct spells")
	check(not Catalog.valid_loadout(["fireball"]),"reject missing slots")
	check(not Catalog.valid_loadout(["fireball","fireball","frost","rejuvenation","lamp"]),"reject duplicates")
	var reordered=Catalog.IDS.duplicate()
	reordered.reverse()
	var order_b=Battle.new(loader.values,0,reordered,loader.layout)
	check(order_b.active_spell()=="lamp","slot order respected")
	for mask in range(64):
		var ids=[]
		for i in range(6):
			if mask&(1<<i): ids.append(OldStats.IDS[i])
		var old=OldStats.compute(loader.values,ids)
		var s=SpellStats.compute(loader.values,"fireball",ids)
		for key in old: check(s[key]==old[key],"fireball property parity %d %s" % [mask,key])
	for id in Catalog.IDS:
		var b=fresh()
		b.select_slot(b.slots.find(id))
		b.command("press")
		advance(b,.2)
		var progress=b.chant
		b.command("dodge")
		advance(b,Battle.STEP)
		check(b.phase=="dodging","dodge starts "+id)
		advance(b,loader.values["dodge.duration"])
		check(b.phase=="chanting" and near(b.chant,progress),"auto resume same progress "+id)
		check(b.summary.released==0 and near(b.player.mana,100),"resume never release or spend "+id)
		check(near(b.cooldown_remaining(id),0),"dodge resume never starts cooldown "+id)
		advance(b,b.stats().chant)
		check(b.phase=="ready","ready "+id)
		advance(b,.4)
		check(b.summary.released==0,"holding never fires "+id)
		b.command("release")
		advance(b,Battle.STEP)
		check(b.summary.released==1 and near(b.by_spell[id].mana,b.stats().cost),"one successful release "+id)
		b.command("press")
		advance(b,Battle.STEP)
		check(b.phase=="idle" and b.cooldown_remaining(id)>0,"spell cooldown blocks repeat "+id)
		b=fresh()
		b.select_slot(b.slots.find(id))
		b.command("press")
		advance(b,.2)
		progress=b.chant
		b.command("dodge")
		advance(b,Battle.STEP)
		b.command("release")
		advance(b,.2)
		check(b.phase=="resume_window","released dodge opens manual window "+id)
		b.command("press")
		advance(b,Battle.STEP)
		check(b.phase=="chanting" and near(b.chant,progress),"manual resume preserves progress "+id)
	var b=fresh()
	b.command("press")
	advance(b,.3)
	var saved=b.chant
	b.command("slot",0)
	advance(b,Battle.STEP)
	check(b.chant>saved,"same slot does not cancel")
	b.command("slot",2)
	advance(b,Battle.STEP)
	check(b.phase=="idle" and b.left_gate,"held switching requires release")
	b.command("release")
	advance(b,Battle.STEP)
	check(not b.left_gate and b.summary.released==0,"switch release not an accidental cast")
	b.command("press")
	advance(b,Battle.STEP)
	check(b.phase=="chanting" and b.active_spell()=="frost","new spell starts from zero")
	b.command("dodge")
	advance(b,Battle.STEP)
	b.command("slot",3)
	advance(b,Battle.STEP)
	check(b.phase=="dodging" and b.saved.is_empty(),"switch preserves dodge but clears saved chant")
	advance(b,.3)
	check(b.phase=="idle","cannot resume wrong spell")
	b.command("release")
	advance(b,Battle.STEP)
	b.command("wheel",1)
	advance(b,Battle.STEP)
	check(b.selected==4,"wheel next")
	b.command("wheel",1)
	advance(b,Battle.STEP)
	check(b.selected==0,"wheel wraps")
	b.command("wheel",-1)
	advance(b,Battle.STEP)
	check(b.selected==4,"wheel wraps backwards")
	b=fresh()
	b.command("press")
	advance(b,.9)
	b.damage_player(15)
	b.command("release")
	advance(b,Battle.STEP)
	check(b.summary.released==0 and near(b.player.health,85),"actual hit wins before release")
	var same_frame=fresh(1)
	same_frame.phase="ready"
	same_frame.held=true
	same_frame.chant=same_frame.stats().chant
	var attacker=same_frame.enemies[0]
	attacker.pos=Vector2(-2,0)
	attacker.start=attacker.pos
	attacker.aim=Vector2.RIGHT
	attacker.state="attack"
	attacker.until=.01
	same_frame.command("release")
	advance(same_frame,Battle.STEP)
	check(same_frame.player.health==85 and same_frame.summary.released==0,"swept actual attack cancels queued release in same tick")
	b.player.mana=10
	b.command("press")
	advance(b,Battle.STEP)
	check(b.phase=="idle" and b.summary.released==0,"no mana no chant")
	advance(b,2)
	check(b.phase=="idle","holding insufficient mana never auto starts later")
	b=fresh()
	b.command("press")
	advance(b,.2)
	b.command("release")
	advance(b,Battle.STEP)
	check(near(b.player.mana,100) and b.phase=="idle","early release free cancel")
	b=fresh()
	cast(b,"fireball")
	var shot=b.bullets[0].duplicate(true)
	b.select_slot(2)
	advance(b,.2,Vector2(-6,0))
	check(b.bullets[0].target==shot.target,"switch and aim don't change in-flight shot")
	advance(b,.3)
	check(b.bullets.is_empty() and b.summary.landed==1,"fixed fireball flight")
	b=fresh()
	cast(b,"meteor")
	check(b.meteors.size()==1 and near(b.player.mana,65),"meteor spend on release")
	b.spawn(1)
	b.enemies[0].pos=Vector2(3,0)
	b.enemies[0].state="recover"
	b.enemies[0].until=100
	b.select_slot(2)
	advance(b,.6,Vector2(-6,0))
	check(near(b.enemies[0].health,90),"meteor waits for fixed fall")
	advance(b,.1)
	check(near(b.enemies[0].health,25) and near(b.by_spell.meteor.damage,65),"meteor hits locked point attributed correctly")
	b=fresh(1)
	b.player.pos=Vector2(0,-4)
	b.enemies[0].pos=Vector2(0,2.3)
	b.enemies[0].slow_until=1
	b.enemies[0].slow_multiplier=.55
	var old=b.enemies[0].pos
	b.step(.1)
	check(near(old.distance_to(b.enemies[0].pos),loader.values["enemy.chase_speed"]*.55*.1),"slow chase multiplier")
	check(near(b.cfg["enemy.chase_speed"],loader.values["enemy.chase_speed"]),"temporary chase speed restored")
	b=fresh(1)
	b.enemies[0].state="warning"
	b.enemies[0].until=100
	cast(b,"frost")
	check(b.enemies[0].slow_until>b.elapsed and b.enemies[0].state=="warning" and b.enemies[0].until==100,"nova preserves windup")
	var deadline=b.enemies[0].slow_until
	b.cfg["frost.cooldown"]=0
	b.spell_ready_at.frost=0
	cast(b,"frost")
	check(b.enemies[0].slow_until>deadline and near(b.enemies[0].slow_multiplier,.55),"recast refreshes no multiply")
	advance(b,3.1)
	check(near(b.enemies[0].slow_multiplier,1),"slow expires")
	b=fresh()
	b.player.health=50
	cast(b,"rejuvenation")
	advance(b,.9)
	check(near(b.player.health,50),"healing starts after one interval")
	advance(b,.2)
	check(near(b.player.health,56),"healing first tick")
	advance(b,4)
	check(near(b.player.health,80) and near(b.heal_total,30),"five ticks total budget")
	check(b.healing.is_empty(),"healing expires")
	b=fresh()
	b.player.health=50
	cast(b,"rejuvenation")
	advance(b,.7)
	b.cfg["rejuvenation.cooldown"]=0
	b.spell_ready_at.rejuvenation=0
	cast(b,"rejuvenation")
	check(near(b.player.health,56),"recast doesn't settle old remainder")
	advance(b,5.1)
	check(near(b.player.health,86) and near(b.heal_total,36),"recast retains old delivered tick only")
	b=fresh()
	cast(b,"rejuvenation")
	advance(b,5.1)
	check(near(b.heal_total,0) and near(b.overheal_total,30),"overheal separated")
	b=fresh()
	b.player.health=5
	cast(b,"rejuvenation")
	b.damage_player(15)
	advance(b,6)
	check(b.result=="failure" and b.player.health==0 and b.heal_total==0,"death prevents revival")
	b=fresh()
	cast(b,"lamp")
	b.spawn(2)
	for e in b.enemies:
		e.pos=Vector2(3,0)
		e.state="recover"
		e.until=100
	advance(b,1.1)
	check(near(b.summary.damage,0),"lamp waits initial interval")
	advance(b,.2)
	check(near(b.enemies[0].health,82) and near(b.enemies[1].health,90),"nearest tie stable id")
	check(near(b.by_spell.lamp.damage,8),"lamp damage not recent player spell")
	b.player.mana=100
	b.cfg["lamp.cooldown"]=0
	b.spell_ready_at.lamp=0
	cast(b,"lamp")
	var before=b.summary.damage
	advance(b,1.1)
	check(near(b.summary.damage,before),"replace restarts full attack interval")
	advance(b,.2)
	check(near(b.summary.damage,before+8),"new lamp attacks once")
	b=fresh()
	cast(b,"lamp")
	advance(b,3)
	b.spawn(1)
	b.enemies[0].pos=Vector2(3,0)
	b.enemies[0].state="recover"
	b.enemies[0].until=100
	advance(b,.1)
	check(b.summary.damage==0,"no stored attacks when target appears")
	advance(b,1.2)
	check(b.summary.damage==8,"next scheduled lamp attack")
	b=fresh()
	cast(b,"fireball")
	var due=b.bullets[0].due
	b.pause()
	advance(b,2)
	check(b.bullets.size()==1 and b.elapsed<due,"pause freezes shot")
	b.paused=false
	advance(b,.6)
	check(b.bullets.is_empty(),"resume continues already released shot")
	b=fresh()
	b.command("press")
	advance(b,.4)
	b.pause()
	check(b.phase=="idle" and not b.held and b.commands.is_empty(),"pause clears input and chant")
	cooldown_checks()
	config_checks()
	record_checks()
	print("Build trial: %d checks, %d failures" % [checks,failures])
	return failures
func cooldown_checks():
	for id in Catalog.IDS:
		var b=fresh()
		b.select_slot(b.slots.find(id))
		b.command("press")
		advance(b,.2)
		check(near(b.cooldown_remaining(id),0),"chant has no cooldown "+id)
		b.command("release")
		advance(b,Battle.STEP)
		check(near(b.cooldown_remaining(id),0),"early cancel has no cooldown "+id)
		b.command("press")
		advance(b,.2)
		b.damage_player(1)
		check(near(b.cooldown_remaining(id),0),"hit has no cooldown "+id)
		b.command("release")
		advance(b,Battle.STEP)
		cast(b,id)
		var duration=b.cfg[id+".cooldown"]
		check(near(b.cooldown_remaining(id),duration),"starts exactly at release "+id)
		var mana=b.player.mana
		b.command("press")
		advance(b,Battle.STEP)
		check(b.phase=="idle" and near(b.player.mana,mana) and b.by_spell[id].cooldown_blocked==1,"blocked once without spending "+id)
		advance(b,duration+.1)
		check(b.phase=="idle" and b.summary.released==1,"held expiry never auto chants "+id)
		b.command("release")
		advance(b,Battle.STEP)
		b.player.mana=100
		b.command("press")
		advance(b,Battle.STEP)
		check(b.phase=="chanting","fresh press after expiry "+id)
		b=fresh()
		cast(b,id)
		var deadline=b.spell_ready_at[id]
		b.select_slot((b.selected+1)%5)
		b.player.mana=100
		b.command("press")
		advance(b,Battle.STEP)
		check(b.phase=="chanting" and b.spell_ready_at[id]==deadline,"no global cooldown or switch reset "+id)
		var remaining=b.cooldown_remaining(id)
		b.pause()
		advance(b,20)
		check(near(b.cooldown_remaining(id),remaining),"pause freezes cooldown "+id)
		b=fresh()
		b.cfg[id+".cooldown"]=0
		cast(b,id)
		b.command("press")
		advance(b,Battle.STEP)
		check(b.phase=="chanting" and near(b.cooldown_remaining(id),0),"zero cooldown baseline "+id)
	var b=fresh()
	cast(b,"meteor")
	b.phase="ready"
	b.held=true
	var mana=b.player.mana
	b.command("release")
	advance(b,Battle.STEP)
	check(b.summary.released==1 and near(b.player.mana,mana),"release rechecks cooldown defensively")
	var reversed=Catalog.IDS.duplicate()
	reversed.reverse()
	b=Battle.new(loader.values,0,reversed,loader.layout)
	cast(b,"meteor")
	check(b.cooldown_remaining("meteor")>0 and near(b.cooldown_remaining("lamp"),0),"cooldown identity independent of slot order")
	check(fresh().cooldown_remaining("meteor")==0,"new session resets cooldown")
	b=fresh()
	cast(b,"meteor")
	var deadline=b.spell_ready_at.meteor
	b.elapsed=deadline-2*Battle.STEP
	b.command("press")
	b.step(Battle.STEP)
	check(b.phase=="idle" and b.by_spell.meteor.cooldown_blocked==1,"one step before expiry still blocked")
	b.release()
	b.command("press")
	b.step(Battle.STEP)
	check(b.phase=="chanting" and near(b.elapsed,deadline),"exact expiry accepts fresh press")
	b=fresh()
	cast(b,"meteor")
	advance(b,4.1)
	b.player.mana=0
	b.command("press")
	b.step(Battle.STEP)
	check(b.phase=="idle" and b.events[-1].kind=="mana_low","expired cooldown still checks mana separately")
func config_checks():
	DirAccess.make_dir_recursive_absolute("res://build/qa/build-trial/fixtures")
	var path="res://build/qa/build-trial/fixtures/config.csv"
	var raw=FileAccess.get_file_as_string("res://data/build_trial.csv")
	var good_hash=loader.config_hash
	fixture(path,raw.replace("meteor.cooldown,4", "meteor.cooldown,-1"))
	check(not loader.load_all(Config.Base.PATH,path) and loader.config_hash==good_hash,"negative cooldown rejected atomically")
	fixture(path,raw.replace("lamp.cooldown,12", "lamp.cooldown,121"))
	check(not loader.load_all(Config.Base.PATH,path) and loader.config_hash==good_hash,"oversize cooldown rejected atomically")
	fixture(path,raw+"meteor.mana_cost,35,float,点,0,1000,duplicate\n")
	check(not loader.load_all(Config.Base.PATH,path) and loader.config_hash==good_hash,"duplicate rejected atomically")
	fixture(path,raw.replace("meteor.mana_cost,35", "meteor.mana_cost,35.5").replace("float,点", "int,点"))
	check(not loader.load_all(Config.Base.PATH,path),"type mismatch rejected")
	fixture(path,raw.replace("frost.slow_multiplier,0.55","frost.slow_multiplier,9"))
	check(not loader.load_all(Config.Base.PATH,path),"schema cannot be bypassed by CSV range")
	fixture(path,raw.replace("rejuvenation.duration,5","rejuvenation.duration,5.5"))
	check(not loader.load_all(Config.Base.PATH,path),"heal duration must divide tick")
	fixture(path,raw.replace("meteor.mana_cost,35","meteor.mana_cost,101"))
	check(not loader.load_all(Config.Base.PATH,path),"shared mana upper bound")
	fixture(path,raw)
	var bad_base="res://build/qa/build-trial/fixtures/base.csv"
	fixture(bad_base,FileAccess.get_file_as_string(Config.Base.PATH).replace("mana.max,100.0","mana.max,0.0"))
	check(not loader.load_all(bad_base,path) and loader.config_hash==good_hash,"cross-file failure no partial adopt")
	var bad_waves="res://build/qa/build-trial/fixtures/waves.json"
	var w=loader.layout.duplicate(true)
	w.free_positions["1"]=[[0,0]]
	fixture(bad_waves,JSON.stringify(w))
	check(not loader.load_all(Config.Base.PATH,path,bad_waves),"unsafe spawn rejected")
	var bad_presets="res://build/qa/build-trial/fixtures/presets.json"
	var p=loader.presets.duplicate(true)
	p.frequency[1]=p.frequency[0]
	fixture(bad_presets,JSON.stringify(p))
	check(not loader.load_all(Config.Base.PATH,path,"res://data/build_trial_waves.json",bad_presets),"duplicate preset rejected")
	fixture(path,"\ufeff"+raw)
	check(loader.load_all(Config.Base.PATH,path),"UTF8 BOM supported")
	check(loader.load_all(),"restore default configuration")
func record_checks():
	var b=fresh()
	b.player.health=50
	cast(b,"rejuvenation")
	advance(b,5.1)
	var r=Records.new(loader.values,{"slots":b.slots,"hash":loader.config_hash},"res://build/qa/build-trial/test-sessions")
	r.finish(b)
	var report=JSON.parse_string(FileAccess.get_file_as_string(r.path+"-summary.json"))
	check(r.error.is_empty() and near(report.heal,30),"record summary reflects actual healing")
	check(report.by_spell.rejuvenation.released==1 and near(report.by_spell.rejuvenation.mana,26),"record mana and releases")
	check(report.hit_rate==null,"empty hit samples are null")
	var raw=FileAccess.get_file_as_string(r.path+".jsonl")
	check(raw.contains("parent_cast_id") and raw.contains(loader.config_hash),"event parent and config snapshot")
	var bad=Records.new(loader.values,{},"res://project.godot")
	check(not bad.error.is_empty(),"record path failure visible")
	b=fresh()
	cast(b,"fireball")
	check(b.summary.released==1,"record failure does not prevent gameplay")
	b.command("press")
	advance(b,Battle.STEP)
	check(b.report().by_spell.fireball.cooldown_blocked==1 and b.report().cooldowns.fireball>0,"cooldown summary contains rejection and remaining")
