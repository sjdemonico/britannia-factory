class_name Inventory
extends RefCounted

const MAX_SLOTS: int = 100

var _objects: Array = []
var _next_id: int = 0
var _cache: Dictionary = {}
var _equipped_by_slot: Dictionary = {}  # slot_id -> Array[int] of instance_ids

func add_object(object_id: String) -> int:
	var data := get_object_data(object_id)
	if data.is_empty():
		return -1
	if not data.get("carriable", false):
		push_error("Inventory: attempted to add non-carriable object: " + object_id)
		return -1
	if _objects.size() >= MAX_SLOTS:
		return -1
	var instance := {
		"object_id": object_id,
		"instance_id": _next_id,
		"data": data,
		"contents": [],
		"equipped": false,
		"stack_count": 1
	}
	_objects.append(instance)
	_next_id += 1
	return instance["instance_id"]

func remove_object(instance_id: int) -> bool:
	for i in range(_objects.size()):
		if _objects[i]["instance_id"] == instance_id:
			_unequip_slot_for_instance(instance_id)
			_objects.remove_at(i)
			return true
	return false

func remove_object_anywhere(instance_id: int) -> bool:
	if remove_object(instance_id):
		return true
	return _remove_from_contents_recursive(_objects, instance_id)

func _remove_from_contents_recursive(objects: Array, instance_id: int) -> bool:
	for obj in objects:
		var contents: Array = obj.get("contents", [])
		for i in range(contents.size()):
			if contents[i]["instance_id"] == instance_id:
				_unequip_slot_for_instance(instance_id)
				contents.remove_at(i)
				return true
		if _remove_from_contents_recursive(contents, instance_id):
			return true
	return false

func get_objects() -> Array:
	return _objects.duplicate()

func get_object_by_instance(instance_id: int) -> Dictionary:
	for obj in _objects:
		if obj["instance_id"] == instance_id:
			return obj
	return {}

func find_object_anywhere(instance_id: int) -> Dictionary:
	var top := get_object_by_instance(instance_id)
	if not top.is_empty():
		return top
	return _find_in_contents_recursive(_objects, instance_id)

func _find_in_contents_recursive(objects: Array, instance_id: int) -> Dictionary:
	for obj in objects:
		for content in obj.get("contents", []):
			if content["instance_id"] == instance_id:
				return content
			var found := _find_in_contents_recursive([content], instance_id)
			if not found.is_empty():
				return found
	return {}

func add_to_container(instance_id: int, object_id: String) -> int:
	var container := find_object_anywhere(instance_id)
	if container.is_empty():
		return -1
	if not container["data"].get("container", false):
		push_error("Inventory: object is not a container: " + str(instance_id))
		return -1
	var _raw_slots = container["data"].get("container_slots", 0)
	var slots: int = int(_raw_slots) if _raw_slots != null else -1
	if slots != -1 and container["contents"].size() >= slots:
		return -1
	var data := get_object_data(object_id)
	if not data.is_empty():
		var raw_wl = container["data"].get("container_weight_limit")
		var weight_limit: float = float(raw_wl) if raw_wl != null else -1.0
		if weight_limit >= 0.0:
			var contents_weight: float = _weight_of_objects(container["contents"])
			if contents_weight + data.get("weight", 0.0) > weight_limit:
				MessageLog.post("That is too heavy for the container.")
				return -1
	if data.is_empty():
		return -1
	if not data.get("carriable", false):
		push_error("Inventory: attempted to add non-carriable object to container: " + object_id)
		return -1
	var instance := {
		"object_id": object_id,
		"instance_id": _next_id,
		"data": data,
		"contents": [],
		"equipped": false,
		"stack_count": 1
	}
	container["contents"].append(instance)
	_next_id += 1
	return instance["instance_id"]

func remove_from_container(instance_id: int, child_instance_id: int) -> bool:
	var container := find_object_anywhere(instance_id)
	if container.is_empty():
		return false
	var contents: Array = container["contents"]
	for i in range(contents.size()):
		if contents[i]["instance_id"] == child_instance_id:
			contents.remove_at(i)
			return true
	return false

func get_container_contents(instance_id: int) -> Array:
	var container := find_object_anywhere(instance_id)
	return container.get("contents", []).duplicate()

func get_container_slots(instance_id: int) -> int:
	var container := find_object_anywhere(instance_id)
	return container.get("data", {}).get("container_slots", 0)

