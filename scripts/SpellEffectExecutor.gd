class_name SpellEffectExecutor
extends RefCounted

var _handlers: Dictionary = {}

func _init() -> void:
	_register_handlers()

func _register_handlers() -> void:
	_handlers["damage"]         = _effect_damage
	_handlers["heal"]           = _effect_heal
	_handlers["apply_modifier"] = _effect_apply_modifier
	_handlers["dispel"]         = _effect_dispel
	_handlers["spawn_object"]   = _effect_spawn_object
	_handlers["transmute"]      = _effect_transmute
	_handlers["unlock"]         = _effect_unlock
	_handlers["teleport"]       = _effect_teleport
	_handlers["displace"]       = _effect_displace
	_handlers["reveal"]         = _effect_reveal
	_handlers["obscure"]        = _effect_obscure
	_handlers["invisibility"]   = _effect_invisibility
	_handlers["charm"]          = _effect_charm
	_handlers["sleep"]          = _effect_sleep
	_handlers["poison"]         = _effect_poison
	_handlers["paralyze"]       = _effect_paralyze

# stat_deltas: Array of {stat_block, stat_id, delta} — collected then applied together.
# affected_entities: non-empty when an AE spell hit multiple combatants; executor
# loops over them instead of using the single target node.
func execute_effects(
		effects: Array,
		caster: Node,
		target: Node,
		target_tile: Vector2i,
		context: String,
		_affected_tiles: Array[Vector2i] = [],
		affected_entities: Array = []) -> void:
	if not affected_entities.is_empty():
		for entity in affected_entities:
			if not (entity is Combatant):
				continue
			var cb: Combatant = entity as Combatant
			var entity_node: Node = cb.node
			var entity_tile: Vector2i = cb.current_tile
			if not is_instance_valid(entity_node):
				continue
			var entity_deltas: Array = []
			for entry in effects:
				if not entry is Dictionary:
					continue
				var effect_type: String = str(entry.get("effect_type", ""))
				var raw_params = entry.get("params")
				var params: Dictionary = raw_params if raw_params is Dictionary else {}
				var handler: Callable = _handlers.get(effect_type, Callable())
				if not handler.is_valid():
					push_error("SpellEffectExecutor: unknown effect type: '" + effect_type + "'")
					continue
				handler.call(params, caster, entity_node, entity_tile, context, entity_deltas)
			for delta_entry in entity_deltas:
				var sb: StatBlock = delta_entry["stat_block"]
				var stat_id: String = delta_entry["stat_id"]
				var delta: int = delta_entry["delta"]
				if sb != null and sb.has_stat(stat_id):
					sb.modify_stat(stat_id, delta)
	else:
		var stat_deltas: Array = []
		for entry in effects:
			if not entry is Dictionary:
				continue
			var effect_type: String = str(entry.get("effect_type", ""))
			var raw_params = entry.get("params")
			var params: Dictionary = raw_params if raw_params is Dictionary else {}
			var handler: Callable = _handlers.get(effect_type, Callable())
			if not handler.is_valid():
				push_error("SpellEffectExecutor: unknown effect type: '" + effect_type + "'")
				continue
			handler.call(params, caster, target, target_tile, context, stat_deltas)
		for delta_entry in stat_deltas:
			var sb: StatBlock = delta_entry["stat_block"]
			var stat_id: String = delta_entry["stat_id"]
			var delta: int = delta_entry["delta"]
			if sb != null and sb.has_stat(stat_id):
				sb.modify_stat(stat_id, delta)

# ── damage ──────────────────────────────────────────────────────────────────

