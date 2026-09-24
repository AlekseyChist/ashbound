extends Node3D
## Separate, full-scale geography prototype. No campaign or save migration.
const Geometry = preload("res://scripts/world/world_graybox_geometry.gd")
const Shapes = preload("res://scripts/world/world_graybox_shapes.gd")
const Headwaters = preload("res://scripts/world/world_graybox_headwaters.gd")
const Landmarks = preload("res://scripts/world/world_graybox_landmarks.gd")
const Starter = preload("res://scripts/world/world_graybox_starter.gd")
const PlayerScene = preload("res://scenes/courtyard/courtyard_player.tscn")
const CameraScene = preload("res://scenes/courtyard/third_person_camera.tscn")
const HudScene = preload("res://scenes/courtyard/courtyard_hud.tscn")
const AcceptedFrames = preload("res://assets/characters/world-graybox-v1/traveler_frames.tres")
const CITY_KEYS = ["WORLD_CITY_FOREST", "WORLD_CITY_SNOW", "WORLD_CITY_DESERT", "WORLD_CITY_LOWLAND"]

var layout: Dictionary
var heights: PackedFloat32Array
var terrain: Node3D
var shapes: Node3D
var player: CharacterBody3D
var camera_rig: Node3D
var hud: CanvasLayer
var overview_camera: Camera3D
var overview := true
var selected_city := 0
var overview_center := Vector3(0, 160, 0)
var overview_distance := 2250.0
var overview_yaw := 0.0
var overview_pitch := deg_to_rad(58.0)
var nav_input := Vector2.ZERO
var drag_touch := -1
var mouse_drag := false
var focused := true
var mode_button: Button
var city_picker: Button
var locations_overlay: Control
var locations_panel: PanelContainer
var locations_scroll: ScrollContainer
var location_buttons: Array[Button] = []
var location_touch := -1
var location_touch_start := Vector2.ZERO
var location_touch_last := Vector2.ZERO
var location_touch_moved := false
var location_touch_choice := -1
var language_button: Button
var zoom_controls: VBoxContainer
var help_label: Label
var city_labels: Array[Label3D] = []
var locations: Array = []
var starter_layout: Dictionary

func _ready() -> void:
	DisplayServer.window_set_title("AshBound — Starter Forest 0.21.3")
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world/graybox-v1/layout.json"))
	locations = layout.cities + layout.sites
	heights = FileAccess.get_file_as_bytes("res://assets/world/graybox-v1/heights.bin").to_float32_array()
	var raw := FileAccess.get_file_as_bytes("res://assets/world/graybox-v1/colors.bin").to_float32_array()
	var colors := PackedColorArray()
	for i in range(0, raw.size(), 4):
		colors.append(Color(raw[i], raw[i + 1], raw[i + 2], raw[i + 3]))
	terrain = Geometry.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(heights, colors, int(layout.width), float(layout.spacing))
	shapes = Shapes.new()
	shapes.name = "RoadsAndSites"
	add_child(shapes)
	for road in layout.roads:
		var points := points_of(road)
		# Overlap road-end caps slightly so shared junctions have no open triangle edge.
		points.insert(0, points[0] + (points[0] - points[1]).normalized() * 0.5)
		points.append(points[-1] + (points[-1] - points[-2]).normalized() * 0.5)
		var width: float = road.get("width_m", 6.0)
		var strip: MeshInstance3D = shapes.add_strip(points, width, Color("958466"), true)
		strip.name = road.id
		_build_shoulders(points, width)
	for river in layout.rivers:
		var points := points_of(river)
		var left := PackedVector3Array()
		var right := PackedVector3Array()
		for i in range(points.size()):
			var tangent := points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]
			var side := Vector3(-tangent.z, 0, tangent.x).normalized() * float(river.world_widths[i]) * 0.5
			left.append(points[i] + side)
			right.append(points[i] - side)
		var strip: MeshInstance3D = shapes.add_band(left, right, Color("537d91"), false)
		strip.name = river.id
	_build_headwaters()
	_build_sites()
	_build_starter()
	_add_light()
	player = PlayerScene.instantiate()
	player.name = "Player"
	add_child(player)
	player.get_node("Visual").set_appearance_frames(AcceptedFrames)
	camera_rig = CameraScene.instantiate()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.set_target(player)
	camera_rig.get_camera().far = 4500.0
	overview_camera = Camera3D.new()
	overview_camera.name = "OverviewCamera"
	overview_camera.far = 6500.0
	overview_camera.near = 2.0
	overview_camera.fov = 55.0
	add_child(overview_camera)
	hud = HudScene.instantiate()
	hud.name = "HUD"
	hud.force_touch_controls = true
	add_child(hud)
	hud.move_changed.connect(_move_changed)
	hud.run_changed.connect(func(enabled: bool): player.set_run_input(enabled and not overview))
	hud.attack_pressed.connect(func():
		if not overview: player.request_attack())
	hud.restart_pressed.connect(reset_position)
	_configure_hud()
	Localization.language_changed.connect(_refresh_text)
	select_city(4)
	set_overview(true)
	reset_overview()
	print("WORLD_GRAYBOX_READY version=%s grid=%d extent=2000" % [layout.version, layout.width])

