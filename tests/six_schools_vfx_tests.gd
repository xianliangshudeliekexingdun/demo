extends "res://tests/formal_spirit_tests.gd"
## Headless Node3D/snapshot rule-boundary check only. No screenshot, viewport
## capture, visible game, pixel readability, frame timing or performance claim.

const RemainingVFX = preload("res://scripts/presentation/route_remaining_schools_vfx.gd")
const RouteVFX = preload("res://scripts/presentation/route_spell_vfx.gd")
const WindRules = preload("res://tests/formal_wind_tests.gd")
const LightningVFX = preload("res://scripts/presentation/route_lightning_vfx.gd")
var samples: Array = []
var render_node: Node3D

func execute():
	render_node = Node3D.new()
	root.add_child(render_node)
	var remaining = RemainingVFX.new()
	var integrated = RouteVFX.new()
	render_node.add_child(remaining)
	render_node.add_child(integrated)
	check(is_instance_valid(remaining._lines), "remaining renderer actual Node3D ready")
	check(is_instance_valid(integrated._remaining_vfx), "route renderer creates remaining-school child")
	group("actual_core_snapshot_shapes", func(): actual_core_snapshot_shapes(remaining, integrated))
	group("effect_and_phase_boundaries", func(): effect_and_phase_boundaries(remaining, integrated))
	group("bounded_batches_and_reduced_motion", func(): bounded_batches_and_reduced_motion(remaining, integrated))
	group("wind_mastery_indicator", func(): wind_mastery_indicator(remaining))
	group("lightning_snapshot_boundaries", func(): lightning_snapshot_boundaries(integrated))
	var hashes: Dictionary = {}
	for path in ["res://tests/six_schools_vfx_tests.gd", "res://tests/formal_spirit_tests.gd", "res://scripts/presentation/route_remaining_schools_vfx.gd", "res://scripts/presentation/route_lightning_vfx.gd", "res://scripts/presentation/route_spell_vfx.gd", "res://scripts/core/route_spell_combat.gd", "res://scripts/core/courtyard_route_run.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	var output: String = "res://build/qa/six-schools-implementation-20261021/vfx"
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--qa-out="): output = str(arg).trim_prefix("--qa-out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	FileAccess.open(output + "/results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks,
		"failures": failures.size(), "details": failures, "groups": groups, "samples": samples, "source_sha256": hashes,
		"scope": "Original engine headless Node3D construction and immutable actual/controlled snapshot synchronization. Null camera bypasses screen projection. No screenshot, pixel QA, interactive gameplay, natural route, frame time or performance measurement."}, "\t"))
	print("SIX SCHOOLS VFX BOUNDARIES checks=%d failures=%d" % [checks, failures.size()])
	render_node.free()
	quit(0 if failures.is_empty() else 1)

func remaining_state(renderer) -> Dictionary:
	var debug: Dictionary = renderer.get_debug_state()
	return debug.remaining_schools if debug.has("remaining_schools") else debug

func sample(renderer, snapshot: Dictionary, label: String, coverage_keys: Array = [], battle = null, reduced: bool = false) -> Dictionary:
	var original: Dictionary = snapshot.duplicate(true)
	var core_before: Dictionary = battle.get_snapshot() if battle != null else {}
	renderer.sync_snapshot(snapshot, null, {"reduced_motion": reduced})
	var first: Dictionary = renderer.get_debug_state()
	var remaining: Dictionary = remaining_state(renderer)
	var geometry: MultiMesh = renderer._remaining_vfx._lines.multimesh if first.has("remaining_schools") else renderer._lines.multimesh
	var initial_buffer: PackedFloat32Array = geometry.buffer.duplicate()
	check(snapshot == original, "input snapshot unchanged " + label)
	check(battle == null or battle.get_snapshot() == core_before, "renderer leaves authoritative core unchanged " + label)
	check(near(float(remaining.clock), float(snapshot.get("combat_time", snapshot.get("time", 0.0)))), "clock reads supplied combat time " + label)
	check(int(remaining.line_count) <= int(remaining.line_limit), "line cap respected " + label)
	check(int(remaining.line_count) == int(renderer._remaining_vfx._lines.multimesh.visible_instance_count) if first.has("remaining_schools") else int(remaining.line_count) == int(renderer._lines.multimesh.visible_instance_count), "visible count matches debug " + label)
	for key in coverage_keys: check(remaining.coverage.has(key), "expected source coverage " + label + " " + str(key))
	for _repeat in range(3): renderer.sync_snapshot(snapshot, null, {"reduced_motion": reduced})
	check(renderer.get_debug_state() == first and snapshot == original, "repeated sync never advances geometry clock or snapshot " + label)
	check(geometry.buffer == initial_buffer, "repeated sync preserves actual geometry and colors " + label)
	check(battle == null or battle.get_snapshot() == core_before, "repeated sync never advances rule timers " + label)
	samples.append({"label": label, "line_count": remaining.line_count, "line_limit": remaining.line_limit,
		"clock": remaining.clock, "coverage": remaining.coverage, "reduced_motion": reduced})
	return remaining

