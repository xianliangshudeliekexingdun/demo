extends RefCounted
const Stats = preload("res://scripts/core/fireball_stats.gd")
const EnemyMotion = preload("res://scripts/core/trial_enemy.gd")
const Legacy = preload("res://scripts/core/battle.gd")
const STEP = 1.0/120.0
const EPS = 0.00000001
var cfg: Dictionary
var player: Dictionary
var enemies: Array = []
var bullets: Array = []
var echoes: Array = []
var burns: Array = []
var effects: Array = []
var events: Array = []
var owned: Array = []
var elapsed = 0.0
var remainder = 0.0
var commands: Array = []
var phase = "idle"
var chant = 0.0
var extra = 0.0
var held = false
var saved: Dictionary = {}
var dodge_start = -INF
var dodge_end = -INF
var dodge_until = -INF
var dodge_direction = Vector2.RIGHT
var window_end = -INF
var regen_at = 0.0
var target = Vector2.ZERO
var aim = Vector2.ZERO
var range_clamped = false
var result = "playing"
var paused = false
var short_run = false
var wave = 1
var choices: Array = []
var rng = RandomNumberGenerator.new()
var next_id = 1
var enemy_count = 0
var summary: Dictionary = {"released":0,"landed":0,"hit_shots":0,"damage":0.0,"hits":0,"windows":0,"attempts":0,"resumed":0,"auto_resumed":0,"timeouts":0,"cancels":{}}

func _init(config: Dictionary,count: int=0,run: bool=false):
	cfg = config.duplicate(true)
	short_run = run
	rng.seed = cfg["trial.seed"]
	player = {"pos":Vector2.ZERO,"health":float(cfg["player.health_max"]),"mana":float(cfg["mana.max"]),"facing":1.0,"flash":0.0}
	spawn(int(cfg["trial.wave_1_count"]) if run else count)

func emit(kind: String,data: Dictionary={}):
	events.append({"time":elapsed,"kind":kind,"data":data.duplicate(true),"upgrades":owned.duplicate()})

func spawn(count: int):
	enemies.clear()
	bullets.clear()
	echoes.clear()
	burns.clear()
	effects.clear()
	enemy_count = count
	var sides = ["center"] if count==1 else (["left","right"] if count==2 else ["left","center","right"])
	for i in range(count):
		var pos = Vector2(cfg["trial.spawn_"+sides[i]+"_x"],cfg["trial.spawn_z"])
		enemies.append({"id":i+1,"pos":pos,"health":cfg["enemy.health"]*cfg["trial.wave_health_multiplier"],"state":"chase","until":0.0,"aim":Vector2.DOWN,"start":pos,"hit":false,"burn_at":-INF})

func stats(enhanced: bool=false) -> Dictionary: return Stats.compute(cfg,owned,enhanced)
func set_owned(ids: Array):
	owned.clear()
	for id in ids:
		if id in Stats.IDS and not id in owned: owned.append(id)
	cancel("upgrade_change")
	emit("upgrades_changed")
func queue(kind: String): commands.append(kind)
func cancel(reason: String):
	if phase!="idle" or not saved.is_empty():
		summary.cancels[reason] = summary.cancels.get(reason,0)+1
		emit("cancel",{"reason":reason})
	phase="idle"
	chant=0
	extra=0
	saved.clear()
	regen_at=elapsed+cfg["mana.regen_delay"]
func pause():
	paused=true
	cancel("pause")
	held=false
	commands.clear()
	remainder=0
func advance(dt: float,direction: Vector2,point: Vector2):
	if paused or result!="playing": return
	aim=point
	remainder+=minf(dt,0.1)
	while remainder+EPS>=STEP and result=="playing":
		step(STEP,direction)
		remainder-=STEP
func clip(pos: Vector2) -> Vector2: return Vector2(clampf(pos.x,-8.5,8.5),clampf(pos.y,-4.65,1.1))
func update_target():
	var delta: Vector2=aim-player.pos
	range_clamped=delta.length()>cfg["fireball.range"]
	target=player.pos+delta.limit_length(cfg["fireball.range"])
func start_dodge(direction: Vector2):
	if elapsed+EPS<dodge_until: return
	if phase in ["chanting","ready","charging_molten","ready_molten"]:
		saved={"phase":phase,"chant":chant,"extra":extra}
	else: saved.clear()
	phase="dodging"
	dodge_start=elapsed
	dodge_end=elapsed+cfg["dodge.duration"]
	dodge_until=elapsed+cfg["dodge.cooldown"]
	dodge_direction=direction.normalized()
	if dodge_direction.is_zero_approx(): dodge_direction=(aim-player.pos).normalized()
	if dodge_direction.is_zero_approx(): dodge_direction=Vector2(player.facing,0)
	regen_at=elapsed+cfg["mana.regen_delay"]
	emit("dodge")
