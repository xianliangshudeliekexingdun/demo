extends Control
## Painted fire/ice retain their assets; the four newer schools use authored vector emblems.
## Static, read-only drawing: no clocks, RNG, gameplay state, textures or fonts are created.
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
const PROCEDURAL_SPELLS=["L01","L02","L03","L04","L05","L06","L07","L08","L09","L10","W01","W02","W03","W04","W05","W06","W07","W08","W09","W10","R01","R02","R03","R04","R05","R06","R07","R08","R09","R10","S01","S02","S03","S04","S05","S06","S07","S08","S09","S10"]
static func supports_spell(id:String)->bool:return PAINTED.has(id) or id in PROCEDURAL_SPELLS
const PROCEDURAL_CATALYSTS=["MC06","MC07","MC08","MC09"]
const CATALYST_SCHOOLS={"MC04":"fire","MC05":"ice","MC06":"lightning","MC07":"wind","MC08":"earth","MC09":"spirit"}
var spell_id = "F01"
var tint = Color("f3b675")
var _center: Vector2
var _r: float
var _stroke_scale: float = 1.0
var _light: Color
var _shade: Color
var _detail: bool = false
const INK = Color("101827")

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _v(x: float, y: float) -> Vector2:
	return _center + Vector2(x, y) * _r

func _points(points: Array) -> PackedVector2Array:
	var result = PackedVector2Array()
	for point in points:
		result.append(_v(point.x, point.y))
	return result

func _line(points: Array, width: float = 2.4, color: Color = Color.TRANSPARENT):
	if points.size() < 2: return
	var path = _points(points)
	var stroke: Color = tint if color == Color.TRANSPARENT else color
	# The dark keyline keeps pale strokes legible on both bright cards and dark slots.
	draw_polyline(path, INK, (width + 1.8) * _stroke_scale, true)
	draw_polyline(path, stroke, width * _stroke_scale, true)
	if width >= 3.2 and color == Color.TRANSPARENT:
		draw_polyline(path, _light, .9 * _stroke_scale, true)

func _shape(points: Array, color: Color = Color.TRANSPARENT):
	var path = _points(points)
	if path.size() < 3: return
	draw_colored_polygon(path, _shade if color == Color.TRANSPARENT else color)
	path.append(path[0])
	draw_polyline(path, INK, 4.4 * _stroke_scale, true)
	draw_polyline(path, tint, 2.3 * _stroke_scale, true)

func _facet(points: Array, color: Color):
	draw_colored_polygon(_points(points), color)

func _arc(x: float, y: float, radius: float, start: float, end: float, width: float = 2.4, color: Color = Color.TRANSPARENT):
	var stroke: Color = tint if color == Color.TRANSPARENT else color
	var segments: int = maxi(12, int(absf(end - start) * 8.0))
	draw_arc(_v(x, y), _r * radius, start, end, segments, INK, (width + 1.7) * _stroke_scale, true)
	draw_arc(_v(x, y), _r * radius, start, end, segments, stroke, width * _stroke_scale, true)

func _node(x: float, y: float, radius: float = .14):
	draw_circle(_v(x, y), _r * radius + _stroke_scale * 1.2, INK)
	draw_circle(_v(x, y), _r * radius, tint.darkened(.25))
	draw_circle(_v(x - radius * .18, y - radius * .18), _r * radius * .5, _light)

func _diamond(x: float, y: float, radius: float, fill: bool = true):
	var path = [Vector2(x, y - radius), Vector2(x + radius * .62, y), Vector2(x, y + radius), Vector2(x - radius * .62, y)]
	if fill:
		_shape(path)
		_facet([path[0], path[1], path[2], Vector2(x, y)], tint.darkened(.12))
		_line([path[3], path[0], path[1]], 1.7, _light)
	else:
		path.append(path[0])
		_line(path, 2.3)

func _bolt(x: float = 0.0, y: float = 0.0, scale: float = 1.0):
	var vertices = [Vector2(.29,-.86), Vector2(-.39,.06), Vector2(-.04,.06), Vector2(-.28,.85), Vector2(.43,-.22), Vector2(.07,-.22)]
	var path: Array = []
	for point in vertices: path.append(point * scale + Vector2(x,y))
	_shape(path, tint.darkened(.1))
	_line([Vector2(.25,-.73)*scale+Vector2(x,y), Vector2(-.28,0)*scale+Vector2(x,y), Vector2(.07,0)*scale+Vector2(x,y)], 1.6, _light)

