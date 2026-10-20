extends CanvasLayer
signal chosen(ability: String)
signal resumed
signal retried
signal returned
const FONT = preload("res://assets/fonts/NotoSansSC.ttf")
const NAMES = {"fireball": "火球术", "lightning": "连锁雷电", "orbit": "环绕法球"}
var root: Control
var overlay: Control
var hud: Control
const HUD_ART = preload("res://scripts/ui/battle_hud.gd")
const ICONS = [preload("res://assets/ui/fireball.png"), preload("res://assets/ui/lightning.png"), preload("res://assets/ui/orbit.png")]
const ICON_REGIONS = [Rect2(97,95,1056,1058),Rect2(120,120,1011,994),Rect2(62,68,1130,1107)]
const ABILITIES = ["fireball", "lightning", "orbit"]
var hud_art: Control
var skill_icons: Array[TextureRect] = []
var health_label: Label
var status: Label
var spell: Label
var first_button: Button

func _ready():
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme = Theme.new()
	var readable_font = FontVariation.new()
	readable_font.base_font = FONT
	readable_font.variation_opentype = {2003265652: 500.0}
	theme.default_font = readable_font
	theme.default_font_size = 18
	root.theme = theme
	add_child(root)
	hud = Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_art = HUD_ART.new()
	hud_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(hud_art)
	health_label = label(hud,"100 / 100",Vector2(112,84),14,Color("f4e8cd"))
	for i in range(ICONS.size()):
		var icon = TextureRect.new()
		var atlas = AtlasTexture.new()
		atlas.atlas = ICONS[i]
		atlas.region = ICON_REGIONS[i]
		icon.texture = atlas
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(520+i*84,620)
		icon.size = Vector2(72,72)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(icon)
		skill_icons.append(icon)
	spell = label(hud,"",Vector2(470,591),16,Color("fff0ce"))
	spell.size = Vector2(340,24)
	spell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ability_plate = panel(hud,Rect2(996,24,256,68),Color("243b42"))
	status = label(ability_plate,"",Vector2(20,20),16,Color("d4dfd8"))
	label(hud,"WASD / 方向键移动 · 自动施法",Vector2(28,651),14,Color("f3f0df"))
	label(hud,"Esc 暂停 · F11 全屏",Vector2(28,675),14,Color("f3f0df"))
	show_menu()

func box(color: Color, radius: int = 12) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.border_color = Color("63817e")
	s.set_border_width_all(1)
	return s

func panel(parent: Node, rect: Rect2, color: Color) -> Panel:
	var p = Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel",box(color))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p

func label(parent: Node, text: String, position: Vector2, size: int, color: Color = Color("f3ecde")) -> Label:
	var l = Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_shadow_color",Color(0.04,0.05,0.06,0.9))
	l.add_theme_constant_override("shadow_offset_x",1)
	l.add_theme_constant_override("shadow_offset_y",2)
	l.position = position
	l.add_theme_font_size_override("font_size",size)
	l.add_theme_color_override("font_color",color)
	parent.add_child(l)
	return l

func button(parent: Node, text: String, rect: Rect2, action: Callable, primary: bool = false) -> Button:
	var b = Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.add_theme_stylebox_override("normal",box(Color("6d568b") if primary else Color("304b50"),10))
	b.add_theme_stylebox_override("hover",box(Color("876ca7") if primary else Color("496a6b"),10))
	b.add_theme_stylebox_override("pressed",box(Color("53656b"),10))
	var focus = box(Color(0,0,0,0),10)
	focus.border_color = Color("eedcae")
	focus.set_border_width_all(2)
	b.add_theme_stylebox_override("focus",focus)
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func clear_overlay():
	if is_instance_valid(overlay):
		root.remove_child(overlay)
		overlay.queue_free()
	overlay = null

func new_overlay(alpha: float):
	clear_overlay()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	var dim = ColorRect.new()
	dim.color = Color(0.055,0.11,0.15,alpha)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

func show_menu():
	hud.hide()
	clear_overlay()
	first_button = null

func show_battle():
	clear_overlay()
	hud.show()

func refresh(battle):
	hud_art.ratio = clampf(float(battle.player.health) / maxf(1.0,battle.cfg.player_health),0,1)
	hud_art.selected = ABILITIES.find(battle.ability)
	hud_art.queue_redraw()
	for i in range(skill_icons.size()):
		skill_icons[i].modulate = Color.WHITE if i == hud_art.selected else Color(0.52,0.55,0.60,1)
	health_label.text = "%d / %d" % [battle.player.health,battle.cfg.player_health]
	spell.text = "当前魔法 · " + NAMES[battle.ability]
	status.text = "史莱姆  %d / 3     %02d:%02d" % [battle.kills,int(battle.elapsed)/60,int(battle.elapsed)%60]

func show_pause():
	new_overlay(0.55)
	var p = panel(overlay,Rect2(420,230,440,270),Color("213940"))
	label(p,"休息一下",Vector2(130,25),32)
	label(p,"庭院的时间已经暂停。",Vector2(125,78),16,Color("bfd0cc"))
	first_button = button(p,"继续试炼",Rect2(54,123,332,52),func(): resumed.emit(),true)
	button(p,"返回选择",Rect2(54,192,332,44),func(): returned.emit())
	first_button.grab_focus()

func show_result(battle):
	new_overlay(0.55)
	var p = panel(overlay,Rect2(396,192,488,330),Color("213940"))
	label(p,"试炼完成" if battle.result == "success" else "再试一次吧",Vector2(145,30),32)
	label(p,"%s   ·   击败 %d / 3   ·   受击 %d 次" % [NAMES[battle.ability],battle.kills,battle.hits],Vector2(60,97),18,Color("bfd0cc"))
	first_button = button(p,"再次挑战",Rect2(54,155,380,57),func(): retried.emit(),true)
	button(p,"返回选择",Rect2(54,232,380,48),func(): returned.emit())
	first_button.grab_focus()
