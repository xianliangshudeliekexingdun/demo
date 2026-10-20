extends RefCounted
## Canonical Boss definitions; never reads the offline design model.

const DATA_PATH := "res://data/route_boss_runtime.json"
var data: Dictionary = {}


func load_data() -> Dictionary:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "无法读取首领运行数据。"}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.get("bosses") is Array or parsed.bosses.size() != 4:
		return {"ok": false, "error": "首领运行数据无效。"}
	data = parsed
	var rooms: Array = []
	var ids: Array = []
	for boss in data.bosses:
		if int(boss.get("room", 0)) in rooms or str(boss.get("id", "")) in ids or float(boss.get("health", 0.0)) <= 0.0 or not boss.get("phases") is Array or boss.phases.is_empty():
			return {"ok": false, "error": "首领定义重复或缺少阶段。"}
		rooms.append(int(boss.room))
		ids.append(str(boss.id))
		for stage in boss.phases:
			if not stage.get("sequence") is Array or stage.sequence.is_empty():
				return {"ok": false, "error": "首领缺少技能顺序。"}
			for key in stage.sequence:
				var pattern: Dictionary = stage.get("patterns", {}).get(key, {})
				if str(pattern.get("kind", "")) not in ["charge", "fan", "ring", "sweep", "marks", "lines"] or float(pattern.get("warning", 0.0)) < 1.1 or float(pattern.get("recovery", 0.0)) <= 0.0:
					return {"ok": false, "error": "首领预警／技能参数无效。"}
	if rooms != [15, 30, 45, 60] or ids != ["BOSS01", "BOSS04", "BOSS02", "BOSS03"]:
		return {"ok": false, "error": "首领房间与兼容ID无效。"}
	return {"ok": true, "error": ""}


func for_room(room: int) -> Dictionary:
	for boss in data.get("bosses", []):
		if int(boss.room) == room:
			return boss.duplicate(true)
	return {}


func spec(boss: Dictionary) -> Dictionary:
	return {"boss": true, "elite": false, "name": boss.name, "health": boss.health,
		"radius": boss.radius, "damage": boss.body_damage, "body_damage": boss.body_damage,
		"body_interval": data.global.body_interval, "body_spawn_grace": data.global.initial_attack_lock,
		"move_speed": boss.move_speed, "behavior": "boss", "warning": 1.2, "recovery": 1.6,
		"attack_cycle": 1.0, "attack_trigger_range": data.global.approach_stop_distance,
		"push_resistance": data.global.push_resistance, "ice_control_coefficient": data.global.control_coeff,
		"projectile_cap": boss.projectile_cap, "stat_room": int(boss.room), "stat_stage_id": "boss",
		"definition": boss.duplicate(true)}
