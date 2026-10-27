extends Node
## User-launched only. Controlled geometry/resistance/movement, real Route rules.
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
	var result: Dictionary = _run.configure({}, 20261027)
	if not result.ok:
		push_error(str(result.error))
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
	var spell: Dictionary = _run._new_spell("F09")
	spell.level = mini(_mode + 1, 3)
	_run._refresh_spell(spell)
	spell.remaining = 9999.0 if _mode == 5 else 0.65
	_run.spells.append(spell)
	for index in 4:
		var pos := Vector2.from_angle(float(index) * TAU / 4.0) * (1.6 if index < 3 else 3.8)
		var enemy: Dictionary = _run._enemy_combat.make_actor(_run, "M01", pos, 901 + index)
		enemy.health = 100000.0
		enemy.max_health = enemy.health
		if _mode == 4: enemy.push_resistance = 1.0 if index == 0 else 0.6
		if _mode == 8: enemy.push_resistance = 0.9
		_run.actors.append(enemy)
	if _mode == 3: _run.blocks.append({"center": Vector2(2.8, 0), "size": Vector2(0.4, 3.0)})
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
	if float(_run.time) - _start_time >= 6.0: _reset()


func _advance(dt: float) -> void:
	var elapsed := float(_run.time) - _start_time
	if _mode == 7 and not _prepared and float(_run.spells[0].cast_remaining) > 0.0:
		for enemy in _run.actors:
			enemy.pos = Vector2(6.0, 5.0)
			enemy.previous = enemy.pos
		_prepared = true
	if _mode == 5 and not _prepared and elapsed >= 0.85:
		_run.cast_extra_spell("F09", _run.actors[0], 0.7)
		_prepared = true
	var move := Vector2.RIGHT if _mode == 6 and elapsed >= 0.90 and elapsed < 2.4 else Vector2.ZERO
	_run.step(dt, move)
	if int(_run.casts) > _last_casts:
		_last_casts = int(_run.casts)
		_run.spells[0].remaining = 9999.0
		if _mode == 8 and not _prepared:
			_prepared = true
			_run.cast_extra_spell("F09", _run.actors[0], 0.7)
			_run.cast_extra_spell("F09", _run.actors[1], 0.7)


func _refresh() -> void:
	var title: String = ["一级 · 压焰／近身火浪／推开", "二级 · 真实范围／自然命中加速", "三级 · 加速／真实减速／附着", "墙边 · 实际推出距离", "抗推 · 零位移与部分位移", "额外释放 · 无自然命中加速", "释放后走位 · 原位火浪与跟随加速", "受控目标移开 · 吟唱取消", "自然＋额外 · 三次真实释放"][_mode]
	_label.text = "灼浪冲击 · %s%s\n1 一级　2 二级　3 三级　4 墙边　5 抗推\n6 额外释放　7 释放后移动　8 目标移开　9 多次释放\n空格 暂停　R 减少动态　Enter 重播　Esc 退出" % [title, " · 已暂停" if _paused else ""]
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
