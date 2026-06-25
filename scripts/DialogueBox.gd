class_name DialogueBox
extends CanvasLayer

const KEYWORD_COLOR: String = "#f0c040"

@onready var panel: Panel = $Panel
@onready var npc_name_label: Label = $Panel/VBoxContainer/NPCNameLabel
@onready var response_label: RichTextLabel = $Panel/VBoxContainer/ResponseLabel
@onready var line_edit: LineEdit = $Panel/VBoxContainer/LineEdit

var _manager: DialogueManager = null
var _current_npc: NPC = null
var _current_party_member: PartyMember = null

signal dialogue_closed

func _ready() -> void:
	response_label.bbcode_enabled = true
	line_edit.text_submitted.connect(_on_text_submitted)
	panel.hide()

func open(npc: NPC) -> void:
	_current_npc = npc
	_current_party_member = null
	npc_name_label.text = npc.display_name
	_manager = npc.dialogue_manager
	if _manager == null:
		_show_response("This person has nothing to say.")
		panel.show()
		return
	_show_response(_manager.get_greeting())
	panel.show()
	line_edit.call_deferred("grab_focus")

func open_for_party_member(member: PartyMember) -> void:
	_current_npc = null
	_current_party_member = member
	npc_name_label.text = member.display_name
	_manager = _load_dialogue_for_member(member)
	if _manager == null:
		_show_response("This person has nothing to say.")
		panel.show()
		return
	_show_response(_manager.get_greeting())
	panel.show()
	line_edit.call_deferred("grab_focus")

func _load_dialogue_for_member(member: PartyMember) -> DialogueManager:
	if member.source_npc_id.is_empty():
		return null
	var path := Constants.NPC_DATA_PATH + member.source_npc_id + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return null
	file.close()
	var data: Dictionary = json.get_data()
	if not data.has("dialogue"):
		return null
	var dm := DialogueManager.new()
	dm.npc_id = member.source_npc_id
	dm.load_from_dict(data["dialogue"])
	return dm

func close() -> void:
	if _manager != null:
		_show_response(_manager.get_farewell())
	panel.hide()
	_manager = null
	_current_npc = null
	_current_party_member = null
	dialogue_closed.emit()

func _close_no_farewell() -> void:
	panel.hide()
	_manager = null
	_current_npc = null
	_current_party_member = null
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

	if keyword == "join" and _current_npc != null:
		_handle_join_keyword(_current_npc)
		return

	if keyword == "dismiss" and _current_party_member != null:
		_handle_dismiss_keyword(_current_party_member)
		return

	if _manager == null:
		return

	var response := _manager.process_keyword(raw_text)
	_show_response(response)

func _handle_join_keyword(npc: NPC) -> void:
	if _manager != null and not _manager.meets_min_standing("join"):
		var alt: String = _manager.get_alternate_response("join")
		if alt.is_empty():
			alt = _manager.get_join_rejects()
		_show_response(alt if not alt.is_empty() else MessageRegistry.get_message("recruit_not_recruitable"))
		return
	if not npc.recruitable:
		MessageLog.post(MessageRegistry.get_message("recruit_not_recruitable"))
		return
	if not npc.recruit_requires_quest.is_empty():
		if not QuestManager.is_quest_complete(npc.recruit_requires_quest):
			var rejects: String = _manager.get_join_rejects() if _manager != null else ""
			MessageLog.post(rejects if not rejects.is_empty() else MessageRegistry.get_message("recruit_not_recruitable"))
			return
	if PartyManager.get_party_size() >= PartyManager.get_max_party_size():
		var rejects: String = _manager.get_join_rejects() if _manager != null else ""
		MessageLog.post(rejects if not rejects.is_empty() else MessageRegistry.get_message("recruit_not_recruitable"))
		return
	var accepts: String = _manager.get_join_accepts() if _manager != null else ""
	if not accepts.is_empty():
		MessageLog.post(accepts)
	var member := PartyMember.new()
	member.initialize_from_npc(npc)
	PartyManager.add_member(member)
	MessageLog.post(MessageRegistry.get_message("recruit_joined", {"name": npc.display_name}))
	MessageLog.post_blank()
	npc.remove_from_world()
	_close_no_farewell()

func _handle_dismiss_keyword(member: PartyMember) -> void:
	var farewell: String = _manager.get_farewell_dismiss() if _manager != null else ""
	if not farewell.is_empty():
		MessageLog.post(farewell)
	PartyManager.remove_member(member.member_id)
	GameManager.reinstantiate_npc(member)
	MessageLog.post(MessageRegistry.get_message("recruit_dismissed", {"name": member.display_name}))
	MessageLog.post_blank()
	_close_no_farewell()

func _show_response(text: String) -> void:
	var result := ""
	var words := text.split(" ")
	for word in words:
		var stripped := word.strip_edges()
		# Highlight ALL-CAPS words of two or more characters — keyword hints.
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
			_current_npc = null
			_current_party_member = null
			dialogue_closed.emit()