func points_of(record: Dictionary) -> PackedVector3Array:
	var points := PackedVector3Array()
	for p in record.world_points:
		points.append(Vector3(p[0], p[1], p[2]))
	return points

func _build_shoulders(points: PackedVector3Array, width: float) -> void:
	# Join land to the deck so the hero can leave/re-enter a road without a step.
	# Deep channels keep an open span; banks must not fill rivers under bridges.
	for side in [-1.0, 1.0]:
		var inner := PackedVector3Array()
		var outer := PackedVector3Array()
		for i in range(points.size()):
			var p := points[i]
			var tangent := points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]
			var perpendicular: Vector3 = Vector3(-tangent.z, 0, tangent.x).normalized() * side
			var edge := p + perpendicular * width * 0.5
			var bank := p + perpendicular * 8.0
			bank.y = ground_height(bank.x, bank.z) + 0.02
			var on_land := p.y - ground_height(p.x, p.z) < 2.0
			if not on_land:
				if inner.size() > 1:
					shapes.add_band(outer if side > 0 else inner, inner if side > 0 else outer, Color("8c836d"), true)
				inner.clear()
				outer.clear()
				continue
			inner.append(edge)
			outer.append(bank)
		if inner.size() > 1:
			shapes.add_band(outer if side > 0 else inner, inner if side > 0 else outer, Color("8c836d"), true)

func _build_headwaters() -> void:
	var water := Headwaters.new()
	water.name = "Headwaters"
	add_child(water)
	for lake in layout.lakes:
		var p: Array = lake.center
		var mesh: MeshInstance3D = water.add_lake(Vector3(p[0] - 1000, p[2], p[1] - 1000), Vector2(lake.radii_m[0], lake.radii_m[1]))
		mesh.name = lake.id
	for spring in layout.springs:
		var p: Array = spring.mouth
		var direction: Array = spring.facing
		var cave: Node3D = water.add_spring_cave(Vector3(p[0] - 1000, p[2] - 1, p[1] - 1000), Vector3(direction[0], 0, direction[2]))
		cave.name = spring.id

func _build_sites() -> void:
	for index in range(locations.size()):
		var city: Dictionary = locations[index]
		var p: Array = city.spawn
		var center := Vector3(p[0], p[1], p[2])
		if index < 4:
			for offset in [Vector3(-28, 0, 15), Vector3(26, 0, 18), Vector3(-20, 0, -25)]:
				var size := Vector3(12, 12 + float(city.number) * 3, 16)
				var base: Vector3 = center + offset
				base.y = ground_height(base.x, base.z)
				shapes.add_marker(base + Vector3.UP * size.y * 0.5, size, Color("92938b"))
		elif city.kind != "lake" and city.kind != "spring_cave" and city.id != "start_hamlet":
			var landmark := Landmarks.new()
			landmark.name = city.id
			add_child(landmark)
			var direction: Array = city.facing
			landmark.build(city.kind, Vector3(center.x, float(city.point[2]), center.z), Vector3(direction[0], 0, direction[2]))
		var label := Label3D.new()
		label.position = center + Vector3.UP * 45
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 64
		label.pixel_size = 0.28
		label.no_depth_test = true
		label.modulate = Color("ede6d6")
		add_child(label)
		city_labels.append(label)

