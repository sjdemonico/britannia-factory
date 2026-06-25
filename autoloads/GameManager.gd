extends Node

signal region_loaded

var current_region: Node = null
var player_tile: Vector2i = Vector2i.ZERO
var dialogue_active: bool = false

var sub_viewport: SubViewport = null
var dialogue_box: CanvasLayer = null
var inventory_screen: CanvasLayer = null
var objects_node: Node = null

var npc_max_path_length: int = 0
var not_talkable_default: String = "They cannot speak with you right now."
var waypoint_manager: WaypointManager = null
var slot_registry: SlotRegistry = null
var character_panel: CharacterPanel = null
var journal_panel = null
var save_load_panel = null
var spellbook_panel = null
var shop_panel: ShopPanel = null
var healer_panel = null
var sidebar = null
var tile_registry: TileRegistry = null
var region_cache: RegionCache = null
var combat_resolver: CombatResolver = null
var level_manager: LevelManager = null
var world_paused: bool = false
var use_action_registry: UseActionRegistry = null
var class_registry: ClassRegistry = null
var equipment_type_registry: EquipmentTypeRegistry = null
var debug_mode: bool = false
var currency_stat_id: String = "gold"
var currency_display_name: String = "Gold"
var sell_multiplier: float = 0.5
var key_initial_delay: float = 0.4
var key_repeat_interval: float = 0.1
var _shop_registry: Dictionary = {}
var shop_ui_pending: ShopManager = null
var darkness_overlay = null
var _fixed_light_sources: Array = []
var _in_underground_region: bool = false
var hazard_processor: HazardProcessor = null
var spawn_manager: SpawnManager = SpawnManager.new()
var _hazard_last_player_tile: Vector2i = Vector2i(-999, -999)
var starting_region: String = "wilderness"
var _pending_region: String = ""
var _quit_pending: bool = false
var _pending_npc_spawns: Dictionary = {}  # region_id -> Array[{npc_id, tile: [x, y]}]

var _spawn_points: Dictionary = {}  # spawn_id -> Vector2i
var _default_spawn: String = ""
var _loading_region_id: String = ""
var _current_region_id: String = ""
var _pending_spawn_id: String = ""
var _object_instances: Dictionary = {}  # instance_id -> WorldObject

var _walk_on_transitions: Dictionary = {}  # Vector2i -> { region_id, spawn_id }
var _enter_transitions: Dictionary = {}    # Vector2i -> { region_id, spawn_id }
var _object_transitions: Dictionary = {}   # String -> { region_id, spawn_id }

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
	var raw_debug = data.get("debug_mode", false)
	debug_mode = bool(raw_debug) if raw_debug != null else false
	var raw_path = data.get("npc_max_path_length", 0)
	npc_max_path_length = int(raw_path) if raw_path != null else 0
	var raw_msg = data.get("not_talkable_default")
	if raw_msg is String:
		not_talkable_default = raw_msg
	var raw_region = data.get("starting_region", "wilderness")
	if raw_region is String and not (raw_region as String).is_empty():
		starting_region = raw_region as String
	var raw_currency_id = data.get("currency_stat_id")
	if raw_currency_id is String and not (raw_currency_id as String).is_empty():
		currency_stat_id = raw_currency_id as String
	var raw_currency_name = data.get("currency_display_name")
	if raw_currency_name is String and not (raw_currency_name as String).is_empty():
		currency_display_name = raw_currency_name as String
	var raw_sell_mult = data.get("sell_multiplier", 0.5)
	sell_multiplier = float(raw_sell_mult) if raw_sell_mult != null else 0.5
	var raw_key_delay = data.get("key_initial_delay", 0.4)
	key_initial_delay = float(raw_key_delay) if raw_key_delay != null else 0.4
	var raw_key_repeat = data.get("key_repeat_interval", 0.1)
	key_repeat_interval = float(raw_key_repeat) if raw_key_repeat != null else 0.1
	level_manager = LevelManager.new()
	var raw_thresholds = data.get("level_thresholds", [])
	if raw_thresholds is Array:
		level_manager.load_config(raw_thresholds)

func load_region(region_id: String, spawn_id: String = "") -> void:
	if _loading_region_id == region_id:
		# Phase 2: called from scene's _ready() during scene load
		_loading_region_id = ""
		_setup_region_nodes()
		if not _validate_region_tiles():
			push_error("GameManager: region tile validation failed, aborting load of '" + region_id + "'")
			return
		if region_id == "combat_arena":
			_pending_spawn_id = ""
			return
		var loader := RegionLoader.new()
		if region_cache != null and region_cache.has_region(region_id):
			_restore_from_cache(region_id, loader)
		else:
			_fresh_load_region(region_id, loader)
			if region_cache != null and region_cache.has_diff(region_id):
				var diff: RegionDiff = region_cache.get_diff(region_id)
				region_cache.clear_diff(region_id)
				loader.apply_diff(diff, current_region)
		QuestManager.check_region_entry_triggers(region_id)
		_register_fixed_light_sources()
		_setup_spawn_manager(region_id)
		spawn_manager.execute_pending_for_region(region_id)
		_place_player_at_spawn(_pending_spawn_id)
		_pending_spawn_id = ""
		return

	# Phase 1: scene loading (called externally)
	if sub_viewport == null:
		push_error("GameManager: sub_viewport not set, cannot load region")
		return

	_pending_spawn_id = spawn_id

	if current_region != null:
		if region_cache != null and not _current_region_id.is_empty() and _current_region_id != "combat_arena":
			SaveManager.autosave()
			_snapshot_and_unload()
		else:
			_clear_region()

	_loading_region_id = region_id

	var scene_path := _region_id_to_scene_path(region_id)
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("GameManager: cannot load scene: " + scene_path)
		_loading_region_id = ""
		return

	var region := packed.instantiate()
	current_region = region
	sub_viewport.add_child(region)  # triggers scene _ready() -> phase 2

	_connect_player_signals()
	_current_region_id = region_id

func _fresh_load_region(region_id: String, loader: RegionLoader) -> void:
	var region_data := loader.load_json(region_id)
	if region_data.is_empty():
		push_error("GameManager: failed to load region data for: " + region_id)
		return
	if region_cache != null:
		region_cache.store_baseline(region_id, region_data)
	loader.register_spawns(region_data)
	loader.load_waypoints(region_data)
	loader.spawn_npcs(region_data, current_region)
	_spawn_pending_npcs(region_id)
	loader.spawn_objects(region_data)
	loader.apply_npc_schedule_placement(current_region)
	_register_transitions(region_data)
	loader.load_tile_triggers(region_data)
	_apply_underground_state(region_data.get("is_underground", false))

