extends PanelContainer

const LINE_HEIGHT: float = 18.0

@onready var _clip: Control = $Clip
@onready var _vbox: VBoxContainer = $Clip/VBoxContainer

var _all_lines: Array[String] = []
var _max_lines: int = 200
var _scroll_list: ScrollableList = ScrollableList.new()
var _scrollbar: Control = null

func _ready() -> void:
	MessageLog._node = self
	_load_config()
	_create_scrollbar()
	_update_visible_rows.call_deferred()
	resized.connect(_on_resized)

func _exit_tree() -> void:
	if MessageLog._node == self:
		MessageLog._node = null

func _load_config() -> void:
	var data: Dictionary = Constants.load_json(Constants.GAME_CONFIG_PATH)
	_max_lines = int(data.get("message_log_max_lines", 200))

func _create_scrollbar() -> void:
	_scrollbar = Control.new()
	_scrollbar.name = "Scrollbar"
	_scrollbar.anchor_left = 1.0
	_scrollbar.anchor_right = 1.0
	_scrollbar.anchor_bottom = 1.0
	_scrollbar.offset_left = -6.0
	_scrollbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_scrollbar)

	var thumb := ColorRect.new()
	thumb.name = "Thumb"
	thumb.color = Color(0.55, 0.55, 0.55, 0.8)
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrollbar.add_child(thumb)
	_scrollbar.hide()

func _on_resized() -> void:
	_update_visible_rows()

func _update_visible_rows() -> void:
	var h: float = size.y
	if h < LINE_HEIGHT:
		return
	var rows: int = maxi(1, int(h / LINE_HEIGHT))
	_scroll_list.setup(rows, _scrollbar)
	_scroll_list.set_items(_all_lines)
	_refresh_visible()

func post(text: String) -> void:
	_all_lines.append(text)
	if _all_lines.size() > _max_lines:
		_all_lines.pop_front()
	_scroll_list.set_items(_all_lines)
	_scroll_list.scroll_to_bottom()
	_refresh_visible()

func update_last(text: String) -> void:
	if _all_lines.is_empty():
		post(text)
		return
	_all_lines[-1] = text
	_scroll_list.set_items(_all_lines)
	_refresh_visible()

func _refresh_visible() -> void:
	for child in _vbox.get_children():
		child.free()
	for line in _scroll_list.get_visible_items():
		var label := Label.new()
		label.text = str(line)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_vbox.add_child(label)

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_scroll_list.scroll_up()
		_refresh_visible()
		accept_event()
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_scroll_list.scroll_down()
		_refresh_visible()
		accept_event()
