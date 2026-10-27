extends RefCounted
## Continuous-route fire combat. All timings/damage come from the approved sources.
## This component owns pending spells, projectiles, spirits and zones; renderers read it.

const FireStatus = preload("res://scripts/core/route_fire_status.gd")
const SpellGrowth = preload("res://scripts/core/route_spell_growth.gd")
var growth = SpellGrowth.new()
const IceCombat = preload("res://scripts/core/route_ice_combat.gd")
const LightningCombat = preload("res://scripts/core/route_lightning_combat.gd")
const WindCombat = preload("res://scripts/core/route_wind_combat.gd")
const EarthCombat = preload("res://scripts/core/route_earth_combat.gd")
const SpiritCombat = preload("res://scripts/core/route_spirit_combat.gd")
const BoltMotion = preload("res://scripts/core/route_fire_bolt_motion.gd")
const BOLT_END_LIMIT := 256 # Bounded read-only presentation journal, not gameplay effects.
const BOLT_END_RETENTION := 1.0
var _bolt_ends: Array = []
var _bolt_end_seq := 0
const RAIN_IMPACT_LIMIT := 256 # Read-only completed falls, never gameplay effects.
const RAIN_IMPACT_RETENTION := 1.0
var _rain_impacts: Array = []
var _rain_impact_seq := 0
const BEAM_FACT_LIMIT := 256 # Pure presentation facts; never gameplay events.
const BEAM_FACT_RETENTION := 1.0
var _beam_facts: Array = []
var _beam_fact_seq := 0
var _beam_visual_sources: Dictionary = {}
var _next_beam_echo_parent := -1
const BOMB_FACT_LIMIT := 512 # Bounded display facts; no gameplay events.
const BOMB_FACT_RETENTION := 1.0
var _bomb_facts: Array = []
var _bomb_fact_seq := 0
const WAVE_FACT_LIMIT := 256 # Read-only releases, never gameplay effects.
const WAVE_FACT_RETENTION := 1.0
var _wave_facts: Array = []
var _wave_fact_seq := 0
const VORTEX_FACT_LIMIT := 512 # Observations only, not gameplay effects.
const VORTEX_PATH_LIMIT := 256
const VORTEX_PATH_POINTS := 64
const VORTEX_FACT_RETENTION := 1.0
const VORTEX_PATH_RETENTION := 0.3
var _vortex_facts: Array = []
var _vortex_fact_seq := 0
var _vortex_paths: Dictionary = {}
const FIELD_FACT_LIMIT := 512 # Bounded observations, never gameplay events.
const FIELD_FACT_RETENTION := 1.0
var _field_facts: Array = []
var _field_fact_seq := 0
const BRAND_FACT_LIMIT := 256 # Completed primary contacts, never gameplay events.
const BRAND_FACT_RETENTION := 1.0
var _brand_facts: Array = []
var _brand_fact_seq := 0
var zones: Array = []
var pending: Array = []
var spirits: Array = []
var runtime: Dictionary = {}
var field_grace: float = 0.0
var _run_ref: WeakRef
var _next_cast: int = 1
var _next_zone: int = 1
var _area_last_hit: Dictionary = {}
var fire_status
var _last_status_time: float = -INF
var _ignited_cast_targets: Dictionary = {}
var _field_grace_bonus: float = 0.0
var ice
var ice_status
var lightning
var wind
var earth
var spirit_school


func configure(run) -> Dictionary:
	var file = FileAccess.open("res://data/route_spell_runtime.json", FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "缺少连续路线法术运行补充表。"}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.has_all(["rain", "spirit", "effects", "wave", "fire"]):
		return {"ok": false, "error": "连续路线法术运行补充表无效。"}
	var fire_error: String = validate_fire_source(run, parsed.fire)
	if not fire_error.is_empty():
		return {"ok": false, "error": fire_error}
	if not BoltMotion.validate(parsed.fire.get("bolt_flight")):
		return {"ok": false, "error": "焰弹飞行参数无效。"}
	runtime = parsed
	fire_status = FireStatus.new()
	fire_status.configure(runtime.get("fire", {}).get("burning", {}))
	ice = IceCombat.new()
	var ice_result: Dictionary = ice.configure(run._ice_source)
	if not ice_result.ok:
		return ice_result
	ice_status = ice.status
	lightning = LightningCombat.new()
	var lightning_result: Dictionary = lightning.configure(run._lightning_source)
	if not lightning_result.ok:
		return lightning_result
	wind = WindCombat.new()
	earth = EarthCombat.new()
	spirit_school = SpiritCombat.new()
	for entry in [[wind, run._wind_source], [earth, run._earth_source], [spirit_school, run._spirit_source]]:
		var school_result: Dictionary = entry[0].configure(entry[1])
		if not school_result.ok:
			return school_result
	_run_ref = weakref(run)
	_next_cast = 1
	_next_zone = 1
	stop_room()
	return {"ok": true, "error": ""}


func validate_fire_source(run, fire: Variant) -> String:
	if not fire is Dictionary or not fire.get("spell_ids") is Array or not fire.get("initial_ids") is Array or not fire.get("burning") is Dictionary:
		return "正式火系参数缺失或类型无效。"
	if fire.spell_ids.size() != 10 or fire.initial_ids.size() != 3:
		return "正式火系法术与起始候选数量无效。"
	var distinct: Dictionary = {}
	for id in fire.spell_ids:
		if not id is String or distinct.has(id) or not run._base.spells.has(id):
			return "正式火系法术ID无效。"
		var source: Dictionary = run._base.spells[id]
		if str(source.get("school", "")) != "fire" or not bool(source.get("active", true)):
			return "正式火系包含未开放或其他学派法术。"
		distinct[id] = true
	var initial: Dictionary = {}
	for id in fire.initial_ids:
		if not id is String or not distinct.has(id) or initial.has(id) or str(run._base.spells[id].kind) == "passive":
			return "正式火系起始候选无效。"
		initial[id] = true
	var burn: Dictionary = fire.burning
	for key in ["duration", "interval", "coefficient", "maximum_ticks"]:
		var value: Variant = burn.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0.0:
			return "正式火系燃烧参数无效：" + key
	if float(burn.maximum_ticks) != floorf(float(burn.maximum_ticks)) or not is_equal_approx(float(burn.duration) / float(burn.interval), float(burn.maximum_ticks)):
		return "正式火系燃烧时长与计划跳数不一致。"
	return ""


func stop_room():
	_bolt_ends.clear()
	_bolt_end_seq = 0
	_rain_impacts.clear()
	_rain_impact_seq = 0
	_beam_facts.clear()
	_beam_fact_seq = 0
	_beam_visual_sources.clear()
	_next_beam_echo_parent = -1
	_bomb_facts.clear()
	_bomb_fact_seq = 0
	_wave_facts.clear()
	_wave_fact_seq = 0
	_vortex_facts.clear()
	_vortex_fact_seq = 0
	_vortex_paths.clear()
	_field_facts.clear()
	_field_fact_seq = 0
	_brand_facts.clear()
	_brand_fact_seq = 0
	zones.clear()
	growth.clear()
	pending.clear()
	spirits.clear()
	field_grace = 0.0
	_field_grace_bonus = 0.0
	_area_last_hit.clear()
	_ignited_cast_targets.clear()
	_last_status_time = -INF
	if fire_status != null:
		fire_status.clear()
	if ice != null:
		ice.stop_room()
	for module in school_modules():
		module.stop_room()
	var run = _run_ref.get_ref() if _run_ref != null else null
	if run != null:
		for spell in run.spells: spell.erase("growth_echo_count")
		for actor in run.actors:
			actor["ice_frozen"] = false


