## TECH-01 / INV-01: регрессионная проверка контракта Inventory.
## Запуск: godot --headless -s res://scripts/tools/validate_inventory_transactions.gd
extends SceneTree

var inv: Node = null
var errors: Array[String] = []
var added_signals: int = 0
var removed_signals: int = 0
var original_items: Array = []
var original_capacity: int = 50
var next_instance: int = 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	inv = root.get_node("Inventory")
	original_items = inv.items.duplicate(true)
	original_capacity = inv.max_capacity
	inv.item_added.connect(_on_item_added)
	inv.item_removed.connect(_on_item_removed)
	_reset()
	_test_split_stacks()
	_reset()
	_test_nonstackable_ids()
	_reset()
	_test_partial_capacity_rollback()
	_reset()
	_test_remove_across_stacks()
	_reset()
	_test_remove_insufficient()
	_reset()
	_test_remove_split_boundary()
	_reset()
	_test_remove_nonstackable()
	_reset()
	_test_invalid_quantities()
	_reset()
	_test_full_stack_plus_new()
	_reset()
	_test_default_quantity_compat()
	# Восстановление исходного состояния
	inv.items = original_items.duplicate(true)
	inv.max_capacity = original_capacity
	if errors.is_empty():
		print("ASHBOUND_INVENTORY_TRANSACTIONS_OK")
		quit(0)
	else:
		print("FAILED:")
		for e in errors:
			print("  - " + e)
		quit(1)


func _on_item_added(_item: Dictionary) -> void:
	added_signals += 1


func _on_item_removed(_item_id: String) -> void:
	removed_signals += 1


func _reset() -> void:
	inv.items = []
	inv.max_capacity = original_capacity
	added_signals = 0
	removed_signals = 0
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


func _stack_quantities(item_id: String) -> Array[int]:
	var result: Array[int] = []
	for entry in inv.items:
		if entry["id"] == item_id:
			result.append(int(entry.get("quantity", 1)))
	return result


func _total(item_id: String) -> int:
	var total: int = 0
	for entry in inv.items:
		if entry["id"] == item_id:
			total += int(entry.get("quantity", 1))
	return total


func _test_split_stacks() -> void:
	inv.max_capacity = 3
	var ok: bool = inv.add_item("bread", 45)
	_check(ok, "split: add_item(bread,45) должен вернуть true")
	_check(_stack_quantities("bread") == [20, 20, 5], "split: bread 45 -> [20,20,5] при capacity=3")


func _test_nonstackable_ids() -> void:
	var ok: bool = inv.add_item("iron_sword", 3)
	_check(ok, "swords: add_item(iron_sword,3) должен вернуть true")
	var ids: Array[String] = []
	for entry in inv.items:
		if entry["id"] == "iron_sword":
			ids.append(str(entry.get("instance_id", "")))
			_check(int(entry.get("quantity", 0)) == 1, "swords: ненастакаемый предмет должен иметь quantity=1")
	_check(ids.size() == 3 and ids[0] != ids[1] and ids[1] != ids[2] and ids[0] != ids[2], "swords: 3 меча -> три разных instance_id")


func _test_partial_capacity_rollback() -> void:
	inv.max_capacity = 2
	inv.items.append(_make("bread", 19))
	inv.items.append(_make("iron_sword", 1))
	var ok: bool = inv.add_item("bread", 2)
	_check(not ok, "rollback: add_item(bread,2) при capacity=2 должен вернуть false")
	_check(_total("bread") == 19, "rollback: bread остаётся 19 после отката")
	_check(added_signals == 0, "rollback: сигналов item_added должно быть 0")


func _test_remove_across_stacks() -> void:
	inv.items.append(_make("bread", 20))
	inv.items.append(_make("bread", 15))
	_check(inv.has_item("bread", 35), "remove25: has_item(bread,35) до remove должен быть true")
	_check(not inv.has_item("bread", 36), "remove25: has_item(bread,36) до remove должен быть false")
	_check(inv.get_item_count("bread") == 35, "remove25: get_item_count(bread) == 35 до remove")
	var ok: bool = inv.remove_item("bread", 25)
	_check(ok, "remove25: remove_item(bread,25) должен вернуть true")
	_check(_total("bread") == 10, "remove25: bread остаётся 10")


