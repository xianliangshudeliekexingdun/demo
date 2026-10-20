extends Control
## Painted spell assets preserve their native aspect; unknown utility glyphs stay vector.
const PAINTED={
	"F01":preload("res://assets/ui/spells_v2/f01_flame_bolt.png"),
	"F02":preload("res://assets/ui/spells_v2/f02_flame_mastery.png"),
	"F03":preload("res://assets/ui/spells_v2/f03_rain_of_fire.png"),
	"F04":preload("res://assets/ui/spells_v2/f04_flame_spirit.png"),
	"F05":preload("res://assets/ui/spells_v2/f05_fire_vortex.png"),
	"F06":preload("res://assets/ui/spells_v2/f06_blazing_field.png"),
	"F07":preload("res://assets/ui/spells_v2/f07_molten_bomb.png"),
	"F08":preload("res://assets/ui/spells_v2/f08_piercing_flame.png"),
	"F09":preload("res://assets/ui/spells_v2/f09_heat_wave.png"),
	"F10":preload("res://assets/ui/spells_v2/f10_warm_guard.png"),
	"F11":preload("res://assets/ui/fire_formal_v1/f11_ignition_mark.png"),
	"I01":preload("res://assets/ui/ice_formal_v1/i01.png"),
	"I02":preload("res://assets/ui/ice_formal_v1/i02.png"),
	"I03":preload("res://assets/ui/ice_formal_v1/i03.png"),
	"I04":preload("res://assets/ui/ice_formal_v1/i04.png"),
	"I05":preload("res://assets/ui/ice_formal_v1/i05.png"),
	"I06":preload("res://assets/ui/ice_formal_v1/i06.png"),
	"I07":preload("res://assets/ui/ice_formal_v1/i07.png"),
	"I08":preload("res://assets/ui/ice_formal_v1/i08.png"),
	"I09":preload("res://assets/ui/ice_formal_v1/i09.png"),
	"I10":preload("res://assets/ui/ice_formal_v1/i10.png")
}
var spell_id="F01"
var tint=Color("f3b675")
var _center:Vector2
var _r:float
func _ready():
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
func _v(x:float,y:float)->Vector2:return _center+Vector2(x,y)*_r
func _line(points:Array,width:float=2.4,color:Color=Color.TRANSPARENT):
	var p=PackedVector2Array()
	for v in points:p.append(_v(v.x,v.y))
	draw_polyline(p,tint if color==Color.TRANSPARENT else color,width,true)
func _diamond(x:float,y:float,r:float,fill:bool=true):
	var p=PackedVector2Array([_v(x,y-r),_v(x+r*.6,y),_v(x,y+r),_v(x-r*.6,y)])
	if fill:draw_colored_polygon(p,tint)
	p.append(p[0]);draw_polyline(p,tint,2,true)
func _draw():
	if PAINTED.has(spell_id):
		var side=minf(size.x,size.y)
		var draw_size=Vector2.ONE*side
		if spell_id.begins_with("I"):
			var native_size=Vector2(PAINTED[spell_id].get_size())
			draw_size=native_size*minf(side/native_size.x,side/native_size.y)
		draw_texture_rect(PAINTED[spell_id],Rect2((size-draw_size)*.5,draw_size),false)
		return
	_center=size*.5
	_r=minf(size.x,size.y)*.37
	for i in range(4):draw_circle(_center,_r*(1.12-i*.18),Color(tint,.025+i*.012))
	draw_arc(_center,_r*1.12,.3,PI-.3,28,Color(tint,.3),1,true)
	draw_arc(_center,_r*1.12,PI+.3,TAU-.3,28,Color(tint,.3),1,true)
	match spell_id:
		"F01":
			var p=PackedVector2Array([_v(-.56,.68),_v(-.75,.04),_v(-.08,-1),_v(.08,-.24),_v(.6,-.62),_v(.66,.4),_v(.24,.86)])
			draw_colored_polygon(p,Color(tint,.22));p.append(p[0]);draw_polyline(p,tint,3,true)
			_line([Vector2(-.12,.6),Vector2(-.27,.15),Vector2(.1,-.23),Vector2(.28,.4)],2)
		"F02":
			_diamond(0,0,.64,false)
			for i in range(8):
				var a=i*TAU/8
				draw_line(_center+Vector2.from_angle(a)*_r*.76,_center+Vector2.from_angle(a)*_r*1.05,tint,2,true)
			draw_circle(_center,_r*.15,tint)
		"F03":
			for x in [-.6,0,.6]:
				_line([Vector2(x+.23,-.9),Vector2(x-.12,.25)],3)
				_diamond(x-.17,.48,.16)
			draw_arc(_v(0,.75),_r*.8,0,PI,24,tint,2,true)
		"F04":
			draw_circle(_center,_r*.31,Color(tint,.22));draw_arc(_center,_r*.31,0,TAU,40,tint,2,true)
			_line([Vector2(-.22,-.35),Vector2(-.7,-.6),Vector2(-.94,0),Vector2(-.52,.19)],3)
			_line([Vector2(.22,-.35),Vector2(.7,-.6),Vector2(.94,0),Vector2(.52,.19)],3)
			_line([Vector2(-.25,.4),Vector2(0,.95),Vector2(.25,.4)],2)
			_diamond(0,-.78,.13)
		"F05":
			for k in range(3):
				var p=PackedVector2Array()
				for j in range(35):
					var a=j*.075+k*TAU/3
					p.append(_center+Vector2.from_angle(a)*_r*(.12+j*.026))
				draw_polyline(p,tint,3,true)
		"F06":
			draw_arc(_center,_r*.86,0,TAU,60,tint,2,true)
			_line([Vector2(0,-.82),Vector2(.72,.42),Vector2(-.72,.42),Vector2(0,-.82)],2)
			_diamond(0,0,.24)
			for i in range(4):_diamond(cos(i*PI/2)*.96,sin(i*PI/2)*.96,.12)
		"F07":
			_diamond(0,0,.57)
			for i in range(8):
				var a=i*TAU/8
				draw_line(_center+Vector2.from_angle(a)*_r*.65,_center+Vector2.from_angle(a)*_r*(1.1 if i%2==0 else .88),tint,3,true)
		"F08":
			_line([Vector2(-.88,.83),Vector2(.71,-.75)],8,Color(tint,.22))
			_line([Vector2(-.88,.83),Vector2(.71,-.75)],3)
			_line([Vector2(-.6,-.1),Vector2(-.16,-.53)],2)
			_line([Vector2(.1,.6),Vector2(.53,.16)],2)
			_diamond(.66,-.7,.23)
		"F09":
			for y in [-.5,0,.5]:_line([Vector2(-.86,y+.18),Vector2(-.42,y-.18),Vector2(0,y+.18),Vector2(.42,y-.18),Vector2(.86,y+.18)],2.4)
		"F10":
			_line([Vector2(0,-.95),Vector2(.76,-.62),Vector2(.66,.4),Vector2(0,.95),Vector2(-.66,.4),Vector2(-.76,-.62),Vector2(0,-.95)],3)
			_line([Vector2(0,-.4),Vector2(0,.45)],3)
			_line([Vector2(-.35,0),Vector2(.35,0)],3)
		_:
			_diamond(0,0,.9,false)
			_diamond(0,0,.4,false)
