extends Node

var _music_player_a: AudioStreamPlayer
var _music_player_b: AudioStreamPlayer
var _music_active: String = "a"
var _crossfade_duration: float = 1.0
var _ambient_player: AudioStreamPlayer
var _current_music_path: String = ""
var _current_ambient_path: String = ""
var _music_tween: Tween = null

var _sound_registry: Dictionary = {}

var _music_priority: String = "none"
var _region_music_path: String = ""
var _time_music_path: String = ""
var _combat_music_path: String = ""

var _ambient_players: Dictionary = {}
var _ambient_tweens: Dictionary = {}
var _current_ambient_tile_type: String = ""
var _pending_ambient_tile_type: String = ""
var _ambient_change_delay: float = 3.0
var _ambient_timer_seq: int = 0

var _volume_master: float = 1.0
var _volume_music: float = 0.8
var _volume_sfx: float = 1.0
var _volume_ambient: float = 0.6
var _audio_defaults: Dictionary = {}

func _ready() -> void:
	var game_data: Dictionary = Constants.load_json(Constants.GAME_CONFIG_PATH)
	var audio_cfg: Dictionary = game_data.get("audio", {})
	var vol_cfg: Dictionary = audio_cfg.get("volume", {})
	_crossfade_duration = float(audio_cfg.get("music_crossfade_duration", 1.0))
	_ambient_change_delay = float(audio_cfg.get("ambient_change_delay", 3.0))
	_volume_master  = float(vol_cfg.get("master",  1.0))
	_volume_music   = float(vol_cfg.get("music",   0.8))
	_volume_sfx     = float(vol_cfg.get("sfx",     1.0))
	_volume_ambient = float(vol_cfg.get("ambient", 0.6))
	_audio_defaults = {
		"master": _volume_master, "music": _volume_music,
		"sfx": _volume_sfx, "ambient": _volume_ambient
	}
	var bus_layout_path = audio_cfg.get("bus_layout_path")
	if bus_layout_path is String and not (bus_layout_path as String).is_empty() and ResourceLoader.exists(bus_layout_path):
		AudioServer.set_bus_layout(load(bus_layout_path) as AudioBusLayout)
	_ensure_buses()
	_load_preferences()
	_apply_bus_volumes()
	_music_player_a = AudioStreamPlayer.new()
	_music_player_a.bus = Constants.AUDIO_BUS_MUSIC
	add_child(_music_player_a)
	_music_player_b = AudioStreamPlayer.new()
	_music_player_b.bus = Constants.AUDIO_BUS_MUSIC
	add_child(_music_player_b)
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = Constants.AUDIO_BUS_AMBIENT
	add_child(_ambient_player)
	_load_sound_registry()

func _ensure_buses() -> void:
	for bus_name in [Constants.AUDIO_BUS_MUSIC, Constants.AUDIO_BUS_SFX, Constants.AUDIO_BUS_AMBIENT]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx: int = AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, Constants.AUDIO_BUS_MASTER)

func _load_sound_registry() -> void:
	var data: Dictionary = Constants.load_json(Constants.SOUNDS_CONFIG_PATH)
	_sound_registry = data

func play_event(event_id: String) -> void:
	if event_id.is_empty():
		return
	var path = _sound_registry.get(event_id, null)
	if not path is String or (path as String).is_empty():
		return
	play_sfx(path)

func get_registry(event_id: String) -> String:
	if event_id.is_empty():
		return ""
	var path = _sound_registry.get(event_id, null)
	if not path is String or (path as String).is_empty():
		return ""
	return path as String

func play_sfx(path: String) -> void:
	if path == null or path.is_empty():
		return
	var stream := _load_audio(path)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.bus = Constants.AUDIO_BUS_SFX
	player.stream = stream
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

func play_music(path: String) -> void:
	if path == null or path.is_empty():
		stop_music()
		return
	if path == _current_music_path:
		return
	var stream := _load_audio(path)
	if stream == null:
		return
	_current_music_path = path
	_crossfade_music(stream)

func stop_music() -> void:
	if _music_tween != null and _music_tween.is_running():
		_music_tween.kill()
	if _music_player_a != null:
		_music_player_a.stop()
	if _music_player_b != null:
		_music_player_b.stop()
	_current_music_path = ""

