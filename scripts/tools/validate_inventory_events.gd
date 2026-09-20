## TECH-01 / INV-EV: регрессионная проверка сигналов Inventory.
## Запуск: godot --headless -s res://scripts/tools/validate_inventory_events.gd
extends SceneTree

const MAX_INT := 9223372036854775807

var inv: Node = null
var errors: Array[String] = []
var original_items: Array = []
var original_capacity: int = 50
var next_instance: int = 1

# Наблюдения, заполняемые общими callback'ами.
var added_obs: Array[Dictionary] = []
var removed_obs: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	inv = root.get_node("Inventory")
	if inv == null:
		errors.append("Inventory autoload not found in scene tree")
		_finish()
		return
	original_items = inv.items.duplicate(true)
	original_capacity = inv.max_capacity
	# Подключаем свои callback'ы один раз перед всеми сценариями.
	inv.item_added.connect(_on_item_added)
	inv.item_removed.connect(_on_item_removed)
	_reset()
	_test_s1()
	_reset()
	_test_s2()
	_reset()
	_test_s3()
	_reset()
	_test_s4()
	_reset()
	_test_s5()
	# Отключаем именно свои callback'ы до восстановления исходных данных.
	if inv.item_added.is_connected(_on_item_added):
		inv.item_added.disconnect(_on_item_added)
	if inv.item_removed.is_connected(_on_item_removed):
		inv.item_removed.disconnect(_on_item_removed)
	inv.items = original_items.duplicate(true)
	inv.max_capacity = original_capacity
	_finish()


func _finish() -> void:
	if errors.is_empty():
		print("ASHBOUND_INVENTORY_EVENTS_OK")
		quit(0)
	else:
		print("FAILED:")
		for e in errors:
			print("  - " + e)
		quit(1)


func _on_item_added(payload: Dictionary) -> void:
	var total: int = 0
	for entry in inv.items:
		if str(entry.get("id", "")) == str(payload.get("id", "")):
			total += int(entry.get("quantity", 0))
	var belongs: bool = false
	for entry in inv.items:
		if is_same(entry, payload):
			belongs = true
			break
	# Исходный id копируем как String ДО любых изменений.
	added_obs.append({
		"total": total,
		"instance_id": str(payload.get("instance_id", "")),
		"quantity": int(payload.get("quantity", 0)),
		"belongs": belongs,
	})


func _on_item_removed(item_id: String) -> void:
	var total: int = 0
	for entry in inv.items:
		if str(entry.get("id", "")) == item_id:
			total += int(entry.get("quantity", 0))
	removed_obs.append({"id": item_id, "total": total})


func _reset() -> void:
	inv.items = []
	inv.max_capacity = original_capacity
	added_obs.clear()
	removed_obs.clear()
	next_instance = 1


func _check(cond: bool, name: String) -> void:
	if not cond:
		errors.append(name)


func _make(item_id: String, quantity: int) -> Dictionary:
	var item: Dictionary = inv.item_database[item_id].duplicate(true)
	item["quantity"] = quantity
	item["instance_id"] = str(next_instance)
	next_instance += 1
	return item


func _total(item_id: String) -> int:
	var total: int = 0
	for entry in inv.items:
		if str(entry.get("id", "")) == item_id:
			total += int(entry.get("quantity", 0))
	return total


func _stack_quantities(item_id: String) -> Array[int]:
	var result: Array[int] = []
	for entry in inv.items:
		if str(entry.get("id", "")) == item_id:
			result.append(int(entry.get("quantity", 1)))
	return result


# S1: capacity2, bread19 + sword1. add bread1 -> 20, словари и id сохранены;
# следующий add bread1 false, полный снимок и счётчики не меняются.
func _test_s1() -> void:
	inv.max_capacity = 2
	var bread: Dictionary = _make("bread", 19)
	var sword: Dictionary = _make("iron_sword", 1)
	inv.items = [bread, sword]
	var bread_id_before: String = str(bread.get("instance_id", ""))
	var ok: bool = inv.add_item("bread", 1)
	_check(ok, "S1: add_item(bread,1) должен вернуть true")
	_check(inv.items.size() == 2, "S1: после добавления остаётся 2 слота")
	if inv.items.size() >= 2:
		_check(int(inv.items[0].get("quantity", -1)) == 20, "S1: bread quantity == 20")
		_check(is_same(inv.items[0], bread), "S1: словарь bread тот же (is_same)")
		_check(str(inv.items[0].get("instance_id", "")) == bread_id_before, "S1: id bread сохранён")
		_check(is_same(inv.items[1], sword), "S1: словарь sword тот же (is_same)")
	var snap_before: Array = inv.items.duplicate(true)
	var added_before: int = added_obs.size()
	var removed_before: int = removed_obs.size()
	var ok2: bool = inv.add_item("bread", 1)
	_check(not ok2, "S1: повторный add_item(bread,1) должен вернуть false")
	_check(inv.items.duplicate(true) == snap_before, "S1: полный снимок не изменился после отказа")
	_check(added_obs.size() == added_before, "S1: новых сигналов item_added нет")
	_check(removed_obs.size() == removed_before, "S1: новых сигналов item_removed нет")


