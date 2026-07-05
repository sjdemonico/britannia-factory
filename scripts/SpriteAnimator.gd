class_name SpriteAnimator
extends RefCounted

var _frame_interval: float = 0.2
var _current_time: float = 0.0
var _current_frame: int = 0
var _registered: Array = []

func load_config(interval: float) -> void:
	_frame_interval = interval

func register(node: Node, sheet_path, size: Vector2i) -> int:
	var texture := SpriteLoader.load_sprite(sheet_path)
	if texture == null:
		return -1
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	var is_anim := _is_animated(texture)
	var frame := _current_frame if is_anim else 0
	atlas.region = Rect2(frame * Constants.SPRITE_SHEET_FRAME_WIDTH, 0,
		Constants.SPRITE_SHEET_FRAME_WIDTH, Constants.SPRITE_SHEET_FRAME_HEIGHT)
	_apply_atlas_to_node(node, atlas, size)
	var entry := {
		"node": node,
		"atlas": atlas,
		"is_animated": is_anim,
		"size": size,
		"active": true
	}
	_registered.append(entry)
	return _registered.size() - 1

func unregister(handle: int) -> void:
	if handle < 0 or handle >= _registered.size():
		return
	_registered[handle]["active"] = false

func set_sheet(handle: int, sheet_path) -> void:
	if handle < 0 or handle >= _registered.size():
		return
	var entry: Dictionary = _registered[handle]
	if not entry["active"]:
		return
	var texture := SpriteLoader.load_sprite(sheet_path)
	if texture == null:
		return
	var is_anim := _is_animated(texture)
	entry["atlas"].atlas = texture
	entry["is_animated"] = is_anim
	_apply_frame(entry)

func tick(delta: float) -> void:
	_current_time += delta
	if _current_time < _frame_interval:
		return
	_current_time -= _frame_interval
	_current_frame = (_current_frame + 1) % Constants.SPRITE_SHEET_FRAME_COUNT
	for entry in _registered:
		if not entry["active"]:
			continue
		var node: Node = entry["node"]
		if not is_instance_valid(node):
			entry["active"] = false
			continue
		_apply_frame(entry)

func _is_animated(texture: Texture2D) -> bool:
	return texture.get_width() > Constants.SPRITE_SHEET_FRAME_WIDTH

func _apply_frame(entry: Dictionary) -> void:
	var frame := _current_frame if entry["is_animated"] else 0
	entry["atlas"].region = Rect2(
		frame * Constants.SPRITE_SHEET_FRAME_WIDTH, 0,
		Constants.SPRITE_SHEET_FRAME_WIDTH, Constants.SPRITE_SHEET_FRAME_HEIGHT)

func _apply_atlas_to_node(node: Node, atlas: AtlasTexture, size: Vector2i) -> void:
	if node is Sprite2D:
		var s := node as Sprite2D
		s.texture = atlas
		s.scale = Vector2(size) / Vector2(Constants.SPRITE_SOURCE_SIZE)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.visible = true
	elif node is TextureRect:
		var rect := node as TextureRect
		rect.texture = atlas
		rect.custom_minimum_size = Vector2(size)
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.visible = true