func _shield():
	_shape([Vector2(0,-.89),Vector2(.67,-.58),Vector2(.55,.34),Vector2(0,.88),Vector2(-.55,.34),Vector2(-.67,-.58)])
	_facet([Vector2(0,-.79),Vector2(.56,-.53),Vector2(.45,.3),Vector2(0,.74)],tint.darkened(.25))
	_line([Vector2(-.5,-.49),Vector2(0,-.73),Vector2(.5,-.49)],1.6,_light)

func _book():
	_shape([Vector2(0,-.46),Vector2(-.69,-.69),Vector2(-.69,.61),Vector2(0,.83),Vector2(.69,.61),Vector2(.69,-.69)])
	_facet([Vector2(.05,-.38),Vector2(.61,-.57),Vector2(.61,.55),Vector2(.05,.73)],tint.darkened(.24))
	_line([Vector2(0,-.42),Vector2(0,.75)],2.0,_light)
	_line([Vector2(-.52,-.24),Vector2(-.19,-.14)],1.5)
	if _detail: _line([Vector2(-.52,.04),Vector2(-.19,.14)],1.4)

func _wisp(x: float, y: float, scale: float):
	var path: Array = []
	for point in [Vector2(0,-.7),Vector2(.3,-.42),Vector2(.27,.02),Vector2(.5,.61),Vector2(.12,.42),Vector2(-.05,.72),Vector2(-.23,.4),Vector2(-.5,.57),Vector2(-.27,.02),Vector2(-.3,-.42)]:
		path.append(point*scale+Vector2(x,y))
	_shape(path,tint.darkened(.24))
	_facet([Vector2(x,y-.59*scale),Vector2(x+.22*scale,y-.35*scale),Vector2(x+.16*scale,y+.29*scale),Vector2(x,y+.52*scale)],tint.darkened(.02))
	for dx in [-.105,.105]:
		draw_circle(_v(x+dx*scale,y-.22*scale),maxf(_r*.045*scale,.8*_stroke_scale),_light)

func _badge():
	# One quiet backing, then the authored silhouette; no animated UI glow or tiny labels.
	draw_circle(_center+Vector2(0,1.5*_stroke_scale),_r*1.14,Color(INK,.66))
	draw_circle(_center,_r*1.09,Color(_shade,.74))
	draw_circle(_center,_r*.86,Color(tint,.045))
	_arc(0,0,1.11,.12,PI-.12,1.2,Color(tint,.38))
	_arc(0,0,1.11,PI+.12,TAU-.12,1.2,Color(tint,.25))
	if _detail:
		for x in [-1.11,1.11]: _node(x,0,.035)

func _draw():
	if PAINTED.has(spell_id):
		var side = minf(size.x,size.y)
		var draw_size = Vector2.ONE*side
		if spell_id.begins_with("I"):
			var native_size = Vector2(PAINTED[spell_id].get_size())
			draw_size = native_size*minf(side/native_size.x,side/native_size.y)
		draw_texture_rect(PAINTED[spell_id],Rect2((size-draw_size)*.5,draw_size),false)
		return
	_center = size*.5
	_r = minf(size.x,size.y)*.37
	if _r <= 0.0: return
	_stroke_scale = clampf(minf(size.x,size.y)/72.0,.5,1.8)
	_detail = minf(size.x,size.y) >= 64.0
	_light = tint.lerp(Color.WHITE,.72)
	_shade = tint.lerp(INK,.7)
	if spell_id not in PROCEDURAL_SPELLS and spell_id not in PROCEDURAL_CATALYSTS:
		_draw_utility()
		return
	_badge()
	if spell_id in PROCEDURAL_CATALYSTS:
		_draw_catalyst()
	elif spell_id.begins_with("L") and spell_id in PROCEDURAL_SPELLS:
		_draw_lightning()
	elif spell_id.begins_with("W") and spell_id in PROCEDURAL_SPELLS:
		_draw_wind()
	elif spell_id.begins_with("R") and spell_id in PROCEDURAL_SPELLS:
		_draw_earth()
	elif spell_id.begins_with("S") and spell_id in PROCEDURAL_SPELLS:
		_draw_spirit()