func press():
	if held: return
	held=true
	if phase=="dodging": return
	if phase=="resume_window" and elapsed<=window_end+EPS:
		resume_cast(false)
		return
	if player.mana+EPS<stats().cost:
		emit("mana_low")
		return
	phase="chanting"
	chant=0
	extra=0
	regen_at=elapsed+cfg["mana.regen_delay"]
	emit("chant_started")
func resume_cast(automatic: bool):
	if saved.is_empty(): return
	summary.attempts+=1
	phase=saved.phase
	chant=saved.chant
	extra=saved.extra
	saved.clear()
	summary.resumed+=1
	if automatic: summary.auto_resumed+=1
	regen_at=elapsed+cfg["mana.regen_delay"]
	emit("resumed",{"automatic":automatic})
func advance_chant(dt: float):
	if not held: return
	var basic=stats()
	if phase=="chanting":
		chant=minf(basic.chant,chant+dt)
		if chant+EPS>=basic.chant:
			phase="ready"
			emit("ready")
	elif phase in ["ready","charging_molten"] and "molten" in owned:
		if player.mana+EPS>=stats(true).cost:
			phase="charging_molten"
			extra=minf(basic.extra_chant,extra+dt)
			if extra+EPS>=basic.extra_chant:
				phase="ready_molten"
				emit("molten_ready")
func release():
	if not held: return
	held=false
	if phase in ["dodging","resume_window"]: return
	if phase in ["ready","charging_molten","ready_molten"]:
		var s=stats(phase=="ready_molten")
		if player.mana+EPS>=s.cost:
			player.mana=maxf(0,player.mana-s.cost)
			bullets.append({"id":next_id,"start":player.pos,"target":target,"born":elapsed,"due":elapsed+cfg["fireball.flight_time"],"stats":s.duplicate(true)})
			next_id+=1
			summary.released+=1
			emit("released",{"target":target,"stats":s})
		else: emit("mana_low")
		phase="idle"
		chant=0
		extra=0
		regen_at=elapsed+cfg["mana.regen_delay"]
	elif phase=="chanting": cancel("early_release")
func damage_player(amount: float):
	if elapsed<dodge_start+cfg["dodge.invulnerable_time"]-EPS or result!="playing": return
	player.health=maxf(0,player.health-amount)
	player.flash=0.25
	summary.hits+=1
	cancel("hit")
	emit("hit",{"damage":amount})
	if player.health<=0: result="failure"
func damage_enemy(e: Dictionary,amount: float,source: int):
	if e.health<=0: return
	var actual=minf(e.health,amount)
	e.health=maxf(0,e.health-amount)
	summary.damage+=actual
	emit("damage",{"enemy":e.id,"amount":actual,"source":source})
func update_enemies(dt: float,old_player: Vector2):
	for e in enemies: EnemyMotion.step(self,e,dt,old_player)
func blast(pos: Vector2,s: Dictionary,id: int,secondary: bool=false):
	var radius=s.radius*(cfg["upgrade.echo.radius_multiplier"] if secondary else 1.0)
	var damage=s.damage*(cfg["upgrade.echo.damage_multiplier"] if secondary else 1.0)
	var hit=false
	for e in enemies:
		if e.health>0 and e.pos.distance_to(pos)<=radius+cfg["enemy.radius"]+0.000001:
			damage_enemy(e,damage,id)
			hit=true
	effects.append({"pos":pos,"radius":radius,"until":elapsed+0.3})
	emit("blast",{"source":id,"secondary":secondary,"hit":hit})
	if secondary: return
	summary.landed+=1
	if hit: summary.hit_shots+=1
	if s.echo: echoes.append({"pos":pos,"stats":s.duplicate(true),"id":id,"due":elapsed+cfg["upgrade.echo.delay"]})
	if s.embers: burns.append({"pos":pos,"radius":s.radius*cfg["upgrade.embers.radius_multiplier"],"id":id,"until":elapsed+cfg["upgrade.embers.duration"],"tick":elapsed+cfg["upgrade.embers.tick_interval"]})
func update_projectiles():
	for i in range(bullets.size()-1,-1,-1):
		var b=bullets[i]
		if elapsed+EPS>=b.due:
			blast(b.target,b.stats,b.id)
			bullets.remove_at(i)
	for i in range(echoes.size()-1,-1,-1):
		var b=echoes[i]
		if elapsed+EPS>=b.due:
			blast(b.pos,b.stats,b.id,true)
			echoes.remove_at(i)
	var due=false
	for b in burns:
		if elapsed+EPS>=b.tick and b.tick<=b.until+EPS:
			due=true
			b.tick+=cfg["upgrade.embers.tick_interval"]
	if due:
		for e in enemies:
			if e.health<=0 or elapsed+EPS<e.burn_at: continue
			for b in burns:
				if elapsed<=b.until+EPS and elapsed>=b.tick-cfg["upgrade.embers.tick_interval"]-EPS and e.pos.distance_to(b.pos)<=b.radius+cfg["enemy.radius"]:
					damage_enemy(e,cfg["upgrade.embers.tick_damage"],b.id)
					e.burn_at=elapsed+cfg["upgrade.embers.tick_interval"]
					break
	burns=burns.filter(func(b): return elapsed<=b.until+EPS)
	effects=effects.filter(func(e): return elapsed<e.until)
