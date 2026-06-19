class_name CombatAI
extends RefCounted

var _priority_list: Array = []

func load_from_dict(combat_dict: Dictionary) -> void:
	_priority_list = combat_dict.get("priority_list", [])

# Returns the first priority-list entry whose conditions pass, or a default
# entry containing only {"action": "attack"/"move_toward_target"}.
# Callers read entry.get("action") and, for "cast_spell", entry.get("spell_id").
func choose_action_entry(combatant: Combatant, target: Combatant, _arena) -> Dictionary:
	for entry in _priority_list:
		var conditions = entry.get("conditions")
		if conditions != null:
			if _evaluate_condition(conditions, combatant.stat_block):
				return (entry as Dictionary).duplicate()
	return {"action": _default_action(combatant, target)}

# Called by CombatManager when choose_action_entry returns action="cast_spell".
# Validates mana, computes AE, applies faction filter, consumes mana, executes effects.
func execute_cast_spell(combatant: Combatant, target: Combatant, spell_id: String, arena) -> void:
	var spell: Dictionary = SpellManager.get_spell(spell_id)
	if spell.is_empty():
		push_warning("CombatAI: unknown spell '" + spell_id + "'")
		return
	var casting_cost: int = int(spell.get("casting_cost", 0))
	if combatant.stat_block.get_effective_value("mana") < casting_cost:
		push_warning("CombatAI: " + combatant.display_name + " has insufficient mana for " + spell_id)
		return

	var caster_tile: Vector2i = combatant.current_tile
	var targeting_type: String = str(spell.get("targeting_type", "targeted"))
	var target_tile: Vector2i
	match targeting_type:
		"point_blank", "none", "self":
			target_tile = caster_tile
		_:
			target_tile = target.current_tile if target != null else caster_tile

	var ae_tiles := SpellTargeting.compute_ae_tiles(spell, caster_tile, target_tile, null)
	var filtered_entities: Array = arena.filter_affected_entities(ae_tiles, "enemy") if arena != null else []

	combatant.stat_block.modify_stat("mana", -casting_cost)

	var target_node: Node = target.node if target != null else null
	if not filtered_entities.is_empty() or is_instance_valid(target_node):
		var effects: Array = spell.get("effects", []) if spell.get("effects") is Array else []
		var executor := SpellEffectExecutor.new()
		executor.execute_effects(
			effects,
			combatant.node,
			target_node,
			target_tile,
			"combat",
			ae_tiles,
			filtered_entities
		)

	MessageLog.post(MessageRegistry.get_message("npc_cast_spell", {
		"name": combatant.display_name,
		"spell": str(spell.get("name", spell_id))
	}))
	MessageLog.post("")

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
