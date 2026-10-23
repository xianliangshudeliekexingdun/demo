extends Node3D
## Ten-core feedback, one bounded batch. Snapshot clocks/events are authoritative.
## No timers, RNG, damage, status callbacks or changes to a supplied dictionary.
const LINE_LIMIT = 768
const HANDLED_EFFECTS = ["gem_inferno", "gem_coffin", "gem_lightning", "gem_earth", "gem_spirit", "gem_wind", "gem_fracture", "gem_echo"]
const Icon = preload("res://scripts/ui/gem_icon.gd")
var _lines: MultiMeshInstance3D
var _count: int = 0
var _budget: int = LINE_LIMIT
var _clock: float = 0.0
var _reduced: bool = false
var _camera: Camera3D
var _coverage: Dictionary = {}
var _footprints: Array = []
var _revision: int = -1
var _tint: Color = Color.WHITE
var _rules: Dictionary = {}

func _ready() -> void:
	name="GemCoreVFX"
	_rules=JSON.parse_string(FileAccess.get_file_as_string("res://data/magic_gems_v1.json"))
	set_meta("source","original_procedural_ten_core_snapshot_only")
	var material=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo=true
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority=-6
	var mesh=BoxMesh.new()
	mesh.size=Vector3.ONE
	var batch=MultiMesh.new()
	batch.transform_format=MultiMesh.TRANSFORM_3D
	batch.use_colors=true
	batch.mesh=mesh
	batch.instance_count=LINE_LIMIT
	batch.visible_instance_count=0
	batch.custom_aabb=AABB(Vector3(-60,-1,-60),Vector3(120,24,120))
	_lines=MultiMeshInstance3D.new()
	_lines.multimesh=batch
	_lines.material_override=material
	_lines.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)
	set_process(false)

static func handles_effect(kind: String) -> bool:
	return kind in HANDLED_EFFECTS

func sync_snapshot(snapshot: Dictionary,camera: Camera3D,options: Dictionary={}) -> void:
	if not is_instance_valid(_lines):return
	_camera=camera
	_reduced=bool(options.get("reduced_motion",false))
	_revision=int(snapshot.get("room_revision",-1))
	var gems: Dictionary=snapshot.get("gems",{})
	_clock=float(gems.get("clock",snapshot.get("combat_time",0.0)))
	_count=0
	_coverage.clear()
	_footprints.clear()
	if str(snapshot.get("phase",""))=="combat":
		_budget=LINE_LIMIT-256 if _has_gem_effect(snapshot) else LINE_LIMIT
		_persistent(snapshot,gems)
		_budget=LINE_LIMIT
		for effect in snapshot.get("effects",[]): _effect(effect)
	_lines.multimesh.visible_instance_count=_count
	visible=_count>0

func get_debug_state() -> Dictionary:
	return {"line_count":_count,"line_limit":LINE_LIMIT,"material_count":1,"batch_count":1,"clock":_clock,"revision":_revision,"coverage":_coverage.duplicate(true),"footprints":_footprints.duplicate(true)}

func _has_gem_effect(snapshot: Dictionary) -> bool:
	for effect in snapshot.get("effects",[]):
		if handles_effect(str(effect.get("kind",""))) and float(effect.get("life",0))>0:return true
	return false

