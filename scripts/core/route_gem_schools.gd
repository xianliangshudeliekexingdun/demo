extends RefCounted
## Four school cores. Numeric defaults are owned by magic_gems_v1.json.
## Callbacks operate on real releases/actions/sources; visuals consume snapshots only.

var core: String = ""
var spec: Dictionary = {}
var clock: float = 0.0
var lightning_charges: int = 0
var lightning_stored: float = 0.0
var lightning_budget: float = 0.0
var lightning_last: float = -INF
var lightning_gate: float = -INF
var lightning_seen: Dictionary = {}
var lightning_pending: Array = []
var wind_layers: int = 0
var wind_distance: float = 0.0
var wind_flow_until: float = 0.0
var wind_last_motion: float = -INF
var wind_decay_started: float = -INF
var wind_next_decay: float = INF
var earth_anchor: Dictionary = {}
var earth_dwell: float = 0.0
var earth_mature: bool = false
var earth_next_pulse: float = INF
var earth_left_at: float = -INF
var spirit_points: int = 0
var spirit_last_family: String = ""
var spirit_last: float = -INF


func configure(active_core: String, values: Dictionary) -> void:
	core = active_core
	spec = values.duplicate(true)
	clear()


func clear() -> void:
	clock = 0.0
	_clear_lightning()
	lightning_seen.clear()
	lightning_pending.clear()
	wind_layers = 0
	wind_distance = 0.0
	wind_flow_until = 0.0
	wind_last_motion = -INF
	wind_decay_started = -INF
	wind_next_decay = INF
	_clear_earth()
	_clear_spirit()


func advance(run, dt: float, combat_clock: float) -> void:
	if not _active(run) or dt <= 0.0: return
	clock = combat_clock
	match core:
		"lightning":
			if lightning_charges > 0 and clock >= lightning_last + float(spec.idle_timeout) - 0.000001:
				_clear_lightning()
			_prune_lightning_casts(run)
			var future: Array = []
			for item in lightning_pending:
				if clock + 0.000001 >= float(item.at):
					_lightning_land(run, item)
					if not _active(run):
						lightning_pending.clear()
						return
				else: future.append(item)
			lightning_pending = future
		"wind": _advance_wind()
		"spirit":
			if spirit_points > 0 and clock >= spirit_last + float(spec.idle_timeout) - 0.000001:
				_clear_spirit()


func _clear_lightning() -> void:
	lightning_charges = 0
	lightning_stored = 0.0
	lightning_budget = 0.0
	lightning_last = -INF
	lightning_gate = -INF


func _prune_lightning_casts(run) -> void:
	var active: Dictionary = {}
	var lightning = run._spell_combat.lightning
	for list in [lightning.projectiles, lightning.zones, lightning.pending]:
		for item in list:
			var context: Dictionary = item.get("context", {})
			if context.has("cast_id"): active[int(context.cast_id)] = true
	for cast_id in lightning_seen.keys():
		if not active.has(cast_id): lightning_seen.erase(cast_id)


func lightning_cast(run, spell: Dictionary, target: Dictionary, context: Dictionary) -> void:
	if core != "lightning" or not _active(run) or not bool(context.get("natural", false)) or str(spell.id) not in ["L01", "L02", "L03", "L04", "L05", "L06", "L07", "L08"]: return
	if lightning_charges < int(spec.charge_count): return
	var status = run._spell_combat.lightning.status
	var main: Dictionary = target
	var level: Dictionary = context.lightning_level
	if str(spell.id) in ["L05", "L06"]:
		var center: Vector2 = run.player.pos if str(spell.id) == "L06" else spell.get("locked_pos", target.pos)
		main = {}
		for actor in _targets(run, center, float(level.radius), run.actors.size(), [], true):
			if status.has_conductive(int(actor.id)):
				main = actor
				break
	if main.is_empty() or float(main.get("health", 0.0)) <= 0.0 or not status.has_conductive(int(main.id)): return
	var selected: Array = [main]
	for actor in _targets(run, main.pos, float(spec.radius), run.actors.size(), [int(main.id)]):
		if selected.size() > int(spec.neighbor_cap): break
		if status.has_conductive(int(actor.id)): selected.append(actor)
	var locked: Array = []
	for index in selected.size():
		var actor: Dictionary = selected[index]
		locked.append({"actor_id": int(actor.id), "pos": actor.pos,
			"amount": lightning_stored * (1.0 if index == 0 else float(spec.neighbor_scale))})
		status.consume_conductive(int(actor.id))
	context["gem_lightning_spend"] = true
	lightning_seen[int(context.cast_id)] = true
	lightning_pending.append({"at": clock + float(spec.discharge_delay), "targets": locked})
	run._emit("gem_lightning", {"phase": "preview", "pos": main.pos, "targets": locked.duplicate(true), "radius": spec.landing_radius}, float(spec.discharge_delay))
	_clear_lightning()