func play_ambient(path: String) -> void:
	if path == null or path.is_empty():
		stop_ambient()
		return
	if path == _current_ambient_path and _ambient_player.playing:
		return
	var stream := _load_audio(path)
	if stream == null:
		return
	_current_ambient_path = path
	_set_stream_looping(stream)
	_ambient_player.stream = stream
	_ambient_player.play()

func stop_ambient() -> void:
	if _ambient_player != null:
		_ambient_player.stop()
	_current_ambient_path = ""

func set_volume(bus: String, value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	match bus:
		Constants.AUDIO_BUS_MASTER:  _volume_master = value
		Constants.AUDIO_BUS_MUSIC:   _volume_music = value
		Constants.AUDIO_BUS_SFX:     _volume_sfx = value
		Constants.AUDIO_BUS_AMBIENT: _volume_ambient = value
		_: return
	var idx: int = AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, _to_db(value))
	_save_preferences()

func get_volume(bus: String) -> float:
	match bus:
		Constants.AUDIO_BUS_MASTER:  return _volume_master
		Constants.AUDIO_BUS_MUSIC:   return _volume_music
		Constants.AUDIO_BUS_SFX:     return _volume_sfx
		Constants.AUDIO_BUS_AMBIENT: return _volume_ambient
	return 0.0

func _load_audio(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if path.begins_with("res://") or path.begins_with("user://"):
		if not ResourceLoader.exists(path):
			return null
		return load(path) as AudioStream
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	if path.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_buffer(bytes)
	if path.ends_with(".mp3"):
		var stream := AudioStreamMP3.new()
		stream.data = bytes
		return stream
	return null

func _to_db(linear: float) -> float:
	if linear <= 0.001:
		return -80.0
	return linear_to_db(linear)

func _apply_bus_volumes() -> void:
	for pair in [
		[Constants.AUDIO_BUS_MASTER,  _volume_master],
		[Constants.AUDIO_BUS_MUSIC,   _volume_music],
		[Constants.AUDIO_BUS_SFX,     _volume_sfx],
		[Constants.AUDIO_BUS_AMBIENT, _volume_ambient]
	]:
		var idx: int = AudioServer.get_bus_index(pair[0])
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, _to_db(pair[1]))

func _crossfade_music(new_stream: AudioStream) -> void:
	if _music_tween != null and _music_tween.is_running():
		_music_tween.kill()
		_music_player_a.stop()
		_music_player_b.stop()
		_music_active = "a"
	var active := _music_player_a if _music_active == "a" else _music_player_b
	var inactive := _music_player_b if _music_active == "a" else _music_player_a
	var next_active := "b" if _music_active == "a" else "a"
	inactive.stream = new_stream
	inactive.volume_db = -80.0
	inactive.play()
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	if active.playing:
		_music_tween.tween_property(active, "volume_db", -80.0, _crossfade_duration)
	_music_tween.tween_property(inactive, "volume_db", 0.0, _crossfade_duration)
	_music_tween.finished.connect(func():
		active.stop()
		_music_active = next_active
		_music_tween = null
	, CONNECT_ONE_SHOT)

