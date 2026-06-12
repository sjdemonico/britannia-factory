extends Control

@onready var sub_viewport: SubViewport = $MapArea/SubViewportContainer/SubViewport
@onready var dialogue_box: CanvasLayer = $DialogueBox
@onready var inventory_screen: CanvasLayer = $InventoryScreen
@onready var character_panel: CanvasLayer = $CharacterPanel
@onready var journal_panel: CanvasLayer = $JournalPanel
@onready var save_load_panel = $SaveLoadPanel

func _ready() -> void:
	var darkness_overlay := DarknessOverlay.new()
	sub_viewport.add_child(darkness_overlay)
	GameManager.darkness_overlay = darkness_overlay
	GameManager.sub_viewport = sub_viewport
	GameManager.dialogue_box = dialogue_box
	GameManager.inventory_screen = inventory_screen
	GameManager.character_panel = character_panel
	GameManager.journal_panel = journal_panel
	GameManager.save_load_panel = save_load_panel
	GameManager.on_hud_ready()
