extends SceneTree
## Real world HUD/input and disk save, using an isolated directory. No owner data.
const DIR := "user://world-quick-save-qa"
var failures: Array[String] = []
var checks := 0
var world: Node3D
var inv: Node
var menu: Node
var panel: Control
var save: Node

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("WORLD_QUICK_SAVE_FAIL ", label)
func settle(seconds := .15) -> void:
	await create_timer(seconds, true, false, true).timeout
func touch(pos: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 14
	event.position = pos
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)
func tap(pos: Vector2) -> void:
	touch(pos, true)
	touch(pos, false)
func drag_between(a: Vector2, b: Vector2) -> void:
	touch(a, true)
	await settle(.30)
	var event := InputEventScreenDrag.new()
	event.index = 14
	event.position = b
	event.relative = b - a
	root.push_input(event, true)
	touch(b, false)
	await settle()
func cell_for(id: String) -> Control:
	for cell in panel._cell_nodes:
		if cell.get_meta("item_id", "") == id: return cell
	return null
func clear_dir() -> void:
	for name in ["slot0.sav", "slot1.sav", "slot0.sav.tmp", "slot1.sav.tmp", "expected.data"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR).path_join(name))
func open_world() -> void:
	world = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)
	await settle(.6)
	menu = world.pocket
	panel = menu.get_pocket_panel()
	save = load("res://scripts/world/world_save.gd").new()
	world.add_child(save)
	save.initialize(world, DIR)
func close_world() -> void:
	menu.close_menu(false)
	paused = false
	world.queue_free()
	await settle(.4)
func equipped() -> String:
	var item: Variant = inv.equipped.get("weapon")
	return str(item.get("instance_id", "")) if item is Dictionary else ""
