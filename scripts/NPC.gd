class_name NPC
extends CharacterBody2D

@export var npc_id: String = ""
@export var npc_tile: Vector2i = Vector2i(0, 0)
@export var display_name_override: String = ""

var display_name: String = ""
var flavor_text: String = ""
var corpse_name: String = ""
var stat_block: StatBlock
var npc_inventory: Inventory
var dialogue_manager: DialogueManager
var _scheduler: NPCScheduler
var _talkable: bool = true
var _not_talkable_message: String = ""
var _current_activity: String = ""
var _spawn_tile: Vector2i
var _current_path: Array[Vector2i] = []
var _current_destination: Vector2i = Vector2i(-1, -1)
var _max_path_length: int = 0

func _ready() -> void:
	_spawn_tile = npc_tile
	position = tile_to_world(npc_tile)
	_load_npc_data()
	WorldState.set_occupant(npc_tile, { "type": "npc", "id": npc_id, "node": self })
	WorldState.register_npc_tile(npc_tile, self)
	_max_path_length = GameManager.npc_max_path_length
	GameTime.tick_advanced.connect(_on_tick_advanced)
	GameTime.hour_changed.connect(_on_hour_changed)
	_evaluate_schedule.call_deferred()

func _load_npc_data() -> void:
	var path := "res://data/npcs/" + npc_id + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	_scheduler = NPCScheduler.new()
	if file == null:
		push_error("NPC: could not open: " + path)
		display_name = display_name_override if not display_name_override.is_empty() else npc_id
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("NPC: JSON parse error in: " + path)
		display_name = display_name_override if not display_name_override.is_empty() else npc_id
		return
	var data: Dictionary = json.get_data()

	display_name = display_name_override if not display_name_override.is_empty() else data.get("name", npc_id)
	flavor_text = data.get("flavor_text", "")
	corpse_name = data.get("corpse_name", "")

	if data.has("schedule"):
		_scheduler.load_schedule(data["schedule"])

	stat_block = StatBlock.new()
	stat_block.load_from_file(Constants.STATS_DATA_PATH + "npc_default.json")
	var overrides: Dictionary = data.get("stat_overrides", {})
	for key in overrides:
		if stat_block.has_stat(key):
			stat_block.set_stat(key, int(overrides[key]))

	npc_inventory = Inventory.new()
	for item_id in data.get("inventory", []):
		npc_inventory.add_object(str(item_id))

	if data.has("dialogue"):
		dialogue_manager = DialogueManager.new()
		dialogue_manager.load_from_dict(data["dialogue"])

func die() -> void:
	GameTime.tick_advanced.disconnect(_on_tick_advanced)
	GameTime.hour_changed.disconnect(_on_hour_changed)
	var resolved: String = corpse_name if not corpse_name.is_empty() else display_name + "'s corpse"
	var inv: Inventory = npc_inventory if npc_inventory != null else Inventory.new()
	GameManager.spawn_corpse(npc_tile, resolved, inv)
	WorldState.unregister_npc_tile(npc_tile)
	WorldState.clear_occupant(npc_tile)
	queue_free()

func _on_tick_advanced(_total_ticks: int) -> void:
	attempt_move()

func _on_hour_changed(_hour: int) -> void:
	_evaluate_schedule()

func _evaluate_schedule() -> void:
	var entry := _scheduler.get_current_entry(GameTime.get_day_name(), GameTime.get_hour())
	if entry.is_empty():
		return
	_current_activity = entry.get("activity", "")
	_talkable = entry.get("talkable", true)
	var raw_msg = entry.get("not_talkable_message")
	_not_talkable_message = raw_msg if raw_msg is String else ""
	var waypoint = entry.get("waypoint")
	if waypoint is String:
		var dest := GameManager.get_waypoint_position(waypoint, _spawn_tile)
		set_destination(dest)

func get_not_talkable_message() -> String:
	if _not_talkable_message.is_empty():
		return GameManager.not_talkable_default
	return _not_talkable_message

func set_destination(tile: Vector2i) -> void:
	var path := Pathfinder.find_path(npc_tile, tile, _passability_check, _max_path_length)
	if path.is_empty():
		_current_path = []
		_current_destination = Vector2i(-1, -1)
		return
	_current_path = path
	_current_destination = tile

func _passability_check(tile: Vector2i) -> bool:
	if not GameManager.is_tile_passable(tile):
		return false
	if WorldState.is_tile_occupied_by_npc(tile) and tile != _current_destination:
		return false
	if tile == GameManager.get_player_tile():
		return false
	return true

func attempt_move() -> void:
	if _current_path.is_empty():
		return
	var next_tile: Vector2i = _current_path[0]
	if not GameManager.is_tile_passable(next_tile):
		return
	if WorldState.is_tile_occupied_by_npc(next_tile):
		return
	if next_tile == GameManager.get_player_tile():
		return
	_current_path.remove_at(0)
	WorldState.clear_occupant(npc_tile)
	WorldState.unregister_npc_tile(npc_tile)
	npc_tile = next_tile
	WorldState.set_occupant(npc_tile, { "type": "npc", "id": npc_id, "node": self })
	WorldState.register_npc_tile(npc_tile, self)
	position = tile_to_world(npc_tile)
	if _current_path.is_empty():
		_current_destination = Vector2i(-1, -1)

func tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2(tile * Constants.TILE_SIZE) + Vector2(Constants.TILE_SIZE / 2.0, Constants.TILE_SIZE / 2.0)
