extends SceneTree
## Independent integration QA: real Inventory transactions across physical storage.
var inv: Node
var failures: Array[String] = []
var groups := 0
var storage_events := 0
var callbacks_valid := true
var callback_guard_results: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		printerr("STORAGE_FAIL: " + label)

func defs() -> Array:
	return [{"id": "coat", "kind": "pocket", "capacity": 1}, {"id": "bag", "kind": "backpack", "capacity": 2}]

func handle(id: String) -> Dictionary:
	for item in inv.items:
		if item["id"] == id:
			return {"instance_id": item["instance_id"]}
	return {}

func audit(_a: Variant = null, _b: Variant = null) -> void:
	var total := 0
	var ids := {}
	for container in inv.get_storage_containers():
		total += container["used"]
		if container["used"] > container["capacity"]:
			callbacks_valid = false
		ids[container["id"]] = true
	if total != inv.items.size():
		callbacks_valid = false
	for item in inv.items:
		if not ids.has(inv.get_item_storage(item["instance_id"])):
			callbacks_valid = false
	for item in inv.equipped.values():
		if item is Dictionary and inv.get_item_storage(item["instance_id"]) != "":
			callbacks_valid = false

func storage_event() -> void:
	storage_events += 1
	audit()

func guarded_callback(_amount: int) -> void:
	callback_guard_results.append(inv.configure_storage(defs()))
	callback_guard_results.append(inv.move_item_to_storage(handle("bread"), "bag"))

