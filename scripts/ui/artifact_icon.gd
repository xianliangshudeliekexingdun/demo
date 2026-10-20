extends Control
## Painted run-local artifacts, with source rarity frames and a safe unknown-ID fallback.
const PAINTED = {
	"B04": preload("res://assets/ui/artifacts_v2/b04.png"),
	"P01": preload("res://assets/ui/artifacts_v2/p01.png"),
	"P04": preload("res://assets/ui/artifacts_v2/p04.png"),
	"P05": preload("res://assets/ui/artifacts_v2/p05.png"),
	"G02": preload("res://assets/ui/artifacts_v2/g02.png"),
	"U01": preload("res://assets/ui/artifacts_v2/u01.png"),
	"U02": preload("res://assets/ui/artifacts_v2/u02.png"),
	"U03": preload("res://assets/ui/artifacts_v2/u03.png"),
	"GU04": preload("res://assets/ui/generic_items_v1/gu04.png"),
	"GU05": preload("res://assets/ui/generic_items_v1/gu05.png"),
	"GU06": preload("res://assets/ui/generic_items_v1/gu06.png"),
	"GU07": preload("res://assets/ui/generic_items_v1/gu07.png"),
	"GU08": preload("res://assets/ui/generic_items_v1/gu08.png"),
	"GU09": preload("res://assets/ui/generic_items_v1/gu09.png"),
	"GU10": preload("res://assets/ui/generic_items_v1/gu10.png"),
	"GU11": preload("res://assets/ui/generic_items_v1/gu11.png"),
	"GU12": preload("res://assets/ui/generic_items_v1/gu12.png"),
	"GU13": preload("res://assets/ui/generic_items_v1/gu13.png"),
	"GU14": preload("res://assets/ui/generic_items_v1/gu14.png"),
	"GU15": preload("res://assets/ui/generic_items_v1/gu15.png"),
	"GU16": preload("res://assets/ui/generic_items_v1/gu16.png"),
	"GU17": preload("res://assets/ui/generic_items_v1/gu17.png"),
	"GU18": preload("res://assets/ui/generic_items_v1/gu18.png"),
	"GT01": preload("res://assets/ui/generic_items_v1/gt01.png"),
	"GT02": preload("res://assets/ui/generic_items_v1/gt02.png"),
	"GT03": preload("res://assets/ui/generic_items_v1/gt03.png"),
	"GT04": preload("res://assets/ui/generic_items_v1/gt04.png"),
}

var item_id: String = "":
	set(value):
		item_id = value.to_upper()
		queue_redraw()
var rarity: String = "":
	set(value):
		rarity = value
		queue_redraw()

var _ink: Color
var _gold: Color = Color("c6a66c")
var _soft: Color
var _weight: float = 2.6


func _init():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func set_item(id: String, tier: String = ""):
	item_id = id
	rarity = tier
	queue_redraw()