func get_snapshot() -> Dictionary:
	var run = _run_ref.get_ref() if _run_ref != null else null
	var result: Dictionary = {"spell_zones": zones.duplicate(true), "spell_pending": pending.duplicate(true), "spirits": spirits.duplicate(true), "field_attack_bonus": field_attack_bonus(),
		"fire_bolt_ends": _bolt_ends.duplicate(true),
		"fire_rain_impacts": _rain_impacts.duplicate(true),
		"fire_beam_facts": _beam_facts.duplicate(true),
		"fire_bomb_facts": _bomb_facts.duplicate(true),
		"fire_wave_facts": _wave_facts.duplicate(true),
		"fire_vortex_facts": _vortex_facts.duplicate(true),
		"fire_vortex_paths": _vortex_paths.duplicate(true),
		"fire_field_facts": _field_facts.duplicate(true),
		"fire_brand_facts": _brand_facts.duplicate(true),
		"fire_field_state": _field_visual_state(run) if run != null else {},
		"fire_wave_speed": growth.wave_speed_snapshot(run) if run != null and growth.has_method("wave_speed_snapshot") else {},
		"fire_bomb_status_facts": fire_status.get_bomb_visual_facts() if fire_status != null and fire_status.has_method("get_bomb_visual_facts") else [],
		"spell_burns": fire_status.snapshot(run) if fire_status != null else [],
		"fire_reignite_pending": fire_status.reignite_pending.duplicate(true) if fire_status != null else []}
	if ice != null:
		result.merge(ice.get_snapshot(run), true)
	for module in school_modules():
		result.merge(module.get_snapshot(run), true)
	return result


func is_fire_spell(id: String) -> bool:
	return id in runtime.get("fire", {}).get("spell_ids", [])


func fire_spell_count(run) -> int:
	var distinct: Dictionary = {}
	for spell in run.spells:
		if is_fire_spell(str(spell.id)):
			distinct[str(spell.id)] = true
	return distinct.size()


func before_damage_tick(run, dt: float) -> void:
	if ice != null:
		ice.before_tick(run, dt)
	for module in school_modules():
		module.before_tick(run, dt)
	if run.phase != "combat" or run.paused or fire_status == null or absf(_last_status_time - float(run.time)) <= 0.000000001:
		return
	_last_status_time = float(run.time)
	# Both live status damage and subsequent spell impacts read the same
	# current grace value at the boundary of this combat step.
	field_grace = maxf(0.0, field_grace - maxf(0.0, dt))
	fire_status.update(run, dt)


func apply_burn(run, actor: Dictionary, source: String = "fixture") -> bool:
	return fire_status.apply_burn(run, actor, source)


func has_burn(run, actor: Dictionary) -> bool:
	return fire_status.has_burn(run, actor)


func remove_actor_status(actor_id: int) -> void:
	if fire_status != null:
		fire_status.remove_actor(actor_id)
	if ice != null:
		ice.status.remove_actor(actor_id)
	for module in school_modules():
		module.remove_actor_status(actor_id)


func detonate_burn(run, actor: Dictionary, multiplier: float, natural: bool = false, cast_id: Variant = -1) -> float:
	before_damage_tick(run, 0.0)
	return fire_status.detonate_burn(run, actor, multiplier, natural, cast_id)


func stats_for(spell: Dictionary) -> Dictionary:
	var run = _run_ref.get_ref() if _run_ref != null else null
	if run == null or spell.is_empty():
		return {}
	if run.has_method("get_spell_stats"):
		return run.get_spell_stats(spell).duplicate(true)
	var result: Dictionary = run._base.spells[spell.id].duplicate(true)
	result["level"] = result.levels[int(spell.level) - 1].duplicate(true)
	return result


func fire_bonus() -> float:
	var run = _run_ref.get_ref() if _run_ref != null else null
	if run == null:
		return 0.0
	var mastery: Dictionary = run._owned_spell("F02")
	return float(stats_for(mastery).level.fire_bonus) if not mastery.is_empty() else 0.0


func crit_multiplier_bonus() -> float:
	var run = _run_ref.get_ref() if _run_ref != null else null
	if run == null:
		return 0.0
	var mastery: Dictionary = run._owned_spell("F02")
	return float(stats_for(mastery).level.crit_bonus) if not mastery.is_empty() else 0.0


func crit_rate_bonus() -> float:
	var run = _run_ref.get_ref() if _run_ref != null else null
	if run == null: return 0.0
	var mastery: Dictionary = run._owned_spell("F02")
	return float(stats_for(mastery).level.get("fire_crit_rate_add", 0.0)) if not mastery.is_empty() else 0.0


func field_attack_bonus() -> float:
	var run = _run_ref.get_ref() if _run_ref != null else null
	if run == null:
		return 0.0
	for zone in zones:
		if zone.kind == "field" and run.player.pos.distance_to(zone.pos) <= float(zone.radius) + 0.000001:
			return float(zone.attack_bonus)
	if field_grace > 0.000001:
		return _field_grace_bonus
	return 0.0


func update(run, dt: float):
	if run.phase != "combat" or run.paused or dt <= 0.0:
		return
	while not _rain_impacts.is_empty() and float(_rain_impacts[0].time) < float(run.time) - RAIN_IMPACT_RETENTION:
		_rain_impacts.pop_front()
	while not _beam_facts.is_empty() and float(_beam_facts[0].time) < float(run.time) - BEAM_FACT_RETENTION:
		_beam_facts.pop_front()
	for id in _beam_visual_sources.keys():
		if float(_beam_visual_sources[id].expires) < float(run.time): _beam_visual_sources.erase(id)
	for index in range(_bomb_facts.size() - 1, -1, -1):
		if float(_bomb_facts[index].retain_until) < float(run.time): _bomb_facts.remove_at(index)
	while not _wave_facts.is_empty() and float(run.time) - float(_wave_facts[0].time) > WAVE_FACT_RETENTION:
		_wave_facts.pop_front()
	while not _vortex_facts.is_empty() and float(run.time) - float(_vortex_facts[0].time) > VORTEX_FACT_RETENTION:
		_vortex_facts.pop_front()
	while not _field_facts.is_empty() and float(run.time) - float(_field_facts[0].time) > FIELD_FACT_RETENTION:
		_field_facts.pop_front()
	while not _brand_facts.is_empty() and float(run.time) - float(_brand_facts[0].time) > BRAND_FACT_RETENTION:
		_brand_facts.pop_front()
	before_damage_tick(run, dt)
	growth.update(run, dt)
	_update_pending(run)
	_update_projectiles(run, dt)
	_update_spirits(run, dt)
	_update_zones(run, dt)
	ice.update_existing(run, dt)
	for module in school_modules():
		module.update_existing(run, dt)
	# Existing impacts and zones consume only fuel already present at their
	# hit; a same-step delayed G04 re-ignition is applied before new releases.
	fire_status.flush_reignites(run)
	for spell in run.spells:
		if run.phase != "combat":
			break
		var stats: Dictionary = stats_for(spell)
		spell.windup = float(stats.get("windup", 0.0))
		var base_cd = float(stats.level.get("cooldown", stats.get("cooldown", 0.0)))
		var reduction = float(run._base.fire_synergy.cooldown_reduction) if is_fire_spell(str(spell.id)) and fire_spell_count(run) >= int(run._base.fire_synergy.distinct_spells) else 0.0
		if ice.is_ice_spell(str(spell.id)):
			reduction += ice.cooldown_bonus(run)
		else:
			var module = spell_module(str(spell.id), str(stats.get("school", "")))
			if module != null: reduction += module.cooldown_bonus(run)
		if run.has_method("artifact_cooldown_reduction"):
			reduction += run.artifact_cooldown_reduction()
		if run.has_method("gem_core"): reduction = run._gem_combat.cooldown_reduction(reduction)
		spell.cooldown = maxf(float(run._base.limits.minimum_cooldown), base_cd * (1.0 - minf(reduction, float(run._base.limits.cooldown_reduction)))) if base_cd > 0.0 else 0.0
		spell.range = float(stats.level.get("range", stats.get("range", 0.0)))
		spell.remaining = maxf(0.0, float(spell.remaining) - dt)
		if run.has_method("gem_core") and run._gem_combat.suspend_cast(str(stats.kind)): continue
		if stats.kind == "passive":
			continue
		if spell.cast_remaining > 0.0:
			spell.cast_remaining = maxf(0.0, float(spell.cast_remaining) - dt)
			if spell.cast_remaining <= 0.000001:
				var target: Dictionary = {}
				if ice.is_ice_spell(str(spell.id)):
					target = ice.finish_target(run, spell, stats)
				elif spell_module(str(spell.id), str(stats.get("school", ""))) != null:
					target = spell_module(str(spell.id), str(stats.school)).finish_target(run, spell, stats)
				else:
					target = legal_target(run, spell, stats)
				if not target.is_empty():
					_cast(run, spell, stats, target, true, 1.0)
				else:
					spell.target_id = -1
		elif spell.remaining <= 0.000001:
			var target = legal_target(run, spell, stats)
			if not target.is_empty():
				spell.cast_remaining = float(spell.windup)
				spell.target_id = int(target.get("id", -1))
				spell["locked_pos"] = target.pos
				run._emit("cast", {"pos": run.player.pos, "spell_id": spell.id, "target_id": spell.target_id}, spell.windup)
	_sync_spirit(run)


