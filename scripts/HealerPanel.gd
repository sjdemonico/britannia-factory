class_name HealerPanel
extends CanvasLayer

const CURSOR_COLOR: Color = Color(1.0, 0.75, 0.0)
const GREY_COLOR: Color = Color(0.5, 0.5, 0.5)
const PANEL_W: float = 500.0
const PANEL_H: float = 380.0
const PANEL_LEFT: float = 182.0
const PANEL_TOP: float = 110.0
const ROW_HEIGHT: int = 24

var panel: Panel = null
var _title_label: Label = null
var _item_list: VBoxContainer = null
var _gold_label: Label = null
var _instruction_label: Label = null

var _cursor: int = 0
var _rows: Array = []
var _service: HealerService = null

func _ready() -> void:
	panel = Panel.new()
	panel.offset_left = PANEL_LEFT
	panel.offset_top = PANEL_TOP
	panel.offset_right = PANEL_LEFT + PANEL_W
	panel.offset_bottom = PANEL_TOP + PANEL_H
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	_item_list = VBoxContainer.new()
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_item_list)

	_gold_label = Label.new()
	vbox.add_child(_gold_label)

	_instruction_label = Label.new()
	_instruction_label.text = MessageRegistry.get_message("healer_instructions_normal")
	vbox.add_child(_instruction_label)

	panel.hide()

func open(service: HealerService, npc_name: String) -> void:
	_service = service
	_cursor = 0
	_title_label.text = "=== " + npc_name + " ==="
	_build_rows()
	_refresh_list()
	_refresh_gold()
	panel.show()

func close() -> void:
	_service = null
	_rows = []
	_clear_list()
	panel.hide()

func _build_rows() -> void:
	_rows = []
	if _service == null:
		return
	var gold: int = PlayerStats.get_effective_value(GameManager.currency_stat_id)
	_rows.append({
		"id": "heal_all",
		"label": "Heal All Party",
		"price": _service.heal_all_price,
		"selectable": gold >= _service.heal_all_price
	})
	_rows.append({
		"id": "cure_all",
		"label": "Cure All Status Effects",
		"price": _service.cure_all_price,
		"selectable": gold >= _service.cure_all_price
	})
	for m in PartyManager.get_downed_members():
		var cost: int = _service.resurrect_price
		_rows.append({
			"id": "resurrect",
			"member_id": m.member_id,
			"label": "Resurrect " + m.display_name,
			"price": cost,
			"selectable": gold >= cost
		})

func _refresh_list() -> void:
	_clear_list()
	for i in range(_rows.size()):
		var row: Dictionary = _rows[i]
		var hbox := HBoxContainer.new()
		hbox.custom_minimum_size.y = float(ROW_HEIGHT)
		var name_lbl := Label.new()
		name_lbl.text = str(row.get("label", ""))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(name_lbl)
		var price_lbl := Label.new()
		price_lbl.text = str(row.get("price", 0)) + "g"
		price_lbl.custom_minimum_size.x = 80.0
		price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(price_lbl)
		if not row.get("selectable", true):
			Constants.set_hbox_color(hbox, GREY_COLOR)
		var captured_i := i
		hbox.gui_input.connect(func(event): _on_row_gui_input(event, captured_i))
		hbox.mouse_entered.connect(func(): _on_row_mouse_entered(_rows[captured_i]))
		hbox.mouse_exited.connect(func(): TooltipManager.on_item_unhovered())
		_item_list.add_child(hbox)
	_refresh_cursor()

func _refresh_cursor() -> void:
	var children := _item_list.get_children()
	for i in range(children.size()):
		var hbox := children[i] as HBoxContainer
		if hbox == null:
			continue
		var selectable: bool = _rows[i].get("selectable", true) if i < _rows.size() else true
		if i == _cursor:
			Constants.set_hbox_color(hbox, CURSOR_COLOR)
		elif not selectable:
			Constants.set_hbox_color(hbox, GREY_COLOR)
		else:
			Constants.clear_hbox_color(hbox)

func _refresh_gold() -> void:
	var gold: int = PlayerStats.get_effective_value(GameManager.currency_stat_id)
	_gold_label.text = "Current %s: %d" % [GameManager.currency_display_name, gold]

func _clear_list() -> void:
	for child in _item_list.get_children():
		child.free()

func _navigate(delta: int) -> void:
	if _rows.is_empty():
		return
	_cursor = posmod(_cursor + delta, _rows.size())
	_refresh_cursor()

func _purchase() -> void:
	if _rows.is_empty() or _cursor >= _rows.size():
		return
	var row: Dictionary = _rows[_cursor]
	if not row.get("selectable", true):
		MessageLog.post(MessageRegistry.get_message("shop_cannot_afford"))
		MessageLog.post_blank()
		return
	var price: int = row.get("price", 0)
	var gold: int = PlayerStats.get_effective_value(GameManager.currency_stat_id)
	if gold < price:
		MessageLog.post(MessageRegistry.get_message("shop_cannot_afford"))
		MessageLog.post_blank()
		return
	PlayerStats.modify_stat(GameManager.currency_stat_id, -price)
	match str(row.get("id", "")):
		"heal_all":
			for m in PartyManager.get_living_members():
				m.stat_block.set_stat("hp", m.stat_block.get_max("hp"))
			MessageLog.post(MessageRegistry.get_message("healer_service_heal_all"))
			MessageLog.post_blank()
		"cure_all":
			for m in PartyManager.get_all_members():
				m.stat_block.remove_all_status_effects()
			MessageLog.post(MessageRegistry.get_message("healer_service_cure_all"))
			MessageLog.post_blank()
		"resurrect":
			var member_id: String = str(row.get("member_id", ""))
			var m: PartyMember = PartyManager.get_member(member_id)
			if m != null:
				PartyManager.revive_member(member_id)
				MessageLog.post(MessageRegistry.get_message("resurrect_success", {"name": m.display_name}))
				MessageLog.post_blank()
	_build_rows()
	_cursor = clampi(_cursor, 0, maxi(0, _rows.size() - 1))
	_refresh_list()
	_refresh_gold()

func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_up"):
		_navigate(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_navigate(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_purchase()
		get_viewport().set_input_as_handled()

# ── Mouse support ─────────────────────────────────────────────────────────────

func _on_row_gui_input(event: InputEvent, row_index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	if row_index >= _rows.size() or not _rows[row_index].get("selectable", true):
		return
	if _cursor == row_index:
		call_deferred("_purchase")
	else:
		_cursor = row_index
		_refresh_cursor()

func _on_row_mouse_entered(row: Dictionary) -> void:
	TooltipManager.on_item_hovered({
		"name": str(row.get("label", "")),
		"description": "%dg" % row.get("price", 0),
		"charges": null,
		"equipment_type": null,
		"base_damage": null,
		"base_armor": null,
	})