func _restore_from_cache(region_id: String, loader: RegionLoader) -> void:
	var snapshot := region_cache.restore_region(region_id)
	region_cache.remove_region(region_id)
	var region_data: Dictionary = snapshot.get("region_data", {})

	loader.register_spawns(region_data)
	loader.load_waypoints(region_data)

	# Restore NPCs at their saved positions
	var actors_node := current_region.get_node_or_null("Actors")
	var npc_scene := load(Constants.NPC_SCENE_PATH) as PackedScene
	if actors_node != null and npc_scene != null:
		for entry in snapshot.get("npcs", []):
			var npc_id: String = str(entry.get("npc_id", ""))
			var raw_tile = entry.get("tile", [0, 0])
			if npc_id.is_empty():
				continue
			var tile := Vector2i(int(raw_tile[0]), int(raw_tile[1]))
			var npc := npc_scene.instantiate()
			npc.npc_id = npc_id
			npc.npc_tile = tile
			actors_node.add_child(npc)
			if bool(entry.get("is_quest_spawn", false)):
				npc.is_quest_spawn = true
				npc.quest_spawn_instance_id = str(entry.get("quest_spawn_instance_id", ""))
				if not npc.quest_spawn_instance_id.is_empty():
					spawn_manager.reregister_quest_spawn(npc.quest_spawn_instance_id, npc, npc.npc_tile)
	_spawn_pending_npcs(region_id)

	# Restore objects with their runtime state
	var wo_scene := load(Constants.WORLD_OBJECT_SCENE_PATH) as PackedScene
	if objects_node != null and wo_scene != null:
		for entry in snapshot.get("objects", []):
			var object_id: String = str(entry.get("object_id", ""))
			var raw_tile = entry.get("tile", [0, 0])
			if object_id.is_empty():
				continue
			var tile := Vector2i(int(raw_tile[0]), int(raw_tile[1]))
			var world_object := wo_scene.instantiate()
			world_object.object_id = object_id
			world_object.object_tile = tile
			world_object.stack_count = maxi(1, int(entry.get("stack_count", 1)))
			var inst_id: String = str(entry.get("instance_id", ""))
			if not inst_id.is_empty():
				world_object.instance_id = inst_id
			var raw_targets = entry.get("targets")
			if raw_targets is Array:
				for t in raw_targets:
					world_object.targets.append(str(t))
			objects_node.add_child(world_object)
			if not inst_id.is_empty():
				register_object_instance(inst_id, world_object)
			# Restore runtime state after _ready()
			world_object.is_open = bool(entry.get("is_open", false))
			if world_object.is_open and world_object.toggleable:
				world_object.queue_redraw()
			world_object.container_open = bool(entry.get("container_open", false))
			if world_object.container_open:
				WorldState.open_container(tile)
			world_object._content_ids = entry.get("_content_ids", []).duplicate()
			if entry.has("is_locked"):
				world_object.is_locked = bool(entry["is_locked"])

	_register_transitions(region_data)
	loader.load_tile_triggers(region_data)
	_apply_underground_state(region_data.get("is_underground", false))

func _apply_underground_state(is_underground: bool) -> void:
	if is_underground == _in_underground_region:
		return
	_in_underground_region = is_underground
	if is_underground:
		GameTime.suppress_ambient()
		PlayerStats.stat_block.remove_modifiers_by_source(Constants.UNDERGROUND_LIGHT_SOURCE_TAG)
		var max_radius: int = PlayerStats.stat_block.get_max("vision_radius")
		PlayerStats.stat_block.apply_dynamic_modifier({
			"modifier_id": "underground_light",
			"stat_id": "vision_radius",
			"magnitude": 1 - max_radius,
			"stacking": "exclusive_per_source",
			"duration_type": "permanent_until_removed"
		}, Constants.UNDERGROUND_LIGHT_SOURCE_TAG)
	else:
		PlayerStats.stat_block.remove_modifiers_by_source(Constants.UNDERGROUND_LIGHT_SOURCE_TAG)
		GameTime.unsuppress_ambient()

func _snapshot_region() -> Dictionary:
	var snapshot: Dictionary = {}

	var loader := RegionLoader.new()
	snapshot["region_data"] = loader.load_json(_current_region_id)

	# Snapshot object nodes
	var objects_snapshot: Array = []
	if objects_node != null:
		for child in objects_node.get_children():
			var wo := child as WorldObject
			if wo == null:
				continue
			var entry: Dictionary = {
				"object_id": wo.object_id,
				"tile": [wo.object_tile.x, wo.object_tile.y],
				"stack_count": wo.stack_count,
				"is_open": wo.is_open,
				"container_open": wo.container_open,
				"_content_ids": wo._content_ids.duplicate(),
				"is_locked": wo.is_locked
			}
			if not wo.instance_id.is_empty():
				entry["instance_id"] = wo.instance_id
			if not wo.targets.is_empty():
				entry["targets"] = wo.targets.duplicate()
			objects_snapshot.append(entry)
	snapshot["objects"] = objects_snapshot

	# Snapshot NPC nodes with current tile positions
	var npcs_snapshot: Array = []
	var actors_node := current_region.get_node_or_null("Actors")
	if actors_node != null:
		for child in actors_node.get_children():
			var npc := child as NPC
			if npc == null or npc.npc_id.is_empty():
				continue
			if npc.is_spawned_monster:
				continue
			var npc_entry: Dictionary = {
				"npc_id": npc.npc_id,
				"tile": [npc.npc_tile.x, npc.npc_tile.y]
			}
			if npc.is_quest_spawn:
				npc_entry["is_quest_spawn"] = true
				npc_entry["quest_spawn_instance_id"] = npc.quest_spawn_instance_id
			npcs_snapshot.append(npc_entry)
	snapshot["npcs"] = npcs_snapshot

	return snapshot

func _snapshot_and_unload() -> void:
	spawn_manager.on_region_exit(_current_region_id)
	region_cache.store_region(_current_region_id, _snapshot_region())
	WorldState.clear_all_occupants()
	WorldState.clear_all_objects()
	_object_instances.clear()
	current_region.queue_free()
	current_region = null
	_current_region_id = ""

func _clear_region() -> void:
	spawn_manager.on_region_exit(_current_region_id)
	WorldState.clear_all_occupants()
	WorldState.clear_all_objects()
	_object_instances.clear()
	if current_region != null:
		current_region.queue_free()
		current_region = null

func _place_player_at_spawn(spawn_id: String) -> void:
	var player: Node = current_region.get_node_or_null("Actors/Player")
	if player == null:
		push_error("GameManager: Player not found when placing at spawn")
		return
	var spawn_tile: Vector2i
	if spawn_id.is_empty():
		spawn_tile = get_default_spawn_tile()
	else:
		if _spawn_points.has(spawn_id):
			spawn_tile = _spawn_points[spawn_id]
		else:
			push_error("GameManager: spawn_id '" + spawn_id + "' not found, using default")
			spawn_tile = get_default_spawn_tile()
	player.teleport_to_tile(spawn_tile)

func _register_transitions(data: Dictionary) -> void:
	_walk_on_transitions.clear()
	_enter_transitions.clear()
	_object_transitions.clear()
	for entry in data.get("transitions", []):
		var t_type: String = str(entry.get("type", ""))
		var region_id: String = str(entry.get("region_id", ""))
		var spawn_id: String = str(entry.get("spawn_id", ""))
		if region_id.is_empty():
			push_error("GameManager: transition missing region_id")
			continue
		match t_type:
			"walk_on":
				var raw_tile = entry.get("tile", [0, 0])
				if raw_tile is Array and raw_tile.size() >= 2:
					var tile := Vector2i(int(raw_tile[0]), int(raw_tile[1]))
					_walk_on_transitions[tile] = { "region_id": region_id, "spawn_id": spawn_id }
			"enter":
				var raw_tile = entry.get("tile", [0, 0])
				if raw_tile is Array and raw_tile.size() >= 2:
					var tile := Vector2i(int(raw_tile[0]), int(raw_tile[1]))
					_enter_transitions[tile] = { "region_id": region_id, "spawn_id": spawn_id }
			"object":
				var inst_id: String = str(entry.get("instance_id", ""))
				if not inst_id.is_empty():
					_object_transitions[inst_id] = { "region_id": region_id, "spawn_id": spawn_id }
			_:
				push_error("GameManager: unknown transition type '" + t_type + "'")