func legal_target(run, spell: Dictionary, stats: Dictionary = {}) -> Dictionary:
	if stats.is_empty():
		stats = stats_for(spell)
	if ice != null and ice.is_ice_spell(str(spell.id)):
		return ice.legal_target(run, spell, stats)
	var module = spell_module(str(spell.id), str(stats.get("school", "")))
	if module != null:
		return module.legal_target(run, spell, stats)
	if stats.kind == "passive" or run.phase != "combat" or run.player.health <= 0.0:
		return {}
	if stats.kind == "shield":
		if run.player.shield >= run.player.max_shield - 0.000001 or not _has_live_enemy(run):
			return {}
		return {"id": -1, "pos": run.player.pos}
	if stats.kind == "spirit" and spirits.size() >= int(stats.count):
		return {}
	var maximum_range = float(stats.level.get("radius", 0.0)) if stats.kind == "wave" else float(stats.level.get("range", stats.get("range", 0.0)))
	var clearance = float(run._runtime.bolt_collision_radius) if stats.kind == "bolt" else (float(stats.width) * 0.5 if stats.kind == "beam" else 0.0)
	if stats.kind != "bomb":
		return run.nearest_target(run.player.pos, maximum_range, stats.kind in ["bolt", "beam", "brand"], clearance)
	var selected: Dictionary = {}
	for actor in run.actors:
		if actor.health <= 0.0 or run.player.pos.distance_to(actor.pos) > maximum_range:
			continue
		if selected.is_empty() or actor.health > selected.health or (is_equal_approx(actor.health, selected.health) and actor.id < selected.id):
			selected = actor
	return selected


func cast_extra(run, spell_id: String, target: Dictionary = {}, damage_scale: float = 1.0) -> bool:
	var spell: Dictionary = run._owned_spell(spell_id)
	if spell.is_empty():
		return false
	var stats: Dictionary = stats_for(spell)
	var legal = legal_target(run, spell, stats)
	if legal.is_empty():
		return false
	# Extra attacks use a fresh local casting record and never alter normal windup/CD.
	var extra = spell.duplicate(true)
	if target.is_empty() or float(target.get("health", 1.0)) <= 0.0:
		target = legal
	extra["locked_pos"] = target.pos
	_cast(run, extra, stats, target, false, damage_scale)
	return true


func _cast(run, spell: Dictionary, stats: Dictionary, target: Dictionary, natural: bool, damage_scale: float):
	var body_scale: float = 1.0
	if run.has_method("gem_core"):
		var prepared: Dictionary = run._gem_combat.prepare_cast(stats, natural)
		stats = prepared.stats
		body_scale = float(prepared.body_scale)
	var level: Dictionary = stats.level
	var context = {"cast_id": _next_cast, "natural": natural, "spell_id": spell.id, "kind": stats.kind, "damage_scale": damage_scale, "field_bonus": field_attack_bonus(), "pos": target.pos, "school": str(stats.get("school", "fire"))}
	context["gem_body_scale"] = body_scale
	context["growth_level"] = level.duplicate(true)
	context["spell_level"] = int(spell.level)
	_next_cast += 1
	if str(spell.id) == "F08": _capture_beam_visual_source(run, stats, context)
	if natural:
		spell.cast_remaining = 0.0
		spell.remaining = float(spell.cooldown)
		spell.target_id = int(target.get("id", -1))
		run.casts += 1
	if ice != null and ice.is_ice_spell(str(spell.id)):
		ice.cast(run, spell, stats, target, context)
		if natural and run.has_method("on_spell_cast"):
			run.on_spell_cast(spell, target, context)
		return
	var module = spell_module(str(spell.id), str(stats.get("school", "")))
	if module != null:
		module.cast(run, spell, stats, target, context)
		if natural and run.has_method("on_spell_cast"):
			run.on_spell_cast(spell, target, context)
		return
	match stats.kind:
		"bolt":
			context["ignite"] = true
			_spawn_bolt(run, spell, stats, target, float(level.coefficient), context)
			if float(level.secondary) > 0.0:
				_queue(run, float(stats.secondary_delay), "secondary_bolt", {"stats": stats, "context": context, "coefficient": float(level.secondary), "spell": spell.duplicate(true)})
		"beam":
			context["ignite"] = true
			var direction: Vector2 = (target.pos - run.player.pos).normalized()
			var end: Vector2 = run._clip_motion(run.player.pos, direction * float(spell.range), float(stats.width) * 0.5)
			_beam(run, run.player.pos, end, float(stats.width) * 0.5, float(level.coefficient), context, true)
			if float(level.secondary) > 0.0:
				var pulse_context: Dictionary = context.duplicate(true)
				pulse_context["ignite"] = false
				_queue(run, float(stats.secondary_delay), "beam_pulse", {"from": run.player.pos, "to": end, "width": float(stats.width) * 0.5, "coefficient": float(level.secondary), "context": pulse_context})
		"spirit":
			_fill_spirits(run, stats, context)
		"rain":
			context["ignite"] = true
			var center: Vector2 = target.pos
			var drops = int(level.drops)
			var last_delay = float(stats.impact_delay) + (drops - 1) * float(stats.interval)
			var rain_zone = _zone("rain", spell.id, center, float(stats.radius), last_delay, 0.0, 0.0, context)
			rain_zone["release_pos"] = run.player.pos # Presentation source; not used by rules.
			rain_zone["terminal"] = false
			rain_zone["active_delay"] = float(stats.impact_delay)
			zones.append(rain_zone)
			for index in drops:
				var angle = run._rng.randf_range(0.0, TAU)
				var offset = Vector2.from_angle(angle) * sqrt(run._rng.randf()) * float(stats.radius) * float(runtime.rain.scatter_radius_fraction)
				var landing = run.move_body(center, offset, 0.0)
				var coefficient = float(stats.get("first_drop_coefficient", level.coefficient)) if index == 0 else float(level.coefficient)
				if index < int(stats.get("fixed_center_drops", 0)):
					landing = center
				if index == 0:
					coefficient *= float(stats.get("first_drop_damage_multiplier", 1.0))
				_queue(run, float(stats.impact_delay) + index * float(stats.interval), "rain_drop", {"pos": landing, "radius": float(runtime.rain.impact_radius), "coefficient": coefficient, "context": context, "last": index == drops - 1, "stats": stats, "center": center, "drop_index": index})
		"vortex":
			context["ignite"] = true
			context["ignite_once_per_target"] = true
			var zone = _zone("vortex", spell.id, run.player.pos, float(level.radius), float(stats.duration) + float(level.end_duration), float(stats.interval), float(level.coefficient), context)
			zone.merge({"direction": (target.pos - run.player.pos).normalized(), "speed": float(stats.speed), "travel_remaining": float(stats.duration), "first_hits": {}}, true)
			zones.append(zone)
			_observe_vortex_position(run, zone)
			_note_vortex_fact(run, "release", zone)
		"field":
			context["ignite"] = true
			context["ignite_once_per_target"] = true
			for index in range(zones.size() - 1, -1, -1):
				if zones[index].kind == "field":
					var replaced_field: Dictionary = zones[index]
					zones.remove_at(index)
					_note_field_fact(run, "replace", replaced_field)
			field_grace = 0.0
			var zone = _zone("field", spell.id, run.player.pos, float(level.radius), float(level.duration), float(stats.interval), float(level.coefficient), context)
			zone.merge({"attack_bonus": float(stats.attack_bonus), "grace": float(level.grace)}, true)
			# F06 never recursively amplifies its own persistent-area snapshot.
			zone.context.field_bonus = 0.0
			zones.append(zone)
			_note_field_fact(run, "release", zone)
		"bomb":
			var center: Vector2 = spell.get("locked_pos", target.pos)
			_queue(run, float(stats.travel_delay), "bomb", {"pos": center, "radius": float(stats.radius), "stats": stats, "context": context})
			run._emit("bomb_flight", {"from": run.player.pos, "to": center, "pos": center, "radius": float(stats.radius), "spell_id": spell.id}, float(stats.travel_delay))
			_note_bomb_fact(run, "flight", {"pos": center, "radius": stats.radius, "stats": stats, "context": context, "at": float(run.time) + float(stats.travel_delay), "from": run.player.pos})
		"wave":
			context["ignite"] = true
			if run.has_method("gem_record_shape"): run.gem_record_shape({"kind": "area", "pos": run.player.pos, "radius": float(level.radius)}, float(level.coefficient), context)
			var hit_count = 0
			var wave_hits: Array = []
			for actor in run.actors:
				if actor.health <= 0.0 or run.player.pos.distance_to(actor.pos) > float(level.radius) + float(actor.radius):
					continue
				var wave_from: Vector2 = actor.pos
				var wave_actual := _hit(run, actor, float(level.coefficient), context)
				if wave_actual > 0.0:
					hit_count += 1
				var direction: Vector2 = (actor.pos - run.player.pos).normalized()
				if direction.length_squared() < 0.000001:
					direction = Vector2(0, 1)
				var resistance = clampf(float(actor.get("push_resistance", runtime.wave.default_push_resistance)), 0.0, 1.0)
				actor.pos = run.move_body(actor.pos, direction * float(level.push) * (1.0 - resistance), float(actor.radius))
				if resistance < 1.0 and run.has_method("interrupt_enemy_by_push"):
					run.interrupt_enemy_by_push(actor, actor.pos)
				if float(level.slow) > 0.0:
					apply_slow(run, actor, float(level.slow), float(level.slow_duration), "F09")
				wave_hits.append({"actor_id": int(actor.id), "from": wave_from, "to": actor.pos, "radius": float(actor.radius), "damage": wave_actual, "alive_after": float(actor.health) > 0.0})
			run._emit("wave", {"pos": run.player.pos, "radius": float(level.radius), "spell_id": spell.id}, float(runtime.effects.impact_lifetime))
			context["hit_count"] = hit_count
			_note_wave_fact(run, context, float(level.radius), wave_hits)
		"brand":
			context["ignite"] = true
			if run.has_method("gem_record_shape"): run.gem_record_shape({"kind": "area", "pos": target.pos, "radius": 0.0, "target_cap": 1}, float(level.coefficient), context)
			var brand_contact := {"actor_id": int(target.id), "pos": target.pos, "radius": float(target.radius)}
			var actual: float = _hit(run, target, float(level.coefficient), context)
			if actual > 0.0:
				fire_status.spread(run, target, float(level.spread_radius), int(level.spread_targets), str(spell.id))
			run._emit("fire_brand", {"pos": target.pos, "spell_id": spell.id, "actor_id": target.id, "radius": float(level.spread_radius)}, float(runtime.effects.impact_lifetime))
			_note_brand_fact(run, context, brand_contact, actual, float(target.health) > 0.0)
		"shield":
			var amount: float
			if run.has_method("restore_player_shield"):
				amount = run.restore_player_shield(float(level.shield), str(spell.id))
			else:
				amount = minf(float(level.shield), float(run.player.max_shield) - float(run.player.shield))
				run.player.shield += amount
			run._emit("shield_restore", {"pos": run.player.pos, "amount": amount, "spell_id": spell.id}, float(runtime.effects.shield_lifetime))
	if natural and run.has_method("on_spell_cast"):
		run.on_spell_cast(spell, target, context)
	_sync_spirit(run)


