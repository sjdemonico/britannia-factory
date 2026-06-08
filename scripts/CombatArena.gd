extends Node2D

const ARENA_WIDTH: int = 27
const ARENA_HEIGHT: int = 21

const _TILE_ATLAS: Dictionary = {
	"grass":    Vector2i(0, 0),
	"mountain": Vector2i(1, 0),
	"dirt":     Vector2i(2, 0),
	"water":    Vector2i(3, 0),
	"swamp":    Vector2i(4, 0),
	"forest":   Vector2i(5, 0),
	"hill":     Vector2i(6, 0)
}

const _ENTRY_TILES: Dictionary = {
	"south": Vector2i(13, 20),
	"north": Vector2i(13, 0),
	"west":  Vector2i(0, 10),
	"east":  Vector2i(26, 10)
}

const _OPPOSITE: Dictionary = {
	"south": "north",
	"north": "south",
	"west":  "east",
	"east":  "west"
}

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var actors: Node2D = $Actors

var _combatants: Array = []
var _player_combatant: Combatant = null
var _player_node  # untyped — CharacterBody2D with Player.gd, duck-typed

var _player_turn_active: bool = false
var _victory: bool = false

# Draw state
var _overlay: Node2D
var _active_combatant_pos: Vector2 = Vector2.ZERO
var _show_active_frame: bool = false
var _reticle_active: bool = false
var _reticle_tile: Vector2i = Vector2i.ZERO
var _weapon_range: int = 1
var _animating: bool = false
var _projectile_active: bool = false
var _projectile_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	_setup_tileset()
	_player_node = $Actors/Player
	var cam = _player_node.get_node("Camera2D")
	Constants.apply_camera_limits(cam, ARENA_WIDTH, ARENA_HEIGHT)
	# Overlay added last so it paints on top of TerrainLayer and Actors
	_overlay = Node2D.new()
	add_child(_overlay)
	_overlay.draw.connect(_on_overlay_draw)
	var objects := Node2D.new()
	objects.name = "Objects"
	add_child(objects)
	GameManager.load_region("combat_arena")
	initialize(CombatManager.combatants, CombatManager.player_entry_edge, CombatManager._pending_world_tile_type)

func initialize(combatant_defs: Array, entry_edge: String, world_tile_type: String) -> void:
	var generator := ArenaGenerator.new()
	generator.load_config()
	var grid := generator.generate(world_tile_type, ARENA_WIDTH, ARENA_HEIGHT)
	_paint_grid(grid)

	var entry_tile: Vector2i = _ENTRY_TILES.get(entry_edge, Vector2i(13, 20))
	_player_node.teleport_to_tile(entry_tile)

	var pc := Combatant.new()
	pc.is_player = true
	pc.display_name = "You"
	pc.stat_block = PlayerStats.stat_block
	pc.inventory = PlayerInventory
	pc.current_tile = entry_tile
	pc.node = _player_node
	_combatants.append(pc)
	_player_combatant = pc

	_spawn_combatants(combatant_defs, entry_edge)
	CombatManager.start_combat(_combatants, self)