func actual_core_snapshot_shapes(remaining, integrated):
	# The wind fixture retains the production movement-recording hook while
	# isolating enemy AI, unlike the stationary spirit fixture used elsewhere.
	var wind = WindRules.Fixture.new()
	check(wind.configure({"route_school": "wind"}, 20261021).ok, "actual wind renderer-fixture configure")
	check(wind.choose_initial("W01"), "actual wind renderer-fixture initial choice")
	wind._spawn_done = true
	wind.spawn_warnings.clear()
	wind.blocks.clear()
	wind.player.pos = Vector2.ZERO
	wind.player.previous = Vector2.ZERO
	wind.player.crit_rate = 0.0
	wind.spells.clear()
	for id in ["W01", "W05", "W08", "W09"]:
		var spell: Dictionary = wind._new_spell(id)
		spell.level = 3
		wind._refresh_spell(spell)
		wind.spells.append(spell)
	wind.actors = [enemy()]
	stop_natural(wind)
	wind._enemy_combat.enemy_projectiles = [{"id": 9900, "pos": Vector2(0, 5), "direction": Vector2(0, -1), "speed": 4.0, "remaining": 2.0, "radius": 0.1}]
	for id in ["W01", "W05", "W08", "W09"]: release(wind, id)
	var before_move: Dictionary = wind.get_snapshot()
	check(not before_move.wind_projectiles.is_empty(), "actual wind projectile exists")
	sample(remaining, before_move, "wind_projectile_zones", ["wind_projectile", "wind_vortex", "wind_guard"], wind)
	for _index in range(48): wind.step(1.0 / 120.0, Vector2.RIGHT)
	var path_snapshot: Dictionary = wind.get_snapshot()
	check(not path_snapshot.wind_path_segments.is_empty(), "actual autonomous movement created recorded path segments")
	sample(integrated, path_snapshot, "wind_actual_path", ["wind_vortex", "wind_guard", "wind_path"], wind)
	var earth = fresh(["R01", "R02", "R03", "R04", "R09"], 3)
	for id in ["R01", "R02", "R03", "R04", "R09"]: release(earth, id)
	advance(earth, 0.05)
	var earth_snapshot: Dictionary = earth.get_snapshot()
	check(not earth_snapshot.earth_projectiles.is_empty() and not earth_snapshot.earth_waves.is_empty(), "actual earth projectile and expanding wave exist")
	sample(remaining, earth_snapshot, "earth_projectile_wave_constructs", ["earth_projectile", "earth_wave", "R04_construct", "R09_construct"], earth)
	advance(earth, 0.35)
	sample(integrated, earth.get_snapshot(), "earth_actual_fall_construct", ["R03_construct", "R04_construct", "R09_construct"], earth)
	var spirit = fresh(["S01", "S02", "S03", "S04", "S05", "S07", "S08", "S09"], 3)
	for id in ["S02", "S03", "S04", "S07", "S05", "S01", "S08"]: release(spirit, id)
	spirit.player.shield -= 10.0
	release(spirit, "S09")
	var spirit_snapshot: Dictionary = spirit.get_snapshot()
	check(spirit_snapshot.spirit_units.size() == 4 and not spirit_snapshot.spirit_projectiles.is_empty() and not spirit_snapshot.spirit_mark.is_empty(), "actual four units three families projectile and shared mark exist")
	var expected: Array = ["S02_unit", "S03_unit", "S04_unit", "spirit_field", "spirit_projectile", "spirit_mark", "spirit_summon", "spirit_command_start", "spirit_chain", "spirit_shield"]
	sample(remaining, spirit_snapshot, "spirit_actual_full_team", expected, spirit)
	sample(integrated, spirit_snapshot, "spirit_route_vfx_integration", expected, spirit)
	spirit.set_paused(true)
	var paused_snapshot: Dictionary = spirit.get_snapshot()
	var before_pause: Dictionary = sample(integrated, paused_snapshot, "paused_actual_snapshot", ["spirit_field", "spirit_mark"], spirit)
	advance(spirit, 0.5)
	check(spirit.get_snapshot() == paused_snapshot, "actual paused core remains frozen after attempted step")
	var after_pause: Dictionary = sample(integrated, spirit.get_snapshot(), "paused_repeated_frame", ["spirit_field", "spirit_mark"], spirit)
	check(before_pause == after_pause, "headless display sync does not animate a paused snapshot")
	spirit.set_paused(false)
	spirit._stop_combat()
	spirit.phase = "pickup"
	sample(integrated, spirit.get_snapshot(), "actual_core_stop_cleanup", [], spirit)
	check(int(remaining_state(integrated).line_count) == 0, "actual stop removes all remaining-school geometry")

