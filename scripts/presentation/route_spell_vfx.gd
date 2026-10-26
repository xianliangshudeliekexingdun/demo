extends Node3D
## Batched, procedural, source-driven friendly magic. No elapsed wall clock.
## Snapshot/context owns position, extent, lifetime and whether an effect exists.

const FIRE_SHADER = preload("res://scripts/presentation/procedural_fire.gdshader")
const IceVFX = preload("res://scripts/presentation/route_ice_vfx.gd")
const LightningVFX = preload("res://scripts/presentation/route_lightning_vfx.gd")
const RemainingVFX = preload("res://scripts/presentation/route_remaining_schools_vfx.gd")
const FLAME_TEXTURE_PATH = "res://assets/vfx/fire_v2/flame_tongue.png"
const QUAD_LIMIT = 768
const CORE_LIMIT = 128
const FRIENDLY_EFFECTS = ["cast", "beam", "spirit_bolt", "bolt_hit", "rain_impact", "bomb_flight", "bomb_impact", "aftershock", "wave", "shield_restore", "summon", "artifact_patch", "artifact_explosion", "artifact_speed", "artifact_cooldown", "artifact_acquired", "fire_brand", "fire_spread", "fire_detonation", "fire_ignited", "fire_reignited"]
const GEM_EFFECTS = [] # Ten-core feedback is owned by route_gem_vfx; retain old branches for source compatibility.

var _cards: MultiMeshInstance3D
var _cores: MultiMeshInstance3D
var _fire_material: ShaderMaterial
var _core_material: StandardMaterial3D
var _camera: Camera3D
var _q: int = 0
var _c: int = 0
var _clock: float = 0.0
var _reduced: bool = false
var _footprints: Array = []
var _coverage: Dictionary = {}
var _revision: int = -1
var _ice_vfx: Node3D
var _lightning_vfx: Node3D
var _remaining_vfx: Node3D
var _fire_bolt_override := false


func set_fire_bolt_override(enabled: bool) -> void:
	_fire_bolt_override = enabled


func _ready():
	name = "RouteSpellVFX"
	set_meta("source", "original_procedural_fire_shader_and_cached_mesh_batches")
	_fire_material = ShaderMaterial.new()
	_fire_material.shader = FIRE_SHADER
	_fire_material.render_priority = -5
	_fire_material.set_shader_parameter("has_flame_texture", false)
	if ResourceLoader.exists(FLAME_TEXTURE_PATH):
		var texture = load(FLAME_TEXTURE_PATH) as Texture2D
		_fire_material.set_shader_parameter("flame_texture", texture)
		var source_image = texture.get_image()
		if source_image != null:
			# Sample the actual alpha footprint, retaining a few transparent pixels.
			# The generated source file remains untouched; padded sprites do not shrink.
			var used = _visible_alpha_rect(source_image).grow(4).intersection(Rect2i(Vector2i.ZERO, source_image.get_size()))
			if used.has_area():
				var image_size = Vector2(source_image.get_size())
				_fire_material.set_shader_parameter("flame_uv_rect", Vector4(float(used.position.x) / image_size.x, float(used.position.y) / image_size.y, float(used.size.x) / image_size.x, float(used.size.y) / image_size.y))
		_fire_material.set_shader_parameter("has_flame_texture", true)
	var quad = QuadMesh.new()
	quad.size = Vector2.ONE
	_cards = _batch("FlameRibbonsAndHeat", quad, _fire_material, QUAD_LIMIT, true)
	var sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 4
	_core_material = StandardMaterial3D.new()
	_core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_material.vertex_color_use_as_albedo = true
	_core_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_core_material.emission_enabled = true
	_core_material.emission = Color(0.27, 0.13, 0.025)
	_cores = _batch("MoltenCores", sphere, _core_material, CORE_LIMIT, false)
	_ice_vfx = IceVFX.new()
	add_child(_ice_vfx)
	_lightning_vfx = LightningVFX.new()
	add_child(_lightning_vfx)
	_remaining_vfx = RemainingVFX.new()
	add_child(_remaining_vfx)
	set_process(false)


