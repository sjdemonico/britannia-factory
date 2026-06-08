extends Node

signal _player_turn_finished

var in_combat: bool = false
var combatants: Array = []
var player_entry_edge: String = ""
var source_npc: Node = null

var _pre_combat_region_id: String = ""
var _pre_combat_player_tile: Vector2i = Vector2i.ZERO
var _pre_combat_source_npc_id: String = ""

var _turn_order: Array = []
var _current_turn_index: int = 0
var _arena  # untyped — CombatArena node
var _unarmed_base_damage: float = 1.0
var _npc_turn_pause_seconds: float = 0.3
var _experience_per_kill: int = 10
var _pending_world_tile_type: String = ""

func _ready() -> void:
	_load_combat_config()

func _load_combat_config() -> void:
	var file := FileAccess.open(Constants.COMBAT_CONFIG_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return
	file.close()
	var data: Dictionary = json.get_data()
	var ubd = data.get("unarmed_base_damage")
	if ubd != null:
		_unarmed_base_damage = float(ubd)
	var ntp = data.get("npc_turn_pause_seconds")
	if ntp != null:
		_npc_turn_pause_seconds = float(ntp)
	var epk = data.get("experience_per_kill")
	if epk != null:
		_experience_per_kill = int(epk)

func initiate_combat(world_npc: Node, player_initiated: bool) -> void:
	if in_combat:
		return
	in_combat = true
	source_npc = world_npc
	_pre_combat_source_npc_id = world_npc.npc_id
	_pre_combat_player_tile = GameManager.get_player_tile()
	_pre_combat_region_id = GameManager.get_current_region_id()
	player_entry_edge = _determine_entry_edge(world_npc.npc_tile, _pre_combat_player_tile)
	var world_npc_node := world_npc as NPC
	var group_override: int = world_npc_node.group_base_count_override if world_npc_node != null else -1
	combatants = _resolve_group_members(world_npc.npc_id, group_override)
	_pending_world_tile_type = GameManager.get_world_tile_type(_pre_combat_player_tile)
	GameManager.world_paused = true
	GameManager.load_region("combat_arena")
	if player_initiated:
		MessageLog.post("Combat begins!")
	else:
		MessageLog.post(world_npc.display_name + " attacks!")
	MessageLog.post("")

func end_combat(player_fled: bool, exit_dir: Vector2i = Vector2i.ZERO) -> void:
	in_combat = false
	_player_turn_finished.emit()  # unblock any awaiting coroutine
	_arena = null

	var survivors: int = 0
	if player_fled:
		for c in _turn_order:
			var cb: Combatant = c
			if not cb.is_player and not cb.is_dead and not cb.is_fled:
				survivors += 1

	GameManager.load_region(_pre_combat_region_id)

	# Place player at exit-direction tile if passable, else pre-combat tile
	var player := GameManager.current_region.get_node_or_null("Actors/Player")
	if player != null:
		var placement_tile := _pre_combat_player_tile
		if exit_dir != Vector2i.ZERO:
			var candidate := _pre_combat_player_tile + exit_dir
			if GameManager.is_tile_passable(candidate):
				placement_tile = candidate
		player.teleport_to_tile(placement_tile)

	# Handle source NPC in restored world
	var actors := GameManager.current_region.get_node_or_null("Actors")
	if actors != null and not _pre_combat_source_npc_id.is_empty():
		for child in actors.get_children():
			var npc := child as NPC
			if npc != null and npc.npc_id == _pre_combat_source_npc_id:
				if player_fled:
					MessageLog.post("You flee the battle.")
					MessageLog.post("")
					if survivors > 0:
						npc.group_base_count_override = survivors
					npc.start_pursuit(GameManager.player_tile, npc.pursuit_ticks_configured)
				else:
					MessageLog.post("Victory!")
					MessageLog.post("")
					npc.remove_from_world()
				break

	GameManager.world_paused = false

	# Clear state
	combatants = []
	_turn_order = []
	source_npc = null
	player_entry_edge = ""
	_pre_combat_source_npc_id = ""

func start_combat(all_combatants: Array, arena: Node) -> void:
	_arena = arena
	_turn_order = []
	_current_turn_index = 0
	_build_turn_order(all_combatants)
	_advance_turn()

func _build_turn_order(all_combatants: Array) -> void:
	for c in all_combatants:
		c.roll_initiative()
	var sorted := all_combatants.duplicate()
	sorted.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		if a.initiative == b.initiative:
			return a.is_player
		return a.initiative > b.initiative
	)
	_turn_order = sorted

