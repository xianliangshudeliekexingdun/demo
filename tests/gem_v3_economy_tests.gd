extends RefCounted
## Production account transactions with isolated user://tests saves only.
const Meta = preload("res://scripts/core/meta_progression.gd")
const Gems = preload("res://scripts/core/magic_gems.gd")
const ROOT = "user://tests/meta_progression/gem_v3/"
const OUT = "res://build/qa/gem-v3-implementation-20261022/economy/"
var checks: int = 0
var failures: Array = []
var result: Dictionary = {}
var paths: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("Gem v3 economy: "+label)

func save(path: String, value: Dictionary) -> void:
	assert(path.begins_with(ROOT) and ".." not in path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(value))
	if path not in paths: paths.append(path)

func account(name: String):
	var path: String = ROOT+name+".json"
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	paths.append(path)
	var meta = Meta.new(path)
	check(meta.load_state().ok,"isolated account loads "+name)
	var seeded: Dictionary = meta.get_state()
	var rng = RandomNumberGenerator.new()
	rng.seed = 20261022
	seeded.gem_state.rng_state = str(rng.state)
	save(path,seeded)
	check(meta.load_state().ok,"fixed-seed fixture reloads "+name)
	return meta

func funded(meta, dust: int = 1000, essence: int = 1000) -> void:
	var state: Dictionary = meta.get_state()
	state.dust = dust
	state.gem_state.essence = essence
	save(meta.save_path,state)
	check(meta.load_state().ok,"funded fixture reloads")

func transactions() -> void:
	var meta = account("transactions")
	check(meta.gems.rules.cores.size()==10 and meta.gems.rules.affixes.size()==8,"ten cores and eight attributes from runtime data")
	var original_gate: float = float(meta.gems.rules.cores.lightning.charge_gate)
	meta.gems.rules.cores.lightning.charge_gate = .73
	check("0.73秒充荷门" in meta.gems.core_description("lightning"),"core description derives changed runtime numeric field")
	meta.gems.rules.cores.lightning.charge_gate = original_gate
	check("最多6层" in meta.gems.legacy_core_description("inferno") and "每4跳" in meta.gems.core_description("inferno"),"old paid choice describes old mechanism separately from new core")
	check(meta.request_unlock_core("inferno").ok and meta.get_state().dust==0,"first directed core free and equipped")
	check(meta.gems.core_id(meta.get_state().gem_state)=="inferno","virtual core slot resolves")
	check(not meta.request_unlock_core("inferno").ok and not meta.request_unlock_core("unknown").ok,"duplicate/unknown core rejected")
	for stat in ["attack","attack","cdr"]: check(meta.claim_starter_attribute(stat).ok,"self chosen starter supports repeated main "+stat)
	check(not meta.claim_starter_attribute("shield").ok,"exactly three starter attributes")
	var state: Dictionary = meta.get_state()
	check(meta.gems.totals(state.gem_state).attack==8 and meta.gems.totals(state.gem_state).cdr==.02,"starting main values count exactly once")
	check(not meta.request_equip_gem(0,str(state.gem_state.slots[1])).ok and not meta.request_equip_gem(1,"core:inferno").ok,"core and attribute slot types enforced")
	funded(meta)
	var before: Dictionary = meta.get_state()
	check(meta.request_unlock_core("wind").ok and meta.get_state().dust==int(before.dust)-30,"second specified core costs30")
	check(meta.request_equip_core("wind").ok,"unlocked core switches free")
	for id in meta.gems.rules.cores:
		if id not in meta.get_state().gem_state.unlocked_cores: check(meta.request_unlock_core(str(id)).ok,"all ten core directions obtainable "+str(id))
	before = meta.get_state()
	var ten: Dictionary = meta.request_draw_gems(10)
	check(ten.ok and ten.gems.size()==10 and meta.get_state().dust==int(before.dust)-50,"ten draw exact price and count")
	var purple: bool = false
	for gem in ten.gems:
		purple = purple or gem.rarity=="purple"
		check(gem.rarity in ["green","blue","purple"] and str(gem.core).is_empty(),"draw pool excludes cores")
		for index in gem.affixes.size(): check(gem.affixes[index].role==("main" if index==0 else "side"),"generated main/side roles")
	check(purple,"ten draw guarantees purple")
	var singles = account("singles")
	save(singles.save_path,before)
	check(singles.load_state().ok,"same RNG fixture")
	for index in 10: check(singles.request_draw_gems(1).ok,"single draw commits")
	check(singles.get_state()==meta.get_state(),"ten equals ten singles including RNG and pity")
	var reload = Meta.new(meta.save_path)
	check(reload.load_state().ok and reload.get_state()==meta.get_state(),"restart preserves all gem progress")
	var run: Dictionary = meta.begin_playable_run("route45")
	check(run.ok and run.snapshot.gem_core=="wind","run locks chosen core snapshot")
	before = meta.get_state()
	check(not meta.request_unlock_core("earth").ok and not meta.request_craft_gem("green","health").ok and not meta.request_equip_core("aegis").ok and meta.get_state()==before,"in-run transactions blocked without spending")
	check(meta.settle_playable_run(run.run_id,[]).ok,"empty run settles without milestones")
	var blocked: String = ROOT+"block"
	FileAccess.open(blocked,FileAccess.WRITE).store_string("not a directory")
	paths.append(blocked)
	meta.save_path = blocked+"/invalid.json"
	before = meta.get_state()
	check(not meta.request_craft_gem("purple","attack").ok and meta.get_state()==before,"failed save preserves expense RNG and instance")
	meta.save_path = ROOT+"transactions.json"

