extends Node


var current_region: Node = null
var player_tile: Vector2i = Vector2i.ZERO
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
var journal_panel = null
var tile_registry: TileRegistry = null
var region_cache: RegionCache = null
var combat_resolver: CombatResolver = null
var level_manager: LevelManager = null
var world_paused: bool = false
var _world_corpses: Dictionary = {}   # Node2D -> { spawn_tick, expiry_tick, display_name }
var _carried_corpses: Dictionary = {} # inventory instance_id (int) -> { spawn_tick, elapsed_at_pickup, display_name }

var use_action_registry: UseActionRegistry = null
var debug_mode: bool = false

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
	var raw_decay = data.get("corpse_decay_ticks", 0)
	_corpse_decay_ticks = int(raw_decay) if raw_decay != null else 0
	var raw_path = data.get("npc_max_path_length", 0)
	npc_max_path_length = int(raw_path) if raw_path != null else 0
	var raw_msg = data.get("not_talkable_default")
	if raw_msg is String:
		not_talkable_default = raw_msg
	level_manager = LevelManager.new()
	var raw_thresholds = data.get("level_thresholds", [])
	var raw_gains = data.get("stat_gains_per_level", {})
	if raw_thresholds is Array and raw_gains is Dictionary:
		level_manager.load_config(raw_thresholds, raw_gains)

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
		QuestManager.check_region_entry_triggers(region_id)
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
	loader.register_spawns(region_data)
	loader.load_waypoints(region_data)
	loader.spawn_npcs(region_data, current_region)
	loader.spawn_objects(region_data)
	loader.apply_npc_schedule_placement(current_region)
	_register_transitions(region_data)
	loader.load_tile_triggers(region_data)

func _restore_from_cache(region_id: String, loader: RegionLoader) -> void:
	var snapshot := region_cache.restore_region(region_id)
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

	_register_transitions(region_data)
	loader.load_tile_triggers(region_data)

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
				"_content_ids": wo._content_ids.duplicate()
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
			npcs_snapshot.append({
				"npc_id": npc.npc_id,
				"tile": [npc.npc_tile.x, npc.npc_tile.y]
			})
	snapshot["npcs"] = npcs_snapshot

	return snapshot

func _snapshot_and_unload() -> void:
	region_cache.store_region(_current_region_id, _snapshot_region())
	WorldState.clear_all_occupants()
	WorldState.clear_all_objects()
	_object_instances.clear()
	_world_corpses.clear()
	current_region.queue_free()
	current_region = null
	_current_region_id = ""

func _clear_region() -> void:
	WorldState.clear_all_occupants()
	WorldState.clear_all_objects()
	_object_instances.clear()
	_world_corpses.clear()
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

const _REGION_SCENE_PATHS: Dictionary = {
	"combat_arena": "res://scenes/combat/CombatArena.tscn",
	"town":         "res://scenes/world/Town.tscn",
	"wilderness":   "res://scenes/world/Wilderness.tscn"
}

func _region_id_to_scene_path(region_id: String) -> String:
	if _REGION_SCENE_PATHS.has(region_id):
		return _REGION_SCENE_PATHS[region_id]
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
	if _corpse_decay_ticks > 0:
		var handle: int = GameTime.schedule(_expire_corpse.bind(world_object), _corpse_decay_ticks)
		_world_corpses[world_object] = {
			"spawn_tick": GameTime.total_ticks,
			"handle": handle,
			"display_name": corpse_display_name
		}

func on_corpse_picked_up(world_obj: Node2D, inventory_instance_id: int) -> void:
	var spawn_tick: int = GameTime.total_ticks
	var display_name: String = world_obj.instance_display_name
	if _world_corpses.has(world_obj):
		var entry: Dictionary = _world_corpses[world_obj]
		spawn_tick = entry["spawn_tick"]
		display_name = entry["display_name"]
		GameTime.cancel(entry["handle"])
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
	var packed := load(Constants.WORLD_OBJECT_SCENE_PATH) as PackedScene
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
			var handle: int = GameTime.schedule(_expire_corpse.bind(world_object), max(remaining, 1))
			_world_corpses[world_object] = {
				"spawn_tick": GameTime.total_ticks,
				"handle": handle,
				"display_name": display_name
			}
	else:
		world_object.instance_display_name = "corpse"
	objects_node.add_child(world_object)

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