func _spawn_combatants(combatant_defs: Array, entry_edge: String) -> void:
	var npc_scene := load(Constants.NPC_SCENE_PATH) as PackedScene
	if npc_scene == null:
		return
	var opposite: String = _OPPOSITE.get(entry_edge, "north")
	for def in combatant_defs:
		var npc_id: String = str(def.get("npc_id", ""))
		if npc_id.is_empty():
			continue
		var tile := _pick_enemy_tile(opposite)
		var npc = npc_scene.instantiate()
		npc.npc_id = npc_id
		npc.npc_tile = tile
		actors.add_child(npc)
		# Disconnect from world time — CombatManager drives NPC turns in arena
		var tick_cb := Callable(npc, "_on_tick_advanced")
		var hour_cb := Callable(npc, "_on_hour_changed")
		if GameTime.tick_advanced.is_connected(tick_cb):
			GameTime.tick_advanced.disconnect(tick_cb)
		if GameTime.hour_changed.is_connected(hour_cb):
			GameTime.hour_changed.disconnect(hour_cb)

		var combatant := Combatant.new()
		combatant.is_player = false
		combatant.display_name = npc.display_name
		combatant.stat_block = npc.stat_block
		combatant.inventory = npc.npc_inventory
		combatant.current_tile = tile
		combatant.node = npc

		var ai := CombatAI.new()
		if not npc.combat_dict.is_empty():
			ai.load_from_dict(npc.combat_dict)
		combatant.ai = ai

		_combatants.append(combatant)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_character_panel"):
		return
	if _animating:
		get_viewport().set_input_as_handled()
		return
	if _victory:
		var dir := _get_direction(event)
		if dir != Vector2i.ZERO:
			_handle_player_move(dir)
		get_viewport().set_input_as_handled()
		return

	if not _player_turn_active:
		get_viewport().set_input_as_handled()
		return

	if _reticle_active:
		if event.is_action_pressed("ui_cancel"):
			_reticle_active = false
			_overlay.queue_redraw()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_accept"):
			_handle_reticle_confirm()
			get_viewport().set_input_as_handled()
			return
		var dir := _get_direction(event)
		if dir != Vector2i.ZERO:
			_handle_reticle_move(dir)
			get_viewport().set_input_as_handled()
			return
	else:
		if event.is_action_pressed("attack"):
			_activate_reticle()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("wait"):
			_end_player_turn()
			get_viewport().set_input_as_handled()
			return
		var dir := _get_direction(event)
		if dir != Vector2i.ZERO:
			_handle_player_move(dir)
			get_viewport().set_input_as_handled()
			return

	get_viewport().set_input_as_handled()

func _on_overlay_draw() -> void:
	var half := float(Constants.TILE_SIZE) * 0.5
	var size := Vector2(float(Constants.TILE_SIZE), float(Constants.TILE_SIZE))
	if _show_active_frame:
		_overlay.draw_rect(Rect2(_active_combatant_pos - Vector2(half, half), size), Color(1.0, 1.0, 0.0, 0.8), false, 2.0)
	if _reticle_active:
		var rpos := Constants.tile_to_world(_reticle_tile)
		_overlay.draw_rect(Rect2(rpos - Vector2(half, half), size), Color(1.0, 0.5, 0.0, 0.9), false, 2.0)
	if _projectile_active:
		_overlay.draw_circle(_projectile_pos, 4.0, Color(0.95, 0.85, 0.2, 1.0))

func highlight_active_combatant(combatant: Combatant) -> void:
	if is_instance_valid(combatant.node):
		_active_combatant_pos = combatant.node.position
	_show_active_frame = true
	_overlay.queue_redraw()

func start_player_turn(_combatant: Combatant) -> void:
	_player_combatant.current_tile = _player_node.tile_pos
	_weapon_range = _get_player_weapon_range()
	_player_turn_active = true

func on_combat_victory() -> void:
	_victory = true
	_show_active_frame = false
	_player_turn_active = false
	_overlay.queue_redraw()

func _end_player_turn() -> void:
	_player_turn_active = false
	_reticle_active = false
	_overlay.queue_redraw()
	CombatManager.on_player_action_taken()

func _handle_player_move(dir: Vector2i) -> void:
	var target_tile := _player_combatant.current_tile + dir
	if _check_arena_exit(target_tile, dir):
		return
	if not GameManager.is_tile_passable(target_tile):
		MessageLog.post("You cannot move there.")
		return
	if WorldState.is_tile_occupied_by_npc(target_tile):
		MessageLog.post("You cannot move there.")
		return
	_player_node.teleport_to_tile(target_tile)
	_player_combatant.current_tile = target_tile
	if not _victory:
		_end_player_turn()

func _check_arena_exit(target_tile: Vector2i, dir: Vector2i) -> bool:
	if target_tile.x >= 0 and target_tile.x < ARENA_WIDTH and target_tile.y >= 0 and target_tile.y < ARENA_HEIGHT:
		return false
	var all_dead := true
	for c in _combatants:
		var cb: Combatant = c
		if not cb.is_player and not cb.is_dead and not cb.is_fled:
			all_dead = false
			break
	CombatManager.end_combat(not all_dead, dir)
	return true

func _activate_reticle() -> void:
	_reticle_tile = _player_combatant.current_tile
	_reticle_active = true
	_overlay.queue_redraw()
	MessageLog.post("Attack! Where?")

