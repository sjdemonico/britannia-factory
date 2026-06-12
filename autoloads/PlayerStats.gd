extends Node

var stat_block: StatBlock
var display_name: String = "Player"

func _ready() -> void:
	stat_block = StatBlock.new()
	stat_block.load_from_file(Constants.STATS_DATA_PATH + "player.json")

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
