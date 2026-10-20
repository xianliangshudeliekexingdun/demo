extends "res://scripts/core/trial_battle.gd"
const Catalog=preload("res://scripts/core/spell_catalog.gd")
const Effects=preload("res://scripts/core/build_effects.gd")
const Rewards=preload("res://scripts/core/build_rewards.gd")
const SpellStats=preload("res://scripts/core/spell_stats.gd")
var slots: Array=Catalog.IDS.duplicate()
var selected=0
var left_gate=false
var layout: Dictionary={}
var health_multiplier=1.5
var meteors: Array=[]
var fields: Array=[]
var shields: Dictionary={}
var freeze_seconds=0.0
var shield_absorbed=0.0
var fatal_used=false
var fatal_invulnerable_until=-INF
var sync_ready_at=-INF
var mana_low_seconds=0.0
var damage_kinds: Dictionary={}
var reward_error=""
var choice_history: Array=[]
var healing: Dictionary={}
var lamp: Dictionary={}
var cast_sources: Dictionary={}
var by_spell: Dictionary={}
var spell_ready_at: Dictionary={}
var heal_total=0.0
var overheal_total=0.0
var slow_seconds=0.0
func _init(config: Dictionary,count: int=0,order: Array=Catalog.IDS,spawn_layout: Dictionary={},multiplier: float=1.5,upgrades: Array=[],run: bool=false):
	var initial=config.duplicate(true)
	initial["trial.seed"]=config["build.seed"]
	super(initial,0,false)
	slots=order.duplicate() if Catalog.valid_loadout(order) else Catalog.IDS.duplicate()
	layout=spawn_layout.duplicate(true)
	health_multiplier=multiplier
	for id in Catalog.IDS:
		by_spell[id]={"started":0,"released":0,"cancels":0,"cooldown_blocked":0,"mana":0.0,"damage":0.0,"heal":0.0,"overheal":0.0}
		spell_ready_at[id]=0.0
	set_owned(upgrades)
	short_run=run
	if run: begin_wave()
	else: spawn(count)
func active_spell() -> String: return slots[selected]
func stats(enhanced: bool=false) -> Dictionary: return SpellStats.compute(cfg,active_spell(),owned,enhanced)
func cooldown_remaining(id: String) -> float:
	return maxf(0,spell_ready_at[id]-elapsed) if elapsed+EPS<spell_ready_at[id] else 0.0
func set_owned(ids: Array):
	if not Catalog.valid_upgrades(ids): return
	owned=ids.duplicate()
	cancel("upgrade_change")
	emit("upgrades_changed")
func spawn(count: int):
	enemies.clear()
	enemy_count=count
	for i in range(count):
		var point=layout.waves[wave-1].positions[i] if short_run else layout.free_positions[str(count)][i]
		var pos=Vector2(point[0],point[1])
		enemies.append({"id":i+1,"pos":pos,"health":cfg["enemy.health"]*health_multiplier,"max_health":cfg["enemy.health"]*health_multiplier,"state":"chase","until":0.0,"aim":Vector2.DOWN,"start":pos,"hit":false,"burn_at":-INF,"slow_until":-INF,"slow_multiplier":1.0,"slows":{},"freeze_until":-INF,"freeze_lockout":-INF,"exposure_until":-INF,"exposure":1.0})
func emit(kind: String,data: Dictionary={}):
	var d=data.duplicate(true)
	if not d.has("spell"): d["spell"]=active_spell()
	if by_spell.has(d.spell):
		var counters=by_spell[d.spell]
		match kind:
			"chant_started": counters.started+=1
			"released":
				counters.released+=1
				counters.mana+=d.stats.cost
			"cancel": counters.cancels+=1
			"cooldown_blocked": counters.cooldown_blocked+=1
			"damage": counters.damage+=d.amount
			"heal":
				counters.heal+=d.amount
				counters.overheal+=d.overheal
	super.emit(kind,d)
