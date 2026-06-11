extends Node

var _registry: Dictionary = {}     # quest_id -> quest definition dict
var _quest_states: Dictionary = {} # quest_id -> state dict
var _tile_triggers: Dictionary = {} # Vector2i -> Array[Dictionary]
var _fired_region_triggers: Dictionary = {} # fire_key -> true

# ── Registry ────────────────────────────────────────────────────────────────

func load_registry(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("QuestManager: cannot open quest registry: " + path)
		return false
	var json := JSON.new()
	var text := file.get_as_text()
	file.close()
	if json.parse(text) != OK:
		push_error("QuestManager: JSON parse error in " + path + ": " + json.get_error_message())
		return false
	var data: Variant = json.get_data()
	if not data is Dictionary:
		push_error("QuestManager: registry root is not a Dictionary: " + path)
		return false
	var quests_raw: Variant = data.get("quests")
	if not quests_raw is Array:
		push_error("QuestManager: 'quests' key missing or not Array in: " + path)
		return false
	for entry in quests_raw:
		if not entry is Dictionary:
			push_warning("QuestManager: skipping non-dictionary quest entry")
			continue
		var quest_id: String = str(entry.get("quest_id", ""))
		if quest_id.is_empty():
			push_warning("QuestManager: quest entry missing quest_id, skipping")
			continue
		_registry[quest_id] = entry
	return true

# ── Tile Trigger API ─────────────────────────────────────────────────────────

func register_tile_triggers(triggers: Array) -> void:
	_tile_triggers = {}
	for entry in triggers:
		if not entry is Dictionary:
			continue
		var raw_tile: Variant = entry.get("tile", [0, 0])
		if not raw_tile is Array or (raw_tile as Array).size() < 2:
			continue
		var tile := Vector2i(int(raw_tile[0]), int(raw_tile[1]))
		if not _tile_triggers.has(tile):
			_tile_triggers[tile] = []
		_tile_triggers[tile].append(entry)

func check_tile_triggers(tile: Vector2i) -> void:
	if _tile_triggers.has(tile):
		for trigger in _tile_triggers[tile]:
			if not trigger is Dictionary:
				continue
			var t_type: String = str(trigger.get("type", ""))
			var params_raw: Variant = trigger.get("params", {})
			var params: Dictionary = params_raw if params_raw is Dictionary else {}
			match t_type:
				"start_quest":
					var qid: String = str(params.get("quest_id", ""))
					if not qid.is_empty() and not is_quest_active(qid):
						start_quest(qid)
				"complete_objective":
					var qid: String = str(params.get("quest_id", ""))
					var oid: String = str(params.get("objective_id", ""))
					if not qid.is_empty() and not oid.is_empty() and is_quest_active(qid) and not is_objective_complete(qid, oid):
						complete_objective(qid, oid)
	for quest_id in get_active_quests():
		var def: Dictionary = _registry.get(quest_id, {})
		for obj_def in def.get("objectives", []):
			if not obj_def is Dictionary or str(obj_def.get("type", "")) != "reach_location":
				continue
			var params_raw: Variant = obj_def.get("params", {})
			var params: Dictionary = params_raw if params_raw is Dictionary else {}
			if str(params.get("trigger", "")) != "tile_step":
				continue
			var obj_id: String = str(obj_def.get("objective_id", ""))
			if obj_id.is_empty() or is_objective_complete(quest_id, obj_id):
				continue
			var obj_st: Dictionary = get_objective_progress(quest_id, obj_id)
			if obj_st.get("status", "") != "active":
				continue
			var tile_raw: Variant = params.get("tile", [0, 0])
			if not tile_raw is Array or (tile_raw as Array).size() < 2:
				continue
			if tile == Vector2i(int(tile_raw[0]), int(tile_raw[1])):
				complete_objective(quest_id, obj_id)

# ── Region Entry Trigger API ─────────────────────────────────────────────────

func check_region_entry_triggers(region_id: String) -> void:
	for quest_id in _registry:
		var def: Dictionary = _registry[quest_id]
		if is_quest_active(quest_id):
			# Complete reach_region and reach_location/region_enter objectives matching this region
			for obj_def in def.get("objectives", []):
				if not obj_def is Dictionary:
					continue
				var obj_type: String = str(obj_def.get("type", ""))
				var params_raw: Variant = obj_def.get("params", {})
				var params: Dictionary = params_raw if params_raw is Dictionary else {}
				var obj_id: String = str(obj_def.get("objective_id", ""))
				if obj_id.is_empty() or is_objective_complete(quest_id, obj_id):
					continue
				var matches: bool = false
				if obj_type == "reach_region" and str(params.get("region_id", "")) == region_id:
					matches = true
				elif obj_type == "reach_location" and str(params.get("trigger", "")) == "region_enter" and str(params.get("region_id", "")) == region_id:
					matches = true
				if matches:
					complete_objective(quest_id, obj_id)
		else:
			# Start quest if a region_entry trigger matches
			var triggers_raw: Variant = def.get("triggers")
			if not triggers_raw is Dictionary:
				continue
			var region_triggers: Variant = triggers_raw.get("region_entry", [])
			if not region_triggers is Array:
				continue
			for rt in region_triggers:
				if not rt is Dictionary:
					continue
				if str(rt.get("region_id", "")) != region_id:
					continue
				var fire_key: String = quest_id + "|region_entry|" + region_id
				if _fired_region_triggers.has(fire_key):
					break
				_fired_region_triggers[fire_key] = true
				start_quest(quest_id)
				break

# ── Dialogue Trigger API ─────────────────────────────────────────────────────

func check_dialogue_triggers(npc_id: String, keyword: String) -> void:
	for quest_id in _registry:
		if is_quest_active(quest_id):
			continue
		var def: Dictionary = _registry[quest_id]
		var triggers_raw: Variant = def.get("triggers")
		if not triggers_raw is Dictionary:
			continue
		var dialogue_triggers: Variant = triggers_raw.get("dialogue", [])
		if not dialogue_triggers is Array:
			continue
		for dt in dialogue_triggers:
			if not dt is Dictionary:
				continue
			if str(dt.get("npc_id", "")) == npc_id and str(dt.get("keyword", "")) == keyword:
				start_quest(quest_id)
				break

func check_talk_objectives(npc_id: String, keyword: String) -> void:
	for quest_id in get_active_quests():
		var def: Dictionary = _registry.get(quest_id, {})
		for obj_def in def.get("objectives", []):
			if not obj_def is Dictionary or str(obj_def.get("type", "")) != "talk":
				continue
			var obj_id: String = str(obj_def.get("objective_id", ""))
			if obj_id.is_empty() or is_objective_complete(quest_id, obj_id):
				continue
			var params_raw: Variant = obj_def.get("params", {})
			var params: Dictionary = params_raw if params_raw is Dictionary else {}
			if str(params.get("npc_id", "")) != npc_id:
				continue
			var kw_raw: Variant = params.get("keyword")
			if kw_raw != null and str(kw_raw) != keyword:
				continue
			complete_objective(quest_id, obj_id)

func check_deliver_objective(delivery: Dictionary) -> void:
	var quest_id: String = str(delivery.get("quest_id", ""))
	var object_id: String = str(delivery.get("object_id", ""))
	var count: int = int(delivery.get("count", 1))
	if quest_id.is_empty() or object_id.is_empty():
		return
	if not is_quest_active(quest_id):
		return
	var trigger_branch_id_raw: Variant = delivery.get("trigger_branch_id")
	if trigger_branch_id_raw is String and not (trigger_branch_id_raw as String).is_empty():
		if _count_in_inventory(object_id) < count:
			MessageLog.post("You do not have what I need.")
			return
		_take_from_inventory(object_id, count)
		var item_name: String = str(PlayerInventory.get_object_data(object_id).get("name", object_id))
		MessageLog.post("You hand over the " + item_name + ".")
		trigger_branch(quest_id, trigger_branch_id_raw as String)
		return
	var objective_id: String = str(delivery.get("objective_id", ""))
	if objective_id.is_empty() or is_objective_complete(quest_id, objective_id):
		return
	var _deliver_obj_state: Dictionary = get_objective_progress(quest_id, objective_id)
	if _deliver_obj_state.get("status", "") != "active":
		return
	if _count_in_inventory(object_id) < count:
		MessageLog.post("You do not have what I need.")
		return
	_take_from_inventory(object_id, count)
	var item_name: String = str(PlayerInventory.get_object_data(object_id).get("name", object_id))
	complete_objective(quest_id, objective_id)
	MessageLog.post("You hand over the " + item_name + ".")

func _count_in_inventory(object_id: String) -> int:
	var total: int = 0
	for obj in PlayerInventory.get_objects():
		if str(obj.get("object_id", "")) == object_id:
			total += int(obj.get("stack_count", 1))
	return total

func _take_from_inventory(object_id: String, count: int) -> void:
	var remaining: int = count
	var snapshot: Array = PlayerInventory.get_objects().duplicate()
	for obj in snapshot:
		if remaining <= 0:
			break
		if str(obj.get("object_id", "")) != object_id:
			continue
		var iid: int = int(obj.get("instance_id", -1))
		if iid == -1:
			continue
		var stack: int = int(obj.get("stack_count", 1))
		var take: int = mini(stack, remaining)
		PlayerInventory.take_from_stack(iid, take)
		remaining -= take

# ── NPC Death ────────────────────────────────────────────────────────────────

func _on_npc_died(npc_id: String) -> void:
	for quest_id in get_active_quests():
		var def: Dictionary = _registry.get(quest_id, {})
		for cond in def.get("fail_conditions", []):
			if not cond is Dictionary or str(cond.get("type", "")) != "npc_dead":
				continue
			var params_raw: Variant = cond.get("params", {})
			var params: Dictionary = params_raw if params_raw is Dictionary else {}
			if str(params.get("npc_id", "")) == npc_id:
				fail_quest(quest_id)
				break
	for quest_id in get_active_quests():
		var def: Dictionary = _registry.get(quest_id, {})
		for obj_def in def.get("objectives", []):
			if not obj_def is Dictionary or str(obj_def.get("type", "")) != "kill":
				continue
			var obj_id: String = str(obj_def.get("objective_id", ""))
			if obj_id.is_empty() or is_objective_complete(quest_id, obj_id):
				continue
			var obj_state: Dictionary = get_objective_progress(quest_id, obj_id)
			if obj_state.get("status", "") != "active":
				continue
			var params_raw: Variant = obj_def.get("params", {})
			var params: Dictionary = params_raw if params_raw is Dictionary else {}
			var target_npc_id: String = str(params.get("npc_id", ""))
			var any_of_group: bool = bool(params.get("any_of_group", false))
			var matches: bool = npc_id.begins_with(target_npc_id) if any_of_group else npc_id == target_npc_id
			if matches:
				increment_objective(quest_id, obj_id, 1)

# ── Fail Condition Scheduling ────────────────────────────────────────────────

func _register_fail_conditions(quest_id: String) -> void:
	var def: Dictionary = _registry.get(quest_id, {})
	for cond in def.get("fail_conditions", []):
		if not cond is Dictionary or str(cond.get("type", "")) != "time_elapsed":
			continue
		var params_raw: Variant = cond.get("params", {})
		var params: Dictionary = params_raw if params_raw is Dictionary else {}
		var ticks: int = int(params.get("ticks", 0))
		if ticks <= 0:
			continue
		var handle: int = GameTime.schedule(fail_quest.bind(quest_id), ticks)
		_quest_states[quest_id]["scheduled_handles"].append(handle)

func _cancel_scheduled_handles(quest_id: String) -> void:
	if not _quest_states.has(quest_id):
		return
	var handles: Array = _quest_states[quest_id].get("scheduled_handles", [])
	for handle in handles:
		GameTime.cancel(handle)
	_quest_states[quest_id]["scheduled_handles"] = []

# ── Query API ────────────────────────────────────────────────────────────────

func get_quest(quest_id: String) -> Dictionary:
	return _registry.get(quest_id, {})

func is_quest_active(quest_id: String) -> bool:
	if not _quest_states.has(quest_id):
		return false
	return _quest_states[quest_id]["status"] == "active"

func is_quest_complete(quest_id: String) -> bool:
	if not _quest_states.has(quest_id):
		return false
	return _quest_states[quest_id]["status"] == "complete"

func is_quest_failed(quest_id: String) -> bool:
	if not _quest_states.has(quest_id):
		return false
	return _quest_states[quest_id]["status"] == "failed"

func is_objective_complete(quest_id: String, objective_id: String) -> bool:
	if not _quest_states.has(quest_id):
		return false
	var state: Dictionary = _quest_states[quest_id]
	if not state["objectives"].has(objective_id):
		return false
	return state["objectives"][objective_id]["status"] == "complete"

func is_objective_hidden(quest_id: String, objective_id: String) -> bool:
	if not _quest_states.has(quest_id):
		return true
	var state: Dictionary = _quest_states[quest_id]
	if not state["objectives"].has(objective_id):
		return true
	return state["objectives"][objective_id]["status"] == "hidden"

func get_objective_progress(quest_id: String, objective_id: String) -> Dictionary:
	if not _quest_states.has(quest_id):
		return {}
	var state: Dictionary = _quest_states[quest_id]
	if not state["objectives"].has(objective_id):
		return {}
	return state["objectives"][objective_id].duplicate()

func get_active_quests() -> Array:
	var result: Array = []
	for qid in _quest_states:
		if _quest_states[qid]["status"] == "active":
			result.append(qid)
	return result

func get_completed_quests() -> Array:
	var result: Array = []
	for qid in _quest_states:
		if _quest_states[qid]["status"] == "complete":
			result.append(qid)
	return result

func get_failed_quests() -> Array:
	var result: Array = []
	for qid in _quest_states:
		if _quest_states[qid]["status"] == "failed":
			result.append(qid)
	return result

func get_all_objective_states(quest_id: String) -> Dictionary:
	if not _quest_states.has(quest_id):
		return {}
	return _quest_states[quest_id]["objectives"].duplicate(true)

func get_journal_updates(quest_id: String) -> Array:
	if not _quest_states.has(quest_id):
		return []
	return _quest_states[quest_id]["journal_updates"].duplicate(true)

# ── Mutation API ─────────────────────────────────────────────────────────────

func start_quest(quest_id: String) -> bool:
	if not _registry.has(quest_id):
		push_error("QuestManager: unknown quest_id: " + quest_id)
		return false
	var def: Dictionary = _registry[quest_id]
	var repeatable: bool = bool(def.get("repeatable", false))
	if _quest_states.has(quest_id):
		var current_status: String = _quest_states[quest_id]["status"]
		if current_status == "active":
			push_warning("QuestManager: quest already active: " + quest_id)
			return false
		if not repeatable and (current_status == "complete" or current_status == "failed"):
			push_warning("QuestManager: quest not repeatable: " + quest_id)
			return false
	var ordered: bool = bool(def.get("ordered", false))
	var objectives_def: Array = def.get("objectives", [])
	var obj_states: Dictionary = {}
	for i in range(objectives_def.size()):
		var obj_def: Variant = objectives_def[i]
		if not obj_def is Dictionary:
			continue
		var obj_id: String = str(obj_def.get("objective_id", ""))
		if obj_id.is_empty():
			continue
		var prerequisite_id: Variant = obj_def.get("prerequisite_id")
		var hidden_until: bool = bool(obj_def.get("hidden_until_prerequisite", false))
		var params: Dictionary = obj_def.get("params", {}) if obj_def.get("params") is Dictionary else {}
		var required: int = int(params.get("count", 1))
		var explicit_status: String = str(obj_def.get("initial_status", ""))
		var initial_status: String
		if not explicit_status.is_empty():
			initial_status = explicit_status
		elif prerequisite_id != null and not str(prerequisite_id).is_empty():
			initial_status = "hidden" if hidden_until else "inactive"
		elif ordered:
			initial_status = "active" if i == 0 else "inactive"
		else:
			initial_status = "active"
		obj_states[obj_id] = {
			"status": initial_status,
			"progress": 0,
			"required": required
		}
	_quest_states[quest_id] = {
		"status": "active",
		"objectives": obj_states,
		"branches_closed": [],
		"journal_updates": [],
		"scheduled_handles": [],
		"triggered_branch_id": null
	}
	_register_fail_conditions(quest_id)
	var quest_name: String = str(def.get("name", quest_id))
	MessageLog.post("New quest: " + quest_name + ".")
	return true

func fail_quest(quest_id: String) -> void:
	if not _quest_states.has(quest_id):
		push_error("QuestManager: cannot fail unknown quest: " + quest_id)
		return
	if _quest_states[quest_id]["status"] != "active":
		return
	_cancel_scheduled_handles(quest_id)
	_quest_states[quest_id]["status"] = "failed"
	var quest_name: String = str(_registry.get(quest_id, {}).get("name", quest_id))
	MessageLog.post("Quest failed: " + quest_name + ".")

func complete_objective(quest_id: String, objective_id: String) -> void:
	if not _quest_states.has(quest_id):
		push_error("QuestManager: complete_objective on unknown quest: " + quest_id)
		return
	var state: Dictionary = _quest_states[quest_id]
	if state["status"] != "active":
		return
	if not state["objectives"].has(objective_id):
		push_error("QuestManager: complete_objective on unknown objective '" + objective_id + "' in quest: " + quest_id)
		return
	var obj_state: Dictionary = state["objectives"][objective_id]
	if obj_state["status"] == "complete" or obj_state["status"] == "skipped":
		return
	obj_state["status"] = "complete"
	obj_state["progress"] = obj_state["required"]

	var def: Dictionary = _registry.get(quest_id, {})
	var objectives_def: Array = def.get("objectives", [])
	var ordered: bool = bool(def.get("ordered", false))

	var obj_desc: String = objective_id
	for od in objectives_def:
		if not od is Dictionary:
			continue
		if str(od.get("objective_id", "")) == objective_id:
			var d: String = str(od.get("description_override", ""))
			if not d.is_empty():
				obj_desc = d
			break
	MessageLog.post("Objective complete: " + obj_desc)
	state["journal_updates"].append({"timestamp": GameTime.get_timestamp_string(), "text": "Objective complete: " + obj_desc})

	# Activate prerequisite dependents
	for obj_def in objectives_def:
		if not obj_def is Dictionary:
			continue
		var dep_id: String = str(obj_def.get("objective_id", ""))
		if dep_id.is_empty() or dep_id == objective_id:
			continue
		var prereq: Variant = obj_def.get("prerequisite_id")
		if prereq != null and str(prereq) == objective_id:
			if state["objectives"].has(dep_id):
				var dep_state: Dictionary = state["objectives"][dep_id]
				if dep_state["status"] == "hidden" or dep_state["status"] == "inactive":
					dep_state["status"] = "active"

	# For ordered quests, activate the next non-complete objective in definition order
	if ordered:
		var found_completed: bool = false
		for obj_def in objectives_def:
			if not obj_def is Dictionary:
				continue
			var oid: String = str(obj_def.get("objective_id", ""))
			if oid.is_empty():
				continue
			if oid == objective_id:
				found_completed = true
				continue
			if found_completed and state["objectives"].has(oid):
				var ns: Dictionary = state["objectives"][oid]
				if ns["status"] == "inactive" or ns["status"] == "hidden":
					ns["status"] = "active"
					var next_desc: String = str(obj_def.get("description_override", oid))
					MessageLog.post("New objective: " + next_desc)
					state["journal_updates"].append({"timestamp": GameTime.get_timestamp_string(), "text": "New objective: " + next_desc})
					break

	_evaluate_branches(quest_id)
	_check_quest_completion(quest_id)

func increment_objective(quest_id: String, objective_id: String, amount: int) -> void:
	if not _quest_states.has(quest_id):
		push_error("QuestManager: increment_objective on unknown quest: " + quest_id)
		return
	var state: Dictionary = _quest_states[quest_id]
	if state["status"] != "active":
		return
	if not state["objectives"].has(objective_id):
		push_error("QuestManager: increment_objective on unknown objective '" + objective_id + "' in quest: " + quest_id)
		return
	var obj_state: Dictionary = state["objectives"][objective_id]
	if obj_state["status"] == "complete":
		return
	obj_state["progress"] = mini(obj_state["progress"] + amount, obj_state["required"])
	if obj_state["progress"] >= obj_state["required"]:
		complete_objective(quest_id, objective_id)

func add_journal_update(quest_id: String, text: String) -> void:
	if not _quest_states.has(quest_id):
		push_error("QuestManager: add_journal_update for unknown quest: " + quest_id)
		return
	_quest_states[quest_id]["journal_updates"].append({
		"timestamp": str(GameTime.total_ticks),
		"text": text
	})

# ── Internal ─────────────────────────────────────────────────────────────────

func _distribute_rewards(quest_id: String) -> void:
	var def: Dictionary = _registry.get(quest_id, {})
	var state: Dictionary = _quest_states.get(quest_id, {})
	var rewards: Array = []
	var quest_rewards: Variant = def.get("rewards", [])
	if quest_rewards is Array:
		rewards.append_array(quest_rewards)
	var triggered_branch_id: Variant = state.get("triggered_branch_id")
	if triggered_branch_id is String:
		for branch in def.get("branches", []):
			if not branch is Dictionary or str(branch.get("branch_id", "")) != triggered_branch_id:
				continue
			var branch_rewards: Variant = branch.get("rewards", [])
			if branch_rewards is Array:
				rewards.append_array(branch_rewards)
			break
	if rewards.is_empty():
		return
	MessageLog.post("Quest rewards received.")
	for reward in rewards:
		if reward is Dictionary:
			_apply_reward(reward)

func _apply_reward(reward: Dictionary) -> void:
	var params_raw: Variant = reward.get("params", {})
	var params: Dictionary = params_raw if params_raw is Dictionary else {}
	match str(reward.get("type", "")):
		"experience":
			var amount: int = int(params.get("amount", 0))
			if amount > 0:
				CombatManager.grant_experience(amount)
		"item":
			var object_id: String = str(params.get("object_id", ""))
			var count: int = int(params.get("count", 1))
			if object_id.is_empty() or count <= 0:
				return
			var item_data: Dictionary = PlayerInventory.get_object_data(object_id)
			if item_data.is_empty():
				push_error("QuestManager: _apply_reward — unknown object_id: " + object_id)
				return
			var item_name: String = str(item_data.get("name", object_id))
			var carry_limit: float = float(PlayerStats.get_effective_value("carry_limit"))
			var item_weight: float = float(item_data.get("weight", 0.0)) * count
			var fits: bool = carry_limit <= 0.0 or (PlayerInventory.get_total_weight() + item_weight <= carry_limit)
			if fits:
				if bool(item_data.get("stackable", false)):
					PlayerInventory.add_stacked(object_id, count)
				else:
					for _i in range(count):
						PlayerInventory.add_object(object_id)
				MessageLog.post("You receive " + str(count) + " " + item_name + ".")
			else:
				GameManager.spawn_or_merge(object_id, GameManager.get_player_tile(), count)
				MessageLog.post("You receive " + str(count) + " " + item_name + ", but cannot carry it. It falls to the ground.")
		"stat":
			var stat_id: String = str(params.get("stat_id", ""))
			var amount: int = int(params.get("amount", 0))
			if stat_id.is_empty() or amount == 0:
				return
			PlayerStats.modify_stat(stat_id, amount)
			MessageLog.post("Your " + stat_id.replace("_", " ").capitalize() + " increases by " + str(amount) + ".")

func _evaluate_branches(quest_id: String) -> void:
	if not _quest_states.has(quest_id):
		return
	var state: Dictionary = _quest_states[quest_id]
	if state["status"] != "active":
		return
	var def: Dictionary = _registry.get(quest_id, {})
	for branch in def.get("branches", []):
		if not branch is Dictionary:
			continue
		var branch_id: String = str(branch.get("branch_id", ""))
		if branch_id.is_empty() or branch_id in state["branches_closed"]:
			continue
		var cond_raw: Variant = branch.get("condition", {})
		var cond: Dictionary = cond_raw if cond_raw is Dictionary else {}
		var cond_obj_id: String = str(cond.get("objective_id", ""))
		var cond_status: String = str(cond.get("status", "complete"))
		if cond_obj_id.is_empty() or not state["objectives"].has(cond_obj_id):
			continue
		if state["objectives"][cond_obj_id]["status"] != cond_status:
			continue
		if bool(branch.get("auto_trigger", true)):
			trigger_branch(quest_id, branch_id)
			return

func trigger_branch(quest_id: String, branch_id: String) -> void:
	if not _quest_states.has(quest_id):
		push_error("QuestManager: trigger_branch on unknown quest: " + quest_id)
		return
	var state: Dictionary = _quest_states[quest_id]
	if state["status"] != "active":
		return
	var def: Dictionary = _registry.get(quest_id, {})
	var branch_def: Dictionary = {}
	for b in def.get("branches", []):
		if b is Dictionary and str(b.get("branch_id", "")) == branch_id:
			branch_def = b
			break
	if branch_def.is_empty():
		push_error("QuestManager: trigger_branch — unknown branch_id '" + branch_id + "' in quest: " + quest_id)
		return
	state["triggered_branch_id"] = branch_id
	var closes: Variant = branch_def.get("closes_branches", [])
	if closes is Array:
		for closed_id_raw in closes:
			var cid: String = str(closed_id_raw)
			if not cid in state["branches_closed"]:
				state["branches_closed"].append(cid)
			for b2 in def.get("branches", []):
				if not b2 is Dictionary or str(b2.get("branch_id", "")) != cid:
					continue
				var b2_objs: Variant = b2.get("activates_objectives", [])
				if b2_objs is Array:
					for obj_id_raw in b2_objs:
						var obj_id: String = str(obj_id_raw)
						if state["objectives"].has(obj_id) and state["objectives"][obj_id]["status"] != "complete":
							state["objectives"][obj_id]["status"] = "skipped"
	var activates: Variant = branch_def.get("activates_objectives", [])
	if activates is Array:
		for obj_id_raw in activates:
			var obj_id: String = str(obj_id_raw)
			if state["objectives"].has(obj_id):
				var os: Dictionary = state["objectives"][obj_id]
				if os["status"] == "hidden" or os["status"] == "inactive":
					os["status"] = "active"
	var completes: Variant = branch_def.get("completes_objectives", [])
	if completes is Array:
		for obj_id_raw in completes:
			complete_objective(quest_id, str(obj_id_raw))
	var followup_raw: Variant = branch_def.get("followup_quest_id")
	if followup_raw is String and not (followup_raw as String).is_empty():
		start_quest(followup_raw as String)
	_check_quest_completion(quest_id)

func _check_quest_completion(quest_id: String) -> void:
	if not _quest_states.has(quest_id):
		return
	var state: Dictionary = _quest_states[quest_id]
	if state["status"] != "active":
		return
	var objectives: Dictionary = state["objectives"]
	for obj_id in objectives:
		var s: String = objectives[obj_id]["status"]
		if s != "hidden" and s != "complete" and s != "skipped":
			return
	_cancel_scheduled_handles(quest_id)
	state["status"] = "complete"
	var def: Dictionary = _registry.get(quest_id, {})
	var quest_name: String = str(def.get("name", quest_id))
	MessageLog.post("Quest complete: " + quest_name + ".")
	state["journal_updates"].append({"timestamp": GameTime.get_timestamp_string(), "text": "Quest complete."})
	_distribute_rewards(quest_id)
	if bool(def.get("repeatable", false)):
		_quest_states.erase(quest_id)

func _ready() -> void:
	load_registry(Constants.QUESTS_DATA_PATH)

func _unhandled_input(event: InputEvent) -> void:
	if not GameManager.debug_mode:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F10:
		if start_quest("test_quest_01"):
			MessageLog.post("[DEBUG] Started quest: test_quest_01")
		else:
			MessageLog.post("[DEBUG] test_quest_01 already started or cannot start")
