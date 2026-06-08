class_name StatBlock extends RefCounted

signal stat_changed(stat_id: String, old_value: int, new_value: int)
signal modifier_applied(modifier_id: String, instance_id: int)
signal modifier_removed(modifier_id: String, instance_id: int)

var _stats: Dictionary = {}
var _base_stats: Dictionary = {}
var _derived_stats: Dictionary = {}
var _modifiers: Dictionary = {}          # stat_id -> Array of active modifier instances
var _modifier_registry: Dictionary = {}  # modifier_id -> modifier definition
var _next_instance_id: int = 0
var _regen_stats: Array = []             # entries: {stat_id, regen_per_tick, regen_interval, ticks_since_last_regen}
var _suppression_sources: Dictionary = {}  # source_tag -> true

func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("StatBlock: file not found: " + path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("StatBlock: could not open: " + path)
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("StatBlock: JSON parse error in " + path + ": " + json.get_error_message())
		return false
	var data = json.data
	if not data is Dictionary or not data.has("stats") or not data["stats"] is Array:
		push_error("StatBlock: malformed stat definition in " + path)
		return false
	_stats = {}
	_base_stats = {}
	_derived_stats = {}
	_modifiers = {}
	_regen_stats = []
	_suppression_sources = {}
	_next_instance_id = 0
	# First pass: load base stats
	for s in data["stats"]:
		if not s.has("id"):
			push_error("StatBlock: stat missing 'id' in " + path)
			continue
		if s.get("derived", false):
			continue
		var entry: Dictionary = {
			"id": s["id"],
			"name": s.get("name", s["id"]),
			"visible": s.get("visible", true),
			"display_format": s.get("display_format", "{value}"),
			"current_value": s.get("base_value", 0),
			"min_value": s.get("min_value", 0),
			"max_value": s.get("max_value", 100)
		}
		_stats[s["id"]] = entry
		_base_stats[s["id"]] = entry
	# Second pass: load and validate derived stats
	for s in data["stats"]:
		if not s.has("id") or not s.get("derived", false):
			continue
		if not s.has("formula"):
			push_error("StatBlock: derived stat '" + s["id"] + "' missing formula in " + path)
			continue
		var formula: String = s["formula"]
		var min_val: int = s.get("min_value", 0)
		var max_val: int = s.get("max_value", 100)
		var args := _build_expression_inputs(formula)
		var expr := Expression.new()
		if expr.parse(args["formula"], args["var_names"]) != OK:
			push_error("StatBlock: formula parse error for '" + s["id"] + "': " + formula + " in " + path)
			continue
		var test_result = expr.execute(args["values"])
		if expr.has_execute_failed():
			push_error("StatBlock: formula execute error for '" + s["id"] + "': " + formula + " in " + path)
			continue
		var initial_val: int = clampi(int(test_result), min_val, max_val)
		var entry: Dictionary = {
			"id": s["id"],
			"name": s.get("name", s["id"]),
			"visible": s.get("visible", true),
			"display_format": s.get("display_format", "{value}"),
			"current_value": initial_val,
			"min_value": min_val,
			"max_value": max_val,
			"formula": formula
		}
		_stats[s["id"]] = entry
		_derived_stats[s["id"]] = entry
	# Third pass: build regen entries (base stats only)
	for s in data["stats"]:
		if not s.has("id") or s.get("derived", false):
			continue
		var rpt: int = s.get("regen_per_tick", 0)
		if rpt == 0 or not _base_stats.has(s["id"]):
			continue
		var ri: int = s.get("regen_interval", 1)
		_regen_stats.append({
			"stat_id": s["id"],
			"regen_per_tick": rpt,
			"regen_interval": ri,
			"ticks_since_last_regen": 0
		})
	_load_modifier_registry()
	return true

func _load_modifier_registry() -> void:
	_modifier_registry = {}
	if not FileAccess.file_exists(Constants.MODIFIER_REGISTRY_PATH):
		return
	var file := FileAccess.open(Constants.MODIFIER_REGISTRY_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("StatBlock: modifier registry parse error")
		return
	var data = json.data
	if not data is Dictionary or not data.has("modifiers") or not data["modifiers"] is Array:
		push_error("StatBlock: malformed modifier registry")
		return
	for m in data["modifiers"]:
		if m.has("modifier_id"):
			_modifier_registry[m["modifier_id"]] = m

func suppress_regen(source_tag: String) -> void:
	_suppression_sources[source_tag] = true

func unsuppress_regen(source_tag: String) -> void:
	if not _suppression_sources.has(source_tag):
		push_warning("StatBlock: suppression source not found: " + source_tag)
		return
	_suppression_sources.erase(source_tag)

func is_regen_suppressed() -> bool:
	return not _suppression_sources.is_empty()

func apply_modifier(modifier_id: String, source_tag: String) -> int:
	if not _modifier_registry.has(modifier_id):
		push_error("StatBlock: modifier not found: " + modifier_id)
		return -1
	var def: Dictionary = _modifier_registry[modifier_id]
	var stat_id: String = def["stat_id"]
	if not _stats.has(stat_id):
		return -1
	var magnitude = def["magnitude"]
	var stacking: String = def["stacking"]
	var duration_type: String = def["duration_type"]
	if duration_type == "one_shot":
		modify_stat(stat_id, int(magnitude))
		return -1
	var old_direct_eff: int = get_effective_value(stat_id)
	var old_derived: Dictionary = _capture_derived_effectives_except(stat_id)
	var instance_id: int = _next_instance_id
	_next_instance_id += 1
	var ticks_remaining = null
	var ticks_since_last_application = null
	var interval = null
	var lifetime_remaining = null
	if duration_type == "ticks":
		ticks_remaining = int(def.get("duration_value", 0))
	elif duration_type == "per_tick":
		interval = int(def.get("duration_value", 1))
		ticks_since_last_application = 0
		var lt: int = int(def.get("lifetime_ticks", 0))
		if lt > 0:
			lifetime_remaining = lt
	var instance: Dictionary = {
		"modifier_id": modifier_id,
		"instance_id": instance_id,
		"source_tag": source_tag,
		"magnitude": magnitude,
		"stacking": stacking,
		"duration_type": duration_type,
		"ticks_remaining": ticks_remaining,
		"ticks_since_last_application": ticks_since_last_application,
		"interval": interval,
		"lifetime_remaining": lifetime_remaining
	}
	if not _modifiers.has(stat_id):
		_modifiers[stat_id] = []
	_modifiers[stat_id].append(instance)
	# per_tick modifiers do not affect get_effective_value, so no emit for them
	if duration_type != "per_tick":
		var new_direct_eff: int = get_effective_value(stat_id)
		if new_direct_eff != old_direct_eff:
			stat_changed.emit(stat_id, old_direct_eff, new_direct_eff)
		_emit_changed_derived_stats(old_derived)
	modifier_applied.emit(modifier_id, instance_id)
	return instance_id

func remove_modifier(instance_id: int) -> bool:
	for stat_id in _modifiers:
		var arr: Array = _modifiers[stat_id]
		for i in arr.size():
			if arr[i]["instance_id"] == instance_id:
				var mod_id: String = arr[i]["modifier_id"]
				var duration_type: String = arr[i]["duration_type"]
				var old_direct_eff: int = get_effective_value(stat_id)
				var old_derived: Dictionary = _capture_derived_effectives_except(stat_id)
				arr.remove_at(i)
				if duration_type != "per_tick":
					var new_direct_eff: int = get_effective_value(stat_id)
					if new_direct_eff != old_direct_eff:
						stat_changed.emit(stat_id, old_direct_eff, new_direct_eff)
					_emit_changed_derived_stats(old_derived)
				modifier_removed.emit(mod_id, instance_id)
				return true
	push_warning("StatBlock: modifier instance not found: " + str(instance_id))
	return false

func get_effective_value(stat_id: String) -> int:
	if not _stats.has(stat_id):
		push_error("StatBlock: stat not found: " + stat_id)
		return 0
	var s: Dictionary = _stats[stat_id]
	# Derived stats: re-evaluate formula using effective values of input base stats.
	var base: int
	if _derived_stats.has(stat_id):
		base = _evaluate_formula_effective(s["formula"], s["min_value"], s["max_value"])
	else:
		base = s["current_value"]
	if not _modifiers.has(stat_id) or _modifiers[stat_id].is_empty():
		return base
	var mods: Array = _modifiers[stat_id]
	var additive_sum: float = 0.0
	var exclusive_max: float = -1e38
	var has_exclusive: bool = false
	var excl_per_source: Dictionary = {}
	var mult_product: float = 1.0
	for mod in mods:
		# per_tick modifiers apply their effect via modify_stat each interval,
		# not via the effective value formula.
		if mod["duration_type"] == "per_tick":
			continue
		var mag: float = float(mod["magnitude"])
		match mod["stacking"]:
			"additive":
				additive_sum += mag
			"exclusive":
				has_exclusive = true
				if mag > exclusive_max:
					exclusive_max = mag
			"exclusive_per_source":
				var src: String = mod["source_tag"]
				if not excl_per_source.has(src) or mag > excl_per_source[src]:
					excl_per_source[src] = mag
			"multiplicative":
				mult_product *= mag
	if has_exclusive:
		additive_sum += exclusive_max
	for src in excl_per_source:
		additive_sum += excl_per_source[src]
	return clampi(floori((float(base) + additive_sum) * mult_product), s["min_value"], s["max_value"])

func tick() -> void:
	# Step 1: Expire ticks-duration modifiers (immediate emit).
	var to_remove: Array = []
	for stat_id in _modifiers:
		var arr: Array = _modifiers[stat_id]
		for j in arr.size():
			if arr[j]["duration_type"] == "ticks":
				arr[j]["ticks_remaining"] -= 1
				if arr[j]["ticks_remaining"] <= 0:
					to_remove.append({
						"stat_id": stat_id,
						"instance_id": arr[j]["instance_id"],
						"modifier_id": arr[j]["modifier_id"]
					})
			elif arr[j]["duration_type"] == "per_tick" and arr[j]["lifetime_remaining"] != null:
				arr[j]["lifetime_remaining"] -= 1
				if arr[j]["lifetime_remaining"] <= 0:
					to_remove.append({
						"stat_id": stat_id,
						"instance_id": arr[j]["instance_id"],
						"modifier_id": arr[j]["modifier_id"]
					})
	if not to_remove.is_empty():
		var old_effectives: Dictionary = {}
		for item in to_remove:
			var sid: String = item["stat_id"]
			if not old_effectives.has(sid):
				old_effectives[sid] = get_effective_value(sid)
		for derived_id in _derived_stats:
			if not old_effectives.has(derived_id):
				old_effectives[derived_id] = get_effective_value(derived_id)
		for item in to_remove:
			var sid: String = item["stat_id"]
			var iid: int = item["instance_id"]
			var arr: Array = _modifiers[sid]
			for i in range(arr.size() - 1, -1, -1):
				if arr[i]["instance_id"] == iid:
					arr.remove_at(i)
					break
			modifier_removed.emit(item["modifier_id"], iid)
		for sid in old_effectives:
			var new_eff: int = get_effective_value(sid)
			if new_eff != old_effectives[sid]:
				stat_changed.emit(sid, old_effectives[sid], new_eff)

	# Step 2: Skip regen and per_tick if suppressed.
	if is_regen_suppressed():
		return

	# Capture pre-regen current_value for every stat for batch emit.
	var pre_regen: Dictionary = {}
	for stat_id in _stats:
		pre_regen[stat_id] = _stats[stat_id]["current_value"]

	# Step 3: Process stat regen.
	for entry in _regen_stats:
		entry["ticks_since_last_regen"] += 1
		if entry["ticks_since_last_regen"] >= entry["regen_interval"]:
			_set_stat_silent(entry["stat_id"],
				_stats[entry["stat_id"]]["current_value"] + entry["regen_per_tick"])
			entry["ticks_since_last_regen"] = 0

	# Step 4: Process per_tick modifiers.
	for stat_id in _modifiers:
		var arr: Array = _modifiers[stat_id]
		for j in arr.size():
			if arr[j]["duration_type"] == "per_tick":
				arr[j]["ticks_since_last_application"] += 1
				if arr[j]["ticks_since_last_application"] >= arr[j]["interval"]:
					_set_stat_silent(stat_id,
						_stats[stat_id]["current_value"] + int(arr[j]["magnitude"]))
					arr[j]["ticks_since_last_application"] = 0

	# Step 5: Emit stat_changed once per stat that actually changed.
	for stat_id in pre_regen:
		var new_val: int = _stats[stat_id]["current_value"]
		if new_val != pre_regen[stat_id]:
			stat_changed.emit(stat_id, pre_regen[stat_id], new_val)

func remove_modifiers_by_source(source_tag: String) -> void:
	var to_remove: Array[int] = []
	for stat_id in _modifiers:
		for mod in _modifiers[stat_id]:
			if mod["source_tag"] == source_tag:
				to_remove.append(mod["instance_id"])
	for iid in to_remove:
		remove_modifier(iid)

func has_modifier_def(modifier_id: String) -> bool:
	return _modifier_registry.has(modifier_id)

func get_active_modifiers() -> Array:
	var result: Array = []
	for stat_id in _modifiers:
		for mod in _modifiers[stat_id]:
			var name: String = _modifier_registry.get(mod["modifier_id"], {}).get("name", mod["modifier_id"])
			result.append({"instance_id": mod["instance_id"], "name": name, "source_tag": mod["source_tag"]})
	return result

func _set_stat_silent(stat_id: String, value: int) -> bool:
	if not _stats.has(stat_id) or _derived_stats.has(stat_id):
		return false
	var s: Dictionary = _stats[stat_id]
	var clamped: int = clampi(value, s["min_value"], s["max_value"])
	if clamped == s["current_value"]:
		return false
	s["current_value"] = clamped
	for derived_id in _derived_stats:
		var ds: Dictionary = _derived_stats[derived_id]
		ds["current_value"] = _evaluate_formula(ds["formula"], ds["min_value"], ds["max_value"])
	return true

func _capture_derived_effectives_except(skip_stat_id: String) -> Dictionary:
	var result: Dictionary = {}
	for derived_id in _derived_stats:
		if derived_id != skip_stat_id:
			result[derived_id] = get_effective_value(derived_id)
	return result

func _emit_changed_derived_stats(old_effectives: Dictionary) -> void:
	for derived_id in old_effectives:
		var new_eff: int = get_effective_value(derived_id)
		if new_eff != old_effectives[derived_id]:
			stat_changed.emit(derived_id, old_effectives[derived_id], new_eff)

# Translates a formula using stat IDs as tokens into one using safe indexed
# placeholders (v0, v1, ...) to avoid conflicts with Expression built-in names.
func _build_expression_inputs(formula: String) -> Dictionary:
	var var_names: PackedStringArray = []
	var values: Array = []
	var safe_formula: String = formula
	var i: int = 0
	for id in _base_stats:
		var placeholder: String = "v%d" % i
		safe_formula = _replace_token(safe_formula, id, placeholder)
		var_names.append(placeholder)
		values.append(_base_stats[id]["current_value"])
		i += 1
	return {"formula": safe_formula, "var_names": var_names, "values": values}

func _build_expression_inputs_effective(formula: String) -> Dictionary:
	var var_names: PackedStringArray = []
	var values: Array = []
	var safe_formula: String = formula
	var i: int = 0
	for id in _base_stats:
		var placeholder: String = "v%d" % i
		safe_formula = _replace_token(safe_formula, id, placeholder)
		var_names.append(placeholder)
		values.append(get_effective_value(id))
		i += 1
	return {"formula": safe_formula, "var_names": var_names, "values": values}

func _replace_token(text: String, token: String, replacement: String) -> String:
	var result := ""
	var i := 0
	var tlen := token.length()
	while i < text.length():
		if text.substr(i, tlen) == token:
			var before_ok: bool = (i == 0) or not _is_ident_char(text[i - 1])
			var after_end: bool = (i + tlen >= text.length())
			var after_ok: bool = after_end or not _is_ident_char(text[i + tlen])
			if before_ok and after_ok:
				result += replacement
				i += tlen
				continue
		result += text[i]
		i += 1
	return result

func _is_ident_char(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_"

func _evaluate_formula(formula: String, min_val: int, max_val: int) -> int:
	var args := _build_expression_inputs(formula)
	var expr := Expression.new()
	if expr.parse(args["formula"], args["var_names"]) != OK:
		push_error("StatBlock: runtime formula parse error: " + formula)
		return 0
	var result = expr.execute(args["values"])
	if expr.has_execute_failed():
		push_error("StatBlock: runtime formula execute error: " + formula)
		return 0
	return clampi(int(result), min_val, max_val)

func _evaluate_formula_effective(formula: String, min_val: int, max_val: int) -> int:
	var args := _build_expression_inputs_effective(formula)
	var expr := Expression.new()
	if expr.parse(args["formula"], args["var_names"]) != OK:
		push_error("StatBlock: runtime formula parse error: " + formula)
		return 0
	var result = expr.execute(args["values"])
	if expr.has_execute_failed():
		push_error("StatBlock: runtime formula execute error: " + formula)
		return 0
	return clampi(int(result), min_val, max_val)

func get_value(stat_id: String) -> int:
	if not _stats.has(stat_id):
		push_error("StatBlock: stat not found: " + stat_id)
		return 0
	return _stats[stat_id]["current_value"]

func get_max(stat_id: String) -> int:
	if not _stats.has(stat_id):
		push_error("StatBlock: stat not found: " + stat_id)
		return 0
	return _stats[stat_id]["max_value"]

func get_min(stat_id: String) -> int:
	if not _stats.has(stat_id):
		push_error("StatBlock: stat not found: " + stat_id)
		return 0
	return _stats[stat_id]["min_value"]

func has_stat(stat_id: String) -> bool:
	return _stats.has(stat_id)

func set_stat(stat_id: String, value: int) -> void:
	if not _stats.has(stat_id):
		push_error("StatBlock: stat not found: " + stat_id)
		return
	if _derived_stats.has(stat_id):
		push_warning("StatBlock: cannot directly set derived stat: " + stat_id)
		return
	var s: Dictionary = _stats[stat_id]
	var clamped: int = clampi(value, s["min_value"], s["max_value"])
	if clamped == s["current_value"]:
		return
	var old_value: int = s["current_value"]
	s["current_value"] = clamped
	stat_changed.emit(stat_id, old_value, clamped)
	for derived_id in _derived_stats:
		var ds: Dictionary = _derived_stats[derived_id]
		var new_val: int = _evaluate_formula(ds["formula"], ds["min_value"], ds["max_value"])
		if new_val != ds["current_value"]:
			var old_ds: int = ds["current_value"]
			ds["current_value"] = new_val
			stat_changed.emit(derived_id, old_ds, new_val)

func modify_stat(stat_id: String, delta: int) -> void:
	set_stat(stat_id, get_value(stat_id) + delta)

func raise_cap(stat_id: String, amount: int) -> void:
	if not _base_stats.has(stat_id):
		push_error("StatBlock: raise_cap requires a base stat: " + stat_id)
		return
	_stats[stat_id]["max_value"] += amount
	modify_stat(stat_id, amount)

func get_visible_stats() -> Array:
	var result: Array = []
	for stat_id in _stats:
		if _stats[stat_id]["visible"]:
			result.append(_stats[stat_id])
	return result

func get_all_stats() -> Array:
	var result: Array = []
	for stat_id in _stats:
		result.append(_stats[stat_id])
	return result

func format_stat(stat_id: String) -> String:
	if not _stats.has(stat_id):
		push_error("StatBlock: stat not found: " + stat_id)
		return ""
	var s: Dictionary = _stats[stat_id]
	var result: String = s["display_format"]
	result = result.replace("{value}", str(s["current_value"]))
	result = result.replace("{max}", str(s["max_value"]))
	return result

func format_effective_stat(stat_id: String) -> String:
	if not _stats.has(stat_id):
		push_error("StatBlock: stat not found: " + stat_id)
		return ""
	var s: Dictionary = _stats[stat_id]
	var result: String = s["display_format"]
	result = result.replace("{value}", str(get_effective_value(stat_id)))
	result = result.replace("{max}", str(s["max_value"]))
	return result
