class_name AEShapeCalculator
extends RefCounted

# Returns all tiles within Chebyshev distance <= radius of center.
static func get_circle_tiles(center: Vector2i, radius: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if maxi(abs(dx), abs(dy)) <= radius:
				tiles.append(center + Vector2i(dx, dy))
	return tiles

# Returns all tiles along the Bresenham line from→to, expanded half_width
# tiles perpendicularly on each side.
static func get_line_tiles(from: Vector2i, to: Vector2i, half_width: int = 0) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var seen: Dictionary = {}
	var dx: int = abs(to.x - from.x)
	var dy: int = abs(to.y - from.y)
	var sx: int = 1 if from.x < to.x else -1
	var sy: int = 1 if from.y < to.y else -1
	var x: int = from.x
	var y: int = from.y
	var err: int = dx - dy
	# Perpendicular to (sx, sy): rotate 90°.
	var perp_x: int = -sy
	var perp_y: int = sx
	while true:
		for w in range(-half_width, half_width + 1):
			var tile := Vector2i(x + perp_x * w, y + perp_y * w)
			if not seen.has(tile):
				seen[tile] = true
				tiles.append(tile)
		if x == to.x and y == to.y:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
	return tiles

# Returns a cone of tiles starting from origin in direction, widening 2N-1
# tiles at distance N (half_width = N-1 on each perpendicular side).
static func get_cone_tiles(origin: Vector2i, direction: Vector2i, length: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var seen: Dictionary = {}
	# Perpendicular to direction: rotate 90°.
	var perp := Vector2i(-direction.y, direction.x)
	for dist in range(1, length + 1):
		var center := origin + direction * dist
		var hw: int = dist - 1
		for w in range(-hw, hw + 1):
			var tile := center + perp * w
			if not seen.has(tile):
				seen[tile] = true
				tiles.append(tile)
	return tiles

# Removes tiles not reachable with line-of-sight from origin. Passes origin through unconditionally.
static func filter_by_los(tiles: Array[Vector2i], origin: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for tile in tiles:
		if tile == origin or LineOfSight.has_line_of_sight(origin, tile):
			result.append(tile)
	return result
