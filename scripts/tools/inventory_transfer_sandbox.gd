extends Node
## Explicit QA fixture. Not part of the courtyard export or campaign start.

var level: Node

func _ready() -> void:
	DisplayServer.window_set_title("ASHBOUND — Touch inventory QA")
	var inventory: Node = get_node("/root/Inventory")
	var localization: Node = get_node("/root/Localization")
	localization.load_preferences("user://transfer-sandbox-language.cfg", "ru_RU")
	var configured: bool = inventory.configure_storage([
		{"id":"traveler_clothing_pocket", "kind":"pocket", "capacity":6},
	])
	if not configured:
		printerr("TRANSFER_SANDBOX_FAIL: fixture setup")
		get_tree().quit(1)
		return
	for id in ["bread", "rusty_sword", "health_potion", "leather_armor", "traveler_backpack", "belt_pouch"]:
		if not inventory.add_item(id, 3 if id == "bread" else 1):
			printerr("TRANSFER_SANDBOX_FAIL: seed ", id)
			get_tree().quit(1)
			return
	inventory.add_gold(17)
	inventory.storage_changed.connect(_report_storage)
	level = preload("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	level.get_node("HUD").force_touch_controls = true
	add_child(level)
	await get_tree().create_timer(0.5).timeout
	level.get_node("InventoryMenu").request_open()
	await get_tree().create_timer(1.0).timeout
	print("ASHBOUND_TRANSFER_SANDBOX_READY")
	_report_storage()
	var panel: Control = level.get_node("InventoryMenu/RootControl/Overlay/Window")
	for id in ["ItemGrid", "StorageTabs", "ArmorSlot", "WeaponSlot", "BackpackSlot", "PouchSlot", "QuickSlots", "LanguageChoice", "CloseButton"]:
		var control: Control = panel.get_node("%" + id)
		print("TRANSFER_SANDBOX_RECT ", id, " ", control.get_global_rect())

func _report_storage() -> void:
	var inventory: Node = get_node("/root/Inventory")
	print("TRANSFER_SANDBOX_STORAGE ", JSON.stringify(inventory.get_save_data().get("storage", {})))
