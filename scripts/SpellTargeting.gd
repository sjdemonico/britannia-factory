class_name SpellTargeting
extends RefCounted

# Computes the area-of-effect tiles for a spell given its ae_shape data.
# caster_tile: origin of the caster. target_tile: where the player aimed.
static func compute_ae_tiles(
		spell: Dictionary,
		caster_tile: Vector2i,
		target_tile: Vector2i) -> Array[Vector2i]:
	var ae_shape: String = str(spell.get("ae_shape", "single"))
	match ae_shape:
		"circle":
			var radius: int = int(spell.get("radius", 1))
			var tiles := AEShapeCalculator.get_circle_tiles(target_tile, radius)
			return AEShapeCalculator.filter_by_los(tiles, caster_tile)
		"line":
			var half_width: int = int(spell.get("half_width", 0))
			return AEShapeCalculator.get_line_tiles(caster_tile, target_tile, half_width)
		"cone":
			var length: int = int(spell.get("cone_length", 3))
			var dir := Vector2i(sign(target_tile.x - caster_tile.x), sign(target_tile.y - caster_tile.y))
			if dir == Vector2i.ZERO:
				dir = Vector2i(0, -1)
			var tiles := AEShapeCalculator.get_cone_tiles(caster_tile, dir, length)
			return AEShapeCalculator.filter_by_los(tiles, caster_tile)
		_:  # "single" or unrecognised
			return [target_tile]

# Returns the targeting range from spell data (0 = unlimited / self).
static func get_spell_range(spell: Dictionary) -> int:
	return int(spell.get("range", 0))
