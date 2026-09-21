extends SceneTree
var failures: Array[String] = []
var groups := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		printerr("STORAGE_PANEL_FAIL: " + label)

func settle() -> void:
	for i in 4:
		await process_frame

func _run() -> void:
	var inv := root.get_node_or_null("Inventory")
	var loc := root.get_node_or_null("Localization")
	if inv == null or loc == null or not inv.has_method("configure_storage"):
		printerr("STORAGE_PANEL_FAIL: required autoload missing")
		quit(1)
		return
	loc.load_preferences("res://.tools/storage-panel-qa.cfg", "en_US")
	var unavailable: Node = load("res://scripts/courtyard/pocket_access.gd").new()
	unavailable.available = false
	root.add_child(unavailable)
	check(not inv.is_storage_configured(), "unavailable clothing cannot create a storage profile")
	unavailable.queue_free()
	await settle()
	var level: Node = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	root.add_child(level)
	await settle()
	var access: Node = level.get_node("Actors/Player/PocketAccess")
	var menu: Node = level.get_node("InventoryMenu")
	var panel: Control = menu.get_node("RootControl/Overlay/Window")
	var source: Label = panel.get_node("%Source")
	check(inv.items.is_empty() and inv.gold == 0, "no free items or money on storage setup")
	check(inv.get_storage_containers().size() == 1 and inv.get_effective_capacity() == 6, "starter clothing provides exactly one configured pocket")
	check(access.has_access() and menu.request_open(), "physical pocket allows gesture")
	check(not panel.visible, "capacity panel waits for gesture")
	await create_timer(0.9).timeout
	check(panel.visible and source.text == "Clothing pocket · slots: 0/6", "empty English capacity displayed")
	groups += 1

	check(inv.add_item("rusty_sword", 6), "fill six slots")
	await settle()
	check(source.text == "Clothing pocket · slots: 6/6", "capacity refreshes on acquisition")
	var full: Dictionary = inv.get_save_data()
	check(not inv.add_item("bread") and inv.get_save_data() == full, "full pocket rejects hidden overflow")
	loc.load_preferences("res://.tools/storage-panel-qa.cfg", "ru_RU")
	await settle()
	check(source.text == "Карман одежды · места: 6/6", "Russian capacity refreshes in open menu")
	check(inv.get_save_data() == full, "language switch cannot move or duplicate belongings")
	groups += 1

	var profile := [{"id": "traveler_clothing_pocket", "kind": "pocket", "capacity": 6}, {"id": "qa_bag", "kind": "backpack", "capacity": 2}]
	check(inv.configure_storage(profile), "trusted fixture adds a second physical storage")
	var item: Dictionary = inv.items[0]
	check(inv.move_item_to_storage({"instance_id": item["instance_id"]}, "qa_bag"), "trusted whole-item transfer")
	await settle()
	check(source.text.contains("Карман одежды · места: 5/6") and source.text.contains("Рюкзак · места: 1/2"), "each storage shows own occupancy")
	var rows: ItemList = panel.get_node("%Items")
	var bag_rows := 0
	for i in rows.item_count:
		if rows.get_item_text(i).contains("Рюкзак"):
			bag_rows += 1
	check(bag_rows == 1 and rows.item_count == 6, "row names identify exactly the moved item")
	check(not source.text.contains("qa_bag"), "internal IDs stay out of visible text")
	groups += 1

	menu.close_menu()
	var contents_before: Dictionary = inv.get_save_data()
	access.available = false
	check(not access.has_access() and not menu.request_open(), "lost access cannot open a hidden store")
	check(inv.get_save_data() == contents_before, "loss of access does not delete carried items")
	access.available = true
	check(access.has_access(), "access returns with real clothing")
	check(inv.remove_item("rusty_sword", 6), "remove fixture belongings")
	check(inv.configure_storage([]), "empty storage can be detached")
	check(not access.has_access() and not menu.request_open(), "menu does not recreate a missing physical pocket")
	check(inv.get_effective_capacity() == 0 and inv.items.is_empty(), "no automatic replacement capacity or loot")
	check(inv.configure_storage([{"id": "traveler_clothing_pocket", "kind": "backpack", "capacity": 6}]), "mismatched-kind fixture")
	check(not access.has_access() and not menu.request_open(), "pocket gesture cannot open a backpack with the same id")
	groups += 1

	level.queue_free()
	await settle()
	if failures.is_empty() and groups == 4:
		print("ASHBOUND_STORAGE_PANEL_OK groups=4")
		quit(0)
	else:
		printerr("ASHBOUND_STORAGE_PANEL_FAILED groups=%d failures=%d" % [groups, failures.size()])
		quit(1)