func _advance_turn() -> void:
	while in_combat:
		if _all_enemies_dead():
			MessageLog.post("Victory!")
			MessageLog.post("")
			if _arena != null and is_instance_valid(_arena):
				_arena.on_combat_victory()
			return

		var active: Combatant = _turn_order[_current_turn_index]
		if active.is_dead or active.is_fled:
			_current_turn_index = (_current_turn_index + 1) % _turn_order.size()
			continue

		if _arena != null and is_instance_valid(_arena):
			_arena.highlight_active_combatant(active)

		if active.is_player:
			if _arena != null and is_instance_valid(_arena):
				_arena.start_player_turn(active)
			await _player_turn_finished
		else:
			await _execute_npc_turn(active)

		if not in_combat:
			break

		_current_turn_index = (_current_turn_index + 1) % _turn_order.size()

func _execute_npc_turn(combatant: Combatant) -> void:
	if combatant.is_dead or combatant.is_fled:
		await get_tree().create_timer(_npc_turn_pause_seconds).timeout
		return

	var player := _get_player_combatant()
	if player == null or player.is_dead:
		await get_tree().create_timer(_npc_turn_pause_seconds).timeout
		return

	var action: String = combatant.ai.evaluate(combatant, player, _arena)

	match action:
		"attack":
			var weapon_range := combatant.get_weapon_range()
			var dist := maxi(
				abs(combatant.current_tile.x - player.current_tile.x),
				abs(combatant.current_tile.y - player.current_tile.y)
			)
			if dist <= weapon_range:
				await resolve_attack(combatant, player)
		"flee":
			_npc_flee(combatant)
		_:  # "move_toward_target" and any unknown action
			_npc_move_toward_player(combatant, player)
			if _arena != null and is_instance_valid(_arena):
				_arena.highlight_active_combatant(combatant)

	await get_tree().create_timer(_npc_turn_pause_seconds).timeout

func _npc_move_toward_player(combatant: Combatant, player: Combatant) -> void:
	if _arena == null or not is_instance_valid(_arena):
		return
	var goal: Vector2i = player.current_tile
	var passability := func(tile: Vector2i) -> bool:
		if tile == goal:
			return true
		return _arena.is_terrain_passable(tile)
	var path := Pathfinder.find_path(combatant.current_tile, goal, passability, 0)
	if path.is_empty():
		return
	var next_tile: Vector2i = path[0]
	if next_tile == goal:
		return  # don't step onto player tile
	if WorldState.is_tile_occupied_by_npc(next_tile):
		return  # another NPC is here this turn — skip and retry next turn
	_step_npc_to(combatant, next_tile)

func _npc_flee(combatant: Combatant) -> void:
	if _arena == null or not is_instance_valid(_arena):
		return
	if _arena.is_arena_edge(combatant.current_tile):
		_remove_npc_from_combat(combatant)
		return
	var goal: Vector2i = _arena.get_nearest_edge_tile(combatant.current_tile)
	var passability := func(tile: Vector2i) -> bool:
		if tile == goal:
			return true
		return _arena.is_passable_for_npc(tile)
	var path := Pathfinder.find_path(combatant.current_tile, goal, passability, 0)
	if path.is_empty():
		return
	var next_tile: Vector2i = path[0]
	_step_npc_to(combatant, next_tile)
	if _arena != null and is_instance_valid(_arena):
		_arena.highlight_active_combatant(combatant)
	if _arena.is_arena_edge(next_tile):
		_remove_npc_from_combat(combatant)

func _remove_npc_from_combat(combatant: Combatant) -> void:
	combatant.is_fled = true
	MessageLog.post(combatant.display_name + " flees the battle.")
	MessageLog.post("")
	if is_instance_valid(combatant.node):
		WorldState.clear_occupant(combatant.current_tile)
		combatant.node.queue_free()

func _step_npc_to(combatant: Combatant, next_tile: Vector2i) -> void:
	WorldState.clear_occupant(combatant.current_tile)
	combatant.current_tile = next_tile
	combatant.node.npc_tile = next_tile
	combatant.node.position = Constants.tile_to_world(next_tile)
	WorldState.set_occupant(next_tile, { "type": "npc", "id": combatant.node.npc_id, "node": combatant.node })

