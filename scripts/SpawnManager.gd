class_name SpawnManager
extends RefCounted

var _active_spawns: Array = []
var _spawn_config: Dictionary = {}
var _spawn_timer_handle: int = -1
var _passable_tile_cache: Array[Vector2i] = []

var _quest_spawns: Dictionary = {}       # instance_id -> {npc_node, region_id, npc_id, tile}
var _pending_quest_spawns: Array = []    # spawn_effects queued for other regions

# ── Random spawn ─────────────────────────────────────────────────────────────

func load_config(config: Dictionary) -> void:
	if _spawn_timer_handle >= 0:
		GameTime.cancel(_spawn_timer_handle)
		_spawn_timer_handle = -1
	_spawn_config = config
	if config.is_empty():
		return
	var rate: int = maxi(1, int(config.get("spawn_rate_ticks", 300)))
	_spawn_timer_handle = GameTime.schedule(_on_spawn_tick, rate, rate)

func _on_spawn_tick() -> void:
	attempt_spawn()

func attempt_spawn() -> void:
	_active_spawns = _active_spawns.filter(func(n) -> bool: return is_instance_valid(n))
	var max_spawns: int = int(_spawn_config.get("max_spawns", 5))
	if _active_spawns.size() >= max_spawns:
		return
	var npc_id: String = _pick_spawn_npc_id()
	if npc_id.is_empty():
		return
	var spawn_tile: Vector2i = _pick_spawn_tile()
	if spawn_tile == Vector2i(-1, -1):
		return
	if GameManager.current_region == null:
		return
	var actors_node: Node = GameManager.current_region.get_node_or_null("Actors")
	var npc_scene := load(Constants.NPC_SCENE_PATH) as PackedScene
	if actors_node == null or npc_scene == null:
		return
	var npc := npc_scene.instantiate()
	npc.npc_id = npc_id
	npc.npc_tile = spawn_tile
	npc.is_spawned_monster = true
	actors_node.add_child(npc)
	npc.availability = "hostile"
	_active_spawns.append(npc)

func get_active_spawn_count() -> int:
	_active_spawns = _active_spawns.filter(func(n) -> bool: return is_instance_valid(n))
	return _active_spawns.size()

func on_spawn_killed(npc_node: Node) -> void:
	_active_spawns.erase(npc_node)

func on_region_exit(region_id: String) -> void:
	for spawn in _active_spawns:
		if not is_instance_valid(spawn):
			continue
		var npc := spawn as NPC
		if npc != null:
			WorldState.clear_occupant(npc.npc_tile)
		(spawn as Node).queue_free()
	_active_spawns.clear()
	if _spawn_timer_handle >= 0:
		GameTime.cancel(_spawn_timer_handle)
		_spawn_timer_handle = -1
	_spawn_config = {}
	_passable_tile_cache = []
	for instance_id in _quest_spawns:
		if str(_quest_spawns[instance_id].get("region_id", "")) == region_id:
			_quest_spawns[instance_id]["npc_node"] = null

func clear_all_spawns() -> void:
	for spawn in _active_spawns:
		if not is_instance_valid(spawn):
			continue
		var npc := spawn as NPC
		if npc != null:
			WorldState.clear_occupant(npc.npc_tile)
		(spawn as Node).queue_free()
	_active_spawns.clear()
	if _spawn_timer_handle >= 0:
		GameTime.cancel(_spawn_timer_handle)
		_spawn_timer_handle = -1
	_spawn_config = {}
	_passable_tile_cache = []
	for instance_id in _quest_spawns:
		var entry: Dictionary = _quest_spawns[instance_id]
		var node = entry.get("npc_node")
		if node != null and is_instance_valid(node):
			var npc := node as NPC
			if npc != null:
				WorldState.clear_occupant(npc.npc_tile)
			(node as Node).queue_free()
	_quest_spawns.clear()
	_pending_quest_spawns.clear()

func spawn_for_rest_interrupt() -> Array:
	if _spawn_config.is_empty():
		return []
	var npc_id: String = _pick_spawn_npc_id()
	if npc_id.is_empty():
		return []
	return [{"npc_id": npc_id}]

