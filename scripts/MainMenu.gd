class_name MainMenu
extends Control

enum _Option { NEW_GAME = 0, LOAD_GAME = 1, QUIT = 2 }
const _OPTION_COUNT: int = 3

const _COLOR_NORMAL   := Color(0.75, 0.75, 0.75, 1.0)
const _COLOR_SELECTED := Color(1.0,  1.0,  0.4,  1.0)
const _COLOR_DISABLED := Color(0.35, 0.35, 0.35, 1.0)

@onready var title_label:     Label        = $Layout/TitleLabel
@onready var new_game_label:  Label        = $Layout/Options/NewGameLabel
@onready var load_game_label: Label        = $Layout/Options/LoadGameLabel
@onready var quit_label:      Label        = $Layout/Options/QuitLabel
@onready var name_prompt:     VBoxContainer = $Layout/NamePrompt
@onready var name_input:      LineEdit     = $Layout/NamePrompt/NameInput

var _cursor: int = _Option.NEW_GAME
var _in_name_input: bool = false
var _load_available: bool = false

func _ready() -> void:
	_load_available = _check_saves_exist()
	_read_title()
	name_prompt.hide()
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
	if _in_name_input:
		if event.is_action_pressed("ui_cancel"):
			_cancel_name_input()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_up"):
		_move_cursor(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_move_cursor(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_select()

func _move_cursor(delta: int) -> void:
	var new_cursor: int = wrapi(_cursor + delta, 0, _OPTION_COUNT)
	if not _load_available and new_cursor == _Option.LOAD_GAME:
		new_cursor = wrapi(new_cursor + delta, 0, _OPTION_COUNT)
	_cursor = new_cursor
	_refresh_labels()

func _select() -> void:
	match _cursor:
		_Option.NEW_GAME:
			_begin_name_input()
		_Option.LOAD_GAME:
			if _load_available:
				get_tree().change_scene_to_file("res://scenes/ui/LoadGameScene.tscn")
		_Option.QUIT:
			get_tree().quit()

func _begin_name_input() -> void:
	_in_name_input = true
	name_prompt.show()
	name_input.text = ""
	name_input.grab_focus()

func _cancel_name_input() -> void:
	_in_name_input = false
	name_prompt.hide()
	name_input.release_focus()
	_refresh_labels()

func _on_name_submitted(text: String) -> void:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return
	GameManager.start_new_game(trimmed)
