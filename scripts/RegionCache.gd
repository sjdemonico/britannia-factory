class_name RegionCache
extends RefCounted

var _cache: Dictionary = {}
var _diffs: Dictionary = {}  # region_id -> RegionDiff

func has_region(region_id: String) -> bool:
	return _cache.has(region_id)

func store_region(region_id: String, state: Dictionary) -> void:
	_cache[region_id] = state

func restore_region(region_id: String) -> Dictionary:
	return _cache.get(region_id, {})

func remove_region(region_id: String) -> void:
	_cache.erase(region_id)

func store_diff(region_id: String, diff: RegionDiff) -> void:
	_diffs[region_id] = diff

func get_diff(region_id: String) -> RegionDiff:
	return _diffs.get(region_id, null)

func has_diff(region_id: String) -> bool:
	return _diffs.has(region_id)

func clear_diff(region_id: String) -> void:
	_diffs.erase(region_id)

func clear() -> void:
	_cache.clear()
	_diffs.clear()
