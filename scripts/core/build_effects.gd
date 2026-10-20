extends RefCounted
# Effect queues use cast snapshots; only the controller's successful release calls sync.
static func param(s: Dictionary,id: String,key: String) -> float: return s["build_upgrade."+id+"."+key]
static func has(s: Dictionary,id: String) -> bool: return id in s.get("owned",[])
static func slow(b,e: Dictionary,duration: float,multiplier: float,source: String):
	e.slows[source]={"until":b.elapsed+duration,"multiplier":multiplier}
	refresh_slow(b,e)
static func refresh_slow(b,e: Dictionary):
	e.slow_until=-INF
	e.slow_multiplier=1.0
	for source in e.slows.keys():
		var status=e.slows[source]
		if status.until<=b.elapsed: e.slows.erase(source)
		else:
			e.slow_until=maxf(e.slow_until,status.until)
			e.slow_multiplier=minf(e.slow_multiplier,status.multiplier)
static func nova(b,s: Dictionary,id: int):
	for e in b.enemies:
		if e.health<=0 or e.pos.distance_to(b.player.pos)>s.radius+b.cfg["enemy.radius"]+b.EPS: continue
		slow(b,e,s.slow_duration,s.slow_multiplier,"nova")
		b.emit("slow",{"enemy":e.id,"cast_id":id,"until":e.slow_until})
		if has(s,"frost_freeze") and b.elapsed+b.EPS>=e.freeze_lockout:
			e.freeze_until=b.elapsed+param(s,"frost_freeze","freeze_duration")
			e.freeze_lockout=b.elapsed+param(s,"frost_freeze","freeze_lockout")
			b.emit("freeze",{"enemy":e.id,"cast_id":id,"until":e.freeze_until})
		if has(s,"frost_exposure"):
			e.exposure_until=b.elapsed+s.slow_duration
			e.exposure=param(s,"frost_exposure","damage_multiplier")
	if has(s,"frost_field"):
		b.fields.append({"id":id,"pos":b.player.pos,"radius":s.radius,"until":b.elapsed+param(s,"frost_field","duration"),"tick":b.elapsed,"stats":s.duplicate(true)})
	b.effects.append({"pos":b.player.pos,"radius":s.radius,"until":b.elapsed+.4,"color":"94dbff"})
static func add_shield(b,source: String,amount: float,cap: float,duration: float,cast_id: int):
	var old=b.shields.get(source,{"amount":0.0,"until":b.elapsed})
	var gain=minf(amount,maxf(0,cap-old.amount))
	if gain<=0: return
	b.shields[source]={"amount":old.amount+gain,"until":b.elapsed+duration,"id":cast_id}
	b.emit("shield_gain",{"spell":source,"amount":gain,"parent_cast_id":cast_id})
static func heal(b,amount: float,s: Dictionary,id: int):
	if b.result!="playing" or b.player.health<=0: return
	var actual=minf(amount,b.cfg["player.health_max"]-b.player.health)
	b.player.health+=actual
	b.heal_total+=actual
	b.overheal_total+=amount-actual
	b.emit("heal",{"spell":"rejuvenation","amount":actual,"overheal":amount-actual,"parent_cast_id":id})
	if has(s,"heal_shield"):
		add_shield(b,"rejuvenation",(amount-actual)*param(s,"heal_shield","overheal_multiplier"),param(s,"heal_shield","shield_cap"),param(s,"heal_shield","shield_duration"),id)
static func rejuvenation(b,s: Dictionary,id: int):
	var immediate=s.total_heal*param(s,"heal_immediate","immediate_fraction") if has(s,"heal_immediate") else 0.0
	b.healing={"id":id,"until":b.elapsed+s.duration,"tick":b.elapsed+s.tick_interval,"stats":s.duplicate(true),"tick_heal":(s.total_heal-immediate)/(s.duration/s.tick_interval)}
	if immediate>0: heal(b,immediate,s,id)
	b.effects.append({"pos":b.player.pos,"radius":.65,"until":b.elapsed+.4,"color":"a4dfaa"})
static func lamp(b,s: Dictionary,id: int):
	b.lamp={"id":id,"until":b.elapsed+s.duration,"tick":b.elapsed+s.attack_interval,"guard_tick":b.elapsed+param(s,"lamp_guard","interval"),"stats":s.duplicate(true)}
static func nearest(b,point: Vector2,radius: float):
	var candidates=b.enemies.filter(func(e): return e.health>0 and e.pos.distance_to(point)<=radius+b.EPS)
	candidates.sort_custom(func(a,c):
		var da=a.pos.distance_squared_to(point)
		var dc=c.pos.distance_squared_to(point)
		return a.id<c.id if is_equal_approx(da,dc) else da<dc)
	return null if candidates.is_empty() else candidates[0]
static func sync(b,target: Vector2,parent: int):
	if b.lamp.is_empty() or b.elapsed>=b.lamp.until: return
	var s=b.lamp.stats
	if not has(s,"lamp_sync") and not has(s,"lamp_twin"): return
	if b.elapsed+b.EPS<b.sync_ready_at: return
	var enemy=nearest(b,target,param(s,"lamp_sync","target_radius"))
	if enemy==null: return
	b.sync_ready_at=b.elapsed+param(s,"lamp_sync","trigger_interval")
	b.hit_enemy(enemy,param(s,"lamp_sync","damage"),b.lamp.id,"lamp_sync",parent)
	b.emit("lamp_attack",{"spell":"lamp","parent_cast_id":b.lamp.id,"trigger_cast_id":parent,"target":enemy.pos,"source_kind":"lamp_sync"})
