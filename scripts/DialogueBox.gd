extends CanvasLayer

const KEYWORD_COLOR: String = "#f0c040"

@onready var panel: Panel = $Panel
@onready var npc_name_label: Label = $Panel/VBoxContainer/NPCNameLabel
@onready var response_label: RichTextLabel = $Panel/VBoxContainer/ResponseLabel
@onready var line_edit: LineEdit = $Panel/VBoxContainer/LineEdit

var _manager: DialogueManager = null

signal dialogue_closed

func _ready() -> void:
	response_label.bbcode_enabled = true
	line_edit.text_submitted.connect(_on_text_submitted)
	panel.hide()

func open(npc: NPC) -> void:
	npc_name_label.text = npc.display_name
	_manager = npc.dialogue_manager
	if _manager == null:
		_show_response("This person has nothing to say.")
		panel.show()
		return
	_show_response(_manager.get_greeting())
	panel.show()
	line_edit.call_deferred("grab_focus")

func close() -> void:
	if _manager != null:
		_show_response(_manager.get_farewell())
	panel.hide()
	_manager = null
	dialogue_closed.emit()

func _on_text_submitted(raw_text: String) -> void:
	if raw_text.strip_edges().is_empty():
		return

	var keyword := raw_text.strip_edges().to_lower()
	line_edit.clear()
	line_edit.call_deferred("grab_focus")

	if keyword == "bye" or keyword == "farewell" or keyword == "exit":
		close()
		return

	if _manager == null:
		return

	var response := _manager.process_keyword(raw_text)
	_show_response(response)

func _show_response(text: String) -> void:
	var result := ""
	var words := text.split(" ")
	for word in words:
		var stripped := word.strip_edges()
		# Highlight only ALL-CAPS words of two or more characters — keyword hints.
		if stripped.length() >= 2 and stripped == stripped.to_upper() and stripped != stripped.to_lower():
			result += "[color=" + KEYWORD_COLOR + "]" + word + "[/color] "
		else:
			result += word + " "
	response_label.text = result.strip_edges()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if panel.visible:
			panel.hide()
			_manager = null
			dialogue_closed.emit()
