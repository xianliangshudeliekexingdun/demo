extends RefCounted
## Exactly one active keystone. Queues use combat time, never UI time.
const Gems = preload("res://scripts/core/magic_gems.gd")
const Echo = preload("res://scripts/core/route_gem_echo.gd")
const Schools = preload("res://scripts/core/route_gem_schools.gd")
var library = Gems.new()
var rules: Dictionary = library.rules
var core: String = ""
var spec: Dictionary = {}
var clock: float = 0.0
var ready_at: float = 0.0
var pending: Array = []
var reserves: Dictionary = {}
var embers: Dictionary = {}
var distance: float = 0.0
var moving: bool = false
var raw_health: float = 0.0
var raw_shield: float = 0.0
var echo = Echo.new()
var schools = Schools.new()

func configure(run, snapshot: Dictionary) -> void:
	core = str(snapshot.get("gem_core", ""))
	spec = library.core_rule(core)
	if spec.is_empty(): core = ""
	var bonuses: Dictionary = snapshot.get("gem_bonuses", {})
	for key in ["defense", "cdr", "speed"]:
		if float(bonuses.get(key, 0.0)) != 0.0: run.player["gem_" + key] = float(bonuses[key])
	raw_health = float(run.player.max_health)
	raw_shield = float(run.player.max_shield)
	if core == "aegis":
		raw_health /= 1.0 - float(spec.life_conversion)
		raw_shield -= raw_health * float(spec.life_conversion) * float(spec.shield_per_life)
	schools.configure(core, spec)
	reset_room()

func reset_room() -> void:
	clock = 0.0
	ready_at = 0.0
	pending.clear()
	reserves.clear()
	embers.clear()
	distance = 0.0
	moving = false
	echo.clear()
	schools.clear()

func advance(dt: float, run = null) -> void:
	if run != null and (run.phase != "combat" or run.paused or float(run.player.health) <= 0.0): return
	clock += maxf(0.0, dt)
	if run == null or core.is_empty(): return
	if core == "sacrifice" and float(run.player.health) > float(run.player.max_health) * float(spec.drain_floor_fraction):
		var floor_health: float = float(run.player.max_health) * float(spec.drain_floor_fraction)
		run.player.health = maxf(floor_health, float(run.player.health) - float(run.player.max_health) * float(spec.drain_max_health_per_second) * dt)
	var due: Array = []
	var future: Array = []
	for item in pending:
		if float(item.at) <= clock + 0.000001: due.append(item)
		else: future.append(item)
	pending = future
	for item in due:
		if run.phase != "combat" or float(run.player.health) <= 0.0: break
		if item.kind == "crystal": _crystal(run, item)
		elif item.kind == "coffin": _pay_coffin(run, item)
	echo.advance(run, clock)
	schools.advance(run, dt, clock)

# Retired stride API remains callable, without suspending spell windups.
func before_spells(_run) -> void: pass
func is_damage_kind(kind: String) -> bool: return kind not in ["", "passive", "shield", "spirit"]
func suspend_cast(_kind: String) -> bool: return false
func prepare_cast(stats: Dictionary, _natural: bool) -> Dictionary: return {"stats": stats, "body_scale": 1.0}
func cooldown_reduction(value: float) -> float: return value

func outgoing_multiplier(run) -> float:
	if core != "sacrifice": return 1.0
	return 1.0 + maxf(0.0, 1.0 - float(run.player.health) / float(run.player.max_health)) * float(spec.damage_per_missing_fraction)

func body(context: Dictionary) -> bool:
	return str(context.get("school", "")) in ["fire", "ice", "lightning", "wind", "earth", "spirit"] and str(context.get("kind", "")) in ["direct", "bolt", "beam", "rain", "bomb", "wave", "brand", "area", "vortex", "field"]

func neighbors(run, actor: Dictionary, radius: float, cap: int) -> Array:
	return targets(run, actor.pos, radius, cap, [int(actor.id)])

func targets(run, center: Vector2, radius: float, cap: int, excluded: Array = []) -> Array:
	var result: Array = []
	for actor in run.actors:
		if int(actor.id) not in excluded and float(actor.health) > 0.0 and center.distance_to(actor.pos) <= radius + 0.000001 and run.line_is_clear(center, actor.pos): result.append(actor)
	result.sort_custom(func(a, b): return center.distance_squared_to(a.pos) < center.distance_squared_to(b.pos) if not is_equal_approx(center.distance_squared_to(a.pos), center.distance_squared_to(b.pos)) else int(a.id) < int(b.id))
	return result.slice(0, mini(cap, result.size()))

