class_name ShopPanel
extends CanvasLayer

const CURSOR_COLOR: Color = Color(1.0, 0.75, 0.0)
const GREY_COLOR: Color = Color(0.5, 0.5, 0.5)
const PANEL_W: float = 780.0
const PANEL_H: float = 600.0
const PANEL_LEFT: float = 42.0
const PANEL_TOP: float = 36.0
const ROW_HEIGHT: int = 20
const COL_TYPE_W: float = 100.0
const COL_STOCK_W: float = 70.0
const COL_PRICE_W: float = 80.0

enum Tab { BUY, SELL }

var panel: Panel = null
var _tab_buy_label: Label = null
var _tab_sell_label: Label = null
var _scroll: ScrollContainer = null
var _item_list: VBoxContainer = null
var _detail_label: RichTextLabel = null
var _instruction_label: Label = null

var _current_tab: Tab = Tab.BUY
var _cursor: int = 0
var _buy_rows: Array = []
var _sell_rows: Array = []
var _shop: ShopManager = null

var _in_quantity_mode: bool = false
var _quantity: int = 1
var _quantity_max: int = 1

var _qty_bar: HBoxContainer = null
var _qty_label: Label = null
var _arrow_direction: int = 0
var _arrow_hold_timer: float = 0.0
const ARROW_HOLD_DELAY: float = 0.5
const ARROW_REPEAT_INTERVAL: float = 0.1

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

	var tab_bar := HBoxContainer.new()
	tab_bar.custom_minimum_size.y = 24.0
	_tab_buy_label = Label.new()
	_tab_sell_label = Label.new()
	_tab_buy_label.gui_input.connect(func(event): _on_tab_label_clicked(event, Tab.BUY))
	_tab_sell_label.gui_input.connect(func(event): _on_tab_label_clicked(event, Tab.SELL))
	tab_bar.add_child(_tab_buy_label)
	tab_bar.add_child(_tab_sell_label)
	vbox.add_child(tab_bar)

	var col_header := _make_row_hbox("Name", "Type", "Stock", "Price")
	vbox.add_child(col_header)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_scroll)

	_item_list = VBoxContainer.new()
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_item_list)

	_detail_label = RichTextLabel.new()
	_detail_label.bbcode_enabled = true
	_detail_label.fit_content = true
	_detail_label.scroll_active = false
	_detail_label.custom_minimum_size = Vector2(0.0, 80.0)
	vbox.add_child(_detail_label)

	_qty_bar = HBoxContainer.new()
	_qty_bar.visible = false
	var _arrow_left := Button.new()
	_arrow_left.text = "<"
	_arrow_left.button_down.connect(func(): _on_arrow_button_down(-1))
	_arrow_left.button_up.connect(func(): _on_arrow_button_up())
	_qty_bar.add_child(_arrow_left)
	_qty_label = Label.new()
	_qty_label.text = "1"
	_qty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qty_bar.add_child(_qty_label)
	var _arrow_right := Button.new()
	_arrow_right.text = ">"
	_arrow_right.button_down.connect(func(): _on_arrow_button_down(1))
	_arrow_right.button_up.connect(func(): _on_arrow_button_up())
	_qty_bar.add_child(_arrow_right)
	vbox.add_child(_qty_bar)

	_instruction_label = Label.new()
	vbox.add_child(_instruction_label)

	panel.hide()

func open(shop: ShopManager, _npc_name: String) -> void:
	_shop = shop
	_current_tab = Tab.BUY
	_cursor = 0
	_in_quantity_mode = false
	_quantity = 1
	_build_buy_rows()
	_build_sell_rows()
	_refresh_tab_labels()
	_refresh_list()
	_refresh_detail()
	_instruction_label.text = _get_normal_instructions()
	panel.show()

func close() -> void:
	_shop = null
	_buy_rows = []
	_sell_rows = []
	_in_quantity_mode = false
	_clear_list()
	panel.hide()

# ── row builders ──────────────────────────────────────────────────────────────

func _build_buy_rows() -> void:
	_buy_rows = []
	if _shop == null:
		return
	for item in _shop.get_inventory():
		var object_id: String = str(item.get("object_id", ""))
		var data: Dictionary = Inventory.get_object_definition(object_id)
		var stock_count: int = item.get("stock_count", 0)
		_buy_rows.append({
			"object_id":    object_id,
			"display_name": Inventory.get_item_display_name(data),
			"type":         str(data.get("type", "")),
			"stock_count":  stock_count,
			"buy_price":    item.get("buy_price", 0),
			"sell_price":   item.get("sell_price", 0),
			"selectable":   stock_count != 0
		})
	_buy_rows.sort_custom(func(a, b):
		if a["type"] != b["type"]:
			return a["type"] < b["type"]
		return a["display_name"] < b["display_name"]
	)

