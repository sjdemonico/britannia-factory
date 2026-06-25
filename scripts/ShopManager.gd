class_name ShopManager
extends RefCounted

var shop_id: String = ""
var _faction_id: String = ""
var _price_multiplier: float = 1.0
var _stock: Dictionary = {}            # object_id -> int (-1 = unlimited)
var _restock_amounts: Dictionary = {}  # object_id -> int
var _restock_handles: Dictionary = {}  # object_id -> GameTime handle (int)

func _cancel_restock_handles() -> void:
	for object_id in _restock_handles:
		GameTime.cancel(_restock_handles[object_id])
	_restock_handles.clear()

func load_shop(shop_def: Dictionary) -> void:
	_cancel_restock_handles()
	shop_id = str(shop_def.get("shop_id", ""))
	var raw_faction = shop_def.get("faction_id")
	_faction_id = str(raw_faction) if raw_faction is String else ""
	_price_multiplier = float(shop_def.get("price_multiplier", 1.0))
	for entry in shop_def.get("inventory", []):
		var object_id: String = str(entry.get("object_id", ""))
		if object_id.is_empty():
			continue
		var stock: int = int(entry.get("stock_count", 0))
		var restock_amount: int = int(entry.get("restock_amount", 0))
		var restock_interval: int = int(entry.get("restock_interval", -1))
		_stock[object_id] = stock
		_restock_amounts[object_id] = restock_amount
		if stock != -1 and restock_interval > 0:
			_schedule_restock(object_id, restock_interval, restock_amount)

func get_stock(object_id: String) -> int:
	return _stock.get(object_id, -2)

func has_stock(object_id: String) -> bool:
	if not _stock.has(object_id):
		return false
	var s: int = _stock[object_id]
	return s == -1 or s > 0

func deplete_stock(object_id: String, amount: int) -> void:
	if not _stock.has(object_id):
		return
	if _stock[object_id] == -1:
		return
	_stock[object_id] = maxi(0, _stock[object_id] - amount)

func get_buy_price(object_id: String) -> int:
	if not _stock.has(object_id):
		return 0
	var data: Dictionary = Inventory.get_object_definition(object_id)
	var base_price: int = int(data.get("base_price", 0))
	if base_price == 0:
		return 0
	var buy_price: int = ceili(float(base_price) * _price_multiplier)
	if not _faction_id.is_empty():
		var tier: Dictionary = FactionManager.get_tier(_faction_id)
		var faction_mult: float = float(tier.get("price_multiplier", 1.0))
		buy_price = ceili(float(buy_price) * faction_mult)
	return buy_price

func get_sell_price(object_id: String) -> int:
	var data: Dictionary = Inventory.get_object_definition(object_id)
	var base_price: int = int(data.get("base_price", 0))
	if base_price == 0:
		return 0
	return floori(float(base_price) * GameManager.sell_multiplier)

func get_inventory() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for object_id in _stock:
		result.append({
			"object_id":   object_id,
			"stock_count": _stock[object_id],
			"buy_price":   get_buy_price(object_id),
			"sell_price":  get_sell_price(object_id)
		})
	return result

func get_stock_snapshot() -> Dictionary:
	return _stock.duplicate()

func get_restock_timer_snapshot() -> Array:
	var result: Array = []
	for object_id in _restock_handles:
		var handle: int = _restock_handles[object_id]
		var entry: Dictionary = GameTime.get_scheduled_entry(handle)
		if entry.is_empty():
			continue
		result.append({
			"object_id":       object_id,
			"remaining_ticks": maxi(1, int(entry["fire_at"]) - GameTime.total_ticks),
			"repeat":          int(entry["repeat"]),
			"restock_amount":  _restock_amounts.get(object_id, 0)
		})
	return result

func restore_stock(snapshot: Dictionary) -> void:
	for object_id in snapshot:
		if _stock.has(str(object_id)):
			_stock[str(object_id)] = int(snapshot[object_id])

func restore_restock_timer(object_id: String, remaining: int, repeat: int, restock_amount: int) -> void:
	if _restock_handles.has(object_id):
		GameTime.cancel(_restock_handles[object_id])
		_restock_handles.erase(object_id)
	var handle: int = GameTime.schedule(
		func(): _on_restock(object_id, restock_amount),
		remaining,
		repeat
	)
	_restock_handles[object_id] = handle

func _schedule_restock(object_id: String, interval_days: int, restock_amount: int) -> void:
	var interval_ticks: int = interval_days * GameTime.ticks_per_hour * GameTime.day_length_hours
	var handle: int = GameTime.schedule(
		func(): _on_restock(object_id, restock_amount),
		interval_ticks,
		interval_ticks
	)
	_restock_handles[object_id] = handle

func _on_restock(object_id: String, restock_amount: int) -> void:
	_stock[object_id] = restock_amount
