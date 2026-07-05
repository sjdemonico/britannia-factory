class_name DirectionPromptOverlay
extends Node2D

var _active: bool = false
var _player_tile: Vector2i = Vector2i(-1, -1)

func show_prompt(player_tile: Vector2i) -> void:
	_active = true
	_player_tile = player_tile
	show()
	queue_redraw()

func hide_prompt() -> void:
	_active = false
	hide()

func _draw() -> void:
	if not _active or _player_tile == Vector2i(-1, -1):
		return
	var bounds: Rect2i = GameManager.get_region_bounds()
	var ts: float = float(Constants.TILE_SIZE)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var t := _player_tile + Vector2i(dx, dy)
			if bounds.size != Vector2i.ZERO and not bounds.has_point(t):
				continue
			draw_rect(Rect2(float(t.x) * ts, float(t.y) * ts, ts, ts), GameManager.direction_prompt_adjacent_color)
	var pt := _player_tile
	draw_rect(Rect2(float(pt.x) * ts, float(pt.y) * ts, ts, ts), GameManager.direction_prompt_player_color)
