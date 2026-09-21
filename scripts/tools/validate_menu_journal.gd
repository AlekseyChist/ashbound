extends SceneTree
## Codex QA: live quest data, real input, isolation from inventory and modal lifecycle.
const OBJECTIVES := ["MEET_HOST", "FETCH_WOOD", "RETURN_WOOD", "MEET_GUARD", "PRACTICE", "REPORT", "DONE"]
var failures: Array[String] = []
var groups := 0
var level: Node
var menu: Node
var panel: Control
var sections: RefCounted
var inv: Node
var loc: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, why: String) -> void:
	if not ok:
		failures.append(why)
		printerr("MENU_JOURNAL_FAIL: " + why)

func settle(n: int = 3) -> void:
	for i in n:
		await physics_frame

func touch(pos: Vector2, down: bool, index: int = 0, canceled: bool = false) -> void:
	var e := InputEventScreenTouch.new()
	e.position = pos
	e.index = index
	e.pressed = down
	e.canceled = canceled
	root.push_input(e, true)

func motion(pos: Vector2, delta: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.position = pos
	e.relative = delta
	e.index = 0
	root.push_input(e, true)

func mouse(pos: Vector2, down: bool, device: int = 0) -> void:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.global_position = pos
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.device = device
	root.push_input(e, true)

func tab(name: String) -> Button:
	return panel.get_node("Margin/RootVBox/Header/SectionTabs/" + name)

func tap_tab(name: String, use_mouse: bool = false) -> void:
	var p := tab(name).get_global_rect().get_center()
	if use_mouse:
		mouse(p, true)
		mouse(p, false)
	else:
		touch(p, true)
		touch(p, false)
	await settle()

func quest_label(name: String) -> Label:
	return panel.get_node("Margin/RootVBox/QuestPage/" + name)

func state_snapshot() -> String:
	return JSON.stringify([inv.get_save_data(), level.state, level.dummy_hits, level.reward_claimed])

func open_menu() -> void:
	level.get_node("HUD").clear_message()
	check(menu.request_open(), "menu starts through physical access")
	check(menu.get_menu_state() == 1 and not panel.visible, "content hidden until gesture ends")
	await settle(50)
	check(menu.get_menu_state() == 2 and panel.visible, "gesture opens menu")
	check(sections.current_section == "items", "reopen begins with belongings")

func assert_entry(stage: int) -> void:
	var before := state_snapshot()
	var character: Dictionary = level.get_node("Actors/Player/Progression").get_character_data()
	check(character.guard_practice_completed == (stage == 6), "character practice only after real report")
	check(character.learning_points == 0 and character.unarmed_mastery == "novice", "lesson does not grant points or trained technique")
	var entry: Dictionary = level.get_journal_entry()
	check(entry.get("id") == "courtyard_lesson", "stable journal ID")
	check(entry.get("objective_key") == "COURTYARD_OBJECTIVE_" + OBJECTIVES[stage], "actual stage %d" % stage)
	check(entry.get("completed") == (stage == 6), "completion only after report")
	var params: Dictionary = {"hits": level.dummy_hits, "total": 3} if stage == 4 else {}
	check(entry.get("params") == params, "practice counts from level")
	check(quest_label("QuestObjective").text == loc.text("COURTYARD_OBJECTIVE_" + OBJECTIVES[stage], params), "live displayed objective")
	check(quest_label("QuestStatus").text == loc.text("MENU_QUEST_COMPLETED" if stage == 6 else "MENU_QUEST_ACTIVE"), "displayed completion")
	entry["completed"] = not bool(entry["completed"])
	entry["params"]["hits"] = 999
	sections.refresh()
	check(state_snapshot() == before, "reading/local refresh cannot mutate progression or items")
	check(level.get_journal_entry().params == params, "snapshot nested data isolated")

func layout(language: String) -> void:
	var bounds := panel.get_global_rect()
	check(root.get_visible_rect().grow(1).encloses(bounds), language + " panel fits viewport")
	for b in [tab("ItemsTab"), tab("QuestsTab"), tab("CharacterTab"), panel.get_node("%CloseButton"), tab("SettingsTab")]:
		check(bounds.grow(1).encloses(b.get_global_rect()), language + " control fits " + b.name)
		check(b.size.y >= 90, "finger height " + b.name)
		check(b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x < b.size.x - 12, language + " text fits " + b.name)
	for name in ["QuestTitle", "QuestStatus", "QuestObjective"]:
		var label := quest_label(name)
		check(bounds.grow(1).encloses(label.get_global_rect()), language + " journal fits " + name)
	check(not panel.get_node("%Title").is_visible_in_tree(), "old title does not consume header space")

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.tools/journal-" + name + ".png") == OK, "capture " + name)

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	inv = root.get_node("Inventory")
	loc = root.get_node("Localization")
	loc.load_preferences("res://.tools/journal-qa-language.cfg", "en_US")
	loc.set_language("en")
	level = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	root.add_child(level)
	await settle(5)
	menu = level.get_node("InventoryMenu")
	panel = menu.get_node("RootControl/Overlay/Window")
	sections = panel.get("_sections")
	if sections == null or not level.has_method("get_journal_entry"):
		check(false, "journal implementation present")
		quit(1)
		return
	await open_menu()
	var settings_rect: Rect2 = tab("SettingsTab").get_global_rect()
	await tap_tab("QuestsTab")
	check(sections.current_section == "quests", "native touch opens quests")
	check(tab("SettingsTab").get_global_rect() == settings_rect, "settings tab stays in place across sections")
	assert_entry(0)
	check(not panel.get_node("%Body").is_visible_in_tree() and not panel.get_node("%QuickSlots").is_visible_in_tree(), "inventory hidden in journal")
	check(not panel.get_node("%Hint").is_visible_in_tree(), "no drag hint in journal")
	groups += 1
	# Exercise the real local quest handlers, including live update while page remains open.
	level._on_innkeeper_interact()
	assert_entry(1)
	level._on_woodpile_interact()
	assert_entry(2)
	level._on_innkeeper_interact()
	assert_entry(3)
	level._on_watchman_interact()
	assert_entry(4)
	menu.close_menu()
	level.get_node("HUD").clear_message()
	var player: Node3D = level.get_node("Actors/Player")
	player.global_position = Vector3(5.7, 0.1, 3.0)
	player.facing_direction = Vector3.RIGHT
	await settle()
	level._on_strike_requested()
	check(level.dummy_hits == 1, "real eligible strike for partial journal progress")
	await open_menu()
	await tap_tab("QuestsTab", true)
	check(sections.current_section == "quests", "real mouse opens quests")
	assert_entry(4)
	groups += 1
	for language in ["en", "ru"]:
		var before := state_snapshot()
		loc.set_language(language)
		await settle()
		check(sections.current_section == "quests", "language preserves selected section")
		check(tab("ItemsTab").text == ("Items" if language == "en" else "Вещи"), "items translation")
		check(tab("QuestsTab").text == ("Quests" if language == "en" else "Задания"), "quests translation")
		assert_entry(4)
		layout(language)
		check(state_snapshot() == before, "translation is read-only")
		await capture(language)
	groups += 1
	menu.close_menu()
	level._on_strike_requested()
	level._on_strike_requested()
	await open_menu()
	await tap_tab("QuestsTab")
	assert_entry(5)
	level._on_watchman_interact()
	assert_entry(6)
	await capture("completed")
	groups += 1
	# Hidden controls must not respond using their last inventory screen rectangles.
	await tap_tab("ItemsTab")
	check(inv.add_item("bread", 1), "fixture bread")
	await settle()
	var cell: Control = panel.get("_cell_nodes")[0]
	var hidden_cell := cell.get_global_rect().get_center()
	var hidden_equipment: Vector2 = panel.get_node("%BackpackSlot").get_global_rect().get_center()
	var before := state_snapshot()
	await tap_tab("QuestsTab")
	var gesture: RefCounted = panel.get("_gesture_handler")
	check(gesture._hit_test(hidden_cell).is_empty(), "hidden item cannot be picked up")
	check(gesture._hit_test(hidden_equipment).is_empty(), "hidden equipment cannot be changed")
	touch(hidden_cell, true)
	await create_timer(0.3).timeout
	motion(hidden_cell + Vector2(30, 0), Vector2(30, 0))
	touch(hidden_equipment, false)
	check(state_snapshot() == before and not panel.get("_ghost").visible, "journal touches cannot mutate inventory")
	groups += 1
	# A canceled tab press or second finger is never a section change or item drop.
	await tap_tab("ItemsTab")
	var qp := tab("QuestsTab").get_global_rect().get_center()
	touch(qp, true)
	touch(qp, false, 0, true)
	check(sections.current_section == "items", "canceled tab tap ignored")
	touch(hidden_cell, true)
	await create_timer(0.3).timeout
	motion(hidden_cell + Vector2(20, 0), Vector2(20, 0))
	check(panel.get("_ghost").visible, "real item drag began")
	touch(qp, true, 1)
	touch(qp, false, 1)
	touch(qp, false)
	check(sections.current_section == "items" and not panel.get("_ghost").visible and state_snapshot() == before, "second finger cancels drag without switching or losing item")
	# Android delivers emulated mouse before native touch; tabs must use native ownership.
	mouse(qp, true, -1)
	touch(qp, true)
	mouse(qp, false, -1)
	touch(qp, false)
	check(sections.current_section == "quests", "emulated mouse/native touch sequence")
	groups += 1
	# Modal Back returns control, reopening resets section, access loss still owns closure.
	menu._handle_go_back()
	check(menu.get_menu_state() == 0 and player.input_enabled, "Back from journal restores game")
	await open_menu()
	await tap_tab("QuestsTab")
	player.get_node("PocketAccess").available = false
	await settle()
	check(menu.get_menu_state() == 0 and player.input_enabled, "access loss closes journal")
	player.get_node("PocketAccess").available = true
	level.reset_lesson()
	await open_menu()
	await tap_tab("QuestsTab")
	assert_entry(0)
	menu.close_menu()
	groups += 1
	level.queue_free()
	await settle()
	check(groups == 7, "all scenario groups completed")
	if failures.is_empty():
		print("ASHBOUND_MENU_JOURNAL_OK groups=", groups)
	else:
		printerr("ASHBOUND_MENU_JOURNAL_FAILED count=", failures.size())
	quit(0 if failures.is_empty() else 1)
