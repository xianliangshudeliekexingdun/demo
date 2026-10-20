extends Node2D
## Whole-body keypose review only: four keys of a half-step, not a walk loop.
const SHEET = preload("res://assets/prototypes/lina-motion/keyposes-v3.png")
const ANCHORS = [Vector2(367,614),Vector2(963,614),Vector2(371,1234),Vector2(970,1221)]
const REGIONS = [Rect2(0,0,620,633),Rect2(620,0,621,633),Rect2(0,633,620,634),Rect2(620,633,621,634)]
var pose = 0
var magnify = 0.26

func _draw():
	var region: Rect2 = REGIONS[pose]
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE*magnify)
	draw_texture_rect_region(SHEET,Rect2(region.position-ANCHORS[pose],region.size),region)
	draw_set_transform(Vector2.ZERO)
