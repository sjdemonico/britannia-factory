class_name Player
extends CharacterBody2D

var INITIAL_DELAY: float = 0.4
var REPEAT_INTERVAL: float = 0.1

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
var _direction_prompt_active: bool = false

var _spell_targeting_active: bool = false
var _spell_targeting_range: int = 0
var _spell_targeting_tile: Vector2i = Vector2i.ZERO
var _spell_targeting_on_move: Callable = Callable()
var _spell_targeting_on_confirm: Callable = Callable()
var _spell_targeting_on_cancel: Callable = Callable()

var _awaiting_quantity: bool = false
var _quantity_buffer: String = ""
var _quantity_max: int = -1
var _quantity_error_text: String = ""
var _quantity_callback: Callable
var _quantity_cancel: Callable

var _awaiting_party_member: bool = false
var _party_member_callback: Callable
var _party_member_cancel: Callable
var _party_member_options: Array[PartyMember] = []

var _awaiting_party_order: bool = false
var _party_order_buffer: String = ""
var _party_order_callback: Callable
var _party_order_cancel: Callable
var _party_order_size: int = 0

var _awaiting_party_talk: bool = false
var _party_talk_options: Array[PartyMember] = []

var is_invisible: bool = false
var is_paralyzed: bool = false

var _rest_active: bool = false
var _rest_ticks_remaining: int = 0
var _rest_ticks_this_hour: int = 0
var _rest_interrupt_base_chance: float = 0.1
var _rest_interrupt_tile_mults: Dictionary = {}
var _rest_accumulator: float = 0.0
var _awaiting_rest_duration: bool = false
var _wait_held: bool = false

var _mouse_path: Array[Vector2i] = []
var _mouse_pathing: bool = false
var _attack_target_on_arrival: Node = null
var _talk_target_on_arrival: Node = null
var _selected_npc: Node = null

var sprite_path = null
var sprite_path_cast = null
var sprite_path_attack = null
var _sprite_handle: int = -1
var _anim_state: String = "idle"

func _ready() -> void:
	INITIAL_DELAY = GameManager.key_initial_delay
	REPEAT_INTERVAL = GameManager.key_repeat_interval
	position = Constants.tile_to_world(tile_pos)
	WorldState.set_occupant(tile_pos, { "type": "player" })
	GameManager.player_tile = tile_pos
	GameManager.player_class_changed.connect(_initialize_sprite)
	call_deferred("_initialize_sprite")

func _initialize_sprite() -> void:
	if _sprite_handle >= 0 and GameManager.sprite_animator != null:
		GameManager.sprite_animator.unregister(_sprite_handle)
		_sprite_handle = -1
	var member := PartyManager.get_player()
	if member == null:
		return
	var cls_data: Dictionary = GameManager.class_registry.get_class_data(member.class_id)
	sprite_path = cls_data.get("sprite_path", null)
	sprite_path_cast = cls_data.get("sprite_path_cast", null)
	sprite_path_attack = cls_data.get("sprite_path_attack", null)
	_sprite_handle = GameManager.sprite_animator.register($Sprite2D, sprite_path, Constants.SPRITE_WORLD_SIZE)

func set_anim_state(state: String) -> void:
	_anim_state = state
	if _sprite_handle < 0:
		return
	match state:
		"idle":
			GameManager.sprite_animator.set_sheet(_sprite_handle, sprite_path)
		"cast":
			var sheet = sprite_path_cast if sprite_path_cast != null else sprite_path
			GameManager.sprite_animator.set_sheet(_sprite_handle, sheet)
		"attack":
			var sheet = sprite_path_attack if sprite_path_attack != null else sprite_path
			GameManager.sprite_animator.set_sheet(_sprite_handle, sheet)

