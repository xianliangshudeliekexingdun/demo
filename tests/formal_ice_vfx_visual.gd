extends SceneTree
## Explicit controlled live-core/VFX fixtures; never a naturally acquired run.
const Rules = preload("res://tests/formal_ice_tests.gd")
const View = preload("res://scripts/presentation/first_room_view.gd")
const T = preload("res://scripts/ui/atelier_theme.gd")
const SourceBinding = preload("res://tests/formal_ice_source_binding.gd")
const OUT="res://build/qa/formal-ice-implementation-20261018/vfx-fixtures/"
var battle
var view
var caption: Label
var checks: int=0
var failures: Array=[]
var captures: Array=[]
var samples: Array=[]
var before: Dictionary={}
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if not ok:
		failures.append(label)
		push_error("Formal ice controlled VFX: "+label)
func sources() -> Dictionary:
	var result: Dictionary={}
	for path in ["res://tests/formal_ice_vfx_visual.gd","res://tests/formal_ice_tests.gd","res://scripts/core/courtyard_route_run.gd","res://scripts/core/route_ice_combat.gd","res://scripts/core/route_ice_status.gd","res://scripts/core/route_spell_combat.gd","res://scripts/core/route_artifacts.gd","res://scripts/core/route_ice_artifacts.gd","res://data/ice_spells_v1.json","res://data/ice_artifacts_v1.json","res://scripts/presentation/first_room_view.gd","res://scripts/presentation/route_spell_vfx.gd"]:
		result[path]=FileAccess.get_sha256(path)
	result.merge(SourceBinding.capture(["res://tests/formal_ice_vfx_visual.gd","res://scripts/presentation/first_room_view.gd","res://project.godot"]),true)
	return result
func advance(seconds: float):
	for _index in roundi(seconds*120.0): battle.step(1.0/120.0)
func stop_natural():
	for spell in battle.spells:
		spell.remaining=9999.0
		spell.cast_remaining=0.0
func release(id: String):
	var spell: Dictionary=battle._owned_spell(id)
	var stats: Dictionary=battle.get_spell_stats(spell)
	var target: Dictionary=battle._spell_combat.legal_target(battle,spell,stats)
	check(not target.is_empty(),"actual controlled legal target "+id)
	if target.is_empty(): return
	spell.locked_pos=target.pos
	battle._spell_combat._cast(battle,spell,stats,target,true,1.0)
	stop_natural()
func snap(label: String,text: String):
	caption.text=text
	var snapshot: Dictionary=battle.get_snapshot()
	view.sync(snapshot,0.0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+label+".png")==OK,"actual production ice pixels "+label)
	check(battle.get_snapshot()==snapshot,"view never changes controlled rules "+label)
	captures.append(label)
	samples.append({"label":label,"snapshot":snapshot,"vfx":view.get_vfx_debug_state()})
