extends RefCounted
## All gameplay is pure data. Positions use logical x/z metres (Vector2.x/y).
const DEFAULT_CONFIG = "res://data/courtyard.json"
var cfg: Dictionary
var ability: String
var player: Dictionary
var enemies: Array = []
var bullets: Array = []
var pending: Array = []
var effects: Array = []
var orbs: Array = []
var elapsed = 0.0
var result = "playing"
var cooldown = 0.0
var target_id = 0
var hits = 0
var attack_hits = 0
var shots = 0
var casts = 0
var kills = 0
var damage_dealt = 0
var next_bullet_id = 1

func _init(selected: String = "fireball", config: Dictionary = {}):
	cfg = JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_CONFIG)) if config.is_empty() else config.duplicate(true)
	ability = selected
	player = {"pos": Vector2.ZERO, "health": cfg.player_health, "flash": 0.0, "facing": 1.0}
	for point in cfg.spawns:
		var p = Vector2(point[0], point[1])
		enemies.append({"id": enemies.size() + 1, "pos": p, "previous": p, "health": cfg.enemy_health,
			"radius": cfg.enemy_radius, "state": "chase", "timer": 0.0, "aim": Vector2(0,-1),
			"attack": p, "hit": false, "flash": 0.0, "died_at": -1.0})

func move_player(direction: Vector2, dt: float):
	if result != "playing" or direction.is_zero_approx(): return
	var p = player.pos + direction.normalized() * cfg.player_speed * dt
	player.pos = Vector2(clampf(p.x, -cfg.player_bounds.half_width, cfg.player_bounds.half_width),
		clampf(p.y, cfg.player_bounds.min_z, cfg.player_bounds.max_z))
	if direction.x != 0: player.facing = signf(direction.x)

func damage_enemy(e: Dictionary, amount: int):
	if e.health <= 0: return
	damage_dealt += mini(e.health, amount)
	e.health = maxi(0, e.health - amount)
	e.flash = 0.16
	if e.health == 0:
		kills += 1
		e.state = "dead"
		e.died_at = elapsed

func damage_player(amount: int):
	if result != "playing": return
	player.health = maxi(0, player.health - amount)
	player.flash = 0.35 # Visual only. There is no invulnerability window in the source.
	hits += 1
	if player.health == 0: result = "failure"

func valid_target(e: Dictionary) -> bool:
	return e.health > 0 and e.pos.distance_to(player.pos) <= cfg.fireball.range

func select_target() -> Dictionary:
	var candidates = enemies.filter(func(e): return valid_target(e))
	candidates.sort_custom(func(a, b):
		if a.id == target_id: return true
		if b.id == target_id: return false
		var da = a.pos.distance_squared_to(player.pos)
		var db = b.pos.distance_squared_to(player.pos)
		return a.id < b.id if da == db else da < db)
	return {} if candidates.is_empty() else candidates[0]

func update_enemy(e: Dictionary, dt: float):
	var delta: Vector2 = player.pos - e.pos
	var distance = delta.length()
	match e.state:
		"chase":
			if distance <= cfg.chase_distance:
				if distance > 0: e.aim = delta / distance
				e.attack = e.pos + e.aim
				e.state = "warning"
				e.timer = cfg.melee_windup
				e.hit = false
			else: e.pos += delta / distance * minf(cfg.chase_speed * dt, distance - cfg.chase_distance)
		"warning":
			e.timer -= dt
			if e.timer <= 0:
				e.state = "attack"
				e.timer = cfg.melee_active
		"attack":
			if not e.hit and player.pos.distance_to(e.attack) <= cfg.melee_radius + cfg.player_radius:
				e.hit = true
				damage_player(cfg.melee_damage)
			e.timer -= dt
			if e.timer <= 0:
				e.state = "recover"
				e.timer = cfg.melee_recover
		"recover":
			e.timer -= dt
			if e.timer <= 0: e.state = "chase"

static func contact_time(a: Vector2, b: Vector2, radius: float) -> float:
	var delta = b - a
	var length_sq = delta.length_squared()
	var closest = 0.0 if length_sq == 0 else clampf(-a.dot(delta) / length_sq, 0, 1)
	if (a + delta * closest).length_squared() > radius * radius: return INF
	var cc = a.length_squared() - radius * radius
	if cc <= 0 or length_sq == 0: return 0.0
	var bb = 2 * a.dot(delta)
	return (-bb - sqrt(maxf(0, bb * bb - 4 * length_sq * cc))) / (2 * length_sq)

