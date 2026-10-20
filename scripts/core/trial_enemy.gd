extends RefCounted
const Legacy=preload("res://scripts/core/battle.gd")
# Shared swept pursuit/telegraph/lunge rules; the caller owns all state.
static func step(b,e: Dictionary,dt: float,old_player: Vector2,chase_multiplier: float=1.0):
	if e.health<=0: return
	var old: Vector2=e.pos
	match e.state:
		"chase":
			var delta: Vector2=b.player.pos-e.pos
			if delta.length()<=b.cfg["enemy.attack_trigger_distance"]:
				e.aim=delta.normalized()
				e.state="warning"
				e.until=b.elapsed+b.cfg["enemy.windup_time"]
			else: e.pos+=delta.normalized()*minf(delta.length(),b.cfg["enemy.chase_speed"]*chase_multiplier*dt)
		"warning":
			if b.elapsed+b.EPS>=e.until:
				e.state="attack"
				e.start=e.pos
				e.until=b.elapsed+b.cfg["enemy.lunge_time"]
				e.hit=false
		"attack":
			var u=clampf(1-(e.until-b.elapsed)/b.cfg["enemy.lunge_time"],0,1)
			e.pos=e.start+e.aim*b.cfg["enemy.lunge_distance"]*u
			if not e.hit and not is_inf(Legacy.contact_time(old-old_player,e.pos-b.player.pos,b.cfg["enemy.attack_radius"]+b.cfg["player.radius"])):
				e.hit=true
				b.damage_player(b.cfg["enemy.damage"])
			if b.elapsed+b.EPS>=e.until:
				e.state="recover"
				e.until=b.elapsed+b.cfg["enemy.recover_time"]
		"recover":
			if b.elapsed+b.EPS>=e.until: e.state="chase"


