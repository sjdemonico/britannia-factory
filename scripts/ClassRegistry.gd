class_name ClassRegistry
extends RefCounted

var _classes: Dictionary = {}

func load_from_file(path: String) -> void:
	var data: Dictionary = Constants.load_json(path)
	for entry in data.get("classes", []):
		var class_id: String = str(entry.get("class_id", ""))
		if not class_id.is_empty():
			_classes[class_id] = entry

func has_class(class_id: String) -> bool:
	return _classes.has(class_id)

func get_class_data(class_id: String) -> Dictionary:
	return _classes.get(class_id, {})

func get_starting_stats(class_id: String) -> Dictionary:
	var cls: Dictionary = _classes.get(class_id, {})
	var raw = cls.get("starting_stats")
	return raw if raw is Dictionary else {}

func get_stat_gains(class_id: String) -> Dictionary:
	var cls: Dictionary = _classes.get(class_id, {})
	var raw = cls.get("stat_gains_per_level")
	return raw if raw is Dictionary else {}

func get_stat_ranges(class_id: String) -> Dictionary:
	var cls: Dictionary = _classes.get(class_id, {})
	var raw = cls.get("stat_ranges")
	return raw if raw is Dictionary else {}

func get_equipment_whitelist(class_id: String) -> Array:
	var cls: Dictionary = _classes.get(class_id, {})
	var raw = cls.get("equipment_whitelist")
	return raw if raw is Array else []

func get_all_class_ids() -> Array:
	return _classes.keys()
