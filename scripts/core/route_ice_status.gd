extends RefCounted
## One frost stage per actor. All deadlines use this room's combat clock.

var clock: float = 0.0
var states: Dictionary = {}
var parameters: Dictionary = {}
var effects: Dictionary = {}
var _next_token: int = 1
var _consumed: Dictionary = {}
var _frozen_frame: Dictionary = {}


func configure(mechanics: Dictionary, visual_effects: Dictionary = {}) -> void:
	parameters = mechanics.duplicate(true)
	effects = visual_effects.duplicate(true)
	clear()


func clear() -> void:
	clock = 0.0
	states.clear()
	_consumed.clear()
	_frozen_frame.clear()
	_next_token = 1


func category(actor: Dictionary) -> String:
	var configured: String = str(parameters.get("control_class_by_type", {}).get(str(actor.get("type_id", "")), ""))
	if not configured.is_empty():
		return configured
	if str(actor.get("type_id", "")) == "EL02_GUARD":
		return "fixed_strong"
	return "elite" if bool(actor.get("elite", false)) or str(actor.get("type_id", "")).begins_with("EL") else "normal"


func control_coefficient(actor: Dictionary) -> float:
	var value: float = float(actor.get("ice_control_coefficient", actor.get("combat_spec", {}).get("ice_control_coefficient", parameters.frost.control_duration_coefficients[category(actor)])))
	return clampf(value, 0.0, 1.0)


func _fresh(actor_id: int) -> Dictionary:
	return {"actor_id": actor_id, "stacks": 0, "frost_until": 0.0, "ready_until": 0.0,
		"frozen_until": 0.0, "immunity_until": 0.0, "token": -1, "short_slows": {}}


func state_for(actor_id: int) -> Dictionary:
	if not states.has(actor_id):
		return {}
	var state: Dictionary = states[actor_id].duplicate(true)
	var ready: float = maxf(0.0, float(state.ready_until) - clock)
	var frozen: float = maxf(0.0, float(state.frozen_until) - clock)
	state["stage"] = "frozen" if frozen > 0.000001 else ("brittle" if ready > 0.000001 else ("frost" if int(state.stacks) > 0 else "none"))
	state["expires"] = float(state.ready_until) if ready > 0.000001 else float(state.frost_until)
	state["remaining"] = maxf(0.0, float(state.expires) - clock)
	state["freeze_remaining"] = frozen
	state["ready"] = ready > 0.000001
	state["window_remaining"] = ready
	state["immunity_remaining"] = maxf(0.0, float(state.immunity_until) - clock) if frozen <= 0.000001 else 0.0
	state.erase("short_slows")
	return state


func capture_ready(actor_id: int) -> Dictionary:
	var state: Dictionary = state_for(actor_id)
	return state if not state.is_empty() and float(state.ready_until) > clock + 0.000001 and int(state.token) >= 0 else {}


func is_frozen(actor_id: int) -> bool:
	return states.has(actor_id) and float(states[actor_id].frozen_until) > clock + 0.000001


func is_immune(actor_id: int) -> bool:
	return states.has(actor_id) and float(states[actor_id].immunity_until) > clock + 0.000001 and not is_frozen(actor_id)


func frozen_frame_time(actor_id: int) -> float:
	return float(_frozen_frame.get(actor_id, 0.0))


func advance(run, dt: float) -> void:
	var previous: float = clock
	clock += maxf(0.0, dt)
	_frozen_frame.clear()
	var alive: Dictionary = {}
	for actor in run.actors:
		if float(actor.health) > 0.0:
			alive[int(actor.id)] = actor
	for actor_id in states.keys():
		if not alive.has(actor_id):
			states.erase(actor_id)
			continue
		var state: Dictionary = states[actor_id]
		var frozen_until: float = float(state.frozen_until)
		_frozen_frame[actor_id] = maxf(0.0, minf(clock, frozen_until) - previous)
		if frozen_until > previous + 0.000001 and frozen_until <= clock + 0.000001:
			run._emit("ice_thawed", {"actor_id": actor_id, "pos": alive[actor_id].pos}, float(effects.get("hit", 0.0)))
		if float(state.ready_until) > 0.0 and float(state.ready_until) <= clock + 0.000001:
			var released_token: int = int(state.token)
			_consumed[int(state.token)] = true
			state.ready_until = 0.0
			state.frost_until = 0.0
			state.stacks = 0
			state.token = -1
			if run.has_method("gem_core"):
				run._gem_combat.release_coffin(run, int(actor_id), released_token, alive[actor_id].pos)
				if float(alive[actor_id].health) <= 0.0: continue
		elif float(state.ready_until) <= 0.0 and float(state.frost_until) <= clock + 0.000001:
			state.stacks = 0
			state.frost_until = 0.0
		for source in state.short_slows.keys():
			if float(state.short_slows[source].until) <= clock + 0.000001:
				state.short_slows.erase(source)
		alive[actor_id]["ice_frozen"] = is_frozen(int(actor_id))
		if int(state.stacks) == 0 and float(state.immunity_until) <= clock + 0.000001 and state.short_slows.is_empty():
			states.erase(actor_id)


