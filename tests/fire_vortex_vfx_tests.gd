extends SceneTree
## Real Route comparison: scenario pairs/checkpoints are reported separately.
## Headless geometry/logic checks never establish pixels or performance.
const Vortex = preload("res://scripts/presentation/route_fire_vortex_vfx.gd")
const View = preload("res://scripts/presentation/first_room_view.gd")
const Rules = preload("res://tests/formal_fire_tests.gd")
const Report = preload("res://tests/qa_report.gd")
const OUTPUT := "res://build/qa/current-visual-regressions/fire_vortex_vfx_tests/results.json"
const STEP := 1.0 / 120.0
var checks := 0
var failures: Array = []
var baseline_cases := 0
var snapshot_comparisons := 0
var baseline_assertions := 0

class Projector extends RefCounted:
	var scale := 40.0
	var offset := Vector2(640, 360)
	var rotation := 0.0
	func screen_position(pos: Vector2, height: float = 0.0) -> Vector2:
		return Vector2(pos.x * scale, -pos.y * scale * 0.65 - height * scale).rotated(rotation) + offset


func _initialize() -> void: call_deferred("execute")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("F05 chain: " + label)


func add_spell(run, id: String, level: int) -> void:
	var spell: Dictionary = run._new_spell(id)
	spell.level = level
	run._refresh_spell(spell)
	spell.remaining = 9999.0
	run.spells.append(spell)


func fresh(level: int = 1, seed: int = 20261027, old_combat: Script = null):
	var run = Rules.Fixture.new()
	check(run.configure({}, seed).ok and run.choose_initial("F01"), "real Route fixture configures")
	if old_combat != null:
		run._spell_combat = old_combat.new()
		check(run._spell_combat.configure(run).ok, "task-frozen combat configures")
	run._spawn_done = true
	run.spawn_warnings.clear()
	run.blocks.clear()
	run.player.pos = Vector2.ZERO
	run.player.previous = Vector2.ZERO
	run.player.crit_rate = 0.0
	run.spells.clear()
	add_spell(run, "F05", level)
	run.actors.clear()
	for index in 3:
		var actor: Dictionary = run._enemy_combat.make_actor(run, "M01", Vector2(0, [1.4, 3.7, 6.2][index]), 71 + index)
		actor.health = 100000.0
		actor.max_health = actor.health
		run.actors.append(actor)
	return run


func cast(run, natural: bool = true, scale: float = 1.0, slot: int = 0) -> void:
	var spell: Dictionary = run.spells[slot]
	spell["locked_pos"] = run.actors[0].pos
	run._spell_combat._cast(run, spell, run.get_spell_stats(spell), run.actors[0], natural, scale)
	spell.remaining = 9999.0


func advance(run, seconds: float) -> void:
	for frame in roundi(seconds / STEP): run.step(STEP)


func facts(run, phase: String) -> Array:
	return run.get_snapshot().fire_vortex_facts.filter(func(f): return str(f.phase) == phase)


