extends SceneTree
## Codex QA: real root-window scaling, safe-area geometry, layout and touch routing.
var errors: Array[String] = []
var groups := 0
var scene: Node
var layout_script: GDScript
var settings_path := "res://.tools/adaptive-qa-language-%d.cfg" % OS.get_process_id()

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		printerr("ADAPTIVE_DISPLAY_FAIL: " + message)

func group(label: String) -> void:
	groups += 1
	print("ADAPTIVE_DISPLAY_GROUP %d %s" % [groups, label])

func settle(frames := 5) -> void:
	for i in frames: await process_frame

func close_rect(a: Rect2, b: Rect2, label: String) -> void:
	check(a.position.distance_to(b.position) < 1.1 and a.size.distance_to(b.size) < 1.1,
		"%s actual=%s expected=%s" % [label, a, b])

func touch_at(pos: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 23
	event.position = pos
	event.pressed = pressed
	root.push_input(event, true)

func tap(control: Control) -> void:
	var center := control.get_global_rect().get_center()
	touch_at(center, true)
	touch_at(center, false)
	await settle()

func snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png("res://.tools/adaptive-" + name + ".png") == OK, "save render evidence")

func button(name: String) -> Button:
	return scene.find_child(name, true, false) as Button

func geometry_examples() -> void:
	var logical := Rect2(0, 0, 2400, 1080)
	var physical := Rect2(0, 0, 2400, 1080)
	var examples := [
		[logical, physical, physical, logical],
		[logical, physical, Rect2(96, 0, 2304, 1080), Rect2(96, 0, 2304, 1080)],
		[logical, physical, Rect2(0, 0, 2304, 1080), Rect2(0, 0, 2304, 1080)],
		[logical, physical, Rect2(96, 24, 2208, 1008), Rect2(96, 24, 2208, 1008)],
		[Rect2(0, 0, 1920, 1080), Rect2(0, 0, 1280, 720), Rect2(40, 0, 1240, 700), Rect2(60, 0, 1860, 1050)],
		[Rect2(10, 20, 1920, 1080), Rect2(100, 200, 1280, 720), Rect2(140, 220, 1240, 700), Rect2(70, 50, 1860, 1050)],
		[logical, physical, Rect2(-200, -100, 3000, 1400), logical],
		[logical, physical, Rect2(), logical],
		[logical, physical, Rect2(4000, 0, 500, 1080), logical],
		[logical, Rect2(), physical, logical],
		[logical, Rect2(0, 0, -50, 1080), physical, logical],
		[logical, physical, Rect2(0, 0, -50, 1080), logical],
		[logical, physical, Rect2(Vector2(NAN, 0), Vector2(2400, 1080)), logical],
		[logical, Rect2(Vector2.ZERO, Vector2(INF, 1080)), physical, logical],
	]
	for i in examples.size():
		var e: Array = examples[i]
		var actual: Rect2 = layout_script.map_safe_rect(e[0], e[1], e[2])
		close_rect(actual, e[3], "safe-area example %d" % i)
	group("14 independent safe-area cases, scaling, origins, clipping and invalid data")