func handles_effect(kind: String) -> bool:
	return kind.begins_with("wind_") or kind.begins_with("earth_") or kind.begins_with("spirit_") or kind in FRIENDLY_EFFECTS or kind in IceVFX.HANDLED_EFFECTS or kind in LightningVFX.HANDLED_EFFECTS or kind in GEM_EFFECTS


func sync_snapshot(snapshot: Dictionary, camera: Camera3D, options: Dictionary = {}):
	if not is_instance_valid(_cards):
		return
	_camera = camera
	_reduced = bool(options.get("reduced_motion", false))
	_clock = float(snapshot.get("combat_time", snapshot.get("time", 0.0)))
	_q = 0
	_c = 0
	_footprints.clear()
	_coverage.clear()
	_revision = int(snapshot.get("room_revision", -1))
	_fire_material.set_shader_parameter("core_time", _clock)
	_fire_material.set_shader_parameter("reduced_motion", _reduced)
	var combat = snapshot.get("phase", "") == "combat"
	if combat:
		var actors_by_id: Dictionary = {}
		for actor in snapshot.get("actors", []):
			actors_by_id[int(actor.id)] = actor
		for burn in snapshot.get("spell_burns", []):
			var actor: Dictionary = actors_by_id.get(int(burn.get("actor_id", -1)), {})
			if not actor.is_empty() and float(actor.get("health", 0)) > 0 and float(burn.get("remaining", 0)) > 0:
				_burning(actor, burn)
		for projectile in snapshot.get("projectiles", []):
			_bolt(projectile)
		for zone in snapshot.get("spell_zones", []):
			_zone(zone)
		for pending in snapshot.get("spell_pending", []):
			_pending(pending, float(snapshot.get("time", 0.0)))
		var units: Array = snapshot.get("spirits", [])
		if units.is_empty() and bool(snapshot.get("spirit", {}).get("active", false)):
			units = [snapshot.spirit]
		for unit in units:
			_spirit(unit)
		for patch in snapshot.get("artifact_patches", []):
			if _fire_bolt_override and str(patch.get("context", {}).get("spell_id", "")) == "F01": continue
			var center: Vector2 = patch.get("pos", Vector2.ZERO)
			var radius = float(patch.get("radius", 0.0))
			_ground(center, radius, 1, 0.65, 0.0, float(patch.get("cast_id", 0)))
			_flame_scatter(center, radius * 0.83, 4, 0.35, 0.6, float(patch.get("cast_id", 0)))
			_footprints.append({"kind": "artifact_patch", "pos": center, "radius": radius})
		for spell in snapshot.get("spells", []):
			if spell.id == "F02":
				_ground(snapshot.player.pos, 0.39, 7, 0.23, 0.0, 2.0)
				_note("F02_passive")
	for effect in snapshot.get("effects", []):
		if combat or effect.get("kind", "") == "artifact_acquired":
			_effect(effect, snapshot)
	_cards.multimesh.visible_instance_count = _q
	_cores.multimesh.visible_instance_count = _c
	_ice_vfx.sync_snapshot(snapshot, camera, options)
	_lightning_vfx.sync_snapshot(snapshot, camera, options)
	_remaining_vfx.sync_snapshot(snapshot, camera, options)
	visible = _q > 0 or _c > 0 or _ice_vfx.visible or _lightning_vfx.visible or _remaining_vfx.visible


