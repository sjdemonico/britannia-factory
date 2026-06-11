extends Node

signal tick_advanced(total_ticks: int)
signal hour_changed(hour: int)
signal day_changed(day: int)
signal week_changed(week: int)
signal month_changed(month: int)
signal season_changed(season: String)
signal year_changed(year: int)
signal time_period_changed(period: String)

var total_ticks: int = 0
var ticks_per_hour: int = 60
var day_length_hours: int = 24
var clock_format: String = "12h"
var _ticks_per_day: int = 1440
var _starting_hour: int = 6
var _time_periods: Dictionary = {"dawn": 5, "day": 7, "dusk": 19, "night": 21}
var _rest_ticks_per_second: int = 20
var _sorted_periods: Array = []

var _calendar: Dictionary = {}
var _days_per_week: int = 7
var _days_per_month: int = 28
var _days_per_year: int = 336
var _starting_day_of_week: int = 0
var _calendar_day_offset: int = 0

var _season_map: Dictionary = {}
var _current_season: String = ""

var _scheduled: Dictionary = {}
var _next_handle: int = 0

func _ready() -> void:
	_load_config()
	_rebuild_sorted_periods()
	total_ticks = _starting_hour * ticks_per_hour
	_current_season = _season_map.get(get_month(), "")

func _load_config() -> void:
	var file := FileAccess.open(Constants.GAME_CONFIG_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		return
	var data: Dictionary = json.get_data()
	ticks_per_hour = data.get("ticks_per_hour", ticks_per_hour)
	day_length_hours = data.get("day_length_hours", day_length_hours)
	clock_format = data.get("clock_format", clock_format)
	_starting_hour = data.get("starting_hour", _starting_hour)
	_rest_ticks_per_second = data.get("rest_ticks_per_second", _rest_ticks_per_second)
	_ticks_per_day = ticks_per_hour * day_length_hours
	if data.has("time_periods"):
		_time_periods = data["time_periods"]
	if data.has("calendar"):
		_calendar = data["calendar"]
		_days_per_week = _calendar.get("days_per_week", 7)
		var weeks_per_month: int = _calendar.get("weeks_per_month", 4)
		var months_per_year: int = _calendar.get("months_per_year", 12)
		_days_per_month = _days_per_week * weeks_per_month
		_days_per_year = _days_per_month * months_per_year
		_starting_day_of_week = _calendar.get("starting_day_of_week", 0)
		var start_dom: int = _calendar.get("starting_day_of_month", 1)
		var start_month: int = _calendar.get("starting_month", 1)
		var start_year: int = _calendar.get("starting_year", 1)
		_calendar_day_offset = (start_year - 1) * _days_per_year \
			+ (start_month - 1) * _days_per_month \
			+ (start_dom - 1)
		if _calendar.has("seasons"):
			_build_season_map(_calendar["seasons"], months_per_year)

func _build_season_map(seasons: Array, months_per_year: int) -> void:
	_season_map = {}
	var seen: Dictionary = {}
	for entry in seasons:
		var season_name: String = entry.get("name", "Unknown")
		for month in entry.get("months", []):
			var m: int = int(month)
			if seen.has(m):
				push_error("GameTime: month %d appears in multiple seasons ('%s' and '%s')" % [m, seen[m], season_name])
				continue
			seen[m] = season_name
			_season_map[m] = season_name
	for m in range(1, months_per_year + 1):
		if not _season_map.has(m):
			push_error("GameTime: month %d is not mapped to any season" % m)

func _rebuild_sorted_periods() -> void:
	_sorted_periods = []
	for p_name in _time_periods:
		_sorted_periods.append({"name": p_name, "hour": _time_periods[p_name]})
	_sorted_periods.sort_custom(func(a, b): return a["hour"] < b["hour"])

func advance(ticks: int = 1) -> void:
	for _i in ticks:
		var old_hour := get_hour()
		var old_day := get_day()
		var old_period := get_time_period()
		var old_month := get_month()
		var old_year := get_year()
		total_ticks += 1
		PlayerStats.stat_block.tick()
		tick_advanced.emit(total_ticks)
		_fire_scheduled()
		var new_hour := get_hour()
		var new_day := get_day()
		var new_period := get_time_period()
		var new_month := get_month()
		var new_year := get_year()
		if new_hour != old_hour:
			hour_changed.emit(new_hour)
		if new_day != old_day:
			day_changed.emit(new_day)
			if get_day_of_week() == 0:
				week_changed.emit(get_week_of_month())
		if new_month != old_month:
			month_changed.emit(new_month)
		if new_year != old_year:
			year_changed.emit(new_year)
		var season: String = _season_map.get(new_month, "")
		if season != _current_season:
			_current_season = season
			season_changed.emit(_current_season)
		if new_period != old_period:
			time_period_changed.emit(new_period)

func get_total_ticks() -> int:
	return total_ticks

func get_hour() -> int:
	@warning_ignore("integer_division")
	return (total_ticks / ticks_per_hour) % day_length_hours

func get_minute() -> int:
	@warning_ignore("integer_division")
	return (total_ticks % ticks_per_hour) * 60 / ticks_per_hour

func get_day() -> int:
	@warning_ignore("integer_division")
	return (total_ticks / _ticks_per_day) + 1

func get_time_period() -> String:
	var hour := get_hour()
	var result: String = _sorted_periods.back()["name"] if not _sorted_periods.is_empty() else "day"
	for p in _sorted_periods:
		if hour >= p["hour"]:
			result = p["name"]
	return result

func _get_absolute_day() -> int:
	@warning_ignore("integer_division")
	return (total_ticks / _ticks_per_day) + _calendar_day_offset

func get_day_of_week() -> int:
	return (_get_absolute_day() + _starting_day_of_week) % _days_per_week

func get_day_name() -> String:
	var names: Array = _calendar.get("day_names", [])
	var dow := get_day_of_week()
	if dow < names.size():
		return names[dow]
	return str(dow + 1)

func get_day_of_month() -> int:
	return _get_absolute_day() % _days_per_month + 1

func get_week_of_month() -> int:
	@warning_ignore("integer_division")
	return (get_day_of_month() - 1) / _days_per_week + 1

func get_month() -> int:
	@warning_ignore("integer_division")
	return (_get_absolute_day() % _days_per_year) / _days_per_month + 1

func get_month_name() -> String:
	var names: Array = _calendar.get("month_names", [])
	var m := get_month() - 1
	if m < names.size():
		return names[m]
	return str(m + 1)

func get_year() -> int:
	@warning_ignore("integer_division")
	return _get_absolute_day() / _days_per_year + 1

func get_season() -> String:
	return _current_season

func format_clock() -> String:
	var h := get_hour()
	var m := get_minute()
	if clock_format == "12h":
		var suffix := "AM" if h < 12 else "PM"
		var display_h := h % 12
		if display_h == 0:
			display_h = 12
		return "%d:%02d %s" % [display_h, m, suffix]
	return "%02d:%02d" % [h, m]

func hours_to_ticks(hours: int) -> int:
	return hours * ticks_per_hour

func ticks_to_hours(ticks: int) -> float:
	return float(ticks) / float(ticks_per_hour)

func get_rest_ticks_per_second() -> int:
	return _rest_ticks_per_second

func get_timestamp_string() -> String:
	return "Day " + str(get_day()) + ", " + format_clock()

func schedule(callback: Callable, ticks_from_now: int, repeat: int = 0) -> int:
	var handle: int = _next_handle
	_next_handle += 1
	_scheduled[handle] = {
		"callback": callback,
		"fire_at": total_ticks + ticks_from_now,
		"repeat": repeat
	}
	return handle

func cancel(handle: int) -> void:
	_scheduled.erase(handle)

func _fire_scheduled() -> void:
	if _scheduled.is_empty():
		return
	var handles: Array = _scheduled.keys()
	for handle in handles:
		if not _scheduled.has(handle):
			continue
		var entry: Dictionary = _scheduled[handle]
		if total_ticks < entry["fire_at"]:
			continue
		var cb: Callable = entry["callback"]
		var repeat: int = entry["repeat"]
		if repeat > 0:
			entry["fire_at"] = total_ticks + repeat
		else:
			_scheduled.erase(handle)
		cb.call()
