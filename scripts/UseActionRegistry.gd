class_name UseActionRegistry
extends RefCounted

var _actions: Dictionary = {}  # String -> Callable

func register(action_name: String, callable: Callable) -> void:
	_actions[action_name] = callable

func has_action(action_name: String) -> bool:
	return _actions.has(action_name)

func execute(action_name: String, params: Dictionary, context: UseContext) -> bool:
	if not _actions.has(action_name):
		push_error("UseActionRegistry: unrecognized action '" + action_name + "'")
		return false
	return _actions[action_name].call(params, context)
