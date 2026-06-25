extends Node

signal class_changed(class_id: String)
signal name_changed(new_name: String)
signal stat_changed(stat_id: String, old_val: int, new_val: int)

# Fallback fields used before PartyManager._ready() runs (e.g. during
# GameManager._ready() → _validate_registries()).  PartyManager._ready()
# adopts _stat_block into the player member so the same object is used
# throughout; _display_name and _current_class_id serve only as placeholders.
var _stat_block: StatBlock = null
var _display_name: String = "Player"
var _current_class_id: String = ""

var stat_block: StatBlock:
	get:
		var player := PartyManager.get_player()
		if player != null:
			return player.stat_block
		return _stat_block

var display_name: String:
	get:
		var player := PartyManager.get_player()
		if player != null:
			return player.display_name
		return _display_name
	set(value):
		var player := PartyManager.get_player()
		if player != null:
			player.display_name = value
		else:
			_display_name = value
		name_changed.emit(value)

var current_class_id: String:
	get:
		var player := PartyManager.get_player()
		if player != null:
			return player.class_id
		return _current_class_id
	set(value):
		var player := PartyManager.get_player()
		if player != null:
			player.class_id = value
		else:
			_current_class_id = value

var _forwarding_stat_block: StatBlock = null

func _ready() -> void:
	_stat_block = StatBlock.new()
	_stat_block.load_from_file(Constants.STATS_DATA_PATH + "player.json")

func reconnect_stat_block() -> void:
	if _forwarding_stat_block != null and is_instance_valid(_forwarding_stat_block):
		if _forwarding_stat_block.stat_changed.is_connected(_forward_stat_changed):
			_forwarding_stat_block.stat_changed.disconnect(_forward_stat_changed)
	_forwarding_stat_block = stat_block
	if _forwarding_stat_block != null:
		_forwarding_stat_block.stat_changed.connect(_forward_stat_changed)

func _forward_stat_changed(stat_id: String, old_val: int, new_val: int) -> void:
	stat_changed.emit(stat_id, old_val, new_val)

func get_stat(stat_id: String) -> int:
	return stat_block.get_value(stat_id)

func get_max(stat_id: String) -> int:
	return stat_block.get_max(stat_id)

func has_stat(stat_id: String) -> bool:
	return stat_block.has_stat(stat_id)

func format_stat(stat_id: String) -> String:
	return stat_block.format_stat(stat_id)

func format_effective_stat(stat_id: String) -> String:
	return stat_block.format_effective_stat(stat_id)

func get_visible_stats() -> Array:
	return stat_block.get_visible_stats()

func set_stat(stat_id: String, value: int) -> void:
	stat_block.set_stat(stat_id, value)

func modify_stat(stat_id: String, delta: int) -> void:
	stat_block.modify_stat(stat_id, delta)

func apply_modifier(modifier_id: String, source_tag: String) -> int:
	return stat_block.apply_modifier(modifier_id, source_tag)

func remove_modifier(instance_id: int) -> bool:
	return stat_block.remove_modifier(instance_id)

func get_effective_value(stat_id: String) -> int:
	return stat_block.get_effective_value(stat_id)

func get_active_modifiers() -> Array:
	return stat_block.get_active_modifiers()

func suppress_regen(source_tag: String) -> void:
	stat_block.suppress_regen(source_tag)

func unsuppress_regen(source_tag: String) -> void:
	stat_block.unsuppress_regen(source_tag)

func is_regen_suppressed() -> bool:
	return stat_block.is_regen_suppressed()

func set_current_class(class_id: String) -> void:
	current_class_id = class_id
	class_changed.emit(class_id)

func get_class_display_name() -> String:
	if current_class_id.is_empty() or GameManager.class_registry == null:
		return ""
	return GameManager.class_registry.get_class_data(current_class_id).get("name", "")

func get_stat_display_name(stat_id: String) -> String:
	var sb := stat_block
	if sb == null or not sb._stats.has(stat_id):
		return stat_id
	return str(sb._stats[stat_id].get("name", stat_id))

func is_stat_visible(stat_id: String) -> bool:
	var sb := stat_block
	if sb == null or not sb._stats.has(stat_id):
		return false
	return bool(sb._stats[stat_id].get("visible", true))
