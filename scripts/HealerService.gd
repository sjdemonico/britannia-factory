class_name HealerService
extends RefCounted

var heal_all_price: int = 0
var cure_all_price: int = 0
var resurrect_price: int = 0

func load_from_npc(npc: NPC) -> void:
	heal_all_price = npc.heal_all_price
	cure_all_price = npc.cure_all_price
	resurrect_price = npc.resurrect_price
