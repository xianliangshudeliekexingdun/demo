extends Control
## Original static gem emblems. Geometry is inspectable; no RNG, clocks or gameplay.
const CORE_IDS = ["inferno", "coffin", "lightning", "wind", "earth", "spirit", "fracture", "echo", "sacrifice", "aegis"]
const STAT_IDS = ["attack", "health", "shield", "defense", "crit_rate", "crit_multiplier", "cdr", "speed"]
const CORE_COLORS = {"inferno":Color("f4a06a"), "coffin":Color("b4e6f4"), "lightning":Color("a5bdfb"), "wind":Color("98e0bd"), "earth":Color("dfb979"), "spirit":Color("c6b1f5"), "fracture":Color("d9c4ff"), "echo":Color("a8dadd"), "sacrifice":Color("f198a2"), "aegis":Color("dba1bf")}
const RARITY_COLORS = {"green":Color("91d4ae"), "blue":Color("89c9f2"), "purple":Color("d1abed"), "gold":Color("edd08b"), "legacy":Color("b7c6ce"), "transition":Color("b7c6ce")}
const INK = Color("101827")
var item_id: String = "stat:attack"
var rarity: String = "green"
var tier: int = 1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_gem(gem: Dictionary) -> void:
	rarity = str(gem.get("rarity", "green"))
	if not str(gem.get("core", "")).is_empty():
		item_id = "core:" + str(gem.core)
	else:
		var affixes: Array = gem.get("affixes", [])
		item_id = "stat:" + (str(affixes[0].get("stat", "attack")) if not affixes.is_empty() else "attack")
		tier = int(affixes[0].get("tier", 1)) if not affixes.is_empty() else 1
	queue_redraw()

static func tint_for(id: String, quality: String = "gold") -> Color:
	return CORE_COLORS.get(id.trim_prefix("core:"), RARITY_COLORS.get(quality, Color("b7c6ce")))

