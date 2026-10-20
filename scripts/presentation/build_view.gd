extends "res://scripts/presentation/battle_view.gd"
const Catalog=preload("res://scripts/core/spell_catalog.gd")
var trial
func ring(point: Vector2,radius: float,color: Color,alpha: float=.12):
	draw_circle(point,radius,Color(color,alpha))
	draw_arc(point,radius,0,TAU,64,color,2.5,true)
func _draw():
	battle=null
	super._draw()
	if trial==null: return
	for field in trial.fields: ring(screen(field.pos),field.radius*64,Color("88dce8"),.07)
	for region in trial.burns: ring(screen(region.pos),region.radius*64,Color("eea164"),.09)
	for e in trial.enemies:
		if e.health<=0: continue
		if e.state in ["warning","attack"]:
			var p=screen(e.pos)
			var end=screen(e.pos+e.aim*trial.cfg["enemy.lunge_distance"])
			draw_line(p,end,Color(1,.25,.22,.13),trial.cfg["enemy.attack_radius"]*128,true)
			draw_dashed_line(p,end,Color("ff7864"),2,8,true)
			draw_arc(end,trial.cfg["enemy.attack_radius"]*64,0,TAU,48,Color("ff7864"),2,true)
	var sprites=[{"kind":"lina","pos":trial.player.pos,"id":0}]
	for e in trial.enemies:
		if e.health>0: sprites.append({"kind":"slime","pos":e.pos,"id":e.id,"enemy":e})
	sprites.sort_custom(func(a,b): return a.id<b.id if a.pos.y==b.pos.y else a.pos.y>b.pos.y)
	for item in sprites:
		var p=screen(item.pos)
		shadow(p,67 if item.kind=="lina" else 60)
		if item.kind=="lina":
			actor(p,LINA,169.6,Vector2(.52,.955),trial.player.facing,Color(1,.6,.6) if trial.player.flash>0 else Color.WHITE)
			if not trial.healing.is_empty(): draw_arc(p+Vector2(0,-5),37,0,TAU,48,Color("a4dfaa"),3,true)
			if trial.shield_total()>0: draw_arc(p+Vector2(0,-52),57,0,TAU,64,Color("cee9c9"),2,true)
			if trial.phase in ["ready","ready_molten","resume_window"]: draw_arc(p+Vector2(0,-4),43,0,TAU,48,Color("b8f5ff") if trial.phase=="resume_window" else Color(Catalog.COLORS[trial.active_spell()]),3,true)
		else:
			var slowed=item.enemy.slow_until>trial.elapsed
			actor(p,SLIME,89.6,Vector2(.52,.9),1,Color(.7,.9,1) if slowed else Color.WHITE)
			var ratio=item.enemy.health/item.enemy.max_health
			draw_line(p+Vector2(-23,-73),p+Vector2(23,-73),Color("263c43"),5)
			draw_line(p+Vector2(-23,-73),p+Vector2(-23+46*ratio,-73),Color("96e9d2"),3)
			if slowed:
				draw_arc(p,27,PI*.1,PI*.9,24,Color("94dbff"),3,true)
				draw_line(p+Vector2(-6,-40),p+Vector2(6,-40),Color("e3f7ff"),2)
				draw_line(p+Vector2(0,-46),p+Vector2(0,-34),Color("e3f7ff"),2)
			if item.enemy.freeze_until>trial.elapsed:
				draw_rect(Rect2(p+Vector2(-32,-66),Vector2(64,62)),Color(.7,.9,1,.24))
				draw_rect(Rect2(p+Vector2(-32,-66),Vector2(64,62)),Color("d7f8ff"),false,2)
			if item.enemy.exposure_until>trial.elapsed: draw_arc(p,33,0,TAU,48,Color("dab2ff"),2,true)
	if trial.phase in ["chanting","ready","charging_molten","ready_molten"]:
		var id=trial.active_spell()
		var s=trial.stats(trial.phase=="ready_molten")
		var color=Color(Catalog.COLORS[id])
		var p=screen(trial.target)
		if s.radius>0: ring(p,s.radius*64,color)
		elif id=="lamp": ring(p,s.range*64,Color(color,.5),.03)
		else: ring(p,36,color)
		if Catalog.targeted(id):
			draw_line(p-Vector2(10,0),p+Vector2(10,0),color,2)
			draw_line(p-Vector2(0,10),p+Vector2(0,10),color,2)
	for b in trial.bullets:
		var u=clampf((trial.elapsed-b.born)/trial.cfg["fireball.flight_time"],0,1)
		var ground=b.start.lerp(b.target,u)
		shadow(screen(ground),24)
		glow(screen(ground)+Vector2(0,-4*trial.cfg["fireball.arc_height"]*64*u*(1-u)-30*(1-u)),11,Color("ff9c4f"))
	for m in trial.meteors:
		if trial.elapsed<m.born: continue
		var u=clampf((trial.elapsed-m.born)/m.stats.fall_time,0,1)
		var p=screen(m.target)
		ring(p,m.stats.radius*64,Color("ff9963"),.04)
		var high=p+Vector2(38*(1-u),-210*(1-u))
		draw_line(high+Vector2(22,-45),high,Color(1,.4,.1,.65),9,true)
		glow(high,21,Color("ffc16f"))
	if not trial.lamp.is_empty():
		var p=screen(trial.player.pos)+Vector2(-65,-94)
		glow(p,12,Color("d5b7ff"))
		draw_rect(Rect2(p-Vector2(13,16),Vector2(26,32)),Color("54435f"),false,2)
		if "lamp_twin" in trial.lamp.stats.owned:
			var twin=screen(trial.player.pos)+Vector2(65,-94)
			glow(twin,12,Color("bdefff"))
			draw_rect(Rect2(twin-Vector2(13,16),Vector2(26,32)),Color("54435f"),false,2)
		for i in range(maxi(0,trial.events.size()-12),trial.events.size()):
			var event=trial.events[i]
			if event.kind=="lamp_attack" and trial.elapsed-event.time<.18 and event.data.parent_cast_id==trial.lamp.id:
				draw_line(p,screen(event.data.target)+Vector2(0,-30),Color("ead6ff"),2,true)
	for fx in trial.effects:
		var alpha=clampf((fx.until-trial.elapsed)/.4,0,1)
		var color=Color(fx.get("color","ffc175"))
		ring(screen(fx.pos),fx.radius*64,Color(color,alpha),alpha*.14)