func gameplay(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			if key not in ["fire_vortex_facts", "fire_vortex_paths"]: result[key] = gameplay(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(gameplay(item))
		return result
	return value


func core_parity() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline="): path = arg.trim_prefix("--baseline=")
	if path.is_empty(): return
	var old_combat: Script = load(path)
	check(old_combat != null, "frozen source loads")
	if old_combat == null: return
	for level in range(1, 4):
		for mode in 12:
			var case_id := (level - 1) * 12 + mode
			var actual = fresh(level, 20261027 + case_id)
			var reference = fresh(level, 20261027 + case_id, old_combat)
			for run in [actual, reference]:
				if mode == 3: run.blocks.append({"center": Vector2(0, 2), "size": Vector2(3.0, 0.4)})
				if mode == 4:
					run.actors[0].pos = Vector2.ZERO
					run.actors[0].previous = Vector2.ZERO
				if mode == 10: run.actors[0].health = 1.0
				if mode == 8:
					for id in ["F01", "F03", "F08", "F07", "F09"]: add_spell(run, id, 3)
					for slot in range(1, 6): cast(run, true, 1.0, slot)
				cast(run, mode != 1, 0.0 if mode == 2 else 0.7 if mode == 1 else 1.0)
				if mode == 6:
					run.spells[0].level = 3
					run._refresh_spell(run.spells[0])
					cast(run, false, 0.7)
				if mode == 7: cast(run, false, 0.7)
				if mode == 9: run.spells[0].level = 1
			for frame in 840:
				for run in [actual, reference]:
					if mode == 5 and frame == 60:
						run.actors[0].pos = Vector2(4, 3)
						run.actors[0].previous = run.actors[0].pos
						run.player.pos = Vector2(-2, 0)
						run.player.previous = run.player.pos
					if mode == 9 and frame == 120: run._spell_combat.apply_burn(run, run.actors[0], "F03")
					if mode == 11 and frame == 10: run.set_paused(true)
					if mode == 11 and frame == 40: run.set_paused(false)
					run.step(STEP)
				if frame in [0, 59, 119, 239, 479, 480, 599, 719, 839]:
					check(gameplay(actual.get_snapshot()) == gameplay(reference.get_snapshot()), "whole frozen snapshot level %d mode %d frame %d" % [level, mode, frame])
					check(actual._rng.state == reference._rng.state, "unchanged gameplay RNG %d/%d/%d" % [level, mode, frame])
					snapshot_comparisons += 1
			for key in ["damage_log", "context_log", "cast_log", "extra_log", "emitted"]:
				check(actual.get(key) == reference.get(key), "unchanged real hooks/events level %d mode %d %s" % [level, mode, key])
			baseline_cases += 1


func release_ticks_and_hold(renderer, projector) -> void:
	for level in range(1, 4):
		var run = fresh(level)
		run.room_revision = 10 + level
		run.spells[0].remaining = 0.0
		run.step(STEP)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(renderer.get_debug_state().coverage.get("F05_cast", 0) == 1 and renderer.get_debug_state().vortices.is_empty(), "real chant precedes zone birth")
		advance(run, 0.4)
		run.spells[0].remaining = 9999.0
		var snapshot: Dictionary = run.get_snapshot()
		check(snapshot.spell_zones.size() == 1 and facts(run, "release").size() == 1 and facts(run, "hit").is_empty(), "release creates one actual zone without immediate damage")
		if snapshot.spell_zones.is_empty(): continue
		var zone: Dictionary = snapshot.spell_zones[0]
		var id := int(zone.id)
		var released := float(zone.born_at)
		check(zone.pos == Vector2.ZERO and is_equal_approx(float(zone.radius), [1.2, 1.6, 1.8][level - 1]), "released origin and true radius")
		renderer.sync_snapshot(snapshot, projector)
		check(renderer.get_debug_state().vortices.size() == 1 and renderer.get_debug_state().coverage.get("F05_release", 0) == 1, "real body and release flare appear together")
		advance(run, 0.49)
		check(facts(run, "hit").is_empty() and run.damage_dealt == 0.0, "existing first full interval is preserved")
		advance(run, 0.01)
		var contacts: Array = facts(run, "hit")
		check(contacts.size() == 1 and contacts[0].contact.actor_id == 71 and contacts[0].contact.first and contacts[0].contact.damage > 0.0, "first actual selected tick records one real target")
		if contacts.is_empty(): continue
		check(is_equal_approx(float(contacts[0].time) - released, 0.5), "first tick remains at original half-second delay")
		var burn: Dictionary = run._spell_combat.fire_status.burns[71].duplicate(true)
		var slow_key := "F05:%d" % id
		var slow: Dictionary = run.actors[0].get("spell_slows", {}).get(slow_key, {}).duplicate(true)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		var debug: Dictionary = renderer.get_debug_state()
		check(debug.coverage.get("F05_hit", 0) == 1 and debug.coverage.get("F05_slow", 0) == (0 if level == 1 else 1) and debug.burns.has(71), "selected hit, real source slow and actual burn have local feedback")
		check(debug.paths.any(func(p): return p.kind == "wake"), "moving wake comes from observed world positions")
		var copy: Dictionary = run.get_snapshot()
		copy.fire_vortex_paths[id][0].pos = Vector2(99, 99)
		copy.fire_vortex_facts[-1].contact.pos = Vector2(99, 99)
		check(run.get_snapshot().fire_vortex_paths[id][0].pos != Vector2(99, 99) and facts(run, "hit")[-1].contact.pos != Vector2(99, 99), "path and nested contact facts are deep copies")
		advance(run, 0.5)
		var repeat_contacts: Array = facts(run, "hit").filter(func(f): return int(f.contact.actor_id) == 71)
		check(repeat_contacts.size() >= 2 and repeat_contacts[-1].contact.first == false and is_equal_approx(float(run._spell_combat.fire_status.burns[71].expires), float(burn.expires)), "repeated area tick neither repeats first contact nor refreshes burn")
		if level > 1: check(run.actors[0].spell_slows[slow_key] == slow, "first-contact slow deadline is not refreshed each tick")
		run.player.pos = Vector2(-2, 0)
		run.player.previous = run.player.pos
		run.actors[0].pos = Vector2(4, 3)
		run.actors[0].previous = run.actors[0].pos
		run.spells[0].level = 1
		advance(run, 3.0)
		var zones: Array = run.get_snapshot().spell_zones
		check(zones.size() == (1 if level == 3 else 0), "only released L3 survives original travel duration")
		if level == 3 and not zones.is_empty():
			var stop: Vector2 = zones[0].pos
			renderer.sync_snapshot(run.get_snapshot(), projector)
			check(renderer.get_debug_state().vortices[0].phase == "hold" and renderer.get_debug_state().vortices[0].spell_level == 3 and is_equal_approx(float(zones[0].radius), 1.8), "hold keeps actual original level and radius after downgrade")
			advance(run, 1.0)
			check(run.get_snapshot().spell_zones[0].pos == stop and run.get_snapshot().spell_zones[0].direction == Vector2(0, 1), "end hold stays at real stopped position without following player or target")
			advance(run, 1.0)
		var ends: Array = facts(run, "end")
		check(ends.size() == 1 and is_equal_approx(float(ends[0].time) - released, 6.0 if level == 3 else 4.0), "one real natural end at the original total duration")
		check(run.get_snapshot().fire_vortex_paths.is_empty(), "expired zone path table is released")
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(renderer.get_debug_state().vortices.is_empty() and renderer.get_debug_state().coverage.get("F05_end", 0) == 1, "actual end removes active radius and only leaves finite local cooling")
		advance(run, 0.4)
		renderer.sync_snapshot(run.get_snapshot(), projector)
		check(renderer.get_debug_state().coverage.get("F05_end", 0) == 0, "zone cooling does not extend active zone lifetime")


func overlap_wall_and_source_edges(renderer, projector) -> void:
	var run = fresh(3)
	run.actors.resize(1)
	cast(run)
	cast(run, false, 0.7)
	advance(run, 0.5)
	check(facts(run, "hit").size() == 1 and facts(run, "hit")[0].zone_id == run._spell_combat.zones[0].id, "equal overlapping zones keep shared interval and actual first selected owner")
	renderer.sync_snapshot(run.get_snapshot(), projector)
	check(renderer.get_debug_state().vortices.size() == 2 and renderer.get_debug_state().coverage.get("F05_hit", 0) == 1, "two live bodies do not fabricate two hit flashes")
	var stronger = fresh(1)
	stronger.actors.resize(1)
	cast(stronger)
	stronger.spells[0].level = 3
	stronger._refresh_spell(stronger.spells[0])
	cast(stronger, false, 0.7)
	advance(stronger, 0.5)
	check(facts(stronger, "hit").size() == 1 and facts(stronger, "hit")[0].zone_id == stronger._spell_combat.zones[1].id and stronger._spell_combat.zones[0].first_hits.is_empty(), "higher released coefficient wins without falsely marking lower first contact")
	var zero = fresh(3)
	zero.actors.resize(1)
	cast(zero, true, 0.0)
	advance(zero, 0.5)
	renderer.sync_snapshot(zero.get_snapshot(), projector)
	check(facts(zero, "hit").size() == 1 and facts(zero, "hit")[0].contact.damage == 0.0 and zero.get_snapshot().spell_burns.is_empty(), "zero-effective-damage contact preserves original first-contact state without ignition")
	check(renderer.get_debug_state().coverage.get("F05_hit", 0) == 0 and renderer.get_debug_state().coverage.get("F05_slow", 0) == 1, "zero damage has only the actually applied source slow, not a damage flash")
	var wall = fresh(3)
	wall.blocks.append({"center": Vector2(0, 2), "size": Vector2(3, 0.4)})
	cast(wall)
	advance(wall, 2.0)
	renderer.sync_snapshot(wall.get_snapshot(), projector)
	var debug: Dictionary = renderer.get_debug_state()
	check(wall._spell_combat.zones[0].pos.y < 2.0 and debug.vortices[0].phase == "travel" and not debug.paths.any(func(p): return p.kind == "wake"), "wall stop has no fictitious wake and does not enter hold early")
	advance(wall, 2.0)
	renderer.sync_snapshot(wall.get_snapshot(), projector)
	check(renderer.get_debug_state().vortices[0].phase == "hold", "wall-stopped L3 enters hold only at original time")
	run._spell_combat.apply_burn(run, run.actors[0], "F03")
	renderer.sync_snapshot(run.get_snapshot(), projector)
	check(renderer.get_debug_state().burns.is_empty() and renderer.get_debug_state().cooling.is_empty(), "burn source handoff has no false extinction")
	advance(run, 0.5)
	check(run._spell_combat.fire_status.burns[71].source == "F03", "already ignited cast does not take source back on every tick")
	var lethal = fresh(3)
	lethal.actors.resize(1)
	lethal.actors[0].health = 1.0
	cast(lethal)
	advance(lethal, 0.5)
	renderer.sync_snapshot(lethal.get_snapshot(), projector)
	check(renderer.get_debug_state().coverage.get("F05_hit", 0) == 1 and renderer.get_debug_state().burns.is_empty() and renderer.get_debug_state().coverage.get("F05_slow", 0) == 0, "lethal contact keeps one factual flash but no corpse status")


func projection_cleanup_and_capacity(renderer, projector) -> void:
	var run = fresh(3)
	run.room_revision = 40
	cast(run)
	advance(run, 0.7)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	var original: Dictionary = renderer.get_debug_state()
	run.set_paused(true)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	check(renderer.get_debug_state() == original, "pause freezes paths, rotation, hits and source statuses")
	projector.rotation = 0.31
	projector.scale = 54.0
	projector.offset += Vector2(91, -29)
	renderer.sync_snapshot(run.get_snapshot(), projector)
	var moved: Dictionary = renderer.get_debug_state()
	check(moved.paths == original.paths and wall_world_unchanged(moved, original) and moved.interior_flames == original.interior_flames and moved.column_vertices != original.column_vertices and moved.vortices == original.vortices, "walls and decoration centers stay in world space while flame billboards face the new camera")
	renderer.sync_snapshot(run.get_snapshot(), projector, {"reduced_motion": true})
	check(renderer.get_debug_state().vortices == moved.vortices and renderer.get_debug_state().paths == moved.paths and renderer._column_material.get_shader_parameter("reduced_motion") == true, "reduced motion freezes flame turbulence while preserving actual zone/phase and observed wake")
	var missing: Dictionary = run.get_snapshot()
	missing.spell_zones.clear()
	missing.fire_vortex_facts.clear()
	missing.spell_burns.clear()
	missing.effects.clear()
	missing.room_revision += 1
	for actor in missing.actors: actor.spell_slows = {}
	renderer.sync_snapshot(missing, projector)
	check(not renderer.visible and renderer.get_debug_state().coverage.get("F05_end", 0) == 0, "disappearing zone never invents natural-end feedback")
	missing.erase("fire_vortex_paths")
	renderer.sync_snapshot(missing, projector)
	check(not renderer.visible, "missing snapshot capability clears native geometry")
	var lifecycle = fresh()
	lifecycle.room_revision = 41
	lifecycle._spell_combat.apply_burn(lifecycle, lifecycle.actors[0], "F05")
	renderer.sync_snapshot(lifecycle.get_snapshot(), projector)
	lifecycle._spell_combat.detonate_burn(lifecycle, lifecycle.actors[0], 1.0)
	renderer.sync_snapshot(lifecycle.get_snapshot(), projector)
	check(renderer.get_debug_state().cooling.is_empty(), "fuel consumption does not fake natural cooling")
	lifecycle._spell_combat.apply_burn(lifecycle, lifecycle.actors[0], "F05")
	renderer.sync_snapshot(lifecycle.get_snapshot(), projector)
	advance(lifecycle, 4.0)
	renderer.sync_snapshot(lifecycle.get_snapshot(), projector)
	check(renderer.get_debug_state().cooling.size() == 1, "source burn naturally expires with finite embers")
	advance(lifecycle, 0.3)
	renderer.sync_snapshot(lifecycle.get_snapshot(), projector)
	check(not renderer.visible, "burn-only lifecycle returns to empty")
	var snapshot: Dictionary = run.get_snapshot()
	snapshot.effects.clear()
	snapshot.fire_vortex_facts.clear()
	snapshot.fire_vortex_paths.clear()
	snapshot.spell_burns.clear()
	for actor in snapshot.actors: actor.spell_slows = {}
	var template: Dictionary = snapshot.spell_zones[0].duplicate(true)
	snapshot.spell_zones.clear()
	for index in 256:
		var zone := template.duplicate(true)
		zone.id = index + 1
		snapshot.spell_zones.append(zone)
	renderer.sync_snapshot(snapshot, projector)
	var capacity: Dictionary = renderer.get_debug_state()
	check(capacity.vortices.size() == 128 and capacity.overflow == 128 and capacity.batch_nodes == 5 and capacity.material_count == 4, "finite live tornado/node/material capacity")
	check(snapshot.spell_zones.size() == 256, "visual capacity never removes actual zones")
	run.set_paused(false)
	for index in 600: cast(run, false, 0.7)
	check(run.get_snapshot().fire_vortex_facts.size() == 512 and run.get_snapshot().fire_vortex_paths.size() <= 256, "bounded contact journal and per-zone path table")
	run._stop_combat()
	check(run.get_snapshot().fire_vortex_facts.is_empty() and run.get_snapshot().fire_vortex_paths.is_empty(), "core stop clears both observation stores")
	snapshot.phase = "pickup"
	renderer.sync_snapshot(snapshot, projector)
	check(not renderer.visible, "phase change clears all native drawing")
	snapshot.phase = "combat"
	snapshot.time = -1.0
	renderer.sync_snapshot(snapshot, projector)
	check(not renderer.visible, "clock rollback does not draw future zones")


func integration() -> void:
	var run = fresh(3)
	cast(run)
	var view = View.new()
	root.add_child(view)
	await process_frame
	view.sync(run.get_snapshot())
	check(view.get_fire_vortex_debug_state().vortices.size() == 1 and view.spell_vfx.get_debug_state().coverage.get("F05", 0) == 0, "native view draws live F05 once")
	check(is_equal_approx(view.screen_depth(run.player.pos, 1.0), -view.camera.to_local(view._point(run.player.pos, 1.0)).z), "native funnel depth uses the actual camera transform")
	check(view.fire_vortex_vfx.z_index < view._overlay.z_index and view.fire_vortex_vfx.z_index < view.magic_missile_vfx.z_index, "hostile warnings/missiles remain above friendly vortex")
	var old: Dictionary = run.get_snapshot()
	old.erase("fire_vortex_facts")
	view.sync(old)
	check(not view.fire_vortex_vfx.visible and view.spell_vfx.get_debug_state().coverage.get("F05", 0) == 1, "old snapshot preserves original vortex rendering")
	view.queue_free()
	await process_frame


func wall_world_unchanged(left: Dictionary, right: Dictionary) -> bool:
	if left.columns != right.columns: return false
	for column in left.columns:
		var start := int(column.vertex_offset)
		var count := (int(column.rows) + 1) * (int(column.sides) + 1)
		for index in range(start, start + count):
			if left.column_world[index] != right.column_world[index]: return false
	return true


func tornado_volume(renderer, projector) -> void:
	for level in range(1, 4):
		var run = fresh(level)
		run.room_revision = 60 + level
		cast(run)
		advance(run, 0.6)
		var snapshot: Dictionary = run.get_snapshot()
		var rng_before: int = run._rng.state
		renderer.sync_snapshot(snapshot, projector)
		var debug: Dictionary = renderer.get_debug_state()
		check(debug.visual_revision == 5 and debug.columns.size() == 2, "v5 retains the two v3 flame-wall layers")
		if debug.columns.is_empty(): continue
		var outer: Dictionary = debug.columns[0]
		check(float(outer.height) >= 2.39 and float(outer.mouth_radius) > float(outer.base_radius) * 2.0, "tornado retains height and a narrow foot without an exaggerated cup flare")
		check(is_equal_approx(float(outer.radius), [1.2, 1.6, 1.8][level - 1]) and float(outer.mouth_radius) < float(outer.radius), "volume keeps the original real radius")
		var bounded := true
		var finite := true
		for point: Vector3 in debug.column_world:
			finite = finite and point.is_finite()
			bounded = bounded and Vector2(point.x, point.z).distance_to(outer.pos) <= float(outer.radius) + 0.00001
		check(finite and bounded and not debug.column_indices.is_empty(), "flame wall vertices are finite and stay within the original horizontal footprint")
		var seam_closed := true
		for column: Dictionary in debug.columns:
			for row in range(int(column.rows) + 1):
				var a := int(column.vertex_offset) + row * (int(column.sides) + 1)
				seam_closed = seam_closed and Vector3(debug.column_world[a]).is_equal_approx(debug.column_world[a + int(column.sides)])
		check(seam_closed, "each flame-wall height band closes around the full circumference")
		var min_top := INF
		var max_top := -INF
		var top_start := int(outer.vertex_offset) + int(outer.rows) * (int(outer.sides) + 1)
		for side in int(outer.sides):
			min_top = minf(min_top, debug.column_world[top_start + side].y)
			max_top = maxf(max_top, debug.column_world[top_start + side].y)
		check(max_top - min_top > float(outer.height) * 0.05, "integrated upper flame silhouette varies in height instead of making a level circular rim")
		check(renderer._column_mesh.get_surface_count() == 1 and renderer._column_node.material.shader == Vortex.COLUMN_SHADER, "continuous funnel mesh is bound to its dedicated flame shader")
		var depth_sorted := true
		var previous := INF
		for face: Dictionary in renderer._column_faces:
			depth_sorted = depth_sorted and float(face.depth) <= previous
			previous = float(face.depth)
		check(depth_sorted, "transparent flame faces are ordered back to front")
		check(run.get_snapshot() == snapshot and run._rng.state == rng_before, "tornado building is read-only for simulation and RNG")
		projector.offset += Vector2(23, -11)
		renderer.sync_snapshot(snapshot, projector)
		check(wall_world_unchanged(renderer.get_debug_state(), debug) and renderer.get_debug_state().interior_flames == debug.interior_flames and renderer.get_debug_state().column_vertices != debug.column_vertices, "wall silhouette and decoration centers reproject without changing world locations")
		var without_burns := snapshot.duplicate(true)
		without_burns.spell_burns.clear()
		renderer.sync_snapshot(without_burns, projector)
		var clean: Dictionary = renderer.get_debug_state()
		check(clean.body_instances == 0 and clean.columns.size() == 2 and not clean.interior_flames.is_empty() and clean.paths.all(func(p): return p.kind == "wake"), "decorations are inside the sorted wall mesh; no detached crown/lattice or fake source-burning sprites")
	var ending = fresh(3)
	cast(ending)
	advance(ending, 6.0)
	renderer.sync_snapshot(ending.get_snapshot(), projector)
	check(renderer.get_debug_state().vortices.is_empty() and renderer.get_debug_state().interior_flames.is_empty() and renderer.get_debug_state().columns.size() == 2 and renderer.get_debug_state().columns.all(func(c): return c.phase == "end"), "interior decorations stop with the real zone; end-collapse mesh never keeps it alive")
	advance(ending, 0.4)
	renderer.sync_snapshot(ending.get_snapshot(), projector)
	check(renderer.get_debug_state().columns.is_empty() and renderer.get_debug_state().column_vertices.is_empty(), "column collapse is finite and fully removed")


func interior_decoration(renderer, projector) -> void:
	for level in range(1, 4):
		var run = fresh(level)
		run.room_revision = 80 + level
		cast(run)
		advance(run, 0.6)
		var actual: Dictionary = run.get_snapshot()
		var rng_before: int = run._rng.state
		var shown := actual.duplicate(true)
		shown.spell_burns.clear()
		renderer.sync_snapshot(shown, projector)
		var debug: Dictionary = renderer.get_debug_state()
		var flames: Array = debug.interior_flames
		check(flames.size() >= 4 and flames.size() <= [9, 12, 15][level - 1], "small flames remain sparse and level-bounded")
		if flames.is_empty(): continue
		var min_y := INF
		var max_y := -INF
		var min_height := INF
		var max_height := -INF
		var min_width := INF
		var max_width := -INF
		var angles: Array[float] = []
		var embedded := true
		var live: Dictionary = debug.vortices[0]
		for flame in flames:
			min_y = minf(min_y, flame.world.y)
			max_y = maxf(max_y, flame.world.y)
			min_height = minf(min_height, flame.height)
			max_height = maxf(max_height, flame.height)
			min_width = minf(min_width, flame.width)
			max_width = maxf(max_width, flame.width)
			angles.append(fposmod(float(flame.angle), TAU))
			embedded = embedded and Vector2(flame.world.x, flame.world.z).distance_to(live.pos) < float(live.radius) * 0.7 and flame.world.y < float(live.height) * 0.75
		angles.sort()
		var min_gap := INF
		var max_gap := -INF
		for index in angles.size():
			var gap := fposmod(angles[(index + 1) % angles.size()] - angles[index], TAU)
			min_gap = minf(min_gap, gap)
			max_gap = maxf(max_gap, gap)
		check(embedded and max_y - min_y > float(live.height) * 0.15, "flames scatter at different heights inside the volume rather than around its crown")
		check(max_height - min_height > 0.02 and max_width - min_width > 0.008 and max_gap - min_gap > 0.15, "flame sizes and angular spacing are visibly nonuniform")
		check(renderer._column_faces.filter(func(face): return face.get("kind", "") == "interior_flame").size() == flames.size() and flames.all(func(flame): return renderer._column_colors[int(flame.vertex_offset)].g > 0.9), "flames use the dedicated shader branch within the actual depth-sorted mesh")
		check(run.get_snapshot() == actual and run._rng.state == rng_before, "irregular flame generation never edits simulation or its RNG")
		advance(run, 0.12)
		var later: Dictionary = run.get_snapshot()
		later.spell_burns.clear()
		renderer.sync_snapshot(later, projector)
		var moving: Dictionary = renderer.get_debug_state()
		var orbit_and_rise := false
		for flame in moving.interior_flames:
			for previous in flames:
				if flame.index != previous.index or flame.progress <= previous.progress: continue
				orbit_and_rise = orbit_and_rise or (flame.angle > previous.angle + 0.1 and flame.world.y > previous.world.y)
		check(orbit_and_rise, "small flames revolve with the column while rising and fading on staggered cycles")
		run.set_paused(true)
		var paused: Dictionary = run.get_snapshot()
		paused.spell_burns.clear()
		renderer.sync_snapshot(paused, projector)
		check(renderer.get_debug_state().interior_flames == moving.interior_flames, "pause freezes all decoration positions/sizes/phases")
		renderer.sync_snapshot(paused, projector, {"reduced_motion": true})
		var reduced: Dictionary = renderer.get_debug_state()
		var reduced_later := paused.duplicate(true)
		reduced_later.time += 0.3
		renderer.sync_snapshot(reduced_later, projector, {"reduced_motion": true})
		check(reduced.interior_flames.size() <= 3 and not reduced.interior_flames.is_empty() and renderer.get_debug_state().interior_flames == reduced.interior_flames, "reduced motion keeps a few static interior flames without decorative orbit/flicker")
		var cleared := reduced_later.duplicate(true)
		cleared.phase = "complete"
		renderer.sync_snapshot(cleared, projector)
		check(renderer.get_debug_state().interior_flames.is_empty() and renderer.get_debug_state().column_vertices.is_empty(), "leaving combat clears interior decorations and their mesh")


func execute() -> void:
	core_parity()
	baseline_assertions = checks
	var renderer = Vortex.new()
	root.add_child(renderer)
	await process_frame
	check(renderer.is_available() and renderer.get_child_count() == 5, "five fixed native draw nodes including the tornado wall")
	for shader: Shader in [Vortex.SURFACE_SHADER, Vortex.COLUMN_SHADER, Vortex.BODY_SHADER, Vortex.TRAIL_SHADER]:
		check(not shader.get_shader_uniform_list().is_empty(), "local shader-language parse: " + shader.resource_path)
	var projector := Projector.new()
	release_ticks_and_hold(renderer, projector)
	overlap_wall_and_source_edges(renderer, projector)
	tornado_volume(renderer, projector)
	interior_decoration(renderer, projector)
	projection_cleanup_and_capacity(renderer, projector)
	await integration()
	renderer.queue_free()
	await process_frame
	var result := {"checks": checks, "failures": failures.size(), "details": failures, "frozen_baseline_cases": baseline_cases,
		"whole_snapshot_comparisons": snapshot_comparisons, "baseline_assertions": baseline_assertions, "non_baseline_assertions": checks - baseline_assertions,
		"scenario_matrix": "Three released levels by 12 setups: natural, extra, zero-effective damage, wall, zero direction, target/player movement, different-level overlap, equal overlap, mixed five approved spells, source/level handoff, lethal hit, pause.",
		"scope": "Headless real-Route movement/clip/direction/radius, shared selected ticks/first-hit slow/once-per-cast ignition, original L3 hold and true expiry; v5 preserves the v3 wall and boosts the visibility of irregular interior flames with world-space orbit/rise, shared mesh depth ordering, camera-facing quads, pause/reduced/cleanup, finite structure and production-view integration. Frozen whole-snapshot/hooks/events/RNG parity runs only with --baseline; zero baseline cases means it was not rerun. No interactive preview, pixels/GPU composition, performance, natural route, export, Git mutation or v4 user visual acceptance."}
	if not Report.write_report(result, OUTPUT): failures.append("cannot write report")
	print("FIRE VORTEX CHAIN scenarios=%d snapshot_comparisons=%d assertions=%d failures=%d" % [baseline_cases, snapshot_comparisons, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
