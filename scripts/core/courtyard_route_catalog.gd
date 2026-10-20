extends RefCounted
## Authored room geometry over the existing 60-room route. All returned values
## are deep copies. This catalog never simulates enemies or changes their stats.

const DATA_PATH := "res://data/courtyard_route.json"
const NonbossRules = preload("res://scripts/core/route_enemy_nonboss.gd")
const BossCatalog = preload("res://scripts/core/route_boss_catalog.gd")
var _bosses = BossCatalog.new()

var error: String = ""
var _data: Dictionary = {}
var _sources: Dictionary = {}
var _rooms: Array = []
var _loaded: bool = false
var _nonboss = NonbossRules.new()


func load_catalog() -> Dictionary:
	_loaded = false
	_rooms.clear()
	_sources.clear()
	var boss_result: Dictionary = _bosses.load_data()
	if not boss_result.ok:
		return _fail(str(boss_result.error))
	var rules_result: Dictionary = _nonboss.load_rules()
	if not rules_result.ok:
		return _fail(str(rules_result.error))
	var read := _read_json(DATA_PATH)
	if not read.ok:
		return _fail(read.error)
	_data = read.data
	if not _data.get("sources") is Dictionary:
		return _fail("庭院路线缺少源数据引用。")
	for key in ["first_room", "spatial", "ordinary", "base", "economy", "enemies"]:
		if not _data.sources.get(key) is String:
			return _fail("庭院路线缺少源数据：" + key)
		read = _read_json(_data.sources[key])
		if not read.ok:
			return _fail(read.error)
		_sources[key] = read.data
	var validation := _validate_data()
	if not validation.is_empty():
		return _fail(validation)
	var occurrences: Dictionary = {}
	for mapped in _sources.spatial.rooms:
		var room_id := int(mapped.room)
		var layout_id := str(mapped.layout)
		var template_id := "first_room"
		var geometry: Dictionary
		var label: String
		var landmark: String
		if room_id == 1:
			geometry = _sources.first_room.room.duplicate(true)
			label = str(_data.first_room.name)
			landmark = "庭院入口与远端传送门"
		else:
			var options: Array = _data.layout_templates[layout_id]
			var occurrence := int(occurrences.get(layout_id, 0))
			template_id = str(options[occurrence % options.size()])
			occurrences[layout_id] = occurrence + 1
			var template: Dictionary = _data.templates[template_id]
			geometry = template.geometry.duplicate(true)
			label = str(template.name)
			landmark = str(template.landmark)
		# Route spawn authoring is independent of the legacy single-room geometry.
		# Every candidate is in the portal forecourt, never beside the entry.
		geometry.spawn["north_band"] = []
		var nonboss_limits := _nonboss.limits(room_id)
		var z_offsets: Array = _sources.enemies.north_spawn.portal_z_offsets if nonboss_limits.is_empty() else _nonboss.data.spawn.north_portal_z_offsets
		var x_fractions: Array = _sources.enemies.north_spawn.x_fractions if nonboss_limits.is_empty() else _nonboss.data.spawn.north_x_fractions
		for z_offset in z_offsets:
			for x_fraction in x_fractions:
				geometry.spawn.north_band.append([float(geometry.floor.width) * 0.5 * float(x_fraction), float(geometry.portal_center[1]) + float(z_offset)])
		var stage := _stage_for_room(room_id)
		var theme: Dictionary = _data.stage_themes[stage.id]
		var encounter := _encounter_for_room(room_id)
		var boss_definition: Dictionary = _bosses.for_room(room_id)
		if not boss_definition.is_empty():
			label = str(boss_definition.name)
		var source_kind := str(encounter.kind)
		var active := room_id <= int(_data.active_room_count)
		var limits := get_encounter_limits(room_id)
		if active:
			var playable: Dictionary = _data.encounters_by_room[str(room_id)]
			encounter["source_kind"] = source_kind
			encounter["kind"] = str(playable.kind)
			encounter["packs"] = playable.packs.duplicate(true)
		else:
			encounter["source_kind"] = source_kind
		if _data.quantity_overrides.has(str(room_id)):
			encounter["quantity_override"] = _data.quantity_overrides[str(room_id)].duplicate(true)
		_rooms.append({
			"room_id": room_id, "name": label, "layout_id": layout_id,
			"template_id": template_id, "landmark": landmark,
			"kind": encounter.kind, "source_kind": source_kind, "stage_id": str(stage.id),
			"active": active, "reward_after": _is_reward_after(room_id),
			"artifact_reward_after": _contains_room(_data.artifact_reward_rooms, room_id),
			"encounter_mode": "map_playtest" if active else "planned",
			"theme_id": str(theme.id), "theme_name": str(theme.name),
			"geometry": geometry, "spike_profile": str(mapped.spikes),
			"encounter": encounter,
			"alive_cap": int(limits.alive_cap), "max_batches": int(limits.max_batches),
			"nonboss": not nonboss_limits.is_empty(), "role_limits": nonboss_limits,
			"spawn_rules": _nonboss.data.spawn.duplicate(true) if not nonboss_limits.is_empty() else {},
			"difficulty_band": get_difficulty_band(room_id),
			"shop_after": _is_shop_after(room_id),
			"terminal": room_id == int(_data.active_room_count),
			"source_terminal": room_id == int(_sources.economy.stages[-1].to),
		})
	_loaded = true
	error = ""
	return {"ok": true, "error": "", "room_count": _rooms.size(), "active_room_count": int(_data.active_room_count)}