func _draw_utility():
	# Existing empty-slot/unknown utility appearance is outside the four-school pass.
	for i in range(4): draw_circle(_center,_r*(1.12-i*.18),Color(tint,.025+i*.012))
	draw_arc(_center,_r*1.12,.3,PI-.3,28,Color(tint,.3),1,true)
	draw_arc(_center,_r*1.12,PI+.3,TAU-.3,28,Color(tint,.3),1,true)
	for radius in [.9,.4]:
		var path = _points([Vector2(0,-radius),Vector2(radius*.6,0),Vector2(0,radius),Vector2(-radius*.6,0),Vector2(0,-radius)])
		draw_polyline(path,tint,2,true)

func _draw_lightning():
	match spell_id:
		"L01": # An unmistakable solid bolt, rather than the spear's long shaft.
			_bolt(0,0,1.05)
			_line([Vector2(-.86,.61),Vector2(-.62,.31)],2.0)
			_line([Vector2(.58,-.57),Vector2(.82,-.86)],2.0,_light)
		"L02":
			_shape([Vector2(-.8,.78),Vector2(.18,-.36),Vector2(.13,-.55),Vector2(.88,-.91),Vector2(.55,-.15),Vector2(.36,-.18),Vector2(-.73,.85)],tint.darkened(.08))
			_line([Vector2(-.63,.66),Vector2(.66,-.64)],2.0,_light)
			_line([Vector2(-.77,.03),Vector2(-.29,-.1),Vector2(-.37,.15)],2.0)
			_line([Vector2(.12,.74),Vector2(.25,.26),Vector2(-.01,.35)],2.0)
		"L03":
			var nodes = [Vector2(-.67,.55),Vector2(-.08,-.55),Vector2(.72,.29)]
			_line([nodes[0],Vector2(-.5,-.01),Vector2(-.29,.12),nodes[1],Vector2(.25,-.2),Vector2(.28,.04),nodes[2]],3.8)
			for point in nodes: _node(point.x,point.y,.2)
		"L04":
			_diamond(0,0,.46)
			for i in range(4):
				var p = Vector2.from_angle(float(i)*PI*.5+PI*.25)*.8
				_line([p*.55,p*.78],2.1)
				_diamond(p.x,p.y,.18)
			_arc(0,0,.69,-.22,.22,1.7)
			_arc(0,0,.69,PI-.22,PI+.22,1.7)
		"L05":
			# Cloud masses are filled, preserving a broad silhouette at slot size.
			for item in [Vector3(-.4,-.29,.31),Vector3(.02,-.44,.4),Vector3(.47,-.25,.29)]:
				draw_circle(_v(item.x,item.y),_r*item.z+1.2*_stroke_scale,INK)
				draw_circle(_v(item.x,item.y),_r*item.z,tint.darkened(.4))
			_shape([Vector2(-.68,-.29),Vector2(.7,-.25),Vector2(.7,.03),Vector2(-.68,.03)],tint.darkened(.35))
			_arc(.02,-.4,.28,PI*1.14,PI*1.83,1.7,_light)
			_bolt(.04,.47,.6)
		"L06":
			_arc(0,0,.89,0,TAU,3.2)
			_arc(0,0,.57,-.8,1.2,2.2,_light)
			_arc(0,0,.57,PI-.8,PI+1.2,2.2)
			_bolt(0,0,.44)
			for x in [-1.03,1.03]: _line([Vector2(x,-.14),Vector2(x,.14)],2.3)
		"L07":
			_bolt(0,-.33,.73)
			_shape([Vector2(-.67,.8),Vector2(-.22,.36),Vector2(-.03,.53),Vector2(.22,.31),Vector2(.69,.8)])
			_line([Vector2(-.1,.31),Vector2(.07,.6),Vector2(-.09,.8)],2.4,_light)
			_line([Vector2(-.85,.35),Vector2(-.56,.5)],2.4)
			_line([Vector2(.83,.29),Vector2(.53,.48)],2.4)
		"L08":
			var nodes = [Vector2(0,-.83),Vector2(.78,-.02),Vector2(.34,.8),Vector2(-.72,.5),Vector2(-.36,-.22)]
			_line([nodes[0],nodes[1],nodes[2],nodes[3],nodes[4],nodes[0]],2.7)
			_line([nodes[1],nodes[4],nodes[2]],2.1,_light)
			for point in nodes: _node(point.x,point.y,.135)
		"L09":
			_shield()
			_bolt(0,0,.55)
			for x in [-.89,.89]: _line([Vector2(x,-.33),Vector2(x*.88,-.04),Vector2(x,.18)],2.0)
		"L10":
			_book()
			_bolt(.35,-.01,.4)
			_node(0,-.86,.085)

