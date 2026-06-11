class_name DialogueManager
extends RefCounted

var _data: Dictionary = {}
var _loaded: bool = false
var npc_id: String = ""

func load_from_dict(data: Dictionary) -> bool:
	if data.is_empty():
		_loaded = false
		return false
	_data = data
	_loaded = true
	return true

func get_greeting() -> String:
	return _data.get("greeting", "...")

func get_farewell() -> String:
	return _data.get("farewell", "Farewell.")

func get_name() -> String:
	return _data.get("name", "???")

func process_keyword(raw_input: String) -> String:
	if not _loaded:
		return "This person has nothing to say."

	var keyword := raw_input.strip_edges().to_lower()
	keyword = keyword.replace(".", "").replace(",", "").replace("?", "").replace("!", "")

	QuestManager.check_dialogue_triggers(npc_id, keyword)
	QuestManager.check_talk_objectives(npc_id, keyword)

	var keywords: Dictionary = _data.get("keywords", {})
	if not keywords.has(keyword):
		return _data.get("unknown", "I know not of what you speak.")

	var entry: Dictionary = keywords[keyword]

	var triggers: Array = entry.get("triggers", [])
	for trigger in triggers:
		if not _process_trigger(trigger):
			return _data.get("unknown", "I know not of what you speak.")

	var delivery: Variant = entry.get("quest_delivery")
	if delivery is Dictionary:
		QuestManager.check_deliver_objective(delivery)

	return entry.get("response", "...")

func _process_trigger(trigger: String) -> bool:
	var parts := trigger.split(":")
	if parts.size() < 2:
		push_error("DialogueManager: malformed trigger: " + trigger)
		return true

	var action := parts[0]
	var flag_name := parts[1]

	match action:
		"flag_set":
			WorldState.flags[flag_name] = true
			return true
		"flag_clear":
			WorldState.flags[flag_name] = false
			return true
		"flag_require":
			return WorldState.flags.get(flag_name, false)
		_:
			push_error("DialogueManager: unknown trigger action: " + action)
			return true
