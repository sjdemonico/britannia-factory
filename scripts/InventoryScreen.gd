class_name InventoryScreen
extends CanvasLayer

signal object_drop_requested(instance_id: int)
signal inventory_closed

const CURSOR_COLOR: Color = Color(1.0, 0.75, 0.0)
const EQUIP_INDICATOR_COLOR: Color = Color(0.4, 0.9, 0.4)
const INDENT: String = "  "
const INDENT_WIDTH: int = 16
const ROW_HEIGHT: int = 20
const NORMAL_INSTRUCTIONS: String = "L: look    D: drop    U: use    M: move    E: equip    arrows: navigate    Left/Right: switch member"
const MOVE_INSTRUCTIONS: String = "Select destination -- Escape to cancel"

@onready var panel: Panel = $Panel
@onready var _scroll: ScrollContainer = $Panel/VBoxContainer/ScrollContainer
@onready var item_list: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/ItemList
@onready var _weight_label: Label = $Panel/VBoxContainer/WeightLabel
@onready var instruction_label: Label = $Panel/VBoxContainer/InstructionLabel
@onready var _title_label: Label = $Panel/VBoxContainer/TitleLabel

var _cursor: int = 0
var _objects: Array = []
var _rows: Array = []      # flat visible rows: {obj, depth, parent_id}
var _expanded: Dictionary = {}  # instance_id -> true

var _in_move_mode: bool = false
var _moving_instance_id: int = -1
var _dest_rows: Array = []  # destination rows for move mode: [{is_top_level:true}] or [{obj, depth}]
var _dest_cursor: int = 0

var _in_quantity_mode: bool = false
var _quantity_buffer: String = ""
var _quantity_max: int = -1
var _pending_dest_id: int = -1

# Cross-member move state
var _current_member_index: int = 0
var _source_member_index: int = 0
var _in_member_move_mode: bool = false
var _in_cross_qty_mode: bool = false
var _cross_qty_buffer: String = ""
var _cross_qty_max: int = 1
var _cross_qty: int = 1

var _ui_initialized: bool = false

func _ready() -> void:
	panel.hide()
	_ui_initialized = true

func open(cursor_instance: int = -1) -> void:
	_current_member_index = 0
	_objects = _get_current_inv().get_objects()
	_build_rows()
	_cursor = 0
	if cursor_instance != -1:
		for i in range(_rows.size()):
			if _rows[i]["obj"]["instance_id"] == cursor_instance:
				_cursor = i
				break
	_scroll.scroll_vertical = 0
	_refresh_title()
	_refresh_display()
	_refresh_weight()
	panel.show()

func close() -> void:
	_clear_labels()
	_objects = []
	_rows = []
	_in_move_mode = false
	_in_quantity_mode = false
	_quantity_buffer = ""
	_quantity_max = -1
	_pending_dest_id = -1
	_moving_instance_id = -1
	_dest_rows = []
	_dest_cursor = 0
	_current_member_index = 0
	_source_member_index = 0
	_in_member_move_mode = false
	_in_cross_qty_mode = false
	_cross_qty_buffer = ""
	_cross_qty_max = 1
	_cross_qty = 1
	instruction_label.text = NORMAL_INSTRUCTIONS
	inventory_closed.emit()
	panel.hide()

func toggle() -> void:
	if panel.visible:
		close()
	else:
		open()

func _get_current_inv() -> Inventory:
	var m := PartyManager.get_member_at(_current_member_index)
	if m == null:
		return PartyManager.get_player().inventory
	return m.inventory

func _refresh_title() -> void:
	var m := PartyManager.get_member_at(_current_member_index)
	if m == null or _title_label == null:
		return
	_title_label.text = m.display_name + "'s Inventory"

func _switch_member(delta: int) -> void:
	var size := PartyManager.get_party_size()
	if size <= 1:
		return
	_current_member_index = posmod(_current_member_index + delta, size)
	_objects = _get_current_inv().get_objects()
	_build_rows()
	_cursor = 0
	_refresh_title()
	_refresh_display()
	_refresh_weight()