func _exit_tree() -> void:
	if _sprite_handle >= 0 and GameManager.sprite_animator != null:
		GameManager.sprite_animator.unregister(_sprite_handle)

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
				MessageLog.post(MessageRegistry.get_message("action_cancelled"))
				MessageLog.post_blank()
			elif ch >= 49 and ch <= 57:
				_awaiting_rest_duration = false
				_begin_rest(ch - 48)
		return

	if _awaiting_party_member:
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
			var ch: int = (event as InputEventKey).unicode
			if (event as InputEventKey).is_action_pressed("ui_cancel") or ch == 48:  # 0 or Escape
				_awaiting_party_member = false
				_party_member_options = []
				MessageLog.post(MessageRegistry.get_message("action_cancelled"))
				MessageLog.post_blank()
				if _party_member_cancel.is_valid():
					_party_member_cancel.call()
			else:
				var idx: int = ch - 49  # '1' → 0, '2' → 1, etc.
				if idx >= 0 and idx < _party_member_options.size():
					_awaiting_party_member = false
					var selected: PartyMember = _party_member_options[idx]
					_party_member_options = []
					_party_member_callback.call(selected)
		get_viewport().set_input_as_handled()
		return

	if _awaiting_party_talk:
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
			var ch: int = (event as InputEventKey).unicode
			if (event as InputEventKey).is_action_pressed("ui_cancel") or ch == 48:  # 0 or Escape
				_awaiting_party_talk = false
				_party_talk_options = []
				MessageLog.post(MessageRegistry.get_message("action_cancelled"))
				MessageLog.post_blank()
			else:
				var idx: int = ch - 49  # '1' → 0, '2' → 1, etc.
				if idx >= 0 and idx < _party_talk_options.size():
					_awaiting_party_talk = false
					var selected: PartyMember = _party_talk_options[idx]
					_party_talk_options = []
					_start_party_member_dialogue(selected)
		get_viewport().set_input_as_handled()
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

	if _awaiting_party_order:
		var key_event := event as InputEventKey
		if key_event != null and key_event.pressed and not key_event.echo:
			if key_event.is_action_pressed("ui_cancel"):
				_cancel_party_order()
			elif key_event.keycode == KEY_BACKSPACE:
				if not _party_order_buffer.is_empty():
					_party_order_buffer = _party_order_buffer.left(_party_order_buffer.length() - 1)
				MessageLog.update_last(_party_order_buffer + "_")
			elif key_event.is_action_pressed("ui_accept"):
				_confirm_party_order()
			elif (key_event.unicode >= 48 and key_event.unicode <= 57) or key_event.unicode == 32:
				_party_order_buffer += char(key_event.unicode)
				MessageLog.update_last(_party_order_buffer + "_")
		get_viewport().set_input_as_handled()
		return

	if _mouse_pathing and event.is_action_pressed("ui_cancel"):
		cancel_mouse_path()

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

	if GameManager.is_any_panel_open():
		return

	if event.is_action_pressed("equip"):
		var enter_t := GameManager.get_enter_transition(tile_pos)
		if not enter_t.is_empty():
			GameManager.trigger_transition(enter_t["region_id"], enter_t.get("spawn_id", ""))
		else:
			MessageLog.post(MessageRegistry.get_message("enter_nothing"))
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

	if _spell_targeting_active:
		if event.is_action_pressed("ui_cancel"):
			_spell_targeting_active = false
			_spell_targeting_on_cancel.call()
		elif event.is_action_pressed("ui_accept"):
			var confirmed_tile := _spell_targeting_tile
			_spell_targeting_active = false
			_spell_targeting_on_confirm.call(confirmed_tile)
		else:
			var dir := _get_direction_from_event(event)
			if dir != Vector2i.ZERO:
				var new_tile := _spell_targeting_tile + dir
				var in_range := true
				if _spell_targeting_range > 0:
					var dist := maxi(abs(new_tile.x - tile_pos.x), abs(new_tile.y - tile_pos.y))
					in_range = dist <= _spell_targeting_range
				if in_range:
					_spell_targeting_tile = new_tile
					_spell_targeting_on_move.call(_spell_targeting_tile)
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
			MessageLog.post(MessageRegistry.get_message("rest_prompt"))
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
			if _mouse_pathing:
				cancel_mouse_path()
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
			_rest_ticks_this_hour -= 1
			if _rest_ticks_this_hour <= 0:
				_on_rest_hour_advanced()
				if _rest_active:
					_rest_ticks_this_hour = GameTime.hours_to_ticks(1)
			if _rest_active and _rest_ticks_remaining <= 0:
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

	if _mouse_pathing:
		if _in_dialogue or _inventory_open or GameManager.is_any_panel_open() or moving or CombatManager.in_combat:
			return
		if _mouse_path.is_empty():
			_finish_mouse_path()
			return
		var next_tile: Vector2i = _mouse_path[0]
		if not GameManager.is_tile_passable(next_tile):
			cancel_mouse_path()
			return
		var dir: Vector2i = next_tile - tile_pos
		attempt_move(dir)
		if tile_pos == next_tile:
			_mouse_path.remove_at(0)
			if _mouse_path.is_empty():
				_finish_mouse_path()
		return

	if _in_dialogue or _inventory_open or GameManager.is_any_panel_open() or moving or held_direction == Vector2i.ZERO:
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
	_direction_prompt_active = true
	_prompt_callback = callback
	_prompt_cancel = on_cancel
	if _inventory_open:
		_close_inventory()
	if GameManager.direction_overlay != null:
		GameManager.direction_overlay.show_prompt(tile_pos)

func _on_direction_prompt_map_click(tile: Vector2i) -> void:
	if GameManager.direction_overlay != null:
		GameManager.direction_overlay.hide_prompt()
	_direction_prompt_active = false
	var delta: Vector2i = tile - tile_pos
	if delta == Vector2i.ZERO:
		_resolve_prompt(Vector2i.ZERO)
	elif absi(delta.x) <= 1 and absi(delta.y) <= 1:
		_resolve_prompt(delta)
	else:
		_cancel_prompt()

