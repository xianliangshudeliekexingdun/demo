extends SceneTree
## Explicit presentation-only fixture. Never presented as natural gameplay evidence.
## The real runner is read once and remains unchanged throughout the test.

const Route = preload("res://scripts/core/courtyard_route_run.gd")
const View = preload("res://scripts/presentation/first_room_view.gd")
const T = preload("res://scripts/ui/atelier_theme.gd")
const OUT = "res://build/qa/material-completion-20261017/visual/vfx-fixtures/"
var checks: int = 0
var failures: Array = []
var captures: Array = []
var samples: Array = []
var view
var caption: Label


func _initialize():
	call_deferred("run")


func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures.append(message)
		push_error("VFX controlled fixture: " + message)


func snap(label: String, description: String):
	caption.text = description
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image.get_size() == Vector2i(1600, 900) and image.save_png(OUT + label + ".png") == OK, "save explicitly labeled fixture " + label)
	captures.append(label)
	samples.append({"label": label, "description": description, "vfx": view.get_vfx_debug_state()})


func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	check(DisplayServer.get_name() != "headless", "native display required for controlled pixels")
	if DisplayServer.get_name() == "headless":
		finish()
		return
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var battle = Route.new()
	check(battle.configure({}, 20261017).ok and battle.choose_initial("F01"), "source runner configures without account")
	var source: Dictionary = battle.get_snapshot()
	view = View.new()
	root.add_child(view)
	view.size = Vector2(1600, 900)
	var labels = CanvasLayer.new()
	labels.layer = 30
	root.add_child(labels)
	var panel = T.panel(labels, Rect2(24, 20, 1552, 112))
	T.label(panel, "特效检查 · F10 暖焰护持 · 受控显示快照", Rect2(24, 8, 1490, 44), 29, T.GOLD)
	caption = T.label(panel, "", Rect2(24, 57, 1490, 42), 20, T.TEXT)
	T.label(labels, "非自然战斗截图 · 仅验证条件效果的渲染、冻结与清理；真实 Main 路线证据另列", Rect2(38, 848, 1520, 32), 19, T.MUTED)
	var runtime: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/route_spell_runtime.json"))
	var life: float = float(runtime.effects.shield_lifetime)
	var fixture: Dictionary = source.duplicate(true)
	fixture.effects = [{"kind": "shield_restore", "spell_id": "F10", "pos": source.player.pos, "life": life*0.8, "max_life": life, "seq": 1}]
	view.sync(fixture, 0.0)
	var frozen: Dictionary = view.get_vfx_debug_state()
	check(frozen.get("coverage", {}).has("shield_restore") and frozen.quad_count > 0, "controlled shield event renders actual production VFX")
	await snap("01-controlled-shield-active", "仅注入表现事件；位置来自真实初始快照，寿命引用 runtime.effects.shield_lifetime。")
	view.sync(fixture, 0.0)
	check(view.get_vfx_debug_state() == frozen, "same read-only snapshot does not advance VFX")
	var paused: Dictionary = fixture.duplicate(true)
	paused.paused = true
	view.sync(paused, 0.0)
	var paused_visual: Dictionary = view.get_vfx_debug_state()
	for _frame in 4: await process_frame
	view.sync(paused, 0.0)
	check(view.get_vfx_debug_state() == paused_visual and paused_visual.clock == frozen.clock, "paused display snapshot freezes shield geometry and clock across rendered frames")
	await snap("01b-controlled-shield-paused", "暂停快照：同一核心时钟与护盾几何保持，不使用墙钟推进。")
	view.set_visual_options({"reduced_motion": true})
	var reduced: Dictionary = view.get_vfx_debug_state()
	check(reduced.quad_count < frozen.quad_count and reduced.clock == frozen.clock, "reduced motion lowers display instances without changing combat clock")
	await snap("02-controlled-shield-reduced-motion", "减少动态效果仅改变显示数量；效果时钟、源快照与真实 runner 保持。")
	var cleared: Dictionary = fixture.duplicate(true)
	cleared.phase = "pickup"
	view.sync(cleared, 0.0)
	var clean: Dictionary = view.get_vfx_debug_state()
	check(clean.quad_count == 0 and clean.core_count == 0 and clean.coverage.is_empty(), "combat-only shield art clears outside combat even if old event is present")
	await snap("03-controlled-post-clear-cleanup", "表现清理检查：受控快照切换到清场阶段，无旧护盾火焰残留。")
	check(battle.get_snapshot() == source, "presentation fixtures never mutate the real runner")
	view.queue_free()
	await process_frame
	finish()


func finish():
	FileAccess.open(OUT + "results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures.size(), "details": failures, "captures": captures, "samples": samples, "provenance": "Explicit controlled presentation-only snapshot fixture, not natural combat screenshots or evidence that F10 triggered during the two real Main routes. Real runner remains unchanged; visual lifetime references existing runtime data."}, "\t"))
	print("MATERIAL VFX FIXTURE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