func _build_starter() -> void:
	starter_layout = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world/graybox-v1/starter-region.json"))
	layout.version = starter_layout.version
	var starter := Starter.new()
	starter.name = "StarterRegion"
	add_child(starter)
	for house in starter_layout.houses:
		var p: Array = house.origin
		var size: Array = house.size
		var model: Node3D = starter.add_house(Vector3(p[0], p[1], p[2]), float(house.yaw), Vector3(size[0], size[1], size[2]), float(house.foundation))
		model.name = house.id
	var forest: Node3D = starter.add_forest(starter_layout.trees)
	forest.name = "Forest"

func _add_light() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("667a81")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b3c0c4")
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color("ece8db")
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)

func _configure_hud() -> void:
	for path in ["TopLeftPanel", "BottomLeft/LegendLabel", "BottomRight/VBox/InteractButton", "PromptLabel"]:
		hud.get_node("RootControl/" + path).hide()
	var root: Control = hud.get_node("RootControl")
	var top := HBoxContainer.new()
	top.name = "WorldToolbar"
	top.position = Vector2(24, 24)
	top.add_theme_constant_override("separation", 16)
	root.add_child(top)
	mode_button = _button(top, Vector2(260, 120))
	mode_button.pressed.connect(func(): set_overview(not overview))
	city_picker = _button(top, Vector2(440, 120))
	city_picker.pressed.connect(func(): show_locations(true))
	language_button = _button(top, Vector2(120, 120))
	language_button.pressed.connect(func():
		Localization.set_language("en" if Localization.get_language() == "ru" else "ru"))
	var help_panel := PanelContainer.new()
	help_panel.position = Vector2(24, 156)
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(help_panel)
	help_label = Label.new()
	help_label.add_theme_font_size_override("font_size", 22)
	help_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	help_panel.add_child(help_label)
	zoom_controls = VBoxContainer.new()
	zoom_controls.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	zoom_controls.position = Vector2(root.size.x - 150, 250)
	root.add_child(zoom_controls)
	zoom_controls.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	zoom_controls.offset_left = -150
	zoom_controls.offset_right = -24
	zoom_controls.offset_top = -140
	zoom_controls.offset_bottom = 140
	var plus := _button(zoom_controls, Vector2(120, 120))
	plus.text = "+"
	plus.pressed.connect(func(): zoom_overview(0.8))
	var minus := _button(zoom_controls, Vector2(120, 120))
	minus.text = "−"
	minus.pressed.connect(func(): zoom_overview(1.25))
	var restart: PanelContainer = hud.get_node("RootControl/TopRightPanel")
	restart.offset_left = -350
	restart.offset_bottom = 164
	restart.get_node("RestartButton").custom_minimum_size = Vector2(300, 120)
	hud.clear_message()
	locations_overlay = Control.new()
	root.add_child(locations_overlay)
	locations_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	locations_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	locations_overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: show_locations(false)
		elif event is InputEventScreenTouch and event.pressed: show_locations(false))
	locations_panel = PanelContainer.new()
	locations_panel.position = Vector2(300, 156)
	locations_overlay.add_child(locations_panel)
	locations_scroll = ScrollContainer.new()
	locations_scroll.custom_minimum_size = Vector2(620, 660)
	locations_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	locations_panel.add_child(locations_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	locations_scroll.add_child(list)
	for index in range(locations.size()):
		var item := _button(list, Vector2(570, 120))
		item.pressed.connect(select_city.bind(index))
		location_buttons.append(item)
	locations_overlay.hide()

func show_locations(enabled: bool) -> void:
	_clear_input()
	locations_overlay.visible = enabled
	# The shared HUD owns its buttons in _input, before GUI hit-testing.
	# A modal chooser must suspend that input too, including controls behind it.
	hud.set_process_input(not enabled)
	player.input_enabled = not enabled and not overview and focused
	camera_rig.input_enabled = player.input_enabled
	if enabled:
		locations_scroll.ensure_control_visible(location_buttons[selected_city])

func _location_event(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
		if event.pressed and location_touch == -1:
			location_touch = event.index
			location_touch_start = event.position
			location_touch_last = event.position
			location_touch_moved = false
			location_touch_choice = -1 if locations_panel.get_global_rect().has_point(event.position) else -2
			if locations_scroll.get_global_rect().has_point(event.position):
				for i in range(location_buttons.size()):
					if location_buttons[i].get_global_rect().has_point(event.position): location_touch_choice = i
		elif not event.pressed and event.index == location_touch:
			var choice := location_touch_choice
			var activate: bool = not location_touch_moved and not event.canceled
			location_touch = -1
			if activate and choice == -2: show_locations(false)
			elif activate and choice >= 0 and locations_scroll.get_global_rect().has_point(event.position) and location_buttons[choice].get_global_rect().has_point(event.position): select_city(choice)
	elif event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
		if event.index != location_touch: return
		location_touch_moved = location_touch_moved or event.position.distance_to(location_touch_start) > 12
		if location_touch_moved and location_touch_choice != -2:
			locations_scroll.scroll_vertical += roundi(location_touch_last.y - event.position.y)
		location_touch_last = event.position

func _button(parent: Node, minimum: Vector2) -> Button:
	var button := Button.new()
	button.custom_minimum_size = minimum
	button.focus_mode = Control.FOCUS_NONE
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	parent.add_child(button)
	return button

func _refresh_text(_language: String = "") -> void:
	mode_button.text = Localization.text("WORLD_WALK" if overview else "WORLD_OVERVIEW")
	language_button.text = "EN" if Localization.get_language() == "ru" else "RU"
	for i in range(locations.size()):
		location_buttons[i].text = "%d · %s" % [i + 1, Localization.text(locations[i].key)]
	city_picker.text = "%d · %s" % [selected_city + 1, Localization.text(locations[selected_city].key)]
	_update_labels()
	hud.get_node("RootControl/TopRightPanel/RestartButton").text = Localization.text("WORLD_ALL" if overview else "WORLD_RESET")
	help_label.text = Localization.text("WORLD_OVERVIEW_HELP" if overview else "WORLD_WALK_HELP")
	if not overview: help_label.text += "\n" + Localization.text("WORLD_SITE_HINT")

func _clear_input() -> void:
	nav_input = Vector2.ZERO
	drag_touch = -1
	mouse_drag = false
	location_touch = -1
	if is_instance_valid(hud): hud.reset_controls()
	if is_instance_valid(player): player.stop_input()
	if is_instance_valid(camera_rig): camera_rig.stop_look()

func set_overview(enabled: bool) -> void:
	_clear_input()
	locations_overlay.hide()
	hud.set_process_input(true)
	overview = enabled
	player.input_enabled = not enabled
	camera_rig.input_enabled = not enabled
	if enabled:
		overview_camera.make_current()
		_update_overview_camera()
	else:
		camera_rig.get_camera().make_current()
		camera_rig.snap_to_target()
	zoom_controls.visible = enabled
	hud.get_node("RootControl/BottomRight").visible = not enabled
	_refresh_text()

func select_city(index: int) -> void:
	_clear_input()
	selected_city = clampi(index, 0, locations.size() - 1)
	show_locations(false)
	_refresh_text()
	var p: Array = locations[selected_city].spawn
	player.position = Vector3(p[0], p[1] + 0.15, p[2])
	player.velocity = Vector3.ZERO
	player.facing_direction = Vector3.FORWARD
	camera_rig.reset_view()
	# Start looking toward the route, rather than straight into the northern mountain.
	var city: Dictionary = locations[selected_city]
	var toward := Vector3(city.point[0] - 1000, city.point[2], city.point[1] - 1000) - player.position
	if selected_city == 1: toward = Vector3(1, 0, 1)
	if selected_city >= 4: toward = -Vector3(city.facing[0], 0, city.facing[2])
	toward.y = 0
	if toward.length_squared() > 0.01:
		player.facing_direction = toward.normalized()
		var was_enabled: bool = camera_rig.input_enabled
		camera_rig.input_enabled = true
		var yaw := atan2(-toward.x, -toward.z)
		camera_rig.rotate_view(Vector2(-yaw / camera_rig.mouse_sensitivity, 0))
		camera_rig.input_enabled = was_enabled
		camera_rig.snap_to_target()
	overview_center = player.position
	if overview: _update_overview_camera()

func reset_position() -> void:
	if overview: reset_overview()
	else: select_city(selected_city)

func reset_overview() -> void:
	_clear_input()
	overview_center = Vector3(0, 160, 0)
	overview_distance = 2250
	overview_yaw = 0
	overview_pitch = deg_to_rad(58)
	_update_overview_camera()

func zoom_overview(factor: float) -> void:
	overview_distance = clampf(overview_distance * factor, 180, 3000)
	_update_overview_camera()

func _update_overview_camera() -> void:
	var direction := Vector3(sin(overview_yaw) * cos(overview_pitch), sin(overview_pitch), cos(overview_yaw) * cos(overview_pitch))
	overview_camera.position = overview_center + direction * overview_distance
	overview_camera.position.y = maxf(overview_camera.position.y, ground_height(overview_camera.position.x, overview_camera.position.z) + 40)
	overview_camera.look_at(overview_center, Vector3.UP)

func ground_height(x: float, z: float) -> float:
	var gx := clampf((x + 1000) / 5, 0, 399.9999)
	var gz := clampf((z + 1000) / 5, 0, 399.9999)
	var ix := int(gx)
	var iz := int(gz)
	var u := gx - ix
	var v := gz - iz
	var a := heights[iz * 401 + ix]
	var b := heights[iz * 401 + ix + 1]
	var c := heights[(iz + 1) * 401 + ix]
	var d := heights[(iz + 1) * 401 + ix + 1]
	return a + u * (b - a) + v * (c - a) if u + v <= 1 else d + (1 - u) * (c - d) + (1 - v) * (b - d)

func _move_changed(value: Vector2) -> void:
	if overview: nav_input = value
	else: player.set_move_input(value)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player): return
	if player.position.y < -40 or absf(player.position.x) > 998 or absf(player.position.z) > 998:
		select_city(selected_city)
	if overview and focused and not locations_overlay.visible:
		var move := (nav_input + Input.get_vector("move_left", "move_right", "move_forward", "move_back")).limit_length()
		var right := overview_camera.global_basis.x
		var back := Vector3(overview_camera.global_basis.z.x, 0, overview_camera.global_basis.z.z).normalized()
		overview_center += (right * move.x + back * move.y) * delta * maxf(80, overview_distance * 0.25)
		overview_center.x = clampf(overview_center.x, -950, 950)
		overview_center.z = clampf(overview_center.z, -950, 950)
		overview_center.y = ground_height(overview_center.x, overview_center.z) + 30
		_update_overview_camera()
	_update_labels()

func _update_labels() -> void:
	for i in range(city_labels.size()):
		var label := city_labels[i]
		label.visible = overview or player.position.distance_to(label.position) < 160
		label.pixel_size = overview_distance * (0.00042 if i < 4 else 0.00032) if overview else 0.04
		var full_name := not overview or i < 4 or overview_distance < 1050
		label.text = "%d · %s" % [i + 1, Localization.text(locations[i].key)] if full_name else str(i + 1)

func _rotate_overview(relative: Vector2) -> void:
	overview_yaw -= relative.x * 0.005
	overview_pitch = clampf(overview_pitch + relative.y * 0.003, deg_to_rad(30), deg_to_rad(82))
	_update_overview_camera()

func _input(event: InputEvent) -> void:
	if is_instance_valid(locations_overlay) and locations_overlay.visible:
		_location_event(event)
		if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_TAB]:
			show_locations(false)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION: return
	# Releases must also reach us when a finger ends over UI.
	if event is InputEventScreenTouch and not event.pressed and event.index == drag_touch: drag_touch = -1
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT: mouse_drag = false
	if not overview or not focused: return
	if event is InputEventScreenDrag and event.index == drag_touch:
		_rotate_overview(event.relative)
		get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and mouse_drag:
		_rotate_overview(event.relative)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not focused: return
	if locations_overlay.visible: return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		set_overview(not overview)
		get_viewport().set_input_as_handled()
	if not overview: return
	if event is InputEventScreenTouch and event.pressed and drag_touch == -1: drag_touch = event.index
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT: mouse_drag = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP: zoom_overview(0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom_overview(1.1)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		focused = false
		_clear_input()
		if is_instance_valid(locations_overlay): show_locations(false)
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_WM_WINDOW_FOCUS_IN]:
		focused = true
		if is_instance_valid(locations_overlay): show_locations(false)

func _exit_tree() -> void:
	if is_instance_valid(camera_rig): camera_rig.stop_look()
