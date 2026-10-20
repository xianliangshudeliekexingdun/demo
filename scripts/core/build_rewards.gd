extends RefCounted
const Catalog=preload("res://scripts/core/spell_catalog.gd")
static func weighted(c: Dictionary,pool: Array,rng: RandomNumberGenerator) -> String:
	var tiers=[]
	var total=0.0
	for tier in ["common","rare","legendary"]:
		if pool.any(func(id): return Catalog.tier(id)==tier) and c["build."+tier+"_weight"]>0:
			tiers.append(tier)
			total+=c["build."+tier+"_weight"]
	if total<=0: return ""
	var roll=rng.randf()*total
	var chosen=tiers[-1]
	for tier in tiers:
		roll-=c["build."+tier+"_weight"]
		if roll<=0:
			chosen=tier
			break
	var options=pool.filter(func(id): return Catalog.tier(id)==chosen)
	return options[rng.randi_range(0,options.size()-1)]
static func draw(c: Dictionary,slots: Array,owned: Array,rng: RandomNumberGenerator) -> Dictionary:
	var pool=Catalog.FUTURE_UPGRADES.filter(func(id): return not id in owned and Catalog.upgrade_spell(id) in slots)
	var ids=[]
	if pool.is_empty(): return {"ids":ids,"error":""}
	if pool.all(func(id): return c["build."+Catalog.tier(id)+"_weight"]<=0): return {"ids":ids,"error":"剩余升级品质权重全部为零，请调整参数并重开"}
	pool=pool.filter(func(id): return c["build."+Catalog.tier(id)+"_weight"]>0)
	var trained=[]
	var weights={}
	for spell in slots:
		var count=owned.filter(func(id): return Catalog.upgrade_spell(id)==spell).size()
		if count>0 and pool.any(func(id): return Catalog.upgrade_spell(id)==spell and c["build."+Catalog.tier(id)+"_weight"]>0):
			trained.append(spell)
			weights[spell]=count+1
	var restricted=[]
	if not trained.is_empty():
		var sum=0.0
		for weight in weights.values(): sum+=weight
		var roll=rng.randf()*sum
		var chosen=trained[-1]
		for spell in trained:
			roll-=weights[spell]
			if roll<=0:
				chosen=spell
				break
		restricted=pool.filter(func(id): return Catalog.upgrade_spell(id)==chosen)
	while ids.size()<int(c["build.choice_count"]) and not pool.is_empty():
		var sub=restricted if ids.is_empty() and not restricted.is_empty() else pool
		if ids.size()==1: sub=pool.filter(func(id): return Catalog.upgrade_spell(id)!=Catalog.upgrade_spell(ids[0]))
		var id=weighted(c,sub,rng)
		if id.is_empty(): id=weighted(c,pool,rng)
		if id.is_empty(): return {"ids":[],"error":"剩余升级品质权重全部为零，请调整参数并重开"}
		ids.append(id)
		pool.erase(id)
	return {"ids":ids,"error":""}