func _effect_damage(params: Dictionary, caster: Node, target: Node,
		_target_tile: Vector2i, _context: String, stat_deltas: Array) -> void:
	if target == null:
		push_warning("SpellEffectExecutor: damage effect requires a target")
		return
	var caster_sb: StatBlock = _get_stat_block(caster)
	var target_sb: StatBlock = _get_stat_block(target)
	var attacker_name: String = _get_combatant_name(caster)
	var defender_name: String = _get_combatant_name(target)
	var caster_inv: Object = PlayerInventory
	if caster is NPC:
		caster_inv = (caster as NPC).npc_inventory
	var target_inv: Object = null
	if target is NPC:
		target_inv = (target as NPC).npc_inventory
	var vars: Dictionary = GameManager.build_combat_variables(caster_sb, caster_inv, target_sb, target_inv)
	if not GameManager.combat_resolver.resolve_hit(vars):
		MessageLog.post(MessageRegistry.get_message("combat_miss", {"attacker": attacker_name, "defender": defender_name}))
		MessageLog.post("")
		return
	var formula: String = str(params.get("formula", "0"))
	var stat_id: String = str(params.get("stat_id", "hp"))
	var amount: int = _evaluate_formula(formula, PlayerStats.stat_block, target_sb)
	stat_deltas.append({"stat_block": target_sb, "stat_id": stat_id, "delta": -amount})
	MessageLog.post(MessageRegistry.get_message("combat_hit", {"attacker": attacker_name, "defender": defender_name, "damage": str(amount)}))
	MessageLog.post("")

# ── heal ─────────────────────────────────────────────────────────────────────

func _effect_heal(params: Dictionary, caster: Node, target: Node,
		_target_tile: Vector2i, _context: String, stat_deltas: Array) -> void:
	var heal_target: Node = target if target != null else caster
	var target_sb: StatBlock = _get_stat_block(heal_target)
	var formula: String = str(params.get("formula", "0"))
	var stat_id: String = str(params.get("stat_id", "hp"))
	var amount: int = _evaluate_formula(formula, PlayerStats.stat_block, target_sb)
	stat_deltas.append({"stat_block": target_sb, "stat_id": stat_id, "delta": amount})
	var target_name: String = _get_combatant_name(heal_target)
	MessageLog.post(MessageRegistry.get_message("spell_healed", {"target": target_name, "amount": str(amount)}))
	MessageLog.post("")

# ── apply_modifier ───────────────────────────────────────────────────────────

func _effect_apply_modifier(params: Dictionary, caster: Node, target: Node,
		_target_tile: Vector2i, _context: String, _stat_deltas: Array) -> void:
	var modifier_id: String = str(params.get("modifier_id", ""))
	var source_tag: String = str(params.get("source_tag", modifier_id))
	if modifier_id.is_empty():
		push_error("SpellEffectExecutor: apply_modifier missing modifier_id")
		return
	var apply_target: Node = target if target != null else caster
	_get_stat_block(apply_target).apply_modifier(modifier_id, source_tag)

# ── dispel ───────────────────────────────────────────────────────────────────

func _effect_dispel(params: Dictionary, caster: Node, target: Node,
		_target_tile: Vector2i, _context: String, _stat_deltas: Array) -> void:
	var source_tag: String = str(params.get("source_tag", ""))
	if source_tag.is_empty():
		push_error("SpellEffectExecutor: dispel missing source_tag")
		return
	var dispel_target: Node = target if target != null else caster
	_get_stat_block(dispel_target).remove_modifiers_by_source(source_tag)
	MessageLog.post(MessageRegistry.get_message("spell_dispel_success"))
	MessageLog.post("")

# ── spawn_object ─────────────────────────────────────────────────────────────

func _effect_spawn_object(params: Dictionary, caster: Node, _target: Node,
		target_tile: Vector2i, _context: String, _stat_deltas: Array) -> void:
	var object_id: String = str(params.get("object_id", ""))
	if object_id.is_empty():
		push_error("SpellEffectExecutor: spawn_object missing object_id")
		return
	var tile: Vector2i = _resolve_tile(params.get("tile", "caster"), caster, target_tile)
	var raw_duration = params.get("duration_ticks")
	if raw_duration == null:
		GameManager.spawn_object(object_id, tile)
	else:
		GameManager.spawn_object_timed(object_id, tile, int(raw_duration))

# ── transmute ────────────────────────────────────────────────────────────────

