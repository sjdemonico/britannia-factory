class_name SlotRegistry
extends RefCounted

var _slots: Dictionary = {}
var _ordered: Array[Dictionary] = []

func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("SlotRegistry: file not found: " + path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SlotRegistry: could not open: " + path)
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("SlotRegistry: JSON parse error in " + path + ": " + json.get_error_message())
		return false
	var data = json.data
	if not data is Dictionary or not data.has("slots") or not data["slots"] is Array:
		push_error("SlotRegistry: malformed slot config: " + path)
		return false
	_slots = {}
	_ordered = []
	for entry in data["slots"]:
		if not entry.has("id") or not entry.has("display_name") or not entry.has("instances"):
			push_error("SlotRegistry: slot entry missing required fields, skipping: " + str(entry))
			continue
		var slot: Dictionary = {
			"id": str(entry["id"]),
			"display_name": str(entry["display_name"]),
			"instances": int(entry["instances"])
		}
		_slots[slot["id"]] = slot
		_ordered.append(slot)
	return true

func get_all_slots() -> Array[Dictionary]:
	return _ordered.duplicate()

func get_slot(slot_id: String) -> Dictionary:
	return _slots.get(slot_id, {})

func has_slot(slot_id: String) -> bool:
	return _slots.has(slot_id)

func get_instance_count(slot_id: String) -> int:
	if not _slots.has(slot_id):
		return 0
	return _slots[slot_id]["instances"]
