extends RefCounted
## Approved ice spells. Geometry is fixed at release; offense is read on hit.

const IceGrowth = preload("res://scripts/core/route_ice_growth.gd")
var growth = IceGrowth.new()
const IceStatus = preload("res://scripts/core/route_ice_status.gd")
var status = IceStatus.new()
var mechanics: Dictionary = {}
var effects: Dictionary = {}
var zones: Array = []
var pending: Array = []
var projectiles: Array = []
var defense_remaining: float = 0.0
var _defense_add: float = 0.0
var _next_id: int = 1
var _last_tick: float = -INF
var _area_last_hit: Dictionary = {}
var _chill_last_hit: Dictionary = {}
var _chill_ordinals: Dictionary = {}
var _effective_hits: Dictionary = {}


func configure(source: Dictionary) -> Dictionary:
	if not source.get("mechanics") is Dictionary or not source.get("spells") is Dictionary or source.spells.size() != 10:
		return {"ok": false, "error": "正式冰系法术源缺失或数量无效。"}
	mechanics = source.mechanics.duplicate(true)
	effects = source.get("effects", {}).duplicate(true)
	for key in ["hit", "ring", "impact", "shatter", "armor"]:
		if not effects.has(key) or not is_finite(float(effects[key])) or float(effects[key]) <= 0.0:
			return {"ok": false, "error": "正式冰系表现时长无效：" + key}
	if not mechanics.has_all(["frost", "resonance", "initial_ids", "shared_slow_caps"]):
		return {"ok": false, "error": "正式冰系状态参数缺失。"}
	for key in ["max_stacks", "expiry", "ready_window", "base_freeze", "post_freeze_immunity"]:
		if not mechanics.frost.has(key) or not is_finite(float(mechanics.frost[key])) or float(mechanics.frost[key]) <= 0.0:
			return {"ok": false, "error": "正式冰系寒霜参数无效：" + key}
	for id in source.spells:
		var spec: Dictionary = source.spells[id]
		if str(spec.get("school", "")) != "ice" or not spec.get("levels") is Array or spec.levels.size() != 3:
			return {"ok": false, "error": "正式冰系三级源无效：" + str(id)}
	status.configure(mechanics, effects)
	stop_room()
	return {"ok": true, "error": ""}


func stop_room() -> void:
	zones.clear()
	growth.clear()
	pending.clear()
	projectiles.clear()
	_area_last_hit.clear()
	_chill_last_hit.clear()
	_chill_ordinals.clear()
	_effective_hits.clear()
	defense_remaining = 0.0
	_defense_add = 0.0
	_last_tick = -INF
	_next_id = 1
	status.clear()


func before_tick(run, dt: float) -> void:
	if run.phase != "combat" or run.paused or absf(_last_tick - float(run.time)) <= 0.000000001:
		return
	_last_tick = float(run.time)
	defense_remaining = maxf(0.0, defense_remaining - maxf(0.0, dt))
	status.advance(run, dt)


func is_ice_spell(id: String) -> bool:
	return id.begins_with("I") and id in ["I01", "I02", "I03", "I04", "I05", "I06", "I07", "I08", "I09", "I10"]


func spell_count(run) -> int:
	var distinct: Dictionary = {}
	for spell in run.spells:
		if is_ice_spell(str(spell.id)):
			distinct[str(spell.id)] = true
	return distinct.size()


func school_bonus(run) -> float:
	var result: float = 0.0
	var mastery: Dictionary = run._owned_spell("I10")
	if not mastery.is_empty():
		result += float(run.get_spell_stats(mastery).level.school_damage_bonus)
	if spell_count(run) >= int(mechanics.resonance.distinct_spells):
		result += float(mechanics.resonance.school_damage_bonus)
	return result


func cooldown_bonus(run) -> float:
	return float(mechanics.resonance.school_cdr) if spell_count(run) >= int(mechanics.resonance.distinct_spells) else 0.0


func ready_duration(run) -> float:
	var duration: float = float(mechanics.frost.ready_window)
	var mastery: Dictionary = run._owned_spell("I10")
	if not mastery.is_empty():
		duration += float(run.get_spell_stats(mastery).level.ready_window_add)
	return duration