func is_loaded() -> bool:
	return _loaded


func get_room(room_id: int) -> Dictionary:
	if not _loaded or room_id < 1 or room_id > _rooms.size():
		return {}
	return _rooms[room_id - 1].duplicate(true)


func get_rooms() -> Array:
	return _rooms.duplicate(true) if _loaded else []


func get_templates() -> Dictionary:
	return _data.get("templates", {}).duplicate(true) if _loaded else {}


func get_summary() -> Dictionary:
	if not _loaded:
		return {}
	var kinds := {"normal": 0, "elite": 0, "boss": 0}
	var shops: Array = []
	for room in _rooms:
		kinds[room.source_kind] += 1
		if room.shop_after:
			shops.append(room.room_id)
	return {"version": _data.version, "room_count": _rooms.size(),
		"template_count": _data.templates.size(), "kinds": kinds,
		"active_room_count": int(_data.active_room_count), "reward_rooms": _integer_copy(_data.reward_rooms),
		"artifact_reward_rooms": _integer_copy(_data.artifact_reward_rooms),
		"reward_pickup": _data.reward_pickup.duplicate(true),
		"shops_after": shops, "quantity_overrides": _data.quantity_overrides.duplicate(true)}


func get_active_room_count() -> int:
	return int(_data.active_room_count) if _loaded else 0


func get_encounter_limits(room_id: int) -> Dictionary:
	var nonboss_limits := _nonboss.limits(room_id)
	if not nonboss_limits.is_empty():
		return nonboss_limits
	for stage in _data.get("encounter_limits", {}).get("stages", []):
		if room_id >= int(stage.from) and room_id <= int(stage.to):
			return stage.duplicate(true)
	# Planned rooms remain catalog references and cannot be entered by the runner.
	return {"alive_cap": int(_sources.ordinary.spawn.alive_cap_by_normal_stat_stage[0]), "max_batches": int(_sources.ordinary.spawn.max_batches)}


func get_difficulty_band(room_id: int) -> Dictionary:
	for band in _data.get("difficulty_bands", []):
		if room_id >= int(band.from) and room_id <= int(band.to):
			return band.duplicate(true)
	return {}


func get_reward_rooms() -> Array:
	return _integer_copy(_data.reward_rooms) if _loaded else []


