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
const TIME_CONFIG_PATH: String = "res://data/config/time.json"
const CLASSES_CONFIG_PATH: String = "res://data/config/classes.json"
const EQUIPMENT_TYPES_CONFIG_PATH: String = "res://data/config/equipment_types.json"
const OBJECTS_REGISTRY_PATH: String = "res://data/objects/objects.json"
const OBJECT_DEFAULTS_PATH: String = "res://data/config/object_defaults.json"
const OBJECT_TYPES_CONFIG_PATH: String = "res://data/config/object_types.json"
const SLOTS_CONFIG_PATH: String = "res://data/config/slots.json"
const REGIONS_DATA_PATH: String = "res://data/regions/"
const TILES_CONFIG_PATH: String = "res://data/config/tiles.json"
const TILE_TYPE_CUSTOM_DATA: String = "tile_type_id"
const STARTING_REGION_KEY: String = "starting_region"
const COMBAT_CONFIG_PATH: String = "res://data/config/combat.json"
const MODIFIER_REGISTRY_PATH: String = "res://data/modifiers/modifiers.json"
const QUESTS_DATA_PATH: String = "res://data/quests/quests.json"
const PLAYER_DATA_PATH: String = "res://data/player/player.json"
const EXPERIENCE_STAT_ID: String = "experience"
const STAT_ID_HP: String = "hp"
const STAT_ID_MANA: String = "mana"
const STAT_ID_MAX_MANA: String = "max_mana"
const STAT_ID_LEVEL: String = "level"
const STAT_ID_VISION_RADIUS: String = "vision_radius"
const SPRITE_CORPSE_PATH: String = "res://assets/sprites/object_corpse.png"
const SPRITE_CARRIABLE_PATH: String = "res://assets/sprites/object_carriable.png"
const SPRITE_NONCARRIABLE_PATH: String = "res://assets/sprites/object_noncarriable.png"
const SPRITE_SOURCE_SIZE := Vector2i(64, 64)
const SPRITE_WORLD_SIZE  := Vector2i(32, 32)
const SPRITE_ICON_SIZE   := Vector2i(16, 16)
const SPRITE_SHEET_FRAME_COUNT: int = 4
const SPRITE_SHEET_FRAME_WIDTH: int = 64
const SPRITE_SHEET_FRAME_HEIGHT: int = 64
const SPRITE_SHEET_TOTAL_WIDTH: int = 256
const THEME_PATH_KEY    : String = "theme_path"
const FONT_BODY_ROLE    : String = "body"
const FONT_HEADER_ROLE  : String = "header"
const FONT_KEY_HINT_ROLE: String = "key_hint"
const NPC_SCENE_PATH: String = "res://scenes/actors/NPC.tscn"
const WORLD_OBJECT_SCENE_PATH: String = "res://scenes/actors/WorldObject.tscn"
const LOOK_DESCRIPTION_LAYER: String = "look_description"
const JOURNAL_PANEL_WIDTH: int = 780
const JOURNAL_PANEL_HEIGHT: int = 600
const SAVES_DIR: String = "user://saves/"
const SAVE_INDEX_PATH: String = "user://saves/index.json"
const GAME_TITLE_KEY: String = "game_title"
const SAVE_VERSION: int = 1
const REGION_CACHE_MAX: int = 8
const AMBIENT_LIGHT_SOURCE_TAG: String = "ambient_light"
const CARRIED_LIGHT_SOURCE_TAG: String = "carried_light"
const UNDERGROUND_LIGHT_SOURCE_TAG: String = "underground_light"
const MESSAGES_CONFIG_PATH: String = "res://data/config/messages.json"
const SPELLS_CONFIG_PATH: String = "res://data/config/spells.json"
const COMMAND_ICONS_CONFIG_PATH: String = "res://data/config/command_icons.json"
const SHOPS_DATA_PATH: String = "res://data/shops/shops.json"
const PLAYER_MEMBER_ID: String = "player"
const MAX_PARTY_SIZE_KEY: String = "max_party_size"
const FACTIONS_CONFIG_PATH: String = "res://data/config/factions.json"
const NPC_DATA_PATH: String = "res://data/npcs/"
const TILESET_PATH: String = "res://assets/tilesets/wilderness.png"
const REGIONS_CONFIG_PATH: String = "res://data/config/regions.json"
const KEY_CONFIRM_YES: int = KEY_Y
const KEY_CONFIRM_NO: int = KEY_N
const AUDIO_BUS_MASTER  : String = "Master"
const AUDIO_BUS_MUSIC   : String = "Music"
const AUDIO_BUS_SFX     : String = "SFX"
const AUDIO_BUS_AMBIENT : String = "Ambient"
const PREFERENCES_PATH  : String = "user://preferences.json"
const SOUNDS_CONFIG_PATH: String = "res://data/config/sounds.json"
const NPC_DEFAULTS_PATH: String = "res://data/config/npc_defaults.json"
const HEALER_SERVICE_TYPES_PATH: String = "res://data/config/healer_service_types.json"

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

