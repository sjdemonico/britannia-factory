class_name PartyMember
extends RefCounted

static var _id_counter: int = 0

var member_id: String = ""
var display_name: String = ""
var stat_block: StatBlock = null
var inventory: Inventory = null
var class_id: String = ""
var known_spells: Array = []
var is_downed: bool = false
var source_npc_id: String = ""
var spawn_tile: Vector2i = Vector2i(-1, -1)
var spawn_region_id: String = ""

func initialize_as_player(p_name: String, p_class_id: String) -> void:
	member_id = Constants.PLAYER_MEMBER_ID
	display_name = p_name
	stat_block = StatBlock.new()
	stat_block.load_from_file(Constants.STATS_DATA_PATH + "player_stats.json")
	inventory = Inventory.new()
	inventory.is_player_inventory = true
	var player_data: Dictionary = Constants.load_json(Constants.PLAYER_DATA_PATH)
	for item_id in player_data.get("inventory", []):
		inventory.add_object(str(item_id))
	class_id = p_class_id
	known_spells = []

func initialize_from_npc(npc: Node) -> void:
	member_id = str(npc.npc_id) + "_" + str(PartyMember._id_counter)
	PartyMember._id_counter += 1
	display_name = str(npc.display_name)
	stat_block = npc.stat_block
	inventory = npc.npc_inventory
	var raw_class_id = npc.get("class_id")
	class_id = str(raw_class_id) if raw_class_id != null and raw_class_id is String else ""
	known_spells = []
	is_downed = false
	source_npc_id = str(npc.npc_id)
	spawn_tile = npc.npc_tile
	spawn_region_id = GameManager.get_current_region_id()
