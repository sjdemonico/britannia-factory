class_name JournalPanel
extends CanvasLayer

@onready var panel: Panel = $Panel
@onready var quest_list: VBoxContainer = $Panel/Content/QuestScroll/QuestList
@onready var detail_container: VBoxContainer = $Panel/Content/DetailScroll/DetailContainer

var _rows: Array = []
var _expanded: Dictionary = {}
var _cursor: int = 0

func _ready() -> void:
	panel.hide()

func toggle() -> void:
	if panel.visible:
		close()
	else:
		open()

func open() -> void:
	_refresh()
	panel.show()

func close() -> void:
	panel.hide()

func _refresh() -> void:
	_build_rows()
	_rebuild_list()
	_refresh_detail()

func _build_rows() -> void:
	_rows.clear()
	var categories: Array = [
		{"id": "active",   "label": "Active Quests",    "quests": QuestManager.get_active_quests()},
		{"id": "complete", "label": "Completed Quests",  "quests": QuestManager.get_completed_quests()},
		{"id": "failed",   "label": "Failed Quests",     "quests": QuestManager.get_failed_quests()}
	]
	for cat in categories:
		if (cat["quests"] as Array).is_empty():
			continue
		_rows.append({"type": "category", "quest_id": "", "label": str(cat["label"])})
		for qid_raw in cat["quests"]:
			var qid: String = str(qid_raw)
			var def: Dictionary = QuestManager.get_quest(qid)
			_rows.append({"type": "quest", "quest_id": qid, "label": str(def.get("name", qid))})
			if _expanded.get(qid, false):
				var obj_states: Dictionary = QuestManager.get_all_objective_states(qid)
				for obj_def in def.get("objectives", []):
					if not obj_def is Dictionary:
						continue
					var obj_id: String = str(obj_def.get("objective_id", ""))
					if obj_id.is_empty():
						continue
					var obj_state_raw: Variant = obj_states.get(obj_id)
					var status: String = str(obj_state_raw.get("status", "hidden")) if obj_state_raw is Dictionary else "hidden"
					if status == "hidden":
						continue
					var desc: String = str(obj_def.get("description_override", obj_id))
					var marker: String
					match status:
						"complete": marker = "[x] "
						"skipped":  marker = "[-] "
						_:          marker = "[ ] "
					_rows.append({"type": "objective", "quest_id": qid, "label": marker + desc})

func _rebuild_list() -> void:
	for child in quest_list.get_children():
		child.free()
	if _rows.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No quests recorded."
		quest_list.add_child(empty_label)
		return
	_cursor = clampi(_cursor, 0, _rows.size() - 1)
	for i in range(_rows.size()):
		var row: Dictionary = _rows[i]
		var row_type: String = str(row["type"])
		var label := Label.new()
		label.text = _row_text(row)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		match row_type:
			"category":
				label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.3, 1.0))
			"objective":
				label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65, 1.0))
		if i == _cursor and row_type != "category":
			label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6, 1.0))
		quest_list.add_child(label)

func _row_text(row: Dictionary) -> String:
	var qid: String = str(row["quest_id"])
	match str(row["type"]):
		"category":
			return "=== " + str(row["label"]) + " ==="
		"quest":
			return "  " + ("v " if _expanded.get(qid, false) else "> ") + str(row["label"])
		"objective":
			return "      " + str(row["label"])
	return str(row["label"])

func _get_selected_quest_id() -> String:
	if _cursor >= _rows.size():
		return ""
	var row: Dictionary = _rows[_cursor]
	var t: String = str(row["type"])
	if t == "quest" or t == "objective":
		return str(row["quest_id"])
	return ""

func _refresh_detail() -> void:
	for child in detail_container.get_children():
		child.free()
	var qid: String = _get_selected_quest_id()
	if qid.is_empty():
		return
	var def: Dictionary = QuestManager.get_quest(qid)
	var desc: String = str(def.get("description", ""))
	if not desc.is_empty():
		var desc_label := Label.new()
		desc_label.text = desc
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_container.add_child(desc_label)
	var updates: Array = QuestManager.get_journal_updates(qid)
	if updates.is_empty():
		return
	var sep := ColorRect.new()
	sep.color = Color(0.4, 0.4, 0.4, 1.0)
	sep.custom_minimum_size = Vector2(0, 1)
	detail_container.add_child(sep)
	for update in updates:
		var entry_label := Label.new()
		entry_label.text = "[" + str(update.get("timestamp", "")) + "] " + str(update.get("text", ""))
		entry_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_container.add_child(entry_label)

func _move_cursor(delta: int) -> void:
	if _rows.is_empty():
		return
	var new_cursor: int = _cursor + delta
	while new_cursor >= 0 and new_cursor < _rows.size() and str(_rows[new_cursor]["type"]) == "category":
		new_cursor += delta
	if new_cursor < 0 or new_cursor >= _rows.size():
		return
	_cursor = new_cursor
	_rebuild_list()
	_refresh_detail()

func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_up"):
		_move_cursor(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_move_cursor(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if _cursor < _rows.size() and str(_rows[_cursor]["type"]) == "quest":
			var qid: String = str(_rows[_cursor]["quest_id"])
			_expanded[qid] = not _expanded.get(qid, false)
			_build_rows()
			_rebuild_list()
			_refresh_detail()
		get_viewport().set_input_as_handled()
