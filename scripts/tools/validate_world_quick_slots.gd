extends SceneTree
## Independent interaction/ownership regression for the world quick bar.
const Schema = preload("res://scripts/courtyard/courtyard_save_schema.gd")
var errors: Array[String] = []
var groups := 0
var level: Node
var inv: Node
var menu: Node
var panel: Node
var bar: Control
var player: Node
var rig: Node
var equips := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		errors.append(label)
		printerr("WORLD_QUICK_FAIL: " + label)

func settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func touch(id: int, pos: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.position = pos
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)

func drag(id: int, pos: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = id
	event.position = pos
	event.relative = relative
	root.push_input(event, true)

func mouse(pos: Vector2, pressed: bool, emulated := false) -> void:
	var event := InputEventMouseButton.new()
	event.device = InputEvent.DEVICE_ID_EMULATION if emulated else 0
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = pos
	event.pressed = pressed
	root.push_input(event, true)

func key(code: int, echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)

func find_item(id: String) -> Dictionary:
	for item in inv.items:
		if item.id == id:
			return item.duplicate(true)
	return {}

func weapon() -> String:
	var current: Variant = inv.equipped.get("weapon")
	return str(current.get("instance_id", "")) if current is Dictionary else ""

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	root.get_node("Localization").load_preferences("user://world-quick-qa-language.cfg", "en_US")
	inv = root.get_node("Inventory")
	check(inv.configure_storage([{"id":"traveler_clothing_pocket", "kind":"pocket", "capacity":6}]), "configure fixture")
	for id in ["rusty_sword", "iron_sword", "bread", "health_potion", "courtyard_sketch"]:
		check(inv.add_item(id, 3 if id == "bread" else 1), "seed " + id)
	level = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	level.get_node("HUD").force_touch_controls = true
	root.add_child(level)
	await settle()
	menu = level.get_node("InventoryMenu")
	panel = menu.get_node("RootControl/Overlay/Window")
	bar = menu.get_node_or_null("RootControl/QuickBar")
	check(bar != null, "world bar exists")
	if bar == null:
		quit(1)
		return
	player = level.get_node("Actors/Player")
	rig = level.get_node("CameraRig")
	rig.set_mouse_capture(false)
	level.get_node("Interactions/MapStand").available_on_crate = false
	inv.item_equipped.connect(func(_item, _slot): equips += 1)
	var sword := find_item("rusty_sword")
	var other := find_item("iron_sword")
	var bread := find_item("bread")
	var potion := find_item("health_potion")
	var map_item := find_item("courtyard_sketch")
	for i in 10:
		panel._quick_bindings[i] = ""
	panel._quick_bindings[0] = sword.instance_id
	panel._quick_bindings[1] = other.instance_id
	panel._quick_bindings[2] = bread.instance_id
	panel._quick_bindings[3] = potion.instance_id
	panel._quick_bindings[9] = map_item.instance_id
	panel.refresh_contents()
	await settle()
	check(bar.visible and bar.cells.size() == 10, "ten visible world slots")
	for i in 10:
		var rect: Rect2 = bar.cells[i].get_global_rect()
		check(rect.size.x >= 120 and rect.size.y >= 120, "touch size %d" % i)
		check(root.get_visible_rect().encloses(rect), "slot in viewport %d" % i)
		for path in ["HUD/RootControl/BottomLeft/DpadGrid", "HUD/RootControl/BottomRight", "HUD/RootControl/MessagePanel"]:
			check(not rect.intersects(level.get_node(path).get_global_rect()), "no HUD overlap %d %s" % [i,path])
	check(bar.cells[2].get_node("Qty").text == "3", "stack quantity visible")
	check(not panel.get_quick_slot_info(2).available and not panel.get_quick_slot_info(3).available, "unfinished effects unavailable")
	groups += 1
	var p0: Vector2 = bar.cells[0].get_global_rect().get_center()
	var p1: Vector2 = bar.cells[1].get_global_rect().get_center()
	var free := Vector2(1300, 400)
	var yaw: float = rig.rotation.y
	# Pointer positions are deliberately unrelated to desktop mouse position.
	touch(30, p0, true)
	check(weapon() == "", "touch press does not activate")
	touch(30, p0, false)
	await settle()
	check(weapon() == sword.instance_id and equips == 1, "one touch selects actual sword")
	check(menu.state == 0 and not player.is_attacking(), "selection does not open menu or attack")
	check(is_equal_approx(rig.rotation.y, yaw), "slot does not turn camera")
	check(panel.get_quick_slot_info(0).equipped, "equipped state shared")
	check(bar.cells[0].get_theme_stylebox("normal").border_color != bar.cells[1].get_theme_stylebox("normal").border_color, "selected weapon highlighted")
	mouse(p0, true, true)
	mouse(p0, false, true)
	check(equips == 1, "emulated duplicate ignored")
	# Emulated click cannot independently activate a different slot.
	mouse(p1, true, true)
	mouse(p1, false, true)
	check(weapon() == sword.instance_id, "standalone emulation never activates")
	groups += 1
	touch(31, p1, true)
	drag(31, free, free-p1)
	drag(31, p1, p1-free)
	touch(31, p1, false)
	check(weapon() == sword.instance_id, "drag away and back remains canceled")
	touch(32, p1, true)
	touch(32, p1, false, true)
	check(weapon() == sword.instance_id, "canceled touch does not activate")
	touch(33, free, true)
	drag(33, p1, p1-free)
	touch(33, p1, false)
	check(weapon() == sword.instance_id, "look finger entering bar does not activate")
	groups += 1
	touch(34, p0, true)
	touch(35, p1, true)
	touch(34, p0, false)
	touch(35, p1, false)
	check(weapon() == sword.instance_id and equips == 1, "second bar finger ignored")
	var up: Vector2 = level.get_node("HUD/RootControl/BottomLeft/DpadGrid/Up").get_global_rect().get_center()
	touch(36, up, true)
	touch(37, p1, true)
	touch(37, p1, false)
	check(player._touch_move == Vector2.UP and weapon() == other.instance_id, "movement survives action finger")
	touch(36, up, false)
	check(player._touch_move == Vector2.ZERO, "movement releases")
	groups += 1
	key(KEY_1, true)
	check(weapon() == other.instance_id, "echo ignored")
	key(KEY_1)
	check(weapon() == sword.instance_id, "physical key activates")
	var count := equips
	key(KEY_1)
	check(equips == count, "equipped slot idempotent")
	# Every key mapping, including 0, maps to the same canonical weapon.
	var saved_bindings: Array = panel._quick_bindings.duplicate()
	for i in 10:
		panel._quick_bindings[i] = other.instance_id
	panel.refresh_contents()
	for code in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6,KEY_7,KEY_8,KEY_9,KEY_0]:
		inv.equip_item({"instance_id":sword.instance_id})
		key(code)
		check(weapon() == other.instance_id, "key mapping %d" % code)
	panel._quick_bindings.assign(saved_bindings)
	panel.refresh_contents()
	# An unfinished effect must not consume anything or mutate the world.
	var before: Dictionary = inv.get_save_data()
	var old_food_template: Dictionary = inv.item_database.bread.duplicate(true)
	inv.item_database.bread["category"] = "magic"
	inv.item_database.bread["subtype"] = "scroll"
	check(not menu.request_quick(2), "magic assignment cannot grant casting")
	inv.item_database.bread = old_food_template
	for index in [2,3,4,-1,10]:
		check(not menu.request_quick(index), "unavailable slot %d" % index)
	check(inv.get_save_data() == before, "rejected actions preserve all items")
	groups += 1
	# Text fields and in-progress inventory drag own keyboard input.
	var edit := LineEdit.new()
	menu.get_node("RootControl").add_child(edit)
	edit.grab_focus()
	key(KEY_1)
	check(weapon() == other.instance_id, "text focus blocks quick key")
	edit.release_focus()
	edit.queue_free()
	panel._active_pointers[99] = true
	key(KEY_1)
	check(weapon() == other.instance_id, "drag pointer blocks quick key")
	panel._active_pointers.clear()
	player.input_enabled = false
	check(not menu.request_quick(0), "disabled actor blocks action")
	player.input_enabled = true
	player.request_attack()
	check(not menu.request_quick(0), "attack blocks equipment switch")
	await create_timer(0.8).timeout
	groups += 1
	# Native mouse requires its own press; a stray release is never an action.
	mouse(p0, false)
	check(weapon() == other.instance_id, "stray mouse release ignored")
	mouse(p0, true)
	mouse(p0, false)
	check(weapon() == sword.instance_id, "native mouse click")
	touch(40, p1, true)
	bar.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	touch(40, p1, false)
	check(weapon() == sword.instance_id, "focus loss cancels pending touch")
	touch(41, p1, true)
	check(menu.request_open(), "open menu during held quick touch")
	await settle()
	touch(41, p1, false)
	check(weapon() == sword.instance_id, "hidden bar cancels held action")
	menu.close_menu(false)
	await settle()
	groups += 1
	# Map uses existing gesture and modal UI, then restores the bar.
	check(menu.request_quick(9), "map opening accepted")
	check(menu.state == 1 and not panel.visible, "map waits for gesture")
	check(not menu.request_quick(1), "opening blocks other action")
	await create_timer(1.1).timeout
	check(menu.state == 2 and panel._sections.current_section == "map", "map reaches real map view")
	check(not bar.visible, "world bar hidden behind menu")
	menu.close_menu(false)
	await settle()
	check(bar.visible and player.input_enabled, "bar and controls restored")
	groups += 1
	var schema := Schema.new()
	var snapshot: Dictionary = schema.capture(level, inv)
	check(schema.validate(snapshot,inv), "saved bindings/equipment coherent")
	# Removing actual map prunes both bars, does not retain a phantom action.
	check(level.get_node("WorldItems").drop_item({"instance_id":map_item.instance_id}), "drop bound map")
	await settle()
	check(panel._quick_bindings[9] == "" and bar.cells[9].icon == null, "lost instance clears both bars")
	check(not menu.request_quick(9), "lost map cannot open")
	check(schema.apply(level,inv,snapshot), "restore shared snapshot")
	await settle()
	check(panel._quick_bindings[9] == map_item.instance_id and bar.cells[9].icon != null, "load restores bar without new binding storage")
	groups += 1
	if DisplayServer.get_name() != "headless":
		for language in ["en", "ru"]:
			root.get_node("Localization").set_language(language)
			await settle()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.tools/world-quick-"+language+".png")
	level.queue_free()
	await settle()
	if errors.is_empty() and groups == 9:
		print("ASHBOUND_WORLD_QUICK_SLOTS_OK groups=9")
		quit(0)
	else:
		printerr("WORLD_QUICK_FAIL: incomplete groups=%d errors=%d" % [groups, errors.size()])
		quit(1)
