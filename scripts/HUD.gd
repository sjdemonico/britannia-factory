extends Control

@onready var sub_viewport: SubViewport = $MapArea/SubViewportContainer/SubViewport
@onready var dialogue_box: CanvasLayer = $DialogueBox
@onready var inventory_screen: CanvasLayer = $InventoryScreen
@onready var character_panel: CanvasLayer = $CharacterPanel

func _ready() -> void:
	GameManager.sub_viewport = sub_viewport
	GameManager.dialogue_box = dialogue_box
	GameManager.inventory_screen = inventory_screen
	GameManager.character_panel = character_panel
	GameManager.load_region("res://scenes/world/Wilderness.tscn")
