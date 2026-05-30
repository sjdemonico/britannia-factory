extends PanelContainer

const MAX_LINES: int = 50

@onready var _vbox: VBoxContainer = $Clip/VBoxContainer

func _ready() -> void:
	MessageLog._node = self

func _exit_tree() -> void:
	if MessageLog._node == self:
		MessageLog._node = null

func post(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(label)
	if _vbox.get_child_count() > MAX_LINES:
		_vbox.get_child(0).queue_free()

func update_last(text: String) -> void:
	var count := _vbox.get_child_count()
	if count == 0:
		post(text)
		return
	var last := _vbox.get_child(count - 1) as Label
	if last != null:
		last.text = text
