extends SceneTree
## Independent regression: duplicate Android Back deliveries must not exit a modal.

var scene: Node
var menu: Node
var failures: Array[String] = []
var groups := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		printerr("INVENTORY_BACK_FAIL: " + label)

func frames(count: int = 3) -> void:
	for i in count:
		await process_frame

func cancel_key() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	menu._input(event)
	event.pressed = false
	menu._input(event)

func back() -> void:
	menu.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)

func _run() -> void:
	root.get_node("Localization").load_preferences("res://.tools/inventory-back-qa.cfg", "en_US")
	quit_on_go_back = true
	scene = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	root.add_child(scene)
	await frames(5)
	menu = scene.get_node("InventoryMenu")
	var snapshot: Dictionary = root.get_node("Inventory").get_save_data()
	for fully_open in [false, true]:
		for order in ["notifications", "key_first", "notification_first"]:
			check(menu.request_open(), "open: " + order)
			if fully_open:
				await create_timer(0.9).timeout
				check(menu.get_menu_state() == 2, "gesture completed")
			else:
				check(menu.get_menu_state() == 1, "opening before delivery")
			print("INVENTORY_BACK_CASE open=%s order=%s" % [fully_open, order])
			match order:
				"notifications":
					back()
					await frames(1)
					back()
				"key_first":
					cancel_key()
					await frames(2)
					back()
				"notification_first":
					back()
					cancel_key()
					await frames(1)
					back()
			await frames(5)
			check(menu.get_menu_state() == 0, "Back closes")
			check(scene.get_node("Actors/Player").input_enabled, "player input restored")
			check(scene.get_node("CameraRig").input_enabled, "camera input restored")
			check(scene.get_node("HUD").visible, "HUD restored")
			check(not quit_on_go_back, "Back still owned")
			check(root.get_node("Inventory").get_save_data() == snapshot, "inventory unchanged")
			groups += 1
	if "--expect-closed-exit" in OS.get_cmdline_user_args():
		check(failures.is_empty() and groups == 6, "all modal cases passed before exit")
		if not failures.is_empty():
			quit(1)
			return
		print("ASHBOUND_INVENTORY_BACK_CLOSED_EXIT_ARMED groups=6")
		# Same hardware press can generate notifications across adjacent frames.
		# An independent later Back is outside the documented 250ms grace.
		await create_timer(0.35).timeout
		back()
		await frames(10)
		printerr("INVENTORY_BACK_FAIL: separate later Back did not exit")
		quit(1)
		return
	scene.queue_free()
	await frames()
	check(quit_on_go_back, "original Back policy restored after teardown")
	if failures.is_empty() and groups == 6:
		print("ASHBOUND_INVENTORY_BACK_OK groups=6")
		quit(0)
	else:
		quit(1)
