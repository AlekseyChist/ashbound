extends SceneTree
## Regression for the owner report: accepting firewood must not block belongings/journal.
var failures: Array[String] = []
var completed := 0
var level: Node
var player: Node3D
var hud: Node
var menu: Node
var panel: Control
var message: Control
var opened := 0
var strikes := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, why: String) -> void:
	if not ok:
		failures.append(why)
		printerr("QUEST_MENU_ACCESS_FAIL: " + why)

func settle(n: int = 3) -> void:
	for i in n: await physics_frame
	await process_frame

func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event,true)

func mouse(pos: Vector2, down: bool, device: int = 0) -> void:
	var event := InputEventMouseButton.new()
	event.position = pos
	event.global_position = pos
	event.pressed = down
	event.button_index = MOUSE_BUTTON_LEFT
	event.device = device
	root.push_input(event,true)

func touch(pos: Vector2, down: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = pos
	event.pressed = down
	event.canceled = canceled
	event.index = 0
	root.push_input(event,true)

func tap(pos: Vector2, mode: String) -> void:
	for down in [true,false]:
		if mode == "mouse": mouse(pos,down)
		elif mode == "paired":
			mouse(pos,down,InputEvent.DEVICE_ID_EMULATION)
			touch(pos,down)
		else: touch(pos,down)

func accept_firewood(mode: String) -> void:
	level.reset_lesson()
	player.global_position = Vector3(-6,0.1,-2)
	player.facing_direction = Vector3.FORWARD
	await settle(5)
	check(level.get_interaction_target() == level.get_node("Actors/Innkeeper"), "actual innkeeper target")
	if mode in ["touch","paired"]:
		tap(hud.get_node("RootControl/BottomRight/VBox/InteractButton").get_global_rect().get_center(),mode)
	else: key(KEY_E)
	await settle()
	check(level.state == 1 and message.visible, "real interaction accepts wood and leaves reply visible")

func snapshot() -> String:
	return JSON.stringify([root.get_node("Inventory").get_save_data(),level.get_journal_entry(),player.get_node("Progression").get_save_data(),level.reward_claimed])

func request_by_input(mode: String) -> void:
	if mode == "i": key(KEY_I)
	elif mode == "tab": key(KEY_TAB)
	else: tap(menu.get_node("RootControl/OpenButton").get_global_rect().get_center(),mode)

func _run() -> void:
	root.size = Vector2i(1920,1080)
	var loc: Node = root.get_node("Localization")
	loc.load_preferences("res://.tools/quest-menu-access-language.cfg","en_US")
	level = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	level.get_node("HUD").force_touch_controls = true
	root.add_child(level)
	await settle(5)
	player = level.get_node("Actors/Player")
	hud = level.get_node("HUD")
	menu = level.get_node("InventoryMenu")
	panel = menu.get_node("RootControl/Overlay/Window")
	message = hud.get_node("RootControl/MessagePanel")
	menu.opened.connect(func(): opened += 1)
	player.strike_requested.connect(func(): strikes += 1)
	for language in ["en","ru"]:
		loc.set_language(language)
		for mode in ["i","tab","mouse","touch","paired"]:
			await accept_firewood(mode)
			var before := snapshot()
			var count := opened
			var hits := strikes
			request_by_input(mode)
			check(menu.get_menu_state() == 1 and not panel.visible, "one command begins gesture after reply " + language + "/" + mode)
			check(not message.visible, "successful open dismisses informational reply")
			await settle(55)
			check(menu.get_menu_state() == 2 and panel.visible and opened == count+1, "opens once after gesture " + language + "/" + mode)
			if panel.visible:
				var quests: Control = panel.get_node("Margin/RootVBox/Header/SectionTabs/QuestsTab")
				tap(quests.get_global_rect().get_center(),"touch")
				await settle()
				check(panel.get("_sections").current_section == "quests", "journal reachable immediately")
				check(panel.get_node("Margin/RootVBox/QuestPage/QuestObjective").text == loc.text("COURTYARD_OBJECTIVE_FETCH_WOOD"), "accepted objective visible")
				if mode == "touch" and DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					check(root.get_texture().get_image().save_png("res://.tools/quest-menu-" + language + ".png") == OK, "journal capture " + language)
				var items: Control = panel.get_node("Margin/RootVBox/Header/SectionTabs/ItemsTab")
				tap(items.get_global_rect().get_center(),"touch")
				await settle()
				check(panel.get_node("%Body").is_visible_in_tree(), "belongings reachable too")
			check(snapshot() == before and strikes == hits, "menu cannot replay quest/reward or attack")
			key(KEY_ESCAPE)
			check(menu.get_menu_state() == 0 and player.input_enabled and hud.is_processing_input(), "close restores control")
			check(not message.visible, "dismissed reply does not reappear on close")
			completed += 1
	# A refused opening must retain the unread reply and every existing gameplay lock.
	await accept_firewood("i")
	var before := snapshot()
	player.input_enabled = false
	check(not menu.request_open() and message.visible and not player.input_enabled, "external lock preserves reply")
	player.input_enabled = true
	var access: Node = player.get_node("PocketAccess")
	access.available = false
	check(not menu.request_open() and message.visible, "no pocket preserves reply")
	access.available = true
	player.request_attack()
	check(not menu.request_open() and message.visible, "active attack preserves reply")
	await settle(55)
	var pocket: AnimatedSprite3D = player.get_node("Visual/PocketPose")
	var frames := pocket.sprite_frames
	pocket.sprite_frames = SpriteFrames.new()
	check(not menu.request_open() and message.visible and player.input_enabled, "failed gesture rolls back without erasing reply")
	pocket.sprite_frames = frames
	check(snapshot() == before, "rejected attempts leave quest/progress/items intact")
	completed += 1
	var open_pos: Vector2 = menu.get_node("RootControl/OpenButton").get_global_rect().get_center()
	touch(open_pos,true)
	touch(open_pos,false,true)
	check(menu.get_menu_state() == 0 and message.visible, "canceled touch does not consume reply")
	request_by_input("touch")
	await settle(55)
	check(menu.get_menu_state() == 2 and not message.visible, "recovery after rejected/canceled requests")
	access.available = false
	await settle()
	check(menu.get_menu_state() == 0 and player.input_enabled and not message.visible, "lost access after success closes safely")
	access.available = true
	completed += 1
	level.queue_free()
	await settle()
	check(completed == 12, "all twelve scenarios completed")
	if failures.is_empty(): print("ASHBOUND_QUEST_MENU_ACCESS_OK scenarios=",completed)
	else: printerr("ASHBOUND_QUEST_MENU_ACCESS_FAILED count=",failures.size())
	quit(0 if failures.is_empty() else 1)
