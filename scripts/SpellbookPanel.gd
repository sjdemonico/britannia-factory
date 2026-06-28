extends CanvasLayer

const TARGETING_DISPLAY: Dictionary = {
	"targeted": "Targeted",
	"point_blank": "Point Blank",
	"directed": "Directed",
	"self": "Self",
	"none": "No Target"
}

const CONTEXT_DISPLAY: Dictionary = {
	"any": "Anywhere",
	"combat": "In combat only",
	"world": "Outside combat only"
}

const SELECTED_COLOR: Color = Color(1.0, 1.0, 0.6, 1.0)
const RED_COLOR: Color = Color(1.0, 0.3, 0.3, 1.0)

@onready var panel: Panel = $Panel
@onready var spell_list: VBoxContainer = $Panel/Content/SpellScroll/SpellList
@onready var _spell_scroll_cont: ScrollContainer = $Panel/Content/SpellScroll
@onready var detail_container: VBoxContainer = $Panel/Content/DetailScroll/DetailContainer

var _known: Array[Dictionary] = []
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
	_known = SpellManager.get_known_spells()
	_known.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")) < str(b.get("name", "")))
	_cursor = clampi(_cursor, 0, maxi(0, _known.size() - 1))
	_rebuild_list()
	_refresh_detail()

func _scroll_to_cursor() -> void:
	if _known.is_empty():
		return
	_do_scroll_to_cursor.call_deferred()

func _do_scroll_to_cursor() -> void:
	if not panel.visible:
		return
	Constants.scroll_list_to_row(_spell_scroll_cont, spell_list, _cursor)

func _rebuild_list() -> void:
	for child in spell_list.get_children():
		child.free()
	if _known.is_empty():
		var empty_label := Label.new()
		empty_label.text = MessageRegistry.get_message("spellbook_empty")
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		spell_list.add_child(empty_label)
		return
	for i in range(_known.size()):
		var label := Label.new()
		label.text = str(_known[i].get("name", ""))
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		if i == _cursor:
			label.add_theme_color_override("font_color", SELECTED_COLOR)
		var captured_i := i
		label.gui_input.connect(func(event): _on_row_gui_input(event, captured_i))
		label.mouse_entered.connect(func(): _on_row_mouse_entered(_known[captured_i]))
		label.mouse_exited.connect(func(): TooltipManager.on_item_unhovered())
		spell_list.add_child(label)
	_scroll_to_cursor()

func _refresh_detail() -> void:
	for child in detail_container.get_children():
		child.free()
	if _known.is_empty() or _cursor >= _known.size():
		return

	var spell: Dictionary = _known[_cursor]
	var spell_id: String = str(spell.get("spell_id", ""))

	var name_label := Label.new()
	name_label.text = str(spell.get("name", ""))
	name_label.add_theme_font_size_override("font_size", 16)
	detail_container.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = str(spell.get("description", ""))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_container.add_child(desc_label)

	var casting_stat: String = SpellManager.get_casting_stat(spell_id)
	var casting_cost: int = int(spell.get("casting_cost", 0))
	var current_stat_value: int = PlayerStats.get_effective_value(casting_stat)
	var stat_display_name: String = PlayerStats.get_stat_display_name(casting_stat)

	var cost_label := Label.new()
	cost_label.text = stat_display_name + ": " + str(casting_cost)
	if current_stat_value < casting_cost:
		cost_label.add_theme_color_override("font_color", RED_COLOR)
	detail_container.add_child(cost_label)

	var reagents_raw: Variant = spell.get("reagents", [])
	if reagents_raw is Array and not (reagents_raw as Array).is_empty():
		for reagent_id_raw in (reagents_raw as Array):
			var rid: String = str(reagent_id_raw)
			var reagent_data: Dictionary = PlayerInventory.get_object_data(rid)
			var reagent_name: String = str(reagent_data.get("name", rid))
			var count_have: int = _count_in_inventory(rid)
			var reagent_label := Label.new()
			reagent_label.text = reagent_name + ": " + str(count_have) + " / 1"
			if count_have < 1:
				reagent_label.add_theme_color_override("font_color", RED_COLOR)
			detail_container.add_child(reagent_label)
	else:
		var no_req_label := Label.new()
		no_req_label.text = "No reagents required."
		detail_container.add_child(no_req_label)

	var targeting_display: String = TARGETING_DISPLAY.get(str(spell.get("targeting_type", "")), str(spell.get("targeting_type", "")))
	var targeting_label := Label.new()
	targeting_label.text = "Targeting: " + targeting_display
	detail_container.add_child(targeting_label)

	var spell_context: String = str(spell.get("context", "any"))
	var context_display: String = CONTEXT_DISPLAY.get(spell_context, spell_context)
	var context_label := Label.new()
	context_label.text = "Usable: " + context_display
	detail_container.add_child(context_label)

	var div := ColorRect.new()
	div.color = Color(0.4, 0.4, 0.4, 1.0)
	div.custom_minimum_size = Vector2(0, 1)
	detail_container.add_child(div)

	var current_context: String = "combat" if CombatManager.in_combat else "world"
	var cast_label := Label.new()
	if SpellManager.can_cast(spell_id, current_context):
		cast_label.text = "Press Enter to cast."
	else:
		cast_label.text = "Cannot cast: " + _get_cannot_cast_reason(spell_id, current_context)
		cast_label.add_theme_color_override("font_color", RED_COLOR)
	detail_container.add_child(cast_label)

