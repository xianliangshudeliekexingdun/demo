extends Node
## Optional controlled real-core review for the user's manual testing.
## No save access, pixels, menu entry or export dependency.
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
var _overlap_done := false
var _start_time := 0.0


func _ready() -> void:
	_run = PreviewRun.new()
	var configured: Dictionary = _run.configure({}, 20261027)
	if not configured.ok:
		push_error(str(configured.error))
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
	var spell: Dictionary = _run._new_spell("F03")
	spell.level = mini(_mode + 1, 3)
	_run._refresh_spell(spell)
	spell.remaining = 0.35
	_run.spells.append(spell)
	for index in 3:
		var enemy: Dictionary = _run._enemy_combat.make_actor(_run, "M01", Vector2(float(index - 1) * 1.3, 1.5), 901 + index)
		enemy.health = 100000.0
		enemy.max_health = enemy.health
		_run.actors.append(enemy)
	_released = false
	_overlap_done = false
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
	if float(_run.time) - _start_time >= 8.8: _reset()


func _advance(dt: float) -> void:
	_run.step(dt)
	if not _released and _run._spell_combat.pending.any(func(item): return item.kind == "rain_drop"):
		_released = true
		_run.spells[0].remaining = 9999.0
		if _mode == 3:
			for enemy in _run.actors:
				enemy.pos.x += 4.0
				enemy.previous = enemy.pos
	if _mode == 4 and _released and not _overlap_done and float(_run.time) - _start_time >= 1.8:
		# Explicitly controlled second release for overlap inspection, not a
		# claim about the natural cooldown or a player-accessible extra cast.
		var spell: Dictionary = _run.spells[0]
		_run._spell_combat._cast(_run, spell, _run.get_spell_stats(spell), _run.actors[2], true, 1.0)
		spell.remaining = 9999.0
		_overlap_done = true


func _refresh() -> void:
	var title: String = ["一级 · 六次落火／首落／点燃", "二级 · 八次落火／前两次中心", "三级 · 末落后原中心余火", "目标移开 · 固定落点与原中心余火", "两次受控释放 · 重叠显示"][_mode]
	_label.text = "流火之雨 · %s%s\n1 一级　2 二级　3 三级　4 目标移开　5 受控重叠\n空格 暂停　R 减少动态　Enter 重播　Esc 退出" % [title, " · 已暂停" if _paused else ""]
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
