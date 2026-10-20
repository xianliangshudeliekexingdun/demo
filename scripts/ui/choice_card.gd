extends Panel
## Presentation-only reward card. Revealing never grants or rerolls a reward.
signal reveal_finished
const T = preload("res://scripts/ui/atelier_theme.gd")
const FRONT_TEXTURE = preload("res://assets/ui/frames_v1/reward_card_front.tres")
const BACK_TEXTURE = preload("res://assets/ui/frames_v1/reward_card_back.tres")
const CARD_SIZE = Vector2(280, 440)
var face: Control
var back: Control
var hit: Button
var face_background: TextureRect
var back_background: TextureRect
var revealed := false
var reveal_complete := false
var accent := T.GOLD
var _keyboard := false
var _flip: Tween

func setup(action: String, id: String, color: Color):
	size = CARD_SIZE
	pivot_offset = size * .5
	accent = color
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	face = Control.new()
	face.name = "CardFace"
	face.size = size
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(face)
	face_background = _background(face, FRONT_TEXTURE, "CardBackground")
	back = Control.new()
	back.name = "CardBack"
	back.size = size
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	back_background = _background(back, BACK_TEXTURE, "CardBackBackground")
	hit = Button.new()
	hit.name = "ChooseCard"
	hit.size = size
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(hit)
	# The whole card is the one hit target; no nested selection button.
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		hit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	hit.set_meta("choice_action", action)
	hit.set_meta("choice_id", id)
	hit.disabled = true
	hit.mouse_entered.connect(_restyle)
	hit.mouse_exited.connect(_restyle)
	hit.button_down.connect(_restyle)
	hit.button_up.connect(_restyle)
	hit.focus_entered.connect(_restyle)
	hit.focus_exited.connect(_restyle)
	_restyle()

func _background(parent: Control, texture: Texture2D, node_name: String) -> TextureRect:
	var picture = TextureRect.new()
	picture.name = node_name
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parent.add_child(picture)
	picture.size = size
	return picture

func reveal(index: int, reduced_motion: bool):
	if reduced_motion:
		reveal_immediately()
		return
	face.hide()
	back.show()
	_flip = create_tween()
	_flip.tween_interval(.05 + index * .07)
	_flip.tween_property(self, "scale:x", .025, .14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_flip.tween_callback(_turn_face_up)
	_flip.tween_property(self, "scale:x", 1.0, .24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_flip.tween_callback(_finish_reveal)

func _turn_face_up():
	revealed = true
	set_meta("revealed", true)
	back.hide()
	face.show()
	queue_redraw()

func _finish_reveal():
	reveal_complete = true
	reveal_finished.emit()

func reveal_immediately():
	if _flip and _flip.is_valid(): _flip.kill()
	scale = Vector2.ONE
	_turn_face_up()
	_finish_reveal()

func set_keyboard_focus(value: bool):
	_keyboard = value
	if value:
		var underline = T.box(Color.TRANSPARENT, T.GOLD, 0, 10)
		underline.border_width_bottom = 2
		hit.add_theme_stylebox_override("focus", underline)
	else:
		hit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_restyle()

func _restyle():
	var hovered = is_instance_valid(hit) and not hit.disabled and hit.is_hovered()
	var focused = is_instance_valid(hit) and _keyboard and hit.has_focus()
	var pressed = is_instance_valid(hit) and hit.is_pressed()
	var border = T.CYAN if hovered else T.GOLD if focused else accent.darkened(.25)
	# Generated artwork supplies the body and rim; code only supplies feedback.
	var style = T.box(Color.TRANSPARENT, border, 2 if hovered or focused else 0, 10)
	style.shadow_color = Color(0, 0, 0, .4)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 6)
	add_theme_stylebox_override("panel", style)
	if is_instance_valid(face_background):
		face_background.modulate = Color(.82,.82,.82) if pressed else Color(1.08,1.08,1.08) if hovered else Color.WHITE