func defense_bonus() -> float:
	return _defense_add if defense_remaining > 0.000001 else 0.0


func apply_frost(run, actor: Dictionary, amount: int = 1, context: Dictionary = {}) -> bool:
	return status.apply_frost(run, actor, amount, context)


func get_snapshot(run) -> Dictionary:
	return {"ice_states": status.snapshot(run), "ice_zones": zones.duplicate(true),
		"ice_pending": pending.duplicate(true), "ice_projectiles": projectiles.duplicate(true),
		"ice_defense": {"remaining": defense_remaining, "defense_add": defense_bonus()}, "ice_clock": status.clock}


func legal_target(run, spell: Dictionary, stats: Dictionary) -> Dictionary:
	if run.phase != "combat" or run.paused or float(run.player.health) <= 0.0 or stats.kind == "passive":
		return {}
	var level: Dictionary = stats.level
	var id: String = str(spell.id)
	if id == "I09":
		if defense_remaining > float(stats.recast_remaining_gate) + 0.000001:
			return {}
		var enemy: Dictionary = _nearest(run, run.player.pos, float(stats.combat_enemy_range))
		return {"id": -1, "pos": run.player.pos} if not enemy.is_empty() else {}
	var distance: float = float(level.get("range", level.get("radius", 0.0)))
	var actors: Array = _targets(run, run.player.pos, distance, id == "I04")
	if id == "I08":
		actors.sort_custom(func(a, b): return float(a.health) > float(b.health) if not is_equal_approx(float(a.health), float(b.health)) else _distance_before(a, b, run.player.pos))
	elif id == "I07":
		actors.sort_custom(func(a, b):
			var ar: bool = not status.capture_ready(int(a.id)).is_empty()
			var br: bool = not status.capture_ready(int(b.id)).is_empty()
			return ar if ar != br else _distance_before(a, b, run.player.pos))
	return actors[0] if not actors.is_empty() else {}


func finish_target(run, spell: Dictionary, stats: Dictionary) -> Dictionary:
	# I07 explicitly reselects its ready-window priority; ring/armor are local
	# group effects. Other ice windups retain the originally acquired actor.
	if str(spell.id) in ["I04", "I07", "I09"]:
		return legal_target(run, spell, stats)
	var original: Dictionary = _actor(run, int(spell.get("target_id", -1)))
	var distance: float = float(stats.level.get("range", 0.0))
	return original if not original.is_empty() and run.player.pos.distance_to(original.pos) <= distance + 0.000001 and run.line_is_clear(run.player.pos, original.pos) else {}


