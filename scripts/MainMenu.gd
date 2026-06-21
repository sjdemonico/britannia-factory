class_name MainMenu
extends Control

enum _Step { MAIN_MENU, NAME_INPUT, CLASS_SELECT, STAT_ALLOC }
enum _Option { NEW_GAME = 0, LOAD_GAME = 1, QUIT = 2 }
const _OPTION_COUNT: int = 3

const _COLOR_NORMAL   := Color(0.75, 0.75, 0.75, 1.0)
const _COLOR_SELECTED := Color(1.0,  1.0,  0.4,  1.0)
const _COLOR_DISABLED := Color(0.35, 0.35, 0.35, 1.0)

@onready var title_label:        Label         = $Layout/TitleLabel
@onready var top_spacer:         Control       = $Layout/TopSpacer
@onready var menu_spacer:        Control       = $Layout/MenuSpacer
@onready var bottom_spacer:      Control       = $Layout/BottomSpacer
@onready var options:            VBoxContainer = $Layout/Options
@onready var new_game_label:     Label         = $Layout/Options/NewGameLabel
@onready var load_game_label:    Label         = $Layout/Options/LoadGameLabel
@onready var quit_label:         Label         = $Layout/Options/QuitLabel
@onready var name_prompt:        VBoxContainer = $Layout/NamePrompt
@onready var name_input:         LineEdit      = $Layout/NamePrompt/NameInput
@onready var class_panel:        VBoxContainer = $Layout/ClassPanel
@onready var class_list:         VBoxContainer = $Layout/ClassPanel/ClassBody/ClassListScroll/ClassList
@onready var class_detail_name:  Label         = $Layout/ClassPanel/ClassBody/ClassDetail/ClassDetailName
@onready var class_detail_desc:  Label         = $Layout/ClassPanel/ClassBody/ClassDetail/ClassDetailDesc
@onready var class_detail_stats: Label         = $Layout/ClassPanel/ClassBody/ClassDetail/ClassDetailStats
@onready var class_detail_equip: Label         = $Layout/ClassPanel/ClassBody/ClassDetail/ClassDetailEquip
@onready var class_empty_label:  Label         = $Layout/ClassPanel/ClassEmptyLabel
@onready var stat_panel:         VBoxContainer = $Layout/StatPanel
@onready var stat_budget_label:  Label         = $Layout/StatPanel/StatBudgetLabel
@onready var stat_list:          VBoxContainer = $Layout/StatPanel/StatListScroll/StatList
@onready var stat_error_label:   Label         = $Layout/StatPanel/StatErrorLabel

var _step: _Step = _Step.MAIN_MENU
var _cursor: int = _Option.NEW_GAME
var _load_available: bool = false

var _entered_name: String = ""
var _selected_class_id: String = ""
var _class_ids: Array = []
var _class_cursor: int = 0
var _stat_allocator: StatAllocator = null
var _stat_cursor: int = 0
var _stat_ids: Array = []

func _ready() -> void:
	_load_available = _check_saves_exist()
	_read_title()
	name_prompt.hide()
	class_panel.hide()
	stat_panel.hide()
	name_input.text_submitted.connect(_on_name_submitted)
	_refresh_labels()

func _read_title() -> void:
	var config: Dictionary = Constants.load_json(Constants.GAME_CONFIG_PATH)
	var raw: Variant = config.get(Constants.GAME_TITLE_KEY)
	title_label.text = raw as String if raw is String else "Britannia Factory"

func _check_saves_exist() -> bool:
	if not FileAccess.file_exists(Constants.SAVE_INDEX_PATH):
		return false
	var file := FileAccess.open(Constants.SAVE_INDEX_PATH, FileAccess.READ)
	if file == null:
		return false
	var json := JSON.new()
	var result: bool = false
	if json.parse(file.get_as_text()) == OK:
		var data: Variant = json.get_data()
		if data is Dictionary:
			var saves: Variant = data.get("saves", [])
			result = saves is Array and (saves as Array).size() > 0
	file.close()
	return result

func _refresh_labels() -> void:
	new_game_label.add_theme_color_override("font_color",
		_COLOR_SELECTED if _cursor == _Option.NEW_GAME else _COLOR_NORMAL)
	load_game_label.add_theme_color_override("font_color",
		_COLOR_DISABLED if not _load_available else
		(_COLOR_SELECTED if _cursor == _Option.LOAD_GAME else _COLOR_NORMAL))
	quit_label.add_theme_color_override("font_color",
		_COLOR_SELECTED if _cursor == _Option.QUIT else _COLOR_NORMAL)

func _unhandled_input(event: InputEvent) -> void:
	match _step:
		_Step.MAIN_MENU:    _handle_main_menu_input(event)
		_Step.NAME_INPUT:   _handle_name_input_key(event)
		_Step.CLASS_SELECT: _handle_class_select_input(event)
		_Step.STAT_ALLOC:   _handle_stat_alloc_input(event)

