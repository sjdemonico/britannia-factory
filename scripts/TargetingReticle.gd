class_name TargetingReticle
extends Node2D

var _cursor_color: Color = Color(1.0, 0.5, 0.0, 0.9)
var _ae_fill_color: Color = Color(1.0, 0.2, 0.2, 0.35)

var current_tile: Vector2i = Vector2i.ZERO
var ae_tiles: Array[Vector2i] = []
var _active: bool = false
var _mouse_tracking: bool = false
var _origin_tile: Vector2i = Vector2i.ZERO
var _valid_range: int = 0

func _ready() -> void:
	_cursor_color = GameManager.reticle_cursor_color
	_ae_fill_color = GameManager.reticle_ae_fill_color

func activate(origin_tile: Vector2i, valid_range: int = 0) -> void:
	current_tile = origin_tile
	_origin_tile = origin_tile
	_valid_range = valid_range
	_mouse_tracking = true
	ae_tiles = []
	_active = true
	queue_redraw()

func deactivate() -> void:
	_active = false
	_mouse_tracking = false
	ae_tiles = []
	queue_redraw()

func move_to(tile: Vector2i) -> void:
	current_tile = tile
	queue_redraw()

func set_ae_tiles(tiles: Array[Vector2i]) -> void:
	ae_tiles = tiles.duplicate()
	queue_redraw()

func _process(_delta: float) -> void:
	if not _mouse_tracking or not _active:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var mouse_pos: Vector2 = vp.get_mouse_position()
	var world_pos: Vector2 = vp.canvas_transform.affine_inverse() * mouse_pos
	var tile := Vector2i(floori(world_pos.x / Constants.TILE_SIZE), floori(world_pos.y / Constants.TILE_SIZE))
	if tile != current_tile:
		move_to(tile)

# Returns true if the click should proceed to confirm (in range), false if rejected.
func _on_map_clicked_during_targeting(tile: Vector2i) -> bool:
	if not _active:
		return false
	if _valid_range > 0:
		var dist := maxi(absi(tile.x - _origin_tile.x), absi(tile.y - _origin_tile.y))
		if dist > _valid_range:
			MessageLog.post(MessageRegistry.get_message("spell_target_out_of_range"))
			return false
	move_to(tile)
	return true

func _draw() -> void:
	if not _active:
		return
	var half: float = float(Constants.TILE_SIZE) * 0.5
	var size: Vector2 = Vector2(float(Constants.TILE_SIZE), float(Constants.TILE_SIZE))
	for tile in ae_tiles:
		if tile == current_tile:
			continue
		var tpos: Vector2 = Constants.tile_to_world(tile)
		draw_rect(Rect2(tpos - Vector2(half, half), size), _ae_fill_color, true)
	var rpos: Vector2 = Constants.tile_to_world(current_tile)
	draw_rect(Rect2(rpos - Vector2(half, half), size), _cursor_color, false, 2.0)