func _notification(what: int):
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw():
	var edge = minf(size.x, size.y)
	if edge <= 0.0:
		return
	draw_set_transform((size - Vector2.ONE * edge) * 0.5, 0.0, Vector2.ONE * edge / 100.0)
	_weight = maxf(2.6, 100.0 / edge)
	var tier = rarity.to_lower()
	if tier.is_empty():
		tier = "gold" if item_id.begins_with("BGT") or item_id.begins_with("GT") or item_id.begins_with("IG") or item_id in ["G01", "G02", "G03", "G04"] else ("purple" if item_id.begins_with("P") or item_id.begins_with("IP") or item_id == "U03" or item_id in ["GU12", "GU13", "GU14", "GU15", "GU16", "GU17", "GU18"] else "blue")
	_ink = Color("e8c67f") if tier in ["gold", "金", "金色"] else (Color("c4a9e8") if tier in ["purple", "紫", "紫色"] else Color("8acdd9"))
	_soft = _ink.darkened(0.64)
	var frame = PackedVector2Array([Vector2(12, 3), Vector2(88, 3), Vector2(97, 12), Vector2(97, 88), Vector2(88, 97), Vector2(12, 97), Vector2(3, 88), Vector2(3, 12)])
	draw_colored_polygon(frame, Color("141b2c"))
	_outline(frame, _ink.darkened(0.5), maxf(1.1, _weight * 0.5))
	draw_line(Vector2(19, 91), Vector2(81, 91), _soft, _weight * 0.5, true)
	_diamond(Vector2(50, 91), Vector2(3.2, 2.2), _ink, true)
	if PAINTED.has(item_id):
		var image_rect=Rect2(5,2,90,88)
		if item_id.begins_with("I"):
			var native_size=Vector2(PAINTED[item_id].get_size())
			var fitted=native_size*minf(image_rect.size.x/native_size.x,image_rect.size.y/native_size.y)
			image_rect=Rect2(image_rect.position+(image_rect.size-fitted)*.5,fitted)
		draw_texture_rect(PAINTED[item_id],image_rect,false)
		return
	match item_id:
		"BGT15", "BGT30", "BGT45", "BGT60":
			_ring(Vector2(50,47),27,_gold)
			_diamond(Vector2(50,47),Vector2(18,23),_ink,true)
			var count={"BGT15":1,"BGT30":2,"BGT45":3,"BGT60":4}[item_id]
			for index in count:
				_diamond(Vector2(50+(index-(count-1)*0.5)*12,80),Vector2(3,4),_gold,true)
			_line([Vector2(35,26),Vector2(40,18),Vector2(50,25),Vector2(60,18),Vector2(65,26)],_gold)
		"B01":
			_ring(Vector2(50, 59), 21, _ink)
			_flame(Vector2(50, 35), 16, _gold)
			_line([Vector2(29, 58), Vector2(22, 52), Vector2(29, 46)], _soft)
			_line([Vector2(71, 58), Vector2(78, 52), Vector2(71, 46)], _soft)
		"B02":
			_book(_ink)
			_flame(Vector2(50, 41), 12, _gold)
			_line([Vector2(30, 57), Vector2(42, 62)], _soft)
			_line([Vector2(58, 62), Vector2(70, 57)], _soft)
		"B03":
			_ring(Vector2(50, 50), 28, _soft)
			_star(Vector2(50, 50), 24, 8, _ink)
			_diamond(Vector2(50, 50), Vector2(5, 8), _gold, true)
			_line([Vector2(72, 20), Vector2(62, 33)], _gold)
		"B04":
			_line([Vector2(37, 29), Vector2(42, 20), Vector2(58, 20), Vector2(63, 29)], _gold)
			_outline(PackedVector2Array([Vector2(30, 34), Vector2(70, 34), Vector2(64, 72), Vector2(36, 72)]), _ink)
			_line([Vector2(29, 30), Vector2(71, 30)], _gold)
			_line([Vector2(38, 78), Vector2(62, 78)], _gold)
			_flame(Vector2(50, 53), 13, _ink)
		"B05":
			_feather(_ink)
			_arc(Vector2(52, 62), 27, -0.6, 1.1, _gold)
			_line([Vector2(34, 73), Vector2(24, 78)], _gold)
		"B06":
			_ring(Vector2(50, 50), 27, _ink)
			_ring(Vector2(50, 50), 20, _soft)
			_diamond(Vector2(50, 50), Vector2(16, 23), _gold)
			for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
				var point = Vector2(50, 50) + Vector2.from_angle(angle) * 30
				_diamond(point, Vector2(3, 3), _ink, true)
		"B07":
			_arc(Vector2(50, 50), 26, -1.2, 1.15, _ink)
			_arc(Vector2(50, 50), 26, 1.9, 4.05, _ink)
			_line([Vector2(48, 20), Vector2(42, 40), Vector2(56, 51), Vector2(43, 76)], _gold)
			_diamond(Vector2(50, 50), Vector2(10, 15), _ink)
		"B08":
			_diamond(Vector2(50, 50), Vector2(16, 30), _ink)
			_line([Vector2(50, 20), Vector2(50, 80)], _soft)
			_line([Vector2(16, 50), Vector2(37, 50)], _gold)
			_line([Vector2(63, 50), Vector2(85, 50)], _gold)
			_line([Vector2(64, 44), Vector2(81, 34)], _ink)
			_line([Vector2(64, 56), Vector2(81, 66)], _ink)
		"B09":
			_outline(PackedVector2Array([Vector2(27, 23), Vector2(72, 31), Vector2(64, 73), Vector2(19, 65)]), _ink)
			_line([Vector2(34, 29), Vector2(27, 61)], _soft)
			_arc(Vector2(48, 43), 13, 0.0, 4.7, _gold)
			_line([Vector2(48, 56), Vector2(81, 56)], _gold)
			_line([Vector2(64, 67), Vector2(82, 67)], _ink)
		"B10":
			_outline(PackedVector2Array([Vector2(39, 20), Vector2(63, 20), Vector2(74, 31), Vector2(67, 72), Vector2(50, 81), Vector2(32, 72), Vector2(27, 31)]), _ink)
			_ring(Vector2(51, 29), 3, _gold)
			_shield(Vector2(50, 55), 17, _gold)
			_line([Vector2(50, 45), Vector2(50, 61)], _ink)
			_line([Vector2(43, 53), Vector2(57, 53)], _ink)
		"P01":
			_diamond(Vector2(50, 51), Vector2(24, 33), _ink)
			_line([Vector2(26, 51), Vector2(50, 36), Vector2(74, 51)], _soft)
			_line([Vector2(50, 18), Vector2(50, 36), Vector2(50, 84)], _soft)
			_flame(Vector2(50, 54), 12, _gold)
		"P02":
			_outline(PackedVector2Array([Vector2(31, 29), Vector2(69, 29), Vector2(76, 67), Vector2(24, 67)]), _ink)
			_flame(Vector2(50, 47), 15, _gold)
			_line([Vector2(22, 75), Vector2(78, 75)], _gold)
			_line([Vector2(30, 81), Vector2(70, 81)], _soft)
		"P03":
			_ring(Vector2(39, 49), 22, _ink)
			_ring(Vector2(61, 49), 22, _gold)
			_diamond(Vector2(50, 49), Vector2(7, 17), _ink, true)
			_line([Vector2(23, 76), Vector2(39, 69)], _soft)
			_line([Vector2(61, 69), Vector2(77, 76)], _soft)
		"P04":
			_book(_ink)
			for x in [34.0, 50.0, 66.0]:
				draw_circle(Vector2(x, 40), 3.3, _gold, true, -1.0, true)
			_line([Vector2(29, 55), Vector2(69, 55), Vector2(62, 48)], _gold)
			_line([Vector2(69, 55), Vector2(62, 62)], _gold)
		"P05":
			_arc(Vector2(50, 61), 27, 0.1, PI - 0.1, _ink)
			_line([Vector2(22, 64), Vector2(78, 64)], _gold)
			_line([Vector2(50, 65), Vector2(50, 33)], _ink)
			_arc(Vector2(38, 45), 12, PI, TAU, _ink)
			_arc(Vector2(62, 45), 12, PI, TAU, _ink)
			_diamond(Vector2(50, 23), Vector2(7, 11), _gold, true)
		"G01":
			_crown(_ink)
			_flame(Vector2(50, 58), 16, _gold)
			_line([Vector2(32, 79), Vector2(68, 79)], _soft)
		"G02":
			_ring(Vector2(50, 52), 20, _ink)
			_flame(Vector2(50, 48), 14, _ink)
			_line([Vector2(29, 51), Vector2(17, 33), Vector2(14, 57), Vector2(28, 68)], _gold)
			_line([Vector2(71, 51), Vector2(83, 33), Vector2(86, 57), Vector2(72, 68)], _gold)
			_diamond(Vector2(50, 22), Vector2(7, 8), _ink, true)
		"G03":
			_ring(Vector2(50, 52), 23, _ink)
			_flame(Vector2(50, 52), 15, _gold)
			for index in 8:
				var direction = Vector2.from_angle(index * TAU / 8.0)
				draw_line(Vector2(50, 52) + direction * 28, Vector2(50, 52) + direction * 36, _ink, _weight, true)
		"U01":
			_diamond(Vector2(50, 50), Vector2(29, 33), _soft)
			var heart = PackedVector2Array([Vector2(50, 70), Vector2(28, 48), Vector2(28, 36), Vector2(37, 29), Vector2(50, 38), Vector2(63, 29), Vector2(72, 36), Vector2(72, 48)])
			_outline(heart, _gold)
			_line([Vector2(36, 51), Vector2(43, 51), Vector2(48, 44), Vector2(54, 58), Vector2(59, 51), Vector2(66, 51)], _ink)
		"U02":
			_shield(Vector2(50, 49), 30, _ink)
			_diamond(Vector2(50, 48), Vector2(14, 23), _gold)
			_line([Vector2(50, 25), Vector2(50, 71)], _soft)
		"U03":
			_diamond(Vector2(50, 52), Vector2(25, 31), _ink)
			_line([Vector2(50, 82), Vector2(37, 45), Vector2(50, 21), Vector2(63, 45), Vector2(50, 82)], _soft)
			_line([Vector2(23, 64), Vector2(23, 41), Vector2(17, 48)], _gold)
			_line([Vector2(23, 41), Vector2(29, 48)], _gold)
			_line([Vector2(77, 64), Vector2(77, 41), Vector2(71, 48)], _gold)
			_line([Vector2(77, 41), Vector2(83, 48)], _gold)
		_:
			_diamond(Vector2(50, 50), Vector2(20, 29), _soft)