func get_debug_state() -> Dictionary:
	var ice: Dictionary = _ice_vfx.get_debug_state() if is_instance_valid(_ice_vfx) else {}
	var lightning: Dictionary = _lightning_vfx.get_debug_state() if is_instance_valid(_lightning_vfx) else {}
	var remaining: Dictionary = _remaining_vfx.get_debug_state() if is_instance_valid(_remaining_vfx) else {}
	var coverage: Dictionary = _coverage.duplicate(true)
	for key in remaining.get("coverage", {}): coverage[key] = int(coverage.get(key, 0)) + int(remaining.coverage[key])
	for key in ice.get("coverage", {}):
		coverage[key] = int(coverage.get(key, 0)) + int(ice.coverage[key])
	for key in lightning.get("coverage", {}):
		coverage[key] = int(coverage.get(key, 0)) + int(lightning.coverage[key])
	var footprints: Array = _footprints.duplicate(true)
	footprints.append_array(ice.get("footprints", []))
	footprints.append_array(lightning.get("footprints", []))
	footprints.append_array(remaining.get("footprints", []))
	return {"quad_count": _q, "core_count": _c, "quad_limit": QUAD_LIMIT, "core_limit": CORE_LIMIT, "clock": _clock, "reduced_motion": _reduced, "revision": _revision, "footprints": footprints, "coverage": coverage, "material_count": 6, "batch_count": 6, "fire_material_count": 2, "fire_batch_count": 2, "ice": ice, "lightning": lightning, "remaining_schools": remaining, "painted_flame_bound": _fire_material.get_shader_parameter("has_flame_texture") == true}


func _bolt(projectile: Dictionary):
	if _fire_bolt_override and str(projectile.get("spell_id", "")) == "F01": return
	var pos: Vector2 = projectile.get("pos", Vector2.ZERO)
	if not _in_view(pos, 1.2):
		return
	var direction: Vector2 = projectile.get("direction", Vector2(0, 1))
	var radius = float(projectile.get("radius", 0.15))
	var seed = float(projectile.get("id", 0))
	var world = _point(pos, 0.66)
	_core(world, Vector3.ONE * radius * 1.7, Color("ffe4a5"))
	_flame(world + Vector3(0, 0.03, 0), Vector2(radius * 3.2, radius * 4.8), 0.94, seed)
	var length = minf(float(projectile.get("travelled", 0.0)), 1.35)
	if length > 0.01:
		_ribbon(_point(pos - direction * length, 0.66), world, radius * 1.6, 0.72, seed)
		_sparks(pos - direction * length * 0.5, radius * 1.5, 0.5, 3, 0.5, seed, true)
	if not bool(projectile.get("context", {}).get("natural", true)):
		_ground(projectile.get("from", pos), 0.36, 7, 0.42, 0.75, seed)
	_note("F01_bolt")


func _zone(zone: Dictionary):
	var pos: Vector2 = zone.get("pos", Vector2.ZERO)
	var radius = float(zone.get("radius", 0.0))
	if not _in_view(pos, radius):
		return
	var kind = str(zone.get("kind", ""))
	var seed = float(zone.get("id", 0))
	var alpha = minf(1.0, float(zone.get("remaining", 1.0)) / 0.25)
	if kind == "rain":
		_ground(pos, radius, 4, 0.32, 0.0, seed)
	elif kind == "rain_ground":
		_ground(pos, radius, 1, alpha * 0.90, 0.0, seed)
		_flame_scatter(pos, radius * 0.83, 7, 0.45, alpha * 0.58, seed)
		_sparks(pos, radius * 0.8, 0.8, 5, alpha * 0.48, seed, true)
	elif kind == "field":
		_ground(pos, radius, 4, alpha, 0.0, seed)
		_ground(pos, radius * 0.65, 1, alpha * 0.50, 0.0, seed)
		_flame_scatter(pos, radius * 0.83, 6, 0.54, alpha * 0.58, seed)
	elif kind == "vortex":
		_ground(pos, radius, 1, alpha * 0.74, 0.0, seed)
		var count = 4 if _reduced else 9
		for index in count:
			var phase = float(index) / count
			var angle = phase * TAU * 1.7 + (0.0 if _reduced else _clock * 2.7)
			var r = radius * (0.72 - phase * 0.32)
			var p = pos + Vector2.from_angle(angle) * r
			_flame(_point(p, 0.10 + phase * 1.25), Vector2(radius * 0.62, 0.65 + phase * 0.55), alpha * 0.58, seed + index)
		_sparks(pos, radius * 0.8, 1.7, 6, alpha * 0.56, seed, true)
	if not bool(zone.get("context", {}).get("natural", true)):
		_ground(pos, radius * 0.22, 7, 0.4, 0.75, seed)
	_footprints.append({"kind": kind, "pos": pos, "radius": radius})
	_note("F03" if kind.begins_with("rain") else "F05" if kind == "vortex" else "F06")


