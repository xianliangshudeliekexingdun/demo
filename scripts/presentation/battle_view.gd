extends Node2D
const GROUND = preload("res://assets/environment/ground.png")
const PORTAL = preload("res://assets/environment/portal.png")
const LINA = preload("res://assets/characters/lina.png")
const SLIME = preload("res://assets/characters/slime.png")
var battle
var menu = true

static func screen(p: Vector2) -> Vector2:
	return Vector2(640 + p.x * 64, 360 - p.y * 64)

static func staff(p: Vector2, facing: float) -> Vector2:
	return screen(p) + Vector2(54 * facing, -98)

func glow(point: Vector2, radius: float, color: Color):
	draw_circle(point, radius * 2.1, Color(color, 0.08))
	draw_circle(point, radius * 1.5, Color(color, 0.18))
	draw_circle(point, radius, color)
	draw_circle(point + Vector2(-radius * 0.2,-radius * 0.2), radius * 0.48, Color("fff3d9"))

func shadow(point: Vector2, width: float, alpha: float = 1):
	# Layered contact shadow: soft outer edge, dense ground contact, no state writes.
	draw_set_transform(point + Vector2(0,1), 0, Vector2(1, 0.28))
	for layer in range(12):
		var radius = width * 0.5 * (1.0 - layer * 0.042)
		draw_circle(Vector2.ZERO, radius, Color(0.14,0.12,0.11,0.034 * alpha),true,-1,true)
	draw_set_transform(Vector2.ZERO)

func actor(point: Vector2, texture: Texture2D, height: float, foot: Vector2, facing: float, tint: Color):
	draw_set_transform(point, 0, Vector2(facing,1))
	draw_texture_rect(texture, Rect2(-foot * height, Vector2.ONE * height), false, tint)
	draw_set_transform(Vector2.ZERO)

func _draw():
	# Equal-scale crop: 720x405 interior strip -> 1280x720. Never stretch portrait art.
	draw_texture_rect_region(GROUND, Rect2(0,0,1280,720), Rect2(0,420,720,405))
	draw_rect(Rect2(0,0,1280,720), Color(0.12,0.20,0.18,0.08))
	draw_texture_rect(PORTAL, Rect2(380,-85,520,347), false)
	# A subtle ground outline identifies the foot-position boundary.
	draw_style_box(arena_style(), Rect2(96,279,1088,379))
	if battle == null: return
	for e in battle.enemies:
		if e.health > 0 and e.state in ["warning", "attack"]:
			var p = screen(e.attack)
			var active = e.state == "attack"
			var col = Color("f5a765") if not active else Color("ffe5af")
			draw_circle(p, battle.cfg.melee_radius * 64, Color(col, 0.22 if active else 0.13))
			draw_arc(p, battle.cfg.melee_radius * 64, 0, TAU, 64, Color(col,0.85), 2.0, true)
			if not active:
				var progress = 1.0 - e.timer / battle.cfg.melee_windup
				draw_arc(p, battle.cfg.melee_radius*64 - 6, -PI/2, -PI/2 + TAU * progress, 64, col, 4.0, true)
	shadow(screen(battle.player.pos), 67)
	var actors: Array = [{"id": 0, "kind": "lina", "pos": battle.player.pos}]
	for e in battle.enemies:
		var age = battle.elapsed - e.died_at
		if e.health > 0 or age < 0.35:
			var alpha = 1.0 if e.health > 0 else maxf(0,1-age/0.35)
			shadow(screen(e.pos), 60, alpha)
			actors.append({"id": e.id, "kind": "slime", "pos": e.pos, "enemy": e, "alpha": alpha})
	for orb in battle.orbs:
		draw_set_transform(screen(orb.pos),0,Vector2(1,0.30))
		draw_circle(Vector2.ZERO,11,Color(0.09,0.16,0.16,0.23))
		draw_set_transform(Vector2.ZERO)
		actors.append({"id": 100, "kind": "orb", "pos": orb.pos})
	actors.sort_custom(func(a,b): return a.id < b.id if a.pos.y == b.pos.y else a.pos.y > b.pos.y)
	for item in actors:
		var p = screen(item.pos)
		match item.kind:
			"lina":
				var tint = Color(1,0.65,0.65) if battle.player.flash > 0 else Color.WHITE
				actor(p, LINA, 169.6, Vector2(0.52,0.955), battle.player.facing, tint)
			"slime":
				var e = item.enemy
				var tint = Color(1.5,1.2,1.1,item.alpha) if e.flash > 0 else Color(1,1,1,item.alpha)
				actor(p, SLIME, 89.6, Vector2(0.52,0.90), 1, tint)
				if e.health > 0 and e.health < battle.cfg.enemy_health:
					draw_line(p+Vector2(-20,-74),p+Vector2(20,-74),Color("263c43"),4)
					draw_line(p+Vector2(-20,-74),p+Vector2(-20+40*e.health/battle.cfg.enemy_health,-74),Color("96e9d2"),3)
			"orb": glow(p+Vector2(0,-42),13,Color("bd9bec"))
	for b in battle.bullets:
		var p = screen(b.pos)
		# Visual-only release arc converges on the unchanged collision trajectory.
		var release = maxf(0, 1-b.age/0.22)
		p += Vector2(54*b.facing,-98) * release
		var tail = Vector2(-b.velocity.x,b.velocity.y).normalized()
		draw_line(p+tail*32,p,Color(1,0.52,0.24,0.35),11,true)
		draw_line(p+tail*20,p,Color("ffbc65"),5,true)
		glow(p,11,Color("ffab59"))
	for fx in battle.effects:
		var alpha = 1-fx.age/fx.life
		if fx.kind == "explosion":
			var p = screen(fx.pos)
			draw_circle(p,64*(1-alpha*0.3),Color(1,0.69,0.31,alpha*0.24))
			draw_arc(p,64*(1-alpha*0.4),0,TAU,40,Color(1,0.80,0.44,alpha),3,true)
		elif fx.kind == "cast":
			draw_arc(staff(fx.pos,fx.facing),18*(2-alpha),0,TAU,24,Color(1,0.81,0.45,alpha),2,true)
		elif fx.kind == "lightning":
			var start = staff(fx.from,fx.facing) if fx.staff else screen(fx.from)+Vector2(0,-30)
			var end = screen(fx.pos)+Vector2(0,-30)
			var points = PackedVector2Array([start])
			var normal = (end-start).normalized().orthogonal()
			for j in range(1,7): points.append(start.lerp(end,j/7.0)+normal*(9 if j%2 else -9))
			points.append(end)
			draw_polyline(points,Color(0.48,0.83,1,alpha*0.3),12,true)
			draw_polyline(points,Color(0.85,0.96,1,alpha),3,true)

func arena_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0,0,0,0)
	style.border_color = Color(0.82,0.91,0.78,0.18)
	style.set_border_width_all(2)
	style.set_corner_radius_all(20)
	return style
