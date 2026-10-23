extends RefCounted
## Body geometry replay. No second cast, state application or critical RNG.
var pending: Array = []
var _path_hits: Dictionary = {}
var _path_gate: Dictionary = {}
var _path_shared: Dictionary = {}
var _area_gate: Dictionary = {}
var _next_record: int = 1

func clear() -> void:
	pending.clear()
	_path_hits.clear()
	_path_gate.clear()
	_path_shared.clear()
	_area_gate.clear()
	_next_record = 1

func record(run, shape: Dictionary, coefficient: float, context: Dictionary) -> void:
	if run.gem_core() != "echo" or not bool(context.get("natural", false)) or not run._gem_combat.body(context) or coefficient <= 0.0: return
	var school: String = str(context.get("school", "fire"))
	var school_bonus: float = 0.0
	if school == "fire":
		school_bonus = run._fire_damage_bonus()
	elif school == "ice":
		school_bonus = run._spell_combat.ice.school_bonus(run)
	else:
		var module = run._spell_combat.school_module(school)
		if module != null:
			school_bonus = module.school_bonus(run)
	var spec: Dictionary = run._gem_combat.spec
	var fraction: float = float(spec.base_multiplier)
	var field: float = run._spell_combat.field_attack_bonus() if school != "fire" else float(context.get("field_bonus", 0.0))
	var raw: float = float(run.player.attack) * (1.0 + field) * (1.0 + school_bonus) * coefficient * float(context.get("damage_scale", 1.0)) * fraction
	pending.append({"at": run._gem_combat.clock + float(spec.delay), "shape": shape.duplicate(true), "raw": raw, "school": school, "record_id": _next_record})
	_next_record += 1

