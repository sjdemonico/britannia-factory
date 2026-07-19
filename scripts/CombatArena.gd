class_name CombatArena
extends Node2D

const ARENA_WIDTH: int = Constants.MAP_TILES_WIDE
const ARENA_HEIGHT: int = Constants.MAP_TILES_TALL


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

# Diamond formation offsets — index 0 is leader (front center), forward = away from entry edge.
const _FORMATION_OFFSETS: Array = [
	Vector2i(0, 0),
	Vector2i(-1, 1),
	Vector2i(1, 1),
	Vector2i(0, 2),
	Vector2i(-2, 2),
	Vector2i(2, 2),
	Vector2i(-1, 3),
	Vector2i(0, 3),
]

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var actors: Node2D = $Actors

var _combatants: Array = []
var _player_combatant: Combatant = null
var _active_combatant: Combatant = null
var _player_node  # untyped — CharacterBody2D with Player.gd, duck-typed

var _player_turn_active: bool = false
var _victory: bool = false
var _spell_targeting_active: bool = false
var _pending_spell_id: String = ""
var _spell_range: int = 0

# Draw state
var _overlay: Node2D
var _targeting_reticle: TargetingReticle
var _active_combatant_pos: Vector2 = Vector2.ZERO
var _show_active_frame: bool = false
var _reticle_active: bool = false
var _reticle_tile: Vector2i = Vector2i.ZERO
var _weapon_range: int = 1
var _animating: bool = false
var _projectile_active: bool = false
var _projectile_pos: Vector2 = Vector2.ZERO
var _projectile_color: Color = Color(0.95, 0.85, 0.2, 1.0)

func _ready() -> void:
	_setup_tileset()
	_player_node = $Actors/Player
	var cam = _player_node.get_node("Camera2D")
	Constants.apply_camera_limits(cam, ARENA_WIDTH, ARENA_HEIGHT)
	_overlay = Node2D.new()
	add_child(_overlay)
	_overlay.draw.connect(_on_overlay_draw)
	_targeting_reticle = TargetingReticle.new()
	add_child(_targeting_reticle)
	var objects := Node2D.new()
	objects.name = "Objects"
	add_child(objects)
	SpellManager.spell_targeting_requested.connect(_on_spell_targeting_requested)
	GameManager.load_region("combat_arena")
	initialize(CombatManager.combatants, CombatManager.player_entry_edge, CombatManager._pending_world_tile_type)

func _exit_tree() -> void:
	if SpellManager.spell_targeting_requested.is_connected(_on_spell_targeting_requested):
		SpellManager.spell_targeting_requested.disconnect(_on_spell_targeting_requested)

func initialize(combatant_defs: Array, entry_edge: String, world_tile_type: String) -> void:
	SoundManager.play_event("arena_entry")
	var generator := ArenaGenerator.new()
	generator.load_config()
	var grid := generator.generate(world_tile_type, ARENA_WIDTH, ARENA_HEIGHT)
	_paint_grid(grid)

	# Create combatants for all living party members and place in diamond formation.
	var party_members := PartyManager.get_living_members()
	var party_combatants: Array[Combatant] = []
	for i in range(party_members.size()):
		var member: PartyMember = party_members[i]
		var pc := Combatant.new()
		pc.is_player = true
		pc.party_member_id = member.member_id
		pc.display_name = member.display_name
		pc.stat_block = member.stat_block
		pc.inventory = member.inventory
		if member.member_id == Constants.PLAYER_MEMBER_ID:
			pc.node = _player_node
			_player_combatant = pc
		else:
			pc.node = _spawn_companion_node(member)
		_combatants.append(pc)
		party_combatants.append(pc)

	_place_party_members(party_combatants, entry_edge)
	_active_combatant = _player_combatant

	_spawn_combatants(combatant_defs, entry_edge)
	CombatManager.start_combat(_combatants, self)

func _spawn_companion_node(member: PartyMember) -> Node2D:
	var node := Node2D.new()
	node.name = "Companion_" + member.member_id
	actors.add_child(node)
	return node

func _place_party_members(members: Array[Combatant], entry_edge: String) -> void:
	var center: Vector2i = _ENTRY_TILES.get(entry_edge, Vector2i(13, 20))
	var occupied: Array[Vector2i] = []
	for i in range(members.size()):
		var combatant: Combatant = members[i]
		var raw_offset: Vector2i = _FORMATION_OFFSETS[i] if i < _FORMATION_OFFSETS.size() else Vector2i(0, i)
		var transformed: Vector2i = _apply_formation_transform(raw_offset, entry_edge)
		var target_tile: Vector2i = center + transformed
		target_tile.x = clampi(target_tile.x, 0, ARENA_WIDTH - 1)
		target_tile.y = clampi(target_tile.y, 0, ARENA_HEIGHT - 1)
		if not GameManager.is_tile_passable(target_tile) or target_tile in occupied:
			target_tile = _find_nearest_passable(target_tile, occupied)
		combatant.current_tile = target_tile
		occupied.append(target_tile)
		if combatant.node == _player_node:
			_player_node.teleport_to_tile(target_tile)
		elif is_instance_valid(combatant.node):
			combatant.node.position = Constants.tile_to_world(target_tile)

