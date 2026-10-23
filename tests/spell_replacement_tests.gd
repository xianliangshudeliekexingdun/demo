extends SceneTree
## Actual Route transactions under explicit controlled reward/loadout fixtures.
const Route = preload("res://scripts/core/courtyard_route_run.gd")
const First = preload("res://scripts/core/first_room_run.gd")
const Sources = preload("res://tests/formal_ice_source_binding.gd")
const OUT = "res://build/qa/six-schools-implementation-20261021/spell-replacement/"
const FULL = ["F01","F02","F03","F05","F06","F07","F08","F09"]
var checks: int = 0
var failures: Array = []
var groups: Array = []
var observations: Array = []
var initial_sources: Dictionary = {}

func _initialize(): call_deferred("execute")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures.append(label)
		push_error("Spell replacement: "+label)
func near(a: float,b: float)->bool: return absf(a-b)<0.00001
func group(id: String, action: Callable):
	var start: int=checks
	var failed: int=failures.size()
	action.call()
	groups.append({"id":id,"checks":checks-start,"failures":failures.size()-failed})
func fresh(ids: Array=FULL, level: int=1):
	var b=Route.new()
	check(b.configure({},20261018).ok and b.choose_initial("F01"),"actual Route configure/start")
	b.spells.clear()
	for id in ids:
		var spell: Dictionary=b._new_spell(str(id))
		spell.level=level
		b._refresh_spell(spell)
		spell.remaining=2.25+float(b.spells.size())*.25
		b.spells.append(spell)
	return b
func offer(b, ids: Array):
	b.phase="reward"
	b.portal.visible=true
	b.portal.usable=false
	b.reward_choices.clear()
	for id in ids: b.reward_choices.append(b._choice(str(id)))
func grant(b,id: String):
	b._artifact_combat._owned.append(id)
	b._artifact_combat.apply_acquisition(b,id)
func advance(b,seconds: float):
	for _tick in roundi(seconds*120): b.step(1.0/120.0,Vector2.RIGHT)
func frozen(snapshot: Dictionary)->Dictionary:
	var result: Dictionary=snapshot.duplicate(true)
	result.erase("time")
	result.erase("room_time")
	return result
func begin(b,id: String)->int:
	check(b.choose_reward(id,b.room_revision),"actual offered new spell opens replacement "+id)
	return int(b.pending_replacement.get("request_id",-1))
func assert_unchanged(b, before: Dictionary, label: String):
	check(b.get_snapshot()==before,label)

