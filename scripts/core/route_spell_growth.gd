extends RefCounted
## The existing three spell levels own these traits. No item ownership gates.

const SOURCE = "res://data/route_spell_growth.json"
var patches: Array = []
var _patch_casts: Dictionary = {}
var _patch_last_hit: Dictionary = {}
var _matured: Dictionary = {}
var _echo_count: int = 0
var _speed_until: float = 0.0
var _speed_bonus: float = 0.0


static func apply_source(spells: Dictionary, source: Dictionary) -> Dictionary:
	if not source.get("spells") is Dictionary or source.spells.size() != 20 or not source.get("retired_items") is Dictionary or source.retired_items.size() != 32:
		return {"ok": false, "error": "火冰法术三级成长表缺失或数量无效。"}
	for id in source.spells:
		var spec: Dictionary = source.spells[id]
		if not spells.has(id) or not spec.get("levels") is Array or spec.levels.size() != 3:
			return {"ok": false, "error": "法术三级成长源无效：" + str(id)}
		for level in spec.levels:
			if not level is Dictionary or level.is_empty():
				return {"ok": false, "error": "法术成长等级无效：" + str(id)}
			for value in level.values():
				if (value is int or value is float) and (not is_finite(float(value)) or float(value) < 0.0):
					return {"ok": false, "error": "法术成长数值无效：" + str(id)}
	for id in source.spells:
		spells[id].levels = source.spells[id].levels.duplicate(true)
		spells[id]["growth_version"] = str(source.get("version", ""))
	return {"ok": true, "error": ""}


func clear() -> void:
	patches.clear()
	_patch_casts.clear()
	_patch_last_hit.clear()
	_matured.clear()
	_echo_count = 0
	_speed_until = 0.0
	_speed_bonus = 0.0


func move_speed_bonus(run) -> float:
	return _speed_bonus if _active(run) and float(run.time) < _speed_until else 0.0


