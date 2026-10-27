extends Node
## Optional user-launched controlled preview, using the real Route and F07.
## Fuel/health/movement setups are fixtures, never production balance changes.
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
var _releases := 0
var _prepared := false
var _extra_done := false


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
	_run.player.pos = Vector2(0, -3)
	_run.player.previous = _run.player.pos
	_run.player.crit_rate = 0.0
	var spell: Dictionary = _run._new_spell("F07")
	spell.level = mini(_mode + 1, 3)
	_run._refresh_spell(spell)
	spell.remaining = 9999.0 if _mode == 6 else 0.35
	_run.spells.append(spell)
	for index in 3:
		var pos := Vector2([0.0, 2.0, 5.2][index], 1)
		var enemy: Dictionary = _run._enemy_combat.make_actor(_run, "M01", pos, 901 + index)
		enemy.health = 100000.0
		enemy.max_health = enemy.health
		_run.actors.append(enemy)
	if _mode in [3, 5, 6, 7]:
		for index in 2: _run._spell_combat.apply_burn(_run, _run.actors[index], "F11")
	if _mode == 8: _run.blocks.append({"center": Vector2(0, -1.0), "size": Vector2(3.0, 0.4)})
	_releases = 0
	_prepared = false
	_extra_done = false
	_last_casts = int(_run.casts)
	_accumulator = 0.0
	_start_time = float(_run.time)
	_refresh()


func _process(delta: float) -> void:
	if _run == null: return
	if not _paused:
		_accumulator += minf(delta, 0.1)
		while _accumulator >= STEP:
			_advance(STEP)
			_accumulator -= STEP
	_view.sync(_run.get_snapshot(), delta)
	if float(_run.time) - _start_time >= 7.0: _reset()


func _advance(dt: float) -> void:
	if _mode == 4 and not _prepared and float(_run.spells[0].cast_remaining) > 0.0:
		# Move the target after chant lock; both aim and later impact stay there.
		_run.actors[0].pos.x = 5.5
		_run.actors[0].previous = _run.actors[0].pos
		_prepared = true
	if _mode == 6 and not _extra_done and float(_run.time) - _start_time >= 0.8:
		_run.cast_extra_spell("F07", _run.actors[0], 0.7)
		_extra_done = true
	_run.step(dt)
	if int(_run.casts) > _last_casts:
		_releases += int(_run.casts) - _last_casts
		_last_casts = int(_run.casts)
		_run.spells[0].remaining = 9999.0
		if _mode == 5 and not _prepared:
			_run.actors[0].health = 1.0
			_prepared = true
		if _mode == 7 and not _extra_done:
			_extra_done = true
			_run.cast_extra_spell("F07", _run.actors[0], 0.7)
			_run.cast_extra_spell("F07", _run.actors[1], 0.7)


func _refresh() -> void:
	var title: String = ["一级 · 聚熔／抛射／内外爆燃", "二级 · 中心与外围", "三级 · 无燃料／原位余震", "三级 · 预置燃烧／兑现／延迟复燃", "受控移动 · 吟唱锁点保留", "受控主爆致死 · 不兑现尸体燃料", "受控额外释放 · 有兑现无增强复燃", "自然＋额外 · 实际多弹交叠", "掩体 · 保持原抛射规则"][_mode]
	_label.text = "熔核爆弹 · %s%s\n1 一级　2 二级　3 三级无燃料　4 燃料／复燃　5 移动锁点\n6 主爆致死　7 额外释放　8 多弹　9 掩体\n空格 暂停　R 减少动态　Enter 重播　Esc 退出" % [title, " · 已暂停" if _paused else ""]
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