func critical_plan(run, actor: Dictionary, base_damage: float, critical_damage: float, context: Dictionary) -> float:
	if core != "fracture" or not body(context) or critical_damage <= base_damage: return critical_damage
	pending.append({"kind": "crystal", "at": clock + float(spec.first_delay), "actor_id": int(actor.id), "pos": actor.pos,
		"amount": (critical_damage - base_damage) * float(spec.extra_damage_multiplier), "visited": [], "bounces": int(spec.bounce_count), "first": true})
	return base_damage

func _crystal(run, item: Dictionary) -> void:
	var actor: Dictionary = {}
	for candidate in run.actors:
		if int(candidate.id) == int(item.actor_id) and float(candidate.health) > 0.0:
			actor = candidate
			break
	if actor.is_empty():
		if not bool(item.get("first", false)): return
		var nearby: Array = targets(run, item.pos, float(spec.radius), 1, item.visited)
		if nearby.is_empty(): return
		actor = nearby[0]
	if not bool(item.get("first", false)) and (Vector2(item.pos).distance_to(actor.pos) > float(spec.radius) + 0.000001 or not run.line_is_clear(item.pos, actor.pos)): return
	var from: Vector2 = item.pos
	var pos: Vector2 = actor.pos
	var visited: Array = item.visited.duplicate()
	visited.append(int(actor.id))
	run.resolve_fixed_item_hit(actor, float(item.amount), "gem_fracture")
	run._emit("gem_fracture", {"from": from, "to": pos, "pos": pos, "amount": item.amount}, 0.35)
	if int(item.bounces) <= 0: return
	var next: Array = targets(run, pos, float(spec.radius), 1, visited)
	if next.is_empty(): return
	pending.append({"kind": "crystal", "at": clock + float(spec.bounce_delay), "actor_id": int(next[0].id), "pos": pos,
		"amount": float(item.amount) * float(spec.bounce_multiplier), "visited": visited, "bounces": int(item.bounces) - 1, "first": false})

func defer_plan(run, actor: Dictionary, damage: float, context: Dictionary) -> float:
	if core != "coffin" or not body(context) or damage <= 0.0: return damage
	var window: Dictionary = run._spell_combat.ice.status.capture_ready(int(actor.id))
	if window.is_empty(): return damage
	var id: int = int(actor.id)
	var record: Dictionary = reserves.get(id, {})
	if record.is_empty() or int(record.token) != int(window.token):
		record = {"token": int(window.token), "amount": 0.0, "pos": actor.pos, "cap": float(run.player.attack) * float(spec.stored_attack_cap)}
	var stored: float = minf(damage * float(spec.defer_fraction), maxf(0.0, float(record.cap) - float(record.amount)))
	record.amount = float(record.amount) + stored
	record.pos = actor.pos
	reserves[id] = record
	return damage - stored

func ice_released(actor: Dictionary, token: int) -> void:
	if core != "coffin" or not reserves.has(int(actor.id)) or int(reserves[int(actor.id)].token) != token: return
	var record: Dictionary = reserves[int(actor.id)]
	reserves.erase(int(actor.id))
	pending.append({"kind": "coffin", "at": clock, "actor_id": int(actor.id), "token": token, "pos": actor.pos, "amount": record.amount, "reason": "consume"})

func release_coffin(run, id: int, token: int, pos: Vector2, reason: String = "natural") -> void:
	if core != "coffin" or not reserves.has(id) or int(reserves[id].token) != token: return
	var record: Dictionary = reserves[id]
	reserves.erase(id)
	_pay_coffin(run, {"actor_id": id, "token": token, "pos": pos, "amount": record.amount, "reason": reason})

func _pay_coffin(run, item: Dictionary) -> void:
	var reason: String = str(item.reason)
	var multiplier: float = float(spec.natural_multiplier) if reason == "natural" else (float(spec.consume_multiplier) if reason == "consume" else float(spec.death_multiplier))
	var amount: float = float(item.amount) * multiplier
	if amount <= 0.0: return
	var others: Array = targets(run, item.pos, float(spec.radius), int(spec.neighbor_cap), [int(item.actor_id)])
	var primary: Dictionary = {}
	for actor in run.actors:
		if int(actor.id) == int(item.actor_id):
			primary = actor
			break
	if reason != "death" and not primary.is_empty() and float(primary.health) > 0.0:
		run.resolve_fixed_item_hit(primary, amount, "gem_coffin")
	for other in others: run.resolve_fixed_item_hit(other, amount * float(spec.neighbor_scale), "gem_coffin")
	run._emit("gem_coffin", {"pos": item.pos, "radius": spec.radius, "amount": amount, "reason": reason, "token": item.token}, 0.65)

