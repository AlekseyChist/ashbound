## Independent trade contract checks. No scene/UI or save-file writes.
extends SceneTree

const LIMIT: int = 9223372036854775807
const EXPECTED_GROUPS: int = 14
var inv: Node
var failures: Array[String] = []
var completed: int = 0
var events: Array = []
var reenter: bool = false
var nested_results: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	inv = root.get_node("Inventory")
	root.get_node("GameManager").player = null
	inv.item_database["qa_trade_token"] = {
		"id": "qa_trade_token", "name": "QA token", "type": 4,
		"stackable": true, "max_stack": 5, "value": 4,
	}
	inv.item_database["qa_trade_sword"] = {
		"id": "qa_trade_sword", "name": "QA sword", "type": 0,
		"stackable": false, "slot": "weapon", "value": 7,
	}
	inv.gold_changed.connect(_gold_event)
	inv.item_added.connect(_added_event)
	inv.item_removed.connect(_removed_event)
	_test_gold_rejects()
	_test_gold_boundaries()
	_test_purchase_rejects()
	_test_purchase_commit()
	_test_full_bag_stack()
	_test_unowned_sale()
	_test_canonical_sale()
	_test_selected_stack()
	_test_stale_and_equipped_sale()
	_test_ambiguous_handle()
	_test_bad_canonical_values()
	_test_sale_overflow()
	_test_purchase_reentry()
	_test_sale_reentry()
	_check(completed == EXPECTED_GROUPS, "all test groups must finish: %d/%d" % [completed, EXPECTED_GROUPS])
	if failures.is_empty():
		print("ASHBOUND_INVENTORY_TRADE_OK groups=%d" % completed)
		quit(0)
	else:
		for failure in failures:
			printerr("TRADE_FAIL: " + failure)
		printerr("ASHBOUND_INVENTORY_TRADE_FAILED failures=%d groups=%d" % [failures.size(), completed])
		quit(1)


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)


func _reset(amount: int = 100, capacity: int = 5) -> void:
	inv.items = []
	for slot in inv.equipped:
		inv.equipped[slot] = null
	inv.gold = amount
	inv.max_capacity = capacity
	events.clear()
	nested_results.clear()
	reenter = false


func _put(id: String, instance_id: String, quantity: int = 1) -> Dictionary:
	var record: Dictionary = inv.item_database[id].duplicate(true)
	record["instance_id"] = instance_id
	record["quantity"] = quantity
	inv.items.append(record)
	return record


func _snapshot() -> Dictionary:
	return {"items": inv.items.duplicate(true), "equipped": inv.equipped.duplicate(true), "gold": inv.gold}


func _unchanged(before: Dictionary, label: String) -> void:
	_check(_snapshot() == before, label + ": state unchanged")
	_check(events.is_empty(), label + ": no signals")


func _gold_event(amount: int) -> void:
	events.append({"kind": "gold", "amount": amount, "state": _snapshot()})


func _added_event(item: Dictionary) -> void:
	events.append({"kind": "add", "item": item.duplicate(true), "state": _snapshot()})
	_try_reenter(item)


func _removed_event(item_id: String) -> void:
	events.append({"kind": "remove", "id": item_id, "state": _snapshot()})
	_try_reenter({"id": item_id, "instance_id": "selected", "value": 4})


func _try_reenter(handle: Dictionary) -> void:
	if not reenter:
		return
	reenter = false
	nested_results.append(inv.buy_item("qa_trade_token", 1))
	nested_results.append(inv.sell_item(handle))
	nested_results.append(inv.remove_gold(1))
	inv.add_gold(1000)


func _committed_events(label: String) -> void:
	_check(events.size() == 2, label + ": one item and one gold signal")
	var kinds: Array = []
	for event in events:
		kinds.append(event["kind"])
		_check(event["state"] == _snapshot(), label + ": observer sees committed items AND gold")
		if event["kind"] == "gold":
			_check(event["amount"] == inv.gold, label + ": correct gold payload")
	_check(kinds.count("gold") == 1, label + ": exactly one gold signal")