func _set_stream_looping(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD

func _save_preferences() -> void:
	var data: Dictionary = {
		"volume": {
			"master":  _volume_master,
			"music":   _volume_music,
			"sfx":     _volume_sfx,
			"ambient": _volume_ambient
		}
	}
	var file := FileAccess.open(Constants.PREFERENCES_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func set_region_music(path) -> void:
	_region_music_path = path as String if path is String else ""
	_resolve_music()

func set_time_music(path) -> void:
	_time_music_path = path as String if path is String else ""
	_resolve_music()

func set_combat_music(path: String) -> void:
	_combat_music_path = path
	_resolve_music()

func _resolve_music() -> void:
	var target_path: String = ""
	var target_priority: String = "none"
	if not _combat_music_path.is_empty():
		target_path = _combat_music_path
		target_priority = "combat"
	elif not _time_music_path.is_empty():
		target_path = _time_music_path
		target_priority = "time_of_day"
	elif not _region_music_path.is_empty():
		target_path = _region_music_path
		target_priority = "region"
	_music_priority = target_priority
	if target_path != _current_music_path:
		play_music(target_path)

func on_player_tile_changed(tile_type_id: String) -> void:
	if tile_type_id == _pending_ambient_tile_type:
		return
	_pending_ambient_tile_type = tile_type_id
	_ambient_timer_seq += 1
	var seq := _ambient_timer_seq
	if tile_type_id == _current_ambient_tile_type:
		return
	get_tree().create_timer(_ambient_change_delay).timeout.connect(func():
		if seq == _ambient_timer_seq:
			_switch_ambient(_pending_ambient_tile_type)
	, CONNECT_ONE_SHOT)

func _switch_ambient(tile_type_id: String) -> void:
	var tile_def: Dictionary = {}
	if GameManager.tile_registry != null:
		tile_def = GameManager.tile_registry.get_tile(tile_type_id)
	var ambient_path = tile_def.get("ambient_sound", null)

	if not _current_ambient_tile_type.is_empty() and _ambient_players.has(_current_ambient_tile_type):
		_crossfade_out_ambient(_current_ambient_tile_type, _ambient_players[_current_ambient_tile_type])

	_current_ambient_tile_type = tile_type_id

	if not ambient_path is String or (ambient_path as String).is_empty():
		return

	if _ambient_players.has(tile_type_id) and _ambient_players[tile_type_id].playing:
		return

	var player := _get_or_create_ambient_player(tile_type_id)
	var stream := _load_audio(ambient_path as String)
	if stream == null:
		return
	_set_stream_looping(stream)
	player.stream = stream
	player.bus = Constants.AUDIO_BUS_AMBIENT
	player.volume_db = -80.0
	player.play()
	_crossfade_in_ambient(tile_type_id, player)

func _get_or_create_ambient_player(tile_type_id: String) -> AudioStreamPlayer:
	if _ambient_players.has(tile_type_id):
		return _ambient_players[tile_type_id]
	var player := AudioStreamPlayer.new()
	player.bus = Constants.AUDIO_BUS_AMBIENT
	add_child(player)
	_ambient_players[tile_type_id] = player
	return player

func _crossfade_out_ambient(tile_type_id: String, player: AudioStreamPlayer) -> void:
	if _ambient_tweens.has(tile_type_id):
		(_ambient_tweens[tile_type_id] as Tween).kill()
	var tween := create_tween()
	_ambient_tweens[tile_type_id] = tween
	tween.tween_property(player, "volume_db", -80.0, _crossfade_duration)
	tween.finished.connect(func():
		player.stop()
		_ambient_tweens.erase(tile_type_id)
	, CONNECT_ONE_SHOT)

func _crossfade_in_ambient(tile_type_id: String, player: AudioStreamPlayer) -> void:
	if _ambient_tweens.has(tile_type_id):
		(_ambient_tweens[tile_type_id] as Tween).kill()
	var tween := create_tween()
	_ambient_tweens[tile_type_id] = tween
	tween.tween_property(player, "volume_db", 0.0, _crossfade_duration)
	tween.finished.connect(func():
		_ambient_tweens.erase(tile_type_id)
	, CONNECT_ONE_SHOT)

func _clear_ambient() -> void:
	for tt in _ambient_tweens.keys():
		(_ambient_tweens[tt] as Tween).kill()
	_ambient_tweens.clear()
	for player in _ambient_players.values():
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	_ambient_players.clear()
	_current_ambient_tile_type = ""
	_pending_ambient_tile_type = ""
	_ambient_timer_seq += 1

func _load_preferences() -> void:
	if not FileAccess.file_exists(Constants.PREFERENCES_PATH):
		return
	var file := FileAccess.open(Constants.PREFERENCES_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	var text := file.get_as_text()
	file.close()
	if json.parse(text) != OK:
		push_warning("SoundManager: failed to parse preferences at " + Constants.PREFERENCES_PATH)
		return
	var result = json.get_data()
	if not result is Dictionary:
		return
	var vol: Dictionary = (result as Dictionary).get("volume", {})
	if not vol is Dictionary:
		return
	_volume_master  = clampf(float(vol.get("master",  _audio_defaults.get("master",  1.0))), 0.0, 1.0)
	_volume_music   = clampf(float(vol.get("music",   _audio_defaults.get("music",   0.8))), 0.0, 1.0)
	_volume_sfx     = clampf(float(vol.get("sfx",     _audio_defaults.get("sfx",     1.0))), 0.0, 1.0)
	_volume_ambient = clampf(float(vol.get("ambient", _audio_defaults.get("ambient", 0.6))), 0.0, 1.0)