func cast(run, spell: Dictionary, stats: Dictionary, target: Dictionary, source_context: Dictionary) -> void:
	var level: Dictionary = stats.level.duplicate(true)
	var context: Dictionary = source_context.duplicate(true)
	context.merge({"kind": "direct", "ice_direct": true, "ice_source_kind": stats.kind,
		"ice_level": level, "spell_level": int(spell.level), "field_bonus": 0.0, "school": "ice"}, true)
	var id: String = str(spell.id)
	match id:
		"I01":
			var direction: Vector2 = (target.pos - run.player.pos).normalized()
			projectiles.append({"id": _new_id(), "spell_id": id, "kind": "ice_bolt", "pos": run.player.pos,
				"from": run.player.pos, "direction": direction, "speed": float(level.speed), "radius": float(level.projectile_radius),
				"range": float(level.range), "travelled": 0.0, "context": context})
		"I02":
			var from: Vector2 = run.player.pos
			var direction: Vector2 = (target.pos - from).normalized()
			var to: Vector2 = run._clip_motion(from, direction * float(level.length), float(level.width) * 0.5)
			var contacts: Array = []
			for actor in run.actors:
				if float(actor.health) <= 0.0 or not run.line_is_clear(from, actor.pos):
					continue
				var at: float = run.segment_circle_time(from, to, actor.pos, float(actor.radius) + float(level.width) * 0.5)
				if at != INF:
					contacts.append({"actor": actor, "at": at})
			contacts.sort_custom(func(a, b): return float(a.at) < float(b.at) if not is_equal_approx(float(a.at), float(b.at)) else int(a.actor.id) < int(b.actor.id))
			if run.has_method("gem_record_shape"): run.gem_record_shape({"kind": "segment", "from": from, "to": to, "width": float(level.width) * 0.5, "target_cap": int(level.target_cap), "following_scale": float(level.following_coefficient) / float(level.coefficient)}, float(level.coefficient), context)
			for index in mini(contacts.size(), int(level.target_cap)):
				_hit(run, contacts[index].actor, float(level.coefficient) if index == 0 else float(level.following_coefficient), context, int(level.chill_stacks))
			run._emit("ice_beam", {"from": from, "to": to, "pos": to, "width": level.width, "spell_id": id}, float(effects.hit))
		"I03":
			var pos: Vector2 = spell.get("locked_pos", target.pos)
			_queue(float(level.impact_delay), "star", {"pos": pos, "radius": level.radius, "context": context})
			run._emit("ice_star_flight", {"pos": pos, "radius": level.radius, "spell_id": id}, float(level.impact_delay))
		"I04":
			_area(run, run.player.pos, float(level.radius), float(level.coefficient), context, int(level.chill_stacks))
			for actor in _targets(run, run.player.pos, float(level.radius), true):
				var amount: float = float(level["slow_" + ("fixed_strong" if status.category(actor) == "fixed_strong" else status.category(actor))])
				status.apply_short_slow(run, actor, amount, float(level.slow_duration), id)
			run._emit("ice_ring", {"pos": run.player.pos, "radius": level.radius, "spell_id": id}, float(effects.ring))
		"I05":
			for index in range(zones.size() - 1, -1, -1):
				if zones[index].spell_id == id:
					zones.remove_at(index)
			var pos: Vector2 = spell.get("locked_pos", target.pos)
			zones.append({"id": _new_id(), "kind": "ice_domain", "spell_id": id, "pos": pos, "radius": level.radius,
				"born_at": status.clock, "expires": status.clock + float(level.duration), "remaining": float(level.duration),
				"next_at": status.clock + float(level.first_tick), "interval": float(level.interval), "context": context})
		"I06":
			var from: Vector2 = run.player.pos
			var direction: Vector2 = (spell.get("locked_pos", target.pos) - from).normalized()
			var to: Vector2 = run._clip_motion(from, direction * float(level.length), float(level.width) * 0.5)
			var duration: float = float(level.first_wave) + float(level.wave_interval) * (int(level.waves) - 1)
			zones.append({"id": _new_id(), "kind": "ice_storm", "spell_id": id, "pos": from.lerp(to, 0.5), "from": from, "to": to,
				"width": level.width, "born_at": status.clock, "next_at": status.clock + float(level.first_wave), "wave": 0,
				"duration": duration, "expires": status.clock + duration, "remaining": duration,
				"waves": int(level.waves), "interval": float(level.wave_interval), "context": context,
				"final_wave_multiplier": float(stats.get("final_wave_multiplier", 1.0))})
		"I07":
			_shatter(run, target, context)
		"I08":
			_queue(float(level.impact_delay), "prison", {"actor_id": int(target.id), "pos": target.pos, "radius": level.radius, "context": context})
			run._emit("ice_coffin_flight", {"pos": target.pos, "radius": level.radius, "spell_id": id, "actor_id": target.id}, float(level.impact_delay))
		"I09":
			growth.armor_context = context.duplicate(true)
			_defense_add = float(level.defense_add)
			defense_remaining = float(level.duration)
			_guard_pulse(run, float(level.radius), int(level.chill_stacks), context)
			# Replacing armor cancels its previous scheduled second pulse.
			for index in range(pending.size() - 1, -1, -1):
				if pending[index].kind == "guard":
					pending.remove_at(index)
			if int(level.followup_chill_stacks) > 0:
				_queue(float(level.followup_delay), "guard", {"radius": level.radius, "stacks": level.followup_chill_stacks, "context": context})
			run._emit("ice_guard", {"pos": run.player.pos, "radius": level.radius, "defense_add": _defense_add, "duration": level.duration, "spell_id": id}, float(effects.armor))


