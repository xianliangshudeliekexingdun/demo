extends Node
## Manual F11 preview: controlled actors with actual Route casting/status rules.
const Route = preload("res://scripts/core/courtyard_route_run.gd")
const View = preload("res://scripts/presentation/first_room_view.gd")
const FONT = preload("res://assets/fonts/NotoSansSC.ttf")
const STEP := 1.0 / 120.0
class PreviewRun extends Route:
	func _reserve_batch(): pass
	func _update_spawn(_dt: float): pass
	func _update_enemies(_dt: float):
		for enemy in actors: enemy.previous = enemy.pos
	func _check_clear(): pass

var _run
var _view
var _label: Label
var _mode := 0
var _paused := false
var _reduced := false
var _accumulator := 0.0
var _start_time := 0.0
var _last_casts := 0
var _prepared := false


func _ready() -> void:
	_run = PreviewRun.new()
	if not _run.configure({}, 20261027).ok:
		get_tree().quit(1)
		return
	_view = View.new()
	add_child(_view)
	_label = Label.new()
	_label.position = Vector2(28, 20)
	_label.z_index = 5
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color("fff0cb"))
	_label.add_theme_color_override("font_outline_color", Color("23150d"))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	_reset()


func _reset() -> void:
	_run._stop_combat()
	_run.spells.clear()
	_run.actors.clear()
	_run.blocks.clear()
	_run.effects.clear()
	_run.spawn_warnings.clear()
	_run._spawn_done = true
	_run.phase = "combat"
	_run.paused = _paused
	_run.room_revision += 1
	_run.player.pos = Vector2.ZERO
	_run.player.previous = Vector2.ZERO
	_run.player.crit_rate = 0.0
	var spell: Dictionary = _run._new_spell("F11")
	spell.level = mini(_mode + 1, 3)
	_run._refresh_spell(spell)
	spell.remaining = 9999.0 if _mode == 5 else 0.65
	_run.spells.append(spell)
	var positions := [Vector2(0, 2), Vector2(1, 2.8), Vector2(-1, 2.8), Vector2(1.8, 3.8), Vector2(-1.8, 3.8), Vector2(0, 4.6), Vector2(2.5, 4.6), Vector2(-2.5, 4.6), Vector2(0, 6.8)]
	for index in positions.size():
		var at: Vector2 = positions[index]
		if _mode == 7 and index > 0: at += Vector2(7, 0)
		var actor: Dictionary = _run._enemy_combat.make_actor(_run, "M01", at, 801 + index)
		actor.health = 1.0 if _mode == 6 and index == 0 else 100000.0
		actor.max_health = actor.health
		_run.actors.append(actor)
	if _mode == 3: _run.blocks.append({"center": Vector2(0.5, 2.4), "size": Vector2(0.16, 0.55), "height": 1.3})
	if _mode == 4:
		for index in [1, 2]: _run._spell_combat.apply_burn(_run, _run.actors[index], "F01")
	_start_time = float(_run.time)
	_last_casts = int(_run.casts)
	_accumulator = 0.0
	_prepared = false
	_refresh()


func _process(delta: float) -> void:
	if _run == null: return
	if not _paused:
		_accumulator += minf(delta, 0.1)
		while _accumulator >= STEP:
			_advance(STEP)
			_accumulator -= STEP
	_view.sync(_run.get_snapshot(), delta)
	if float(_run.time) - _start_time >= 10.0: _reset()


func _advance(dt: float) -> void:
	var elapsed := float(_run.time) - _start_time
	if _mode == 5 and not _prepared and elapsed >= 0.85:
		_run.cast_extra_spell("F11", _run.actors[0], 0.7)
		_prepared = true
	if _mode == 8 and not _prepared and elapsed >= 1.1:
		_run.actors[0].pos += Vector2(0.8, 0.1)
		_run.actors[0].previous = _run.actors[0].pos
		_run._spell_combat.apply_burn(_run, _run.actors[1], "F01")
		_prepared = true
	_run.step(dt)
	if int(_run.casts) > _last_casts:
		_last_casts = int(_run.casts)
		_run.spells[0].remaining = 9999.0


func _refresh() -> void:
	var title: String = ["一级 · 火印／一轮传火／燃烧收尾", "二级 · 更多实际分支", "三级 · 完整传播与燃烧", "隔墙目标 · 保留真实视线", "已燃烧邻敌 · 不重复传播", "额外法印 · 原追加规则", "致死主目标 · 仍按实际传播", "无合格邻敌 · 单体烙印", "移动与来源交接 · 各守真实状态"][_mode]
	DisplayServer.window_set_title("引燃之印 · 完整链路预览 v1" + (" · 减少动态" if _reduced else ""))
	_label.text = "引燃之印 · 完整链路预览 v1\n%s%s\n1 一级　2 二级　3 三级　4 隔墙　5 已燃烧\n6 额外法印　7 致死　8 无邻敌　9 移动／来源交接\n空格 暂停　R 减少动态：%s　Enter 重播　Esc 退出" % [title, " · 已暂停" if _paused else "", "开" if _reduced else "关"]
	_view.set_visual_options({"reduced_motion": _reduced})
	_view.sync(_run.get_snapshot())


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			_mode = int(event.keycode) - KEY_1
			_reset()
		KEY_SPACE:
			_paused = not _paused
			_run.set_paused(_paused)
			_refresh()
		KEY_R:
			_reduced = not _reduced
			_refresh()
		KEY_ENTER: _reset()
		KEY_ESCAPE: get_tree().quit()
