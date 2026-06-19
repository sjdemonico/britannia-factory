class_name TargetingReticle
extends Node2D

const _CURSOR_COLOR: Color = Color(1.0, 0.5, 0.0, 0.9)
const _AE_FILL_COLOR: Color = Color(1.0, 0.2, 0.2, 0.35)

var current_tile: Vector2i = Vector2i.ZERO
var ae_tiles: Array[Vector2i] = []
var _active: bool = false

func activate(start_tile: Vector2i) -> void:
	current_tile = start_tile
	ae_tiles = []
	_active = true
	queue_redraw()

func deactivate() -> void:
	_active = false
	ae_tiles = []
	queue_redraw()

func move_to(tile: Vector2i) -> void:
	current_tile = tile
	queue_redraw()

func set_ae_tiles(tiles: Array[Vector2i]) -> void:
	ae_tiles = tiles.duplicate()
	queue_redraw()

func _draw() -> void:
	if not _active:
		return
	var half: float = float(Constants.TILE_SIZE) * 0.5
	var size: Vector2 = Vector2(float(Constants.TILE_SIZE), float(Constants.TILE_SIZE))
	for tile in ae_tiles:
		if tile == current_tile:
			continue
		var tpos: Vector2 = Constants.tile_to_world(tile)
		draw_rect(Rect2(tpos - Vector2(half, half), size), _AE_FILL_COLOR, true)
	var rpos: Vector2 = Constants.tile_to_world(current_tile)
	draw_rect(Rect2(rpos - Vector2(half, half), size), _CURSOR_COLOR, false, 2.0)
