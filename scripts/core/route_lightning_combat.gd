extends RefCounted
## Lightning rules and finite transactions. Presentation only consumes snapshots.

const LightningStatus = preload("res://scripts/core/route_lightning_status.gd")
var status = LightningStatus.new()
var mechanics: Dictionary = {}
var effects: Dictionary = {}
var source_spells: Dictionary = {}
var zones: Array = []
var pending: Array = []
var projectiles: Array = []
var _next_id: int = 1
var _last_tick: float = -INF


func configure(source: Dictionary) -> Dictionary:
	if not source.get("mechanics") is Dictionary or not source.get("spells") is Dictionary or source.spells.size() != 10:
		return {"ok": false, "error": "正式雷系源缺失或数量无效。"}
	mechanics = source.mechanics.duplicate(true)
	effects = source.get("effects", {}).duplicate(true)
	source_spells = source.spells.duplicate(true)
	if not mechanics.has_all(["conductive", "resonance", "initial_ids", "overload"]):
		return {"ok": false, "error": "正式雷系机制参数缺失。"}
	for key in ["hit", "beam", "arc", "ring", "impact", "mark", "shield"]:
		if not _positive(effects.get(key)):
			return {"ok": false, "error": "正式雷系表现时长无效：" + key}
	for number in range(1, 11):
		var id: String = "L%02d" % number
		var spec: Dictionary = source_spells.get(id, {})
		if str(spec.get("school", "")) != "lightning" or not spec.get("levels") is Array or spec.levels.size() != 3:
			return {"ok": false, "error": "正式雷系三级源无效：" + id}
		for level in spec.levels:
			if not level is Dictionary or not level.has("cooldown") or not is_finite(float(level.cooldown)) or float(level.cooldown) < 0.0:
				return {"ok": false, "error": "正式雷系冷却源无效：" + id}
	status.configure(mechanics)
	stop_room()
	return {"ok": true, "error": ""}


