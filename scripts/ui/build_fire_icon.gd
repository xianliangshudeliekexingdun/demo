extends Control
const TEXTURE=preload("res://assets/ui/fireball.png")
func _draw():
	draw_texture_rect_region(TEXTURE,Rect2(0,0,34,34),Rect2(97,95,1056,1058))
