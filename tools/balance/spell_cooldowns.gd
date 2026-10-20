extends SceneTree
# Reuses the real fixed-step rules. No enemies, movement, misses or human decisions.
# Repro: Godot --headless --path D:/demo --script res://tools/balance/spell_cooldowns.gd
const Config=preload("res://scripts/core/build_config.gd")
const Battle=preload("res://scripts/core/build_battle.gd")
const Catalog=preload("res://scripts/core/spell_catalog.gd")
const HORIZON=60.0
var failures=0
func _initialize(): call_deferred("run")
func verify(ok: bool):
	if not ok: failures+=1
func simulate(loader,order: Array,multiplier: float,reaction: float,unlimited: bool=false) -> Dictionary:
	var c=loader.values.duplicate(true)
	for id in Catalog.IDS: c[id+".cooldown"]*=multiplier
	if unlimited:
		c["mana.max"]=1000000.0
		c["mana.regen_rate"]=0.0
	var b=Battle.new(c,0,Catalog.IDS,loader.layout)
	var last_release=-INF
	var releases=[]
	var idle=0.0
	var cursor=0
	for tick in range(roundi(HORIZON/Battle.STEP)):
		if b.phase=="ready":
			b.command("release")
		elif b.phase=="idle" and b.elapsed>=last_release+reaction:
			for offset in range(order.size()):
				var id=order[(cursor+offset)%order.size()]
				if b.cooldown_remaining(id)==0 and b.player.mana>=c[id+".mana_cost"]:
					b.select_slot(b.slots.find(id))
					b.command("press")
					cursor=(cursor+offset+1)%order.size()
					break
		b.step(Battle.STEP)
		if b.phase=="idle": idle+=Battle.STEP
		while releases.size()<b.summary.released:
			last_release=b.elapsed
			releases.append({"time":b.elapsed,"spell":b.active_spell()})
		verify(b.player.mana>=-Battle.EPS and b.player.mana<=c["mana.max"]+Battle.EPS)
	var minimum=INF
	var previous={}
	for release in releases:
		var id=release.spell
		if previous.has(id):
			var gap=release.time-previous[id]
			minimum=minf(minimum,gap)
			verify(gap+Battle.EPS>=c[id+".cooldown"]+b.SpellStats.compute(c,id).chant)
		previous[id]=release.time
	return {"order":order,"cooldown_multiplier":multiplier,"reaction_seconds":reaction,"unlimited_mana":unlimited,"released":releases.size(),"min_same_spell_gap":minimum if is_finite(minimum) else null,"idle_seconds":idle,"by_spell":b.by_spell,"releases":releases}
func run():
	var loader=Config.new()
	if not loader.load_all():
		push_error(loader.error)
		quit(1)
		return
	var cases=[]
	for id in Catalog.IDS:
		for multiplier in [0.0,.5,1.0,1.5]:
			cases.append(simulate(loader,[id],multiplier,0.0))
		var known=simulate(loader,[id],1.0,0.0,true)
		var theoretical=loader.values[id+".cooldown"]+loader.values[id+".chant_time"]
		verify(absf(known.min_same_spell_gap-theoretical)<=3*Battle.STEP)
		cases.append(known)
	for reaction in [0.0,.15,.4]:
		for multiplier in [0.0,1.0]: cases.append(simulate(loader,Catalog.IDS,multiplier,reaction))
	var path="res://build/qa/build-trial/cooldown-balance.json"
	var output={"model_version":"cooldown-runtime-1","config_hash":loader.config_hash,"config":loader.values,"horizon":HORIZON,"seed":loader.values["build.seed"],"failures":failures,"cases":cases,"limitations":"No enemies or human tactics; rotation scans affordable ready spells, cannot predict fun, survival or combat balance."}
	var f=FileAccess.open(path,FileAccess.WRITE)
	if f==null:
		quit(1)
		return
	f.store_string(JSON.stringify(output,"\t"))
	print("COOLDOWN_BALANCE cases=",cases.size()," failures=",failures)
	for row in cases:
		if row.cooldown_multiplier in [0.0,1.0] and row.reaction_seconds==0:
			print(row.order," cd=",row.cooldown_multiplier," casts=",row.released," gap=",row.min_same_spell_gap," idle=",snappedf(row.idle_seconds,.01)," unlimited=",row.unlimited_mana)
	quit(failures)
