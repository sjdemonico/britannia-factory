class_name CharacterPanel
extends CanvasLayer

@onready var panel: Panel = $Panel
@onready var left_col: VBoxContainer = $Panel/Content/Left/SlotColumns/LeftCol
@onready var right_col: VBoxContainer = $Panel/Content/Left/SlotColumns/RightCol
@onready var stat_list: VBoxContainer = $Panel/Content/Right/StatList

var _stat_labels: Dictionary = {}
var _stat_names: Dictionary = {}

func _ready() -> void:
	panel.hide()

func toggle() -> void:
	if panel.visible:
		_close()
	else:
		_open()

func _open() -> void:
	_build_slots()
	_build_stats()
	if not PlayerStats.stat_block.stat_changed.is_connected(_on_stat_changed):
		PlayerStats.stat_block.stat_changed.connect(_on_stat_changed)
	if not PlayerInventory.equip_changed.is_connected(_on_equip_changed):
		PlayerInventory.equip_changed.connect(_on_equip_changed)
	panel.show()

func _close() -> void:
	if PlayerStats.stat_block.stat_changed.is_connected(_on_stat_changed):
		PlayerStats.stat_block.stat_changed.disconnect(_on_stat_changed)
	if PlayerInventory.equip_changed.is_connected(_on_equip_changed):
		PlayerInventory.equip_changed.disconnect(_on_equip_changed)
	panel.hide()

func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()

func _build_slots() -> void:
	for child in left_col.get_children():
		child.free()
	for child in right_col.get_children():
		child.free()
	if GameManager.slot_registry == null:
		return
	var expanded: Array[Dictionary] = []
	for slot in GameManager.slot_registry.get_all_slots():
		for _i in range(slot["instances"]):
			expanded.append(slot)
	var slot_proc_count: Dictionary = {}
	for i in range(expanded.size()):
		var slot: Dictionary = expanded[i]
		var slot_id: String = slot["id"]
		var idx: int = slot_proc_count.get(slot_id, 0)
		slot_proc_count[slot_id] = idx + 1
		var is_occupied: bool = PlayerInventory.get_slot_occupancy(slot_id) > idx
		var box := _make_slot_box(slot["display_name"], is_occupied)
		if i % 2 == 0:
			left_col.add_child(box)
		else:
			right_col.add_child(box)

func _make_slot_box(display_name: String, is_occupied: bool = false) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(64, 64)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.2, 0.2, 0.35, 1.0)
	box.add_child(bg)

	var label := Label.new()
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = 4.0
	label.offset_top = 4.0
	label.offset_right = -4.0
	label.offset_bottom = -4.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if is_occupied:
		label.text = "▲"
		label.add_theme_font_size_override("font_size", 40)
	else:
		label.text = display_name
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)

	return box

func _build_stats() -> void:
	for child in stat_list.get_children():
		child.free()
	_stat_labels.clear()
	_stat_names.clear()
	var player_name_label := Label.new()
	player_name_label.text = PlayerStats.display_name
	player_name_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5, 1.0))
	stat_list.add_child(player_name_label)
	for stat in PlayerStats.get_visible_stats():
		var stat_id: String = stat["id"]
		var stat_name: String = stat["name"]
		var label := Label.new()
		label.text = _format_stat_line(stat_id, stat_name)
		stat_list.add_child(label)
		_stat_labels[stat_id] = label
		_stat_names[stat_id] = stat_name
	var exp_label := Label.new()
	exp_label.text = _format_experience_line()
	stat_list.add_child(exp_label)
	_stat_labels[Constants.EXPERIENCE_STAT_ID] = exp_label
	_stat_names[Constants.EXPERIENCE_STAT_ID] = "Experience"

func _format_stat_line(stat_id: String, stat_name: String) -> String:
	return stat_name + ": " + PlayerStats.format_effective_stat(stat_id)

func _format_experience_line() -> String:
	var current: int = PlayerStats.get_stat(Constants.EXPERIENCE_STAT_ID)
	if GameManager.level_manager == null:
		return "Experience: " + str(current)
	var next_t := GameManager.level_manager.get_next_threshold(current)
	if next_t < 0:
		return "Experience: " + str(current) + " / MAX"
	return "Experience: " + str(current) + " / " + str(next_t)

func _on_stat_changed(stat_id: String, _old_val: int, _new_val: int) -> void:
	if not _stat_labels.has(stat_id):
		return
	if stat_id == Constants.EXPERIENCE_STAT_ID:
		_stat_labels[stat_id].text = _format_experience_line()
	else:
		_stat_labels[stat_id].text = _format_stat_line(stat_id, _stat_names[stat_id])

func _on_equip_changed() -> void:
	_build_slots()
