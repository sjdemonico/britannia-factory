extends Control

@onready var sub_viewport: SubViewport = $MapArea/SubViewportContainer/SubViewport
@onready var dialogue_box: CanvasLayer = $DialogueBox
@onready var inventory_screen: CanvasLayer = $InventoryScreen
@onready var character_panel: CanvasLayer = $CharacterPanel
@onready var journal_panel: CanvasLayer = $JournalPanel
@onready var save_load_panel = $SaveLoadPanel
@onready var spellbook_panel: CanvasLayer = $SpellbookPanel

var _world_reticle: TargetingReticle = null

func _ready() -> void:
	var darkness_overlay := DarknessOverlay.new()
	sub_viewport.add_child(darkness_overlay)
	_world_reticle = TargetingReticle.new()
	sub_viewport.add_child(_world_reticle)
	GameManager.darkness_overlay = darkness_overlay
	GameManager.sub_viewport = sub_viewport
	GameManager.dialogue_box = dialogue_box
	GameManager.inventory_screen = inventory_screen
	GameManager.character_panel = character_panel
	GameManager.journal_panel = journal_panel
	GameManager.save_load_panel = save_load_panel
	GameManager.spellbook_panel = spellbook_panel
	SpellManager.spell_targeting_requested.connect(_on_spell_targeting_requested)
	GameManager.on_hud_ready()

func _on_spell_targeting_requested(spell_id: String) -> void:
	if CombatManager.in_combat:
		return  # CombatArena handles it via its own connection.
	_start_world_spell_targeting(spell_id)

func _start_world_spell_targeting(spell_id: String) -> void:
	var region: Node = GameManager.current_region
	if region == null:
		return
	var player_node: Node = region.get_node_or_null("Actors/Player")
	if player_node == null or not player_node.has_method("start_spell_targeting"):
		return
	var tilemap: TileMapLayer = region.get_node_or_null("TerrainLayer")
	var spell: Dictionary = SpellManager.get_spell(spell_id)
	var spell_range: int = SpellTargeting.get_spell_range(spell)

	_world_reticle.activate(GameManager.player_tile)
	_world_reticle.set_ae_tiles(SpellTargeting.compute_ae_tiles(
		spell, GameManager.player_tile, GameManager.player_tile, tilemap))

	player_node.start_spell_targeting(
		spell_range,
		func(tile: Vector2i) -> void:
			_world_reticle.move_to(tile)
			_world_reticle.set_ae_tiles(SpellTargeting.compute_ae_tiles(
				spell, GameManager.player_tile, tile, tilemap)),
		func(tile: Vector2i) -> void:
			_world_reticle.deactivate()
			_complete_world_spell_cast(spell_id, tile, tilemap),
		func() -> void:
			_world_reticle.deactivate()
			MessageLog.post(MessageRegistry.get_message("spell_cancelled"))
			MessageLog.post("")
	)

func _complete_world_spell_cast(spell_id: String, target_tile: Vector2i, tilemap: TileMapLayer) -> void:
	var target_node: Node = WorldState.get_npc_at_tile(target_tile)
	var spell: Dictionary = SpellManager.get_spell(spell_id)
	var ae_tiles := SpellTargeting.compute_ae_tiles(spell, GameManager.player_tile, target_tile, tilemap)
	SpellManager.attempt_cast(spell_id, target_node, target_tile, ae_tiles)
