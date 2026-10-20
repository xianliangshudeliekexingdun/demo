extends Control
## Original geometric courtyard ornament, drawn without external artwork.
var motif="room"
var tint=Color("c6a66c")
var variant=0
func _ready():mouse_filter=Control.MOUSE_FILTER_IGNORE
func _draw():
	if motif=="background":
		draw_rect(Rect2(Vector2.ZERO,size),Color("0e1320"))
		for i in range(18):draw_circle(Vector2(1130,410),490-i*23,Color(.14,.2,.29,.032))
		for x in [782,1420]:
			draw_rect(Rect2(x,170,58,570),Color("151d2b"))
			draw_rect(Rect2(x-12,154,82,24),Color("202a3b"))
			draw_line(Vector2(x+3,190),Vector2(x+3,738),Color("2a3444"),2)
		draw_arc(Vector2(1130,400),320,PI,TAU,72,Color("202b3d"),34,true)
		draw_arc(Vector2(1130,400),293,PI,TAU,72,Color("354054"),1,true)
		for i in range(18):
			var x=748+fmod(i*211.0,740)
			var y=110+fmod(i*157.0,640)
			draw_circle(Vector2(x,y),1.2,Color(tint,.28))
		draw_line(Vector2(48,839),Vector2(1552,839),Color(tint,.24),1)
		return
	var center=size/2
	var r=minf(size.x,size.y)*.38
	if motif=="gem":
		var points=PackedVector2Array([Vector2(0,-1),Vector2(.72,-.36),Vector2(.55,.62),Vector2(0,1),Vector2(-.55,.62),Vector2(-.72,-.36)])
		for i in range(points.size()):points[i]=center+points[i]*r
		draw_colored_polygon(points,Color(tint,.16))
		var outline=points.duplicate();outline.append(points[0]);draw_polyline(outline,tint,2.4,true)
		for p in points:draw_line(p,center,Color(tint,.55),1.5,true)
	else:
		for n in [1.0,.87,.63]:draw_arc(center,r*n,0,TAU,90,Color(tint,.4 if n==1.0 else .22),1.5,true)
		for i in range(12):
			var v=Vector2.from_angle(i*TAU/12)
			draw_line(center+v*r*.9,center+v*r,Color(tint,.65),2,true)
		for i in range(4):
			var a=i*PI/2
			var v=Vector2.from_angle(a)
			var w=v.orthogonal()
			draw_polyline(PackedVector2Array([center+v*r*.74,center+v*r*.5+w*r*.15,center+v*r*.26,center+v*r*.5-w*r*.15,center+v*r*.74]),Color(tint,.6),1.5,true)
