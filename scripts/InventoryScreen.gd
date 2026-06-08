extends CanvasLayer

signal object_drop_requested(instance_id: int)
signal inventory_closed

const CURSOR_COLOR: Color = Color(1.0, 0.75, 0.0)
const EQUIP_INDICATOR_COLOR: Color = Color(0.4, 0.9, 0.4)
const INDENT: String = "  "
const ROW_HEIGHT: int = 20
const NORMAL_INSTRUCTIONS: String = "L: look    D: drop    U: use    M: move    E: equip    arrows: navigate"
const MOVE_INSTRUCTIONS: String = "Select destination -- Escape to cancel"

@onready var panel: Panel = $Panel
@onready var _scroll: ScrollContainer = $Panel/VBoxContainer/ScrollContainer
@onready var item_list: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/ItemList
@onready var _weight_label: Label = $Panel/VBoxContainer/WeightLabel
@onready var instruction_label: Label = $Panel/VBoxContainer/InstructionLabel

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

func _ready() -> void:
	panel.hide()

func open(cursor_instance: int = -1) -> void:
	_objects = PlayerInventory.get_objects()
	_build_rows()
	_cursor = 0
	if cursor_instance != -1:
		for i in range(_rows.size()):
			if _rows[i]["obj"]["instance_id"] == cursor_instance:
				_cursor = i
				break
	_scroll.scroll_vertical = 0
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
	instruction_label.text = NORMAL_INSTRUCTIONS
	inventory_closed.emit()
	panel.hide()

func _build_rows() -> void:
	_rows = []
	_build_rows_from(_objects, 0, -1)

func _build_rows_from(objects: Array, depth: int, parent_id: int) -> void:
	for obj in objects:
		_rows.append({"obj": obj, "depth": depth, "parent_id": parent_id})
		var iid: int = obj["instance_id"]
		if obj["data"].get("container", false) and _expanded.has(iid):
			_build_rows_from(obj.get("contents", []), depth + 1, iid)

func _build_dest_rows() -> void:
	_dest_rows = [{"is_top_level": true}]
	_collect_containers(_objects, 0)

func _collect_containers(objects: Array, depth: int) -> void:
	for obj in objects:
		if not obj["data"].get("container", false):
			continue
		if obj["instance_id"] == _moving_instance_id:
			continue
		_dest_rows.append({"obj": obj, "depth": depth})
		_collect_containers(obj.get("contents", []), depth + 1)

func _make_row(text: String, is_equipped: bool = false, stack_count: int = 1) -> HBoxContainer:
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

	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(16, 16)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(icon)

	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_clear_labels()
	for row in _rows:
		item_list.add_child(_make_row(_format_row(row), row["obj"].get("equipped", false), row["obj"].get("stack_count", 1)))
	_refresh_cursor()
	_scroll_to_cursor()

func _refresh_display_move() -> void:
	_clear_labels()
	for row in _dest_rows:
		var text: String
		if row.get("is_top_level", false):
			text = "[ Player inventory (top level) ]"
		else:
			text = INDENT.repeat(row["depth"]) + row["obj"]["data"]["name"]
		item_list.add_child(_make_row(text))
	_refresh_cursor_move()

func _format_row(row: Dictionary) -> String:
	var obj: Dictionary = row["obj"]
	var depth: int = row["depth"]
	var indent: String = INDENT.repeat(depth)
	if obj["data"].get("container", false):
		var indicator: String = "- " if _expanded.has(obj["instance_id"]) else "+ "
		return indent + indicator + obj["data"]["name"]
	return indent + obj["data"]["name"]

func _clear_labels() -> void:
	for child in item_list.get_children():
		child.free()

func _refresh_cursor() -> void:
	var children := item_list.get_children()
	for i in range(children.size()):
		var rtl: RichTextLabel = children[i].get_child(2)
		if i == _cursor:
			rtl.add_theme_color_override("default_color", CURSOR_COLOR)
		else:
			rtl.remove_theme_color_override("default_color")

func _refresh_cursor_move() -> void:
	var children := item_list.get_children()
	for i in range(children.size()):
		var rtl: RichTextLabel = children[i].get_child(2)
		if i == _dest_cursor:
			rtl.add_theme_color_override("default_color", CURSOR_COLOR)
		else:
			rtl.remove_theme_color_override("default_color")

func _refresh_weight() -> void:
	var current: float = PlayerInventory.get_total_weight()
	var limit: float = float(PlayerStats.get_effective_value("carry_limit"))
	_weight_label.text = "%.1f / %.1f kg" % [current, limit]

func _scroll_to_cursor() -> void:
	_do_scroll_to_cursor.call_deferred()

