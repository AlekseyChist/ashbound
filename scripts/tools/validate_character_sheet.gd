extends SceneTree
## Codex QA: actual hero progress, touch ownership, translated layout and worn portrait.
const BARE = preload("res://assets/characters/courtyard/traveler_frames.tres")
const PACKED = preload("res://assets/characters/courtyard/traveler_backpack_frames.tres")
var failures: Array[String] = []
var groups := 0
var level: Node
var menu: Node
var panel: Control
var sections: RefCounted
var inv: Node
var loc: Node
var progress: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, why: String) -> void:
	if not ok:
		failures.append(why)
		printerr("CHARACTER_SHEET_FAIL: " + why)

func settle(n: int = 3) -> void:
	for i in n: await physics_frame
	# Several physics ticks may precede one rendered frame; TextureRect refreshes in _process.
	await process_frame
	await process_frame

func touch(pos: Vector2, down: bool, index: int = 0, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = pos
	event.pressed = down
	event.index = index
	event.canceled = canceled
	root.push_input(event, true)

func mouse(pos: Vector2, down: bool, device: int = 0) -> void:
	var event := InputEventMouseButton.new()
	event.position = pos
	event.global_position = pos
	event.pressed = down
	event.button_index = MOUSE_BUTTON_LEFT
	event.device = device
	root.push_input(event, true)

func tab(name: String) -> Button:
	return panel.get_node("Margin/RootVBox/Header/SectionTabs/" + name)

func tap_tab(name: String, use_mouse: bool = false) -> void:
	var pos := tab(name).get_global_rect().get_center()
	if use_mouse:
		mouse(pos, true)
		mouse(pos, false)
	else:
		touch(pos, true)
		touch(pos, false)
	await settle()

func label(name: String) -> Label:
	return panel.get_node("Margin/RootVBox/CharacterPage/Details/" + name)

func snapshot() -> String:
	return JSON.stringify([inv.get_save_data(), progress.get_save_data(), level.state, level.dummy_hits])

func open_menu() -> void:
	level.get_node("HUD").clear_message()
	check(menu.request_open(), "physical access starts")
	check(menu.get_menu_state() == 1 and not panel.visible, "page waits for access animation")
	await settle(50)
	check(panel.visible and sections.current_section == "items", "open always starts with belongings")

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.tools/character-" + name + ".png") == OK, "capture " + name)

func layout(language: String) -> void:
	var bounds := panel.get_global_rect()
	check(root.get_visible_rect().grow(1).encloses(bounds), "full panel fits " + language)
	for control in [tab("ItemsTab"), tab("QuestsTab"), tab("CharacterTab"), panel.get_node("%CloseButton"), panel.get_node("%LanguageChoice")]:
		check(bounds.grow(1).encloses(control.get_global_rect()), "control fits " + control.name)
		check(control.size.y >= 90, "finger target " + control.name)
		check(control.get_theme_font("font").get_string_size(control.text, HORIZONTAL_ALIGNMENT_LEFT, -1, control.get_theme_font_size("font_size")).x < control.size.x - 12, "button text fits " + language + control.name)
	for name in ["CharacterTitle", "LearningPoints", "SkillsTitle", "Unarmed", "GuardPractice", "TeacherHint"]:
		var item := label(name)
		check(item.is_visible_in_tree() and bounds.grow(1).encloses(item.get_global_rect()), "label fits " + language + name)
		check(not item.text.is_empty() and not item.text.contains("MENU_"), "actual translated label " + name)
		check(item.size.y >= item.get_minimum_size().y, "label not vertically clipped " + name)
	check(bounds.grow(1).encloses(panel.get_node("Margin/RootVBox/CharacterPage/Portrait").get_global_rect()), "portrait fits")

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	inv = root.get_node("Inventory")
	loc = root.get_node("Localization")
	loc.load_preferences("res://.tools/character-qa-language.cfg", "en_US")
	loc.set_language("en")
	level = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	root.add_child(level)
	await settle(5)
	progress = level.get_node_or_null("Actors/Player/Progression")
	if progress == null:
		check(false, "active player owns Progression")
		quit(1)
		return
	menu = level.get_node("InventoryMenu")
	panel = menu.get_node("RootControl/Overlay/Window")
	sections = panel.get("_sections")
	check(progress.get_character_data() == {"learning_points":0,"unarmed_mastery":"novice","guard_practice_completed":false}, "fresh actual hero")
	await open_menu()
	var before := snapshot()
	var footer: Rect2 = panel.get_node("%LanguageChoice").get_global_rect()
	await tap_tab("CharacterTab")
	check(sections.current_section == "character", "native tap selects character")
	check(panel.get_node("Margin/RootVBox/CharacterPage").is_visible_in_tree(), "character visible")
	for node in ["%Body", "%Hint", "%QuickSlots", "Margin/RootVBox/QuestPage"]:
		check(not panel.get_node(node).is_visible_in_tree(), "other content hidden " + node)
	check(panel.get_node("%LanguageChoice").get_global_rect() == footer, "footer stable")
	check(label("LearningPoints").text == "Learning points: 0", "no invented initial points")
	check(snapshot() == before, "opening page read-only")
	var portrait: TextureRect = panel.get_node("Margin/RootVBox/CharacterPage/Portrait")
	check(portrait.texture == BARE.get_frame_texture("idle_front",0), "bare portrait is full existing frame")
	groups += 1
	# QA-only reward injection checks live binding. Production lesson awards no points.
	check(progress.award_learning_points("qa_character_reward",17), "grant QA points")
	check(label("LearningPoints").text == "Learning points: 17", "signal updates visible points")
	check(not progress.award_learning_points("qa_character_reward",17), "repeated reward blocked")
	var saved: Dictionary = progress.get_save_data()
	check(progress.load_save_data(JSON.parse_string(JSON.stringify(saved))), "progress JSON restore")
	check(label("LearningPoints").text == "Learning points: 17", "restore keeps actual points")
	check(progress.complete_guard_practice(), "QA practice changes sheet")
	check(label("GuardPractice").text == loc.text("MENU_CHARACTER_PRACTICE_DONE"), "live practice fact")
	check(label("Unarmed").text == loc.text("MENU_CHARACTER_UNARMED_NOVICE"), "practice cannot grant trained technique")
	progress.reset_guard_practice()
	groups += 1
	for language in ["en", "ru"]:
		before = snapshot()
		loc.set_language(language)
		await settle()
		check(sections.current_section == "character", "locale preserves section")
		check(tab("CharacterTab").text == ("Character" if language == "en" else "Персонаж"), "translated section")
		check(label("LearningPoints").text == loc.text("MENU_CHARACTER_POINTS",{"count":17}), "translated actual points")
		check(label("GuardPractice").text == loc.text("MENU_CHARACTER_PRACTICE_PENDING"), "translated practice pending")
		layout(language)
		check(snapshot() == before, "language cannot mutate gameplay")
		await capture(language)
	groups += 1
	check(inv.add_item("traveler_backpack"), "QA bag")
	for entry in inv.items:
		if entry.id == "traveler_backpack":
			check(inv.equip_storage_item({"instance_id":entry.instance_id}), "equip physical bag")
			break
	await settle()
	check(portrait.texture == PACKED.get_frame_texture("idle_front",0), "equipped portrait uses whole painted frame")
	await capture("packed")
	check(inv.unequip_storage_item("backpack","traveler_clothing_pocket"), "remove empty bag")
	await settle()
	check(portrait.texture == BARE.get_frame_texture("idle_front",0), "portrait follows removal")
	groups += 1
	await tap_tab("ItemsTab")
	var hidden_equipment: Vector2 = panel.get_node("%BackpackSlot").get_global_rect().get_center()
	var hidden_cell: Vector2 = panel.get("_cell_nodes")[0].get_global_rect().get_center()
	before = snapshot()
	await tap_tab("CharacterTab", true)
	check(sections.current_section == "character", "mouse opens character")
	var gesture: RefCounted = panel.get("_gesture_handler")
	check(gesture._hit_test(hidden_equipment).is_empty() and gesture._hit_test(hidden_cell).is_empty(), "hidden item/equipment inactive")
	touch(hidden_cell, true)
	await create_timer(0.3).timeout
	touch(hidden_equipment, false)
	check(snapshot() == before and not panel.get("_ghost").visible, "page cannot pick/drop hidden items")
	await tap_tab("QuestsTab")
	check(not panel.get_node("Margin/RootVBox/CharacterPage").is_visible_in_tree(), "journal hides character")
	await tap_tab("ItemsTab")
	var cp := tab("CharacterTab").get_global_rect().get_center()
	touch(cp,true)
	touch(cp,false,0,true)
	check(sections.current_section == "items", "canceled character tap ignored")
	mouse(cp,true,-1)
	touch(cp,true)
	mouse(cp,false,-1)
	touch(cp,false)
	check(sections.current_section == "character" and snapshot() == before, "Android mouse/touch order safe")
	groups += 1
	var max_state := {"schema_version":1,"learning_points":2147483647,"point_awards":{"qa_max":2147483647},"guard_practice_completed":true}
	check(progress.load_save_data(max_state), "max count QA")
	await settle()
	layout("ru max")
	check(label("LearningPoints").text.contains("2147483647"), "maximum count not truncated")
	check(progress.load_save_data(saved), "restore QA balance")
	menu._handle_go_back()
	check(menu.get_menu_state() == 0 and level.get_node("Actors/Player").input_enabled, "Back restores control")
	await open_menu()
	await tap_tab("CharacterTab")
	level.get_node("Actors/Player/PocketAccess").available = false
	await settle()
	check(menu.get_menu_state() == 0, "loss of physical access closes character")
	level.get_node("Actors/Player/PocketAccess").available = true
	level.reset_lesson()
	check(progress.get_character_data().learning_points == 17 and not progress.get_character_data().guard_practice_completed, "lesson reset preserves progress balance")
	groups += 1
	level.queue_free()
	await settle()
	var standalone: Control = load("res://scenes/courtyard/touch_inventory_panel.tscn").instantiate()
	root.add_child(standalone)
	await settle()
	var empty_sections: RefCounted = standalone.get("_sections")
	check(standalone.get_node("Margin/RootVBox/Header/SectionTabs/CharacterTab").disabled, "missing profile disables character")
	empty_sections.select_section("character")
	check(empty_sections.current_section == "items", "cannot select missing profile")
	for item in standalone.get_node("Margin/RootVBox/CharacterPage/Details").get_children():
		if item is Label: check(item.text.is_empty(), "missing profile shows no fake values")
	standalone.queue_free()
	await settle()
	groups += 1
	check(groups == 7, "all integration groups completed")
	if failures.is_empty(): print("ASHBOUND_CHARACTER_SHEET_OK groups=",groups)
	else: printerr("ASHBOUND_CHARACTER_SHEET_FAILED count=",failures.size())
	quit(0 if failures.is_empty() else 1)