func execute():
	initial_sources=Sources.capture(["res://tests/spell_replacement_tests.gd"])
	group("pool_and_legacy",pool_and_legacy)
	group("append_and_upgrade",append_and_upgrade)
	group("pending_cancel_and_rng",pending_cancel_and_rng)
	group("confirm_and_invalid_requests",confirm_and_invalid_requests)
	group("pause_stale_and_mutation",pause_stale_and_mutation)
	group("passive_synergy_and_items",passive_synergy_and_items)
	group("physical_pickup_once",physical_pickup_once)
	group("approved_all_new_skip",approved_all_new_skip)
	check(Sources.capture(["res://tests/spell_replacement_tests.gd"])==initial_sources,"actual rule dependency bytes fixed during run")
	var output: String = OUT
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with("--qa-out=res://build/qa/") and not str(argument).contains(".."):
			output = str(argument).trim_prefix("--qa-out=").path_join("")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output+"rules.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"details":failures,"groups":groups,"observations":observations,"source_sha256":initial_sources,"source_stable":Sources.capture(["res://tests/spell_replacement_tests.gd"])==initial_sources,"engine":Engine.get_version_info(),"scope":"Actual Route transactions; specified loadouts/reward fixtures and explicit kill-clear pickup fixture. Not natural acquisition, player win rate or runtime balance changes."},"\t"))
	print("SPELL REPLACEMENT RULES checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func pool_and_legacy():
	for size in range(0,9):
		for level in [1,2,3]:
			var b=fresh(FULL.slice(0,size),level)
			var eligible: Array=b.eligible_reward_ids()
			check(eligible.size()==57-(size if level==3 else 0),"legal pool retains unowned spells with slots%d lv%d"%[size,level])
			check("F04" not in eligible and "I01" in eligible,"archived spirit excluded, other school stays legal")
			var sampled: Array=b._sample_rewards()
			check(sampled.size()==3,"three real weighted candidates at slots%d lv%d"%[size,level])
			var seen: Array=[]
			for card in sampled:
				check(str(card.id) in eligible and str(card.id) not in seen,"actual sampling legal without replacement")
				seen.append(str(card.id))
	var old=First.new()
	check(old.configure().ok and old.choose_initial("F01"),"legacy standalone configures")
	old.spells.clear()
	for id in ["F01","F02","F03","F04","F05","F06","F07","F08"]:
		var spell: Dictionary=old._new_spell(id)
		spell.level=3
		old._refresh_spell(spell)
		old.spells.append(spell)
	check(old.eligible_reward_ids().is_empty(),"legacy standalone still has old full-slot behavior")

func append_and_upgrade():
	for size in [1,7]:
		var b=fresh(FULL.slice(0,size))
		offer(b,["I01","F01","I02"])
		check(b.choose_reward("I01",b.room_revision),"underfilled inventory learns directly")
		check(b.spells.size()==size+1 and b.spells.back().id=="I01" and b.spells.back().level==1,"append exactly one level1")
		check(b.phase=="exit" and b.portal.usable and b.pending_replacement.is_empty() and b.reward_choices.is_empty(),"direct learn consumes one reward")
		var before: Dictionary=b.get_snapshot()
		check(not b.choose_reward("I01",b.room_revision),"direct learn duplicate rejected")
		assert_unchanged(b,before,"duplicate direct learn has no side effect")
	for level in [1,2]:
		var b=fresh(FULL,level)
		offer(b,["F01","I01","I02"])
		var others: Array=b.spells.slice(1).duplicate(true)
		var remaining: float=b.spells[0].remaining
		check(b.choose_reward("F01",b.room_revision),"owned spell upgrades without replacement at full slots")
		check(b.spells.size()==8 and b.spells[0].level==level+1 and b.spells[0].remaining==remaining and b.pending_replacement.is_empty(),"upgrade preserves slot and existing cooldown progress")
		check(b.spells.slice(1).map(func(s):return [s.id,s.level,s.remaining])==others.map(func(s):return [s.id,s.level,s.remaining]),"upgrade leaves other inventory/progress intact")

func pending_cancel_and_rng():
	var b=fresh(FULL,3)
	offer(b,["I01","I02","I03"])
	var cards: Array=b.reward_choices.duplicate(true)
	var spells: Array=b.spells.duplicate(true)
	var rng: int=b._rng.state
	var charge: Dictionary=b.get_snapshot().generic_items
	var token: int=begin(b,"I01")
	check(token>0 and b.phase=="reward" and not b.portal.usable,"replacement pending retains reward phase and closed gate")
	check(b.spells==spells and b.reward_choices==cards and b._rng.state==rng,"opening pending does not consume old spell, original offer or RNG")
	var exposed: Dictionary=b.get_snapshot()
	exposed.pending_replacement.slots[0].level=99
	check(b.spells==spells and b.pending_replacement.slots==spells,"pending snapshot deeply independent")
	var frozen_before: Dictionary=b.get_snapshot()
	advance(b,1.0)
	check(near(b.time,float(frozen_before.time)+1.0) and frozen(b.get_snapshot())==frozen(frozen_before),"pending selection advances route time only; actor/cooldown/status/artifact frozen")
	check(b.get_snapshot().generic_items==charge,"generic timers frozen while deciding")
	check(b.cancel_spell_replacement(token,b.room_revision),"cancel returns to original three")
	check(b.spells==spells and b.reward_choices==cards and b._rng.state==rng and b.phase=="reward" and not b.portal.usable,"cancel preserves inventory/RNG/cards/gate")
	var token2: int=begin(b,"I02")
	check(token2>token and b.pending_replacement.spell_id=="I02","new request after cancellation has fresh token")
	var before: Dictionary=b.get_snapshot()
	check(not b.confirm_spell_replacement(0,token,b.room_revision) and not b.cancel_spell_replacement(token,b.room_revision),"old token cannot commit or cancel new pending")
	assert_unchanged(b,before,"old requests leave current pending intact")
	check(not b.choose_reward("I03",b.room_revision),"another reward cannot bypass pending transaction")
	check(b.cancel_spell_replacement(token2),"legacy optional revision compatible")

func confirm_and_invalid_requests():
	for slot in range(8):
		var b=fresh(FULL,3)
		grant(b,"B01")
		offer(b,["I01","I02","I03"])
		var spells: Array=b.spells.duplicate(true)
		var owned: Array=b.get_snapshot().artifacts.duplicate(true)
		var money: Array=[b.gold,b.dust,b.player.health,b.player.shield]
		var token: int=begin(b,"I01")
		check(b.confirm_spell_replacement(slot,token,b.room_revision),"valid atomic confirmation at slot%d"%slot)
		check(b.spells.size()==8 and b.spells[slot].id=="I01" and b.spells[slot].level==1,"replacement retains eight slots and resets new spell to level1")
		check(near(b.spells[slot].remaining,0) and near(b.spells[slot].cast_remaining,0) and b.spells[slot].target_id==-1,"new spell inherits no cooldown, windup or target")
		for index in range(8):
			if index!=slot: check(b.spells[index].id==spells[index].id and b.spells[index].level==3 and b.spells[index].remaining==spells[index].remaining,"all unselected slots and remaining cooldowns preserved")
		check(b.get_snapshot().artifacts==owned and [b.gold,b.dust,b.player.health,b.player.shield]==money,"replacement preserves treasures/attributes/currency")
		check(b.phase=="exit" and b.portal.usable and b.pending_replacement.is_empty() and b.reward_choices.is_empty(),"confirmed one reward atomically opens gate")
		var before: Dictionary=b.get_snapshot()
		check(not b.confirm_spell_replacement(slot,token) and not b.cancel_spell_replacement(token) and not b.choose_reward("I02"),"duplicate confirmation/cancel/choice rejected after consumption")
		assert_unchanged(b,before,"duplicates do not remove another spell")
	var b=fresh()
	offer(b,["I01","I02","I03"])
	var token: int=begin(b,"I01")
	for invalid in [-1,8,99]:
		var before: Dictionary=b.get_snapshot()
		check(not b.confirm_spell_replacement(invalid,token,b.room_revision),"invalid slot rejected "+str(invalid))
		assert_unchanged(b,before,"invalid slot keeps transaction")
	check(not b.confirm_spell_replacement(0,token+999) and not b.cancel_spell_replacement(token+999),"wrong request ID rejected")
	check(not b.confirm_spell_replacement(0,token,b.room_revision-1) and not b.cancel_spell_replacement(token,b.room_revision-1),"wrong expected room revision rejected")

func pause_stale_and_mutation():
	var b=fresh()
	offer(b,["I01","I02","I03"])
	var token: int=begin(b,"I01")
	b.set_paused(true)
	var paused: Dictionary=b.get_snapshot()
	advance(b,1)
	check(b.get_snapshot()==paused,"pause freezes even total route time and pending")
	check(not b.confirm_spell_replacement(0,token) and not b.cancel_spell_replacement(token) and not b.choose_reward("I02"),"paused choice/confirm/cancel cannot transact")
	assert_unchanged(b,paused,"paused requests leave selection unchanged")
	b.set_paused(false)
	check(b.confirm_spell_replacement(0,token),"resume can confirm same pending request")
	for field in ["level","remaining"]:
		b=fresh()
		offer(b,["I01","I02","I03"])
		token=begin(b,"I01")
		b.spells[4][field]+=1
		var before: Dictionary=b.get_snapshot()
		check(not b.confirm_spell_replacement(0,token),"stale original inventory detected: "+field)
		assert_unchanged(b,before,"failed stale inventory commit is atomic")
	b=fresh()
	offer(b,["I01","I02","I03"])
	token=begin(b,"I01")
	var revision: int=b.room_revision
	b._enter_room(2)
	offer(b,["I01","I02","I03"])
	var before: Dictionary=b.get_snapshot()
	check(b.pending_replacement.is_empty() and not b.confirm_spell_replacement(0,token,revision) and not b.cancel_spell_replacement(token,revision) and not b.choose_reward("I01",revision),"old room requests cannot touch next room")
	assert_unchanged(b,before,"cross-room stale request leaves new cards intact")
	b=fresh()
	offer(b,["I01","I02","I03"])
	token=begin(b,"I01")
	b.player.health=0
	before=b.get_snapshot()
	check(not b.confirm_spell_replacement(0,token) and not b.cancel_spell_replacement(token),"dead player cannot commit or cancel")
	assert_unchanged(b,before,"dead request has no mutation")

func passive_synergy_and_items():
	var ids: Array=["F01","F02","F03","I01","I02","I03","I09","I10"]
	for old_id in ["F02","F03","I10"]:
		var b=fresh(ids,3)
		grant(b,"U01")
		grant(b,"P05")
		var initial: Dictionary=b.get_snapshot().combat_stats
		var old_remaining: Array=b.spells.map(func(s):return s.remaining)
		var new_id: String="I04" if old_id!="I10" else "F05"
		offer(b,[new_id,"F08","I08"])
		var token: int=begin(b,new_id)
		var slot: int=ids.find(old_id)
		check(b.confirm_spell_replacement(slot,token),"replace passive or third school member "+old_id)
		var after: Dictionary=b.get_snapshot().combat_stats
		if old_id=="F02": check(float(after.fire_bonus)<float(initial.fire_bonus),"removing fire mastery immediately removes its damage bucket")
		if old_id=="F03": check(not after.fire_synergy_active and after.fire_cooldown_reduction<float(initial.fire_cooldown_reduction),"third-fire loss immediately removes resonance and cooldown bonus")
		if old_id=="I10": check(float(after.ice_bonus)<float(initial.ice_bonus),"removing ice passive immediately removes its damage bucket")
		for i in range(8):
			if i!=slot: check(b.spells[i].remaining==old_remaining[i],"recalculated school stats preserve old remaining cooldown")
		var cached: Array=b.spells.map(func(s):return [s.cooldown,s.windup,s.range])
		b.phase="combat"
		b._spell_combat.update(b,0)
		check(b.spells.map(func(s):return [s.cooldown,s.windup,s.range])==cached,"reward refresh agrees with next actual combat parameter recomputation")
		check(b._artifact_combat.has_artifact("U01") and b._artifact_combat.has_artifact("P05"),"school replacement never deletes held treasures")
		if new_id=="I04":
			var stats: Dictionary=b.get_spell_stats(b._owned_spell("I04"))
			check(near(float(stats.level.radius),float(b._base.spells.I04.levels[0].radius)),"replacement starts at canonical level one without retired blue bonus")
		observations.append({"removed":old_id,"new":new_id,"before":initial,"after":after})
	var b=fresh(["I01","I02","I10","F01","F02","F03","F06","F08"],3)
	offer(b,["I08","F05","I09"])
	var token: int=begin(b,"F05")
	check(b.confirm_spell_replacement(2,token),"replace third ice passive with another school")
	check(not b.get_snapshot().combat_stats.ice_synergy_active and near(b.get_snapshot().combat_stats.ice_cooldown_reduction,0),"two remaining ice spells lose ice resonance immediately")

func physical_pickup_once():
	var b=fresh(FULL,3)
	for _guard in range(1500):
		if b.phase!="combat":break
		b.step(1.0/120.0)
		for enemy in b.actors:
			if enemy.health>0: b.damage_enemy(enemy,enemy.health)
	check(b.phase=="pickup" and b.reward_choices.size()==3 and not b.portal.usable,"maxed inventory still creates one real spell book and three cached new candidates")
	check(b.reward_choices.all(func(c):return c.next_level==1 and c.is_new),"full maxed offer contains actual new level1 spells")
	var cards: Array=b.reward_choices.duplicate(true)
	check(not b.choose_reward(str(cards[0].id),b.room_revision),"cannot bypass physical reward contact")
	for _guard in range(3600):
		if b.phase!="pickup":break
		var point: Vector2=b._chase_position(b.player.pos,b.reward_pickup.pos,1,b.player.radius)
		b.step(1.0/120.0,(point-b.player.pos).normalized())
	check(b.phase=="reward" and b.reward_pickup.claimed and not b.reward_pickup.visible,"actual walking claims the unique book")
	var seq: int=b.event_seq
	var token: int=begin(b,str(cards[0].id))
	check(b.cancel_spell_replacement(token),"physical reward may return to cached cards")
	check(b.reward_choices==cards and b.reward_pickup.claimed and not b.reward_pickup.visible,"cancel does not respawn/reclaim book")
	token=begin(b,str(cards[1].id))
	check(b.confirm_spell_replacement(7,token),"physical reward replacement confirms once")
	check(b.spells.size()==8 and b.portal.usable and b.phase=="exit","one physical reward leaves eight slots and opens portal")
	check(not b.choose_reward(str(cards[2].id),b.room_revision),"no second award after physical replacement")
	check(b.effects.filter(func(e):return e.kind=="reward" and e.seq>seq).size()==1,"exactly one final reward event despite cancel/reopen")

func approved_all_new_skip():
	for level in [1,2,3]:
		var b=fresh(FULL,level)
		grant(b,"B01")
		offer(b,["I01","I02","I03"])
		check(b.can_skip_spell_reward() and b.get_snapshot().can_skip_spell_reward,"full all-new offer can be declined even if carried spells are not all maxed")
		var spells: Array=b.spells.duplicate(true)
		var owned: Array=b.get_snapshot().artifacts.duplicate(true)
		var rng: int=b._rng.state
		var before: Dictionary=b.get_snapshot()
		check(not b.skip_spell_reward(b.room_revision-1),"stale revision skip rejected")
		assert_unchanged(b,before,"stale skip cannot consume current node")
		var token: int=begin(b,"I01")
		check(not b.can_skip_spell_reward() and not b.get_snapshot().can_skip_spell_reward,"replacement pending must first be cancelled before declining reward")
		before=b.get_snapshot()
		check(not b.skip_spell_reward(b.room_revision),"skip cannot bypass pending")
		assert_unchanged(b,before,"pending skip has no side effects")
		check(b.cancel_spell_replacement(token,b.room_revision) and b.can_skip_spell_reward(),"cancel restores original all-new skip eligibility")
		b.set_paused(true)
		before=b.get_snapshot()
		check(not b.skip_spell_reward(b.room_revision),"paused skip rejected")
		assert_unchanged(b,before,"paused skip leaves all state fixed")
		b.set_paused(false)
		var seq: int=b.event_seq
		check(b.skip_spell_reward(b.room_revision),"approved all-new offer skipped exactly once")
		check(b.spells==spells and b.get_snapshot().artifacts==owned and b._rng.state==rng,"skip preserves full old spells/levels/CDs, treasures and RNG")
		check(b.phase=="exit" and b.portal.usable and b.reward_choices.is_empty() and b.pending_replacement.is_empty(),"skip consumes current offer and opens portal")
		check(b._reward_claimed_revision==b.room_revision and not b.can_skip_spell_reward(),"skip consumes same revision as learning")
		check(b.effects.filter(func(e):return e.kind=="reward_skipped" and e.seq>seq).size()==1,"skip has one explicit non-learning event")
		before=b.get_snapshot()
		check(not b.skip_spell_reward() and not b.choose_reward("I01") and not b.confirm_spell_replacement(0,token),"duplicate skip/learning/old commit rejected after decline")
		assert_unchanged(b,before,"duplicate skip does not change inventory or award")
	for size in [0,1,7]:
		var b=fresh(FULL.slice(0,size))
		offer(b,["I01","I02","I03"])
		var before: Dictionary=b.get_snapshot()
		check(not b.can_skip_spell_reward() and not b.skip_spell_reward(b.room_revision),"underfilled inventory cannot use full-slot decline")
		assert_unchanged(b,before,"underfilled decline leaves real reward available")
	for ids in [["F01","I01","I02"],["F01","F02","F03"],[]]:
		var b=fresh()
		offer(b,ids)
		var before: Dictionary=b.get_snapshot()
		check(not b.can_skip_spell_reward() and not b.skip_spell_reward(b.room_revision),"mixed upgrade offer or empty cards cannot be declined")
		assert_unchanged(b,before,"upgrade/empty offer rejected without mutation")
	for phase in ["combat","pickup","artifact","exit","complete","dead"]:
		var b=fresh()
		offer(b,["I01","I02","I03"])
		b.phase=phase
		var before: Dictionary=b.get_snapshot()
		check(not b.can_skip_spell_reward() and not b.skip_spell_reward(b.room_revision),"skip rejected outside reward "+phase)
		assert_unchanged(b,before,"wrong-phase skip is atomic")
	var b=fresh()
	offer(b,["I01","I02","I03"])
	var revision: int=b.room_revision
	b._enter_room(2)
	offer(b,["I01","I02","I03"])
	var before: Dictionary=b.get_snapshot()
	check(not b.skip_spell_reward(revision),"previous room skip rejected")
	assert_unchanged(b,before,"previous room skip preserves current offer")