func _switch_member_in_target(delta: int) -> void:
	var size := PartyManager.get_party_size()
	if size <= 2:
		return
	var next := posmod(_current_member_index + delta, size)
	var attempts := 0
	while next == _source_member_index and attempts < size:
		next = posmod(next + delta, size)
		attempts += 1
	_current_member_index = next
	_build_dest_rows()
	_dest_cursor = 0
	_refresh_title()
	_refresh_display_move()

func _build_rows() -> void:
	_rows = []
	_build_rows_from(_objects, 0, -1)

func _build_rows_from(objects: Array, depth: int, parent_id: int) -> void:
	for obj in objects:
		_rows.append({"obj": obj, "depth": depth, "parent_id": parent_id})
		var iid: int = obj["instance_id"]
		if obj["data"].get("type", "") == "container" and _expanded.has(iid):
			_build_rows_from(obj.get("contents", []), depth + 1, iid)

func _build_dest_rows() -> void:
	_dest_rows = [{"is_top_level": true}]
	_collect_containers(_get_current_inv().get_objects(), 0)

func _collect_containers(objects: Array, depth: int) -> void:
	for obj in objects:
		if obj["data"].get("type", "") != "container":
			continue
		if obj["instance_id"] == _moving_instance_id:
			continue
		_dest_rows.append({"obj": obj, "depth": depth})
		_collect_containers(obj.get("contents", []), depth + 1)

func _make_row(text: String, is_equipped: bool = false, stack_count: int = 1, depth: int = 0) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size.y = ROW_HEIGHT

	var equip_label := Label.new()
	equip_label.custom_minimum_size = Vector2(12, 0)
	equip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if is_equipped:
		equip_label.text = "E"
		equip_label.add_theme_color_override("font_color", EQUIP_INDICATOR_COLOR)
	else:
		equip_label.text = " "
	hbox.add_child(equip_label)

	if depth > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(depth * INDENT_WIDTH, 0)
		hbox.add_child(spacer)

	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(16, 16)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(icon)

	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_equipped:
		rtl.push_italics()
		rtl.add_text(text)
		rtl.pop()
	else:
		rtl.add_text(text)
	hbox.add_child(rtl)

	var count_label := Label.new()
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if stack_count > 1:
		count_label.text = str(stack_count)
	hbox.add_child(count_label)

	return hbox

func _refresh_display() -> void:
	if not _ui_initialized:
		return
	_clear_labels()
	for i in range(_rows.size()):
		var row: Dictionary = _rows[i]
		var hbox := _make_row(_format_row(row), row["obj"].get("equipped", false), row["obj"].get("stack_count", 1), row["depth"])
		var captured_i := i
		hbox.gui_input.connect(func(event): _on_normal_row_gui_input(event, captured_i))
		hbox.mouse_entered.connect(func(): _on_row_mouse_entered(row["obj"]))
		hbox.mouse_exited.connect(func(): TooltipManager.on_item_unhovered())
		item_list.add_child(hbox)
	_refresh_cursor()
	_scroll_to_cursor()

func _refresh_display_move() -> void:
	if not _ui_initialized:
		return
	_clear_labels()
	var m := PartyManager.get_member_at(_current_member_index)
	var member_name: String = m.display_name if m != null else "?"
	for i in range(_dest_rows.size()):
		var row: Dictionary = _dest_rows[i]
		var text: String
		if row.get("is_top_level", false):
			text = "[ " + member_name + "'s inventory (top level) ]"
		else:
			text = INDENT.repeat(row["depth"]) + Inventory.get_item_display_name(row["obj"]["data"])
		var hbox := _make_row(text)
		var captured_i := i
		hbox.gui_input.connect(func(event): _on_dest_row_gui_input(event, captured_i))
		item_list.add_child(hbox)
	_refresh_cursor_move()

