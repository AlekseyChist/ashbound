class_name CourtyardThirdPersonCamera
extends Node3D
## Модульная камера от третьего лица (вид сзади, в духе Gothic).
## Целевой объект (игрок) внедряется уровнем через set_target() — без путей между сценами.

@export var distance: float = 3.0
@export var follow_height: float = 1.45
@export var mouse_sensitivity: float = 0.003
@export var touch_sensitivity: float = 0.004
@export var pitch_min_degrees: float = -50.0
@export var pitch_max_degrees: float = 12.0
@export var follow_speed: float = 12.0

var target: Node3D
var input_enabled: bool = true

var _spring_arm: SpringArm3D
var _camera: Camera3D
var _yaw: float = 0.0
var _pitch: float = deg_to_rad(-12.0)
var _mouse_captured: bool = false
var _touch_index: int = -1


func _ready() -> void:
	_spring_arm = $SpringArm3D as SpringArm3D
	_camera = $SpringArm3D/Camera3D as Camera3D
	if _spring_arm != null:
		_spring_arm.spring_length = distance
		_spring_arm.margin = 0.2
		_spring_arm.rotation.x = deg_to_rad(-12.0)
	if _camera != null:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = 65.0
		_camera.near = 0.08
		_camera.far = 180.0
		_camera.current = true
	_apply_rotation()
	if _should_capture_mouse():
		_set_mouse_captured(true)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var desired := target.global_position + Vector3(0.0, follow_height, 0.0)
	var t: float = clampf(1.0 - exp(-follow_speed * delta), 0.0, 1.0)
	global_position = global_position.lerp(desired, t)


func set_target(node: Node3D) -> void:
	if _spring_arm != null and target is CollisionObject3D:
		_spring_arm.clear_excluded_objects()
	target = node
	if _spring_arm != null and target is CollisionObject3D:
		_spring_arm.add_excluded_object(target.get_rid())


func snap_to_target() -> void:
	if target == null or not is_instance_valid(target):
		return
	global_position = target.global_position + Vector3(0.0, follow_height, 0.0)


func reset_view() -> void:
	_yaw = 0.0
	_pitch = deg_to_rad(-12.0)
	_apply_rotation()
	snap_to_target()


func rotate_view(delta_pixels: Vector2, touch: bool = false) -> void:
	if not input_enabled:
		return
	var sens: float = touch_sensitivity if touch else mouse_sensitivity
	_yaw -= delta_pixels.x * sens
	_pitch -= delta_pixels.y * sens
	_pitch = clampf(_pitch, deg_to_rad(pitch_min_degrees), deg_to_rad(pitch_max_degrees))
	_yaw = wrapf(_yaw, -PI, PI)
	_apply_rotation()


func get_camera() -> Camera3D:
	return _camera


func stop_look() -> void:
	_touch_index = -1
	if _mouse_captured:
		_set_mouse_captured(false)


func _apply_rotation() -> void:
	rotation.y = _yaw
	if _spring_arm != null:
		_spring_arm.rotation.x = _pitch


func _should_capture_mouse() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if OS.get_name() == "Android":
		return false
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if String(arg).begins_with("--capture-courtyard=") or String(arg) == "--no-mouse-capture":
			return false
	return true


func _set_mouse_captured(captured: bool) -> void:
	if captured and not _mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_mouse_captured = true
	elif not captured and _mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_mouse_captured = false


## Внешний запрос захвата мыши (например, из меню инвентаря).
## Захват желателен только при включённом вводе и _should_capture_mouse().
func set_mouse_capture(captured: bool) -> void:
	var desired := captured and input_enabled and _should_capture_mouse()
	_set_mouse_captured(desired)
	if desired:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_mouse_captured = true
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_mouse_captured = false


func _input(event: InputEvent) -> void:
	# Релиз палеца камеры обязан очищаться всегда, даже если GUI позже
	# пометит событие обработанным.
	if event is InputEventScreenTouch and event.pressed == false:
		var st := event as InputEventScreenTouch
		if st.index == _touch_index:
			_touch_index = -1
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _mouse_captured:
			rotate_view(mm.screen_relative, false)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Эмулированные клики (тачскрин -> мышь) не захватывают курсор.
		if mb.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT \
				and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE \
				and not _mouse_captured:
			# Первый клик по свободному миру при видимой мыши — только захват,
			# чтобы не атаковать.
			if _should_capture_mouse():
				_set_mouse_captured(true)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and _touch_index == -1:
			var vp_size := get_viewport().get_visible_rect().size
			if st.position.x >= vp_size.x * 0.45:
				_touch_index = st.index
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _touch_index != -1 and sd.index == _touch_index:
			rotate_view(sd.relative, true)
			get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE:
			if _mouse_captured:
				_set_mouse_captured(false)
			elif _should_capture_mouse():
				_set_mouse_captured(true)
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_touch_index = -1
		if _mouse_captured:
			_set_mouse_captured(false)