func effect_and_phase_boundaries(remaining, integrated):
	var snapshot: Dictionary = empty_snapshot()
	var kinds: Array = RemainingVFX.HANDLED_EFFECTS.duplicate()
	kinds.append_array(["wind_guard", "wind_hit", "wind_mark", "wind_path_hit", "wind_scatter", "wind_vacuum_flight", "wind_vacuum_followup", "wind_vortex_hit", "wind_vacuum"])
	for kind in kinds:
		snapshot.effects.append({"kind": kind, "spell_id": "W04" if str(kind).begins_with("wind") else "R03" if str(kind).begins_with("earth") else "S01",
			"pos": Vector2.ZERO, "from": Vector2(-1, 0), "to": Vector2(1, 0), "direction": Vector2.UP, "angle_degrees": 100,
			"radius": 1.5, "life": 0.4, "max_life": 0.5})
	for id in ["W01", "R01", "S01"]: snapshot.effects.append({"kind": "cast", "spell_id": id, "pos": Vector2.ZERO, "life": 0.2, "max_life": 0.3})
	var expected: Array = kinds.duplicate()
	expected.append_array(["wind_cast", "earth_cast", "spirit_cast"])
	sample(remaining, snapshot, "all_controlled_source_effects", expected)
	sample(integrated, snapshot, "all_effects_route_integration", expected)
	for kind in kinds: check(integrated.handles_effect(str(kind)), "route claims new source effect " + str(kind))
	for phase in ["initial_choice", "cleared", "reward", "shop", "transition", "dead", "complete", "ended"]:
		var other: Dictionary = snapshot.duplicate(true)
		other.phase = phase
		sample(integrated, other, "phase_" + phase)
		check(int(remaining_state(integrated).line_count) == 0 and remaining_state(integrated).coverage.is_empty() and not integrated.visible, "noncombat phase clears all friendly batches " + phase)
	var next_room: Dictionary = empty_snapshot()
	next_room.room_revision = 999
	sample(integrated, next_room, "new_room_empty_combat")
	check(remaining_state(integrated).revision == 999 and remaining_state(integrated).footprints.is_empty() and not integrated.visible, "empty new room cannot retain old effect or footprint")

func bounded_batches_and_reduced_motion(remaining, integrated):
	var snapshot: Dictionary = empty_snapshot()
	snapshot.earth_constructs = [{"id": 1, "spell_id": "R04", "pos": Vector2.ZERO, "radius": 3.0}]
	snapshot.spirit_units = [{"id": 2, "spell_id": "S02", "family": "ranged", "pos": Vector2(1, 0)}]
	snapshot.spirit_fields = [{"id": 3, "pos": Vector2.ZERO, "radius": 3.0}]
	snapshot.wind_zones = [{"kind": "wind_vortex", "pos": Vector2(0, 1), "radius": 2.5}]
	var source_before: Dictionary = snapshot.duplicate(true)
	var normal: Dictionary = sample(remaining, snapshot, "normal_motion_controlled")
	var reduced: Dictionary = sample(remaining, snapshot, "reduced_motion_controlled", [], null, true)
	check(snapshot == source_before and normal.coverage == reduced.coverage and near(float(normal.clock), float(reduced.clock)), "reduced motion preserves every rule footprint and source coverage")
	check(int(reduced.line_count) < int(normal.line_count), "reduced motion changes displayed ring geometry only")
	sample(integrated, snapshot, "reduced_route_integration", [], null, true)
	check(bool(integrated.get_debug_state().reduced_motion), "route forwards reduced-motion display option")
	var saturated: Dictionary = empty_snapshot()
	saturated.earth_constructs = []
	for index in range(180): saturated.earth_constructs.append({"id": index + 1, "spell_id": "R04", "pos": Vector2.ZERO, "radius": 3.0})
	var full: Dictionary = sample(remaining, saturated, "controlled_batch_saturation")
	check(int(full.line_count) == int(full.line_limit), "controlled dense geometry saturates finite cap")
	var integrated_full: Dictionary = sample(integrated, saturated, "route_controlled_batch_saturation")
	check(int(integrated_full.line_count) <= int(integrated_full.line_limit), "route integration keeps same finite line cap")