func _pending(pending: Dictionary, total_time: float):
	if pending.get("kind", "") != "rain_drop":
		return
	var pos: Vector2 = pending.get("pos", Vector2.ZERO)
	var delay = float(pending.get("stats", {}).get("impact_delay", 0.0))
	var wait = float(pending.get("at", 0.0)) - total_time
	if delay <= 0.0 or wait < 0.0 or wait > delay or not _in_view(pos, 1.0):
		return
	var height = 0.12 + 3.5 * clampf(wait / delay, 0.0, 1.0)
	var world = _point(pos, height)
	_core(world, Vector3(0.13, 0.28, 0.13), Color("ffe0a0"))
	_flame(world + Vector3(0, 0.18, 0), Vector2(0.33, 0.85), 0.9, float(pending.get("at", 0.0)))
	_note("F03_rainfall")


func _spirit(unit: Dictionary):
	var pos: Vector2 = unit.get("pos", Vector2.ZERO)
	if not _in_view(pos, 0.8):
		return
	var seed = float(unit.get("index", 0)) + 4.0
	var world = _point(pos, 1.03)
	_core(world, Vector3(0.22, 0.28, 0.22), Color("ffda85"))
	_flame(world + Vector3(0, 0.09, 0), Vector2(0.49, 0.77), 0.9, seed)
	_flame(world + Vector3(-0.15, -0.13, 0.02), Vector2(0.25, 0.40), 0.65, seed + 2.0)
	_sparks(pos, 0.30, 1.0, 3, 0.65, seed, true)
	_note("F04_spirit")

func _burning(actor: Dictionary, burn: Dictionary):
	if _fire_bolt_override and str(burn.get("source", "")) == "F01": return
	var pos: Vector2 = actor.get("pos", Vector2.ZERO)
	var radius = maxf(0.25, float(actor.get("radius", 0.4)))
	if not _in_view(pos, radius):
		return
	var alpha = minf(1.0, float(burn.get("remaining", 0)) / 0.3)
	var seed = float(actor.get("id", 0))
	_ground(pos, radius * 1.05, 7, alpha * 0.36, 0.0, seed)
	_flame_scatter(pos, radius * 0.7, 3, 0.38, alpha * 0.50, seed)
	_footprints.append({"kind": "burning", "pos": pos, "actor_id": actor.get("id", -1), "remaining": burn.get("remaining", 0)})
	_note("burning")


