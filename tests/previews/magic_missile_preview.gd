extends Node
## Optional visual-review scene. Not a menu entry, export dependency or save
## consumer. Drives the real projectile collision step in a controlled fixture.
const Route = preload("res://scripts/core/courtyard_route_run.gd")
const View = preload("res://scripts/presentation/first_room_view.gd")
const FONT = preload("res://assets/fonts/NotoSansSC.ttf")
const FIXED_STEP := 1.0 / 120.0
var _run
var _view
var _label: Label
var _mode := 0
var _paused := false
var _reduced := false
var _accumulator := 0.0
var _next_shot := 0.0


func _ready() -> void:
	_run = Route.new()
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
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color("f5e8f1"))
	_label.add_theme_color_override("font_outline_color", Color("241323"))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	_reset()


func _reset() -> void:
	_run._enemy_combat.clear()
	_run.actors.clear()
	_run.spawn_warnings.clear()
	_run.effects.clear()
	_run.phase = "combat"
	_run.paused = _paused
	_run.room_revision += 1
	_run.player.health = _run.player.max_health
	_run.player.invulnerable = 0.0
	_run.player.pos = Vector2(2.7, 0) if _mode == 0 else Vector2(0, -3.5)
	_run.player.previous = _run.player.pos
	var origins: Array = [Vector2(-2.7, 0)] if _mode == 0 else [Vector2(-2.7, -1.7), Vector2(-2.7, 1.7), Vector2(2.7, -1.7), Vector2(2.7, 1.7)]
	for index in origins.size():
		var actor: Dictionary = _run._enemy_combat.make_actor(_run, "M02", origins[index], 900 + index)
		actor.phase = "recover"
		_run.actors.append(actor)
	_next_shot = float(_run.time) + 0.3
	_accumulator = 0.0
	_refresh()


func _process(delta: float) -> void:
	if _run == null:
		return
	if not _paused:
		_accumulator += minf(delta, 0.1)
		while _accumulator >= FIXED_STEP:
			_advance(FIXED_STEP)
			_accumulator -= FIXED_STEP
	_view.sync(_run.get_snapshot(), delta)


func _advance(dt: float) -> void:
	_run.time += dt
	_run.combat_time += dt
	_run.player.previous = _run.player.pos
	_run.player.invulnerable = maxf(0.0, float(_run.player.invulnerable) - dt)
	_run._fade_effects(dt)
	if float(_run.time) >= _next_shot:
		_run.phase = "combat"
		_run.player.health = _run.player.max_health
		for actor: Dictionary in _run.actors:
			var direction: Vector2 = (_run.player.pos - actor.pos).normalized() if _mode == 0 else (-Vector2(actor.pos)).normalized()
			var count := 16 if _mode == 2 else 1
			for index in count:
				var spread := (float(index) - float(count - 1) * 0.5) * 0.035
				_run._enemy_combat._emit_projectile(actor, actor.combat_spec, direction.rotated(spread))
		_next_shot = float(_run.time) + (2.0 if _mode == 0 else 3.0)
	_run._enemy_combat._update_projectiles(_run, dt)


func _refresh() -> void:
	var mode_name: String = ["单发与真实接触", "四向交叉", "64 发密集展示"][_mode]
	var visual_revision := int(_view.get_magic_missile_debug_state().get("visual_revision", 0))
	_label.text = "魔法飞弹样板 v%d · %s%s\n1 单发　2 交叉　3 多发　空格 暂停　R 减少动态　Esc 退出" % [visual_revision, mode_name, " · 已暂停" if _paused else ""]
	_view.set_visual_options({"reduced_motion": _reduced})
	_view.sync(_run.get_snapshot())


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE:
			get_tree().quit()
		KEY_SPACE:
			_paused = not _paused
			_run.paused = _paused
			_refresh()
		KEY_R:
			_reduced = not _reduced
			_refresh()
		KEY_1, KEY_2, KEY_3:
			_mode = int(event.keycode) - int(KEY_1)
			_reset()
