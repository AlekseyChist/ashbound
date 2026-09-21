## Additional independent adversarial and conservation checks for trade.
extends SceneTree

const LIMIT: int = 9223372036854775807
var inv: Node
var errors: Array[String] = []
var completed: int = 0
var events: Array = []
var reenter_on_gold: bool = false
var nested: Array = []
var selected: Dictionary = {}
var added_payloads: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	inv = root.get_node("Inventory")
	root.get_node("GameManager").player = null
	inv.item_database["qa_trade"] = {"id": "qa_trade", "name": "QA", "type": 4, "stackable": true, "max_stack": 5, "value": 4}
	inv.gold_changed.connect(_on_gold)
	inv.item_added.connect(func(item: Dictionary):
		events.append(_snapshot())
		added_payloads.append(item)
	)
	inv.item_removed.connect(func(_id: String): events.append(_snapshot()))
	_handles()
	_bad_records()
	_negative_balance()
	_equipped_alias()
	_gold_reentry()
	_extreme_purchase()
	_purchase_payload()
	_conservation()
	_check(completed == 8, "all eight groups completed")
	if errors.is_empty():
		print("ASHBOUND_INVENTORY_TRADE_EDGES_OK groups=8 exchanges=600")
		quit(0)
	else:
		for error in errors:
			printerr("TRADE_EDGE_FAIL: " + error)
		quit(1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)


func _reset(amount: int = 100) -> void:
	inv.items = []
	for slot in inv.equipped:
		inv.equipped[slot] = null
	inv.gold = amount
	inv.max_capacity = 3
	events.clear()
	added_payloads.clear()
	nested.clear()
	selected = {}
	reenter_on_gold = false


func _record() -> Dictionary:
	var record: Dictionary = inv.item_database["qa_trade"].duplicate(true)
	record["instance_id"] = "selected"
	record["quantity"] = 2
	inv.items.append(record)
	return record


func _snapshot() -> Dictionary:
	return {"items": inv.items.duplicate(true), "equipped": inv.equipped.duplicate(true), "gold": inv.gold}


func _reject_sale(handle: Dictionary, label: String) -> void:
	var before := _snapshot()
	_check(not inv.sell_item(handle), label + ": rejected")
	_check(_snapshot() == before and events.is_empty(), label + ": no changes/events")


func _on_gold(_gold: int) -> void:
	events.append(_snapshot())
	if not reenter_on_gold:
		return
	reenter_on_gold = false
	nested.append(inv.buy_item("qa_trade", 1))
	nested.append(inv.sell_item(selected))
	nested.append(inv.remove_gold(1))
	inv.add_gold(1000)


func _handles() -> void:
	for identity in [null, "", 2, 2.0, true, [], {}]:
		_reset()
		_record()
		_reject_sale({"instance_id": identity, "id": "qa_trade", "value": 4}, "bad handle %s" % str(identity))
	_reset()
	_record()
	_reject_sale({}, "missing handle")
	completed += 1


func _bad_records() -> void:
	for field in ["quantity", "value"]:
		for value in [null, "4", true, [], {}, INF, 2.5]:
			_reset()
			var record := _record()
			record[field] = value
			_reject_sale({"instance_id": "selected"}, "bad canonical %s %s" % [field, str(value)])
	for id in [null, "", 5, false]:
		_reset()
		var record := _record()
		record["id"] = id
		_reject_sale({"instance_id": "selected"}, "bad canonical id")
	_reset()
	var record := _record()
	record["stackable"] = false
	_reject_sale({"instance_id": "selected"}, "nonstackable quantity >1")
	_reset()
	record = _record()
	record.merge({"id": "qa_crafted", "stackable": false, "quantity": 1, "value": 13}, true)
	_check(inv.sell_item({"instance_id": "selected"}), "owned crafted value independent of template")
	_check(inv.gold == 113 and inv.items.is_empty(), "crafted sale canonical value")
	completed += 1