func _handle_main_menu_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_move_cursor(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_move_cursor(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_select()

func _handle_name_input_key(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_show_main_menu()
		get_viewport().set_input_as_handled()

func _handle_class_select_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_selected_class_id = ""
		_show_name_input()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		if _class_cursor > 0:
			_class_cursor -= 1
			_refresh_class_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		if _class_cursor < _class_ids.size() - 1:
			_class_cursor += 1
			_refresh_class_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if not _class_ids.is_empty():
			_confirm_class()
		get_viewport().set_input_as_handled()

func _handle_stat_alloc_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_show_class_select()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		if _stat_cursor > 0:
			_stat_cursor -= 1
			_refresh_stat_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		if _stat_cursor < _stat_ids.size() - 1:
			_stat_cursor += 1
			_refresh_stat_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		if not _stat_ids.is_empty() and _stat_allocator != null:
			_stat_allocator.decrement(_stat_ids[_stat_cursor])
			_refresh_stat_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		if not _stat_ids.is_empty() and _stat_allocator != null:
			_stat_allocator.increment(_stat_ids[_stat_cursor])
			_refresh_stat_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_confirm_allocation()

func _move_cursor(delta: int) -> void:
	var new_cursor: int = wrapi(_cursor + delta, 0, _OPTION_COUNT)
	if not _load_available and new_cursor == _Option.LOAD_GAME:
		new_cursor = wrapi(new_cursor + delta, 0, _OPTION_COUNT)
	_cursor = new_cursor
	_refresh_labels()

func _select() -> void:
	match _cursor:
		_Option.NEW_GAME:
			_show_name_input()
		_Option.LOAD_GAME:
			if _load_available:
				get_tree().change_scene_to_file("res://scenes/ui/LoadGameScene.tscn")
		_Option.QUIT:
			get_tree().quit()

# ── Step transitions ──────────────────────────────────────────────────────────

func _show_main_menu() -> void:
	_step = _Step.MAIN_MENU
	_restore_menu_chrome()
	name_prompt.hide()
	class_panel.hide()
	stat_panel.hide()
	_refresh_labels()

func _show_name_input() -> void:
	_step = _Step.NAME_INPUT
	_restore_menu_chrome()
	class_panel.hide()
	stat_panel.hide()
	name_prompt.show()
	name_input.text = _entered_name
	name_input.grab_focus()

func _show_class_select() -> void:
	_step = _Step.CLASS_SELECT
	_hide_menu_chrome()
	name_prompt.hide()
	stat_panel.hide()
	_stat_allocator = null
	_build_class_panel()
	class_panel.show()

func _show_stat_alloc() -> void:
	_step = _Step.STAT_ALLOC
	_hide_menu_chrome()
	name_prompt.hide()
	class_panel.hide()
	_stat_allocator = StatAllocator.new()
	_stat_allocator.load_class(_selected_class_id)
	_stat_cursor = 0
	if GameManager.class_registry != null:
		var ranges: Dictionary = GameManager.class_registry.get_stat_ranges(_selected_class_id)
		_stat_ids = []
		for sid in ranges.keys():
			if PlayerStats.is_stat_visible(str(sid)):
				_stat_ids.append(sid)
	else:
		_stat_ids = []
	_build_stat_panel()
	stat_panel.show()

func _restore_menu_chrome() -> void:
	top_spacer.show()
	menu_spacer.show()
	bottom_spacer.show()
	options.show()

func _hide_menu_chrome() -> void:
	top_spacer.hide()
	menu_spacer.hide()
	bottom_spacer.hide()
	options.hide()

# ── Class panel ───────────────────────────────────────────────────────────────

func _build_class_panel() -> void:
	_class_ids = []
	if GameManager.class_registry != null:
		_class_ids = GameManager.class_registry.get_all_class_ids()
	for child in class_list.get_children():
		child.free()
	if _class_ids.is_empty():
		class_empty_label.show()
		class_detail_name.text = ""
		class_detail_desc.text = ""
		class_detail_stats.text = ""
		class_detail_equip.text = ""
		return
	class_empty_label.hide()
	if not _selected_class_id.is_empty():
		var idx: int = _class_ids.find(_selected_class_id)
		if idx >= 0:
			_class_cursor = idx
	_class_cursor = clampi(_class_cursor, 0, _class_ids.size() - 1)
	for cid in _class_ids:
		var lbl := Label.new()
		lbl.text = "  " + _get_class_name(cid)
		class_list.add_child(lbl)
	_refresh_class_panel()

func _refresh_class_panel() -> void:
	var children: Array = class_list.get_children()
	for i in range(children.size()):
		children[i].add_theme_color_override("font_color",
			_COLOR_SELECTED if i == _class_cursor else _COLOR_NORMAL)
	if _class_ids.is_empty():
		return
	_update_class_detail(_class_ids[_class_cursor])

func _update_class_detail(class_id: String) -> void:
	if GameManager.class_registry == null:
		return
	var cls: Dictionary = GameManager.class_registry.get_class_data(class_id)
	var cname: String = str(cls.get("name", class_id))
	class_detail_name.text = cname
	class_detail_desc.text = str(cls.get("description", ""))

	var starting: Dictionary = GameManager.class_registry.get_starting_stats(class_id)
	var lines: PackedStringArray = ["Starting Stats:"]
	for stat_id in starting:
		if PlayerStats.is_stat_visible(str(stat_id)):
			lines.append("  " + PlayerStats.get_stat_display_name(str(stat_id)) + ": " + str(starting[stat_id]))
	class_detail_stats.text = "\n".join(lines)

	var whitelist: Array = GameManager.class_registry.get_equipment_whitelist(class_id)
	var type_names: Array = []
	for eq_type in whitelist:
		if GameManager.equipment_type_registry != null:
			type_names.append(GameManager.equipment_type_registry.get_display_name(str(eq_type)))
		else:
			type_names.append(str(eq_type))
	class_detail_equip.text = cname + " can use: " + ", ".join(type_names)

func _get_class_name(class_id: String) -> String:
	if GameManager.class_registry == null:
		return class_id
	return str(GameManager.class_registry.get_class_data(class_id).get("name", class_id))

func _confirm_class() -> void:
	_selected_class_id = _class_ids[_class_cursor]
	_show_stat_alloc()

# ── Stat panel ────────────────────────────────────────────────────────────────

func _build_stat_panel() -> void:
	_update_budget_label()
	stat_error_label.hide()
	_rebuild_stat_rows()

func _update_budget_label() -> void:
	if _stat_allocator == null:
		stat_budget_label.hide()
		return
	var budget: int = _stat_allocator.get_budget_remaining()
	if budget >= 0:
		stat_budget_label.text = "Points remaining: " + str(budget)
		stat_budget_label.show()
	else:
		stat_budget_label.hide()

func _rebuild_stat_rows() -> void:
	for child in stat_list.get_children():
		child.free()
	if _stat_ids.is_empty() or _stat_allocator == null:
		return
	var ranges: Dictionary = {}
	if GameManager.class_registry != null:
		ranges = GameManager.class_registry.get_stat_ranges(_selected_class_id)
	for i in range(_stat_ids.size()):
		var stat_id: String = _stat_ids[i]
		var r: Dictionary = ranges.get(stat_id, {})
		var min_val: int = int(r.get("min", 0))
		var max_val: int = int(r.get("max", 999))
		var current: int = _stat_allocator.get_allocated(stat_id)
		var sname: String = PlayerStats.get_stat_display_name(stat_id)
		var selected: bool = (i == _stat_cursor)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)

		var name_lbl := Label.new()
		name_lbl.text = sname
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_color_override("font_color",
			_COLOR_SELECTED if selected else _COLOR_NORMAL)
		hbox.add_child(name_lbl)

		var left_lbl := Label.new()
		left_lbl.text = "<"
		left_lbl.add_theme_color_override("font_color",
			_COLOR_NORMAL if _stat_allocator.can_decrement(stat_id) else _COLOR_DISABLED)
		hbox.add_child(left_lbl)

		var val_lbl := Label.new()
		val_lbl.text = str(current)
		val_lbl.custom_minimum_size = Vector2(30, 0)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val_lbl.add_theme_color_override("font_color",
			_COLOR_SELECTED if selected else _COLOR_NORMAL)
		hbox.add_child(val_lbl)

		var right_lbl := Label.new()
		right_lbl.text = ">"
		right_lbl.add_theme_color_override("font_color",
			_COLOR_NORMAL if _stat_allocator.can_increment(stat_id) else _COLOR_DISABLED)
		hbox.add_child(right_lbl)

		var range_lbl := Label.new()
		range_lbl.text = "  " + str(min_val) + " - " + str(max_val)
		range_lbl.add_theme_color_override("font_color", _COLOR_DISABLED)
		hbox.add_child(range_lbl)

		stat_list.add_child(hbox)

func _refresh_stat_panel() -> void:
	_update_budget_label()
	stat_error_label.hide()
	_rebuild_stat_rows()

func _confirm_allocation() -> void:
	if _stat_allocator == null or not _stat_allocator.is_valid():
		stat_error_label.text = MessageRegistry.get_message("allocation_invalid")
		stat_error_label.show()
		return
	PartyManager.initialize_player(_entered_name, _selected_class_id)
	GameManager.apply_class_starting_stats(_selected_class_id)
	_stat_allocator.apply_to_player()
	PlayerStats.stat_block.set_stat("mana", PlayerStats.get_effective_value("max_mana"))
	SaveManager.save_new_game(_entered_name, _selected_class_id)
	GameManager.start_new_game(_entered_name)

# ── Name entry ────────────────────────────────────────────────────────────────

func _on_name_submitted(text: String) -> void:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return
	_entered_name = trimmed
	PlayerStats.display_name = trimmed
	_show_class_select()
