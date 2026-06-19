class_name Inventory
extends RefCounted

const MAX_SLOTS: int = 100

var is_player_inventory: bool = false

var _objects: Array = []
var _next_id: int = 0
var _cache: Dictionary = {}
var _equipped_by_slot: Dictionary = {}  # slot_id -> Array[int] of instance_ids

static var _obj_registry: Dictionary = {}
static var _obj_global_defaults: Dictionary = {}
static var _obj_type_defaults: Dictionary = {}
static var _obj_registry_loaded: bool = false

static func _ensure_registry() -> void:
	if _obj_registry_loaded:
		return
	_obj_global_defaults = Constants.load_json(Constants.OBJECT_DEFAULTS_PATH)
	var types_data: Dictionary = Constants.load_json(Constants.OBJECT_TYPES_CONFIG_PATH)
	for entry in types_data.get("object_types", []):
		var tid: String = str(entry.get("type_id", ""))
		if not tid.is_empty():
			_obj_type_defaults[tid] = entry.get("defaults", {})
	var reg_data: Dictionary = Constants.load_json(Constants.OBJECTS_REGISTRY_PATH)
	for entry in reg_data.get("objects", []):
		var oid: String = str(entry.get("object_id", ""))
		if not oid.is_empty():
			_obj_registry[oid] = entry
	_obj_registry_loaded = true

static func resolve_object_definition(raw_entry: Dictionary) -> Dictionary:
	var resolved: Dictionary = _obj_global_defaults.duplicate()
	var type_id: String = str(raw_entry.get("type", "item"))
	if _obj_type_defaults.has(type_id):
		for key in _obj_type_defaults[type_id]:
			resolved[key] = _obj_type_defaults[type_id][key]
	for key in raw_entry:
		resolved[key] = raw_entry[key]
	return resolved

static func get_object_definition(object_id: String) -> Dictionary:
	_ensure_registry()
	if not _obj_registry.has(object_id):
		push_error("Inventory: object not found in registry: " + object_id)
		return {}
	return resolve_object_definition(_obj_registry[object_id])