func _format_row(row: Dictionary) -> String:
	var obj: Dictionary = row["obj"]
	if obj["data"].get("type", "") == "container":
		var indicator: String = "- " if _expanded.has(obj["instance_id"]) else "+ "
		return indicator + Inventory.get_item_display_name(obj["data"])
	return Inventory.get_item_display_name(obj["data"])

func _clear_labels() -> void:
	for child in item_list.get_children():
		child.free()

func _get_row_rtl(hbox: HBoxContainer) -> RichTextLabel:
	for child in hbox.get_children():
		if child is RichTextLabel:
			return child as RichTextLabel
	return null

func _refresh_cursor() -> void:
	var children := item_list.get_children()
	for i in range(children.size()):
		var rtl := _get_row_rtl(children[i])
		if rtl == null:
			continue
		if i == _cursor:
			rtl.add_theme_color_override("default_color", CURSOR_COLOR)
		else:
			rtl.remove_theme_color_override("default_color")

func _refresh_cursor_move() -> void:
	var children := item_list.get_children()
	for i in range(children.size()):
		var rtl := _get_row_rtl(children[i])
		if rtl == null:
			continue
		if i == _dest_cursor:
			rtl.add_theme_color_override("default_color", CURSOR_COLOR)
		else:
			rtl.remove_theme_color_override("default_color")

func _refresh_weight() -> void:
	if not _ui_initialized:
		return
	var m := PartyManager.get_member_at(_current_member_index)
	if m == null:
		return
	var current: float = m.inventory.get_total_weight()
	var limit: float = float(m.stat_block.get_effective_value("carry_limit"))
	_weight_label.text = "%.1f / %.1f kg" % [current, limit]

func _scroll_to_cursor() -> void:
	if not _ui_initialized:
		return
	_do_scroll_to_cursor.call_deferred()

func _do_scroll_to_cursor() -> void:
	if not _ui_initialized or _rows.is_empty() or not panel.visible:
		return
	Constants.scroll_list_to_row(_scroll, item_list, _cursor)