func resolve_attack(attacker: Combatant, defender: Combatant) -> void:
	var check_msg := GameManager.combat_resolver.pre_attack_checks(attacker, defender, _arena)
	if not check_msg.is_empty():
		if attacker.is_player:
			MessageLog.post(check_msg)
			MessageLog.post("")
		return

	var weapon := attacker.get_equipped_weapon()
	var is_ranged: bool = weapon.get("data", {}).get("ammo_type") != null

	var vars := GameManager.build_combat_variables(attacker.stat_block, attacker.inventory, defender.stat_block, defender.inventory)
	if vars.get("attacker_base_damage", 0.0) == 0.0:
		vars["attacker_base_damage"] = _unarmed_base_damage

	_consume_ammo(attacker)

	if is_ranged and _arena != null and is_instance_valid(_arena):
		await _arena.animate_projectile(attacker.current_tile, defender.current_tile)

	if not GameManager.combat_resolver.resolve_hit(vars):
		MessageLog.post(attacker.display_name + " misses " + defender.display_name + ".")
		MessageLog.post("")
		return

	var damage := GameManager.combat_resolver.resolve_damage(vars)
	defender.stat_block.modify_stat("hp", -damage)
	MessageLog.post(attacker.display_name + " hits " + defender.display_name + " for " + str(damage) + " damage.")
	MessageLog.post("")

	if defender.stat_block.get_value("hp") <= 0:
		_handle_death(defender)

func _consume_ammo(attacker: Combatant) -> void:
	if attacker.inventory == null:
		return
	var weapon := attacker.get_equipped_weapon()
	if weapon.is_empty():
		return
	var ammo_type = weapon.get("data", {}).get("ammo_type")
	if ammo_type == null:
		return
	var raw_aps = weapon.get("data", {}).get("ammo_per_shot")
	var ammo_per_shot: int = int(raw_aps) if raw_aps != null else 1
	var quiver_item: Dictionary = attacker.inventory.get_item_in_slot("quiver")
	if quiver_item.is_empty():
		return
	var ammo_instance_id: int = quiver_item["instance_id"]
	var before: int = quiver_item.get("stack_count", 0)
	var remaining: int = before - ammo_per_shot
	var plural: String = quiver_item.get("data", {}).get("display_name_plural", "ammo")
	attacker.inventory.take_from_stack(ammo_instance_id, ammo_per_shot)
	if not attacker.is_player:
		return
	if remaining <= 0:
		MessageLog.post("You are out of " + plural + ".")
		MessageLog.post("")
	elif remaining <= 5:
		MessageLog.post("You have " + str(remaining) + " " + plural + " left.")
		MessageLog.post("")

func _handle_death(combatant: Combatant) -> void:
	combatant.is_dead = true
	if combatant.is_player:
		MessageLog.post("You have died!")
		MessageLog.post("")
		show_mortis()
	else:
		MessageLog.post(combatant.display_name + " is slain.")
		MessageLog.post("")
		if _arena != null and is_instance_valid(_arena):
			_arena.spawn_npc_corpse(combatant)
		if is_instance_valid(combatant.node):
			WorldState.clear_occupant(combatant.current_tile)
			combatant.node.queue_free()
			_award_experience(combatant)

func show_mortis() -> void:
	in_combat = false
	var packed := load("res://scenes/ui/MortisScreen.tscn") as PackedScene
	if packed == null:
		push_error("CombatManager: cannot load MortisScreen.tscn")
		return
	var mortis := packed.instantiate()
	get_tree().root.add_child(mortis)

func on_player_action_taken() -> void:
	_player_turn_finished.emit()

func _get_player_combatant() -> Combatant:
	for c in _turn_order:
		var cb: Combatant = c
		if cb.is_player:
			return cb
	return null

func _all_enemies_dead() -> bool:
	for c in _turn_order:
		var cb: Combatant = c
		if not cb.is_player and not cb.is_dead and not cb.is_fled:
			return false
	return true

func _determine_entry_edge(npc_tile: Vector2i, player_tile: Vector2i) -> String:
	var diff := player_tile - npc_tile
	if abs(diff.x) >= abs(diff.y):
		return "east" if diff.x > 0 else "west"
	else:
		return "south" if diff.y > 0 else "north"