func burn_parameters(run, base: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	var brand: Dictionary = run._owned_spell("F11")
	if not brand.is_empty():
		var level: Dictionary = run.get_spell_stats(brand).level
		result.duration = float(level.get("burn_duration", result.duration))
		result.maximum_ticks = int(level.get("burn_maximum_ticks", result.maximum_ticks))
	return result


func fire_vulnerability(run, actor: Dictionary) -> float:
	# Read the released F06 zone, including when its slot was later replaced.
	var bonus: float = 0.0
	var kinds: Array = []
	for area in run._spell_combat.zones:
		if str(area.spell_id) in ["F03", "F05", "F06"] and bool(area.context.get("natural", false)) and float(area.get("active_delay", 0.0)) <= 0.000001 and actor.pos.distance_to(area.pos) <= float(area.radius) + float(actor.radius) and str(area.spell_id) not in kinds:
			kinds.append(str(area.spell_id))
	if kinds.size() < 2 or "F06" not in kinds:
		return bonus
	for zone in run._spell_combat.zones:
		if zone.spell_id == "F06" and bool(zone.context.get("natural", false)) and actor.pos.distance_to(zone.pos) <= float(zone.radius) + float(actor.radius):
			bonus = maxf(bonus, float(zone.context.get("growth_level", {}).get("overlap_fire_vulnerability", 0.0)))
	return bonus


func on_hit(run, actor: Dictionary, context: Dictionary, result: Dictionary) -> void:
	if not _active(run) or not bool(context.get("natural", false)) or str(context.get("spell_id", "")) != "F01" or not bool(result.get("critical", false)) or float(result.get("damage", 0.0)) <= 0.0:
		return
	var level: Dictionary = context.get("growth_level", {})
	var cast_id: String = str(context.get("cast_id", ""))
	if float(level.get("crit_patch_coefficient", 0.0)) <= 0.0 or _patch_casts.has(cast_id):
		return
	_patch_casts[cast_id] = true
	var ctx: Dictionary = context.duplicate(true)
	ctx.merge({"natural": false, "kind": "growth_patch", "ignite": false, "detonate": false, "gem_body_scale": 1.0, "field_bonus": 0.0}, true)
	patches.append({"pos": actor.pos, "radius": float(level.crit_patch_radius), "remaining": float(level.crit_patch_duration),
		"interval": float(level.crit_patch_interval), "tick_remaining": float(level.crit_patch_interval),
		"coefficient": float(level.crit_patch_coefficient), "born_at": float(run.time), "context": ctx})
	run._emit("artifact_patch", {"pos": actor.pos, "radius": float(level.crit_patch_radius), "spell_id": "F01"}, float(level.crit_patch_duration))


func on_cast(run, spell: Dictionary, target: Dictionary, context: Dictionary) -> void:
	if not _active(run) or not bool(context.get("natural", false)):
		return
	var level: Dictionary = context.get("growth_level", {})
	if str(spell.id) == "F09" and int(context.get("hit_count", 0)) > 0 and float(level.get("hit_move_speed_bonus", 0.0)) > 0.0:
		_speed_bonus = float(level.hit_move_speed_bonus)
		_speed_until = float(run.time) + float(level.hit_move_speed_duration)
	if str(spell.id) != "F08" or int(level.get("echo_every", 0)) <= 0:
		return
	_echo_count = int(spell.get("growth_echo_count", 0)) + 1
	spell["growth_echo_count"] = _echo_count
	if _echo_count >= int(level.echo_every):
		_echo_count = 0
		spell["growth_echo_count"] = 0
		run.cast_extra_spell("F08", target, float(level.echo_scale))


func on_area_matured(run, context: Dictionary, pos: Vector2, age: float) -> void:
	var level: Dictionary = context.get("growth_level", {})
	var cast_id: String = str(context.get("cast_id", ""))
	if not _active(run) or str(context.get("spell_id", "")) != "F06" or not bool(context.get("natural", false)) or _matured.has(cast_id) or float(level.get("mature_coefficient", 0.0)) <= 0.0 or age + 0.000001 < float(level.mature_after):
		return
	_matured[cast_id] = true
	var ctx: Dictionary = context.duplicate(true)
	ctx.merge({"natural": false, "kind": "growth_burst", "ignite": false, "detonate": false, "gem_body_scale": 1.0, "field_bonus": 0.0}, true)
	run._spell_combat._area_hit(run, pos, float(level.mature_radius), float(level.mature_coefficient), ctx)
	run._emit("artifact_explosion", {"pos": pos, "radius": float(level.mature_radius), "spell_id": "F06"}, 0.5)


func update(run, dt: float) -> void:
	if not _active(run):
		return
	var retained: Array = []
	var candidates: Dictionary = {}
	for patch in patches:
		var elapsed: float = minf(minf(dt, float(patch.remaining)), maxf(0.0, float(run.time) - float(patch.born_at)))
		patch.remaining = maxf(0.0, float(patch.remaining) - elapsed)
		patch.tick_remaining -= elapsed
		while float(patch.tick_remaining) <= 0.000001 and _active(run):
			patch.tick_remaining += float(patch.interval)
			for actor in run.actors:
				if float(actor.health) > 0.0 and actor.pos.distance_to(patch.pos) <= float(patch.radius) + float(actor.radius):
					var strength: float = float(patch.coefficient) * float(patch.context.get("damage_scale", 1.0))
					if not candidates.has(actor.id) or strength > float(candidates[actor.id].strength):
						candidates[actor.id] = {"actor": actor, "patch": patch, "strength": strength}
		if float(patch.remaining) > 0.000001:
			retained.append(patch)
	patches = retained
	for id in candidates:
		var value: Dictionary = candidates[id]
		if float(run.time) - float(_patch_last_hit.get(id, -INF)) + 0.000001 >= float(value.patch.interval):
			_patch_last_hit[id] = float(run.time)
			run.resolve_spell_hit(value.actor, float(value.patch.coefficient), value.patch.context)


func _active(run) -> bool:
	return run.phase == "combat" and not bool(run.paused) and float(run.player.health) > 0.0
