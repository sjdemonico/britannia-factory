class_name EquipmentTypeRegistry
extends RefCounted

var _types: Dictionary = {}

func load_from_file(path: String) -> void:
	var data: Dictionary = Constants.load_json(path)
	for entry in data.get("equipment_types", []):
		var id: String = str(entry.get("id", ""))
		if not id.is_empty():
			_types[id] = entry

func has_type(id: String) -> bool:
	return _types.has(id)

func get_display_name(id: String) -> String:
	return str(_types.get(id, {}).get("display_name", id))

func get_all() -> Array:
	return _types.values()
