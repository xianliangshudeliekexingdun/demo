extends Control
## Read-only HUD ornament. Geometry stays crisp at every canvas scale.
const LINA = preload("res://assets/ui/lina_portrait.png")
var ratio: float = 1.0
var selected: int = 0

func bevel(rect: Rect2, cut: float) -> PackedVector2Array:
	var p = rect.position
	var e = rect.end
	return PackedVector2Array([p+Vector2(cut,0),Vector2(e.x-cut,p.y),Vector2(e.x,p.y+cut),e-Vector2(0,cut),e-Vector2(cut,0),Vector2(p.x+cut,e.y),Vector2(p.x,e.y-cut),p+Vector2(0,cut)])

func plate(rect: Rect2, cut: float, color: Color, edge: Color, width: float = 1.0):
	var points = bevel(rect,cut)
	draw_colored_polygon(points,color)
	points.append(points[0])
	draw_polyline(points,edge,width,true)

var show_selection=true
func _draw():
	draw_set_transform(Vector2(0,16))
	# The portrait overlaps the bar, as on the supplied reference.
	plate(Rect2(71,35,246,30),7,Color("171b1c"),Color("171719"),4)
	plate(Rect2(73,35,242,27),6,Color("66665f"),Color("b0aa93"),1.5)
	plate(Rect2(77,39,234,19),4,Color("161b1c"),Color("343735"),2)
	if ratio > 0:
		var fill = Rect2(80,42,228*clampf(ratio,0,1),13)
		draw_rect(fill,Color("bc4944"))
		draw_rect(Rect2(fill.position,Vector2(fill.size.x,4)),Color("e77462"))
		draw_line(fill.position+Vector2(0,12),fill.end,Color("772f36"),2)
	draw_line(Vector2(83,36),Vector2(302,36),Color("dad0b5"),1,true)
	draw_line(Vector2(82,63),Vector2(302,63),Color("323539"),2,true)
	draw_texture_rect(LINA,Rect2(16,-4,92,92),false)
	draw_set_transform(Vector2.ZERO)
	if not show_selection: return
	# Slim selection brackets live outside the icon, never over its painting.
	var x = 520.0 + selected*84.0
	var gold = Color("f1d79a")
	for offset in [Vector2(-3,-3),Vector2(75,-3),Vector2(-3,75),Vector2(75,75)]:
		var p = Vector2(x,620)+offset
		var sx = 1 if offset.x<0 else -1
		var sy = 1 if offset.y<0 else -1
		draw_line(p,p+Vector2(10*sx,0),gold,2,true)
		draw_line(p,p+Vector2(0,10*sy),gold,2,true)
