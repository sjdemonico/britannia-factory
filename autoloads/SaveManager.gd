extends Node

const MAX_AUTOSAVES: int = 5

var _pending_data: Dictionary = {}
var _pending_player_tile: Vector2i = Vector2i(-1, -1)

# ── Public API ───────────────────────────────────────────────────────────────

func save(slot_id: int, player_name: String = "") -> bool:
	_ensure_saves_dir()
	var save_name: String = player_name if not player_name.is_empty() else PlayerStats.display_name
	var data := _serialize_all(slot_id, save_name, false)
	_write_save(slot_id, data)
	_update_index(slot_id, save_name, false)
	return true

func autosave() -> bool:
	_ensure_saves_dir()
	_rotate_autosaves()
	var slot_id := _next_slot_id()
	var data := _serialize_all(slot_id, PlayerStats.display_name, true)
	_write_save(slot_id, data)
	_update_index(slot_id, PlayerStats.display_name, true)
	return true

func load_save(slot_id: int) -> bool:
	var save_path := Constants.SAVES_DIR + str(slot_id) + ".json"
	if not FileAccess.file_exists(save_path):
		push_error("SaveManager: save file not found: " + save_path)
		return false
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_error("SaveManager: cannot open save: " + save_path)
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("SaveManager: JSON parse error in save " + str(slot_id))
		file.close()
		return false
	file.close()
	var data: Variant = json.get_data()
	if not data is Dictionary:
		push_error("SaveManager: save data is not a Dictionary")
		return false
	var version: int = int((data as Dictionary).get("save_version", 0))
	if version != Constants.SAVE_VERSION:
		push_error("SaveManager: save version mismatch (got %d, expected %d)" % [version, Constants.SAVE_VERSION])
		return false
	if GameManager.sub_viewport != null:
		_reset_all_state()
		_deserialize_all(data)
	else:
		_pending_data = data
		get_tree().change_scene_to_file("res://scenes/ui/HUD.tscn")
	return true

func get_save_index() -> Array:
	if not FileAccess.file_exists(Constants.SAVE_INDEX_PATH):
		return []
	var file := FileAccess.open(Constants.SAVE_INDEX_PATH, FileAccess.READ)
	if file == null:
		return []
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return []
	file.close()
	var data: Variant = json.get_data()
	if not data is Dictionary:
		return []
	var saves: Variant = data.get("saves", [])
	return saves if saves is Array else []

func delete_save(slot_id: int) -> void:
	var dir := DirAccess.open(Constants.SAVES_DIR)
	if dir != null:
		dir.remove(str(slot_id) + ".json")
	_remove_from_index(slot_id)

func get_next_slot_id() -> int:
	return _next_slot_id()

func rename_save(slot_id: int, new_name: String) -> bool:
	var save_path := Constants.SAVES_DIR + str(slot_id) + ".json"
	if not FileAccess.file_exists(save_path):
		return false
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return false
	file.close()
	var data: Variant = json.get_data()
	if not data is Dictionary:
		return false
	(data as Dictionary)["player_name"] = new_name
	_write_save(slot_id, data)
	var index: Dictionary = _read_index()
	var saves: Array = []
	var raw: Variant = index.get("saves", [])
	if raw is Array:
		for s in raw:
			if s is Dictionary:
				if int(s.get("slot_id", -1)) == slot_id:
					s["player_name"] = new_name
				saves.append(s)
	index["saves"] = saves
	_write_index(index)
	return true

func _apply_pending_load() -> void:
	if _pending_data.is_empty():
		return
	var data: Dictionary = _pending_data
	_pending_data = {}
	_deserialize_all(data)

# ── Deserialization ──────────────────────────────────────────────────────────