func command(kind: String,value: int=0): commands.append({"kind":kind,"value":value})
func select_slot(index: int):
	index=posmod(index,slots.size())
	if index==selected: return
	var dodging=phase=="dodging"
	cancel("switch")
	if dodging: phase="dodging"
	left_gate=held
	selected=index
	update_target()
	emit("selected",{"slot":selected})
func update_target():
	if not Catalog.targeted(active_spell()):
		target=player.pos
		range_clamped=false
		return
	var delta: Vector2=aim-player.pos
	range_clamped=delta.length()>stats().range
	target=player.pos+delta.limit_length(stats().range)
func press():
	if left_gate:
		held=true
		return
	if held: return
	# A rejected press is consumed; expiry never starts a cast automatically.
	if cooldown_remaining(active_spell())>0:
		held=true
		emit("cooldown_blocked",{"remaining":cooldown_remaining(active_spell())})
		return
	super.press()
func start_dodge(direction: Vector2):
	super.start_dodge(direction)
	if not saved.is_empty(): saved["spell_id"]=active_spell()
func pause():
	super.pause()
	left_gate=false
func shield_total() -> float:
	var total=0.0
	for shield in shields.values(): total+=shield.amount
	return total
func expire_shields():
	for source in shields.keys():
		if elapsed+EPS>=shields[source].until: shields.erase(source)
func damage_player(amount: float):
	if elapsed<dodge_start+cfg["dodge.invulnerable_time"]-EPS or elapsed<fatal_invulnerable_until-EPS or result!="playing": return
	expire_shields()
	var incoming=amount
	var sources=shields.keys()
	sources.sort_custom(func(a,b): return a<b if shields[a].until==shields[b].until else shields[a].until<shields[b].until)
	for source in sources:
		var shield=shields[source]
		var absorbed=minf(amount,shield.amount)
		amount-=absorbed
		shield.amount-=absorbed
		shield_absorbed+=absorbed
		emit("shield_absorb",{"spell":source,"amount":absorbed,"parent_cast_id":shield.id})
		if shield.amount<=0: shields.erase(source)
	var before=player.health
	if amount>=player.health and not fatal_used and not healing.is_empty() and elapsed<healing.until-EPS and Effects.has(healing.stats,"heal_spring"):
		fatal_used=true
		player.health=minf(before,Effects.param(healing.stats,"heal_spring","retained_health"))
		fatal_invulnerable_until=elapsed+Effects.param(healing.stats,"heal_spring","invulnerable_time")
		emit("fatal_protection",{"spell":"rejuvenation","parent_cast_id":healing.id})
		healing.clear()
	else: player.health=maxf(0,player.health-amount)
	player.flash=.25
	summary.hits+=1
	cancel("hit")
	left_gate=held
	emit("hit",{"damage":before-player.health,"shield":incoming-amount,"incoming":incoming})
	if player.health<=0: result="failure"
func release():
	if left_gate:
		held=false
		left_gate=false
		return
	if not held: return
	held=false
	if phase in ["dodging","resume_window"]: return
	if phase=="chanting":
		cancel("early_release")
		return
	if phase not in ["ready","charging_molten","ready_molten"]: return
	if cooldown_remaining(active_spell())>0:
		emit("cooldown_blocked",{"remaining":cooldown_remaining(active_spell())})
		cancel("cooldown")
		return
	var s=stats(phase=="ready_molten")
	if player.mana+EPS<s.cost:
		emit("mana_low")
		cancel("mana_low")
		return
	var id=next_id
	next_id+=1
	cast_sources[id]=active_spell()
	player.mana=maxf(0,player.mana-s.cost)
	spell_ready_at[active_spell()]=elapsed+s.cooldown
	summary.released+=1
	emit("released",{"cast_id":id,"target":target,"stats":s})
	match active_spell():
		"fireball": bullets.append({"id":id,"start":player.pos,"target":target,"born":elapsed,"due":elapsed+cfg["fireball.flight_time"],"stats":s.duplicate(true)})
		"meteor": Effects.meteor(self,target,s,id)
		"frost": Effects.nova(self,s,id)
		"rejuvenation": Effects.rejuvenation(self,s,id)
		"lamp": Effects.lamp(self,s,id)
	if active_spell() in ["fireball","meteor"]: Effects.sync(self,target,id)
	phase="idle"
	chant=0
	extra=0
	regen_at=elapsed+cfg["mana.regen_delay"]
