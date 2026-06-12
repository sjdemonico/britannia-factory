class_name RegionLoader
extends RefCounted

func load_json(region_id: String) -> Dictionary:
	var path := Constants.REGIONS_DATA_PATH + region_id + ".json"
	if not FileAccess.file_exists(path):
		push_error("RegionLoader: region file not found: " + path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("RegionLoader: cannot open: " + path)
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("RegionLoader: JSON parse error in " + path + ": " + json.get_error_message())
		return {}
	var data: Dictionary = json.get_data()
	for field in ["region_id", "region_name", "default_spawn", "spawns"]:
		if not data.has(field):
			push_error("RegionLoader: missing required field '" + field + "' in " + path)
			return {}
	return data

func register_spawns(data: Dictionary) -> void:
	var points: Dictionary = {}
	for entry in data.get("spawns", []):
		var sid: String = str(entry.get("id", ""))
		var raw_tile = entry.get("tile", [0, 0])
		if sid.is_empty() or not raw_tile is Array or raw_tile.size() < 2:
			push_error("RegionLoader: malformed spawn entry, skipping")
			continue
		points[sid] = Vector2i(int(raw_tile[0]), int(raw_tile[1]))
	GameManager.configure_spawns(points, str(data.get("default_spawn", "")))

func load_waypoints(data: Dictionary) -> void:
	var wpt_mgr := GameManager.waypoint_manager
	if wpt_mgr == null:
		return
	var waypoints = data.get("waypoints", [])
	if waypoints is Array:
		wpt_mgr.load_from_array(waypoints)

func spawn_npcs(data: Dictionary, scene_root: Node) -> void:
	var actors_node := scene_root.get_node_or_null("Actors")
	if actors_node == null:
		push_error("RegionLoader: Actors node not found in scene")
		return
	var npc_scene := load(Constants.NPC_SCENE_PATH) as PackedScene
	if npc_scene == null:
		push_error("RegionLoader: cannot load NPC scene")
		return
	for entry in data.get("npcs", []):
		var npc_id: String = str(entry.get("npc_id", ""))
		var raw_tile = entry.get("tile", [0, 0])
		if npc_id.is_empty() or not raw_tile is Array or raw_tile.size() < 2:
			push_error("RegionLoader: malformed NPC entry, skipping")
			continue
		var npc := npc_scene.instantiate()
		npc.npc_id = npc_id
		npc.npc_tile = Vector2i(int(raw_tile[0]), int(raw_tile[1]))
		actors_node.add_child(npc)

func spawn_objects(data: Dictionary) -> void:
	if GameManager.objects_node == null:
		push_error("RegionLoader: objects_node is null, cannot spawn objects")
		return
	var wo_scene := load(Constants.WORLD_OBJECT_SCENE_PATH) as PackedScene
	if wo_scene == null:
		push_error("RegionLoader: cannot load WorldObject scene")
		return
	for entry in data.get("objects", []):
		var object_id: String = str(entry.get("object_id", ""))
		var raw_tile = entry.get("tile", [0, 0])
		if object_id.is_empty() or not raw_tile is Array or raw_tile.size() < 2:
			push_error("RegionLoader: malformed object entry, skipping")
			continue
		var tile := Vector2i(int(raw_tile[0]), int(raw_tile[1]))
		var stack_count: int = maxi(1, int(entry.get("stack_count", 1)))
		var world_object := wo_scene.instantiate()
		world_object.object_id = object_id
		world_object.object_tile = tile
		world_object.stack_count = stack_count
		var inst_id: String = str(entry.get("instance_id", ""))
		if not inst_id.is_empty():
			world_object.instance_id = inst_id
		var raw_targets = entry.get("targets")
		if raw_targets is Array:
			for t in raw_targets:
				world_object.targets.append(str(t))
		GameManager.objects_node.add_child(world_object)
		if not inst_id.is_empty():
			GameManager.register_object_instance(inst_id, world_object)
		var raw_contents = entry.get("container_contents")
		if raw_contents is Array:
			world_object.apply_contents_override(raw_contents)

func load_tile_triggers(data: Dictionary) -> void:
	var raw: Variant = data.get("tile_triggers", [])
	var triggers: Array = raw if raw is Array else []
	QuestManager.register_tile_triggers(triggers)

func apply_npc_schedule_placement(scene_root: Node) -> void:
	var actors_node := scene_root.get_node_or_null("Actors")
	if actors_node == null:
		return
	for child in actors_node.get_children():
		var npc := child as NPC
		if npc == null:
			continue
		npc.apply_initial_schedule_placement()

func apply_diff(diff: RegionDiff, scene_root: Node) -> void:
	var objects_node := GameManager.objects_node

	# Remove baseline objects that were picked up or destroyed
	if objects_node != null and not diff.removed.is_empty():
		for child in objects_node.get_children():
			var wo := child as WorldObject
			if wo == null:
				continue
			if wo.instance_id in diff.removed:
				WorldState.clear_object_from_tile(wo.object_tile, wo.object_id)
				wo.queue_free()

	# Apply state changes to modified objects
	for mod_entry in diff.modified:
		if not mod_entry is Dictionary:
			continue
		var iid: String = str(mod_entry.get("instance_id", ""))
		if iid.is_empty():
			continue
		var wo: WorldObject = GameManager.get_object_by_instance_id(iid)
		if wo == null:
			continue
		wo.is_open = bool(mod_entry.get("is_open", false))
		wo.container_open = bool(mod_entry.get("container_open", false))
		wo.stack_count = maxi(1, int(mod_entry.get("stack_count", 1)))
		wo._content_ids = mod_entry.get("_content_ids", []).duplicate()
		if wo.is_open and wo.toggleable:
			wo.queue_redraw()
		if wo.container_open:
			WorldState.open_container(wo.object_tile)

	# Spawn runtime-added objects
	var wo_scene := load(Constants.WORLD_OBJECT_SCENE_PATH) as PackedScene
	if objects_node != null and wo_scene != null:
		for add_entry in diff.added:
			if not add_entry is Dictionary:
				continue
			var object_id: String = str(add_entry.get("object_id", ""))
			var raw_tile = add_entry.get("tile", [0, 0])
			if object_id.is_empty() or not raw_tile is Array or (raw_tile as Array).size() < 2:
				continue
			var tile := Vector2i(int(raw_tile[0]), int(raw_tile[1]))
			var world_object := wo_scene.instantiate()
			world_object.object_id = object_id
			world_object.object_tile = tile
			world_object.stack_count = maxi(1, int(add_entry.get("stack_count", 1)))
			objects_node.add_child(world_object)

	# Remove killed / permanently-despawned NPCs
	var removed_npc_ids: Array = []
	for ns in diff.npc_states:
		if ns is Dictionary and bool(ns.get("removed", false)):
			removed_npc_ids.append(str(ns.get("npc_id", "")))
	if not removed_npc_ids.is_empty():
		var actors_node := scene_root.get_node_or_null("Actors")
		if actors_node != null:
			for child in actors_node.get_children():
				var npc := child as NPC
				if npc == null:
					continue
				if npc.npc_id in removed_npc_ids:
					WorldState.clear_occupant(npc.npc_tile)
					npc.queue_free()