func _reset_all_state() -> void:
	_pending_player_tile = Vector2i(-1, -1)

	# Reset inventory (clears objects, equipped slots, and modifier applications)
	PlayerInventory.get_inventory().restore_objects([])
	PlayerInventory.equip_changed.emit()

	# Reset stat block to base values (also clears all applied modifiers)
	PlayerStats.stat_block.load_from_file(Constants.STATS_DATA_PATH + "player.json")

	# Clear quest state and cancel all scheduled handles
	QuestManager.restore_from_state({})

	# Clear region cache (full snapshots and diff entries)
	if GameManager.region_cache != null:
		GameManager.region_cache.clear()

	# Clear WorldState occupancy and object maps
	WorldState.clear_all_occupants()
	WorldState.clear_all_objects()

	# Null out references to freed region nodes
	GameManager.waypoint_manager = null
	GameManager.objects_node = null

	# Unload current region without snapshotting
	if GameManager.current_region != null:
		GameManager.current_region.queue_free()
		GameManager.current_region = null
	GameManager._current_region_id = ""
	GameManager._object_instances.clear()
	GameManager._world_corpses.clear()

func _deserialize_all(data: Dictionary) -> void:
	_deserialize_game_time(data.get("game_time", {}))
	_deserialize_player(data.get("player", {}))
	_deserialize_inventory(data.get("inventory", []), PlayerInventory.get_inventory())
	_deserialize_quest_state(data.get("quest_state", {}), data.get("game_time", {}))
	_deserialize_region_diffs(data.get("region_diffs", []))

	var raw_region: Variant = data.get("current_region", "")
	var region_id: String = raw_region if raw_region is String and not (raw_region as String).is_empty() else GameManager.starting_region
	GameManager.load_region(region_id)

	if _pending_player_tile != Vector2i(-1, -1) and GameManager.current_region != null:
		var player_node := GameManager.current_region.get_node_or_null("Actors/Player")
		if player_node != null:
			player_node.teleport_to_tile(_pending_player_tile)
	_pending_player_tile = Vector2i(-1, -1)

func _deserialize_game_time(data: Dictionary) -> void:
	if data.is_empty():
		return
	if data.has("total_ticks"):
		GameTime.restore_ticks(int(data["total_ticks"]))

func _deserialize_player(data: Dictionary) -> void:
	if data.is_empty():
		return
	var name_raw: Variant = data.get("display_name")
	if name_raw is String:
		PlayerStats.display_name = name_raw as String
	var stats: Dictionary = data.get("stats", {})
	for stat_id in stats:
		if not PlayerStats.stat_block.is_derived(str(stat_id)):
			PlayerStats.set_stat(str(stat_id), int(stats[stat_id]))
	var tile_raw: Variant = data.get("tile")
	if tile_raw is Array and (tile_raw as Array).size() >= 2:
		_pending_player_tile = Vector2i(int(tile_raw[0]), int(tile_raw[1]))

func _deserialize_inventory(items: Array, target: Inventory) -> void:
	if items.is_empty():
		return
	target.restore_objects(items)
	PlayerInventory.equip_changed.emit()

func _deserialize_quest_state(quest_data: Dictionary, game_time_data: Dictionary) -> void:
	if quest_data.is_empty():
		return
	QuestManager.restore_from_state(quest_data)
	QuestManager.restore_scheduled_handles(game_time_data.get("scheduled_quests", []))

func _deserialize_region_diffs(diff_list: Array) -> void:
	if GameManager.region_cache == null:
		return
	for entry in diff_list:
		if not entry is Dictionary:
			continue
		var diff := RegionDiff.new()
		diff.from_dict(entry)
		if diff.region_id.is_empty():
			continue
		GameManager.region_cache.store_diff(diff.region_id, diff)

# ── Serialization ────────────────────────────────────────────────────────────

func _serialize_all(slot_id: int, player_name: String, is_autosave: bool) -> Dictionary:
	var timestamp := Time.get_datetime_string_from_system(false, true).left(16)
	return {
		"save_version":   Constants.SAVE_VERSION,
		"slot_id":        slot_id,
		"player_name":    player_name,
		"timestamp":      timestamp,
		"autosave":       is_autosave,
		"current_region": GameManager.get_current_region_id(),
		"player":         _serialize_player(),
		"inventory":      _serialize_inventory(PlayerInventory.get_inventory()),
		"game_time":      _serialize_game_time(),
		"quest_state":    QuestManager.get_serializable_state(),
		"region_diffs":   _serialize_region_diffs()
	}

