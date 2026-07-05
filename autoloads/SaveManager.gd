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
	_update_index(slot_id, save_name, false,
		PlayerStats.current_class_id, PlayerStats.get_class_display_name())
	return true

func autosave() -> bool:
	_ensure_saves_dir()
	_rotate_autosaves()
	var slot_id := _next_slot_id()
	var data := _serialize_all(slot_id, PlayerStats.display_name, true)
	_write_save(slot_id, data)
	_update_index(slot_id, PlayerStats.display_name, true,
		PlayerStats.current_class_id, PlayerStats.get_class_display_name())
	return true

func save_new_game(player_name: String, class_id: String) -> bool:
	_ensure_saves_dir()
	var slot_id := _next_slot_id()
	var data := _serialize_all(slot_id, player_name, false)
	_write_save(slot_id, data)
	var class_display_name: String = PlayerStats.get_class_display_name()
	_update_index(slot_id, player_name, false, class_id, class_display_name)
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
	if version > Constants.SAVE_VERSION:
		push_error("SaveManager: save is from a newer version (got %d, expected %d) — cannot load" % [version, Constants.SAVE_VERSION])
		return false
	if version < Constants.SAVE_VERSION:
		push_warning("SaveManager: migrating save from version %d to %d" % [version, Constants.SAVE_VERSION])
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

func get_autosave_display_number(slot_id: int) -> int:
	var autosaves: Array = []
	for s in get_save_index():
		if s is Dictionary and bool(s.get("autosave", false)):
			autosaves.append(int(s.get("slot_id", 0)))
	autosaves.sort()
	return autosaves.find(slot_id) + 1

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

	# Reinitialise party: creates a fresh player member with a new stat block
	# and inventory.  All subsequent pass-through access via PlayerStats and
	# PlayerInventory automatically redirects to this new member.
	PartyManager.reset_for_load()
	FactionManager.initialize_standings()

	# Reset inventory (clears starting items loaded by initialize_as_player)
	PlayerInventory.get_inventory().restore_objects([])
	PlayerInventory.equip_changed.emit()

	# Reset stat block to base values (also clears all applied modifiers)
	PlayerStats.stat_block.load_from_file(Constants.STATS_DATA_PATH + "player_stats.json")
	PlayerStats.current_class_id = ""

	# Clear quest state and cancel all scheduled handles
	QuestManager.restore_from_state({})

	# Clear known spells
	SpellManager._known_spells.clear()

	# Reset quest spawn state
	GameManager.spawn_manager.clear_all_spawns()

	# Reset shop stock to defaults
	GameManager._reset_shop_state()

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

func _deserialize_all(data: Dictionary) -> void:
	_migrate_save_data(data)
	_deserialize_game_time(data.get("game_time", {}))
	_deserialize_party(data.get("party", {}))
	_deserialize_quest_state(data.get("quest_state", {}), data.get("game_time", {}))
	_deserialize_quest_spawns(data.get("quest_spawns", {}))
	_deserialize_region_diffs(data.get("region_diffs", []))
	_deserialize_shop_state(data.get("shop_state", {}), data.get("game_time", {}))
	_deserialize_faction_standings(data.get("faction_standings", {}))

	var raw_region: Variant = data.get("current_region", "")
	var region_id: String = raw_region if raw_region is String and not (raw_region as String).is_empty() else GameManager.starting_region
	GameManager.load_region(region_id)

	if _pending_player_tile != Vector2i(-1, -1) and GameManager.current_region != null:
		var player_node := GameManager.current_region.get_node_or_null("Actors/Player")
		if player_node != null:
			player_node.teleport_to_tile(_pending_player_tile)
	_pending_player_tile = Vector2i(-1, -1)

func _migrate_save_data(data: Dictionary) -> void:
	var _from_version: int = int(data.get("save_version", 0))
	# Add one block per version step: if from_version < N, run _migrate_vN(data)
	data["save_version"] = Constants.SAVE_VERSION

