extends "res://scripts/presentation/battle_view.gd"
var trial
func _draw():
	battle=null
	super._draw()
	if trial==null: return
	for burn in trial.burns:
		var p=screen(burn.pos)
		draw_circle(p,burn.radius*64,Color(0.95,0.3,0.12,0.12))
		draw_arc(p,burn.radius*64,0,TAU,64,Color(1,0.55,0.2,0.5),2,true)
	for e in trial.enemies:
		if e.health<=0: continue
		if e.state in ["warning","attack"]:
			var end=screen(e.pos+e.aim*trial.cfg["enemy.lunge_distance"])
			var p=screen(e.pos)
			draw_line(p,end,Color(1,0.3,0.3,0.16),trial.cfg["enemy.attack_radius"]*128,true)
			draw_line(p,end,Color(1,0.58,0.4,0.85),2,true)
			draw_arc(end,trial.cfg["enemy.attack_radius"]*64,0,TAU,48,Color("f5a765"),2,true)
	var sprites=[{"kind":"lina","pos":trial.player.pos,"id":0}]
	for e in trial.enemies:
		if e.health>0: sprites.append({"kind":"slime","pos":e.pos,"id":e.id,"enemy":e})
	sprites.sort_custom(func(a,b): return a.id<b.id if a.pos.y==b.pos.y else a.pos.y>b.pos.y)
	for item in sprites:
		var p=screen(item.pos)
		shadow(p,67 if item.kind=="lina" else 60)
		if item.kind=="lina":
			var tint=Color(1,0.6,0.6) if trial.player.flash>0 else Color.WHITE
			actor(p,LINA,169.6,Vector2(.52,.955),trial.player.facing,tint)
			if trial.phase in ["ready","ready_molten","resume_window"]:
				var c=Color("b8f5ff") if trial.phase=="resume_window" else Color("ffc175")
				draw_arc(p+Vector2(0,-4),42,0,TAU,48,c,3,true)
		else:
			actor(p,SLIME,89.6,Vector2(.52,.9),1,Color.WHITE)
			var ratio=item.enemy.health/(trial.cfg["enemy.health"]*trial.cfg["trial.wave_health_multiplier"])
			draw_line(p+Vector2(-23,-73),p+Vector2(23,-73),Color("263c43"),5)
			draw_line(p+Vector2(-23,-73),p+Vector2(-23+46*ratio,-73),Color("96e9d2"),3)
	if trial.phase in ["chanting","ready","charging_molten","ready_molten"]:
		var p=screen(trial.target)
		var radius=trial.stats(trial.phase=="ready_molten").radius*64
		var c=Color("ff6b5e") if trial.phase=="ready_molten" else Color("ffc175")
		if trial.range_clamped: c=Color("ffad92")
		draw_circle(p,radius,Color(c,0.10))
		draw_arc(p,radius,0,TAU,64,c,2.5,true)
		draw_line(p-Vector2(10,0),p+Vector2(10,0),c,2)
		draw_line(p-Vector2(0,10),p+Vector2(0,10),c,2)
	for bullet in trial.bullets:
		var u=clampf((trial.elapsed-bullet.born)/trial.cfg["fireball.flight_time"],0,1)
		var ground=bullet.start.lerp(bullet.target,u)
		shadow(screen(ground),24)
		var p=screen(ground)+Vector2(0,-4*trial.cfg["fireball.arc_height"]*64*u*(1-u)-30*(1-u))
		glow(p,17 if bullet.stats.enhanced else 11,Color("ff9c4f"))
	for fx in trial.effects:
		var alpha=clampf((fx.until-trial.elapsed)/0.3,0,1)
		draw_circle(screen(fx.pos),fx.radius*64,Color(1,0.55,0.16,alpha*0.22))
		draw_arc(screen(fx.pos),fx.radius*64,0,TAU,64,Color(1,0.8,0.45,alpha),3,true)