func coverage(key: String,label: String):
	check(view.get_vfx_debug_state().coverage.has(key),label+" actual coverage "+key)
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	before=sources()
	check(DisplayServer.get_name()!="headless","native renderer required")
	if DisplayServer.get_name()=="headless":
		finish()
		return
	DisplayServer.window_set_size(Vector2i(1600,900))
	battle=Rules.Fixture.new()
	check(battle.configure({"route_school":"ice"},20261018).ok and battle.choose_initial("I01"),"actual ice Route configured and started")
	battle._spawn_done=true
	battle.spawn_warnings.clear()
	battle.blocks.clear()
	battle.player.pos=Vector2.ZERO
	battle.player.previous=Vector2.ZERO
	battle.player.crit_rate=0.0
	battle.spells.clear()
	for id in ["I01","I02","I03","I05","I06","I07","I08","I09"]:
		var spell: Dictionary=battle._new_spell(id)
		spell.level=3 if id in ["I03","I06","I07","I09"] else 1
		battle._refresh_spell(spell)
		battle.spells.append(spell)
	stop_natural()
	for id in ["IB07","IP02","IG02","IB09","IG03","GT01"]:
		battle._artifact_combat._owned.append(id)
		battle._artifact_combat.apply_acquisition(battle,id)
	battle.actors=[Rules.actor(1,Vector2(0,2.5),50000.0),Rules.actor(2,Vector2(-1.2,3.0),50000.0),Rules.actor(3,Vector2(1.3,2.8),50000.0),Rules.actor(4,Vector2(0,5.3),50000.0)]
	view=View.new()
	root.add_child(view)
	view.size=Vector2(1600,900)
	var layer=CanvasLayer.new()
	layer.layer=30
	root.add_child(layer)
	var panel=T.panel(layer,Rect2(24,20,1552,110))
	T.label(panel,"正式冰系 · 受控 core / VFX 专项",Rect2(24,6,1490,44),29,T.GOLD)
	caption=T.label(panel,"",Rect2(24,55,1490,43),20,T.TEXT)
	T.label(layer,"受控法术、宝物、敌人与回盾缺口；非自然库存。全部效果由真实 core 结算，只读显示。",Rect2(28,848,1544,36),19,T.MUTED)
	release("I01")
	advance(0.2)
	await snap("01-controlled-frost-one","真实霜弹命中后1层寒霜：低矮冷雾与层数状态来自同一份core状态。")
	coverage("ice_frost_status","one partial frost stage")
	release("I01")
	advance(0.2)
	await snap("02-controlled-frost-two","第二次真实霜弹形成2层；仍只是减速，尚未硬冻结。")
	release("I02")
	advance(0.0833333333)
	await snap("03-controlled-hard-frozen","真实冰锥使第3层开窗：普通敌硬冻结，其他目标可继续保留各自寒霜。")
	coverage("ice_frozen_status","hard frozen stage")
	battle.set_paused(true)
	var frozen: Dictionary=view.get_vfx_debug_state()
	var frozen_states: Array=battle.get_snapshot().ice_states
	advance(1.0)
	view.sync(battle.get_snapshot(),0.0)
	check(view.get_vfx_debug_state().clock==frozen.clock and battle.get_snapshot().ice_states==frozen_states,"pause freezes actual state and VFX clock")
	await snap("04-controlled-frozen-paused","真实暂停1秒：寒霜、冻结期限与表现时钟均冻结，不使用墙钟补进度。")
	battle.set_paused(false)
	advance(1.2)
	await snap("05-controlled-brittle-and-immunity","硬冻结已经结束，仍保留可兑现冰裂；免控状态独立于伤害窗口。")
	coverage("ice_brittle_status","brittle stage after natural thaw")
	coverage("ice_immunity_status","post-thaw immunity stage")
	release("I07")
	advance(0.0833333333)
	await snap("06-controlled-shatter-and-neighbor-shards","自然碎冰消费唯一旧窗口并发有限邻片；IG02留1层，不延长既有免控。")
	coverage("ice_shatter","old window consumed")
	coverage("ice_shard","finite actual neighboring shards")
	var guard: Dictionary=Rules.actor(5,Vector2(2.5,4.5),100000.0,"EL02_GUARD")
	battle.actors.append(guard)
	battle.player.shield=40.0
	release("I08")
	advance(0.3333333333)
	await snap("07-controlled-fixed-strong-crack","真实冰棺命中受控守门强敌：有冰裂、没有硬冻结；自然IG03仅恢复实际缺盾。")
	coverage("ice_coffin","coffin event")
	var strong_state: Dictionary=battle._spell_combat.ice.status.state_for(5)
	check(not strong_state.is_empty() and float(strong_state.freeze_remaining)<=0.000001,"fixed strong enemy remains unfrozen in rendered source")
	release("I05")
	release("I06")
	release("I09")
	advance(0.4)
	await snap("08-controlled-domain-storm-and-armor","真实领域、固定条带风暴与防御施霜；显示边界来自ice_zones及当前护体增益。")
	coverage("ice_domain","persistent domain")
	coverage("ice_storm","finite fixed storm")
	coverage("ice_guard","real defense spell event")
	release("I03")
	advance(0.4333333333)
	await snap("09-controlled-star-impact","真实寒星固定落点及三级有限后续；不由画面新增伤害或施霜。")
	coverage("ice_star","actual delayed ground impact")
	battle._stop_combat()
	battle.phase="pickup"
	await snap("10-controlled-clear-cleanup","实际清场后：寒霜、冰区、弹道、延迟与护体清空，不留跨房状态。")
	var clean: Dictionary=view.get_vfx_debug_state()
	check(clean.quad_count==0 and clean.core_count==0 and clean.coverage.is_empty(),"all combat ice VFX removed outside combat")
	check(battle.get_snapshot().ice_states.is_empty() and battle.get_snapshot().ice_zones.is_empty() and battle.get_snapshot().ice_pending.is_empty(),"actual core cleanup removes all temporary ice state")
	view.queue_free()
	await process_frame
	finish()
func finish():
	check(sources()==before,"controlled core and production renderer hashes fixed")
	FileAccess.open(OUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"details":failures,"captures":captures,"samples":samples,"source_sha256":before,"source_stable":sources()==before,"scope":"Controlled actual Route spells/items/enemies rendered by production first_room_view. Spell/item/enemy/deficit setup is explicit fixture, not natural acquisition or a 45-room gameplay sample. No save access, balance verdict, Boss or user acceptance claim."},"\t"))
	print("FORMAL ICE CONTROLLED VFX checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
