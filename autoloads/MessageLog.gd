extends Node

var _node: PanelContainer = null

func post(text: String) -> void:
	if is_instance_valid(_node):
		_node.post(text)

func update_last(text: String) -> void:
	if is_instance_valid(_node):
		_node.update_last(text)
