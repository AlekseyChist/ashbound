extends SceneTree

var _errors: PackedStringArray = []
var _strikes: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var scene: Node = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	var hud: Node = scene.get_node("HUD")
	hud.force_touch_controls = true
	root.add_child(scene)
	await _frames(5)
	var player: Node = scene.get_node("Actors/Player")
	var rig: Node = scene.get_node("CameraRig")
	var run_btn: Control = scene.get_node("HUD/RootControl/BottomRight/VBox/RunButton")
	var atk_btn: Control = scene.get_node("HUD/RootControl/BottomRight/VBox/AttackButton")
	var right_btn: Control = scene.get_node("HUD/RootControl/BottomLeft/DpadGrid/Right")
	var run_center := run_btn.get_global_rect().get_center()
	var atk_center := atk_btn.get_global_rect().get_center()
	var right_center := right_btn.get_global_rect().get_center()
	_setup(player, rig)

	# --- 1. RunButton press/release/tap ---
	touch(1, run_center, true)
	await _frames(2)
	if not player._touch_run:
		_errors.append("run press: _touch_run false")
	if str(run_btn.text) != "Бег":
		_errors.append("run press: text not Бег")
	var yaw0: float = rig.rotation.y
	drag(1, run_center + Vector2(40, 0), Vector2(40, 0))
	await _frames(2)
	if is_equal_approx(rig.rotation.y, yaw0):
		_errors.append("run drag rotated camera")
	touch(1, run_center, false)
	await _frames(2)
	if not player._touch_run:
		_errors.append("run release lost mode")
	touch(1, run_center, true)
	await _frames(1)
	touch(1, run_center, false)
	await _frames(2)
	if player._touch_run:
		_errors.append("second tap did not toggle off")
	if str(run_btn.text) != "Ходьба":
		_errors.append("second tap text not Ходьба")

	# --- 2. Right hold + run tap, speed, release ---
	touch(10, right_center, true)
	await _frames(5)
	touch(11, run_center, true)
	await _frames(1)
	touch(11, run_center, false)
	await _frames(25)
	if player._touch_move != Vector2.RIGHT:
		_errors.append("move not RIGHT")
	if not player.is_running():
		_errors.append("not running after 25 frames")
	var vel: Vector3 = player.velocity
	if absf(vel.x - 6.4) > 0.15:
		_errors.append("speed %f not ~6.4" % vel.x)
	touch(10, right_center, false)
	await _frames(25)
	if player._touch_move != Vector2.ZERO:
		_errors.append("move not ZERO after release")
	if player.is_running():
		_errors.append("still running after release")
	if not hud._run_enabled:
		_errors.append("_run_enabled lost after release")

	# --- 3. mouse emulation on run button must not re-toggle or attack ---
	var mb := InputEventMouseButton.new()
	mb.device = Input.DEVICE_ID_EMULATION
	mb.position = run_center
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	root.push_input(mb, true)
	await _frames(1)
	mb.pressed = false
	root.push_input(mb, true)
	await _frames(2)
	if hud._run_enabled:
		_errors.append("mouse click toggled run")
	if player._attack_active:
		_errors.append("mouse click started attack")

	# --- 4. move finger + free look + attack ---
	touch(10, right_center, true)
	await _frames(2)
	var free_pos := Vector2(1100, 400)
	touch(12, free_pos, true)
	await _frames(1)
	drag(12, free_pos + Vector2(70, 0), Vector2(70, 0))
	await _frames(2)
	if player._touch_move != Vector2.RIGHT:
		_errors.append("move lost during look drag")
	touch(13, atk_center, true)
	await _frames(2)
	if not player._attack_active:
		_errors.append("attack not active")
	var yaw_atk: float = rig.rotation.y
	drag(13, atk_center + Vector2(30, 0), Vector2(30, 0))
	await _frames(2)
	if is_equal_approx(rig.rotation.y, yaw_atk):
		_errors.append("attack drag rotated camera")
	touch(13, atk_center, false)
	touch(12, free_pos + Vector2(70, 0), false)
	touch(10, right_center, false)
	await _frames(40)
	if _strikes != 1:
		_errors.append("strikes %d != 1" % _strikes)
	if player._touch_move != Vector2.ZERO:
		_errors.append("stuck move")
	if not is_equal_approx(rig.rotation.y, yaw_atk):
		_errors.append("camera stuck rotating")

	# --- 5. reset_lesson + focus out ---
	scene.reset_lesson()
	await _frames(2)
	if str(run_btn.text) != "Ходьба":
		_errors.append("reset: text not Ходьба")
	if hud._run_enabled:
		_errors.append("reset: _run_enabled true")
	if player._touch_run:
		_errors.append("reset: _touch_run true")
	touch(1, run_center, true)
	await _frames(1)
	touch(1, run_center, false)
	await _frames(2)
	hud.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	player.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	rig.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(2)
	if player._touch_run:
		_errors.append("focus out: run stuck")
	if player._touch_move != Vector2.ZERO:
		_errors.append("focus out: move stuck")

	scene.queue_free()
	await _frames(2)
	if _errors.is_empty():
		print("ASHBOUND_COURTYARD_RUN_TOUCH_OK")
		quit(0)
	else:
		for e in _errors:
			push_error(e)
		quit(1)

func _setup(player: Node, rig: Node) -> void:
	player.global_position = Vector3(-6.0, 0.1, 10.0)
	rig.reset_view()
	if player.has_signal("strike"):
		player.connect("strike", _on_strike)

func _on_strike() -> void:
	_strikes += 1

func touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	root.push_input(ev, true)

func drag(index: int, pos: Vector2, relative: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	ev.relative = relative
	root.push_input(ev, true)

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