func is_tile_transparent(tile: Vector2i) -> bool:
	var type_id := _get_tile_type_id(tile)
	if not type_id.is_empty() and tile_registry != null and not tile_registry.is_transparent(type_id):
		return false
	for object_id in WorldState.get_objects_at(tile):
		var data := PlayerInventory.get_object_data(object_id)
		if not data.get("transparent", true):
			return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_character_panel"):
		if character_panel != null:
			if not character_panel.panel.visible and journal_panel != null:
				journal_panel.close()
			character_panel.toggle()
	if event.is_action_pressed("toggle_journal"):
		if journal_panel != null:
			if not journal_panel.panel.visible and character_panel != null:
				character_panel._close()
			journal_panel.toggle()

func _ready() -> void:
	_load_config()
	slot_registry = SlotRegistry.new()
	slot_registry.load_from_file(Constants.SLOTS_CONFIG_PATH)
	tile_registry = TileRegistry.new()
	tile_registry.load_from_file(Constants.TILES_CONFIG_PATH)
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
	use_action_registry.register("expend_charge", _action_expend_charge)
	use_action_registry.register("read", _action_read)

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
	obj.toggle()
	var obj_name: String = PlayerInventory.get_object_data(obj.object_id).get("name", obj.object_id)
	if obj.is_open:
		MessageLog.post("You open the " + obj_name + ".")
	else:
		MessageLog.post("You close the " + obj_name + ".")
	MessageLog.post("")
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
	MessageLog.post("")
	return true

func _action_toggle_container(_params: Dictionary, context: UseContext) -> bool:
	if not context.target is WorldObject:
		return false
	var obj: WorldObject = context.target
	var obj_name: String = PlayerInventory.get_object_data(obj.object_id).get("name", obj.object_id)
	if obj.container_open:
		WorldState.close_container(obj.object_tile)
		obj.container_open = false
		MessageLog.post("The " + obj_name + " closes.")
	else:
		WorldState.open_container(obj.object_tile)
		obj.container_open = true
		for content_id in obj._content_ids:
			spawn_object(content_id, obj.object_tile)
		obj._content_ids.clear()
		MessageLog.post("The " + obj_name + " opens.")
	MessageLog.post("")
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

func _action_consume(params: Dictionary, context: UseContext) -> bool:
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
	MessageLog.post("")
	var item_data: Dictionary = item.get("data", {})
	var branch_trigger: Variant = item_data.get("quest_branch_trigger")
	if branch_trigger is Dictionary:
		var bq_id: String = str(branch_trigger.get("quest_id", ""))
		var bb_id: String = str(branch_trigger.get("branch_id", ""))
		if not bq_id.is_empty() and not bb_id.is_empty():
			QuestManager.trigger_branch(bq_id, bb_id)
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
					MessageLog.post("The " + str(item.get("data", {}).get("name", "item")) + " is spent.")
					MessageLog.post("")
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
		MessageLog.post("You cannot read that.")
		MessageLog.post("")
		return false
	var quest_def: Dictionary = QuestManager.get_quest(source)
	if not quest_def.is_empty():
		var text: Variant = quest_def.get("readable_text")
		if text is String and not (text as String).is_empty():
			MessageLog.post(text as String)
		else:
			MessageLog.post("The text is illegible.")
		MessageLog.post("")
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
		MessageLog.post("")
	return true

func _execute_use(context: UseContext) -> void:
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
		MessageLog.post("Nothing happens.")
		MessageLog.post("")
		return
	for action_entry in actions:
		if not action_entry is Dictionary:
			continue
		var action_name: String = str(action_entry.get("action", ""))
		var params_raw: Variant = action_entry.get("params", {})
		var params: Dictionary = params_raw if params_raw is Dictionary else {}
		if use_action_registry != null:
			use_action_registry.execute(action_name, params, context)

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