func _encounter_for_room(room_id: int) -> Dictionary:
	var current_boss: Dictionary = _bosses.for_room(room_id)
	if not current_boss.is_empty():
		return {"kind": "boss", "source_id": str(current_boss.id), "source_room": room_id, "source_packs": [], "quantity_override": {}}
	for elite in _sources.base.elites:
		if int(elite.room) == room_id:
			return {"kind": "elite", "source_id": str(elite.id), "source_room": room_id,
				"source_packs": [], "quantity_override": {}}
	for boss in _sources.base.bosses:
		if int(boss.room) == room_id:
			return {"kind": "boss", "source_id": str(boss.id), "source_room": room_id,
				"source_packs": [], "quantity_override": {}}
	for ordinary in _sources.ordinary.rooms:
		if int(ordinary.room) == room_id:
			return {"kind": "normal", "source_id": "", "source_room": room_id,
				"source_packs": ordinary.packs.duplicate(true), "quantity_override": {}}
	return {}


func _stage_for_room(room_id: int) -> Dictionary:
	for stage in _sources.economy.stages:
		if room_id >= int(stage.from) and room_id <= int(stage.to):
			return stage
	return {}


func _is_shop_after(room_id: int) -> bool:
	# JSON numbers arrive as floats, while room ids are integers. Array membership
	# uses Variant equality and must not decide whether a recovery node exists.
	for after in _sources.base.recovery.shop_after:
		if int(after) == room_id:
			return true
	return false


func _is_reward_after(room_id: int) -> bool:
	for reward_room in _data.reward_rooms:
		if int(reward_room) == room_id:
			return true
	return false


func _integer_copy(values: Array) -> Array:
	var result: Array = []
	for value in values:
		result.append(int(value))
	return result


func _contains_room(values: Array, room_id: int) -> bool:
	for value in values:
		if int(value) == room_id:
			return true
	return false