func _note_brand_fact(run, context: Dictionary, contact: Dictionary, actual: float, alive: bool) -> void:
	_brand_fact_seq += 1
	var observed := contact.duplicate(true)
	observed["damage"] = actual
	observed["alive_after"] = alive
	_brand_facts.append({"seq": _brand_fact_seq, "time": float(run.time), "cast_id": context.cast_id,
		"natural": bool(context.natural), "spell_level": int(context.spell_level), "contact": observed})
	if _brand_facts.size() > BRAND_FACT_LIMIT: _brand_facts.pop_front()


func _queue(run, delay: float, kind: String, payload: Dictionary):
	payload["at"] = float(run.time) + delay
	payload["kind"] = kind
	pending.append(payload)


func _update_pending(run):
	var due: Array = []
	var future: Array = []
	for item in pending:
		if run.time + 0.000001 >= float(item.at):
			due.append(item)
		else:
			future.append(item)
	pending = future
	for item in due:
		if run.phase != "combat":
			return
		match item.kind:
			"secondary_bolt":
				var target: Dictionary = run.nearest_target(run.player.pos, float(item.spell.range), true, float(run._runtime.bolt_collision_radius))
				if not target.is_empty():
					_spawn_bolt(run, item.spell, item.stats, target, float(item.coefficient), item.context)
			"beam_pulse":
				_beam(run, item.from, item.to, float(item.width), float(item.coefficient), item.context, true, "pulse")
			"rain_drop":
				_area_hit(run, item.pos, float(item.radius), float(item.coefficient), item.context)
				run._emit("rain_impact", {"pos": item.pos, "radius": item.radius, "spell_id": "F03"}, float(runtime.effects.impact_lifetime))
				_note_rain_impact(run, item)
				if item.last and float(item.stats.level.ground_duration) > 0.0:
					var ground_context: Dictionary = item.context.duplicate(true)
					ground_context["ignite"] = false
					zones.append(_zone("rain_ground", "F03", item.center, float(item.stats.radius), float(item.stats.level.ground_duration), float(item.stats.ground_interval), float(item.stats.level.ground_coefficient), ground_context))
			"bomb":
				if run.has_method("gem_record_shape"):
					run.gem_record_shape({"kind": "area", "pos": item.pos, "radius": item.radius, "inner_radius": item.stats.level.center_radius,
						"inner_scale": float(item.stats.level.coefficient) * float(item.stats.get("main_center_damage_multiplier", 1.0)), "outer_scale": float(item.stats.level.outer)}, 1.0, item.context)
				var visual_hits: Array = []
				for actor in run.actors:
					if actor.health <= 0.0 or actor.pos.distance_to(item.pos) > float(item.radius) + float(actor.radius):
						continue
					var center_hit = actor.pos.distance_to(item.pos) <= float(item.stats.level.center_radius) + float(actor.radius)
					var coefficient = float(item.stats.level.coefficient) if center_hit else float(item.stats.level.outer)
					var ctx: Dictionary = item.context.duplicate(true)
					ctx["center"] = center_hit
					ctx["detonate"] = true
					ctx["detonation_multiplier"] = float(item.stats.level.get("detonation_multiplier", 0.0))
					if center_hit:
						coefficient *= float(item.stats.get("main_center_damage_multiplier", 1.0))
						ctx["crit_multiplier_bonus"] = float(item.stats.get("main_center_crit_multiplier_add", 0.0))
					var visual_pos: Vector2 = actor.pos
					var actual := _hit(run, actor, coefficient, ctx)
					if actual > 0.0: visual_hits.append({"actor_id": int(actor.id), "pos": visual_pos, "radius": float(actor.radius), "center": center_hit, "damage": actual, "alive_after": float(actor.health) > 0.0})
				run._emit("bomb_impact", {"pos": item.pos, "radius": item.radius, "spell_id": "F07"}, float(runtime.effects.impact_lifetime))
				_note_bomb_fact(run, "impact", item, visual_hits)
				if float(item.stats.level.aftershock) > 0.0:
					_queue(run, float(item.stats.aftershock_delay), "aftershock", {"pos": item.pos, "radius": item.radius, "coefficient": float(item.stats.level.aftershock), "context": item.context})
			"aftershock":
				_area_hit(run, item.pos, float(item.radius), float(item.coefficient), item.context)
				run._emit("aftershock", {"pos": item.pos, "radius": item.radius, "spell_id": "F07"}, float(runtime.effects.impact_lifetime))
				_note_bomb_fact(run, "aftershock", item)


