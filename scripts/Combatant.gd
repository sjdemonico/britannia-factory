class_name Combatant
extends RefCounted

var display_name: String = ""
var stat_block: StatBlock
var inventory         # untyped — Inventory or PlayerInventory node
var initiative: int = 0
var is_player: bool = false
var current_tile: Vector2i = Vector2i.ZERO
var is_dead: bool = false
var is_fled: bool = false
var ai: CombatAI = null
var node              # untyped — CharacterBody2D subclass, duck-typed

func roll_initiative() -> void:
	initiative = stat_block.get_effective_value("initiative") + randi() % 10

func get_weapon_range() -> int:
	if inventory == null:
		return 1
	var max_range: int = 0
	for item in inventory.get_equipped_items():
		var r = item.get("data", {}).get("range")
		if r != null:
			max_range = maxi(max_range, int(r))
	return max_range if max_range > 0 else 1

func get_equipped_weapon() -> Dictionary:
	if inventory == null:
		return {}
	for item in inventory.get_equipped_items():
		if item.get("data", {}).get("type", "") == "weapon":
			return item
	return {}