func _validate_data() -> String:
	for key in ["templates", "layout_templates", "stage_themes", "quantity_overrides", "first_room", "encounters_by_room"]:
		if not _data.get(key) is Dictionary:
			return "庭院路线字段类型无效：" + key
	if not _sources.spatial.get("rooms") is Array or not _sources.economy.get("stages") is Array or _sources.economy.stages.is_empty():
		return "庭院路线缺少原房间映射或阶段。"
	if not _sources.first_room.get("room") is Dictionary:
		return "首房空间引用无效。"
	if not _sources.ordinary.get("rooms") is Array or not _sources.base.get("elites") is Array or not _sources.base.get("bosses") is Array:
		return "庭院路线缺少原遭遇配置。"
	var last_room := int(_sources.economy.stages[-1].to)
	if not _positive_integer(_data.get("active_room_count")) or int(_data.active_room_count) > last_room:
		return "庭院试玩范围无效。"
	var pickup: Variant = _data.get("reward_pickup")
	if not pickup is Dictionary:
		return "庭院路线缺少门前奖励拾取参数。"
	for key in ["portal_z_offset", "radius"]:
		if not (pickup.get(key) is float or pickup.get(key) is int) or not is_finite(float(pickup[key])):
			return "奖励拾取参数必须为有限数字。"
	if float(pickup.radius) <= 0.0 or float(pickup.portal_z_offset) >= 0.0:
		return "奖励拾取半径或门前偏移无效。"
	if not _data.get("reward_rooms") is Array or _data.reward_rooms.is_empty():
		return "庭院试玩缺少法术奖励节点。"
	var previous_reward := 0
	for reward_room in _data.reward_rooms:
		if not _positive_integer(reward_room) or int(reward_room) <= previous_reward or int(reward_room) > int(_data.active_room_count):
			return "庭院试玩奖励节点必须在范围内升序且不重复。"
		previous_reward = int(reward_room)
	if not _data.get("artifact_reward_rooms") is Array:
		return "庭院路线缺少精英宝物节点。"
	previous_reward = 0
	for reward_room in _data.artifact_reward_rooms:
		if not _positive_integer(reward_room) or int(reward_room) <= previous_reward or int(reward_room) > int(_data.active_room_count):
			return "庭院路线宝物节点必须在范围内升序且不重复。"
		previous_reward = int(reward_room)
	if _data.encounters_by_room.size() != int(_data.active_room_count):
		return "庭院试玩人数配置必须完整覆盖范围。"
	var limit_stages: Variant = _data.get("encounter_limits", {}).get("stages")
	if not limit_stages is Array or limit_stages.is_empty():
		return "庭院路线缺少在场容量与批次分段。"
	var next_limit_room := 1
	var anchor_count: int = _sources.enemies.north_spawn.x_fractions.size() * _sources.enemies.north_spawn.portal_z_offsets.size()
	for stage in limit_stages:
		if not stage is Dictionary or int(stage.get("from", 0)) != next_limit_room or not _positive_integer(stage.get("to")) or int(stage.to) < next_limit_room:
			return "庭院路线容量分段必须连续覆盖可玩房间。"
		if not _positive_integer(stage.get("alive_cap")) or int(stage.alive_cap) > anchor_count or not _positive_integer(stage.get("max_batches")):
			return "庭院路线容量或批次无效，或超出真实出生锚点。"
		next_limit_room = int(stage.to) + 1
	if next_limit_room != int(_data.active_room_count) + 1:
		return "庭院路线容量分段与可玩房数不符。"
	var next_band_room := 1
	if not _data.get("difficulty_bands") is Array:
		return "庭院路线缺少难度段落。"
	for band in _data.difficulty_bands:
		if not band is Dictionary or int(band.get("from", 0)) != next_band_room or not _positive_integer(band.get("to")) or int(band.to) < next_band_room or str(band.get("name", "")).is_empty():
			return "庭院路线难度段落必须连续且具备名称。"
		next_band_room = int(band.to) + 1
	if next_band_room != int(_data.active_room_count) + 1:
		return "庭院路线难度段落与可玩房数不符。"
	for room_id in range(1, int(_data.active_room_count) + 1):
		var limits := get_encounter_limits(room_id)
		var playable: Variant = _data.encounters_by_room.get(str(room_id))
		if not playable is Dictionary or playable.get("kind") not in ["normal", "elite", "elite_guard", "boss"] or not playable.get("packs") is Array:
			return "庭院试玩遭遇类型／批次无效：%d" % room_id
		if playable.packs.is_empty() or playable.packs.size() > int(limits.max_batches):
			return "庭院试玩批次数量超出本房限制：%d" % room_id
		for pack in playable.packs:
			if not pack is Dictionary or pack.is_empty():
				return "庭院试玩批次组合无效：%d" % room_id
			var count := 0
			var role_counts := {"ranged": 0, "ring": 0, "sweep": 0, "heavy": 0}
			for type_id in pack:
				var boss_definition: Dictionary = _bosses.for_room(room_id)
				var is_boss: bool = not boss_definition.is_empty() and str(type_id) == str(boss_definition.id) and str(playable.kind) == "boss" and int(pack[type_id]) == 1 and playable.packs.size() == 1 and pack.size() == 1
				if (not _sources.enemies.types.has(type_id) and not is_boss) or not _positive_integer(pack[type_id]):
					return "庭院试玩怪物类型／数量无效：%d" % room_id
				count += int(pack[type_id])
				if limits.has("stage_index"):
					if not _nonboss.data.types.has(type_id) or room_id < int(_nonboss.data.types[type_id].introduced):
						return "非Boss怪物超出本房解锁范围：%d" % room_id
					for role in _nonboss.roles(str(type_id)):
						role_counts[role] += int(pack[type_id])
			if count > int(limits.alive_cap):
				return "庭院试玩单批人数超出本房在场上限：%d" % room_id
			if limits.has("stage_index"):
				for role in role_counts:
					if int(role_counts[role]) > int(limits[str(role) + "_alive_cap"]):
						return "非Boss单批角色人数超限：%d" % room_id
	if _sources.spatial.rooms.size() != last_room:
		return "庭院路线映射数量与原关卡长度不一致。"
	for index in _sources.spatial.rooms.size():
		var mapped: Dictionary = _sources.spatial.rooms[index]
		var room_id: int = int(index) + 1
		if int(mapped.get("room", 0)) != room_id:
			return "庭院路线必须从首房连续编号。"
		var layout_id := str(mapped.get("layout", ""))
		if not _data.layout_templates.get(layout_id) is Array or _data.layout_templates[layout_id].is_empty():
			return "庭院路线布局缺少模板：" + layout_id
		for template_id in _data.layout_templates[layout_id]:
			if not _data.templates.has(template_id) or _data.templates[template_id].get("layout") != layout_id:
				return "庭院路线模板与原布局不匹配：" + str(template_id)
		var encounter := _encounter_for_room(room_id)
		if encounter.is_empty():
			return "庭院路线缺少原遭遇：%d" % room_id
		var stage := _stage_for_room(room_id)
		if stage.is_empty() or not _data.stage_themes.has(stage.id):
			return "庭院路线主题缺少原阶段引用：%d" % room_id
	for template_id in _data.templates:
		var template: Dictionary = _data.templates[template_id]
		var validation := _validate_geometry(template.get("geometry", {}))
		if not validation.is_empty():
			return "庭院模板 %s：%s" % [template_id, validation]
	return _validate_geometry(_sources.first_room.room)