func get_walk_on_transition(tile: Vector2i) -> Dictionary:
	return _walk_on_transitions.get(tile, {})

func get_enter_transition(tile: Vector2i) -> Dictionary:
	return _enter_transitions.get(tile, {})

func get_object_transition(instance_id: String) -> Dictionary:
	return _object_transitions.get(instance_id, {})

func trigger_transition(region_id: String, spawn_id: String) -> void:
	load_region(region_id, spawn_id)

func _region_id_to_scene_path(region_id: String) -> String:
	if Constants.REGION_SCENE_PATHS.has(region_id):
		return Constants.REGION_SCENE_PATHS[region_id]
	push_error("GameManager: no scene path registered for region_id '" + region_id + "'")
	return ""

func _setup_region_nodes() -> void:
	objects_node = current_region.get_node_or_null("Objects")
	waypoint_manager = current_region.get_node_or_null("WaypointManager") as WaypointManager

func _connect_player_signals() -> void:
	var player: Node = current_region.get_node_or_null("Actors/Player")
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

func register_object_instance(instance_id: String, obj: WorldObject) -> void:
	_object_instances[instance_id] = obj

func unregister_object_instance(instance_id: String) -> void:
	_object_instances.erase(instance_id)

func get_object_by_instance_id(instance_id: String) -> WorldObject:
	return _object_instances.get(instance_id, null) as WorldObject

func configure_spawns(points: Dictionary, default_spawn: String) -> void:
	_spawn_points = points
	_default_spawn = default_spawn

func get_spawn_tile(spawn_id: String) -> Vector2i:
	return _spawn_points.get(spawn_id, Vector2i.ZERO)

func get_default_spawn_tile() -> Vector2i:
	if _default_spawn.is_empty():
		return Vector2i.ZERO
	return get_spawn_tile(_default_spawn)

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
	var packed := load(Constants.WORLD_OBJECT_SCENE_PATH) as PackedScene
	if packed == null:
		return
	var world_object := packed.instantiate()
	world_object.object_id = object_id
	world_object.object_tile = tile
	objects_node.add_child(world_object)

func spawn_object_timed(object_id: String, tile: Vector2i, duration_ticks: int) -> void:
	if objects_node == null:
		return
	var packed := load(Constants.WORLD_OBJECT_SCENE_PATH) as PackedScene
	if packed == null:
		return
	var world_object := packed.instantiate()
	world_object.object_id = object_id
	world_object.object_tile = tile
	objects_node.add_child(world_object)
	var weak_ref: WeakRef = weakref(world_object)
	GameTime.schedule(func():
		var obj: Object = weak_ref.get_ref()
		if obj != null and is_instance_valid(obj):
			WorldState.clear_object_from_tile(tile, object_id)
			(obj as Node).queue_free()
	, duration_ticks)

func spawn_or_merge(object_id: String, tile: Vector2i, count: int) -> void:
	if objects_node == null:
		return
	var existing_objs := get_objects_at(tile)
	for obj in existing_objs:
		if obj.object_id == object_id:
			obj.stack_count += count
			return
	var packed := load(Constants.WORLD_OBJECT_SCENE_PATH) as PackedScene
	if packed == null:
		return
	var world_object := packed.instantiate()
	world_object.object_id = object_id
	world_object.object_tile = tile
	world_object.stack_count = count
	objects_node.add_child(world_object)

func get_fixed_light_sources() -> Array:
	return _fixed_light_sources

func notify_spawn_killed(npc_node: Node) -> void:
	if spawn_manager != null:
		spawn_manager.on_spawn_killed(npc_node)

func notify_quest_spawn_killed(instance_id: String) -> void:
	spawn_manager.on_quest_spawn_killed(instance_id)

func _setup_spawn_manager(region_id: String) -> void:
	var loader := RegionLoader.new()
	var region_data := loader.load_json(region_id)
	var spawn_config = region_data.get("spawn_config")
	if not (spawn_config is Dictionary) or (spawn_config as Dictionary).is_empty():
		spawn_manager.load_config({})
	else:
		spawn_manager.load_config(spawn_config)
	spawn_manager.build_passable_cache()

func _register_fixed_light_sources() -> void:
	_fixed_light_sources.clear()
	if objects_node == null:
		region_loaded.emit()
		return
	for child in objects_node.get_children():
		var wo := child as WorldObject
		if wo == null:
			continue
		if wo.light_radius > 0 and not wo.carriable:
			_fixed_light_sources.append({"tile": wo.object_tile, "radius": wo.light_radius})
	region_loaded.emit()

func spawn_with_duration(object_id: String, tile: Vector2i, dur_remaining: int) -> void:
	if objects_node == null:
		return
	var packed := load(Constants.WORLD_OBJECT_SCENE_PATH) as PackedScene
	if packed == null:
		return
	var world_object := packed.instantiate()
	world_object.object_id = object_id
	world_object.object_tile = tile
	objects_node.add_child(world_object)
	world_object.duration_remaining = dur_remaining

func spawn_corpse(tile: Vector2i, corpse_display_name: String, npc_inventory: Inventory) -> void:
	if objects_node == null:
		return
	var packed := load(Constants.WORLD_OBJECT_SCENE_PATH) as PackedScene
	if packed == null:
		return
	var world_object := packed.instantiate()
	world_object.object_id = "corpse"
	world_object.object_tile = tile
	world_object.instance_display_name = corpse_display_name
	objects_node.add_child(world_object)
	for item in npc_inventory.get_objects():
		world_object._content_ids.append(item["object_id"])
	world_object.container_open = true
	WorldState.open_container(tile)

func reinstantiate_npc(member: PartyMember) -> void:
	if member.source_npc_id.is_empty():
		return
	var region_id := member.spawn_region_id
	var tile := member.spawn_tile
	if region_id == _current_region_id and current_region != null:
		var actors_node := current_region.get_node_or_null("Actors")
		if actors_node == null:
			return
		var npc_scene := load(Constants.NPC_SCENE_PATH) as PackedScene
		if npc_scene == null:
			return
		var npc := npc_scene.instantiate()
		npc.npc_id = member.source_npc_id
		npc.npc_tile = tile
		actors_node.add_child(npc)
	else:
		if not _pending_npc_spawns.has(region_id):
			_pending_npc_spawns[region_id] = []
		_pending_npc_spawns[region_id].append({
			"npc_id": member.source_npc_id,
			"tile": [tile.x, tile.y]
		})

func _spawn_pending_npcs(region_id: String) -> void:
	if not _pending_npc_spawns.has(region_id):
		return
	var actors_node := current_region.get_node_or_null("Actors")
	var npc_scene := load(Constants.NPC_SCENE_PATH) as PackedScene
	if actors_node == null or npc_scene == null:
		_pending_npc_spawns.erase(region_id)
		return
	for entry in _pending_npc_spawns[region_id]:
		var npc := npc_scene.instantiate()
		npc.npc_id = str(entry.get("npc_id", ""))
		var raw_tile = entry.get("tile", [0, 0])
		npc.npc_tile = Vector2i(int(raw_tile[0]), int(raw_tile[1]))
		actors_node.add_child(npc)
	_pending_npc_spawns.erase(region_id)

