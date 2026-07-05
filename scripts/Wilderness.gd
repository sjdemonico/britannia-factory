extends Node2D

var WORLD_TILES_WIDE: int = 40
var WORLD_TILES_TALL: int = 30

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var player: CharacterBody2D = $Actors/Player

func _ready() -> void:
	var rc: Dictionary = GameManager.get_region_config("wilderness")
	WORLD_TILES_WIDE = int(rc.get("width_tiles", WORLD_TILES_WIDE))
	WORLD_TILES_TALL = int(rc.get("height_tiles", WORLD_TILES_TALL))
	_setup_tileset()
	_paint_map()
	var cam: Camera2D = player.get_node("Camera2D")
	Constants.apply_camera_limits(cam, WORLD_TILES_WIDE, WORLD_TILES_TALL)
	GameManager.load_region("wilderness")

func _setup_tileset() -> void:
	Constants.setup_tileset_from_atlas(terrain_layer, GameManager.tile_registry)

func _paint_map() -> void:
	Constants.paint_bordered_map(terrain_layer, WORLD_TILES_WIDE, WORLD_TILES_TALL, Vector2i(1, 0), Vector2i(0, 0))
	Constants.paint_rect(terrain_layer, 18, 3,  22, 7,  Vector2i(2, 0))  # dirt
	Constants.paint_rect(terrain_layer, 26, 4,  32, 10, Vector2i(3, 0))  # water
	Constants.paint_rect(terrain_layer, 4,  19, 9,  24, Vector2i(4, 0))  # swamp
	Constants.paint_rect(terrain_layer, 16, 18, 22, 24, Vector2i(5, 0))  # forest
	Constants.paint_rect(terrain_layer, 27, 15, 33, 21, Vector2i(6, 0))  # hill