func _observe_vortex_position(run, zone: Dictionary) -> void:
	if str(zone.spell_id) != "F05": return
	var id := int(zone.id)
	if not _vortex_paths.has(id) and _vortex_paths.size() >= VORTEX_PATH_LIMIT: return
	var points: Array = _vortex_paths.get(id, [])
	if points.is_empty() or not Vector2(points[-1].pos).is_equal_approx(zone.pos):
		points.append({"pos": zone.pos, "time": float(run.time)})
	while not points.is_empty() and float(run.time) - float(points[0].time) > VORTEX_PATH_RETENTION: points.pop_front()
	while points.size() > VORTEX_PATH_POINTS: points.pop_front()
	_vortex_paths[id] = points


func _field_visual_state(run) -> Dictionary:
	if run.phase != "combat": return {}
	var inside := false
	var zone_id := -1
	for zone in zones:
		if zone.kind == "field" and run.player.pos.distance_to(zone.pos) <= float(zone.radius) + 0.000001:
			inside = true
			zone_id = int(zone.id)
			break
	var vulnerable: Array = []
	for actor in run.actors:
		if float(actor.health) <= 0.0: continue
		var bonus: float = growth.fire_vulnerability(run, actor)
		if bonus > 0.0:
			vulnerable.append({"actor_id": int(actor.id), "pos": actor.pos, "radius": float(actor.radius), "bonus": bonus})
	return {"attack_bonus": field_attack_bonus(), "inside": inside, "zone_id": zone_id,
		"grace_remaining": field_grace, "grace_bonus": _field_grace_bonus,
		"matured_casts": growth._matured.keys().duplicate(), "vulnerable": vulnerable}


func _note_field_fact(run, phase: String, zone: Dictionary, contact: Dictionary = {}) -> void:
	if str(zone.spell_id) != "F06": return
	_field_fact_seq += 1
	var fact := {"seq": _field_fact_seq, "phase": phase, "zone_id": int(zone.id), "cast_id": int(zone.context.cast_id),
		"time": float(run.time), "pos": zone.pos, "radius": float(zone.radius),
		"spell_level": int(zone.context.get("spell_level", 1)), "natural": bool(zone.context.get("natural", false))}
	if not contact.is_empty(): fact["contact"] = contact.duplicate(true)
	_field_facts.append(fact)
	if _field_facts.size() > FIELD_FACT_LIMIT: _field_facts.pop_front()


func note_field_matured(run, context: Dictionary, pos: Vector2, radius: float) -> void:
	# Called only after the original successful maturity hit/event branch.
	_field_fact_seq += 1
	_field_facts.append({"seq": _field_fact_seq, "phase": "mature", "cast_id": int(context.cast_id),
		"time": float(run.time), "pos": pos, "radius": radius,
		"spell_level": int(context.get("spell_level", 1)), "natural": bool(context.get("natural", false))})
	if _field_facts.size() > FIELD_FACT_LIMIT: _field_facts.pop_front()


func _note_vortex_fact(run, phase: String, zone: Dictionary, contact: Dictionary = {}) -> void:
	if str(zone.spell_id) != "F05": return
	_vortex_fact_seq += 1
	var fact := {"seq": _vortex_fact_seq, "phase": phase, "zone_id": int(zone.id), "cast_id": int(zone.context.cast_id),
		"time": float(run.time), "pos": zone.pos, "radius": float(zone.radius), "direction": zone.direction,
		"spell_level": int(zone.context.get("spell_level", 1)), "natural": bool(zone.context.get("natural", false))}
	if phase == "end": fact["path"] = _vortex_paths.get(int(zone.id), []).duplicate(true)
	if not contact.is_empty(): fact["contact"] = contact.duplicate(true)
	_vortex_facts.append(fact)
	if _vortex_facts.size() > VORTEX_FACT_LIMIT: _vortex_facts.pop_front()


func _retain_vortex_paths() -> void:
	var live: Dictionary = {}
	for zone in zones:
		if str(zone.spell_id) == "F05": live[int(zone.id)] = true
	for id in _vortex_paths.keys():
		if not live.has(id): _vortex_paths.erase(id)


func _note_wave_fact(run, context: Dictionary, radius: float, hits: Array) -> void:
	# Observe original results after all area hits, pushes, slows and the event.
	_wave_fact_seq += 1
	_wave_facts.append({"seq": _wave_fact_seq, "cast_id": int(context.cast_id), "time": float(run.time),
		"pos": run.player.pos, "radius": radius, "spell_level": int(context.spell_level),
		"natural": bool(context.natural), "hits": hits.duplicate(true)})
	if _wave_facts.size() > WAVE_FACT_LIMIT: _wave_facts.pop_front()


func _note_bomb_fact(run, phase: String, item: Dictionary, hits: Array = []) -> void:
	# Observations after the original queue/hit/event, never another attack.
	var level: Dictionary = item.context.get("growth_level", {})
	var stats: Dictionary = item.get("stats", {})
	var flight_seconds := float(stats.get("travel_delay", 0.0))
	_bomb_fact_seq += 1
	_bomb_facts.append({"seq": _bomb_fact_seq, "phase": phase, "cast_id": int(item.context.cast_id),
		"spell_level": int(item.context.get("spell_level", 1)), "natural": bool(item.context.get("natural", false)),
		"pos": item.pos, "from": item.get("from", item.pos), "radius": float(item.radius),
		"center_radius": float(level.get("center_radius", 0.0)), "time": float(run.time),
		"scheduled_at": float(item.at), "flight_seconds": flight_seconds, "hits": hits.duplicate(true),
		"retain_until": float(run.time) + (flight_seconds if phase == "flight" else 0.0) + BOMB_FACT_RETENTION})
	if _bomb_facts.size() > BOMB_FACT_LIMIT: _bomb_facts.pop_front()


func _note_rain_impact(run, item: Dictionary) -> void:
	# Called only after the original damage/event branch. No hits, RNG or
	# gameplay events here; completed falls remain visible across skipped frames.
	_rain_impact_seq += 1
	_rain_impacts.append({"seq": _rain_impact_seq, "cast_id": int(item.context.cast_id),
		"drop_index": int(item.get("drop_index", -1)), "spell_level": int(item.context.get("spell_level", 1)),
		"pos": item.pos, "center": item.center, "radius": float(item.radius),
		"time": float(run.time), "scheduled_at": float(item.at),
		"fall_seconds": float(item.stats.impact_delay), "last": bool(item.last)})
	if _rain_impacts.size() > RAIN_IMPACT_LIMIT: _rain_impacts.pop_front()


func _spawn_bolt(run, spell: Dictionary, stats: Dictionary, target: Dictionary, coefficient: float, context: Dictionary):
	var id := int(run._next_projectile_id)
	var flight := BoltMotion.build(run.player.pos, target.pos, 1.0 if id % 2 == 1 else -1.0, runtime.fire.bolt_flight)
	var velocity := BoltMotion.velocity_at(flight, 0.0)
	var length = float(spell.range)
	var duration := BoltMotion.lifetime(flight, length)
	run.projectiles.append({"id": id, "spell_id": "F01", "from": run.player.pos, "to": BoltMotion.position_at(flight, duration),
		"pos": run.player.pos, "direction": velocity.normalized(), "speed": velocity.length(), "travelled": 0.0, "range": length,
		"duration": duration, "remaining": duration, "radius": float(run._runtime.bolt_collision_radius), "blast_radius": float(stats.level.radius),
		"coefficient": coefficient, "context": context.duplicate(true), "flight": flight, "age": 0.0, "born_at": float(run.time)})
	run._next_projectile_id += 1