func prompt_party_member(callback: Callable, on_cancel: Callable = Callable(), prompt_label: String = "Who?") -> void:
	var living := PartyManager.get_living_members()
	if living.size() <= 1:
		callback.call(living[0] if not living.is_empty() else PartyManager.get_player())
		return
	_party_member_options = living
	_party_member_callback = callback
	_party_member_cancel = on_cancel
	_awaiting_party_member = true
	var parts: Array = []
	for i in range(living.size()):
		parts.append(str(i + 1) + ". " + living[i].display_name)
	MessageLog.post(prompt_label + "  " + "  ".join(parts))

func prompt_party_member_for_resurrect(callback: Callable, on_cancel: Callable = Callable()) -> void:
	var downed := PartyManager.get_downed_members()
	if downed.is_empty():
		if on_cancel.is_valid():
			on_cancel.call()
		return
	if downed.size() == 1:
		callback.call(downed[0])
		return
	_party_member_options = downed
	_party_member_callback = callback
	_party_member_cancel = on_cancel
	_awaiting_party_member = true
	var parts: Array = []
	for i in range(downed.size()):
		parts.append(str(i + 1) + ". " + downed[i].display_name)
	MessageLog.post(MessageRegistry.get_message("prompt_resurrect_whom") + "  ".join(parts))

func prompt_party_order(callback: Callable, on_cancel: Callable = Callable()) -> void:
	if PartyManager.get_party_size() == 1:
		MessageLog.post(MessageRegistry.get_message("party_order_single"))
		MessageLog.post_blank()
		return
	_party_order_callback = callback
	_party_order_cancel = on_cancel
	_party_order_buffer = ""
	_party_order_size = PartyManager.get_party_size()
	_awaiting_party_order = true
	var members := PartyManager.get_all_members()
	var parts: Array = []
	for i in range(members.size()):
		parts.append(str(i + 1) + ". " + members[i].display_name)
	MessageLog.post(MessageRegistry.get_message("prompt_party_order") + "  ".join(parts))
	MessageLog.post(MessageRegistry.get_message("party_order_prompt"))
	MessageLog.post("_")

func _confirm_party_order() -> void:
	var tokens: Array = _party_order_buffer.strip_edges().split(" ", false)
	var indices: Array[int] = []
	var valid := true
	for t in tokens:
		if not t.is_valid_int():
			valid = false
			break
		indices.append(int(t))
	if valid:
		if indices.size() != _party_order_size:
			valid = false
		else:
			var seen: Dictionary = {}
			for idx in indices:
				if idx < 1 or idx > _party_order_size or seen.has(idx):
					valid = false
					break
				seen[idx] = true
	if not valid:
		MessageLog.post(MessageRegistry.get_message("party_order_invalid"))
		_party_order_buffer = ""
		MessageLog.post("_")
		return
	_awaiting_party_order = false
	var result: Array[int] = []
	for idx in indices:
		result.append(idx)
	_party_order_callback.call(result)

func _cancel_party_order() -> void:
	_awaiting_party_order = false
	_party_order_buffer = ""
	if _party_order_cancel.is_valid():
		_party_order_cancel.call()

func start_spell_targeting(range_tiles: int, on_move: Callable, on_confirm: Callable, on_cancel: Callable) -> void:
	held_direction = Vector2i.ZERO
	_spell_targeting_active = true
	_spell_targeting_range = range_tiles
	_spell_targeting_tile = tile_pos
	_spell_targeting_on_move = on_move
	_spell_targeting_on_confirm = on_confirm
	_spell_targeting_on_cancel = on_cancel

func _resolve_prompt(dir: Vector2i) -> void:
	_awaiting_prompt = false
	_direction_prompt_active = false
	if GameManager.direction_overlay != null:
		GameManager.direction_overlay.hide_prompt()
	_prompt_callback.call(dir)

func _cancel_prompt() -> void:
	_awaiting_prompt = false
	_direction_prompt_active = false
	if GameManager.direction_overlay != null:
		GameManager.direction_overlay.hide_prompt()
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
		MessageLog.post(_quantity_error_text if not _quantity_error_text.is_empty() else MessageRegistry.get_message("quantity_invalid"))
		_quantity_buffer = ""
		return
	_awaiting_quantity = false
	_quantity_callback.call(qty)

func _cancel_quantity() -> void:
	_awaiting_quantity = false
	_quantity_buffer = ""
	MessageLog.post(MessageRegistry.get_message("action_cancelled"))
	MessageLog.post_blank()
	if _quantity_cancel.is_valid():
		_quantity_cancel.call()

func _on_talk() -> void:
	MessageLog.post(MessageRegistry.get_message("talk_prompt"))
	prompt_direction(func(dir): _resolve_talk(dir), _cancel_quiet)