func workshop() -> void:
	var meta = account("workshop")
	funded(meta)
	var craft: Dictionary = meta.request_craft_gem("green","attack")
	check(craft.ok and meta.get_state().gem_state.essence==997,"craft green3 chooses main")
	var id: String = str(craft.gem_id)
	var original: Dictionary = meta.gems.find(meta.get_state().gem_state,id)
	check(original.affixes==[meta.gems.line("attack",1,true)],"craft all initial rows I")
	check(meta.request_raise_gem_affix(id,0).ok and meta.request_raise_gem_affix(id,0).ok and not meta.request_raise_gem_affix(id,0).ok,"main deterministic tier8/16 and III cap")
	check(meta.get_state().gem_state.essence==973,"main exact tier cost")
	check(meta.request_upgrade_gem(id).ok and meta.request_upgrade_gem(id).ok,"green8 then blue20 to purple")
	var gem: Dictionary = meta.gems.find(meta.get_state().gem_state,id)
	check(gem.rarity=="purple" and gem.affixes[0]==meta.gems.line("attack",3,true) and gem.affixes[1].tier==1 and gem.affixes[2].tier==1,"upgrade preserves old tier and adds I side")
	check(meta.get_state().gem_state.essence==945 and not meta.request_upgrade_gem(id).ok,"upgrade exact cost and max cap")
	check(meta.request_raise_gem_affix(id,1).ok and meta.request_raise_gem_affix(id,1).ok and meta.get_state().gem_state.essence==927,"side deterministic tier6/12")
	var before: Dictionary = meta.get_state()
	check(not meta.request_reforge(id,"affix",0).ok and meta.get_state()==before,"main cannot randomly change")
	check(meta.request_reforge(id,"affix",1).ok,"side random retype opens durable choice")
	var pending: Dictionary = meta.get_state().gem_state.pending_reforge
	check(pending.cost==5 and pending.candidate.tier==3 and pending.candidate.stat!=pending.old.stat,"random type reforge costs5 and preserves tier")
	var reload = Meta.new(meta.save_path)
	check(reload.load_state().ok and reload.get_state()==meta.get_state(),"pending choice and RNG persist restart")
	before = reload.get_state()
	check(not reload.request_craft_gem("purple","health").ok and reload.get_state()==before,"pending blocks second spend without mutation")
	var old_values: Dictionary = reload.gems.totals(before.gem_state)
	var held_run: Dictionary = reload.begin_playable_run("route45")
	check(held_run.ok and held_run.snapshot.gem_bonuses==old_values,"modern pending may start with original equipped values")
	check(not reload.resolve_reforge(int(pending.token),true).ok and reload.get_state().gem_state.pending_reforge==pending,"in-run pending cannot alter the frozen equipment")
	check(reload.settle_playable_run(held_run.run_id,[]).ok,"pending run settles and unlocks original choice")
	check(reload.resolve_reforge(int(pending.token),false).ok,"keep original consumes paid choice once")
	check(reload.gems.find(reload.get_state().gem_state,id).affixes[1]==pending.old and reload.get_state().gem_state.essence==922,"keep original no refund and unchanged row")
	check(not reload.resolve_reforge(int(pending.token),true).ok,"choice token cannot repeat")
	gem = reload.gems.find(reload.get_state().gem_state,id)
	var desired: String = ""
	for stat in reload.gems.rules.affixes:
		var used: bool = false
		for affix in gem.affixes: used = used or affix.stat==stat
		if not used: desired = str(stat); break
	check(reload.request_retype_gem(id,1,desired).ok,"direct type choice succeeds")
	gem = reload.gems.find(reload.get_state().gem_state,id)
	check(gem.affixes[1]==reload.gems.line(desired,3,false) and reload.get_state().gem_state.essence==897,"direct25 preserves III value")
	check(reload.request_lock_gem(id).ok and not reload.request_raise_gem_affix(id,2).ok and not reload.request_salvage_gems([id]).ok,"lock protects upgrade and salvage")
	check(reload.request_lock_gem(id).ok and reload.request_equip_gem(1,id).ok and not reload.request_salvage_gems([id]).ok,"equipped protects salvage")
	check(reload.request_equip_gem(1,"").ok,"unequip attribute")
	check(reload.request_salvage_gems([id]).essence_gained==10,"purple base salvage10 no tier refund")
	check(reload.get_state().gem_state.essence==907,"workshop complete ledger")
	for rarity in ["green","blue","purple"]:
		craft = reload.request_craft_gem(rarity,"health")
		check(craft.ok,"direct craft each quality "+rarity)
		gem = reload.gems.find(reload.get_state().gem_state,str(craft.gem_id))
		var used: Array = []
		for affix in gem.affixes:
			check(affix.tier==1 and affix.stat not in used,"craft initial tiers and no duplicate type")
			used.append(affix.stat)

