class_name TileRegistry
extends RefCounted

var _tiles: Dictionary = {}

func load_from_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("TileRegistry: cannot open: " + path)
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("TileRegistry: JSON parse error in " + path + ": " + json.get_error_message())
		file.close()
		return false
	file.close()
	var data: Dictionary = json.get_data()
	_tiles.clear()
	for entry in data.get("tiles", []):
		var id: String = str(entry.get("id", ""))
		if id.is_empty():
			push_error("TileRegistry: tile entry missing 'id', skipping")
			continue
		var passable = entry.get("passable")
		if passable == null:
			push_error("TileRegistry: tile '" + id + "' missing 'passable', skipping")
			continue
		var fail_chance = entry.get("move_fail_chance")
		if fail_chance == null:
			push_error("TileRegistry: tile '" + id + "' missing 'move_fail_chance', skipping")
			continue
		var transparent = entry.get("transparent", true)
		_tiles[id] = { "passable": bool(passable), "transparent": bool(transparent), "move_fail_chance": float(fail_chance) }
	return true

func get_tile(tile_id: String) -> Dictionary:
	return _tiles.get(tile_id, {})

func has_tile(tile_id: String) -> bool:
	return _tiles.has(tile_id)

func is_passable(tile_id: String) -> bool:
	return _tiles.get(tile_id, {}).get("passable", false)

func is_transparent(tile_id: String) -> bool:
	return bool(_tiles.get(tile_id, {}).get("transparent", true))

func get_move_fail_chance(tile_id: String) -> float:
	return float(_tiles.get(tile_id, {}).get("move_fail_chance", 0.0))