func _effect_transmute(params: Dictionary, caster: Node, _target: Node,
		target_tile: Vector2i, _context: String, _stat_deltas: Array) -> void:
	var from_id: String = str(params.get("from_object_id", ""))
	var to_id: String = str(params.get("to_object_id", ""))
	var tile: Vector2i = _resolve_tile(params.get("tile", "target"), caster, target_tile)
	for obj in GameManager.get_objects_at(tile):
		var wo: WorldObject = obj as WorldObject
		if wo != null and wo.object_id == from_id:
			WorldState.clear_object_from_tile(tile, from_id)
			var parent: Node = wo.get_parent()
			if parent != null:
				parent.remove_child(wo)
			wo.queue_free()
			GameManager.spawn_object(to_id, tile)
			return
	push_warning("SpellEffectExecutor: transmute: no object '" + from_id + "' at tile " + str(tile))
	MessageLog.post(MessageRegistry.get_message("spell_transmute_no_target"))
	MessageLog.post("")

# ── unlock ───────────────────────────────────────────────────────────────────

func _effect_unlock(params: Dictionary, caster: Node, _target: Node,
		target_tile: Vector2i, _context: String, _stat_deltas: Array) -> void:
	var tile: Vector2i = _resolve_tile(params.get("tile", "target"), caster, target_tile)
	for obj in GameManager.get_objects_at(tile):
		var wo: WorldObject = obj as WorldObject
		if wo != null and wo.toggleable:
			wo.is_open = true
			wo.queue_redraw()
			MessageLog.post(MessageRegistry.get_message("spell_unlock"))
			MessageLog.post("")
			return
	push_warning("SpellEffectExecutor: unlock: no toggleable object at tile " + str(tile))

# ── teleport ─────────────────────────────────────────────────────────────────

func _effect_teleport(params: Dictionary, _caster: Node, _target: Node,
		_target_tile: Vector2i, context: String, _stat_deltas: Array) -> void:
	if context == "combat":
		push_warning("SpellEffectExecutor: teleport cannot be used in combat")
		return
	var region_id: String = str(params.get("region_id", ""))
	if region_id.is_empty():
		push_error("SpellEffectExecutor: teleport missing region_id")
		return
	var spawn_id: String = str(params.get("spawn_id", ""))
	GameManager.load_region(region_id, spawn_id)

# ── displace ─────────────────────────────────────────────────────────────────

func _effect_displace(params: Dictionary, caster: Node, target: Node,
		target_tile: Vector2i, _context: String, _stat_deltas: Array) -> void:
	var target_str: String = str(params.get("target", "target"))
	var direction_str: String = str(params.get("direction", "away_from_caster"))
	var distance: int = int(params.get("distance", 1))

	var is_self: bool = (target_str == "self")
	var entity: Node = caster if is_self else target

	var caster_tile: Vector2i = GameManager.player_tile
	var entity_tile: Vector2i = caster_tile if is_self else target_tile
	if entity is NPC:
		entity_tile = (entity as NPC).npc_tile

	var dir: Vector2i = _resolve_direction(direction_str, caster_tile, entity_tile)
	if dir == Vector2i.ZERO:
		return

	var current_tile: Vector2i = entity_tile
	var blocked: bool = false
	for _i in range(distance):
		var next_tile: Vector2i = current_tile + dir
		if not GameManager.is_tile_passable(next_tile):
			blocked = true
			break
		current_tile = next_tile

	if blocked and current_tile == entity_tile:
		MessageLog.post(MessageRegistry.get_message("spell_displace_blocked"))
		MessageLog.post("")
		return

	if current_tile == entity_tile:
		return

	if is_self or entity == null or not (entity is NPC):
		# Displace player
		var player_node: Node = _get_player_node()
		if player_node != null and player_node.has_method("teleport_to_tile"):
			player_node.call("teleport_to_tile", current_tile)
	else:
		# Displace NPC in world context
		var npc: NPC = entity as NPC
		WorldState.clear_occupant(npc.npc_tile)
		npc.npc_tile = current_tile
		npc.position = Constants.tile_to_world(current_tile)
		WorldState.set_occupant(current_tile, {"type": "npc", "id": npc.npc_id, "node": npc})

	if blocked:
		MessageLog.post(MessageRegistry.get_message("spell_displace_blocked"))
		MessageLog.post("")

# ── reveal ───────────────────────────────────────────────────────────────────