func _get_cannot_cast_reason(spell_id: String, current_context: String) -> String:
	var spell: Dictionary = SpellManager.get_spell(spell_id)
	var spell_context: String = str(spell.get("context", "any"))
	if spell_context != "any" and spell_context != current_context:
		return MessageRegistry.get_message("spell_wrong_context")
	var casting_stat: String = SpellManager.get_casting_stat(spell_id)
	var casting_cost: int = int(spell.get("casting_cost", 0))
	var stat_display_name: String = PlayerStats.get_stat_display_name(casting_stat)
	var insufficient_stat: bool = PlayerStats.get_effective_value(casting_stat) < casting_cost
	var missing_reagents: bool = not SpellManager.get_missing_reagents(spell_id).is_empty()
	if insufficient_stat and missing_reagents:
		return "Not enough " + stat_display_name + " and missing reagents."
	if insufficient_stat:
		return MessageRegistry.get_message("spell_insufficient_stat", {"stat": stat_display_name})
	return MessageRegistry.get_message("spell_missing_reagents")

func _count_in_inventory(object_id: String) -> int:
	var inv: Inventory = PlayerInventory.get_inventory()
	var total: int = 0
	for obj in inv.get_objects():
		if str(obj.get("object_id", "")) == object_id:
			total += int(obj.get("stack_count", 1))
	return total

func _move_cursor(delta: int) -> void:
	if _known.is_empty():
		return
	_cursor = posmod(_cursor + delta, _known.size())
	_rebuild_list()
	_refresh_detail()

func _attempt_cast() -> void:
	if _known.is_empty() or _cursor >= _known.size():
		return
	var spell_id: String = str(_known[_cursor].get("spell_id", ""))
	var current_context: String = "combat" if CombatManager.in_combat else "world"
	if not SpellManager.can_cast(spell_id, current_context):
		return
	close()
	SpellManager.cast_spell(spell_id)

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
		return
	if event.is_action_pressed("ui_down"):
		_move_cursor(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_spellbook"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cast_spell") or event.is_action_pressed("ui_accept"):
		_attempt_cast()
		get_viewport().set_input_as_handled()
		return

# ── Mouse support ─────────────────────────────────────────────────────────────

func _on_row_gui_input(event: InputEvent, row_index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	if _cursor == row_index:
		_attempt_cast()
	else:
		_cursor = row_index
		call_deferred("_rebuild_list")
		call_deferred("_refresh_detail")

func _on_row_mouse_entered(spell: Dictionary) -> void:
	TooltipManager.on_item_hovered({
		"name": str(spell.get("name", "")),
		"description": str(spell.get("description", "")),
		"charges": null,
		"equipment_type": null,
		"base_damage": null,
		"base_armor": null,
	})
