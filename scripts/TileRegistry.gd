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
		var atlas_x: int = int(entry.get("atlas_x", 0))
		var atlas_y: int = int(entry.get("atlas_y", 0))
		var footstep_snd = entry.get("footstep_sound", null)
		var hazard_snd = entry.get("hazard_sound", null)
		var ambient_snd = entry.get("ambient_sound", null)
		_tiles[id] = {
			"passable": bool(passable),
			"transparent": bool(transparent),
			"move_fail_chance": float(fail_chance),
			"hazards": hazards if hazards is Array else [],
			"look_description": str(look_desc),
			"atlas_x": atlas_x,
			"atlas_y": atlas_y,
			"footstep_sound": str(footstep_snd) if footstep_snd is String else "",
			"hazard_sound": str(hazard_snd) if hazard_snd is String else "",
			"ambient_sound": str(ambient_snd) if ambient_snd is String else ""
		}
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

func get_atlas_coords(tile_id: String) -> Vector2i:
	var t: Dictionary = _tiles.get(tile_id, {})
	return Vector2i(int(t.get("atlas_x", 0)), int(t.get("atlas_y", 0)))

func get_all_tile_ids() -> Array:
	return _tiles.keys()
