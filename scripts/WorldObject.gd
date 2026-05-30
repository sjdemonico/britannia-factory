class_name WorldObject
extends Node2D

@export var object_id: String = ""
@export var object_tile: Vector2i = Vector2i.ZERO
@export var stat_def_path: String = ""

var instance_display_name: String = ""
var passable: bool = true
var movable: bool = true
var transparent: bool = true
var carriable: bool = true
var use_action: String = ""
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

func _ready() -> void:
	var data := PlayerInventory.get_object_data(object_id)
	passable = data.get("passable", true)
	movable = data.get("movable", true)
	transparent = data.get("transparent", true)
	carriable = data.get("carriable", true)
	var raw_ua = data.get("use_action")
	use_action = raw_ua if raw_ua is String else ""
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
	if object_id == "corpse":
		sprite.texture = load("res://assets/sprites/object_corpse.png")
	elif carriable:
		sprite.texture = load("res://assets/sprites/object_carriable.png")
	else:
		sprite.texture = load("res://assets/sprites/object_noncarriable.png")
	position = Vector2(object_tile * Constants.TILE_SIZE) + Vector2(Constants.TILE_SIZE / 2.0, Constants.TILE_SIZE / 2.0)
	WorldState.mark_object_tile(object_tile, object_id)
	if not stat_def_path.is_empty():
		stat_block = StatBlock.new()
		stat_block.load_from_file(stat_def_path)

func get_total_weight() -> float:
	var contents_weight: float = 0.0
	for content_id in _content_ids:
		var content_data := PlayerInventory.get_object_data(content_id)
		contents_weight += content_data.get("weight", 0.0)
	return (weight * stack_count) + contents_weight
