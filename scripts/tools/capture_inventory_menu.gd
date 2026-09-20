extends SceneTree
## Graphical QA only; fixtures never run from the shipped main scene.

var failures: Array[String] = []
var scene: Node
var menu: Node
var panel: Control
var prefix := "res://.tools/inv01"

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("CAPTURE_FAIL: " + message)

func _wait(seconds: float = 0.15) -> void:
	await create_timer(seconds).timeout

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image.save_png(prefix + "-" + name + ".png") == OK, "write " + name)
	print("INVENTORY_CAPTURE ", name)

func _layout(language: String) -> void:
	var window_rect := panel.get_global_rect()
	var viewport_rect := root.get_visible_rect()
	_check(viewport_rect.encloses(window_rect), language + " window within viewport")
	for id in ["Title", "CloseButton", "Source", "Empty", "Items", "Coins", "LanguageLabel", "LanguageChoice", "SettingsError"]:
		var control: Control = panel.get_node("%" + id)
		if not control.visible:
			continue
		_check(window_rect.grow(1).encloses(control.get_global_rect()), language + " fits " + id)
		if control is Label and control.autowrap_mode == TextServer.AUTOWRAP_OFF:
			var font: Font = control.get_theme_font("font")
			var font_size: int = control.get_theme_font_size("font_size")
			_check(font.get_string_size(control.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= control.size.x + 1, language + " label not clipped " + id)

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--inventory-capture-prefix="):
			prefix = argument.trim_prefix("--inventory-capture-prefix=")
	if DisplayServer.get_name() == "headless":
		printerr("Graphical rendering required")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	var loc: Node = root.get_node("Localization")
	var inv: Node = root.get_node("Inventory")
	var original: Dictionary = inv.get_save_data()
	loc.load_preferences("res://.tools/inventory-capture-qa.cfg", "en_US")
	scene = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	scene.get_node("HUD").force_touch_controls = true
	root.add_child(scene)
	current_scene = scene
	await _wait(0.5)
	menu = scene.get_node("InventoryMenu")
	panel = menu.get_node("RootControl/Overlay/Window")
	await _capture("closed-en")
	_check(menu.request_open(), "start gesture")
	await _wait(0.28)
	_check(not panel.visible, "window hidden during gesture")
	await _capture("gesture-en")
	await _wait(0.8)
	_check(panel.visible, "window after gesture")
	_layout("empty EN")
	await _capture("empty-en")
	menu.close_menu()
	inv.add_item("bread", 3)
	inv.add_item("rusty_sword", 1)
	inv.add_item("health_potion", 2)
	inv.add_gold(17)
	var seeded: Dictionary = inv.get_save_data()
	for language in ["en", "ru"]:
		loc.load_preferences("res://.tools/inventory-capture-qa.cfg", language)
		_check(menu.request_open(), "open " + language)
		await _wait(0.85)
		_layout(language)
		await _capture("items-" + language)
		menu.close_menu()
	_check(inv.get_save_data() == seeded, "presentation never mutates fixture")
	inv.load_save_data(original)
	scene.queue_free()
	await _wait()
	if failures.is_empty():
		print("ASHBOUND_INVENTORY_CAPTURE_OK images=5")
		quit(0)
	else:
		printerr("ASHBOUND_INVENTORY_CAPTURE_FAILED errors=", failures.size())
		quit(1)