func get_waypoint_position(waypoint_name: String, fallback_tile: Vector2i) -> Vector2i:
	if waypoint_manager == null or not waypoint_manager.has_waypoint(waypoint_name):
		push_error("GameManager: waypoint not found: " + waypoint_name)
		return fallback_tile
	return waypoint_manager.get_waypoint(waypoint_name)

func get_player_tile() -> Vector2i:
	return player_tile

func get_current_region_id() -> String:
	return _current_region_id

func get_world_tile_type(tile: Vector2i) -> String:
	return _get_tile_type_id(tile)

func get_region_bounds() -> Rect2i:
	if current_region == null:
		return Rect2i()
	var terrain_layer: TileMapLayer = current_region.get_node_or_null("TerrainLayer")
	if terrain_layer == null:
		return Rect2i()
	return terrain_layer.get_used_rect()

func _get_tile_type_id(tile: Vector2i) -> String:
	if current_region == null:
		return ""
	var terrain_layer: TileMapLayer = current_region.get_node_or_null("TerrainLayer")
	if terrain_layer == null or terrain_layer.tile_set == null:
		return ""
	var tile_data := terrain_layer.get_cell_tile_data(tile)
	if tile_data == null:
		return ""
	var tile_set := terrain_layer.tile_set
	for i in range(tile_set.get_custom_data_layers_count()):
		if tile_set.get_custom_data_layer_name(i) == Constants.TILE_TYPE_CUSTOM_DATA:
			return tile_data.get_custom_data_by_layer_id(i)
	return ""

func is_tile_passable(tile: Vector2i) -> bool:
	if WorldState.is_tile_occupied(tile):
		return false
	for world_obj in get_objects_at(tile):
		if world_obj.toggleable:
			if not world_obj.is_open:
				return false
		elif not world_obj.passable:
			return false
	var tile_type_id := _get_tile_type_id(tile)
	if tile_type_id.is_empty():
		return false
	if tile_registry == null or not tile_registry.is_passable(tile_type_id):
		return false
	return true

func get_move_fail_chance(tile: Vector2i) -> float:
	if tile_registry == null:
		return 0.0
	var tile_type_id := _get_tile_type_id(tile)
	if tile_type_id.is_empty():
		return 0.0
	return tile_registry.get_move_fail_chance(tile_type_id)

func _validate_region_tiles() -> bool:
	if current_region == null:
		return true
	var terrain_layer: TileMapLayer = current_region.get_node_or_null("TerrainLayer")
	if terrain_layer == null or terrain_layer.tile_set == null:
		return true
	var tile_set := terrain_layer.tile_set
	var layer_idx: int = -1
	for i in range(tile_set.get_custom_data_layers_count()):
		if tile_set.get_custom_data_layer_name(i) == Constants.TILE_TYPE_CUSTOM_DATA:
			layer_idx = i
			break
	if layer_idx == -1:
		push_error("GameManager: TileSet missing custom data layer '" + Constants.TILE_TYPE_CUSTOM_DATA + "'")
		return false
	var valid := true
	for cell in terrain_layer.get_used_cells():
		var tile_data := terrain_layer.get_cell_tile_data(cell)
		if tile_data == null:
			continue
		var type_id: String = tile_data.get_custom_data_by_layer_id(layer_idx)
		if type_id.is_empty() or not tile_registry.has_tile(type_id):
			push_error("GameManager: unrecognized tile_type_id '" + type_id + "' at tile " + str(cell))
			valid = false
	return valid

func is_terrain_transparent(tile: Vector2i) -> bool:
	var type_id := _get_tile_type_id(tile)
	if type_id.is_empty() or tile_registry == null:
		return true
	return tile_registry.is_transparent(type_id)

func is_tile_transparent(tile: Vector2i) -> bool:
	if not is_terrain_transparent(tile):
		return false
	for object_id in WorldState.get_object_ids_at(tile):
		var data := PlayerInventory.get_object_data(object_id)
		if not data.get("transparent", true):
			return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	if _quit_pending:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == Constants.KEY_CONFIRM_YES:
				_quit_pending = false
				world_paused = false
				SaveManager.autosave()
				get_tree().quit()
			elif event.physical_keycode == Constants.KEY_CONFIRM_NO:
				_quit_pending = false
				world_paused = false
				MessageLog.post(MessageRegistry.get_message("action_cancelled"))
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("quit_game") and current_region != null:
		_quit_pending = true
		world_paused = true
		MessageLog.post(MessageRegistry.get_message("quit_save_prompt"))
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("toggle_save_load") and current_region != null:
		if save_load_panel != null:
			if not save_load_panel.panel.visible:
				if inventory_screen != null:
					inventory_screen.close()
				if character_panel != null:
					character_panel._close()
				if journal_panel != null:
					journal_panel.close()
				if spellbook_panel != null:
					spellbook_panel.close()
				if shop_panel != null:
					shop_panel.close()
				if healer_panel != null:
					healer_panel.close()
			save_load_panel.toggle()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("toggle_character_panel"):
		if character_panel != null:
			if not character_panel.panel.visible:
				if journal_panel != null:
					journal_panel.close()
				if save_load_panel != null:
					save_load_panel.close()
				if spellbook_panel != null:
					spellbook_panel.close()
				if shop_panel != null:
					shop_panel.close()
				if healer_panel != null:
					healer_panel.close()
			character_panel.toggle()
	if event.is_action_pressed("toggle_journal"):
		if journal_panel != null:
			if not journal_panel.panel.visible:
				if character_panel != null:
					character_panel._close()
				if save_load_panel != null:
					save_load_panel.close()
				if spellbook_panel != null:
					spellbook_panel.close()
				if shop_panel != null:
					shop_panel.close()
				if healer_panel != null:
					healer_panel.close()
			journal_panel.toggle()
	if event.is_action_pressed("toggle_spellbook") and current_region != null:
		if spellbook_panel != null:
			if not spellbook_panel.panel.visible:
				if inventory_screen != null:
					inventory_screen.close()
				if character_panel != null:
					character_panel._close()
				if journal_panel != null:
					journal_panel.close()
				if save_load_panel != null:
					save_load_panel.close()
				if shop_panel != null:
					shop_panel.close()
				if healer_panel != null:
					healer_panel.close()
			spellbook_panel.toggle()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("party_order") and not CombatManager.in_combat and current_region != null:
		var player_node = current_region.get_node_or_null("Actors/Player")
		if player_node != null and player_node.has_method("prompt_party_order"):
			player_node.prompt_party_order(
				func(new_order: Array):
					var ordered_ids: Array[String] = []
					for index in new_order:
						var m := PartyManager.get_member_at(index - 1)
						if m != null:
							ordered_ids.append(m.member_id)
					PartyManager.set_order(ordered_ids)
					MessageLog.post(MessageRegistry.get_message("party_order_confirmed"))
					MessageLog.post_blank(),
				func():
					MessageLog.post(MessageRegistry.get_message("party_order_cancelled"))
					MessageLog.post_blank()
			)
		get_viewport().set_input_as_handled()
		return

func on_hud_ready() -> void:
	if not SaveManager._pending_data.is_empty():
		SaveManager._apply_pending_load()
	elif not _pending_region.is_empty():
		var region_to_load: String = _pending_region
		_pending_region = ""
		load_region(region_to_load)
func start_new_game(player_name: String) -> void:
	PlayerStats.display_name = player_name
	_pending_region = starting_region
	get_tree().change_scene_to_file("res://scenes/ui/HUD.tscn")

