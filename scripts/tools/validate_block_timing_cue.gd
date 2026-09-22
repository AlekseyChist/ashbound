extends Node
## Codex independent acceptance of the displayed press window and input result.
var errors: Array[String] = []
var groups := 0
var sandbox: Node
var defense: Node
var player: Node
var toolbar: Node
var guard: Button
var pad: MeshInstance3D
var spark: Node3D
var loc: Node

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		printerr("BLOCK_CUE_FAIL: " + message)

func group(message: String) -> void:
	groups += 1
	print("BLOCK_CUE_GROUP %d %s" % [groups, message])

func settle() -> void:
	for i in 4: await get_tree().process_frame

func reset() -> void:
	toolbar._clear_all_input()
	defense.reset_trial()
	player.velocity = Vector3.ZERO
	sandbox.set_technique("trained")
	toolbar._process(0.0)

func step(dt: float) -> void:
	defense.advance(dt)
	toolbar._process(0.0)

func check_cue(expected: bool, label: String) -> void:
	check(defense.is_block_window_open() == expected, "window " + label)
	check(spark.visible == expected, "world spark " + label)
	check(guard.text == loc.text("DEFENSE_GUARD_NOW" if expected else "DEFENSE_GUARD"), "button label " + label)
	check(pad.material_override.emission_enabled == expected, "pad emission " + label)

func send_guard(mode: String, pressed: bool) -> void:
	var event: InputEvent
	if mode == "touch":
		var e := InputEventScreenTouch.new()
		e.position = guard.get_global_rect().get_center()
		e.pressed = pressed
		e.index = 17
		event = e
	elif mode == "mouse":
		var e := InputEventMouseButton.new()
		e.position = guard.get_global_rect().get_center()
		e.global_position = e.position
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		event = e
	else:
		var e := InputEventKey.new()
		e.physical_keycode = KEY_G
		e.pressed = pressed
		event = e
	get_tree().root.push_input(event, true)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var dest := ("user://" if OS.has_feature("android") else "res://.tools/") + "block-cue-" + label + ".png"
	check(get_viewport().get_texture().get_image().save_png(dest) == OK, "capture " + label)