func move_to_top_level(instance_id: int) -> bool:
	var obj := find_object_anywhere(instance_id)
	if obj.is_empty():
		return false
	var is_at_top := not get_object_by_instance(instance_id).is_empty()
	if is_at_top:
		return true
	if _objects.size() >= MAX_SLOTS:
		return false
	if not remove_object_anywhere(instance_id):
		return false
	# Merge with existing unequipped top-level stack of same type.
	if not obj.get("equipped", false):
		var existing := _find_unequipped_top_level_stack(obj["object_id"])
		if not existing.is_empty():
			existing["stack_count"] = existing.get("stack_count", 1) + obj.get("stack_count", 1)
			return true
	_objects.append(obj)
	return true

func move_to_container(instance_id: int, container_instance_id: int) -> bool:
	var obj := find_object_anywhere(instance_id)
	if obj.is_empty():
		return false
	var container := find_object_anywhere(container_instance_id)
	if container.is_empty():
		return false
	if not container["data"].get("container", false):
		return false
	var _raw_mv_slots = container["data"].get("container_slots", 0)
	var mv_slots: int = int(_raw_mv_slots) if _raw_mv_slots != null else -1
	if mv_slots != -1 and container["contents"].size() >= mv_slots:
		return false
	if not remove_object_anywhere(instance_id):
		return false
	container["contents"].append(obj)
	return true

func set_instance_name(instance_id: int, name: String) -> void:
	var obj := find_object_anywhere(instance_id)
	if not obj.is_empty():
		obj["data"]["name"] = name

func get_total_weight() -> float:
	return _weight_of_objects(_objects)

func _weight_of_objects(objects: Array) -> float:
	var total: float = 0.0
	for obj in objects:
		total += obj["data"].get("weight", 0.0) * obj.get("stack_count", 1)
		total += _weight_of_objects(obj.get("contents", []))
	return total

func _find_unequipped_top_level_stack(object_id: String) -> Dictionary:
	for obj in _objects:
		if obj["object_id"] == object_id and not obj.get("equipped", false):
			return obj
	return {}

func _find_unequipped_top_level_stack_excluding(object_id: String, exclude_id: int) -> Dictionary:
	for obj in _objects:
		if obj["object_id"] == object_id and not obj.get("equipped", false) and obj["instance_id"] != exclude_id:
			return obj
	return {}

func add_stacked(object_id: String, count: int) -> int:
	if count <= 0:
		return -1
	var existing := _find_unequipped_top_level_stack(object_id)
	if not existing.is_empty():
		existing["stack_count"] = existing.get("stack_count", 1) + count
		return existing["instance_id"]
	if _objects.size() >= MAX_SLOTS:
		return -1
	var data := get_object_data(object_id)
	if data.is_empty():
		return -1
	if not data.get("carriable", false):
		push_error("Inventory: attempted to add non-carriable object: " + object_id)
		return -1
	var instance := {
		"object_id": object_id,
		"instance_id": _next_id,
		"data": data,
		"contents": [],
		"equipped": false,
		"stack_count": count
	}
	_objects.append(instance)
	_next_id += 1
	return instance["instance_id"]

func take_from_stack(instance_id: int, count: int) -> int:
	var item := find_object_anywhere(instance_id)
	if item.is_empty():
		return 0
	var current: int = item.get("stack_count", 1)
	var actual: int = mini(count, current)
	if actual >= current:
		remove_object_anywhere(instance_id)
	else:
		item["stack_count"] = current - actual
	return actual

func _split_one_for_equip(instance_id: int) -> int:
	var item := find_object_anywhere(instance_id)
	if item.is_empty():
		return -1
	var current: int = item.get("stack_count", 1)
	if current <= 1:
		return -1
	if _objects.size() >= MAX_SLOTS:
		return -1
	item["stack_count"] = current - 1
	var data: Dictionary = item["data"]
	var new_instance := {
		"object_id": item["object_id"],
		"instance_id": _next_id,
		"data": data,
		"contents": [],
		"equipped": false,
		"stack_count": 1
	}
	_objects.append(new_instance)
	_next_id += 1
	return new_instance["instance_id"]

