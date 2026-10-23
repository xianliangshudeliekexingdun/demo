extends SceneTree
## Executes the actual icon drawing source with every CanvasItem primitive replaced
## by a recorder. Detached Controls never draw a frame or enter a scene/viewport.
## This checks authored geometry, not pixel appearance, readability or performance.
const ICON_SOURCE = "res://scripts/ui/arcane_icon.gd"
const OUTPUT = "res://build/qa/new-schools-visuals-20261022/icons"
const SIZES = [32,44,64,96]
const PRIMITIVES = ["draw_colored_polygon","draw_polyline","draw_circle","draw_arc","draw_texture_rect"]
var checks: int = 0
var failures: Array = []
var samples: Array = []
var polygon_count: int = 0
var primitive_count: int = 0

const RECORDERS = """
var _captured: Array = []
func _capture_draw_colored_polygon(points: PackedVector2Array, color: Color):
	_captured.append({"kind":"polygon","points":points,"color":color})
func _capture_draw_polyline(points: PackedVector2Array, color: Color, width: float = -1.0, antialiased: bool = false):
	_captured.append({"kind":"polyline","points":points,"color":color,"width":width,"antialiased":antialiased})
func _capture_draw_circle(center: Vector2, radius: float, color: Color):
	_captured.append({"kind":"circle","center":center,"radius":radius,"color":color})
func _capture_draw_arc(center: Vector2, radius: float, start: float, end: float, count: int, color: Color, width: float = -1.0, antialiased: bool = false):
	_captured.append({"kind":"arc","center":center,"radius":radius,"start":start,"end":end,"count":count,"color":color,"width":width,"antialiased":antialiased})
func _capture_draw_texture_rect(_texture: Texture2D, rect: Rect2, _tile: bool):
	_captured.append({"kind":"texture","rect":rect})
"""

func _initialize():
	call_deferred("execute")

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures.append(label)
		push_error("New school icon geometry: " + label)

func finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)

func command_bounds(command: Dictionary) -> Rect2:
	var points = PackedVector2Array()
	var grow: float = .0
	var finite: bool = true
	var kind: String = str(command.kind)
	if kind in ["polygon","polyline"]:
		points = command.points
		if kind == "polyline":
			grow = maxf(float(command.width),1.0)*.5
			finite = is_finite(float(command.width)) and float(command.width)>0.0
	elif kind == "circle":
		var center: Vector2 = command.center
		var radius: float = command.radius
		finite = finite_vector(center) and is_finite(radius) and radius>0.0
		points.append(center-Vector2.ONE*radius)
		points.append(center+Vector2.ONE*radius)
	elif kind == "arc":
		var center: Vector2 = command.center
		var radius: float = command.radius
		var start: float = command.start
		var end: float = command.end
		finite = finite_vector(center) and is_finite(radius) and radius>0.0 and is_finite(start) and is_finite(end) and end>=start and int(command.count)>=2
		grow = maxf(float(command.width),1.0)*.5
		finite = finite and is_finite(float(command.width)) and float(command.width)>0.0
		points.append(center+Vector2.from_angle(start)*radius)
		points.append(center+Vector2.from_angle(end)*radius)
		# Exact extrema of the continuous arc include every cardinal angle in its range.
		for i in range(int(floor(start/(PI*.5)))-1,int(ceil(end/(PI*.5)))+2):
			var angle: float = float(i)*PI*.5
			if angle>=start and angle<=end: points.append(center+Vector2.from_angle(angle)*radius)
	else:
		finite = false
	if command.has("color"):
		var color: Color = command.color
		finite = finite and is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and is_finite(color.a)
	for point in points: finite = finite and finite_vector(point)
	check(finite and not points.is_empty(),"finite arguments for "+kind)
	if not finite or points.is_empty(): return Rect2(-1000,-1000,2000,2000)
	var bounds = Rect2(points[0],Vector2.ZERO)
	for point in points: bounds = bounds.expand(point)
	return bounds.grow(grow)