func _resolve_talk(dir: Vector2i) -> void:
	if not CombatManager.in_combat:
		GameTime.advance(1)
	if dir == Vector2i.ZERO:
		_do_party_talk()
		return
	var target_tile := tile_pos + dir
	var occupant := WorldState.get_occupant(target_tile)
	if occupant.get("type", "") == "npc":
		var npc := occupant.get("node") as NPC
		if npc != null and not npc._talkable:
			MessageLog.post(npc.get_not_talkable_message())
			MessageLog.post_blank()
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
				MessageLog.post_blank()
				return
			if CombatManager.in_combat:
				CombatManager.on_player_action_taken()
			_start_dialogue(npc)
			return
	MessageLog.post(MessageRegistry.get_message("talk_nobody"))
	MessageLog.post_blank()

func _do_party_talk() -> void:
	var npc_members: Array[PartyMember] = []
	for m in PartyManager.get_all_members():
		if m.member_id != Constants.PLAYER_MEMBER_ID:
			npc_members.append(m)
	if npc_members.is_empty():
		MessageLog.post(MessageRegistry.get_message("party_no_members_to_talk"))
		MessageLog.post_blank()
		return
	if npc_members.size() == 1:
		_start_party_member_dialogue(npc_members[0])
		return
	var parts: Array = []
	for i in range(npc_members.size()):
		parts.append(str(i + 1) + ". " + npc_members[i].display_name)
	MessageLog.post(MessageRegistry.get_message("prompt_talk_to_whom") + "  ".join(parts))
	_party_talk_options = npc_members
	_awaiting_party_talk = true

func _start_party_member_dialogue(member: PartyMember) -> void:
	if dialogue_box == null:
		return
	held_direction = Vector2i.ZERO
	_in_dialogue = true
	GameManager.dialogue_active = true
	dialogue_box.open_for_party_member(member)

func _on_get_prompt() -> void:
	MessageLog.post(MessageRegistry.get_message("get_prompt"))
	prompt_direction(func(dir): _resolve_get(dir), _cancel_quiet)

func _resolve_get(dir: Vector2i) -> void:
	if not CombatManager.in_combat:
		GameTime.advance(1)
	var target := tile_pos if dir == Vector2i.ZERO else tile_pos + dir
	var world_objects := GameManager.get_objects_at(target)
	if world_objects.is_empty():
		MessageLog.post(MessageRegistry.get_message("get_nothing"))
		MessageLog.post_blank()
		return
	var top_obj = world_objects[world_objects.size() - 1]
	if not top_obj.carriable:
		MessageLog.post(MessageRegistry.get_message("get_not_carriable"))
		MessageLog.post_blank()
		return
	var data := PlayerInventory.get_object_data(top_obj.object_id)
	if top_obj.stack_count > 1:
		var stack_max: int = top_obj.stack_count
		var on_qty_chosen := func(qty: int):
			prompt_party_member(
				func(member: PartyMember):
					_do_get(top_obj, data, qty, member)
					if CombatManager.in_combat:
						CombatManager.on_player_action_taken(),
				_cancel_quiet
			)
		prompt_quantity(
			MessageRegistry.get_message("get_how_many", {"max": str(stack_max)}),
			on_qty_chosen,
			stack_max,
			MessageRegistry.get_message("quantity_too_many")
		)
		return
	prompt_party_member(
		func(member: PartyMember):
			_do_get(top_obj, data, 1, member)
			if CombatManager.in_combat:
				CombatManager.on_player_action_taken(),
		_cancel_quiet
	)

func _do_get(top_obj: WorldObject, data: Dictionary, qty: int, member: PartyMember = null) -> void:
	if member == null:
		member = PartyManager.get_player()
	if not is_instance_valid(top_obj):
		MessageLog.post(MessageRegistry.get_message("get_gone"))
		MessageLog.post_blank()
		return
	var member_inv: Inventory = member.inventory if member != null and member.inventory != null else PlayerInventory.get_inventory()
	var carry_limit: float = float(member.stat_block.get_effective_value("carry_limit")) if member != null and member.stat_block != null else float(PlayerStats.get_effective_value("carry_limit"))
	if qty > 1:
		if carry_limit > 0.0:
			var current_weight: float = member_inv.get_total_weight()
			if current_weight + top_obj.weight * qty > carry_limit:
				var available: float = carry_limit - current_weight
				qty = int(available / top_obj.weight)
				if qty <= 0:
					MessageLog.post(MessageRegistry.get_message("inventory_too_heavy"))
					MessageLog.post_blank()
					return
				MessageLog.post(MessageRegistry.get_message("get_partial_count", {"count": str(qty)}))
	else:
		if carry_limit > 0.0 and member_inv.get_total_weight() + top_obj.get_total_weight() > carry_limit:
			MessageLog.post(MessageRegistry.get_message("inventory_too_heavy"))
			MessageLog.post_blank()
			return
	var pick_name: String = top_obj.get_display_name()
	var object_id: String = top_obj.object_id
	var object_tile: Vector2i = top_obj.object_tile
	if qty >= top_obj.stack_count:
		if member != null and member.member_id == Constants.PLAYER_MEMBER_ID:
			PlayerInventory.add_stacked(object_id, qty)
		else:
			member_inv.add_stacked(object_id, qty)
		WorldState.clear_object_from_tile(object_tile, object_id)
		top_obj.queue_free()
	else:
		top_obj.stack_count -= qty
		if member != null and member.member_id == Constants.PLAYER_MEMBER_ID:
			PlayerInventory.add_stacked(object_id, qty)
		else:
			member_inv.add_stacked(object_id, qty)
	if qty > 1:
		var raw_plural = data.get("display_name_plural")
		var plural: String = raw_plural if raw_plural is String else (pick_name + "s")
		MessageLog.post(MessageRegistry.get_message("get_picked_up_plural", {"count": str(qty), "name": plural}))
	else:
		MessageLog.post(MessageRegistry.get_message("get_picked_up", {"name": pick_name}))
	MessageLog.post_blank()
	SoundManager.play_event("item_pickup")