static func geometry(id: String) -> Array:
	var result: Array = []
	var key: String = id.trim_prefix("core:").trim_prefix("stat:")
	var core: bool = id.begins_with("core:")
	var body: Array = [Vector2(0,-.88),Vector2(.62,-.30),Vector2(.45,.55),Vector2(0,.86),Vector2(-.45,.55),Vector2(-.62,-.30)]
	match key:
		"inferno": body=[Vector2(-.63,-.56),Vector2(0,-.85),Vector2(.63,-.56),Vector2(.56,.57),Vector2(0,.83),Vector2(-.56,.57)]
		"coffin": body=[Vector2(0,-.89),Vector2(.64,-.46),Vector2(.64,.46),Vector2(0,.89),Vector2(-.64,.46),Vector2(-.64,-.46)]
		"lightning": body=[Vector2(0,-.90),Vector2(.70,0),Vector2(0,.90),Vector2(-.70,0)]
		"wind": body=[Vector2(.26,-.87),Vector2(.70,-.38),Vector2(.22,.48),Vector2(-.36,.84),Vector2(-.65,.32),Vector2(-.40,-.48)]
		"earth": body=[Vector2(-.69,-.57),Vector2(.69,-.57),Vector2(.69,.53),Vector2(.40,.82),Vector2(-.40,.82),Vector2(-.69,.53)]
		"spirit": body=[Vector2(0,-.87),Vector2(.29,-.43),Vector2(.76,-.12),Vector2(.57,.53),Vector2(0,.84),Vector2(-.57,.53),Vector2(-.76,-.12),Vector2(-.29,-.43)]
		"fracture": body=[Vector2(-.18,-.89),Vector2(.63,-.47),Vector2(.79,.12),Vector2(.22,.79),Vector2(-.16,.42),Vector2(-.55,.82),Vector2(-.76,.11),Vector2(-.53,-.45)]
		"echo": body=[Vector2(-.64,-.59),Vector2(-.08,-.85),Vector2(.65,-.48),Vector2(.65,.59),Vector2(.08,.85),Vector2(-.64,.48)]
		"sacrifice": body=[Vector2(0,-.51),Vector2(.40,-.79),Vector2(.73,-.32),Vector2(.52,.31),Vector2(0,.87),Vector2(-.52,.31),Vector2(-.73,-.32),Vector2(-.40,-.79)]
		"aegis": body=[Vector2(0,-.86),Vector2(.72,-.53),Vector2(.59,.37),Vector2(0,.88),Vector2(-.59,.37),Vector2(-.72,-.53)]
	result.append({"kind":"polygon", "points":body, "role":"body"})
	result.append({"kind":"line", "points":[body[-1],body[0],body[1]], "role":"light", "width":1.5})
	if core:
		match key:
			"inferno":
				result.append({"kind":"polygon","points":[Vector2(0,-.48),Vector2(.30,-.02),Vector2(.24,.43),Vector2(-.24,.43),Vector2(-.30,-.02)],"role":"deep"})
				for x in [-.30,-.10,.10,.30]: result.append({"kind":"line","points":[Vector2(x,-.35),Vector2(x*.68,.05),Vector2(x,.46)],"role":"light"})
			"coffin":
				result.append({"kind":"line","points":[Vector2(0,-.65),Vector2(0,.62)],"role":"light"})
				for sign_value in [-1,1]:
					result.append({"kind":"line","points":[Vector2(-.45,-.25*sign_value),Vector2(.45,.25*sign_value)],"role":"light"})
				result.append({"kind":"polygon","points":[Vector2(0,-.29),Vector2(.19,0),Vector2(0,.29),Vector2(-.19,0)],"role":"deep"})
			"lightning":
				result.append({"kind":"line","points":[Vector2(0,-.59),Vector2(.44,0),Vector2(0,.59),Vector2(-.44,0),Vector2(0,-.59)],"role":"light"})
				for p in [Vector2(0,-.59),Vector2(.44,0),Vector2(0,.59),Vector2(-.44,0)]: result.append({"kind":"circle","center":p,"radius":.095,"role":"light"})
				result.append({"kind":"polygon","points":[Vector2(.13,-.36),Vector2(-.20,.08),Vector2(.02,.08),Vector2(-.12,.39),Vector2(.23,-.08),Vector2(0,-.08)],"role":"light"})
			"wind":
				for offset in [-.28,0,.28]: result.append({"kind":"line","points":[Vector2(-.40,offset+.19),Vector2(-.04,offset-.06),Vector2(.38,offset-.12)],"role":"light"})
			"earth":
				result.append({"kind":"line","points":[Vector2(-.48,.43),Vector2(.48,.43)],"role":"light","width":3.0})
				result.append({"kind":"polygon","points":[Vector2(-.33,.26),Vector2(-.33,-.28),Vector2(0,-.53),Vector2(.33,-.28),Vector2(.33,.26)],"role":"deep"})
				result.append({"kind":"line","points":[Vector2(0,-.42),Vector2(0,.28)],"role":"light"})
			"spirit":
				for angle in [-PI/2,PI/6,5*PI/6]:
					var p=Vector2.from_angle(angle)*.40
					result.append({"kind":"circle","center":p,"radius":.19,"role":"deep"})
					result.append({"kind":"line","points":[p,Vector2.ZERO],"role":"light"})
				result.append({"kind":"circle","center":Vector2.ZERO,"radius":.13,"role":"light"})
			"fracture":
				result.append({"kind":"line","points":[Vector2(-.15,-.65),Vector2(.10,-.12),Vector2(-.22,.24),Vector2(-.11,.56)],"role":"light","width":3.0})
				for p in [Vector2(.39,-.33),Vector2(.42,.28),Vector2(-.42,.36)]: result.append({"kind":"polygon","points":[p+Vector2(0,-.16),p+Vector2(.11,0),p+Vector2(0,.16),p+Vector2(-.11,0)],"role":"light"})
			"echo":
				for x in [-.22,.22]: result.append({"kind":"polygon","points":[Vector2(x,-.56),Vector2(x+.19,-.25),Vector2(x+.19,.36),Vector2(x,.56),Vector2(x-.19,.25),Vector2(x-.19,-.36)],"role":"deep" if x<0 else "light"})
			"sacrifice":
				result.append({"kind":"line","points":[Vector2(-.40,-.20),Vector2(-.17,-.12),Vector2(0,.36),Vector2(.17,-.12),Vector2(.40,-.20)],"role":"light"})
				result.append({"kind":"polygon","points":[Vector2(0,-.28),Vector2(.16,.12),Vector2(0,.39),Vector2(-.16,.12)],"role":"deep"})
			"aegis":
				result.append({"kind":"line","points":[Vector2(-.51,-.38),Vector2(0,-.62),Vector2(.51,-.38),Vector2(.39,.24),Vector2(0,.60),Vector2(-.39,.24),Vector2(-.51,-.38)],"role":"light"})
				result.append({"kind":"line","points":[Vector2(0,-.33),Vector2(0,.36)],"role":"light","width":3.0})
	else:
		match key:
			"attack": result.append({"kind":"polygon","points":[Vector2(.25,-.52),Vector2(.32,-.24),Vector2(-.15,.40),Vector2(-.34,.25),Vector2(.06,-.38)],"role":"light"})
			"health":
				result.append({"kind":"line","points":[Vector2(0,-.42),Vector2(0,.40)],"role":"light","width":5.0})
				result.append({"kind":"line","points":[Vector2(-.35,0),Vector2(.35,0)],"role":"light","width":5.0})
			"shield": result.append({"kind":"polygon","points":[Vector2(0,-.50),Vector2(.39,-.28),Vector2(.29,.22),Vector2(0,.49),Vector2(-.29,.22),Vector2(-.39,-.28)],"role":"light"})
			"defense":
				for x in [-.28,0,.28]: result.append({"kind":"line","points":[Vector2(x,-.39),Vector2(x,.37)],"role":"light","width":4.0})
				result.append({"kind":"line","points":[Vector2(-.40,.40),Vector2(.40,.40)],"role":"light"})
			"crit_rate":
				result.append({"kind":"circle","center":Vector2.ZERO,"radius":.27,"role":"deep"})
				for p in [Vector2(0,-.48),Vector2(0,.48),Vector2(-.43,0),Vector2(.43,0)]: result.append({"kind":"line","points":[p,p*.40],"role":"light"})
			"crit_multiplier":
				for p in [Vector2(-.19,-.10),Vector2(.20,.19)]: result.append({"kind":"line","points":[p+Vector2(-.17,0),p+Vector2(.17,0),p,p+Vector2(0,-.24),p+Vector2(0,.24)],"role":"light"})
			"cdr":
				result.append({"kind":"circle","center":Vector2.ZERO,"radius":.37,"role":"deep"})
				result.append({"kind":"line","points":[Vector2(0,-.27),Vector2.ZERO,Vector2(.24,.13)],"role":"light","width":3.0})
			"speed":
				for x in [-.15,.14]: result.append({"kind":"line","points":[Vector2(x-.18,-.37),Vector2(x+.10,0),Vector2(x-.18,.37)],"role":"light","width":3.2})
	return result