func _book(color: Color):
	_outline(PackedVector2Array([Vector2(20, 29), Vector2(36, 25), Vector2(50, 32), Vector2(64, 25), Vector2(80, 29), Vector2(80, 72), Vector2(64, 68), Vector2(50, 75), Vector2(36, 68), Vector2(20, 72)]), color)
	draw_line(Vector2(50, 33), Vector2(50, 74), _soft, _weight, true)


func _flame(center: Vector2, radius: float, color: Color):
	var points = PackedVector2Array([center + Vector2(-radius * 0.7, radius * 0.6), center + Vector2(-radius * 0.9, 0), center + Vector2(-radius * 0.35, -radius * 0.65), center + Vector2(-radius * 0.18, -radius * 0.05), center + Vector2(radius * 0.35, -radius * 1.2), center + Vector2(radius * 0.9, -radius * 0.1), center + Vector2(radius * 0.65, radius * 0.65), center + Vector2(0, radius)])
	_outline(points, color)


func _feather(color: Color):
	_outline(PackedVector2Array([Vector2(31, 67), Vector2(30, 50), Vector2(41, 31), Vector2(69, 18), Vector2(72, 45), Vector2(58, 62), Vector2(41, 67)]), color)
	_line([Vector2(25, 78), Vector2(64, 29)], _gold)
	_line([Vector2(34, 64), Vector2(34, 47)], _soft)
	_line([Vector2(43, 53), Vector2(60, 52)], _soft)
	_line([Vector2(49, 45), Vector2(49, 31)], _soft)


