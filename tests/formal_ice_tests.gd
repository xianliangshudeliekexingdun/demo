extends SceneTree
## Actual Route/Ice/Artifact implementation checks. AI/spawn/clear are isolated
## unless a group explicitly enables the production enemy engine. No copied
## damage simulator, natural inventory assertion, or production save access.

const First = preload("res://scripts/core/first_room_run.gd")
const OUT = "res://build/qa/spell-growth-implementation-20261020/formal-ice"
const ICE_IDS = ["I01", "I02", "I03", "I04", "I05", "I06", "I07", "I08", "I09", "I10"]
const FIRE_IDS = ["F01", "F02", "F03", "F05", "F06", "F07", "F08", "F09", "F10", "F11"]
const BLUE_IDS = ["IB01", "IB02", "IB03", "IB04", "IB05", "IB06", "IB07", "IB08", "IB09", "IB10"]
var checks: int = 0
var failures: Array = []
var groups: Array = []
var observations: Array = []
var before_sources: Dictionary = {}

class Fixture extends "res://scripts/core/courtyard_route_run.gd":
	var damage_log: Array = []
	var context_log: Array = []
	var cast_log: Array = []
	var extra_log: Array = []
	var emitted: Array = []
	var extra_cdr: float = 0.0
	var simulate_enemy_ai: bool = false
	func _reserve_batch(): pass
	func _update_spawn(_dt: float): pass
	func _check_clear(): pass
	func _update_enemies(dt: float):
		if simulate_enemy_ai:
			super._update_enemies(dt)
		else:
			_spell_combat.ice.before_tick(self,dt)
			for enemy in actors: enemy.previous = enemy.pos
	func artifact_cooldown_reduction() -> float:
		return super.artifact_cooldown_reduction() + extra_cdr
	func damage_enemy(enemy: Dictionary, amount: float, spell_id: String = ""):
		var before: float = float(enemy.get("health", 0.0))
		super.damage_enemy(enemy, amount, spell_id)
		damage_log.append({"at": time, "actor_id": enemy.get("id", -1), "source": spell_id,
			"amount": maxf(0.0, before - float(enemy.get("health", 0.0)))})
	func resolve_spell_hit(enemy: Dictionary, coefficient: float, context: Dictionary) -> Dictionary:
		var result: Dictionary = super.resolve_spell_hit(enemy, coefficient, context)
		context_log.append({"at": time, "actor_id": enemy.get("id", -1), "coefficient": coefficient,
			"context": context.duplicate(true), "result": result.duplicate(true)})
		return result
	func on_spell_cast(spell: Dictionary, target: Dictionary, context: Dictionary):
		cast_log.append({"at": time, "id": spell.id, "context": context.duplicate(true)})
		super.on_spell_cast(spell, target, context)
	func cast_extra_spell(id: String, target: Dictionary = {}, scale: float = 1.0) -> bool:
		extra_log.append({"id": id, "target": target.duplicate(true), "scale": scale})
		return super.cast_extra_spell(id, target, scale)
	func _emit(kind: String, values: Dictionary, lifetime: float):
		emitted.append({"kind": kind, "at": time, "values": values.duplicate(true)})
		super._emit(kind, values, lifetime)

func _initialize(): call_deferred("execute")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures.append(label)
		push_error("Formal ice: " + label)
func near(a: float, b: float, tolerance: float = 0.0001) -> bool:
	return absf(a - b) < tolerance
static func actor(id: int = 1, pos: Vector2 = Vector2(0, 2), health: float = 1000000.0, type_id: String = "M01") -> Dictionary:
	return {"id": id, "type": type_id, "type_id": type_id, "pos": pos, "previous": pos,
		"health": health, "max_health": health, "radius": 0.3, "phase": "chase", "push_resistance": 0.0,
		"spell_slows": {}, "slow_remaining": 0.0, "slow_multiplier": 1.0}
func fresh(ids: Array = ["I01"], level: int = 1):
	var battle = Fixture.new()
	check(battle.configure({"route_school":"ice"}, 20261018).ok, "fixture real Route.configure ice")
	check(battle.choose_initial("I01"), "fixture starts via actual ice choice")
	battle._spawn_done = true
	battle.spawn_warnings.clear()
	battle.blocks.clear()
	battle.player.pos = Vector2.ZERO
	battle.player.previous = Vector2.ZERO
	battle.player.crit_rate = 0.0
	battle.spells.clear()
	for id in ids:
		var spell: Dictionary = battle._new_spell(str(id))
		spell.level = level
		battle._refresh_spell(spell)
		battle.spells.append(spell)
	battle.actors = [actor()]
	stop_natural(battle)
	return battle
func stop_natural(battle):
	for spell in battle.spells:
		spell.remaining = 9999.0
		spell.cast_remaining = 0.0
func grant(battle, id: String):
	check(not battle._artifact_combat.has_artifact(id), "unique controlled grant " + id)
	battle._artifact_combat._owned.append(id)
	battle._artifact_combat.apply_acquisition(battle, id)
func ticks(battle, count: int):
	for _index in count: battle.step(1.0 / 120.0)
func advance(battle, seconds: float): ticks(battle, roundi(seconds * 120.0))
func state(battle, id: int = 1) -> Dictionary:
	var result: Dictionary=battle._spell_combat.ice.status.state_for(id).duplicate(true)
	if not result.is_empty():
		for enemy in battle.actors:
			if int(enemy.id)==id: result["slow_amount"]=battle._spell_combat.ice.status.slow_amount(enemy)
	return result
func is_ready(battle, id: int = 1) -> bool:
	return not battle._spell_combat.ice.status.capture_ready(id).is_empty()
func frost(battle, stacks: int = 1, id: int = 1, source: String = "I01", natural: bool = true):
	for enemy in battle.actors:
		if int(enemy.id) == id:
			return battle._spell_combat.ice.apply_frost(battle, enemy, stacks, context(source, 8100 + checks, natural))
	return false
func ready(battle, id: int = 1, freeze_base: float = 1.2):
	for enemy in battle.actors:
		if int(enemy.id) == id:
			return battle._spell_combat.ice.status.force_ready(battle, enemy, freeze_base, context("I08", 8900 + checks))
	return {}
func context(id: String = "I01", cast_id: int = 1, natural: bool = true, kind: String = "ice_bolt") -> Dictionary:
	return {"spell_id": id, "cast_id": cast_id, "natural": natural, "kind": kind,
		"damage_scale": 1.0, "field_bonus": 0.0, "school":"ice" if id in ICE_IDS else ("fire" if id in FIRE_IDS else "spirit")}
