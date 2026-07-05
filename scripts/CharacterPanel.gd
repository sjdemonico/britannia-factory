class_name CharacterPanel
extends CanvasLayer

@onready var panel: Panel = $Panel
@onready var _title_bar: Control = $Panel/VBox/TitleBar
@onready var title_label: Label = $Panel/VBox/TitleBar/TitleLabel
@onready var left_col: VBoxContainer = $Panel/VBox/Content/Left/SlotColumns/LeftCol
@onready var right_col: VBoxContainer = $Panel/VBox/Content/Left/SlotColumns/RightCol
@onready var stat_columns: VBoxContainer = $Panel/VBox/Content/Right/StatColumns
@onready var faction_header: Label = $Panel/VBox/Content/Right/FactionHeader
@onready var faction_list: VBoxContainer = $Panel/VBox/Content/Right/FactionList

var _current_member_index: int = 0
var _stat_labels: Dictionary = {}
var _stat_names: Dictionary = {}
var _class_label: Label = null
var _currency_label: Label = null
var _faction_scroll: ScrollableList = ScrollableList.new()
var _faction_tier_labels: Dictionary = {}

func _ready() -> void:
	panel.hide()
	_apply_fonts()
	var btn_left := Button.new()
	btn_left.text = "<"
	btn_left.flat = true
	btn_left.pressed.connect(func(): if panel.visible: _navigate(-1))
	_title_bar.add_child(btn_left)
	_title_bar.move_child(btn_left, 0)
	var btn_right := Button.new()
	btn_right.text = ">"
	btn_right.flat = true
	btn_right.pressed.connect(func(): if panel.visible: _navigate(1))
	_title_bar.add_child(btn_right)

func _apply_fonts() -> void:
	for lbl in [title_label, faction_header]:
		if GameManager.get_font(Constants.FONT_HEADER_ROLE):
			lbl.add_theme_font_override("font", GameManager.get_font(Constants.FONT_HEADER_ROLE))
		lbl.add_theme_font_size_override("font_size", GameManager.get_font_size(Constants.FONT_HEADER_ROLE))

func _apply_body_font_to_container(container: Control) -> void:
	for child in container.get_children():
		if child is Label:
			if GameManager.get_font(Constants.FONT_BODY_ROLE):
				(child as Label).add_theme_font_override("font", GameManager.get_font(Constants.FONT_BODY_ROLE))
			(child as Label).add_theme_font_size_override("font_size", GameManager.get_font_size(Constants.FONT_BODY_ROLE))
		elif child is Control:
			_apply_body_font_to_container(child as Control)

func toggle() -> void:
	if panel.visible:
		_close()
	else:
		_open()

func _open() -> void:
	open_at_index(0)

func open_at_index(index: int) -> void:
	_disconnect_member_signals()
	var count: int = PartyManager.get_party_size()
	if count == 0:
		return
	_current_member_index = clampi(index, 0, count - 1)
	if not panel.visible:
		_faction_scroll.setup(8)
		_faction_scroll.reset()
	_build_slots()
	_build_stats()
	_build_faction_section()
	_connect_member_signals()
	panel.show()
	_refresh_faction_visible_rows.call_deferred()

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
		return
	if event.is_action_pressed("ui_up"):
		_scroll_factions(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_down"):
		_scroll_factions(1)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and _faction_scroll.needs_scroll():
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll_factions(-1)
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_factions(1)
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

func _scroll_factions(delta: int) -> void:
	if not _faction_scroll.needs_scroll():
		return
	if delta < 0:
		_faction_scroll.scroll_up()
	else:
		_faction_scroll.scroll_down()
	_build_faction_section()

func _connect_member_signals() -> void:
	var member := PartyManager.get_member_at(_current_member_index)
	if member != null and member.stat_block != null:
		if not member.stat_block.stat_changed.is_connected(_on_stat_changed):
			member.stat_block.stat_changed.connect(_on_stat_changed)
	if not PlayerInventory.equip_changed.is_connected(_on_equip_changed):
		PlayerInventory.equip_changed.connect(_on_equip_changed)
	if not PlayerStats.class_changed.is_connected(_on_class_changed):
		PlayerStats.class_changed.connect(_on_class_changed)
	if not FactionManager.standing_changed.is_connected(_on_faction_changed):
		FactionManager.standing_changed.connect(_on_faction_changed)

func _disconnect_member_signals() -> void:
	var member := PartyManager.get_member_at(_current_member_index)
	if member != null and member.stat_block != null:
		if member.stat_block.stat_changed.is_connected(_on_stat_changed):
			member.stat_block.stat_changed.disconnect(_on_stat_changed)
	if PlayerInventory.equip_changed.is_connected(_on_equip_changed):
		PlayerInventory.equip_changed.disconnect(_on_equip_changed)
	if PlayerStats.class_changed.is_connected(_on_class_changed):
		PlayerStats.class_changed.disconnect(_on_class_changed)
	if FactionManager.standing_changed.is_connected(_on_faction_changed):
		FactionManager.standing_changed.disconnect(_on_faction_changed)

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
		var slot_sprite_path = null
		if member != null and member.inventory != null:
			is_occupied = member.inventory.get_slot_occupancy(slot_id) > idx
			if is_occupied:
				var item_dict := member.inventory.get_item_in_slot(slot_id, idx)
				slot_sprite_path = item_dict.get("data", {}).get("sprite_path", null)
		else:
			is_occupied = PlayerInventory.get_slot_occupancy(slot_id) > idx
			if is_occupied:
				var item_dict := PlayerInventory.get_item_in_slot(slot_id, idx)
				slot_sprite_path = item_dict.get("data", {}).get("sprite_path", null)
		var box := _make_slot_box(slot["display_name"], is_occupied, slot_sprite_path)
		if i % 2 == 0:
			left_col.add_child(box)
		else:
			right_col.add_child(box)

func _make_slot_box(display_name: String, is_occupied: bool = false, sprite_path = null) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(64, 64)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.2, 0.2, 0.35, 1.0)
	box.add_child(bg)

	var item_sprite := TextureRect.new()
	item_sprite.name = "ItemSprite"
	item_sprite.anchor_right = 1.0
	item_sprite.anchor_bottom = 1.0
	item_sprite.offset_left = 8.0
	item_sprite.offset_top = 8.0
	item_sprite.offset_right = -8.0
	item_sprite.offset_bottom = -8.0
	item_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	item_sprite.visible = false
	box.add_child(item_sprite)
	if SpriteLoader.apply_to_node(item_sprite, sprite_path, Constants.SPRITE_SOURCE_SIZE):
		item_sprite.visible = true

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
		label.text = "" if item_sprite.visible else "▲"
		label.add_theme_font_size_override("font_size", 40)
	else:
		label.text = display_name
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)

	return box

