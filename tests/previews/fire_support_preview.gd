extends Node
## Optional manual F10/F02 preview. Fixture choices use actual Route transactions.
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
var _prepared := false
var _second := false
var _last_casts := 0


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


func _add_spell(id: String, level: int) -> void:
	var spell: Dictionary = _run._new_spell(id)
	spell.level = level
	_run._refresh_spell(spell)
	spell.remaining = 9999.0
	_run.spells.append(spell)


func _reset() -> void:
	_run._stop_combat()
	_run.spells.clear()
	_run.actors.clear()
	_run.blocks.clear()
	_run.effects.clear()
	_run.spawn_warnings.clear()
	_run.pending_replacement.clear()
	_run._spawn_done = true
	_run.phase = "combat"
	_run.paused = _paused
	_run.room_revision += 1
	_run.player.pos = Vector2.ZERO
	_run.player.previous = Vector2.ZERO
	_run.player.health = _run.player.max_health
	_run.player.max_shield = 100.0
	_run.player.shield = 0.0
	_run.player.invulnerable = 0.0
	_run.player.crit_rate = 0.0
	if _mode not in [6, 7]:
		_add_spell("F10", mini(_mode + 1, 3))
		_run.spells[0].remaining = 9999.0 if _mode == 5 else 0.60
	if _mode == 7: _add_spell("F02", 1)
	if _mode == 3: _run.player.shield = 95.0
	if _mode == 4: _run.player.shield = 100.0
	var actor: Dictionary = _run._enemy_combat.make_actor(_run, "M01", Vector2(0, 3), 901)
	actor.health = 100000.0
	actor.max_health = actor.health
	_run.actors.append(actor)
	_start_time = float(_run.time)
	_last_casts = int(_run.casts)
	_accumulator = 0.0
	_prepared = false
	_second = false
	_refresh()


func _award_mastery() -> bool:
	_run.phase = "reward"
	_run.room_revision += 1
	_run.reward_choices = [_run._choice("F02")]
	return _run.choose_reward("F02", _run.room_revision)


func _advance(dt: float) -> void:
	var elapsed := float(_run.time) - _start_time
	if _mode == 4 and not _prepared and elapsed >= 2.2:
		_run.player.shield = 0.0
		_run.actors.clear()
		_prepared = true
	if _mode == 5:
		if not _prepared and elapsed >= 0.85:
			_run.cast_extra_spell("F10")
			_prepared = true
		if not _second and elapsed >= 1.1:
			_run.damage_player(float(_run.player.shield) + 1.0)
			_second = true
	if _mode in [6, 7, 8] and not _prepared and elapsed >= (1.05 if _mode == 8 else 0.8):
		_award_mastery()
		_prepared = true
	if _mode == 7 and not _second and elapsed >= 2.3:
		_award_mastery()
		_second = true
	_run.step(dt)
	if int(_run.casts) > _last_casts:
		_last_casts = int(_run.casts)
		_run.spells[0].remaining = 9999.0


func _process(delta: float) -> void:
	if _run == null: return
	if not _paused:
		_accumulator += minf(delta, 0.1)
		while _accumulator >= STEP:
			_advance(STEP)
			_accumulator -= STEP
	_view.sync(_run.get_snapshot(), delta)
	if float(_run.time) - _start_time >= 7.0: _reset()


func _refresh() -> void:
	var title: String = ["一级护持 · 聚焰／真实回盾／淡出", "二级护持 · 真实回盾强度", "三级护持 · 真实回盾强度", "仅缺少量盾 · 按实际回盾反馈", "满盾／无敌人 · 保持原施放条件", "额外回盾与破盾 · 短反馈不延长护盾", "炎法精通 · 真实学习成功", "炎法精通 · 二级／三级真实升级", "同场回盾与精通 · 遮挡检查"][_mode]
	DisplayServer.window_set_title("暖焰护持／炎法精通 · 完整链路预览 v1" + (" · 减少动态" if _reduced else ""))
	_label.text = "暖焰护持／炎法精通 · 完整链路预览 v1\n%s%s\n1 一级护持　2 二级　3 三级　4 少量缺盾　5 满盾／无敌人\n6 额外／破盾　7 学习精通　8 升级精通　9 同场反馈\n空格 暂停　R 减少动态：%s　Enter 重播　Esc 退出" % [title, " · 已暂停" if _paused else "", "开" if _reduced else "关"]
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