func _handle_reticle_move(dir: Vector2i) -> void:
	var new_tile := _reticle_tile + dir
	var dist := maxi(abs(new_tile.x - _player_combatant.current_tile.x),
	                 abs(new_tile.y - _player_combatant.current_tile.y))
	if dist <= _weapon_range:
		_reticle_tile = new_tile
		_overlay.queue_redraw()

func animate_projectile(from_tile: Vector2i, to_tile: Vector2i) -> void:
	var from_world := Constants.tile_to_world(from_tile)
	var to_world := Constants.tile_to_world(to_tile)
	_projectile_pos = from_world
	_projectile_active = true
	_overlay.queue_redraw()
	var tween := create_tween()
	tween.tween_method(func(pos: Vector2) -> void:
		_projectile_pos = pos
		_overlay.queue_redraw()
	, from_world, to_world, 0.3)
	await tween.finished
	_projectile_active = false
	_overlay.queue_redraw()

func _handle_reticle_confirm() -> void:
	if _reticle_tile == _player_combatant.current_tile:
		MessageLog.post("There is nothing to attack there.")
		return
	var target := _find_combatant_at_tile(_reticle_tile)
	if target == null:
		MessageLog.post("There is nothing to attack there.")
		return
	_reticle_active = false
	_animating = true
	_overlay.queue_redraw()
	await CombatManager.resolve_attack(_player_combatant, target)
	_animating = false
	_end_player_turn()

func _find_combatant_at_tile(tile: Vector2i) -> Combatant:
	for c in _combatants:
		var cb: Combatant = c
		if not cb.is_dead and not cb.is_fled and not cb.is_player and cb.current_tile == tile:
			return cb
	return null

func _get_player_weapon_range() -> int:
	return _player_combatant.get_weapon_range()

func _get_direction(event: InputEvent) -> Vector2i:
	if event.is_action_pressed("move_up"):         return Vector2i(0, -1)
	if event.is_action_pressed("move_down"):        return Vector2i(0, 1)
	if event.is_action_pressed("move_left"):        return Vector2i(-1, 0)
	if event.is_action_pressed("move_right"):       return Vector2i(1, 0)
	if event.is_action_pressed("move_up_left"):     return Vector2i(-1, -1)
	if event.is_action_pressed("move_up_right"):    return Vector2i(1, -1)
	if event.is_action_pressed("move_down_left"):   return Vector2i(-1, 1)
	if event.is_action_pressed("move_down_right"):  return Vector2i(1, 1)
	return Vector2i.ZERO

# --- Arena passability and geometry helpers (used by CombatManager) ---

func is_passable_for_npc(tile: Vector2i) -> bool:
	if tile.x < 0 or tile.x >= ARENA_WIDTH or tile.y < 0 or tile.y >= ARENA_HEIGHT:
		return false
	return GameManager.is_tile_passable(tile)

func spawn_npc_corpse(combatant: Combatant) -> void:
	var corpse_label: String
	if is_instance_valid(combatant.node) and not combatant.node.corpse_name.is_empty():
		corpse_label = combatant.node.corpse_name
	else:
		corpse_label = combatant.display_name + "'s corpse"
	var inventory: Inventory
	if is_instance_valid(combatant.node) and combatant.node.npc_inventory != null:
		inventory = combatant.node.npc_inventory
	else:
		inventory = Inventory.new()
	GameManager.spawn_corpse(combatant.current_tile, corpse_label, inventory)

func is_terrain_passable(tile: Vector2i) -> bool:
	if tile.x < 0 or tile.x >= ARENA_WIDTH or tile.y < 0 or tile.y >= ARENA_HEIGHT:
		return false
	var tile_data := terrain_layer.get_cell_tile_data(tile)
	if tile_data == null:
		return false
	var tile_set := terrain_layer.tile_set
	for i in range(tile_set.get_custom_data_layers_count()):
		if tile_set.get_custom_data_layer_name(i) == Constants.TILE_TYPE_CUSTOM_DATA:
			var type_id: String = tile_data.get_custom_data_by_layer_id(i)
			return GameManager.tile_registry.is_passable(type_id)
	return false

