extends SceneTree
## Read-only actual current sampler bridge. Never runs combat, saves or a scene.
const First = preload("res://scripts/core/first_room_run.gd")
const OUT="res://build/qa/formal-spell-framework-20261018/runtime_fidelity.json"
var checks:=0
var failures: Array=[]
var rows: Array=[]
var before: Dictionary={}
const SOURCES=["res://scripts/core/first_room_run.gd","res://scripts/core/courtyard_route_run.gd","res://scripts/core/meta_progression.gd","res://data/balance_candidates/first_run_v1.json","res://data/balance_candidates/meta_growth_v1.json","res://data/courtyard_route.json","res://tools/balance/formal_spell_framework/runtime_fidelity.gd"]
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks+=1
	if not value:
		failures.append(label)
		push_error("Formal spell sampler fidelity: "+label)
func hashes() -> Dictionary:
	var result: Dictionary={}
	for path in SOURCES: result[path]=FileAccess.get_sha256(path)
	return result
func run():
	before=hashes()
	var parameters: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/balance/formal_spell_framework/parameters.json"))
	var trials: int=int(parameters.runtime_fidelity_trials_per_nonempty_case)
	var states: Array=[
		{"id":"fresh_starter","owned":{"F01":1}},
		{"id":"some_owned_and_one_max","owned":{"F01":2,"F04":1,"F02":3}},
		{"id":"full_slots_some_max","owned":{"F01":2,"F02":3,"F03":1,"F04":2,"F05":3,"F06":1,"F07":2,"F08":3}},
		{"id":"all_eight_max","owned":{"F01":3,"F02":3,"F03":3,"F04":3,"F05":3,"F06":3,"F07":3,"F08":3}}
	]
	for level in [0,1,2,3]:
		for state in states:
			var battle=First.new()
			var snapshot: Dictionary={"equipment":{"catalyst":"MC04"},"levels":{"MC04":level}}
			check(battle.configure(snapshot,20261017+level*100).ok,"actual current First.configure reads source")
			battle.spells.clear()
			for id in state.owned:
				var spell: Dictionary=battle._new_spell(str(id))
				spell.level=int(state.owned[id])
				battle._refresh_spell(spell)
				battle.spells.append(spell)
			var legal: Array=battle.eligible_reward_ids()
			var weights: Dictionary={}
			for id in battle._base.spells: weights[id]=battle.reward_weight(str(id))
			var histogram: Array=[0,0,0,0]
			var unique_legal:=true
			var before_player: Dictionary=battle.player.duplicate(true)
			for index in (trials if not legal.is_empty() else 1):
				var offered: Array=battle._sample_rewards()
				var selected: Dictionary={}
				var primary:=0
				for card in offered:
					if selected.has(card.id) or card.id not in legal: unique_legal=false
					selected[card.id]=true
					if card.id in battle._meta.catalysts.MC04.related_spells: primary+=1
				if offered.size()!=mini(legal.size(),3):unique_legal=false
				histogram[primary]+=1
			check(unique_legal,"actual sampler legal and without replacement "+str(state.id)+str(level))
			check(battle.player==before_player,"draw bias never adds player attack or combat stats")
			rows.append({"state":state.id,"owned":state.owned,"level":level,"legal":legal,"weights":weights,"primary_ids":battle._meta.catalysts.MC04.related_spells,"histogram":histogram,"trials":trials if not legal.is_empty() else 1,"unique_and_legal":unique_legal})
	check(hashes()==before,"current runtime/data never modified")
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	FileAccess.open(OUT,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"details":failures,"cases":rows,"source_sha256":before,"source_stable":hashes()==before,"engine":Engine.get_version_info(),"scope":"Headless read-only actual First sampler fixtures on the current ten fire spells and MC04 fire catalyst bias. No combat/scene/interactive game/save/account writes. Confirms the fire-side sampler baseline, not future school or two-pool implementation."},"\t"))
	print("FORMAL SPELL CURRENT SAMPLER FIDELITY: %d checks; %d failures" %[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