func _persistent(snapshot: Dictionary,gems: Dictionary) -> void:
	var core: String=str(gems.get("core",""))
	var school: Dictionary=gems.get("schools",{})
	var player: Dictionary=snapshot.get("player",{})
	var pos: Vector2=player.get("pos",Vector2.ZERO)
	var actor_positions: Dictionary={}
	for actor in snapshot.get("actors",[]):
		if float(actor.get("health",0))>0:actor_positions[int(actor.id)]=actor.pos
	_tint=Icon.tint_for(core)
	match core:
		"inferno":
			var required: int=int(_rules.cores.inferno.ticks_required)
			for actor_id in gems.get("embers",{}):
				var entry: Dictionary=gems.embers[actor_id]
				if float(entry.get("amount",0))<=0:continue
				var at: Vector2=actor_positions.get(int(actor_id),entry.get("pos",Vector2.ZERO))
				for index in required:
					_glyph(at+Vector2((index-(required-1)*.5)*.13,0),.045,1.32,.82 if index<int(entry.get("ticks",0)) else .18)
				_note("inferno_stock")
		"coffin":
			for actor_id in gems.get("coffin_reserves",{}):
				var entry: Dictionary=gems.coffin_reserves[actor_id]
				if float(entry.get("amount",0))<=0:continue
				var at: Vector2=actor_positions.get(int(actor_id),entry.get("pos",Vector2.ZERO))
				var fraction: float=clampf(float(entry.amount)/maxf(1,float(entry.get("cap",1))),0,1)
				_glyph(at,.24,1.25,.50)
				_line(_point(at,.83),_point(at,.83+.75*fraction),.04,Color(_tint,.75))
				_note("coffin_stock")
		"lightning":
			var charges: int=int(school.get("lightning_charges",0))
			var required: int=int(_rules.cores.lightning.charge_count)
			if charges>0:
				for index in required:
					var offset: Vector2=Vector2.from_angle(-PI*.5+index*TAU/required)*.60
					_glyph(pos+offset,.08,.26,.82 if index<charges else .16)
				if charges>=required:_ring(pos,.68,.21,.50,0,TAU)
				_note("lightning_charge")
		"wind":
			var layers: int=int(school.get("wind_layers",0))
			var face: Vector2=player.get("face",Vector2.UP)
			if face.length_squared()<.001:face=Vector2.UP
			for index in layers:
				var back: Vector2=pos-face.normalized()*(.30+index*.17)
				var side: Vector2=face.normalized().orthogonal()*(.25+index*.06)
				_line(_point(back-side,.22),_point(back-face*.18,.22),.025,Color(_tint,.42))
				_line(_point(back-face*.18,.22),_point(back+side,.22),.025,Color(_tint,.42))
			if layers>0:_note("wind_layers")
		"earth":
			if int(school.get("earth_anchor_id",-1))>=0:
				var anchor: Vector2=school.get("earth_anchor_pos",pos)
				var progress: float=clampf(float(school.get("earth_progress",0)),0,1)
				_ring(anchor,.44,.13,.45,0,TAU)
				_ring(anchor,.51,.13,.75,-PI*.5,-PI*.5+TAU*progress)
				if bool(school.get("earth_mature",false)):
					for index in 4:_glyph(anchor+Vector2.from_angle(index*PI*.5)*.47,.065,.25,.75)
				_line(_point(pos,.13),_point(anchor,.13),.016,Color(_tint,.18))
				_note("earth_anchor")
		"spirit":
			var points: int=int(school.get("spirit_points",0))
			for index in points:_glyph(pos+Vector2((index-1)*.21,0),.09,1.62,.65)
			if points>=int(_rules.cores.spirit.charge_count):_ring(pos,.48,.12,.30,0,TAU)
			if points>0:_note("spirit_points")
		"fracture":
			_glyph(pos+Vector2(-.35,0),.10,1.20,.36)
			_note("fracture_active")
		"echo":
			_glyph(pos+Vector2(-.30,0),.09,1.15,.34)
			_glyph(pos+Vector2(-.43,0),.09,1.25,.20)
			_note("echo_active")
		"sacrifice":
			var missing: float=1-clampf(float(player.get("health",0))/maxf(1,float(player.get("max_health",1))),0,1)
			if missing>0:
				_ring(pos,.39,.12,.23,-PI*.5,-PI*.5+TAU*missing)
				_glyph(pos+Vector2(.32,0),.09,.68,.45)
				_note("sacrifice_missing_health")
		"aegis":
			var shield: float=clampf(float(player.get("shield",0))/maxf(1,float(player.get("max_shield",1))),0,1)
			if shield>0:
				_ring(pos,.48,.14,.32,-PI*.5,-PI*.5+TAU*shield)
				_glyph(pos+Vector2(.34,0),.11,.65,.40)
				_note("aegis_real_shield")

func _effect(effect: Dictionary) -> void:
	var kind: String=str(effect.get("kind",""))
	if not handles_effect(kind):return
	var alpha: float=clampf(float(effect.get("life",0))/maxf(.001,float(effect.get("max_life",1))),0,1)
	if alpha<=0:return
	var progress: float=1-alpha
	var pos: Vector2=effect.get("pos",Vector2.ZERO)
	var radius: float=maxf(.05,float(effect.get("radius",.5)))
	match kind:
		"gem_inferno":
			_tint=Icon.tint_for("inferno")
			var extent: float=radius if _reduced else radius*(.32+.68*progress)
			_ring(pos,extent,.19,alpha*.65,0,TAU)
			for index in (4 if _reduced else 6):
				var offset: Vector2=Vector2.from_angle(index*TAU/(4 if _reduced else 6))*extent*.55
				_glyph(pos+offset,.12,.50 if _reduced else .45+progress*.25,alpha*.65)
		"gem_coffin":
			_tint=Icon.tint_for("coffin")
			var reason: String=str(effect.get("reason","natural"))
			var height: float=.40 if reason=="consume" else .80
			for index in (4 if _reduced else 6):
				var offset: Vector2=Vector2.from_angle(index*TAU/(4 if _reduced else 6))*radius*(.70 if _reduced else .25+progress*.45)
				_glyph(pos+offset,.13,height,alpha*.62)
			_ring(pos,radius*.75,.15,alpha*.38,0,TAU)
		"gem_lightning":
			_tint=Icon.tint_for("lightning")
			for target in effect.get("targets",[]):
				var at: Vector2=target.get("pos",pos)
				if str(effect.get("phase","impact"))=="preview":
					_ring(at,radius,.13,alpha*.48,0,TAU)
					_glyph(at,.13,.32,alpha*.60)
				else:
					_line(_point(at,2.0),_point(at+Vector2(.12,0),1.05),.05,Color(_tint,alpha*.8))
					_line(_point(at+Vector2(.12,0),1.05),_point(at,.24),.065,Color(_tint,alpha*.8))
					_ring(at,.34,.15,alpha*.6,0,TAU)
		"gem_earth":
			_tint=Icon.tint_for("earth")
			_ring(pos,radius if _reduced else radius*(.45+progress*.55),.15,alpha*.56,0,TAU)
			for index in 4:_glyph(pos+Vector2.from_angle(index*PI*.5)*radius*.56,.11,.20,alpha*.55)
		"gem_spirit":
			_tint=Icon.tint_for("spirit")
			for target in effect.get("targets",[]):
				var at: Vector2=target.get("pos",pos)
				_line(_point(pos,.70),_point(at,.70),.023,Color(_tint,alpha*.55))
				_glyph(at,.17,1.10,alpha*.72)
		"gem_wind":
			_tint=Icon.tint_for("wind")
			_ring(pos,.46,.14,alpha*.25,PI*.10,PI*.90)
		"gem_fracture":
			_tint=Icon.tint_for("fracture")
			var from: Vector2=effect.get("from",pos)
			var to: Vector2=effect.get("to",pos)
			_line(_point(from,.66),_point(to,.66),.025,Color(_tint,alpha*.58))
			_glyph(to,.15,1.10,alpha*.8)
		"gem_echo":
			_tint=Icon.tint_for("echo")
			_echo_shape(effect,alpha*.48)
	_note(kind)
	_footprints.append({"kind":kind,"pos":pos,"radius":radius})