func _validate_geometry(geometry: Dictionary) -> String:
	if not geometry.get("floor") is Dictionary or not geometry.get("blocks") is Array or not geometry.get("spawn") is Dictionary:
		return "缺少地面、掩体或出生锚点。"
	var width := float(geometry.floor.get("width", 0.0))
	var depth := float(geometry.floor.get("depth", 0.0))
	if not is_finite(width) or not is_finite(depth) or width <= 0.0 or depth <= 0.0:
		return "地面尺寸无效。"
	for key in ["entry_player_center", "portal_center"]:
		if not _finite_pair(geometry.get(key)):
			return "入口或门户坐标无效。"
		var point: Array = geometry[key]
		if absf(float(point[0])) >= width * 0.5 or absf(float(point[1])) >= depth * 0.5:
			return "入口或门户超出地面。"
	var clear_width := float(_sources.spatial.layout_rules.central_clear_width)
	var wall_gap := float(_sources.spatial.layout_rules.minimum_solid_wall_gap)
	for block in geometry.blocks:
		if not block is Dictionary or not _finite_pair(block.get("center")) or not _finite_pair(block.get("size")):
			return "掩体坐标无效。"
		var center := Vector2(block.center[0], block.center[1])
		var size := Vector2(block.size[0], block.size[1])
		if size.x <= 0.0 or size.y <= 0.0:
			return "掩体尺寸无效。"
		if absf(center.x) - size.x * 0.5 < clear_width * 0.5:
			return "掩体侵入中央净空通道。"
		if width * 0.5 - absf(center.x) - size.x * 0.5 < wall_gap or depth * 0.5 - absf(center.y) - size.y * 0.5 < wall_gap:
			return "掩体与外墙之间的通道过窄。"
	for key in ["side_x", "anchor_z"]:
		if not geometry.spawn.get(key) is Array or geometry.spawn[key].is_empty():
			return "缺少出生边线或纵向锚点。"
		for value in geometry.spawn[key]:
			if not (value is float or value is int) or not is_finite(float(value)):
				return "出生锚点数值无效。"
			if absf(float(value)) >= (width if key == "side_x" else depth) * 0.5:
				return "出生锚点超出地面。"
	return ""


func _finite_pair(value: Variant) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for number in value:
		if not (number is float or number is int) or not is_finite(float(number)):
			return false
	return true


func _positive_integer(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= 1.0 and float(value) == floorf(float(value))


func _fail(message: String) -> Dictionary:
	error = message
	return {"ok": false, "error": message}


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "无法读取庭院路线参数：" + path}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "庭院路线参数格式无效：" + path}
	return {"ok": true, "data": parser.data}