func _do_scroll_to_cursor() -> void:
	if _rows.is_empty() or not panel.visible:
		return
	var children := item_list.get_children()
	if _cursor >= children.size():
		return
	var row := children[_cursor] as Control
	var row_top: float = row.position.y
	var row_bottom: float = row_top + row.size.y
	var visible_height: float = _scroll.size.y
	if visible_height <= 0.0:
		return
	var scroll_top: float = float(_scroll.scroll_vertical)
	if row_top < scroll_top:
		_scroll.scroll_vertical = int(row_top)
	elif row_bottom > scroll_top + visible_height:
		_scroll.scroll_vertical = int(row_bottom - visible_height)

func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible:
		return
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
	elif event.is_action_pressed("ui_right"):
		_expand_selected()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_collapse_or_parent()
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
	_cursor = clamp(_cursor + delta, 0, _rows.size() - 1)
	_refresh_cursor()
	_scroll_to_cursor()

func _navigate_dest(delta: int) -> void:
	if _dest_rows.is_empty():
		return
	_dest_cursor = clamp(_dest_cursor + delta, 0, _dest_rows.size() - 1)
	_refresh_cursor_move()

func _expand_selected() -> void:
	if _rows.is_empty():
		return
	var obj: Dictionary = _rows[_cursor]["obj"]
	if not obj["data"].get("container", false):
		return
	var iid: int = obj["instance_id"]
	if _expanded.has(iid):
		return
	_expanded[iid] = true
	_rebuild_keep_cursor(iid)

func _collapse_or_parent() -> void:
	if _rows.is_empty():
		return
	var row: Dictionary = _rows[_cursor]
	var obj: Dictionary = row["obj"]
	var iid: int = obj["instance_id"]
	if obj["data"].get("container", false) and _expanded.has(iid):
		_expanded.erase(iid)
		_rebuild_keep_cursor(iid)
	elif row["parent_id"] != -1:
		var pid: int = row["parent_id"]
		for i in range(_rows.size()):
			if _rows[i]["obj"]["instance_id"] == pid:
				_cursor = i
				break
		_refresh_cursor()
		_scroll_to_cursor()

func _rebuild_keep_cursor(anchor_id: int) -> void:
	_objects = PlayerInventory.get_objects()
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
		MessageLog.post("You cannot use that.")
		return
	var ctx := UseContext.new()
	var player: Node = null
	if GameManager.current_region != null:
		player = GameManager.current_region.get_node_or_null("Actors/Player")
	ctx.actor = player
	ctx.target = obj
	ctx.inventory = PlayerInventory
	GameManager._execute_use(ctx)
	var anchor_id: int = obj.get("instance_id", -1)
	_rebuild_keep_cursor(anchor_id)

func _on_move_selected() -> void:
	if _rows.is_empty():
		return
	_enter_move_mode()

func _enter_move_mode() -> void:
	_moving_instance_id = _rows[_cursor]["obj"]["instance_id"]
	_in_move_mode = true
	_objects = PlayerInventory.get_objects()
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
			MessageLog.post("You are carrying too much.")
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
		MessageLog.post("The container is full.")
		_exit_move_mode_cancel()
		return
	_exit_move_mode()

func _update_quantity_label() -> void:
	instruction_label.text = "How many? " + _quantity_buffer + "_  (max " + str(_quantity_max) + ")  Esc to cancel"

func _confirm_quantity_move() -> void:
	var qty: int = int(_quantity_buffer) if not _quantity_buffer.is_empty() else 0
	if qty == 0:
		_exit_move_mode_cancel()
		return
	if qty > _quantity_max:
		MessageLog.post("There aren't that many.")
		_quantity_buffer = ""
		return
	if not PlayerInventory.move_stack_to_container(_moving_instance_id, _pending_dest_id, qty):
		MessageLog.post("The container is full.")
		_exit_move_mode_cancel()
		return
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
	_objects = PlayerInventory.get_objects()
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

func _on_equip_selected() -> void:
	if _rows.is_empty():
		return
	var obj: Dictionary = _rows[_cursor]["obj"]
	if not obj["data"].get("equippable", false):
		return
	var instance_id: int = obj["instance_id"]
	if obj.get("equipped", false):
		PlayerInventory.unequip_item(instance_id)
		_objects = PlayerInventory.get_objects()
		_build_rows()
		_cursor = clamp(_cursor, 0, max(_rows.size() - 1, 0))
		_refresh_display()
		return
	if not PlayerInventory.equip_item(instance_id):
		var slots: Array = obj["data"].get("equip_slots", [])
		MessageLog.post("Your " + _natural_slot_list(slots) + (" slots are" if slots.size() > 1 else " slot is") + " already occupied.")
	else:
		_objects = PlayerInventory.get_objects()
		_build_rows()
		_cursor = clamp(_cursor, 0, max(_rows.size() - 1, 0))
		_refresh_display()

func _natural_slot_list(slot_ids: Array) -> String:
	var names: Array = []
	for slot_id in slot_ids:
		var slot_def := GameManager.slot_registry.get_slot(str(slot_id)) if GameManager.slot_registry != null else {}
		names.append(slot_def.get("display_name", str(slot_id)))
	return Constants.natural_list(names)