func _on_look_prompt() -> void:
	MessageLog.post(MessageRegistry.get_message("look_prompt"))
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
		parts.append(MessageRegistry.get_message("look_standing_here"))

	if occupant.get("type", "") == "npc":
		var npc_node := occupant.get("node") as NPC
		if npc_node != null and not npc_node.flavor_text.is_empty():
			parts.append(npc_node.flavor_text)
		else:
			var npc_label: String = npc_node.display_name if npc_node != null else occupant.get("id", "someone")
			parts.append(MessageRegistry.get_message("look_see", {"name": npc_label}))

	# Step 1: structural object takes priority over terrain description
	var structural_obj: WorldObject = null
	for wo in world_objects:
		if wo.object_type == "structural":
			structural_obj = wo
			break

	if structural_obj != null:
		var s_data := PlayerInventory.get_object_data(structural_obj.object_id)
		var s_desc: String = s_data.get("description", "")
		var s_line: String
		if not s_desc.is_empty():
			s_line = MessageRegistry.get_message("look_see_desc", {"description": s_desc})
		else:
			s_line = MessageRegistry.get_message("look_see", {"name": structural_obj.get_display_name()})
		if structural_obj.toggleable:
			s_line += " " + MessageRegistry.get_message("look_is_open" if structural_obj.is_open else "look_is_closed")
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
			var state: String = MessageRegistry.get_message("look_is_open" if wo.is_open else "look_is_closed")
			parts.append((desc + " " if not desc.is_empty() else "") + state)

	# Step 2: non-structural objects on tile
	var non_structural: Array = []
	for wo in world_objects:
		if wo.object_type != "structural":
			non_structural.append(wo)

	if not non_structural.is_empty():
		var names: Array = []
		for wo in non_structural:
			var wo_name: String
			if wo.stack_count > 1:
				var wo_data := PlayerInventory.get_object_data(wo.object_id)
				var raw_plural = wo_data.get("display_name_plural")
				var plural: String = raw_plural if raw_plural is String else (wo.get_display_name() + "s")
				wo_name = str(wo.stack_count) + " " + plural
			else:
				wo_name = wo.get_display_name()
			names.append(wo_name)
		var prefix: String
		if structural_obj != null and not structural_obj.surface_name.is_empty():
			prefix = MessageRegistry.get_message("look_on_surface", {"surface": structural_obj.surface_name})
		else:
			prefix = MessageRegistry.get_message("look_on_ground")
		parts.append(prefix + ": " + Constants.natural_list(names) + ".")

	# Container disgorge
	for wo in world_objects:
		if wo.container_open and not wo._content_ids.is_empty():
			var cont_name: String = wo.get_display_name()
			for content_id in wo._content_ids:
				GameManager.spawn_object(content_id, tile)
			wo._content_ids.clear()
			parts.append(MessageRegistry.get_message("look_container_disgorges", {"name": cont_name}))

	if parts.is_empty():
		MessageLog.post(MessageRegistry.get_message("look_nothing"))
	else:
		for p in parts:
			MessageLog.post(p)
	MessageLog.post_blank()

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
		MessageLog.post(MessageRegistry.get_message("inventory_empty"))
		MessageLog.post_blank()
		return
	_open_inventory()

func _on_object_drop(instance_id: int) -> void:
	var obj := PlayerInventory.find_object_anywhere(instance_id)
	if obj.is_empty():
		return
	_close_inventory()
	var object_id: String = obj["object_id"]
	var obj_name: String = Inventory.get_item_display_name(obj["data"])
	var stack: int = obj.get("stack_count", 1)
	if stack > 1:
		var raw_plural = obj["data"].get("display_name_plural")
		var plural: String = raw_plural if raw_plural is String else (obj_name + "s")
		prompt_quantity(
			MessageRegistry.get_message("drop_how_many", {"name": plural, "max": str(stack)}),
			func(qty: int): _on_drop_qty_chosen(instance_id, object_id, obj_name, qty),
			stack,
			MessageRegistry.get_message("quantity_too_many")
		)
		return
	MessageLog.post(MessageRegistry.get_message("drop_prompt"))
	prompt_direction(
		func(dir): _resolve_drop(instance_id, object_id, obj_name, 1, dir),
		_cancel_quiet
	)

