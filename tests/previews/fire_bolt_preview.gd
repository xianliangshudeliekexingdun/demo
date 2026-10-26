extends Node
## Optional controlled real-core review. Never starts from the game menu,
## touches a save, records pixels, or becomes an export dependency.
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
var _released := false
var _start_time := 0.0


func _ready() -> void:
	_run = PreviewRun.new()
	var configured: Dictionary = _run.configure({}, 20261026)
	if not configured.ok:
		push_error(str(configured.error))
		get_tree().quit(1)
		return
	_view = View.new()
	_view.size = Vector2(1600, 900)
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
	_run.player.crit_rate = 1.0 if _mode in [1, 2] else 0.0
	var spell: Dictionary = _run._new_spell("F01")
	spell.level = 3 if _mode == 2 else 2 if _mode == 1 else 1
	_run._refresh_spell(spell)
	spell.remaining = 0.35
	_run.spells.append(spell)
	var enemy: Dictionary = _run._enemy_combat.make_actor(_run, "M01", Vector2(0, 1.5), 901)
	enemy.health = 100000.0
	enemy.max_health = enemy.health
	_run.actors.append(enemy)
	_released = false
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
	if float(_run.time) - _start_time >= 5.8: _reset()


func _advance(dt: float) -> void:
	_run.step(dt)
	if not _released and not _run.projectiles.is_empty():
		_released = true
		_run.spells[0].remaining = 9999.0
		if _mode == 3:
			# Add a real obstacle after the legitimate cast acquired its clear line.
			_run.blocks.append({"center": Vector2(0, -0.7), "size": Vector2(1.6, 0.5)})
		elif _mode == 4:
			# A real target dodge leaves the released straight shot to expire.
			_run.actors[0].pos = Vector2(4, 1.5)
			_run.actors[0].previous = _run.actors[0].pos


func _refresh() -> void:
	var title: String = ["一级 · 聚焰／飞行／命中／点燃", "二级 · 必定暴击留火", "三级 · 双弹／暴击留火", "撞墙 · 散火收尾", "目标避开 · 射程熄灭"][_mode]
	_label.text = "焰弹术样板 v2 · %s%s\n1 一级　2 二级暴击　3 三级双弹　4 撞墙　5 射程结束\n空格 暂停　R 减少动态　Enter 重播　Esc 退出" % [title, " · 已暂停" if _paused else ""]
	_view.set_visual_options({"reduced_motion": _reduced})
	_view.sync(_run.get_snapshot())


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
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