# S2: capacity3, bread19. add bread25 -> [20,20,4]. Три сигнала видят общий
# total 44; id непустой и уникальный, quantity > 0, payload принадлежит inv.items.
func _test_s2() -> void:
	inv.max_capacity = 3
	var bread: Dictionary = _make("bread", 19)
	var bread_id_before: String = str(bread.get("instance_id", ""))
	inv.items = [bread]
	var ok: bool = inv.add_item("bread", 25)
	_check(ok, "S2: add_item(bread,25) должен вернуть true")
	_check(_stack_quantities("bread") == [20, 20, 4], "S2: bread -> [20,20,4]")
	_check(added_obs.size() == 3, "S2: ровно 3 сигнала item_added")
	var seen_ids: Dictionary = {}
	for obs in added_obs:
		_check(int(obs["total"]) == 44, "S2: сигнал видит общий total 44")
		_check(str(obs["instance_id"]).length() > 0, "S2: instance_id непустой")
		_check(int(obs["quantity"]) > 0, "S2: quantity положительный")
		_check(bool(obs["belongs"]), "S2: payload принадлежит inv.items (is_same)")
		var key: String = str(obs["instance_id"])
		_check(not seen_ids.has(key), "S2: instance_id уникален между сигналами")
		seen_ids[key] = true
	_check(inv.items.size() >= 1, "S2: инвентарь не пуст после split")
	if inv.items.size() >= 1:
		_check(is_same(inv.items[0], bread), "S2: первый словарь тот же (is_same)")
		_check(str(inv.items[0].get("instance_id", "")) == bread_id_before, "S2: скопированный до изменения id сохранён")


# S3: capacity2, sword1 + bread19. add bread2 false: полный snapshot равен,
# ноль сигналов.
func _test_s3() -> void:
	inv.max_capacity = 2
	var sword: Dictionary = _make("iron_sword", 1)
	var bread: Dictionary = _make("bread", 19)
	inv.items = [sword, bread]
	var snap_before: Array = inv.items.duplicate(true)
	var ok: bool = inv.add_item("bread", 2)
	_check(not ok, "S3: add_item(bread,2) при capacity=2 должен вернуть false")
	_check(inv.items.duplicate(true) == snap_before, "S3: полный снимок не изменился")
	_check(added_obs.size() == 0, "S3: сигналов item_added нет")
	_check(removed_obs.size() == 0, "S3: сигналов item_removed нет")


# S4: bread20 + bread15. remove 25 -> 10, один removed c id bread и total 10;
# remove 1 -> 9, второй removed total 9. Первая стопка и её id сохранены.
func _test_s4() -> void:
	var bread_a: Dictionary = _make("bread", 20)
	var bread_b: Dictionary = _make("bread", 15)
	var first_id_before: String = str(bread_a.get("instance_id", ""))
	inv.items = [bread_a, bread_b]
	var ok1: bool = inv.remove_item("bread", 25)
	_check(ok1, "S4: remove_item(bread,25) должен вернуть true")
	_check(_total("bread") == 10, "S4: bread остаётся 10")
	_check(removed_obs.size() == 1, "S4: ровно один сигнал item_removed")
	if removed_obs.size() >= 1:
		var s0: Dictionary = removed_obs[0]
		_check(str(s0["id"]) == "bread", "S4: id первого removed == bread")
		_check(int(s0["total"]) == 10, "S4: первый removed видит total 10")
	var ok2: bool = inv.remove_item("bread", 1)
	_check(ok2, "S4: remove_item(bread,1) должен вернуть true")
	_check(_total("bread") == 9, "S4: bread остаётся 9")
	_check(removed_obs.size() == 2, "S4: всего два сигнала item_removed")
	if removed_obs.size() >= 2:
		var s1: Dictionary = removed_obs[1]
		_check(int(s1["total"]) == 9, "S4: второй removed видит total 9")
	_check(inv.items.size() == 1, "S4: остаётся одна стопка")
	if inv.items.size() >= 1:
		_check(is_same(inv.items[0], bread_a), "S4: оставшаяся стопка — тот же словарь (is_same)")
		_check(str(inv.items[0].get("instance_id", "")) == first_id_before, "S4: первоначальный id сохранён")


# S5: capacity2, пусто. add bread MAX_INT / sword MAX_INT false без изменений
# и сигналов. Затем bread40 true ровно [20,20]; bread1 false, снимок и
# счётчики не меняются.
func _test_s5() -> void:
	inv.max_capacity = 2
	var snap_empty: Array = inv.items.duplicate(true)
	var ok1: bool = inv.add_item("bread", MAX_INT)
	_check(not ok1, "S5: add_item(bread,MAX_INT) должен вернуть false")
	var ok2: bool = inv.add_item("iron_sword", MAX_INT)
	_check(not ok2, "S5: add_item(iron_sword,MAX_INT) должен вернуть false")
	_check(inv.items.duplicate(true) == snap_empty, "S5: предметы не изменились после overflow")
	_check(added_obs.size() == 0, "S5: сигналов item_added нет при overflow")
	_check(removed_obs.size() == 0, "S5: сигналов item_removed нет при overflow")
	var ok3: bool = inv.add_item("bread", 40)
	_check(ok3, "S5: add_item(bread,40) должен вернуть true")
	_check(_stack_quantities("bread") == [20, 20], "S5: bread -> [20,20]")
	var snap_full: Array = inv.items.duplicate(true)
	var added_before: int = added_obs.size()
	var removed_before: int = removed_obs.size()
	var ok4: bool = inv.add_item("bread", 1)
	_check(not ok4, "S5: add_item(bread,1) при полном инвентаре должен вернуть false")
	_check(inv.items.duplicate(true) == snap_full, "S5: полный снимок не изменился после отказа")
	_check(added_obs.size() == added_before, "S5: новых сигналов item_added нет")
	_check(removed_obs.size() == removed_before, "S5: новых сигналов item_removed нет")
