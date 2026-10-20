extends RefCounted
## Exactly one active keystone. Queues use combat time, never UI time.
const Gems = preload("res://scripts/core/magic_gems.gd")
const Echo = preload("res://scripts/core/route_gem_echo.gd")
var library = Gems.new()
var rules: Dictionary = library.rules
var core: String = ""
var spec: Dictionary = {}
var clock: float = 0.0
var ready_at: float = 0.0
var pending: Array = []
var reserves: Dictionary = {}
var distance: float = 0.0
var moving: bool = false
var raw_health: float = 0.0
var raw_shield: float = 0.0
var echo = Echo.new()

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
	reset_room()

func reset_room() -> void:
	clock = 0.0
	ready_at = 0.0
	pending.clear()
	reserves.clear()
	distance = 0.0
	moving = false
	echo.clear()

func advance(dt: float, run = null) -> void:
	if run != null and (run.phase != "combat" or run.paused): return
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
		elif item.kind == "coffin": release_coffin(run, int(item.actor_id), int(item.token), item.pos)
	echo.advance(run, clock)

func before_spells(run) -> void:
	moving = false
	if core != "stride": return
	var travelled: float = run.player.pos.distance_to(run.player.previous)
	moving = travelled > float(spec.minimum_motion)
	if moving: distance = minf(float(spec.maximum_distance), distance + travelled)

func is_damage_kind(kind: String) -> bool:
	return kind not in ["", "passive", "shield", "spirit", "ice_armor"]

func suspend_cast(kind: String) -> bool:
	return core == "stride" and moving and is_damage_kind(kind)

func prepare_cast(stats: Dictionary, natural: bool) -> Dictionary:
	var result: Dictionary = {"stats": stats, "body_scale": 1.0}
	if core != "stride" or not natural or not is_damage_kind(str(stats.kind)) or distance <= 0.0: return result
	var fraction: float = clampf(distance / float(spec.maximum_distance), 0.0, 1.0)
	var copied: Dictionary = stats.duplicate(true)
	_scale_sizes(copied, 1.0 + float(spec.maximum_size_bonus) * fraction)
	result.stats = copied
	result.body_scale = 1.0 + float(spec.maximum_body_damage_bonus) * fraction
	distance = 0.0
	return result

func _scale_sizes(values: Dictionary, scale: float) -> void:
	for key in values:
		if key in ["radius", "width", "length", "projectile_radius", "center_radius"] and (values[key] is float or values[key] is int):
			values[key] = float(values[key]) * scale
		elif values[key] is Dictionary: _scale_sizes(values[key], scale)

func cooldown_reduction(value: float) -> float:
	return 0.0 if core == "echo" else value

func outgoing_multiplier(run) -> float:
	if core != "sacrifice": return 1.0
	return 1.0 + maxf(0.0, 1.0 - float(run.player.health) / float(run.player.max_health)) * float(spec.damage_per_missing_fraction)

func body(context: Dictionary) -> bool:
	return str(context.get("school", "")) in ["fire", "ice"] and str(context.get("kind", "")) in ["direct", "bolt", "beam", "rain", "bomb", "wave", "brand", "area"]

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
		"amount": (critical_damage - base_damage) * float(spec.extra_damage_multiplier), "visited": [], "bounces": int(spec.bounce_count)})
	return base_damage

func _crystal(run, item: Dictionary) -> void:
	var actor: Dictionary = {}
	for candidate in run.actors:
		if int(candidate.id) == int(item.actor_id) and float(candidate.health) > 0.0:
			actor = candidate
			break
	if actor.is_empty():
		var nearby: Array = targets(run, item.pos, float(spec.radius), 1, item.visited)
		if nearby.is_empty(): return
		actor = nearby[0]
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
		"amount": float(item.amount) * float(spec.bounce_multiplier), "visited": visited, "bounces": int(item.bounces) - 1})

func defer_plan(run, actor: Dictionary, damage: float, context: Dictionary) -> float:
	if core != "coffin" or not body(context) or damage <= 0.0: return damage
	var window: Dictionary = run._spell_combat.ice.status.capture_ready(int(actor.id))
	if window.is_empty(): return damage
	var id: int = int(actor.id)
	var record: Dictionary = reserves.get(id, {"token": int(window.token), "amount": 0.0, "pos": actor.pos})
	if int(record.token) != int(window.token): return damage
	var stored: float = minf(damage * float(spec.defer_fraction), maxf(0.0, float(run.player.attack) * float(spec.stored_attack_cap) - float(record.amount)))
	record.amount = float(record.amount) + stored
	record.pos = actor.pos
	reserves[id] = record
	return damage - stored

func ice_released(actor: Dictionary, token: int) -> void:
	if core != "coffin" or not reserves.has(int(actor.id)): return
	pending.append({"kind": "coffin", "at": clock, "actor_id": int(actor.id), "token": token, "pos": actor.pos})

func release_coffin(run, id: int, token: int, pos: Vector2) -> void:
	if core != "coffin" or not reserves.has(id) or int(reserves[id].token) != token: return
	var amount: float = float(reserves[id].amount) * float(spec.release_multiplier)
	reserves.erase(id)
	if amount <= 0.0: return
	for actor in targets(run, pos, float(spec.radius), int(spec.target_cap)):
		run.resolve_fixed_item_hit(actor, amount, "gem_coffin")
	run._emit("gem_coffin", {"pos": pos, "radius": spec.radius, "amount": amount}, 0.65)

func actor_died(run, actor: Dictionary) -> void:
	if core == "coffin" and reserves.has(int(actor.id)):
		release_coffin(run, int(actor.id), int(reserves[int(actor.id)].token), actor.pos)

func after_spell_status(run, actor: Dictionary, context: Dictionary) -> void:
	if core != "reactor" or run.phase != "combat" or run.paused or float(actor.get("health", 0.0)) <= 0.0 or clock + 0.000001 < ready_at or not body(context): return
	var fire = run._spell_combat.fire_status
	var ice = run._spell_combat.ice.status
	var window: Dictionary = ice.capture_ready(int(actor.id))
	if window.is_empty() or not fire.has_burn(run, actor): return
	var fuel: float = fire.consume_coefficient(run, actor)
	if fuel <= 0.0: return
	ice.consume_ready(run, actor, int(window.token), {"spell_id": "gem_reactor"})
	ready_at = clock + float(spec.cooldown)
	var nearby: Array = neighbors(run, actor, float(spec.radius), int(spec.neighbor_cap))
	var planned: float = run.gem_planned_damage(actor, float(spec.base_coefficient) + fuel * float(spec.remaining_burn_scale), "thermal")
	run.resolve_fixed_item_hit(actor, planned, "gem_reactor")
	for other in nearby: run.resolve_fixed_item_hit(other, planned * float(spec.neighbor_scale), "gem_reactor")
	run._emit("gem_reactor", {"pos": actor.pos, "radius": spec.radius, "amount": planned}, 0.65)

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
	return {"core": core, "clock": clock, "cooldown_remaining": maxf(0.0, ready_at - clock),
		"coffin_reserves": reserves.duplicate(true), "pending_count": pending.size() + echo.pending.size(),
		"stride_distance": distance, "stride_fraction": distance / float(spec.maximum_distance) if core == "stride" else 0.0, "moving": moving}