func _draw_wind():
	match spell_id:
		"W01":
			_shape([Vector2(-.87,.74),Vector2(-.36,.1),Vector2(.03,-.23),Vector2(.81,-.8),Vector2(.58,-.04),Vector2(.13,.36)],tint.darkened(.18))
			_line([Vector2(-.71,.65),Vector2(.07,.01),Vector2(.71,-.68)],1.8,_light)
			_line([Vector2(-.8,-.06),Vector2(-.39,-.37)],2)
			_line([Vector2(-.07,.76),Vector2(.45,.39)],2)
		"W02":
			_arc(0,0,.79,-PI*.86,PI*.57,4.5)
			_arc(0,0,.43,PI*.15,PI*1.69,2.7,_light)
			_shape([Vector2(-.68,.4),Vector2(-.77,.94),Vector2(-.24,.73)],tint.darkened(.02))
			_shape([Vector2(.19,-.32),Vector2(.02,-.66),Vector2(-.22,-.34)])
		"W03":
			_shape([Vector2(-.75,.84),Vector2(.35,-.42),Vector2(.16,-.73),Vector2(.86,-.89),Vector2(.72,-.17),Vector2(.43,-.32),Vector2(-.69,.91)],tint.darkened(.12))
			_line([Vector2(-.64,.75),Vector2(.64,-.66)],1.7,_light)
			_line([Vector2(-.82,.22),Vector2(-.48,.17),Vector2(-.54,-.16)],2.4)
			_line([Vector2(-.26,.8),Vector2(-.21,.46),Vector2(.12,.52)],2.4)
		"W04":
			_facet([Vector2(-.79,0),Vector2(.76,-.64),Vector2(.76,.64)],Color(tint,.12))
			for y in [-.56,0,.56]:
				_line([Vector2(-.77,0),Vector2(.75,y)],3.3)
				_shape([Vector2(.43,y-.15),Vector2(.86,y),Vector2(.48,y+.16)],tint.darkened(.12))
			_arc(-.8,0,.25,-.58,.58,2.0,_light)
		"W05":
			for i in range(3):
				var path: Array = []
				for j in range(21):
					var a = float(i)*TAU/3+float(j)*.11
					path.append(Vector2.from_angle(a)*(.91-float(j)*.032))
				_line(path,3.4)
				var p: Vector2 = path[-1]
				_node(p.x,p.y,.06)
			_node(0,0,.15)
		"W06":
			_arc(0,0,.43,0,TAU,3.0,_light)
			for i in range(6):
				var axis = Vector2.from_angle(float(i)*TAU/6)
				var side = Vector2(-axis.y,axis.x)*.13
				_line([axis*.98,axis*.63],2.7)
				_shape([axis*.77+side,axis*.48,axis*.77-side])
		"W07":
			for sign_x in [-1.0,1.0]:
				_shape([Vector2(sign_x*.91,.56),Vector2(sign_x*.66,-.79),Vector2(sign_x*.37,-.31),Vector2(-sign_x*.29,.41),Vector2(-sign_x*.71,.76),Vector2(sign_x*.25,.36)],tint.darkened(.25))
				_line([Vector2(sign_x*.65,-.57),Vector2(sign_x*.35,-.01),Vector2(-sign_x*.52,.66)],1.7,_light)
		"W08":
			_line([Vector2(-.83,.73),Vector2(-.34,.43),Vector2(-.44,-.15),Vector2(.23,-.13),Vector2(.73,-.79)],4.3)
			_line([Vector2(-.69,.95),Vector2(-.11,.52),Vector2(-.19,.13),Vector2(.38,.07),Vector2(.94,-.61)],1.7,Color(tint,.65))
			for point in [Vector2(-.6,.58),Vector2(-.38,.08),Vector2(.31,-.26)]: _node(point.x,point.y,.105)
			_shape([Vector2(.45,-.76),Vector2(.84,-.92),Vector2(.78,-.5)],tint.darkened(.08))
		"W09":
			for x in [-.52,0,.52]:
				_line([Vector2(x,-.88),Vector2(x-.13,-.34),Vector2(x+.13,.3),Vector2(x,.85)],3.8)
			_line([Vector2(-.91,-.42),Vector2(-.72,-.42)],2.2,_light)
			_shape([Vector2(.75,.29),Vector2(.97,.43),Vector2(.76,.58)],tint.darkened(.12))
		"W10":
			_book()
			_shape([Vector2(.2,.36),Vector2(.16,-.11),Vector2(.34,-.5),Vector2(.86,-.84),Vector2(.73,-.25),Vector2(.48,.15)],tint.darkened(.08))
			_line([Vector2(.21,.4),Vector2(.69,-.61)],1.6,_light)