func add_object(object_id: String) -> int:
	var data := get_object_data(object_id)
	if data.is_empty():
		return -1
	if not data.get("carriable", false):
		push_error("Inventory: attempted to add non-carriable object: " + object_id)
		return -1
	if _objects.size() >= MAX_SLOTS:
		return -1
	var raw_charges = data.get("charges")
	var instance := {
		"object_id": object_id,
		"instance_id": _next_id,
		"data": data,
		"contents": [],
		"equipped": false,
		"stack_count": 1,
		"charges": int(raw_charges) if raw_charges != null else -1
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
	if container["data"].get("type", "") != "container":
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
				MessageLog.post(MessageRegistry.get_message("inventory_container_too_heavy"))
				return -1
	if data.is_empty():
		return -1
	if not data.get("carriable", false):
		push_error("Inventory: attempted to add non-carriable object to container: " + object_id)
		return -1
	var raw_cont_charges = data.get("charges")
	var instance := {
		"object_id": object_id,
		"instance_id": _next_id,
		"data": data,
		"contents": [],
		"equipped": false,
		"stack_count": 1,
		"charges": int(raw_cont_charges) if raw_cont_charges != null else -1
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
	# Merge with existing unequipped top-level stack of same type and charges.
	if not obj.get("equipped", false):
		var existing := _find_unequipped_top_level_stack(obj["object_id"], int(obj.get("charges", -1)))
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
	if container["data"].get("type", "") != "container":
		return false
	var _raw_mv_slots = container["data"].get("container_slots", 0)
	var mv_slots: int = int(_raw_mv_slots) if _raw_mv_slots != null else -1
	if mv_slots != -1 and container["contents"].size() >= mv_slots:
		return false
	var raw_mv_wl = container["data"].get("container_weight_limit")
	if raw_mv_wl != null:
		var mv_weight_limit: float = float(raw_mv_wl)
		var mv_item_weight: float = obj["data"].get("weight", 0.0) * obj.get("stack_count", 1)
		if _weight_of_objects(container["contents"]) + mv_item_weight > mv_weight_limit:
			MessageLog.post(MessageRegistry.get_message("inventory_container_too_heavy"))
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

func _find_unequipped_top_level_stack(object_id: String, charges: int = -1) -> Dictionary:
	for obj in _objects:
		if obj["object_id"] == object_id and not obj.get("equipped", false) and int(obj.get("charges", -1)) == charges:
			return obj
	return {}

func _find_unequipped_top_level_stack_excluding(object_id: String, exclude_id: int, charges: int = -1) -> Dictionary:
	for obj in _objects:
		if obj["object_id"] == object_id and not obj.get("equipped", false) and obj["instance_id"] != exclude_id and int(obj.get("charges", -1)) == charges:
			return obj
	return {}

func add_stacked(object_id: String, count: int) -> int:
	if count <= 0:
		return -1
	var data := get_object_data(object_id)
	if data.is_empty():
		return -1
	if not data.get("carriable", false):
		push_error("Inventory: attempted to add non-carriable object: " + object_id)
		return -1
	var raw_stacked_charges = data.get("charges")
	var stacked_charges: int = int(raw_stacked_charges) if raw_stacked_charges != null else -1
	var existing: Dictionary = {}
	if data.get("stackable") != false:
		existing = _find_unequipped_top_level_stack(object_id, stacked_charges)
	if not existing.is_empty():
		existing["stack_count"] = existing.get("stack_count", 1) + count
		return existing["instance_id"]
	if _objects.size() >= MAX_SLOTS:
		return -1
	var instance := {
		"object_id": object_id,
		"instance_id": _next_id,
		"data": data,
		"contents": [],
		"equipped": false,
		"stack_count": count,
		"charges": stacked_charges
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
		"stack_count": 1,
		"charges": item.get("charges", -1)
	}
	_objects.append(new_instance)
	_next_id += 1
	return new_instance["instance_id"]

func move_stack_to_container(moving_id: int, dest_container_id: int, count: int) -> bool:
	var source := find_object_anywhere(moving_id)
	if source.is_empty():
		return false
	var container := find_object_anywhere(dest_container_id)
	if container.is_empty() or container["data"].get("type", "") != "container":
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
			MessageLog.post(MessageRegistry.get_message("inventory_container_too_heavy"))
			return false
	var source_stack: int = source.get("stack_count", 1)
	if count >= source_stack:
		return move_to_container(moving_id, dest_container_id)
	source["stack_count"] = source_stack - count
	var object_id: String = source["object_id"]
	var src_charges: int = int(source.get("charges", -1))
	for content in container["contents"]:
		if content["object_id"] == object_id and not content.get("equipped", false):
			if int(content.get("charges", -1)) == src_charges:
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

func _check_equipment_restriction(item: Dictionary) -> bool:
	if not is_player_inventory:
		return true
	var equipment_type = item["data"].get("equipment_type")
	if equipment_type == null:
		MessageLog.post(MessageRegistry.get_message("equip_not_equippable"))
		return false
	if PlayerStats.current_class_id.is_empty():
		return true
	if GameManager.class_registry == null or not GameManager.class_registry.has_class(PlayerStats.current_class_id):
		if GameManager.class_registry != null:
			push_error("Inventory: class not found in registry: " + PlayerStats.current_class_id)
		return true
	var whitelist: Array = GameManager.class_registry.get_equipment_whitelist(PlayerStats.current_class_id)
	if not whitelist.has(str(equipment_type)):
		MessageLog.post(MessageRegistry.get_message("equip_class_restricted"))
		return false
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
	if not _check_equipment_restriction(item):
		return false
	# All required slots must be free before any are claimed.
	for slot_id in slots:
		if is_slot_occupied(str(slot_id)):
			return false
	# Ammo equips as a whole stack; other stackables split one off.
	var equip_id := instance_id
	var is_ammo: bool = item["data"].get("type", "") == "ammo"
	if item.get("stack_count", 1) > 1 and not is_ammo:
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
	var existing := _find_unequipped_top_level_stack_excluding(item["object_id"], instance_id, int(item.get("charges", -1)))
	if not existing.is_empty():
		existing["stack_count"] = existing.get("stack_count", 1) + item.get("stack_count", 1)
		remove_object(instance_id)

func _unequip_slot_for_instance(instance_id: int) -> void:
	for slot_id in _equipped_by_slot.keys().duplicate():
		var arr: Array = _equipped_by_slot[slot_id]
		for i in range(arr.size()):
			if arr[i] == instance_id:
				arr.remove_at(i)
				if arr.is_empty():
					_equipped_by_slot.erase(slot_id)
				break

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

func split_charged_item(instance_id: int) -> Dictionary:
	var item := find_object_anywhere(instance_id)
	if item.is_empty() or int(item.get("charges", -1)) == -1:
		return item
	var current: int = item.get("stack_count", 1)
	if current <= 1:
		return item
	if _objects.size() >= MAX_SLOTS:
		return {}
	item["stack_count"] = current - 1
	var new_instance := {
		"object_id": item["object_id"],
		"instance_id": _next_id,
		"data": item["data"],
		"contents": [],
		"equipped": false,
		"stack_count": 1,
		"charges": item.get("charges", -1)
	}
	_objects.append(new_instance)
	_next_id += 1
	return new_instance

func restore_objects(saved_items: Array) -> void:
	_objects.clear()
	_equipped_by_slot.clear()
	_next_id = 0
	for item in saved_items:
		_restore_item(item, _objects)

func _restore_item(saved: Dictionary, target: Array) -> void:
	var object_id: String = str(saved.get("object_id", ""))
	if object_id.is_empty():
		return
	var data := get_object_data(object_id)
	if data.is_empty():
		push_error("Inventory: restore_objects: unknown object_id: " + object_id)
		return
	var instance_id: int = _next_id
	_next_id += 1
	var instance := {
		"object_id":   object_id,
		"instance_id": instance_id,
		"data":        data,
		"contents":    [],
		"equipped":    bool(saved.get("equipped", false)),
		"stack_count": maxi(1, int(saved.get("stack_count", 1))),
		"charges":     int(saved.get("charges", -1))
	}
	target.append(instance)
	for child in saved.get("contents", []):
		_restore_item(child, instance["contents"])
	if instance["equipped"]:
		var slots: Array = data.get("equip_slots", [])
		for slot_id in slots:
			var sid := str(slot_id)
			if not _equipped_by_slot.has(sid):
				_equipped_by_slot[sid] = []
			_equipped_by_slot[sid].append(instance_id)
		var modifier_ids = data.get("modifiers")
		if modifier_ids is Array:
			for mod_id in modifier_ids:
				var mid := str(mod_id)
				if PlayerStats.stat_block.has_modifier_def(mid):
					PlayerStats.stat_block.apply_modifier(mid, object_id)

static func get_item_display_name(data: Dictionary) -> String:
	if str(data.get("type", "")) == "scroll":
		var raw_spell_id = data.get("spell_id")
		if raw_spell_id is String and not (raw_spell_id as String).is_empty():
			var spell: Dictionary = SpellManager.get_spell(raw_spell_id as String)
			if not spell.is_empty():
				return "Scroll of " + str(spell.get("name", "Unknown Spell"))
		return "Scroll of Unknown Spell"
	return str(data.get("name", ""))

func get_object_data(object_id: String) -> Dictionary:
	if _cache.has(object_id):
		return _cache[object_id]
	_ensure_registry()
	if not _obj_registry.has(object_id):
		push_error("Inventory: object not found in registry: " + object_id)
		return {}
	var data: Dictionary = resolve_object_definition(_obj_registry[object_id])
	_cache[object_id] = data
	return data