func _serialize_player() -> Dictionary:
	var tile := GameManager.get_player_tile()
	var stats: Dictionary = {}
	for entry in PlayerStats.stat_block.get_all_stats():
		var stat_id: String = str(entry.get("id", ""))
		if not stat_id.is_empty():
			stats[stat_id] = int(entry.get("current_value", 0))
	return {
		"tile":         [tile.x, tile.y],
		"display_name": PlayerStats.display_name,
		"stats":        stats
	}

func _serialize_inventory(inv: Inventory) -> Array:
	if inv == null:
		return []
	var result: Array = []
	for item in inv.get_objects():
		result.append(_serialize_item(item))
	return result

func _serialize_item(item: Dictionary) -> Dictionary:
	var entry := {
		"object_id":   str(item.get("object_id", "")),
		"stack_count": int(item.get("stack_count", 1)),
		"charges":     int(item.get("charges", -1)),
		"equipped":    bool(item.get("equipped", false))
	}
	var contents: Array = []
	for child in item.get("contents", []):
		contents.append(_serialize_item(child))
	if not contents.is_empty():
		entry["contents"] = contents
	return entry

func _serialize_game_time() -> Dictionary:
	var scheduled_quests: Array = []
	for quest_id in QuestManager._quest_states:
		var handles: Array = QuestManager._quest_states[quest_id].get("scheduled_handles", [])
		for handle in handles:
			if GameTime._scheduled.has(handle):
				var entry: Dictionary = GameTime._scheduled[handle]
				var remaining: int = maxi(1, entry["fire_at"] - GameTime.total_ticks)
				scheduled_quests.append({
					"quest_id":       quest_id,
					"remaining_ticks": remaining,
					"repeat":         int(entry.get("repeat", 0))
				})
	return {
		"total_ticks":      GameTime.total_ticks,
		"scheduled_quests": scheduled_quests
	}

func _serialize_region_diffs() -> Array:
	var result: Array = []
	var current_id: String = GameManager.get_current_region_id()
	if not current_id.is_empty() and current_id != "combat_arena":
		var snapshot := GameManager._snapshot_region()
		var diff := _build_region_diff(current_id, snapshot)
		if not diff.is_empty():
			result.append(diff)
	if GameManager.region_cache != null:
		for region_id in GameManager.region_cache._cache.keys():
			if region_id == current_id:
				continue  # live snapshot already taken above; cache entry is stale
			var snapshot: Dictionary = GameManager.region_cache._cache[region_id]
			var diff := _build_region_diff(region_id, snapshot)
			if not diff.is_empty():
				result.append(diff)
	return result

func _build_region_diff(region_id: String, snapshot: Dictionary) -> Dictionary:
	var baseline_data := Constants.load_json(Constants.REGIONS_DATA_PATH + region_id + ".json")
	if baseline_data.is_empty():
		return {}

	var baseline_objects: Array = baseline_data.get("objects", [])
	var baseline_npcs: Array   = baseline_data.get("npcs", [])
	var current_objects: Array = snapshot.get("objects", [])
	var current_npcs: Array    = snapshot.get("npcs", [])

	# Build lookup by instance_id for the JSON baseline
	var baseline_by_id: Dictionary = {}
	for obj in baseline_objects:
		var iid: String = str(obj.get("instance_id", ""))
		if not iid.is_empty():
			baseline_by_id[iid] = obj

	var added:    Array = []
	var modified: Array = []
	var seen_ids: Array = []

	for obj in current_objects:
		var iid: String = str(obj.get("instance_id", ""))
		if iid.is_empty() or not baseline_by_id.has(iid):
			# Runtime-spawned object with no authored baseline entry
			added.append(obj)
		else:
			seen_ids.append(iid)
			if _object_differs_from_baseline(obj, baseline_by_id[iid]):
				modified.append(obj)

	var removed: Array = []
	for iid in baseline_by_id:
		if not (iid in seen_ids):
			removed.append(iid)

	# NPC states: only track killed/despawned NPCs (position not saved per spec)
	var baseline_npc_ids: Array = []
	for entry in baseline_npcs:
		var npc_id: String = str(entry.get("npc_id", ""))
		if not npc_id.is_empty():
			baseline_npc_ids.append(npc_id)

	var current_npc_ids: Array = []
	for entry in current_npcs:
		var npc_id: String = str(entry.get("npc_id", ""))
		if not npc_id.is_empty():
			current_npc_ids.append(npc_id)

	var npc_states: Array = []
	for npc_id in baseline_npc_ids:
		if not (npc_id in current_npc_ids):
			npc_states.append({"npc_id": npc_id, "removed": true})

	if added.is_empty() and modified.is_empty() and removed.is_empty() and npc_states.is_empty():
		return {}

	return {
		"region_id": region_id,
		"added":      added,
		"modified":   modified,
		"removed":    removed,
		"npc_states": npc_states
	}

