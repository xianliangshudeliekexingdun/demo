extends Node
## Optional manual F06 preview. Controlled fixtures use the real Route/core.
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
var _returned := false


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
	var spell: Dictionary = _run._new_spell("F06")
	spell.level = mini(_mode + 1, 3)
	_run._refresh_spell(spell)
	spell.remaining = 9999.0 if _mode == 5 else 0.65
	_run.spells.append(spell)
	if _mode == 4:
		var vortex: Dictionary = _run._new_spell("F05")
		vortex.level = 3
		_run._refresh_spell(vortex)
		vortex.remaining = 1.1
		_run.spells.append(vortex)
	for index in 3:
		var actor: Dictionary = _run._enemy_combat.make_actor(_run, "M01", Vector2(0, [1.4, 3.7, 6.2][index]), 901 + index)
		actor.health = 100000.0
		actor.max_health = actor.health
		_run.actors.append(actor)
	_start_time = float(_run.time)
	_last_casts = int(_run.casts)
	_accumulator = 0.0
	_prepared = false
	_returned = false
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
		_run.cast_extra_spell("F06", _run.actors[0], 0.7)
		_prepared = true
	if _mode == 6 and not _prepared and elapsed >= 1.8:
		_run.player.pos = Vector2(-2.0, 0)
		_run.player.previous = _run.player.pos
		_run.cast_extra_spell("F06", _run.actors[0], 0.7)
		_prepared = true
	if _mode == 3 and not _prepared and elapsed >= 2.8:
		_run.player.pos = Vector2(5.5, 0)
		_run.player.previous = _run.player.pos
		_prepared = true
	if _mode == 3 and not _returned and elapsed >= 4.5:
		_run.player.pos = Vector2.ZERO
		_run.player.previous = Vector2.ZERO
		_returned = true
	if _mode == 8 and not _prepared and elapsed >= 2.3:
		_run.actors[0].pos = Vector2(6.0, 2.0)
		_run.actors[0].previous = _run.actors[0].pos
		_prepared = true
	_run.step(dt)
	if int(_run.casts) > _last_casts:
		_last_casts = int(_run.casts)
		_run.spells[0].remaining = 9999.0
	if _mode == 4 and _run._spell_combat.zones.any(func(z): return z.spell_id == "F05"):
		_run.spells[1].remaining = 9999.0


func _refresh() -> void:
	var title: String = ["一级 · 铺阵／持续阵火／收尾", "二级 · 更大真实范围", "三级 · 积蓄／一次成熟爆燃", "进出法阵 · 真实增益余留", "自然火区重叠 · 局部易伤提示", "额外法阵 · 不伪造成熟", "提前替换 · 旧阵撤去", "自然到期 · 三级增益余留", "目标移开 · 成熟仍守真实范围"][_mode]
	DisplayServer.window_set_title("炽焰法阵 v2 · 金色符纹与余烬" + (" · 减少动态" if _reduced else ""))
	_label.text = "炽焰法阵 v2 · 金色符纹与余烬\n%s%s\n1 一级　2 二级　3 三级　4 进出法阵　5 自然重叠\n6 额外法阵　7 提前替换　8 到期余留　9 目标移开\n空格 暂停　R 减少动态：%s　Enter 重播　Esc 退出" % [title, " · 已暂停" if _paused else "", "开" if _reduced else "关"]
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
