extends SceneTree
## Independent QA: modal lifecycle, input ownership, loss of access and cleanup.

var failures: Array[String] = []
var groups := 0
var scene: Node
var menu: Node
var player: Node
var hud: Node
var camera: Node
var access: Node
var panel: Control
var opened_count := 0
var closed_count := 0
var strikes := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("MENU_FAIL: " + message)

func frames(n: int = 3) -> void:
	for i in n:
		await physics_frame

func key(code: Key, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	event.echo = echo
	root.push_input(event, true)
	if not echo:
		event = event.duplicate()
		event.pressed = false
		root.push_input(event, true)

func touch(index: int, pos: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)

func drag(index: int, pos: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	event.relative = relative
	root.push_input(event, true)

func mouse_click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.global_position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.device = InputEvent.DEVICE_ID_MOUSE
		root.push_input(event, true)

func assert_closed(label: String) -> void:
	check(menu.get_menu_state() == 0 and not panel.visible, label + ": closed")
	check(player.input_enabled and camera.input_enabled, label + ": movement/look restored")
	check(hud.visible and hud.is_processing_input(), label + ": HUD restored")
	check(not player.get_node("Visual").is_inventory_access_active(), label + ": normal artwork restored")

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	root.get_node("Localization").load_preferences("res://.tools/inventory-menu-qa.cfg", "en_US")
	var original_back := quit_on_go_back
	var snapshot: Dictionary = root.get_node("Inventory").get_save_data()
	scene = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	hud = scene.get_node("HUD")
	hud.force_touch_controls = true
	root.add_child(scene)
	await frames(5)
	menu = scene.get_node_or_null("InventoryMenu")
	if menu == null or not menu.has_method("request_open"):
		printerr("MENU_FAIL: integrated menu script is unavailable")
		quit(1)
		return
	player = scene.get_node("Actors/Player")
	camera = scene.get_node("CameraRig")
	access = player.get_node("PocketAccess")
	panel = menu.get_node("RootControl/Overlay/Window")
	menu.opened.connect(func(): opened_count += 1)
	menu.closed.connect(func(): closed_count += 1)
	player.strike_requested.connect(func(): strikes += 1)
	assert_closed("initial")
	check(not quit_on_go_back, "menu owns mobile Back")
	var position: Vector3 = player.global_position
	var yaw: float = camera.rotation.y
	var initial_mouse_mode := Input.mouse_mode
	check(menu.request_open(), "valid access starts")
	check(menu.get_menu_state() == 1 and not panel.visible, "gesture before content")
	check(not player.input_enabled and not camera.input_enabled and not hud.is_processing_input(), "all gameplay input locked")
	check(not paused and not menu.request_open(), "world running / duplicate begin rejected")
	player.request_attack()
	player.set_move_input(Vector2.RIGHT)
	camera.rotate_view(Vector2(100, 30))
	await frames(50)
	check(menu.get_menu_state() == 2 and panel.visible and opened_count == 1, "only actual gesture completion opens once")
	check(player.global_position.distance_to(position) < 0.2 and is_equal_approx(camera.rotation.y, yaw) and strikes == 0, "modal doesn't move, look or attack")
	menu.close_menu()
	assert_closed("normal close")
	check(Input.mouse_mode == initial_mouse_mode, "normal close restores actual desktop mouse mode")
	check(root.get_node("Inventory").get_save_data() == snapshot, "opening creates no items")
	groups += 1

	key(KEY_I)
	check(menu.get_menu_state() == 1, "I opens")
	key(KEY_I, true)
	check(menu.get_menu_state() == 1, "keyboard repeat ignored")
	key(KEY_TAB)
	assert_closed("Tab cancels gesture")
	await frames(50)
	check(opened_count == 1, "cancel never opens later")
	key(KEY_TAB)
	await frames(50)
	key(KEY_ESCAPE)
	assert_closed("Escape closes")
	groups += 1

	player.input_enabled = false
	check(not menu.request_open() and not player.input_enabled, "external player lock preserved")
	player.input_enabled = true
	var message: Control = hud.get_node("RootControl/MessagePanel")
	message.show()
	check(not menu.request_open(), "dialogue prevents opening")
	message.hide()
	player.request_attack()
	check(player.is_attacking() and not menu.request_open(), "active strike prevents opening")
	await frames(50)
	player.set("_cooldown", 4.0)
	check(menu.request_open(), "opening permitted after strike")
	menu.close_menu()
	check(float(player.get("_cooldown")) > 3.9, "menu must not bypass attack cooldown")
	player.set("_cooldown", 0.0)
	groups += 1

	var pocket: AnimatedSprite3D = player.get_node("Visual/PocketPose")
	var good_frames := pocket.sprite_frames
	pocket.sprite_frames = SpriteFrames.new()
	check(not menu.request_open(), "invalid gesture fails without locking player")
	assert_closed("failed gesture rollback")
	pocket.sprite_frames = good_frames
	check(menu.request_open(), "begin before availability loss")
	access.available = false
	await frames()
	assert_closed("access lost during opening")
	check(not menu.request_open(), "unavailable pocket prevents opening")
	access.available = true
	check(menu.request_open(), "access restored")
	await frames(50)
	access.storage_id = &"different_clothing"
	await frames()
	assert_closed("storage identity changed")
	access.storage_id = &"traveler_clothing_pocket"
	check(root.get_node("Inventory").get_save_data() == snapshot, "access loss never destroys items")
	groups += 1

	check(menu.request_open(), "begin before node replacement")
	player.remove_child(access)
	var old_access := access
	access = load("res://scripts/courtyard/pocket_access.gd").new()
	access.name = "PocketAccess"
	player.add_child(access)
	await frames()
	assert_closed("replacement isn't original pocket")
	old_access.free()
	groups += 1

	check(menu.request_open(), "begin before focus loss")
	menu.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_closed("focus loss")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "focus loss leaves cursor free")
	await frames(50)
	check(menu.get_menu_state() == 0, "no reopen after focus loss")
	check(menu.request_open(), "begin before mobile pause")
	menu.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_closed("mobile pause")
	check(menu.request_open(), "begin before Android Back")
	menu.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_closed("Android Back")
	groups += 1

	check(menu.request_open(), "begin before reset")
	scene.reset_lesson()
	await frames()
	assert_closed("lesson reset")
	camera.input_enabled = false
	hud.visible = false
	hud.set_process_input(false)
	check(menu.request_open(), "begin with pre-existing camera/HUD flags")
	menu.close_menu()
	check(not camera.input_enabled and not hud.visible and not hud.is_processing_input(), "original flags restored exactly")
	camera.input_enabled = true
	hud.visible = true
	hud.set_process_input(true)
	groups += 1

	var open_button: Control = menu.get_node("RootControl/OpenButton")
	var center := open_button.get_global_rect().get_center()
	var move_button: Control = hud.get_node("RootControl/BottomLeft/DpadGrid/Right")
	touch(10, move_button.get_global_rect().get_center(), true)
	await frames(3)
	check(player.get("_touch_move") == Vector2.RIGHT, "touch fixture moves")
	touch(11, center, true)
	touch(11, center, false)
	await frames(2)
	check(menu.get_menu_state() == 1, "touch opens once")
	touch(10, move_button.get_global_rect().get_center(), false)
	await frames(50)
	check(menu.get_menu_state() == 2, "touch open reaches window")
	var background := panel.get_global_rect().position + Vector2(5, 250)
	touch(12, background, true)
	touch(12, background, false)
	await frames(2)
	check(menu.get_menu_state() == 2, "panel background touch doesn't close")
	var close_button: Control = panel.get_node("%CloseButton")
	var close_center := close_button.get_global_rect().get_center()
	touch(14, close_center, true)
	touch(14, close_center, false, true)
	await frames(2)
	check(menu.get_menu_state() == 2, "canceled close touch has no action")
	touch(13, close_center, true)
	touch(15, close_center, false)
	check(menu.get_menu_state() == 2, "other finger cannot release owned Close")
	touch(13, close_center, false)
	await frames(2)
	assert_closed("touch close")
	check(player.get("_touch_move") == Vector2.ZERO and not player.is_running(), "no stuck motion/run after release over menu")
	var strikes_before := strikes
	var mouse := InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.position = close_center
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	root.push_input(mouse, true)
	mouse = mouse.duplicate()
	mouse.pressed = false
	root.push_input(mouse, true)
	await frames(30)
	check(strikes == strikes_before and menu.get_menu_state() == 0, "emulated mouse doesn't attack or reopen")
	groups += 1

	touch(20, center, true)
	drag(20, center + Vector2(-450, 200), Vector2(-450, 200))
	touch(20, center + Vector2(-450, 200), false)
	await frames(2)
	check(menu.get_menu_state() == 0, "drag off Open button cancels")
	touch(21, center + Vector2(-450, 0), true)
	drag(21, center, Vector2(450, 0))
	touch(21, center, false)
	await frames(2)
	check(menu.get_menu_state() == 0, "drag from outside cannot open")
	camera.set_mouse_capture(false)
	mouse_click(center)
	await frames(50)
	check(menu.get_menu_state() == 2, "native mouse opens only through GUI button")
	mouse_click(panel.get_node("%CloseButton").get_global_rect().get_center())
	await frames()
	assert_closed("native mouse close")
	groups += 1

	check(menu.request_open(), "begin before controller teardown")
	menu.queue_free()
	await frames()
	check(player.input_enabled and camera.input_enabled and hud.visible and hud.is_processing_input(), "teardown restores owned locks")
	check(quit_on_go_back == original_back, "teardown restores Back ownership")
	check(root.get_node("Inventory").get_save_data() == snapshot, "entire menu lifecycle leaves inventory unchanged")
	groups += 1
	scene.queue_free()
	await frames()
	if failures.is_empty() and groups == 10:
		print("ASHBOUND_INVENTORY_MENU_OK groups=10")
		quit(0)
	else:
		printerr("ASHBOUND_INVENTORY_MENU_FAILED groups=%d errors=%d" % [groups, failures.size()])
		quit(1)
