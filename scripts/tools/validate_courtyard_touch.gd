extends SceneTree

var fails: Array = []
var last_move: Vector2 = Vector2.ZERO
var attack_count: int = 0
var interact_count: int = 0
var restart_count: int = 0
var hud: Node = null
var up_button: Button = null
var interact_button: Button = null

func _init() -> void:
	_run.call_deferred()

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)
		push_error("COURTYARD_TOUCH FAIL: " + msg)

func _on_move_changed(v: Vector2) -> void:
	last_move = v

func _on_interact_pressed() -> void:
	interact_count += 1

func _on_attack_pressed() -> void:
	attack_count += 1

func _on_restart_pressed() -> void:
	restart_count += 1

func _touch(position: Vector2, index: int, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.position = position
	ev.index = index
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _drag(position: Vector2, index: int) -> void:
	var ev := InputEventScreenDrag.new()
	ev.position = position
	ev.index = index
	Input.parse_input_event(ev)

func _center_of(btn: Button) -> Vector2:
	return btn.get_global_rect().get_center()

func _run() -> void:
	print("PHASE: setup")
	root.size = Vector2i(1920, 1080)
	var packed: PackedScene = load("res://scenes/courtyard/courtyard_hud.tscn")
	hud = packed.instantiate()
	hud.force_touch_controls = true
	root.add_child(hud)
	await process_frame
	await process_frame

	hud.move_changed.connect(_on_move_changed)
	hud.interact_pressed.connect(_on_interact_pressed)
	hud.attack_pressed.connect(_on_attack_pressed)
	hud.restart_pressed.connect(_on_restart_pressed)
	# Isolated HUD test: also exercise real synchronous reset behavior.
	hud.restart_pressed.connect(hud.reset_controls)

	up_button = hud.get_node("RootControl/BottomLeft/DpadGrid/Up") as Button
	interact_button = hud.get_node("RootControl/BottomRight/VBox/InteractButton") as Button
	var left_button: Button = hud.get_node("RootControl/BottomLeft/DpadGrid/Left") as Button
	var right_button: Button = hud.get_node("RootControl/BottomLeft/DpadGrid/Right") as Button
	var attack_button: Button = hud.get_node("RootControl/BottomRight/VBox/AttackButton") as Button

	# TEST 1: Up press, attack press/release, up release.
	print("PHASE: test1")
	_touch(_center_of(up_button), 10, true)
	await process_frame
	_check(last_move == Vector2.UP, "test1 up move")
	_touch(_center_of(attack_button), 11, true)
	await process_frame
	_check(attack_count == 1, "test1 attack count")
	_check(last_move == Vector2.UP, "test1 move persists during attack")
	_touch(_center_of(attack_button), 11, false)
	await process_frame
	_check(last_move == Vector2.UP, "test1 move after attack release")
	_touch(_center_of(up_button), 10, false)
	await process_frame
	_check(last_move == Vector2.ZERO, "test1 zero after up release")

	# TEST 2: Left press, drag finger far away -> zero.
	print("PHASE: test2")
	_touch(_center_of(left_button), 20, true)
	await process_frame
	_check(last_move == Vector2.LEFT, "test2 left move")
	_drag(Vector2(960, 400), 20)
	await process_frame
	_check(last_move == Vector2.ZERO, "test2 zero after drag away")
	_touch(_center_of(left_button), 20, false)
	await process_frame

	# TEST 3: Interact press/release.
	print("PHASE: test3")
	var attack_before: int = attack_count
	_touch(_center_of(interact_button), 30, true)
	await process_frame
	_touch(_center_of(interact_button), 30, false)
	await process_frame
	_check(interact_count == 1, "test3 interact count")
	_check(attack_count == attack_before, "test3 attack unchanged")

	# TEST 4: Restart press/release.
	print("PHASE: test4")
	_touch(_center_of(hud.get_node("RootControl/TopRightPanel/RestartButton")), 31, true)
	await process_frame
	_touch(_center_of(hud.get_node("RootControl/TopRightPanel/RestartButton")), 31, false)
	await process_frame
	_check(restart_count == 1, "test4 restart count")

	# TEST 5: button_up while finger held -> still UP (suppression guard).
	print("PHASE: test5")
	_touch(_center_of(up_button), 40, true)
	await process_frame
	up_button.button_up.emit()
	await process_frame
	_check(last_move == Vector2.UP, "test5 suppression keeps up")
	_touch(_center_of(up_button), 40, false)
	await process_frame
	_check(last_move == Vector2.ZERO, "test5 zero after release")

	# TEST 6: focus out zeroes movement; later release stays zero.
	print("PHASE: test6")
	_touch(_center_of(right_button), 50, true)
	await process_frame
	_check(last_move == Vector2.RIGHT, "test6 right move")
	hud.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await process_frame
	_check(last_move == Vector2.ZERO, "test6 zero on focus out")
	_touch(_center_of(right_button), 50, false)
	await process_frame
	_check(last_move == Vector2.ZERO, "test6 still zero after release")

	# TEST 7: synthetic PC mouse click on Interact after suppression window.
	print("PHASE: test7 (synthetic PC mouse input, not physical device evidence)")
	var interact_before: int = interact_count
	var attack_before7: int = attack_count
	await create_timer(0.4).timeout
	var mdown := InputEventMouseButton.new()
	mdown.position = _center_of(interact_button)
	mdown.button_index = MOUSE_BUTTON_LEFT
	mdown.pressed = true
	Input.parse_input_event(mdown)
	await process_frame
	var mup := InputEventMouseButton.new()
	mup.position = _center_of(interact_button)
	mup.button_index = MOUSE_BUTTON_LEFT
	mup.pressed = false
	Input.parse_input_event(mup)
	await process_frame
	_check(interact_count == interact_before + 1, "test7 mouse interact exactly once")
	_check(attack_count == attack_before7, "test7 attack unchanged")

	hud.queue_free()
	await process_frame
	await process_frame

	if fails.is_empty():
		print("ASHBOUND_COURTYARD_TOUCH_OK")
		quit(0)
	else:
		for f in fails:
			print("FAIL: ", f)
		quit(1)