func _test_gold_rejects() -> void:
	for amount in [0, -1, -LIMIT]:
		_reset()
		var before := _snapshot()
		inv.add_gold(amount)
		_unchanged(before, "add invalid %d" % amount)
		_reset()
		before = _snapshot()
		_check(not inv.remove_gold(amount), "remove invalid %d" % amount)
		_unchanged(before, "remove invalid %d" % amount)
	_reset()
	_check(not inv.has_gold(-1), "negative affordability query rejected")
	_check(inv.has_gold(0), "zero affordability query is valid")
	_check(not inv.remove_gold(101), "insufficient gold")
	_check(events.is_empty(), "insufficient gold no signal")
	completed += 1


func _test_gold_boundaries() -> void:
	_reset(LIMIT - 2)
	var before := _snapshot()
	inv.add_gold(3)
	_unchanged(before, "overflow rejected")
	inv.add_gold(2)
	_check(inv.gold == LIMIT and events.size() == 1, "exact upper boundary")
	events.clear()
	_check(inv.remove_gold(LIMIT), "exact balance spend")
	_check(inv.gold == 0 and events.size() == 1, "balance reaches zero once")
	completed += 1


func _test_purchase_rejects() -> void:
	for price in [-10, 0, 101, LIMIT]:
		_reset()
		var before := _snapshot()
		_check(not inv.buy_item("qa_trade_token", price), "reject purchase price %d" % price)
		_unchanged(before, "purchase price %d" % price)
	_reset()
	var before := _snapshot()
	_check(not inv.buy_item("qa_missing", 10), "unknown purchase rejected")
	_unchanged(before, "unknown purchase")
	_reset(100, 1)
	_put("qa_trade_sword", "other")
	before = _snapshot()
	_check(not inv.buy_item("qa_trade_token", 10), "full purchase rejected")
	_unchanged(before, "full purchase")
	completed += 1


func _test_purchase_commit() -> void:
	_reset(10)
	_check(inv.buy_item("qa_trade_sword", 10), "purchase exact balance")
	_check(inv.gold == 0 and inv.items.size() == 1, "purchase final state")
	if inv.items.size() == 1:
		_check(inv.items[0]["quantity"] == 1 and inv.items[0]["id"] == "qa_trade_sword", "correct purchased record")
		_check(inv.items[0].get("instance_id", "") != "", "purchased identity exists")
	_committed_events("purchase")
	completed += 1


func _test_full_bag_stack() -> void:
	_reset(20, 1)
	var existing := _put("qa_trade_token", "existing", 4)
	_check(inv.buy_item("qa_trade_token", 3), "purchase fits existing stack in full bag")
	_check(existing["quantity"] == 5 and inv.items.size() == 1 and inv.gold == 17, "stack purchase commits")
	_check(inv.items[0]["instance_id"] == "existing", "stack identity preserved")
	_committed_events("stack purchase")
	events.clear()
	var before := _snapshot()
	_check(not inv.buy_item("qa_trade_token", 3), "full stack rejected")
	_unchanged(before, "full stack")
	completed += 1


func _test_unowned_sale() -> void:
	_reset()
	_put("qa_trade_token", "owned")
	for handle in [{"id": "qa_trade_token", "value": 4}, {"id": "qa_trade_token", "value": 4, "instance_id": "missing"}]:
		var before := _snapshot()
		_check(not inv.sell_item(handle), "unowned handle rejected")
		_unchanged(before, "unowned sale")
	completed += 1


func _test_canonical_sale() -> void:
	_reset()
	_put("qa_trade_sword", "selected")["value"] = 9
	_check(inv.sell_item({"id": "qa_trade_token", "instance_id": "selected", "value": 9000, "quantity": 99}), "canonical handle resolves")
	_check(inv.gold == 109 and inv.items.is_empty(), "canonical value and item used")
	_committed_events("canonical sale")
	if events.size() > 0:
		var removal_ids: Array = []
		for event in events:
			if event["kind"] == "remove":
				removal_ids.append(event["id"])
		_check(removal_ids == ["qa_trade_sword"], "canonical removal id")
	completed += 1


