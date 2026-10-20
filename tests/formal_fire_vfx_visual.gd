extends SceneTree
## Explicit controlled core/VFX fixture, never a natural inventory or route.
const Rules = preload("res://tests/formal_fire_tests.gd")
const View = preload("res://scripts/presentation/first_room_view.gd")
const T = preload("res://scripts/ui/atelier_theme.gd")
const OUT = "res://build/qa/formal-fire-implementation-20261018/vfx-fixtures/"
var checks: int = 0
var failures: Array = []
var captures: Array = []
var samples: Array = []
var hashes: Dictionary = {}
var battle
var view
var caption: Label

func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures.append(label)
		push_error("Formal fire controlled VFX: " + label)
func sources() -> Dictionary:
	var result: Dictionary = {}
	for path in ["res://tests/formal_fire_vfx_visual.gd", "res://tests/formal_fire_tests.gd", "res://scripts/core/route_spell_combat.gd", "res://scripts/core/route_fire_status.gd", "res://scripts/core/courtyard_route_run.gd", "res://scripts/core/route_artifacts.gd", "res://scripts/presentation/first_room_view.gd", "res://scripts/presentation/route_spell_vfx.gd", "res://data/route_spell_runtime.json"]:
		result[path] = FileAccess.get_sha256(path)
	return result
func advance(count: int):
	for _index in count: battle.step(1.0/120.0)
func stop_natural():
	for spell in battle.spells:
		spell.remaining = 9999.0
		spell.cast_remaining = 0.0
func release(id: String):
	var spell: Dictionary = battle._owned_spell(id)
	var stats: Dictionary = battle.get_spell_stats(spell)
	var target: Dictionary = battle._spell_combat.legal_target(battle, spell, stats)
	check(not target.is_empty(), "controlled actual legal target " + id)
	if target.is_empty(): return
	spell.locked_pos = target.pos
	battle._spell_combat._cast(battle, spell, stats, target, true, 1.0)
	stop_natural()
func snap(label: String, text: String):
	caption.text = text
	var source: Dictionary = battle.get_snapshot()
	view.sync(source, 0.0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+label+".png") == OK, "actual production VFX pixels " + label)
	check(battle.get_snapshot() == source, "view never changes controlled core " + label)
	captures.append(label)
	samples.append({"label":label,"source":source,"vfx":view.get_vfx_debug_state()})
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	hashes = sources()
	check(DisplayServer.get_name() != "headless", "native display required")
	if DisplayServer.get_name() == "headless":
		finish()
		return
	DisplayServer.window_set_size(Vector2i(1600,900))
	battle = Rules.Fixture.new()
	check(battle.configure({},20261018).ok and battle.choose_initial("F01"), "actual Route config and initial start")
	battle._spawn_done = true
	battle.spawn_warnings.clear()
	battle.blocks.clear()
	battle.spells.clear()
	battle.player.pos = Vector2.ZERO
	battle.player.previous = Vector2.ZERO
	battle.player.crit_rate = 0.0
	for id in ["F11", "F07"]:
		var spell: Dictionary = battle._new_spell(id)
		spell.level = 3
		battle._refresh_spell(spell)
		battle.spells.append(spell)
	stop_natural()
	for id in ["B11", "P06", "G04"]:
		battle._artifact_combat._owned.append(id)
		battle._artifact_combat.apply_acquisition(battle,id)
	battle.actors.clear()
	for index in 4:
		var pos: Vector2 = [Vector2(0,2.3),Vector2(-2.3,3.1),Vector2(2.3,3.1),Vector2(0,5.0)][index]
		battle.actors.append({"id":index+1,"type":"M01","type_id":"M01","pos":pos,"previous":pos,"health":10000.0,"max_health":10000.0,"radius":0.3,"phase":"chase","push_resistance":0.0})
	view = View.new()
	root.add_child(view)
	view.size = Vector2(1600,900)
	var overlay = CanvasLayer.new()
	overlay.layer = 30
	root.add_child(overlay)
	var panel = T.panel(overlay,Rect2(24,20,1552,110))
	T.label(panel,"正式火系 · 受控 core / VFX 专项",Rect2(24,6,1490,44),29,T.GOLD)
	caption = T.label(panel,"",Rect2(24,55,1490,43),20,T.TEXT)
	T.label(overlay,"受控法术、宝物与敌人夹具；不代表自然抽取库存。使用真实 core 结算和只读显示。",Rect2(32,848,1536,36),19,T.MUTED)
	release("F11")
	await snap("01-controlled-f11-propagation","F11 真实主击与一次传播：4 名受控敌人点燃；事件与持续燃烧均来自实际 core。")
	check(view.get_vfx_debug_state().coverage.has("fire_spread") and view.get_vfx_debug_state().coverage.has("fire_brand"), "actual F11 spread and brand render")
	advance(24)
	await snap("02-controlled-burning-persistent","持续燃烧读取真实 spell_burns；同目标仅一份燃烧，P06 延长持续时间。")
	check(view.get_vfx_debug_state().coverage.has("burning"), "persistent burning snapshot renders")
	var frozen: Dictionary = view.get_vfx_debug_state()
	battle.set_paused(true)
	advance(120)
	view.sync(battle.get_snapshot(),0.0)
	var paused: Dictionary = view.get_vfx_debug_state()
	await process_frame
	await process_frame
	view.sync(battle.get_snapshot(),0.0)
	check(view.get_vfx_debug_state() == paused and paused.clock == frozen.clock, "paused actual core freezes flame geometry and clock")
	await snap("03-controlled-burning-paused","真实暂停：核心与燃烧表现时钟冻结；不使用墙钟推进火焰。")
	battle.set_paused(false)
	release("F07")
	advance(54)
	await snap("04-controlled-g04-detonation","自然 F07 真实落地消耗旧燃烧并引爆；G04 仅安排延迟复燃，不立即再伤害。")
	check(view.get_vfx_debug_state().coverage.has("fire_detonation"), "actual detonation source event renders")
	advance(60)
	advance(10) # sample 0.083s into the genuine visual pulse, not its zero-age birth frame
	await snap("05-controlled-g04-reignition","0.5 秒后仍存活目标真实复燃；不传播、不递归、不立即结算燃烧跳。")
	check(view.get_vfx_debug_state().coverage.has("fire_reignited"), "actual delayed re-ignition event renders")
	battle._stop_combat()
	battle.phase = "pickup"
	await snap("06-controlled-clear-cleanup","调用实际清房后，燃烧与待复燃状态清空；旧战斗事件不留火焰残影。")
	var clean: Dictionary = view.get_vfx_debug_state()
	check(clean.quad_count == 0 and clean.core_count == 0 and clean.coverage.is_empty(), "all combat fire VFX cleaned outside combat")
	check(battle.get_snapshot().spell_burns.is_empty() and battle.get_snapshot().fire_reignite_pending.is_empty(), "actual core cleanup removes both new states")
	view.queue_free()
	await process_frame
	finish()
func finish():
	check(sources() == hashes, "controlled core and presentation sources fixed")
	FileAccess.open(OUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"details":failures,"captures":captures,"samples":samples,"source_sha256":hashes,"source_stable":sources()==hashes,"scope":"Explicit controlled actual-core spell/item/enemy fixtures rendered by production view. No natural acquisition, survival, balance, Boss or account progression claim; no save access."},"\t"))
	print("FORMAL FIRE CONTROLLED VFX: %d checks %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