func inspect_commands(commands: Array, label: String, side: int) -> Dictionary:
	check(not commands.is_empty(),label+" records geometry")
	var union_bounds: Rect2
	var first: bool = true
	var kinds: Dictionary = {}
	for command in commands:
		primitive_count += 1
		kinds[str(command.kind)] = int(kinds.get(str(command.kind),0))+1
		check(str(command.kind)!="texture",label+" authored geometry uses no raster fallback")
		var bounds: Rect2 = command_bounds(command)
		check(bounds.position.x>=-.0001 and bounds.position.y>=-.0001 and bounds.end.x<=float(side)+.0001 and bounds.end.y<=float(side)+.0001,label+" command remains inside control including keyline: "+str(bounds))
		union_bounds = bounds if first else union_bounds.merge(bounds)
		first = false
		if str(command.kind)=="polygon":
			polygon_count += 1
			var vertices: PackedVector2Array = command.points
			var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(vertices)
			check(vertices.size()>=3 and not triangles.is_empty() and triangles.size()%3==0,label+" polygon triangulates: "+str(vertices))
	var geometry: Array = commands.duplicate(true)
	for command in geometry: command.erase("color")
	return {"commands":commands.size(),"kinds":kinds,"geometry_sha256":str(geometry).sha256_text(),"bounds":{"x":union_bounds.position.x,"y":union_bounds.position.y,"width":union_bounds.size.x,"height":union_bounds.size.y}}

func execute():
	var original_source: String = FileAccess.get_file_as_string(ICON_SOURCE)
	check(not original_source.is_empty(),"production source exists")
	var intercepted: String = original_source
	for primitive in PRIMITIVES:
		intercepted = intercepted.replace(str(primitive)+"(","_capture_"+str(primitive)+"(")
	# No production drawing call can escape the recorder into the renderer.
	var drawing = RegEx.new()
	drawing.compile("(?<![A-Za-z0-9_])draw_[A-Za-z0-9_]+\\s*\\(")
	check(drawing.search(intercepted)==null,"all CanvasItem draw primitives intercepted")
	var script = GDScript.new()
	script.source_code = intercepted+RECORDERS
	var error: Error = script.reload()
	check(error==OK,"intercepted production script parses")
	if error!=OK:
		finish()
		return
	var icon = script.new()
	var ids: Array = icon.PROCEDURAL_SPELLS.duplicate()
	ids.append_array(icon.PROCEDURAL_CATALYSTS)
	check(ids.size()==44,"forty spells and four catalyst identities")
	for side in SIZES:
		var fingerprints: Dictionary = {}
		for id in ids:
			icon.size = Vector2.ONE*float(side)
			icon.spell_id = str(id)
			# Shared tint means uniqueness cannot be satisfied by a color change alone.
			icon.tint = Color("d8c6f6")
			icon._captured.clear()
			icon._draw()
			var commands: Array = icon._captured.duplicate(true)
			var label: String = str(id)+" @ "+str(side)
			var result: Dictionary = inspect_commands(commands,label,int(side))
			check(not fingerprints.has(result.geometry_sha256),label+" has distinct authored geometry from "+str(fingerprints.get(result.geometry_sha256,"")))
			fingerprints[result.geometry_sha256] = str(id)
			check(icon.spell_id==str(id) and icon.size==Vector2.ONE*float(side) and icon.tint==Color("d8c6f6"),label+" draw leaves input properties untouched")
			icon._captured.clear()
			icon._draw()
			check(icon._captured==commands,label+" repeated draw is deterministic")
			result["id"] = str(id)
			result["side"] = int(side)
			samples.append(result)
		check(fingerprints.size()==44,str(side)+" all forty-four geometry fingerprints distinct")
	icon.free()
	finish()

func finish():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var output = FileAccess.open(OUTPUT+"/results.json",FileAccess.WRITE)
	check(output!=null,"QA result opens")
	var result: Dictionary = {"version":"new-school-icon-geometry-20261022","checks":checks,"failed":failures.size(),"failures":failures,"sample_count":samples.size(),"primitive_count":primitive_count,"polygon_count":polygon_count,"sizes":SIZES,"samples":samples,"source_sha256":{ICON_SOURCE:FileAccess.get_sha256(ICON_SOURCE),"res://tests/new_school_icon_geometry_tests.gd":FileAccess.get_sha256("res://tests/new_school_icon_geometry_tests.gd")},"geometry_repairs":["R04 pedestal arc moved/resized to remain inside the card at 64/96px.","R07 resonance base arc moved/resized to remain inside all four tested sizes.","S02 summoning base arc moved/resized to include its dark keyline inside all four sizes. No polygon triangulation failures occurred."],"scope":"Actual production Control source with every draw primitive replaced by a geometry recorder. Checks finite values, continuous bounds including dark keylines, native polygon triangulation, geometric identity and deterministic drawing for forty spells/four catalysts at four sizes. Detached nodes, no rendered frame, screenshot, pixel readability, gameplay, natural route, performance or export evidence."}
	if output!=null: output.store_string(JSON.stringify(result,"  "))
	print("NEW SCHOOL ICON GEOMETRY checks=%d failures=%d samples=%d primitives=%d polygons=%d"%[checks,failures.size(),samples.size(),primitive_count,polygon_count])
	quit(0 if failures.is_empty() else 1)