func _test_selected_stack() -> void:
	_reset()
	var selected := _put("qa_trade_token", "selected", 3)
	var other := _put("qa_trade_token", "other", 4)
	_check(inv.sell_item(selected.duplicate(true)), "sell from selected stack")
	_check(selected["quantity"] == 2 and other["quantity"] == 4, "only selected stack decreases")
	_check(inv.gold == 104 and inv.items.size() == 2, "one item sold")
	_committed_events("stack sale")
	completed += 1


func _test_stale_and_equipped_sale() -> void:
	_reset()
	var handle := _put("qa_trade_sword", "selected").duplicate(true)
	_check(inv.sell_item(handle), "first sale")
	events.clear()
	var before := _snapshot()
	_check(not inv.sell_item(handle), "stale handle rejected")
	_unchanged(before, "stale sale")
	_reset()
	var worn := _put("qa_trade_sword", "worn")
	inv.items.clear()
	inv.equipped["weapon"] = worn
	_put("qa_trade_sword", "other")
	before = _snapshot()
	_check(not inv.sell_item(worn), "equipped-only handle rejected")
	_unchanged(before, "equipped sale")
	completed += 1


func _test_ambiguous_handle() -> void:
	_reset()
	var handle := _put("qa_trade_token", "duplicate")
	_put("qa_trade_token", "duplicate")
	var before := _snapshot()
	_check(not inv.sell_item(handle), "duplicate instance rejected")
	_unchanged(before, "ambiguous sale")
	completed += 1


func _test_bad_canonical_values() -> void:
	for quantity in [0, -1, 1.5]:
		_reset()
		var record := _put("qa_trade_token", "selected")
		record["quantity"] = quantity
		var before := _snapshot()
		_check(not inv.sell_item(record), "invalid sale quantity %s" % quantity)
		_unchanged(before, "invalid sale quantity")
	for value in [0, -1, 1.5]:
		_reset()
		var record := _put("qa_trade_token", "selected")
		record["value"] = value
		var before := _snapshot()
		_check(not inv.sell_item(record), "invalid sale value %s" % value)
		_unchanged(before, "invalid sale value")
	completed += 1


func _test_sale_overflow() -> void:
	_reset(LIMIT - 3)
	var record := _put("qa_trade_token", "selected")
	var before := _snapshot()
	_check(not inv.sell_item(record), "sale overflow rejected")
	_unchanged(before, "sale overflow")
	_reset(LIMIT - 4)
	record = _put("qa_trade_token", "selected")
	_check(inv.sell_item(record), "sale reaches exact upper boundary")
	_check(inv.gold == LIMIT and inv.items.is_empty(), "sale exact boundary commits")
	_committed_events("boundary sale")
	completed += 1


func _test_purchase_reentry() -> void:
	_reset(10)
	reenter = true
	_check(inv.buy_item("qa_trade_token", 10), "outer reentrant purchase")
	_check(nested_results == [false, false, false], "nested trade/gold mutations blocked during purchase")
	_check(inv.gold == 0 and inv.items.size() == 1, "purchase observers cannot change money or resell")
	_committed_events("reentrant purchase")
	events.clear()
	inv.add_gold(1)
	_check(inv.gold == 1, "transaction guard released after purchase")
	completed += 1


func _test_sale_reentry() -> void:
	_reset(0)
	var handle := _put("qa_trade_token", "selected", 2)
	reenter = true
	_check(inv.sell_item(handle), "outer reentrant sale")
	_check(nested_results == [false, false, false], "nested trade/gold mutations blocked during sale")
	_check(inv.gold == 4 and handle["quantity"] == 1, "sale observers cannot sell remaining stack")
	_committed_events("reentrant sale")
	events.clear()
	_check(inv.sell_item(handle), "guard released for next sale")
	_check(inv.gold == 8 and inv.items.is_empty(), "second explicit sale valid")
	completed += 1
