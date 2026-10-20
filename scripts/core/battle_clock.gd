extends RefCounted
const STEP = 1.0 / 120.0
var remainder = 0.0
var suspended = true

func suspend(value: bool):
	suspended = value
	remainder = 0.0

func advance(delta: float, battle, direction: Vector2):
	if suspended or battle.result != "playing": return
	# Discard long stalls rather than fast-forwarding a battle after a blocked window.
	remainder += minf(delta, 0.1)
	while remainder + 0.000000001 >= STEP and battle.result == "playing":
		battle.step(STEP, direction)
		remainder -= STEP