func advance_chant(dt: float):
	if active_spell()=="fireball": super.advance_chant(dt)
	elif held and phase=="chanting":
		chant=minf(stats().chant,chant+dt)
		if chant+EPS>=stats().chant:
			phase="ready"
			emit("ready")
func damage_enemy(e: Dictionary,amount: float,source: int): hit_enemy(e,amount,source,"fireball_main")
func hit_enemy(e: Dictionary,amount: float,source: int,kind: String,trigger: int=0):
	if e.health<=0: return
	if kind in ["fireball_main","fireball_echo","meteor_main","meteor_fragment"] and elapsed<e.exposure_until:
		amount*=e.exposure
	var actual=minf(e.health,amount)
	e.health=maxf(0,e.health-amount)
	summary.damage+=actual
	damage_kinds[kind]=damage_kinds.get(kind,0.0)+actual
	emit("damage",{"enemy":e.id,"amount":actual,"source":source,"parent_cast_id":source,"trigger_cast_id":trigger,"source_kind":kind,"spell":cast_sources.get(source,"fireball")})
func update_enemies(dt: float,old_player: Vector2):
	for e in enemies:
		if e.health<=0: continue
		var frozen=maxf(0,minf(elapsed,e.freeze_until)-maxf(elapsed-dt,0))
		freeze_seconds+=frozen
		if frozen>0:
			e.until+=frozen
			if frozen>=dt-EPS: continue
		var effective=maxf(0,minf(elapsed,e.slow_until)-maxf(elapsed-dt,0))
		var multiplier=1.0
		if effective>0:
			slow_seconds+=effective
			multiplier=1-(1-e.slow_multiplier)*effective/dt
		else: e.slow_multiplier=1.0
		if not e.slows.is_empty(): Effects.refresh_slow(self,e)
		EnemyMotion.step(self,e,dt-frozen,old_player,multiplier)
func blast(pos: Vector2,s: Dictionary,id: int,secondary: bool=false):
	var radius=s.radius*(cfg["upgrade.echo.radius_multiplier"] if secondary else 1.0)
	var damage=s.damage*(cfg["upgrade.echo.damage_multiplier"] if secondary else 1.0)
	var hit=false
	for e in enemies:
		if e.health>0 and e.pos.distance_to(pos)<=radius+cfg["enemy.radius"]+.000001:
			hit_enemy(e,damage,id,"fireball_echo" if secondary else "fireball_main")
			hit=true
	effects.append({"pos":pos,"radius":radius,"until":elapsed+.3})
	emit("blast",{"source":id,"secondary":secondary,"hit":hit,"source_kind":"fireball_echo" if secondary else "fireball_main","spell":"fireball"})
	if secondary: return
	summary.landed+=1
	if hit: summary.hit_shots+=1
	if s.echo: echoes.append({"pos":pos,"stats":s.duplicate(true),"id":id,"due":elapsed+cfg["upgrade.echo.delay"]})
	if s.embers: Effects.add_burn(self,pos,s.radius*cfg["upgrade.embers.radius_multiplier"],cfg["upgrade.embers.duration"],cfg["upgrade.embers.tick_damage"],id)
func update_projectiles():
	for i in range(bullets.size()-1,-1,-1):
		var bullet=bullets[i]
		if elapsed+EPS>=bullet.due:
			blast(bullet.target,bullet.stats,bullet.id)
			bullets.remove_at(i)
	for i in range(echoes.size()-1,-1,-1):
		var echo=echoes[i]
		if elapsed+EPS>=echo.due:
			blast(echo.pos,echo.stats,echo.id,true)
			echoes.remove_at(i)
	Effects.update(self)
