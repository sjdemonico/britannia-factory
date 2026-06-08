extends Node

signal equip_changed

var _inv: Inventory = Inventory.new()

func add_object(object_id: String) -> int:
	if _inv.get_objects().size() >= Inventory.MAX_SLOTS:
		MessageLog.post("You are carrying too much.")
		return -1
	return _inv.add_object(object_id)

func remove_object(instance_id: int) -> bool:
	return _inv.remove_object(instance_id)

func remove_object_anywhere(instance_id: int) -> bool:
	var obj := _inv.find_object_anywhere(instance_id)
	var was_equipped: bool = not obj.is_empty() and obj.get("equipped", false)
	var result := _inv.remove_object_anywhere(instance_id)
	if result and was_equipped:
		equip_changed.emit()
	return result

func get_objects() -> Array:
	return _inv.get_objects()

func get_object_by_instance(instance_id: int) -> Dictionary:
	return _inv.get_object_by_instance(instance_id)

func find_object_anywhere(instance_id: int) -> Dictionary:
	return _inv.find_object_anywhere(instance_id)

func add_to_container(instance_id: int, object_id: String) -> int:
	return _inv.add_to_container(instance_id, object_id)

func remove_from_container(instance_id: int, child_instance_id: int) -> bool:
	return _inv.remove_from_container(instance_id, child_instance_id)

func get_container_contents(instance_id: int) -> Array:
	return _inv.get_container_contents(instance_id)

func get_container_slots(instance_id: int) -> int:
	return _inv.get_container_slots(instance_id)

func move_to_top_level(instance_id: int) -> bool:
	return _inv.move_to_top_level(instance_id)

func move_to_container(instance_id: int, container_instance_id: int) -> bool:
	return _inv.move_to_container(instance_id, container_instance_id)

func set_instance_name(instance_id: int, new_name: String) -> void:
	_inv.set_instance_name(instance_id, new_name)

func get_object_data(object_id: String) -> Dictionary:
	return _inv.get_object_data(object_id)

func get_total_weight() -> float:
	return _inv.get_total_weight()

func add_stacked(object_id: String, count: int) -> int:
	return _inv.add_stacked(object_id, count)

func take_from_stack(instance_id: int, count: int) -> int:
	var obj := _inv.find_object_anywhere(instance_id)
	var was_equipped: bool = not obj.is_empty() and obj.get("equipped", false)
	var taken := _inv.take_from_stack(instance_id, count)
	if taken > 0 and was_equipped:
		equip_changed.emit()
	return taken

func move_stack_to_container(moving_id: int, dest_container_id: int, count: int) -> bool:
	return _inv.move_stack_to_container(moving_id, dest_container_id, count)

func would_exceed_carry_limit(item: WorldObject) -> bool:
	var carry_limit: float = float(PlayerStats.get_effective_value("carry_limit"))
	if carry_limit <= 0.0:
		return false
	return _inv.get_total_weight() + item.get_total_weight() > carry_limit

func equip_item(instance_id: int) -> bool:
	var result := _inv.equip_item(instance_id)
	if result:
		equip_changed.emit()
	return result

func unequip_item(instance_id: int) -> void:
	var obj := _inv.find_object_anywhere(instance_id)
	if obj.is_empty() or not obj.get("equipped", false):
		return
	_inv.unequip_item(instance_id)
	equip_changed.emit()

func get_equipped_items() -> Array:
	return _inv.get_equipped_items()

func is_slot_occupied(slot_id: String) -> bool:
	return _inv.is_slot_occupied(slot_id)

func get_slot_occupancy(slot_id: String) -> int:
	return _inv.get_slot_occupancy(slot_id)

func get_item_in_slot(slot_id: String, idx: int = 0) -> Dictionary:
	return _inv.get_item_in_slot(slot_id, idx)

func split_charged_item(instance_id: int) -> Dictionary:
	return _inv.split_charged_item(instance_id)