static func add_burn(b,point: Vector2,radius: float,duration: float,damage: float,id: int):
	b.burns.append({"pos":point,"radius":radius,"id":id,"until":b.elapsed+duration,"tick":b.elapsed+b.cfg["upgrade.embers.tick_interval"],"damage":damage})
static func meteor(b,point: Vector2,s: Dictionary,id: int):
	var count=int(param(s,"meteor_storm","count")) if has(s,"meteor_storm") else 1
	var damage=s.damage*param(s,"meteor_storm","damage_multiplier") if has(s,"meteor_storm") else s.damage
	for i in range(count):
		b.meteors.append({"id":id,"target":point,"born":b.elapsed+i*param(s,"meteor_storm","interval"),"due":b.elapsed+s.fall_time+i*param(s,"meteor_storm","interval"),"stats":s.duplicate(true),"first":i==0,"damage":damage,"kind":"meteor_main"})
static func meteor_hit(b,m: Dictionary):
	var hit=false
	for e in b.enemies:
		if e.health>0 and e.pos.distance_to(m.target)<=m.stats.radius+b.cfg["enemy.radius"]+b.EPS:
			b.hit_enemy(e,m.damage,m.id,m.kind)
			hit=true
	if m.first:
		b.summary.landed+=1
		if hit: b.summary.hit_shots+=1
	b.effects.append({"pos":m.target,"radius":m.stats.radius,"until":b.elapsed+.3,"color":"ff9963"})
	b.emit("blast",{"source":m.id,"spell":"meteor","hit":hit,"source_kind":m.kind})
	if not m.first: return
	var s=m.stats
	if has(s,"meteor_fragments"):
		for i in range(int(param(s,"meteor_fragments","count"))):
			var angle=TAU*i/param(s,"meteor_fragments","count")
			var fragment=s.duplicate(true)
			fragment.radius=param(s,"meteor_fragments","radius")
			b.meteors.append({"id":m.id,"target":m.target+Vector2.from_angle(angle)*s.radius*param(s,"meteor_fragments","ring_multiplier"),"born":b.elapsed,"due":b.elapsed+param(s,"meteor_fragments","delay"),"stats":fragment,"first":false,"damage":s.damage*param(s,"meteor_fragments","damage_multiplier"),"kind":"meteor_fragment"})
	if has(s,"meteor_burn"):
		add_burn(b,m.target,s.radius*param(s,"meteor_burn","radius_multiplier"),param(s,"meteor_burn","duration"),param(s,"meteor_burn","tick_damage"),m.id)
static func update(b):
	for i in range(b.meteors.size()-1,-1,-1):
		var m=b.meteors[i]
		if b.elapsed+b.EPS<m.due: continue
		meteor_hit(b,m)
		b.meteors.remove_at(i)
	for i in range(b.fields.size()-1,-1,-1):
		var field=b.fields[i]
		if b.elapsed+b.EPS>=field.tick and field.tick<field.until-b.EPS:
			for e in b.enemies:
				if e.health>0 and e.pos.distance_to(field.pos)<=field.radius+b.cfg["enemy.radius"]+b.EPS:
					slow(b,e,param(field.stats,"frost_field","slow_linger"),field.stats.slow_multiplier,"field_%d" % field.id)
			field.tick+=param(field.stats,"frost_field","refresh_interval")
		if b.elapsed>=field.until: b.fields.remove_at(i)
	if not b.healing.is_empty():
		var h=b.healing
		if b.elapsed+b.EPS>=h.tick and h.tick<=h.until+b.EPS:
			heal(b,h.tick_heal,h.stats,h.id)
			h.tick+=h.stats.tick_interval
		if b.elapsed>h.until+b.EPS: b.healing.clear()
	if not b.lamp.is_empty():
		var l=b.lamp
		if b.elapsed+b.EPS>=l.tick and l.tick<=l.until+b.EPS:
			var e=nearest(b,b.player.pos,l.stats.range)
			if e!=null:
				b.hit_enemy(e,l.stats.damage,l.id,"lamp_basic")
				b.emit("lamp_attack",{"spell":"lamp","parent_cast_id":l.id,"target":e.pos,"source_kind":"lamp_basic"})
			l.tick+=l.stats.attack_interval
		if has(l.stats,"lamp_guard") and b.elapsed+b.EPS>=l.guard_tick and l.guard_tick<=l.until+b.EPS:
			add_shield(b,"lamp",param(l.stats,"lamp_guard","shield_gain"),param(l.stats,"lamp_guard","shield_cap"),param(l.stats,"lamp_guard","shield_duration"),l.id)
			l.guard_tick+=param(l.stats,"lamp_guard","interval")
		if b.elapsed>l.until+b.EPS: b.lamp.clear()
	# One shared burn gate per enemy, only due regions compete for this tick.
	var due=[]
	for region in b.burns:
		if b.elapsed+b.EPS>=region.tick and region.tick<=region.until+b.EPS:
			due.append(region)
			region.tick+=b.cfg["upgrade.embers.tick_interval"]
	for e in b.enemies:
		if e.health<=0 or b.elapsed+b.EPS<e.burn_at: continue
		var best=null
		for region in due:
			if b.elapsed>region.until+b.EPS or e.pos.distance_to(region.pos)>region.radius+b.cfg["enemy.radius"]+b.EPS: continue
			if best==null or region.damage>best.damage or (region.damage==best.damage and region.id<best.id): best=region
		if best!=null:
			b.hit_enemy(e,best.damage,best.id,"burn")
			e.burn_at=b.elapsed+b.cfg["upgrade.embers.tick_interval"]
	b.burns=b.burns.filter(func(region): return b.elapsed<=region.until+b.EPS)
	b.effects=b.effects.filter(func(fx): return b.elapsed<fx.until)
