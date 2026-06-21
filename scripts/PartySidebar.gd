extends PanelContainer

@onready var party_summary: VBoxContainer = $VBoxContainer/PartySummary

# Exposed for tests: one dict per member in display order.
# Keys: display_name, hp, hp_max, mp, mp_max, status_effects (Array[String]), is_downed
var _displayed_rows: Array[Dictionary] = []
var _row_nodes: Array = []  # VBoxContainer nodes, one per member
var _connected_stat_block: StatBlock = null

const MAX_STATUS_DISPLAY: int = 3

func _ready() -> void:
	GameTime.tick_advanced.connect(_on_tick_advanced)
	PartyManager.member_added.connect(_on_party_changed)
	PartyManager.member_removed.connect(_on_party_changed_by_id)
	PartyManager.member_downed.connect(_on_party_changed_by_id)
	PartyManager.member_revived.connect(_on_party_changed_by_id)
	PartyManager.order_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	# Reconnect to current player stat_block (reference can change on new game/load)
	var player := PartyManager.get_player()
	var current_sb: StatBlock = player.stat_block if player != null else null
	if current_sb != _connected_stat_block:
		if _connected_stat_block != null and _connected_stat_block.stat_changed.is_connected(_on_player_stat_changed):
			_connected_stat_block.stat_changed.disconnect(_on_player_stat_changed)
		_connected_stat_block = current_sb
		if _connected_stat_block != null and not _connected_stat_block.stat_changed.is_connected(_on_player_stat_changed):
			_connected_stat_block.stat_changed.connect(_on_player_stat_changed)

	for node in _row_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_row_nodes.clear()
	_displayed_rows.clear()

	for member in PartyManager.get_all_members():
		var row_data := _build_row_data(member)
		_displayed_rows.append(row_data)
		var row_node := _build_row_node(row_data, member.is_downed)
		party_summary.add_child(row_node)
		_row_nodes.append(row_node)

func _build_row_data(member: PartyMember) -> Dictionary:
	var sb: StatBlock = member.stat_block
	var hp: int = sb.get_value("hp") if sb != null and sb.has_stat("hp") else 0
	var hp_max: int = sb.get_max("hp") if sb != null and sb.has_stat("hp") else 0
	var mp: int = 0
	var mp_max: int = 0
	if sb != null and sb.has_stat("mana"):
		mp = sb.get_value("mana")
		mp_max = sb.get_max("mana")
	var status_effects: Array[String] = []
	if sb != null:
		var count := 0
		for mod in sb.get_active_modifiers():
			if mod.get("is_status_effect", false) and mod.get("is_detrimental", false):
				status_effects.append(mod["name"])
				count += 1
				if count >= MAX_STATUS_DISPLAY:
					break
	return {
		"display_name": member.display_name,
		"hp": hp,
		"hp_max": hp_max,
		"mp": mp,
		"mp_max": mp_max,
		"status_effects": status_effects,
		"is_downed": member.is_downed
	}

func _build_row_node(data: Dictionary, is_downed: bool) -> VBoxContainer:
	var row := VBoxContainer.new()

	var top_line := Label.new()
	var hp_text: String = "%d/%d" % [data["hp"], data["hp_max"]]
	var line: String = "%s    HP: %s" % [data["display_name"], hp_text]
	if data["mp_max"] > 0:
		line += "  MP: %d/%d" % [data["mp"], data["mp_max"]]
	top_line.text = line
	if is_downed:
		top_line.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
	row.add_child(top_line)

	var effects: Array = data["status_effects"]
	if not effects.is_empty():
		var fx_label := Label.new()
		fx_label.text = "  " + ", ".join(effects)
		if is_downed:
			fx_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
		else:
			fx_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4, 1.0))
		row.add_child(fx_label)

	if is_downed:
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		bg.border_color = Color(0.7, 0.1, 0.1, 1.0)
		bg.border_width_left = 2
		bg.border_width_right = 2
		bg.border_width_top = 2
		bg.border_width_bottom = 2
		row.add_theme_stylebox_override("panel", bg)

	return row

func _on_tick_advanced(_total: int) -> void:
	_refresh()

func _on_player_stat_changed(_stat_id: String, _old: int, _new: int) -> void:
	_refresh()

func _on_party_changed(_member: PartyMember) -> void:
	_refresh()

func _on_party_changed_by_id(_member_id: String) -> void:
	_refresh()