func _run() -> void:
	inv = root.get_node_or_null("Inventory")
	if inv == null or not inv.has_method("configure_storage"):
		printerr("STORAGE_FAIL: integration API missing")
		quit(1)
		return
	check(not inv.is_storage_configured() and inv.get_effective_capacity() == 50, "legacy behavior until explicitly configured")
	check(not inv.get_save_data().has("storage"), "legacy snapshot shape unchanged")
	check(inv.configure_storage(defs()), "configure actual carried capacities")
	check(inv.get_effective_capacity() == 3, "physical slots limit capacity")
	inv.storage_changed.connect(storage_event)
	inv.item_added.connect(audit)
	inv.item_removed.connect(audit)
	inv.item_equipped.connect(audit)
	inv.item_unequipped.connect(audit)
	inv.inventory_restored.connect(audit)
	check(inv.add_item("rusty_sword") and inv.add_item("iron_sword") and inv.add_item("bread", 20), "fill all real slots")
	var rusty := handle("rusty_sword")
	var iron := handle("iron_sword")
	var bread := handle("bread")
	check(inv.get_item_storage(rusty["instance_id"]) == "coat", "first item in clothing")
	check(inv.get_item_storage(iron["instance_id"]) == "bag" and inv.get_item_storage(bread["instance_id"]) == "bag", "remaining items in bag")
	groups += 1

	inv.add_gold(100)
	var before: Dictionary = inv.get_save_data()
	var before_events := storage_events
	check(not inv.add_item("bread") and not inv.add_item("leather_armor"), "full carried containers refuse new entries")
	check(not inv.buy_item("health_potion", 10), "purchase fails without physical room")
	check(inv.get_save_data() == before and storage_events == before_events, "failed acquisition loses no money/items/locations")
	check(not inv.move_item_to_storage(rusty, "bag"), "full destination rejects move")
	check(not inv.move_item_to_storage({"instance_id": "ghost"}, "coat"), "stale handle cannot create placement")
	check(inv.get_save_data() == before, "failed moves unchanged")
	groups += 1

	check(inv.equip_item(rusty), "equip frees clothing slot")
	check(inv.get_item_storage(rusty["instance_id"]) == "", "equipped item not in container")
	check(inv.move_item_to_storage(bread, "coat"), "move whole stack into freed clothing slot")
	check(inv.get_item_count("bread") == 20, "movement conserves stack quantity")
	check(inv.add_item("health_potion"), "freed bag slot accepts item")
	before = inv.get_save_data()
	check(not inv.unequip_slot("weapon") and inv.get_save_data() == before, "cannot unequip into full physical storage")
	check(inv.equip_item(iron), "equipment exchange works when full")
	check(inv.get_item_storage(rusty["instance_id"]) == "bag" and inv.get_item_storage(iron["instance_id"]) == "", "outgoing weapon occupies incoming vacancy")
	groups += 1

	before = inv.get_save_data()
	check(not inv.configure_storage([defs()[0]]) and inv.get_save_data() == before, "occupied bag cannot disappear")
	var malformed := defs()
	malformed[1]["capacity"] = 1
	check(not inv.configure_storage(malformed) and inv.get_save_data() == before, "occupied bag cannot shrink")
	check(inv.remove_item("health_potion"), "consume/remove releases assignment")
	check(inv.sell_item(rusty), "sell releases exact unique item")
	check(inv.get_item_storage(rusty["instance_id"]) == "", "sold handle no longer carried")
	check(inv.configure_storage([defs()[0]]) and inv.get_effective_capacity() == 1, "empty bag can be detached")
	check(inv.get_item_storage(bread["instance_id"]) == "coat", "remaining clothing contents unchanged")
	groups += 1

	check(inv.configure_storage(defs()), "reattach empty capacity through trusted profile API")
	check(inv.move_item_to_storage(bread, "bag"), "preserve a non-default chosen location")
	check(inv.configure_storage(defs()) and inv.get_item_storage(bread["instance_id"]) == "bag", "reconfiguring identical definitions cannot repack chosen locations")
	var saved: Dictionary = inv.get_save_data()
	var saved_copy := saved.duplicate(true)
	check(inv.move_item_to_storage(bread, "coat"), "temporary moved state")
	check(inv.load_save_data(saved), "restore physical placement snapshot")
	check(inv.get_item_storage(bread["instance_id"]) == "bag", "load restores exact container not first free")
	check(saved == saved_copy, "load does not mutate input")
	saved["storage"]["placements"][bread["instance_id"]] = "coat"
	check(inv.get_item_storage(bread["instance_id"]) == "bag", "snapshot cannot change live ownership")
	groups += 1

	before = inv.get_save_data()
	before_events = storage_events
	for payload in [null, [], {}, {"placements": {}}, {"placements": {bread["instance_id"]: "ghost"}}, {"placements": {bread["instance_id"]: "bag", "ghost": "coat"}}]:
		var bad := before.duplicate(true)
		bad["gold"] = 999
		bad["storage"] = payload
		check(not inv.load_save_data(bad) and inv.get_save_data() == before, "bad placement snapshot rejects all fields")
	check(storage_events == before_events, "invalid restore emits no successful refresh")
	var legacy := before.duplicate(true)
	legacy.erase("storage")
	check(inv.load_save_data(legacy), "old v1 snapshots migrate into configured storage")
	check(inv.get_item_storage(bread["instance_id"]) == "coat", "legacy placement deterministic")
	groups += 1

	# The trade guard must also cover newly added storage mutations during callbacks.
	inv.gold_changed.connect(guarded_callback)
	check(inv.buy_item("health_potion", 2), "trade after physical restore")
	check(callback_guard_results == [false, false], "purchase callbacks cannot reconfigure/move storage")
	callback_guard_results.clear()
	check(inv.load_save_data(inv.get_save_data()), "restore under callbacks")
	check(callback_guard_results == [false, false], "restore callbacks cannot alter placement")
	inv.gold_changed.disconnect(guarded_callback)
	check(callbacks_valid, "all externally visible events observe committed assignments")
	groups += 1

	# A smaller legacy hard cap still constrains configured containers.
	inv.max_capacity = inv.items.size()
	before = inv.get_save_data()
	check(not inv.add_item("leather_armor") and inv.get_save_data() == before, "hard cap cannot be bypassed by physical capacity")
	check(inv.remove_item("bread", 1) and inv.add_item("bread", 1), "existing partial stack can be topped up at capacity")
	audit()
	check(callbacks_valid, "conservation audit after final transactions")
	groups += 1

	if failures.is_empty() and groups == 8:
		print("ASHBOUND_STORAGE_INTEGRATION_OK groups=8")
		quit(0)
	else:
		printerr("ASHBOUND_STORAGE_INTEGRATION_FAILED groups=%d failures=%d" % [groups, failures.size()])
		quit(1)
