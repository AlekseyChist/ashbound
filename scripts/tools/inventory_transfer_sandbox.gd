extends Node
## Explicit QA fixture. Not part of the courtyard export or campaign start.

var level: Node

func _ready() -> void:
	DisplayServer.window_set_title("ASHBOUND — Inventory transfer QA")
	var inventory: Node = get_node("/root/Inventory")
	var localization: Node = get_node("/root/Localization")
	localization.load_preferences("user://transfer-sandbox-language.cfg", "ru_RU")
	var configured: bool = inventory.configure_storage([
		{"id":"traveler_clothing_pocket", "kind":"pocket", "capacity":6},
		{"id":"qa_backpack", "kind":"backpack", "capacity":8},
		{"id":"qa_pouch", "kind":"pouch", "capacity":2},
	])
	if not configured or not inventory.add_item("bread", 3) or not inventory.add_item("rusty_sword", 1) or not inventory.add_item("health_potion", 2):
		printerr("TRANSFER_SANDBOX_FAIL: fixture setup")
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
	for id in ["Items", "TransferTarget", "TransferButton", "LanguageChoice", "CloseButton"]:
		var control: Control = panel.get_node("%" + id)
		print("TRANSFER_SANDBOX_RECT ", id, " ", control.get_global_rect())

func _report_storage() -> void:
	var inventory: Node = get_node("/root/Inventory")
	print("TRANSFER_SANDBOX_STORAGE ", JSON.stringify(inventory.get_save_data().get("storage", {})))
