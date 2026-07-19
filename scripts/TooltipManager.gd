extends Node

var _tooltip_node: Tooltip = null
var _canvas_layer: CanvasLayer = null
var _hover_timer: float = 0.0
var _hover_delay: float = 1.0
var _pending_content: Dictionary = {}
var _active: bool = false


func _ready() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 100
	add_child(_canvas_layer)

	var tooltip_scene := load("res://scenes/ui/Tooltip.tscn") as PackedScene
	if tooltip_scene == null:
		push_error("TooltipManager: could not load Tooltip.tscn")
		return
	_tooltip_node = tooltip_scene.instantiate() as Tooltip
	_tooltip_node.visible = false
	_canvas_layer.add_child(_tooltip_node)


func _process(delta: float) -> void:
	if not _active:
		return
	_hover_timer += delta
	if _hover_timer >= _hover_delay:
		show_tooltip()


func on_item_hovered(content: Dictionary) -> void:
	_pending_content = content
	_hover_timer = 0.0
	_active = true


func on_item_unhovered() -> void:
	_hover_timer = 0.0
	_active = false
	hide_tooltip()


func show_tooltip() -> void:
	if _tooltip_node == null:
		return
	_tooltip_node.populate(_pending_content)
	_tooltip_node.visible = true
	call_deferred("_position_tooltip")


func hide_tooltip() -> void:
	if _tooltip_node == null:
		return
	_tooltip_node.clear_sprite()
	_tooltip_node.visible = false


func _position_tooltip() -> void:
	if _tooltip_node == null:
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var tooltip_size := _tooltip_node.size
	var vp_size := get_viewport().get_visible_rect().size
	_tooltip_node.position = _compute_position(mouse_pos, tooltip_size, vp_size)


func _compute_position(mouse_pos: Vector2, tooltip_size: Vector2, vp_size: Vector2) -> Vector2:
	var offset := Vector2(8.0, 8.0)
	var pos := mouse_pos + offset
	if pos.x + tooltip_size.x > vp_size.x:
		pos.x = mouse_pos.x - tooltip_size.x - offset.x
	if pos.y + tooltip_size.y > vp_size.y:
		pos.y = mouse_pos.y - tooltip_size.y - offset.y
	return pos


func on_tile_hovered(tile: Vector2i) -> void:
	var content: Dictionary = _build_tile_tooltip(tile)
	if content.is_empty():
		on_item_unhovered()
		return
	on_item_hovered(content)


func _build_tile_tooltip(tile: Vector2i) -> Dictionary:
	if tile == GameManager.player_tile:
		return {}
	var tile_type_id: String = GameManager.get_world_tile_type(tile)
	if tile_type_id.is_empty():
		return {}

	var npc = WorldState.get_npc_at_tile(tile)
	if npc != null:
		return _tooltip_entry((npc as NPC).display_name, "")

	var world_objects: Array = GameManager.get_objects_at(tile)
	for wo in world_objects:
		var obj := wo as WorldObject
		if obj.object_type == "structural":
			var label: String = obj.get_display_name()
			if obj.toggleable:
				label += " (" + MessageRegistry.get_message("look_is_open" if obj.is_open else "look_is_closed") + ")"
			return _tooltip_entry(label, "")

	var desc_parts: Array[String] = []
	for wo in world_objects:
		var obj := wo as WorldObject
		if obj == null:
			continue
		desc_parts.append(obj.get_display_name())
	return _tooltip_entry(tile_type_id.capitalize(),
		"\n".join(PackedStringArray(desc_parts)) if not desc_parts.is_empty() else "")


func _tooltip_entry(label: String, description: String) -> Dictionary:
	return {
		"name": label,
		"description": description,
		"charges": null,
		"equipment_type": null,
		"base_damage": null,
		"base_armor": null,
	}