func _update_projectiles(run, dt: float):
	while not _bolt_ends.is_empty() and float(run.time) - float(_bolt_ends[0].time) > BOLT_END_RETENTION:
		_bolt_ends.pop_front()
	var retained: Array = []
	for projectile in run.projectiles:
		if projectile.has("flight"):
			if _advance_curved_bolt(run, projectile, dt): retained.append(projectile)
			continue
		var from: Vector2 = projectile.pos
		var distance = minf(float(projectile.speed) * dt, float(projectile.range) - float(projectile.travelled))
		var to: Vector2 = from + projectile.direction * distance
		var earliest = run._first_block_contact(from, to, float(projectile.radius))
		var hit: Dictionary = {}
		for actor in run.actors:
			if actor.health <= 0.0:
				continue
			var contact: float = run.segment_circle_time(from - actor.previous, to - actor.pos, Vector2.ZERO, float(actor.radius) + float(projectile.radius))
			if contact < earliest - 0.000001 or (absf(contact - earliest) < 0.000001 and contact != INF and not hit.is_empty() and actor.id < hit.id):
				earliest = contact
				hit = actor
		if earliest != INF:
			var impact = from.lerp(to, clampf(earliest, 0.0, 1.0))
			if not hit.is_empty():
				_area_hit(run, impact, float(projectile.blast_radius), float(projectile.coefficient), projectile.context, true)
			run._emit("bolt_hit", {"pos": impact, "radius": projectile.blast_radius, "spell_id": "F01", "blocked": hit.is_empty()}, float(runtime.effects.impact_lifetime))
			_note_bolt_end(run, projectile, from, to, clampf(earliest, 0.0, 1.0), dt, "wall" if hit.is_empty() else "enemy", hit)
			continue
		projectile.pos = to
		projectile.travelled += distance
		projectile.remaining = maxf(0.0, float(projectile.remaining) - dt)
		if projectile.travelled < projectile.range - 0.000001 and run._inside_floor(projectile.pos, float(projectile.radius)):
			retained.append(projectile)
		else:
			_note_bolt_end(run, projectile, from, to, 1.0, dt, "expired", {}, true)
	run.projectiles = retained


func _advance_curved_bolt(run, projectile: Dictionary, dt: float) -> bool:
	var flight: Dictionary = projectile.flight
	# A secondary created by this tick's pending queue starts at its real
	# release time. A primary from the prior tick gets the whole next step.
	var available := minf(dt, maxf(0.0, float(run.time) - float(projectile.born_at) - float(projectile.age)))
	var elapsed := dt - available
	while available > 0.000000001:
		var age := float(projectile.age)
		var step := minf(available, float(flight.sweep_seconds))
		if age < float(flight.curve_seconds): step = minf(step, float(flight.curve_seconds) - age)
		var from: Vector2 = projectile.pos
		var next_age := age + step
		var to := BoltMotion.position_at(flight, next_age)
		var length := from.distance_to(to)
		var left := maxf(0.0, float(projectile.range) - float(projectile.travelled))
		if length > left:
			next_age = BoltMotion.age_at_segment_distance(flight, age, next_age, left)
			to = from + (to - from).normalized() * left
			step = next_age - age
			length = left
		var earliest: float = run._first_block_contact(from, to, float(projectile.radius))
		var hit: Dictionary = {}
		var a := clampf(elapsed / dt, 0.0, 1.0)
		var b := clampf((elapsed + step) / dt, 0.0, 1.0)
		for actor: Dictionary in run.actors:
			if actor.health <= 0.0: continue
			var actor_from: Vector2 = actor.previous.lerp(actor.pos, a)
			var actor_to: Vector2 = actor.previous.lerp(actor.pos, b)
			var contact: float = run.segment_circle_time(from - actor_from, to - actor_to, Vector2.ZERO, float(actor.radius) + float(projectile.radius))
			if contact < earliest - 0.000001 or (absf(contact - earliest) < 0.000001 and contact != INF and not hit.is_empty() and actor.id < hit.id):
				earliest = contact
				hit = actor
		if earliest != INF:
			var fraction := clampf(earliest, 0.0, 1.0)
			var impact := from.lerp(to, fraction)
			projectile.age = age + step * fraction
			var velocity := BoltMotion.velocity_at(flight, float(projectile.age))
			projectile.direction = velocity.normalized()
			projectile.speed = velocity.length()
			if not hit.is_empty(): _area_hit(run, impact, float(projectile.blast_radius), float(projectile.coefficient), projectile.context, true)
			run._emit("bolt_hit", {"pos": impact, "radius": projectile.blast_radius, "spell_id": "F01", "blocked": hit.is_empty()}, float(runtime.effects.impact_lifetime))
			_note_bolt_end(run, projectile, from, to, fraction, dt, "wall" if hit.is_empty() else "enemy", hit, false, elapsed, step)
			return false
		projectile.pos = to
		projectile.age = next_age
		projectile.travelled = float(projectile.travelled) + length
		projectile.remaining = maxf(0.0, float(projectile.duration) - next_age)
		var velocity := BoltMotion.velocity_at(flight, next_age)
		projectile.direction = velocity.normalized()
		projectile.speed = velocity.length()
		if float(projectile.travelled) >= float(projectile.range) - 0.000001 or not run._inside_floor(to, float(projectile.radius)):
			_note_bolt_end(run, projectile, from, to, 1.0, dt, "expired", {}, true, elapsed, step)
			return false
		elapsed += step
		available -= step
	return true


func _note_bolt_end(run, projectile: Dictionary, from: Vector2, to: Vector2, fraction: float, dt: float, reason: String, actor: Dictionary = {}, moved: bool = false, step_offset: float = 0.0, step_seconds: float = -1.0) -> void:
	# The existing hit/expiry decision above is unchanged. Never emit gameplay
	# events here, roll RNG, resolve another hit, or let visuals own collision.
	var pos := from.lerp(to, fraction)
	var normal := -Vector2(projectile.direction)
	if normal.length_squared() < 0.00000001:
		normal = -Vector2(projectile.get("flight", {}).get("direction", Vector2.UP))
	var contact := pos
	if not actor.is_empty():
		var whole_fraction := fraction if step_seconds < 0.0 else clampf((step_offset + step_seconds * fraction) / dt, 0.0, 1.0)
		var center: Vector2 = actor.previous.lerp(actor.pos, whole_fraction)
		if pos.distance_squared_to(center) > 0.00000001:
			normal = (pos - center).normalized()
		contact = pos - normal * float(projectile.radius)
	elif reason == "wall":
		for block: Dictionary in run.blocks:
			var half: Vector2 = block.size * 0.5
			var inflated := half + Vector2.ONE * float(projectile.radius)
			if absf(run.segment_rectangle_time(from, to, block.center - inflated, block.center + inflated) - fraction) < 0.000001:
				contact = pos.clamp(block.center - half, block.center + half)
				if pos.distance_squared_to(contact) > 0.00000001:
					normal = (pos - contact).normalized()
				break
	var motion_seconds := from.distance_to(to) / maxf(0.000001, float(projectile.speed))
	var distance := from.distance_to(pos)
	_bolt_end_seq += 1
	_bolt_ends.append({"seq": _bolt_end_seq, "projectile_id": int(projectile.id), "spell_id": "F01",
		"reason": reason, "pos": pos, "contact_pos": contact, "normal": normal, "from": from,
		"origin": projectile.from, "direction": projectile.direction, "radius": float(projectile.radius),
		"blast_radius": float(projectile.blast_radius), "speed": float(projectile.speed),
		"travelled": float(projectile.travelled) + (0.0 if moved else distance),
		"time": float(run.time) - dt + (motion_seconds * fraction if step_seconds < 0.0 else step_offset + step_seconds * fraction),
		"from_time": float(run.time) - dt + step_offset, "actor_id": int(actor.get("id", -1)),
		"flight": projectile.get("flight", {}).duplicate(true), "age": float(projectile.get("age", 0.0)),
		"born_at": float(projectile.get("born_at", float(run.time) - dt)), "spell_level": int(projectile.get("context", {}).get("spell_level", 1))})
	if _bolt_ends.size() > BOLT_END_LIMIT:
		_bolt_ends.pop_front()