# Transforms a formation offset (x=lateral, y=depth-away-from-entry) for the given entry edge.
func _apply_formation_transform(offset: Vector2i, entry_edge: String) -> Vector2i:
	match entry_edge:
		"south": return Vector2i(offset.x, -offset.y)
		"north": return Vector2i(offset.x,  offset.y)
		"west":  return Vector2i(offset.y,  offset.x)
		"east":  return Vector2i(-offset.y, offset.x)
	return offset

func _find_nearest_passable(from: Vector2i, occupied: Array[Vector2i]) -> Vector2i:
	for radius in range(1, 6):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue
				var tile := from + Vector2i(dx, dy)
				if tile.x < 0 or tile.x >= ARENA_WIDTH or tile.y < 0 or tile.y >= ARENA_HEIGHT:
					continue
				if GameManager.is_tile_passable(tile) and not (tile in occupied):
					return tile
	return from

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
	if event.is_action_pressed("toggle_spellbook"):
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
			var was_spell := _spell_targeting_active
			_reticle_active = false
			_spell_targeting_active = false
			_pending_spell_id = ""
			_targeting_reticle.deactivate()
			_overlay.queue_redraw()
			if was_spell:
				MessageLog.post(MessageRegistry.get_message("spell_cancelled"))
				MessageLog.post_blank()
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
		_overlay.draw_rect(Rect2(_active_combatant_pos - Vector2(half, half), size), GameManager.active_combatant_frame_color, false, 2.0)
	if _projectile_active:
		_overlay.draw_circle(_projectile_pos, 4.0, _projectile_color)

func highlight_active_combatant(combatant: Combatant) -> void:
	if is_instance_valid(combatant.node):
		_active_combatant_pos = combatant.node.position
	_show_active_frame = true
	_overlay.queue_redraw()

func start_player_turn(combatant: Combatant) -> void:
	_active_combatant = combatant
	# Sync tile position from the Player node for the actual player character.
	if combatant == _player_combatant and _player_node != null:
		_player_combatant.current_tile = _player_node.tile_pos
	_weapon_range = _active_combatant.get_weapon_range()
	_player_turn_active = true
	# Route spell resource consumption to the active party member.
	if combatant.party_member_id != Constants.PLAYER_MEMBER_ID and not combatant.party_member_id.is_empty():
		var member := PartyManager.get_member(combatant.party_member_id)
		if member != null:
			SpellManager.set_caster(member)

func on_combat_victory() -> void:
	_victory = true
	_show_active_frame = false
	_player_turn_active = false
	_reticle_active = false
	_targeting_reticle.deactivate()
	_overlay.queue_redraw()

func _end_player_turn() -> void:
	SpellManager.clear_caster()
	_player_turn_active = false
	_reticle_active = false
	_targeting_reticle.deactivate()
	_overlay.queue_redraw()
	CombatManager.on_player_action_taken()

func _handle_player_move(dir: Vector2i) -> void:
	var target_tile := _active_combatant.current_tile + dir
	if _check_arena_exit(target_tile, dir):
		return
	if not GameManager.is_tile_passable(target_tile):
		MessageLog.post(MessageRegistry.get_message("combat_move_blocked"))
		return
	if _is_tile_blocked(target_tile, _active_combatant):
		MessageLog.post(MessageRegistry.get_message("combat_move_blocked"))
		return
	_move_active_combatant_to(target_tile)
	if not _victory:
		_end_player_turn()

func _move_active_combatant_to(target_tile: Vector2i) -> void:
	_active_combatant.current_tile = target_tile
	if _active_combatant.node == _player_node:
		_player_node.teleport_to_tile(target_tile)
	elif is_instance_valid(_active_combatant.node):
		_active_combatant.node.position = Constants.tile_to_world(target_tile)
	if GameManager.hazard_processor != null:
		GameManager.hazard_processor.process_tile_entry(_active_combatant, target_tile)

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
	_reticle_tile = _active_combatant.current_tile
	_reticle_active = true
	_targeting_reticle.activate(_reticle_tile, _weapon_range)
	MessageLog.post(MessageRegistry.get_message("combat_attack_prompt"))

