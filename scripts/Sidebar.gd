extends PanelContainer

@onready var name_label: Label = $VBoxContainer/StatBlock/NameLabel
@onready var stats_list: VBoxContainer = $VBoxContainer/StatBlock/Columns/StatsList
@onready var modifiers_list: VBoxContainer = $VBoxContainer/StatBlock/Columns/ModifiersList

var _stat_labels: Dictionary = {}  # stat_id -> {label: Label, name: String}
var _class_label: Label = null
var _currency_label: Label = null

func _ready() -> void:
	name_label.text = PlayerStats.display_name
	var stat_block_node: Node = name_label.get_parent()
	_class_label = Label.new()
	_class_label.text = PlayerStats.get_class_display_name()
	stat_block_node.add_child(_class_label)
	stat_block_node.move_child(_class_label, name_label.get_index() + 1)
	_currency_label = Label.new()
	_currency_label.text = _format_currency()
	stat_block_node.add_child(_currency_label)
	stat_block_node.move_child(_currency_label, _class_label.get_index() + 1)
	_build_stats()
	PlayerStats.stat_changed.connect(_on_stat_changed)
	PlayerStats.stat_block.modifier_applied.connect(_on_modifier_event)
	PlayerStats.stat_block.modifier_removed.connect(_on_modifier_event)
	PlayerStats.class_changed.connect(_on_class_changed)
	PlayerStats.name_changed.connect(func(new_name: String) -> void:
		name_label.text = new_name)

func _build_stats() -> void:
	_stat_labels = {}
	for stat in PlayerStats.get_visible_stats():
		var label := Label.new()
		label.name = "stat_" + stat["id"]
		label.text = stat["name"] + ": " + PlayerStats.format_effective_stat(stat["id"])
		stats_list.add_child(label)
		_stat_labels[stat["id"]] = {"label": label, "name": stat["name"]}

func _format_currency() -> String:
	var stat_id: String = GameManager.currency_stat_id
	if stat_id.is_empty() or not PlayerStats.has_stat(stat_id):
		return ""
	return str(PlayerStats.get_effective_value(stat_id)) + " " + GameManager.currency_display_name

func _on_stat_changed(stat_id: String, _old_value: int, _new_value: int) -> void:
	if stat_id == GameManager.currency_stat_id:
		_currency_label.text = _format_currency()
		return
	if not _stat_labels.has(stat_id):
		return
	var entry: Dictionary = _stat_labels[stat_id]
	entry["label"].text = entry["name"] + ": " + PlayerStats.format_effective_stat(stat_id)

func _on_modifier_event(_modifier_id: String, _instance_id: int) -> void:
	refresh_stats()
	_rebuild_modifier_labels()

func _rebuild_modifier_labels() -> void:
	var children: Array = modifiers_list.get_children()
	for child in children:
		modifiers_list.remove_child(child)
		child.free()
	var equipped_sources: Dictionary = {}
	for item in PlayerInventory.get_equipped_items():
		equipped_sources[item["object_id"]] = true
	for mod in PlayerStats.get_active_modifiers():
		if equipped_sources.has(mod["source_tag"]):
			continue
		if not mod.get("stat_visible", true):
			continue
		var label := Label.new()
		label.text = mod["name"]
		modifiers_list.add_child(label)

func refresh_stats() -> void:
	for stat_id in _stat_labels:
		var entry: Dictionary = _stat_labels[stat_id]
		entry["label"].text = entry["name"] + ": " + PlayerStats.format_effective_stat(stat_id)

func _on_class_changed(_class_id: String) -> void:
	_class_label.text = PlayerStats.get_class_display_name()