func _fill_spirits(run, stats: Dictionary, context: Dictionary):
	while spirits.size() < int(stats.count):
		var index = spirits.size()
		var unit = {"active": true, "remaining": float(stats.duration), "attack_remaining": float(stats.level.interval), "interval": float(stats.level.interval), "pos": _spirit_position(run, index), "index": index, "stats": stats.duplicate(true), "context": context.duplicate(true)}
		spirits.append(unit)
		run._emit("summon", {"pos": unit.pos, "spell_id": "F04"}, float(runtime.effects.summon_lifetime))


func refresh_spirit_capacity(run):
	var owned: Dictionary = run._owned_spell("F04")
	if spirits.is_empty() or owned.is_empty():
		return
	var stats: Dictionary = stats_for(owned)
	var remaining = float(spirits[0].remaining)
	var before = spirits.size()
	_fill_spirits(run, stats, spirits[0].context)
	for index in range(before, spirits.size()):
		spirits[index].remaining = remaining
	_sync_spirit(run)


func _update_spirits(run, dt: float):
	var retained: Array = []
	for unit in spirits:
		unit.pos = _spirit_position(run, int(unit.index))
		unit.remaining = maxf(0.0, float(unit.remaining) - dt)
		unit.attack_remaining = maxf(0.0, float(unit.attack_remaining) - dt)
		if unit.attack_remaining <= 0.000001:
			var target: Dictionary = run.nearest_target(unit.pos, float(unit.stats.range), true)
			if not target.is_empty():
				var end: Vector2 = target.pos
				if unit.stats.level.pierce:
					end = run._clip_motion(unit.pos, (target.pos - unit.pos).normalized() * float(unit.stats.range), 0.0)
				var context: Dictionary = unit.context.duplicate(true)
				context["kind"] = "spirit"
				_beam(run, unit.pos, end, 0.0, float(unit.stats.level.coefficient) * float(unit.stats.get("normal_laser_damage_multiplier", 1.0)), context, bool(unit.stats.level.pierce))
			unit.attack_remaining = float(unit.interval)
		if unit.remaining > 0.000001:
			retained.append(unit)
	spirits = retained


func _sync_spirit(run):
	if spirits.is_empty():
		run.spirit = {"active": false, "remaining": 0.0, "pos": run.player.pos, "attack_remaining": 0.0}
	else:
		run.spirit = spirits[0].duplicate(true)


func fire_spirit_sync(run, target: Dictionary, coefficient: float) -> bool:
	if spirits.is_empty():
		return false
	var unit: Dictionary = spirits[0]
	var selected = target
	if selected.is_empty() or int(selected.get("id", -1)) < 0 or float(selected.get("health", 0.0)) <= 0.0:
		selected = run.nearest_target(unit.pos, float(unit.stats.range), true)
	if selected.is_empty() or unit.pos.distance_to(selected.pos) > float(unit.stats.range) or not run.line_is_clear(unit.pos, selected.pos):
		return false
	var end: Vector2 = selected.pos
	if unit.stats.level.pierce:
		end = run._clip_motion(unit.pos, (selected.pos - unit.pos).normalized() * float(unit.stats.range), 0.0)
	var context = {"cast_id": -1, "natural": false, "spell_id": "F04", "kind": "artifact_sync", "damage_scale": 1.0, "field_bonus": field_attack_bonus()}
	_beam(run, unit.pos, end, 0.0, coefficient, context, bool(unit.stats.level.pierce))
	return true


func _spirit_position(run, index: int) -> Vector2:
	var offset: Array = run._runtime.spirit_offset
	var displacement = Vector2(float(offset[0]) + float(runtime.spirit.additional_offset_x) * index, float(offset[1]))
	return run.move_body(run.player.pos, displacement, float(runtime.spirit.body_radius))


func _zone(kind: String, spell_id: String, center: Vector2, radius: float, duration: float, interval: float, coefficient: float, context: Dictionary) -> Dictionary:
	var run = _run_ref.get_ref() if _run_ref != null else null
	var born_at: float = float(run.time) if run != null else 0.0
	var zone = {"id": _next_zone, "kind": kind, "spell_id": spell_id, "pos": center, "radius": radius, "remaining": duration, "duration": duration, "interval": interval, "tick_remaining": interval, "coefficient": coefficient, "context": context.duplicate(true), "terminal": true, "age": 0.0, "born_at": born_at}
	_next_zone += 1
	return zone


func _update_zones(run, dt: float):
	var retained: Array = []
	var candidates: Dictionary = {}
	var expired: Array = []
	for zone in zones:
		var elapsed = minf(minf(dt, float(zone.remaining)), maxf(0.0, float(run.time) - float(zone.get("born_at", -INF))))
		zone.age = float(zone.get("age", 0.0)) + elapsed
		if zone.has("active_delay"):
			zone.active_delay = maxf(0.0, float(zone.active_delay) - elapsed)
		if zone.kind == "vortex":
			var move_time = minf(elapsed, float(zone.travel_remaining))
			zone.pos = run._clip_motion(zone.pos, zone.direction * float(zone.speed) * move_time, 0.0)
			zone.travel_remaining = maxf(0.0, float(zone.travel_remaining) - move_time)
		zone.remaining = maxf(0.0, float(zone.remaining) - elapsed)
		if zone.kind == "vortex": _observe_vortex_position(run, zone)
		if float(zone.interval) > 0.0 and run.has_method("on_spell_area_matured"):
			run.on_spell_area_matured(zone.context, zone.pos, float(zone.age))
		if zone.kind == "field" and run.player.pos.distance_to(zone.pos) <= float(zone.radius) + 0.000001:
			field_grace = float(zone.grace)
			_field_grace_bonus = float(zone.attack_bonus)
		if float(zone.interval) > 0.0:
			zone.tick_remaining -= elapsed
			if zone.tick_remaining <= 0.000001:
				zone.tick_remaining += float(zone.interval)
				if run.has_method("gem_record_shape"): run.gem_record_shape({"kind": "area", "pos": zone.pos, "radius": zone.radius, "shared_spell": zone.spell_id, "shared_interval": zone.interval}, float(zone.coefficient), zone.context)
				for actor in run.actors:
					if actor.health <= 0.0 or actor.pos.distance_to(zone.pos) > float(zone.radius) + float(actor.radius):
						continue
					var key = "%s:%s" % [zone.spell_id, actor.id]
					if not candidates.has(key) or float(zone.coefficient) > float(candidates[key].zone.coefficient):
						candidates[key] = {"actor": actor, "zone": zone}
		if zone.remaining > 0.000001:
			retained.append(zone)
		elif zone.terminal:
			expired.append(zone)
	for value in candidates.values():
		var key = "%s:%s" % [value.zone.spell_id, value.actor.id]
		if float(run.time) - float(_area_last_hit.get(key, -INF)) < float(value.zone.interval) - 0.000001:
			continue
		_area_last_hit[key] = float(run.time)
		var context: Dictionary = value.zone.context.duplicate(true)
		context["kind"] = "area"
		var vortex_first: bool = value.zone.kind == "vortex" and not value.zone.first_hits.has(value.actor.id)
		var vortex_hit_pos: Vector2 = value.actor.pos
		var field_hit_pos: Vector2 = value.actor.pos
		var area_actual := _hit(run, value.actor, float(value.zone.coefficient), context)
		if value.zone.kind == "field":
			_note_field_fact(run, "hit", value.zone, {"actor_id": int(value.actor.id), "pos": field_hit_pos, "radius": float(value.actor.radius), "damage": area_actual, "alive_after": float(value.actor.health) > 0.0})
		if value.zone.kind == "vortex" and not value.zone.first_hits.has(value.actor.id):
			value.zone.first_hits[value.actor.id] = true
			var level: Dictionary = context.get("growth_level", {})
			if float(level.get("first_hit_slow", 0.0)) > 0.0:
				apply_slow(run, value.actor, float(level.first_hit_slow), float(level.first_hit_slow_duration), "F05:%s" % value.zone.id)
			else:
				var legacy: Dictionary = stats_for(run._owned_spell("F05"))
				if legacy.has("first_hit_slow"):
					apply_slow(run, value.actor, float(legacy.first_hit_slow), float(legacy.first_hit_slow_duration), "B05:%s" % value.zone.id)
		if value.zone.kind == "vortex":
			_note_vortex_fact(run, "hit", value.zone, {"actor_id": int(value.actor.id), "pos": vortex_hit_pos, "radius": float(value.actor.radius), "damage": area_actual, "first": vortex_first, "alive_after": float(value.actor.health) > 0.0})
	zones = retained
	for zone in expired:
		if run.has_method("on_spell_area_expired"):
			run.on_spell_area_expired(zone.context, zone.pos)
		if zone.kind == "vortex": _note_vortex_fact(run, "end", zone)
		if zone.kind == "field": _note_field_fact(run, "end", zone)
	_retain_vortex_paths()