func _effect(effect: Dictionary, snapshot: Dictionary):
	var kind = str(effect.get("kind", ""))
	if _fire_bolt_override and ((kind in ["cast", "bolt_hit", "artifact_patch"] and str(effect.get("spell_id", "")) == "F01") or (kind == "fire_ignited" and str(effect.get("source", "")) == "F01")): return
	if (kind not in FRIENDLY_EFFECTS and kind not in GEM_EFFECTS) or (kind == "cast" and str(effect.get("spell_id", "")).left(1) in ["I", "L", "W", "R", "S"]):
		return
	var alpha = clampf(float(effect.get("life", 0.0)) / maxf(0.001, float(effect.get("max_life", 0.1))), 0.0, 1.0)
	if alpha <= 0.0:
		return
	var progress = 1.0 - alpha
	var pos: Vector2 = effect.get("pos", Vector2.ZERO)
	var radius = float(effect.get("radius", 0.7))
	var seed = float(effect.get("seq", 0))
	match kind:
		"gem_fracture":
			var from: Vector2 = effect.get("from", pos)
			var to: Vector2 = effect.get("to", pos)
			var a: Vector3 = _point(from, 0.55)
			var b: Vector3 = _point(to, 0.55)
			for index in 7:
				_core(a.lerp(b, float(index)/6.0), Vector3.ONE*0.08*alpha, Color("b3efff"))
			_core(_point(to,1.0),Vector3(0.17,0.7,0.17)*alpha,Color("d3f5ff"))
		"gem_coffin", "gem_reactor":
			var color: Color = Color("9ae1f6") if kind == "gem_coffin" else Color("f0cd96")
			var extent: float = radius
			for index in (8 if _reduced else 16):
				var angle: float = TAU*float(index)/(8.0 if _reduced else 16.0)
				_core(_point(pos+Vector2.from_angle(angle)*extent*(0.3+0.7*progress), 0.3),Vector3.ONE*0.11*alpha,color)
			_core(_point(pos, 0.65),Vector3(0.28,0.65,0.28)*alpha,color)
		"gem_echo":
			var color:Color=Color("ad9bf4")
			for index in (8 if _reduced else 16):
				var at:float=float(index)/(7.0 if _reduced else 15.0)
				var point: Vector2
				var shape: String = str(effect.get("kind_shape", ""))
				if shape == "segment": point = effect.from.lerp(effect.to, at)
				elif shape == "segments":
					var pieces: Array = effect.get("segments", [])
					if pieces.is_empty(): continue
					var piece: Dictionary = pieces[mini(pieces.size() - 1, int(at * pieces.size()))]
					point = piece.from.lerp(piece.to, fmod(at * pieces.size(), 1.0))
				elif shape == "cone":
					var direction: Vector2 = effect.get("direction", Vector2.UP)
					point = pos + direction.rotated(deg_to_rad(float(effect.get("angle_degrees", 0))) * (at - 0.5)) * radius
				else: point = pos + Vector2.from_angle(at * TAU) * radius
				_core(_point(point,0.25),Vector3.ONE*0.13*alpha,color)
		"fire_spread":
			var from: Vector2 = effect.get("from", pos)
			var to: Vector2 = effect.get("to", pos)
			_ribbon(_point(from, 0.4), _point(to, 0.4), 0.055, alpha * 0.72, seed)
			_flame(_point(to, 0.3), Vector2(0.26, 0.48), alpha * 0.8, seed)
			_footprints.append({"kind": kind, "from": from, "to": to})
		"fire_brand":
			_ground(pos, 0.48, 7, alpha * 0.9, 0.0, seed)
			_flame(_point(pos, 0.65), Vector2(0.42, 0.92), alpha * 0.85, seed)
			_sparks(pos, 0.34, 0.9, 4, alpha * 0.7, seed, false, progress)
		"fire_detonation":
			# A target-local upward flare, not a new area-of-effect explosion.
			_ground(pos, 0.36, 3, alpha * 0.75, 0.0, seed)
			_flame(_point(pos, 0.75), Vector2(0.62, 1.4) * (0.8 + progress * 0.2), alpha * 0.95, seed)
			_core(_point(pos, 0.4), Vector3(0.28, 0.6, 0.28) * alpha, Color("ffe6a4"))
			_sparks(pos, 0.42, 1.35, 7, alpha * 0.8, seed, false, progress)
			_footprints.append({"kind": kind, "pos": pos, "actor_id": effect.get("actor_id", -1)})
		"fire_ignited", "fire_reignited":
			if kind == "fire_reignited":
				# The one-off relic proc must read above the body; persistent burn stays low.
				_flame(_point(pos, 1.15), Vector2(0.45, 1.0), alpha * 0.9, seed)
				_ground(pos, 0.4, 7, alpha * 0.6, 0.0, seed)
				if not _reduced:
					for index in 3:
						var point = pos + Vector2.from_angle(index * TAU / 3.0 + seed) * 0.18
						_card(_point(point, 1.05 + progress * 0.8 + index * 0.08), _billboard_basis(), Vector2(0.04, 0.075), 6, alpha * 0.8, 0.0, seed + index)
			else:
				_flame(_point(pos, 0.3), Vector2(0.32, 0.6), alpha * 0.75, seed)
		"beam", "spirit_bolt":
			var from: Vector2 = effect.get("from", pos)
			var to: Vector2 = effect.get("to", pos)
			var width = float(effect.get("radius", 0.0)) * 2.0
			if kind == "spirit_bolt":
				width = 0.10
			_ribbon(_point(from, 0.72), _point(to, 0.72), maxf(width, 0.06), alpha * 0.91, seed)
			_sparks(to, maxf(width * 0.4, 0.12), 0.65, 4, alpha * 0.75, seed, false, progress)
			_footprints.append({"kind": kind, "from": from, "to": to, "half_width": float(effect.get("radius", 0.0))})
		"cast":
			# Chant feedback stays below impact art; the ring and motion still read.
			_ground(pos, 0.48, 7, alpha * 0.30, 0.0, seed)
			_flame(_point(pos, 0.82), Vector2(0.22, 0.45), alpha * 0.36, seed)
		"bolt_hit", "rain_impact", "bomb_impact", "aftershock", "artifact_explosion":
			if bool(effect.get("blocked", false)):
				_sparks(pos, 0.28, 0.65, 5, alpha * 0.8, seed, false, progress)
			else:
				var heavy = kind in ["bomb_impact", "artifact_explosion"]
				_ground(pos, radius, 1, alpha * 0.85, 0.0, seed)
				_ground(pos, radius * (0.38 + progress * 0.62), 3, alpha * 0.92, 0.0, seed)
				_core(_point(pos, 0.46), Vector3.ONE * (0.18 + alpha * 0.16), Color("fff1c4"))
				_flame_scatter(pos, radius * 0.68, 8 if heavy else 4, (1.15 if heavy else 0.62) * alpha + 0.12, alpha * 0.9, seed)
				_sparks(pos, radius * 0.86, 1.8 if heavy else 0.85, 13 if heavy else 7, alpha * 0.9, seed, false, progress)
			_footprints.append({"kind": kind, "pos": pos, "radius": radius})
		"bomb_flight":
			var from: Vector2 = effect.get("from", pos)
			var to: Vector2 = effect.get("to", pos)
			var current = from.lerp(to, progress)
			var world = _point(current, 0.65 + sin(progress * PI) * 2.7)
			_core(world, Vector3.ONE * 0.43, Color("ffce7d"))
			_flame(world + Vector3(0, 0.05, 0), Vector2(0.68, 1.05), 0.93, seed)
			var prior = maxf(0.0, progress - 0.15)
			_ribbon(_point(from.lerp(to, prior), 0.65 + sin(prior * PI) * 2.7), world, 0.20, 0.65, seed)
		"wave":
			var current_radius = radius * (0.18 + progress * 0.82)
			_ground(pos, current_radius, 3, alpha * 0.90, 0.0, seed)
			_flame_scatter(pos, current_radius * 0.90, 8, 0.72 * alpha + 0.1, alpha * 0.75, seed)
			_footprints.append({"kind": kind, "pos": pos, "radius": radius})
		"shield_restore":
			var center: Vector2 = snapshot.get("player", {}).get("pos", pos)
			var camera_basis = _camera.global_basis if _camera != null else Basis.IDENTITY
			for side in [-1, 1]:
				# Two broad, bowed wings sit outside Lina's body in the camera plane,
				# so neither a rear plate nor an edge-on card can hide the restoration.
				var offset = camera_basis.x * (side * 0.58) + camera_basis.z * 0.14
				var world = _point(center, 1.02) + offset
				_card(world, camera_basis, Vector2(0.90, 1.46), 5, alpha * 0.98, 0.0 if side < 0 else 1.0, seed + side)
				var light_start = _point(center, 0.25) + camera_basis.x * (side * 0.62) + camera_basis.z * 0.16
				_ribbon(light_start, light_start + Vector3(0, 1.3 * (0.55 + progress * 0.45), 0), 0.045, alpha * 0.36, seed + side)
			_sparks(center, 0.62, 1.7, 8, alpha * 0.8, seed, false, progress)
		"summon":
			_sparks(pos, 0.39, 1.1, 7, alpha * 0.85, seed, false, progress)
		"artifact_acquired":
			var center: Vector2 = snapshot.get("player", {}).get("pos", pos)
			_ground(center, 0.95, 7, alpha * 0.72, 0.45, seed)
			_sparks(center, 0.75, 2.2, 13, alpha, seed, false, progress)
			for index in 3:
				_flame(_point(center + Vector2.from_angle(index * TAU / 3.0) * 0.35, 0.5 + progress * 0.7), Vector2(0.14, 0.85), alpha * 0.42, seed + index)
		"artifact_patch":
			if progress < 0.15:
				_flame_scatter(pos, radius * 0.6, 5, 0.45, alpha * 0.55, seed)
		"artifact_cooldown":
			var center: Vector2 = snapshot.get("player", {}).get("pos", pos)
			_ground(center, 0.80, 7, alpha * 0.73, 0.9, seed)
			_sparks(center, 0.6, 1.3, 5, alpha * 0.8, seed, false, progress)
		"artifact_speed":
			var center: Vector2 = snapshot.get("player", {}).get("pos", pos)
			_sparks(center, 0.4, 0.35, 4, alpha * 0.6, seed, true)
	_note(kind)


