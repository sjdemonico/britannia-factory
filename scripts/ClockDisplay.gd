extends VBoxContainer

@onready var left_label: Label = $ClockLine/LeftLabel
@onready var right_label: Label = $ClockLine/RightLabel

func _ready() -> void:
	_update_display()
	GameTime.tick_advanced.connect(_on_tick_advanced)

func _on_tick_advanced(_total: int) -> void:
	_update_display()

func _update_display() -> void:
	left_label.text = GameTime.get_day_name() + "  " + GameTime.format_clock()
	right_label.text = str(GameTime.get_day_of_month()) + " " + GameTime.get_month_name() + ", Year " + str(GameTime.get_year())
