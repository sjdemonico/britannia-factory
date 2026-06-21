class_name CharacterPanel
extends CanvasLayer

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/VBox/TitleBar/TitleLabel
@onready var left_col: VBoxContainer = $Panel/VBox/Content/Left/SlotColumns/LeftCol
@onready var right_col: VBoxContainer = $Panel/VBox/Content/Left/SlotColumns/RightCol
@onready var stat_list: VBoxContainer = $Panel/VBox/Content/Right/StatList

var _current_member_index: int = 0
var _stat_labels: Dictionary = {}
var _stat_names: Dictionary = {}
var _class_label: Label = null
var _currency_label: Label = null

func _ready() -> void:
	panel.hide()

func toggle() -> void:
	if panel.visible:
		_close()
	else:
		_open()

func _open() -> void:
	_current_member_index = 0
	_build_slots()
	_build_stats()
	_connect_member_signals()
	panel.show()

func _close() -> void:
	_disconnect_member_signals()
	panel.hide()

func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_left"):
		_navigate(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_right"):
		_navigate(1)
		get_viewport().set_input_as_handled()

func _navigate(delta: int) -> void:
	_disconnect_member_signals()
	var count: int = PartyManager.get_party_size()
	if count == 0:
		return
	_current_member_index = (_current_member_index + delta + count) % count
	_build_slots()
	_build_stats()
	_connect_member_signals()

func _connect_member_signals() -> void:
	var member := PartyManager.get_member_at(_current_member_index)
	if member != null and member.stat_block != null:
		if not member.stat_block.stat_changed.is_connected(_on_stat_changed):
			member.stat_block.stat_changed.connect(_on_stat_changed)
	if not PlayerInventory.equip_changed.is_connected(_on_equip_changed):
		PlayerInventory.equip_changed.connect(_on_equip_changed)
	if not PlayerStats.class_changed.is_connected(_on_class_changed):
		PlayerStats.class_changed.connect(_on_class_changed)

func _disconnect_member_signals() -> void:
	var member := PartyManager.get_member_at(_current_member_index)
	if member != null and member.stat_block != null:
		if member.stat_block.stat_changed.is_connected(_on_stat_changed):
			member.stat_block.stat_changed.disconnect(_on_stat_changed)
	if PlayerInventory.equip_changed.is_connected(_on_equip_changed):
		PlayerInventory.equip_changed.disconnect(_on_equip_changed)
	if PlayerStats.class_changed.is_connected(_on_class_changed):
		PlayerStats.class_changed.disconnect(_on_class_changed)

func _build_slots() -> void:
	for child in left_col.get_children():
		child.free()
	for child in right_col.get_children():
		child.free()
	if GameManager.slot_registry == null:
		return
	var member := PartyManager.get_member_at(_current_member_index)
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
		var is_occupied: bool = false
		if member != null and member.inventory != null:
			is_occupied = member.inventory.get_slot_occupancy(slot_id) > idx
		else:
			is_occupied = PlayerInventory.get_slot_occupancy(slot_id) > idx
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
	_class_label = null
	_currency_label = null

	var member := PartyManager.get_member_at(_current_member_index)
	if member == null:
		return

	# Update panel title
	var cls_display: String = _get_class_display_name(member)
	if title_label != null:
		title_label.text = member.display_name + (" — " + cls_display if not cls_display.is_empty() else "")

	var name_label := Label.new()
	name_label.text = member.display_name
	name_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5, 1.0))
	stat_list.add_child(name_label)

	if not cls_display.is_empty():
		_class_label = Label.new()
		_class_label.text = cls_display
		stat_list.add_child(_class_label)

	# Currency only for player
	if member.member_id == Constants.PLAYER_MEMBER_ID:
		var currency_stat: String = GameManager.currency_stat_id
		if not currency_stat.is_empty() and member.stat_block != null and member.stat_block.has_stat(currency_stat):
			_currency_label = Label.new()
			_currency_label.text = _format_currency(member)
			stat_list.add_child(_currency_label)

	if member.stat_block == null:
		return

	for stat in member.stat_block.get_visible_stats():
		var stat_id: String = stat["id"]
		var stat_name: String = stat["name"]
		var label := Label.new()
		label.text = _format_stat_line(member, stat_id, stat_name)
		stat_list.add_child(label)
		_stat_labels[stat_id] = label
		_stat_names[stat_id] = stat_name

	if member.stat_block.has_stat(Constants.EXPERIENCE_STAT_ID):
		var exp_label := Label.new()
		exp_label.text = _format_experience_line(member)
		stat_list.add_child(exp_label)
		_stat_labels[Constants.EXPERIENCE_STAT_ID] = exp_label
		_stat_names[Constants.EXPERIENCE_STAT_ID] = "Experience"

func _get_class_display_name(member: PartyMember) -> String:
	if member.class_id.is_empty() or GameManager.class_registry == null:
		return ""
	var cls_data: Dictionary = GameManager.class_registry.get_class_data(member.class_id)
	return str(cls_data.get("name", member.class_id))

func _format_currency(member: PartyMember) -> String:
	var stat_id: String = GameManager.currency_stat_id
	if stat_id.is_empty() or member.stat_block == null or not member.stat_block.has_stat(stat_id):
		return ""
	return str(member.stat_block.get_effective_value(stat_id)) + " " + GameManager.currency_display_name

func _format_stat_line(member: PartyMember, stat_id: String, stat_name: String) -> String:
	if member.stat_block == null:
		return stat_name + ": —"
	return stat_name + ": " + member.stat_block.format_effective_stat(stat_id)

func _format_experience_line(member: PartyMember) -> String:
	if member.stat_block == null:
		return "Experience: —"
	var current: int = member.stat_block.get_value(Constants.EXPERIENCE_STAT_ID)
	if GameManager.level_manager == null:
		return "Experience: " + str(current)
	var next_t := GameManager.level_manager.get_next_threshold(current)
	if next_t < 0:
		return "Experience: " + str(current) + " / MAX"
	return "Experience: " + str(current) + " / " + str(next_t)

func _on_stat_changed(stat_id: String, _old_val: int, _new_val: int) -> void:
	var member := PartyManager.get_member_at(_current_member_index)
	if member == null:
		return
	if stat_id == GameManager.currency_stat_id and _currency_label != null:
		_currency_label.text = _format_currency(member)
		return
	if not _stat_labels.has(stat_id):
		return
	if stat_id == Constants.EXPERIENCE_STAT_ID:
		_stat_labels[stat_id].text = _format_experience_line(member)
	else:
		_stat_labels[stat_id].text = _format_stat_line(member, stat_id, _stat_names[stat_id])

func _on_class_changed(_class_id: String) -> void:
	_build_stats()

func _on_equip_changed() -> void:
	_build_slots()
