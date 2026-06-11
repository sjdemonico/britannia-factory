extends CharacterBody2D

const INITIAL_DELAY: float = 0.4
const REPEAT_INTERVAL: float = 0.1

var tile_pos: Vector2i = Vector2i.ZERO
var moving: bool = false
var held_direction: Vector2i = Vector2i.ZERO
var hold_timer: float = 0.0

var dialogue_box: CanvasLayer = null
var inventory_screen: CanvasLayer = null
var _in_dialogue: bool = false
var _inventory_open: bool = false

var _awaiting_prompt: bool = false
var _prompt_callback: Callable
var _prompt_cancel: Callable

var _awaiting_quantity: bool = false
var _quantity_buffer: String = ""
var _quantity_max: int = -1
var _quantity_error_text: String = ""
var _quantity_callback: Callable
var _quantity_cancel: Callable

var _rest_active: bool = false
var _rest_ticks_remaining: int = 0
var _rest_accumulator: float = 0.0
var _awaiting_rest_duration: bool = false
var _wait_held: bool = false

func _ready() -> void:
	position = Constants.tile_to_world(tile_pos)
	WorldState.set_occupant(tile_pos, { "type": "player" })
	GameManager.player_tile = tile_pos

func teleport_to_tile(tile: Vector2i) -> void:
	WorldState.clear_occupant(tile_pos)
	tile_pos = tile
	position = Constants.tile_to_world(tile_pos)
	WorldState.set_occupant(tile_pos, { "type": "player" })
	GameManager.player_tile = tile_pos

func _unhandled_input(event: InputEvent) -> void:
	if _rest_active:
		if event.is_action_pressed("ui_cancel"):
			_end_rest(false)
		return

	if _awaiting_rest_duration:
		if event is InputEventKey and event.pressed and not event.echo:
			var ch: int = event.unicode
			if event.is_action_pressed("ui_cancel") or ch == 48:
				_awaiting_rest_duration = false
				MessageLog.post("Cancelled.")
				MessageLog.post("")
			elif ch >= 49 and ch <= 57:
				_awaiting_rest_duration = false
				_begin_rest(ch - 48)
		return

	if _awaiting_quantity:
		var key_event := event as InputEventKey
		if key_event != null and key_event.pressed and not key_event.echo:
			if key_event.is_action_pressed("ui_cancel") or key_event.is_action_pressed("inventory"):
				_cancel_quantity()
			elif key_event.keycode == KEY_BACKSPACE:
				if not _quantity_buffer.is_empty():
					_quantity_buffer = _quantity_buffer.left(_quantity_buffer.length() - 1)
				MessageLog.update_last(_quantity_buffer + "_")
			elif key_event.is_action_pressed("ui_accept"):
				_confirm_quantity()
			elif key_event.unicode >= 48 and key_event.unicode <= 57:
				_quantity_buffer += char(key_event.unicode)
				MessageLog.update_last(_quantity_buffer + "_")
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("inventory"):
		if _inventory_open:
			_close_inventory()
		elif not _in_dialogue and not _awaiting_prompt:
			_open_inventory()
		return

	if _inventory_open:
		if CombatManager.in_combat:
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("equip"):
		var enter_t := GameManager.get_enter_transition(tile_pos)
		if not enter_t.is_empty():
			GameManager.trigger_transition(enter_t["region_id"], enter_t.get("spawn_id", ""))
		return

	if _in_dialogue:
		return

	if _awaiting_prompt:
		if event.is_action_pressed("ui_cancel"):
			_cancel_prompt()
		elif event.is_action_pressed("target_self"):
			_resolve_prompt(Vector2i.ZERO)
		else:
			var dir := _get_direction_from_event(event)
			if dir != Vector2i.ZERO:
				_resolve_prompt(dir)
		get_viewport().set_input_as_handled()
		return

	if moving:
		return

	if event.is_action_pressed("wait"):
		if not CombatManager.in_combat:
			held_direction = Vector2i.ZERO
			_wait_held = true
			hold_timer = INITIAL_DELAY
			GameTime.advance(1)
		return

	if event.is_action_pressed("rest"):
		if not CombatManager.in_combat:
			held_direction = Vector2i.ZERO
			MessageLog.post("Rest how many hours? (0-9)")
			_awaiting_rest_duration = true
		return

	if event.is_action_pressed("talk"):
		_on_talk()
		return

	if event.is_action_pressed("get"):
		_on_get_prompt()
		return

	if event.is_action_pressed("look"):
		_on_look_prompt()
		return

	if event.is_action_pressed("drop"):
		_on_drop()
		return

	if event.is_action_pressed("use"):
		_on_use()
		return

	if event.is_action_pressed("move"):
		_on_move()
		return

	if event.is_action_pressed("attack") and not CombatManager.in_combat:
		_on_attack()
		return

	if not CombatManager.in_combat:
		var direction := Vector2i.ZERO
		if event.is_action_pressed("move_up"):
			direction = Vector2i(0, -1)
		elif event.is_action_pressed("move_down"):
			direction = Vector2i(0, 1)
		elif event.is_action_pressed("move_left"):
			direction = Vector2i(-1, 0)
		elif event.is_action_pressed("move_right"):
			direction = Vector2i(1, 0)
		elif event.is_action_pressed("move_up_left"):
			direction = Vector2i(-1, -1)
		elif event.is_action_pressed("move_up_right"):
			direction = Vector2i(1, -1)
		elif event.is_action_pressed("move_down_left"):
			direction = Vector2i(-1, 1)
		elif event.is_action_pressed("move_down_right"):
			direction = Vector2i(1, 1)
		if direction != Vector2i.ZERO:
			held_direction = direction
			hold_timer = INITIAL_DELAY
			attempt_move(direction)