func milestones() -> void:
	var meta = account("milestones")
	for count in [0,15,15,30]:
		var run: Dictionary = meta.begin_playable_run("route45")
		var rooms: Array = []
		for index in count: rooms.append(index+1)
		var settle: Dictionary = meta.settle_playable_run(run.run_id,rooms)
		check(settle.ok,"real clear ledger settles "+str(count))
		var before: Dictionary = meta.get_state()
		check(meta.settle_playable_run(run.run_id,rooms).already_settled and meta.get_state()==before,"same settlement is idempotent")
	check(meta.get_state().gem_state.cumulative_cleared==60 and meta.get_state().gem_state.essence==24,"split clears grant exactly24 once")
	check(meta.get_state().gem_state.milestone_claimed==[15,30],"milestone receipt stores both thresholds")
	var merged = account("milestone_merged")
	var run: Dictionary = merged.begin_playable_run("route45")
	var rooms: Array = []
	for index in 30: rooms.append(index+1)
	check(merged.settle_playable_run(run.run_id,rooms).essence_earned==24,"merged30 grants same24")
	check(merged.begin_run().ok and merged.end_run().ok and merged.get_state().gem_state.cumulative_cleared==30,"preview never progresses milestones")
	var failed = account("milestone_failed_save")
	run = failed.begin_playable_run("route45")
	var before: Dictionary = failed.get_state()
	var blocker: String = ROOT+"milestone_blocker"
	FileAccess.open(blocker,FileAccess.WRITE).store_string("not a directory")
	paths.append(blocker)
	failed.save_path = blocker+"/save.json"
	check(not failed.settle_playable_run(run.run_id,rooms).ok and failed.get_state()==before and failed.is_in_run(),"failed settlement preserves unclaimed milestones and active token")
	failed.save_path = ROOT+"milestone_failed_save.json"
	check(failed.settle_playable_run(run.run_id,rooms).essence_earned==24 and failed.get_state().gem_state.essence==24,"failed settlement retry credits exactly once")

func old_gem(serial: int, core: String = "", rarity: String = "gold") -> Dictionary:
	var lib = Gems.new()
	var affixes: Array = []
	for stat in ["attack","health","shield"].slice(0,int(lib.rules.legacy_affix_counts[rarity])):
		var line: Dictionary = lib.line(str(stat),1,false)
		line.erase("role")
		affixes.append(line)
	return {"id":"gem-%d"%serial,"serial":serial,"rarity":rarity,"core":core,"affixes":affixes,"locked":serial==1}

