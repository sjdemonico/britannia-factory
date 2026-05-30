class_name NPCScheduler
extends RefCounted

var _schedule_data: Dictionary = {}

func load_schedule(schedule_data: Dictionary) -> void:
	_schedule_data = schedule_data

func get_current_entry(day_name: String, hour: int) -> Dictionary:
	var entries: Array
	if _schedule_data.has(day_name):
		entries = _schedule_data[day_name]
	elif _schedule_data.has("default"):
		entries = _schedule_data["default"]
	else:
		return {}
	var best: Dictionary = {}
	var best_hour: int = -1
	for entry: Dictionary in entries:
		var entry_hour: int = int(entry.get("hour", -1))
		if entry_hour <= hour and entry_hour > best_hour:
			best = entry
			best_hour = entry_hour
	return best
