extends SceneTree
## Reproduces S23's emulated-mouse-before-touch order, plus desktop input.

var errors: PackedStringArray = []
var run_events := 0
var attack_events := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)

func mouse_at(position: Vector2, pressed: bool, device: int) -> void:
	var event := InputEventMouseButton.new()
	event.device = device
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)

func touch_at(position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = pressed
	root.push_input(event, true)

func paired_tap(position: Vector2, mouse_first: bool) -> void:
	for pressed in [true, false]:
		if mouse_first:
			mouse_at(position, pressed, InputEvent.DEVICE_ID_EMULATION)
			touch_at(position, pressed)
		else:
			touch_at(position, pressed)
			mouse_at(position, pressed, InputEvent.DEVICE_ID_EMULATION)
	await process_frame

func run() -> void:
	root.size = Vector2i(1920, 1080)
	var scene: Node = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	var hud: Node = scene.get_node("HUD")
	hud.force_touch_controls = true
	root.add_child(scene)
	await process_frame
	await process_frame
	var run_button: Control = hud.get_node("RootControl/BottomRight/VBox/RunButton")
	var attack_button: Control = hud.get_node("RootControl/BottomRight/VBox/AttackButton")
	var right_button: Control = hud.get_node("RootControl/BottomLeft/DpadGrid/Right")
	hud.run_changed.connect(func(_enabled: bool): run_events += 1)
	hud.attack_pressed.connect(func(): attack_events += 1)
	var scenarios := 0
	for mouse_first in [true, false]:
		for after_menu in [false, true]:
			if after_menu:
				var menu: Node = scene.get_node("InventoryMenu")
				check(menu.request_open(), "menu opens before input regression")
				await create_timer(1.1).timeout
				menu.close_menu()
			hud.reset_controls()
			await create_timer(0.4).timeout
			run_events = 0
			await paired_tap(run_button.get_global_rect().get_center(), mouse_first)
			check(hud._run_enabled, "first paired tap must enable running: %s/%s" % [mouse_first, after_menu])
			check(run_events == 1, "first paired tap must emit exactly once")
			await create_timer(0.4).timeout
			await paired_tap(run_button.get_global_rect().get_center(), mouse_first)
			check(not hud._run_enabled, "second paired tap must disable running")
			check(run_events == 2, "two paired taps must emit exactly twice")
			check(hud._touch_run_index == -1, "paired tap releases run ownership")
			await create_timer(0.4).timeout
			attack_events = 0
			await paired_tap(attack_button.get_global_rect().get_center(), mouse_first)
			check(attack_events == 1, "paired attack must emit once: %s/%s" % [mouse_first, after_menu])
			scenarios += 1
			await create_timer(0.9).timeout
	# A physical desktop mouse remains supported even when touch controls are shown.
	hud.reset_controls()
	await create_timer(0.4).timeout
	run_events = 0
	for pressed in [true, false]:
		mouse_at(run_button.get_global_rect().get_center(), pressed, 0)
	await process_frame
	check(hud._run_enabled and run_events == 1, "real mouse toggles running once")
	mouse_at(right_button.get_global_rect().get_center(), true, 0)
	check(hud._held_dir == hud.Dir.RIGHT, "real mouse can hold movement")
	mouse_at(right_button.get_global_rect().get_center(), false, 0)
	check(hud._held_dir == hud.Dir.NONE, "real mouse release stops movement")
	scenarios += 1
	scene.queue_free()
	await process_frame
	if errors.is_empty() and scenarios == 5:
		print("ASHBOUND_COURTYARD_INPUT_ORDER_OK scenarios=5")
		quit(0)
	else:
		for message in errors:
			push_error(message)
		quit(1)