func update_existing(run, dt: float) -> void:
	if run.phase != "combat" or run.paused:
		return
	_update_pending(run)
	_update_projectiles(run, dt)
	_update_zones(run)


func _update_pending(run) -> void:
	var due: Array = []
	var future: Array = []
	for item in pending:
		if float(item.at) <= status.clock + 0.000001:
			due.append(item)
		else:
			future.append(item)
	pending = future
	for item in due:
		if run.phase != "combat":
			return
		var level: Dictionary = item.context.ice_level
		match item.kind:
			"star":
				_area(run, item.pos, float(item.radius), float(level.coefficient), item.context, int(level.chill_stacks))
				run._emit("ice_star", {"pos": item.pos, "radius": item.radius, "spell_id": "I03"}, float(effects.impact))
				if float(level.followup_coefficient) > 0.0:
					_queue(float(level.followup_delay), "star_followup", {"pos": item.pos, "radius": item.radius, "context": item.context})
			"star_followup":
				var followup_context: Dictionary = item.context.duplicate(true)
				followup_context["growth_primary"] = false
				_area(run, item.pos, float(item.radius), float(level.followup_coefficient), followup_context, 0)
				run._emit("ice_star", {"pos": item.pos, "radius": item.radius, "spell_id": "I03", "followup": true}, float(effects.hit))
			"prison":
				if run.has_method("gem_record_shape"): run.gem_record_shape({"kind": "area", "pos": item.pos, "radius": item.radius, "block": true, "target_cap": 1}, float(level.coefficient), item.context)
				var actor: Dictionary = _actor(run, int(item.actor_id))
				if not actor.is_empty() and actor.pos.distance_to(item.pos) <= float(item.radius) + float(actor.radius) and run.line_is_clear(item.pos, actor.pos):
					_hit(run, actor, float(level.coefficient), item.context, 0)
					if float(actor.health) > 0.0:
						status.force_ready(run, actor, float(level.freeze_base), item.context)
						if run.has_method("gem_after_spell_status"): run.gem_after_spell_status(actor, item.context)
					run._emit("ice_coffin", {"pos": item.pos, "radius": item.radius, "spell_id": "I08", "actor_id": item.actor_id}, float(effects.impact))
			"guard":
				_guard_pulse(run, float(item.radius), int(item.stacks), item.context)


func _update_projectiles(run, dt: float) -> void:
	var retained: Array = []
	for bolt in projectiles:
		if run.phase != "combat":
			break
		var from: Vector2 = bolt.pos
		var distance: float = minf(float(bolt.speed) * dt, float(bolt.range) - float(bolt.travelled))
		var to: Vector2 = from + bolt.direction * distance
		var first: float = run._first_block_contact(from, to, float(bolt.radius))
		var hit: Dictionary = {}
		for actor in run.actors:
			if float(actor.health) <= 0.0:
				continue
			var at: float = run.segment_circle_time(from - actor.get("previous", actor.pos), to - actor.pos, Vector2.ZERO, float(actor.radius) + float(bolt.radius))
			if at < first - 0.000001 or (not hit.is_empty() and is_equal_approx(at, first) and int(actor.id) < int(hit.id)):
				first = at
				hit = actor
		if not hit.is_empty():
			if run.has_method("gem_record_shape"): run.gem_record_shape({"kind": "area", "pos": from.lerp(to, first), "radius": float(bolt.radius), "block": true, "target_cap": 1}, float(bolt.context.ice_level.coefficient), bolt.context)
			_hit(run, hit, float(bolt.context.ice_level.coefficient), bolt.context, int(bolt.context.ice_level.chill_stacks))
			run._emit("ice_bolt_hit", {"pos": from.lerp(to, first), "actor_id": hit.id, "spell_id": "I01"}, float(effects.hit))
			continue
		if first != INF:
			continue
		bolt.pos = to
		bolt.travelled = float(bolt.travelled) + distance
		if float(bolt.travelled) < float(bolt.range) - 0.000001:
			retained.append(bolt)
	projectiles = retained