func _build_stats() -> void:
	for child in stat_columns.get_children():
		child.free()
	_stat_labels.clear()
	_stat_names.clear()
	_class_label = null
	_currency_label = null

	var member := PartyManager.get_member_at(_current_member_index)
	if member == null:
		return

	var cls_display: String = _get_class_display_name(member)
	if title_label != null:
		title_label.text = member.display_name + (" — " + cls_display if not cls_display.is_empty() else "")

	# Row 1: Name | Class
	var row1 := HBoxContainer.new()
	row1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Label.new()
	name_lbl.text = member.display_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5, 1.0))
	row1.add_child(name_lbl)
	if not cls_display.is_empty():
		_class_label = Label.new()
		_class_label.text = cls_display
		_class_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row1.add_child(_class_label)
	stat_columns.add_child(row1)

	if member.stat_block == null:
		return

	# Row 2: Level | Experience
	var row2 := HBoxContainer.new()
	row2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if member.stat_block.has_stat("level"):
		var level_name: String = _get_stat_name(member, "level")
		var level_lbl := Label.new()
		level_lbl.text = level_name + " " + _format_stat_value(member, "level")
		level_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row2.add_child(level_lbl)
		_stat_labels["level"] = level_lbl
		_stat_names["level"] = level_name
	if member.stat_block.has_stat(Constants.EXPERIENCE_STAT_ID):
		var exp_name: String = _get_stat_name(member, Constants.EXPERIENCE_STAT_ID)
		var exp_lbl := Label.new()
		exp_lbl.text = exp_name + " " + _format_stat_value(member, Constants.EXPERIENCE_STAT_ID)
		exp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		exp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row2.add_child(exp_lbl)
		_stat_labels[Constants.EXPERIENCE_STAT_ID] = exp_lbl
		_stat_names[Constants.EXPERIENCE_STAT_ID] = exp_name
	stat_columns.add_child(row2)

	# Currency (player only)
	if member.member_id == Constants.PLAYER_MEMBER_ID:
		var currency_stat: String = GameManager.currency_stat_id
		if not currency_stat.is_empty() and member.stat_block.has_stat(currency_stat):
			_currency_label = Label.new()
			_currency_label.text = _format_currency(member)
			stat_columns.add_child(_currency_label)

	# Remaining visible stats (level excluded — already in row 2)
	var all_stats: Array = []
	for stat in member.stat_block.get_visible_stats():
		if str(stat.get("id", "")) != "level":
			all_stats.append(stat)

	var i: int = 0
	while i < all_stats.size():
		var left_stat: Dictionary = all_stats[i]
		var right_stat: Variant = all_stats[i + 1] if i + 1 < all_stats.size() else null

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var left_id: String = str(left_stat.get("id", ""))
		var left_name: String = str(left_stat.get("name", ""))
		var left_desc: String = str(left_stat.get("description", ""))
		var left_lbl := Label.new()
		left_lbl.text = left_name + " " + _format_stat_value(member, left_id)
		left_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		left_lbl.mouse_entered.connect(func(): _on_stat_hovered(left_name, left_desc))
		left_lbl.mouse_exited.connect(func(): TooltipManager.on_item_unhovered())
		row.add_child(left_lbl)
		_stat_labels[left_id] = left_lbl
		_stat_names[left_id] = left_name

		if right_stat != null:
			var right_id: String = str(right_stat.get("id", ""))
			var right_name: String = str(right_stat.get("name", ""))
			var right_desc: String = str(right_stat.get("description", ""))
			var right_lbl := Label.new()
			right_lbl.text = right_name + " " + _format_stat_value(member, right_id)
			right_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			right_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right_lbl.mouse_entered.connect(func(): _on_stat_hovered(right_name, right_desc))
			right_lbl.mouse_exited.connect(func(): TooltipManager.on_item_unhovered())
			row.add_child(right_lbl)
			_stat_labels[right_id] = right_lbl
			_stat_names[right_id] = right_name

		stat_columns.add_child(row)
		i += 2
	_apply_body_font_to_container(stat_columns)

