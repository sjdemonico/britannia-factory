class_name Tooltip
extends PanelContainer

@onready var _name_label: Label = $VBox/NameLabel
@onready var _desc_label: Label = $VBox/DescLabel
@onready var _charges_label: Label = $VBox/ChargesLabel
@onready var _equip_label: Label = $VBox/EquipLabel
@onready var _damage_label: Label = $VBox/DamageLabel
@onready var _armor_label: Label = $VBox/ArmorLabel


func populate(content: Dictionary) -> void:
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