func _resolve_group_members(npc_id: String, base_count_override: int = -1) -> Array:
	var path := "res://data/npcs/" + npc_id + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return [{"npc_id": npc_id}]
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return [{"npc_id": npc_id}]
	file.close()
	var data: Dictionary = json.get_data()
	var group = data.get("group")
	if not group is Dictionary:
		return [{"npc_id": npc_id}]
	if base_count_override >= 0:
		group = group.duplicate()
		group["base_count"] = base_count_override
	return _resolve_group(group)

func _resolve_group(group: Dictionary) -> Array:
	var base_count: int = int(group.get("base_count", 1))
	var members_def: Array = group.get("members", [])
	var result: Array = []
	var current_counts: Dictionary = {}

	for m in members_def:
		var exact_v = m.get("count")
		if exact_v == null:
			continue
		var exact: int = int(exact_v)
		var max_v = m.get("max_count")
		if max_v != null:
			exact = mini(exact, int(max_v))
		exact = mini(exact, base_count - result.size())
		var nid: String = str(m.get("npc_id", ""))
		for _i in range(exact):
			result.append({"npc_id": nid})
		current_counts[nid] = current_counts.get(nid, 0) + exact

	for m in members_def:
		if m.get("count") != null:
			continue
		var min_v = m.get("min_count")
		if min_v == null:
			continue
		var nid: String = str(m.get("npc_id", ""))
		var max_v = m.get("max_count")
		var max_count: int = base_count if max_v == null else int(max_v)
		var already: int = current_counts.get(nid, 0)
		var add: int = mini(int(min_v) - already, max_count - already)
		add = mini(add, base_count - result.size())
		if add > 0:
			for _i in range(add):
				result.append({"npc_id": nid})
			current_counts[nid] = already + add

	var pool: Array = []
	for m in members_def:
		if m.get("count") != null:
			continue
		var nid: String = str(m.get("npc_id", ""))
		var max_v = m.get("max_count")
		pool.append({
			"npc_id": nid,
			"weight": float(m.get("weight", 1)),
			"max_count": base_count if max_v == null else int(max_v)
		})

	while result.size() < base_count:
		var eligible: Array = []
		var total_weight: float = 0.0
		for p in pool:
			if current_counts.get(p["npc_id"], 0) < p["max_count"]:
				eligible.append(p)
				total_weight += p["weight"]
		if eligible.is_empty():
			break
		var roll := randf() * total_weight
		var cumulative: float = 0.0
		var chosen: Dictionary = eligible[0]
		for p in eligible:
			cumulative += p["weight"]
			if roll <= cumulative:
				chosen = p
				break
		var nid: String = chosen["npc_id"]
		result.append({"npc_id": nid})
		current_counts[nid] = current_counts.get(nid, 0) + 1

	return result

func grant_experience(amount: int) -> void:
	if GameManager.level_manager == null:
		return
	var old_exp: int = PlayerStats.get_stat("experience")
	PlayerStats.modify_stat("experience", amount)
	MessageLog.post("You gain " + str(amount) + " experience.")
	MessageLog.post("")
	var levels_gained := GameManager.level_manager.check_level_up(old_exp, old_exp + amount)
	if levels_gained > 0:
		_apply_level_up(levels_gained)

func _award_experience(killed_combatant: Combatant) -> void:
	grant_experience(_get_npc_experience_value(killed_combatant))

func _get_npc_experience_value(combatant: Combatant) -> int:
	if is_instance_valid(combatant.node) and not combatant.node.npc_id.is_empty():
		var path: String = "res://data/npcs/" + str(combatant.node.npc_id) + ".json"
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK:
				file.close()
				var ev = json.get_data().get("experience_value")
				if ev != null:
					return int(ev)
			else:
				file.close()
	return _experience_per_kill

func _apply_level_up(levels_gained: int) -> void:
	for _i in range(levels_gained):
		PlayerStats.modify_stat("level", 1)
		var new_level: int = PlayerStats.get_stat("level")
		MessageLog.post("You have reached level " + str(new_level) + "!")
		MessageLog.post("")
		for stat_id in GameManager.level_manager.stat_gains:
			var gain: int = int(GameManager.level_manager.stat_gains[stat_id])
			if PlayerStats.has_stat(stat_id):
				PlayerStats.stat_block.raise_cap(stat_id, gain)
