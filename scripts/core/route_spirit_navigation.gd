extends RefCounted
## Visibility graph over authored rectangular obstacles. Pets have no collision
## body; this path only prevents their own pursuit from crossing solid walls.

func path(run, origin: Vector2, goal: Vector2, radius: float, margin: float) -> Array:
	if not run._body_clear(goal, radius): return []
	if _clear(run, origin, goal, radius): return [goal]
	var nodes: Array = [origin, goal]
	for block in run.blocks:
		var half: Vector2 = block.size * 0.5 + Vector2.ONE * (radius + margin)
		for offset in [Vector2(-half.x, -half.y), Vector2(-half.x, half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y)]:
			var point: Vector2 = block.center + offset
			if run._body_clear(point, radius): nodes.append(point)
	var distances: Array = []
	var previous: Array = []
	var visited: Dictionary = {}
	for _index in nodes.size():
		distances.append(INF)
		previous.append(-1)
	distances[0] = 0.0
	for _step in nodes.size():
		var current: int = -1
		for index in nodes.size():
			if visited.has(index): continue
			if current < 0 or float(distances[index]) < float(distances[current]): current = index
		if current < 0 or float(distances[current]) == INF: break
		if current == 1: break
		visited[current] = true
		for index in nodes.size():
			if visited.has(index) or index == current or not _clear(run, nodes[current], nodes[index], radius): continue
			var distance: float = float(distances[current]) + nodes[current].distance_to(nodes[index])
			if distance < float(distances[index]) - 0.000001:
				distances[index] = distance
				previous[index] = current
	if float(distances[1]) == INF: return []
	var result: Array = []
	var cursor: int = 1
	while cursor > 0:
		result.push_front(nodes[cursor])
		cursor = int(previous[cursor])
	return result

func _clear(run, origin: Vector2, goal: Vector2, radius: float) -> bool:
	return run._inside_floor(goal, radius) and run._first_block_contact(origin, goal, radius) == INF