func step(dt: float,direction: Vector2=Vector2.ZERO):
	if paused or result!="playing": return
	var before=elapsed
	elapsed+=dt
	update_target()
	var input=commands.duplicate()
	commands.clear()
	if "dodge" in input: start_dodge(direction)
	var old_player: Vector2=player.pos
	if phase=="dodging":
		var movement_time=maxf(0,minf(elapsed,dodge_end)-maxf(before,dodge_start))
		player.pos=clip(player.pos+dodge_direction*cfg["dodge.distance"]*movement_time/cfg["dodge.duration"])
		if elapsed+EPS>=dodge_end:
			if saved.is_empty(): phase="idle"
			else:
				phase="resume_window"
				window_end=dodge_end+cfg["dodge.resume_window"]
				summary.windows+=1
				emit("resume_window")
	else:
		var slow=cfg["player.casting_move_multiplier"] if phase in ["chanting","ready","charging_molten","ready_molten"] else 1.0
		player.pos=clip(player.pos+direction.normalized()*cfg["player.move_speed"]*slow*dt)
	if direction.x!=0: player.facing=signf(direction.x)
	update_target()
	update_enemies(dt,old_player)
	if result=="failure": return
	if phase=="resume_window" and elapsed>window_end+EPS:
		summary.timeouts+=1
		cancel("resume_timeout")
	# Existing held cast accrues through this timestamp before release edges.
	advance_chant(dt)
	for command in input:
		match command:
			"press": press()
			"release": release()
			"cancel":
				held=false
				cancel("ui_release")
	# Resolve releases and actual hits first; holding never auto-fires a ready spell.
	if phase=="resume_window" and held and elapsed<=window_end+EPS:
		resume_cast(true)
	if phase in ["chanting","ready","charging_molten","ready_molten"]: regen_at=elapsed+cfg["mana.regen_delay"]
	elif elapsed>regen_at: player.mana=minf(cfg["mana.max"],player.mana+cfg["mana.regen_rate"]*minf(dt,elapsed-maxf(before,regen_at)))
	player.flash=maxf(0,player.flash-dt)
	update_projectiles()
	if short_run and enemies.all(func(e): return e.health<=0):
		if wave>=3: result="success"
		else:
			result="choice"
			choices=draw_choices()
		if result=="success": emit("result",{"result":result})
func draw_choices() -> Array:
	var pool=Stats.IDS.filter(func(id): return not id in owned)
	var selected=[]
	while selected.size()<cfg["choice.count"] and not pool.is_empty():
		var available={}
		var total=0.0
		for id in pool:
			var tier=Stats.TIERS[Stats.IDS.find(id)]
			available[tier]=cfg["choice."+tier+"_weight"]
		for weight in available.values(): total+=weight
		if total<=0:
			result="config_error"
			emit("config_error",{"reason":"剩余升级品质权重全部为零，请调整数值表并重开"})
			return []
		var pick=rng.randf()*total
		var tier_pick=""
		for tier in available:
			pick-=available[tier]
			if pick<=0:
				tier_pick=tier
				break
		var candidates=pool.filter(func(id): return Stats.TIERS[Stats.IDS.find(id)]==tier_pick)
		var chosen=candidates[rng.randi_range(0,candidates.size()-1)]
		selected.append(chosen)
		pool.erase(chosen)
	return selected
func choose(id: String):
	if result!="choice" or (not choices.is_empty() and not id in choices): return
	if not id.is_empty() and not id in owned: owned.append(id)
	emit("chosen",{"id":id})
	wave+=1
	player.health=minf(cfg["player.health_max"],player.health+cfg["trial.between_wave_heal"])
	player.mana=maxf(player.mana,cfg["mana.max"]*cfg["trial.between_wave_mana_fraction"])
	player.pos=Vector2.ZERO
	cancel("wave")
	held=false
	commands.clear()
	remainder=0
	result="playing"
	spawn(int(cfg["trial.wave_%d_count" % wave]))
func report() -> Dictionary:
	var r=summary.duplicate(true)
	r["duration"]=elapsed
	r["result"]=result
	r["upgrades"]=owned.duplicate()
	r["resume_rate"]=float(summary.resumed)/summary.attempts if summary.attempts>0 else null
	r["hit_rate"]=float(summary.hit_shots)/summary.landed if summary.landed>0 else null
	return r
