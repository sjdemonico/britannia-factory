class_name LineOfSight
extends RefCounted

static func has_line_of_sight(from_tile: Vector2i, to_tile: Vector2i, tilemap: TileMapLayer) -> bool:
	var intermediate := _bresenham_intermediate(from_tile, to_tile)
	for tile in intermediate:
		for object_id in WorldState.get_objects_at(tile):
			var data := PlayerInventory.get_object_data(object_id)
			if not data.get("transparent", true):
				return false
		if not _tile_type_transparent(tilemap, tile):
			return false
	return true

static func _tile_type_transparent(tilemap: TileMapLayer, tile: Vector2i) -> bool:
	if tilemap == null or tilemap.tile_set == null:
		return true
	var tile_data := tilemap.get_cell_tile_data(tile)
	if tile_data == null:
		return true
	var tile_set := tilemap.tile_set
	for i in range(tile_set.get_custom_data_layers_count()):
		if tile_set.get_custom_data_layer_name(i) == Constants.TILE_TYPE_CUSTOM_DATA:
			var type_id: String = tile_data.get_custom_data_by_layer_id(i)
			if GameManager.tile_registry != null:
				return GameManager.tile_registry.is_transparent(type_id)
	return true

static func _bresenham_intermediate(from_tile: Vector2i, to_tile: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var x0: int = from_tile.x
	var y0: int = from_tile.y
	var x1: int = to_tile.x
	var y1: int = to_tile.y
	var dx: int = abs(x1 - x0)
	var dy: int = abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	while true:
		var cur := Vector2i(x0, y0)
		if cur != from_tile and cur != to_tile:
			result.append(cur)
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
	return result