func actor_died(run, actor: Dictionary, allow_release: bool = true) -> void:
	embers.erase(int(actor.id))
	if core == "coffin" and reserves.has(int(actor.id)):
		if allow_release: release_coffin(run, int(actor.id), int(reserves[int(actor.id)].token), actor.pos, "death")
		else: reserves.erase(int(actor.id))

func _ember_record(run, actor: Dictionary, token: int) -> Dictionary:
	var record: Dictionary = embers.get(int(actor.id), {})
	if record.is_empty() or int(record.token) != token:
		record = {"token": token, "amount": 0.0, "ticks": 0, "body_casts": {}, "cap": float(run.player.attack) * float(spec.stored_attack_cap), "pos": actor.pos}
	elif int(record.ticks) == 0 and float(record.amount) <= 0.0:
		record.cap = float(run.player.attack) * float(spec.stored_attack_cap)
	record.pos = actor.pos
	return record

func fire_body_hit(run, actor: Dictionary, actual: float, context: Dictionary, old_token: int) -> void:
	if core != "inferno" or old_token < 0 or actual <= 0.0 or float(actor.health) <= 0.0 or not bool(context.get("natural", false)) or not body(context) or str(context.get("school", "")) != "fire" or str(context.get("spell_id", "")) == "F07": return
	if run._spell_combat.fire_status.burn_token(run, actor) != old_token: return
	var record: Dictionary = _ember_record(run, actor, old_token)
	var cast: String = str(context.get("cast_id", -1))
	if record.body_casts.has(cast): return
	record.body_casts[cast] = true
	record.amount = minf(float(record.cap), float(record.amount) + actual * float(spec.body_damage_fraction))
	embers[int(actor.id)] = record

func fire_tick(run, actor: Dictionary, token: int, actual: float) -> void:
	if core != "inferno" or actual <= 0.0 or float(actor.health) <= 0.0: return
	var record: Dictionary = _ember_record(run, actor, token)
	record.amount = minf(float(record.cap), float(record.amount) + actual * float(spec.burn_damage_fraction))
	record.ticks = int(record.ticks) + 1
	embers[int(actor.id)] = record
	if int(record.ticks) < int(spec.ticks_required): return
	var amount: float = float(record.amount)
	record.amount = 0.0
	record.ticks = 0
	var others: Array = neighbors(run, actor, float(spec.radius), int(spec.neighbor_cap))
	run.resolve_fixed_item_hit(actor, amount, "gem_inferno")
	for other in others: run.resolve_fixed_item_hit(other, amount * float(spec.neighbor_scale), "gem_inferno")
	run._emit("gem_inferno", {"pos": record.pos, "radius": spec.radius, "amount": amount, "actor_id": actor.id}, 0.55)

func fire_ended(actor_id: int, token: int) -> void:
	if embers.has(actor_id) and int(embers[actor_id].token) == token: embers.erase(actor_id)

func after_spell_status(_run, _actor: Dictionary, _context: Dictionary) -> void: pass

func begin_cap_change(run) -> Dictionary:
	if core != "aegis": return {}
	var fractions: Dictionary = {"health": float(run.player.health) / maxf(1.0, float(run.player.max_health)), "shield": float(run.player.shield) / maxf(1.0, float(run.player.max_shield))}
	run.player.max_health = raw_health
	run.player.max_shield = raw_shield
	return fractions

func finish_cap_change(run, fractions: Dictionary) -> void:
	if fractions.is_empty(): return
	raw_health = float(run.player.max_health)
	raw_shield = float(run.player.max_shield)
	var converted: float = raw_health * float(spec.life_conversion)
	run.player.max_health = raw_health - converted
	run.player.max_shield = raw_shield + converted * float(spec.shield_per_life)
	run.player.health = float(run.player.max_health) * float(fractions.health)
	run.player.shield = float(run.player.max_shield) * float(fractions.shield)

func snapshot() -> Dictionary:
	return {"core": core, "clock": clock, "cooldown_remaining": 0.0, "coffin_reserves": reserves.duplicate(true), "embers": embers.duplicate(true),
		"pending_count": pending.size() + echo.pending.size(), "schools": schools.snapshot(), "stride_distance": 0.0, "stride_fraction": 0.0, "moving": moving}
