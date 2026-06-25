class_name TileRegistry
extends RefCounted

var _tiles: Dictionary = {}

func load_from_file(path: String) -> bool:
	var data: Dictionary = Constants.load_json(path)
	if data.is_empty():
		return false
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
		var hazards = entry.get("hazards", [])
		var look_desc = entry.get("look_description", "")
		_tiles[id] = { "passable": bool(passable), "transparent": bool(transparent), "move_fail_chance": float(fail_chance), "hazards": hazards if hazards is Array else [], "look_description": str(look_desc) }
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

func get_hazards(tile_id: String) -> Array:
	var h = _tiles.get(tile_id, {}).get("hazards", [])
	return h if h is Array else []

func get_look_description(tile_id: String) -> String:
	return str(_tiles.get(tile_id, {}).get("look_description", ""))
