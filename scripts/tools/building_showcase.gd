extends Node3D
# AshBound — building showcase (preview scene).
# Orbit camera: LMB drag rotate, wheel zoom, 1/2/3 focus building, 0 all, R reset.

const HOUSE_PATH := "res://scenes/buildings/house.tscn"
const TOWER_PATH := "res://scenes/buildings/watchtower.tscn"
const GATE_PATH := "res://scenes/buildings/gate.tscn"

const HOME_POS := Vector3(17, 13, 31)
const HOME_TARGET := Vector3(0, 3, 0)
const MIN_DIST := 4.0
const MAX_DIST := 60.0
const MIN_ELEV := 5.0
const MAX_ELEV := 89.0

var _camera: Camera3D
var _target: Vector3 = HOME_TARGET
var _yaw: float
var _pitch: float
var _dist: float
var _dragging := false
var _last_mouse: Vector2

var _capture_path := ""
var _capture_pending := false
var _capture_frames := 0


func _ready() -> void:
	# Windowed preview so the main project's fullscreen setting doesn't disrupt it.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 800))

	_setup_ground()
	_setup_buildings()
	_setup_camera()
	_setup_lights()
	_setup_ui()
	_parse_capture_arg()


func _setup_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var box := BoxMesh.new()
	box.size = Vector3(48.0, 1.0, 28.0)
	ground.mesh = box
	ground.position = Vector3(0, -0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.31, 0.24)
	mat.roughness = 1.0
	mat.metallic = 0.0
	ground.material_override = mat
	add_child(ground)

	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(48.0, 1.0, 28.0)
	col.shape = shape
	body.add_child(col)
	body.position = Vector3(0, -0.5, 0)
	add_child(body)


func _setup_buildings() -> void:
	var paths: Array[String] = [HOUSE_PATH, TOWER_PATH, GATE_PATH]
	var xs: Array[float] = [-10.0, 0.0, 10.0]
	for i in paths.size():
		var res := load(paths[i])
		if res == null:
			push_warning("building_showcase: cannot load %s" % paths[i])
			continue
		var inst = (res as PackedScene).instantiate()
		inst.name = "Building%d" % i
		inst.position = Vector3(xs[i], 0.0, 0.0)
		add_child(inst)


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.near = 0.1
	_camera.far = 200.0
	add_child(_camera)
	_reset_view()


func _reset_view() -> void:
	_target = HOME_TARGET
	var offset := HOME_POS - HOME_TARGET
	_dist = offset.length()
	_yaw = rad_to_deg(atan2(offset.x, offset.z))
	_pitch = rad_to_deg(asin(clampf(offset.y / _dist, -1.0, 1.0)))
	_apply_camera()


func _apply_camera() -> void:
	var yaw := deg_to_rad(_yaw)
	var pitch := deg_to_rad(_pitch)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	_camera.position = _target + dir * _dist
	_camera.look_at(_target, Vector3.UP)


func _setup_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)

	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.62, 0.70, 0.80)
	sky_mat.sky_horizon_color = Color(0.85, 0.86, 0.84)
	sky_mat.sky_curve = 0.3
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.82)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	add_child(layer)

	var panel := PanelContainer.new()
	panel.name = "InfoPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.72)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "AshBound — здания"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	var controls := Label.new()
	controls.text = "ЛКМ: вращение • колесо: масштаб • 1/2/3: здание • 0: все • R: сброс"
	controls.add_theme_font_size_override("font_size", 14)
	vbox.add_child(controls)

	var anchor := Control.new()
	anchor.name = "PanelAnchor"
	anchor.set_anchors_preset(Control.PRESET_TOP_LEFT)
	anchor.position = Vector2(16, 16)
	layer.add_child(anchor)
	anchor.add_child(panel)


func _parse_capture_arg() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if not args[i].begins_with("--capture-buildings="):
			continue
		var raw: String = args[i].substr("--capture-buildings=".length())
		var base := ProjectSettings.globalize_path("res://local/previews/")
		var simplified := raw.simplify_path()
		if not simplified.begins_with(base) or not simplified.ends_with(".png"):
			push_warning("building_showcase: capture path rejected: %s" % raw)
			return
		_capture_path = simplified
		_capture_pending = true
		_capture_frames = 8
		break


func _process(_delta: float) -> void:
	if _capture_pending and _capture_frames > 0:
		_capture_frames -= 1
		if _capture_frames == 0:
			_capture_pending = false
			RenderingServer.frame_post_draw.connect(_on_frame_post_draw, CONNECT_ONE_SHOT)


func _on_frame_post_draw() -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_capture_path)
	if err == OK:
		print("ASHBOUND_CAPTURE_OK")
		get_tree().quit(0)
	else:
		push_error("building_showcase: save_png failed: %s" % error_string(err))
		get_tree().quit(1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _dragging:
		var ev := event as InputEventMouseMotion
		_yaw -= ev.relative.x * 0.35
		_pitch += ev.relative.y * 0.35
		_pitch = clampf(_pitch, MIN_ELEV, MAX_ELEV)
		_apply_camera()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			_last_mouse = mb.position
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = clampf(_dist * 0.9, MIN_DIST, MAX_DIST)
			_apply_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = clampf(_dist / 0.9, MIN_DIST, MAX_DIST)
			_apply_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_1:
			_focus(0)
		elif key == KEY_2:
			_focus(1)
		elif key == KEY_3:
			_focus(2)
		elif key == KEY_0:
			_reset_view()
		elif key == KEY_R:
			_reset_view()


func _focus(index: int) -> void:
	var xs: Array[float] = [-10.0, 0.0, 10.0]
	_target = Vector3(xs[index], 3.0, 0.0)
	_dist = 16.0
	_apply_camera()
