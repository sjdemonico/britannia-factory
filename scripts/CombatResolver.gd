class_name CombatResolver
extends RefCounted

var _hit_chance_formula: String = ""
var _hit_chance_min: float = 5.0
var _hit_chance_max: float = 95.0
var _damage_formula: String = ""
var _damage_min: float = 1.0
var _experience_per_kill: int = 10

func load_config() -> void:
	var file := FileAccess.open(Constants.COMBAT_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("CombatResolver: cannot open " + Constants.COMBAT_CONFIG_PATH)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		push_error("CombatResolver: JSON parse error in " + Constants.COMBAT_CONFIG_PATH)
		return
	file.close()
	var data: Dictionary = json.get_data()
	_hit_chance_formula = str(data.get("hit_chance_formula", ""))
	_hit_chance_min = float(data.get("hit_chance_min", 5.0))
	_hit_chance_max = float(data.get("hit_chance_max", 95.0))
	_damage_formula = str(data.get("damage_formula", ""))
	_damage_min = float(data.get("damage_min", 1.0))
	_experience_per_kill = int(data.get("experience_per_kill", 10))

func resolve_hit(variables: Dictionary) -> bool:
	var hit_chance := _evaluate(_hit_chance_formula, variables)
	hit_chance = clampf(hit_chance, _hit_chance_min, _hit_chance_max)
	return randf() * 100.0 < hit_chance

func resolve_damage(variables: Dictionary) -> int:
	var damage := _evaluate(_damage_formula, variables)
	return maxi(int(damage), int(_damage_min))

func get_experience_per_kill() -> int:
	return _experience_per_kill

func pre_attack_checks(attacker: Combatant, defender: Combatant, arena) -> String:
	# Range check (defensive — reticle already enforces this for the player)
	var weapon_range := attacker.get_weapon_range()
	var dist := maxi(
		abs(attacker.current_tile.x - defender.current_tile.x),
		abs(attacker.current_tile.y - defender.current_tile.y)
	)
	if dist > weapon_range:
		return "Target is out of range."

	# Check if attacker has a ranged weapon (ammo_type != null)
	var weapon := attacker.get_equipped_weapon()
	var ammo_type = weapon.get("data", {}).get("ammo_type") if not weapon.is_empty() else null
	if ammo_type == null:
		return ""  # melee — no further checks

	# Ammo check
	if attacker.inventory == null:
		return "You have no ammo."
	var quiver_item: Dictionary = attacker.inventory.get_item_in_slot("quiver")
	if quiver_item.is_empty():
		return "You have no ammo."
	var quiver_ammo_type = quiver_item.get("data", {}).get("ammo_type")
	if quiver_ammo_type != ammo_type:
		return "Your weapon cannot use that ammo."
	var raw_aps = weapon.get("data", {}).get("ammo_per_shot")
	var ammo_per_shot: int = int(raw_aps) if raw_aps != null else 1
	if quiver_item.get("stack_count", 1) < ammo_per_shot:
		return "You do not have enough ammo."

	# Line of sight check
	if arena != null and is_instance_valid(arena):
		var tilemap: TileMapLayer = arena.terrain_layer
		if not LineOfSight.has_line_of_sight(attacker.current_tile, defender.current_tile, tilemap):
			return "Your shot is blocked."

	return ""

func _evaluate(formula: String, variables: Dictionary) -> float:
	if formula.is_empty():
		return 0.0
	var keys: PackedStringArray = PackedStringArray(variables.keys())
	var values: Array = variables.values()
	var expression := Expression.new()
	if expression.parse(formula, keys) != OK:
		push_error("CombatResolver: parse error in formula: " + formula)
		return 0.0
	var result = expression.execute(values)
	if expression.has_execute_failed():
		push_error("CombatResolver: execute error in formula: " + formula)
		return 0.0
	return float(result)
