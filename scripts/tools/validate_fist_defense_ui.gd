extends Node
## Codex QA through viewport input, including paired emulated events and multitouch.
var errors: Array[String] = []
var groups := 0
var root: Window
var sandbox: Node
var defense: Node
var player: Node
var loc: Node

func _ready() -> void:
	root = get_tree().root
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		printerr("DEFENSE_UI_FAIL: " + message)

func group(message: String) -> void:
	groups += 1
	print("DEFENSE_UI_GROUP %d %s" % [groups, message])

func settle(count: int = 3) -> void:
	for i in count: await get_tree().process_frame

func button(name: String) -> Button:
	return sandbox.find_child(name, true, false) as Button

func center(name: String) -> Vector2:
	return button(name).get_global_rect().get_center()

func touch(pos: Vector2, pressed: bool, index: int = 11, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = pos
	event.pressed = pressed
	event.index = index
	event.canceled = canceled
	root.push_input(event, true)

func mouse(pos: Vector2, pressed: bool, device: int = 0) -> void:
	var event := InputEventMouseButton.new()
	event.position = pos
	event.global_position = pos
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	event.device = device
	root.push_input(event, true)

func key(code: Key, pressed: bool, physical_only: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_NONE if physical_only else code
	event.physical_keycode = code
	event.pressed = pressed
	root.push_input(event, true)

func tap(name: String, mode: String) -> void:
	var pos := center(name)
	for pressed in [true, false]:
		match mode:
			"mouse": mouse(pos, pressed)
			"touch": touch(pos, pressed)
			"touch_first":
				touch(pos, pressed)
				mouse(pos, pressed, InputEvent.DEVICE_ID_EMULATION)
			"mouse_first":
				mouse(pos, pressed, InputEvent.DEVICE_ID_EMULATION)
				touch(pos, pressed)
	await settle()

func screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var dest := "user://defense-" + name + ".png" if OS.has_feature("android") else "res://.tools/defense-" + name + ".png"
	check(root.get_texture().get_image().save_png(dest) == OK, "capture " + name)

func run() -> void:
	root.size = Vector2i(1920,1080)
	loc = root.get_node("Localization")
	loc.load_preferences("user://defense-qa-settings.cfg", "en_US")
	sandbox = load("res://scripts/tools/fist_defense_sandbox.tscn").instantiate()
	add_child(sandbox)
	await settle(6)
	player = sandbox.level.get_node("Actors/Player")
	defense = sandbox.get("defense")
	player.set_physics_process(false)
	defense.set_physics_process(false)
	for name in ["SwingButton","ResetTrialButton","GuardButton"]:
		if button(name) == null:
			check(false, "missing button " + name)
			get_tree().quit(1)
			return
	for language in ["en","ru"]:
		loc.set_language(language)
		for dimensions in [Vector2i(1920,1080),Vector2i(2340,1080),Vector2i(1600,900)]:
			root.size = dimensions
			await settle(5)
			var rects: Array[Rect2] = []
			for name in ["NoviceButton","TrainedButton","BackpackButton","ViewButton","SwingButton","ResetTrialButton","GuardButton"]:
				var b := button(name)
				var rect := b.get_global_rect()
				check(root.get_visible_rect().encloses(rect), "onscreen " + language + name + str(dimensions))
				check(rect.size.x >= 220 and rect.size.y >= 88, "finger target " + name)
				for other in rects: check(not rect.intersects(other), "buttons do not overlap " + name)
				rects.append(rect)
				check(b.get_theme_font("font").get_string_size(b.text,HORIZONTAL_ALIGNMENT_LEFT,-1,b.get_theme_font_size("font_size")).x < b.size.x - 10, "label fits " + language + name)
			for name in ["SwingButton","ResetTrialButton","GuardButton"]:
				print("DEFENSE_UI_RECT %s %s %s" % [language,name,button(name).get_global_rect()])
			var old_panel: Control = sandbox.get("_toolbar").get("_panel")
			check(not old_panel.get_global_rect().intersects(button("SwingButton").get_global_rect()), "new row clears entire old panel")
			var hud: Node = sandbox.level.get_node("HUD")
			for field in ["_btn_attack","_btn_interact","_btn_run"]:
				var old_button: Button = hud.get(field)
				check(not old_button.get_global_rect().intersects(button("GuardButton").get_global_rect()), "guard clears existing HUD " + field)
		check(button("GuardButton").text == loc.text("DEFENSE_GUARD"), "translated guard")
		check(button("GuardButton").text == ("Hold guard" if language == "en" else "Держать защиту"), "guard has actual complete translation")
		check(button("SwingButton").text == ("Incoming strike" if language == "en" else "Входящий удар"), "swing has actual complete translation")
		check(button("ResetTrialButton").text == ("Reset positions" if language == "en" else "На исходную"), "reset has actual complete translation")
		var hint: Label = sandbox.find_child("DefenseHintLabel",true,false) as Label
		check(hint != null and not hint.text.contains("DEFENSE_"), "hint uses translated text")
		await screenshot(language)
	group("EN/RU layout and finger targets across aspect ratios")

	for mode in ["mouse","touch","touch_first","mouse_first"]:
		await tap("ResetTrialButton",mode)
		await tap("TrainedButton",mode)
		await tap("SwingButton",mode)
		check(defense.snapshot().phase == "windup", "explicit start " + mode)
		defense.advance(0.68)
		var pos := center("GuardButton")
		if mode == "mouse": mouse(pos,true)
		elif mode == "mouse_first":
			mouse(pos,true,InputEvent.DEVICE_ID_EMULATION)
			touch(pos,true)
		else:
			touch(pos,true)
			if mode == "touch_first": mouse(pos,true,InputEvent.DEVICE_ID_EMULATION)
		check(defense.snapshot().guarding, "hold down takes effect immediately " + mode)
		defense.advance(0.13)
		check(defense.snapshot().result == "perfect_block" and defense.snapshot().contacts == 1, "real input timely block " + mode)
		if mode == "mouse": mouse(pos,false)
		else:
			touch(pos,false)
			mouse(pos,false,InputEvent.DEVICE_ID_EMULATION)
		check(not defense.snapshot().guarding, "release " + mode)
	group("real mouse/touch and emulation order")

	await tap("ResetTrialButton","touch")
	key(KEY_G,true)
	check(defense.snapshot().guarding, "G down")
	key(KEY_F5,true)
	key(KEY_F5,false)
	defense.advance(0.81)
	check(defense.snapshot().result == "block", "F5 while G held")
	key(KEY_G,false)
	check(not defense.snapshot().guarding, "G up")
	key(KEY_F6,true)
	key(KEY_F6,false)
	check(defense.snapshot().contacts == 0, "F6 resets")
	key(KEY_G,true,true)
	check(defense.snapshot().guarding, "physical G works with non-Latin keyboard layout")
	await tap("SwingButton","mouse")
	check(defense.snapshot().phase == "windup" and defense.snapshot().guarding, "mouse starts swing while keyboard guard held")
	key(KEY_G,false,true)
	check(not defense.snapshot().guarding, "physical G release")
	await tap("ResetTrialButton","touch")
	group("keyboard hold/swing/reset")

	var guard := center("GuardButton")
	touch(guard,true,21)
	touch(guard,true,22)
	touch(guard,false,22)
	check(defense.snapshot().guarding, "second finger cannot release owner's guard")
	touch(center("SwingButton"),true,23)
	touch(center("SwingButton"),false,23)
	check(defense.snapshot().phase == "windup", "second independent action finger")
	var move_button: Button = sandbox.level.get_node("HUD").find_child("DpadRight",true,false) as Button
	# Find the actual movement pad by its scene name if the HUD renamed it.
	if move_button == null: move_button = sandbox.level.get_node("HUD").get("_dpad_right") as Button
	check(move_button != null, "existing movement control")
	if move_button != null:
		var pos := move_button.get_global_rect().get_center()
		touch(pos,true,24)
		check(player.get("_touch_move").length() > 0.5, "movement finger passes while guarding")
		var rig: Node = sandbox.level.get_node("CameraRig")
		var yaw_before: float = rig.get("_yaw")
		var look_pos := root.get_visible_rect().size * Vector2(0.64,0.54)
		touch(look_pos,true,25)
		var look_drag := InputEventScreenDrag.new()
		look_drag.index = 25
		look_drag.position = look_pos + Vector2(55,0)
		look_drag.relative = Vector2(55,0)
		root.push_input(look_drag,true)
		check(absf(float(rig.get("_yaw"))-yaw_before) > 0.1, "camera finger moves while movement and guard held")
		check(defense.snapshot().guarding and player.get("_touch_move").length() > 0.5, "look preserves other two fingers")
		touch(look_drag.position,false,25)
		touch(pos,false,24)
	touch(guard,false,21)
	check(not defense.snapshot().guarding, "owner finger released")
	group("simultaneous movement and independent touch ownership")

	await tap("ResetTrialButton","touch")
	touch(guard,true,31)
	touch(guard,true,31,true)
	check(not defense.snapshot().guarding, "canceled touch marked pressed releases")
	touch(guard,true,32)
	var drag := InputEventScreenDrag.new()
	drag.index = 32
	drag.position = Vector2(5,450)
	drag.relative = drag.position - guard
	root.push_input(drag,true)
	check(not defense.snapshot().guarding, "drag outside releases guard")
	touch(drag.position,false,32)
	touch(guard,true,34)
	drag.index = 34
	drag.position = center("SwingButton")
	root.push_input(drag,true)
	check(not defense.snapshot().guarding, "leaving guard for another owned button releases")
	touch(drag.position,false,34)
	touch(center("SwingButton"),true,35)
	drag.index = 35
	drag.position = Vector2(5,450)
	root.push_input(drag,true)
	touch(center("SwingButton"),false,35)
	check(defense.snapshot().phase == "idle", "drag outside permanently cancels action tap")
	mouse(guard,true)
	mouse(Vector2(5,450),false)
	check(not defense.snapshot().guarding, "mouse release outside releases guard")
	touch(center("SwingButton"),true,33)
	touch(Vector2(5,450),false,33)
	check(defense.snapshot().phase == "idle", "release outside cancels swing tap")
	mouse(center("SwingButton"),true)
	mouse(Vector2(5,450),false)
	mouse(center("SwingButton"),false)
	check(defense.snapshot().phase == "idle", "no stale mouse action after outside release")
	group("canceled/dragged/outside inputs")

	var ui: Node = button("GuardButton")
	while ui != null and not ui is CanvasLayer: ui = ui.get_parent()
	check(ui != null, "defense CanvasLayer")
	touch(guard,true,41)
	ui.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	defense.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not defense.snapshot().guarding, "focus clears hold")
	ui.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	touch(center("SwingButton"),true,42)
	touch(center("SwingButton"),false,42)
	check(defense.snapshot().phase == "idle", "resume alone doesn't activate UI")
	ui.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	defense.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	touch(guard,false,41)
	check(not defense.snapshot().guarding, "no old finger revived")
	var menu: Node = sandbox.level.get_node("InventoryMenu")
	touch(center("SwingButton"),true,43)
	check(menu.request_open(), "menu opens")
	await settle()
	check(not button("GuardButton").is_visible_in_tree(), "modal hides defense controls")
	check(ui.get("_pointer_buttons").is_empty(), "menu clears pending taps without active guard")
	touch(center("SwingButton"),true,44)
	check(ui.get("_pointer_buttons").is_empty(), "hidden controls don't steal menu fingers")
	key(KEY_G,true)
	key(KEY_F5,true)
	key(KEY_G,false)
	key(KEY_F5,false)
	check(not defense.snapshot().guarding and defense.snapshot().phase == "idle", "modal blocks keys")
	menu.close_menu(false)
	await settle()
	touch(center("SwingButton"),false,43)
	touch(center("SwingButton"),false,44)
	check(defense.snapshot().phase == "idle", "menu release cannot replay old taps")
	check(button("GuardButton").is_visible_in_tree(), "controls restore")
	group("focus and menu don't retain input")

	await tap("ResetTrialButton","touch")
	await tap("TrainedButton","touch")
	await tap("BackpackButton","touch")
	defense.start_swing()
	defense.advance(0.68)
	await screenshot("windup")
	touch(center("GuardButton"),true,51)
	defense.advance(0.13)
	await screenshot("block")
	touch(center("GuardButton"),false,51)
	if errors.is_empty() and groups == 6:
		print("ASHBOUND_FIST_DEFENSE_UI_OK groups=6")
		get_tree().quit(0)
	else:
		printerr("DEFENSE_UI_INCOMPLETE groups=%d errors=%d" % [groups,errors.size()])
		get_tree().quit(1)
