extends VBoxContainer

@onready var left_label: Label = $ClockLine/LeftLabel
@onready var right_label: Label = $ClockLine/RightLabel

var _last_hour: int = -1
var _last_minute: int = -1
var _last_dom: int = -1
var _last_month: int = -1
var _last_year: int = -1

func _ready() -> void:
	_update_display()
	GameTime.tick_advanced.connect(_on_tick_advanced)

func _on_tick_advanced(_total: int) -> void:
	var h := GameTime.get_hour()
	var m := GameTime.get_minute()
	var dom := GameTime.get_day_of_month()
	var mo := GameTime.get_month()
	var yr := GameTime.get_year()
	if h == _last_hour and m == _last_minute and dom == _last_dom and mo == _last_month and yr == _last_year:
		return
	_last_hour = h
	_last_minute = m
	_last_dom = dom
	_last_month = mo
	_last_year = yr
	_update_display()

func _update_display() -> void:
	left_label.text = GameTime.get_day_name() + "  " + GameTime.format_clock()
	right_label.text = str(GameTime.get_day_of_month()) + " " + GameTime.get_month_name() + ", Year " + str(GameTime.get_year())
