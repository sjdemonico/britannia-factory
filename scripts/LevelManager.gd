class_name LevelManager
extends RefCounted

var stat_gains: Dictionary = {}
var _thresholds: Array = []

func load_config(thresholds: Array, gains: Dictionary) -> void:
	_thresholds = thresholds
	stat_gains = gains

func get_level_for_experience(experience: int) -> int:
	var level: int = 1
	for i in range(_thresholds.size()):
		if experience >= _thresholds[i]:
			level = i + 1
		else:
			break
	return level

func get_next_threshold(experience: int) -> int:
	for t in _thresholds:
		if t > experience:
			return t
	return -1  # at or past max level threshold

func check_level_up(old_experience: int, new_experience: int) -> int:
	return get_level_for_experience(new_experience) - get_level_for_experience(old_experience)
