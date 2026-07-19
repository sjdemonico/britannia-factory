class_name RegionCache
extends RefCounted

var _cache: Dictionary = {}        # region_id -> snapshot Dictionary
var _baselines: Dictionary = {}    # region_id -> baseline JSON Dictionary
var _diffs: Dictionary = {}        # region_id -> RegionDiff
var _order: Array[String] = []     # LRU insertion order (oldest at front)

func has_region(region_id: String) -> bool:
	return _cache.has(region_id)

func store_region(region_id: String, state: Dictionary) -> void:
	if _cache.has(region_id):
		_order.erase(region_id)
	elif _order.size() >= Constants.REGION_CACHE_MAX:
		var evict: String = _order[0]
		_order.remove_at(0)
		_cache.erase(evict)
		_baselines.erase(evict)
		_diffs.erase(evict)
	_cache[region_id] = state
	_order.append(region_id)

func restore_region(region_id: String) -> Dictionary:
	return _cache.get(region_id, {})

func get_cached_region_ids() -> Array[String]:
	return _order.duplicate()

func remove_region(region_id: String) -> void:
	_cache.erase(region_id)
	_order.erase(region_id)

func store_baseline(region_id: String, baseline: Dictionary) -> void:
	if not _baselines.has(region_id) and _baselines.size() >= Constants.REGION_CACHE_MAX:
		var oldest: String = _order[0] if not _order.is_empty() else _baselines.keys()[0]
		_baselines.erase(oldest)
	_baselines[region_id] = baseline

func get_baseline(region_id: String) -> Dictionary:
	return _baselines.get(region_id, {})

func has_baseline(region_id: String) -> bool:
	return _baselines.has(region_id)

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
	_baselines.clear()
	_diffs.clear()
	_order.clear()
