class_name SpriteLoader
extends RefCounted

static func load_sprite(path) -> Texture2D:
	if path == null or (path is String and path.is_empty()):
		return null
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

static func apply_to_node(node: Node, path, size: Vector2i) -> bool:
	var texture := load_sprite(path)
	if texture == null:
		return false
	if node is Sprite2D:
		var s := node as Sprite2D
		s.texture = texture
		var tex_w := texture.get_width()
		var tex_h := texture.get_height()
		if Vector2i(tex_w, tex_h) != Constants.SPRITE_SOURCE_SIZE:
			push_warning("SpriteLoader: '%s' is %dx%d, expected %s; scale adjusted to fit %s" % [
				str(path), tex_w, tex_h, Constants.SPRITE_SOURCE_SIZE, size])
		s.scale = Vector2(size) / Vector2(tex_w, tex_h)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.visible = true
	elif node is TextureRect:
		var rect := node as TextureRect
		rect.texture = texture
		rect.custom_minimum_size = Vector2(size)
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.visible = true
	return true
