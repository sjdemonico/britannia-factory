extends Node2D

const WORLD_TILES_WIDE: int = 40
const WORLD_TILES_TALL: int = 30

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var player: CharacterBody2D = $Actors/Player
@onready var waypoint_manager: WaypointManager = $WaypointManager

func _ready() -> void:
	_setup_tileset()
	_paint_map()
	_register_waypoints()
	_spawn_test_items.call_deferred()
	var cam: Camera2D = player.get_node("Camera2D")
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = WORLD_TILES_WIDE * Constants.TILE_SIZE
	cam.limit_bottom = WORLD_TILES_TALL * Constants.TILE_SIZE

func _spawn_test_items() -> void:
	GameManager.spawn_object("sword_iron",     Vector2i(8,  3))
	GameManager.spawn_object("shield_wooden",  Vector2i(9,  3))
	GameManager.spawn_object("helmet_leather", Vector2i(10, 3))
	GameManager.spawn_object("ring_silver",    Vector2i(11, 3))
	GameManager.spawn_object("ring_gold",      Vector2i(8,  4))
	GameManager.spawn_or_merge("boots_leather", Vector2i(9, 4), 3)
	GameManager.spawn_object("sword_twohanded", Vector2i(11, 4))

func _register_waypoints() -> void:
	waypoint_manager.register_waypoint("innkeep_counter", Vector2i(7, 5))
	waypoint_manager.register_waypoint("common_table",    Vector2i(9, 5))
	waypoint_manager.register_waypoint("innkeep_bed",     Vector2i(7, 9))
	waypoint_manager.register_waypoint("guard_post",      Vector2i(4, 3))

func _setup_tileset() -> void:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(Constants.TILE_SIZE, Constants.TILE_SIZE)
	tile_set.add_physics_layer()
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(0, "look_description")
	tile_set.set_custom_data_layer_type(0, TYPE_STRING)

	var source := TileSetAtlasSource.new()
	source.texture = load("res://assets/tilesets/wilderness.png")
	source.texture_region_size = Vector2i(Constants.TILE_SIZE, Constants.TILE_SIZE)

	source.create_tile(Vector2i(0, 0))
	source.create_tile(Vector2i(1, 0))

	tile_set.add_source(source, 0)

	var grass_data: TileData = source.get_tile_data(Vector2i(0, 0), 0)
	grass_data.set_custom_data_by_layer_id(0, "You see a grassy field.")

	var wall_data: TileData = source.get_tile_data(Vector2i(1, 0), 0)
	wall_data.add_collision_polygon(0)
	wall_data.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-16, -16), Vector2(16, -16),
		Vector2(16, 16), Vector2(-16, 16)
	]))
	wall_data.set_custom_data_by_layer_id(0, "You see a stone wall.")

	terrain_layer.tile_set = tile_set

func _paint_map() -> void:
	for y in range(WORLD_TILES_TALL):
		for x in range(WORLD_TILES_WIDE):
			var is_border := (x == 0 or y == 0 or x == WORLD_TILES_WIDE - 1 or y == WORLD_TILES_TALL - 1)
			var atlas_coords := Vector2i(1, 0) if is_border else Vector2i(0, 0)
			terrain_layer.set_cell(Vector2i(x, y), 0, atlas_coords)