func _process(delta: float) -> void:
	if _rest_active:
		_rest_accumulator += delta
		var tick_interval := 1.0 / float(GameTime.get_rest_ticks_per_second())
		while _rest_accumulator >= tick_interval and _rest_active:
			_rest_accumulator -= tick_interval
			GameTime.advance(1)
			_rest_ticks_remaining -= 1
			_check_rest_interrupt()
			if _rest_ticks_remaining <= 0:
				_end_rest(true)
		return

	if _wait_held:
		if not Input.is_action_pressed("wait"):
			_wait_held = false
			return
		hold_timer -= delta
		if hold_timer <= 0.0:
			hold_timer += REPEAT_INTERVAL
			GameTime.advance(1)
		return

	if _in_dialogue or _inventory_open or moving or held_direction == Vector2i.ZERO:
		return
	if not _is_direction_held(held_direction):
		held_direction = Vector2i.ZERO
		return
	hold_timer -= delta
	if hold_timer <= 0.0:
		hold_timer += REPEAT_INTERVAL
		attempt_move(held_direction)

func prompt_direction(callback: Callable, on_cancel: Callable) -> void:
	held_direction = Vector2i.ZERO
	_awaiting_prompt = true
	_prompt_callback = callback
	_prompt_cancel = on_cancel

func _resolve_prompt(dir: Vector2i) -> void:
	_awaiting_prompt = false
	_prompt_callback.call(dir)

func _cancel_prompt() -> void:
	_awaiting_prompt = false
	_prompt_cancel.call()

func _cancel_quiet() -> void:
	pass

func prompt_quantity(prompt_text: String, callback: Callable, max_value: int = -1, error_text: String = "", on_cancel: Callable = Callable()) -> void:
	held_direction = Vector2i.ZERO
	_awaiting_quantity = true
	_quantity_buffer = ""
	_quantity_max = max_value
	_quantity_error_text = error_text
	_quantity_callback = callback
	_quantity_cancel = on_cancel
	MessageLog.post(prompt_text)
	MessageLog.post("_")

func _confirm_quantity() -> void:
	var qty: int = int(_quantity_buffer) if not _quantity_buffer.is_empty() else 0
	if qty == 0:
		_cancel_quantity()
		return
	if _quantity_max != -1 and qty > _quantity_max:
		MessageLog.post(_quantity_error_text if not _quantity_error_text.is_empty() else "Invalid quantity.")
		_quantity_buffer = ""
		return
	_awaiting_quantity = false
	_quantity_callback.call(qty)