func _draw_earth():
	match spell_id:
		"R01":
			_line([Vector2(-.81,.82),Vector2(-.15,.13)],4)
			_shape([Vector2(-.11,.15),Vector2(-.1,-.39),Vector2(.56,-.89),Vector2(.74,-.2),Vector2(.3,.37)])
			_facet([Vector2(-.1,-.39),Vector2(.56,-.89),Vector2(.29,-.12),Vector2(.3,.37)],tint.darkened(.05))
			_line([Vector2(-.1,-.39),Vector2(.29,-.12),Vector2(.56,-.89)],1.6,_light)
			for p in [Vector2(-.54,-.59),Vector2(.85,.42)]: _diamond(p.x,p.y,.17)
		"R02":
			for radius in [.36,.65,.96]: _arc(0,.46,radius,PI*1.04,TAU*.98,3.2)
			_shape([Vector2(-.68,.79),Vector2(-.32,.59),Vector2(-.08,.76),Vector2(.18,.58),Vector2(.67,.79)])
			_line([Vector2(0,.47),Vector2(-.1,.7),Vector2(.05,.91)],1.8,_light)
		"R03":
			for x in [-.49,-.13,.28]: _line([Vector2(x,-.96),Vector2(x+.1,-.58)],2.2)
			_shape([Vector2(-.3,-.38),Vector2(.2,-.62),Vector2(.56,-.19),Vector2(.3,.32),Vector2(-.23,.2)])
			_facet([Vector2(.2,-.62),Vector2(.56,-.19),Vector2(.3,.32),Vector2(.09,-.12)],tint.darkened(.08))
			_line([Vector2(-.3,-.38),Vector2(.09,-.12),Vector2(.2,-.62)],1.7,_light)
			_shape([Vector2(-.8,.77),Vector2(-.49,.47),Vector2(-.17,.72),Vector2(.15,.45),Vector2(.77,.78)])
		"R04":
			_shape([Vector2(-.36,.68),Vector2(-.36,-.61),Vector2(.02,-.91),Vector2(.4,-.61),Vector2(.4,.68)])
			_facet([Vector2(.02,-.91),Vector2(.4,-.61),Vector2(.4,.68),Vector2(.02,.51)],tint.darkened(.08))
			_line([Vector2(.02,-.82),Vector2(.02,.5)],1.8,_light)
			_shape([Vector2(-.58,.7),Vector2(-.36,.49),Vector2(.4,.49),Vector2(.6,.7),Vector2(.6,.87),Vector2(-.58,.87)])
			if _detail: _arc(0,.56,.67,0,PI,1.7,Color(tint,.7))
		"R05":
			_shield()
			for y in [-.25,.16]:
				_shape([Vector2(-.34,y-.12),Vector2(0,y-.28),Vector2(.34,y-.12),Vector2(.27,y+.13),Vector2(0,y+.3),Vector2(-.27,y+.13)],tint.darkened(.15))
			_line([Vector2(0,-.49),Vector2(0,.57)],1.7,_light)
		"R06":
			_shape([Vector2(-.76,-.73),Vector2(-.33,-.79),Vector2(-.17,-.16),Vector2(-.42,.14),Vector2(-.63,-.17)])
			_shape([Vector2(.22,-.58),Vector2(.64,-.8),Vector2(.76,-.12),Vector2(.4,.25),Vector2(.11,.02)],tint.darkened(.16))
			_line([Vector2(-.82,.73),Vector2(-.41,.42),Vector2(-.03,.82),Vector2(.42,.41),Vector2(.85,.71)],3.7)
			_line([Vector2(-.02,-.73),Vector2(.05,-.3),Vector2(-.14,.02)],1.8,_light)
		"R07":
			for x in [-.62,.62]:
				_shape([Vector2(x-.17,.57),Vector2(x-.17,-.21),Vector2(x,-.48),Vector2(x+.17,-.21),Vector2(x+.17,.57)])
				_line([Vector2(x,-.35),Vector2(x,.4)],1.5,_light)
			_line([Vector2(-.44,.1),Vector2(-.2,.1),Vector2(-.07,-.22),Vector2(.1,.35),Vector2(.24,.1),Vector2(.44,.1)],3.1)
			_arc(0,.52,.65,0,PI,2.2)
		"R08":
			_shape([Vector2(-.86,.65),Vector2(-.35,-.43),Vector2(-.03,-.03),Vector2(.34,-.88),Vector2(.91,.65)])
			_facet([Vector2(.34,-.88),Vector2(.91,.65),Vector2(.36,.65),Vector2(.16,.14)],tint.darkened(.07))
			_line([Vector2(.28,-.66),Vector2(.1,-.26),Vector2(.35,.11),Vector2(.13,.58)],2,_light)
			_line([Vector2(-.85,.91),Vector2(-.37,.79)],2.6)
			_line([Vector2(.39,.8),Vector2(.88,.95)],2.6)
		"R09":
			_arc(0,.13,.86,PI*.97,TAU*1.02,3.5)
			_shape([Vector2(-.33,.65),Vector2(-.33,-.6),Vector2(0,-.77),Vector2(.33,-.6),Vector2(.33,.65)])
			_diamond(0,-.13,.23)
			_shape([Vector2(-.53,.65),Vector2(.53,.65),Vector2(.65,.87),Vector2(-.65,.87)])
			if _detail: _line([Vector2(-.16,.34),Vector2(.16,.34)],1.5,_light)
		"R10":
			_book()
			_diamond(.34,-.03,.36)
			_line([Vector2(-.49,.36),Vector2(-.19,.45)],1.6,_light)

