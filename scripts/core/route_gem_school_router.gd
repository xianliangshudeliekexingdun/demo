extends RefCounted
## Keeps one independent school state machine per equipped keystone. Call sites
## stay unchanged: each school method forwards to the core that owns it.
const Schools = preload("res://scripts/core/route_gem_schools.gd")
const CORE_IDS = ["lightning", "wind", "earth", "spirit"]
var sets: Dictionary = {}

func configure(cores: Array, specs: Dictionary) -> void:
	sets.clear()
	for id in CORE_IDS:
		if id not in cores: continue
		var school = Schools.new()
		school.configure(id, specs.get(id, {}))
		sets[id] = school

func clear() -> void:
	for id in sets: sets[id].clear()

func advance(run, dt: float, clock: float) -> void:
	for id in sets: sets[id].advance(run, dt, clock)

func snapshot() -> Dictionary:
	var result: Dictionary = {}
	for id in sets: result[id] = sets[id].snapshot()
	return result

func active(ids: Array) -> Array:
	var result: Array = []
	for id in ids:
		if sets.has(id): result.append(sets[id])
	return result

func lightning_cast(run, spell: Dictionary, target: Dictionary, context: Dictionary) -> void:
	if sets.has("lightning"): sets["lightning"].lightning_cast(run, spell, target, context)

func lightning_hit(run, actor: Dictionary, actual: float, context: Dictionary, pre_conductive: bool) -> void:
	if sets.has("lightning"): sets["lightning"].lightning_hit(run, actor, actual, context, pre_conductive)

func wind_motion(run, length: float) -> void:
	if sets.has("wind"): sets["wind"].wind_motion(run, length)

func wind_cast(run, id: String, level: Dictionary, context: Dictionary) -> void:
	if sets.has("wind"): sets["wind"].wind_cast(run, id, level, context)

func earth_tick(run, dt: float) -> void:
	if sets.has("earth"): sets["earth"].earth_tick(run, dt)

func earth_source_removed(source_id: int) -> void:
	if sets.has("earth"): sets["earth"].earth_source_removed(source_id)

func spirit_presence(run) -> void:
	if sets.has("spirit"): sets["spirit"].spirit_presence(run)

func spirit_action(run, family: String, contacts: Array) -> void:
	if sets.has("spirit"): sets["spirit"].spirit_action(run, family, contacts)
