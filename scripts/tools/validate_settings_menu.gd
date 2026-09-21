extends "res://scripts/tools/validate_menu_journal.gd"
## Independent QA: real input, persisted preferences, isolation and mobile layout.
var settings_path := "res://.tools/settings-menu-qa-%d.cfg" % OS.get_process_id()

func choice(code: String) -> Button:
	var names := {"auto":"LanguageAuto", "en":"LanguageEnglish", "ru":"LanguageRussian"}
	return panel.get_node("Margin/RootVBox/SettingsPage").find_child(names[code], true, false)

func choose(code: String, use_mouse: bool = false) -> void:
	var p := choice(code).get_global_rect().get_center()
	if use_mouse:
		mouse(p, true)
		mouse(p, false)
	else:
		touch(p, true)
		touch(p, false)
	await settle(5)

func assert_selected(code: String) -> void:
	for id: String in ["auto", "en", "ru"]:
		check(choice(id).button_pressed == (code == id), "one selected preference: " + id)
	check(sections.current_section == "settings", "changing language preserves settings page")

func settings_layout(language: String) -> void:
	var bounds := panel.get_global_rect()
	check(root.get_visible_rect().grow(1).encloses(bounds), language + " panel fits screen")
	var previous := Rect2()
	for name: String in ["ItemsTab", "MapTab", "QuestsTab", "CharacterTab", "SettingsTab"]:
		var b := tab(name)
		var r := b.get_global_rect()
		check(bounds.grow(1).encloses(r), language + " tab fits " + name)
		check(b.size.y >= 100, "large tab height " + name)
		check(b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x < b.size.x - 12, language + " tab text fits " + name)
		if previous.size != Vector2.ZERO:
			check(not previous.intersects(r), "tabs do not overlap")
		previous = r
	check(not previous.intersects(panel.get_node("%CloseButton").get_global_rect()), "settings does not cover close")
	for code: String in ["auto", "en", "ru"]:
		var b := choice(code)
		check(bounds.grow(1).encloses(b.get_global_rect()), language + " language button fits " + code)
		check(b.size.y >= 110 and b.size.x >= 600, "large language target " + code)
		check(b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x < b.size.x - 24, "language text fits")
	check(not panel.get_node("%Body").is_visible_in_tree(), "inventory hidden in settings")
	check(not panel.get_node("%QuickSlots").is_visible_in_tree(), "quick bindings hidden in settings")
	check(not panel.get("_drop_button").is_visible_in_tree(), "drop hidden in settings")
	check(panel.get_node("Margin/RootVBox/SettingsPage").find_child("LanguageTitle", true, false).text == loc.text("SETTINGS_LANGUAGE_TITLE"), "translated settings title")
	check(choice("auto").text == loc.text("UI_LANGUAGE_AUTO") and choice("en").text == "English" and choice("ru").text == "Русский", "all language names are readable and localized")

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	inv = root.get_node("Inventory")
	loc = root.get_node("Localization")
	loc.load_preferences(settings_path, "en_US")
	check(inv.configure_storage([{"id":"traveler_clothing_pocket", "kind":"pocket", "capacity":6}]), "configure fixture")
	check(inv.add_item("bread"), "fixture bread")
	inv.add_gold(17)
	level = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	root.add_child(level)
	await settle(5)
	menu = level.get_node("InventoryMenu")
	panel = menu.get_node("RootControl/Overlay/Window")
	sections = panel.get("_sections")
	if not panel.has_node("Margin/RootVBox/Header/SectionTabs/SettingsTab"):
		check(false, "Settings tab is implemented")
		quit(1)
		return
	check(panel.find_children("*", "OptionButton", true, false).is_empty(), "active menu has no dropdown")
	await open_menu()
	var snapshot := state_snapshot()
	await tap_tab("SettingsTab")
	check(sections.current_section == "settings", "touch opens settings without map")
	assert_selected("auto")
	settings_layout("auto-en")
	groups += 1
	for code: String in ["ru", "en", "auto"]:
		await choose(code, code == "en")
		check(loc.get_preference() == code, "real input applied " + code)
		assert_selected(code)
		settings_layout(code)
		var cfg := ConfigFile.new()
		check(cfg.load(settings_path) == OK and cfg.get_value("localization", "language", "missing") == code, "selection persisted " + code)
		await capture("settings-" + code)
		check(state_snapshot() == snapshot, "language leaves game snapshot untouched")
	# auto -> en has the same effective language, so no language_changed is emitted.
	await choose("en")
	assert_selected("en")
	await choose("auto")
	assert_selected("auto")
	groups += 1
	# Native cancel, second finger and release onto another choice are not choices.
	var start := choice("ru").get_global_rect().get_center()
	var target := choice("en").get_global_rect().get_center()
	touch(start, true)
	touch(start, false, 0, true)
	await settle()
	assert_selected("auto")
	touch(start, true)
	touch(target, true, 1)
	touch(start, false)
	touch(target, false, 1)
	await settle()
	assert_selected("auto")
	touch(start, true)
	motion(target, target - start)
	touch(target, false)
	await settle()
	assert_selected("auto")
	mouse(start, true, -1)
	mouse(start, false, -1)
	await settle()
	assert_selected("auto")
	check(loc.get_preference() == "auto", "canceled inputs never changed preference")
	groups += 1
	# Failure must not falsely highlight an unsaved choice.
	loc.load_preferences("res://.tools/missing-settings-menu-%d/settings.cfg" % OS.get_process_id(), "ru_RU")
	await settle()
	await choose("en")
	check(loc.get_preference() == "auto" and loc.get_language() == "ru", "failed write preserves device preference")
	assert_selected("auto")
	check(panel.get_node("%SettingsError").is_visible_in_tree(), "write failure visible")
	check(panel.get_node("%SettingsError").text == loc.text("INV_SETTINGS_FAILURE"), "write failure translated")
	loc.load_preferences(settings_path, "en_US")
	await choose("ru")
	check(not panel.get_node("%SettingsError").visible, "successful retry clears error")
	assert_selected("ru")
	groups += 1
	menu.close_menu()
	await open_menu()
	await tap_tab("SettingsTab", true)
	assert_selected("ru")
	var reload_service: Node = load("res://scripts/core/localization.gd").new()
	reload_service.load_preferences(settings_path, "en_US")
	check(reload_service.get_preference() == "ru", "new service reads persisted choice")
	reload_service.free()
	for dimensions: Vector2i in [Vector2i(2340,1080), Vector2i(1920,1080)]:
		root.size = dimensions
		await settle(6)
		for code: String in ["en", "ru"]:
			await choose(code)
			settings_layout(code + str(dimensions))
	groups += 1
	# Return to Items: old targets still work and cannot leak through settings.
	await tap_tab("ItemsTab")
	check(panel.get("_drop_button").is_visible_in_tree(), "drop restored in items")
	var cells: Array = panel.get("_cell_nodes")
	var first: Control = cells[0]
	var second: Control = cells[1]
	var iid: String = str(first.get_meta("item_id", ""))
	check(not iid.is_empty(), "seed item still present")
	var from := first.get_global_rect().get_center()
	var to := second.get_global_rect().get_center()
	mouse(from,true)
	var mm := InputEventMouseMotion.new()
	mm.position = to
	mm.relative = to-from
	mm.device = 0
	root.push_input(mm,true)
	mouse(to,false)
	await settle(5)
	var new_cells: Array = panel.get("_cell_nodes")
	check(str(new_cells[1].get_meta("item_id", "")) == iid, "item drag still works after settings")
	await tap_tab("SettingsTab")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc,true)
	await settle(5)
	check(not panel.visible and menu.get_menu_state() == 0, "Escape closes settings through menu lifecycle")
	groups += 1
	level.queue_free()
	await settle()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	if failures.is_empty() and groups == 6:
		print("ASHBOUND_SETTINGS_MENU_OK groups=6")
		quit(0)
	else:
		printerr("ASHBOUND_SETTINGS_MENU_FAILED groups=%d failures=%d" % [groups, failures.size()])
		quit(1)
