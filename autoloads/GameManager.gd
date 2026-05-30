extends Node

const _WORLD_OBJECT_SCENE: String = "res://scenes/actors/WorldObject.tscn"

var current_region: Node = null
var player_tile: Vector2i = Vector2i(5, 5)
var dialogue_active: bool = false

var sub_viewport: SubViewport = null
var dialogue_box: CanvasLayer = null
var inventory_screen: CanvasLayer = null
var objects_node: Node = null

var _corpse_decay_ticks: int = 0
var npc_max_path_length: int = 0
var not_talkable_default: String = "They cannot speak with you right now."
var waypoint_manager: WaypointManager = null
var slot_registry: SlotRegistry = null
var character_panel: CharacterPanel = null
var _world_corpses: Dictionary = {}   # Node2D -> { spawn_tick, expiry_tick, display_name }
var _carried_corpses: Dictionary = {} # inventory instance_id (int) -> { spawn_tick, elapsed_at_pickup, display_name }

func _load_config() -> void:
	var file := FileAccess.open(Constants.GAME_CONFIG_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return
	file.close()
	var data: Dictionary = json.get_data()
	var raw_decay = data.get("corpse_decay_ticks", 0)
	_corpse_decay_ticks = int(raw_decay) if raw_decay != null else 0
	var raw_path = data.get("npc_max_path_length", 0)
	npc_max_path_length = int(raw_path) if raw_path != null else 0
	var raw_msg = data.get("not_talkable_default")
	if raw_msg is String:
		not_talkable_default = raw_msg

func load_region(scene_path: String) -> void:
	if sub_viewport == null:
		return
	if current_region != null:
		WorldState.clear_npc_registry()
		# Clear world corpses from outgoing region without spilling
		for world_obj in _world_corpses.keys():
			if is_instance_valid(world_obj) and current_region.is_ancestor_of(world_obj):
				WorldState.clear_object_from_tile(world_obj.object_tile, world_obj.object_id)
				_world_corpses.erase(world_obj)
		current_region.queue_free()
		current_region = null
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var region := packed.instantiate()
	sub_viewport.add_child(region)
	current_region = region
	objects_node = region.get_node_or_null("Objects")
	waypoint_manager = region.get_node_or_null("WaypointManager") as WaypointManager
	var player: Node = region.get_node_or_null("Actors/Player")
	if player == null:
		return
	if dialogue_box != null:
		player.dialogue_box = dialogue_box
		if not dialogue_box.dialogue_closed.is_connected(player._on_dialogue_closed):
			dialogue_box.dialogue_closed.connect(player._on_dialogue_closed)
	if inventory_screen != null:
		player.inventory_screen = inventory_screen
		if not inventory_screen.object_drop_requested.is_connected(player._on_object_drop):
			inventory_screen.object_drop_requested.connect(player._on_object_drop)
		if not inventory_screen.inventory_closed.is_connected(player._on_inventory_closed):
			inventory_screen.inventory_closed.connect(player._on_inventory_closed)

func get_objects_at(tile: Vector2i) -> Array:
	if objects_node == null:
		return []
	var result: Array = []
	for child in objects_node.get_children():
		if child.object_tile == tile:
			result.append(child)
	return result

func spawn_object(object_id: String, tile: Vector2i) -> void:
	if objects_node == null:
		return
	var packed := load(_WORLD_OBJECT_SCENE) as PackedScene
	if packed == null:
		return
	var world_object := packed.instantiate()
	world_object.object_id = object_id
	world_object.object_tile = tile
	objects_node.add_child(world_object)

func spawn_or_merge(object_id: String, tile: Vector2i, count: int) -> void:
	if objects_node == null:
		return
	var existing_objs := get_objects_at(tile)
	for obj in existing_objs:
		if obj.object_id == object_id:
			obj.stack_count += count
			return
	var packed := load(_WORLD_OBJECT_SCENE) as PackedScene
	if packed == null:
		return
	var world_object := packed.instantiate()
	world_object.object_id = object_id
	world_object.object_tile = tile
	world_object.stack_count = count
	objects_node.add_child(world_object)

func spawn_corpse(tile: Vector2i, corpse_display_name: String, npc_inventory: Inventory) -> void:
	if objects_node == null:
		return
	var packed := load(_WORLD_OBJECT_SCENE) as PackedScene
	if packed == null:
		return
	var world_object := packed.instantiate()
	world_object.object_id = "corpse"
	world_object.object_tile = tile
	world_object.instance_display_name = corpse_display_name
	objects_node.add_child(world_object)
	for item in npc_inventory.get_objects():
		world_object._content_ids.append(item["object_id"])
	if _corpse_decay_ticks > 0:
		_world_corpses[world_object] = {
			"spawn_tick": GameTime.total_ticks,
			"expiry_tick": GameTime.total_ticks + _corpse_decay_ticks,
			"display_name": corpse_display_name
		}

func on_corpse_picked_up(world_obj: Node2D, inventory_instance_id: int) -> void:
	var spawn_tick: int = GameTime.total_ticks
	var display_name: String = world_obj.instance_display_name
	if _world_corpses.has(world_obj):
		var entry: Dictionary = _world_corpses[world_obj]
		spawn_tick = entry["spawn_tick"]
		display_name = entry["display_name"]
		_world_corpses.erase(world_obj)
	var elapsed: int = GameTime.total_ticks - spawn_tick
	_carried_corpses[inventory_instance_id] = {
		"spawn_tick": spawn_tick,
		"elapsed_at_pickup": elapsed,
		"display_name": display_name
	}
	PlayerInventory.set_instance_name(inventory_instance_id, display_name)

func on_corpse_dropped(inventory_instance_id: int, tile: Vector2i) -> void:
	if objects_node == null:
		return
	var packed := load(_WORLD_OBJECT_SCENE) as PackedScene
	if packed == null:
		return
	var world_object := packed.instantiate()
	world_object.object_id = "corpse"
	world_object.object_tile = tile
	var display_name: String = "corpse"
	if _carried_corpses.has(inventory_instance_id):
		var entry: Dictionary = _carried_corpses[inventory_instance_id]
		display_name = entry.get("display_name", "corpse")
		world_object.instance_display_name = display_name
		_carried_corpses.erase(inventory_instance_id)
		if _corpse_decay_ticks > 0:
			var remaining: int = _corpse_decay_ticks - entry.get("elapsed_at_pickup", 0)
			_world_corpses[world_object] = {
				"spawn_tick": GameTime.total_ticks,
				"expiry_tick": GameTime.total_ticks + max(remaining, 1),
				"display_name": display_name
			}
	else:
		world_object.instance_display_name = "corpse"
	objects_node.add_child(world_object)

func _on_tick_advanced_decay(total_ticks: int) -> void:
	if _world_corpses.is_empty():
		return
	var to_expire: Array = []
	for world_obj in _world_corpses:
		if total_ticks >= _world_corpses[world_obj]["expiry_tick"]:
			to_expire.append(world_obj)
	for world_obj in to_expire:
		_expire_corpse(world_obj)

func _expire_corpse(world_obj: Node2D) -> void:
	if not _world_corpses.has(world_obj):
		return
	var entry: Dictionary = _world_corpses[world_obj]
	for content_id in world_obj._content_ids:
		spawn_object(content_id, world_obj.object_tile)
	world_obj._content_ids.clear()
	MessageLog.post(entry["display_name"] + " has crumbled to dust.")
	WorldState.clear_object_from_tile(world_obj.object_tile, world_obj.object_id)
	_world_corpses.erase(world_obj)
	world_obj.queue_free()


func get_waypoint_position(waypoint_name: String, fallback_tile: Vector2i) -> Vector2i:
	if waypoint_manager == null or not waypoint_manager.has_waypoint(waypoint_name):
		push_error("GameManager: waypoint not found: " + waypoint_name)
		return fallback_tile
	return waypoint_manager.get_waypoint(waypoint_name)

func get_player_tile() -> Vector2i:
	return player_tile

func get_region_bounds() -> Rect2i:
	if current_region == null:
		return Rect2i()
	var terrain_layer: TileMapLayer = current_region.get_node_or_null("TerrainLayer")
	if terrain_layer == null:
		return Rect2i()
	return terrain_layer.get_used_rect()

func is_tile_passable(tile: Vector2i) -> bool:
	if WorldState.is_tile_occupied(tile):
		return false
	if WorldState.is_tile_blocked_by_object(tile):
		return false
	if current_region != null:
		var terrain_layer: TileMapLayer = current_region.get_node_or_null("TerrainLayer")
		if terrain_layer != null:
			var tile_data := terrain_layer.get_cell_tile_data(tile)
			if tile_data != null and tile_data.get_collision_polygons_count(0) > 0:
				return false
	return true

func is_tile_transparent(tile: Vector2i) -> bool:
	if current_region != null:
		var terrain_layer: TileMapLayer = current_region.get_node_or_null("TerrainLayer")
		if terrain_layer != null:
			var tile_data := terrain_layer.get_cell_tile_data(tile)
			if tile_data != null and tile_data.get_collision_polygons_count(0) > 0:
				return false
	var obj_ids := WorldState.get_objects_at(tile)
	if not obj_ids.is_empty():
		if PlayerInventory.get_object_data(obj_ids.back()).get("container", false):
			return true
	for object_id in obj_ids:
		var data := PlayerInventory.get_object_data(object_id)
		if not data.get("transparent", true):
			return false
	return true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_character_panel"):
		if character_panel != null:
			character_panel.toggle()

func _ready() -> void:
	_load_config()
	slot_registry = SlotRegistry.new()
	slot_registry.load_from_file(Constants.SLOTS_CONFIG_PATH)
	GameTime.time_period_changed.connect(_on_time_period_changed)
	GameTime.season_changed.connect(_on_season_changed)
	GameTime.tick_advanced.connect(_on_tick_advanced_decay)

func _on_time_period_changed(period: String) -> void:
	match period:
		"dawn": _on_dawn()
		"day": _on_day()
		"dusk": _on_dusk()
		"night": _on_night()

func _on_dawn() -> void:
	MessageLog.post("The sun rises.")

func _on_day() -> void:
	MessageLog.post("It is day.")

func _on_dusk() -> void:
	MessageLog.post("The sun sets.")

func _on_night() -> void:
	MessageLog.post("It is night.")

func _on_season_changed(season: String) -> void:
	match season:
		"Spring": _on_spring()
		"Summer": _on_summer()
		"Autumn": _on_autumn()
		"Winter": _on_winter()

func _on_spring() -> void:
	MessageLog.post("Spring has arrived.")

func _on_summer() -> void:
	MessageLog.post("Summer has arrived.")

func _on_autumn() -> void:
	MessageLog.post("Autumn has arrived.")

func _on_winter() -> void:
	MessageLog.post("Winter has arrived.")

func deposit_into_container(tile: Vector2i, object_id: String, _instance: Dictionary) -> bool:
	var world_objs := get_objects_at(tile)
	if world_objs.is_empty():
		return false
	var container: Node = world_objs.back()
	if not container.is_container:
		return false
	if container.container_slots != -1 and container._content_ids.size() >= container.container_slots:
		return false
	container._content_ids.append(object_id)
	return true
