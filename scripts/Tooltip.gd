class_name Tooltip
extends PanelContainer

@onready var _sprite_area: TextureRect = $VBox/SpriteArea
@onready var _name_label: Label = $VBox/NameLabel

var _sprite_handle: int = -1
@onready var _desc_label: Label = $VBox/DescLabel
@onready var _charges_label: Label = $VBox/ChargesLabel
@onready var _equip_label: Label = $VBox/EquipLabel
@onready var _damage_label: Label = $VBox/DamageLabel
@onready var _armor_label: Label = $VBox/ArmorLabel

func _ready() -> void:
	_apply_fonts()

func _apply_fonts() -> void:
	for lbl in [_name_label]:
		if GameManager.get_font(Constants.FONT_HEADER_ROLE):
			lbl.add_theme_font_override("font", GameManager.get_font(Constants.FONT_HEADER_ROLE))
		lbl.add_theme_font_size_override("font_size", GameManager.get_font_size(Constants.FONT_HEADER_ROLE))
	for lbl in [_desc_label, _charges_label, _equip_label, _damage_label, _armor_label]:
		if GameManager.get_font(Constants.FONT_BODY_ROLE):
			lbl.add_theme_font_override("font", GameManager.get_font(Constants.FONT_BODY_ROLE))
		lbl.add_theme_font_size_override("font_size", GameManager.get_font_size(Constants.FONT_BODY_ROLE))

func populate(content: Dictionary) -> void:
	if _sprite_handle >= 0 and GameManager.sprite_animator != null:
		GameManager.sprite_animator.unregister(_sprite_handle)
		_sprite_handle = -1
	_sprite_area.texture = null
	_sprite_area.visible = false
	var sp = content.get("sprite_path", null)
	if sp != null:
		_sprite_handle = GameManager.sprite_animator.register(
			_sprite_area, sp, Constants.SPRITE_SOURCE_SIZE)
		_sprite_area.visible = _sprite_handle >= 0

	_name_label.text = content.get("name", "")
	_name_label.visible = _name_label.text != ""

	_desc_label.text = content.get("description", "")
	_desc_label.visible = _desc_label.text != ""

	var charges = content.get("charges", null)
	_charges_label.text = "Charges: %d" % charges if charges != null else ""
	_charges_label.visible = charges != null

	var equip_type = content.get("equipment_type", null)
	_equip_label.text = equip_type if equip_type != null else ""
	_equip_label.visible = equip_type != null

	var base_damage = content.get("base_damage", null)
	_damage_label.text = "Damage: %s" % str(base_damage) if base_damage != null else ""
	_damage_label.visible = base_damage != null

	var base_armor = content.get("base_armor", null)
	_armor_label.text = "Armor: %s" % str(base_armor) if base_armor != null else ""
	_armor_label.visible = base_armor != null

func clear_sprite() -> void:
	if _sprite_handle >= 0 and GameManager.sprite_animator != null:
		GameManager.sprite_animator.unregister(_sprite_handle)
		_sprite_handle = -1
	_sprite_area.texture = null
	_sprite_area.visible = false