func _pick_spawn_npc_id() -> String:
	var spawn_list: Array = _spawn_config.get("spawn_list", [])
	if spawn_list.is_empty():
		return ""
	var total_weight: float = 0.0
	for entry in spawn_list:
		total_weight += float(entry.get("weight", 1))
	if total_weight <= 0.0:
		return ""
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for entry in spawn_list:
		cumulative += float(entry.get("weight", 1))
		if roll < cumulative:
			return str(entry.get("npc_id", ""))
	return str(spawn_list.back().get("npc_id", ""))

func _pick_spawn_tile() -> Vector2i:
	var player_tile: Vector2i = GameManager.get_player_tile()
	var hw: int = Constants.MAP_TILES_WIDE >> 1
	var hh: int = Constants.MAP_TILES_TALL >> 1
	var vp_min_x: int = player_tile.x - hw
	var vp_max_x: int = player_tile.x + hw
	var vp_min_y: int = player_tile.y - hh
	var vp_max_y: int = player_tile.y + hh
	var candidates: Array[Vector2i] = []
	for x in range(vp_min_x, vp_max_x + 1):
		candidates.append(Vector2i(x, vp_min_y))
		candidates.append(Vector2i(x, vp_max_y))
	for y in range(vp_min_y + 1, vp_max_y):
		candidates.append(Vector2i(vp_min_x, y))
		candidates.append(Vector2i(vp_max_x, y))
	var valid: Array[Vector2i] = []
	for tile in candidates:
		if _is_valid_spawn_tile(tile):
			valid.append(tile)
	if valid.is_empty():
		return Vector2i(-1, -1)
	return valid[randi() % valid.size()]

func build_passable_cache() -> void:
	_passable_tile_cache = []
	var bounds: Rect2i = GameManager.get_region_bounds()
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var tile := Vector2i(x, y)
			if GameManager.is_tile_passable(tile):
				_passable_tile_cache.append(tile)

func _pick_random_passable_tile() -> Vector2i:
	var player_tile: Vector2i = GameManager.get_player_tile()
	var valid: Array[Vector2i] = []
	for tile in _passable_tile_cache:
		if tile != player_tile:
			valid.append(tile)
	if valid.is_empty():
		return Vector2i(-1, -1)
	return valid[randi() % valid.size()]

func _is_valid_spawn_tile(tile: Vector2i) -> bool:
	var bounds: Rect2i = GameManager.get_region_bounds()
	if not bounds.has_point(tile):
		return false
	if tile == GameManager.get_player_tile():
		return false
	if not GameManager.is_tile_passable(tile):
		return false
	return true

# ── Quest spawn ──────────────────────────────────────────────────────────────

func handle_quest_spawn(spawn_effect: Dictionary) -> void:
	var region_id: String = str(spawn_effect.get("region_id", ""))
	if region_id.is_empty():
		push_error("SpawnManager: quest spawn effect has no region_id")
		return
	var instance_id: String = str(spawn_effect.get("instance_id", ""))
	if _quest_spawns.has(instance_id):
		return
	if region_id == GameManager.get_current_region_id():
		execute_quest_spawn(spawn_effect)
	else:
		if not _is_pending(instance_id):
			_pending_quest_spawns.append(spawn_effect.duplicate())

func _is_pending(instance_id: String) -> bool:
	for effect in _pending_quest_spawns:
		if str(effect.get("instance_id", "")) == instance_id:
			return true
	return false

func execute_quest_spawn(spawn_effect: Dictionary) -> void:
	if GameManager.current_region == null:
		return
	var npc_id: String = str(spawn_effect.get("npc_id", ""))
	var instance_id: String = str(spawn_effect.get("instance_id", ""))
	var region_id: String = str(spawn_effect.get("region_id", GameManager.get_current_region_id()))
	if npc_id.is_empty() or instance_id.is_empty():
		push_error("SpawnManager: quest spawn missing npc_id or instance_id")
		return
	if _quest_spawns.has(instance_id):
		return
	var spawn_tile: Vector2i = _resolve_quest_spawn_tile(spawn_effect)
	if spawn_tile == Vector2i(-1, -1):
		push_error("SpawnManager: could not resolve tile for quest spawn: " + instance_id)
		return
	var actors_node: Node = GameManager.current_region.get_node_or_null("Actors")
	var npc_scene := load(Constants.NPC_SCENE_PATH) as PackedScene
	if actors_node == null or npc_scene == null:
		return
	var npc := npc_scene.instantiate()
	npc.npc_id = npc_id
	npc.npc_tile = spawn_tile
	npc.is_quest_spawn = true
	npc.quest_spawn_instance_id = instance_id
	actors_node.add_child(npc)
	npc.availability = "hostile"
	_quest_spawns[instance_id] = {
		"npc_node":  npc,
		"region_id": region_id,
		"npc_id":    npc_id,
		"tile":      [spawn_tile.x, spawn_tile.y]
	}