func _positive(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0.0


func stop_room() -> void:
	zones.clear()
	pending.clear()
	projectiles.clear()
	status.clear()
	_last_tick = -INF
	_next_id = 1


func before_tick(run, dt: float) -> void:
	if not _active(run) or absf(_last_tick - float(run.time)) <= 0.000000001:
		return
	_last_tick = float(run.time)
	status.advance(run, dt)


func is_lightning_spell(id: String) -> bool:
	return source_spells.has(id)


func spell_count(run) -> int:
	var distinct: Dictionary = {}
	for spell in run.spells:
		if is_lightning_spell(str(spell.id)):
			distinct[str(spell.id)] = true
	return distinct.size()


func school_bonus(run) -> float:
	var result: float = _mastery_value(run, "school_damage_bonus")
	if spell_count(run) >= int(mechanics.resonance.distinct_spells):
		result += float(mechanics.resonance.school_damage_bonus)
	return result


func cooldown_bonus(run) -> float:
	return float(mechanics.resonance.school_cdr) if spell_count(run) >= int(mechanics.resonance.distinct_spells) else 0.0


func target_vulnerability(actor: Dictionary) -> float:
	return status.target_vulnerability(actor)


func remove_actor_status(actor_id: int) -> void:
	status.remove_actor(actor_id)


func _mastery_value(run, key: String) -> float:
	var mastery: Dictionary = run._owned_spell("L10")
	return float(run.get_spell_stats(mastery).level.get(key, 0.0)) if not mastery.is_empty() else 0.0


func get_snapshot(run) -> Dictionary:
	return {"lightning_states": status.snapshot(run), "lightning_zones": zones.duplicate(true),
		"lightning_pending": pending.duplicate(true), "lightning_projectiles": projectiles.duplicate(true),
		"lightning_clock": status.clock}


func legal_target(run, spell: Dictionary, stats: Dictionary) -> Dictionary:
	if not _active(run) or str(stats.kind) == "passive":
		return {}
	var id: String = str(spell.id)
	var level: Dictionary = stats.level
	if id == "L09":
		if float(run.player.shield) >= float(run.player.max_shield) - 0.000001:
			return {}
		var enemy: Array = _targets(run, run.player.pos, float(level.enemy_range))
		return {"id": -1, "pos": run.player.pos} if not enemy.is_empty() else {}
	var actors: Array = _targets(run, run.player.pos, float(level.get("range", level.get("radius", 0.0))))
	if id == "L02":
		actors.sort_custom(func(a, b): return _health_before(a, b, run.player.pos))
	elif id == "L07":
		actors.sort_custom(func(a, b):
			var ac: bool = status.has_conductive(int(a.id))
			var bc: bool = status.has_conductive(int(b.id))
			if ac != bc: return ac
			var ae: bool = bool(a.get("elite", false)) or str(a.get("type", "")).begins_with("EL") or bool(a.get("boss", false))
			var be: bool = bool(b.get("elite", false)) or str(b.get("type", "")).begins_with("EL") or bool(b.get("boss", false))
			if ae != be: return ae
			return _health_before(a, b, run.player.pos))
	elif id == "L08":
		var sizes: Dictionary = {}
		for actor in actors:
			sizes[int(actor.id)] = _component(run, actor, _mastery_value(run, "both_conductive_range_add")).size()
		actors.sort_custom(func(a, b):
			var ac: int = int(sizes[int(a.id)])
			var bc: int = int(sizes[int(b.id)])
			return ac > bc if ac != bc else _health_before(a, b, run.player.pos))
	return actors[0] if not actors.is_empty() else {}


func finish_target(run, spell: Dictionary, stats: Dictionary) -> Dictionary:
	if str(spell.id) in ["L06", "L09"]:
		return legal_target(run, spell, stats)
	var original: Dictionary = _actor(run, int(spell.get("target_id", -1)))
	return original if not original.is_empty() and run.player.pos.distance_to(original.pos) <= float(stats.level.range) + 0.000001 and run.line_is_clear(run.player.pos, original.pos) else {}


func cast(run, spell: Dictionary, stats: Dictionary, target: Dictionary, source_context: Dictionary) -> void:
	if not _active(run):
		return
	var level: Dictionary = stats.level.duplicate(true)
	var context: Dictionary = source_context.duplicate(true)
	context.merge({"kind": "direct", "lightning_direct": true, "lightning_source_kind": stats.kind,
		"lightning_level": level, "spell_level": int(spell.level), "school": "lightning",
		"connection_add": _mastery_value(run, "both_conductive_range_add")}, true)
	var id: String = str(spell.id)
	# Spend before L07 checks/queues old conditions or L08 captures network members.
	if run.has_method("gem_core"): run._gem_combat.schools.lightning_cast(run, spell, target, context)
	match id:
		"L01":
			projectiles.append({"id": _new_id(), "spell_id": id, "kind": "lightning_bolt", "pos": run.player.pos,
				"from": run.player.pos, "direction": (target.pos - run.player.pos).normalized(),
				"speed": float(level.speed), "radius": float(level.radius), "range": float(level.range),
				"travelled": 0.0, "context": context})
		"L02":
			_cast_lance(run, target, context)
		"L03":
			_chain_hit(run, {"kind": "chain", "target_id": int(target.id), "visited": [], "ordinal": 0,
				"context": context, "at": status.clock})
		"L04":
			var point: Vector2 = target.pos
			_direct_hit(run, target, float(level.coefficient), context)
			var count: int = 0
			for neighbor in _targets(run, point, float(level.spread_range)):
				if int(neighbor.id) == int(target.id) or status.has_conductive(int(neighbor.id)):
					continue
				if count >= int(level.neighbor_cap): break
				count += 1
				_apply_conductive(run, neighbor, float(level.conductive_duration))
		"L05":
			_cast_cloud(run, spell.get("locked_pos", target.pos), context)
		"L06":
			var center: Vector2 = run.player.pos
			_ring(run, center, float(level.coefficient), context, true)
			if float(level.get("followup_coefficient", 0.0)) > 0.0:
				_queue(status.clock + float(level.followup_delay), "ring_followup", {"pos": center, "context": context})
		"L07":
			_queue(status.clock + float(level.impact_delay), "judgment", {"actor_id": int(target.id), "pos": target.pos, "context": context})
			run._emit("lightning_judgment_flight", {"pos": target.pos, "radius": level.radius, "actor_id": target.id, "spell_id": id}, float(level.impact_delay))
		"L08":
			var members: Array = _component(run, target, float(context.connection_add))
			_chain_hit(run, {"kind": "network", "target_id": int(target.id), "visited": [], "ordinal": 0,
				"members": members, "overloaded": members.size() >= int(mechanics.overload.minimum_precast_conductive_component),
				"context": context, "at": status.clock})
		"L09":
			var restored: float = run.restore_player_shield(float(level.shield_restore), id)
			if restored > 0.0:
				var count: int = 0
				for neighbor in _targets(run, run.player.pos, float(level.conductive_range)):
					if count >= int(level.conductive_target_cap): break
					count += 1
					_apply_conductive(run, neighbor, float(level.conductive_duration))
			run._emit("lightning_shield", {"pos": run.player.pos, "amount": restored, "spell_id": id}, float(effects.shield))


func update_existing(run, dt: float) -> void:
	if not _active(run):
		return
	_update_pending(run)
	_update_projectiles(run, dt)
	_update_cloud(run)


func _cast_lance(run, target: Dictionary, context: Dictionary) -> void:
	var level: Dictionary = context.lightning_level
	var origin: Vector2 = run.player.pos
	var direction: Vector2 = (target.pos - origin).normalized()
	var end: Vector2 = run._clip_motion(origin, direction * float(level.range), float(level.width) * 0.5)
	var contacts: Array = []
	for actor in run.actors:
		if float(actor.health) <= 0.0 or not run.line_is_clear(origin, actor.pos): continue
		var at: float = run.segment_circle_time(origin, end, actor.pos, float(actor.radius) + float(level.width) * 0.5)
		if at != INF: contacts.append({"actor": actor, "at": at})
	contacts.sort_custom(func(a, b): return float(a.at) < float(b.at) if not is_equal_approx(float(a.at), float(b.at)) else int(a.actor.id) < int(b.actor.id))
	var isolated: bool = true
	for other in run.actors:
		if float(other.health) > 0.0 and int(other.id) != int(target.id) and target.pos.distance_to(other.pos) <= float(level.isolated_radius) + 0.000001:
			isolated = false
			break
	var main_coefficient: float = float(level.coefficient) * (float(level.isolated_main_multiplier) if isolated else 1.0)
	var beam_context: Dictionary = context.duplicate(true)
	beam_context["echo_shape_recorded"] = true
	if run.has_method("gem_record_shape"):
		run.gem_record_shape({"kind": "segment", "from": origin, "to": end, "width": float(level.width) * 0.5,
			"target_cap": int(level.secondary_target_cap) + 1, "secondary_target_cap": int(level.secondary_target_cap),
			"primary_actor_id": int(target.id), "following_scale": float(level.secondary_coefficient) / main_coefficient}, main_coefficient, context)
	# The instantaneous main component resolves before its finite side hits;
	# killing a side target cannot manufacture isolation for this same beam.
	for contact in contacts:
		if int(contact.actor.id) == int(target.id):
			_direct_hit(run, target, main_coefficient, beam_context)
			break
	var secondary_count: int = 0
	for contact in contacts:
		if not _active(run): break
		var actor: Dictionary = contact.actor
		if int(actor.id) == int(target.id):
			continue
		elif secondary_count < int(level.secondary_target_cap):
			secondary_count += 1
			_direct_hit(run, actor, float(level.secondary_coefficient), beam_context)
	run._emit("lightning_beam", {"from": origin, "to": end, "pos": end, "width": level.width, "spell_id": "L02"}, float(effects.beam))


func _update_projectiles(run, dt: float) -> void:
	var retained: Array = []
	for bolt in projectiles:
		if not _active(run): break
		var origin: Vector2 = bolt.pos
		var distance: float = minf(float(bolt.speed) * dt, float(bolt.range) - float(bolt.travelled))
		var end: Vector2 = origin + bolt.direction * distance
		var earliest: float = run._first_block_contact(origin, end, float(bolt.radius))
		var target: Dictionary = {}
		for actor in run.actors:
			if float(actor.health) <= 0.0: continue
			var at: float = run.segment_circle_time(origin - actor.get("previous", actor.pos), end - actor.pos, Vector2.ZERO, float(actor.radius) + float(bolt.radius))
			if at < earliest - 0.000001 or (not target.is_empty() and is_equal_approx(at, earliest) and int(actor.id) < int(target.id)):
				earliest = at
				target = actor
		if earliest != INF:
			var point: Vector2 = origin.lerp(end, clampf(earliest, 0.0, 1.0))
			if not target.is_empty():
				_direct_hit(run, target, float(bolt.context.lightning_level.coefficient), bolt.context)
			run._emit("lightning_bolt_hit", {"pos": point, "spell_id": "L01", "blocked": target.is_empty()}, float(effects.hit))
			continue
		bolt.pos = end
		bolt.travelled = float(bolt.travelled) + distance
		if float(bolt.travelled) < float(bolt.range) - 0.000001:
			retained.append(bolt)
	projectiles = retained


func _chain_hit(run, transaction: Dictionary) -> void:
	if not _active(run): return
	var context: Dictionary = transaction.context
	var level: Dictionary = context.lightning_level
	var visited: Array = transaction.visited
	var ordinal: int = int(transaction.ordinal)
	var network: bool = str(transaction.kind) == "network"
	var target: Dictionary
	if ordinal == 0:
		target = _actor(run, int(transaction.target_id))
	else:
		target = _next_connection(run, transaction.origin, bool(transaction.origin_qualified), visited,
			transaction.members if network else [], float(context.connection_add), network)
	if target.is_empty(): return
	var point: Vector2 = target.pos
	var before_conductive: bool = status.has_conductive(int(target.id))
	var coefficient: float = float(level.coefficient)
	var actual: float
	if network and ordinal > 0:
		coefficient = float(level.edge_coefficient)
		var boosted: int = int(mechanics.overload.boosted_existing_edges)
		var multiplier: float = float(mechanics.overload.coefficient_multiplier)
		if bool(context.get("natural", false)) and level.has("natural_overload_edges"):
			boosted = int(level.natural_overload_edges)
			multiplier = float(level.natural_overload_multiplier)
		if bool(transaction.overloaded) and ordinal <= boosted: coefficient *= multiplier
		actual = _derived_hit(run, target, coefficient, context, "lightning_network", true)
	else:
		if not network: coefficient *= pow(float(level.hop_decay), ordinal)
		actual = _direct_hit(run, target, coefficient, context)
	visited.append(int(target.id))
	if ordinal > 0:
		run._emit("lightning_arc", {"from": transaction.origin, "to": point, "pos": point,
			"actor_id": target.id, "spell_id": context.spell_id, "derived": network}, float(effects.arc))
	if actual <= 0.0 or not _active(run) or visited.size() >= int(level.target_cap): return
	var next: Dictionary = {"origin": point, "origin_qualified": before_conductive, "context": context,
		"visited": visited, "ordinal": ordinal + 1, "target_id": -1}
	if network:
		next["members"] = transaction.members
		next["overloaded"] = transaction.overloaded
	_queue(float(transaction.at) + float(level.edge_interval if network else level.hop_interval), str(transaction.kind), next)


func _next_connection(run, origin: Vector2, origin_qualified: bool, visited: Array, members: Array, addition: float, network: bool) -> Dictionary:
	var found: Array = []
	for actor in run.actors:
		var actor_id: int = int(actor.id)
		if float(actor.health) <= 0.0 or actor_id in visited or (network and actor_id not in members): continue
		var marked: bool = status.has_conductive(actor_id)
		var reach: float = float(mechanics.conductive.base_hop_range)
		if origin_qualified and marked: reach += float(mechanics.conductive.both_conductive_range_add) + addition
		if origin.distance_to(actor.pos) <= reach + 0.000001 and run.line_is_clear(origin, actor.pos): found.append(actor)
	found.sort_custom(func(a, b):
		var ac: bool = status.has_conductive(int(a.id))
		var bc: bool = status.has_conductive(int(b.id))
		return ac if ac != bc and not network else _distance_before(a, b, origin))
	return found[0] if not found.is_empty() else {}


func _component(run, start: Dictionary, addition: float) -> Array:
	if start.is_empty() or not status.has_conductive(int(start.id)): return []
	var found: Array = [int(start.id)]
	var todo: Array = [start]
	var reach: float = float(mechanics.conductive.base_hop_range) + float(mechanics.conductive.both_conductive_range_add) + addition
	while not todo.is_empty():
		var origin: Dictionary = todo.pop_front()
		for actor in _targets(run, origin.pos, reach):
			if int(actor.id) in found or not status.has_conductive(int(actor.id)): continue
			found.append(int(actor.id))
			todo.append(actor)
	return found


func _judgment(run, item: Dictionary) -> void:
	var context: Dictionary = item.context
	var level: Dictionary = context.lightning_level
	var main_context: Dictionary = context.duplicate(true)
	main_context["echo_shape_recorded"] = true
	if run.has_method("gem_record_shape"):
		run.gem_record_shape({"kind": "area", "pos": item.pos, "radius": level.radius, "block": true, "target_cap": 1}, float(level.coefficient), context)
	var target: Dictionary = _actor(run, int(item.actor_id))
	if target.is_empty() or target.pos.distance_to(item.pos) > float(level.radius) + float(target.radius) or not run.line_is_clear(item.pos, target.pos): return
	var old_mark: bool = status.has_conductive(int(target.id))
	var age: float = status.conductive_age(int(target.id))
	var neighbors: Array = []
	if bool(context.get("natural", false)) and level.has("mature_age") and old_mark and age >= float(level.mature_age) - 0.000001:
		for neighbor in _targets(run, target.pos, float(level.mature_arc_range)):
			if int(neighbor.id) != int(target.id) and status.has_conductive(int(neighbor.id)): neighbors.append(int(neighbor.id))
	_direct_hit(run, target, float(level.coefficient), main_context)
	if _active(run) and float(target.health) > 0.0 and old_mark:
		_derived_hit(run, target, float(level.conductive_extra_coefficient), context, "lightning_conditional", false)
	if _active(run) and float(target.health) > 0.0 and not neighbors.is_empty():
		var count: int = 0
		for actor_id in neighbors:
			var neighbor: Dictionary = _actor(run, int(actor_id))
			if neighbor.is_empty() or not status.has_conductive(int(actor_id)) or target.pos.distance_to(neighbor.pos) > float(level.mature_arc_range) + 0.000001 or not run.line_is_clear(target.pos, neighbor.pos): continue
			if count >= int(level.mature_arc_target_cap): break
			count += 1
			_derived_hit(run, neighbor, float(level.mature_arc_coefficient), context, "lightning_mature_arc", false)
			run._emit("lightning_arc", {"from": target.pos, "to": neighbor.pos, "pos": neighbor.pos,
				"actor_id": neighbor.id, "spell_id": "L07", "derived": true}, float(effects.arc))
	run._emit("lightning_judgment", {"pos": item.pos, "radius": level.radius, "actor_id": item.actor_id, "spell_id": "L07"}, float(effects.impact))


func _ring(run, center: Vector2, coefficient: float, context: Dictionary, refresh: bool) -> void:
	var level: Dictionary = context.lightning_level
	var ring_context: Dictionary = context.duplicate(true)
	ring_context["echo_shape_recorded"] = true
	if run.has_method("gem_record_shape"):
		run.gem_record_shape({"kind": "area", "pos": center, "radius": level.radius, "block": true}, coefficient, context)
	for actor in _targets(run, center, float(level.radius), true):
		if not _active(run): break
		_direct_hit(run, actor, coefficient, ring_context, refresh)
	run._emit("lightning_ring", {"pos": center, "radius": level.radius, "spell_id": "L06"}, float(effects.ring))


func _cast_cloud(_run, center: Vector2, context: Dictionary) -> void:
	var level: Dictionary = context.lightning_level
	# Each successful cast owns one finite schedule. A later cast cannot cancel
	# earlier damage or lower it by replacing its context with a weaker extra.
	zones.append({"id": _new_id(), "kind": "lightning_cloud", "spell_id": "L05", "pos": center,
		"radius": level.radius, "born_at": status.clock, "expires": status.clock + float(level.duration),
		"remaining": float(level.duration), "next_at": status.clock + float(level.strike_times[0]),
		"next_index": 0, "context": context, "first_hits": {}})


func _update_cloud(run) -> void:
	if zones.is_empty(): return
	var due: Array = []
	for cloud in zones:
		var level: Dictionary = cloud.context.lightning_level
		while int(cloud.next_index) < level.strike_times.size() and float(cloud.next_at) <= minf(status.clock, float(cloud.expires)) + 0.000001:
			due.append({"at": float(cloud.next_at), "cloud": cloud, "wave": int(cloud.next_index)})
			cloud.next_index = int(cloud.next_index) + 1
			cloud.next_at = float(cloud.born_at) + float(level.strike_times[int(cloud.next_index)]) if int(cloud.next_index) < level.strike_times.size() else float(cloud.expires)
	due.sort_custom(func(a, b): return float(a.at) < float(b.at) if not is_equal_approx(float(a.at), float(b.at)) else int(a.cloud.id) < int(b.cloud.id))
	for event in due:
		if not _active(run): break
		var cloud: Dictionary = event.cloud
		var context: Dictionary = cloud.context
		var level: Dictionary = context.lightning_level
		var selected: Array = _targets(run, cloud.pos, float(cloud.radius))
		selected.sort_custom(func(a, b): return _health_before(a, b, cloud.pos))
		for index in mini(selected.size(), int(level.strike_target_cap)):
			if not _active(run): break
			var actor: Dictionary = selected[index]
			var actor_id: int = int(actor.id)
			var area_context: Dictionary = context.duplicate(true)
			area_context["kind"] = "area"
			var actual: float = _direct_hit(run, actor, float(level.coefficient), area_context)
			if actual <= 0.0: continue
			if not cloud.first_hits.has(actor_id):
				cloud.first_hits[actor_id] = true
				if bool(context.get("natural", false)) and float(actor.health) > 0.0 and float(level.get("natural_first_hit_vulnerability", 0.0)) > 0.0:
					status.apply_vulnerability(actor, float(level.natural_first_hit_vulnerability), float(level.vulnerability_duration))
			run._emit("lightning_cloud_strike", {"pos": actor.pos, "from": cloud.pos, "to": actor.pos,
				"actor_id": actor_id, "spell_id": "L05", "cloud_id": cloud.id, "wave": event.wave}, float(effects.hit))
	var retained: Array = []
	for cloud in zones:
		cloud.remaining = maxf(0.0, float(cloud.expires) - status.clock)
		if float(cloud.remaining) > 0.000001: retained.append(cloud)
	zones = retained


func _update_pending(run) -> void:
	while not pending.is_empty() and _active(run):
		pending.sort_custom(func(a, b): return float(a.at) < float(b.at) if not is_equal_approx(float(a.at), float(b.at)) else int(a.id) < int(b.id))
		if float(pending[0].at) > status.clock + 0.000001: break
		var item: Dictionary = pending.pop_front()
		match str(item.kind):
			"chain", "network": _chain_hit(run, item)
			"judgment": _judgment(run, item)
			"ring_followup":
				var level: Dictionary = item.context.lightning_level
				_ring(run, item.pos, float(level.followup_coefficient), item.context, bool(level.followup_conductive_refresh))


func _direct_hit(run, actor: Dictionary, coefficient: float, context: Dictionary, refresh: bool = true) -> float:
	if not _active(run) or actor.is_empty() or float(actor.get("health", 0.0)) <= 0.0: return 0.0
	var pre_conductive: bool = status.has_conductive(int(actor.id))
	context["gem_echo_eligible"] = bool(context.get("natural", false))
	var level: Dictionary = context.lightning_level
	if str(context.spell_id) == "L01" and not status.has_conductive(int(actor.id)):
		coefficient += float(level.get("unconductive_coefficient_add", 0.0))
	if run.has_method("gem_record_shape") and not bool(context.get("echo_shape_recorded", false)):
		run.gem_record_shape({"kind": "area", "pos": actor.pos, "radius": 0.0, "block": true, "target_cap": 1}, coefficient, context)
	var before: float = float(actor.health)
	var body_result: Dictionary = run.resolve_spell_hit(actor, coefficient, context)
	var actual: float = before - maxf(0.0, float(actor.health))
	if float(body_result.get("damage", 0.0)) > 0.0 and run.has_method("gem_core"):
		# on-hit items may already have damaged this target; stock only the body result.
		run._gem_combat.schools.lightning_hit(run, actor, float(body_result.damage), context, pre_conductive)
	if actual > 0.0 and float(actor.health) > 0.0 and refresh:
		_apply_conductive(run, actor, float(level.conductive_duration))
	if actual > 0.0 and run.has_method("gem_after_spell_status"):
		run.gem_after_spell_status(actor, context)
	return actual


func _derived_hit(run, actor: Dictionary, coefficient: float, context: Dictionary, kind: String, refresh: bool) -> float:
	if not _active(run) or actor.is_empty() or float(actor.get("health", 0.0)) <= 0.0: return 0.0
	var derived: Dictionary = context.duplicate(true)
	derived.merge({"kind": kind, "natural": false, "lightning_direct": false}, true)
	var actual: float = run.resolve_lightning_derived_hit(actor, coefficient, derived)
	if actual > 0.0 and float(actor.health) > 0.0 and refresh:
		_apply_conductive(run, actor, float(context.lightning_level.conductive_duration))
	return actual


func _apply_conductive(run, actor: Dictionary, duration: float) -> void:
	var actual_duration: float = duration + _mastery_value(run, "conductive_duration_add")
	if status.apply(run, actor, actual_duration):
		run._emit("lightning_mark", {"pos": actor.pos, "actor_id": actor.id, "spell_id": "lightning", "duration": actual_duration}, float(effects.mark))


func _targets(run, center: Vector2, radius: float, include_body: bool = false) -> Array:
	var found: Array = []
	for actor in run.actors:
		if float(actor.health) > 0.0 and center.distance_to(actor.pos) <= radius + (float(actor.radius) if include_body else 0.0) + 0.000001 and run.line_is_clear(center, actor.pos): found.append(actor)
	found.sort_custom(func(a, b): return _distance_before(a, b, center))
	return found


func _health_before(a: Dictionary, b: Dictionary, center: Vector2) -> bool:
	return float(a.health) > float(b.health) if not is_equal_approx(float(a.health), float(b.health)) else _distance_before(a, b, center)


func _distance_before(a: Dictionary, b: Dictionary, center: Vector2) -> bool:
	var ad: float = center.distance_squared_to(a.pos)
	var bd: float = center.distance_squared_to(b.pos)
	return ad < bd if not is_equal_approx(ad, bd) else int(a.id) < int(b.id)


func _actor(run, actor_id: int) -> Dictionary:
	for actor in run.actors:
		if int(actor.id) == actor_id and float(actor.health) > 0.0: return actor
	return {}


func _queue(at: float, kind: String, values: Dictionary) -> void:
	values.merge({"id": _new_id(), "kind": kind, "at": at}, true)
	pending.append(values)


func _new_id() -> int:
	var result: int = _next_id
	_next_id += 1
	return result


func _active(run) -> bool:
	return run.phase == "combat" and not run.paused and float(run.player.health) > 0.0
