extends Control
## Painted local progression equipment. Item identity is read-only UI state.
const PAINTED = {
	# The MC01-MC03 items are retired: MC01 art is reused by MC04, MC05 art is
	# derived from MC02, and the MC02/MC03 originals stay archived.
	"MC04": preload("res://assets/ui/equipment_v2/mc01.png"),
	"MC05": preload("res://assets/ui/equipment_v2/mc05_ice.png"),
	"MG01": preload("res://assets/ui/equipment_v2/mg01.png"),
	"MG02": preload("res://assets/ui/equipment_v2/mg02.png"),
	"MG03": preload("res://assets/ui/equipment_v2/mg03.png"),
}
var item_id: String = "":
	set(value):
		item_id = value.to_upper()
		queue_redraw()

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func set_item(id: String):
	item_id = id

func _draw():
	var side = minf(size.x, size.y)
	if PAINTED.has(item_id):
		draw_texture_rect(PAINTED[item_id], Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side), false)
	else:
		# A genuinely unequipped slot has an outline, never a different item's art.
		var center = size * 0.5
		var r = side * 0.30
		var points = PackedVector2Array([center + Vector2(0, -r), center + Vector2(r * 0.7, 0), center + Vector2(0, r), center - Vector2(r * 0.7, 0), center + Vector2(0, -r)])
		draw_polyline(points, Color("63748a"), 1.5, true)
