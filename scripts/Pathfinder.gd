class_name Pathfinder

const DIRECTIONS: Array = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1,  0),                  Vector2i(1,  0),
	Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1)
]

static func heuristic(a: Vector2i, b: Vector2i) -> int:
	return maxi(abs(a.x - b.x), abs(a.y - b.y))

static func find_path(
		start: Vector2i,
		goal: Vector2i,
		passability_callable: Callable,
		max_length: int) -> Array[Vector2i]:
	if start == goal:
		return []

	var open_set: Array = []           # [f, Vector2i]
	var closed_set: Dictionary = {}    # Vector2i -> true
	var came_from: Dictionary = {}     # Vector2i -> Vector2i
	var g_score: Dictionary = {}       # Vector2i -> int

	g_score[start] = 0
	_insert_sorted(open_set, [heuristic(start, goal), start])

	while not open_set.is_empty():
		var entry: Array = open_set[0]
		open_set.remove_at(0)
		var current: Vector2i = entry[1]

		if closed_set.has(current):
			continue
		closed_set[current] = true

		if current == goal:
			return reconstruct_path(came_from, goal)

		for dir: Vector2i in DIRECTIONS:
			var neighbor: Vector2i = current + dir
			if closed_set.has(neighbor):
				continue
			if not passability_callable.call(neighbor):
				continue
			var tentative_g: int = g_score[current] + 1
			if max_length > 0 and tentative_g > max_length:
				continue
			if g_score.has(neighbor) and tentative_g >= g_score[neighbor]:
				continue
			came_from[neighbor] = current
			g_score[neighbor] = tentative_g
			_insert_sorted(open_set, [tentative_g + heuristic(neighbor, goal), neighbor])

	return []

static func reconstruct_path(came_from: Dictionary, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current: Vector2i = goal
	while came_from.has(current):
		path.append(current)
		current = came_from[current]
	path.reverse()
	return path

static func _insert_sorted(arr: Array, entry: Array) -> void:
	var f: int = entry[0]
	for i: int in range(arr.size()):
		if arr[i][0] > f:
			arr.insert(i, entry)
			return
	arr.append(entry)
