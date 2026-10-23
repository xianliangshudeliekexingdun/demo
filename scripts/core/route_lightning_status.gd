extends RefCounted
## Per-enemy conductivity and lightning vulnerability, driven only by combat time.

var clock: float = 0.0
var states: Dictionary = {}
var vulnerabilities: Dictionary = {}
var mechanics: Dictionary = {}


func configure(source: Dictionary) -> void:
	mechanics = source.duplicate(true)
	clear()


func clear() -> void:
	clock = 0.0
	states.clear()
	vulnerabilities.clear()


func advance(run, dt: float) -> void:
	clock += maxf(0.0, dt)
	for key in states.keys():
		if float(states[key].until) <= clock + 0.000001 or _actor(run, int(key)).is_empty():
			states.erase(key)
	for key in vulnerabilities.keys():
		if float(vulnerabilities[key].until) <= clock + 0.000001 or _actor(run, int(key)).is_empty():
			vulnerabilities.erase(key)


func remove_actor(actor_id: int) -> void:
	states.erase(actor_id)
	vulnerabilities.erase(actor_id)


func has_conductive(actor_id: int) -> bool:
	return states.has(actor_id) and float(states[actor_id].until) > clock + 0.000001


func consume_conductive(actor_id: int) -> bool:
	# Core consumption removes only conductivity; independent vulnerability survives.
	if not has_conductive(actor_id): return false
	states.erase(actor_id)
	return true


func state_for(actor_id: int) -> Dictionary:
	if not has_conductive(actor_id):
		return {}
	var result: Dictionary = states[actor_id].duplicate(true)
	result["remaining"] = maxf(0.0, float(result.until) - clock)
	result["age"] = maxf(0.0, clock - float(result.since))
	return result


func conductive_age(actor_id: int) -> float:
	return maxf(0.0, clock - float(states[actor_id].since)) if has_conductive(actor_id) else 0.0


func apply(run, actor: Dictionary, duration: float) -> bool:
	if actor.is_empty() or float(actor.get("health", 0.0)) <= 0.0 or duration <= 0.0 or run.phase != "combat":
		return false
	var actor_id: int = int(actor.id)
	var since: float = float(states[actor_id].since) if has_conductive(actor_id) else clock
	states[actor_id] = {"actor_id": actor_id, "until": clock + duration, "since": since}
	return true


func apply_vulnerability(actor: Dictionary, amount: float, duration: float) -> bool:
	if actor.is_empty() or float(actor.get("health", 0.0)) <= 0.0 or amount <= 0.0 or duration <= 0.0:
		return false
	vulnerabilities[int(actor.id)] = {"amount": amount, "until": clock + duration}
	return true


func target_vulnerability(actor: Dictionary) -> float:
	if actor.is_empty():
		return 0.0
	var value: Dictionary = vulnerabilities.get(int(actor.id), {})
	return float(value.get("amount", 0.0)) if float(value.get("until", -INF)) > clock + 0.000001 else 0.0


func snapshot(run) -> Array:
	var result: Array = []
	if run == null:
		return result
	for actor in run.actors:
		if float(actor.get("health", 0.0)) <= 0.0:
			continue
		var actor_id: int = int(actor.id)
		var conductive: Dictionary = state_for(actor_id)
		var vulnerability: Dictionary = vulnerabilities.get(actor_id, {})
		if conductive.is_empty() and target_vulnerability(actor) <= 0.0:
			continue
		result.append({"actor_id": actor_id, "pos": actor.pos,
			"remaining": float(conductive.get("remaining", 0.0)), "age": float(conductive.get("age", 0.0)),
			"vulnerability": target_vulnerability(actor),
			"vulnerability_remaining": maxf(0.0, float(vulnerability.get("until", clock)) - clock)})
	return result


func _actor(run, actor_id: int) -> Dictionary:
	for actor in run.actors:
		if int(actor.id) == actor_id and float(actor.get("health", 0.0)) > 0.0:
			return actor
	return {}