func overlapping_spell_kinds(pos: Vector2, actor_radius: float = 0.0) -> Array:
	var distinct: Array = []
	for zone in zones:
		if zone.spell_id in ["F03", "F05", "F06"] and float(zone.get("active_delay", 0.0)) <= 0.000001 and pos.distance_to(zone.pos) <= float(zone.radius) + actor_radius and zone.spell_id not in distinct:
			distinct.append(zone.spell_id)
	return distinct


func apply_slow(run, actor: Dictionary, amount: float, duration: float, source: String):
	if run.has_method("apply_enemy_slow"):
		run.apply_enemy_slow(actor, amount, duration, source)
		return
	var slows: Dictionary = actor.get("spell_slows", {})
	slows[source] = {"amount": amount, "until": float(run.time) + duration}
	actor["spell_slows"] = slows


func begin_beam_echo_visual(parent_cast_id: int) -> void:
	# One-use annotation for the next actual F08 release, not release authority.
	_next_beam_echo_parent = parent_cast_id


func end_beam_echo_visual() -> void:
	_next_beam_echo_parent = -1


func _capture_beam_visual_source(run, stats: Dictionary, context: Dictionary) -> void:
	var parent := _next_beam_echo_parent
	_next_beam_echo_parent = -1
	_beam_visual_sources[int(context.cast_id)] = {
		"source": "natural" if bool(context.natural) else "echo" if parent >= 0 else "extra",
		"parent_cast_id": parent if not bool(context.natural) else -1,
		"expires": float(run.time) + maxf(float(stats.get("secondary_delay", 0.0)), float(runtime.effects.beam_lifetime)) + BEAM_FACT_RETENTION}
	if _beam_visual_sources.size() > BEAM_FACT_LIMIT: _beam_visual_sources.erase(_beam_visual_sources.keys()[0])


func _note_beam_fact(run, from: Vector2, to: Vector2, width: float, context: Dictionary, phase: String, hits: Array) -> void:
	var source: Dictionary = _beam_visual_sources.get(int(context.cast_id), {})
	_beam_fact_seq += 1
	_beam_facts.append({"seq": _beam_fact_seq, "cast_id": int(context.cast_id),
		"parent_cast_id": int(source.get("parent_cast_id", -1)),
		"source": str(source.get("source", "natural" if bool(context.natural) else "extra")),
		"phase": phase, "time": float(run.time), "lifetime": float(runtime.effects.beam_lifetime),
		"from": from, "to": to, "half_width": width, "spell_level": int(context.get("spell_level", 1)),
		"ignite": bool(context.get("ignite", false)), "hits": hits.duplicate(true)})
	if _beam_facts.size() > BEAM_FACT_LIMIT: _beam_facts.pop_front()


func _beam(run, from: Vector2, to: Vector2, width: float, coefficient: float, context: Dictionary, pierce: bool, visual_phase: String = "main"):
	if run.has_method("gem_record_shape"): run.gem_record_shape({"kind": "segment", "from": from, "to": to, "width": width, "target_cap": run.actors.size() if pierce else 1}, coefficient, context)
	var contacts: Array = []
	for actor in run.actors:
		if actor.health <= 0.0:
			continue
		var contact: float = run.segment_circle_time(from, to, actor.pos, float(actor.radius) + width)
		if contact != INF:
			contacts.append({"actor": actor, "at": contact})
	contacts.sort_custom(func(a, b): return a.at < b.at if not is_equal_approx(a.at, b.at) else a.actor.id < b.actor.id)
	var visual_hits: Array = []
	for hit in contacts:
		var visual_pos: Vector2 = hit.actor.pos
		var visual_radius := float(hit.actor.radius)
		var actual := _hit(run, hit.actor, coefficient, context)
		if str(context.spell_id) == "F08" and actual > 0.0:
			visual_hits.append({"actor_id": int(hit.actor.id), "pos": visual_pos, "radius": visual_radius,
				"contact_pos": from.lerp(to, float(hit.at)), "damage": actual, "alive_after": float(hit.actor.health) > 0.0})
		if not pierce:
			to = hit.actor.pos
			break
	run._emit("spirit_bolt" if context.spell_id == "F04" else "beam", {"from": from, "to": to, "pos": to, "radius": width, "spell_id": context.spell_id}, float(runtime.effects.beam_lifetime))
	if str(context.spell_id) == "F08": _note_beam_fact(run, from, to, width, context, visual_phase, visual_hits)


func _area_hit(run, center: Vector2, radius: float, coefficient: float, context: Dictionary, block_blast: bool = false):
	if run.has_method("gem_record_shape"): run.gem_record_shape({"kind": "area", "pos": center, "radius": radius, "block": block_blast}, coefficient, context)
	for actor in run.actors:
		if actor.health > 0.0 and actor.pos.distance_to(center) <= radius + float(actor.radius) and (not block_blast or run.line_is_clear(center, actor.pos)):
			_hit(run, actor, coefficient, context)


func _hit(run, actor: Dictionary, coefficient: float, context: Dictionary) -> float:
	if actor.is_empty() or float(actor.get("health", 0.0)) <= 0.0 or run.phase != "combat":
		return 0.0
	var before: float = float(actor.health)
	var old_burn: int = fire_status.burn_token(run, actor) if bool(context.get("detonate", false)) else -1
	if run.has_method("resolve_spell_hit"):
		run.resolve_spell_hit(actor, coefficient, context)
	else:
		run.damage_enemy(actor, run._roll_damage(coefficient * float(context.damage_scale)), str(context.spell_id))
	var actual: float = before - maxf(0.0, float(actor.health))
	if actual <= 0.0 or float(actor.health) <= 0.0:
		return actual
	if bool(context.get("detonate", false)) and old_burn >= 0 and float(context.get("detonation_multiplier", 0.0)) > 0.0:
		var level: Dictionary = context.get("growth_level", {})
		var reapply: Dictionary = {}
		if bool(context.get("natural", false)) and float(level.get("reapply_delay", 0.0)) > 0.0:
			reapply = {"detonation_multiplier_add": float(level.get("natural_detonation_multiplier_add", 0.0)), "reapply_delay": level.reapply_delay, "reapply_shared_cooldown": level.reapply_shared_cooldown, "source": "F07"}
		fire_status.detonate_burn(run, actor, float(context.detonation_multiplier), bool(context.get("natural", false)), context.get("cast_id", -1), old_burn, reapply, str(context.get("spell_id", "")))
	if bool(context.get("ignite", false)) and is_fire_spell(str(context.get("spell_id", ""))):
		var key: String = "%s:%s" % [str(context.get("cast_id", "")), str(actor.id)]
		if not bool(context.get("ignite_once_per_target", false)) or not _ignited_cast_targets.has(key):
			_ignited_cast_targets[key] = true
			apply_burn(run, actor, str(context.get("spell_id", "")))
	if run.has_method("gem_after_spell_status"): run.gem_after_spell_status(actor, context)
	return actual


func _has_live_enemy(run) -> bool:
	for actor in run.actors:
		if actor.health > 0.0:
			return true
	return false


func school_module(school: String):
	match school:
		"ice": return ice
		"lightning": return lightning
		"wind": return wind
		"earth": return earth
		"spirit": return spirit_school
	return null


func school_modules() -> Array:
	var result: Array = []
	for module in [lightning, wind, earth, spirit_school]:
		if module != null: result.append(module)
	return result


func spell_module(id: String, school: String):
	# Archived F04 keeps its original standalone summon lifecycle.
	return null if id == "F04" else school_module(school)