func step(dt: float,direction: Vector2=Vector2.ZERO):
	if paused or result!="playing": return
	var before=elapsed
	elapsed+=dt
	expire_shields()
	update_target()
	var input=commands.duplicate()
	commands.clear()
	# Dodge edges begin before movement, matching the original trial.
	for cmd in input:
		if cmd.kind=="dodge": start_dodge(direction)
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
	advance_chant(dt)
	for cmd in input:
		match cmd.kind:
			"slot": select_slot(cmd.value)
			"wheel": select_slot(selected+cmd.value)
			"press": press()
			"release": release()
			"cancel":
				held=false
				left_gate=false
				cancel("ui_release")
	if phase=="resume_window" and held and not left_gate and elapsed<=window_end+EPS: resume_cast(true)
	if phase in ["chanting","ready","charging_molten","ready_molten"]: regen_at=elapsed+cfg["mana.regen_delay"]
	elif elapsed>regen_at: player.mana=minf(cfg["mana.max"],player.mana+cfg["mana.regen_rate"]*minf(dt,elapsed-maxf(before,regen_at)))
	player.flash=maxf(0,player.flash-dt)
	update_projectiles()
	if player.mana+EPS<stats().cost: mana_low_seconds+=dt
	if short_run and enemies.all(func(e): return e.health<=0):
		cancel("wave_clear")
		held=false
		commands.clear()
		remainder=0
		if wave>=layout.waves.size():
			result="success"
			emit("result",{"result":result})
		else:
			result="choice"
			choices=draw_choices()
func draw_choices() -> Array:
	var reward=Rewards.draw(cfg,slots,owned,rng)
	reward_error=reward.error
	if not reward_error.is_empty():
		result="config_error"
		emit("config_error",{"reason":reward_error})
	emit("choices",{"candidates":reward.ids,"wave":wave})
	return reward.ids
func begin_wave():
	var row=layout.waves[wave-1]
	health_multiplier=row.health_multiplier
	bullets.clear()
	echoes.clear()
	burns.clear()
	effects.clear()
	meteors.clear()
	fields.clear()
	healing.clear()
	lamp.clear()
	shields.clear()
	fatal_used=false
	fatal_invulnerable_until=-INF
	sync_ready_at=-INF
	dodge_start=-INF
	dodge_until=-INF
	for id in Catalog.IDS: spell_ready_at[id]=0.0
	player.pos=Vector2.ZERO
	cancel("wave")
	held=false
	left_gate=false
	commands.clear()
	remainder=0
	result="playing"
	spawn(int(row.count))
	emit("wave_started",{"wave":wave,"count":enemy_count,"health_multiplier":health_multiplier})
func choose(id: String):
	if result!="choice" or (choices.is_empty() and not id.is_empty()) or (not choices.is_empty() and id not in choices) or id in owned: return
	if not id.is_empty(): owned.append(id)
	choice_history.append({"wave":wave,"candidates":choices.duplicate(),"chosen":id})
	emit("chosen",{"id":id,"wave":wave})
	choices.clear()
	wave+=1
	player.health=minf(cfg["player.health_max"],player.health+cfg["build.between_wave_heal"])
	player.mana=maxf(player.mana,cfg["mana.max"]*cfg["build.between_wave_mana_fraction"])
	begin_wave()
func report() -> Dictionary:
	var r=super.report()
	r["slots"]=slots.duplicate()
	r["by_spell"]=by_spell.duplicate(true)
	var remaining={}
	for id in Catalog.IDS: remaining[id]=cooldown_remaining(id)
	r["cooldowns"]=remaining
	r["heal"]=heal_total
	r["overheal"]=overheal_total
	r["slow_enemy_seconds"]=slow_seconds
	r["seed"]=cfg["build.seed"]
	r["enemy_count"]=enemy_count
	r["health_multiplier"]=health_multiplier
	r["phase"]="B"
	r["freeze_enemy_seconds"]=freeze_seconds
	r["shield_absorbed"]=shield_absorbed
	r["fatal_protections"]=events.filter(func(e): return e.kind=="fatal_protection").size()
	r["damage_by_kind"]=damage_kinds.duplicate()
	r["mana_low_seconds"]=mana_low_seconds
	r["choice_history"]=choice_history.duplicate(true)
	r["wave"]=wave
	r["short_run"]=short_run
	return r
