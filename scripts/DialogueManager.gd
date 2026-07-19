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
	return _data.get("greeting", MessageRegistry.get_message("dialogue_no_response"))

func get_farewell() -> String:
	return _data.get("farewell", MessageRegistry.get_message("dialogue_farewell"))

func get_farewell_dismiss() -> String:
	return _data.get("farewell_dismiss", "")

func get_join_accepts() -> String:
	return _data.get("join_accepts", "")

func get_join_rejects() -> String:
	return _data.get("join_rejects", "")

func get_name() -> String:
	return _data.get("name", "???")

func meets_min_standing(keyword: String) -> bool:
	var keywords: Dictionary = _data.get("keywords", {})
	var entry: Dictionary = keywords.get(keyword, {})
	var raw: Variant = entry.get("min_standing")
	if not raw is Dictionary:
		return true
	var faction_id: String = str((raw as Dictionary).get("faction_id", ""))
	var threshold: int = int((raw as Dictionary).get("threshold", 0))
	if faction_id.is_empty():
		return true
	return FactionManager.get_standing(faction_id) >= threshold

func get_alternate_response(keyword: String) -> String:
	var keywords: Dictionary = _data.get("keywords", {})
	var entry: Dictionary = keywords.get(keyword, {})
	return str(entry.get("alternate_response", ""))

func process_keyword(raw_input: String) -> String:
	if not _loaded:
		return MessageRegistry.get_message("dialogue_no_dialogue")

	var keyword := raw_input.strip_edges().to_lower()
	keyword = keyword.replace(".", "").replace(",", "").replace("?", "").replace("!", "")

	var keywords: Dictionary = _data.get("keywords", {})
	var not_found_msg: String = _data.get("unknown", MessageRegistry.get_message("dialogue_keyword_not_found"))
	if not keywords.has(keyword):
		return not_found_msg

	var entry: Dictionary = keywords[keyword]

	var triggers: Array = entry.get("triggers", [])
	for trigger in triggers:
		if not _process_trigger(trigger):
			return not_found_msg

	if not meets_min_standing(keyword):
		var alt: String = get_alternate_response(keyword)
		if alt.is_empty():
			alt = MessageRegistry.get_message("dialogue_faction_gated")
		return alt

	var cost_raw: Variant = entry.get("currency_cost")
	if cost_raw is Dictionary:
		var cost_dict: Dictionary = cost_raw as Dictionary
		var amount: int = int(cost_dict.get("amount", 0))
		if amount > 0:
			var currency_id: String = GameManager.currency_stat_id
			if PlayerStats.get_stat(currency_id) < amount:
				return str(cost_dict.get("response_insufficient", ""))
			PlayerStats.modify_stat(currency_id, -amount)

	QuestManager.check_dialogue_triggers(npc_id, keyword)
	QuestManager.check_talk_objectives(npc_id, keyword)

	var delivery: Variant = entry.get("quest_delivery")
	if delivery is Dictionary:
		if not QuestManager.check_deliver_objective(delivery):
			return not_found_msg

	var response: String = str(entry.get("response", "..."))
	var changes: Variant = entry.get("faction_changes")
	if changes is Array:
		for change in changes as Array:
			if not change is Dictionary:
				continue
			var fid: String = str((change as Dictionary).get("faction_id", ""))
			var amt: int = int((change as Dictionary).get("amount", 0))
			if not fid.is_empty() and amt != 0:
				FactionManager.modify_standing(fid, amt)
	return response

func _process_trigger(trigger: String) -> bool:
	var parts := trigger.split(":")
	if parts.size() < 2:
		push_error("DialogueManager: malformed trigger: " + trigger)
		return true

	var action := parts[0]
	var flag_name := parts[1]

	match action:
		"flag_set":
			WorldState.set_flag(flag_name, true)
			return true
		"flag_clear":
			WorldState.set_flag(flag_name, false)
			return true
		"flag_require":
			return WorldState.get_flag(flag_name)
		_:
			push_error("DialogueManager: unknown trigger action: " + action)
			return true