func _update_zones(run) -> void:
	var retained: Array = []
	var candidates: Dictionary = {}
	for zone in zones:
		zone.remaining = maxf(0.0, float(zone.expires) - status.clock)
		var level: Dictionary = zone.context.ice_level
		var completed: bool = false
		while float(zone.next_at) <= status.clock + 0.000001:
			if run.phase != "combat":
				return
			if zone.kind == "ice_domain":
				if float(zone.next_at) > float(zone.expires) + 0.000001:
					break
				if run.has_method("gem_record_shape"): run.gem_record_shape({"kind": "area", "pos": zone.pos, "radius": zone.radius, "block": true}, float(level.coefficient), zone.context)
				for actor in _targets(run, zone.pos, float(zone.radius), true):
					_offer_zone_hit(candidates, actor, zone, float(level.coefficient), float(level.interval))
			else:
				zone.wave = int(zone.wave) + 1
				if run.has_method("gem_record_shape"): run.gem_record_shape({"kind": "segment", "from": zone.from, "to": zone.to, "width": float(zone.width) * 0.5}, float(level.coefficient) * (float(zone.final_wave_multiplier) if int(zone.wave) == int(zone.waves) else 1.0), zone.context)
				var actors: Array = []
				for actor in run.actors:
					if float(actor.health) > 0.0 and run.segment_circle_time(zone.from, zone.to, actor.pos, float(actor.radius) + float(zone.width) * 0.5) != INF and run.line_is_clear(zone.from, actor.pos):
						actors.append(actor)
				actors.sort_custom(func(a, b): return int(a.id) < int(b.id))
				for actor in actors:
					var coefficient: float = float(level.coefficient)
					if int(zone.wave) == int(zone.waves):
						if not status.capture_ready(int(actor.id)).is_empty():
							coefficient = float(level.final_ready_coefficient)
						coefficient *= float(zone.final_wave_multiplier)
					_offer_zone_hit(candidates, actor, zone, coefficient, float(level.wave_interval))
				run._emit("ice_storm_wave", {"from": zone.from, "to": zone.to, "pos": zone.pos, "width": zone.width, "spell_id": "I06", "wave": zone.wave}, float(effects.hit))
				if int(zone.wave) >= int(zone.waves):
					completed = true
					break
			zone.next_at = float(zone.next_at) + float(zone.interval)
		if zone.kind == "ice_domain":
			zone.remaining = maxf(0.0, float(zone.expires) - status.clock)
			completed = float(zone.remaining) <= 0.000001
		if not completed:
			retained.append(zone)
	zones = retained
	for value in candidates.values():
		if not _active(run):
			break
		if float(value.actor.health) > 0.0:
			_zone_hit(run, value.actor, value.zone, float(value.coefficient), float(value.interval))


func _offer_zone_hit(candidates: Dictionary, actor: Dictionary, zone: Dictionary, coefficient: float, interval: float) -> void:
	var key: String = "%s:%s" % [zone.spell_id, actor.id]
	var effective: float = coefficient * float(zone.context.damage_scale)
	if not candidates.has(key) or effective > float(candidates[key].effective) + 0.000001 or (is_equal_approx(effective, float(candidates[key].effective)) and int(zone.context.cast_id) < int(candidates[key].zone.context.cast_id)):
		candidates[key] = {"actor": actor, "zone": zone, "coefficient": coefficient, "interval": interval, "effective": effective}


func _zone_hit(run, actor: Dictionary, zone: Dictionary, coefficient: float, interval: float) -> void:
	var key: String = "%s:%s" % [zone.spell_id, actor.id]
	if status.clock - float(_area_last_hit.get(key, -INF)) < interval - 0.000001:
		return
	_area_last_hit[key] = status.clock
	var context: Dictionary = zone.context.duplicate(true)
	context["kind"] = "area"
	context["ice_direct"] = false
	var cast_key: String = "%s:%s" % [str(context.cast_id), actor.id]
	var hit_number: int = int(_effective_hits.get(cast_key, 0)) + 1
	_effective_hits[cast_key] = hit_number
	var scheduled_chill: bool = str(zone.spell_id) == "I06" and context.ice_level.chill_effective_waves.any(func(value): return int(value) == hit_number)
	var stacks: int = int(context.ice_level.chill_stacks) if str(zone.spell_id) == "I05" else (1 if scheduled_chill else 0)
	if status.clock - float(_chill_last_hit.get(key, -INF)) < interval - 0.000001:
		stacks = 0
	if stacks > 0 and str(zone.spell_id) == "I05" and not _chill_ordinals.has(cast_key):
		stacks = int(context.ice_level.first_valid_chill_stacks)
	context["ice_shared_chill_key"] = key
	_hit(run, actor, coefficient, context, stacks)