func _build_sell_rows() -> void:
	_sell_rows = []
	if _shop == null:
		return
	for obj in PlayerInventory.get_objects():
		var object_id: String = str(obj.get("object_id", ""))
		var sell_price: int = _shop.get_sell_price(object_id)
		if sell_price == 0:
			continue
		var data: Dictionary = obj.get("data", {})
		_sell_rows.append({
			"object_id":    object_id,
			"instance_id":  int(obj.get("instance_id", -1)),
			"display_name": Inventory.get_item_display_name(data),
			"type":         str(data.get("type", "")),
			"stack_count":  int(obj.get("stack_count", 1)),
			"sell_price":   sell_price,
			"selectable":   true
		})
	_sell_rows.sort_custom(func(a, b):
		if a["type"] != b["type"]:
			return a["type"] < b["type"]
		return a["display_name"] < b["display_name"]
	)

func _current_rows() -> Array:
	return _buy_rows if _current_tab == Tab.BUY else _sell_rows

# ── display refresh ───────────────────────────────────────────────────────────

func _refresh_tab_labels() -> void:
	if _current_tab == Tab.BUY:
		_tab_buy_label.text = "[ Buy ]"
		_tab_sell_label.text = "   Sell   "
	else:
		_tab_buy_label.text = "   Buy   "
		_tab_sell_label.text = "[ Sell ]"

func _refresh_list() -> void:
	_clear_list()
	var rows := _current_rows()
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var selectable: bool = row.get("selectable", true)
		var stock_str: String
		var price_str: String
		if _current_tab == Tab.BUY:
			var s: int = row.get("stock_count", 0)
			stock_str = "--" if s == -1 else str(s)
			price_str = str(row.get("buy_price", 0)) + "g"
		else:
			stock_str = str(row.get("stack_count", 1))
			price_str = str(row.get("sell_price", 0)) + "g"
		var hbox := _make_row_hbox(
			str(row.get("display_name", "")),
			str(row.get("type", "")),
			stock_str,
			price_str
		)
		if not selectable:
			Constants.set_hbox_color(hbox, GREY_COLOR)
		var captured_i := i
		hbox.gui_input.connect(func(event): _on_row_gui_input(event, captured_i))
		hbox.mouse_entered.connect(func(): _on_row_mouse_entered(rows[captured_i]))
		hbox.mouse_exited.connect(func(): TooltipManager.on_item_unhovered())
		_item_list.add_child(hbox)
	_refresh_cursor()
	_scroll_to_cursor()

func _refresh_detail() -> void:
	_detail_label.clear()
	var rows := _current_rows()
	if rows.is_empty() or _cursor >= rows.size():
		return
	var row: Dictionary = rows[_cursor]
	var data: Dictionary = Inventory.get_object_definition(str(row.get("object_id", "")))
	var desc: String = str(data.get("description", ""))
	if not desc.is_empty():
		_detail_label.append_text(desc + "\n")
	if GameManager.class_registry != null:
		var eq_type: String = str(data.get("equipment_type", ""))
		if not eq_type.is_empty() and eq_type != "null":
			var usable: Array = []
			for class_id in GameManager.class_registry.get_all_class_ids():
				if eq_type in GameManager.class_registry.get_equipment_whitelist(class_id):
					var cd: Dictionary = GameManager.class_registry.get_class_data(class_id)
					usable.append(str(cd.get("name", class_id)))
			if not usable.is_empty():
				_detail_label.append_text("Usable by: " + ", ".join(usable))

# ── row helpers ───────────────────────────────────────────────────────────────

func _make_row_hbox(name_text: String, type_text: String, stock_text: String, price_text: String) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size.y = float(ROW_HEIGHT)

	var name_lbl := Label.new()
	name_lbl.text = name_text
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	hbox.add_child(name_lbl)

	var type_lbl := Label.new()
	type_lbl.text = type_text
	type_lbl.custom_minimum_size.x = COL_TYPE_W
	hbox.add_child(type_lbl)

	var stock_lbl := Label.new()
	stock_lbl.text = stock_text
	stock_lbl.custom_minimum_size.x = COL_STOCK_W
	stock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(stock_lbl)

	var price_lbl := Label.new()
	price_lbl.text = price_text
	price_lbl.custom_minimum_size.x = COL_PRICE_W
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(price_lbl)

	return hbox

