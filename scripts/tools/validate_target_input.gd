extends SceneTree
## Windowed validation of target-input rules for first_courtyard.
const SCENE_PATH := "res://scenes/courtyard/first_courtyard.tscn"

var _errors: Array[String] = []
var _root: Node
var _player: Node
var _rig: Node
var _hud: Node
var _strike_count: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("scene not found: " + SCENE_PATH)
		return
	_root = packed.instantiate()
	_hud = _root.get_node("HUD")
	_hud.force_touch_controls = true
	root.add_child(_root)
	_player = _root.get_node_or_null("Actors/Player")
	_rig = _root.get_node_or_null("CameraRig")
	if _player == null or _rig == null or _hud == null:
		_fail("missing Player/CameraRig/HUD nodes")
		return
	_player.connect("strike_requested", _on_strike_requested)
	await _frames(3)
	await _physics(3)

	var err1 := await _test_captured_touch_and_air_mouse()
	var err2 := await _test_direct_emulated_mouse_guard()
	var err3 := await _test_visible_mode_guards()
	var err4 := await _test_hud_attack_button()
	_errors.append_array(err1)
	_errors.append_array(err2)
	_errors.append_array(err3)
	_errors.append_array(err4)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.queue_free()
	await _frames(2)
	if _errors.is_empty():
		print("ASHBOUND_TARGET_INPUT_OK")
		quit(0)
	else:
		for e in _errors:
			push_error(e)
		quit(1)


func _on_strike_requested() -> void:
	_strike_count += 1


func _frames(n: int) -> void:
	var i := 0
	while i < n:
		await process_frame
		i += 1


func _physics(n: int) -> void:
	var i := 0
	while i < n:
		await physics_frame
		i += 1


func _touch(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	return ev


func _mouse(device: int, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.device = device
	return ev


func _test_captured_touch_and_air_mouse() -> Array[String]:
	var errs: Array[String] = []
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.parse_input_event(_touch(1, Vector2(1100, 400), true))
	await process_frame
	Input.parse_input_event(_touch(1, Vector2(1100, 400), false))
	await process_frame
	Input.parse_input_event(_touch(2, Vector2(500, 350), true))
	await process_frame
	Input.parse_input_event(_touch(2, Vector2(500, 350), false))
	await process_frame
	Input.parse_input_event(_touch(3, Vector2(1300, 600), true))
	await process_frame
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = Vector2(1400, 600)
	drag.relative = Vector2(100, 0)
	Input.parse_input_event(drag)
	await process_frame
	Input.parse_input_event(_touch(3, Vector2(1500, 600), false))
	await _physics(10)
	if _strike_count != 0:
		errs.append("T1: strike_count %d expected 0" % _strike_count)
	if bool(_player.get("_attack_active")):
		errs.append("T1: attack still active after air input")
	return errs


func _test_direct_emulated_mouse_guard() -> Array[String]:
	var errs: Array[String] = []
	_player._unhandled_input(_mouse(InputEvent.DEVICE_ID_EMULATION, true))
	await _physics(3)
	if bool(_player.get("_attack_active")):
		errs.append("T2: emulated mouse must not attack")
	if _strike_count != 0:
		errs.append("T2: strike_count %d expected 0" % _strike_count)
	_player._unhandled_input(_mouse(InputEvent.DEVICE_ID_MOUSE, true))
	if not bool(_player.get("_attack_active")):
		errs.append("T2: real PC mouse must start attack immediately")
	await _physics(40)
	if _strike_count != 1:
		errs.append("T2: strike_count %d expected 1" % _strike_count)
	return errs


func _test_visible_mode_guards() -> Array[String]:
	var errs: Array[String] = []
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_player._unhandled_input(_mouse(InputEvent.DEVICE_ID_MOUSE, true))
	await _physics(3)
	if bool(_player.get("_attack_active")):
		errs.append("T3: visible-mode real mouse must not attack")
	if _strike_count != 1:
		errs.append("T3: strike_count %d expected 1" % _strike_count)
	_rig._unhandled_input(_mouse(InputEvent.DEVICE_ID_EMULATION, true))
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		errs.append("T3: rig emulated mouse changed mouse mode")
	return errs


func _test_hud_attack_button() -> Array[String]:
	var errs: Array[String] = []
	var btn := _root.get_node_or_null("HUD/RootControl/BottomRight/VBox/AttackButton")
	if btn == null:
		errs.append("T4: AttackButton not found")
		return errs
	var center := (btn as Control).get_global_rect().get_center()
	Input.parse_input_event(_touch(4, center, true))
	await process_frame
	Input.parse_input_event(_touch(4, center, false))
	await _physics(40)
	if _strike_count != 2:
		errs.append("T4: strike_count %d expected 2" % _strike_count)
	return errs


func _fail(msg: String) -> void:
	push_error(msg)
	_errors.append(msg)
	quit(1)
