class_name WaypointManager
extends Node

var _waypoints: Dictionary = {}  # String -> Vector2i

func register_waypoint(waypoint_name: String, tile: Vector2i) -> void:
	_waypoints[waypoint_name] = tile

func get_waypoint(waypoint_name: String) -> Vector2i:
	return _waypoints.get(waypoint_name, Vector2i(-1, -1))

func has_waypoint(waypoint_name: String) -> bool:
	return _waypoints.has(waypoint_name)