func run() -> void:
	root.size = Vector2i(1920, 1080)
	inv = root.get_node("Inventory")
	if "--read" in OS.get_cmdline_user_args():
		await verify_new_process()
		return
	clear_dir()
	await open_world()
	for id in ["rusty_sword", "rusty_sword", "bread", "courtyard_sketch", "leather_armor"]:
		check(inv.add_item(id), "seed " + id)
	var swords: Array[String] = []
	var map_id := ""
	var bread_id := ""
	var armor_id := ""
	for item in inv.items:
		if item.id == "rusty_sword": swords.append(item.instance_id)
		if item.id == "courtyard_sketch": map_id = item.instance_id
		if item.id == "bread": bread_id = item.instance_id
		if item.id == "leather_armor": armor_id = item.instance_id
	await settle()
	var bar: Node = menu.get_node_or_null("RootControl/QuickBar")
	check(bar != null and bar.visible, "bar exists and is visible during world play")
	if bar == null:
		await close_world()
		quit(1)
		return
	for size in [Vector2i(1920,1080), Vector2i(2340,1080)]:
		root.size = size
		await settle()
		var controls: Array = [world.hud.get_node("RootControl/BottomLeft"), world.hud.get_node("RootControl/BottomRight"), world.hud.get_node("RootControl/JumpButton"), world.combat.toolbar._guard_btn]
		for i in 10:
			var rect: Rect2 = bar.cells[i].get_global_rect()
			check(root.get_visible_rect().encloses(rect), "slot %d inside viewport %s" % [i,size])
			for control in controls:
				check(not rect.intersects(control.get_global_rect()), "slot %d clears %s at %s" % [i,control.name,size])
	root.size = Vector2i(1920,1080)
	await settle()
	check(menu.request_open(), "open world pocket normally")
	await settle(1.4)
	check(menu.state == menu.State.OPEN and paused and not bar.visible, "open inventory pauses and hides world bar")
	for pair in [[swords[0],0],[swords[1],1],[map_id,9],[bread_id,2]]:
		await drag_between(cell_for(pair[0]).get_global_rect().get_center(), panel._quick_cells[pair[1]].get_global_rect().get_center())
		check(panel._quick_bindings[pair[1]] == pair[0], "touch assigns exact instance to %d" % pair[1])
	await settle()
	var good: Dictionary = save.capture()
	check(good.has("quick") and good.quick[0] == swords[0] and good.quick[9] == map_id, "capture stores assigned instance IDs")
	check(save.store.sequence > 1, "assignment notification autosaves while paused")
	menu.close_menu()
	await settle()
	var cam_before: Vector3 = world.camera_rig.rotation
	tap(bar.cells[0].get_global_rect().get_center())
	await settle()
	check(equipped() == swords[0] and menu.state == menu.State.CLOSED and not paused, "world touch equips without opening inventory")
	check(world.camera_rig.rotation.is_equal_approx(cam_before) and not world.player.is_attacking(), "slot touch does not rotate camera or attack")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_2
	key.pressed = true
	root.push_input(key,true)
	key = key.duplicate()
	key.pressed = false
	root.push_input(key,true)
	await settle()
	check(equipped() == swords[1], "key2 chooses other identical sword instance")
	world.player.input_enabled = false
	tap(bar.cells[0].get_global_rect().get_center())
	check(equipped() == swords[1], "disabled world input cannot activate slot")
	world.player.input_enabled = true
	touch(bar.cells[0].get_global_rect().get_center(), true)
	touch(bar.cells[0].get_global_rect().get_center(), false, true)
	check(equipped() == swords[1], "cancelled touch has no effect")
	check(bar.cells[2].disabled and not menu.request_quick(2), "food is visibly unavailable, not falsely consumed")
	tap(bar.cells[9].get_global_rect().get_center())
	await settle(1.4)
	check(menu.state == menu.State.OPEN and panel.current_section() == "map" and paused, "world map slot opens real map through pocket gesture")
	menu.close_menu()
	await settle()
	good = save.capture()
	for bad_quick in [[""], "wrong", [0,"","","","","","","","",""], ["foreign","","","","","","","","",""], [armor_id,"","","","","","","","",""]]:
		var bad := good.duplicate(true)
		bad.quick = bad_quick
		var before: Dictionary = save.capture()
		check(not save.apply(bad) and save.capture() == before, "invalid quick data refused atomically: " + str(bad_quick))
	var legacy := good.duplicate(true)
	legacy.erase("quick")
	check(save.apply(legacy) and panel._quick_bindings == ["","","","","","","","","",""], "old save without quick loads empty assignments")
	check(save.apply(good), "restore valid assignments")
	panel._quick_bindings[3] = "gone-instance"
	check(save.capture().quick[3] == "" and panel._quick_bindings[3] == "gone-instance", "capture normalizes stale ID without modifying live array")
	panel._quick_bindings[3] = ""
	check(save.flush_now(), "commit quick slots to actual disk store")
	var expected: Dictionary = save.capture()
	await close_world()
	await open_world()
	check(save.load_status == "loaded", "next world session loads disk save")
	check(save.capture().quick == expected.quick and inv.get_save_data() == expected.inventory, "all ten assignments, equipped IDs and quantities survive recreation")
	check(menu.request_open(), "reopen inventory")
	await settle(1.4)
	await drag_between(panel._quick_cells[0].get_global_rect().get_center(), panel._tab_buttons["traveler_clothing_pocket"].get_global_rect().get_center())
	check(panel._quick_bindings[0] == "" and inv.get_save_data() == expected.inventory, "touch clearing binding does not move or duplicate item")
	await settle()
	await close_world()
	await open_world()
	check(panel._quick_bindings[0] == "" and panel._quick_bindings[1] == swords[1], "cleared slot remains clear after another load")
	if "--write" in OS.get_cmdline_user_args():
		var file := FileAccess.open(DIR.path_join("expected.data"), FileAccess.WRITE)
		file.store_var(save.capture())
		file.close()
	await close_world()
	if not "--write" in OS.get_cmdline_user_args(): clear_dir()
	print("WORLD_QUICK_SAVE_CHECKS checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func verify_new_process() -> void:
	var file := FileAccess.open(DIR.path_join("expected.data"), FileAccess.READ)
	if file == null:
		printerr("WORLD_QUICK_SAVE_FAIL run with --write first")
		quit(1)
		return
	var expected: Dictionary = file.get_var()
	file.close()
	await open_world()
	var bar: Node = menu.get_node("RootControl/QuickBar")
	check(save.load_status == "loaded", "new OS process loads save")
	check(save.capture().quick == expected.quick, "new process retains exact ten IDs and cleared slot")
	check(inv.get_save_data() == expected.inventory, "new process retains inventory, quantities and equipment")
	check(bar.visible and not bar.cells[1].disabled, "restored weapon slot is visible and available")
	tap(bar.cells[1].get_global_rect().get_center())
	check(equipped() == expected.quick[1], "restored weapon remains actionable")
	tap(bar.cells[9].get_global_rect().get_center())
	await settle(1.4)
	check(panel.current_section() == "map", "restored map slot opens map")
	menu.close_menu()
	await settle()
	# Write a structurally valid envelope with invalid assignments. The previous
	# good slot must recover, rather than accepting foreign IDs or losing items.
	var bad: Dictionary = save.capture()
	bad.quick[0] = "foreign-instance"
	check(save.store.commit(bad, func(_data: Dictionary) -> bool: return true), "write corrupt quick fixture")
	save.enabled = false
	await close_world()
	await open_world()
	check(save.load_status == "recovered", "invalid assignments trigger previous-slot recovery")
	check(save.capture().quick == expected.quick and inv.get_save_data() == expected.inventory, "recovery keeps items and valid bindings")
	await close_world()
	clear_dir()
	print("WORLD_QUICK_SAVE_RESTART checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
