extends PanelContainer

@onready var name_label: Label = $VBoxContainer/StatBlock/NameLabel
@onready var stats_list: VBoxContainer = $VBoxContainer/StatBlock/Columns/StatsList
@onready var modifiers_list: VBoxContainer = $VBoxContainer/StatBlock/Columns/ModifiersList

var _stat_labels: Dictionary = {}  # stat_id -> {label: Label, name: String}

func _ready() -> void:
	name_label.text = PlayerStats.display_name
	_build_stats()
	PlayerStats.stat_block.stat_changed.connect(_on_stat_changed)
	PlayerStats.stat_block.modifier_applied.connect(_on_modifier_event)
	PlayerStats.stat_block.modifier_removed.connect(_on_modifier_event)

func _build_stats() -> void:
	_stat_labels = {}
	for stat in PlayerStats.get_visible_stats():
		var label := Label.new()
		label.name = "stat_" + stat["id"]
		label.text = stat["name"] + ": " + PlayerStats.format_effective_stat(stat["id"])
		stats_list.add_child(label)
		_stat_labels[stat["id"]] = {"label": label, "name": stat["name"]}

func _on_stat_changed(stat_id: String, _old_value: int, _new_value: int) -> void:
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