func _draw() -> void:
	var side: float = minf(size.x,size.y)
	if side <= 0: return
	var center: Vector2 = size*.5
	var radius: float = side*.42
	var stroke: float = clampf(side/64.0,.5,1.6)
	var tint: Color = tint_for(item_id,rarity)
	draw_circle(center,radius*1.06,Color(INK,.78))
	for command in geometry(item_id):
		var role: String = str(command.get("role","light"))
		var color: Color = tint.lerp(Color.WHITE,.65) if role=="light" else (tint.lerp(INK,.74) if role=="body" else tint.darkened(.38))
		if command.kind=="circle":
			draw_circle(center+command.center*radius,float(command.radius)*radius+stroke,INK)
			draw_circle(center+command.center*radius,float(command.radius)*radius,color)
		else:
			var points=PackedVector2Array()
			for p in command.points: points.append(center+p*radius)
			if command.kind=="polygon":
				draw_colored_polygon(points,color)
				points.append(points[0])
			var width: float = float(command.get("width",1.8))*stroke
			draw_polyline(points,INK,width+2*stroke,true)
			draw_polyline(points,tint if role=="body" else color,width,true)
	if not item_id.begins_with("core:") and side>=44:
		for index in clampi(tier,1,3):
			draw_circle(center+Vector2((index-(clampi(tier,1,3)-1)*.5)*.19,.73)*radius,1.6*stroke,Color.WHITE)