func _effect_reveal(params: Dictionary, _caster: Node, _target: Node,
		_target_tile: Vector2i, _context: String, _stat_deltas: Array) -> void:
	var modifier_id: String = str(params.get("modifier_id", "spell_reveal_vision"))
	PlayerStats.stat_block.apply_modifier(modifier_id, modifier_id)

# ── obscure ──────────────────────────────────────────────────────────────────

func _effect_obscure(params: Dictionary, caster: Node, target: Node,
		_target_tile: Vector2i, _context: String, _stat_deltas: Array) -> void:
	var modifier_id: String = str(params.get("modifier_id", "spell_obscure_vision"))
	var apply_target: Node = target if target != null else caster
	_get_stat_block(apply_target).apply_modifier(modifier_id, modifier_id)

# ── invisibility ─────────────────────────────────────────────────────────────

func _effect_invisibility(params: Dictionary, caster: Node, target: Node,
		_target_tile: Vector2i, _context: String, _stat_deltas: Array) -> void:
	var modifier_id: String = str(params.get("modifier_id", "spell_invisibility"))
	var target_str: String = str(params.get("target", "self"))

	var entity: Node = caster if target_str == "self" else (target if target != null else caster)
	_get_stat_block(entity).apply_modifier(modifier_id, modifier_id)

	if entity is NPC:
		(entity as NPC).is_invisible = true
	else:
		var player_node: Node = _get_player_node()
		if player_node != null:
			player_node.set("is_invisible", true)
		if CombatManager.in_combat:
			CombatManager.trigger_all_npc_flee()

# ── charm ────────────────────────────────────────────────────────────────────

func _effect_charm(params: Dictionary, _caster: Node, target: Node,
		_target_tile: Vector2i, _context: String, _stat_deltas: Array) -> void:
	if target == null or not (target is NPC):
		push_warning("SpellEffectExecutor: charm requires an NPC target")
		return
	var npc: NPC = target as NPC
	var dur: int = int(params.get("duration_ticks", 200))
	var orig_hostile: bool = npc.hostile
	npc.availability = "available"
	npc.hostile = false
	MessageLog.post(MessageRegistry.get_message("spell_charm_success", {"name": npc.display_name}))
	MessageLog.post("")
	var npc_ref: NPC = npc
	GameTime.schedule(func():
		if is_instance_valid(npc_ref):
			npc_ref.availability = "default"
			npc_ref.hostile = orig_hostile
	, dur)

# ── sleep ────────────────────────────────────────────────────────────────────

func _effect_sleep(params: Dictionary, _caster: Node, target: Node,
		_target_tile: Vector2i, _context: String, _stat_deltas: Array) -> void:
	if target == null or not (target is NPC):
		push_warning("SpellEffectExecutor: sleep requires an NPC target")
		return
	var npc: NPC = target as NPC
	var dur: int = int(params.get("duration_ticks", 100))
	var orig_hostile: bool = npc.hostile
	var orig_talkable: bool = npc._talkable
	npc.availability = "unconscious"
	npc.hostile = false
	npc._talkable = false
	MessageLog.post(MessageRegistry.get_message("spell_sleep_success", {"name": npc.display_name}))
	MessageLog.post("")
	var npc_ref: NPC = npc
	GameTime.schedule(func():
		if is_instance_valid(npc_ref):
			npc_ref.availability = "default"
			npc_ref.hostile = orig_hostile
			npc_ref._talkable = orig_talkable
	, dur)

# ── poison ───────────────────────────────────────────────────────────────────

func _effect_poison(params: Dictionary, caster: Node, target: Node,
		_target_tile: Vector2i, _context: String, _stat_deltas: Array) -> void:
	var modifier_id: String = str(params.get("modifier_id", "spell_poison"))
	var apply_target: Node = target if target != null else caster
	_get_stat_block(apply_target).apply_modifier(modifier_id, modifier_id)

# ── paralyze ─────────────────────────────────────────────────────────────────

