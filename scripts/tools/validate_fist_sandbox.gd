extends SceneTree
## Codex QA of real preview UI, paired mobile events, practice and isolation.
var errors: Array[String] = []
var groups := 0
var scene: Node
var level: Node
var player: Node
var loc: Node
var strikes := 0
var settings_path := "res://.tools/fist-settings-%d.cfg" % OS.get_process_id()

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		printerr("FIST_SANDBOX_FAIL: " + message)

func group(message: String) -> void:
	groups += 1
	print("FIST_SANDBOX_GROUP %d %s" % [groups, message])

func settle(count: int = 3) -> void:
	for index in count: await process_frame

func button(name: String) -> Button:
	return scene.find_child(name, true, false) as Button

func mouse(position: Vector2, pressed: bool, device: int = 0) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.device = device
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)

func touch(position: Vector2, pressed: bool, index: int = 1, cancelled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = position
	event.index = index
	event.pressed = pressed
	event.canceled = cancelled
	root.push_input(event, true)

func tap(name: String, mode: String) -> void:
	var position := button(name).get_global_rect().get_center()
	for pressed in [true, false]:
		match mode:
			"mouse": mouse(position, pressed)
			"touch": touch(position, pressed)
			"mouse_first":
				mouse(position, pressed, InputEvent.DEVICE_ID_EMULATION)
				touch(position, pressed)
			"touch_first":
				touch(position, pressed)
				mouse(position, pressed, InputEvent.DEVICE_ID_EMULATION)
	await settle()

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event, true)
	await settle()

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.tools/fist-sandbox-" + name + ".png") == OK, "screenshot")