func is_arena_edge(tile: Vector2i) -> bool:
	return tile.x == 0 or tile.x == ARENA_WIDTH - 1 or tile.y == 0 or tile.y == ARENA_HEIGHT - 1

func get_nearest_edge_tile(from: Vector2i) -> Vector2i:
	var north_dist := from.y
	var south_dist := ARENA_HEIGHT - 1 - from.y
	var west_dist := from.x
	var east_dist := ARENA_WIDTH - 1 - from.x
	var min_dist := mini(mini(north_dist, south_dist), mini(west_dist, east_dist))
	if min_dist == north_dist:
		return Vector2i(from.x, 0)
	elif min_dist == south_dist:
		return Vector2i(from.x, ARENA_HEIGHT - 1)
	elif min_dist == west_dist:
		return Vector2i(0, from.y)
	else:
		return Vector2i(ARENA_WIDTH - 1, from.y)

# --- Map setup ---

func _paint_grid(grid: Array) -> void:
	for y in range(grid.size()):
		var row: Array = grid[y]
		for x in range(row.size()):
			var type_id: String = row[x]
			var atlas: Vector2i = _TILE_ATLAS.get(type_id, Vector2i(0, 0))
			terrain_layer.set_cell(Vector2i(x, y), 0, atlas)

func _pick_enemy_tile(opposite_edge: String) -> Vector2i:
	for _attempt in range(5):
		var tile := _random_tile_near_edge(opposite_edge)
		if GameManager.is_tile_passable(tile) and not WorldState.is_tile_occupied(tile):
			return tile
	return _edge_center(opposite_edge)

func _random_tile_near_edge(edge: String) -> Vector2i:
	match edge:
		"north": return Vector2i(randi_range(1, ARENA_WIDTH - 2), randi_range(0, 2))
		"south": return Vector2i(randi_range(1, ARENA_WIDTH - 2), randi_range(ARENA_HEIGHT - 3, ARENA_HEIGHT - 1))
		"west":  return Vector2i(randi_range(0, 2), randi_range(1, ARENA_HEIGHT - 2))
		"east":  return Vector2i(randi_range(ARENA_WIDTH - 3, ARENA_WIDTH - 1), randi_range(1, ARENA_HEIGHT - 2))
	return Vector2i(13, 0)

func _edge_center(edge: String) -> Vector2i:
	match edge:
		"north": return Vector2i(13, 1)
		"south": return Vector2i(13, ARENA_HEIGHT - 2)
		"west":  return Vector2i(1, 10)
		"east":  return Vector2i(ARENA_WIDTH - 2, 10)
	return Vector2i(13, 1)

func _setup_tileset() -> void:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(Constants.TILE_SIZE, Constants.TILE_SIZE)
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(0, Constants.LOOK_DESCRIPTION_LAYER)
	tile_set.set_custom_data_layer_type(0, TYPE_STRING)
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(1, Constants.TILE_TYPE_CUSTOM_DATA)
	tile_set.set_custom_data_layer_type(1, TYPE_STRING)

	var source := TileSetAtlasSource.new()
	source.texture = load("res://assets/tilesets/wilderness.png")
	source.texture_region_size = Vector2i(Constants.TILE_SIZE, Constants.TILE_SIZE)
	for coords in _TILE_ATLAS.values():
		if not source.has_tile(coords):
			source.create_tile(coords)
	tile_set.add_source(source, 0)

	var _td := func(coords: Vector2i, look: String, type_id: String) -> void:
		var td: TileData = source.get_tile_data(coords, 0)
		td.set_custom_data_by_layer_id(0, look)
		td.set_custom_data_by_layer_id(1, type_id)

	_td.call(Vector2i(0, 0), "You see a grassy field.",         "grass")
	_td.call(Vector2i(1, 0), "You see a stone wall.",           "mountain")
	_td.call(Vector2i(2, 0), "You see a patch of bare earth.",  "dirt")
	_td.call(Vector2i(3, 0), "The water blocks your path.",     "water")
	_td.call(Vector2i(4, 0), "You see dark, boggy ground.",     "swamp")
	_td.call(Vector2i(5, 0), "Dense trees slow your passage.",  "forest")
	_td.call(Vector2i(6, 0), "The hillside is rough going.",    "hill")

	terrain_layer.tile_set = tile_set
