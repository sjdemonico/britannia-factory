class_name SaveLoadPanel
extends CanvasLayer

enum Mode { BROWSING, ACTION_MENU, NAME_INPUT, CONFIRMING }

const _COLOR_NORMAL   := Color(0.75, 0.75, 0.75, 1.0)
const _COLOR_SELECTED := Color(1.0,  1.0,  0.4,  1.0)
const _COLOR_DIM      := Color(0.5,  0.5,  0.5,  1.0)
const _COLOR_HEADER   := Color(0.55, 0.55, 0.55, 1.0)

@onready var panel:      Panel          = $Panel
@onready var slot_list:  VBoxContainer  = $Panel/VBox/Scroll/SlotList
@onready var scroll:     ScrollContainer = $Panel/VBox/Scroll

var _slots: Array = []       # [{blank:true}] or save Dictionaries
var _cursor: int = 0
var _mode: Mode = Mode.BROWSING
var _action_cursor: int = 0
var _actions: Array = []     # strings
var _confirm_action: String = ""
var _name_input_purpose: String = ""  # "save_here", "overwrite", "rename"
var _cursor_row: Control = null   # reference for scroll-to

func _ready() -> void:
	panel.hide()

func toggle() -> void:
	if panel.visible:
		close()
	else:
		open()

func open() -> void:
	_mode = Mode.BROWSING
	_action_cursor = 0
	_refresh_slots()
	_rebuild_list()
	panel.show()

func close() -> void:
	panel.hide()
	_mode = Mode.BROWSING

# ── Slot data ──────────────────────────────────────────────────────────────────

func _refresh_slots() -> void:
	_slots.clear()
	_slots.append({"blank": true})
	var saves: Array = SaveManager.get_save_index()
	var manual: Array = []
	var autosaves: Array = []
	for s in saves:
		if s is Dictionary:
			if bool(s.get("autosave", false)):
				autosaves.append(s)
			else:
				manual.append(s)
	manual.sort_custom(func(a, b): return int(a.get("slot_id", 0)) > int(b.get("slot_id", 0)))
	autosaves.sort_custom(func(a, b): return int(a.get("slot_id", 0)) > int(b.get("slot_id", 0)))
	for s in manual:
		_slots.append(s)
	for s in autosaves:
		_slots.append(s)
	_cursor = clampi(_cursor, 0, _slots.size() - 1)

func _get_autosave_display_number(slot_id: int) -> int:
	var autosaves: Array = []
	for s in _slots:
		if s is Dictionary and bool(s.get("autosave", false)):
			autosaves.append(int(s.get("slot_id", 0)))
	autosaves.sort()
	return autosaves.find(slot_id) + 1

# ── List rendering ─────────────────────────────────────────────────────────────

func _rebuild_list() -> void:
	for child in slot_list.get_children():
		child.queue_free()
	_cursor_row = null

	_add_header_row()

	for i in range(_slots.size()):
		var slot: Dictionary = _slots[i]
		var is_selected: bool = (i == _cursor)
		var row := _make_slot_row(slot, i, is_selected)
		slot_list.add_child(row)
		if is_selected:
			_cursor_row = row

		if is_selected and _mode == Mode.ACTION_MENU:
			_add_action_menu()
		elif is_selected and _mode == Mode.NAME_INPUT:
			_add_name_input_row()

	if _cursor_row != null:
		await get_tree().process_frame
		if is_instance_valid(scroll) and is_instance_valid(_cursor_row):
			scroll.ensure_control_visible(_cursor_row)

func _add_header_row() -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	_add_col(hbox, "Slot",      60,  _COLOR_HEADER, false)
	_add_col(hbox, "Name",      0,   _COLOR_HEADER, true)
	_add_col(hbox, "Timestamp", 160, _COLOR_HEADER, false)
	_add_col(hbox, "Status",    130, _COLOR_HEADER, false)
	_add_right_pad(hbox)
	slot_list.add_child(hbox)

func _make_slot_row(slot: Dictionary, _idx: int, selected: bool) -> HBoxContainer:
	var is_blank: bool = slot.get("blank", false)
	var is_auto: bool = not is_blank and bool(slot.get("autosave", false))
	var color: Color = _COLOR_SELECTED if selected else _COLOR_NORMAL

	var slot_text: String
	var name_text: String
	var time_text: String
	var status_text: String

	if is_blank:
		slot_text = "--"
		name_text = "[NEW SAVE]"
		time_text = ""
		status_text = ""
	else:
		slot_text = str(slot.get("slot_id", "?"))
		name_text = str(slot.get("player_name", "Unknown"))
		time_text = str(slot.get("timestamp", ""))
		if is_auto:
			var n: int = _get_autosave_display_number(int(slot.get("slot_id", 0)))
			status_text = "Autosave #" + str(n)
		else:
			status_text = ""

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	_add_col(hbox, slot_text,   60,  color, false)
	_add_col(hbox, name_text,   0,   color, true)
	_add_col(hbox, time_text,   160, color if not is_auto else _COLOR_DIM, false)
	_add_col(hbox, status_text, 130, _COLOR_DIM if is_auto else color, false)
	_add_right_pad(hbox)
	return hbox

func _add_col(parent: HBoxContainer, text: String, min_width: int, color: Color, expand: bool) -> void:
	var lbl := Label.new()
	lbl.text = "  " + text
	lbl.add_theme_color_override("font_color", color)
	lbl.clip_text = true
	if expand:
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		lbl.custom_minimum_size = Vector2(min_width, 0)
	parent.add_child(lbl)

