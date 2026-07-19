class_name DarknessOverlay
extends Node2D

var _player_vision_radius: int = 27
var _fixed_sources: Array = []
var _needs_redraw: bool = true
var _last_player_tile: Vector2i = Vector2i(-999, -999)

func _ready() -> void:
	z_index = 100
	_player_vision_radius = PlayerStats.get_effective_value("vision_radius")
	PlayerStats.stat_changed.connect(_on_stat_changed)
	GameManager.region_loaded.connect(_on_region_loaded)
	GameTime.tick_advanced.connect(_on_tick_advanced)

func _exit_tree() -> void:
	if PlayerStats.stat_changed.is_connected(_on_stat_changed):
		PlayerStats.stat_changed.disconnect(_on_stat_changed)
	if GameManager.region_loaded.is_connected(_on_region_loaded):
		GameManager.region_loaded.disconnect(_on_region_loaded)
	if GameTime.tick_advanced.is_connected(_on_tick_advanced):
		GameTime.tick_advanced.disconnect(_on_tick_advanced)

func _on_tick_advanced(_total_ticks: int) -> void:
	var sources := GameManager.get_fixed_light_sources()
	if sources != _fixed_sources:
		_fixed_sources = sources
		_needs_redraw = true

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

func is_tile_visible(tile: Vector2i) -> bool:
	var player_tile: Vector2i = GameManager.player_tile
	var draw_radius: float = maxf(float(_player_vision_radius), 3.0)
	var chebyshev: int = maxi(absi(tile.x - player_tile.x), absi(tile.y - player_tile.y))
	if float(chebyshev) <= draw_radius and LineOfSight.has_line_of_sight(player_tile, tile):
		return true
	for source in _fixed_sources:
		var s_tile: Vector2i = source.get("tile", Vector2i.ZERO)
		var s_radius: int = source.get("radius", 0)
		var s_chebyshev: int = maxi(absi(tile.x - s_tile.x), absi(tile.y - s_tile.y))
		if s_chebyshev <= s_radius and LineOfSight.has_line_of_sight(s_tile, tile):
			return true
	return false

func _opacity_at(dist: float, radius: float) -> float:
	var inner: float = maxf(0.0, radius - 1.0)
	if dist <= inner:
		return 0.0
	elif dist >= radius:
		return 1.0
	else:
		return (dist - inner) / (radius - inner)

func _draw() -> void:
	if GameManager.current_region == null:
		return
	var player_tile: Vector2i = GameManager.player_tile
	var vision_radius: int = _player_vision_radius
	var bounds: Rect2i = GameManager.get_region_bounds()
	if bounds.size == Vector2i.ZERO:
		return
	var draw_radius: float = maxf(float(vision_radius), 3.0)

	# Per-tile redraw with Chebyshev culling then Bresenham LOS.
	# Performance note: each in-radius tile makes one LOS raycast (~O(radius) steps).
	# Fixed sources each add another pass. Flag to profile if map size grows.
	for ty in range(bounds.position.y, bounds.end.y):
		for tx in range(bounds.position.x, bounds.end.x):
			var tile := Vector2i(tx, ty)
			var chebyshev: int = maxi(absi(tx - player_tile.x), absi(ty - player_tile.y))
			var best_opacity: float = 1.0
			var player_los: bool = float(chebyshev) <= draw_radius and LineOfSight.has_line_of_sight(player_tile, tile)
			if player_los:
				best_opacity = _opacity_at(float(chebyshev), draw_radius)

			for source in _fixed_sources:
				var s_tile: Vector2i = source.get("tile", Vector2i.ZERO)
				var s_radius: int = source.get("radius", 0)
				var s_chebyshev: int = maxi(absi(tx - s_tile.x), absi(ty - s_tile.y))
				if player_los and s_chebyshev <= s_radius and LineOfSight.has_line_of_sight(s_tile, tile):
					best_opacity = minf(best_opacity, _opacity_at(float(s_chebyshev), float(s_radius)))

			if best_opacity > 0.0:
				var dc := GameManager.darkness_color
				draw_rect(
					Rect2(float(tx) * Constants.TILE_SIZE, float(ty) * Constants.TILE_SIZE,
						float(Constants.TILE_SIZE), float(Constants.TILE_SIZE)),
					Color(dc.r, dc.g, dc.b, best_opacity)
				)
