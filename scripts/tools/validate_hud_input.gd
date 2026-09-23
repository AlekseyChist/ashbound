extends "res://scripts/tools/validate_combat_ui.gd"
## Codex requirement-based HUD QA. Actual viewport events in the combat scene.
var hud: Node
var attacks := 0
var interactions := 0
var runs := 0
var move := Vector2.ZERO

func hp(name_: String) -> Vector2:
	return (hud.find_child(name_, true, false) as Control).get_global_rect().get_center()

func clean() -> void:
	hud.reset_controls()
	session.reset_trial()
	attacks = 0
	interactions = 0
	runs = 0
	await settle()

func hud_wake() -> void:
	hud.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	hud.notification(NOTIFICATION_WM_WINDOW_FOCUS_IN)
	hud.notification(NOTIFICATION_APPLICATION_RESUMED)
	await wake()

func run() -> void:
	get_node("/root/Localization").load_preferences("user://hud-input-qa-language.cfg", "ru_RU")
	sandbox = load("res://scripts/tools/combat_dodge_sandbox.tscn").instantiate()
	sandbox.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(sandbox)
	await settle()
	session = sandbox.defense
	player = sandbox.level.get_node("Actors/Player")
	hud = sandbox.level.get_node("HUD")
	tools_bar = sandbox._toolbar
	defense_bar = sandbox.find_child("DodgeButton", true, false).get_parent().get_parent()
	cam = sandbox.level.get_node("CameraRig")
	session.set_physics_process(false)
	player.set_physics_process(false)
	hud.move_changed.connect(func(v: Vector2): move = v)
	hud.attack_pressed.connect(func(): attacks += 1)
	hud.interact_pressed.connect(func(): interactions += 1)
	hud.run_changed.connect(func(_enabled: bool): runs += 1)
	await hud_wake()
	await clean()

	for name_ in ["Up", "AttackButton", "RunButton", "InteractButton"]:
		touch(hp(name_), true, 51, true)
		touch(hp(name_), false, 51)
	check(move == Vector2.ZERO and attacks == 0 and runs == 0 and interactions == 0,
		"canceled DOWN cannot move/attack/run/interact")
	await clean()
	touch(hp("Up"), true, 51)
	check(move == Vector2(0,-1), "fresh move works")
	touch(hp("Up"), false, 51, true)
	check(move == Vector2.ZERO and not hud._dpad_up.button_pressed, "canceled UP clears move")
	group("canceled touch and valid release")

	await clean()
	for name_ in ["Up", "AttackButton", "RunButton", "InteractButton"]:
		var b: Button = hud.find_child(name_, true, false)
		b.disabled = true
		touch(hp(name_), true, 52)
		touch(hp(name_), false, 52)
		b.disabled = false
	check(move == Vector2.ZERO and attacks == 0 and runs == 0 and interactions == 0,
		"disabled controls cannot issue gameplay requests")
	var attack_pos := hp("AttackButton")
	hud._btn_attack.hide()
	touch(attack_pos, true, 52)
	touch(attack_pos, false, 52)
	check(attacks == 0, "hidden attack cannot issue request")
	hud._btn_attack.show()
	group("unavailable controls")

	await clean()
	touch(hp("Up"), true, 53)
	touch(hp("AttackButton"), true, 53)
	check(attacks == 0, "one pointer cannot start second action")
	touch(hp("Up"), false, 53)
	check(move == Vector2.ZERO and not hud._attack_held, "duplicate DOWN leaves no stuck attack")
	await clean()
	touch(hp("RunButton"), true, 54)
	touch(hp("AttackButton"), true, 54)
	check(attacks == 0, "run owner cannot also attack")
	touch(hp("RunButton"), false, 54)
	check(hud._run_enabled and hud._btn_run.button_pressed, "run stays selected after UP")
	group("pointer ownership and selected run")

	await clean()
	touch(hp("Up"), true, 0)
	touch(hp("AttackButton"), true, 55)
	mouse(hp("Up"), false, InputEvent.DEVICE_ID_EMULATION)
	touch(hp("AttackButton"), false, 55)
	check(move == Vector2(0,-1) and attacks == 1, "attack finger/emulation does not release move")
	touch(hp("Up"), false, 0)
	check(move == Vector2.ZERO, "move finger releases")
	group("multitouch and emulated mouse")

	for what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		await clean()
		touch(hp("Up"), true, 56)
		hud.notification(what)
		check(move == Vector2.ZERO and not hud._dpad_up.button_pressed, "focus/pause clears move " + str(what))
		touch(hp("AttackButton"), true, 57)
		check(attacks == 0, "inactive HUD rejects new input " + str(what))
		await hud_wake()
		touch(hp("Up"), false, 56)
		touch(hp("AttackButton"), false, 57)
		touch(hp("Up"), true, 58)
		check(move == Vector2(0,-1), "fresh input resumes " + str(what))
		touch(hp("Up"), false, 58)
	await clean()
	touch(hp("Up"), true, 56)
	get_tree().paused = true
	await get_tree().process_frame
	check(move == Vector2.ZERO and not hud._dpad_up.button_pressed, "tree pause clears held move")
	get_tree().paused = false
	await hud_wake()
	touch(hp("Up"), false, 56)
	await clean()
	hud.notification(NOTIFICATION_APPLICATION_PAUSED)
	hud.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	hud.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	touch(hp("AttackButton"), true, 57)
	touch(hp("AttackButton"), false, 57)
	check(attacks == 0, "focus IN cannot clear application pause")
	await hud_wake()
	group("focus and pause reset")

	await clean()
	touch(hp("Up"), true, 59)
	var menu: Node = sandbox.level.get_node("InventoryMenu")
	check(menu.request_open(), "menu opens from movement")
	await settle()
	check(move == Vector2.ZERO and not hud.visible, "opening menu clears and hides HUD")
	touch(hp("AttackButton"), true, 60)
	touch(hp("AttackButton"), false, 60)
	check(attacks == 0, "menu shields hidden attack")
	menu.close_menu(false)
	await settle()
	await hud_wake()
	touch(hp("Up"), false, 59)
	check(move == Vector2.ZERO, "stale release after menu is safe")
	touch(hp("Up"), true, 61)
	check(move == Vector2(0,-1), "HUD returns after menu")
	touch(hp("Up"), false, 61)
	group("menu handoff and return")

	await clean()
	await get_tree().create_timer(.4).timeout
	mouse(hp("RunButton"), true)
	mouse(hp("RunButton"), false)
	await settle()
	check(hud._run_enabled and hud._btn_run.button_pressed, "mouse run remains visibly selected")
	mouse(hp("RunButton"), true)
	mouse(hp("RunButton"), false)
	await settle()
	check(not hud._run_enabled and not hud._btn_run.button_pressed, "second mouse press returns walking")
	mouse(hp("AttackButton"), true, 0, true)
	mouse(hp("AttackButton"), false)
	check(attacks == 0, "canceled mouse DOWN cannot attack")
	mouse(hp("Up"), true)
	check(move == Vector2(0,-1) and hud._dpad_up.button_pressed, "real mouse holds movement with feedback")
	mouse_motion(Vector2(640,400))
	check(move == Vector2.ZERO, "mouse leaving pad stops movement")
	mouse(Vector2(640,400), false)
	mouse(hp("AttackButton"), true)
	check(attacks == 1 and hud._btn_attack.button_pressed, "real mouse attack once with feedback")
	mouse(Vector2(640,400), false)
	check(not hud._btn_attack.button_pressed, "outside mouse release clears attack")
	group("real mouse and persistent run state")

	await clean()
	var loc: Node = get_node("/root/Localization")
	for language in ["ru", "en"]:
		loc.set_language(language)
		await settle()
		touch(hp("RunButton"), true, 62)
		touch(hp("RunButton"), false, 62)
		check(hud._btn_run.text == loc.text("UI_ACTION_RUN"), "running caption " + language)
		check(hud._btn_attack.text == loc.text("UI_ACTION_ATTACK"), "attack caption " + language)
		await capture("hud-" + language + "-running")
		touch(hp("RunButton"), true, 62)
		touch(hp("RunButton"), false, 62)
		check(hud._btn_run.text == loc.text("UI_ACTION_WALK"), "walking caption " + language)
	await capture("hud-idle")
	group("localized ordinary HUD states")
	hud.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	sandbox.queue_free()
	await settle()
	group("scene teardown after focus loss")
	if groups != 9: errors.append("HUD_INPUT_INCOMPLETE groups=" + str(groups))
	if errors.is_empty(): print("ASHBOUND_HUD_INPUT_OK groups=9")
	else: printerr("HUD_INPUT_FAILED ", errors)
	get_tree().quit(0 if errors.is_empty() else 1)