func empty_snapshot() -> Dictionary:
	return {"phase": "combat", "time": 12.0, "combat_time": 8.5, "room_revision": 12,
		"player": {"pos": Vector2.ZERO}, "actors": [], "effects": [], "spells": []}

func wind_mastery_indicator(remaining):
	for level in range(1, 4):
		var battle = WindRules.Fixture.new()
		check(battle.configure({"route_school": "wind"}, 20261022).ok, "wind mastery display fixture configure")
		check(battle.choose_initial("W01"), "wind mastery display fixture start")
		battle._spawn_done = true
		battle.spawn_warnings.clear()
		battle.blocks.clear()
		battle.player.pos = Vector2.ZERO
		battle.player.previous = Vector2.ZERO
		battle.spells.clear()
		var spell: Dictionary = battle._new_spell("W10")
		spell.level = level
		battle._refresh_spell(spell)
		battle.spells.append(spell)
		battle.actors = [enemy()]
		for _tick in 60: battle.step(1.0 / 120.0, Vector2.RIGHT)
		var active: Dictionary = battle.get_snapshot()
		check(float(active.combat_stats.wind_bonus) > 0.0, "actual W10 bonus active L" + str(level))
		var state: Dictionary = sample(remaining, active, "wind_mastery_active_L" + str(level), ["wind_mastery"], battle)
		check(int(state.line_count) > 0, "actual active W10 has geometry L" + str(level))
		var unowned: Dictionary = active.duplicate(true)
		unowned.spells.clear()
		state = sample(remaining, unowned, "wind_mastery_unowned_L" + str(level))
		check(not state.coverage.has("wind_mastery"), "W10 display requires actual ownership L" + str(level))
		for _tick in 240: battle.step(1.0 / 120.0)
		var inactive: Dictionary = battle.get_snapshot()
		check(near(float(inactive.combat_stats.wind_bonus), 0.0), "actual W10 bonus expired L" + str(level))
		state = sample(remaining, inactive, "wind_mastery_expired_L" + str(level), [], battle)
		check(not state.coverage.has("wind_mastery"), "expired W10 has no marker L" + str(level))

func lightning_sample(integrated, snapshot: Dictionary, label: String, battle = null, reduced: bool = false) -> Dictionary:
	var original: Dictionary = snapshot.duplicate(true)
	var before: Dictionary = battle.get_snapshot() if battle != null else {}
	integrated.sync_snapshot(snapshot, null, {"reduced_motion": reduced})
	var state: Dictionary = integrated._lightning_vfx.get_debug_state()
	var batch: MultiMesh = integrated._lightning_vfx._lines.multimesh
	var initial_buffer: PackedFloat32Array = batch.buffer.duplicate()
	check(snapshot == original, "lightning snapshot unchanged " + label)
	check(battle == null or battle.get_snapshot() == before, "lightning authoritative core unchanged " + label)
	check(near(float(state.clock), float(snapshot.get("lightning_clock", snapshot.get("combat_time", snapshot.get("time", 0))))), "lightning supplied clock " + label)
	check(int(state.line_count) <= int(state.line_limit) and int(state.line_count) == batch.visible_instance_count, "lightning bounded actual batch " + label)
	var finite_geometry: bool = true
	for index in batch.visible_instance_count:
		var transform: Transform3D = batch.get_instance_transform(index)
		finite_geometry = finite_geometry and transform.origin.is_finite() and transform.basis.is_finite() and absf(transform.basis.determinant()) > 0.0000000001
	check(finite_geometry, "lightning finite nonsingular transforms " + label)
	for _repeat in range(3): integrated.sync_snapshot(snapshot, null, {"reduced_motion": reduced})
	check(integrated._lightning_vfx.get_debug_state() == state and snapshot == original, "lightning repeated sync frozen " + label)
	check(batch.buffer == initial_buffer, "lightning repeated sync preserves geometry and colors " + label)
	check(battle == null or battle.get_snapshot() == before, "lightning repeated sync preserves core " + label)
	samples.append({"label": label, "lightning": state, "reduced_motion": reduced})
	return state