func _validate_registries() -> void:
	for class_id in class_registry.get_all_class_ids():
		for eq_id in class_registry.get_equipment_whitelist(class_id):
			if not equipment_type_registry.has_type(eq_id):
				push_warning("ClassRegistry: unknown equipment_type '" + eq_id + "' in class '" + class_id + "' equipment_whitelist")
		for stat_id in class_registry.get_starting_stats(class_id):
			if not PlayerStats.has_stat(stat_id):
				push_warning("ClassRegistry: unknown stat '" + stat_id + "' in class '" + class_id + "' starting_stats")
	var objects_data: Dictionary = Constants.load_json(Constants.OBJECTS_REGISTRY_PATH)
	for entry in objects_data.get("objects", []):
		if entry is Dictionary and bool(entry.get("equippable", false)):
			var slots = entry.get("equip_slots")
			if not slots is Array or (slots as Array).is_empty():
				push_warning("ObjectRegistry: equippable object '" + str(entry.get("object_id", "?")) + "' has no equip_slots")

func _ready() -> void:
	_load_config()
	slot_registry = SlotRegistry.new()
	slot_registry.load_from_file(Constants.SLOTS_CONFIG_PATH)
	tile_registry = TileRegistry.new()
	tile_registry.load_from_file(Constants.TILES_CONFIG_PATH)
	equipment_type_registry = EquipmentTypeRegistry.new()
	equipment_type_registry.load_from_file(Constants.EQUIPMENT_TYPES_CONFIG_PATH)
	class_registry = ClassRegistry.new()
	class_registry.load_from_file(Constants.CLASSES_CONFIG_PATH)
	_validate_registries()
	region_cache = RegionCache.new()
	combat_resolver = CombatResolver.new()
	combat_resolver.load_config()
	GameTime.time_period_changed.connect(_on_time_period_changed)
	GameTime.season_changed.connect(_on_season_changed)
	use_action_registry = UseActionRegistry.new()
	use_action_registry.register("toggle_passability", _action_toggle_passability)
	use_action_registry.register("trigger_targets", _action_trigger_targets)
	use_action_registry.register("toggle_container", _action_toggle_container)
	use_action_registry.register("apply_modifier", _action_apply_modifier)
	use_action_registry.register("consume", _action_consume)
	use_action_registry.register("modify_faction_standing", _action_modify_faction_standing)
	use_action_registry.register("expend_charge", _action_expend_charge)
	use_action_registry.register("read", _action_read)
	use_action_registry.register("light_source_toggle", _action_light_source_toggle)
	use_action_registry.register("learn_spell", _action_learn_spell)
	use_action_registry.register("use_key", _action_use_key)
	use_action_registry.register("use_lockpick", _action_use_lockpick)
	use_action_registry.register("cast_effect", _action_cast_effect)
	use_action_registry.register("damage_target", _action_damage_target)
	hazard_processor = HazardProcessor.new()
	GameTime.tick_advanced.connect(_on_world_tick)
	FactionManager.standing_changed.connect(_on_standing_changed)
	_load_shops()
	QuestManager.quest_spawn_triggered.connect(spawn_manager.handle_quest_spawn)

func _load_shops() -> void:
	_shop_registry = {}
	var data: Dictionary = Constants.load_json(Constants.SHOPS_DATA_PATH)
	for shop_def in data.get("shops", []):
		var sid: String = str(shop_def.get("shop_id", ""))
		if sid.is_empty():
			continue
		var mgr := ShopManager.new()
		mgr.load_shop(shop_def)
		_shop_registry[sid] = mgr

func _reset_shop_state() -> void:
	for shop_id in _shop_registry:
		var shop: ShopManager = _shop_registry[shop_id]
		for object_id in shop._restock_handles:
			GameTime.cancel(shop._restock_handles[object_id])
	_load_shops()

func get_serializable_shop_state() -> Dictionary:
	var result: Dictionary = {}
	for shop_id in _shop_registry:
		result[shop_id] = (_shop_registry[shop_id] as ShopManager).get_stock_snapshot()
	return result

func get_serializable_shop_timers() -> Array:
	var result: Array = []
	for shop_id in _shop_registry:
		for entry in (_shop_registry[shop_id] as ShopManager).get_restock_timer_snapshot():
			var e: Dictionary = entry.duplicate()
			e["shop_id"] = shop_id
			result.append(e)
	return result

func restore_shop_state(shop_data: Dictionary) -> void:
	for shop_id in shop_data:
		var shop: ShopManager = get_shop(shop_id)
		if shop != null:
			shop.restore_stock(shop_data[shop_id])

func restore_shop_timers(timers: Array) -> void:
	for entry in timers:
		var shop_id: String = str(entry.get("shop_id", ""))
		var object_id: String = str(entry.get("object_id", ""))
		var remaining: int = maxi(1, int(entry.get("remaining_ticks", 1)))
		var repeat: int = int(entry.get("repeat", 0))
		var restock_amount: int = int(entry.get("restock_amount", 0))
		if shop_id.is_empty() or object_id.is_empty():
			continue
		var shop: ShopManager = get_shop(shop_id)
		if shop != null:
			shop.restore_restock_timer(object_id, remaining, repeat, restock_amount)

func _on_standing_changed(faction_id: String, old_value: int, new_value: int) -> void:
	var old_tier: Dictionary = FactionManager.get_tier_for_value(old_value)
	var new_tier: Dictionary = FactionManager.get_tier_for_value(new_value)
	if str(old_tier.get("name", "")) == str(new_tier.get("name", "")):
		return
	if current_region == null:
		return
	var actors_node := current_region.get_node_or_null("Actors")
	if actors_node == null:
		return
	var new_is_hostile: bool = FactionManager.is_hostile(faction_id)
	for child in actors_node.get_children():
		var npc := child as NPC
		if npc == null or npc.npc_id.is_empty():
			continue
		var factions: Array[String] = FactionManager.get_factions_for_npc(npc.npc_id)
		if not factions.has(faction_id):
			continue
		if new_is_hostile:
			npc.availability = "hostile"
		elif npc.availability == "hostile":
			npc.availability = "default"
			npc._evaluate_schedule()

func get_shop(shop_id: String) -> ShopManager:
	return _shop_registry.get(shop_id) as ShopManager

func open_panel(panel_node) -> void:
	if inventory_screen != null and inventory_screen != panel_node:
		inventory_screen.close()
	if character_panel != null and character_panel != panel_node:
		character_panel._close()
	if journal_panel != null and journal_panel != panel_node:
		journal_panel.close()
	if save_load_panel != null and save_load_panel != panel_node:
		save_load_panel.close()
	if spellbook_panel != null and spellbook_panel != panel_node:
		spellbook_panel.close()
	if shop_panel != null and shop_panel != panel_node:
		shop_panel.close()
	if healer_panel != null and healer_panel != panel_node:
		healer_panel.close()

func try_open_shop(npc: NPC) -> bool:
	if npc == null or npc._current_activity != "shopkeeper" or npc.shop_id.is_empty():
		return false
	var shop: ShopManager = get_shop(npc.shop_id)
	if shop == null:
		return false
	open_panel(shop_panel)
	shop_ui_pending = shop
	MessageLog.post(MessageRegistry.get_message("shop_greeting", {"name": npc.display_name}))
	MessageLog.post_blank()
	if shop_panel != null:
		shop_panel.open(shop, npc.display_name)
	return true

