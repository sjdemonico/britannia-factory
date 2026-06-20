class_name LockManager
extends RefCounted

# Set before calling attempt_unlock when using a lockpick (inventory item dict).
var _lockpick_data: Dictionary = {}

# ── public API ────────────────────────────────────────────────────────────────

func attempt_unlock(_actor: Node, target: WorldObject, key_item: Dictionary = {}) -> bool:
	if target.lock_id.is_empty():
		MessageLog.post(MessageRegistry.get_message("lock_cannot_lock"))
		MessageLog.post("")
		return false
	if not target.is_locked:
		MessageLog.post(MessageRegistry.get_message("lock_not_locked"))
		MessageLog.post("")
		return false
	if not key_item.is_empty():
		var lock_ids: Array = key_item.get("data", {}).get("lock_ids", [])
		if not target.lock_id in lock_ids:
			MessageLog.post(MessageRegistry.get_message("lock_wrong_key"))
			MessageLog.post("")
			return false
		target.is_locked = false
		MessageLog.post(MessageRegistry.get_message("lock_unlocked_key", {"name": target.get_display_name()}))
		MessageLog.post("")
		return true
	if not _lockpick_data.is_empty():
		if _roll_lockpick_success():
			target.is_locked = false
			MessageLog.post(MessageRegistry.get_message("lock_picked"))
			MessageLog.post("")
			return true
		MessageLog.post(MessageRegistry.get_message("lock_pick_failed"))
		MessageLog.post("")
		_roll_lockpick_break()
		return false
	# Spell context: unlock directly
	target.is_locked = false
	MessageLog.post(MessageRegistry.get_message("lock_unlocked_spell", {"name": target.get_display_name()}))
	MessageLog.post("")
	return true

func attempt_lock(_actor: Node, target: WorldObject, key_item: Dictionary = {}) -> bool:
	if target.lock_id.is_empty():
		MessageLog.post(MessageRegistry.get_message("lock_cannot_lock"))
		MessageLog.post("")
		return false
	if target.is_locked:
		MessageLog.post(MessageRegistry.get_message("lock_already_locked"))
		MessageLog.post("")
		return false
	if not key_item.is_empty():
		var lock_ids: Array = key_item.get("data", {}).get("lock_ids", [])
		if not target.lock_id in lock_ids:
			MessageLog.post(MessageRegistry.get_message("lock_wrong_key"))
			MessageLog.post("")
			return false
	if target.is_open:
		target.is_open = false
		target.queue_redraw()
		MessageLog.post(MessageRegistry.get_message("door_closed", {"name": target.get_display_name()}))
	target.is_locked = true
	MessageLog.post(MessageRegistry.get_message("lock_locked", {"name": target.get_display_name()}))
	MessageLog.post("")
	return true

# ── private helpers ───────────────────────────────────────────────────────────

func _roll_lockpick_success() -> bool:
	var data: Dictionary = _lockpick_data.get("data", {})
	var stat_id: String = str(data.get("success_stat", ""))
	var threshold: int = int(data.get("success_threshold", 1))
	if stat_id.is_empty() or not PlayerStats.has_stat(stat_id):
		return false
	var value: float = float(PlayerStats.get_effective_value(stat_id))
	if value >= float(threshold):
		return true
	if threshold <= 0:
		return false
	return randf() < value / float(threshold)

func _roll_lockpick_break() -> bool:
	var data: Dictionary = _lockpick_data.get("data", {})
	var break_chance: float = float(data.get("break_chance", 0.0))
	if randf() < break_chance:
		var instance_id: int = int(_lockpick_data.get("instance_id", -1))
		if instance_id != -1:
			PlayerInventory.take_from_stack(instance_id, 1)
		MessageLog.post(MessageRegistry.get_message("lock_pick_broken"))
		return true
	return false
