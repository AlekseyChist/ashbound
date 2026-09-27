extends SceneTree
## Codex QA: physical map ownership, real pickup, live revocation, mobile layout.
const Access = preload("res://scripts/courtyard/carried_map_access.gd")
var failures: Array[String] = []
var groups := 0
var inv: Node
var loc: Node
var level: Node
var player: Node3D
var pocket: Node
var stand: Node3D
var menu: Node
var panel: Control
var sections: RefCounted

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, why: String) -> void:
	if not ok:
		failures.append(why)
		printerr("PHYSICAL_MAP_FAIL: " + why)

func settle(n: int = 3) -> void:
	for i in n: await physics_frame
	# process_frame is emitted BEFORE node _process. A rendered catch-up frame
	# may contain all requested physics ticks, so wait for one completed process.
	await process_frame
	await process_frame

func key(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event,true)

func tap(control: Control) -> void:
	for pressed in [true,false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = control.get_global_rect().get_center()
		event.pressed = pressed
		root.push_input(event,true)

func map_tab() -> Button:
	return panel.get_node("Margin/RootVBox/Header/SectionTabs/MapTab")

func drawing() -> TextureRect:
	return panel.get_node("Margin/RootVBox/MapPage/MapDrawing")

func map_handle() -> Dictionary:
	return Access.find_carried_map(inv,pocket)

func invariant() -> String:
	return JSON.stringify([inv.get_save_data(),level.get_journal_entry(),level.reward_claimed,player.get_node("Progression").get_save_data()])

func open_menu() -> void:
	key(KEY_I)
	check(menu.get_menu_state() == 1 and not panel.visible,"physical gesture precedes menu")
	await settle(55)
	check(menu.get_menu_state() == 2 and panel.visible,"menu gesture completes")

func _run() -> void:
	root.size = Vector2i(1920,1080)
	inv = root.get_node("Inventory")
	loc = root.get_node("Localization")
	loc.load_preferences("res://.tools/physical-map-language.cfg","en_US")
	level = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	level.get_node("HUD").force_touch_controls = true
	root.add_child(level)
	await settle(5)
	player = level.get_node("Actors/Player")
	pocket = player.get_node("PocketAccess")
	stand = level.get_node("Interactions/MapStand")
	menu = level.get_node("InventoryMenu")
	panel = menu.get_node("RootControl/Overlay/Window")
	sections = panel.get("_sections")
	check(not inv.has_item("courtyard_sketch") and map_handle().is_empty(),"ordinary start has no map")
	check(stand.available_on_crate and stand.get_node("Paper").visible,"physical sheet exists on crate")
	check(not stand.try_transfer(),"remote pickup denied")
	await open_menu()
	check(map_tab().disabled,"map tab unavailable without item")
	sections.select_section("map")
	tap(map_tab())
	check(sections.current_section == "items" and not drawing().is_visible_in_tree() and drawing().texture == null,"no direct or touch bypass")
	menu.close_menu()
	groups += 1

	player.global_position = Vector3(-10.5,0.1,-2.0)
	await settle(5)
	check(level.get_interaction_target() == stand,"stand is actual nearest visible interaction")
	var quest_before: Dictionary = level.get_journal_entry()
	var reentry: Array[bool] = []
	inv.item_added.connect(func(_item): reentry.append(stand.try_transfer()),CONNECT_ONE_SHOT)
	key(KEY_E)
	await settle(3)
	check(reentry == [false],"item-added observer cannot reenter world transfer")
	check(inv.get_item_count("courtyard_sketch") == 1 and not stand.available_on_crate and not stand.get_node("Paper").visible,"real E takes exactly one physical sheet")
	check(not map_handle().is_empty(),"carried map grants access")
	check(level.get_journal_entry() == quest_before and inv.gold == 0,"pickup does not advance quest or grant money")
	check(not stand.try_transfer() and inv.get_item_count("courtyard_sketch") == 1,"same interaction cannot toggle twice")
	groups += 1

	await open_menu()
	check(not stand.try_transfer(),"open menu denies world transfer")
	for language in ["en","ru"]:
		loc.set_language(language)
		await settle()
		var before := invariant()
		tap(map_tab())
		await settle()
		check(sections.current_section == "map" and drawing().is_visible_in_tree() and drawing().texture != null,"carried map renders " + language)
		check(panel.get_node("Margin/RootVBox/MapPage/MapTitle").text == loc.text("ITEM_COURTYARD_SKETCH_NAME"),"localized map title")
		check(invariant() == before,"reading and language do not change inventory/progress")
		var bounds := panel.get_global_rect()
		check(root.get_visible_rect().grow(1).encloses(bounds),"panel fits " + language)
		for tab_name in ["ItemsTab","MapTab","QuestsTab","CharacterTab"]:
			var button: Button = panel.get_node("Margin/RootVBox/Header/SectionTabs/"+tab_name)
			check(bounds.grow(1).encloses(button.get_global_rect()) and button.size.y >= 90,"finger target fits " + tab_name)
			check(button.get_theme_font("font").get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x < button.size.x-12,"tab text fits " + language+tab_name)
		check(bounds.grow(1).encloses(drawing().get_global_rect()) and drawing().size.y >= 500,"map uses available screen")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("res://.tools/physical-map-"+language+".png") == OK,"capture " + language)
		groups += 1

	var carried_save: Dictionary = inv.get_save_data()
	check(inv.remove_item("courtyard_sketch"),"remove held map")
	check(sections.current_section == "items" and map_tab().disabled and drawing().texture == null,"revocation is immediate while page open")
	sections.select_section("map")
	check(sections.current_section == "items","stale selection cannot reopen")
	check(inv.load_save_data(bytes_to_var(var_to_bytes(carried_save))),"typed serialized snapshot restores actual item")
	check(not map_tab().disabled and sections.current_section == "items","snapshot restores access without changing page")
	tap(map_tab())
	check(sections.current_section == "map","restored carried map reopens")
	groups += 1

	# D-057: no bags. The map is readable wherever it is carried on the hero: main inventory or wallet.
	var handle := map_handle()
	check(inv.move_item_to_storage(handle,"traveler_wallet"),"move map into the wallet")
	check(not map_handle().is_empty() and not map_tab().disabled,"map carried in the wallet stays readable")
	check(inv.move_item_to_storage(handle,str(pocket.storage_id)),"return map to the main inventory")
	check(not map_handle().is_empty() and not map_tab().disabled,"main inventory grants access again")
	check(inv.configure_storage([{ "id":str(pocket.storage_id), "kind":"pocket", "capacity":6 }]),"narrow to a six-cell pocket for the full-inventory case")
	groups += 1

	tap(map_tab())
	pocket.available = false
	await settle()
	check(menu.get_menu_state() == 0 and map_handle().is_empty(),"loss of physical pocket closes menu and map access")
	pocket.available = true
	await open_menu()
	check(not map_tab().disabled,"pocket recovery")
	menu.close_menu()
	await settle(24)
	key(KEY_E)
	await settle(3)
	check(not inv.has_item("courtyard_sketch") and stand.available_on_crate and stand.get_node("Paper").visible,"real E returns sheet to crate")
	await open_menu()
	check(map_tab().disabled and drawing().texture == null,"returned map has no menu content")
	menu.close_menu()
	groups += 1

	for i in 6: check(inv.add_item("iron_sword"),"fill pocket "+str(i))
	await settle(24)
	var before := invariant()
	check(not stand.try_transfer(),"full inventory cannot take map")
	check(invariant() == before and stand.available_on_crate and stand.get_node("Paper").visible,"failed pickup preserves world sheet and inventory")
	check(inv.remove_item("iron_sword",6),"clear test items")
	check(stand.try_transfer(),"retry after capacity failure succeeds")
	groups += 1

	var counts: int = inv.get_item_count("courtyard_sketch")
	level.reset_lesson()
	check(inv.get_item_count("courtyard_sketch") == counts and not stand.available_on_crate,"lesson restart cannot clone sheet")
	await open_menu()
	tap(map_tab())
	check(inv.add_item("courtyard_sketch"),"second-copy fixture")
	check(inv.remove_item("courtyard_sketch") and not map_handle().is_empty() and sections.current_section == "map","another carried copy retains access")
	check(inv.remove_item("courtyard_sketch") and map_handle().is_empty() and sections.current_section == "items","last copy revokes access")
	groups += 1

	menu.close_menu()
	check(player.input_enabled,"control restored after map tests")
	level.queue_free()
	await settle()
	check(groups == 9,"all nine scenario groups completed (bag group removed, D-057)")
	if failures.is_empty(): print("ASHBOUND_PHYSICAL_MAP_OK groups=",groups)
	else: printerr("ASHBOUND_PHYSICAL_MAP_FAILED count=",failures.size())
	quit(0 if failures.is_empty() else 1)