func try_open_healer(npc: NPC) -> bool:
	if npc == null or not npc.healer_service:
		return false
	var service := HealerService.new()
	service.load_from_npc(npc)
	open_panel(healer_panel)
	MessageLog.post(MessageRegistry.get_message("healer_greeting", {"name": npc.display_name}))
	MessageLog.post_blank()
	if healer_panel != null:
		healer_panel.open(service, npc.display_name)
	return true

func _action_cast_effect(params: Dictionary, _context: UseContext) -> bool:
	var effects_raw = params.get("effects", [])
	if not effects_raw is Array:
		return false
	var effects: Array = effects_raw as Array
	if effects.is_empty():
		return true
	var current_context: String = "combat" if CombatManager.in_combat else "world"
	var has_resurrect: bool = false
	for e in effects:
		if e is Dictionary and str(e.get("effect_type", "")) == "resurrect":
			has_resurrect = true
			break
	var player_node: Node = null
	if current_region != null:
		player_node = current_region.get_node_or_null("Actors/Player")
	if has_resurrect and not CombatManager.in_combat:
		var downed := PartyManager.get_downed_members()
		if downed.is_empty():
			MessageLog.post(MessageRegistry.get_message("resurrect_no_target"))
			MessageLog.post_blank()
			return true
		var effects_copy: Array = effects.duplicate(true)
		if downed.size() == 1:
			SpellManager._resurrect_target = downed[0]
			var res_exec := SpellEffectExecutor.new()
			res_exec.execute_effects(effects_copy, player_node, null, Vector2i.ZERO, current_context)
		elif player_node != null and player_node.has_method("prompt_party_member_for_resurrect"):
			player_node.prompt_party_member_for_resurrect(
				func(member: PartyMember):
					SpellManager._resurrect_target = member
					var res_exec := SpellEffectExecutor.new()
					res_exec.execute_effects(effects_copy, player_node, null, Vector2i.ZERO, current_context),
				func(): pass
			)
		return true
	var exec := SpellEffectExecutor.new()
	exec.execute_effects(effects, player_node, null, Vector2i.ZERO, current_context)
	return true

func _on_world_tick(_total: int) -> void:
	if not CombatManager.in_combat and current_region != null and PartyManager.is_party_wiped():
		CombatManager.show_mortis()
	if hazard_processor == null or CombatManager.in_combat:
		return
	var current_tile: Vector2i = player_tile
	if current_tile != _hazard_last_player_tile:
		_hazard_last_player_tile = current_tile
		for member in PartyManager.get_living_members():
			hazard_processor.process_tile_entry(member, current_tile)
	else:
		for member in PartyManager.get_living_members():
			hazard_processor.process_tile_tick(member, current_tile)

func _action_damage_target(params: Dictionary, context: UseContext) -> bool:
	if context.target == null or not context.target is Object:
		return false
	var damage: int = int(params.get("damage", 0))
	if damage <= 0:
		return false
	var sb = (context.target as Object).get("stat_block")
	if sb == null:
		return false
	sb.modify_stat("hp", -damage)
	return true

func _on_time_period_changed(period: String) -> void:
	match period:
		"dawn": _on_dawn()
		"day": _on_day()
		"dusk": _on_dusk()
		"night": _on_night()

func _on_dawn() -> void:
	MessageLog.post(MessageRegistry.get_message("time_dawn"))

func _on_day() -> void:
	MessageLog.post(MessageRegistry.get_message("time_day"))

func _on_dusk() -> void:
	MessageLog.post(MessageRegistry.get_message("time_dusk"))

func _on_night() -> void:
	MessageLog.post(MessageRegistry.get_message("time_night"))

func _on_season_changed(season: String) -> void:
	match season:
		"Spring": _on_spring()
		"Summer": _on_summer()
		"Autumn": _on_autumn()
		"Winter": _on_winter()

func _on_spring() -> void:
	MessageLog.post(MessageRegistry.get_message("season_spring"))

func _on_summer() -> void:
	MessageLog.post(MessageRegistry.get_message("season_summer"))

func _on_autumn() -> void:
	MessageLog.post(MessageRegistry.get_message("season_autumn"))

func _on_winter() -> void:
	MessageLog.post(MessageRegistry.get_message("season_winter"))

func build_combat_variables(
	attacker_stats: StatBlock,
	attacker_inventory,
	defender_stats: StatBlock,
	defender_inventory
) -> Dictionary:
	var vars: Dictionary = {}
	_append_stat_vars(vars, "attacker", attacker_stats)
	_append_inventory_vars(vars, "attacker", attacker_inventory)
	_append_stat_vars(vars, "defender", defender_stats)
	_append_inventory_vars(vars, "defender", defender_inventory)
	return vars

func _append_stat_vars(vars: Dictionary, prefix: String, stats: StatBlock) -> void:
	if stats == null:
		return
	for entry in stats.get_all_stats():
		var stat_id: String = str(entry.get("id", ""))
		if stat_id.is_empty():
			continue
		vars[prefix + "_" + stat_id] = stats.get_effective_value(stat_id)

func _append_inventory_vars(vars: Dictionary, prefix: String, inventory) -> void:
	var base_damage: float = 0.0
	var base_armor: float = 0.0
	if prefix == "attacker":
		vars["attacker_ammo_damage"] = 0.0
	if inventory != null:
		var equipped: Array = inventory.get_equipped_items()
		var has_ranged_weapon: bool = false
		for item in equipped:
			var data: Dictionary = item.get("data", {})
			var bd = data.get("base_damage")
			var ba = data.get("base_armor")
			if bd != null:
				base_damage += float(bd)
			if ba != null:
				base_armor += float(ba)
			if data.get("type", "") == "weapon" and data.get("ammo_type") != null:
				has_ranged_weapon = true
		if prefix == "attacker" and has_ranged_weapon:
			var quiver_item: Dictionary = inventory.get_item_in_slot("quiver")
			if not quiver_item.is_empty():
				var qbd = quiver_item.get("data", {}).get("base_damage")
				if qbd != null:
					vars["attacker_ammo_damage"] = float(qbd)
	vars[prefix + "_base_damage"] = base_damage
	vars[prefix + "_base_armor"] = base_armor

func _action_toggle_passability(_params: Dictionary, context: UseContext) -> bool:
	if not context.target is WorldObject:
		return false
	var obj: WorldObject = context.target
	if obj.is_locked:
		MessageLog.post(MessageRegistry.get_message("lock_door_locked"))
		MessageLog.post_blank()
		return false
	obj.toggle()
	var obj_name: String = obj.get_display_name()
	if obj.is_open:
		MessageLog.post(MessageRegistry.get_message("door_opened", {"name": obj_name}))
	else:
		MessageLog.post(MessageRegistry.get_message("door_closed", {"name": obj_name}))
	MessageLog.post_blank()
	return true

func _action_trigger_targets(params: Dictionary, context: UseContext) -> bool:
	if not context.target is WorldObject:
		return false
	var obj: WorldObject = context.target
	for target_id in obj.targets:
		var target_obj: WorldObject = get_object_by_instance_id(str(target_id))
		if target_obj == null:
			push_error("GameManager: trigger target not found: " + str(target_id))
			continue
		if target_obj.toggleable:
			target_obj.toggle()
	var msg: String = str(params.get("message", ""))
	if not msg.is_empty():
		MessageLog.post(msg)
	MessageLog.post_blank()
	return true