func _negative_balance() -> void:
	_reset(-1)
	var record := _record()
	var before := _snapshot()
	_check(not inv.has_gold(0), "invalid balance cannot afford zero")
	_check(not inv.remove_gold(1), "invalid balance remove rejected")
	inv.add_gold(2)
	_check(not inv.buy_item("qa_trade", 1), "invalid balance buy rejected")
	_check(not inv.sell_item(record), "invalid balance sale rejected")
	_check(_snapshot() == before and events.is_empty(), "bad balance untouched")
	completed += 1


func _equipped_alias() -> void:
	_reset()
	var record := _record()
	inv.equipped["weapon"] = record
	_reject_sale({"instance_id": "selected"}, "record also equipped")
	inv.equipped["weapon"] = record.duplicate(true)
	inv.equipped["weapon"]["name"] = "same identity, different copy"
	_reject_sale({"instance_id": "selected"}, "identity also equipped")
	completed += 1


func _gold_reentry() -> void:
	for buy in [true, false]:
		_reset()
		selected = _record()
		reenter_on_gold = true
		var ok: bool = inv.buy_item("qa_trade", 4) if buy else inv.sell_item(selected)
		_check(ok, "outer transaction gold callback")
		_check(nested == [false, false, false], "gold callback blocks reentry")
		_check(inv.gold == (96 if buy else 104), "gold callback final amount")
		_check(events.size() == 2, "gold callback no extra events")
		for event in events:
			_check(event == _snapshot(), "gold callback observes committed state")
		_check(inv.remove_gold(1), "guard releases after gold callback")
	completed += 1


func _extreme_purchase() -> void:
	_reset(LIMIT)
	_check(inv.buy_item("qa_trade", LIMIT), "max price with exact balance")
	_check(inv.gold == 0 and inv.get_item_count("qa_trade") == 1, "max purchase no overflow")
	for event in events:
		_check(event == _snapshot(), "max purchase signal state")
	completed += 1


func _purchase_payload() -> void:
	_reset()
	var first := _record()
	var last := _record()
	last["instance_id"] = "last"
	_check(inv.buy_item("qa_trade", 4), "purchase into first of two stacks")
	_check(first["quantity"] == 3 and last["quantity"] == 2, "only first stack filled")
	_check(added_payloads.size() == 1, "one payload")
	if added_payloads.size() == 1:
		_check(is_same(added_payloads[0], first), "signal uses real changed first stack, not last/template/copy")
	_check(first["instance_id"] == "selected", "changed stack identity preserved")
	completed += 1


func _conservation() -> void:
	_reset(100)
	var rng := RandomNumberGenerator.new()
	rng.seed = 208765
	var successes: int = 0
	for step in range(600):
		events.clear()
		var before := _snapshot()
		var ok: bool
		if inv.items.is_empty() or rng.randi_range(0, 1) == 0:
			ok = inv.buy_item("qa_trade", 4)
		else:
			var item: Dictionary = inv.items[rng.randi_range(0, inv.items.size() - 1)]
			ok = inv.sell_item({"instance_id": item["instance_id"], "value": LIMIT, "id": "forged"})
		var count: int = 0
		var seen: Dictionary = {}
		for item in inv.items:
			count += int(item["quantity"])
			_check(item["quantity"] > 0 and item["quantity"] <= 5, "valid stack at %d" % step)
			_check(not seen.has(item["instance_id"]), "unique identity at %d" % step)
			seen[item["instance_id"]] = true
		_check(inv.gold >= 0 and inv.gold + count * 4 == 100, "wealth conserved at %d" % step)
		_check(inv.items.size() <= 3, "capacity at %d" % step)
		if ok:
			successes += 1
			_check(events.size() == 2, "two transaction events at %d" % step)
			for event in events:
				_check(event == _snapshot(), "committed observer at %d" % step)
		else:
			_check(_snapshot() == before and events.is_empty(), "failed transaction unchanged at %d" % step)
	_check(successes > 300, "conservation exercise actually trades")
	completed += 1
