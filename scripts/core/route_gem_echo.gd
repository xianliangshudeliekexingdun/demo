extends RefCounted
## Body geometry replay. No second cast, state application or critical RNG.
var pending: Array = []

func clear() -> void:
	pending.clear()

func record(run, shape: Dictionary, coefficient: float, context: Dictionary) -> void:
	if run.gem_core() != "echo" or not bool(context.get("natural", false)) or coefficient <= 0.0: return
	var school: String = str(context.get("school", "fire"))
	var cdr: float = run.artifact_cooldown_reduction()
	var school_bonus: float = 0.0
	if school == "fire":
		if run._spell_combat.fire_spell_count(run) >= int(run._base.fire_synergy.distinct_spells): cdr += float(run._base.fire_synergy.cooldown_reduction)
		school_bonus = run._fire_damage_bonus()
	else:
		cdr += run._spell_combat.ice.cooldown_bonus(run)
		school_bonus = run._spell_combat.ice.school_bonus(run)
	cdr = clampf(cdr, 0.0, float(run._base.limits.cooldown_reduction))
	var spec: Dictionary = run._gem_combat.spec
	var fraction: float = float(spec.base_multiplier) + cdr * float(spec.cdr_multiplier)
	var field: float = run._spell_combat.field_attack_bonus() if school == "ice" else float(context.get("field_bonus", 0.0))
	var raw: float = float(run.player.attack) * (1.0 + field) * (1.0 + school_bonus) * coefficient * float(context.get("damage_scale", 1.0)) * fraction
	pending.append({"at": run._gem_combat.clock + float(spec.delay), "shape": shape.duplicate(true), "raw": raw, "school": school})

func advance(run, clock: float) -> void:
	var due: Array = []
	var retained: Array = []
	for item in pending:
		if float(item.at) <= clock + 0.000001: due.append(item)
		else: retained.append(item)
	pending = retained
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
			elif center.distance_to(actor.pos) > float(shape.radius) + float(actor.radius) + 0.000001: continue
			elif bool(shape.get("block", false)) and not run.line_is_clear(center, actor.pos): continue
			contacts.append({"actor": actor, "at": at})
		contacts.sort_custom(func(a, b): return float(a.at) < float(b.at) if not is_equal_approx(float(a.at), float(b.at)) else int(a.actor.id) < int(b.actor.id))
		for index in mini(contacts.size(), int(shape.get("target_cap", contacts.size()))):
			var actor: Dictionary = contacts[index].actor
			var coefficient_scale: float = float(shape.get("following_scale", 1.0)) if index > 0 else 1.0
			if shape.has("inner_radius"):
				coefficient_scale = float(shape.inner_scale) if center.distance_to(actor.pos) <= float(shape.inner_radius) + float(actor.radius) else float(shape.outer_scale)
			var bonus: Dictionary = run._artifact_combat.modify_damage_context(run, actor, {"school": item.school, "kind": "gem_echo", "natural": false, "spell_id": "gem_echo"})
			run.resolve_fixed_item_hit(actor, float(item.raw) * coefficient_scale * float(bonus.damage_multiplier), "gem_echo")
		var visual: Dictionary = shape.duplicate(true)
		visual["kind_shape"] = str(shape.kind)
		visual["school"] = item.school
		run._emit("gem_echo", visual, 0.45)