func lightning_hit(run, actor: Dictionary, actual: float, context: Dictionary, pre_conductive: bool) -> void:
	if core != "lightning" or not _active(run) or actual <= 0.0 or not bool(context.get("natural", false)) or bool(context.get("gem_lightning_spend", false)): return
	var cast_id: int = int(context.get("cast_id", -1))
	if cast_id < 0 or lightning_seen.has(cast_id): return
	# First *effective body* hit spends this cast's check, even if unmarked/gated/full.
	lightning_seen[cast_id] = true
	if not pre_conductive or lightning_charges >= int(spec.charge_count) or clock < lightning_gate - 0.000001: return
	if lightning_charges == 0: lightning_budget = float(run.player.attack) * float(spec.stored_attack_cap)
	lightning_stored = minf(lightning_budget, lightning_stored + actual * float(spec.charge_damage_fraction))
	lightning_charges += 1
	lightning_last = clock
	lightning_gate = clock + float(spec.charge_gate)
	run._emit("gem_lightning_charge", {"pos": actor.pos, "charges": lightning_charges, "amount": lightning_stored}, float(run._spell_combat.lightning.effects.mark))


func _lightning_land(run, item: Dictionary) -> void:
	if not _active(run): return
	var hits: Array = []
	for lock in item.targets:
		var actor: Dictionary = _actor(run, int(lock.actor_id))
		if actor.is_empty() or actor.pos.distance_to(lock.pos) > float(spec.landing_radius) + 0.000001 or not run.line_is_clear(lock.pos, actor.pos): continue
		var amount: float = run.resolve_fixed_item_hit(actor, float(lock.amount), "gem_lightning")
		if amount > 0.0: hits.append(lock.duplicate(true))
		if not _active(run): break
	if not hits.is_empty():
		run._emit("gem_lightning", {"phase": "impact", "pos": hits[0].pos, "targets": hits, "radius": spec.landing_radius}, float(run._spell_combat.lightning.effects.impact))


func wind_motion(run, length: float) -> void:
	if core != "wind" or not _active(run) or length <= 0.000001: return
	wind_last_motion = clock
	if clock >= wind_flow_until - 0.000001: return
	wind_decay_started = -INF
	wind_next_decay = INF
	if wind_layers >= int(spec.max_stacks):
		wind_distance = 0.0
		return
	wind_distance += length
	while wind_layers < int(spec.max_stacks) and wind_distance >= float(spec.distance_per_stack) - 0.000001:
		wind_distance = maxf(0.0, wind_distance - float(spec.distance_per_stack))
		wind_layers += 1
		run._emit("gem_wind", {"pos": run.player.pos, "layers": wind_layers}, float(run._spell_combat.wind.effects.mark))
	if wind_layers == int(spec.max_stacks): wind_distance = 0.0


func _advance_wind() -> void:
	var stopped: float = maxf(wind_last_motion, 0.0)
	var invalid_since: float = minf(stopped, wind_flow_until)
	if clock < wind_flow_until - 0.000001 and clock < stopped + float(spec.decay_delay) - 0.000001:
		wind_decay_started = -INF
		wind_next_decay = INF
		return
	if wind_decay_started == -INF:
		wind_decay_started = invalid_since
		wind_next_decay = invalid_since + float(spec.decay_delay)
	while (wind_layers > 0 or wind_distance > 0.0) and clock + 0.000001 >= wind_next_decay:
		wind_layers = maxi(0, wind_layers - 1)
		wind_distance = 0.0
		wind_next_decay += float(spec.decay_interval)