func _flame_scatter(pos: Vector2, radius: float, count: int, height: float, alpha: float, seed: float):
	var number = mini(count, 3) if _reduced else count
	for index in number:
		var angle = index * TAU / number + seed * 0.21
		var r = radius * (0.7 + 0.25 * sin(seed + index * 2.1))
		var point = pos + Vector2.from_angle(angle) * r
		var variation = 0.83 + 0.17 * sin(seed * 0.7 + index * 2.7)
		_flame(_point(point, 0.08 + height * 0.36 * variation), Vector2(height * (0.58 + 0.12 * sin(index + seed)), height) * variation, alpha, seed + index)


func _sparks(pos: Vector2, radius: float, height: float, count: int, alpha: float, seed: float, looping: bool, progress: float = 0.0):
	if _reduced:
		return
	for index in count:
		var cycle = fposmod(_clock * 0.73 + index * 0.618 + seed * 0.11, 1.0) if looping else progress
		var angle = index * 2.4 + seed
		var distance = radius * sqrt(clampf(cycle, 0.0, 1.0))
		var point = pos + Vector2.from_angle(angle) * distance
		var y = 0.08 + height * sin(cycle * PI * 0.78)
		_card(_point(point, y), _billboard_basis(), Vector2(0.035, 0.07) * (1.0 - cycle * 0.4), 6, alpha * (1.0 - cycle * 0.7), 0.0, seed + index)