func move_stack_to_container(moving_id: int, dest_container_id: int, count: int) -> bool:
	var source := find_object_anywhere(moving_id)
	if source.is_empty():
		return false
	var container := find_object_anywhere(dest_container_id)
	if container.is_empty() or not container["data"].get("container", false):
		return false
	var raw_slots = container["data"].get("container_slots", 0)
	var slot_limit: int = int(raw_slots) if raw_slots != null else -1
	if slot_limit != -1 and container["contents"].size() >= slot_limit:
		return false
	var raw_wl = container["data"].get("container_weight_limit")
	if raw_wl != null:
		var weight_limit: float = float(raw_wl)
		var contents_weight: float = _weight_of_objects(container["contents"])
		var item_weight: float = source["data"].get("weight", 0.0) * count
		if contents_weight + item_weight > weight_limit:
			MessageLog.post("That is too heavy for the container.")
			return false
	var source_stack: int = source.get("stack_count", 1)
	if count >= source_stack:
		return move_to_container(moving_id, dest_container_id)
	source["stack_count"] = source_stack - count
	var object_id: String = source["object_id"]
	for content in container["contents"]:
		if content["object_id"] == object_id and not content.get("equipped", false):
			content["stack_count"] = content.get("stack_count", 1) + count
			return true
	var cdata := get_object_data(object_id)
	if cdata.is_empty():
		source["stack_count"] = source_stack
		return false
	var new_entry := {
		"object_id": object_id,
		"instance_id": _next_id,
		"data": cdata,
		"contents": [],
		"equipped": false,
		"stack_count": count
	}
	container["contents"].append(new_entry)
	_next_id += 1
	return true

func equip_item(instance_id: int) -> bool:
	var item := find_object_anywhere(instance_id)
	if item.is_empty() or not item["data"].get("equippable", false):
		return false
	if item.get("equipped", false):
		return false
	var slots: Array = item["data"].get("equip_slots", [])
	if slots.is_empty():
		return false
	# All required slots must be free before any are claimed.
	for slot_id in slots:
		if is_slot_occupied(str(slot_id)):
			return false
	# If the stack has more than one item, split one off for the equip.
	var equip_id := instance_id
	if item.get("stack_count", 1) > 1:
		equip_id = _split_one_for_equip(instance_id)
		if equip_id == -1:
			return false
		item = get_object_by_instance(equip_id)
		if item.is_empty():
			return false
	for slot_id in slots:
		var sid := str(slot_id)
		if not _equipped_by_slot.has(sid):
			_equipped_by_slot[sid] = []
		_equipped_by_slot[sid].append(equip_id)
	item["equipped"] = true
	var modifier_ids = item["data"].get("modifiers")
	if modifier_ids is Array:
		for mod_id in modifier_ids:
			var mid := str(mod_id)
			if PlayerStats.stat_block.has_modifier_def(mid):
				PlayerStats.stat_block.apply_modifier(mid, item["object_id"])
			else:
				push_warning("Inventory: unrecognized modifier_id '" + mid + "' on object '" + item["object_id"] + "'. Skipping.")
	return true

func unequip_item(instance_id: int) -> void:
	var item := find_object_anywhere(instance_id)
	if item.is_empty() or not item.get("equipped", false):
		return
	_unequip_slot_for_instance(instance_id)
	item["equipped"] = false
	PlayerStats.stat_block.remove_modifiers_by_source(item["object_id"])
	if get_object_by_instance(instance_id).is_empty():
		return
	var existing := _find_unequipped_top_level_stack_excluding(item["object_id"], instance_id)
	if not existing.is_empty():
		existing["stack_count"] = existing.get("stack_count", 1) + item.get("stack_count", 1)
		remove_object(instance_id)

func _unequip_slot_for_instance(instance_id: int) -> void:
	for slot_id in _equipped_by_slot.keys():
		var arr: Array = _equipped_by_slot[slot_id]
		for i in range(arr.size()):
			if arr[i] == instance_id:
				arr.remove_at(i)
				if arr.is_empty():
					_equipped_by_slot.erase(slot_id)
				return

func get_slot_occupancy(slot_id: String) -> int:
	return _equipped_by_slot.get(slot_id, []).size()

func is_slot_occupied(slot_id: String) -> bool:
	var max_inst: int = 1
	if GameManager.slot_registry != null:
		max_inst = GameManager.slot_registry.get_instance_count(slot_id)
	return get_slot_occupancy(slot_id) >= max_inst

func get_item_in_slot(slot_id: String, idx: int = 0) -> Dictionary:
	var arr: Array = _equipped_by_slot.get(slot_id, [])
	if idx >= arr.size():
		return {}
	return find_object_anywhere(arr[idx])

func get_equipped_items() -> Array:
	var result: Array = []
	_collect_equipped(_objects, result)
	return result

func _collect_equipped(objects: Array, result: Array) -> void:
	for obj in objects:
		if obj.get("equipped", false):
			result.append(obj)
		_collect_equipped(obj.get("contents", []), result)

func get_object_data(object_id: String) -> Dictionary:
	if _cache.has(object_id):
		return _cache[object_id]
	var path := "res://data/objects/" + object_id + ".json"
	if not FileAccess.file_exists(path):
		push_error("Inventory: object file not found: " + path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Inventory: could not open: " + path)
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("Inventory: JSON parse error in " + path + ": " + json.get_error_message())
		return {}
	var data: Dictionary = json.data
	_cache[object_id] = data
	return data
