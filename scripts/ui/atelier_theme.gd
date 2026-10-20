extends RefCounted
const FONT=preload("res://assets/fonts/NotoSansSC.ttf")
const Icon=preload("res://scripts/ui/arcane_icon.gd")
const TEXT=Color("eeeae2")
const INK=TEXT
const MUTED=Color("adb5c8")
const GOLD=Color("c6a66c")
const CYAN=Color("76dce5")
const BLUE=Color("9baddc")
const DIM=Color("101522")
const PAPER=Color("232b40")
const PANEL=Color("181e30")
const STONE=Color("30394e")
const LINE=Color("50576d")
static func make_theme()->Theme:
	var t=Theme.new()
	var readable=FontVariation.new()
	readable.base_font=FONT
	readable.variation_opentype={2003265652:500.0}
	t.default_font=readable
	t.default_font_size=22
	t.set_color("font_color","Label",TEXT)
	return t
static func box(fill:Color,border:Color=LINE,width:int=1,radius:int=8)->StyleBoxFlat:
	var s=StyleBoxFlat.new()
	s.bg_color=fill
	s.border_color=border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.corner_detail=1
	return s
static func panel(parent:Node,rect:Rect2,paper:bool=false)->Panel:
	var p=Panel.new()
	p.position=rect.position
	p.size=rect.size
	p.mouse_filter=Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel",box(PAPER if paper else PANEL,GOLD.darkened(.38) if paper else LINE))
	parent.add_child(p)
	return p
static func label(parent:Node,text:String,rect:Rect2,px:int=22,color:Color=TEXT)->Label:
	var l=Label.new()
	l.clip_text=true
	l.text=text
	l.position=rect.position
	l.size=rect.size
	l.add_theme_font_size_override("font_size",px)
	l.add_theme_color_override("font_color",color)
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l
static func paragraph(parent:Node,text:String,rect:Rect2,px:int=22,color:Color=MUTED)->Label:
	var l=label(parent,text,rect,px,color)
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.clip_text=true
	l.size=rect.size
	l.vertical_alignment=VERTICAL_ALIGNMENT_TOP
	return l
static func button(parent:Node,text:String,rect:Rect2,action:Callable,primary:bool=false,disabled:bool=false)->Button:
	var b=Button.new()
	b.text=text
	b.position=rect.position
	b.size=rect.size
	b.disabled=disabled
	b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size",22)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		b.add_theme_color_override(state,Color("171c2a") if primary else TEXT)
	b.add_theme_color_override("font_disabled_color",Color("8e96a9"))
	b.add_theme_stylebox_override("normal",box(GOLD if primary else Color("252d42"),GOLD if primary else LINE))
	b.add_theme_stylebox_override("hover",box(Color("e7c58b") if primary else Color("344358"),CYAN))
	b.add_theme_stylebox_override("pressed",box(Color("af8e57") if primary else Color("182538"),CYAN))
	b.add_theme_stylebox_override("disabled",box(Color("222739"),Color("3e4557")))
	b.add_theme_stylebox_override("focus",box(Color(0,0,0,0),CYAN,3))
	b.pressed.connect(action)
	parent.add_child(b)
	return b
static func icon(parent:Node,spell_id:String,rect:Rect2,tint:Color=Color("f3b675"))->Control:
	var node=Icon.new()
	node.spell_id=spell_id
	node.tint=tint
	node.position=rect.position
	node.size=rect.size
	parent.add_child(node)
	return node