func _echo_shape(effect: Dictionary,alpha: float) -> void:
	var shape: String=str(effect.get("kind_shape","circle"))
	var pos: Vector2=effect.get("pos",Vector2.ZERO)
	if shape=="segment":
		_segment(effect,alpha)
	elif shape=="segments":
		for piece in effect.get("segments",[]):_segment(piece,alpha)
	elif shape=="cone":
		var direction: Vector2=effect.get("direction",Vector2.UP)
		var half: float=deg_to_rad(float(effect.get("angle_degrees",0))*.5)
		var radius: float=float(effect.get("radius",0))
		var angle: float=direction.angle()
		_ring(pos,radius,.16,alpha,angle-half,angle+half)
		for side in [-1,1]:_line(_point(pos,.16),_point(pos+direction.rotated(half*side)*radius,.16),.025,Color(_tint,alpha))
	else:_ring(pos,float(effect.get("radius",.3)),.16,alpha,0,TAU)

func _segment(piece: Dictionary,alpha: float) -> void:
	var from: Vector2=piece.get("from",Vector2.ZERO)
	var to: Vector2=piece.get("to",from)
	var direction: Vector2=(to-from).normalized()
	var side: Vector2=direction.orthogonal()*float(piece.get("width",.05))
	for sign_value in [-1,1]:_line(_point(from+side*sign_value,.16),_point(to+side*sign_value,.16),.022,Color(_tint,alpha))

func _ring(pos: Vector2,radius: float,height: float,alpha: float,start: float,end: float) -> void:
	if radius<=0 or end-start<.001:return
	var segments: int=clampi(ceili(absf(end-start)*(3 if _reduced else 5)),2,32)
	for index in segments:
		var a: float=lerpf(start,end,float(index)/segments)
		var b: float=lerpf(start,end,float(index+1)/segments)
		_line(_point(pos+Vector2.from_angle(a)*radius,height),_point(pos+Vector2.from_angle(b)*radius,height),.022,Color(_tint,alpha))

func _glyph(pos: Vector2,radius: float,height: float,alpha: float) -> void:
	var center: Vector3=_point(pos,height)
	var right: Vector3=(_camera.global_basis.x.normalized() if _camera!=null else Vector3.RIGHT)*radius
	var up: Vector3=Vector3.UP*radius*1.5
	var points: Array=[center-up,center+right,center+up,center-right]
	for index in 4:_line(points[index],points[(index+1)%4],.024,Color(_tint,alpha))

func _line(from: Vector3,to: Vector3,width: float,color: Color) -> void:
	if _count>=mini(_budget,LINE_LIMIT) or color.a<=0:return
	var length: float=from.distance_to(to)
	if length<=.0001 or not is_finite(length):return
	var center: Vector3=(from+to)*.5
	if _camera!=null and _camera.is_position_behind(center):return
	var x: Vector3=(to-from).normalized()
	var facing: Vector3=(_camera.global_position-center).normalized() if _camera!=null else Vector3(0,.6,.8)
	var y: Vector3=facing.cross(x).normalized()
	if y.length_squared()<.001:y=Vector3.RIGHT
	var z: Vector3=x.cross(y).normalized()
	_lines.multimesh.set_instance_transform(_count,Transform3D(Basis(x*length,y*width,z*width*.5),center))
	_lines.multimesh.set_instance_color(_count,color)
	_count+=1

func _point(pos: Vector2,height: float) -> Vector3:return Vector3(pos.x,height,-pos.y)
func _note(kind: String) -> void:_coverage[kind]=int(_coverage.get(kind,0))+1