func wind_cast(run, id: String, level: Dictionary, context: Dictionary) -> void:
	if core != "wind" or not _active(run) or not bool(context.get("natural", false)) or id not in ["W01", "W02", "W03", "W04", "W05", "W06", "W07", "W08"]: return
	var multiplier: float = 1.0 + wind_layers * float(spec.body_per_stack)
	context["gem_wind_multiplier"] = multiplier
	context["damage_scale"] = float(context.get("damage_scale", 1.0)) * multiplier
	var geometry: float = 1.0 + wind_layers * float(spec.size_per_stack)
	if id in ["W01", "W02", "W03", "W07"]: level.width = float(level.width) * geometry
	elif id in ["W06", "W08"]:
		if id == "W06": context["gem_wind_followup_radius"] = float(level.radius)
		level.radius = float(level.radius) * geometry
	wind_flow_until = clock + float(spec.flow_duration)
	if clock < wind_last_motion + float(spec.decay_delay) - 0.000001:
		wind_decay_started = -INF
		wind_next_decay = INF


func _clear_earth() -> void:
	earth_anchor.clear()
	earth_dwell = 0.0
	earth_mature = false
	earth_next_pulse = INF
	earth_left_at = -INF


func earth_source_removed(source_id: int) -> void:
	if core == "earth" and int(earth_anchor.get("id", -1)) == source_id: _clear_earth()


func earth_tick(run, dt: float) -> void:
	if core != "earth" or not _active(run) or dt <= 0.0: return
	var earth = run._spell_combat.earth
	if not earth_anchor.is_empty():
		var still_registered: bool = false
		for candidate in earth.constructs:
			if int(candidate.id) == int(earth_anchor.id) and float(candidate.expires) > float(earth.clock) + 0.000001:
				still_registered = true
				break
		if not still_registered: _clear_earth()
	if earth_anchor.is_empty():
		var found: Array = []
		for candidate in earth.constructs:
			if str(candidate.spell_id) in ["R03", "R04", "R09"] and float(candidate.expires) > float(earth.clock) + 0.000001 and _earth_inside(run, candidate): found.append(candidate)
		found.sort_custom(func(a, b): return _distance_before(a, b, run.player.pos))
		if not found.is_empty(): earth_anchor = {"id": int(found[0].id), "pos": found[0].pos}
		return # Initial selection does not count a tick which preceded its existence.
	if not _earth_inside(run, earth_anchor):
		if earth_left_at == -INF: earth_left_at = clock
		while earth_mature and clock + 0.000001 >= earth_next_pulse: earth_next_pulse += float(spec.pulse_interval)
		if clock >= earth_left_at + float(spec.leave_grace) - 0.000001: _clear_earth()
		return
	earth_left_at = -INF
	if not earth_mature:
		earth_dwell += dt
		if earth_dwell + 0.000001 < float(spec.mature_duration): return
		earth_dwell = float(spec.mature_duration)
		earth_mature = true
		earth_next_pulse = clock
	while _active(run) and earth_mature and clock + 0.000001 >= earth_next_pulse:
		earth_next_pulse += float(spec.pulse_interval)
		var selected: Array = _targets(run, earth_anchor.pos, float(spec.pulse_radius), int(spec.target_cap))
		var ids: Array = []
		for actor in selected:
			ids.append(int(actor.id))
			run.gem_derived_hit(actor, float(spec.pulse_coefficient), "earth", "gem_earth")
			if not _active(run): break
		if _active(run): run._emit("gem_earth", {"pos": earth_anchor.pos, "source_id": earth_anchor.id, "radius": spec.pulse_radius, "targets": ids}, float(earth.effects.impact))


func _earth_inside(run, anchor: Dictionary) -> bool:
	return run.player.pos.distance_to(anchor.pos) <= float(spec.anchor_radius) + 0.000001 and run.line_is_clear(run.player.pos, anchor.pos)