func _add_right_pad(parent: HBoxContainer) -> void:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(12, 0)
	parent.add_child(pad)

func _add_action_menu() -> void:
	for ai in range(_actions.size()):
		var lbl := Label.new()
		lbl.text = "    > " + _actions[ai]
		var col: Color = _COLOR_SELECTED if ai == _action_cursor else _COLOR_NORMAL
		lbl.add_theme_color_override("font_color", col)
		slot_list.add_child(lbl)

func _add_name_input_row() -> void:
	var le := LineEdit.new()
	le.name = "NameInput"
	le.placeholder_text = "Enter save name..."
	le.max_length = 40
	le.focus_mode = Control.FOCUS_ALL
	le.text_submitted.connect(_on_name_submitted)
	slot_list.add_child(le)
	le.grab_focus()

# ── Actions ────────────────────────────────────────────────────────────────────

func _get_actions_for(slot: Dictionary) -> Array:
	if slot.get("blank", false):
		return ["Save Here"]
	if bool(slot.get("autosave", false)):
		return ["Load"]
	return ["Save Here", "Load", "Rename", "Delete"]

func _open_action_menu() -> void:
	var slot: Dictionary = _slots[_cursor]
	_actions = _get_actions_for(slot)
	_action_cursor = 0
	_mode = Mode.ACTION_MENU
	_rebuild_list()

func _execute_action(action: String) -> void:
	var slot: Dictionary = _slots[_cursor]
	match action:
		"Save Here":
			if slot.get("blank", false):
				_name_input_purpose = "save_here"
			else:
				_name_input_purpose = "overwrite"
			_mode = Mode.NAME_INPUT
			_rebuild_list()
		"Load":
			_confirm_action = "load"
			_mode = Mode.CONFIRMING
			var slot_id: int = int(slot.get("slot_id", 0))
			MessageLog.post("Load save slot " + str(slot_id) + "? Y / N")
		"Rename":
			_name_input_purpose = "rename"
			_mode = Mode.NAME_INPUT
			_rebuild_list()
		"Delete":
			_confirm_action = "delete"
			_mode = Mode.CONFIRMING
			var slot_id: int = int(slot.get("slot_id", 0))
			MessageLog.post("Delete save slot " + str(slot_id) + "? Y / N")

func _execute_confirmed() -> void:
	var slot: Dictionary = _slots[_cursor]
	match _confirm_action:
		"save_here":
			var new_slot_id: int = SaveManager.get_next_slot_id()
			var player_name: String = str(slot.get("_pending_name", PlayerStats.display_name))
			SaveManager.save(new_slot_id, player_name)
			MessageLog.post("Game saved.")
			close()
		"overwrite":
			var slot_id: int = int(slot.get("slot_id", 0))
			var player_name: String = str(slot.get("_pending_name", slot.get("player_name", PlayerStats.display_name)))
			SaveManager.save(slot_id, player_name)
			MessageLog.post("Game saved.")
			close()
		"load":
			var slot_id: int = int(slot.get("slot_id", 0))
			SaveManager.load_save(slot_id)
			close()
		"delete":
			var slot_id: int = int(slot.get("slot_id", 0))
			SaveManager.delete_save(slot_id)
			_refresh_slots()
			_mode = Mode.BROWSING
			_rebuild_list()

func _cancel_action() -> void:
	_mode = Mode.BROWSING
	_rebuild_list()

# ── Name submission ────────────────────────────────────────────────────────────

func _on_name_submitted(text: String) -> void:
	var save_name: String = text.strip_edges()
	if save_name.is_empty():
		_cancel_action()
		return
	var slot: Dictionary = _slots[_cursor]
	match _name_input_purpose:
		"save_here":
			slot["_pending_name"] = save_name
			_confirm_action = "save_here"
			_execute_confirmed()
		"overwrite":
			slot["_pending_name"] = save_name
			_confirm_action = "overwrite"
			_mode = Mode.CONFIRMING
			_rebuild_list()
			MessageLog.post("Overwrite save slot " + str(slot.get("slot_id", "?")) + "? Y / N")
		"rename":
			SaveManager.rename_save(int(slot.get("slot_id", 0)), save_name)
			_refresh_slots()
			_mode = Mode.BROWSING
			_rebuild_list()

# ── Input ──────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not panel.visible:
		return
	if _mode == Mode.NAME_INPUT:
		if event.is_action_pressed("ui_cancel"):
			_cancel_action()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible:
		return

	if _mode == Mode.NAME_INPUT:
		return

	if _mode == Mode.CONFIRMING:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == 89:  # Y
				_execute_confirmed()
			elif event.physical_keycode == 78:  # N
				MessageLog.post("Cancelled.")
				_cancel_action()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel"):
		if _mode == Mode.ACTION_MENU:
			_cancel_action()
		else:
			close()
		get_viewport().set_input_as_handled()
		return

	if _mode == Mode.ACTION_MENU:
		if event.is_action_pressed("ui_up"):
			_action_cursor = maxi(0, _action_cursor - 1)
			_rebuild_list()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_down"):
			_action_cursor = mini(_actions.size() - 1, _action_cursor + 1)
			_rebuild_list()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept"):
			_execute_action(_actions[_action_cursor])
			get_viewport().set_input_as_handled()
		return

	# BROWSING
	if event.is_action_pressed("ui_up"):
		_cursor = maxi(0, _cursor - 1)
		_rebuild_list()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_cursor = mini(_slots.size() - 1, _cursor + 1)
		_rebuild_list()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_open_action_menu()
		get_viewport().set_input_as_handled()