func _draw_spirit():
	match spell_id:
		"S01":
			_line([Vector2(-.81,.79),Vector2(.3,-.32)],4.1)
			_diamond(.45,-.46,.39)
			_arc(.45,-.46,.49,-.24,PI*1.61,2.1,_light)
			_line([Vector2(-.76,.19),Vector2(-.32,-.23)],1.8)
			_line([Vector2(-.2,.77),Vector2(.1,.49)],1.8)
		"S02":
			_wisp(0,.02,.98)
			_arc(0,-.62,.34,PI*1.04,TAU*.98,2.0,_light)
			for x in [-.73,.73]: _diamond(x,-.21,.15)
			_arc(0,.48,.65,0,PI,1.8)
		"S03":
			_shape([Vector2(-.69,-.48),Vector2(-.4,-.77),Vector2(-.11,-.48),Vector2(-.17,-.14),Vector2(-.6,-.14)])
			_line([Vector2(-.56,-.4),Vector2(-.25,-.4)],2.0,_light)
			_shape([Vector2(-.61,-.04),Vector2(-.2,-.04),Vector2(.02,.71),Vector2(-.36,.5),Vector2(-.79,.75)])
			_shape([Vector2(.11,.48),Vector2(.53,-.62),Vector2(.8,-.91),Vector2(.8,-.51),Vector2(.28,.56)],tint.darkened(.02))
			_line([Vector2(-.03,.14),Vector2(.49,.38)],3.0,_light)
		"S04":
			_shape([Vector2(-.97,-.47),Vector2(-.42,-.18),Vector2(-.16,-.44),Vector2(0,-.22),Vector2(.17,-.45),Vector2(.43,-.18),Vector2(.97,-.47),Vector2(.64,.15),Vector2(.27,.3),Vector2(0,.85),Vector2(-.27,.3),Vector2(-.64,.15)])
			for sign_x in [-1.0,1.0]:
				_facet([Vector2(sign_x*.79,-.29),Vector2(sign_x*.42,-.06),Vector2(sign_x*.12,.11),Vector2(sign_x*.3,.27),Vector2(sign_x*.6,.08)],tint.darkened(.05))
				_line([Vector2(sign_x*.73,-.2),Vector2(sign_x*.39,.07)],1.5,_light)
			_diamond(0,-.03,.15)
		"S05":
			_diamond(0,-.62,.29)
			for x in [-.67,0,.67]:
				_line([Vector2(0,-.26),Vector2(x,.15)],2.0)
				_wisp(x,.48,.38)
			_arc(0,-.48,.53,PI*1.13,PI*1.87,1.8,_light)
		"S06":
			_wisp(-.25,-.25,.55)
			_diamond(.2,.28,.28)
			for i in range(5):
				var axis = Vector2.from_angle(float(i)*TAU/5-.27)
				_line([Vector2(.2,.28)+axis*.43,Vector2(.2,.28)+axis*.76],3.3)
			_arc(-.04,.06,.87,PI*.96,PI*1.75,2.6)
		"S07":
			_arc(0,0,.88,0,TAU,2.8)
			_line([Vector2(0,-.69),Vector2(.6,.35),Vector2(-.6,.35),Vector2(0,-.69)],2.3)
			for i in range(3):
				var p = Vector2.from_angle(-PI*.5+float(i)*TAU/3)*.84
				_diamond(p.x,p.y,.16)
			_wisp(0,.04,.35)
		"S08":
			for i in range(3):
				var p = Vector2(-.53+float(i)*.47,.53-float(i)*.47)
				_arc(p.x,p.y,.29,0,TAU,3.5)
			_diamond(.66,-.66,.22)
			_line([Vector2(-.91,.51),Vector2(-.78,.36)],2.0,_light)
		"S09":
			_shield()
			_wisp(0,-.04,.58)
			_arc(0,-.43,.28,PI*1.1,PI*1.9,1.6,_light)
		"S10":
			_book()
			_arc(.25,-.18,.19,0,TAU,2.2,_light)
			_arc(.42,.09,.19,0,TAU,2.2)
			_diamond(0,-.81,.1)

