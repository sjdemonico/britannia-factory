class_name WorldObject
extends Node2D

@export var object_id: String = ""
@export var object_tile: Vector2i = Vector2i.ZERO
@export var stat_def_path: String = ""

var instance_display_name: String = ""
var instance_id: String = ""
var targets: Array = []
var passable: bool = true
var movable: bool = true
var transparent: bool = true
var carriable: bool = true
var toggleable: bool = false
var is_open: bool = false
var structural: bool = false
var surface_name: String = ""
var use_actions: Array = []
var charges: int = -1
var is_container: bool = false
var container_slots: int = 0  # -1 = unlimited
var container_open: bool = false
var _content_ids: Array = []
var stat_block: StatBlock
var weight: float = 0.0
var equippable: bool = false
var equip_slots: Array = []
var equipped: bool = false
var stack_count: int = 1
var draw_style: String = ""
var readable_source: String = ""
var light_radius: int = 0
var is_lit: bool = false
var duration_remaining: int = -1

func _ready() -> void:
	var data := PlayerInventory.get_object_data(object_id)
	passable = data.get("passable", true)
	movable = data.get("movable", true)
	transparent = data.get("transparent", true)
	carriable = data.get("carriable", true)
	var raw_actions = data.get("use_actions")
	if raw_actions is Array:
		use_actions = raw_actions.duplicate()
	var raw_charges = data.get("charges")
	charges = int(raw_charges) if raw_charges != null else -1
	toggleable = data.get("toggleable", false)
	structural = data.get("structural", false)
	var raw_surface = data.get("surface_name")
	surface_name = raw_surface if raw_surface is String else ""
	var raw_draw_style = data.get("draw_style")
	draw_style = raw_draw_style if raw_draw_style is String else ""
	var raw_readable = data.get("readable_source")
	readable_source = raw_readable if raw_readable is String else ""
	weight = data.get("weight", 0.0)
	equippable = data.get("equippable", false)
	if equippable:
		var raw_slots = data.get("equip_slots")
		if raw_slots is Array:
			for slot_id in raw_slots:
				var sid := str(slot_id)
				if GameManager.slot_registry != null and not GameManager.slot_registry.has_slot(sid):
					push_warning("WorldObject: unrecognized equip_slot '" + sid + "' on object '" + object_id + "'. Slot will be ignored.")
				else:
					equip_slots.append(sid)
	is_container = data.get("container", false)
	var _raw_slots = data.get("container_slots", 0)
	container_slots = int(_raw_slots) if _raw_slots != null else -1
	container_open = false
	if is_container:
		_content_ids = data.get("container_contents", []).duplicate()
	var sprite: Sprite2D = $Sprite2D
	if sprite != null:
		if toggleable or not draw_style.is_empty():
			sprite.hide()
		elif object_id == "corpse":
			sprite.texture = load(Constants.SPRITE_CORPSE_PATH)
		elif carriable:
			sprite.texture = load(Constants.SPRITE_CARRIABLE_PATH)
		else:
			sprite.texture = load(Constants.SPRITE_NONCARRIABLE_PATH)
	var raw_light_radius = data.get("light_radius")
	light_radius = int(raw_light_radius) if raw_light_radius != null else 0
	var raw_duration = data.get("duration")
	duration_remaining = int(raw_duration) if raw_duration != null else -1
	position = Constants.tile_to_world(object_tile)
	WorldState.mark_object_tile(object_tile, object_id)
	if toggleable or not draw_style.is_empty():
		queue_redraw()
	if not stat_def_path.is_empty():
		stat_block = StatBlock.new()
		stat_block.load_from_file(stat_def_path)

func apply_contents_override(override: Array) -> void:
	_content_ids = []
	for entry in override:
		var oid: String = str(entry.get("object_id", ""))
		if oid.is_empty():
			continue
		var cnt: int = maxi(1, int(entry.get("stack_count", 1)))
		for _i in range(cnt):
			_content_ids.append(oid)

func toggle() -> void:
	is_open = not is_open
	queue_redraw()

func _draw() -> void:
	if toggleable:
		var half := Constants.TILE_SIZE / 2.0
		var rect := Rect2(-half, -half, Constants.TILE_SIZE, Constants.TILE_SIZE)
		if is_open:
			draw_rect(rect, Color.BLACK, false, 2.0)
		else:
			draw_rect(rect, Color.BLACK, true)
	elif draw_style == "circle":
		draw_circle(Vector2.ZERO, Constants.TILE_SIZE / 2.0 * 0.8, Color.BLACK)
	elif draw_style == "rect_white":
		var half := Constants.TILE_SIZE / 2.0 * 0.9
		draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0), Color.WHITE, true)

func get_total_weight() -> float:
	var contents_weight: float = 0.0
	for content_id in _content_ids:
		var content_data := PlayerInventory.get_object_data(content_id)
		contents_weight += content_data.get("weight", 0.0)
	return (weight * stack_count) + contents_weight