func _cancel_quantity() -> void:
	_awaiting_quantity = false
	_quantity_buffer = ""
	MessageLog.post("Cancelled.")
	MessageLog.post("")
	if _quantity_cancel.is_valid():
		_quantity_cancel.call()

func _on_talk() -> void:
	MessageLog.post("Talk - Direction?")
	prompt_direction(func(dir): _resolve_talk(dir), _cancel_quiet)

func _resolve_talk(dir: Vector2i) -> void:
	if not CombatManager.in_combat:
		GameTime.advance(1)
	var target_tile := tile_pos + dir
	var occupant := WorldState.get_occupant(target_tile)
	if occupant.get("type", "") == "npc":
		var npc := occupant.get("node") as NPC
		if npc != null and not npc._talkable:
			MessageLog.post(npc.get_not_talkable_message())
			MessageLog.post("")
			return
		if CombatManager.in_combat:
			CombatManager.on_player_action_taken()
		_start_dialogue(npc)
		return
	if GameManager.is_tile_transparent(target_tile):
		var far_tile := target_tile + dir
		var far_occupant := WorldState.get_occupant(far_tile)
		if far_occupant.get("type", "") == "npc":
			var npc := far_occupant.get("node") as NPC
			if npc != null and not npc._talkable:
				MessageLog.post(npc.get_not_talkable_message())
				MessageLog.post("")
				return
			if CombatManager.in_combat:
				CombatManager.on_player_action_taken()
			_start_dialogue(npc)
			return
	MessageLog.post("Nobody There!")
	MessageLog.post("")

func _on_get_prompt() -> void:
	MessageLog.post("Get - Direction?")
	prompt_direction(func(dir): _resolve_get(dir), _cancel_quiet)

func _resolve_get(dir: Vector2i) -> void:
	if not CombatManager.in_combat:
		GameTime.advance(1)
	var target := tile_pos if dir == Vector2i.ZERO else tile_pos + dir
	var world_objects := GameManager.get_objects_at(target)
	if world_objects.is_empty():
		MessageLog.post("Nothing to get.")
		MessageLog.post("")
		return
	var top_obj = world_objects[world_objects.size() - 1]
	if not top_obj.carriable:
		MessageLog.post("You cannot pick that up.")
		MessageLog.post("")
		return
	var data := PlayerInventory.get_object_data(top_obj.object_id)
	if top_obj.stack_count > 1:
		var stack_max: int = top_obj.stack_count
		var on_qty_chosen := func(qty: int):
			_do_get(top_obj, data, qty)
			if CombatManager.in_combat:
				CombatManager.on_player_action_taken()
		prompt_quantity(
			"How many? (max " + str(stack_max) + ")",
			on_qty_chosen,
			stack_max,
			"There aren't that many."
		)
		return
	_do_get(top_obj, data, 1)
	if CombatManager.in_combat:
		CombatManager.on_player_action_taken()