func lightning_snapshot_boundaries(integrated):
	# Reuse the existing production-core fixture, isolating AI/spawn/clear only.
	var battle = fresh(["L01", "L02", "L03", "L04", "L05", "L06", "L07", "L08", "L09"], 3)
	battle.actors.append(enemy(2, Vector2(0.7, 2)))
	battle.actors.append(enemy(3, Vector2(-0.6, 2.4)))
	battle.player.shield -= 10.0
	for id in ["L01", "L02", "L04", "L05", "L06", "L07", "L09", "L03", "L08"]: release(battle, id)
	var actual: Dictionary = battle.get_snapshot()
	var state: Dictionary = lightning_sample(integrated, actual, "lightning_actual_release", battle)
	for key in ["L01_bolt", "L05_cloud", "lightning_status", "lightning_beam", "lightning_ring", "lightning_judgment_flight", "lightning_shield"]:
		check(state.coverage.has(key), "lightning actual source coverage " + key)
	advance(battle, 0.1)
	lightning_sample(integrated, battle.get_snapshot(), "lightning_actual_chain", battle)
	advance(battle, 0.31)
	var delayed: Dictionary = battle.get_snapshot()
	state = lightning_sample(integrated, delayed, "lightning_actual_delayed_hits", battle)
	for key in ["lightning_cloud_strike", "lightning_judgment"]:
		check(state.coverage.has(key), "actual delayed lightning source " + key)
		for effect in delayed.effects:
			if effect.kind != key: continue
			var found: bool = false
			for footprint in state.footprints:
				if footprint.kind != key: continue
				if key == "lightning_cloud_strike":
					found = found or (footprint.from == effect.from and footprint.to == effect.pos and footprint.cloud_id == effect.cloud_id and footprint.wave == effect.wave)
				else:
					found = found or (footprint.pos == effect.pos and near(float(footprint.radius), float(effect.radius)))
			check(found, "actual delayed lightning geometry follows emitted fields " + key)
	battle.set_paused(true)
	var paused: Dictionary = battle.get_snapshot()
	advance(battle, 0.3)
	check(battle.get_snapshot() == paused, "lightning paused rule snapshot frozen")
	lightning_sample(integrated, paused, "lightning_actual_pause", battle)
	var controlled: Dictionary = empty_snapshot()
	for kind in LightningVFX.HANDLED_EFFECTS:
		controlled.effects.append({"kind": kind, "spell_id": "L08" if kind == "lightning_arc" else "L07", "pos": Vector2.ZERO,
			"from": Vector2(-1, 0), "to": Vector2(1, 0), "radius": 1.5, "life": 0.3, "max_life": 0.5})
	state = lightning_sample(integrated, controlled, "lightning_all_events")
	for kind in LightningVFX.HANDLED_EFFECTS:
		check(state.coverage.has(kind), "lightning controlled event coverage " + kind)
		check(integrated.handles_effect(kind), "route dispatch claims lightning event " + kind)
	var reduced: Dictionary = lightning_sample(integrated, controlled, "lightning_reduced_events", null, true)
	check(state.coverage == reduced.coverage and int(reduced.line_count) < int(state.line_count), "lightning reduced motion preserves source information with fewer decorative segments")
	# Vulnerability is independently valid after conductivity expires.
	var vulnerability: Dictionary = empty_snapshot()
	vulnerability.actors = [enemy()]
	vulnerability.lightning_states = [{"actor_id": 1, "remaining": 0.0, "vulnerability": 0.2, "vulnerability_remaining": 2.0}]
	state = lightning_sample(integrated, vulnerability, "lightning_vulnerability_only")
	check(int(state.line_count) > 0, "valid vulnerability stays visible without conductivity")
	vulnerability.lightning_states[0].vulnerability_remaining = 0.0
	state = lightning_sample(integrated, vulnerability, "lightning_expired_status")
	check(int(state.line_count) == 0, "expired lightning status leaves no marker")
	var saturated: Dictionary = empty_snapshot()
	for index in range(180):
		saturated.effects.append({"kind": "lightning_judgment", "spell_id": "L07", "pos": Vector2.ZERO, "radius": 2.0, "life": 0.3, "max_life": 0.5})
	state = lightning_sample(integrated, saturated, "lightning_controlled_saturation")
	check(int(state.line_count) == int(state.line_limit), "lightning finite batch saturation")
	for phase in ["reward", "transition", "dead", "complete", "ended"]:
		controlled.phase = phase
		state = lightning_sample(integrated, controlled, "lightning_phase_" + phase)
		check(int(state.line_count) == 0 and state.coverage.is_empty() and state.footprints.is_empty(), "lightning no retained geometry outside combat " + phase)
	state = lightning_sample(integrated, empty_snapshot(), "lightning_new_room_empty")
	check(int(state.line_count) == 0 and not integrated.visible, "lightning empty snapshot cannot retain previous geometry")