func _flame(pos: Vector3, dimensions: Vector2, alpha: float, seed: float):
	_card(pos, _billboard_basis(), dimensions, 0, alpha, 0.0, seed)


func _ground(pos: Vector2, radius: float, mode: int, alpha: float, phase: float, seed: float):
	if radius <= 0.0 or not _in_view(pos, radius):
		return
	_card(_point(pos, 0.055), Basis(Vector3.RIGHT, Vector3(0, 0, -1), Vector3.UP), Vector2.ONE * radius * 2.0, mode, alpha, phase, seed)


func _ribbon(from: Vector3, to: Vector3, width: float, alpha: float, seed: float):
	var length = from.distance_to(to)
	if length <= 0.001:
		return
	var center = (from + to) * 0.5
	if not _in_view(Vector2(center.x, -center.z), length * 0.5):
		return
	var x = (to - from).normalized()
	var facing = (_camera.global_position - center).normalized() if _camera != null else Vector3(0, 0.6, 0.8)
	var y = facing.cross(x).normalized()
	if y.length_squared() < 0.001:
		y = Vector3.UP
	_card(center, Basis(x, y, x.cross(y).normalized()), Vector2(length, width), 2, alpha, 0.0, seed)


func _card(pos: Vector3, basis: Basis, dimensions: Vector2, mode: int, alpha: float, phase: float, seed: float):
	if _q >= QUAD_LIMIT or alpha <= 0.0 or not _in_view(Vector2(pos.x, -pos.z), maxf(dimensions.x, dimensions.y) * 0.55):
		return
	var transform = Transform3D(Basis(basis.x * dimensions.x, basis.y * dimensions.y, basis.z), pos)
	_cards.multimesh.set_instance_transform(_q, transform)
	_cards.multimesh.set_instance_color(_q, Color.WHITE)
	_cards.multimesh.set_instance_custom_data(_q, Color(float(mode) / 10.0, phase, alpha, fposmod(seed * 0.173, 1.0)))
	_q += 1