func _deserialize_game_time(data: Dictionary) -> void:
	if data.is_empty():
		return
	if data.has("total_ticks"):
		GameTime.restore_ticks(int(data["total_ticks"]))

func _deserialize_inventory(items: Array, target: Inventory) -> void:
	if items.is_empty():
		return
	target.restore_objects(items)
	PlayerInventory.equip_changed.emit()

func _deserialize_known_spells(spell_ids: Array) -> void:
	for entry in spell_ids:
		SpellManager.know_spell(str(entry))

func _deserialize_party(party_data: Dictionary) -> void:
	var members_arr: Array = party_data.get("members", [])
	for entry in members_arr:
		if not entry is Dictionary:
			continue
		var mid: String = str((entry as Dictionary).get("member_id", ""))
		if mid == Constants.PLAYER_MEMBER_ID:
			_restore_player_member(entry as Dictionary)
		else:
			_restore_npc_member(entry as Dictionary)

func _restore_player_member(data: Dictionary) -> void:
	var name_raw: Variant = data.get("display_name")
	if name_raw is String:
		PlayerStats.display_name = name_raw as String
	var class_id_raw: Variant = data.get("class_id")
	if class_id_raw is String and not (class_id_raw as String).is_empty():
		PlayerStats.set_current_class(class_id_raw as String)
	var is_downed_raw: Variant = data.get("is_downed", false)
	PartyManager.get_player().is_downed = bool(is_downed_raw)
	var stats: Dictionary = data.get("stats", {})
	for stat_id in stats:
		if not PlayerStats.stat_block.is_derived(str(stat_id)):
			PlayerStats.set_stat(str(stat_id), int(stats[stat_id]))
	_deserialize_inventory(data.get("inventory", []), PlayerInventory.get_inventory())
	_deserialize_known_spells(data.get("known_spells", []))
	var tile_raw: Variant = data.get("tile")
	if tile_raw is Array and (tile_raw as Array).size() >= 2:
		_pending_player_tile = Vector2i(int((tile_raw as Array)[0]), int((tile_raw as Array)[1]))

func _restore_npc_member(data: Dictionary) -> void:
	var member := PartyMember.new()
	member.member_id = str(data.get("member_id", ""))
	member.display_name = str(data.get("display_name", ""))
	member.class_id = str(data.get("class_id", ""))
	member.is_downed = bool(data.get("is_downed", false))
	member.known_spells = []
	for sid in data.get("known_spells", []):
		member.known_spells.append(str(sid))
	member.stat_block = StatBlock.new()
	member.stat_block.load_from_file(Constants.STATS_DATA_PATH + "npc_default.json")
	var stats: Dictionary = data.get("stats", {})
	for stat_id in stats:
		if not member.stat_block.is_derived(str(stat_id)):
			member.stat_block.set_stat(str(stat_id), int(stats[stat_id]))
	member.inventory = Inventory.new()
	var inv_items: Array = data.get("inventory", [])
	if not inv_items.is_empty():
		member.inventory.restore_objects(inv_items)
	PartyManager.add_member(member)

func _deserialize_quest_state(quest_data: Dictionary, game_time_data: Dictionary) -> void:
	if quest_data.is_empty():
		return
	QuestManager.restore_from_state(quest_data)
	QuestManager.restore_scheduled_handles(game_time_data.get("scheduled_quests", []))

func _deserialize_quest_spawns(data: Dictionary) -> void:
	if data.is_empty():
		return
	GameManager.spawn_manager.restore_quest_spawns(data)

func _deserialize_shop_state(shop_data: Dictionary, game_time_data: Dictionary) -> void:
	GameManager.restore_shop_state(shop_data)
	GameManager.restore_shop_timers(game_time_data.get("scheduled_shops", []))

func _deserialize_faction_standings(data: Dictionary) -> void:
	FactionManager.restore_standings(data)

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
		"party":          _serialize_party(),
		"game_time":      _serialize_game_time(),
		"quest_state":       QuestManager.get_serializable_state(),
		"quest_spawns":      _serialize_quest_spawns(),
		"region_diffs":      _serialize_region_diffs(),
		"shop_state":        _serialize_shop_state(),
		"faction_standings": FactionManager.get_serializable_standings()
	}