func update_bullets(dt: float):
	for i in range(bullets.size() - 1, -1, -1):
		var b = bullets[i]
		var next: Vector2 = b.pos + b.velocity * dt
		var first: Dictionary = {}
		var contact = INF
		for e in enemies:
			if e.health <= 0: continue
			var t = contact_time(b.pos - e.previous, next - e.pos, e.radius + cfg.fireball.radius)
			if t < contact:
				first = e
				contact = t
		if not first.is_empty():
			var point: Vector2 = b.pos.lerp(next, contact)
			attack_hits += 1
			effects.append({"kind": "explosion", "pos": point, "age": 0.0, "life": 0.25})
			for e in enemies:
				if e.id == first.id or e.previous.lerp(e.pos, contact).distance_to(point) <= cfg.fireball.explosion_radius + e.radius:
					damage_enemy(e, cfg.fireball.damage)
		b.pos = next
		b.age += dt
		if not first.is_empty() or b.age >= cfg.fireball.lifetime or absf(next.x) > cfg.arena_size[0]/2 + 1 or absf(next.y) > cfg.arena_size[1]/2 + 1:
			bullets.remove_at(i)

func update_fireball(dt: float):
	cooldown = maxf(0, cooldown - dt)
	if cooldown == 0:
		var target = select_target()
		if not target.is_empty():
			pending.append({"target": target, "due": elapsed})
			cooldown = cfg.fireball.interval
			casts += 1
	var i = 0
	while i < pending.size():
		var shot = pending[i]
		if not valid_target(shot.target): pending.remove_at(i)
		elif shot.due <= elapsed:
			var delta: Vector2 = shot.target.pos - player.pos
			if delta.is_zero_approx(): delta = Vector2(0,1)
			bullets.append({"id": next_bullet_id, "pos": player.pos, "velocity": delta.normalized() * cfg.fireball.speed, "age": 0.0,
				"origin": player.pos, "facing": player.facing})
			effects.append({"kind": "cast", "pos": player.pos, "facing": player.facing, "age": 0.0, "life": 0.22})
			next_bullet_id += 1
			shots += 1
			pending.remove_at(i)
		else: i += 1

func update_arcane(dt: float):
	if ability == "lightning":
		cooldown = maxf(0, cooldown - dt)
		if cooldown == 0:
			var target = select_target()
			if not target.is_empty():
				var visited: Array = []
				var previous: Vector2 = player.pos
				for chain in range(int(cfg.lightning.count)):
					if target.is_empty(): break
					visited.append(target.id)
					effects.append({"kind": "lightning", "from": previous, "pos": target.pos, "staff": chain == 0, "facing": player.facing, "age": 0.0, "life": 0.22})
					damage_enemy(target, cfg.lightning.damage)
					attack_hits += 1
					previous = target.pos
					var next: Dictionary = {}
					var nearest = float(cfg.lightning.chain_range)
					for e in enemies:
						var distance = previous.distance_to(e.pos)
						if e.health > 0 and not visited.has(e.id) and distance <= nearest:
							next = e
							nearest = distance
					target = next
				cooldown = cfg.lightning.interval
	if ability == "orbit":
		if orbs.is_empty(): orbs.append({"pos": Vector2.ZERO, "hits": {}})
		var orb = orbs[0]
		orb.pos = player.pos + Vector2(cos(elapsed * cfg.orbit.speed), sin(elapsed * cfg.orbit.speed)) * cfg.orbit.radius
		for e in enemies:
			if e.health > 0 and orb.pos.distance_to(e.pos) <= e.radius + cfg.orbit.contact_radius and elapsed >= orb.hits.get(e.id, 0):
				damage_enemy(e, cfg.orbit.damage)
				orb.hits[e.id] = elapsed + cfg.orbit.hit_interval
				attack_hits += 1

func step(dt: float, direction: Vector2 = Vector2.ZERO):
	if result != "playing": return
	move_player(direction, dt)
	elapsed += dt
	player.flash = maxf(0, player.flash - dt)
	for i in range(effects.size() - 1, -1, -1):
		effects[i].age += dt
		if effects[i].age >= effects[i].life: effects.remove_at(i)
	for e in enemies:
		e.previous = e.pos
		e.flash = maxf(0, e.flash - dt)
		if e.health > 0: update_enemy(e, dt)
		if result != "playing": return
	update_bullets(dt)
	update_arcane(dt)
	var target: Dictionary = {}
	var nearest = float(cfg.orbit.radius + cfg.orbit.contact_radius) if ability == "orbit" else float(cfg.fireball.range)
	var living = 0
	for e in enemies:
		if e.health > 0:
			living += 1
			if e.id == target_id and e.pos.distance_to(player.pos) <= nearest: target = e
	if target.is_empty():
		for e in enemies:
			var distance = e.pos.distance_to(player.pos)
			if e.health > 0 and distance <= nearest:
				target = e
				nearest = distance
	target_id = int(target.get("id", 0))
	if living == 0:
		result = "success"
		bullets.clear()
		pending.clear()
	elif ability == "fireball": update_fireball(dt)
