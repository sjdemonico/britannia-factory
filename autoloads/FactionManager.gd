extends Node

signal standing_changed(faction_id: String, old_value: int, new_value: int)

var _standings: Dictionary = {}
var _npc_factions: Dictionary = {}
var _factions: Array = []
var _scale_min: int = 0
var _scale_max: int = 100
var _tiers: Array[Dictionary] = []
var _modified_factions: Array[String] = []

func _ready() -> void:
	load_from_file(Constants.FACTIONS_CONFIG_PATH)

func load_from_file(path: String) -> bool:
	var data := Constants.load_json(path)
	if data.is_empty():
		push_error("FactionManager: failed to load " + path)
		return false
	var scale: Dictionary = data.get("scale", {})
	_scale_min = int(scale.get("min", 0))
	_scale_max = int(scale.get("max", 100))
	_tiers = []
	for tier in scale.get("tiers", []):
		if tier is Dictionary:
			_tiers.append(tier as Dictionary)
	_factions = []
	_npc_factions = {}
	for f in data.get("factions", []):
		if not f is Dictionary:
			continue
		_factions.append(f as Dictionary)
		var fid: String = str(f.get("faction_id", ""))
		if fid.is_empty():
			continue
		for npc_id in f.get("member_npc_ids", []):
			var nid: String = str(npc_id)
			if not _npc_factions.has(nid):
				_npc_factions[nid] = []
			var nid_arr: Array = _npc_factions[nid]
			nid_arr.append(fid)
	initialize_standings()
	return true

func initialize_standings() -> void:
	_standings = {}
	_modified_factions = []
	for f in _factions:
		var fid: String = str(f.get("faction_id", ""))
		if not fid.is_empty():
			_standings[fid] = int(f.get("default_standing", 50))

func get_standing(faction_id: String) -> int:
	return int(_standings.get(faction_id, 0))

func set_standing(faction_id: String, value: int) -> void:
	if not _standings.has(faction_id):
		return
	var old_value: int = int(_standings[faction_id])
	var new_value: int = clampi(value, _scale_min, _scale_max)
	if old_value == new_value:
		return
	_standings[faction_id] = new_value
	if new_value != _get_default_standing(faction_id) and not _modified_factions.has(faction_id):
		_modified_factions.append(faction_id)
	standing_changed.emit(faction_id, old_value, new_value)

func _get_default_standing(faction_id: String) -> int:
	for f in _factions:
		if str(f.get("faction_id", "")) == faction_id:
			return int(f.get("default_standing", 50))
	return 50

func modify_standing(faction_id: String, amount: int) -> void:
	if not _standings.has(faction_id):
		return
	set_standing(faction_id, int(_standings[faction_id]) + amount)

func get_tier(faction_id: String) -> Dictionary:
	return get_tier_for_value(get_standing(faction_id))

func get_tier_for_value(value: int) -> Dictionary:
	for tier in _tiers:
		if value >= int(tier.get("min", 0)) and value <= int(tier.get("max", 100)):
			return tier
	return {}

func get_tier_name(faction_id: String) -> String:
	return str(get_tier(faction_id).get("name", ""))

func get_faction_name(faction_id: String) -> String:
	for f in _factions:
		if str(f.get("faction_id", "")) == faction_id:
			return str(f.get("name", faction_id))
	return faction_id

func is_hostile(faction_id: String) -> bool:
	var tier := get_tier(faction_id)
	return int(tier.get("min", 0)) == _scale_min and not tier.is_empty()

func get_factions_for_npc(npc_id: String) -> Array[String]:
	var result: Array[String] = []
	var raw: Variant = _npc_factions.get(npc_id, [])
	if raw is Array:
		for fid in raw as Array:
			result.append(str(fid))
	return result

func get_serializable_standings() -> Dictionary:
	var result: Dictionary = {}
	for fid in _standings:
		result[fid] = _standings[fid]
	return result

func restore_standings(data: Dictionary) -> void:
	for fid in data:
		var key: String = str(fid)
		if _standings.has(key):
			_standings[key] = clampi(int(data[fid]), _scale_min, _scale_max)
	_rebuild_modified_factions()

func _rebuild_modified_factions() -> void:
	_modified_factions = []
	for f in _factions:
		var fid: String = str(f.get("faction_id", ""))
		if fid.is_empty():
			continue
		var default_val: int = int(f.get("default_standing", 50))
		if int(_standings.get(fid, default_val)) != default_val:
			_modified_factions.append(fid)

func get_modified_factions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for fid in _modified_factions:
		for f in _factions:
			if str(f.get("faction_id", "")) == fid:
				result.append(f as Dictionary)
				break
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	return result
