class_name CombatAI
extends RefCounted

var _priority_list: Array = []

func load_from_dict(combat_dict: Dictionary) -> void:
	_priority_list = combat_dict.get("priority_list", [])

func evaluate(combatant: Combatant, target: Combatant, _arena) -> String:
	for entry in _priority_list:
		var conditions = entry.get("conditions")
		if conditions != null:
			if _evaluate_condition(conditions, combatant.stat_block):
				return str(entry.get("action", ""))
	return _default_action(combatant, target)

func _default_action(combatant: Combatant, target: Combatant) -> String:
	var weapon_range := combatant.get_weapon_range()
	var dist := maxi(
		abs(combatant.current_tile.x - target.current_tile.x),
		abs(combatant.current_tile.y - target.current_tile.y)
	)
	return "attack" if dist <= weapon_range else "move_toward_target"

func _evaluate_condition(node: Dictionary, stat_block: StatBlock) -> bool:
	if node.has("operator"):
		var op: String = str(node["operator"])
		var operands: Array = node.get("operands", [])
		match op:
			"AND":
				for operand in operands:
					if not _evaluate_condition(operand, stat_block):
						return false
				return true
			"OR":
				for operand in operands:
					if _evaluate_condition(operand, stat_block):
						return true
				return false
			"NOT":
				if operands.is_empty():
					return false
				return not _evaluate_condition(operands[0], stat_block)
		return false

	var stat_id: String = str(node.get("stat", ""))
	var compare: String = str(node.get("compare", ""))
	if not stat_block.has_stat(stat_id):
		return false

	var current_value: float = float(stat_block.get_effective_value(stat_id))
	var threshold: float
	if node.has("threshold_percent"):
		threshold = float(stat_block.get_max(stat_id)) * float(node["threshold_percent"]) / 100.0
	else:
		threshold = float(node.get("threshold", 0))

	match compare:
		"lt":  return current_value < threshold
		"lte": return current_value <= threshold
		"gt":  return current_value > threshold
		"gte": return current_value >= threshold
		"eq":  return current_value == threshold
		"neq": return current_value != threshold
	return false