func run() -> void:
	root.size = Vector2i(1920, 1080)
	loc = root.get_node("Localization")
	loc.load_preferences(settings_path, "en_US")
	scene = load("res://scripts/tools/fist_technique_sandbox.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await settle(6)
	level = scene.level
	player = level.get_node("Actors/Player")
	player.set_physics_process(false)
	player.strike_requested.connect(func(): strikes += 1)
	var progress: Node = player.get_node("Progression")
	var initial: Dictionary = progress.get_character_data().duplicate(true)
	var inv: Node = root.get_node("Inventory")
	check(initial.unarmed_mastery == "novice" and initial.learning_points == 0, "campaign skill starts novice")
	check(level.get_node_or_null("Persistence") == null, "nested preview has no campaign persistence")
	check(inv.items.size() == 1 and inv.items[0].id == "traveler_backpack", "only an actual bag fixture")
	check(scene.technique == "novice" and not scene.set_technique("master"), "only two explicit preview techniques")
	check(player.get_node("Visual/Body").sprite_frames.get_meta("fist_preview_technique", "") == "novice", "initial preview actually uses novice artwork")
	for name in ["NoviceButton", "TrainedButton", "BackpackButton", "ViewButton"]:
		check(button(name) != null, "button exists " + name)
		if button(name) == null:
			quit(1)
			return
	group("isolated preview, no free training or campaign writes")
	for language in ["en", "ru"]:
		check(loc.set_language(language) == OK, "choose isolated QA language")
		await settle()
		check(button("NoviceButton").text == loc.text("FIST_PREVIEW_NOVICE"), "translated novice")
		check(button("TrainedButton").text == loc.text("FIST_PREVIEW_TRAINED"), "translated trained")
		var previous := Rect2()
		for name in ["NoviceButton", "TrainedButton", "BackpackButton", "ViewButton"]:
			var b := button(name)
			var rect := b.get_global_rect()
			print("FIST_SANDBOX_BUTTON %s %s %s" % [language, name, rect])
			check(root.get_visible_rect().encloses(rect), "toolbar fits " + language + name)
			check(rect.size.y >= 88 and rect.size.x >= 220, "finger-sized target " + name)
			check(b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x < b.size.x - 12, "label fits " + language + name)
			if previous.size != Vector2.ZERO: check(not previous.intersects(rect), "no overlapping buttons")
			previous = rect
		await capture(language)
	group("EN/RU readable toolbar")
	for dimensions in [Vector2i(1600, 900), Vector2i(2340, 1080), Vector2i(1920, 1080)]:
		root.size = dimensions
		await settle(4)
		for name in ["NoviceButton", "TrainedButton", "BackpackButton", "ViewButton"]:
			check(root.get_visible_rect().encloses(button(name).get_global_rect()), "resize keeps toolbar on screen " + str(dimensions) + name)
	for mode in ["mouse", "touch", "mouse_first", "touch_first"]:
		check(scene.set_backpack_enabled(false), "reset bag")
		check(scene.set_technique("novice"), "reset technique")
		await tap("TrainedButton", mode)
		check(scene.technique == "trained" and button("TrainedButton").button_pressed and not button("NoviceButton").button_pressed, "selected trained via " + mode)
		await tap("BackpackButton", mode)
		check(not inv.get_worn_storage("backpack").is_empty(), "single bag activation " + mode)
		await tap("BackpackButton", mode)
		check(inv.get_worn_storage("backpack").is_empty(), "single bag removal " + mode)
		var yaw: float = level.get_node("CameraRig").rotation.y
		await tap("ViewButton", mode)
		for frame in 3: await physics_frame
		var difference := wrapf(float(level.get_node("CameraRig").rotation.y) - yaw, -PI, PI)
		check(is_equal_approx(absf(difference), PI / 2.0), "one quarter-turn " + mode)
		check(level.get_node("CameraRig/SpringArm3D").get_hit_length() >= 2.4, "clear initial camera orbit " + mode)
	check(strikes == 0 and level.get_node("CameraRig")._touch_index == -1, "toolbar does not attack or capture camera")
	await key(KEY_F1)
	check(scene.technique == "novice", "F1")
	await key(KEY_F2)
	check(scene.technique == "trained", "F2")
	await key(KEY_F3)
	check(not inv.get_worn_storage("backpack").is_empty(), "F3")
	group("mouse, touch, emulation orders and keyboard")
	var position := button("NoviceButton").get_global_rect().get_center()
	touch(position, true)
	touch(position, false, 1, true)
	await settle()
	check(scene.technique == "trained", "cancelled finger does not choose")
	touch(position, true)
	touch(Vector2(10, 500), false)
	await settle()
	check(scene.technique == "trained", "release outside cancels")
	touch(position, true, 1)
	touch(button("TrainedButton").get_global_rect().get_center(), true, 2)
	touch(button("TrainedButton").get_global_rect().get_center(), false, 2)
	check(scene.technique == "trained", "second finger cannot steal first press")
	touch(position, false, 1)
	check(scene.technique == "novice", "original finger activates original choice")
	check(scene.set_technique("trained"), "reset for focus cancellation")
	touch(position, true)
	scene.get("_toolbar").notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	touch(position, false)
	check(scene.technique == "trained", "focus loss clears pending choice")
	var menu: Node = level.get_node("InventoryMenu")
	check(menu.request_open(), "menu can open through pocket gesture")
	await settle()
	check(not button("NoviceButton").is_visible_in_tree(), "toolbar hidden during opening")
	await key(KEY_F1)
	check(scene.technique == "trained", "F1 blocked behind menu")
	await create_timer(1.1).timeout
	check(menu.get_menu_state() == 2, "menu reaches open")
	menu.close_menu(false)
	await settle()
	check(button("NoviceButton").is_visible_in_tree(), "toolbar restored on close")
	group("cancelled input and modal menu")
	player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	player.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	player.input_enabled = true
	player.position = Vector3(5.7, 0.1, 3)
	player.facing_direction = Vector3.RIGHT
	level._apply_state(4)
	level.dummy_hits = 0
	for count in 6:
		player.stop_input()
		player.request_attack()
		player._physics_process(0.13)
		await settle()
		check(level.state == 4, "practice stays repeatable")
		check(level.dummy_hits == (count + 1) % 3, "actual dummy contact and third-hit reset")
	check(strikes == 6, "six actual strike signals")
	check(progress.get_character_data() == initial, "practice/switches never grant skill or points")
	level.get_node("Actors/Watchman").interacted.emit(level.get_node("Actors/Watchman"))
	check(progress.get_character_data() == initial, "no preview guard reward")
	check(level.get_node_or_null("Persistence") == null, "still no campaign persistence")
	check(scene.set_backpack_enabled(false), "remove bag before absent-item boundary")
	check(inv.remove_item("traveler_backpack"), "fixture relinquishes actual bag")
	var without_bag: Dictionary = inv.get_save_data().duplicate(true)
	check(not scene.set_backpack_enabled(true), "missing bag cannot be equipped or recreated")
	check(inv.get_save_data() == without_bag, "failed preview equip leaves inventory unchanged")
	group("repeat practice with progression isolation")
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	if errors.is_empty() and groups == 5:
		print("ASHBOUND_FIST_SANDBOX_OK groups=5")
		quit(0)
	else:
		quit(1)
