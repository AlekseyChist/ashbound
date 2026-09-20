## Snapshot isolation, whole-state validation and restore notification contract.
extends SceneTree

const LIMIT: int = 9223372036854775807
var inv: Node
var gm: Node
var failures: Array[String] = []
var completed: int = 0
var notifications: Array = []
var action_events: int = 0
var reenter: bool = false
var nested_result: Variant = null
var valid_data: Dictionary = {}

class StatPlayer extends Node3D:
	var strength: int = 10
	var dexterity: int = 10
	var base_damage: int = 0
	var defense: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	inv = root.get_node("Inventory")
	gm = root.get_node("GameManager")
	gm.player = null
	inv.gold_changed.connect(_on_gold)
	if inv.has_signal("inventory_restored"):
		inv.connect("inventory_restored", _on_restored)
	else:
		_check(false, "inventory_restored signal exists")
	inv.item_added.connect(func(_item: Dictionary): action_events += 1)
	inv.item_removed.connect(func(_id: String): action_events += 1)
	inv.item_equipped.connect(func(_item: Dictionary, _slot: String): action_events += 1)
	inv.item_unequipped.connect(func(_slot: String): action_events += 1)
	_snapshot_isolation()
	_restore_isolation_and_stats()
	_structure_rejections()
	_item_rejections()
	_equipment_rejections()
	_native_roundtrip()
	_reentrant_restore()
	_restore_during_trade()
	_check(completed == 8, "eight groups must complete (%d)" % completed)
	gm.player = null
	if failures.is_empty():
		print("ASHBOUND_INVENTORY_SNAPSHOT_OK groups=8")
		quit(0)
	else:
		for failure in failures:
			printerr("SNAPSHOT_FAIL: " + failure)
		printerr("ASHBOUND_INVENTORY_SNAPSHOT_FAILED failures=%d groups=%d" % [failures.size(), completed])
		quit(1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _reset() -> void:
	inv.items = []
	inv.equipped = {"weapon": null, "armor": null, "helmet": null, "ring": null, "amulet": null}
	inv.gold = 77
	inv.max_capacity = 3
	gm.player = null
	notifications.clear()
	action_events = 0
	reenter = false
	nested_result = null


func _item(id: String, instance: String, quantity: int = 1) -> Dictionary:
	var result: Dictionary = inv.item_database[id].duplicate(true)
	result["instance_id"] = instance
	result["quantity"] = quantity
	return result


func _valid() -> Dictionary:
	return {
		"schema_version": 1,
		"items": [_item("health_potion", "potion", 3), _item("iron_sword", "spare")],
		"equipped": {"weapon": _item("rusty_sword", "worn"), "armor": null, "helmet": null, "ring": null, "amulet": null},
		"gold": 121,
	}


func _state() -> Dictionary:
	return {"items": inv.items.duplicate(true), "equipped": inv.equipped.duplicate(true), "gold": inv.gold}


func _on_gold(amount: int) -> void:
	notifications.append({"kind": "gold", "state": _state(), "amount": amount})
	_try_reenter()


func _on_restored() -> void:
	notifications.append({"kind": "restored", "state": _state()})
	_try_reenter()


func _try_reenter() -> void:
	if not reenter:
		return
	reenter = false
	nested_result = inv.load_save_data(valid_data)
	inv.add_gold(1000)


func _reject(data: Dictionary, label: String) -> void:
	_reset()
	inv.items.append(_item("bread", "keep", 2))
	var before := _state()
	var retained: Dictionary = inv.items[0]
	var source := data.duplicate(true)
	_check(inv.load_save_data(data) == false, label + ": false result")
	_check(_state() == before, label + ": no partial state change")
	_check(data == source, label + ": input not modified")
	_check(notifications.is_empty() and action_events == 0, label + ": no events")
	if inv.items.size() == 1:
		_check(is_same(inv.items[0], retained), label + ": live reference retained")


func _snapshot_isolation() -> void:
	_reset()
	inv.items.append(_item("health_potion", "potion", 3))
	inv.equipped["weapon"] = _item("rusty_sword", "worn")
	var snap: Dictionary = inv.get_save_data()
	_check(snap.get("schema_version", 0) == 1, "versioned snapshot")
	snap["items"][0]["effect"]["heal"] = 900
	snap["items"][0]["quantity"] = 9
	snap["equipped"]["weapon"]["stats"]["damage"] = 999
	_check(inv.items[0]["effect"]["heal"] == 50 and inv.items[0]["quantity"] == 3, "snapshot cannot mutate carried state")
	_check(inv.equipped["weapon"]["stats"]["damage"] == 8, "snapshot cannot mutate equipped stats")
	snap = inv.get_save_data()
	var copy := snap.duplicate(true)
	inv.items[0]["quantity"] = 1
	inv.equipped["weapon"]["stats"]["damage"] = 17
	_check(snap == copy, "live mutations cannot change captured snapshot")
	_check(action_events == 0 and notifications.is_empty(), "snapshot read emits nothing")
	completed += 1


func _restore_isolation_and_stats() -> void:
	_reset()
	var player := StatPlayer.new()
	gm.player = player
	var data := _valid()
	_check(inv.load_save_data(data) == true, "valid restore accepted")
	_check(inv.gold == 121 and inv.items.size() == 2, "restored money and items")
	_check(player.base_damage == 23 and player.defense == 2, "equipped stats applied once")
	_check(inv.max_capacity == 3, "restore does not change configured capacity")
	_check(notifications.size() == 2 and action_events == 0, "restore sends state refresh, not acquisition events")
	for event in notifications:
		_check(event["state"] == _state(), "restore observer sees all state")
	data["items"][0]["effect"]["heal"] = 999
	data["equipped"]["weapon"]["stats"]["damage"] = 999
	_check(inv.items[0]["effect"]["heal"] == 50, "input mutation cannot alter restored effect")
	_check(inv.equipped["weapon"]["stats"]["damage"] == 8, "input mutation cannot alter restored equipment")
	data = _valid()
	_check(inv.load_save_data(data) == true, "second valid restore")
	inv.items[0]["quantity"] = 2
	_check(data["items"][0]["quantity"] == 3, "runtime mutation cannot alter input snapshot")
	gm.player = null
	player.free()
	completed += 1


func _structure_rejections() -> void:
	_reject({}, "missing required schema")
	for field in ["schema_version", "items", "equipped", "gold"]:
		var data := _valid()
		data.erase(field)
		_reject(data, "missing " + field)
	for version in [0, 2, 1.0, "1", true]:
		var data := _valid()
		data["schema_version"] = version
		_reject(data, "invalid schema version")
	for gold in [-1, 1.5, "121", true, INF]:
		var data := _valid()
		data["gold"] = gold
		_reject(data, "invalid gold")
	var over := _valid()
	over["items"].append(_item("bread", "third"))
	over["items"].append(_item("bread", "fourth"))
	_reject(over, "over capacity")
	completed += 1


func _item_rejections() -> void:
	for pair in [["id", "missing"], ["instance_id", ""], ["instance_id", 3], ["quantity", 0], ["quantity", -1], ["quantity", 1.5], ["quantity", "1"], ["quantity", true], ["quantity", 11], ["value", -1], ["value", "1"], ["value", 1.5], ["type", 999], ["type", "2"], ["stackable", "true"], ["max_stack", 0], ["max_stack", 2.5], ["effect", "bad"]]:
		var data := _valid()
		data["items"][0][pair[0]] = pair[1]
		_reject(data, "bad item field " + str(pair[0]))
	var data := _valid()
	data["items"][1]["quantity"] = 2
	_reject(data, "nonstackable quantity")
	data = _valid()
	data["items"][1]["stats"]["damage"] = "99"
	_reject(data, "invalid numeric stat")
	data = _valid()
	data["items"][1]["instance_id"] = "potion"
	_reject(data, "duplicate carried identity")
	completed += 1


func _equipment_rejections() -> void:
	var data := _valid()
	data["equipped"]["weapon"]["instance_id"] = "potion"
	_reject(data, "identity shared with equipment")
	data = _valid()
	data["equipped"]["armor"] = data["equipped"]["weapon"].duplicate(true)
	_reject(data, "identity repeated in equipment")
	data = _valid()
	data["equipped"]["weapon"] = _item("leather_armor", "wrong_slot")
	_reject(data, "wrong equipped slot")
	data = _valid()
	data["equipped"]["weapon"] = _item("bread", "food")
	_reject(data, "food equipped as weapon")
	data = _valid()
	data["equipped"].erase("amulet")
	_reject(data, "missing slot")
	data = _valid()
	data["equipped"]["extra_slot"] = null
	_reject(data, "unknown slot")
	completed += 1


func _native_roundtrip() -> void:
	_reset()
	var data := _valid()
	data["gold"] = LIMIT
	data["items"][1]["value"] = LIMIT
	data["items"][1]["stats"]["damage"] = 19
	var roundtrip: Dictionary = bytes_to_var(var_to_bytes(data))
	_check(inv.load_save_data(roundtrip) == true, "typed roundtrip loads")
	_check(inv.gold == LIMIT and inv.items[1]["value"] == LIMIT, "int64 preserved without float loss")
	_check(inv.items[1]["stats"]["damage"] == 19, "instance upgrade survives")
	_check(inv.get_save_data() == roundtrip, "snapshot reproduces native data")
	completed += 1


func _reentrant_restore() -> void:
	_reset()
	valid_data = _valid()
	valid_data["gold"] = 999
	reenter = true
	_check(inv.load_save_data(_valid()) == true, "outer restore")
	_check(nested_result == false, "restore callback cannot restore again")
	_check(inv.gold == 121 and notifications.size() == 2, "restore callback cannot change money")
	_check(inv.load_save_data(valid_data) == true and inv.gold == 999, "guard released after restore")
	completed += 1


func _restore_during_trade() -> void:
	_reset()
	valid_data = _valid()
	reenter = true
	_check(inv.buy_item("bread", 3), "purchase during restore guard test")
	_check(nested_result == false, "trade callback cannot replace whole inventory")
	_check(inv.gold == 74 and inv.items.size() == 1 and inv.items[0]["id"] == "bread", "trade remains intact")
	completed += 1
