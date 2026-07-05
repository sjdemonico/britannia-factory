extends Node2D

var WORLD_TILES_WIDE: int = 30
var WORLD_TILES_TALL: int = 25

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var player: CharacterBody2D = $Actors/Player

func _ready() -> void:
	var rc: Dictionary = GameManager.get_region_config("town")
	WORLD_TILES_WIDE = int(rc.get("width_tiles", WORLD_TILES_WIDE))
	WORLD_TILES_TALL = int(rc.get("height_tiles", WORLD_TILES_TALL))
	_setup_tileset()
	_paint_map()
	var cam: Camera2D = player.get_node("Camera2D")
	Constants.apply_camera_limits(cam, WORLD_TILES_WIDE, WORLD_TILES_TALL)
	GameManager.load_region("town")

func _setup_tileset() -> void:
	Constants.setup_tileset_from_atlas(terrain_layer, GameManager.tile_registry)

func _paint_map() -> void:
	Constants.paint_bordered_map(terrain_layer, WORLD_TILES_WIDE, WORLD_TILES_TALL, Vector2i(1, 0), Vector2i(0, 0))
	Constants.paint_rect(terrain_layer, 12, 1, 18, 24, Vector2i(2, 0))  # central dirt road
