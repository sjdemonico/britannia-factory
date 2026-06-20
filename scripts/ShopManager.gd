class_name ShopManager
extends RefCounted

var shop_id: String = ""
var _price_multiplier: float = 1.0
var _stock: Dictionary = {}            # object_id -> int (-1 = unlimited)
var _restock_amounts: Dictionary = {}  # object_id -> int
var _restock_handles: Dictionary = {}  # object_id -> GameTime handle (int)

func load_shop(shop_def: Dictionary) -> void:
	shop_id = str(shop_def.get("shop_id", ""))
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
	return ceili(float(base_price) * _price_multiplier)

func get_sell_price(object_id: String) -> int:
	var data: Dictionary = Inventory.get_object_definition(object_id)
	var base_price: int = int(data.get("base_price", 0))
	if base_price == 0:
		return 0
	return floori(float(base_price) * 0.5)

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