func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible:
		return

	# -- cross-member quantity prompt --
	if _in_cross_qty_mode:
		var key_event := event as InputEventKey
		if key_event != null and key_event.pressed and not key_event.echo:
			if key_event.is_action_pressed("ui_cancel"):
				_cancel_cross_member_move()
			elif key_event.keycode == KEY_BACKSPACE:
				if not _cross_qty_buffer.is_empty():
					_cross_qty_buffer = _cross_qty_buffer.left(_cross_qty_buffer.length() - 1)
				_update_cross_qty_label()
			elif key_event.is_action_pressed("ui_accept"):
				_confirm_cross_qty()
			elif key_event.unicode >= 48 and key_event.unicode <= 57:
				_cross_qty_buffer += char(key_event.unicode)
				_update_cross_qty_label()
		get_viewport().set_input_as_handled()
		return

	# -- cross-member target selection --
	if _in_member_move_mode:
		if event.is_action_pressed("ui_cancel"):
			_cancel_cross_member_move()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("move_up"):
			_navigate_dest(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("move_down"):
			_navigate_dest(1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("move_left"):
			_switch_member_in_target(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("move_right"):
			_switch_member_in_target(1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept"):
			_confirm_member_move()
			get_viewport().set_input_as_handled()
		return

	# -- within-inventory container move --
	if _in_move_mode:
		if _in_quantity_mode:
			var key_event := event as InputEventKey
			if key_event != null and key_event.pressed and not key_event.echo:
				if key_event.is_action_pressed("ui_cancel"):
					_exit_move_mode_cancel()
				elif key_event.keycode == KEY_BACKSPACE:
					if not _quantity_buffer.is_empty():
						_quantity_buffer = _quantity_buffer.left(_quantity_buffer.length() - 1)
					_update_quantity_label()
				elif key_event.is_action_pressed("ui_accept"):
					_confirm_quantity_move()
				elif key_event.unicode >= 48 and key_event.unicode <= 57:
					_quantity_buffer += char(key_event.unicode)
					_update_quantity_label()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_cancel"):
			_exit_move_mode_cancel()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("move_up"):
			_navigate_dest(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("move_down"):
			_navigate_dest(1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept"):
			_confirm_move()
			get_viewport().set_input_as_handled()
		return

	# -- normal mode --
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("move_up"):
		_navigate(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_navigate(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_left"):
		_switch_member(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		_switch_member(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("look"):
		_on_look()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drop"):
		_on_drop_selected()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("use"):
		_on_use()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move"):
		_on_move_selected()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("equip"):
		_on_equip_selected()
		get_viewport().set_input_as_handled()

func _navigate(delta: int) -> void:
	if _rows.is_empty():
		return
	_cursor = posmod(_cursor + delta, _rows.size())
	_refresh_cursor()
	_scroll_to_cursor()

func _navigate_dest(delta: int) -> void:
	if _dest_rows.is_empty():
		return
	_dest_cursor = posmod(_dest_cursor + delta, _dest_rows.size())
	_refresh_cursor_move()

func _rebuild_keep_cursor(anchor_id: int) -> void:
	_objects = _get_current_inv().get_objects()
	_build_rows()
	_cursor = 0
	for i in range(_rows.size()):
		if _rows[i]["obj"]["instance_id"] == anchor_id:
			_cursor = i
			break
	_cursor = clamp(_cursor, 0, max(_rows.size() - 1, 0))
	_refresh_display()

func _on_look() -> void:
	if _rows.is_empty():
		return
	var obj: Dictionary = _rows[_cursor]["obj"]
	var desc: String = obj["data"].get("description", "You see nothing special about it.")
	var charges: int = int(obj.get("charges", -1))
	if charges != -1:
		desc += " (" + str(charges) + " charge" + ("s" if charges != 1 else "") + " remaining)"
	MessageLog.post(desc)

func _on_drop_selected() -> void:
	if _rows.is_empty():
		return
	var instance_id: int = _rows[_cursor]["obj"]["instance_id"]
	object_drop_requested.emit(instance_id)

func _on_use() -> void:
	if _rows.is_empty():
		return
	var obj: Dictionary = _rows[_cursor]["obj"]
	var actions: Array = obj.get("data", {}).get("use_actions", [])
	if actions.is_empty():
		MessageLog.post(MessageRegistry.get_message("use_cannot_use"))
		return
	var ctx := UseContext.new()
	var player: Node = null
	if GameManager.current_region != null:
		player = GameManager.current_region.get_node_or_null("Actors/Player")
	ctx.actor = player
	ctx.target = obj
	ctx.inventory = PlayerInventory
	GameManager.execute_use(ctx)
	if not panel.visible:
		return
	var anchor_id: int = obj.get("instance_id", -1)
	_rebuild_keep_cursor(anchor_id)

func _on_move_selected() -> void:
	if _rows.is_empty():
		return
	if PartyManager.get_party_size() <= 1:
		_enter_move_mode()
	else:
		_enter_cross_member_move()

func _enter_move_mode() -> void:
	_moving_instance_id = _rows[_cursor]["obj"]["instance_id"]
	_in_move_mode = true
	_objects = _get_current_inv().get_objects()
	_build_dest_rows()
	_dest_cursor = 0
	_refresh_display_move()
	instruction_label.text = MOVE_INSTRUCTIONS

func _confirm_move() -> void:
	if _dest_rows.is_empty():
		return
	var dest_row: Dictionary = _dest_rows[_dest_cursor]
	if dest_row.get("is_top_level", false):
		if not PlayerInventory.move_to_top_level(_moving_instance_id):
			MessageLog.post(MessageRegistry.get_message("inventory_too_heavy"))
			_exit_move_mode_cancel()
			return
		_exit_move_mode()
		return
	var dest_id: int = dest_row["obj"]["instance_id"]
	var moving_obj := PlayerInventory.find_object_anywhere(_moving_instance_id)
	if moving_obj.is_empty():
		_exit_move_mode_cancel()
		return
	var stack: int = moving_obj.get("stack_count", 1)
	if stack > 1:
		_in_quantity_mode = true
		_pending_dest_id = dest_id
		_quantity_buffer = ""
		_quantity_max = stack
		_update_quantity_label()
		return
	if not PlayerInventory.move_to_container(_moving_instance_id, dest_id):
		MessageLog.post(MessageRegistry.get_message("inventory_container_full"))
		_exit_move_mode_cancel()
		return
	_expanded[dest_id] = true
	_exit_move_mode()

func _update_quantity_label() -> void:
	instruction_label.text = MessageRegistry.get_message("inventory_quantity_label", {"buffer": _quantity_buffer, "max": str(_quantity_max)})

func _confirm_quantity_move() -> void:
	var qty: int = int(_quantity_buffer) if not _quantity_buffer.is_empty() else 0
	if qty == 0:
		_exit_move_mode_cancel()
		return
	if qty > _quantity_max:
		MessageLog.post(MessageRegistry.get_message("quantity_too_many"))
		_quantity_buffer = ""
		return
	if not PlayerInventory.move_stack_to_container(_moving_instance_id, _pending_dest_id, qty):
		MessageLog.post(MessageRegistry.get_message("inventory_container_full"))
		_exit_move_mode_cancel()
		return
	_expanded[_pending_dest_id] = true
	_exit_move_mode()

func _exit_move_mode() -> void:
	var moved_id := _moving_instance_id
	_in_move_mode = false
	_in_quantity_mode = false
	_quantity_buffer = ""
	_quantity_max = -1
	_pending_dest_id = -1
	_moving_instance_id = -1
	_dest_rows = []
	_dest_cursor = 0
	_objects = _get_current_inv().get_objects()
	_build_rows()
	_cursor = 0
	for i in range(_rows.size()):
		if _rows[i]["obj"]["instance_id"] == moved_id:
			_cursor = i
			break
	_cursor = clamp(_cursor, 0, max(_rows.size() - 1, 0))
	_refresh_display()
	_refresh_weight()
	instruction_label.text = NORMAL_INSTRUCTIONS

func _exit_move_mode_cancel() -> void:
	_in_move_mode = false
	_in_quantity_mode = false
	_quantity_buffer = ""
	_quantity_max = -1
	_pending_dest_id = -1
	_moving_instance_id = -1
	_dest_rows = []
	_dest_cursor = 0
	_refresh_display()
	instruction_label.text = NORMAL_INSTRUCTIONS

# ── Cross-member move ────────────────────────────────────────────────────────

func _enter_cross_member_move() -> void:
	var obj: Dictionary = _rows[_cursor]["obj"]
	if obj.get("equipped", false):
		MessageLog.post(MessageRegistry.get_message("inventory_move_unequip_first"))
		return
	_moving_instance_id = obj["instance_id"]
	_source_member_index = _current_member_index
	var stack: int = obj.get("stack_count", 1)
	if stack > 1:
		_in_cross_qty_mode = true
		_cross_qty_buffer = ""
		_cross_qty_max = stack
		_cross_qty = stack
		_update_cross_qty_label()
	else:
		_cross_qty = 1
		_enter_target_mode()

func _update_cross_qty_label() -> void:
	if not _ui_initialized:
		return
	instruction_label.text = MessageRegistry.get_message("inventory_quantity_label", {"buffer": _cross_qty_buffer, "max": str(_cross_qty_max)})

func _confirm_cross_qty() -> void:
	var qty: int = int(_cross_qty_buffer) if not _cross_qty_buffer.is_empty() else 0
	if qty == 0:
		_cancel_cross_member_move()
		return
	if qty > _cross_qty_max:
		MessageLog.post(MessageRegistry.get_message("quantity_too_many"))
		_cross_qty_buffer = ""
		_update_cross_qty_label()
		return
	_cross_qty = qty
	_in_cross_qty_mode = false
	_enter_target_mode()

func _enter_target_mode() -> void:
	_in_member_move_mode = true
	var size := PartyManager.get_party_size()
	_current_member_index = posmod(_source_member_index + 1, size)
	var attempts := 0
	while _current_member_index == _source_member_index and attempts < size:
		_current_member_index = posmod(_current_member_index + 1, size)
		attempts += 1
	_build_dest_rows()
	_dest_cursor = 0
	_refresh_title()
	_refresh_display_move()
	if _ui_initialized:
		instruction_label.text = MessageRegistry.get_message("inventory_move_select_target")

func _confirm_member_move() -> void:
	if _dest_rows.is_empty():
		return
	var dest_row: Dictionary = _dest_rows[_dest_cursor]
	var source_m := PartyManager.get_member_at(_source_member_index)
	var target_m := PartyManager.get_member_at(_current_member_index)
	if source_m == null or target_m == null:
		_cancel_cross_member_move()
		return
	var source_inv: Inventory = source_m.inventory
	var target_inv: Inventory = target_m.inventory

	var moving_obj := source_inv.find_object_anywhere(_moving_instance_id)
	if moving_obj.is_empty():
		_cancel_cross_member_move()
		return

	var object_id: String = moving_obj["object_id"]
	var item_weight: float = moving_obj["data"].get("weight", 0.0)
	var total_weight: float = item_weight * _cross_qty

	var carry_limit: float = float(target_m.stat_block.get_effective_value("carry_limit"))
	if target_inv.get_total_weight() + total_weight > carry_limit:
		MessageLog.post(MessageRegistry.get_message("inventory_move_carry_limit"))
		_cancel_cross_member_move()
		return

	if dest_row.get("is_top_level", false):
		source_inv.take_from_stack(_moving_instance_id, _cross_qty)
		target_inv.add_stacked(object_id, _cross_qty)
	else:
		var dest_id: int = dest_row["obj"]["instance_id"]
		var container_obj := target_inv.find_object_anywhere(dest_id)
		if container_obj.is_empty():
			_cancel_cross_member_move()
			return

		# Check container weight limit for full transfer quantity
		var raw_wl = container_obj["data"].get("container_weight_limit")
		if raw_wl != null:
			var wl: float = float(raw_wl)
			var cur_w: float = 0.0
			for content in container_obj["contents"]:
				cur_w += content["data"].get("weight", 0.0) * content.get("stack_count", 1)
			if cur_w + total_weight > wl:
				MessageLog.post(MessageRegistry.get_message("inventory_container_full"))
				_cancel_cross_member_move()
				return

		# Find existing matching stack in container
		var existing_content: Dictionary = {}
		for content in container_obj["contents"]:
			if content["object_id"] == object_id and not content.get("equipped", false):
				existing_content = content
				break

		# If no existing stack, need a free slot
		if existing_content.is_empty():
			var raw_slots = container_obj["data"].get("container_slots", 0)
			var slot_limit: int = int(raw_slots) if raw_slots != null else -1
			if slot_limit != -1 and container_obj["contents"].size() >= slot_limit:
				MessageLog.post(MessageRegistry.get_message("inventory_container_full"))
				_cancel_cross_member_move()
				return

		# Execute transfer
		source_inv.take_from_stack(_moving_instance_id, _cross_qty)
		if not existing_content.is_empty():
			existing_content["stack_count"] = existing_content.get("stack_count", 1) + _cross_qty
		else:
			var new_id := target_inv.add_to_container(dest_id, object_id)
			if new_id != -1 and _cross_qty > 1:
				var new_obj := target_inv.find_object_anywhere(new_id)
				if not new_obj.is_empty():
					new_obj["stack_count"] = _cross_qty
		_expanded[dest_id] = true

	var item_name: String = Inventory.get_item_display_name(moving_obj["data"])
	MessageLog.post(MessageRegistry.get_message("inventory_move_complete", {"name": item_name, "target": target_m.display_name}))
	_exit_cross_member_move()

func _exit_cross_member_move() -> void:
	_in_member_move_mode = false
	_in_cross_qty_mode = false
	_cross_qty_buffer = ""
	_cross_qty_max = 1
	_cross_qty = 1
	_moving_instance_id = -1
	_dest_rows = []
	_dest_cursor = 0
	_objects = _get_current_inv().get_objects()
	_build_rows()
	_cursor = 0
	_refresh_title()
	_refresh_display()
	_refresh_weight()
	if _ui_initialized:
		instruction_label.text = NORMAL_INSTRUCTIONS

func _cancel_cross_member_move() -> void:
	_current_member_index = _source_member_index
	_in_member_move_mode = false
	_in_cross_qty_mode = false
	_cross_qty_buffer = ""
	_cross_qty_max = 1
	_cross_qty = 1
	_moving_instance_id = -1
	_dest_rows = []
	_dest_cursor = 0
	_objects = _get_current_inv().get_objects()
	_build_rows()
	_cursor = clamp(_cursor, 0, max(_rows.size() - 1, 0))
	_refresh_title()
	_refresh_display()
	_refresh_weight()
	if _ui_initialized:
		instruction_label.text = NORMAL_INSTRUCTIONS

# ── Equip ────────────────────────────────────────────────────────────────────

func _on_equip_selected() -> void:
	if _rows.is_empty():
		return
	var obj: Dictionary = _rows[_cursor]["obj"]
	if not obj["data"].get("equippable", false):
		return
	var instance_id: int = obj["instance_id"]
	if obj.get("equipped", false):
		PlayerInventory.unequip_item(instance_id)
		_objects = _get_current_inv().get_objects()
		_build_rows()
		_cursor = clamp(_cursor, 0, max(_rows.size() - 1, 0))
		_refresh_display()
		return
	if not PlayerInventory.equip_item(instance_id):
		var slots: Array = obj["data"].get("equip_slots", [])
		if slots.size() > 1:
			MessageLog.post(MessageRegistry.get_message("equip_slots_occupied_plural", {"slots": _natural_slot_list(slots)}))
		else:
			MessageLog.post(MessageRegistry.get_message("equip_slot_occupied_single", {"slot": _natural_slot_list(slots)}))
	else:
		_objects = _get_current_inv().get_objects()
		_build_rows()
		_cursor = clamp(_cursor, 0, max(_rows.size() - 1, 0))
		_refresh_display()

func _natural_slot_list(slot_ids: Array) -> String:
	var names: Array = []
	for slot_id in slot_ids:
		var slot_def := GameManager.slot_registry.get_slot(str(slot_id)) if GameManager.slot_registry != null else {}
		names.append(slot_def.get("display_name", str(slot_id)))
	return Constants.natural_list(names)

# ── Mouse support ─────────────────────────────────────────────────────────────

func _on_normal_row_gui_input(event: InputEvent, row_index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	if _in_cross_qty_mode:
		return
	if _cursor == row_index:
		call_deferred("_on_use")
	else:
		_cursor = row_index
		_refresh_cursor()
		_scroll_to_cursor()

func _on_dest_row_gui_input(event: InputEvent, row_index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	if _in_quantity_mode or _in_cross_qty_mode:
		return
	if _dest_cursor == row_index:
		_confirm_move()
	else:
		_dest_cursor = row_index
		_refresh_cursor_move()

func _on_row_mouse_entered(obj: Dictionary) -> void:
	TooltipManager.on_item_hovered(_build_tooltip_content(obj))

func _build_tooltip_content(obj: Dictionary) -> Dictionary:
	var data: Dictionary = obj.get("data", {})
	var charges = obj.get("charges", null)
	if charges != null and int(charges) < 0:
		charges = null
	return {
		"name": Inventory.get_item_display_name(data),
		"description": data.get("description", ""),
		"charges": charges,
		"equipment_type": data.get("equip_type", null),
		"base_damage": data.get("base_damage", null),
		"base_armor": data.get("base_armor", null),
	}