func _handle_reticle_move(dir: Vector2i) -> void:
	var new_tile := _reticle_tile + dir
	if new_tile.x < 0 or new_tile.x >= ARENA_WIDTH or new_tile.y < 0 or new_tile.y >= ARENA_HEIGHT:
		return
	if _spell_targeting_active:
		if _spell_range > 0:
			var dist := maxi(abs(new_tile.x - _active_combatant.current_tile.x),
							 abs(new_tile.y - _active_combatant.current_tile.y))
			if dist > _spell_range:
				return
	else:
		var dist := maxi(abs(new_tile.x - _active_combatant.current_tile.x),
						 abs(new_tile.y - _active_combatant.current_tile.y))
		if dist > _weapon_range:
			return
	_reticle_tile = new_tile
	_targeting_reticle.move_to(_reticle_tile)
	if _spell_targeting_active:
		var spell: Dictionary = SpellManager.get_spell(_pending_spell_id)
		var ae_tiles := SpellTargeting.compute_ae_tiles(
			spell, _active_combatant.current_tile, _reticle_tile)
		_targeting_reticle.set_ae_tiles(ae_tiles)

func animate_projectile(from_tile: Vector2i, to_tile: Vector2i, override_color: Color = Color(-1, -1, -1, -1)) -> void:
	var from_world := Constants.tile_to_world(from_tile)
	var to_world := Constants.tile_to_world(to_tile)
	_projectile_color = override_color if override_color.r >= 0.0 else Color(0.95, 0.85, 0.2, 1.0)
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
	var target: Combatant = null

	if _spell_targeting_active and _reticle_tile == _active_combatant.current_tile:
		target = _active_combatant
	else:
		if _reticle_tile == _active_combatant.current_tile:
			MessageLog.post(MessageRegistry.get_message("combat_nothing_at_target"))
			return
		target = _find_combatant_at_tile(_reticle_tile)
		if target == null:
			var msg_key: String = "spell_no_target" if _spell_targeting_active else "combat_nothing_at_target"
			MessageLog.post(MessageRegistry.get_message(msg_key))
			return

	_reticle_active = false
	_targeting_reticle.deactivate()
	_overlay.queue_redraw()

	if _spell_targeting_active:
		_spell_targeting_active = false
		var spell_id: String = _pending_spell_id
		_pending_spell_id = ""
		var spell: Dictionary = SpellManager.get_spell(spell_id)
		var ae_tiles := SpellTargeting.compute_ae_tiles(
			spell, _active_combatant.current_tile, target.current_tile)
		var filtered := filter_affected_entities(ae_tiles, "player")
		if _active_combatant.node != null and _active_combatant.node.has_method("set_anim_state"):
			_active_combatant.node.set_anim_state("cast")
		SpellManager.attempt_cast(spell_id, target.node, target.current_tile, ae_tiles, filtered)
		if _active_combatant.node != null and _active_combatant.node.has_method("set_anim_state"):
			_active_combatant.node.set_anim_state("idle")
		_end_player_turn()
	else:
		_animating = true
		_overlay.queue_redraw()
		await CombatManager.resolve_attack(_active_combatant, target)
		_animating = false
		_end_player_turn()

# Called by SpellManager.spell_targeting_requested signal.
func _on_spell_targeting_requested(spell_id: String) -> void:
	if not CombatManager.in_combat:
		return
	var spell: Dictionary = SpellManager.get_spell(spell_id)
	var targeting_type: String = str(spell.get("targeting_type", "targeted"))
	if targeting_type == "point_blank":
		cast_point_blank_spell(spell_id)
	elif targeting_type == "targeted":
		start_spell_targeting(spell_id)

func start_spell_targeting(spell_id: String) -> void:
	var spell: Dictionary = SpellManager.get_spell(spell_id)
	_spell_range = SpellTargeting.get_spell_range(spell)
	_pending_spell_id = spell_id
	_spell_targeting_active = true
	_reticle_tile = _active_combatant.current_tile
	_reticle_active = true
	_targeting_reticle.activate(_reticle_tile, _spell_range)
	var ae_tiles := SpellTargeting.compute_ae_tiles(
		spell, _active_combatant.current_tile, _reticle_tile)
	_targeting_reticle.set_ae_tiles(ae_tiles)
	MessageLog.post(MessageRegistry.get_message("cast_prompt_target"))

func get_entities_on_tile(tile: Vector2i) -> Array:
	var result: Array = []
	for c in _combatants:
		var cb: Combatant = c as Combatant
		if cb == null or cb.is_dead or cb.is_fled or cb.is_downed:
			continue
		if cb.current_tile == tile:
			result.append(cb)
	return result

func filter_affected_entities(affected_tiles: Array[Vector2i], caster_faction: String) -> Array:
	var result: Array = []
	for tile in affected_tiles:
		for cb in get_entities_on_tile(tile):
			var cb_faction: String = "player" if cb.is_player else "enemy"
			if cb_faction != caster_faction and cb not in result:
				result.append(cb)
	return result

