extends Node

var _messages: Dictionary = {}

func _init() -> void:
	load_from_file(Constants.MESSAGES_CONFIG_PATH)

func load_from_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MessageRegistry: cannot open messages file: " + path)
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("MessageRegistry: JSON parse error in " + path + ": " + json.get_error_message())
		file.close()
		return false
	file.close()
	var data: Variant = json.get_data()
	if not data is Dictionary:
		push_error("MessageRegistry: root is not a Dictionary: " + path)
		return false
	_messages = data as Dictionary
	return true

func get_message(key: String, substitutions: Dictionary = {}) -> String:
	if not _messages.has(key):
		push_error("MessageRegistry: missing key: " + key)
		return key
	var text: String = str(_messages[key])
	for token in substitutions:
		text = text.replace("{" + str(token) + "}", str(substitutions[token]))
	return text
