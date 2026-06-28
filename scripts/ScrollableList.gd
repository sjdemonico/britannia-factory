class_name ScrollableList
extends RefCounted

var _items: Array = []
var _scroll_offset: int = 0
var _visible_rows: int = 10
var _scrollbar_node: Control = null

func setup(visible_rows: int, scrollbar: Control = null) -> void:
	_visible_rows = maxi(1, visible_rows)
	_scrollbar_node = scrollbar
	_scroll_offset = clampi(_scroll_offset, 0, maxi(0, _items.size() - _visible_rows))
	update_scrollbar()

func reset() -> void:
	_scroll_offset = 0
	update_scrollbar()

func set_items(items: Array) -> void:
	_items = items
	_scroll_offset = clampi(_scroll_offset, 0, maxi(0, _items.size() - _visible_rows))
	update_scrollbar()

func scroll_up() -> void:
	_scroll_offset = maxi(0, _scroll_offset - 1)
	update_scrollbar()

func scroll_down() -> void:
	_scroll_offset = mini(maxi(0, _items.size() - _visible_rows), _scroll_offset + 1)
	update_scrollbar()

func scroll_to_index(index: int) -> void:
	if _items.is_empty():
		return
	if index < _scroll_offset:
		_scroll_offset = index
	elif index >= _scroll_offset + _visible_rows:
		_scroll_offset = index - _visible_rows + 1
	_scroll_offset = clampi(_scroll_offset, 0, maxi(0, _items.size() - _visible_rows))
	update_scrollbar()

func scroll_to_bottom() -> void:
	_scroll_offset = maxi(0, _items.size() - _visible_rows)
	update_scrollbar()

func get_visible_items() -> Array:
	if _items.is_empty():
		return []
	var end: int = mini(_scroll_offset + _visible_rows, _items.size())
	return _items.slice(_scroll_offset, end)

func needs_scroll() -> bool:
	return _items.size() > _visible_rows

func update_scrollbar() -> void:
	if _scrollbar_node == null or not is_instance_valid(_scrollbar_node):
		return
	_scrollbar_node.visible = needs_scroll()
	if not needs_scroll():
		return
	var thumb := _scrollbar_node.get_node_or_null("Thumb") as ColorRect
	if thumb == null:
		return
	var track_h: float = _scrollbar_node.size.y
	if track_h <= 0.0:
		return
	var thumb_ratio: float = float(_visible_rows) / float(_items.size())
	var thumb_h: float = maxf(8.0, track_h * thumb_ratio)
	var max_offset: int = maxi(1, _items.size() - _visible_rows)
	var thumb_y: float = (track_h - thumb_h) * float(_scroll_offset) / float(max_offset)
	thumb.position.y = thumb_y
	thumb.size = Vector2(_scrollbar_node.size.x, thumb_h)
