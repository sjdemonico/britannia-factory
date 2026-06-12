class_name LoadGameScene
extends Control

enum Mode { BROWSING, ACTION_MENU, NAME_INPUT }

const _COLOR_NORMAL   := Color(0.75, 0.75, 0.75, 1.0)
const _COLOR_SELECTED := Color(1.0,  1.0,  0.4,  1.0)
const _COLOR_DIM      := Color(0.5,  0.5,  0.5,  1.0)
const _COLOR_HEADER   := Color(0.55, 0.55, 0.55, 1.0)

@onready var saves_scroll: ScrollContainer = $Layout/SavesScroll
@onready var saves_list:   VBoxContainer   = $Layout/SavesScroll/SavesList
@onready var empty_label:  Label           = $Layout/EmptyLabel

var _saves: Array = []
var _cursor: int = 0
var _mode: Mode = Mode.BROWSING
var _action_cursor: int = 0
var _actions: Array = []

func _ready() -> void:
	_load_saves()
	_rebuild_list()

func _load_saves() -> void:
	_saves.clear()
	var raw: Array = SaveManager.get_save_index()
	for s in raw:
		if s is Dictionary:
			_saves.append(s)
	_saves.sort_custom(func(a, b): return int(a.get("slot_id", 0)) > int(b.get("slot_id", 0)))

func _get_autosave_display_number(slot_id: int) -> int:
	var autosaves: Array = []
	for s in _saves:
		if bool(s.get("autosave", false)):
			autosaves.append(int(s.get("slot_id", 0)))
	autosaves.sort()
	return autosaves.find(slot_id) + 1

func _rebuild_list() -> void:
	for child in saves_list.get_children():
		child.free()

	if _saves.is_empty():
		saves_scroll.hide()
		empty_label.show()
		return

	saves_scroll.show()
	empty_label.hide()
	_cursor = clampi(_cursor, 0, _saves.size() - 1)

	_add_header_row()

	for i in range(_saves.size()):
		var save: Dictionary = _saves[i] if _saves[i] is Dictionary else {}
		var is_auto: bool = bool(save.get("autosave", false))
		var selected: bool = (i == _cursor)
		var color: Color = _COLOR_SELECTED if selected else _COLOR_NORMAL

		var slot_text: String = str(save.get("slot_id", "?"))
		var name_text: String = str(save.get("player_name", "Unknown"))
		var time_text: String = str(save.get("timestamp", ""))
		var status_text: String = ""
		if is_auto:
			var n: int = _get_autosave_display_number(int(save.get("slot_id", 0)))
			status_text = "Autosave #" + str(n)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 0)
		_add_col(hbox, slot_text,   60,  color, false)
		_add_col(hbox, name_text,   0,   color, true)
		_add_col(hbox, time_text,   160, color if not is_auto else _COLOR_DIM, false)
		_add_col(hbox, status_text, 130, _COLOR_DIM if is_auto else color, false)
		_add_right_pad(hbox)
		saves_list.add_child(hbox)

		if selected and _mode == Mode.ACTION_MENU:
			for ai in range(_actions.size()):
				var lbl := Label.new()
				lbl.text = "    > " + _actions[ai]
				lbl.add_theme_color_override("font_color",
					_COLOR_SELECTED if ai == _action_cursor else _COLOR_NORMAL)
				saves_list.add_child(lbl)
		elif selected and _mode == Mode.NAME_INPUT:
			var le := LineEdit.new()
			le.name = "NameInput"
			le.placeholder_text = "Enter new name..."
			le.max_length = 40
			le.focus_mode = Control.FOCUS_ALL
			le.text_submitted.connect(_on_name_submitted)
			saves_list.add_child(le)
			le.grab_focus()

func _add_header_row() -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	_add_col(hbox, "Slot",      60,  _COLOR_HEADER, false)
	_add_col(hbox, "Name",      0,   _COLOR_HEADER, true)
	_add_col(hbox, "Timestamp", 160, _COLOR_HEADER, false)
	_add_col(hbox, "Status",    130, _COLOR_HEADER, false)
	_add_right_pad(hbox)
	saves_list.add_child(hbox)

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

func _get_actions_for(save: Dictionary) -> Array:
	if bool(save.get("autosave", false)):
		return ["Load"]
	return ["Load", "Rename", "Delete"]

func _on_name_submitted(text: String) -> void:
	var save_name: String = text.strip_edges()
	if not save_name.is_empty():
		var save: Dictionary = _saves[_cursor] if _saves[_cursor] is Dictionary else {}
		SaveManager.rename_save(int(save.get("slot_id", 0)), save_name)
		_load_saves()
	_mode = Mode.BROWSING
	_rebuild_list()

func _input(event: InputEvent) -> void:
	if _mode == Mode.NAME_INPUT:
		if event.is_action_pressed("ui_cancel"):
			_mode = Mode.BROWSING
			_rebuild_list()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if _mode == Mode.NAME_INPUT:
		return

	if event.is_action_pressed("ui_cancel"):
		if _mode == Mode.ACTION_MENU:
			_mode = Mode.BROWSING
			_rebuild_list()
			get_viewport().set_input_as_handled()
		else:
			get_viewport().set_input_as_handled()
			get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
		return

	if _saves.is_empty():
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
			get_viewport().set_input_as_handled()
			_execute_action(_actions[_action_cursor])
		return

	# BROWSING
	if event.is_action_pressed("ui_up"):
		_cursor = maxi(0, _cursor - 1)
		_rebuild_list()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_cursor = mini(_saves.size() - 1, _cursor + 1)
		_rebuild_list()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if not _saves.is_empty():
			var save: Dictionary = _saves[_cursor] if _saves[_cursor] is Dictionary else {}
			_actions = _get_actions_for(save)
			_action_cursor = 0
			_mode = Mode.ACTION_MENU
			_rebuild_list()
		get_viewport().set_input_as_handled()

func _execute_action(action: String) -> void:
	var save: Dictionary = _saves[_cursor] if _saves[_cursor] is Dictionary else {}
	match action:
		"Load":
			SaveManager.load_save(int(save.get("slot_id", 0)))
		"Rename":
			_mode = Mode.NAME_INPUT
			_rebuild_list()
		"Delete":
			SaveManager.delete_save(int(save.get("slot_id", 0)))
			_load_saves()
			_mode = Mode.BROWSING
			_rebuild_list()