func _on_drop_qty_chosen(instance_id: int, object_id: String, obj_name: String, qty: int) -> void:
	MessageLog.post(MessageRegistry.get_message("drop_prompt"))
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
			MessageLog.post(MessageRegistry.get_message("drop_blocked"))
			MessageLog.post_blank()
			return
	if WorldState.is_container_open(target):
		var world_objs := GameManager.get_objects_at(target)
		var container_name: String = ""
		if not world_objs.is_empty():
			var c = world_objs.back()
			container_name = (c as WorldObject).get_display_name()
		var deposited: int = 0
		for _i in range(qty):
			if not GameManager.deposit_into_container(target, object_id, {}):
				break
			deposited += 1
		if deposited == 0:
			MessageLog.post(MessageRegistry.get_message("inventory_container_full"))
			MessageLog.post_blank()
			_open_inventory_at(instance_id)
			return
		PlayerInventory.take_from_stack(instance_id, deposited)
		if deposited == 1:
			MessageLog.post(MessageRegistry.get_message("put_in_container", {"name": obj_name, "container": container_name}))
		else:
			var drop_data_c := PlayerInventory.get_object_data(object_id)
			var raw_plural_c = drop_data_c.get("display_name_plural")
			var plural_c: String = raw_plural_c if raw_plural_c is String else (obj_name + "s")
			MessageLog.post(MessageRegistry.get_message("put_in_container_plural", {"count": str(deposited), "name": plural_c, "container": container_name}))
		MessageLog.post_blank()
		SoundManager.play_event("item_drop")
		if CombatManager.in_combat:
			CombatManager.on_player_action_taken()
		return
	var drop_data := PlayerInventory.get_object_data(object_id)
	var pending_duration: int = PlayerInventory.get_pending_drop_duration(instance_id)
	var taken := PlayerInventory.take_from_stack(instance_id, qty)
	if taken <= 0:
		return
	if pending_duration >= 0 and taken == 1:
		GameManager.spawn_with_duration(object_id, target, pending_duration)
	else:
		GameManager.spawn_or_merge(object_id, target, taken)
	if taken > 1:
		var raw_plural = drop_data.get("display_name_plural")
		var plural: String = raw_plural if raw_plural is String else (obj_name + "s")
		MessageLog.post(MessageRegistry.get_message("drop_plural", {"count": str(taken), "name": plural}))
	else:
		MessageLog.post(MessageRegistry.get_message("drop_single", {"name": obj_name}))
	MessageLog.post_blank()
	SoundManager.play_event("item_drop")
	if CombatManager.in_combat:
		CombatManager.on_player_action_taken()

func _on_use() -> void:
	MessageLog.post(MessageRegistry.get_message("use_prompt"))
	prompt_direction(func(dir): _resolve_use(dir), _cancel_quiet)

func _resolve_use(dir: Vector2i) -> void:
	if not CombatManager.in_combat:
		GameTime.advance(1)
	if dir == Vector2i.ZERO:
		MessageLog.post(MessageRegistry.get_message("use_cannot_use"))
		MessageLog.post_blank()
		return
	var target_tile := tile_pos + dir
	var world_objects := GameManager.get_objects_at(target_tile)
	if world_objects.is_empty():
		MessageLog.post(MessageRegistry.get_message("use_cannot_use"))
		MessageLog.post_blank()
		return
	var top_obj: WorldObject = world_objects[world_objects.size() - 1]
	if not top_obj.instance_id.is_empty():
		var obj_t := GameManager.get_object_transition(top_obj.instance_id)
		if not obj_t.is_empty():
			GameManager.trigger_transition(obj_t["region_id"], obj_t.get("spawn_id", ""))
			return
	if top_obj.use_actions.is_empty():
		MessageLog.post(MessageRegistry.get_message("use_cannot_use"))
		MessageLog.post_blank()
		return
	var ctx := UseContext.new()
	ctx.actor = self
	ctx.target = top_obj
	ctx.inventory = null
	GameManager.execute_use(ctx)
	if CombatManager.in_combat:
		CombatManager.on_player_action_taken()

func _start_dialogue(npc: NPC) -> void:
	if npc == null:
		return
	if GameManager.try_open_shop(npc):
		return
	if GameManager.try_open_healer(npc):
		return
	if dialogue_box == null:
		return
	held_direction = Vector2i.ZERO
	_in_dialogue = true
	GameManager.dialogue_active = true
	if not npc.talk_sound.is_empty():
		SoundManager.play_sfx(npc.talk_sound)
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
	if GameManager.spellbook_panel != null:
		GameManager.spellbook_panel.close()
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
	MessageLog.post(MessageRegistry.get_message("attack_prompt"))
	prompt_direction(func(dir): _resolve_attack(dir), func(): pass)