func _crown(color: Color):
	_outline(PackedVector2Array([Vector2(25, 48), Vector2(19, 23), Vector2(37, 36), Vector2(50, 16), Vector2(63, 36), Vector2(81, 23), Vector2(75, 48)]), color)
	_line([Vector2(25, 53), Vector2(75, 53)], color)
	_diamond(Vector2(50, 38), Vector2(4, 6), _gold, true)


func _shield(center: Vector2, radius: float, color: Color):
	_outline(PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius * 0.8, -radius * 0.6), center + Vector2(radius * 0.65, radius * 0.5), center + Vector2(0, radius), center + Vector2(-radius * 0.65, radius * 0.5), center + Vector2(-radius * 0.8, -radius * 0.6)]), color)


func _diamond(center: Vector2, half: Vector2, color: Color, filled: bool = false):
	var points = PackedVector2Array([center + Vector2(0, -half.y), center + Vector2(half.x, 0), center + Vector2(0, half.y), center + Vector2(-half.x, 0)])
	if filled:
		draw_colored_polygon(points, color)
	else:
		_outline(points, color)


func _star(center: Vector2, radius: float, inner: float, color: Color):
	var points = PackedVector2Array()
	for index in 10:
		points.append(center + Vector2.from_angle(-PI * 0.5 + index * PI / 5.0) * (radius if index % 2 == 0 else inner))
	_outline(points, color)


func _ring(center: Vector2, radius: float, color: Color):
	draw_arc(center, radius, 0, TAU, 40, color, _weight, true)


func _arc(center: Vector2, radius: float, start: float, end: float, color: Color):
	draw_arc(center, radius, start, end, 24, color, _weight, true)


func _line(points: Array, color: Color):
	draw_polyline(PackedVector2Array(points), color, _weight, true)


func _outline(points: PackedVector2Array, color: Color, width: float = -1.0):
	var closed = points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, color, _weight if width < 0.0 else width, true)
