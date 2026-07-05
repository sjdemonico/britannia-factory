extends PanelContainer

@onready var _scroll: ScrollContainer = $Scroll
@onready var _vbox: VBoxContainer = $Scroll/VBoxContainer

var _all_lines: Array[String] = []
var _max_lines: int = 200

func _ready() -> void:
	MessageLog._node = self
	_load_config()
	_refresh_visible.call_deferred()

func _exit_tree() -> void:
	if MessageLog._node == self:
		MessageLog._node = null

func _load_config() -> void:
	var data: Dictionary = Constants.load_json(Constants.GAME_CONFIG_PATH)
	_max_lines = int(data.get("message_log_max_lines", 200))

func post(text: String) -> void:
	_all_lines.append(text)
	if _all_lines.size() > _max_lines:
		_all_lines.pop_front()
	_refresh_visible()
	_do_scroll_to_bottom.call_deferred()

func update_last(text: String) -> void:
	if _all_lines.is_empty():
		post(text)
		return
	_all_lines[-1] = text
	_refresh_visible()

func _refresh_visible() -> void:
	for child in _vbox.get_children():
		child.free()
	for line in _all_lines:
		var label := Label.new()
		label.text = str(line)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if GameManager.get_font(Constants.FONT_BODY_ROLE):
			label.add_theme_font_override("font", GameManager.get_font(Constants.FONT_BODY_ROLE))
		label.add_theme_font_size_override("font_size", GameManager.get_font_size(Constants.FONT_BODY_ROLE))
		_vbox.add_child(label)

func _do_scroll_to_bottom() -> void:
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