func _action_toggle_container(_params: Dictionary, context: UseContext) -> bool:
	if not context.target is WorldObject:
		return false
	var obj: WorldObject = context.target
	var obj_name: String = obj.get_display_name()
	if obj.container_open:
		WorldState.close_container(obj.object_tile)
		obj.container_open = false
		MessageLog.post(MessageRegistry.get_message("container_closes", {"name": obj_name}))
	else:
		WorldState.open_container(obj.object_tile)
		obj.container_open = true
		for content_id in obj._content_ids:
			spawn_object(content_id, obj.object_tile)
		obj._content_ids.clear()
		MessageLog.post(MessageRegistry.get_message("container_opens", {"name": obj_name}))
	MessageLog.post_blank()
	return true

func _action_apply_modifier(params: Dictionary, context: UseContext) -> bool:
	var mod_id: String = str(params.get("modifier_id", ""))
	if mod_id.is_empty():
		return false
	var source_id: String = ""
	if context.target is Dictionary:
		source_id = str(context.target.get("object_id", ""))
	elif context.target is WorldObject:
		source_id = (context.target as WorldObject).object_id
	if PlayerStats.stat_block.has_modifier_def(mod_id):
		PlayerStats.stat_block.apply_modifier(mod_id, source_id)
		return true
	push_warning("GameManager: unrecognized modifier_id '" + mod_id + "'")
	return false

func _action_learn_spell(_params: Dictionary, context: UseContext) -> bool:
	var spell_id: String = ""
	if context.target is WorldObject:
		spell_id = (context.target as WorldObject).spell_id
	elif context.target is Dictionary:
		spell_id = str(context.target.get("data", {}).get("spell_id", ""))
	if spell_id.is_empty() or spell_id == "null":
		MessageLog.post(MessageRegistry.get_message("spell_no_spell_on_scroll"))
		MessageLog.post_blank()
		return false
	if not SpellManager.has_spell(spell_id):
		push_error("GameManager: learn_spell: unrecognized spell_id '" + spell_id + "'")
		MessageLog.post(MessageRegistry.get_message("spell_unknown_spell"))
		MessageLog.post_blank()
		return false
	var spell: Dictionary = SpellManager.get_spell(spell_id)
	var spell_name: String = str(spell.get("name", spell_id))
	if not SpellManager.know_spell(spell_id):
		MessageLog.post(MessageRegistry.get_message("spell_already_known", {"name": spell_name}))
		MessageLog.post_blank()
		return false
	MessageLog.post(MessageRegistry.get_message("spell_learned", {"name": spell_name}))
	MessageLog.post_blank()
	return true

func _action_use_key(_params: Dictionary, context: UseContext) -> bool:
	var actor: Node = context.actor
	if not is_instance_valid(actor) or not actor.has_method("prompt_direction"):
		return false
	var key_item: Dictionary = context.target if context.target is Dictionary else {}
	actor.prompt_direction(func(dir): _resolve_use_key(dir, key_item), func(): pass)
	return true

func _resolve_use_key(dir: Vector2i, key_item: Dictionary) -> void:
	if dir == Vector2i.ZERO:
		MessageLog.post(MessageRegistry.get_message("lock_cannot_lock"))
		MessageLog.post_blank()
		return
	var target_tile := player_tile + dir
	var target_obj: WorldObject = _find_lockable_object(target_tile)
	if target_obj == null:
		MessageLog.post(MessageRegistry.get_message("lock_nothing_there"))
		MessageLog.post_blank()
		return
	var lm := LockManager.new()
	if target_obj.is_locked:
		lm.attempt_unlock(null, target_obj, key_item)
	else:
		lm.attempt_lock(null, target_obj, key_item)

func _action_use_lockpick(_params: Dictionary, context: UseContext) -> bool:
	if class_registry != null:
		var whitelist: Array = class_registry.get_equipment_whitelist(PlayerStats.current_class_id)
		if not "lockpick" in whitelist:
			MessageLog.post(MessageRegistry.get_message("equip_class_restricted"))
			MessageLog.post_blank()
			return false
	var actor: Node = context.actor
	if not is_instance_valid(actor) or not actor.has_method("prompt_direction"):
		return false
	var lockpick_item: Dictionary = context.target if context.target is Dictionary else {}
	actor.prompt_direction(func(dir): _resolve_use_lockpick(dir, lockpick_item), func(): pass)
	return true

func _resolve_use_lockpick(dir: Vector2i, lockpick_item: Dictionary) -> void:
	if dir == Vector2i.ZERO:
		MessageLog.post(MessageRegistry.get_message("lock_cannot_lock"))
		MessageLog.post_blank()
		return
	var target_tile := player_tile + dir
	var target_obj: WorldObject = _find_lockable_object(target_tile)
	if target_obj == null:
		MessageLog.post(MessageRegistry.get_message("lock_cannot_lock"))
		MessageLog.post_blank()
		return
	if not target_obj.is_locked:
		MessageLog.post(MessageRegistry.get_message("lock_not_locked"))
		MessageLog.post_blank()
		return
	var lm := LockManager.new()
	lm._lockpick_data = lockpick_item
	lm.attempt_unlock(null, target_obj)

func _find_lockable_object(tile: Vector2i) -> WorldObject:
	for obj in get_objects_at(tile):
		var wo := obj as WorldObject
		if wo != null and not wo.lock_id.is_empty():
			return wo
	return null

func _action_consume(params: Dictionary, context: UseContext) -> bool:
	if context.target is WorldObject:
		var obj: WorldObject = context.target
		WorldState.clear_object_from_tile(obj.object_tile, obj.object_id)
		obj.queue_free()
		return true
	if context.inventory == null or not context.target is Dictionary:
		return false
	var item: Dictionary = context.target
	var instance_id: int = int(item.get("instance_id", -1))
	if instance_id == -1:
		return false
	context.inventory.take_from_stack(instance_id, 1)
	var msg: String = str(params.get("message", ""))
	if not msg.is_empty():
		MessageLog.post(msg)
	MessageLog.post_blank()
	var item_data: Dictionary = item.get("data", {})
	var branch_trigger: Variant = item_data.get("quest_branch_trigger")
	if branch_trigger is Dictionary:
		var bq_id: String = str(branch_trigger.get("quest_id", ""))
		var bb_id: String = str(branch_trigger.get("branch_id", ""))
		if not bq_id.is_empty() and not bb_id.is_empty():
			QuestManager.trigger_branch(bq_id, bb_id)
	return true

func _action_modify_faction_standing(params: Dictionary, _context: UseContext) -> bool:
	var faction_id: String = str(params.get("faction_id", ""))
	var amount: int = int(params.get("amount", 0))
	if faction_id.is_empty():
		return false
	FactionManager.modify_standing(faction_id, amount)
	var faction_name: String = FactionManager.get_faction_name(faction_id)
	var tier_name: String = FactionManager.get_tier_name(faction_id)
	MessageLog.post(MessageRegistry.get_message("faction_standing_changed", {"faction": faction_name, "tier": tier_name}))
	return true

