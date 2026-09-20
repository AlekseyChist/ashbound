extends SceneTree

var _errors: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var scene: Node = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	var hud := scene.get_node("HUD")
	hud.force_touch_controls = true
	root.add_child(scene)
	await process_frame
	await process_frame
	await process_frame
	var rig := scene.get_node("CameraRig")
	var player := scene.get_node("Actors/Player")
	var up_btn: Control = scene.get_node("HUD/RootControl/BottomLeft/DpadGrid/Up")
	var atk_btn: Control = scene.get_node("HUD/RootControl/BottomRight/VBox/AttackButton")
	var free_area := Vector2(1100, 400)
	var up_center := up_btn.get_global_rect().get_center()
	var atk_center := atk_btn.get_global_rect().get_center()
	var atk_rect := atk_btn.get_global_rect()
	print("viewport rect: ", get_root().get_viewport().get_visible_rect())
	print("up center: ", up_center, " atk center: ", atk_center)
	var yaw0: float = rig.rotation.y
	# finger10 press Up
	_touch(10, up_center, true)
	await process_frame
	await _frames(2)
	# finger11 free area press + drag
	_touch(11, free_area, true)
	await process_frame
	_drag(11, free_area + Vector2(100, 0), Vector2(100, 0))
	await _frames(2)
	if player._touch_move != Vector2.UP:
		_errors.append("move not UP after Up+drag")
	if is_equal_approx(rig.rotation.y, yaw0):
		_errors.append("yaw unchanged after free drag")
	_touch(11, free_area + Vector2(100, 0), false)
	await _frames(2)
	if player._touch_move != Vector2.UP:
		_errors.append("move not UP after release 11")
	var yaw_before_attack: float = rig.rotation.y
	# finger12 attack button drag inside rect
	_touch(12, atk_center, true)
	await process_frame
	var p2 := atk_center + Vector2(100, 0)
	if not atk_rect.has_point(p2):
		p2 = atk_center
	_drag(12, p2, p2 - atk_center)
	await _frames(2)
	print("attack after press: _attack_active=", player._attack_active, " hud._touch_attack_index=", hud._touch_attack_index)
	if not is_equal_approx(rig.rotation.y, yaw_before_attack):
		_errors.append("yaw changed by attack drag")
	if player._touch_move != Vector2.UP:
		_errors.append("move lost during attack drag")
	if not player._attack_active:
		_errors.append("attack not active")
	_touch(12, p2, false)
	await process_frame
	await _frames(1)
	print("after free press/drag: rig._touch_index=", rig._touch_index, " rig.rotation.y=", rig.rotation.y)
	_touch(10, up_center, false)
	await process_frame
	await _frames(2)
	if player._touch_move != Vector2.ZERO:
		_errors.append("move not zero after releases")
	var yaw_after: float = rig.rotation.y
	# stray drag 11 after release must not rotate
	_drag(11, free_area + Vector2(200, 0), Vector2(100, 0))
	await _frames(2)
	if not is_equal_approx(rig.rotation.y, yaw_after):
		_errors.append("stray drag rotated camera")
	# focus out test
	_touch(13, free_area, true)
	await process_frame
	_drag(13, free_area + Vector2(50, 0), Vector2(50, 0))
	await _frames(1)
	rig.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	hud.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	player.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var yaw_focus: float = rig.rotation.y
	_drag(13, free_area + Vector2(150, 0), Vector2(100, 0))
	await _frames(2)
	if not is_equal_approx(rig.rotation.y, yaw_focus):
		_errors.append("drag after focus-out rotated camera")
	if player._touch_move != Vector2.ZERO:
		_errors.append("move not zero after focus-out")
	_touch(13, free_area + Vector2(150, 0), false)
	await process_frame
	await _frames(1)
	# reset_lesson clears look state (scene root is the Level)
	scene.reset_lesson()
	await _frames(2)
	var yaw_reset: float = rig.rotation.y
	_drag(11, free_area + Vector2(300, 0), Vector2(100, 0))
	await _frames(2)
	if not is_equal_approx(rig.rotation.y, yaw_reset):
		_errors.append("stray drag after reset rotated camera")
	scene.queue_free()
	await _frames(2)
	if _errors.is_empty():
		print("ASHBOUND_CAMERA_TOUCH_OK")
		quit(0)
	else:
		for e in _errors:
			push_error(e)
		quit(1)

func _touch(index: int, position: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = position
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _drag(index: int, position: Vector2, relative: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = position
	ev.relative = relative
	Input.parse_input_event(ev)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
