extends RefCounted
## Per-release ice growth traits. Status ownership remains in route_ice_status.
var _first_checks: Dictionary = {}
var _second_checks: Dictionary = {}
var _shatter_ready: Dictionary = {}
var _restore_casts: Dictionary = {}
var _restore_ready: float = 0.0
var _retaliate_ready: float = 0.0
var armor_context: Dictionary = {}


func clear() -> void:
	_first_checks.clear()
	_second_checks.clear()
	_shatter_ready.clear()
	_restore_casts.clear()
	_restore_ready = 0.0
	_retaliate_ready = 0.0
	armor_context.clear()


func extra_frost(run, actor: Dictionary, context: Dictionary, result: Dictionary, pre: Dictionary, ordinal: int) -> int:
	if not _active(run) or not bool(context.get("natural", false)):
		return 0
	var level: Dictionary = context.get("ice_level", {})
	var cast_id: String = str(context.get("cast_id", ""))
	var id: String = str(context.get("spell_id", ""))
	var extra: int = 0
	if id in ["I02", "I03"] and bool(context.get("growth_primary", true)) and bool(context.get("ice_direct", false)) and float(result.get("damage", 0.0)) > 0.0 and int(level.get("first_direct_extra_frost", 0)) > 0 and not _first_checks.has(cast_id):
		_first_checks[cast_id] = true
		if float(actor.health) > 0.0 and not bool(pre.get("ready", false)) and int(pre.get("stacks", 0)) in [1, 2]:
			extra += int(level.first_direct_extra_frost)
	if id == "I06" and not bool(context.get("ice_direct", false)) and ordinal == 2 and int(level.get("second_area_extra_frost", 0)) > 0:
		var key: String = "%s:%s" % [cast_id, actor.id]
		if not _second_checks.has(key) and float(actor.health) > 0.0 and float(result.get("damage", 0.0)) > 0.0 and not bool(pre.get("ready", false)):
			_second_checks[key] = true
			extra += int(level.second_area_extra_frost)
	return extra


func on_window_created(run, actor: Dictionary, context: Dictionary) -> void:
	var level: Dictionary = context.get("ice_level", {})
	if not _active(run) or not bool(context.get("natural", false)) or str(context.get("spell_id", "")) != "I08" or float(actor.health) <= 0.0 or float(level.get("window_restore", 0.0)) <= 0.0:
		return
	var cast_id: String = str(context.get("cast_id", ""))
	if _restore_casts.has(cast_id):
		return
	_restore_casts[cast_id] = true
	var clock: float = run._spell_combat.ice.status.clock
	if clock + 0.000001 < _restore_ready:
		return
	_restore_ready = clock + float(level.window_restore_cooldown)
	var actual: float = run.restore_player_shield(float(level.window_restore), "I08")
	run._emit("ice_artifact_restore", {"spell_id": "I08", "pos": run.player.pos, "amount": actual, "requested": float(level.window_restore)}, 0.5)


func shatter_effect(run, actor: Dictionary, context: Dictionary) -> Dictionary:
	var effect: Dictionary = {"damage_multiplier": 1.0, "retain_frost": 0, "fragment_frost_targets": 0, "fragment_frost_stacks": 0}
	if not _active(run) or not bool(context.get("natural", false)):
		return effect
	var level: Dictionary = context.get("ice_level", {})
	effect.fragment_frost_targets = int(level.get("fragment_frost_targets", 0))
	effect.fragment_frost_stacks = int(level.get("fragment_frost_stacks", 0))
	var key: int = int(actor.id)
	var clock: float = run._spell_combat.ice.status.clock
	if float(actor.health) > 0.0 and float(level.get("natural_shatter_multiplier", 1.0)) > 1.0 and clock + 0.000001 >= float(_shatter_ready.get(key, 0.0)):
		_shatter_ready[key] = clock + float(level.shatter_per_actor_cooldown)
		effect.damage_multiplier = float(level.natural_shatter_multiplier)
		effect.retain_frost = int(level.retained_frost)
	return effect


func on_player_damaged(run, shield_loss: float, health_loss: float) -> void:
	var level: Dictionary = armor_context.get("ice_level", {})
	if not _active(run) or shield_loss + health_loss <= 0.0 or run._spell_combat.ice.defense_bonus() <= 0.0 or int(level.get("retaliate_frost", 0)) <= 0:
		return
	var clock: float = run._spell_combat.ice.status.clock
	if clock + 0.000001 < _retaliate_ready:
		return
	var actor: Dictionary = run.nearest_target(run.player.pos, float(level.retaliate_range), true)
	if actor.is_empty():
		return
	_retaliate_ready = clock + float(level.retaliate_cooldown)
	run._spell_combat.ice.apply_frost(run, actor, int(level.retaliate_frost), {"kind": "ice_status", "school": "ice", "spell_id": "I09", "natural": false})


func _active(run) -> bool:
	return run.phase == "combat" and not bool(run.paused) and float(run.player.health) > 0.0