func _action_expend_charge(_params: Dictionary, context: UseContext) -> bool:
	if context.target is Dictionary:
		var item: Dictionary = context.target
		var current: int = int(item.get("charges", -1))
		if current == -1:
			return false
		current -= 1
		item["charges"] = current
		if current <= 0:
			if context.inventory != null:
				var instance_id: int = int(item.get("instance_id", -1))
				if instance_id != -1:
					context.inventory.remove_object_anywhere(instance_id)
					MessageLog.post(MessageRegistry.get_message("item_spent", {"name": Inventory.get_item_display_name(item.get("data", {}))}))
					MessageLog.post_blank()
		return true
	elif context.target is WorldObject:
		var obj: WorldObject = context.target
		if obj.charges == -1:
			return false
		obj.charges -= 1
		if obj.charges <= 0:
			WorldState.clear_object_from_tile(obj.object_tile, obj.object_id)
			obj.queue_free()
		return true
	return false

func _action_read(_params: Dictionary, context: UseContext) -> bool:
	var source: String = ""
	var object_id: String = ""
	if context.target is WorldObject:
		var obj: WorldObject = context.target
		source = obj.readable_source
		object_id = obj.object_id
	elif context.target is Dictionary:
		var item: Dictionary = context.target
		source = str(item.get("data", {}).get("readable_source", ""))
		object_id = str(item.get("object_id", ""))
	if source.is_empty():
		MessageLog.post(MessageRegistry.get_message("read_cannot"))
		MessageLog.post_blank()
		return false
	var quest_def: Dictionary = QuestManager.get_quest(source)
	if not quest_def.is_empty():
		var text: Variant = quest_def.get("readable_text")
		if text is String and not (text as String).is_empty():
			MessageLog.post(text as String)
		else:
			MessageLog.post(MessageRegistry.get_message("read_illegible"))
		MessageLog.post_blank()
		var triggers_raw: Variant = quest_def.get("triggers")
		if triggers_raw is Dictionary:
			var readable_triggers: Variant = triggers_raw.get("readable", [])
			if readable_triggers is Array:
				for rt in readable_triggers:
					if rt is Dictionary and str(rt.get("object_id", "")) == object_id:
						QuestManager.start_quest(source)
						break
	else:
		MessageLog.post(source)
		MessageLog.post_blank()
	return true

func execute_use(context: UseContext) -> void:
	var actions: Array = []
	if context.target is WorldObject:
		var obj: WorldObject = context.target
		actions = obj.use_actions
	elif context.target is Dictionary:
		var item: Dictionary = context.target
		if int(item.get("charges", -1)) != -1 and int(item.get("stack_count", 1)) > 1:
			if context.inventory != null:
				var instance_id: int = int(item.get("instance_id", -1))
				if instance_id != -1:
					var split_item: Dictionary = context.inventory.split_charged_item(instance_id)
					if not split_item.is_empty():
						context.target = split_item
						item = split_item
		actions = item.get("data", {}).get("use_actions", [])
	if actions.is_empty():
		MessageLog.post(MessageRegistry.get_message("use_nothing_happens"))
		MessageLog.post_blank()
		return
	for action_entry in actions:
		if not action_entry is Dictionary:
			continue
		var action_name: String = str(action_entry.get("action", ""))
		var params_raw: Variant = action_entry.get("params", {})
		var params: Dictionary = params_raw if params_raw is Dictionary else {}
		if use_action_registry != null:
			if not use_action_registry.execute(action_name, params, context):
				break

func _action_light_source_toggle(_params: Dictionary, context: UseContext) -> bool:
	if not context.target is Dictionary:
		return false
	var item: Dictionary = context.target
	var item_data: Dictionary = item.get("data", {})
	var light_rad: int = int(item_data.get("light_radius", 0)) if item_data.get("light_radius") != null else 0
	if light_rad <= 0:
		return false
	var instance_id: int = int(item.get("instance_id", -1))
	if instance_id == -1:
		return false
	var item_name: String = Inventory.get_item_display_name(item_data)
	var duration_def: int = int(item_data.get("duration", -1)) if item_data.get("duration") != null else -1

	if not PlayerInventory._light_states.has(instance_id):
		PlayerInventory._light_states[instance_id] = {
			"is_lit": false,
			"duration_remaining": duration_def,
			"handle": -1,
			"radius": light_rad
		}
	var state: Dictionary = PlayerInventory._light_states[instance_id]

	if state.get("is_lit", false):
		state["is_lit"] = false
		var handle: int = state.get("handle", -1)
		if handle >= 0:
			GameTime.cancel(handle)
		state["handle"] = -1
		PlayerInventory._recalculate_light_modifier()
		MessageLog.post(MessageRegistry.get_message("light_extinguished", {"name": item_name}))
		MessageLog.post_blank()
	else:
		var dur_remaining: int = state.get("duration_remaining", duration_def)
		if duration_def == 0 or dur_remaining == 0:
			MessageLog.post(MessageRegistry.get_message("light_burnout_spent", {"name": item_name}))
			MessageLog.post_blank()
			return false
		state["is_lit"] = true
		state["duration_remaining"] = dur_remaining
		if duration_def != -1:
			var handle: int = GameTime.schedule(_on_light_duration_tick.bind(instance_id), 1, 1)
			state["handle"] = handle
		PlayerInventory._recalculate_light_modifier()
		MessageLog.post(MessageRegistry.get_message("light_lit", {"name": item_name}))
		MessageLog.post_blank()
	return true

func _on_light_duration_tick(instance_id: int) -> void:
	if not PlayerInventory._light_states.has(instance_id):
		return
	var state: Dictionary = PlayerInventory._light_states[instance_id]
	if not state.get("is_lit", false):
		return
	state["duration_remaining"] = state.get("duration_remaining", 0) - 1
	if state.get("duration_remaining", 0) <= 0:
		var handle: int = state.get("handle", -1)
		if handle >= 0:
			GameTime.cancel(handle)
		state["handle"] = -1
		state["is_lit"] = false
		PlayerInventory._recalculate_light_modifier()
		var item: Dictionary = PlayerInventory.get_object_by_instance(instance_id)
		var item_name: String = Inventory.get_item_display_name(item.get("data", {})) if not item.is_empty() else "item"
		MessageLog.post(MessageRegistry.get_message("light_burnout", {"name": item_name}))
		MessageLog.post_blank()
		PlayerInventory.remove_object_anywhere(instance_id)

func apply_class_starting_stats(class_id: String) -> void:
	if class_registry == null or not class_registry.has_class(class_id):
		push_error("GameManager: class not found: " + class_id)
		return
	var starting_stats: Dictionary = class_registry.get_starting_stats(class_id)
	for stat_id in starting_stats:
		if PlayerStats.has_stat(stat_id):
			PlayerStats.stat_block.set_stat(stat_id, int(starting_stats[stat_id]))
	PlayerStats.set_current_class(class_id)

func apply_class_change(new_class_id: String) -> void:
	if class_registry == null or not class_registry.has_class(new_class_id):
		push_error("GameManager: apply_class_change — unknown class_id: " + new_class_id)
		return
	PlayerInventory.force_unequip_restricted(new_class_id)
	PlayerStats.set_current_class(new_class_id)
	var cls_name: String = str(class_registry.get_class_data(new_class_id).get("name", new_class_id))
	MessageLog.post(MessageRegistry.get_message("class_changed", {"name": cls_name}))
	SaveManager._update_save_slot_class(new_class_id)

func deposit_into_container(tile: Vector2i, object_id: String, _instance: Dictionary) -> bool:
	var world_objs := get_objects_at(tile)
	if world_objs.is_empty():
		return false
	var container: Node = world_objs.back()
	if container.object_type != "container":
		return false
	if container.container_slots != -1 and container._content_ids.size() >= container.container_slots:
		return false
	container._content_ids.append(object_id)
	return true
