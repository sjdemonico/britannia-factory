class_name WaypointManager
extends Node

var _waypoints: Dictionary = {}  # String -> Vector2i

func register_waypoint(waypoint_name: String, tile: Vector2i) -> void:
	_waypoints[waypoint_name] = tile

func get_waypoint(waypoint_name: String) -> Vector2i:
	return _waypoints.get(waypoint_name, Vector2i(-1, -1))

func has_waypoint(waypoint_name: String) -> bool:
	return _waypoints.has(waypoint_name)

func load_from_array(waypoints: Array) -> void:
	_waypoints.clear()
	for entry in waypoints:
		var id: String = str(entry.get("id", ""))
		var raw_tile = entry.get("tile", [0, 0])
		if id.is_empty() or not raw_tile is Array or raw_tile.size() < 2:
			push_error("WaypointManager: malformed waypoint entry, skipping")
			continue
		_waypoints[id] = Vector2i(int(raw_tile[0]), int(raw_tile[1]))
