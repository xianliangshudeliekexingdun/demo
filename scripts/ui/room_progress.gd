extends Control
## Read-only window onto the actual authored room route.
const T = preload("res://scripts/ui/atelier_theme.gd")
var steps: Array = []
var _encounters: Dictionary = {}
var _signature := ""

func _ready():
	size = Vector2(350, 44)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var source = JSON.parse_string(FileAccess.get_file_as_string("res://data/courtyard_route.json"))
	if source is Dictionary:_encounters = source.get("encounters_by_room", {})
	for i in range(3):
		var step = Control.new()
		step.position = Vector2(i * 124, 0)
		step.size = Vector2(102, 40)
		step.mouse_filter = Control.MOUSE_FILTER_IGNORE
		step.set_meta("state", "pending")
		add_child(step)
		var marker = T.label(step, "", Rect2(0, 6, 24, 24), 13)
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		T.label(step, "", Rect2(34, 2, 66, 32), 19)
		steps.append(step)

func refresh(snapshot: Dictionary):
	var current_room = int(snapshot.get("room_index", 1))
	var total = int(snapshot.get("room_total", 1))
	var complete = str(snapshot.phase) == "complete"
	var preview: Array = snapshot.get("room_progress", [])
	var signature = "%d/%d/%s/%s" % [current_room, total, complete, str(preview)]
	if signature == _signature:return
	_signature = signature
	# Look ahead two rooms; near the end retain the last three actual rooms.
	var start = mini(current_room, maxi(1, total - 2))
	var kinds = {"normal":"战斗", "combat":"战斗", "elite":"精英", "elite_guard":"精英", "shop":"商店", "tavern":"酒馆", "boss":"首领"}
	var descriptions: Array[String] = []
	for i in range(steps.size()):
		var room_id = int(preview[i].room_id) if i < preview.size() else start + i
		steps[i].visible = i < preview.size() if not preview.is_empty() else room_id <= total
		if not steps[i].visible:continue
		var is_shop = bool(preview[i].get("is_shop", false)) if i < preview.size() else false
		var kind = str(preview[i].kind) if i < preview.size() else str(_encounters.get(str(room_id), {}).get("kind", "unknown"))
		# Current kind is also supplied by the real snapshot; future labels use data.
		if preview.is_empty() and room_id == current_room:kind = str(snapshot.get("encounter_kind", kind))
		var done = complete or (str(preview[i].state) == "done" if i < preview.size() else room_id < current_room)
		var current = (str(preview[i].state) == "current" if i < preview.size() else room_id == current_room) and not complete
		steps[i].set_meta("room_id", room_id)
		steps[i].set_meta("room_kind", kind)
		steps[i].set_meta("state", "done" if done else "current" if current else "pending")
		var color = T.CYAN if current else T.GOLD if done else T.MUTED
		steps[i].get_child(0).text = "店" if is_shop else str(room_id)
		steps[i].get_child(1).text = str(kinds.get(kind,"未知"))
		for label in steps[i].get_children(): label.add_theme_color_override("font_color", color)
		descriptions.append(("第 %d 房后 · 商店" % room_id if is_shop else "第 %d 房 · %s" % [room_id, kinds.get(kind,"未知")]) + (" · 当前" if current else " · 已通过" if done else ""))
	tooltip_text = "\n".join(descriptions)
	queue_redraw()

func _draw():
	for i in range(3):
		if i >= steps.size() or not steps[i].visible:continue
		var done = steps[i].get_meta("state", "pending") == "done"
		var current = steps[i].get_meta("state", "pending") == "current"
		var center = Vector2(12+i*124,18)
		var color = T.CYAN if current else T.GOLD if done else T.LINE
		draw_circle(center, 13, Color("172032"))
		draw_arc(center, 13, 0, TAU, 40, color, 2 if current else 1, true)
		if current: draw_line(center+Vector2(21,21),center+Vector2(82,21),color,2,true)
		if i < 2: draw_line(center+Vector2(93,0), center+Vector2(108,0), T.GOLD if done else T.LINE, 1, true)
