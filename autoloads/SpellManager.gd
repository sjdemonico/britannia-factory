extends Node

# Emitted when a spell's targeting_type requires interactive UI (targeted or
# point_blank in combat). CombatArena and HUD each connect and respond only
# when they are the active context.
signal spell_targeting_requested(spell_id: String)

var _spells: Dictionary = {}
# Fallback array used before PartyManager._ready() adopts it into the player
# member.  After adoption, _known_spells returns player.known_spells instead.
var _local_known_spells: Array = []
var _known_spells: Array:
	get:
		var player := PartyManager.get_player()
		if player != null:
			return player.known_spells
		return _local_known_spells
var _default_casting_stat: String = "mana"

# When set, all resource checks and consumption use this member instead of player.
# Cleared automatically after attempt_cast() executes.
var _active_caster: PartyMember = null
var _resurrect_target: PartyMember = null

func _ready() -> void:
	load_registry(Constants.SPELLS_CONFIG_PATH)

func load_registry(path: String) -> bool:
	var data: Dictionary = Constants.load_json(path)
	if data.is_empty():
		push_error("SpellManager: failed to load spells from " + path)
		return false
	var raw_default_stat = data.get("default_casting_stat")
	if raw_default_stat is String and not (raw_default_stat as String).is_empty():
		_default_casting_stat = raw_default_stat as String
	var spells_raw: Variant = data.get("spells", [])
	if not spells_raw is Array:
		push_error("SpellManager: missing or invalid 'spells' array in " + path)
		return false
	_spells = {}
	for entry in (spells_raw as Array):
		if not entry is Dictionary:
			push_error("SpellManager: skipping non-dictionary spell entry")
			continue
		var spell: Dictionary = entry as Dictionary
		if not (spell.has("spell_id") and spell.has("name") and spell.has("casting_cost") and spell.has("reagents")):
			push_error("SpellManager: skipping malformed spell entry (missing required fields): " + str(spell))
			continue
		_spells[str(spell["spell_id"])] = spell
	return true

func set_caster(member: PartyMember) -> void:
	_active_caster = member

func clear_caster() -> void:
	_active_caster = null

func _spell_has_resurrect_effect(spell_id: String) -> bool:
	if not _spells.has(spell_id):
		return false
	var effects = _spells[spell_id].get("effects", [])
	if not effects is Array:
		return false
	for e in (effects as Array):
		if e is Dictionary and str(e.get("effect_type", "")) == "resurrect":
			return true
	return false

func _get_caster() -> PartyMember:
	if _active_caster != null:
		return _active_caster
	return PartyManager.get_player()

func get_spell(spell_id: String) -> Dictionary:
	return _spells.get(spell_id, {})

func has_spell(spell_id: String) -> bool:
	return _spells.has(spell_id)

func know_spell(spell_id: String) -> bool:
	if spell_id in _known_spells:
		return false
	if not _spells.has(spell_id):
		push_error("SpellManager: spell not found in registry: " + spell_id)
		return false
	_known_spells.append(spell_id)
	return true

func get_known_spells() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for sid in _known_spells:
		if _spells.has(sid):
			result.append(_spells[sid])
	return result

func get_casting_stat(spell_id: String) -> String:
	if not _spells.has(spell_id):
		return _default_casting_stat
	var raw = _spells[spell_id].get("casting_stat")
	if raw is String and not (raw as String).is_empty():
		return raw as String
	return _default_casting_stat

func can_cast(spell_id: String, current_context: String) -> bool:
	if not _spells.has(spell_id):
		return false
	var spell: Dictionary = _spells[spell_id]
	var spell_context: String = str(spell.get("context", "any"))
	if spell_context != "any" and spell_context != current_context:
		return false
	var casting_stat: String = get_casting_stat(spell_id)
	var casting_cost: int = int(spell.get("casting_cost", 0))
	var caster := _get_caster()
	if caster != null and caster.member_id != Constants.PLAYER_MEMBER_ID:
		if spell_id not in caster.known_spells:
			return false
		if caster.stat_block == null or caster.stat_block.get_effective_value(casting_stat) < casting_cost:
			return false
		return _get_missing_reagents_from(spell_id, caster.inventory).is_empty()
	if PlayerStats.get_effective_value(casting_stat) < casting_cost:
		return false
	return get_missing_reagents(spell_id).is_empty()

func get_missing_reagents(spell_id: String) -> Array:
	if not _spells.has(spell_id):
		return []
	var spell: Dictionary = _spells[spell_id]
	var reagents: Variant = spell.get("reagents", [])
	if not reagents is Array:
		return []
	var missing: Array = []
	var inv: Inventory = PlayerInventory.get_inventory()
	for reagent_id in (reagents as Array):
		var rid: String = str(reagent_id)
		if _count_in_inventory(inv, rid) < 1:
			missing.append(rid)
	return missing

func _get_missing_reagents_from(spell_id: String, inv: Inventory) -> Array:
	if not _spells.has(spell_id) or inv == null:
		return []
	var spell: Dictionary = _spells[spell_id]
	var reagents: Variant = spell.get("reagents", [])
	if not reagents is Array:
		return []
	var missing: Array = []
	for reagent_id in (reagents as Array):
		if _count_in_inventory(inv, str(reagent_id)) < 1:
			missing.append(str(reagent_id))
	return missing