func _clear_spirit() -> void:
	spirit_points = 0
	spirit_last_family = ""
	spirit_last = -INF


func spirit_presence(run) -> void:
	if core != "spirit": return
	for unit in run._spell_combat.spirit_school.units:
		if not bool(unit.get("consumed", false)): return
	_clear_spirit()


func spirit_action(run, family: String, contacts: Array) -> void:
	if core != "spirit" or not _active(run) or family not in ["S02", "S03", "S04"]: return
	var success: bool = false
	for contact in contacts:
		if float(contact.actual) > 0.0: success = true; break
	if not success: return
	var ready: bool = spirit_points >= int(spec.charge_count)
	if ready:
		spirit_points = 0
		var hits: Array = []
		for contact in contacts:
			var actor: Dictionary = contact.actor
			if float(contact.actual) <= 0.0 or float(actor.health) <= 0.0: continue
			var amount: float = float(contact.base) * float(spec.bonus_fraction)
			if run.resolve_fixed_item_hit(actor, amount, "gem_spirit") > 0.0:
				hits.append({"actor_id": int(actor.id), "pos": actor.pos, "amount": amount})
			if not _active(run): break
		if not hits.is_empty(): run._emit("gem_spirit", {"pos": hits[0].pos, "targets": hits, "family": family}, float(run._spell_combat.spirit_school.effects.beam))
	else:
		spirit_points = mini(int(spec.charge_count), spirit_points + int(spec.base_charge) + (int(spec.alternate_charge) if not spirit_last_family.is_empty() and spirit_last_family != family else 0))
	if _active(run):
		spirit_last_family = family
		spirit_last = clock


func snapshot() -> Dictionary:
	return {"lightning_charges": lightning_charges, "lightning_stored": lightning_stored,
		"lightning_idle_remaining": maxf(0.0, lightning_last + float(spec.get("idle_timeout", 0.0)) - clock),
		"wind_layers": wind_layers, "wind_distance": wind_distance, "wind_flow_until": wind_flow_until,
		"wind_decay_remaining": maxf(0.0, wind_next_decay - clock) if is_finite(wind_next_decay) else 0.0,
		"moving": clock - wind_last_motion < 0.000001,
		"earth_anchor_id": int(earth_anchor.get("id", -1)), "earth_anchor_pos": earth_anchor.get("pos", Vector2.ZERO),
		"earth_mature": earth_mature, "earth_progress": earth_dwell / float(spec.mature_duration) if core == "earth" else 0.0,
		"earth_pulse_remaining": maxf(0.0, earth_next_pulse - clock) if is_finite(earth_next_pulse) else 0.0,
		"earth_leave_remaining": maxf(0.0, earth_left_at + float(spec.get("leave_grace", 0.0)) - clock),
		"spirit_points": spirit_points, "spirit_last_family": spirit_last_family,
		"school_pending_count": lightning_pending.size()}


func _targets(run, point: Vector2, radius: float, cap: int, excluded: Array = [], include_body: bool = false) -> Array:
	var found: Array = []
	for actor in run.actors:
		if int(actor.id) not in excluded and float(actor.get("health", 0.0)) > 0.0 and point.distance_to(actor.pos) <= radius + (float(actor.radius) if include_body else 0.0) + 0.000001 and run.line_is_clear(point, actor.pos): found.append(actor)
	found.sort_custom(func(a, b): return _distance_before(a, b, point))
	return found.slice(0, mini(cap, found.size()))


func _distance_before(a: Dictionary, b: Dictionary, point: Vector2) -> bool:
	var ad: float = point.distance_squared_to(a.pos)
	var bd: float = point.distance_squared_to(b.pos)
	return ad < bd if not is_equal_approx(ad, bd) else int(a.id) < int(b.id)


func _actor(run, id: int) -> Dictionary:
	for actor in run.actors:
		if int(actor.id) == id and float(actor.get("health", 0.0)) > 0.0: return actor
	return {}


func _active(run) -> bool:
	return run.phase == "combat" and not run.paused and float(run.player.health) > 0.0
