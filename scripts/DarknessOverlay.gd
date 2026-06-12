class_name DarknessOverlay
extends Node2D

var _player_vision_radius: int = 27
var _max_vision_radius: int = 27
var _fixed_sources: Array = []
var _needs_redraw: bool = true
var _last_player_tile: Vector2i = Vector2i(-999, -999)

func _ready() -> void:
	z_index = 100
	_max_vision_radius = PlayerStats.stat_block.get_max("vision_radius")
	_player_vision_radius = PlayerStats.get_effective_value("vision_radius")
	PlayerStats.stat_block.stat_changed.connect(_on_stat_changed)
	GameManager.region_loaded.connect(_on_region_loaded)

func _on_stat_changed(stat_id: String, _old_val: int, new_val: int) -> void:
	if stat_id == "vision_radius":
		_player_vision_radius = new_val
		_needs_redraw = true

func _on_region_loaded() -> void:
	_fixed_sources = GameManager.get_fixed_light_sources()
	_needs_redraw = true

func _process(_delta: float) -> void:
	if GameManager.current_region == null:
		return
	var current_tile: Vector2i = GameManager.player_tile
	if current_tile != _last_player_tile:
		_last_player_tile = current_tile
		_needs_redraw = true
	if _needs_redraw:
		_needs_redraw = false
		queue_redraw()

func _opacity_at(dist: float, radius: float) -> float:
	var inner: float = maxf(0.0, radius - 2.0)
	if dist <= inner:
		return 0.0
	elif dist >= radius:
		return 1.0
	else:
		return (dist - inner) / (radius - inner)

func _draw() -> void:
	if GameManager.current_region == null:
		return
	if _player_vision_radius >= _max_vision_radius:
		return
	var player_tile: Vector2i = GameManager.player_tile
	var vision_radius: int = _player_vision_radius
	var bounds: Rect2i = GameManager.get_region_bounds()
	if bounds.size == Vector2i.ZERO:
		return

	for ty in range(bounds.position.y, bounds.end.y):
		for tx in range(bounds.position.x, bounds.end.x):
			var tile := Vector2i(tx, ty)
			var player_dist: float = Vector2(tile - player_tile).length()
			var draw_radius: float = maxf(float(vision_radius), 3.0)
			var best_opacity: float = _opacity_at(player_dist, draw_radius)

			for source in _fixed_sources:
				var s_tile: Vector2i = source.get("tile", Vector2i.ZERO)
				var s_radius: int = source.get("radius", 0)
				var s_dist: float = Vector2(tile - s_tile).length()
				best_opacity = minf(best_opacity, _opacity_at(s_dist, float(s_radius)))

			if best_opacity > 0.0:
				var rect := Rect2(
					float(tx) * Constants.TILE_SIZE,
					float(ty) * Constants.TILE_SIZE,
					float(Constants.TILE_SIZE),
					float(Constants.TILE_SIZE)
				)
				draw_rect(rect, Color(0.0, 0.0, 0.0, best_opacity))