func _resolve_attack(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO:
		MessageLog.post(MessageRegistry.get_message("attack_self"))
		MessageLog.post_blank()
		return
	var target_tile: Vector2i = tile_pos + dir
	var npc = WorldState.get_npc_at_tile(target_tile)
	if npc == null:
		MessageLog.post(MessageRegistry.get_message("attack_nothing"))
		MessageLog.post_blank()
		return
	CombatManager.initiate_combat(npc, true)

func attempt_move(direction: Vector2i) -> void:
	var target_tile := tile_pos + direction
	if not GameManager.is_tile_passable(target_tile):
		return
	var fail_chance := GameManager.get_move_fail_chance(target_tile)
	if fail_chance > 0.0 and randf() < fail_chance:
		MessageLog.post(MessageRegistry.get_message("movement_slow_progress"))
		GameTime.advance(1)
		return
	WorldState.clear_occupant(tile_pos)
	tile_pos = target_tile
	position = Constants.tile_to_world(tile_pos)
	WorldState.set_occupant(tile_pos, { "type": "player" })
	GameManager.player_tile = tile_pos
	GameManager.on_player_moved(tile_pos)
	GameTime.advance(1)
	QuestManager.check_tile_triggers(tile_pos)
	var walk_t := GameManager.get_walk_on_transition(tile_pos)
	if not walk_t.is_empty():
		GameManager.trigger_transition(walk_t["region_id"], walk_t.get("spawn_id", ""))
		return
	var enter_t := GameManager.get_enter_transition(tile_pos)
	if not enter_t.is_empty():
		MessageLog.post(MessageRegistry.get_message("transition_enter_prompt"))

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
	MessageLog.post(MessageRegistry.get_message("move_object_prompt"))
	prompt_direction(func(dir): _resolve_move_source(dir), _cancel_quiet)

func _resolve_move_source(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO:
		MessageLog.post(MessageRegistry.get_message("move_object_what"))
		MessageLog.post_blank()
		return
	var source_tile := tile_pos + dir
	var world_objs := GameManager.get_objects_at(source_tile)
	if world_objs.is_empty():
		MessageLog.post(MessageRegistry.get_message("move_object_nothing"))
		MessageLog.post_blank()
		return
	var world_obj = world_objs.back()
	if not world_obj.movable:
		MessageLog.post(MessageRegistry.get_message("move_object_cannot"))
		MessageLog.post_blank()
		return
	if world_obj.stack_count > 1:
		var move_data := PlayerInventory.get_object_data(world_obj.object_id)
		var raw_plural_m = move_data.get("display_name_plural")
		var plural_m: String = raw_plural_m if raw_plural_m is String else ((world_obj as WorldObject).get_display_name() + "s")
		prompt_quantity(
			MessageRegistry.get_message("move_object_how_many", {"name": plural_m, "max": str(world_obj.stack_count)}),
			func(qty: int): _on_move_qty_chosen(world_obj, source_tile, qty),
			world_obj.stack_count,
			MessageRegistry.get_message("quantity_too_many")
		)
		return
	MessageLog.post(MessageRegistry.get_message("move_object_dest_prompt"))
	prompt_direction(
		func(dest_dir): _resolve_move_destination(world_obj, source_tile, 1, dest_dir),
		_cancel_quiet
	)

func _on_move_qty_chosen(world_obj: Node, source_tile: Vector2i, qty: int) -> void:
	MessageLog.post(MessageRegistry.get_message("move_object_dest_prompt"))
	prompt_direction(
		func(dest_dir): _resolve_move_destination(world_obj, source_tile, qty, dest_dir),
		_cancel_quiet
	)

func _resolve_move_destination(world_obj: Node, source_tile: Vector2i, qty: int, dir: Vector2i) -> void:
	if not CombatManager.in_combat:
		GameTime.advance(1)
	var object_id: String = world_obj.object_id
	var obj_name: String = (world_obj as WorldObject).get_display_name()
	if dir == Vector2i.ZERO:
		if WorldState.is_container_open(tile_pos):
			_world_move_into_container(world_obj, source_tile, tile_pos, obj_name, qty)
			if CombatManager.in_combat:
				CombatManager.on_player_action_taken()
		else:
			MessageLog.post(MessageRegistry.get_message("move_object_blocked"))
			MessageLog.post_blank()
		return
	var dest_tile := source_tile + dir
	if WorldState.is_container_open(dest_tile):
		_world_move_into_container(world_obj, source_tile, dest_tile, obj_name, qty)
		if CombatManager.in_combat:
			CombatManager.on_player_action_taken()
		return
	if not GameManager.is_tile_passable(dest_tile):
		MessageLog.post(MessageRegistry.get_message("move_object_blocked"))
		MessageLog.post_blank()
		return
	if qty >= world_obj.stack_count:
		WorldState.clear_object_from_tile(source_tile, object_id)
		WorldState.mark_object_tile(dest_tile, object_id)
		world_obj.object_tile = dest_tile
		world_obj.position = Constants.tile_to_world(dest_tile)
	else:
		world_obj.stack_count -= qty
		GameManager.spawn_or_merge(object_id, dest_tile, qty)
	MessageLog.post(MessageRegistry.get_message("move_object_done", {"name": obj_name}))
	MessageLog.post_blank()
	if CombatManager.in_combat:
		CombatManager.on_player_action_taken()

func _world_move_into_container(world_obj: Node, source_tile: Vector2i, container_tile: Vector2i, obj_name: String, qty: int) -> void:
	var dest_objs := GameManager.get_objects_at(container_tile)
	if dest_objs.is_empty():
		MessageLog.post(MessageRegistry.get_message("move_object_blocked"))
		MessageLog.post_blank()
		return
	var container = dest_objs.back()
	var container_name: String = (container as WorldObject).get_display_name()
	var deposited: int = 0
	for _i in range(qty):
		if not GameManager.deposit_into_container(container_tile, world_obj.object_id, {}):
			break
		deposited += 1
	if deposited == 0:
		MessageLog.post(MessageRegistry.get_message("inventory_container_full"))
		MessageLog.post_blank()
		return
	if deposited >= world_obj.stack_count:
		WorldState.clear_object_from_tile(source_tile, world_obj.object_id)
		world_obj.queue_free()
	else:
		world_obj.stack_count -= deposited
	MessageLog.post(MessageRegistry.get_message("put_in_container", {"name": obj_name, "container": container_name}))
	MessageLog.post_blank()

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

# ── Mouse-path movement ───────────────────────────────────────────────────────

func start_mouse_path(path: Array[Vector2i]) -> void:
	_mouse_path = path.duplicate()
	_mouse_pathing = true
	held_direction = Vector2i.ZERO
	_wait_held = false

func cancel_mouse_path() -> void:
	_mouse_pathing = false
	_mouse_path.clear()
	_attack_target_on_arrival = null
	_talk_target_on_arrival = null
	set_selected_npc(null)

func set_selected_npc(npc: Node) -> void:
	if _selected_npc != null and is_instance_valid(_selected_npc):
		_selected_npc.modulate = Color.WHITE
	_selected_npc = npc
	if npc != null and is_instance_valid(npc):
		npc.modulate = GameManager.npc_selection_highlight_color

func start_dialogue_with_npc(npc: NPC) -> void:
	_start_dialogue(npc)

func _finish_mouse_path() -> void:
	_mouse_pathing = false
	var attack_npc: Node = _attack_target_on_arrival
	var talk_npc: Node = _talk_target_on_arrival
	_attack_target_on_arrival = null
	_talk_target_on_arrival = null
	set_selected_npc(null)
	if attack_npc != null and is_instance_valid(attack_npc):
		CombatManager.initiate_combat(attack_npc as NPC, true)
	elif talk_npc != null and is_instance_valid(talk_npc):
		_start_dialogue(talk_npc as NPC)

func _begin_rest(hours: int) -> void:
	_rest_active = true
	_rest_ticks_remaining = GameTime.hours_to_ticks(hours)
	_rest_ticks_this_hour = GameTime.hours_to_ticks(1)
	_rest_interrupt_base_chance = GameTime.get_rest_interrupt_base_chance()
	_rest_interrupt_tile_mults = _load_tile_interrupt_mults()
	_rest_accumulator = 0.0
	MessageLog.post(MessageRegistry.get_message("rest_resting"))

func _end_rest(completed: bool) -> void:
	_rest_active = false
	_rest_ticks_remaining = 0
	_rest_accumulator = 0.0
	if completed:
		MessageLog.post(MessageRegistry.get_message("rest_done"))
	else:
		MessageLog.post(MessageRegistry.get_message("rest_cancelled"))
	MessageLog.post_blank()

func interrupt_rest() -> void:
	if not _rest_active:
		return
	_rest_active = false
	_rest_ticks_remaining = 0
	_rest_accumulator = 0.0
	MessageLog.post(MessageRegistry.get_message("rest_interrupted"))
	MessageLog.post_blank()

func _on_rest_hour_advanced() -> void:
	if _check_rest_interrupt():
		return

func _check_rest_interrupt() -> bool:
	var tile_type: String = GameManager.get_world_tile_type(GameManager.get_player_tile())
	var tile_mult: float = _rest_interrupt_tile_mults.get(tile_type, 1.0)
	var chance: float = _rest_interrupt_base_chance * tile_mult
	if randf() >= chance:
		return false
	interrupt_rest()
	MessageLog.post(MessageRegistry.get_message("rest_interrupted_combat"))
	MessageLog.post_blank()
	var group: Array = GameManager.spawn_manager.spawn_for_rest_interrupt()
	if not group.is_empty():
		CombatManager.initiate_combat_with_group(group, false)
	return true

func _load_tile_interrupt_mults() -> Dictionary:
	var mults: Dictionary = {}
	var data: Dictionary = Constants.load_json(Constants.TILES_CONFIG_PATH)
	for tile_def in data.get("tiles", []):
		var id: String = str(tile_def.get("id", ""))
		if not id.is_empty():
			mults[id] = float(tile_def.get("rest_interrupt_multiplier", 1.0))
	return mults