func replace_token(text: String, token: String, replacement: String) -> String:
	var result := ""
	var i := 0
	var tlen := token.length()
	while i < text.length():
		if text.substr(i, tlen) == token:
			var before_ok: bool = (i == 0) or not is_ident_char(text[i - 1])
			var after_end: bool = (i + tlen >= text.length())
			var after_ok: bool = after_end or not is_ident_char(text[i + tlen])
			if before_ok and after_ok:
				result += replacement
				i += tlen
				continue
		result += text[i]
		i += 1
	return result

func is_ident_char(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_"

func make_terrain_tileset() -> Array:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(0, LOOK_DESCRIPTION_LAYER)
	tile_set.set_custom_data_layer_type(0, TYPE_STRING)
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(1, TILE_TYPE_CUSTOM_DATA)
	tile_set.set_custom_data_layer_type(1, TYPE_STRING)
	var source := TileSetAtlasSource.new()
	source.texture = load(GameManager.tile_atlas_path)
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_source(source, 0)
	return [tile_set, source]

func paint_rect(layer: TileMapLayer, x0: int, y0: int, x1: int, y1: int, atlas_coords: Vector2i) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			layer.set_cell(Vector2i(x, y), 0, atlas_coords)

func setup_tileset_from_atlas(layer: TileMapLayer, tile_registry) -> void:
	var ts_pair: Array = make_terrain_tileset()
	var tile_set: TileSet = ts_pair[0]
	var source: TileSetAtlasSource = ts_pair[1]
	if tile_registry == null:
		layer.tile_set = tile_set
		return
	var tex_size: Vector2i = Vector2i(source.texture.get_size()) if source.texture != null else Vector2i.ZERO
	for tile_id in tile_registry.get_all_tile_ids():
		var coords: Vector2i = tile_registry.get_atlas_coords(tile_id)
		var tile_px: Vector2i = coords * TILE_SIZE
		if tile_px.x + TILE_SIZE > tex_size.x or tile_px.y + TILE_SIZE > tex_size.y:
			continue
		if not source.has_tile(coords):
			source.create_tile(coords)
		var td: TileData = source.get_tile_data(coords, 0)
		td.set_custom_data_by_layer_id(0, tile_registry.get_look_description(tile_id))
		td.set_custom_data_by_layer_id(1, tile_id)
	layer.tile_set = tile_set

func paint_bordered_map(layer: TileMapLayer, width: int, height: int, border_coords: Vector2i, fill_coords: Vector2i) -> void:
	for y in range(height):
		for x in range(width):
			var is_border := (x == 0 or y == 0 or x == width - 1 or y == height - 1)
			layer.set_cell(Vector2i(x, y), 0, border_coords if is_border else fill_coords)

func set_hbox_color(hbox: HBoxContainer, color: Color) -> void:
	for child in hbox.get_children():
		if child is Label:
			(child as Label).add_theme_color_override("font_color", color)

func clear_hbox_color(hbox: HBoxContainer) -> void:
	for child in hbox.get_children():
		if child is Label:
			(child as Label).remove_theme_color_override("font_color")

func scroll_list_to_row(scroll: ScrollContainer, item_list: Control, cursor: int) -> void:
	var children := item_list.get_children()
	if cursor >= children.size():
		return
	var row := children[cursor] as Control
	if row == null:
		return
	var row_top := row.position.y
	var row_bottom := row_top + row.size.y
	var visible_h := scroll.size.y
	if visible_h <= 0.0:
		return
	var scroll_top := float(scroll.scroll_vertical)
	if row_top < scroll_top:
		scroll.scroll_vertical = int(row_top)
	elif row_bottom > scroll_top + visible_h:
		scroll.scroll_vertical = int(row_bottom - visible_h)

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