func release_once(battle, id: String, natural: bool = true, scale: float = 1.0):
	var spell: Dictionary = battle._owned_spell(id)
	var stats: Dictionary = battle.get_spell_stats(spell)
	var target: Dictionary = battle._spell_combat.legal_target(battle, spell, stats)
	check(not target.is_empty(), "controlled actual legal target " + id)
	if target.is_empty(): return
	spell.locked_pos = target.pos
	battle._spell_combat._cast(battle, spell, stats, target, natural, scale)
	stop_natural(battle)
func source_damage(battle, id: String, actor_id: int = -1) -> float:
	var total: float = 0.0
	for hit in battle.damage_log:
		if hit.source == id and (actor_id < 0 or int(hit.actor_id) == actor_id): total += float(hit.amount)
	return total
func actor_damage(battle, id: int) -> float:
	var total: float = 0.0
	for hit in battle.damage_log:
		if int(hit.actor_id) == id: total += float(hit.amount)
	return total
func group(label: String, callable: Callable):
	var count_before: int = checks
	var failed_before: int = failures.size()
	callable.call()
	groups.append({"id":label, "checks":checks-count_before, "failures":failures.size()-failed_before})
func source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in ["res://tests/formal_ice_tests.gd", "res://scripts/core/first_room_run.gd", "res://scripts/core/courtyard_route_run.gd", "res://scripts/core/courtyard_route_catalog.gd", "res://scripts/core/route_spell_combat.gd", "res://scripts/core/route_ice_combat.gd", "res://scripts/core/route_ice_status.gd", "res://scripts/core/route_enemy_combat.gd", "res://scripts/core/route_artifacts.gd", "res://scripts/core/route_generic_items.gd", "res://scripts/core/route_fire_status.gd", "res://data/balance_candidates/first_run_v1.json", "res://data/balance_candidates/meta_growth_v1.json", "res://data/balance_candidates/fire_artifacts_v1.json", "res://data/generic_artifacts_v1.json", "res://data/ice_spells_v1.json", "res://data/ice_artifacts_v1.json", "res://data/route_spell_runtime.json", "res://data/route_artifact_runtime.json", "res://data/route_enemy_runtime.json"]:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	result["res://scripts/core/route_ice_artifacts.gd"]=FileAccess.get_sha256("res://scripts/core/route_ice_artifacts.gd")
	return result
