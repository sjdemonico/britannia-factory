extends Node

var tile_occupants: Dictionary = {}
var flags: Dictionary = {}
var object_tiles: Dictionary = {}  # Vector2i -> Array[String] (object_ids, index 0 = bottom)
var open_containers: Dictionary = {}  # Vector2i -> true
var _npc_by_tile: Dictionary = {}  # Vector2i -> NPC node

func set_occupant(tile: Vector2i, data: Dictionary) -> void:
	tile_occupants[tile] = data

func clear_occupant(tile: Vector2i) -> void:
	tile_occupants.erase(tile)

func get_occupant(tile: Vector2i) -> Dictionary:
	return tile_occupants.get(tile, {})

func is_tile_occupied(tile: Vector2i) -> bool:
	return tile_occupants.has(tile)

func mark_object_tile(tile: Vector2i, object_id: String) -> void:
	if not object_tiles.has(tile):
		object_tiles[tile] = []
	object_tiles[tile].append(object_id)

func clear_object_from_tile(tile: Vector2i, object_id: String) -> void:
	if not object_tiles.has(tile):
		return
	var arr: Array = object_tiles[tile]
	var idx := arr.rfind(object_id)
	if idx != -1:
		arr.remove_at(idx)
	if arr.is_empty():
		object_tiles.erase(tile)

func get_objects_at(tile: Vector2i) -> Array:
	return object_tiles.get(tile, []).duplicate()

func has_object(tile: Vector2i) -> bool:
	return object_tiles.has(tile)

func is_tile_blocked_by_object(tile: Vector2i) -> bool:
	for object_id in object_tiles.get(tile, []):
		var data := PlayerInventory.get_object_data(object_id)
		if not data.get("passable", true):
			return true
	return false

func open_container(tile: Vector2i) -> void:
	open_containers[tile] = true

func close_container(tile: Vector2i) -> void:
	open_containers.erase(tile)

func is_container_open(tile: Vector2i) -> bool:
	return open_containers.has(tile)

func clear_item_tile(tile: Vector2i) -> void:
	object_tiles.erase(tile)

func register_npc_tile(tile: Vector2i, npc) -> void:
	_npc_by_tile[tile] = npc

func unregister_npc_tile(tile: Vector2i) -> void:
	_npc_by_tile.erase(tile)

func is_tile_occupied_by_npc(tile: Vector2i) -> bool:
	return _npc_by_tile.has(tile)

func get_npc_at_tile(tile: Vector2i):
	return _npc_by_tile.get(tile, null)

func clear_npc_registry() -> void:
	for tile in _npc_by_tile:
		tile_occupants.erase(tile)
	_npc_by_tile.clear()
