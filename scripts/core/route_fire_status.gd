extends RefCounted
## One shared fire burn per enemy. Only core combat time schedules ticks.

var burns: Dictionary = {}
var reignite_pending: Array = []
var _rules: Dictionary = {}
var _reignite_ready: Dictionary = {}
var _serial: int = 0
var _clock: float = 0.0


func configure(rules: Dictionary) -> void:
	_rules = rules.duplicate(true)
	clear()


func clear() -> void:
	burns.clear()
	reignite_pending.clear()
	_reignite_ready.clear()
	_serial = 0
	_clock = 0.0


func remove_actor(actor_id: int) -> void:
	burns.erase(actor_id)
	_reignite_ready.erase(actor_id)
	reignite_pending = reignite_pending.filter(func(item): return int(item.actor_id) != actor_id)


func apply_burn(run, actor: Dictionary, source: String = "") -> bool:
	if not _active(run) or actor.is_empty() or float(actor.get("health", 0.0)) <= 0.0:
		return false
	var parameters: Dictionary = _parameters(run)
	var key: int = int(actor.id)
	var now: float = _clock
	if burns.has(key) and float(burns[key].expires) + 0.000001 >= now:
		burns[key].expires = maxf(float(burns[key].expires), now + float(parameters.duration))
		burns[key].maximum_ticks = maxi(int(burns[key].maximum_ticks), int(parameters.maximum_ticks))
		burns[key].source = source
		if run.has_method("gem_core") and run.gem_core() == "inferno":
			var spec: Dictionary = run._gem_combat.spec
			if now + 0.000001 >= float(burns[key].get("layer_ready", 0.0)):
				burns[key].layers = mini(int(spec.cap), int(burns[key].get("layers", 1)) + 1)
				burns[key].layer_ready = now + float(spec.gain_interval)
			burns[key].decay_at = now + float(spec.decay_delay)
	else:
		_serial += 1
		burns[key] = {"actor_id": key, "next_tick": now + float(parameters.interval),
			"expires": now + float(parameters.duration), "interval": float(parameters.interval),
			"coefficient": float(parameters.coefficient), "maximum_ticks": int(parameters.maximum_ticks),
			"token": _serial, "source": source, "layers": 1,
			"layer_ready": now}
		if run.has_method("gem_core") and run.gem_core() == "inferno":
			burns[key].layer_ready = now + float(run._gem_combat.spec.gain_interval)
			burns[key]["decay_at"] = now + float(run._gem_combat.spec.decay_delay)
			burns[key]["decay_interval"] = float(run._gem_combat.spec.decay_interval)
	_emit(run, "fire_ignited", {"actor_id": key, "pos": actor.pos, "source": source,
		"expires": burns[key].expires, "next_tick": burns[key].next_tick})
	return true


func has_burn(run, actor: Dictionary) -> bool:
	return future_ticks(run, actor) > 0


func burn_token(run, actor: Dictionary) -> int:
	return int(burns[int(actor.id)].token) if has_burn(run, actor) else -1


func future_ticks(run, actor: Dictionary) -> int:
	if actor.is_empty() or not burns.has(int(actor.id)) or float(actor.get("health", 0.0)) <= 0.0:
		return 0
	var state: Dictionary = burns[int(actor.id)]
	if float(state.expires) + 0.000001 < _clock or float(state.next_tick) > float(state.expires) + 0.000001:
		return 0
	return mini(int(state.maximum_ticks), maxi(0, int(floor((float(state.expires) - float(state.next_tick) + 0.000001) / float(state.interval))) + 1))


func update(run, dt: float) -> void:
	if not _active(run):
		return
	_clock += maxf(0.0, dt)
	var now: float = _clock
	# Complete all due old ticks before any impact or delayed re-ignition.
	var keys: Array = burns.keys()
	keys.sort()
	for key in keys:
		if not burns.has(key):
			continue
		var actor: Dictionary = _actor(run, int(key))
		if actor.is_empty() or float(actor.health) <= 0.0:
			burns.erase(key)
			continue
		var state: Dictionary = burns[key]
		while float(state.next_tick) <= now + 0.000001 and float(state.next_tick) <= float(state.expires) + 0.000001 and float(actor.health) > 0.0 and _active(run):
			var tick_at: float = float(state.next_tick)
			_age_layers(state, tick_at, false)
			state.next_tick = float(state.next_tick) + float(state.interval)
			_damage(run, actor, float(state.coefficient) * int(state.get("layers", 1)), "burning", {"source": str(state.source)})
			_age_layers(state, tick_at, true)
		_age_layers(state, now, true)
		if float(actor.health) <= 0.0 or float(state.expires) <= now + 0.000001:
			burns.erase(key)


func flush_reignites(run) -> void:
	if not _active(run):
		return
	var now: float = _clock
	var retained: Array = []
	for item in reignite_pending:
		if float(item.at) > now + 0.000001:
			retained.append(item)
			continue
		var actor: Dictionary = _actor(run, int(item.actor_id))
		if not actor.is_empty() and float(actor.health) > 0.0 and apply_burn(run, actor, str(item.get("source", "G04"))):
			_emit(run, "fire_reignited", {"actor_id": actor.id, "pos": actor.pos, "spell_id": str(item.get("source", "G04"))})
	reignite_pending = retained