func advance(run, clock: float) -> void:
	var due: Array = []
	var retained: Array = []
	for item in pending:
		if float(item.at) <= clock + 0.000001: due.append(item)
		else: retained.append(item)
	pending = retained
	# Fire persistent areas share one same-spell hit per enemy and interval.
	# Keep each finite geometry, choosing the strongest real overlapping replay.
	var area_choices: Dictionary = {}
	for item in due:
		var shape: Dictionary = item.shape
		if not shape.has("shared_spell"): continue
		for actor in run.actors:
			if float(actor.health) <= 0.0 or Vector2(shape.pos).distance_to(actor.pos) > float(shape.radius) + float(actor.radius) + 0.000001: continue
			if bool(shape.get("block", false)) and not run.line_is_clear(shape.pos, actor.pos): continue
			var key: String = str(shape.shared_spell) + ":" + str(actor.id)
			if not area_choices.has(key) or float(item.raw) > float(area_choices[key].raw):
				area_choices[key] = {"record_id": item.record_id, "raw": item.raw}
	for item in due:
		if run.phase != "combat": return
		var contacts: Array = []
		var shape: Dictionary = item.shape
		var center: Vector2 = shape.get("pos", Vector2.ZERO)
		for actor in run.actors:
			if float(actor.health) <= 0.0: continue
			var at: float = 0.0
			if str(shape.kind) == "segment":
				at = run.segment_circle_time(shape.from, shape.to, actor.pos, float(actor.radius) + float(shape.width))
				if at == INF or not run.line_is_clear(shape.from, actor.pos): continue
			elif str(shape.kind) == "segments":
				at = INF
				for segment in shape.get("segments", []):
					var contact: float = run.segment_circle_time(segment.from, segment.to, actor.pos, float(actor.radius) + float(segment.width))
					if contact == INF: continue
					var origin: Vector2 = segment.from.lerp(segment.to, contact)
					if bool(shape.get("block", false)) and not run.line_is_clear(origin, actor.pos): continue
					at = minf(at, contact)
				if at == INF: continue
			elif center.distance_to(actor.pos) > float(shape.radius) + float(actor.radius) + 0.000001: continue
			elif bool(shape.get("block", false)) and not run.line_is_clear(center, actor.pos): continue
			if str(shape.kind) == "cone":
				var offset: Vector2 = actor.pos - center
				var direction: Vector2 = shape.get("direction", Vector2.UP)
				if offset.length_squared() > 0.000001 and absf(direction.angle_to(offset)) > deg_to_rad(float(shape.get("angle_degrees", 0)) * 0.5): continue
			contacts.append({"actor": actor, "at": at})
		contacts.sort_custom(func(a, b): return float(a.at) < float(b.at) if not is_equal_approx(float(a.at), float(b.at)) else int(a.actor.id) < int(b.actor.id))
		var delivered: int = 0
		var secondaries: int = 0
		for index in contacts.size():
			if delivered >= int(shape.get("target_cap", contacts.size())): break
			var actor: Dictionary = contacts[index].actor
			if shape.has("shared_spell"):
				var area_key: String = str(shape.shared_spell) + ":" + str(actor.id)
				if not area_choices.has(area_key) or int(area_choices[area_key].record_id) != int(item.record_id): continue
				if float(item.at) < float(_area_gate.get(area_key, -INF)) - 0.000001: continue
				_area_gate[area_key] = float(item.at) + float(shape.shared_interval)
			var is_primary: bool = shape.has("primary_actor_id") and int(actor.id) == int(shape.primary_actor_id)
			if shape.has("primary_actor_id") and not is_primary:
				if secondaries >= int(shape.get("secondary_target_cap", contacts.size())): continue
				secondaries += 1
			if bool(shape.get("wind_path", false)):
				var cast_key: String = str(shape.get("cast_id", -1)) + ":" + str(actor.id)
				var gate_key: String = str(actor.id)
				var history: Array = []
				for at in _path_shared.get(gate_key, []):
					if float(at) > float(item.at) - float(shape.get("shared_window", 2.0)) + 0.000001: history.append(at)
				if int(_path_hits.get(cast_key, 0)) >= int(shape.get("per_actor_cap", 1)): continue
				if history.size() >= int(shape.get("shared_cap", 1)): continue
				if float(item.at) < float(_path_gate.get(gate_key, -INF)) - 0.000001: continue
				_path_hits[cast_key] = int(_path_hits.get(cast_key, 0)) + 1
				history.append(float(item.at))
				_path_shared[gate_key] = history
				_path_gate[gate_key] = float(item.at) + float(shape.get("hit_gate", 0.5))
			delivered += 1
			var coefficient_scale: float = float(shape.get("following_scale", 1.0)) if index > 0 else 1.0
			if shape.has("falloff"): coefficient_scale = pow(float(shape.falloff), delivered - 1)
			if shape.has("primary_actor_id"):
				coefficient_scale = 1.0 if is_primary else float(shape.get("following_scale", 1.0))
			if shape.has("inner_radius"):
				coefficient_scale = float(shape.inner_scale) if center.distance_to(actor.pos) <= float(shape.inner_radius) + float(actor.radius) else float(shape.outer_scale)
			var bonus: Dictionary = run._artifact_combat.modify_damage_context(run, actor, {"school": item.school, "kind": "gem_echo", "natural": false, "spell_id": "gem_echo"})
			var module = run._spell_combat.school_module(str(item.school))
			if str(item.school) == "fire": bonus.damage_multiplier *= 1.0 + run._spell_combat.growth.fire_vulnerability(run, actor)
			elif module != null and module.has_method("target_vulnerability"): bonus.damage_multiplier *= 1.0 + module.target_vulnerability(actor)
			run.resolve_fixed_item_hit(actor, float(item.raw) * coefficient_scale * float(bonus.damage_multiplier), "gem_echo")
		var visual: Dictionary = shape.duplicate(true)
		visual["kind_shape"] = str(shape.kind)
		visual["school"] = item.school
		run._emit("gem_echo", visual, 0.45)