func _test_remove_insufficient() -> void:
	inv.items.append(_make("iron_sword", 1))
	inv.items.append(_make("iron_sword", 1))
	var before: Array = inv.items.duplicate(true)
	var ok: bool = inv.remove_item("iron_sword", 3)
	_check(not ok, "remove3: remove_item(iron_sword,3) при 2 мечах должен вернуть false")
	_check(inv.items.duplicate(true) == before, "remove3: предметы не изменились после отказа")
	_check(added_signals == 0 and removed_signals == 0, "remove3: сигналов быть не должно")


func _test_remove_split_boundary() -> void:
	inv.items.append(_make("bread", 5))
	inv.items.append(_make("bread", 5))
	var before: Array = inv.items.duplicate(true)
	var ok: bool = inv.remove_item("bread", 11)
	_check(not ok, "split11: remove_item(bread,11) при 5+5 должен вернуть false")
	_check(inv.items.duplicate(true) == before, "split11: предметы не изменились после отказа")
	_check(added_signals == 0 and removed_signals == 0, "split11: сигналов быть не должно")


func _test_remove_nonstackable() -> void:
	inv.items.append(_make("iron_sword", 1))
	inv.items.append(_make("iron_sword", 1))
	inv.items.append(_make("iron_sword", 1))
	var ok: bool = inv.remove_item("iron_sword", 2)
	_check(ok, "swords2: remove_item(iron_sword,2) из трёх должен вернуть true")
	_check(_total("iron_sword") == 1, "swords2: ровно один меч остаётся")


func _test_invalid_quantities() -> void:
	inv.items.append(_make("bread", 7))
	var before: Array = inv.items.duplicate(true)
	var ok_add_zero: bool = inv.add_item("bread", 0)
	var ok_add_neg: bool = inv.add_item("bread", -1)
	var ok_remove_zero: bool = inv.remove_item("bread", 0)
	var ok_remove_neg: bool = inv.remove_item("bread", -1)
	var ok_has_zero: bool = inv.has_item("bread", 0)
	var ok_has_neg: bool = inv.has_item("bread", -1)
	_check(not ok_add_zero, "invalid: add_item(bread,0) -> false")
	_check(not ok_add_neg, "invalid: add_item(bread,-1) -> false")
	_check(not ok_remove_zero, "invalid: remove_item(bread,0) -> false")
	_check(not ok_remove_neg, "invalid: remove_item(bread,-1) -> false")
	_check(not ok_has_zero, "invalid: has_item(bread,0) -> false")
	_check(not ok_has_neg, "invalid: has_item(bread,-1) -> false")
	_check(inv.items.duplicate(true) == before, "invalid: предметы не изменились при quantity<=0")
	_check(_total("bread") == 7, "invalid: bread остаётся 7 после отрицательного списания")
	_check(added_signals == 0 and removed_signals == 0, "invalid: сигналов быть не должно")


func _test_full_stack_plus_new() -> void:
	inv.max_capacity = 2
	inv.items.append(_make("bread", 20))
	var ok: bool = inv.add_item("bread", 5)
	_check(ok, "fullstack: add_item(bread,5) к полному стаку должен вернуть true")
	_check(_stack_quantities("bread") == [20, 5], "fullstack: bread -> [20,5]")


func _test_default_quantity_compat() -> void:
	inv.items.append(_make("bread", 3))
	var ok_add: bool = inv.add_item("bread")
	_check(ok_add, "default: add_item(\"bread\") по умолчанию должен вернуть true")
	_check(_total("bread") == 4, "default: bread становится 4")
	var ok_remove: bool = inv.remove_item("bread")
	_check(ok_remove, "default: remove_item(\"bread\") по умолчанию должен вернуть true")
	_check(_total("bread") == 3, "default: bread возвращается к 3")