func old_state(meta) -> Dictionary:
	var state: Dictionary = meta.get_state()
	state.version = Meta.EIGHT_CORE_SAVE_VERSION
	state.gem_state = {"inventory":[],"slots":["","","",""],"serial":0,"draws":0,"gold_misses":0,"rare_misses":0,"first_gold":true,"rng_state":"1234567","essence":0,"salvaged":0,"work_serial":0,"pending_reforge":{}}
	return state

func migration() -> void:
	var meta = account("migration")
	var source: Dictionary = old_state(meta)
	for core in ["inferno","reactor","stride","inferno"]:
		source.gem_state.serial += 1
		source.gem_state.draws += 1
		source.gem_state.inventory.append(old_gem(int(source.gem_state.serial),core))
	source.gem_state.first_gold = false
	source.gem_state.slots = ["gem-1","gem-2","gem-3","gem-4"]
	save(meta.save_path,source)
	var bytes: String = FileAccess.get_file_as_string(meta.save_path)
	check(meta.load_state().ok,"v5 eight-core save migrates in memory")
	check(FileAccess.get_file_as_string(meta.save_path)==bytes,"read migration does not rewrite old file")
	var state: Dictionary = meta.get_state()
	check(state.version==Meta.SAVE_VERSION and state.gem_state.inventory.size()==4,"migration keeps every attribute asset")
	check(state.gem_state.unlocked_cores==["inferno"] and state.gem_state.core_choice_credits==2 and state.gem_state.essence==20,"removed directions grant choices and repeated core20")
	check(state.gem_state.slots[0]=="core:inferno" and state.gem_state.inventory[0].locked and state.gem_state.inventory[0].affixes==source.gem_state.inventory[0].affixes,"old active direction and original attributes lock preserved")
	check(not state.gem_state.core_claimed and state.gem_state.starter_attributes_claimed==0,"new starter package does not consume migration choices")
	check(meta.request_unlock_core("wind").ok and meta.get_state().gem_state.core_choice_credits==2,"free first new core preserves two choice credits")
	check(meta.request_unlock_core("earth").ok and meta.request_unlock_core("spirit").ok and meta.get_state().gem_state.core_choice_credits==0,"removed-core choices redeem exactly twice")
	var before: Dictionary = meta.get_state()
	var loaded: Dictionary = meta.load_state()
	check(loaded.ok and meta.get_state()==before,"committed migration reload gives no repeated compensation")
	check(meta.request_lock_gem("gem-1").ok and meta.request_convert_gem("gem-1","health").ok,"optional old stone conversion")
	var converted: Dictionary = meta.gems.find(meta.get_state().gem_state,"gem-1")
	check(converted.rarity=="purple" and converted.affixes[0]==meta.gems.line("health",1,true) and converted.affixes[1].value==2,"conversion chosen existing main doubled, sides preserved")
	check(not meta.request_convert_gem("gem-2","cdr").ok,"conversion cannot invent a previously absent type")
	var pending = account("legacy_pending")
	source = old_state(pending)
	source.gem_state.inventory = [old_gem(1,"inferno")]
	source.gem_state.serial = 1; source.gem_state.draws = 1; source.gem_state.first_gold = false
	source.gem_state.work_serial = 1; source.gem_state.essence = 17
	source.gem_state.pending_reforge = {"gem_id":"gem-1","mode":"core","index":-1,"old":"inferno","candidate":"reactor","cost":60,"token":1}
	save(pending.save_path,source)
	check(pending.load_state().ok and pending.get_state().gem_state.pending_reforge==source.gem_state.pending_reforge,"old paid core candidate remains exact")
	check(not pending.begin_playable_run().ok and not pending.request_unlock_core("wind").ok,"old pending must resolve before migration or play")
	check(pending.resolve_reforge(1,true).ok,"adopt original old candidate then migrate")
	state = pending.get_state()
	check(state.gem_state.core_choice_credits==1 and state.gem_state.essence==17 and state.gem_state.inventory[0].transition_core=="reactor","old choice no redraw no new fee, chosen removed direction becomes entitlement")
	var pity = account("legacy_pity")
	source = old_state(pity)
	for index in 9: source.gem_state.inventory.append(old_gem(index+1,"","green"))
	source.gem_state.serial=9; source.gem_state.draws=9; source.gem_state.gold_misses=9; source.gem_state.rare_misses=9
	save(pity.save_path,source)
	check(pity.load_state().ok and pity.get_state().dust==27 and pity.get_state().gem_state.rare_misses==9,"old first-gold progress converts proportional dust and purple pity remains")
	check(pity.request_draw_gems(1).gems[0].rarity=="purple","inherited tenth purple guarantee")
	var bad: Dictionary = pity.get_state()
	bad.gem_state.slots[0] = str(bad.gem_state.inventory[0].id)
	save(pity.save_path,bad)
	bytes = FileAccess.get_file_as_string(pity.save_path)
	check(not Meta.new(pity.save_path).load_state().ok and FileAccess.get_file_as_string(pity.save_path)==bytes,"invalid modern core slot rejected without overwriting")
	for version in [Meta.FIXED_GEM_SAVE_VERSION,Meta.TWO_CATALYST_SAVE_VERSION]:
		var older = account("older_"+version)
		source = old_state(older)
		source.version = version
		for id in Meta.NEW_CATALYST_IDS: source.levels.erase(id)
		source.gem_state.inventory = [old_gem(1,"inferno")]
		source.gem_state.serial=1; source.gem_state.draws=1; source.gem_state.first_gold=false
		source.gem_state.slots[0]="gem-1"
		if version==Meta.FIXED_GEM_SAVE_VERSION:
			source.gem_state.inventory[0].core="layers"
			for affix in source.gem_state.inventory[0].affixes:
				affix.value=older.gems.rules.affixes[affix.stat].gold
				affix.erase("tier")
			for key in ["essence","salvaged","work_serial","pending_reforge"]: source.gem_state.erase(key)
		save(older.save_path,source)
		check(older.load_state().ok and older.gems.core_id(older.get_state().gem_state)=="inferno","older v3/v4 reaches ten-core schema "+version)
	var affix_pending = account("legacy_affix_pending")
	source = old_state(affix_pending)
	source.gem_state.inventory = [old_gem(1,"inferno")]
	source.gem_state.serial=1; source.gem_state.draws=1; source.gem_state.first_gold=false
	source.gem_state.work_serial=1; source.gem_state.essence=19
	var old_line: Dictionary = source.gem_state.inventory[0].affixes[0].duplicate(true)
	var new_line: Dictionary = {"stat":"defense","tier":3,"value":affix_pending.gems.rules.affixes.defense.tiers[2]}
	source.gem_state.pending_reforge={"gem_id":"gem-1","mode":"affix","index":0,"old":old_line,"candidate":new_line,"cost":3,"token":1}
	save(affix_pending.save_path,source)
	check(affix_pending.load_state().ok and affix_pending.resolve_reforge(1,true).ok,"old paid affix candidate can be adopted before migration")
	state = affix_pending.get_state()
	check(state.gem_state.essence==19 and state.gem_state.inventory[0].affixes[0]==new_line and state.gem_state.rng_state==source.gem_state.rng_state,"old affix adopted exact value tier RNG with no new fee")

