extends SceneTree
## RUN-01: проверка бега во дворе (headless, fixed-fps 60).
## Время измеряется только physics frames: (Engine.get_physics_frames()-start)/60.0.

var _errors: PackedStringArray = []
var _strikes := 0
var _strike_time := -1.0
var _attack_start_frame := -1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var scene: Node = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	var player := scene.get_node("Actors/Player") as CharacterBody3D
	var visual := player.get_node("Visual") as Node
	var body := visual.get_node("Body") as AnimatedSprite3D
	var rig := scene.get_node("CameraRig") as Node
	if player == null or body == null or rig == null:
		_fail("missing player/visual/body/rig")
	player.strike_requested.connect(_on_strike)
	root.add_child(scene)
	await _frames(5)

	var start_pos := Vector3(-6.0, 0.1, 10.0)

	# --- Скорость: walk 4.2, run 6.4 (реальная скорость) ---
	player.global_position = start_pos
	player.velocity = Vector3.ZERO
	_clear_inputs()
	await _frames(5)
	Input.action_press("move_right")
	await _settle(player, 4.2)
	var walk_speed := player.get_real_velocity().length()
	if absf(walk_speed - 4.2) > 0.15:
		_errors.append("walk speed %f != 4.2" % walk_speed)
	Input.action_press("run")
	await _settle(player, 6.4)
	var run_speed := player.get_real_velocity().length()
	if absf(run_speed - 6.4) > 0.15:
		_errors.append("run speed %f != 6.4" % run_speed)
	Input.action_release("run")
	await _settle(player, 4.2)
	var walk_back := player.get_real_velocity().length()
	if absf(walk_back - 4.2) > 0.15:
		_errors.append("speed after run release %f != 4.2" % walk_back)
	Input.action_release("move_right")
	await _frames(3)

	# --- Диагональ: get_real_velocity <= run_speed + 0.05 ---
	player.global_position = start_pos
	player.velocity = Vector3.ZERO
	_clear_inputs()
	await _frames(5)
	Input.action_press("move_right")
	Input.action_press("move_back")
	Input.action_press("run")
	await _settle(player, 6.4)
	var diag_speed := player.get_real_velocity().length()
	if diag_speed > 6.4 + 0.05:
		_errors.append("diagonal run speed %f > 6.45" % diag_speed)
	_clear_inputs()
	await _frames(3)

	# --- Metadata pixel_size (обычные и run-специфичные) и run-клипы (8 кадров, 15 fps) ---
	var frames := body.sprite_frames
	for key in ["pixel_size_back", "pixel_size_front", "pixel_size_side"]:
		if not frames.has_meta(key) or float(frames.get_meta(key)) <= 0.0:
			_errors.append("missing/invalid meta %s" % key)
	for key in ["pixel_size_run_back", "pixel_size_run_front", "pixel_size_run_side"]:
		if not frames.has_meta(key) or float(frames.get_meta(key)) <= 0.0:
			_errors.append("missing/invalid run meta %s" % key)
	for view in ["back", "front", "side"]:
		var clip := StringName("run_" + view)
		if not frames.has_animation(clip):
			_errors.append("missing run clip %s" % clip)
			continue
		if frames.get_frame_count(clip) != 8:
			_errors.append("run_%s frame count %d != 8" % [view, frames.get_frame_count(clip)])
		if absf(frames.get_animation_speed(clip) - 15.0) > 0.01:
			_errors.append("run_%s fps %f != 15" % [view, frames.get_animation_speed(clip)])

	# --- run_pose_fps 5 vs 15: одинаковая дистанция за 60 physics frames ---
	var dist_a := await _measure_distance(player, start_pos, 15)
	var dist_b := await _measure_distance(player, start_pos, 5)
	print("ASHBOUND_DIST pose_fps=15: %.4f  pose_fps=5: %.4f" % [dist_a, dist_b])
	if absf(dist_a - dist_b) > 0.05:
		_errors.append("run distance differs by pose_fps: %f vs %f" % [dist_a, dist_b])
	if absf(player.move_speed - 4.2) > 0.001:
		_errors.append("move_speed changed to %f" % player.move_speed)

	# --- run без движения не бежит; input_enabled=false запрещает бег ---
	player.global_position = start_pos
	player.velocity = Vector3.ZERO
	_clear_inputs()
	await _frames(5)
	Input.action_press("run")
	await _frames(10)
	if player.is_running():
		_errors.append("is_running without movement input")
	if player.get_real_velocity().length() > 0.01:
		_errors.append("moved with run only")
	Input.action_release("run")
	player.input_enabled = false
	Input.action_press("move_right")
	Input.action_press("run")
	await _frames(10)
	if player.is_running():
		_errors.append("running while input disabled")
	player.set_run_input(false)
	if player._touch_run:
		_errors.append("set_run_input(false) not reset while disabled")
	player.input_enabled = true
	_clear_inputs()
	await _frames(3)

	# --- stop_input и focus-out сбрасывают сенсорный бег ---
	player.set_run_input(true)
	if not player._touch_run:
		_errors.append("set_run_input(true) failed")
	player.stop_input()
	if player._touch_run:
		_errors.append("stop_input did not reset _touch_run")
	player.set_run_input(true)
	player.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	if player._touch_run:
		_errors.append("focus-out did not reset _touch_run")

	# --- Атака из бега: один strike на 0.12 с (7-8 physics frame), скорость 1.05 ---
	player.global_position = start_pos
	player.velocity = Vector3.ZERO
	_clear_inputs()
	await _frames(5)
	Input.action_press("move_right")
	Input.action_press("run")
	await _settle(player, 6.4)
	_strikes = 0
	_strike_time = -1.0
	_attack_start_frame = Engine.get_physics_frames()
	player.request_attack()
	var attack_deadline := Engine.get_physics_frames() + 40
	while _strikes == 0 and Engine.get_physics_frames() < attack_deadline:
		await physics_frame
	if _strikes != 1:
		_errors.append("strike count %d != 1" % _strikes)
	elif _strike_time < 0.12 or _strike_time > 0.13:
		_errors.append("strike at %f s outside 0.12-0.13" % _strike_time)
	# Скорость 6.4 -> 1.05 с accel 20: ~0.267 с (16 кадров). На 18-20 кадре
	# после атаки скорость уже 1.05 и атака ещё активна (длится 24 кадра).
	await _frames(18)
	var slowed := player.get_real_velocity().length()
	if absf(slowed - 1.05) > 0.1:
		_errors.append("speed at frame ~18 after attack %f != 1.05" % slowed)
	while player._attack_active and Engine.get_physics_frames() < _attack_start_frame + 60:
		await physics_frame
	if player._attack_active:
		_errors.append("attack did not end within 60 frames")
	await _settle(player, 6.4)
	var resumed := player.get_real_velocity().length()
	if absf(resumed - 6.4) > 0.15:
		_errors.append("run not resumed after attack: %f" % resumed)
	_clear_inputs()
	await _frames(3)

	# --- Стена: не проходить сквозь, is_running=false после упора ---
	var wall := StaticBody3D.new()
	wall.name = "TestWall"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 4.0, 8.0)
	col.shape = shape
	wall.add_child(col)
	wall.position = Vector3(1.0, 0.5, 10.0)
	scene.add_child(wall)
	await _frames(2)
	player.global_position = start_pos
	player.velocity = Vector3.ZERO
	_clear_inputs()
	await _frames(5)
	Input.action_press("move_right")
	Input.action_press("run")
	for i in 90:
		await physics_frame
	var px := player.global_position.x
	if px > 1.0 - 0.2:
		_errors.append("player passed through wall at x=%f" % px)
	if player.is_running():
		_errors.append("is_running after wall impact")
	_clear_inputs()
	wall.queue_free()
	await _frames(2)

	# --- Виды run_back/front/side, left flip, фаза при смене вида ---
	player.set_physics_process(false)
	player.stop_input()
	_clear_inputs()
	rig.rotation.y = 0.0
	var view_cases: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.RIGHT, Vector3.LEFT]
	var expected_views: Array[StringName] = [&"run_back", &"run_front", &"run_side", &"run_side"]
	for i in view_cases.size():
		visual.update_visual(&"run", view_cases[i], 15, 15)
		var vd: StringName = visual.get_visual_direction()
		if body.animation != expected_views[i]:
			_errors.append("view %d: clip %s want %s" % [i, body.animation, expected_views[i]])
	# LEFT -> run_side с flip_h; RIGHT -> без flip
	visual.update_visual(&"run", Vector3.LEFT, 15, 15)
	if body.flip_h != true:
		_errors.append("flip_h not set for left")
	visual.update_visual(&"run", Vector3.RIGHT, 15, 15)
	if body.flip_h != false:
		_errors.append("flip_h set for right")
	# Пауза + сохранение кадра/прогресса при смене вида
	body.pause()
	body.set_frame_and_progress(3, 0.5)
	visual.update_visual(&"run", Vector3.FORWARD, 15, 15)
	if body.frame != 3 or absf(body.frame_progress - 0.5) > 0.01:
		_errors.append("frame/progress not preserved on view change: %d/%f" % [body.frame, body.frame_progress])
	if body.is_playing():
		_errors.append("body resumed playing while paused")
	body.play()
	player.set_physics_process(true)

	# --- Старый набор без run_: walk_sameview во время бега, атомарность ---
	var old_frames := frames.duplicate(true)
	for view in ["back", "front", "side"]:
		old_frames.remove_animation(StringName("run_" + view))
	var ok_old: bool = visual.set_appearance_frames(old_frames)
	if not ok_old:
		_errors.append("old set without run_ rejected")
	else:
		Input.action_press("move_right")
		Input.action_press("run")
		await _settle(player, 6.4)
		var clip := body.animation
		if not String(clip).begins_with("walk"):
			_errors.append("old set running clip %s not walk_*" % clip)
		_clear_inputs()
	# Неполный run-набор отклоняется атомарно (остаются 2 из 3 run-клипов)
	var partial := frames.duplicate(true)
	partial.remove_animation(&"run_front")
	var before := body.sprite_frames
	if visual.set_appearance_frames(partial):
		_errors.append("partial run set accepted")
	elif body.sprite_frames != before:
		_errors.append("partial run set not atomic")
	# Вернуть исходный
	if not visual.set_appearance_frames(frames):
		_errors.append("restore original frames failed")
	_clear_inputs()

	scene.queue_free()
	await _frames(2)
	if _errors.is_empty():
		print("ASHBOUND_COURTYARD_RUN_OK")
		quit(0)
	else:
		for e in _errors:
			push_error(e)
		quit(1)

# --- helpers ---

func _fail(msg: String) -> void:
	_errors.append(msg)
	quit(1)

func _clear_inputs() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back", "run"]:
		Input.action_release(a)

func _settle(player: CharacterBody3D, target_speed: float) -> void:
	for i in 60:
		await physics_frame
		if absf(player.get_real_velocity().length() - target_speed) < 0.05:
			return

func _measure_distance(player: CharacterBody3D, start_pos: Vector3, pose_fps: int) -> float:
	player.run_pose_fps = pose_fps
	player.global_position = start_pos
	player.velocity = Vector3.ZERO
	_clear_inputs()
	await _frames(5)
	Input.action_press("move_right")
	Input.action_press("run")
	var p0 := player.global_position
	for i in 60:
		await physics_frame
	var dist := (player.global_position - p0).length()
	print("ASHBOUND_MEASURE pose_fps=%d dist=%.4f" % [pose_fps, dist])
	_clear_inputs()
	await _frames(3)
	return dist

func _on_strike() -> void:
	_strikes += 1
	_strike_time = float(Engine.get_physics_frames() - _attack_start_frame) / 60.0

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