# Unified entry point called by SpellbookPanel. Handles can-cast check and
# dispatches: none/self execute immediately; targeted/point_blank emit
# spell_targeting_requested for the active scene to handle.
func cast_spell(spell_id: String) -> void:
	var current_context: String = "combat" if CombatManager.in_combat else "world"
	# Resurrect in world: prompt for downed member as target, skip normal caster prompt
	if not CombatManager.in_combat and _spell_has_resurrect_effect(spell_id):
		var downed := PartyManager.get_downed_members()
		if downed.is_empty():
			MessageLog.post(MessageRegistry.get_message("resurrect_no_target"))
			MessageLog.post_blank()
			return
		if GameManager.current_region != null:
			var player_node = GameManager.current_region.get_node_or_null("Actors/Player")
			if player_node != null and player_node.has_method("prompt_party_member_for_resurrect"):
				player_node.prompt_party_member_for_resurrect(
					func(member: PartyMember):
						_resurrect_target = member
						_do_cast_spell(spell_id, current_context),
					func(): pass
				)
				return
		_resurrect_target = downed[0]
		_do_cast_spell(spell_id, current_context)
		return
	# Which-caster prompt when party has multiple living members (world only)
	if not CombatManager.in_combat and PartyManager.get_living_members().size() > 1 and GameManager.current_region != null:
		var player_node = GameManager.current_region.get_node_or_null("Actors/Player")
		if player_node != null and player_node.has_method("prompt_party_member"):
			player_node.prompt_party_member(
				func(member: PartyMember):
					_active_caster = member
					_do_cast_spell(spell_id, current_context),
				func(): pass
			)
			return
	_do_cast_spell(spell_id, current_context)

func _do_cast_spell(spell_id: String, current_context: String) -> void:
	if not can_cast(spell_id, current_context):
		_active_caster = null
		_resurrect_target = null
		return
	var spell: Dictionary = _spells[spell_id]
	var targeting_type: String = str(spell.get("targeting_type", "targeted"))
	# Resurrect in world: target already selected, skip tile targeting
	if current_context == "world" and _spell_has_resurrect_effect(spell_id):
		attempt_cast(spell_id)
		return
	match targeting_type:
		"none":
			attempt_cast(spell_id)
		"self":
			var player: Node = null
			if GameManager.current_region != null:
				player = GameManager.current_region.get_node_or_null("Actors/Player")
			attempt_cast(spell_id, player, GameManager.player_tile)
		"point_blank":
			if CombatManager.in_combat:
				spell_targeting_requested.emit(spell_id)
			else:
				attempt_cast(spell_id)
		"targeted":
			spell_targeting_requested.emit(spell_id)

func attempt_cast(spell_id: String, target: Node = null, target_tile: Vector2i = Vector2i(-1, -1), affected_tiles: Array[Vector2i] = [], affected_entities: Array = []) -> bool:
	var current_context: String = "combat" if CombatManager.in_combat else "world"
	if not can_cast(spell_id, current_context):
		_active_caster = null
		return false
	consume_cast_resources(spell_id)
	_active_caster = null
	var spell: Dictionary = _spells[spell_id]
	var player: Node = null
	if GameManager.current_region != null:
		player = GameManager.current_region.get_node_or_null("Actors/Player")
	var spell_name: String = str(spell.get("name", spell_id))
	MessageLog.post(MessageRegistry.get_message("spell_cast", {"name": spell_name}))
	var executor := SpellEffectExecutor.new()
	var effects: Array = spell.get("effects", []) if spell.get("effects") is Array else []
	executor.execute_effects(effects, player, target, target_tile, current_context, affected_tiles, affected_entities)
	_resurrect_target = null
	MessageLog.post_blank()
	return true

func consume_cast_resources(spell_id: String) -> void:
	if not _spells.has(spell_id):
		return
	var spell: Dictionary = _spells[spell_id]
	var casting_stat: String = get_casting_stat(spell_id)
	var casting_cost: int = int(spell.get("casting_cost", 0))
	var reagents: Variant = spell.get("reagents", [])
	var caster := _get_caster()
	if caster != null and caster.member_id != Constants.PLAYER_MEMBER_ID:
		if caster.stat_block != null:
			caster.stat_block.modify_stat(casting_stat, -casting_cost)
		if reagents is Array and caster.inventory != null:
			for reagent_id in (reagents as Array):
				_consume_one_reagent_from(str(reagent_id), caster.inventory)
		return
	PlayerStats.stat_block.modify_stat(casting_stat, -casting_cost)
	if reagents is Array:
		for reagent_id in (reagents as Array):
			_consume_one_reagent(str(reagent_id))

func _count_in_inventory(inv: Inventory, object_id: String) -> int:
	var total: int = 0
	for obj in inv.get_objects():
		if str(obj.get("object_id", "")) == object_id:
			total += int(obj.get("stack_count", 1))
	return total

func _consume_one_reagent(object_id: String) -> void:
	var inv: Inventory = PlayerInventory.get_inventory()
	for obj in inv.get_objects():
		if str(obj.get("object_id", "")) == object_id:
			var iid: int = int(obj.get("instance_id", -1))
			if iid >= 0:
				PlayerInventory.take_from_stack(iid, 1)
				return
	push_error("SpellManager: attempt_cast: could not find reagent '" + object_id + "' to consume")

func _consume_one_reagent_from(object_id: String, inv: Inventory) -> void:
	for obj in inv.get_objects():
		if str(obj.get("object_id", "")) == object_id:
			var iid: int = int(obj.get("instance_id", -1))
			if iid >= 0:
				inv.take_from_stack(iid, 1)
				return
	push_error("SpellManager: could not find reagent '" + object_id + "' in member inventory")