func run() -> void:
	check(ProjectSettings.get_setting("display/window/stretch/aspect", "keep") == "expand", "project expands instead of letterboxing")
	layout_script = load("res://scripts/courtyard/adaptive_screen_root.gd")
	if layout_script == null or not layout_script.can_instantiate():
		printerr("ADAPTIVE_DISPLAY_FAIL: layout script missing/invalid")
		quit(1)
		return
	geometry_examples()
	var loc: Node = root.get_node("Localization")
	loc.load_preferences(settings_path, "en_US")
	scene = load("res://scripts/tools/fist_technique_sandbox.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await settle()
	var level: Node = scene.level
	var player: Node = level.get_node("Actors/Player")
	player.set_physics_process(false)
	var hud: Node = level.get_node("HUD")
	var menu: Node = level.get_node("InventoryMenu")
	var panel: Control = menu.get_node("RootControl/Overlay/Window")
	var bar: Control = menu.get_node("RootControl/QuickBar")
	var inv: Node = root.get_node("Inventory")
	check(inv.add_item("courtyard_sketch"), "real carried map fixture for map section")
	var ui_roots: Array[Control] = [hud.get_node("RootControl"), menu.get_node("RootControl"), scene.find_child("FistPreviewRoot", true, false)]
	var sizes := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2340, 1080), Vector2i(2400, 1080), Vector2i(3200, 1440), Vector2i(1920, 1200), Vector2i(1600, 1200), Vector2i(3440, 1440)]
	if OS.has_feature("android"):
		sizes = [root.size] # Real phone resolution: do not attempt to resize Android's surface.
	for requested in sizes:
		if not OS.has_feature("android"): root.size = requested
		await settle()
		var visible := root.get_visible_rect()
		var transform := root.get_final_transform()
		close_rect(transform * visible, Rect2(Vector2.ZERO, Vector2(root.size)), "render fills physical window " + str(requested))
		check(absf(transform.x.length() - transform.y.length()) < 0.001, "uniform UI scale " + str(requested))
		var safe: Rect2 = layout_script.get_safe_rect(root)
		for control in ui_roots:
			close_rect(control.get_global_rect(), safe, "root follows safe area " + str(control.name))
		var targets: Array[Control] = [button("NoviceButton"), button("TrainedButton"), button("ViewButton"), menu.get_node("RootControl/OpenButton")]
		for b in hud._all_buttons():
			if b.is_visible_in_tree(): targets.append(b)
		for b in bar.cells: targets.append(b)
		for b in targets:
			check(safe.grow(1).encloses(b.get_global_rect()), "visible target inside safe area " + str(requested) + " " + str(b.name))
		for i in targets.size():
			for j in range(i + 1, targets.size()):
				check(not targets[i].get_global_rect().intersects(targets[j].get_global_rect()), "no control overlap " + str(targets[i].name) + "/" + str(targets[j].name))
		for i in range(1, bar.cells.size()):
			check(not bar.cells[i - 1].get_global_rect().intersects(bar.cells[i].get_global_rect()), "quick slots do not overlap")
		await tap(button("TrainedButton"))
		check(scene.technique == "trained", "touch follows new bounds " + str(requested))
		await tap(button("NoviceButton"))
		check(scene.technique == "novice", "touch switches back exactly once")
		print("ADAPTIVE_DISPLAY_SIZE requested=%s physical=%s logical=%s safe=%s" % [requested, root.size, visible, safe])
	group("window coverage, uniform scaling, three UI roots, controls and touch across 8 aspect/size cases")
	for language in ["en", "ru"]:
		check(loc.set_language(language) == OK, "select QA language")
		if not OS.has_feature("android"): root.size = Vector2i(2340, 1080)
		await settle()
		await snapshot("world-" + language)
		# Exercise real gesture instead of exposing UI by mutating its state.
		await tap(menu.get_node("RootControl/OpenButton"))
		for frame in 90:
			if menu.state == 2: break
			await physics_frame
		check(menu.state == 2, "inventory opens through actual gesture")
		await settle()
		var safe: Rect2 = layout_script.get_safe_rect(root)
		check(safe.grow(1).encloses(panel.get_global_rect()), "inventory bounds fit " + language)
		for section in ["items", "map", "quests", "character", "settings"]:
			panel._sections.select_section(section)
			await settle()
			check(panel._sections.current_section == section, "real section selected " + section)
			check(safe.grow(1).encloses(panel.get_global_rect()), "section fits " + language + section)
		await snapshot("settings-" + language)
		await tap(panel.find_child("CloseButton", true, false))
		check(menu.state == 0 and player.input_enabled, "close restores input " + language)
		await settle()
	group("EN/RU inventory gesture, five sections, settings and restored input")
	# Resize repeatedly; no offset accumulation and no changes to actual inventory/technique.
	var carried_before: Array = inv.items.duplicate(true)
	var equipped_before: Dictionary = inv.equipped.duplicate(true)
	for iteration in 8:
		if not OS.has_feature("android"): root.size = Vector2i(1600, 1200) if iteration % 2 == 0 else Vector2i(2400, 1080)
		await settle()
		for control in ui_roots: close_rect(control.get_global_rect(), layout_script.get_safe_rect(root), "no accumulated offsets")
	check(inv.items == carried_before and inv.equipped == equipped_before and scene.technique == "novice", "resize preserves exact carried/equipped item records and preview choice")
	group("repeated live resize preserves state without accumulated offsets")
	scene.queue_free()
	await settle()
	if FileAccess.file_exists(settings_path): DirAccess.remove_absolute(settings_path)
	check(groups == 4, "all four groups completed")
	if errors.is_empty():
		print("ASHBOUND_ADAPTIVE_DISPLAY_OK groups=4 sizes=%d" % sizes.size())
		quit(0)
	else:
		printerr("ADAPTIVE_DISPLAY_FAILED count=%d" % errors.size())
		quit(1)
