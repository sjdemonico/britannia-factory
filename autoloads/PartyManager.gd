extends Node

signal member_added(member: PartyMember)
signal member_removed(member_id: String)
signal member_downed(member_id: String)
signal member_revived(member_id: String)
signal order_changed

var _members: Array[PartyMember] = []
var _max_party_size: int = 4

func _ready() -> void:
	var config: Dictionary = Constants.load_json(Constants.GAME_CONFIG_PATH)
	_max_party_size = int(config.get(Constants.MAX_PARTY_SIZE_KEY, 4))
	# Adopt the objects already created by PlayerStats._ready(), PlayerInventory._ready(),
	# and SpellManager._ready() so that pass-through properties remain coherent before
	# any new game or load is initiated.
	var player := PartyMember.new()
	player.member_id = Constants.PLAYER_MEMBER_ID
	player.display_name = ""
	player.class_id = ""
	player.is_downed = false
	player.stat_block = PlayerStats._stat_block
	player.inventory = PlayerInventory._inv
	player.known_spells = SpellManager._local_known_spells
	_members.append(player)
	PlayerStats.reconnect_stat_block()
	GameTime.tick_advanced.connect(_on_tick_advanced)

func initialize_player(p_name: String, p_class_id: String) -> void:
	_members.clear()
	var player := PartyMember.new()
	player.initialize_as_player(p_name, p_class_id)
	_members.append(player)
	PlayerStats.reconnect_stat_block()

func reset_for_load() -> void:
	_members.clear()
	var player := PartyMember.new()
	player.initialize_as_player("", "")
	_members.append(player)
	PlayerStats.reconnect_stat_block()

func get_player() -> PartyMember:
	for m in _members:
		if m.member_id == Constants.PLAYER_MEMBER_ID:
			return m
	return null

func get_member(member_id: String) -> PartyMember:
	for m in _members:
		if m.member_id == member_id:
			return m
	return null

func get_member_at(index: int) -> PartyMember:
	if index < 0 or index >= _members.size():
		return null
	return _members[index]

func get_all_members() -> Array[PartyMember]:
	return _members.duplicate()

func get_living_members() -> Array[PartyMember]:
	var result: Array[PartyMember] = []
	for m in _members:
		if not m.is_downed:
			result.append(m)
	return result

func get_downed_members() -> Array[PartyMember]:
	var result: Array[PartyMember] = []
	for m in _members:
		if m.is_downed:
			result.append(m)
	return result

func get_party_size() -> int:
	return _members.size()

func get_max_party_size() -> int:
	return _max_party_size

func add_member(member: PartyMember) -> bool:
	if _members.size() >= _max_party_size:
		push_warning("PartyManager: party is full (max %d)" % _max_party_size)
		return false
	_members.append(member)
	member_added.emit(member)
	return true

func remove_member(member_id: String) -> PartyMember:
	for i in range(_members.size()):
		if _members[i].member_id == member_id:
			var removed: PartyMember = _members[i]
			_members.remove_at(i)
			member_removed.emit(member_id)
			return removed
	return null

func set_member_downed(member_id: String, downed: bool) -> void:
	var m := get_member(member_id)
	if m == null or m.is_downed == downed:
		return
	m.is_downed = downed
	if downed:
		member_downed.emit(member_id)
	else:
		member_revived.emit(member_id)

func revive_member(member_id: String) -> void:
	var m := get_member(member_id)
	if m == null or not m.is_downed:
		return
	set_member_downed(member_id, false)
	if m.stat_block != null:
		m.stat_block.set_stat("hp", 1)
		m.stat_block.remove_all_status_effects()

func set_order(ordered_ids: Array[String]) -> void:
	var reordered: Array[PartyMember] = []
	for mid in ordered_ids:
		var m := get_member(mid)
		if m != null:
			reordered.append(m)
	for m in _members:
		if not (m.member_id in ordered_ids):
			reordered.append(m)
	_members = reordered
	order_changed.emit()

func is_party_wiped() -> bool:
	for m in _members:
		if not m.is_downed:
			return false
	return true

func _on_tick_advanced(_total: int) -> void:
	# GameTime.advance() already calls PlayerStats.stat_block.tick() for the player.
	# Tick every other living member here.
	for m in _members:
		if m.is_downed or m.member_id == Constants.PLAYER_MEMBER_ID:
			continue
		if m.stat_block != null:
			m.stat_block.tick()
