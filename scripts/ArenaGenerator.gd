class_name ArenaGenerator
extends RefCounted

var _impassable_fallbacks: Dictionary = {}

func load_config() -> void:
	var file := FileAccess.open(Constants.COMBAT_CONFIG_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return
	file.close()
	var fb = json.get_data().get("impassable_tile_fallbacks")
	if fb is Dictionary:
		_impassable_fallbacks = fb

func generate(world_tile_type: String, width: int, height: int) -> Array:
	var grid: Array = []
	for y in range(height):
		var row: Array = []
		for x in range(width):
			row.append("grass")
		grid.append(row)

	var feature_type := _determine_feature(world_tile_type)
	if not feature_type.is_empty():
		var cluster_count := randi_range(3, 5)
		for _c in range(cluster_count):
			_place_cluster(grid, feature_type, width, height)

	_clear_spawn_strip(grid, "south", width, height)
	_clear_spawn_strip(grid, "north", width, height)
	_clear_spawn_strip(grid, "west",  width, height)
	_clear_spawn_strip(grid, "east",  width, height)
	return grid

func _determine_feature(world_tile_type: String) -> String:
	if world_tile_type.is_empty() or GameManager.tile_registry == null:
		return ""
	if not GameManager.tile_registry.is_passable(world_tile_type):
		return _impassable_fallbacks.get(world_tile_type, "hill")
	if GameManager.tile_registry.get_move_fail_chance(world_tile_type) > 0.0:
		return world_tile_type
	return ""

func _place_cluster(grid: Array, tile_type: String, width: int, height: int) -> void:
	var seed_x := randi_range(3, width - 4)
	var seed_y := randi_range(3, height - 4)
	var size := randi_range(4, 10)
	var frontier: Array = [Vector2i(seed_x, seed_y)]
	var visited: Dictionary = {}
	var placed := 0
	while not frontier.is_empty() and placed < size:
		var idx := randi() % frontier.size()
		var pos: Vector2i = frontier[idx]
		frontier.remove_at(idx)
		if visited.has(pos):
			continue
		visited[pos] = true
		var dist: int = abs(pos.x - seed_x) + abs(pos.y - seed_y)
		if randf() > 1.0 - float(dist) / float(size + 1):
			continue
		grid[pos.y][pos.x] = tile_type
		placed += 1
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var nx: int = pos.x + dx
				var ny: int = pos.y + dy
				if nx >= 0 and nx < width and ny >= 0 and ny < height:
					var nb := Vector2i(nx, ny)
					if not visited.has(nb):
						frontier.append(nb)

func _clear_spawn_strip(grid: Array, edge: String, width: int, height: int) -> void:
	match edge:
		"south":
			for x in range(11, 16):
				grid[height - 1][x] = "grass"
		"north":
			for x in range(11, 16):
				grid[0][x] = "grass"
		"west":
			for y in range(8, 13):
				grid[y][0] = "grass"
		"east":
			for y in range(8, 13):
				grid[y][width - 1] = "grass"
