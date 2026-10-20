extends Control
## A read-only health / phase strip. Thresholds and action state come from core.

const T = preload("res://scripts/ui/atelier_theme.gd")
var _state: Dictionary = {}
var _name: Label
var _status: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(580, 66)
	_name = T.label(self, "", Rect2(0, 0, 580, 26), 20, Color("f1d29b"))
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status = T.label(self, "", Rect2(0, 46, 580, 22), 14, T.MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	visible = false


func refresh(snapshot: Dictionary) -> void:
	_state = {}
	for actor in snapshot.get("actors", []):
		if bool(actor.get("boss", false)) and float(actor.get("health", 0.0)) > 0.0:
			_state = actor
			break
	visible = not _state.is_empty() and str(snapshot.get("phase", "")) == "combat"
	if not visible:
		return
	_name.text = "%s   %d / %d" % [_state.name, ceili(float(_state.health)), int(_state.max_health)]
	var phase_text := "阶段 %d / %d" % [int(_state.boss_phase_index) + 1, int(_state.boss_phase_count)]
	if float(_state.get("boss_transition_remaining", 0.0)) > 0.0:
		phase_text += " · 转阶段 %.1f秒 · 可继续攻击" % float(_state.boss_transition_remaining)
	else:
		var names := {"charge": "岩冠冲撞", "fan": "扇形弹幕", "ring": "缺口环弹", "double_ring": "双重环弹", "marks": "追迹落印", "line": "横纵符线", "cross_line": "十字符阵", "sweep": "扇区扫射"}
		var action: String = str(_state.get("boss_action", {}).get("key", ""))
		phase_text += " · " + ("恢复间隙" if str(_state.phase) == "recover" else str(names.get(action, "靠近目标")))
	_status.text = phase_text
	queue_redraw()


func _draw() -> void:
	if _state.is_empty():
		return
	var track := Rect2(1, 29, 578, 14)
	draw_style_box(T.box(Color("1d2130"), Color("a38160"), 1, 3), track)
	var fraction: float = clampf(float(_state.health) / maxf(1.0, float(_state.max_health)), 0.0, 1.0)
	draw_rect(Rect2(track.position + Vector2.ONE * 2.0, Vector2((track.size.x - 4.0) * fraction, track.size.y - 4.0)), Color("c56379"))
	for threshold in _state.get("boss_thresholds", []):
		var x := track.position.x + 2.0 + (track.size.x - 4.0) * float(threshold)
		draw_line(Vector2(x, 30), Vector2(x, 42), Color("ffe1ac"), 1.5)