func sampling() -> void:
	var lib = Gems.new()
	for seed_value in 8:
		var state: Dictionary = lib.fresh()
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_value
		var gap: int = 0
		for index in 100:
			var gem: Dictionary = lib.sample(state,rng)
			gap = 0 if gem.rarity=="purple" else gap+1
			check(gap<10 and gem.rarity!="gold","actual draw ten guarantee seed%d index%d"%[seed_value,index])
			var used: Array = []
			for i in gem.affixes.size():
				var affix: Dictionary = gem.affixes[i]
				check(affix.stat not in used and affix==lib.line(str(affix.stat),int(affix.tier),i==0),"production affix exact runtime tier and uniqueness")
				used.append(affix.stat)

func run() -> int:
	transactions()
	workshop()
	milestones()
	migration()
	sampling()
	for path in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	result = {"checks":checks,"failures":failures.size(),"failed_cases":failures,"scope":"production account/RNG/workshop/migration isolated fixtures; no interactive gameplay or real account"}
	result["source_sha256"] = {}
	for path in ["data/magic_gems_v1.json","scripts/core/magic_gems.gd","scripts/core/meta_progression.gd","tests/gem_v3_economy_tests.gd"]:
		result.source_sha256[path] = FileAccess.get_sha256("res://"+path)
	FileAccess.open(OUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("GEM_V3_ECONOMY "+JSON.stringify(result))
	return checks if failures.is_empty() else -failures.size()