func execute():
	before_sources = source_hashes()
	var probe = Fixture.new()
	var configured: Dictionary = probe.configure({"route_school":"ice"}, 20261018)
	check(bool(configured.get("ok", false)), "ice runtime config valid")
	if bool(configured.get("ok", false)):
		check(probe._spell_combat.get("ice") != null, "actual IceCombat integrated")
		if probe._spell_combat.get("ice") != null:
			group("current_growth_transactions", current_growth_transactions)
			group("targeting_geometry_and_cadence", targeting_geometry_and_cadence)
			group("frost_time_and_immunity", frost_time_and_immunity)
			group("shatter_old_token", shatter_old_token)
			group("shared_area_gates", shared_area_gates)
			group("dynamic_scope_and_general_items", dynamic_scope_and_general_items)
			group("actual_enemy_freeze", actual_enemy_freeze)
			group("high_cdr_eight_slot_state_stress", high_cdr_eight_slot_state_stress)
			group("pause_cleanup", pause_cleanup)
	check(source_hashes() == before_sources, "rules sources unchanged during execution")
	var output: String=OUT
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with("--qa-out=res://build/qa/") and not str(argument).contains(".."):
			output=str(argument).trim_prefix("--qa-out=")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output+"/rules.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"details":failures,"groups":groups,"observations":observations,"source_hashes":before_sources,"source_stable":source_hashes()==before_sources,"scope":"Actual Route/Spell/Ice/Artifact fixed-step implementation under controlled AI/spawn/clear fixtures; real enemy engine enabled only in its group. Not a natural inventory, save, player win-rate, Boss or final timing claim."},"\t"))
	print("FORMAL ICE RULES checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func current_growth_transactions():
	var suite = preload("res://tests/spell_growth_tests.gd").new()
	suite.ice_transactions()
	checks += suite.checks
	for issue in suite.details: failures.append(issue)

# Historical profession/old coefficient probes are retained for reference;
# current source/level and replacement mechanics are covered in spell_growth_tests.
func catalog_and_qualification():
	var b = fresh()
	check(b.initial_choices().map(func(value): return value.id) == ["I01","I02","I03"], "ice actual three starters")
	var fire = Fixture.new()
	check(fire.configure({},20261018).ok and fire.initial_choices().map(func(value): return value.id)==["F01","F03","F08"], "default fire three starters preserved")
	var ice_catalyst = Fixture.new()
	check(ice_catalyst.configure({"route_school":"ice","equipment":{"catalyst":"MC05"},"levels":{"MC05":3}},20261018).ok, "ice catalyst route config valid")
	check(near(ice_catalyst.reward_weight("I01"),2.0) and near(ice_catalyst.reward_weight("F01"),1.0), "level three ice catalyst biases only ice rewards")
	var fire_catalyst = Fixture.new()
	check(fire_catalyst.configure({"route_school":"ice","equipment":{"catalyst":"MC04"},"levels":{"MC04":3}},20261018).ok, "fire catalyst on ice route config valid")
	check(near(fire_catalyst.reward_weight("F01"),2.0) and near(fire_catalyst.reward_weight("I01"),1.0), "level three fire catalyst biases only fire rewards")
	var first = First.new()
	check(first.configure().ok and first.initial_choices().map(func(value): return value.id)==["F01","F04","F08"], "independent historical starters preserved")
	check(not first.eligible_reward_ids().any(func(id): return str(id).begins_with("I")), "independent old reward pool excludes unsupported ice")
	var eligible: Array = b.eligible_reward_ids()
	check(eligible.size()==20 and "F04" not in eligible, "mixed Route twenty active spells, no archive")
	for id in ICE_IDS+FIRE_IDS: check(id in eligible, "normal mixed legal ID " + id)
	var items: Dictionary = b._artifact_combat._items
	check(items.size()==63, "63 stored treasure IDs including four Boss-only seals")
	for scope in ["generic","fire","ice","spirit"]:
		check(items.keys().filter(func(id): return str(items[id].scope)==scope and not bool(items[id].get("boss_only", false))).size()=={"generic":24,"fire":16,"ice":16,"spirit":3}[scope], "ordinary and archived scope count " + scope)
	for rarity in ["blue","purple","gold"]:
		check(items.keys().filter(func(id): return str(items[id].scope)=="ice" and str(items[id].rarity)==rarity).size()=={"blue":10,"purple":3,"gold":3}[rarity], "ice career rarity budget " + rarity)
	for id in ["B04","P01","G02"]: check(id not in b._artifact_combat.eligible_ids(b) and not bool(items[id].active), "archive stays inactive " + id)
	for index in 10:
		var single = fresh([ICE_IDS[index]])
		check(BLUE_IDS[index] in single._artifact_combat.eligible_ids(single), "blue follows actually held spell " + BLUE_IDS[index])
		check(single._artifact_combat.eligible_ids(single).filter(func(id): return str(id).begins_with("IB")).size()==1, "single spell cannot qualify unrelated ice blues")
	var shatter = fresh(["I07","I01"])
	check("IP02" not in shatter._artifact_combat.eligible_ids(shatter), "IP02 excludes level1 with no fragments")
	shatter._owned_spell("I07").level = 2
	check("IP02" in shatter._artifact_combat.eligible_ids(shatter), "IP02 enters only once fragments exist")
	var two = fresh(["I01","I02"])
	check("IP01" in two._artifact_combat.eligible_ids(two) and "IG01" not in two._artifact_combat.eligible_ids(two), "two starters qualify purple but not three-ice area gold")
	var armor = fresh(["I08","I09"])
	check("IG03" in armor._artifact_combat.eligible_ids(armor), "coffin and armor actual gold prerequisite")
	check("GT01" not in armor._artifact_combat.eligible_ids(armor), "ice armor and coffin alone are not combat shield recovery")
	grant(armor,"IG03")
	check("GT01" in armor._artifact_combat.eligible_ids(armor), "owned IG03 actual restore source qualifies generic charge")
	check("IP03" in armor._artifact_combat.eligible_ids(armor), "armor plus damaging ice active purple prerequisite")
	var defensive = fresh(["I09","I10"])
	check("IP03" not in defensive._artifact_combat.eligible_ids(defensive), "passive is not damaging active for IP03")
	for recovery in ["GU11","GU16"]:
		var pure_defense = fresh(["I09","I10"])
		grant(pure_defense,recovery)
		check("GT01" not in pure_defense._artifact_combat.eligible_ids(pure_defense), "recovery but no actual damage cannot qualify charge " + recovery)
	var duplicate = fresh(["I05","I05","I01"])
	check("IG01" not in duplicate._artifact_combat.eligible_ids(duplicate), "duplicate slots cannot fake three distinct ice prerequisite")
	var area = fresh(["I05","I01","I10"])
	check("IG01" in area._artifact_combat.eligible_ids(area), "three distinct ice including area qualifies IG01")
	grant(area,"IG01")
	check("IG01" not in area._artifact_combat.eligible_ids(area), "owned unique career excluded")
	area.room_index=45
	area.boss_rewards={"book_resolved":true,"chest_resolved":false}
	var offered: Array=area._artifact_combat.sample_choices(area,area._rng)
	var rng_state: int=area._rng.state
	check(not offered.is_empty() and offered.size()<=3 and offered.all(func(item):return str(item.rarity)=="gold"), "mixed Boss chest uses only legal gold after book resolution")
	check(area._artifact_combat.sample_choices(area,area._rng)==offered and area._rng.state==rng_state, "mixed offers cached without RNG redraw")
	for item in offered: check(offered.filter(func(other): return other.id==item.id).size()==1, "mixed offers no replacement " + str(item.id))

func ten_spells_three_levels():
	for level in range(1,4):
		for id in ICE_IDS:
			var b = fresh([id],level)
			if id=="I10":
				var result: Dictionary=b.resolve_spell_hit(b.actors[0],1.0,context())
				check(near(float(result.damage),100.0*[1.1,1.18,1.25][level-1]), "mastery current school bucket L"+str(level))
				advance(b,2.0)
				check(b.cast_log.is_empty(), "passive no natural cast L"+str(level))
				continue
			if id=="I02": b.actors=[actor(1,Vector2(0,2)),actor(2,Vector2(0,3)),actor(3,Vector2(0,4)),actor(4,Vector2(0,5)),actor(5,Vector2(0,6))]
			release_once(b,id)
			if id=="I01": advance(b,0.3)
			elif id=="I03": advance(b,0.8)
			elif id=="I05": advance(b,5.1)
			elif id=="I06": advance(b,3.4)
			elif id=="I08": advance(b,0.3)
			elif id=="I09": advance(b,0.01)
			var expected: Dictionary={"I01":[120.0,160.0,190.0],"I02":[480.0,800.0,920.0],"I03":[180.0,240.0,320.0],"I04":[80.0,100.0,100.0],"I05":[180.0,300.0,300.0],"I06":[180.0,300.0,360.0],"I07":[100.0,140.0,180.0],"I08":[200.0,260.0,320.0],"I09":[0.0,0.0,0.0]}
			check(near(float(b.damage_dealt),float(expected[id][level-1])), "actual full basic damage " + id + " L"+str(level))
			check(b.cast_log.size()==1 and b.cast_log[0].context.natural, "one natural release for all components " + id+" L"+str(level))
			if id=="I02":
				check(near(actor_damage(b,1),160.0 if level==1 else 200.0), "pierce first target never receives unused bonuses")
				check(near(actor_damage(b,5),0.0), "base piercing cap respects ordered targets")
			if id=="I09":
				check(near(b._spell_combat.ice.defense_bonus(),20.0 if level==1 else 30.0), "armor actual defense L"+str(level))
				check(near(float(b.player.shield),float(b.player.max_shield)), "armor no shield restoration or damage")
			if id=="I08": check(near(float(state(b).get("freeze_remaining",-99)),[1.5,1.75,2.0][level-1]-0.05,0.02), "coffin correct hard duration L"+str(level))
	var doubled = fresh(["I01"],3)
	frost(doubled,1)
	release_once(doubled,"I01")
	advance(doubled,0.3)
	check(is_ready(doubled), "L3 bolt prior1 gains2 and opens one window")
	var pulsed = fresh(["I09"],3)
	release_once(pulsed,"I09")
	advance(pulsed,2.0)
	check(int(state(pulsed).get("stacks",0))==2, "L3 armor second pulse adds exactly one at2s")
	advance(pulsed,2.0)
	check(near(pulsed._spell_combat.ice.defense_bonus(),0.0), "armor exact expiry clears defense")

func targeting_geometry_and_cadence():
	for cdr in [0.0,0.9]:
		var cadence = fresh(["I01"])
		cadence.extra_cdr=cdr
		cadence.spells[0].remaining=0.0
		advance(cadence,2.0)
		check(cadence.cast_log.size()>=2, "actual automatic cadence releases repeated bolts " + str(cdr))
		if cadence.cast_log.size()>=2:
			var period: float=1.45 if cdr==0.0 else 0.67
			check(near(float(cadence.cast_log[0].at),0.15,0.02), "CDR never shortens actual windup " + str(cdr))
			check(near(float(cadence.cast_log[1].at)-float(cadence.cast_log[0].at),period,0.02), "actual successful-release-to-release cadence " + str(cdr))
	var canceled = fresh(["I01"])
	canceled.spells[0].remaining=0.0
	ticks(canceled,1)
	canceled.damage_enemy(canceled.actors[0],1000000.0,"fixture_death")
	canceled.actors.append(actor(2,Vector2(0,3)))
	advance(canceled,0.2)
	check(canceled.cast_log.is_empty(), "dead locked target cannot skip new complete windup")
	check(float(canceled.spells[0].remaining)<=0.000001, "failed windup does not start cooldown")
	advance(canceled,0.2)
	check(canceled.cast_log.size()==1, "new valid target eventually gets full windup release")
	var start_lock = fresh(["I03"])
	start_lock.spells[0].remaining=0.0
	advance(start_lock,0.1)
	start_lock.actors[0].pos=Vector2(0,5)
	start_lock.actors[0].previous=start_lock.actors[0].pos
	advance(start_lock,0.7)
	check(start_lock.cast_log.size()==1 and near(start_lock.damage_dealt,0.0), "I03 fixes start-of-windup ground point, target may dodge")
	var release_lock = fresh(["I08"])
	release_lock.spells[0].remaining=0.0
	advance(release_lock,0.1)
	release_lock.actors[0].pos=Vector2(0,5)
	release_lock.actors[0].previous=release_lock.actors[0].pos
	advance(release_lock,0.5)
	check(release_lock.cast_log.size()==1, "coffin valid target still releases after moving during windup")
	release_lock.actors[0].pos=Vector2(0,7)
	release_lock.actors[0].previous=release_lock.actors[0].pos
	advance(release_lock,0.3)
	check(near(release_lock.damage_dealt,0.0) and not is_ready(release_lock), "I08 fixes release-time point, moved target dodges and gets no window")
	for id in ["I01","I02","I03","I05","I06","I08"]:
		var wall = fresh([id])
		wall.actors=[actor(1,Vector2(0,4))]
		wall.blocks=[{"center":Vector2(0,2),"size":Vector2(2,0.5)}]
		check(wall._spell_combat.legal_target(wall,wall.spells[0],wall.get_spell_stats(wall.spells[0])).is_empty(), "cannot acquire target through actual wall " + id)
	var no_near = fresh(["I04"])
	no_near.actors=[actor(1,Vector2(0,5))]
	check(no_near._spell_combat.legal_target(no_near,no_near.spells[0],no_near.get_spell_stats(no_near.spells[0])).is_empty(), "ring waits when no actual local target")
	var armor = fresh(["I09"])
	armor.actors=[actor(1,Vector2(0,5))]
	release_once(armor,"I09")
	check(near(armor._spell_combat.ice.defense_bonus(),20.0) and state(armor).is_empty(), "armor may defend against6m threat without local frost target")
	check(armor._spell_combat.legal_target(armor,armor.spells[0],armor.get_spell_stats(armor.spells[0])).is_empty(), "active armor cannot constantly refresh above.25 remaining")

func frost_time_and_immunity():
	var b = fresh()
	frost(b,1)
	check(int(state(b).get("stacks",-1))==1 and near(float(state(b).get("frost_until",-99)),4.0), "first frost finite4s")
	advance(b,3.0)
	frost(b,1)
	check(int(state(b).stacks)==2 and near(float(state(b).frost_until),7.0), "partial frost refreshes whole duration")
	advance(b,4.0)
	check(int(state(b).get("stacks",0))==0, "frost expiry clears all layers at once")
	for kind in ["M01","EL01","EL02_GUARD"]:
		var control = fresh()
		control.actors=[actor(1,Vector2(0,2),1000000.0,kind)]
		frost(control,3)
		var initial: Dictionary=state(control)
		check(is_ready(control) and near(float(initial.get("ready_until",-99)),2.5), "same ready window for " + kind)
		check(near(float(initial.get("freeze_remaining",-99)),{"M01":1.2,"EL01":0.42,"EL02_GUARD":0.0}[kind]), "control factor once " + kind)
		advance(control,0.2)
		frost(control,3)
		check(near(float(state(control).ready_until),2.5), "hit cannot extend ready " + kind)
		advance(control,2.3)
		check(not is_ready(control), "ready exact expiry " + kind)
		var slow = fresh()
		slow.actors=[actor(1,Vector2(0,2),1000000.0,kind)]
		frost(slow,2)
		check(near(float(state(slow).slow_amount),{"M01":0.16,"EL01":0.12,"EL02_GUARD":0.08}[kind]), "frost classified slow does not multiply control factor " + kind)
		slow._spell_combat.ice.status.apply_short_slow(slow,slow.actors[0],0.9,1.0,"cap_fixture")
		check(near(float(state(slow).slow_amount),{"M01":0.45,"EL01":0.25,"EL02_GUARD":0.15}[kind]), "final classified strongest slow cap " + kind)
	var immune_action = fresh()
	immune_action.actors[0]["ice_control_coefficient"]=0.0
	frost(immune_action,3)
	check(is_ready(immune_action) and near(float(state(immune_action).freeze_remaining),0.0) and near(float(state(immune_action).slow_amount),0.24), "explicit uninterruptible action only removes hard freeze, not crack or normal slow")
	var immunity = fresh()
	frost(immunity,3)
	advance(immunity,1.2)
	check(near(float(state(immunity).get("immunity_until",-99)),4.2), "natural freeze end starts3s immunity")
	advance(immunity,1.3)
	frost(immunity,3)
	check(is_ready(immunity) and near(float(state(immunity).freeze_remaining),0.0), "immune still forms crack without freeze")
	advance(immunity,1.7)
	check(near(float(state(immunity).freeze_remaining),0.0), "immunity expiry does not repay missed freeze")
	advance(immunity,0.8)
	frost(immunity,3)
	check(near(float(state(immunity).freeze_remaining),1.2), "new ready after immunity can freeze again")
	var mastery = fresh(["I10"],3)
	frost(mastery,3)
	check(near(float(state(mastery).ready_until),3.0) and near(float(state(mastery).freeze_remaining),1.2), "mastery lengthens crack not hard control")
	var long_frost = fresh(["I10"],3)
	frost(long_frost,1)
	check(near(float(state(long_frost).frost_until),6.0), "I10 level3 ordinary frost duration6")
	frost(long_frost,2)
	check(near(float(state(long_frost).ready_until),3.0) and near(float(state(long_frost).freeze_remaining),1.2), "ordinary frost duration does not exceed existing mastery ready extension or hard freeze")
	var snapshot: Array=long_frost.get_snapshot().get("ice_states",[])
	check(snapshot.size()==1, "snapshot exposes one ice state per actor")
	if not snapshot.is_empty(): snapshot[0].ready_until=-100.0
	check(float(state(long_frost).ready_until)>0.0, "ice snapshot is deep copy")

func shatter_old_token():
	for level in range(1,4):
		var b = fresh(["I07"],level)
		ready(b)
		var captured: Dictionary=b._spell_combat.ice.status.capture_ready(1)
		check(not captured.is_empty(), "capture real old ready token")
		release_once(b,"I07")
		check(near(b.damage_dealt,[300.0,450.0,776.0][level-1]), "base plus noncritical shatter L"+str(level))
		check(not is_ready(b), "one shatter consumes full old stage")
		check(near(float(state(b).get("immunity_remaining",-99)),3.0), "early shatter starts immunity at actual release")
		var first_damage: float=b.damage_dealt
		release_once(b,"I07")
		check(near(b.damage_dealt-first_damage,[100.0,150.0,200.0][level-1]), "same-time second cast gets no duplicate token")
	var crit = fresh(["I07"])
	crit.player.crit_rate=1.8
	crit.player.crit_multiplier=2.0
	ready(crit)
	release_once(crit,"I07")
	check(near(crit.damage_dealt,400.0), "base may crit above100, derived shatter cannot")
	for via_charge in [false,true]:
		var lethal = fresh(["I07"],3)
		lethal.actors=[actor(1,Vector2(0,2),250.0 if via_charge else 100.0),actor(3,Vector2(0,3)),actor(2,Vector2(1,2)),actor(4,Vector2(-1,2)),actor(5,Vector2(0,4)),actor(6,Vector2(1,3))]
		if via_charge:
			grant(lethal,"GT01")
			lethal.player.shield=0.0
			lethal.restore_player_shield(100.0,"I09_fixture")
		ready(lethal)
		var lethal_token: Dictionary=lethal._spell_combat.ice.status.capture_ready(1)
		release_once(lethal,"I07")
		check(float(lethal.actors[0].health)<=0.0, "effective parent death path " + str(via_charge))
		check(near(actor_damage(lethal,1),250.0 if via_charge else 100.0), "no shatter damage added to dead primary")
		check(lethal.damage_log.filter(func(hit):return int(hit.actor_id)!=1 and float(hit.amount)>0.0).size()==4, "effective fatal parent still exactly four fragments")
		var before: float=lethal.damage_dealt
		var repeated: Dictionary=lethal._spell_combat.ice.status.consume_ready(lethal,lethal.actors[0],int(lethal_token.token),context("I07",999),lethal_token)
		check(repeated.is_empty() and near(lethal.damage_dealt,before), "same valid captured corpse token cannot pay twice")
	var expired = fresh(["I07"])
	ready(expired)
	advance(expired,2.5)
	release_once(expired,"I07")
	check(near(expired.damage_dealt,100.0), "expiry clears old token before same-time shatter")
	var wall = fresh(["I07"],3)
	wall.actors=[actor(1,Vector2(0,2)),actor(2,Vector2(2,2)),actor(3,Vector2(-1,2))]
	wall.blocks=[{"center":Vector2(1.0,2.0),"size":Vector2(0.4,1.0)}]
	ready(wall)
	release_once(wall,"I07")
	check(near(actor_damage(wall,2),0.0) and near(actor_damage(wall,3),140.0), "fragments use center-neighbor LOS and exclude blocked neighbor")

func shared_area_gates():
	var field = fresh(["I05"])
	release_once(field,"I05",false)
	advance(field,0.5)
	check(near(field.damage_dealt,45.0) and int(state(field).stacks)==1, "initial field first jump .5")
	release_once(field,"I05",false)
	advance(field,0.5)
	check(near(field.damage_dealt,45.0) and int(state(field).stacks)==1, "replacement cannot reset field shared1s gate")
	advance(field,1.0)
	check(near(field.damage_dealt,90.0) and int(state(field).stacks)==2, "replacement phase resumes only after shared gate")
	var storm = fresh(["I06"])
	release_once(storm,"I06",false)
	advance(storm,0.3)
	observations.append({"probe":"storm_first_effective_wave","damage":storm.damage_log.duplicate(true),"state":state(storm),"zones":storm._spell_combat.ice.zones.duplicate(true)})
	check(near(storm.damage_dealt,45.0) and int(state(storm).get("stacks",0))==1, "storm first effective wave")
	release_once(storm,"I06",false)
	advance(storm,0.3)
	check(near(storm.damage_dealt,45.0) and int(state(storm).get("stacks",0))==1, "additional storm cannot bypass shared.6s gate")
	advance(storm,0.3)
	check(near(storm.damage_dealt,90.0), "old storm next actual wave allowed at.9")
	var frozen = fresh(["I05"])
	ready(frozen)
	var expiry: float=float(state(frozen).ready_until)
	release_once(frozen,"I05")
	advance(frozen,2.0)
	check(near(float(state(frozen).ready_until),expiry) and near(frozen.damage_dealt,90.0), "field deals damage during window without renewal")
	for reverse in [false,true]:
		var strongest = fresh(["I06"])
		release_once(strongest,"I06",false)
		strongest._owned_spell("I06").level=3
		release_once(strongest,"I06",false)
		if reverse: strongest._spell_combat.ice.zones.reverse()
		advance(strongest,0.3)
		check(near(strongest.damage_dealt,80.0) and int(state(strongest).get("stacks",0))==1, "same-time storms choose highest coefficient once order="+str(reverse))

func blue_profession():
	for prior in [0,1,2,3]:
		var bolt = fresh(["I01"])
		grant(bolt,"IB01")
		if prior>0: frost(bolt,prior)
		release_once(bolt,"I01")
		advance(bolt,0.3)
		check(near(bolt.damage_dealt,150.0 if prior in [1,2] else 120.0), "IB01 only pre-hit1-2 stacks " + str(prior))
	var line = fresh(["I02"])
	grant(line,"IB02")
	line.actors=[actor(1,Vector2(0,2)),actor(2,Vector2(0,3)),actor(3,Vector2(0,4)),actor(4,Vector2(0,5)),actor(5,Vector2(0,6))]
	release_once(line,"I02")
	check(near(line.damage_dealt,640.0) and near(actor_damage(line,5),0.0), "IB02 increases actual piercing cap by one")
	var star = fresh(["I03"])
	grant(star,"IB03")
	release_once(star,"I03")
	advance(star,0.15)
	check(near(star.damage_dealt,180.0), "IB03 changes first fall .35 to .15")
	for kind in ["M01","EL01","EL02_GUARD"]:
		var ring = fresh(["I04"])
		grant(ring,"IB04")
		ring.actors=[actor(1,Vector2(2.65,0),1000000.0,kind)]
		release_once(ring,"I04")
		check(near(ring.damage_dealt,80.0), "IB04 larger actual ring " + kind)
		check(near(float(state(ring).get("slow_amount",-99)),{"M01":0.4,"EL01":0.25,"EL02_GUARD":0.12}[kind]), "IB04 classified short slow strongest " + kind)
	var field = fresh(["I05"])
	grant(field,"IB05")
	release_once(field,"I05")
	advance(field,6.1)
	check(near(field.damage_dealt,270.0), "IB05 extends finite field to six jumps")
	for level in range(1,4):
		var storm = fresh(["I06"],level)
		grant(storm,"IB06")
		release_once(storm,"I06")
		advance(storm,3.4)
		check(near(storm.damage_dealt,[207.0,336.0,396.0][level-1]), "IB06 only last wave1.6 L"+str(level))
	var shatter = fresh(["I07"])
	grant(shatter,"IB07")
	ready(shatter)
	release_once(shatter,"I07")
	check(near(shatter.damage_dealt,340.0), "IB07 level1 adds40pp to primary shatter")
	var strong = fresh(["I08"])
	grant(strong,"IB08")
	strong.actors=[actor(1,Vector2(0,2),1000000.0,"EL02_GUARD")]
	release_once(strong,"I08")
	advance(strong,0.3)
	check(near(strong.damage_dealt,300.0) and near(float(state(strong).freeze_remaining),0.0), "IB08 no-hard-control bonus without granting freeze")
	var frozen_prison = fresh(["I08"])
	grant(frozen_prison,"IB08")
	ready(frozen_prison)
	release_once(frozen_prison,"I08")
	advance(frozen_prison,0.3)
	check(near(frozen_prison.damage_dealt,200.0), "IB08 not boosted during active hard freeze before immunity starts")
	advance(frozen_prison,0.9)
	release_once(frozen_prison,"I08")
	advance(frozen_prison,0.3)
	check(near(frozen_prison.damage_dealt,500.0) and near(float(state(frozen_prison).ready_until),2.5), "IB08 boosted only after actual thaw immunity, without refreshing existing window")
	var armor = fresh(["I09"])
	grant(armor,"IB09")
	armor.actors=[actor(1,Vector2(2.5,0))]
	release_once(armor,"I09")
	check(int(state(armor).get("stacks",0))==1, "IB09 actual larger frost pulse, no damage")
	check(near(armor.damage_dealt,0.0) and near(armor._spell_combat.ice.defense_bonus(),20.0), "IB09 does not add layers/defense/damage")

func purple_and_gold_profession():
	for first_prior in [0,1]:
		var sequel = fresh(["I01","I02"])
		grant(sequel,"IP01")
		sequel.actors=[actor(1,Vector2(0,2)),actor(2,Vector2(0,3))]
		if first_prior>0: frost(sequel,first_prior,1)
		frost(sequel,1,2)
		release_once(sequel,"I02")
		check(is_ready(sequel,1)==(first_prior==1), "IP01 first hit decision uses pre-stack")
		check(int(state(sequel,2).get("stacks",0))==2, "IP01 check cannot transfer to eligible rear enemy")
	var dead_first = fresh(["I01","I02"])
	grant(dead_first,"IP01")
	dead_first.actors=[actor(1,Vector2(0,2),1.0),actor(2,Vector2(0,3))]
	frost(dead_first,1,2)
	release_once(dead_first,"I02")
	check(int(state(dead_first,2).get("stacks",0))==2, "IP01 fatal first hit consumes check without rear transfer")
	var fragments = fresh(["I07","I01"],2)
	grant(fragments,"IP02")
	fragments.actors=[actor(1,Vector2(0,2)),actor(2,Vector2(0,3)),actor(3,Vector2(1,2)),actor(4,Vector2(-1.2,2))]
	ready(fragments)
	release_once(fragments,"I07")
	check([2,3,4].filter(func(id):return int(state(fragments,id).get("stacks",0))==1).size()==2, "IP02 only nearest two surviving hurt fragments")
	var reaction = fresh(["I09","I01"])
	grant(reaction,"IP03")
	release_once(reaction,"I09")
	check(int(state(reaction).get("stacks",0))==1, "armor base pulse before reaction")
	reaction.damage_player(10.0)
	check(int(state(reaction).get("stacks",0))==2 and near(reaction.damage_dealt,0.0), "IP03 actual surviving loss adds one frost without damage")
	advance(reaction,0.7)
	reaction.damage_player(10.0)
	check(int(state(reaction).get("stacks",0))==2, "IP03 shared1.5s unaffected by repeated hurt")
	advance(reaction,0.8)
	reaction.damage_player(10.0)
	check(is_ready(reaction) and reaction.cast_log.size()==1, "IP03 next actual loss opens one window without natural recast")
	var zero = fresh(["I09","I01"])
	grant(zero,"IP03")
	release_once(zero,"I09")
	zero.damage_player(0.0)
	check(int(state(zero).get("stacks",0))==1, "zero loss cannot trigger reaction")
	zero.player.shield=0.0
	zero.damage_player(999999.0)
	check(zero.phase=="dead" and state(zero).is_empty(), "fatal loss has no reaction or resurrection")
	for source in ["I05","I06"]:
		for natural in [true,false]:
			var winter = fresh([source,"I01","I10"])
			grant(winter,"IG01")
			release_once(winter,source,natural)
			advance(winter,1.5)
			observations.append({"probe":"IG01_second_chill","source":source,"natural":natural,"damage":winter.damage_log.duplicate(true),"state":state(winter),"ordinals":winter._spell_combat.ice._chill_ordinals.duplicate(true),"hits":winter._spell_combat.ice._effective_hits.duplicate(true)})
			check(is_ready(winter)==natural, "IG01 only natural second qualified chill " + source + str(natural))
	for natural in [true,false]:
		var king = fresh(["I07","I01"])
		grant(king,"IB07")
		grant(king,"IG02")
		ready(king)
		release_once(king,"I07",natural,1.0 if natural else 0.7)
		check(near(king.damage_dealt,484.0 if natural else 238.0), "IB07 flat addition before natural IG02 multiplier " + str(natural))
		check(int(state(king).get("stacks",0))==(1 if natural else 0), "only natural gold leaves one frost")
		check(near(float(state(king).get("immunity_remaining",0.0)),3.0), "retained layer never clears early-shatter immunity")
	var king_gate = fresh(["I07","I01"])
	grant(king_gate,"IG02")
	ready(king_gate)
	release_once(king_gate,"I07")
	advance(king_gate,1.0)
	ready(king_gate)
	var before: float=king_gate.damage_dealt
	release_once(king_gate,"I07")
	check(near(king_gate.damage_dealt-before,300.0), "IG02 per-actor2s gate rejects second gold multiplier")
	advance(king_gate,1.0)
	ready(king_gate)
	before=king_gate.damage_dealt
	release_once(king_gate,"I07")
	check(near(king_gate.damage_dealt-before,420.0), "IG02 same actor valid again at exact2s")
	check(near(float(state(king_gate).get("immunity_until",-99)),3.0), "crack-only shatter and retained frost never reset old immunity")
	var covenant = fresh(["I08","I09"])
	grant(covenant,"IG03")
	grant(covenant,"GT01")
	covenant.player.shield=90.0
	release_once(covenant,"I08")
	advance(covenant,0.3)
	check(near(float(covenant.player.shield),100.0), "IG03 restores only actual ten deficit after GT01 amplification")
	check(near(float(covenant._artifact_combat.state_snapshot().generic.get("charge",-99)),40.0), "IG03 GT01 stores actual10 times4, not requested31.25")
	covenant.player.shield=80.0
	release_once(covenant,"I08")
	advance(covenant,0.3)
	check(near(float(covenant.player.shield),80.0), "existing ready window gives no gold shield")
	var extra_covenant = fresh(["I08","I09"])
	grant(extra_covenant,"IG03")
	extra_covenant.player.shield=0.0
	release_once(extra_covenant,"I08",false)
	advance(extra_covenant,0.3)
	check(is_ready(extra_covenant) and near(float(extra_covenant.player.shield),0.0), "additional coffin keeps window mechanism but no natural gold restore")
	for deficit in [0.0,100.0]:
		var actual_restore = fresh(["I08","I09"])
		grant(actual_restore,"IG03")
		grant(actual_restore,"GT01")
		actual_restore.player.shield=float(actual_restore.player.max_shield)-deficit
		release_once(actual_restore,"I08")
		advance(actual_restore,0.3)
		var restored: float=0.0 if deficit==0.0 else 31.25
		check(near(float(actual_restore.player.shield),100.0-deficit+restored), "IG03 actual request25 times1.25 capped by deficit " + str(deficit))
		check(near(float(actual_restore._artifact_combat.state_snapshot().generic.charge),restored*4.0), "gold overflow never becomes GT01 charge " + str(deficit))

func dynamic_scope_and_general_items():
	var dynamic = fresh(["I03"])
	release_once(dynamic,"I03")
	dynamic.player.attack=200.0
	advance(dynamic,0.35)
	check(near(dynamic.damage_dealt,360.0), "ice delayed hit reads current attack")
	var release_values = fresh(["I03"])
	release_once(release_values,"I03")
	release_values._owned_spell("I03").level=3
	release_values._refresh_spell(release_values._owned_spell("I03"))
	advance(release_values,0.8)
	check(near(release_values.damage_dealt,180.0), "in-flight ice keeps released coefficient/level and does not gain future L3 followup")
	var field = fresh(["I03","F06"])
	release_once(field,"F06")
	release_once(field,"I03")
	field.player.pos=Vector2(5,0)
	field.player.previous=field.player.pos
	advance(field,0.35)
	check(near(source_damage(field,"I03"),180.0), "ice cannot retain vanished F06 release snapshot")
	var old_fire = fresh(["F01","F06"])
	old_fire.actors=[actor(1,Vector2(0,4))]
	release_once(old_fire,"F06")
	release_once(old_fire,"F01")
	old_fire.player.pos=Vector2(5,0)
	old_fire.player.previous=old_fire.player.pos
	advance(old_fire,0.3)
	check(near(source_damage(old_fire,"F01"),120.0), "ice realtime policy does not migrate existing fire field snapshot")
	var mastery = fresh(["I01","I02","I10"],3)
	var result: Dictionary=mastery.resolve_spell_hit(mastery.actors[0],1.0,context())
	check(near(float(result.damage),145.0), "three ice10 plus mastery35 additive")
	result=mastery.resolve_spell_hit(mastery.actors[0],1.0,context("F01",2,true,"bolt"))
	check(near(float(result.damage),100.0), "ice mastery and resonance never amplify fire")
	mastery.extra_cdr=0.9
	ticks(mastery,1)
	check(near(float(mastery._owned_spell("I01").cooldown),1.3*0.4), "ice total CDR60cap")
	var minimum = fresh(["I01"])
	minimum._base.spells.I01.cooldown=0.01
	minimum._base.spells.I01.levels[0].cooldown=0.01
	minimum.extra_cdr=0.9
	ticks(minimum,1)
	check(near(float(minimum.spells[0].cooldown),0.2), "explicit controlled .01 base CD still floors .2 without changing runtime data")
	for rate in [1.0,1.8]:
		var crit = fresh()
		crit.player.crit_rate=rate
		result=crit.resolve_spell_hit(crit.actors[0],1.0,context())
		check(result.critical and near(float(result.damage),150.0), "ice crit100plus always single critical " + str(rate))
	var echo = fresh(["I01","F01"])
	grant(echo,"P04")
	for id in ["I01","F01","I01"]: release_once(echo,id)
	check(echo.extra_log.size()==1 and echo._artifact_combat._natural_casts==3, "mixed natural casts advance universal P04 once")
	var clock = fresh(["I01","F01"])
	grant(clock,"P05")
	clock._owned_spell("I01").remaining=10.0
	clock._owned_spell("F01").remaining=10.0
	advance(clock,8.0)
	check(float(clock._owned_spell("I01").remaining)<2.0 and float(clock._owned_spell("F01").remaining)<2.0, "P05 independent8s timer reduces both schools")

func actual_enemy_freeze():
	var b = fresh()
	b.simulate_enemy_ai=true
	b.actors=[b._enemy_combat.make_actor(b,"M02",Vector2(0,5),1)]
	var enemy: Dictionary=b.actors[0]
	var spec: Dictionary=enemy.combat_spec
	b._enemy_combat._start_warning(b,enemy,spec,float(spec.warning))
	var warning: float=float(enemy.warning_remaining)
	var aim: Vector2=enemy.attack_to
	b._enemy_combat._shoot(b,enemy,spec)
	var shots: Array=b._enemy_combat.get_projectiles()
	check(not shots.is_empty(), "actual shooter emitted independent projectile")
	ready(b)
	var shield_before: float=float(b.player.shield)
	advance(b,0.5)
	check(near(float(enemy.warning_remaining),warning) and enemy.attack_to==aim, "freeze preserves warning countdown and locked aim")
	var after: Array=b._enemy_combat.get_projectiles()
	check(after.size()<shots.size() or (not after.is_empty() and after[0].pos!=shots[0].pos) or float(b.player.shield)<shield_before, "detached enemy projectile moves or hits during owner freeze")
	check(near(b.combat_time,0.5), "world combat clock continues during enemy hard freeze")
	advance(b,0.7)
	ticks(b,1)
	check(float(enemy.warning_remaining)<warning and enemy.attack_to==aim, "unfreeze resumes old warning without retarget")
	var lunge = fresh()
	lunge.simulate_enemy_ai=true
	lunge.actors=[lunge._enemy_combat.make_actor(lunge,"M01",Vector2(0,1.2),1)]
	var body: Dictionary=lunge.actors[0]
	lunge._enemy_combat._start_warning(lunge,body,body.combat_spec,0.1)
	lunge._enemy_combat._start_attack(lunge,body,body.combat_spec)
	var start: Vector2=body.pos
	var hp: float=float(lunge.player.health)+float(lunge.player.shield)
	ready(lunge)
	advance(lunge,0.5)
	check(body.pos==start and near(float(body.attack_elapsed),0.0), "frozen lunge body and active timer both hang")
	check(near(float(lunge.player.health)+float(lunge.player.shield),hp), "frozen body cannot deal contact/lunge damage")
	var reaction = fresh(["I09","I01"],2)
	reaction.simulate_enemy_ai=true
	reaction.actors=[reaction._enemy_combat.make_actor(reaction,"M04",Vector2(0,5),1),reaction._enemy_combat.make_actor(reaction,"M02",Vector2(0,2),2)]
	release_once(reaction,"I09")
	frost(reaction,1,2)
	var mark: Dictionary=reaction.actors[0]
	var later: Dictionary=reaction.actors[1]
	reaction._enemy_combat._start_warning(reaction,mark,mark.combat_spec,0.1)
	reaction._enemy_combat._start_attack(reaction,mark,mark.combat_spec)
	reaction._enemy_combat._start_warning(reaction,later,later.combat_spec,float(later.combat_spec.warning))
	var later_warning: float=float(later.warning_remaining)
	ready(reaction,1)
	var life_before: float=float(reaction.player.health)+float(reaction.player.shield)
	ticks(reaction,1)
	check(float(mark.attack_elapsed)>0.0 and float(reaction.player.health)+float(reaction.player.shield)<life_before, "already-released ground mark continues while owner frozen")
	check(is_ready(reaction,2) and near(float(later.warning_remaining),later_warning), "armor growth freezes later enemy immediately within same actor loop without one-step AI leak")

func pause_cleanup():
	var b = fresh(["I05","I09","I08"])
	release_once(b,"I05")
	release_once(b,"I09")
	ready(b)
	var ice_before: Array=b.get_snapshot().get("ice_states",[])
	var armor_before: float=b._spell_combat.ice.defense_remaining
	var damage_before: float=b.damage_dealt
	b.set_paused(true)
	advance(b,2.0)
	check(b.get_snapshot().get("ice_states",[])==ice_before and near(b._spell_combat.ice.defense_remaining,armor_before) and near(b.damage_dealt,damage_before), "pause freezes state/timers/pending/armor")
	b.set_paused(false)
	b.phase="reward"
	advance(b,2.0)
	check(b.get_snapshot().get("ice_states",[])==ice_before and near(b._spell_combat.ice.defense_remaining,armor_before) and near(b.damage_dealt,damage_before), "choice only route time, no ice catchup")
	b._stop_combat()
	check(b.get_snapshot().get("ice_states",[]).is_empty() and near(b._spell_combat.ice.defense_bonus(),0.0), "clear removes frost/ready/immunity/armor")
	b._enter_room(2)
	check(b.get_snapshot().get("ice_states",[]).is_empty(), "room actor ID reuse has no old frost")
	var death = fresh(["I09","I03"])
	release_once(death,"I09")
	release_once(death,"I03")
	frost(death,3)
	death.player.shield=0.0
	death.damage_player(999999.0)
	advance(death,2.0)
	check(death.phase=="dead" and death.get_snapshot().get("ice_states",[]).is_empty() and near(death.damage_dealt,0.0), "death cancels pending ice impact and all statuses")

func high_cdr_eight_slot_state_stress():
	var b = fresh(["I01","I02","I03","I04","I05","I06","I08","I10"],3)
	b.extra_cdr=0.9
	grant(b,"P04")
	grant(b,"P05")
	for spell in b.spells: spell.remaining=0.0
	var last_token: int=-1
	var last_until: float=0.0
	var previous_frozen: bool=false
	var freeze_start: float=0.0
	var last_end: float=-INF
	var minimum_gap: float=INF
	var maximum_hard: float=0.0
	var hard_time: float=0.0
	var window_refreshes: int=0
	var invalid_states: int=0
	var periods: Array=[]
	for index in 60*120:
		ticks(b,1)
		var now: float=b._spell_combat.ice.status.clock
		var current: Dictionary=state(b)
		if b._spell_combat.ice.status.states.size()>1 or int(current.get("stacks",0)) not in [0,1,2,3]: invalid_states+=1
		var captured: Dictionary=b._spell_combat.ice.status.capture_ready(1)
		if not captured.is_empty():
			if int(captured.token)==last_token and not near(float(captured.ready_until),last_until): window_refreshes+=1
			last_token=int(captured.token)
			last_until=float(captured.ready_until)
		var frozen: bool=b._spell_combat.ice.status.is_frozen(1)
		hard_time+=b._spell_combat.ice.status.frozen_frame_time(1)
		if frozen and not previous_frozen:
			freeze_start=now
			if is_finite(last_end): minimum_gap=minf(minimum_gap,now-last_end)
		elif previous_frozen and not frozen:
			maximum_hard=maxf(maximum_hard,now-freeze_start)
			last_end=now
			periods.append({"start":freeze_start,"end":now})
		previous_frozen=frozen
		if index%120==0:
			var snapshot: Array=b.get_snapshot().ice_states
			if snapshot.size()>1: invalid_states+=1
	if previous_frozen: maximum_hard=maxf(maximum_hard,60.0-freeze_start)
	check(near(b.combat_time,60.0) and float(b.actors[0].health)>0.0,"stress actually advances60 combat seconds against live target")
	check(b.cast_log.size()>60 and not b.extra_log.is_empty(),"eight independent natural spells and real P04 extras executed")
	check(invalid_states==0 and window_refreshes==0,"maximal natural/extra stream preserves one bounded unextended stage")
	check(periods.size()>=2 and minimum_gap>=3.0-2.0/120.0,"every repeated hard freeze respects3s gap")
	check(maximum_hard<=2.0+1.0/120.0 and hard_time<=24.1,"60s hard-control time stays within largest2s freeze/3s immunity envelope")
	observations.append({"probe":"eight_slot_60s_60cdr_P04_P05","casts":b.cast_log.size(),"extra_calls":b.extra_log.size(),"hard_seconds":hard_time,"minimum_thaw_gap":minimum_gap,"maximum_hard_period":maximum_hard,"periods":periods,"window_refreshes":window_refreshes,"invalid_states":invalid_states})
