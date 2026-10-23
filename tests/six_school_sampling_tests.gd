extends SceneTree
## Pure probabilities plus real route reward transactions; no natural combat.
const Sampling = preload("res://scripts/core/route_spell_sampling.gd")
const Route = preload("res://scripts/core/courtyard_route_run.gd")
const First = preload("res://scripts/core/first_room_run.gd")
const OUT = "res://build/qa/six-school-sampling-20261021/sampling"
var checks: int = 0
var failures: Array = []
var bridge: Array = []
var policy = Sampling.new()
var source: Dictionary

func _initialize(): call_deferred("execute")
func check(value: bool, label: String):
	checks += 1
	if not value:
		failures.append(label)
		push_error("Six-school sampling: " + label)
func near(a: float, b: float) -> bool: return absf(a - b) < 0.0000001

func execute():
	source = JSON.parse_string(FileAccess.get_file_as_string(Sampling.SOURCE))
	check(policy.configure(source).ok, "production sampling source configures")
	known_probabilities()
	boundary_and_validation()
	actual_route_and_transactions()
	distribution_check()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	FileAccess.open(OUT + "/runtime_bridge.json", FileAccess.WRITE).store_string(JSON.stringify(bridge, "\t"))
	var hashes: Dictionary = {}
	for path in [Sampling.SOURCE, "res://scripts/core/route_spell_sampling.gd", "res://scripts/core/courtyard_route_run.gd", "res://tests/six_school_sampling_tests.gd"]: hashes[path] = FileAccess.get_sha256(path)
	FileAccess.open(OUT + "/results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"details":failures,"source_sha256":hashes,"scope":"Conditional probabilities, fixed-seed draws and actual legal route reward transactions. No natural route, pixels, performance or final balance."}, "\t"))
	print("SIX SCHOOL SAMPLING checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func definitions(main: int, other: int) -> Dictionary:
	var result: Dictionary = {}
	for i in main: result["M%02d" % i] = {"school":"fire"}
	for i in other: result["O%02d" % i] = {"school":"ice"}
	return result

func sum_values(values: Dictionary) -> float:
	var total: float = 0.0
	for value in values.values(): total += float(value)
	return total

func known_probabilities():
	for pair in [[10,50],[10,10],[6,2],[1,56],[0,20],[20,0],[0,0]]:
		var d: Dictionary = definitions(pair[0], pair[1])
		for level in range(4):
			var p: Dictionary = policy.probabilities(d.keys(),d,{},"fire",level)
			check(near(sum_values(p), 1.0 if not d.is_empty() else 0.0), "conditional sum %s/%d" % [pair,level])
			var actual: float = 0.0
			for id in p:
				check(float(p[id]) >= 0.0 and float(p[id]) <= 1.0, "probability bounds " + id)
				if str(d[id].school) == "fire": actual += float(p[id])
			var q: float = float(pair[0]) / d.size() if not d.is_empty() else 0.0
			var a: float = float(source.catalyst_affinity_by_level[level-1]) if level > 0 else 0.0
			var expected: float = q + (1.0-q)*a if pair[0] > 0 and pair[1] > 0 else q
			check(near(actual,expected), "known school mixture %s/%d" % [pair,level])
			bridge.append({"main":pair[0],"other":pair[1],"level":level,"main_probability":actual,"owned":0})
	var d: Dictionary = definitions(10,50)
	for level in range(1,4):
		check(near(float(policy.probabilities(d.keys(),d,{},"fire",level).M00)*10.0,[0.4,0.5,0.6][level-1]), "complete equal-pool40/50/60 benchmark")
	var owned: Dictionary = {"M00":1,"O00":2}
	var p: Dictionary = policy.probabilities(d.keys(),d,owned,"fire",2)
	check(near(float(p.M00)/float(p.M01),float(source.owned_upgrade_weight)), "held upgrade weight inside main school")
	check(near(float(p.O00)/float(p.O01),float(source.owned_upgrade_weight)), "held upgrade weight inside cross school")
	check(near(sum_values(p),1.0), "weighted owned pool normalized")
	var main_probability: float = 0.0
	for id in p:
		if str(d[id].school) == "fire": main_probability += float(p[id])
	bridge.append({"case":"weighted_owned", "main":10,"other":50,"level":2,"main_probability":main_probability,"owned":owned,"definitions":d,"probabilities":p})
	var reduced: Array = d.keys()
	reduced.erase("M00")
	var later: Dictionary = policy.probabilities(reduced,d,{},"fire",3)
	check(near(float(later.M01)*9.0,9.0/59.0+(1.0-9.0/59.0)*0.52), "remove then recompute next card")

func boundary_and_validation():
	var d: Dictionary = definitions(1,1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2891
	var before: int = rng.state
	check(policy.sample([],d,{},"fire",3,rng).is_empty() and rng.state == before, "empty pool consumes no RNG")
	var drawn: Array = policy.sample(["M00","M00","O00","missing"],d,{},"fire",3,rng)
	check(drawn.size()==2 and drawn[0].id != drawn[1].id, "sampler cannot duplicate IDs or draw missing definitions")
	var one: Array = policy.sample(["O00"],d,{},"fire",3,rng)
	check(one.size()==1 and near(float(one[0].draw_probability),1.0), "depleted main falls back to sole cross spell")
	for field in ["pity","reroll","new_or_upgrade_quota","affects_initial_offer","affects_artifact_quality"]:
		var invalid: Dictionary = source.duplicate(true)
		invalid[field] = true
		check(not Sampling.new().configure(invalid).ok, "reject undeclared special behavior " + field)
	for strength in [[0.4,0.28,0.52],[0.28,0.28,0.52],[0.28,0.4,1.0],[0.28,0.4,NAN]]:
		var invalid: Dictionary = source.duplicate(true)
		invalid.catalyst_affinity_by_level = strength
		check(not Sampling.new().configure(invalid).ok, "reject malformed affinity " + str(strength))
	for weight in [0.5,0.0,-1.0,NAN,INF]:
		var invalid: Dictionary = source.duplicate(true)
		invalid.owned_upgrade_weight = weight
		check(not Sampling.new().configure(invalid).ok, "reject invalid upgrade weight")
	for version in ["", 12, null]:
		var invalid: Dictionary = source.duplicate(true)
		invalid.version = version
		check(not Sampling.new().configure(invalid).ok, "metadata requires nonempty version")
	var extreme: Dictionary = source.duplicate(true)
	extreme.owned_upgrade_weight = 1e308
	extreme.baseline_spell_weight = 1e308
	var normalized = Sampling.new()
	check(normalized.configure(extreme).ok, "finite extreme weights accepted without common-scale overflow")
	var chances: Dictionary = normalized.probabilities(d.keys(), d, {"O00":1}, "fire", 3)
	check(near(sum_values(chances),1.0), "extreme weights stay normalized")
	for value in chances.values(): check(is_finite(float(value)) and float(value)>=0.0, "extreme weight probability finite")
	check(policy.rules == source, "validation never mutates production source")

func actual_route_and_transactions():
	for row in [["fire","MC04"],["ice","MC05"],["lightning","MC06"],["wind","MC07"],["earth","MC08"],["spirit","MC09"]]:
		for level in range(4):
			var snapshot: Dictionary = {"route_school":row[0],"equipment":{"catalyst":row[1] if level>0 else ""},"levels":{row[1]:level}}
			var run = Route.new()
			check(run.configure(snapshot,1029+level).ok,"six-school route configures "+str(row))
			check(run.initial_choices().map(func(c):return str(c.id)) == run._initial_spell_ids(),"catalyst rank never changes three independent starters")
			check(run.eligible_reward_ids().size()==57 and "R06" not in run.eligible_reward_ids() and "S05" not in run.eligible_reward_ids(),"prerequisites applied before all weights")
			var rng_state: int = run._rng.state
			var p: Dictionary = run.reward_probabilities()
			for _i in 3: run.get_snapshot()
			check(run._rng.state == rng_state,"snapshot and probability inspection preserve RNG")
			check(near(sum_values(p),1.0),"actual legal pool normalized")
			var main: float = 0.0
			for id in p:
				if str(run._base.spells[id].school)==str(row[0]): main += float(p[id])
			bridge.append({"school":row[0],"level":level,"main_probability":main,"pool":run.eligible_reward_ids(),"owned":[]})
			var cards: Array = run._sample_rewards()
			check(cards.size()==3 and cards.map(func(c):return c.id).size()==3,"actual three candidate offers")
			var ids: Dictionary = {}
			for card in cards:
				check(not ids.has(card.id) and card.id in run.eligible_reward_ids(),"sampled actual IDs legal and unique")
				ids[card.id] = true
				check(float(card.draw_probability)>0 and float(card.draw_probability)<=1.0,"actual conditional metadata")
	var run = Route.new()
	check(run.configure({"equipment":{"catalyst":"MC09"},"levels":{"MC09":3}},2901).ok and run.choose_initial("F01"),"cross-school catalyst independent from chosen fire starter")
	run.spells.clear()
	for id in ["F01","F03","F08","I01","I02","I03","W01","W02"]:
		var spell: Dictionary = run._new_spell(id)
		spell.level=3
		run.spells.append(spell)
	check(run.eligible_reward_ids().size()==49,"eight maxed slots keep all other qualified new IDs")
	run.phase="reward"
	run.reward_choices=run._sample_rewards()
	var cached: Array = run.reward_choices.duplicate(true)
	var rng_state: int = run._rng.state
	check(run.choose_reward(str(cached[0].id),run.room_revision),"full-slot actual new candidate requests replacement")
	var token: int = int(run.pending_replacement.request_id)
	check(run.cancel_spell_replacement(token,run.room_revision),"cancel actual replacement")
	check(run.reward_choices == cached and run._rng.state == rng_state,"cancel/reopen keeps exact cards and RNG")
	check(run.choose_reward(str(cached[0].id),run.room_revision) and run.confirm_spell_replacement(0,int(run.pending_replacement.request_id),run.room_revision),"actual replacement confirms once")
	check(str(run.spells[0].id)==str(cached[0].id) and int(run.spells[0].level)==1,"new selected spell resets to level1")
	check(not run.confirm_spell_replacement(0,token,run.room_revision),"stale replacement cannot consume twice")
	var weighted = Route.new()
	check(weighted.configure({"equipment":{"catalyst":"MC04"},"levels":{"MC04":2}},9921).ok and weighted.choose_initial("F01"),"weighted actual ownership fixture")
	weighted.spells.append(weighted._new_spell("I01"))
	var actual: Dictionary = weighted.reward_probabilities()
	var main_probability: float = 0.0
	for id in actual:
		if str(weighted._base.spells[id].school) == "fire": main_probability += float(actual[id])
	bridge.append({"case":"actual_weighted_owned","school":"fire","level":2,"main_probability":main_probability,"pool":weighted.eligible_reward_ids(),"owned":{"F01":1,"I01":1},"probabilities":actual})
	var old = First.new()
	check(old.configure({"equipment":{"catalyst":"MC04"},"levels":{"MC04":3}}).ok,"legacy standalone still configures")
	check(near(old.reward_weight("F01"),2.0),"standalone retains historical per-ID weighting")

func distribution_check():
	var d: Dictionary = definitions(10,50)
	for level in range(4):
		var rng := RandomNumberGenerator.new()
		rng.seed = 829710 + level
		var hits: int = 0
		var samples: int = 3000
		for _trial in samples:
			var cards: Array = policy.sample(d.keys(),d,{},"fire",level,rng)
			if str(cards[0].id).begins_with("M"): hits += 1
		var expected: float = [1.0/6.0,0.4,0.5,0.6][level]
		var tolerance: float = 6.0 * sqrt(expected*(1.0-expected)/samples)
		check(absf(float(hits)/samples-expected)<tolerance,"fixed-seed first-card frequency agrees with analytic probability rank"+str(level))
