extends SceneTree
## Independent QA: physical wearable ownership, capacity, transactions and snapshots.
var failures: Array[String] = []
var groups := 0
var inv: Node

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, why: String) -> void:
	if not ok:
		failures.append(why)
		printerr("WEARABLE_FAIL: " + why)

func snapshot() -> String:
	return JSON.stringify(inv.get_save_data())

func find_item(id: String) -> Dictionary:
	for item: Dictionary in inv.items:
		if item.id == id:
			return item
	return {}

func bag_container(kind: String) -> String:
	var item: Dictionary = inv.get_worn_storage(kind)
	return "" if item.is_empty() else "worn_storage:" + str(item.instance_id)

func run() -> void:
	await process_frame
	inv = root.get_node("Inventory")
	check(inv.configure_storage([{"id":"traveler_clothing_pocket","kind":"pocket","capacity":6}]), "configure starter")
	check(inv.get_worn_storage("backpack").is_empty() and inv.get_storage_containers().size() == 1, "starter only pocket")
	check(inv.add_item("traveler_backpack"), "obtain real backpack")
	var bag: Dictionary = find_item("traveler_backpack").duplicate(true)
	check(inv.get_storage_containers().size() == 1, "carrying does not equip")
	groups += 1
	var before := snapshot()
	check(not inv.equip_storage_item({"instance_id":"absent","id":"traveler_backpack"}), "unowned cannot equip")
	check(snapshot() == before, "unowned atomic")
	check(inv.equip_storage_item({"instance_id":bag.instance_id,"id":"bread","quantity":999}), "canonical handle only")
	check(inv.get_worn_storage("backpack").instance_id == bag.instance_id, "real worn owner")
	check(find_item("traveler_backpack").is_empty(), "worn absent from carried")
	check(inv.get_effective_capacity() == 14, "equipped backpack adds eight")
	groups += 1
	check(inv.add_item("bread",3), "bread stack")
	var bread: Dictionary = find_item("bread").duplicate(true)
	check(inv.move_item_to_storage({"instance_id":bread.instance_id}, bag_container("backpack")), "store bread")
	before = snapshot()
	check(not inv.unequip_storage_item("backpack","traveler_clothing_pocket"), "occupied backpack refuses removal")
	check(snapshot() == before, "occupied removal loses nothing")
	groups += 1
	var saved: Dictionary = inv.get_save_data()
	var result: Dictionary = inv.get_worn_storage("backpack")
	result.id = "bread"
	check(inv.get_worn_storage("backpack").id == "traveler_backpack", "worn API defensive copy")
	check(inv.move_item_to_storage({"instance_id":bread.instance_id},"traveler_clothing_pocket"), "empty backpack")
	check(inv.unequip_storage_item("backpack","traveler_clothing_pocket"), "remove empty backpack")
	check(inv.get_effective_capacity() == 6 and inv.get_worn_storage("backpack").is_empty(), "removed capacity")
	check(find_item("traveler_backpack").instance_id == bag.instance_id, "same backpack returned")
	groups += 1
	check(inv.load_save_data(saved), "restore worn backpack from pocket only runtime")
	check(inv.get_worn_storage("backpack").instance_id == bag.instance_id, "restore worn identity")
	check(inv.get_item_storage(bread.instance_id) == bag_container("backpack"), "restore contents")
	check(inv.get_item_count("bread") == 3, "restore quantity")
	groups += 1
	before = snapshot()
	var invalid: Dictionary = saved.duplicate(true)
	invalid.worn_storage.pouch = invalid.worn_storage.backpack.duplicate(true)
	check(not inv.load_save_data(invalid), "reject duplicate and wrong wearable")
	check(snapshot() == before, "invalid restore atomic")
	invalid = saved.duplicate(true)
	invalid.items.append(invalid.worn_storage.backpack.duplicate(true))
	check(not inv.load_save_data(invalid), "reject duplicate carried and worn owner")
	check(snapshot() == before, "duplicate restore atomic")
	groups += 1
	check(inv.add_item("belt_pouch"), "obtain pouch")
	var pouch: Dictionary = find_item("belt_pouch").duplicate(true)
	check(inv.equip_storage_item({"instance_id":pouch.instance_id}), "equip separate pouch")
	check(inv.get_effective_capacity() == 16, "pouch plus pack plus pocket")
	check(inv.get_worn_storage("backpack").instance_id == bag.instance_id, "pouch does not replace pack")
	check(inv.get_worn_storage("pouch").instance_id == pouch.instance_id, "pouch owner")
	groups += 1
	check(inv.add_item("traveler_backpack"), "second backpack")
	var second: Dictionary = find_item("traveler_backpack").duplicate(true)
	before = snapshot()
	check(not inv.equip_storage_item({"instance_id":second.instance_id}), "cannot swap occupied pack")
	check(snapshot() == before, "swap occupied atomic")
	check(inv.move_item_to_storage({"instance_id":bread.instance_id}, "traveler_clothing_pocket"), "clear old pack")
	check(inv.equip_storage_item({"instance_id":second.instance_id}), "swap empty pack")
	check(inv.get_worn_storage("backpack").instance_id == second.instance_id, "replacement identity")
	check(find_item("traveler_backpack").instance_id == bag.instance_id, "old bag returned")
	groups += 1
	var reentered := [false]
	var mutate := func() -> void:
		var old_gold: int = inv.gold
		var old_size: int = inv.items.size()
		inv.add_gold(25)
		inv.add_item("bread")
		reentered[0] = inv.gold != old_gold or inv.items.size() != old_size
	inv.storage_changed.connect(mutate)
	check(inv.unequip_storage_item("pouch","traveler_clothing_pocket"), "guarded unequip")
	inv.storage_changed.disconnect(mutate)
	check(not reentered[0], "signal cannot mutate midway through wearable transaction")
	groups += 1
	before = snapshot()
	check(not inv.unequip_storage_item("backpack","does_not_exist"), "unknown destination")
	check(snapshot() == before, "unknown destination atomic")
	check(inv.get_worn_storage("helmet").is_empty(), "unknown wearable slot")
	groups += 1
	# Restore more carried entries than fit in the starter pocket. Capacity must
	# come from validated worn ownership, not the current runtime or save fields.
	check(inv.load_save_data(saved), "reset fixture for large restore")
	for i in 8:
		check(inv.add_item("iron_sword"), "large snapshot item")
	var large: Dictionary = inv.get_save_data()
	var fresh: Node = load("res://scripts/systems/inventory_system.gd").new()
	root.add_child(fresh)
	check(fresh.configure_storage([{"id":"traveler_clothing_pocket","kind":"pocket","capacity":6}]), "fresh six-slot runtime")
	check(fresh.load_save_data(large), "restore validates worn capacity before carried count")
	check(fresh.items.size() == inv.items.size() and fresh.get_effective_capacity() == 14, "large restore count and trusted capacity")
	var forged: Dictionary = large.duplicate(true)
	forged.worn_storage.backpack.capacity = 99999
	check(fresh.load_save_data(forged), "extra capacity field sanitized")
	check(fresh.get_effective_capacity() == 14, "saved item cannot forge capacity")
	var unchanged := JSON.stringify(fresh.get_save_data())
	forged = large.duplicate(true)
	forged.worn_storage.backpack = null
	check(not fresh.load_save_data(forged), "missing worn owner cannot restore overflow")
	check(JSON.stringify(fresh.get_save_data()) == unchanged, "overflow restore atomic")
	fresh.queue_free()
	await process_frame
	groups += 1
	print("ASHBOUND_WEARABLE_GROUPS=",groups)
	if failures.is_empty() and groups == 11:
		print("ASHBOUND_WEARABLE_STORAGE_OK")
		quit(0)
	else:
		quit(1)