func _clear_list() -> void:
	for child in _item_list.get_children():
		child.free()

func _refresh_cursor() -> void:
	var children := _item_list.get_children()
	var rows := _current_rows()
	for i in range(children.size()):
		var hbox := children[i] as HBoxContainer
		if hbox == null:
			continue
		var selectable: bool = rows[i].get("selectable", true) if i < rows.size() else true
		if i == _cursor:
			Constants.set_hbox_color(hbox, CURSOR_COLOR)
		elif not selectable:
			Constants.set_hbox_color(hbox, GREY_COLOR)
		else:
			Constants.clear_hbox_color(hbox)

func _scroll_to_cursor() -> void:
	_do_scroll_to_cursor.call_deferred()

func _do_scroll_to_cursor() -> void:
	if not panel.visible:
		return
	Constants.scroll_list_to_row(_scroll, _item_list, _cursor)

# ── input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible:
		return

	if _in_quantity_mode:
		if event.is_action_pressed("move_left"):
			_quantity = maxi(1, _quantity - 1)
			_update_quantity_label()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("move_right"):
			_quantity = mini(_quantity_max, _quantity + 1)
			_update_quantity_label()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept"):
			_confirm_transaction()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel"):
			_exit_quantity_mode()
			get_viewport().set_input_as_handled()
		else:
			get_viewport().set_input_as_handled()
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
	elif event.is_action_pressed("move_left"):
		_switch_tab(Tab.BUY)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		_switch_tab(Tab.SELL)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_enter_quantity_mode()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		close()
		# Fall through: let Player.gd open inventory

# ── navigation and tab switching ──────────────────────────────────────────────

func _navigate(delta: int) -> void:
	var rows := _current_rows()
	if rows.is_empty():
		return
	_cursor = posmod(_cursor + delta, rows.size())
	_refresh_cursor()
	_scroll_to_cursor()
	_refresh_detail()

func _switch_tab(tab: Tab) -> void:
	if _current_tab == tab:
		return
	_current_tab = tab
	_cursor = 0
	_refresh_tab_labels()
	_refresh_list()
	_refresh_detail()
	_instruction_label.text = _get_normal_instructions()

# ── quantity mode ─────────────────────────────────────────────────────────────

func _enter_quantity_mode() -> void:
	var rows := _current_rows()
	if rows.is_empty():
		return
	var row: Dictionary = rows[_cursor]
	if not row.get("selectable", true):
		return

	if _current_tab == Tab.BUY:
		var stock: int = row.get("stock_count", 0)
		var buy_price: int = row.get("buy_price", 1)
		var gold: int = PlayerStats.get_effective_value(GameManager.currency_stat_id)
		var max_affordable: int = floori(float(gold) / float(buy_price)) if buy_price > 0 else 0
		_quantity_max = mini(stock, max_affordable) if stock != -1 else max_affordable
		if _quantity_max <= 0:
			MessageLog.post(MessageRegistry.get_message("shop_cannot_afford"))
			MessageLog.post_blank()
			return
	else:
		_quantity_max = row.get("stack_count", 1)

	_quantity = 1
	_in_quantity_mode = true
	_qty_bar.visible = true
	_update_quantity_label()

func _update_quantity_label() -> void:
	var rows := _current_rows()
	if _cursor >= rows.size():
		return
	var row: Dictionary = rows[_cursor]
	if _current_tab == Tab.BUY:
		var total: int = row.get("buy_price", 0) * _quantity
		_instruction_label.text = MessageRegistry.get_message("shop_instructions_buy_qty", {"quantity": _quantity, "price": total})
	else:
		var total: int = row.get("sell_price", 0) * _quantity
		_instruction_label.text = MessageRegistry.get_message("shop_instructions_sell_qty", {"quantity": _quantity, "price": total})
	if _qty_label != null:
		_qty_label.text = str(_quantity)

func _exit_quantity_mode() -> void:
	_in_quantity_mode = false
	_arrow_direction = 0
	_arrow_hold_timer = 0.0
	_qty_bar.visible = false
	_instruction_label.text = _get_normal_instructions()

func _confirm_transaction() -> void:
	if _current_tab == Tab.BUY:
		_do_buy()
	else:
		_do_sell()
	_exit_quantity_mode()