func _draw_catalyst():
	_shape([Vector2(-.25,-.9),Vector2(.25,-.9),Vector2(.25,-.49),Vector2(.61,.1),Vector2(.49,.85),Vector2(-.49,.85),Vector2(-.61,.1),Vector2(-.25,-.49)])
	_facet([Vector2(-.49,.17),Vector2(.49,.17),Vector2(.4,.74),Vector2(-.4,.74)],Color(tint,.22))
	_shape([Vector2(-.3,-.98),Vector2(.3,-.98),Vector2(.3,-.73),Vector2(-.3,-.73)],tint.darkened(.25))
	_line([Vector2(-.4,.13),Vector2(-.33,.62)],1.8,_light)
	match spell_id:
		"MC06":
			_bolt(.02,.17,.56)
			for x in [-.83,.83]: _diamond(x,-.06,.12)
		"MC07":
			for y in [-.1,.17,.44]:
				_line([Vector2(-.3,y+.07),Vector2(-.04,y-.06),Vector2(.28,y+.01)],2.8)
			_arc(.02,.14,.81,PI*.84,PI*1.25,1.8)
		"MC08":
			_diamond(.02,.04,.31)
			_shape([Vector2(-.29,.49),Vector2(-.08,.34),Vector2(.3,.49),Vector2(.26,.65),Vector2(-.25,.65)],tint.darkened(.08))
			_diamond(-.82,.45,.13)
		"MC09":
			_arc(-.1,.02,.2,0,TAU,2.7,_light)
			_arc(.16,.32,.2,0,TAU,2.7)
			_line([Vector2(-.03,.15),Vector2(.08,.2)],2.4)
			_diamond(.82,-.03,.12)