func _core(pos: Vector3, dimensions: Vector3, color: Color):
	if _c >= CORE_LIMIT or not _in_view(Vector2(pos.x, -pos.z), maxf(dimensions.x, dimensions.z)):
		return
	_cores.multimesh.set_instance_transform(_c, Transform3D(Basis.from_scale(dimensions), pos))
	_cores.multimesh.set_instance_color(_c, color)
	_c += 1


func _batch(batch_name: String, mesh: Mesh, material: Material, capacity: int, custom: bool) -> MultiMeshInstance3D:
	var node = MultiMeshInstance3D.new()
	node.name = batch_name
	var batch = MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.use_custom_data = custom
	batch.mesh = mesh
	batch.instance_count = capacity
	batch.visible_instance_count = 0
	batch.custom_aabb = AABB(Vector3(-60, -1, -60), Vector3(120, 24, 120))
	node.multimesh = batch
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _billboard_basis() -> Basis:
	if _camera == null:
		return Basis.IDENTITY
	var x = _camera.global_basis.x.normalized()
	return Basis(x, Vector3.UP, x.cross(Vector3.UP).normalized())


func _vertical_basis(angle: float) -> Basis:
	return Basis(Vector3.UP, angle)


func _in_view(pos: Vector2, radius: float) -> bool:
	if _camera == null:
		return true
	var point = _point(pos, 0.7)
	if _camera.is_position_behind(point):
		return false
	var viewport = _camera.get_viewport()
	var rect = Rect2(Vector2.ZERO, viewport.get_visible_rect().size)
	var p = _camera.unproject_position(point)
	var margin = p.distance_to(_camera.unproject_position(point + Vector3(radius, 0, 0))) + 36.0
	return rect.grow(margin).has_point(p)


func _note(kind: String):
	_coverage[kind] = int(_coverage.get(kind, 0)) + 1


func _point(pos: Vector2, height: float) -> Vector3:
	return Vector3(pos.x, height, -pos.y)


func _visible_alpha_rect(image: Image) -> Rect2i:
	var minimum = image.get_size()
	var maximum = Vector2i(-1, -1)
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.035:
				minimum = minimum.min(Vector2i(x, y))
				maximum = maximum.max(Vector2i(x, y))
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE) if maximum.x >= 0 else Rect2i()