func _hit(run, actor: Dictionary, coefficient: float, context: Dictionary, frost_stacks: int = 0) -> Dictionary:
	if not _active(run) or float(actor.get("health", 0.0)) <= 0.0:
		return {"damage": 0.0}
	var before: Dictionary = status.state_for(int(actor.id))
	var level: Dictionary = context.ice_level
	var id: String = str(context.spell_id)
	if id == "I01" and int(before.get("stacks", 0)) in [1, 2] and not bool(before.get("ready", false)):
		coefficient += float(level.get("frosted_coefficient_add", 0.0))
		frost_stacks = int(level.get("chill_stacks_if_pre_frost_1_or_2", frost_stacks))
	if id == "I08" and (status.is_immune(int(actor.id)) or status.control_coefficient(actor) <= 0.0):
		coefficient += float(level.get("immune_coefficient_add", 0.0))
	var hp: float = float(actor.health)
	var result: Dictionary = run.resolve_spell_hit(actor, coefficient, context)
	var actual: float = hp - maxf(0.0, float(actor.health))
	var cast_key: String = "%s:%s" % [str(context.cast_id), actor.id]
	var qualified: bool = actual > 0.0 and float(actor.health) > 0.0 and frost_stacks > 0 and not bool(before.get("ready", false))
	var ordinal: int = int(_chill_ordinals.get(cast_key, 0)) + 1 if qualified else 0
	var extra: int = growth.extra_frost(run, actor, context, result, before, ordinal)
	if run._artifact_combat != null and run._artifact_combat.has_method("ice_extra_frost"):
		extra += run._artifact_combat.ice_extra_frost(run, actor, context, result, before, ordinal)
	if qualified:
		_chill_ordinals[cast_key] = ordinal
		if context.has("ice_shared_chill_key"):
			_chill_last_hit[str(context.ice_shared_chill_key)] = status.clock
		apply_frost(run, actor, frost_stacks, context)
	if extra > 0 and actual > 0.0 and float(actor.health) > 0.0:
		apply_frost(run, actor, extra, context)
	# I07 completes its own old-token transaction before trying a core reaction.
	if id != "I07" and actual > 0.0 and run.has_method("gem_after_spell_status"): run.gem_after_spell_status(actor, context)
	return {"damage": actual, "critical": bool(result.get("critical", false)), "pre_state": before}


