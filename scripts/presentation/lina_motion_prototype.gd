extends Node2D
## Isolated visual experiment. No battle state, input or damage ownership.
const ATLAS = preload("res://assets/prototypes/lina-motion/rig-v1.png")
const CYCLE = 0.8
const STRIDE = 22.0
var sample_time = 0.0
var walking = false
var debug_joints = false
var feet: Array[Vector2] = []
var motion_weight = 1.0

func sample(t: float, moving: bool, weight: float = 1.0):
	sample_time = t
	walking = moving
	motion_weight = clampf(weight,0.0,1.0) if moving else 0.0
	queue_redraw()

func piece(region: Rect2, anchor: Vector2, at: Vector2, factor: Vector2, angle: float = 0.0):
	draw_set_transform(at, angle, factor)
	draw_texture_rect_region(ATLAS, Rect2(region.position-anchor, region.size), region)
	draw_set_transform(Vector2.ZERO)

func segment(region: Rect2, start: Vector2, finish: Vector2, width: float, overlap: float):
	var delta = finish-start
	draw_set_transform(start, delta.angle()-PI/2)
	draw_texture_rect_region(ATLAS, Rect2(-width/2,-overlap,width,delta.length()+overlap*2),region)
	draw_set_transform(Vector2.ZERO)

func foot_at(index: int) -> Vector2:
	var base = Vector2(-8 if index == 0 else 8, -3 if index == 0 else 0)
	if not walking: return base
	var phase = fposmod(sample_time/CYCLE+index*0.5,1.0)
	var travel: float
	var lift = 0.0
	if phase < 0.5:
		travel = STRIDE*(0.5-phase*2.0)
	else:
		var u = (phase-0.5)*2.0
		travel = STRIDE*(-0.5+u*u*(3.0-2.0*u))
		lift = sin(u*PI)*8.0
	return base+Vector2(travel,-lift)*motion_weight

func leg(index: int, bob: float):
	var hip = Vector2(-8 if index == 0 else 8,(-38 if index == 0 else -35)+bob)
	var sole = foot_at(index)
	feet.append(sole)
	var phase = fposmod(sample_time/CYCLE+index*0.5,1.0)
	var lift = sin((phase-0.5)*2*PI)*8.0*motion_weight if walking and phase>=0.5 else 0.0
	# Keep the planted boot upright and its sole fixed to the ground.
	# Only the lifted boot articulates; never squash a whole shoe along the shin.
	var boot_angle = -lift*0.014
	var knee = sole+Vector2(0,-21).rotated(boot_angle)
	# Exclude the generated open joint caps; overlap stocking material instead.
	var thigh = Rect2(202,598,113,186) if index == 0 else Rect2(575,598,114,186)
	var boot = Rect2(168,908,148,286) if index == 0 else Rect2(565,908,146,286)
	segment(thigh,hip,knee,10,3.0)
	draw_set_transform(sole,boot_angle)
	draw_texture_rect_region(ATLAS,Rect2(-7,-23,14,24),boot)
	draw_set_transform(Vector2.ZERO)
	if debug_joints:
		draw_line(hip,knee,Color.CYAN,0.7)
		draw_line(knee,sole,Color.CYAN,0.7)
		draw_circle(sole,1.5,Color.YELLOW)

func _draw():
	feet.clear()
	var breath = sin(sample_time*TAU/3.2)
	var bob = -absf(sin(sample_time*TAU/CYCLE))*1.2*motion_weight if walking else breath*0.5
	var lean = 0.012*motion_weight if walking else breath*0.003
	var neck = Vector2(0,-76+bob)
	var blink = fposmod(sample_time,3.2)>2.75 and fposmod(sample_time,3.2)<2.90
	# Back hair first; torso covers its middle. Head/front hair goes over collar.
	piece(Rect2(12,45,412,453),Vector2(281,362),neck,Vector2.ONE*0.24,lean)
	leg(0,bob)
	leg(1,bob)
	piece(Rect2(827,45,410,427),Vector2(1015,445),Vector2(0,-27+bob),Vector2.ONE*0.205,lean)
	piece(Rect2(12,45,412,322),Vector2(281,362),neck,Vector2.ONE*0.24,lean)
	if blink:
		# Replace only the eye region. Full closed-head atlas cell catches a
		# neighboring cape and shifts the hat silhouette between blink frames.
		piece(Rect2(631,282,136,67),Vector2(702,362),neck,Vector2.ONE*0.24,lean)