func cast_point_blank_spell(spell_id: String) -> void:
	if not SpellManager.can_cast(spell_id, "combat"):
		return
	SpellManager.consume_cast_resources(spell_id)
	var spell: Dictionary = SpellManager.get_spell(spell_id)
	var spell_name: String = str(spell.get("name", spell_id))
	MessageLog.post(MessageRegistry.get_message("spell_cast", {"name": spell_name}))
	var ae_tiles := SpellTargeting.compute_ae_tiles(
		spell, _active_combatant.current_tile, _active_combatant.current_tile)
	var filtered := filter_affected_entities(ae_tiles, "player")
	var effects: Array = spell.get("effects", []) if spell.get("effects") is Array else []
	var executor := SpellEffectExecutor.new()
	if _active_combatant.node != null and _active_combatant.node.has_method("set_anim_state"):
		_active_combatant.node.set_anim_state("cast")
	executor.execute_effects(effects, _active_combatant.node, null, _active_combatant.current_tile, "combat", ae_tiles, filtered)
	if _active_combatant.node != null and _active_combatant.node.has_method("set_anim_state"):
		_active_combatant.node.set_anim_state("idle")
	MessageLog.post_blank()
	_end_player_turn()

func _find_combatant_at_tile(tile: Vector2i) -> Combatant:
	for c in _combatants:
		var cb: Combatant = c
		if not cb.is_dead and not cb.is_fled and not cb.is_player and cb.current_tile == tile:
			return cb
	return null

func _get_player_weapon_range() -> int:
	return _active_combatant.get_weapon_range()

# Returns true if the tile is occupied by any non-fled, non-dead combatant (including downed).
func _is_tile_blocked(tile: Vector2i, ignore: Combatant = null) -> bool:
	if WorldState.is_tile_occupied_by_npc(tile):
		return true
	for c in _combatants:
		var cb: Combatant = c
		if cb == ignore or cb.is_fled or cb.is_dead:
			continue
		if cb.current_tile == tile:
			return true
	return false

# Public: called by CombatManager to block NPC movement through party member tiles.
func is_tile_occupied_in_arena(tile: Vector2i) -> bool:
	for c in _combatants:
		var cb: Combatant = c
		if cb.is_fled or cb.is_dead:
			continue
		if cb.current_tile == tile:
			return true
	return false

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

func _on_arena_clicked(tile: Vector2i) -> void:
	if _victory:
		_move_one_step_toward(tile)
		return
	if not _player_turn_active:
		return
	if _reticle_active:
		if _targeting_reticle._on_map_clicked_during_targeting(tile):
			_reticle_tile = tile
			_handle_reticle_confirm()
		return
	var enemy: Combatant = _find_combatant_at_tile(tile)
	if enemy != null:
		var dist := maxi(absi(tile.x - _active_combatant.current_tile.x),
						 absi(tile.y - _active_combatant.current_tile.y))
		if dist <= _weapon_range:
			_reticle_tile = tile
			_animating = true
			_overlay.queue_redraw()
			await CombatManager.resolve_attack(_active_combatant, enemy)
			_animating = false
			_end_player_turn()
		else:
			_move_one_step_toward(tile)
		return
	var objects := GameManager.get_objects_at(tile)
	if not objects.is_empty():
		var dir := tile - _active_combatant.current_tile
		if absi(dir.x) <= 1 and absi(dir.y) <= 1 and dir != Vector2i.ZERO:
			_player_node._resolve_get(dir)
			CombatManager.on_player_action_taken()
		else:
			_move_one_step_toward(tile)
		return
	_move_one_step_toward(tile)

func _move_one_step_toward(target: Vector2i) -> void:
	var path: Array[Vector2i] = Pathfinder.find_path(
		_active_combatant.current_tile,
		target,
		func(t: Vector2i) -> bool: return GameManager.is_tile_passable(t) and not _is_tile_blocked(t, _active_combatant),
		ARENA_WIDTH * ARENA_HEIGHT
	)
	if path.is_empty():
		MessageLog.post(MessageRegistry.get_message("combat_move_blocked"))
		return
	_handle_player_move(path[0] - _active_combatant.current_tile)

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
	var tile_reg: TileRegistry = GameManager.tile_registry
	for y in range(grid.size()):
		var row: Array = grid[y]
		for x in range(row.size()):
			var type_id: String = row[x]
			var atlas: Vector2i = tile_reg.get_atlas_coords(type_id) if tile_reg != null else Vector2i(0, 0)
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
	Constants.setup_tileset_from_atlas(terrain_layer, GameManager.tile_registry)