func _effect_paralyze(params: Dictionary, caster: Node, target: Node,
		_target_tile: Vector2i, _context: String, _stat_deltas: Array) -> void:
	var dur: int = int(params.get("duration_ticks", 50))
	var entity: Node = target if target != null else caster
	if entity == null:
		entity = _get_player_node()
	if entity == null:
		return
	entity.set("is_paralyzed", true)
	var entity_ref: WeakRef = weakref(entity)
	GameTime.schedule(func():
		var e: Object = entity_ref.get_ref()
		if e != null and is_instance_valid(e as Node):
			(e as Node).set("is_paralyzed", false)
	, dur)
	var entity_name: String = ""
	if entity is NPC:
		entity_name = (entity as NPC).display_name
	else:
		entity_name = PlayerStats.display_name
	MessageLog.post(MessageRegistry.get_message("spell_paralyze_success", {"name": entity_name}))
	MessageLog.post("")

# ── helpers ───────────────────────────────────────────────────────────────────

func _get_combatant_name(node: Node) -> String:
	if node is NPC:
		return (node as NPC).display_name
	return "You"

func _get_stat_block(node: Node) -> StatBlock:
	if node is NPC:
		return (node as NPC).stat_block
	return PlayerStats.stat_block

func _get_player_node() -> Node:
	if GameManager.current_region == null:
		return null
	return GameManager.current_region.get_node_or_null("Actors/Player")

func _resolve_tile(tile_param: Variant, _caster: Node, target_tile: Vector2i) -> Vector2i:
	if tile_param is Array and (tile_param as Array).size() == 2:
		return Vector2i(int((tile_param as Array)[0]), int((tile_param as Array)[1]))
	match str(tile_param):
		"target": return target_tile
		_: return GameManager.player_tile  # "caster" or fallback

func _resolve_direction(direction_str: String, caster_tile: Vector2i, entity_tile: Vector2i) -> Vector2i:
	match direction_str:
		"north":     return Vector2i(0, -1)
		"south":     return Vector2i(0, 1)
		"east":      return Vector2i(1, 0)
		"west":      return Vector2i(-1, 0)
		"northeast": return Vector2i(1, -1)
		"northwest": return Vector2i(-1, -1)
		"southeast": return Vector2i(1, 1)
		"southwest": return Vector2i(-1, 1)
		"away_from_caster":
			var diff: Vector2i = entity_tile - caster_tile
			if diff == Vector2i.ZERO:
				return Vector2i.ZERO
			return Vector2i(sign(diff.x), 0) if abs(diff.x) >= abs(diff.y) else Vector2i(0, sign(diff.y))
		"toward_caster":
			var diff: Vector2i = caster_tile - entity_tile
			if diff == Vector2i.ZERO:
				return Vector2i.ZERO
			return Vector2i(sign(diff.x), 0) if abs(diff.x) >= abs(diff.y) else Vector2i(0, sign(diff.y))
	return Vector2i.ZERO

func _evaluate_formula(formula: String, caster_stats: StatBlock, target_stats: StatBlock) -> int:
	var var_names: PackedStringArray = []
	var values: Array = []
	var safe_formula: String = formula
	var idx: int = 0
	for stat_id in caster_stats._stats:
		var placeholder: String = "v%d" % idx
		safe_formula = _replace_token(safe_formula, stat_id, placeholder)
		var_names.append(placeholder)
		values.append(caster_stats.get_effective_value(stat_id))
		idx += 1
	var t_defense: int = 0
	var t_hp: int = 0
	if target_stats != null:
		if target_stats.has_stat("defense"):
			t_defense = target_stats.get_effective_value("defense")
		if target_stats.has_stat("hp"):
			t_hp = target_stats.get_value("hp")
	safe_formula = _replace_token(safe_formula, "target_defense", "v%d" % idx)
	var_names.append("v%d" % idx)
	values.append(t_defense)
	idx += 1
	safe_formula = _replace_token(safe_formula, "target_hp", "v%d" % idx)
	var_names.append("v%d" % idx)
	values.append(t_hp)
	var expr := Expression.new()
	if expr.parse(safe_formula, var_names) != OK:
		push_error("SpellEffectExecutor: formula parse error: " + formula)
		return 0
	var result = expr.execute(values)
	if expr.has_execute_failed():
		push_error("SpellEffectExecutor: formula execute failed: " + formula)
		return 0
	return maxi(0, int(result))

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
