extends SceneTree
## Read-only presentation records for floating damage. No rendering, screenshot,
## gameplay, natural route or performance measurement is performed.
const View = preload("res://scripts/presentation/first_room_view.gd")
var checks: int = 0
var failures: Array = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("Damage numbers presentation: " + label)


func run() -> void:
	var view = View.new()
	var source := {"time": 10.0, "effects": [
		{"seq": 1, "kind": "damage", "actor_id": 4, "pos": Vector2(1.0, 2.0), "amount": 37.0, "spell_id": "F01"},
		{"seq": 2, "kind": "damage", "actor_id": 4, "pos": Vector2(1.0, 2.0), "amount": 41.0, "spell_id": "F01"},
	]}
	var before: Dictionary = source.duplicate(true)
	view._state = source
	view._consume_visual_events(10.0)
	var visible_state: Dictionary = view.get_damage_number_debug_state()
	check(int(visible_state.count) == 2, "two actual damage events create two independent records")
	check(visible_state.records.size() == 2 and not visible_state.records[0].has("group"), "records never form or reuse a merge group")
	check(is_equal_approx(float(visible_state.records[0].amount), 37.0) and is_equal_approx(float(visible_state.records[1].amount), 41.0), "independent records retain the exact event amounts")
	check(int(visible_state.records[0].seq) == 1 and int(visible_state.records[1].seq) == 2, "records retain their distinct core event sequence")
	check(is_equal_approx(float(visible_state.lifetime), 0.72) and int(visible_state.limit) == 20, "number lifetime and global cap remain unchanged")
	check(source == before, "presentation never changes the core snapshot")
	view.set_visual_options({"damage_numbers": false})
	var disabled_state: Dictionary = view.get_damage_number_debug_state()
	view.set_visual_options({"damage_numbers": true})
	var enabled_state: Dictionary = view.get_damage_number_debug_state()
	check(not bool(disabled_state.enabled) and bool(enabled_state.enabled) and int(enabled_state.count) == 2, "damage-number switch toggles visibility without changing records")
	view._consume_visual_events(10.0)
	check(int(view.get_damage_number_debug_state().count) == 2, "re-consuming the same sequence does not draw an event twice")
	view._prune_damage_numbers(10.719)
	check(int(view.get_damage_number_debug_state().count) == 2, "both independent records remain inside the unchanged lifetime")
	view._prune_damage_numbers(10.721)
	check(int(view.get_damage_number_debug_state().count) == 0, "records expire at the unchanged 0.72 second lifetime")

	view._damage_numbers.clear()
	view._last_visual_seq = -1
	var effects: Array = []
	for index in range(21):
		effects.append({"seq": 10 + index, "kind": "damage", "actor_id": 8, "pos": Vector2.ZERO, "amount": float(index + 1), "spell_id": "F03"})
	view._state = {"time": 20.0, "effects": effects}
	view._consume_visual_events(20.0)
	var capped: Dictionary = view.get_damage_number_debug_state()
	check(int(capped.count) == 20, "independent records still obey the existing 20-number cap")
	check(is_equal_approx(float(capped.records[0].amount), 2.0) and is_equal_approx(float(capped.records[-1].amount), 21.0), "cap evicts only the oldest independent record")
	view.free()
	print("DAMAGE NUMBERS PRESENTATION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