func _do_get(top_obj: WorldObject, data: Dictionary, qty: int) -> void:
	if not is_instance_valid(top_obj):
		MessageLog.post("It is no longer there.")
		MessageLog.post("")
		return
	if qty > 1:
		var carry_limit: float = float(PlayerStats.get_effective_value("carry_limit"))
		if carry_limit > 0.0:
			var current_weight: float = PlayerInventory.get_total_weight()
			if current_weight + top_obj.weight * qty > carry_limit:
				var available: float = carry_limit - current_weight
				qty = int(available / top_obj.weight)
				if qty <= 0:
					MessageLog.post("You are carrying too much.")
					MessageLog.post("")
					return
				MessageLog.post("You can only carry " + str(qty) + ".")
	else:
		if PlayerInventory.would_exceed_carry_limit(top_obj):
			MessageLog.post("You are carrying too much.")
			MessageLog.post("")
			return
	if data.get("type", "") == "corpse" and not top_obj._content_ids.is_empty():
		for content_id in top_obj._content_ids:
			GameManager.spawn_object(content_id, top_obj.object_tile)
		top_obj._content_ids.clear()
	var pick_name: String = top_obj.instance_display_name if not top_obj.instance_display_name.is_empty() else data.get("name", top_obj.object_id)
	var object_id: String = top_obj.object_id
	var object_tile: Vector2i = top_obj.object_tile
	if qty >= top_obj.stack_count:
		var instance_id := PlayerInventory.add_stacked(object_id, qty)
		if data.get("type", "") == "corpse" and instance_id != -1:
			GameManager.on_corpse_picked_up(top_obj, instance_id)
		WorldState.clear_object_from_tile(object_tile, object_id)
		top_obj.queue_free()
	else:
		top_obj.stack_count -= qty
		PlayerInventory.add_stacked(object_id, qty)
	if qty > 1:
		var raw_plural = data.get("display_name_plural")
		var plural: String = raw_plural if raw_plural is String else (data.get("name", object_id) + "s")
		MessageLog.post("You pick up " + str(qty) + " " + plural + ".")
	else:
		MessageLog.post("You pick up the " + pick_name + ".")
	MessageLog.post("")

func _on_look_prompt() -> void:
	MessageLog.post("Look - Direction (or 5 for self)?")
	prompt_direction(func(dir): _resolve_look(dir), _cancel_quiet)