func apply_frost(run, actor: Dictionary, amount: int = 1, context: Dictionary = {}) -> bool:
	if not _active(run, actor) or amount <= 0:
		return false
	var id: int = int(actor.id)
	var state: Dictionary = states.get(id, _fresh(id))
	if float(state.ready_until) > clock + 0.000001:
		return false
	state.stacks = mini(int(parameters.frost.max_stacks), int(state.stacks) + amount)
	var expiry: float = float(parameters.frost.expiry)
	if run._artifact_combat != null and run._artifact_combat.has_method("ice_frost_expiry"):
		expiry = run._artifact_combat.ice_frost_expiry(run)
	var mastery: Dictionary = run._owned_spell("I10")
	if not mastery.is_empty():
		expiry = maxf(expiry, float(run.get_spell_stats(mastery).level.get("frost_expiry", expiry)))
	state.frost_until = maxf(float(state.frost_until), clock + expiry)
	states[id] = state
	run._emit("ice_frost", {"actor_id": id, "pos": actor.pos, "stacks": state.stacks, "spell_id": context.get("spell_id", "")}, float(effects.get("hit", 0.0)))
	if int(state.stacks) >= int(parameters.frost.max_stacks):
		return force_ready(run, actor, float(parameters.frost.base_freeze), context)
	return true


func force_ready(run, actor: Dictionary, freeze_base: float, context: Dictionary = {}) -> bool:
	if not _active(run, actor):
		return false
	var id: int = int(actor.id)
	var state: Dictionary = states.get(id, _fresh(id))
	if float(state.ready_until) > clock + 0.000001:
		return false
	var duration: float = float(parameters.frost.ready_window)
	if run._spell_combat != null and run._spell_combat.ice != null:
		duration = run._spell_combat.ice.ready_duration(run)
	var freeze: float = 0.0 if float(state.immunity_until) > clock + 0.000001 else freeze_base * control_coefficient(actor)
	state.stacks = int(parameters.frost.max_stacks)
	state.frost_until = 0.0
	state.ready_until = clock + duration
	state.frozen_until = clock + freeze if freeze > 0.0 else 0.0
	if freeze > 0.0:
		state.immunity_until = clock + freeze + float(parameters.frost.post_freeze_immunity)
	state.token = _next_token
	_next_token += 1
	states[id] = state
	actor["ice_frozen"] = freeze > 0.000001
	run._emit("ice_window", {"actor_id": id, "pos": actor.pos, "freeze_duration": freeze, "window_duration": duration, "token": state.token, "spell_id": context.get("spell_id", "")}, float(effects.get("impact", 0.0)))
	if run._artifact_combat != null and run._artifact_combat.has_method("on_ice_window_created"):
		run._artifact_combat.on_ice_window_created(run, actor, context, state_for(id))
	if run._spell_combat != null and run._spell_combat.ice != null:
		run._spell_combat.ice.growth.on_window_created(run, actor, context)
	return true


func consume_ready(run, actor: Dictionary, token: int, context: Dictionary = {}, proof: Dictionary = {}) -> Dictionary:
	if run.phase != "combat" or token < 0 or _consumed.has(token):
		return {}
	var id: int = int(actor.get("id", -1))
	var state: Dictionary = states.get(id, {})
	var valid: bool = not state.is_empty() and int(state.token) == token and float(state.ready_until) > clock + 0.000001
	# A parent hit may kill the actor and synchronously clear its state. Only
	# that hit's captured token can still pay its one finite neighboring shard.
	if not valid:
		valid = float(actor.get("health", 0.0)) <= 0.0 and int(proof.get("actor_id", -2)) == id and int(proof.get("token", -2)) == token and float(proof.get("ready_until", 0.0)) > clock + 0.000001
	if not valid:
		return {}
	_consumed[token] = true
	var consumed: Dictionary = state_for(id) if not state.is_empty() else proof.duplicate(true)
	if float(actor.get("health", 0.0)) > 0.0:
		if float(state.frozen_until) > clock + 0.000001:
			state.immunity_until = clock + float(parameters.frost.post_freeze_immunity)
		state.frozen_until = 0.0
		state.ready_until = 0.0
		state.frost_until = 0.0
		state.stacks = 0
		state.token = -1
		actor["ice_frozen"] = false
	consumed["pos"] = actor.get("pos", Vector2.ZERO)
	consumed["spell_id"] = context.get("spell_id", "I07")
	if run.has_method("gem_core"): run._gem_combat.ice_released(actor, token)
	return consumed


func apply_short_slow(run, actor: Dictionary, amount: float, duration: float, source: String) -> void:
	if not _active(run, actor) or amount <= 0.0 or duration <= 0.0:
		return
	var id: int = int(actor.id)
	var state: Dictionary = states.get(id, _fresh(id))
	state.short_slows[source] = {"amount": amount, "until": clock + duration}
	states[id] = state


func slow_amount(actor: Dictionary) -> float:
	var state: Dictionary = states.get(int(actor.get("id", -1)), {})
	if state.is_empty():
		return 0.0
	var kind: String = category(actor)
	var amount: float = float(parameters.frost.slow_per_stack[kind]) * int(state.stacks)
	for entry in state.short_slows.values():
		if float(entry.until) > clock + 0.000001:
			amount = maxf(amount, float(entry.amount))
	return minf(amount, float(parameters.shared_slow_caps[kind]))


func remove_actor(actor_id: int) -> void:
	states.erase(actor_id)
	_frozen_frame.erase(actor_id)


func snapshot(run) -> Array:
	var result: Array = []
	if run == null:
		return result
	for actor in run.actors:
		if float(actor.health) <= 0.0 or not states.has(int(actor.id)):
			continue
		var state: Dictionary = state_for(int(actor.id))
		state["slow_amount"] = slow_amount(actor)
		result.append(state)
	return result


func _active(run, actor: Dictionary) -> bool:
	return run.phase == "combat" and not run.paused and float(run.player.health) > 0.0 and not actor.is_empty() and float(actor.get("health", 0.0)) > 0.0
