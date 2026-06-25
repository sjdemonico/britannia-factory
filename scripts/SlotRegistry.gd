class_name SlotRegistry
extends RefCounted

var _slots: Dictionary = {}
var _ordered: Array[Dictionary] = []

func load_from_file(path: String) -> bool:
	var data: Dictionary = Constants.load_json(path)
	if data.is_empty():
		return false
	if not data.has("slots") or not data["slots"] is Array:
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
