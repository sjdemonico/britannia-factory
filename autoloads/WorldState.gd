extends Node

var tile_occupants: Dictionary = {}
var flags: Dictionary = {}
var object_tiles: Dictionary = {}  # Vector2i -> Array[String] (object_ids, index 0 = bottom)
var open_containers: Dictionary = {}  # Vector2i -> true

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

func open_container(tile: Vector2i) -> void:
	open_containers[tile] = true

func close_container(tile: Vector2i) -> void:
	open_containers.erase(tile)

func is_container_open(tile: Vector2i) -> bool:
	return open_containers.has(tile)

func is_tile_occupied_by_npc(tile: Vector2i) -> bool:
	if not tile_occupants.has(tile):
		return false
	var occ: Dictionary = tile_occupants[tile]
	if occ.get("type") != "npc":
		return false
	var node = occ.get("node")
	if node != null and not is_instance_valid(node):
		tile_occupants.erase(tile)
		return false
	return true

func get_npc_at_tile(tile: Vector2i):
	if not tile_occupants.has(tile):
		return null
	var occ: Dictionary = tile_occupants[tile]
	if occ.get("type") != "npc":
		return null
	var node = occ.get("node")
	if node != null and not is_instance_valid(node):
		tile_occupants.erase(tile)
		return null
	return node

func clear_all_occupants() -> void:
	tile_occupants.clear()

func clear_all_objects() -> void:
	object_tiles.clear()
	open_containers.clear()