# ── transactions ──────────────────────────────────────────────────────────────

func _do_buy() -> void:
	if _buy_rows.is_empty() or _cursor >= _buy_rows.size():
		return
	var row: Dictionary = _buy_rows[_cursor]
	var object_id: String = str(row.get("object_id", ""))
	var buy_price: int = row.get("buy_price", 0)
	var total_cost: int = buy_price * _quantity

	var gold: int = PlayerStats.get_effective_value(GameManager.currency_stat_id)
	if gold < total_cost:
		MessageLog.post(MessageRegistry.get_message("shop_cannot_afford"))
		MessageLog.post_blank()
		return

	if PlayerInventory.would_exceed_carry_limit_for(object_id, _quantity):
		MessageLog.post(MessageRegistry.get_message("shop_carry_limit"))
		MessageLog.post_blank()
		return

	var stock: int = row.get("stock_count", 0)
	if stock != -1 and _quantity > stock:
		MessageLog.post(MessageRegistry.get_message("shop_out_of_stock"))
		MessageLog.post_blank()
		return

	PlayerStats.modify_stat(GameManager.currency_stat_id, -total_cost)
	PlayerInventory.add_stacked(object_id, _quantity)
	if _shop != null:
		_shop.deplete_stock(object_id, _quantity)

	MessageLog.post(MessageRegistry.get_message("shop_buy_success", {
		"count": str(_quantity), "name": str(row.get("display_name", object_id)), "price": str(total_cost)
	}))
	MessageLog.post_blank()

	_build_buy_rows()
	_cursor = clampi(_cursor, 0, maxi(0, _buy_rows.size() - 1))
	_refresh_list()
	_refresh_detail()

func _do_sell() -> void:
	if _sell_rows.is_empty() or _cursor >= _sell_rows.size():
		return
	var row: Dictionary = _sell_rows[_cursor]
	var instance_id: int = int(row.get("instance_id", -1))
	if instance_id == -1:
		return
	var sell_price: int = row.get("sell_price", 0)
	var total: int = sell_price * _quantity

	PlayerInventory.take_from_stack(instance_id, _quantity)
	PlayerStats.modify_stat(GameManager.currency_stat_id, total)

	MessageLog.post(MessageRegistry.get_message("shop_sell_success", {
		"count": str(_quantity), "name": str(row.get("display_name", "")), "price": str(total)
	}))
	MessageLog.post_blank()

	_build_sell_rows()
	_cursor = clampi(_cursor, 0, maxi(0, _sell_rows.size() - 1))
	_refresh_list()
	_refresh_detail()

func _get_normal_instructions() -> String:
	return MessageRegistry.get_message("shop_instructions_normal")

# ── Mouse support ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _arrow_direction == 0 or not _in_quantity_mode:
		return
	_arrow_hold_timer += delta
	if _arrow_hold_timer >= ARROW_HOLD_DELAY:
		_arrow_hold_timer -= ARROW_REPEAT_INTERVAL
		_apply_arrow(_arrow_direction)

func _on_arrow_button_down(direction: int) -> void:
	_arrow_direction = direction
	_arrow_hold_timer = 0.0
	_apply_arrow(direction)

func _on_arrow_button_up() -> void:
	_arrow_direction = 0
	_arrow_hold_timer = 0.0

func _apply_arrow(direction: int) -> void:
	if direction < 0:
		_quantity = maxi(1, _quantity - 1)
	else:
		_quantity = mini(_quantity_max, _quantity + 1)
	_update_quantity_label()

func _on_tab_label_clicked(event: InputEvent, tab: Tab) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	_switch_tab(tab)

func _on_row_gui_input(event: InputEvent, row_index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	if _in_quantity_mode:
		return
	var rows := _current_rows()
	if row_index >= rows.size() or not rows[row_index].get("selectable", true):
		return
	if _cursor == row_index:
		_enter_quantity_mode()
	else:
		_cursor = row_index
		_refresh_cursor()
		_scroll_to_cursor()
		_refresh_detail()

func _on_row_mouse_entered(row: Dictionary) -> void:
	var object_id: String = str(row.get("object_id", ""))
	var data: Dictionary = Inventory.get_object_definition(object_id)
	TooltipManager.on_item_hovered({
		"name": str(row.get("display_name", "")),
		"description": str(data.get("description", "")),
		"charges": null,
		"equipment_type": data.get("equip_type", null),
		"base_damage": data.get("base_damage", null),
		"base_armor": data.get("base_armor", null),
	})