func _object_differs_from_baseline(current: Dictionary, baseline: Dictionary) -> bool:
	if current.get("tile") != baseline.get("tile"):
		return true
	if bool(current.get("is_open", false)) != false:
		return true
	if bool(current.get("container_open", false)) != false:
		return true
	if int(current.get("stack_count", 1)) != int(baseline.get("stack_count", 1)):
		return true
	var cur_content: Array = current.get("_content_ids", [])
	var base_content: Array = baseline.get("container_contents", [])
	if cur_content != base_content:
		return true
	return false

# ── Index management ─────────────────────────────────────────────────────────

func _next_slot_id() -> int:
	var saves := get_save_index()
	var max_id: int = 0
	for s in saves:
		if s is Dictionary:
			max_id = maxi(max_id, int(s.get("slot_id", 0)))
	return max_id + 1

func _write_save(slot_id: int, data: Dictionary) -> void:
	var save_path := Constants.SAVES_DIR + str(slot_id) + ".json"
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write save: " + save_path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func _update_index(slot_id: int, player_name: String, is_autosave: bool) -> void:
	var index: Dictionary = _read_index()
	var saves: Array = []
	var raw: Variant = index.get("saves", [])
	if raw is Array:
		for s in raw:
			if s is Dictionary and int(s.get("slot_id", -1)) != slot_id:
				saves.append(s)
	var timestamp := Time.get_datetime_string_from_system(false, true).left(16)
	saves.append({
		"slot_id":     slot_id,
		"player_name": player_name,
		"timestamp":   timestamp,
		"autosave":    is_autosave
	})
	index["saves"] = saves
	_write_index(index)

func _remove_from_index(slot_id: int) -> void:
	var index: Dictionary = _read_index()
	var saves: Array = []
	var raw: Variant = index.get("saves", [])
	if raw is Array:
		for s in raw:
			if s is Dictionary and int(s.get("slot_id", -1)) != slot_id:
				saves.append(s)
	index["saves"] = saves
	_write_index(index)

func _rotate_autosaves() -> void:
	var saves := get_save_index()
	var autosaves: Array = []
	for s in saves:
		if s is Dictionary and bool(s.get("autosave", false)):
			autosaves.append(s)
	if autosaves.size() < MAX_AUTOSAVES:
		return
	autosaves.sort_custom(func(a, b): return int(a.get("slot_id", 0)) < int(b.get("slot_id", 0)))
	delete_save(int(autosaves[0].get("slot_id", 0)))

func _read_index() -> Dictionary:
	if not FileAccess.file_exists(Constants.SAVE_INDEX_PATH):
		return {}
	var file := FileAccess.open(Constants.SAVE_INDEX_PATH, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return {}
	file.close()
	var data: Variant = json.get_data()
	return data if data is Dictionary else {}

func _write_index(index: Dictionary) -> void:
	var file := FileAccess.open(Constants.SAVE_INDEX_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write save index")
		return
	file.store_string(JSON.stringify(index, "\t"))
	file.close()

func _ensure_saves_dir() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("saves"):
		dir.make_dir("saves")