func _resolve_look(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO:
		_post_look_at(tile_pos, true)
	else:
		_post_look_at(tile_pos + dir, false)

func _post_look_at(tile: Vector2i, is_self: bool) -> void:
	var occupant := WorldState.get_occupant(tile)
	var world_objects := GameManager.get_objects_at(tile)
	var parts: Array = []

	if is_self:
		parts.append("You are standing here.")

	if occupant.get("type", "") == "npc":
		var npc_node := occupant.get("node") as NPC
		if npc_node != null and not npc_node.flavor_text.is_empty():
			parts.append(npc_node.flavor_text)
		else:
			var npc_label: String = npc_node.display_name if npc_node != null else occupant.get("id", "someone")
			parts.append("You see " + npc_label + ".")

	# Step 1: structural object takes priority over terrain description
	var structural_obj: WorldObject = null
	for wo in world_objects:
		if wo.structural:
			structural_obj = wo
			break

	if structural_obj != null:
		var s_data := PlayerInventory.get_object_data(structural_obj.object_id)
		var s_desc: String = s_data.get("description", "")
		var s_line: String
		if not s_desc.is_empty():
			s_line = "You see " + s_desc
		else:
			s_line = "You see " + s_data.get("name", structural_obj.object_id) + "."
		if structural_obj.toggleable:
			s_line += " It is " + ("open" if structural_obj.is_open else "closed") + "."
		parts.append(s_line)
	else:
		var terrain_desc := _get_terrain_description(tile)
		if not terrain_desc.is_empty():
			parts.append(terrain_desc)
		for wo in world_objects:
			if not wo.toggleable:
				continue
			var wo_data := PlayerInventory.get_object_data(wo.object_id)
			var desc: String = wo_data.get("description", "")
			var state: String = "It is open." if wo.is_open else "It is closed."
			parts.append((desc + " " if not desc.is_empty() else "") + state)

	# Step 2: non-structural objects on tile
	var non_structural: Array = []
	for wo in world_objects:
		if not wo.structural:
			non_structural.append(wo)

	if not non_structural.is_empty():
		var names: Array = []
		for wo in non_structural:
			var wo_name: String
			if not wo.instance_display_name.is_empty():
				wo_name = wo.instance_display_name
			else:
				var wo_data := PlayerInventory.get_object_data(wo.object_id)
				if wo.stack_count > 1:
					var raw_plural = wo_data.get("display_name_plural")
					var plural: String = raw_plural if raw_plural is String else (wo_data.get("name", wo.object_id) + "s")
					wo_name = str(wo.stack_count) + " " + plural
				else:
					wo_name = wo_data.get("name", wo.object_id)
			names.append(wo_name)
		var prefix: String
		if structural_obj != null and not structural_obj.surface_name.is_empty():
			prefix = "On " + structural_obj.surface_name
		else:
			prefix = "On the ground"
		parts.append(prefix + ": " + Constants.natural_list(names) + ".")

	# Container/corpse disgorge
	for wo in world_objects:
		var wo_data := PlayerInventory.get_object_data(wo.object_id)
		var is_corpse: bool = wo_data.get("type", "") == "corpse"
		if (wo.container_open or is_corpse) and not wo._content_ids.is_empty():
			var cont_name: String = wo.instance_display_name if not wo.instance_display_name.is_empty() else wo_data.get("name", wo.object_id)
			for content_id in wo._content_ids:
				GameManager.spawn_object(content_id, tile)
			wo._content_ids.clear()
			parts.append(cont_name + " disgorges its contents.")

	if parts.is_empty():
		MessageLog.post("You see nothing special.")
	else:
		for p in parts:
			MessageLog.post(p)
	MessageLog.post("")

func _get_terrain_description(tile: Vector2i) -> String:
	var region := GameManager.current_region
	if region == null:
		return ""
	var terrain_layer: TileMapLayer = region.get_node_or_null("TerrainLayer")
	if terrain_layer == null or terrain_layer.tile_set == null:
		return ""
	var tile_set := terrain_layer.tile_set
	var layer_idx: int = -1
	for i in range(tile_set.get_custom_data_layers_count()):
		if tile_set.get_custom_data_layer_name(i) == Constants.LOOK_DESCRIPTION_LAYER:
			layer_idx = i
			break
	if layer_idx == -1:
		return ""
	var tile_data := terrain_layer.get_cell_tile_data(tile)
	if tile_data == null:
		return ""
	return tile_data.get_custom_data_by_layer_id(layer_idx)

func _on_drop() -> void:
	if PlayerInventory.get_objects().is_empty():
		MessageLog.post("You are not carrying anything.")
		MessageLog.post("")
		return
	_open_inventory()

func _on_object_drop(instance_id: int) -> void:
	var obj := PlayerInventory.find_object_anywhere(instance_id)
	if obj.is_empty():
		return
	_close_inventory()
	var object_id: String = obj["object_id"]
	var obj_name: String = obj["data"].get("name", object_id)
	var stack: int = obj.get("stack_count", 1)
	if stack > 1:
		var raw_plural = obj["data"].get("display_name_plural")
		var plural: String = raw_plural if raw_plural is String else (obj_name + "s")
		prompt_quantity(
			"Drop how many " + plural + "? (max " + str(stack) + ")",
			func(qty: int): _on_drop_qty_chosen(instance_id, object_id, obj_name, qty),
			stack,
			"There aren't that many."
		)
		return
	MessageLog.post("Drop - Direction?")
	prompt_direction(
		func(dir): _resolve_drop(instance_id, object_id, obj_name, 1, dir),
		_cancel_quiet
	)

func _on_drop_qty_chosen(instance_id: int, object_id: String, obj_name: String, qty: int) -> void:
	MessageLog.post("Drop - Direction?")
	prompt_direction(
		func(dir): _resolve_drop(instance_id, object_id, obj_name, qty, dir),
		_cancel_quiet
	)

func _resolve_drop(instance_id: int, object_id: String, obj_name: String, qty: int, dir: Vector2i) -> void:
	if not CombatManager.in_combat:
		GameTime.advance(1)
	var target := tile_pos if dir == Vector2i.ZERO else tile_pos + dir
	if dir != Vector2i.ZERO:
		if not GameManager.is_tile_passable(target) and not GameManager.is_tile_transparent(target):
			MessageLog.post("You cannot drop there.")
			MessageLog.post("")
			return
	if WorldState.is_container_open(target):
		var world_objs := GameManager.get_objects_at(target)
		var container_name: String = ""
		if not world_objs.is_empty():
			var c = world_objs.back()
			container_name = PlayerInventory.get_object_data(c.object_id).get("name", c.object_id)
		var deposited: int = 0
		for _i in range(qty):
			if not GameManager.deposit_into_container(target, object_id, {}):
				break
			deposited += 1
		if deposited == 0:
			MessageLog.post("The container is full.")
			MessageLog.post("")
			_open_inventory_at(instance_id)
			return
		PlayerInventory.take_from_stack(instance_id, deposited)
		if deposited == 1:
			MessageLog.post("You put the " + obj_name + " in the " + container_name + ".")
		else:
			var drop_data_c := PlayerInventory.get_object_data(object_id)
			var raw_plural_c = drop_data_c.get("display_name_plural")
			var plural_c: String = raw_plural_c if raw_plural_c is String else (obj_name + "s")
			MessageLog.post("You put " + str(deposited) + " " + plural_c + " in the " + container_name + ".")
		MessageLog.post("")
		if CombatManager.in_combat:
			CombatManager.on_player_action_taken()
		return
	var drop_data := PlayerInventory.get_object_data(object_id)
	var taken := PlayerInventory.take_from_stack(instance_id, qty)
	if taken <= 0:
		return
	if drop_data.get("type", "") == "corpse":
		GameManager.on_corpse_dropped(instance_id, target)
	else:
		GameManager.spawn_or_merge(object_id, target, taken)
	if taken > 1:
		var raw_plural = drop_data.get("display_name_plural")
		var plural: String = raw_plural if raw_plural is String else (obj_name + "s")
		MessageLog.post("You drop " + str(taken) + " " + plural + ".")
	else:
		MessageLog.post("You drop the " + obj_name + ".")
	MessageLog.post("")
	if CombatManager.in_combat:
		CombatManager.on_player_action_taken()

func _on_use() -> void:
	MessageLog.post("Use - Direction?")
	prompt_direction(func(dir): _resolve_use(dir), _cancel_quiet)

func _resolve_use(dir: Vector2i) -> void:
	if not CombatManager.in_combat:
		GameTime.advance(1)
	if dir == Vector2i.ZERO:
		MessageLog.post("You cannot use that.")
		MessageLog.post("")
		return
	var target_tile := tile_pos + dir
	var world_objects := GameManager.get_objects_at(target_tile)
	if world_objects.is_empty():
		MessageLog.post("You cannot use that.")
		MessageLog.post("")
		return
	var top_obj: WorldObject = world_objects[world_objects.size() - 1]
	if not top_obj.instance_id.is_empty():
		var obj_t := GameManager.get_object_transition(top_obj.instance_id)
		if not obj_t.is_empty():
			GameManager.trigger_transition(obj_t["region_id"], obj_t.get("spawn_id", ""))
			return
	if top_obj.use_actions.is_empty():
		MessageLog.post("You cannot use that.")
		MessageLog.post("")
		return
	var ctx := UseContext.new()
	ctx.actor = self
	ctx.target = top_obj
	ctx.inventory = null
	GameManager._execute_use(ctx)
	if CombatManager.in_combat:
		CombatManager.on_player_action_taken()

func _start_dialogue(npc: NPC) -> void:
	if dialogue_box == null or npc == null:
		return
	held_direction = Vector2i.ZERO
	_in_dialogue = true
	GameManager.dialogue_active = true
	dialogue_box.open(npc)

func _on_inventory_closed() -> void:
	_inventory_open = false

func _on_dialogue_closed() -> void:
	_in_dialogue = false
	_awaiting_prompt = false
	GameManager.dialogue_active = false

func _open_inventory() -> void:
	held_direction = Vector2i.ZERO
	_inventory_open = true
	if GameManager.journal_panel != null:
		GameManager.journal_panel.close()
	if inventory_screen != null:
		inventory_screen.open()

func _open_inventory_at(instance_id: int) -> void:
	held_direction = Vector2i.ZERO
	_inventory_open = true
	if inventory_screen != null:
		inventory_screen.open(instance_id)

func _close_inventory() -> void:
	_inventory_open = false
	if inventory_screen != null:
		inventory_screen.close()

func _on_attack() -> void:
	MessageLog.post("Attack - Direction?")
	prompt_direction(func(dir): _resolve_attack(dir), func(): pass)

func _resolve_attack(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO:
		MessageLog.post("You cannot attack yourself.")
		MessageLog.post("")
		return
	var target_tile: Vector2i = tile_pos + dir
	var npc = WorldState.get_npc_at_tile(target_tile)
	if npc == null:
		MessageLog.post("There is nothing to attack.")
		MessageLog.post("")
		return
	CombatManager.initiate_combat(npc, true)

func attempt_move(direction: Vector2i) -> void:
	var target_tile := tile_pos + direction
	if not GameManager.is_tile_passable(target_tile):
		return
	var fail_chance := GameManager.get_move_fail_chance(target_tile)
	if fail_chance > 0.0 and randf() < fail_chance:
		MessageLog.post("Slow progress!")
		GameTime.advance(1)
		return
	WorldState.clear_occupant(tile_pos)
	tile_pos = target_tile
	position = Constants.tile_to_world(tile_pos)
	WorldState.set_occupant(tile_pos, { "type": "player" })
	GameManager.player_tile = tile_pos
	GameTime.advance(1)
	QuestManager.check_tile_triggers(tile_pos)
	var walk_t := GameManager.get_walk_on_transition(tile_pos)
	if not walk_t.is_empty():
		GameManager.trigger_transition(walk_t["region_id"], walk_t.get("spawn_id", ""))
		return
	var enter_t := GameManager.get_enter_transition(tile_pos)
	if not enter_t.is_empty():
		MessageLog.post("Press E to enter.")

func _get_direction_from_event(event: InputEvent) -> Vector2i:
	if event.is_action_pressed("move_up"): return Vector2i(0, -1)
	if event.is_action_pressed("move_down"): return Vector2i(0, 1)
	if event.is_action_pressed("move_left"): return Vector2i(-1, 0)
	if event.is_action_pressed("move_right"): return Vector2i(1, 0)
	if event.is_action_pressed("move_up_left"): return Vector2i(-1, -1)
	if event.is_action_pressed("move_up_right"): return Vector2i(1, -1)
	if event.is_action_pressed("move_down_left"): return Vector2i(-1, 1)
	if event.is_action_pressed("move_down_right"): return Vector2i(1, 1)
	return Vector2i.ZERO

func _on_move() -> void:
	MessageLog.post("Move - Direction?")
	prompt_direction(func(dir): _resolve_move_source(dir), _cancel_quiet)

func _resolve_move_source(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO:
		MessageLog.post("Move what?")
		MessageLog.post("")
		return
	var source_tile := tile_pos + dir
	var world_objs := GameManager.get_objects_at(source_tile)
	if world_objs.is_empty():
		MessageLog.post("There is nothing to move there.")
		MessageLog.post("")
		return
	var world_obj = world_objs.back()
	if not world_obj.movable:
		MessageLog.post("You cannot move that.")
		MessageLog.post("")
		return
	if world_obj.stack_count > 1:
		var move_data := PlayerInventory.get_object_data(world_obj.object_id)
		var raw_plural_m = move_data.get("display_name_plural")
		var plural_m: String = raw_plural_m if raw_plural_m is String else (move_data.get("name", world_obj.object_id) + "s")
		prompt_quantity(
			"Move how many " + plural_m + "? (max " + str(world_obj.stack_count) + ")",
			func(qty: int): _on_move_qty_chosen(world_obj, source_tile, qty),
			world_obj.stack_count,
			"There aren't that many."
		)
		return
	MessageLog.post("Move to - Direction?")
	prompt_direction(
		func(dest_dir): _resolve_move_destination(world_obj, source_tile, 1, dest_dir),
		_cancel_quiet
	)

func _on_move_qty_chosen(world_obj: Node, source_tile: Vector2i, qty: int) -> void:
	MessageLog.post("Move to - Direction?")
	prompt_direction(
		func(dest_dir): _resolve_move_destination(world_obj, source_tile, qty, dest_dir),
		_cancel_quiet
	)

func _resolve_move_destination(world_obj: Node, source_tile: Vector2i, qty: int, dir: Vector2i) -> void:
	if not CombatManager.in_combat:
		GameTime.advance(1)
	var object_id: String = world_obj.object_id
	var obj_name: String = PlayerInventory.get_object_data(object_id).get("name", object_id)
	if dir == Vector2i.ZERO:
		if WorldState.is_container_open(tile_pos):
			_world_move_into_container(world_obj, source_tile, tile_pos, obj_name, qty)
			if CombatManager.in_combat:
				CombatManager.on_player_action_taken()
		else:
			MessageLog.post("You cannot move that there.")
			MessageLog.post("")
		return
	var dest_tile := source_tile + dir
	if WorldState.is_container_open(dest_tile):
		_world_move_into_container(world_obj, source_tile, dest_tile, obj_name, qty)
		if CombatManager.in_combat:
			CombatManager.on_player_action_taken()
		return
	if not GameManager.is_tile_passable(dest_tile):
		MessageLog.post("You cannot move that there.")
		MessageLog.post("")
		return
	if qty >= world_obj.stack_count:
		WorldState.clear_object_from_tile(source_tile, object_id)
		WorldState.mark_object_tile(dest_tile, object_id)
		world_obj.object_tile = dest_tile
		world_obj.position = Constants.tile_to_world(dest_tile)
	else:
		world_obj.stack_count -= qty
		GameManager.spawn_or_merge(object_id, dest_tile, qty)
	MessageLog.post("You move the " + obj_name + ".")
	MessageLog.post("")
	if CombatManager.in_combat:
		CombatManager.on_player_action_taken()

func _world_move_into_container(world_obj: Node, source_tile: Vector2i, container_tile: Vector2i, obj_name: String, qty: int) -> void:
	var dest_objs := GameManager.get_objects_at(container_tile)
	if dest_objs.is_empty():
		MessageLog.post("You cannot move that there.")
		MessageLog.post("")
		return
	var container = dest_objs.back()
	var container_name: String = PlayerInventory.get_object_data(container.object_id).get("name", container.object_id)
	var deposited: int = 0
	for _i in range(qty):
		if not GameManager.deposit_into_container(container_tile, world_obj.object_id, {}):
			break
		deposited += 1
	if deposited == 0:
		MessageLog.post("The container is full.")
		MessageLog.post("")
		return
	if deposited >= world_obj.stack_count:
		WorldState.clear_object_from_tile(source_tile, world_obj.object_id)
		world_obj.queue_free()
	else:
		world_obj.stack_count -= deposited
	MessageLog.post("You put the " + obj_name + " in the " + container_name + ".")
	MessageLog.post("")

func _is_direction_held(dir: Vector2i) -> bool:
	if dir == Vector2i(0, -1): return Input.is_action_pressed("move_up")
	if dir == Vector2i(0, 1): return Input.is_action_pressed("move_down")
	if dir == Vector2i(-1, 0): return Input.is_action_pressed("move_left")
	if dir == Vector2i(1, 0): return Input.is_action_pressed("move_right")
	if dir == Vector2i(-1, -1): return Input.is_action_pressed("move_up_left")
	if dir == Vector2i(1, -1): return Input.is_action_pressed("move_up_right")
	if dir == Vector2i(-1, 1): return Input.is_action_pressed("move_down_left")
	if dir == Vector2i(1, 1): return Input.is_action_pressed("move_down_right")
	return false

func _begin_rest(hours: int) -> void:
	_rest_active = true
	_rest_ticks_remaining = GameTime.hours_to_ticks(hours)
	_rest_accumulator = 0.0
	MessageLog.post("Resting...")

func _end_rest(completed: bool) -> void:
	_rest_active = false
	_rest_ticks_remaining = 0
	_rest_accumulator = 0.0
	if completed:
		MessageLog.post("Rested.")
	else:
		MessageLog.post("Rest cancelled.")
	MessageLog.post("")

func interrupt_rest() -> void:
	if not _rest_active:
		return
	_rest_active = false
	_rest_ticks_remaining = 0
	_rest_accumulator = 0.0
	MessageLog.post("Thy rest is interrupted!")
	MessageLog.post("")

func _check_rest_interrupt() -> void:
	pass