func run() -> void:
	get_tree().root.size = Vector2i(1920,1080)
	loc = get_node("/root/Localization")
	loc.load_preferences("user://block-cue-qa.cfg", "en_US")
	sandbox = load("res://scripts/tools/fist_defense_sandbox.tscn").instantiate()
	add_child(sandbox)
	await settle()
	player = sandbox.level.get_node("Actors/Player")
	defense = sandbox.defense
	guard = sandbox.find_child("GuardButton", true, false)
	toolbar = guard.get_parent().get_parent()
	pad = defense.get("_pad_mesh")
	spark = defense.find_child("BlockWindowSpark", true, false)
	if spark == null or not defense.has_method("is_block_window_open"):
		check(false,"missing cue API or world spark")
		finish()
		return
	player.set_physics_process(false)
	defense.set_physics_process(false)
	var hud: Node = sandbox.level.get_node("HUD")
	var attack: Button = hud.get("_btn_attack")
	for name in ["SwingButton","ResetTrialButton","GuardButton"]:
		var b: Button = sandbox.find_child(name,true,false)
		for state in ["normal","hover","pressed"]:
			check(b.get_theme_stylebox(state) == attack.get_theme_stylebox(state), "shared HUD style " + name + state)
		check(b.get_theme_stylebox("disabled") == attack.get_theme_stylebox("normal"), "disabled button retains HUD frame " + name)
		check(b.get_theme_font("font") == attack.get_theme_font("font") and b.get_theme_font_size("font_size") == attack.get_theme_font_size("font_size"), "shared HUD typography " + name)
	var hint_panel: Panel = sandbox.find_child("DefenseHintPanel",true,false)
	check(hint_panel.get_theme_stylebox("panel") == hud.get_node("RootControl/TopLeftPanel").get_theme_stylebox("panel"), "shared HUD hint panel")
	for t in [0.0, .619999, .62, .620001, .799999, .8, 1.5]:
		reset()
		defense.start_swing()
		step(t)
		var open: bool = t >= .62 and t < .8
		check_cue(open, str(t))
		check(defense.snapshot().contacts == (0 if t < .8 else 1), "contact boundary " + str(t))
		if t < .8:
			defense.set_guard(true)
			step(.8-t)
			check(defense.snapshot().result == ("perfect_block" if open else "block"), "cue agrees with press " + str(t))
		else:
			defense.set_guard(true)
			check(defense.snapshot().result == "hit", "late press cannot undo contact")
	group("exact opening/contact boundaries agree with result")
	reset()
	defense.set_guard(true)
	defense.start_swing()
	step(.68)
	check_cue(true,"held signal")
	step(.12)
	check(defense.snapshot().result == "block", "early hold stays ordinary")
	step(.7)
	defense.start_swing()
	step(.8)
	check(defense.snapshot().contacts == 2 and defense.snapshot().result == "block", "hold does not refresh on another flash")
	reset()
	defense.start_swing()
	step(.4)
	defense.set_guard(true)
	defense.set_guard(false)
	step(.28)
	defense.set_guard(true)
	step(.12)
	check(defense.snapshot().result == "block", "spam refractory retained")
	reset()
	defense.start_swing()
	step(.8)
	check(defense.snapshot().result == "hit", "signal never guards automatically")
	group("holding repeated attacks and spam")
	for fps in [15,30,60,120]:
		reset()
		defense.start_swing()
		var elapsed := 0.0
		while elapsed < .68:
			var dt := minf(1.0/fps, .68-elapsed)
			step(dt)
			elapsed += dt
		check_cue(true,"fps " + str(fps))
		var before: Dictionary = defense.snapshot().duplicate(true)
		for i in 100:
			defense.is_block_window_open()
			defense._update_arm_visual()
		check(defense.snapshot() == before, "read-only presentation")
		defense.set_guard(true)
		step(3.0)
		check(defense.snapshot().contacts == 1 and defense.snapshot().result == "perfect_block", "fps and large contact step " + str(fps))
		check_cue(false,"long-step idle")
	group("simulation time and independent rendering")
	reset()
	defense.start_swing()
	var neutral: Vector3 = pad.global_position
	step(.32)
	var retracted: Vector3 = pad.global_position
	check(neutral.distance_to(retracted) > .4, "visible retraction")
	step(.30)
	check(pad.global_position.is_equal_approx(retracted), "anticipation hold until cue")
	await capture("opening")
	step(.14)
	check(pad.global_position.distance_to(retracted) > .15, "visible forward stroke before contact")
	check(defense.snapshot().contacts == 0, "stroke animation not early damage")
	await capture("forward")
	step(.04)
	check(Vector2(pad.global_position.x-player.global_position.x,pad.global_position.z-player.global_position.z).length() < .4, "pad agrees with contact")
	check_cue(false,"contact")
	check(pad.material_override.albedo_color.r > pad.material_override.albedo_color.b, "hit feedback remains red")
	await capture("contact")
	var arm: MeshInstance3D = pad.get_parent().get_node("Arm")
	check(arm.position.z + arm.mesh.size.z/2.0 <= pad.position.z + pad.mesh.size.z/2.0, "spar stays behind pad")
	group("visible anticipation stroke and contact")
	for cancellation in ["cancel","reset","focus","pause","menu","technique"]:
		reset()
		defense.start_swing()
		step(.68)
		match cancellation:
			"cancel": defense.cancel_trial()
			"reset": defense.reset_trial()
			"focus": defense.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
			"pause": get_tree().paused = true
			"menu":
				check(sandbox.level.get_node("InventoryMenu").request_open(), "real menu open")
				defense.advance(0.0)
			"technique": sandbox.set_technique("novice")
		toolbar._process(0.0)
		check_cue(false,"immediate " + cancellation)
		check(defense.snapshot().contacts == 0, "cancel suppresses contact " + cancellation)
		if cancellation == "focus": defense.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		if cancellation == "pause": get_tree().paused = false
		if cancellation == "menu": sandbox.level.get_node("InventoryMenu").close_menu(false)
		await settle()
		step(1.0)
		check_cue(false,"resumed " + cancellation)
		check(defense.snapshot().contacts == 0, "resume no replay")
	group("synchronous cleanup menu focus pause and technique")
	for language in ["en","ru"]:
		loc.set_language(language)
		for mode in ["key","mouse","touch"]:
			reset()
			var rect := guard.get_global_rect()
			check(guard.text == ("BLOCK" if language == "en" else "БЛОК"), "normal translated label")
			check(guard.get_theme_color("font_color") == attack.get_theme_color("font_color"), "font restored after cue")
			check(guard.get_theme_stylebox("normal") == attack.get_theme_stylebox("normal"), "normal style restored after cue")
			defense.start_swing()
			step(.68)
			check(guard.text == ("BLOCK!" if language == "en" else "БЛОК!"), "window translated label")
			check(guard.get_global_rect() == rect, "signal doesn't move input target")
			check(guard.get_theme_font("font").get_string_size(guard.text,HORIZONTAL_ALIGNMENT_LEFT,-1,guard.get_theme_font_size("font_size")).x < guard.size.x-10, "label fits")
			send_guard(mode,true)
			player._update_visual()
			check(String(player.get_node("Visual/Body").animation).begins_with("guard_"), "button gives visible guard pose " + mode)
			step(.12)
			check(defense.snapshot().result == "perfect_block", "actual input path " + language + mode)
			send_guard(mode,false)
		reset()
		defense.start_swing()
		step(.68)
		await capture(language)
	group("EN RU actual key mouse touch and stable button geometry")
	var rig: Node = sandbox.level.get_node("CameraRig")
	reset()
	defense.start_swing()
	step(.68)
	var fixed_position := pad.global_position
	var fixed_state: Dictionary = defense.snapshot().duplicate(true)
	for i in 4:
		rig.rotate_view(Vector2(deg_to_rad(90.0)/rig.mouse_sensitivity,0))
		await get_tree().physics_frame
		await settle()
		check_cue(true,"camera " + str(i))
		check(pad.global_position.is_equal_approx(fixed_position),"camera cannot aim weapon")
		check(defense.snapshot() == fixed_state,"camera no time mutation")
		await capture("view-" + str(i))
	group("world cue camera independence in four directions")
	finish()

func finish() -> void:
	if errors.is_empty() and groups == 7:
		print("ASHBOUND_BLOCK_CUE_OK groups=7")
		get_tree().quit(0)
	else:
		printerr("BLOCK_CUE_INCOMPLETE groups=%d errors=%d" % [groups,errors.size()])
		get_tree().quit(1)
