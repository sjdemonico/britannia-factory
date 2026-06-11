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