func _serialize_party() -> Dictionary:
	var members: Array = []
	for member in PartyManager.get_all_members():
		members.append(_serialize_party_member(member))
	return {"members": members}

func _serialize_party_member(member: PartyMember) -> Dictionary:
	var stats: Dictionary = {}
	if member.stat_block != null:
		for entry in member.stat_block.get_all_stats():
			var stat_id: String = str(entry.get("id", ""))
			if not stat_id.is_empty():
				stats[stat_id] = int(entry.get("current_value", 0))
	var inv_data: Array = _serialize_inventory(member.inventory) if member.inventory != null else []
	var entry: Dictionary = {
		"member_id":    member.member_id,
		"display_name": member.display_name,
		"class_id":     member.class_id,
		"is_downed":    member.is_downed,
		"stats":        stats,
		"inventory":    inv_data,
		"known_spells": member.known_spells.duplicate()
	}
	if member.member_id == Constants.PLAYER_MEMBER_ID:
		var tile := GameManager.get_player_tile()
		entry["tile"] = [tile.x, tile.y]
	return entry

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
	return {
		"total_ticks":      GameTime.total_ticks,
		"scheduled_quests": QuestManager.get_serializable_handles(),
		"scheduled_shops":  GameManager.get_serializable_shop_timers()
	}

func _serialize_shop_state() -> Dictionary:
	return GameManager.get_serializable_shop_state()

func _serialize_quest_spawns() -> Dictionary:
	return GameManager.spawn_manager.get_serializable_quest_spawns()

func _serialize_region_diffs() -> Array:
	var result: Array = []
	var current_id: String = GameManager.get_current_region_id()
	if not current_id.is_empty() and current_id != "combat_arena":
		var snapshot := GameManager._snapshot_region()
		var diff := _build_region_diff(current_id, snapshot)
		if not diff.is_empty():
			result.append(diff)
	if GameManager.region_cache != null:
		for region_id in GameManager.region_cache.get_cached_region_ids():
			if region_id == current_id:
				continue  # live snapshot already taken above; cache entry is stale
			var snapshot: Dictionary = GameManager.region_cache.restore_region(region_id)
			var diff := _build_region_diff(region_id, snapshot)
			if not diff.is_empty():
				result.append(diff)
	return result

func _build_region_diff(region_id: String, snapshot: Dictionary) -> Dictionary:
	var baseline_data: Dictionary
	if GameManager.region_cache != null and GameManager.region_cache.has_baseline(region_id):
		baseline_data = GameManager.region_cache.get_baseline(region_id)
	else:
		baseline_data = Constants.load_json(Constants.REGIONS_DATA_PATH + region_id + ".json")
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
	if bool(current.get("is_locked", false)) != bool(baseline.get("is_locked", false)):
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

func _update_index(slot_id: int, player_name: String, is_autosave: bool,
		class_id: String = "", cls_name: String = "") -> void:
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
		"class_id":    class_id,
		"class_name":  cls_name,
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

func _update_save_slot_class(new_class_id: String) -> void:
	var cls_name: String = PlayerStats.get_class_display_name()
	var index: Dictionary = _read_index()
	var raw: Variant = index.get("saves", [])
	if not raw is Array:
		return
	var saves: Array = raw as Array
	var target_slot_id: int = -1
	for s in saves:
		if s is Dictionary and not bool(s.get("autosave", false)):
			var sid: int = int(s.get("slot_id", 0))
			if sid > target_slot_id:
				target_slot_id = sid
	if target_slot_id == -1:
		return
	for s in saves:
		if s is Dictionary and int(s.get("slot_id", -1)) == target_slot_id:
			s["class_id"] = new_class_id
			s["class_name"] = cls_name
			break
	index["saves"] = saves
	_write_index(index)

func _ensure_saves_dir() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("saves"):
		dir.make_dir("saves")
