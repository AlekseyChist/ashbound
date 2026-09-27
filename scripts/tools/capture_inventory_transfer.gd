extends SceneTree
## Rendered input and layout QA; never selected by production export.
var failures: Array[String] = []
var level: Node
var panel: Control
var inv: Node
var loc: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("TRANSFER_CAPTURE_FAIL: " + message)

func settle() -> void:
	await create_timer(0.2).timeout

func tap(position: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = position
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await settle()

func capture(suffix: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://.tools/transfer-" + suffix + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, "capture " + suffix)

func layout(label: String) -> void:
	var area := panel.get_global_rect()
	check(root.get_visible_rect().encloses(area), label + " window fits viewport")
	for id in ["CloseButton", "Source", "Items", "ItemDetails", "TransferTarget", "TransferButton", "TransferError", "Coins", "LanguageChoice"]:
		var control: Control = panel.get_node("%" + id)
		if control.is_visible_in_tree():
			check(area.grow(1).encloses(control.get_global_rect()), label + " fits " + id)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Graphical rendering required")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	inv = root.get_node("Inventory")
	loc = root.get_node("Localization")
	loc.load_preferences("res://.tools/transfer-capture-qa.cfg", "en_US")
	inv.configure_storage([{"id":"traveler_clothing_pocket", "kind":"pocket", "capacity":6}, {"id":"traveler_wallet", "kind":"wallet", "capacity":4}])
	inv.add_item("bread", 3)
	inv.add_item("rusty_sword", 1)
	inv.add_item("health_potion", 2)
	level = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	level.get_node("HUD").force_touch_controls = true
	root.add_child(level)
	current_scene = level
	await settle()
	var menu: Node = level.get_node("InventoryMenu")
	check(menu.request_open(), "open actual pocket menu")
	await create_timer(0.9).timeout
	panel = menu.get_node("RootControl/Overlay/Window")
	check(panel.visible, "gesture finished")
	var rows: ItemList = panel.get_node("%Items")
	# Actual native screen-touch input, no signal shortcut for row selection.
	await tap(rows.global_position + rows.get_item_rect(0).get_center())
	check(rows.get_selected_items().size() == 1, "native touch selects one row with emulation off")
	check(panel.get_node("%TransferRow").visible, "touch selection reveals physical destination")
	for language in ["en", "ru"]:
		loc.load_preferences("res://.tools/transfer-capture-qa.cfg", language)
		await settle()
		layout(language)
		await capture("selected-" + language)
	var bread: Dictionary = inv.items[0].duplicate(true)
	var before: Dictionary = inv.get_save_data()
	await tap(panel.get_node("%TransferButton").get_global_rect().get_center())
	check(inv.get_item_storage(bread.instance_id) == "traveler_wallet", "real touch moves whole stack")
	check(inv.get_item_count("bread") == 3 and inv.items.size() == before.items.size(), "real touch does not duplicate or consume")
	layout("after move")
	await capture("moved-ru")
	check(inv.add_item("rusty_sword", 8), "seed a scrolling list")
	await settle()
	var selected_before := rows.get_selected_items()
	var scroll_before := rows.get_v_scroll_bar().value
	var start := rows.global_position + Vector2(150, rows.size.y - 30)
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = start
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	for i in 10:
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = start - Vector2(0, (i + 1) * 18)
		drag.relative = Vector2(0, -18)
		Input.parse_input_event(drag)
		await process_frame
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = start - Vector2(0, 180)
	release.pressed = false
	Input.parse_input_event(release)
	await settle()
	check(rows.get_v_scroll_bar().value > scroll_before, "native drag scrolls overflowing item list")
	check(rows.get_selected_items() == selected_before, "scroll does not select another item")
	menu.close_menu()
	check(not panel.visible and level.get_node("Actors/Player").input_enabled, "close restores movement")
	level.queue_free()
	await settle()
	if failures.is_empty():
		print("ASHBOUND_TRANSFER_CAPTURE_OK images=3")
		quit(0)
	else:
		printerr("ASHBOUND_TRANSFER_CAPTURE_FAILED failures=%d" % failures.size())
		quit(1)
