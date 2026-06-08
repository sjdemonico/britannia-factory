extends Node2D

const WORLD_TILES_WIDE: int = 40
const WORLD_TILES_TALL: int = 30

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var player: CharacterBody2D = $Actors/Player

func _ready() -> void:
	_setup_tileset()
	_paint_map()
	var cam: Camera2D = player.get_node("Camera2D")
	Constants.apply_camera_limits(cam, WORLD_TILES_WIDE, WORLD_TILES_TALL)
	GameManager.load_region("wilderness")

func _setup_tileset() -> void:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(Constants.TILE_SIZE, Constants.TILE_SIZE)
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(0, Constants.LOOK_DESCRIPTION_LAYER)
	tile_set.set_custom_data_layer_type(0, TYPE_STRING)
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(1, Constants.TILE_TYPE_CUSTOM_DATA)
	tile_set.set_custom_data_layer_type(1, TYPE_STRING)

	var source := TileSetAtlasSource.new()
	source.texture = load("res://assets/tilesets/wilderness.png")
	source.texture_region_size = Vector2i(Constants.TILE_SIZE, Constants.TILE_SIZE)

	source.create_tile(Vector2i(0, 0))
	source.create_tile(Vector2i(1, 0))
	source.create_tile(Vector2i(2, 0))
	source.create_tile(Vector2i(3, 0))
	source.create_tile(Vector2i(4, 0))
	source.create_tile(Vector2i(5, 0))
	source.create_tile(Vector2i(6, 0))

	tile_set.add_source(source, 0)

	var grass_data: TileData = source.get_tile_data(Vector2i(0, 0), 0)
	grass_data.set_custom_data_by_layer_id(0, "You see a grassy field.")
	grass_data.set_custom_data_by_layer_id(1, "grass")

	var wall_data: TileData = source.get_tile_data(Vector2i(1, 0), 0)
	wall_data.set_custom_data_by_layer_id(0, "You see a stone wall.")
	wall_data.set_custom_data_by_layer_id(1, "mountain")

	var dirt_data: TileData = source.get_tile_data(Vector2i(2, 0), 0)
	dirt_data.set_custom_data_by_layer_id(0, "You see a patch of bare earth.")
	dirt_data.set_custom_data_by_layer_id(1, "dirt")

	var water_data: TileData = source.get_tile_data(Vector2i(3, 0), 0)
	water_data.set_custom_data_by_layer_id(0, "The water blocks your path.")
	water_data.set_custom_data_by_layer_id(1, "water")

	var swamp_data: TileData = source.get_tile_data(Vector2i(4, 0), 0)
	swamp_data.set_custom_data_by_layer_id(0, "You see dark, boggy ground.")
	swamp_data.set_custom_data_by_layer_id(1, "swamp")

	var forest_data: TileData = source.get_tile_data(Vector2i(5, 0), 0)
	forest_data.set_custom_data_by_layer_id(0, "Dense trees slow your passage.")
	forest_data.set_custom_data_by_layer_id(1, "forest")

	var hill_data: TileData = source.get_tile_data(Vector2i(6, 0), 0)
	hill_data.set_custom_data_by_layer_id(0, "The hillside is rough going.")
	hill_data.set_custom_data_by_layer_id(1, "hill")

	terrain_layer.tile_set = tile_set

func _paint_map() -> void:
	for y in range(WORLD_TILES_TALL):
		for x in range(WORLD_TILES_WIDE):
			var is_border := (x == 0 or y == 0 or x == WORLD_TILES_WIDE - 1 or y == WORLD_TILES_TALL - 1)
			var atlas_coords := Vector2i(1, 0) if is_border else Vector2i(0, 0)
			terrain_layer.set_cell(Vector2i(x, y), 0, atlas_coords)
	_paint_rect(18, 3,  22, 7,  Vector2i(2, 0))  # dirt
	_paint_rect(26, 4,  32, 10, Vector2i(3, 0))  # water
	_paint_rect(4,  19, 9,  24, Vector2i(4, 0))  # swamp
	_paint_rect(16, 18, 22, 24, Vector2i(5, 0))  # forest
	_paint_rect(27, 15, 33, 21, Vector2i(6, 0))  # hill

func _paint_rect(x0: int, y0: int, x1: int, y1: int, atlas_coords: Vector2i) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			terrain_layer.set_cell(Vector2i(x, y), 0, atlas_coords)