func detonate_burn(run, actor: Dictionary, multiplier: float, natural: bool = false, cast_id: Variant = -1, required_token: int = -1, reapply: Dictionary = {}) -> float:
	if not _active(run) or actor.is_empty() or float(actor.get("health", 0.0)) <= 0.0:
		return 0.0
	var key: int = int(actor.id)
	if required_token >= 0 and (not burns.has(key) or int(burns[key].token) != required_token):
		return 0.0
	var count: int = future_ticks(run, actor)
	if count <= 0:
		return 0.0
	var state: Dictionary = burns[key]
	var fuel: float = future_coefficient(run, actor)
	var g04: Dictionary = reapply.duplicate(true)
	if g04.is_empty() and natural and run.has_method("artifact_reignite_spec"):
		g04 = run.artifact_reignite_spec()
	if not g04.is_empty():
		multiplier += float(g04.detonation_multiplier_add)
	burns.erase(key)
	var actual: float = _damage(run, actor, fuel * multiplier, "detonation", {"cast_id": cast_id, "future_ticks": count, "natural_bomb": natural})
	_emit(run, "fire_detonation", {"actor_id": actor.id, "pos": actor.pos, "future_ticks": count, "multiplier": multiplier, "amount": actual, "cast_id": cast_id})
	if not g04.is_empty() and float(actor.health) > 0.0 and _clock + 0.000001 >= float(_reignite_ready.get(key, -INF)):
		_reignite_ready[key] = _clock + float(g04.reapply_shared_cooldown)
		reignite_pending.append({"actor_id": key, "at": _clock + float(g04.reapply_delay), "cast_id": cast_id, "source": g04.get("source", "G04")})
	return actual


func spread(run, primary: Dictionary, radius: float, count: int, source: String = "F11") -> Array:
	var chosen: Array = []
	if not _active(run) or count <= 0:
		return chosen
	var origin: Vector2 = primary.pos
	var candidates: Array = []
	for actor in run.actors:
		if int(actor.id) == int(primary.id) or float(actor.health) <= 0.0 or has_burn(run, actor):
			continue
		var distance: float = origin.distance_to(actor.pos)
		if distance <= radius + 0.000001 and run.line_is_clear(origin, actor.pos):
			candidates.append({"actor": actor, "distance": distance})
	candidates.sort_custom(func(a, b): return a.distance < b.distance if not is_equal_approx(float(a.distance), float(b.distance)) else int(a.actor.id) < int(b.actor.id))
	for entry in candidates:
		if chosen.size() >= count:
			break
		if apply_burn(run, entry.actor, source):
			chosen.append(int(entry.actor.id))
			_emit(run, "fire_spread", {"from": origin, "to": entry.actor.pos, "pos": entry.actor.pos, "actor_id": entry.actor.id, "spell_id": source})
	return chosen

func consume_coefficient(run, actor: Dictionary) -> float:
	var count: int = future_ticks(run, actor)
	if count <= 0: return 0.0
	var fuel: float = future_coefficient(run, actor)
	burns.erase(int(actor.id))
	return fuel

func _age_layers(state: Dictionary, at: float, inclusive: bool) -> void:
	if not state.has("decay_at"): return
	while (float(state.decay_at) <= at + 0.000001 if inclusive else float(state.decay_at) < at - 0.000001):
		state.layers = maxi(1, int(state.layers) - 1)
		state.decay_at = float(state.decay_at) + float(state.decay_interval)

func future_coefficient(run, actor: Dictionary) -> float:
	var count: int = future_ticks(run, actor)
	if count <= 0: return 0.0
	var state: Dictionary = burns[int(actor.id)].duplicate(true)
	var fuel: float = 0.0
	for index in count:
		var tick_at: float = float(state.next_tick) + index * float(state.interval)
		_age_layers(state, tick_at, false)
		fuel += float(state.coefficient) * int(state.get("layers", 1))
		_age_layers(state, tick_at, true)
	return fuel


func snapshot(run = null) -> Array:
	var result: Array = []
	var keys: Array = burns.keys()
	keys.sort()
	for key in keys:
		var value: Dictionary = burns[key].duplicate(true)
		value["remaining"] = maxf(0.0, float(value.expires) - _clock)
		result.append(value)
	return result


func _parameters(run) -> Dictionary:
	return run.artifact_burn_parameters(_rules).duplicate(true) if run.has_method("artifact_burn_parameters") else _rules.duplicate(true)


func _actor(run, id: int) -> Dictionary:
	for actor in run.actors:
		if int(actor.id) == id:
			return actor
	return {}


func _damage(run, actor: Dictionary, coefficient: float, kind: String, context: Dictionary) -> float:
	if run.has_method("resolve_fire_status_hit"):
		return float(run.resolve_fire_status_hit(actor, coefficient, kind, context))
	var before: float = float(actor.health)
	# Legacy standalone spell harnesses have no fire-status resolver. Retain
	# their real base damage path while never rolling a critical for status.
	run.damage_enemy(actor, float(run.player.attack) * coefficient, kind)
	return before - maxf(0.0, float(actor.health))


func _active(run) -> bool:
	return run.phase == "combat" and not bool(run.paused) and float(run.player.health) > 0.0


func _emit(run, kind: String, data: Dictionary) -> void:
	if run.has_method("_emit"):
		run._emit(kind, data, 0.5)
