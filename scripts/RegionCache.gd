class_name RegionCache
extends RefCounted

var _cache: Dictionary = {}

func has_region(region_id: String) -> bool:
	return _cache.has(region_id)

func store_region(region_id: String, state: Dictionary) -> void:
	_cache[region_id] = state

func restore_region(region_id: String) -> Dictionary:
	return _cache.get(region_id, {})

func clear() -> void:
	_cache.clear()