func _build_faction_section() -> void:
	for child in faction_list.get_children():
		child.free()
	_faction_tier_labels.clear()

	var modified: Array[Dictionary] = FactionManager.get_modified_factions()
	if modified.is_empty():
		var none_label := Label.new()
		none_label.text = "No known factions."
		none_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
		faction_list.add_child(none_label)
		return

	_faction_scroll.set_items(modified)

	for f in _faction_scroll.get_visible_items():
		var fid: String = str(f.get("faction_id", ""))
		var fname: String = str(f.get("name", fid))
		var tier_name: String = FactionManager.get_tier_name(fid)

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_lbl := Label.new()
		name_lbl.text = fname
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(name_lbl)

		var tier_lbl := Label.new()
		tier_lbl.text = tier_name
		tier_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
		tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var tier_color_str: String = str(FactionManager.get_tier(fid).get("color", ""))
		var tier_color: Color = Color(tier_color_str) if not tier_color_str.is_empty() else Color.WHITE
		tier_lbl.add_theme_color_override("font_color", tier_color)
		row.add_child(tier_lbl)

		var captured_fname := fname
		var captured_tier := tier_name
		row.mouse_entered.connect(func(): _on_faction_hovered(captured_fname, captured_tier))
		row.mouse_exited.connect(func(): TooltipManager.on_item_unhovered())
		faction_list.add_child(row)
		_faction_tier_labels[fid] = tier_lbl
	_apply_body_font_to_container(faction_list)

func _refresh_faction_visible_rows() -> void:
	const ROW_HEIGHT: float = 20.0
	var h: float = faction_list.size.y
	if h >= ROW_HEIGHT:
		var computed: int = int(h / ROW_HEIGHT)
		if computed != _faction_scroll._visible_rows:
			_faction_scroll.setup(computed)
			_build_faction_section()

func _get_stat_name(member: PartyMember, stat_id: String) -> String:
	for s in member.stat_block.get_all_stats():
		if str(s.get("id", "")) == stat_id:
			return str(s.get("name", stat_id))
	return stat_id

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

func _format_stat_value(member: PartyMember, stat_id: String) -> String:
	if member.stat_block == null:
		return "—"
	if stat_id == Constants.EXPERIENCE_STAT_ID:
		return _format_experience_value(member)
	return member.stat_block.format_effective_stat(stat_id)

func _format_experience_value(member: PartyMember) -> String:
	if member.stat_block == null:
		return "—"
	var current: int = member.stat_block.get_value(Constants.EXPERIENCE_STAT_ID)
	if GameManager.level_manager == null:
		return str(current)
	var next_t := GameManager.level_manager.get_next_threshold(current)
	if next_t < 0:
		return str(current) + " / MAX"
	return str(current) + " / " + str(next_t)

func _on_stat_changed(stat_id: String, _old_val: int, _new_val: int) -> void:
	var member := PartyManager.get_member_at(_current_member_index)
	if member == null:
		return
	if stat_id == GameManager.currency_stat_id and _currency_label != null:
		_currency_label.text = _format_currency(member)
		return
	if not _stat_labels.has(stat_id):
		return
	_stat_labels[stat_id].text = _stat_names.get(stat_id, stat_id) + " " + _format_stat_value(member, stat_id)

func _on_class_changed(_class_id: String) -> void:
	_build_stats()

func _on_equip_changed() -> void:
	_build_slots()

func _on_faction_changed(_faction_id: String, _old: int, _new: int) -> void:
	_build_faction_section()

# ── Mouse support ─────────────────────────────────────────────────────────────

func _on_stat_hovered(stat_name: String, description: String) -> void:
	TooltipManager.on_item_hovered({
		"name": stat_name,
		"description": description,
		"charges": null,
		"equipment_type": null,
		"base_damage": null,
		"base_armor": null,
	})

func _on_faction_hovered(faction_name: String, tier_name: String) -> void:
	TooltipManager.on_item_hovered({
		"name": faction_name,
		"description": tier_name,
		"charges": null,
		"equipment_type": null,
		"base_damage": null,
		"base_armor": null,
	})
