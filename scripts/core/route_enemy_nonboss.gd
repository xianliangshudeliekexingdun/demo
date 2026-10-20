extends RefCounted
## Approved encounter limits and final attack values for the 56 non-Boss rooms.
## Bosses use their own catalog. No dependency on the offline design model.

const DATA_PATH := "res://data/route_nonboss_runtime.json"

var data: Dictionary = {}


func load_rules() -> Dictionary:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "无法读取非Boss运行规则。"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "非Boss运行规则格式无效。"}
	data = parser.data
	if not data.get("stages") is Array or data.stages.size() != 4 or not data.get("types") is Dictionary or not data.get("patterns") is Dictionary:
		return {"ok": false, "error": "非Boss规则缺少阶段、类型或弹幕。"}
	for index in range(4):
		var stage: Dictionary = data.stages[index]
		if int(stage.get("from", 0)) != index * 15 + 1 or int(stage.get("to", 0)) != index * 15 + 14:
			return {"ok": false, "error": "非Boss阶段范围无效。"}
		for key in ["alive_cap", "max_waves", "projectile_cap"]:
			if int(stage.get(key, 0)) <= 0:
				return {"ok": false, "error": "非Boss数量上限无效。"}
		if int(stage.alive_cap) > data.spawn.north_x_fractions.size() * data.spawn.north_portal_z_offsets.size():
			return {"ok": false, "error": "非Boss出生候选少于在场上限。"}
	for group in ["small", "heavy", "elite"]:
		if float(data.get("body_contact", {}).get("base_damage_by_group", {}).get(group, 0)) <= 0.0:
			return {"ok": false, "error": "非Boss接触基础伤害无效。"}
	for pattern in data.patterns.values():
		for key in ["counts", "cycle", "speed", "volleys", "release_interval", "min_start_distance"]:
			if not pattern.get(key) is Array or pattern[key].size() != 4:
				return {"ok": false, "error": "非Boss弹幕需要四阶段参数。"}
		for index in 4:
			if int(pattern.counts[index]) <= 0:
				continue
			if float(pattern.cycle[index]) <= 0.0 or float(pattern.speed[index]) <= 0.0 or int(pattern.volleys[index]) <= 0 or float(pattern.min_start_distance[index]) < 0.0:
				return {"ok": false, "error": "非Boss弹幕发射参数无效。"}
			var shot_interval: float = float(pattern.shot_interval[index]) if pattern.get("shot_interval") is Array else float(pattern.get("shot_interval", 0.0))
			var train: float = shot_interval * float(int(pattern.counts[index]) - 1) if str(pattern.kind) in ["aimed", "sweep"] else 0.0
			if int(pattern.volleys[index]) > 1 and float(pattern.release_interval[index]) + 0.000001 < train + float(pattern.followup_warning):
				return {"ok": false, "error": "非Boss子轮间隔必须容纳完整发射和后续预警。"}
	return {"ok": true, "error": ""}


func limits(room_id: int) -> Dictionary:
	for index in range(data.get("stages", []).size()):
		var stage: Dictionary = data.stages[index]
		if room_id >= int(stage.from) and room_id <= int(stage.to):
			var result := stage.duplicate(true)
			result["stage_index"] = index
			result["max_batches"] = int(stage.max_waves)
			return result
	return {}


func roles(type_id: String) -> Array:
	return data.get("types", {}).get(type_id, {}).get("roles", []).duplicate()


func apply_specs(raw: Dictionary, room_id: int) -> Dictionary:
	var result := raw.duplicate(true)
	var stage := limits(room_id)
	if stage.is_empty():
		return result
	var index := int(stage.stage_index)
	for type_id in result:
		var spec: Dictionary = result[type_id]
		var info: Dictionary = data.types.get(type_id, {})
		if info.is_empty():
			continue
		var reference: String = str(info.health_reference)
		var factor := float(info.health_factor)
		if room_id <= 3 and type_id in ["M01", "M02"]:
			factor = 1.0
		spec.health = float(raw[reference].health) * factor
		spec.radius = float(info.radius)
		spec["nonboss"] = true
		spec["roles"] = info.roles.duplicate()
		spec["body_damage"] = float(data.body_contact.base_damage_by_group[info.body_group])
		spec["body_interval"] = float(data.body_contact.player_contact_interval)
		spec["body_spawn_grace"] = float(data.body_contact.contact_grace_after_spawn)
		spec["projectile_cap"] = int(stage.projectile_cap)
		spec["heavy"] = "heavy" in info.roles
		var pattern_id := str(info.pattern)
		if pattern_id.is_empty():
			continue
		var pattern: Dictionary = data.patterns[pattern_id].duplicate(true)
		for key in ["counts", "cycle", "speed", "shot_interval", "volleys", "release_interval", "min_start_distance"]:
			if pattern.get(key) is Array:
				pattern[key] = pattern[key][index]
		if room_id <= 3 and pattern_id == "aimed":
			pattern.merge(data.teaching_aimed, true)
		pattern["count"] = int(pattern.counts)
		pattern["range"] = float(data.projectiles.range)
		spec["attack_disabled"] = int(pattern.count) <= 0
		spec["barrage"] = pattern
		if not spec.attack_disabled:
			# Speed and cycle are final pattern values. Damage is the pattern's
			# BASE value; combat applies room damage once after all overrides.
			spec.warning = float(pattern.warning)
			spec.damage = float(pattern.damage)
			spec.projectile_speed = float(pattern.speed)
			spec.projectile_radius = float(pattern.radius)
			spec.projectile_range = float(pattern.range)
			spec.attack_cycle = float(pattern.cycle)
			spec["projectile_lifetime"] = float(data.projectiles.lifetime)
	return result
