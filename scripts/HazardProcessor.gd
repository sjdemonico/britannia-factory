class_name HazardProcessor
extends RefCounted

func process_tile_entry(entity: Object, tile: Vector2i) -> void:
	_process_tile_hazards(entity, tile, "on_entry")
	_process_trap_objects(entity, tile)

func process_tile_tick(entity: Object, tile: Vector2i) -> void:
	_process_tile_hazards(entity, tile, "continuous")

func _process_tile_hazards(entity: Object, tile: Vector2i, trigger: String) -> void:
	for hazard in _get_tile_hazards(tile):
		if str(hazard.get("trigger", "")) != trigger:
			continue
		var immunity_id: String = str(hazard.get("immunity_id", ""))
		if not immunity_id.is_empty() and _is_immune(entity, immunity_id):
			continue
		_apply_hazard(entity, hazard)

func _process_trap_objects(entity: Object, tile: Vector2i) -> void:
	for obj in GameManager.get_objects_at(tile):
		var wo := obj as WorldObject
		if wo == null:
			continue
		var data: Dictionary = PlayerInventory.get_object_data(wo.object_id)
		if not data.get("trigger_on_entry", false):
			continue
		MessageLog.post(MessageRegistry.get_message("trap_triggered"))
		for action_entry in data.get("use_actions", []):
			var action_name: String = str(action_entry.get("action", ""))
			var action_params: Dictionary = action_entry.get("params", {})
			if action_name == "damage_target":
				var ctx := UseContext.new()
				ctx.target = entity
				GameManager.use_action_registry.execute("damage_target", action_params, ctx)
			elif action_name == "consume":
				var ctx := UseContext.new()
				ctx.target = wo
				GameManager.use_action_registry.execute("consume", action_params, ctx)

func _get_tile_hazards(tile: Vector2i) -> Array:
	var tile_id: String = GameManager.get_world_tile_type(tile)
	if tile_id.is_empty() or GameManager.tile_registry == null:
		return []
	return GameManager.tile_registry.get_hazards(tile_id)

func _apply_hazard(entity: Object, hazard: Dictionary) -> void:
	var hazard_type: String = str(hazard.get("type", ""))
	match hazard_type:
		"damage":
			var amount: int = int(hazard.get("amount", 0))
			entity.get("stat_block").modify_stat("hp", -amount)
			MessageLog.post(MessageRegistry.get_message("hazard_lava_damage", {"name": str(entity.get("display_name"))}))
		"apply_status":
			var modifier_id: String = str(hazard.get("modifier_id", ""))
			if modifier_id.is_empty():
				return
			if _has_status_effect_active(entity, modifier_id):
				return
			entity.get("stat_block").apply_modifier(modifier_id, modifier_id)
			MessageLog.post(MessageRegistry.get_message("hazard_poison_applied", {"name": str(entity.get("display_name"))}))

func _is_immune(entity: Object, immunity_id: String) -> bool:
	if immunity_id.is_empty():
		return false
	var inv = entity.get("inventory")
	if inv == null:
		return false
	for item in inv.get_equipped_items():
		var data: Dictionary = item.get("data", {})
		if immunity_id in data.get("hazard_immunity", []):
			return true
	return false

func _has_status_effect_active(entity: Object, modifier_id: String) -> bool:
	var sb = entity.get("stat_block")
	if sb == null:
		return false
	for mod in sb.get_active_modifiers():
		if str(mod.get("source_tag", "")) == modifier_id:
			return true
	return false
