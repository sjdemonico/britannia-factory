class_name NPC
extends CharacterBody2D

signal npc_died(npc_id: String)

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
var hostile: bool = false
var _talkable: bool = true
var _not_talkable_message: String = ""
var _current_activity: String = ""
var _spawn_tile: Vector2i
var _current_path: Array[Vector2i] = []
var _current_destination: Vector2i = Vector2i(-1, -1)
var _max_path_length: int = 0

var combat_dict: Dictionary = {}
var pursuit_ticks_configured: int = 0
var spontaneous: bool = false
var group_base_count_override: int = -1

var _pursuit_active: bool = false
var _pursuit_ticks_remaining: int = 0

func _ready() -> void:
	_spawn_tile = npc_tile
	position = Constants.tile_to_world(npc_tile)
	_load_npc_data()
	WorldState.set_occupant(npc_tile, { "type": "npc", "id": npc_id, "node": self })
	_max_path_length = GameManager.npc_max_path_length
	GameTime.tick_advanced.connect(_on_tick_advanced)
	GameTime.hour_changed.connect(_on_hour_changed)
	npc_died.connect(QuestManager._on_npc_died)
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
	hostile = data.get("hostile", false)
	pursuit_ticks_configured = int(data.get("pursuit_ticks", 0))
	spontaneous = bool(data.get("spontaneous", false))

	if data.has("combat"):
		combat_dict = data["combat"]

	if data.has("schedule"):
		_scheduler.load_schedule(data["schedule"])

	stat_block = StatBlock.new()
	stat_block.load_from_file(Constants.STATS_DATA_PATH + "npc_default.json")
	var overrides: Dictionary = data.get("stat_overrides", {})
	for key in overrides:
		if stat_block.has_stat(key):
			stat_block.set_stat(key, int(overrides[key]))

	npc_inventory = Inventory.new()
	for item_entry in data.get("inventory", []):
		var item_id: String
		var count: int = 1
		var do_equip: bool = false
		if item_entry is String:
			item_id = item_entry
		elif item_entry is Dictionary:
			item_id = str(item_entry.get("object_id", ""))
			count = int(item_entry.get("count", 1))
			do_equip = bool(item_entry.get("equipped", false))
		if item_id.is_empty():
			continue
		var instance_id: int
		if count > 1:
			instance_id = npc_inventory.add_stacked(item_id, count)
		else:
			instance_id = npc_inventory.add_object(item_id)
		if do_equip and instance_id != -1:
			npc_inventory.equip_item(instance_id)

	if data.has("dialogue"):
		dialogue_manager = DialogueManager.new()
		dialogue_manager.npc_id = npc_id
		dialogue_manager.load_from_dict(data["dialogue"])

func remove_from_world() -> void:
	if GameTime.tick_advanced.is_connected(_on_tick_advanced):
		GameTime.tick_advanced.disconnect(_on_tick_advanced)
	if GameTime.hour_changed.is_connected(_on_hour_changed):
		GameTime.hour_changed.disconnect(_on_hour_changed)
	WorldState.clear_occupant(npc_tile)
	queue_free()

func die() -> void:
	if GameTime.tick_advanced.is_connected(_on_tick_advanced):
		GameTime.tick_advanced.disconnect(_on_tick_advanced)
	if GameTime.hour_changed.is_connected(_on_hour_changed):
		GameTime.hour_changed.disconnect(_on_hour_changed)
	var resolved: String = corpse_name if not corpse_name.is_empty() else display_name + "'s corpse"
	var inv: Inventory = npc_inventory if npc_inventory != null else Inventory.new()
	npc_died.emit(npc_id)
	GameManager.spawn_corpse(npc_tile, resolved, inv)
	WorldState.clear_occupant(npc_tile)
	queue_free()

func _despawn() -> void:
	if GameTime.tick_advanced.is_connected(_on_tick_advanced):
		GameTime.tick_advanced.disconnect(_on_tick_advanced)
	if GameTime.hour_changed.is_connected(_on_hour_changed):
		GameTime.hour_changed.disconnect(_on_hour_changed)
	WorldState.clear_occupant(npc_tile)
	queue_free()

func _on_tick_advanced(_total_ticks: int) -> void:
	if _pursuit_active:
		_pursue_tick()
	else:
		_check_combat_initiation()
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

func _pursuit_passability(tile: Vector2i) -> bool:
	if tile == GameManager.get_player_tile():
		return true  # allow player tile so A* can reach goal
	return _passability_check(tile)

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
	_step_to(next_tile)
	if _current_path.is_empty():
		_current_destination = Vector2i(-1, -1)

func _step_to(tile: Vector2i) -> void:
	WorldState.clear_occupant(npc_tile)
	npc_tile = tile
	WorldState.set_occupant(npc_tile, { "type": "npc", "id": npc_id, "node": self })
	position = Constants.tile_to_world(npc_tile)

func _check_combat_initiation() -> void:
	if not hostile or CombatManager.in_combat:
		return
	var player_tile := GameManager.get_player_tile()
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			if npc_tile + Vector2i(dx, dy) == player_tile:
				CombatManager.initiate_combat(self, false)
				return

func start_pursuit(_player_tile: Vector2i, ticks: int) -> void:
	if ticks == 0:
		_evaluate_schedule()
		return
	_pursuit_active = true
	_pursuit_ticks_remaining = ticks
	_current_path = []
	_current_destination = Vector2i(-1, -1)

func _pursue_tick() -> void:
	_check_combat_initiation()
	if CombatManager.in_combat:
		return
	var player_tile := GameManager.get_player_tile()
	var path := Pathfinder.find_path(npc_tile, player_tile, _pursuit_passability, _max_path_length)
	if not path.is_empty():
		var next_tile: Vector2i = path[0]
		if next_tile != player_tile:
			_step_to(next_tile)
	if _pursuit_ticks_remaining > 0:
		_pursuit_ticks_remaining -= 1
		if _pursuit_ticks_remaining == 0:
			_end_pursuit()

func _end_pursuit() -> void:
	_pursuit_active = false
	if spontaneous:
		_despawn()
	else:
		_evaluate_schedule()

func apply_initial_schedule_placement() -> void:
	var entry := _scheduler.get_current_entry(GameTime.get_day_name(), GameTime.get_hour())
	if entry.is_empty():
		return
	var waypoint = entry.get("waypoint")
	if not waypoint is String:
		return
	var dest_tile := GameManager.get_waypoint_position(waypoint, _spawn_tile)
	if dest_tile == npc_tile:
		return
	if WorldState.is_tile_occupied(dest_tile):
		return
	WorldState.clear_occupant(npc_tile)
	npc_tile = dest_tile
	position = Constants.tile_to_world(npc_tile)
	WorldState.set_occupant(npc_tile, { "type": "npc", "id": npc_id, "node": self })
