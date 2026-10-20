extends SceneTree
## Native source/spec and bounded one-source cadence fixtures. No scene or save.
const Combat = preload("res://scripts/core/route_enemy_combat.gd")
const First = preload("res://scripts/core/first_room_run.gd")
var output := "res://build/qa/enemy-pressure-20261020/native-current.json"

class Harness extends "res://scripts/core/first_room_run.gd":
	var room_index := 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--out=res://") and not str(arg).contains(".."):
			output = str(arg).trim_prefix("--out=")
	var base := First.new()
	if not base.configure().ok:
		quit(1)
		return
	var combat := Combat.new()
	if not combat.configure(base._base, base._runtime, {}, 60).ok:
		quit(1)
		return
	var specs := {}
	for room in range(1, 61):
		specs[str(room)] = {}
		for id in ["M01", "M02", "M03", "M04", "M05", "M06", "M07", "EL01", "EL02", "EL02_GUARD"]:
			specs[str(room)][id] = combat.type_spec(id, room)
	for room in [15, 30, 45, 60]:
		var boss: Dictionary = combat.bosses.catalog.for_room(room)
		specs[str(room)][str(boss.id)] = combat.type_spec(str(boss.id), room)
	var cadence := []
	for room in [2, 4, 14, 29, 44, 59]:
		for id in ["M02", "M05", "M06", "M07", "EL02"]:
			var spec: Dictionary = combat.type_spec(id, room)
			if bool(spec.get("attack_disabled", false)):
				continue
			var run := Harness.new()
			if not run.configure().ok:
				quit(1)
				return
			run.phase = "combat"
			run.room_index = room
			run.blocks.clear()
			run.player.pos = Vector2(5, 0)
			run.player.previous = run.player.pos
			run.player.health = 1000000.0
			run.player.shield = 0.0
			combat.clear()
			var actor: Dictionary = combat.make_actor(run, id, Vector2.ZERO, 1, room)
			run.actors = [actor]
			var warnings := []
			var releases := []
			for tick in 2400:
				run.time += 1.0 / 120.0
				run.player.invulnerable = maxf(0, run.player.invulnerable - 1.0 / 120.0)
				var phase := str(actor.phase)
				var next_id := int(combat._next_projectile)
				combat.update(run, 1.0 / 120.0)
				if phase == "chase" and actor.phase == "warning":
					warnings.append(run.time)
				if int(combat._next_projectile) > next_id:
					releases.append({"time": run.time, "count": int(combat._next_projectile) - next_id})
			cadence.append({"room": room, "type": id, "warnings": warnings, "releases": releases, "emitted": int(combat._next_projectile) - 1, "damage_taken": run.damage_taken})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify({"specs": specs, "cadence": cadence, "scope": "Controlled stationary one-source 20s fixtures; no natural route, render, account or performance measurement."}, "\t"))
	print("Native pressure capture: %d rooms, %d cadence fixtures -> %s" % [specs.size(), cadence.size(), output])
	quit(0)