func _shatter(run, actor: Dictionary, context: Dictionary) -> void:
	var old: Dictionary = status.capture_ready(int(actor.id))
	var pos: Vector2 = actor.pos
	if run.has_method("gem_record_shape"): run.gem_record_shape({"kind": "area", "pos": pos, "radius": 0.0, "block": true, "target_cap": 1}, float(context.ice_level.coefficient), context)
	_hit(run, actor, float(context.ice_level.coefficient), context, 0)
	if old.is_empty() or not _active(run):
		return
	var token: int = int(old.token)
	var consumed: Dictionary = status.consume_ready(run, actor, token, context, old)
	if consumed.is_empty():
		if run.has_method("gem_after_spell_status"): run.gem_after_spell_status(actor, context)
		return
	var effect: Dictionary = growth.shatter_effect(run, actor, context)
	if run._artifact_combat != null and run._artifact_combat.has_method("ice_shatter_effect"):
		var legacy: Dictionary = run._artifact_combat.ice_shatter_effect(run, actor, context, {"token": token, "pos": pos, "primary_alive": float(actor.health) > 0.0})
		effect.damage_multiplier *= float(legacy.get("damage_multiplier", 1.0))
		for key in ["retain_frost", "fragment_frost_targets", "fragment_frost_stacks"]:
			effect[key] = maxi(int(effect[key]), int(legacy.get(key, 0)))
	var amount: float = 0.0
	if float(actor.health) > 0.0:
		amount = run.resolve_ice_derived_hit(actor, float(context.ice_level.shatter_coefficient) * float(effect.damage_multiplier), _derived_context(context, "ice_shatter"))
	run._emit("ice_shatter", {"pos": pos, "actor_id": actor.id, "token": token, "amount": amount, "spell_id": "I07"}, float(effects.shatter))
	if float(actor.health) > 0.0 and int(effect.retain_frost) > 0:
		apply_frost(run, actor, int(effect.retain_frost), _derived_context(context, "ice_status"))
	var used_frost: int = 0
	var count: int = 0
	for neighbor in _targets(run, pos, float(context.ice_level.shard_radius), true):
		if int(neighbor.id) == int(actor.id):
			continue
		if count >= int(context.ice_level.shard_target_cap):
			break
		count += 1
		var dealt: float = run.resolve_ice_derived_hit(neighbor, float(context.ice_level.shard_coefficient), _derived_context(context, "ice_shard"))
		run._emit("ice_shard", {"from": pos, "to": neighbor.pos, "pos": neighbor.pos, "actor_id": neighbor.id, "spell_id": "I07"}, float(effects.hit))
		if dealt > 0.0 and float(neighbor.health) > 0.0 and used_frost < int(effect.fragment_frost_targets):
			used_frost += 1
			apply_frost(run, neighbor, int(effect.fragment_frost_stacks), _derived_context(context, "ice_status"))


func _derived_context(context: Dictionary, kind: String) -> Dictionary:
	var result: Dictionary = context.duplicate(true)
	result.merge({"kind": kind, "natural": false, "ice_direct": false, "school": "ice"}, true)
	return result


func _area(run, center: Vector2, radius: float, coefficient: float, context: Dictionary, stacks: int) -> void:
	if run.has_method("gem_record_shape"): run.gem_record_shape({"kind": "area", "pos": center, "radius": radius, "block": true}, coefficient, context)
	for actor in _targets(run, center, radius, true):
		if not _active(run):
			break
		_hit(run, actor, coefficient, context, stacks)


func _guard_pulse(run, radius: float, stacks: int, context: Dictionary) -> void:
	for actor in _targets(run, run.player.pos, radius, true):
		apply_frost(run, actor, stacks, context)
	run._emit("ice_guard_pulse", {"pos": run.player.pos, "radius": radius, "spell_id": "I09"}, float(effects.armor))


func _targets(run, center: Vector2, radius: float, include_body: bool = false) -> Array:
	var result: Array = []
	for actor in run.actors:
		if float(actor.health) > 0.0 and center.distance_to(actor.pos) <= radius + (float(actor.radius) if include_body else 0.0) + 0.000001 and run.line_is_clear(center, actor.pos):
			result.append(actor)
	result.sort_custom(func(a, b): return _distance_before(a, b, center))
	return result


func _nearest(run, center: Vector2, radius: float) -> Dictionary:
	var found: Array = _targets(run, center, radius)
	return found[0] if not found.is_empty() else {}


func _distance_before(a: Dictionary, b: Dictionary, center: Vector2) -> bool:
	var da: float = center.distance_squared_to(a.pos)
	var db: float = center.distance_squared_to(b.pos)
	return da < db if not is_equal_approx(da, db) else int(a.id) < int(b.id)


func _actor(run, actor_id: int) -> Dictionary:
	for actor in run.actors:
		if int(actor.id) == actor_id and float(actor.health) > 0.0:
			return actor
	return {}


func _queue(delay: float, kind: String, values: Dictionary) -> void:
	values.merge({"id": _new_id(), "kind": kind, "at": status.clock + delay}, true)
	pending.append(values)


func _new_id() -> int:
	var value: int = _next_id
	_next_id += 1
	return value


func _active(run) -> bool:
	return run.phase == "combat" and not run.paused and float(run.player.health) > 0.0
