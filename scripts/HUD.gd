extends Control

@onready var sub_viewport: SubViewport = $MapArea/SubViewportContainer/SubViewport
@onready var dialogue_box: CanvasLayer = $DialogueBox
@onready var inventory_screen: CanvasLayer = $InventoryScreen
@onready var character_panel: CanvasLayer = $CharacterPanel
@onready var journal_panel: CanvasLayer = $JournalPanel

func _ready() -> void:
	GameManager.sub_viewport = sub_viewport
	GameManager.dialogue_box = dialogue_box
	GameManager.inventory_screen = inventory_screen
	GameManager.character_panel = character_panel
	GameManager.journal_panel = journal_panel
	GameManager.load_region(_read_starting_region())

func _read_starting_region() -> String:
	var file := FileAccess.open(Constants.GAME_CONFIG_PATH, FileAccess.READ)
	if file == null:
		return "wilderness"
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return "wilderness"
	var data: Dictionary = json.get_data()
	var region = data.get(Constants.STARTING_REGION_KEY)
	if region is String and not region.is_empty():
		return region
	return "wilderness"