func _resolve_quest_spawn_tile(spawn_effect: Dictionary) -> Vector2i:
	var location_type: String = str(spawn_effect.get("location_type", "random"))
	var location: Variant = spawn_effect.get("location")
	match location_type:
		"fixed":
			if location is Array and (location as Array).size() >= 2:
				return Vector2i(int((location as Array)[0]), int((location as Array)[1]))
			return Vector2i(-1, -1)
		"waypoint":
			var waypoint_name: String = str(location) if location != null else ""
			if waypoint_name.is_empty():
				push_warning("SpawnManager: waypoint location_type with empty name, falling back to random")
				return _pick_random_passable_tile()
			if GameManager.waypoint_manager == null:
				return _pick_random_passable_tile()
			if not GameManager.waypoint_manager.has_waypoint(waypoint_name):
				push_warning("SpawnManager: waypoint not found: " + waypoint_name + ", falling back to random")
				return _pick_random_passable_tile()
			return GameManager.waypoint_manager.get_waypoint(waypoint_name)
		_:
			return _pick_random_passable_tile()

func execute_pending_for_region(region_id: String) -> void:
	var to_execute: Array = []
	var remaining: Array = []
	for effect in _pending_quest_spawns:
		if str(effect.get("region_id", "")) == region_id:
			to_execute.append(effect)
		else:
			remaining.append(effect)
	_pending_quest_spawns = remaining
	for effect in to_execute:
		execute_quest_spawn(effect)

func on_quest_spawn_killed(instance_id: String) -> void:
	_quest_spawns.erase(instance_id)

func reregister_quest_spawn(instance_id: String, npc_node: NPC, tile: Vector2i) -> void:
	if _quest_spawns.has(instance_id):
		_quest_spawns[instance_id]["npc_node"] = npc_node
		_quest_spawns[instance_id]["tile"] = [tile.x, tile.y]
	else:
		_quest_spawns[instance_id] = {
			"npc_node":  npc_node,
			"region_id": GameManager.get_current_region_id(),
			"npc_id":    npc_node.npc_id,
			"tile":      [tile.x, tile.y]
		}

func get_active_quest_spawn_count() -> int:
	return _quest_spawns.size()

func get_serializable_quest_spawns() -> Dictionary:
	var active: Array = []
	for instance_id in _quest_spawns:
		var entry: Dictionary = _quest_spawns[instance_id]
		var tile_arr: Array = entry.get("tile", [0, 0])
		var npc_node = entry.get("npc_node")
		if npc_node != null and is_instance_valid(npc_node):
			var npc := npc_node as NPC
			if npc != null:
				tile_arr = [npc.npc_tile.x, npc.npc_tile.y]
		active.append({
			"instance_id": instance_id,
			"npc_id":      str(entry.get("npc_id", "")),
			"region_id":   str(entry.get("region_id", "")),
			"tile":        tile_arr
		})
	var pending: Array = []
	for effect in _pending_quest_spawns:
		if effect is Dictionary:
			pending.append((effect as Dictionary).duplicate())
	return {"active": active, "pending": pending}

func restore_quest_spawns(data: Dictionary) -> void:
	_quest_spawns.clear()
	_pending_quest_spawns.clear()
	for entry in data.get("active", []):
		if not entry is Dictionary:
			continue
		var instance_id: String = str(entry.get("instance_id", ""))
		var npc_id: String = str(entry.get("npc_id", ""))
		var region_id: String = str(entry.get("region_id", ""))
		var tile_raw: Variant = entry.get("tile", [0, 0])
		if instance_id.is_empty() or npc_id.is_empty() or region_id.is_empty():
			continue
		_pending_quest_spawns.append({
			"instance_id":   instance_id,
			"npc_id":        npc_id,
			"region_id":     region_id,
			"location_type": "fixed",
			"location":      tile_raw
		})
	for effect in data.get("pending", []):
		if effect is Dictionary:
			_pending_quest_spawns.append((effect as Dictionary).duplicate())
