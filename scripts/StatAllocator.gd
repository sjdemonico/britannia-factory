class_name StatAllocator
extends RefCounted

var class_id: String = ""
var _ranges: Dictionary = {}      # stat_id -> { "min": int, "max": int }
var _budget: int = -1
var _allocated: Dictionary = {}   # stat_id -> current allocated value
var _budget_spent: int = 0

func load_class(cid: String) -> void:
	class_id = cid
	_ranges = {}
	_allocated = {}
	_budget_spent = 0
	_budget = -1
	if GameManager.class_registry == null:
		push_error("StatAllocator: class_registry not initialized")
		return
	if not GameManager.class_registry.has_class(cid):
		push_error("StatAllocator: class not found: " + cid)
		return
	var cls: Dictionary = GameManager.class_registry.get_class_data(cid)
	var raw_budget = cls.get("stat_budget")
	_budget = int(raw_budget) if raw_budget != null else -1
	var raw_ranges: Dictionary = GameManager.class_registry.get_stat_ranges(cid)
	for stat_id in raw_ranges:
		var r = raw_ranges[stat_id]
		_ranges[stat_id] = {"min": int(r.get("min", 0)), "max": int(r.get("max", 999))}
	var starting: Dictionary = GameManager.class_registry.get_starting_stats(cid)
	for stat_id in _ranges:
		_allocated[stat_id] = int(starting.get(stat_id, _ranges[stat_id]["min"]))

func can_increment(stat_id: String) -> bool:
	if not _allocated.has(stat_id):
		return false
	if _allocated[stat_id] >= _ranges[stat_id]["max"]:
		return false
	if _budget >= 0 and _budget_spent >= _budget:
		return false
	return true

func can_decrement(stat_id: String) -> bool:
	if not _allocated.has(stat_id):
		return false
	return _allocated[stat_id] > _ranges[stat_id]["min"]

func increment(stat_id: String) -> void:
	if not can_increment(stat_id):
		return
	_allocated[stat_id] += 1
	_budget_spent += 1

func decrement(stat_id: String) -> void:
	if not can_decrement(stat_id):
		return
	_allocated[stat_id] -= 1
	_budget_spent -= 1

func get_allocated(stat_id: String) -> int:
	return _allocated.get(stat_id, 0)

func get_budget_remaining() -> int:
	if _budget < 0:
		return -1
	return _budget - _budget_spent

func is_valid() -> bool:
	for stat_id in _allocated:
		var val: int = _allocated[stat_id]
		if val < _ranges[stat_id]["min"] or val > _ranges[stat_id]["max"]:
			return false
	if _budget >= 0 and _budget_spent > _budget:
		return false
	return true

func apply_to_player() -> void:
	if not is_valid():
		push_error("StatAllocator: cannot apply — allocation is invalid")
		return
	for stat_id in _allocated:
		if PlayerStats.has_stat(stat_id):
			PlayerStats.stat_block.set_stat(stat_id, _allocated[stat_id])
