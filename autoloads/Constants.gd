extends Node

const TILE_SIZE: int = 32
const MAP_TILES_WIDE: int = 27
const MAP_TILES_TALL: int = 21
const MAP_PIXEL_WIDTH: int = 864
const MAP_PIXEL_HEIGHT: int = 672
const SIDEBAR_WIDTH: int = 400
const DIVIDER_WIDTH: int = 16
const BELOW_MAP_HEIGHT: int = 181
const SCREEN_WIDTH: int = 1280
const SCREEN_HEIGHT: int = 853
const STATS_DATA_PATH: String = "res://data/stats/"
const GAME_CONFIG_PATH: String = "res://data/config/game.json"
const SLOTS_CONFIG_PATH: String = "res://data/config/slots.json"
const REGIONS_DATA_PATH: String = "res://data/regions/"
const TILES_CONFIG_PATH: String = "res://data/config/tiles.json"
const TILE_TYPE_CUSTOM_DATA: String = "tile_type_id"
const STARTING_REGION_KEY: String = "starting_region"
const COMBAT_CONFIG_PATH: String = "res://data/config/combat.json"
const MODIFIER_REGISTRY_PATH: String = "res://data/modifiers/modifiers.json"
const EXPERIENCE_STAT_ID: String = "experience"
const SPRITE_CORPSE_PATH: String = "res://assets/sprites/object_corpse.png"
const SPRITE_CARRIABLE_PATH: String = "res://assets/sprites/object_carriable.png"
const SPRITE_NONCARRIABLE_PATH: String = "res://assets/sprites/object_noncarriable.png"
const NPC_SCENE_PATH: String = "res://scenes/actors/NPC.tscn"
const WORLD_OBJECT_SCENE_PATH: String = "res://scenes/actors/WorldObject.tscn"
const LOOK_DESCRIPTION_LAYER: String = "look_description"

func tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2(tile * TILE_SIZE) + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)

func natural_list(names: Array) -> String:
	if names.size() == 0:
		return ""
	if names.size() == 1:
		return names[0]
	if names.size() == 2:
		return names[0] + " and " + names[1]
	var result := ""
	for i in range(names.size()):
		if i == names.size() - 1:
			result += "and " + names[i]
		else:
			result += names[i] + ", "
	return result

func apply_camera_limits(cam: Camera2D, width_tiles: int, height_tiles: int) -> void:
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = width_tiles * TILE_SIZE
	cam.limit_bottom = height_tiles * TILE_SIZE

func load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Constants: cannot open " + path)
		return {}
	var json := JSON.new()
	var text := file.get_as_text()
	file.close()
	if json.parse(text) != OK:
		push_error("Constants: JSON parse error in " + path)
		return {}
	var result = json.get_data()
	if result is Dictionary:
		return result
	return {}
