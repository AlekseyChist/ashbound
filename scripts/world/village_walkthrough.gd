extends Node3D
## A walkthrough of the model family; not the final settlement layout or campaign.
const Catalog = preload("res://scripts/world/village_building_catalog.gd")
const Building = preload("res://scripts/world/village_building.gd")
const PlayerScene = preload("res://scenes/courtyard/courtyard_player.tscn")
const CameraScene = preload("res://scenes/courtyard/third_person_camera.tscn")
const HudScene = preload("res://scenes/courtyard/courtyard_hud.tscn")
const AcceptedFrames = preload("res://assets/characters/world-graybox-v1/traveler_frames.tres")
var buildings: Array[Node3D] = []
var player: CharacterBody3D
var camera_rig: Node3D
var hud: CanvasLayer
var selected := 0
var current_door: Node3D
var picker: Button
var language_button: Button
var interact_button: Button
var focus_ok := true
var window_focus_ok := true
var app_active := true
var feedback_time := 0.0

func _ready() -> void:
	DisplayServer.window_set_title("AshBound — Village Houses 0.22.1")
	_environment()
	for record in Catalog.all():
		var building := Building.new()
		add_child(building)
		building.build(record)
		buildings.append(building)
	player = PlayerScene.instantiate()
	player.name = "Player"
	add_child(player)
	player.get_node("Visual").set_appearance_frames(AcceptedFrames)
	player.interact_requested.connect(interact)
	camera_rig = CameraScene.instantiate()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.set_target(player)
	camera_rig.get_camera().far = 150.0
	hud = HudScene.instantiate()
	hud.name = "HUD"
	hud.force_touch_controls = true
	add_child(hud)
	hud.move_changed.connect(player.set_move_input)
	hud.run_changed.connect(player.set_run_input)
	hud.interact_pressed.connect(interact)
	hud.restart_pressed.connect(func(): select_building(selected))
	_configure_hud()
	Localization.language_changed.connect(_refresh_text)
	select_building(0)
	print("VILLAGE_WALKTHROUGH_READY version=0.22.1 buildings=3")

func _environment() -> void:
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "InspectionGround"
	var box := BoxMesh.new()
	box.size = Vector3(64, 0.25, 44)
	floor_mesh.mesh = box
	floor_mesh.position.y = -0.125
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.26, 0.29, 0.19)
	material.roughness = 1.0
	floor_mesh.material_override = material
	add_child(floor_mesh)
	floor_mesh.create_trimesh_collision()
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.36, 0.43, 0.44)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.76, 0.8)
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.light_color = Color(1.0, 0.95, 0.84)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 75.0
	add_child(sun)

func _configure_hud() -> void:
	for path in ["TopLeftPanel/VBox/TitleLabel", "TopLeftPanel/VBox/SubtitleLabel", "BottomRight/VBox/AttackButton"]:
		hud.get_node("RootControl/" + path).hide()
	var panel: PanelContainer = hud.get_node("RootControl/TopLeftPanel")
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.offset_right = 690.0
	panel.offset_bottom = 110.0
	var legend: Label = hud.get_node("RootControl/BottomLeft/LegendLabel")
	legend.hide()
	var restart: PanelContainer = hud.get_node("RootControl/TopRightPanel")
	restart.offset_left = -340.0
	restart.offset_bottom = 164.0
	restart.get_node("RestartButton").custom_minimum_size = Vector2(288,120)
	var bar := HBoxContainer.new()
	bar.name = "HousePicker"
	bar.position = Vector2(720,24)
	bar.add_theme_constant_override("separation",20)
	hud.get_node("RootControl").add_child(bar)
	picker = _button(bar,Vector2(320,120))
	picker.pressed.connect(func():
		if is_input_available(): select_building((selected+1)%buildings.size()))
	language_button = _button(bar,Vector2(240,120))
	language_button.pressed.connect(func():
		if is_input_available(): Localization.set_language("en" if Localization.get_language()=="ru" else "ru"))
	interact_button = hud.get_node("RootControl/BottomRight/VBox/InteractButton")
	var prompt: Label = hud.get_node("RootControl/PromptLabel")
	prompt.offset_left = -380.0
	prompt.offset_right = 380.0
	prompt.offset_top = -110.0
	prompt.offset_bottom = -24.0
	prompt.add_theme_stylebox_override("normal", hud.get_node("RootControl").theme.get_stylebox("panel", "PanelContainer"))
	hud.clear_message()
	_refresh_text()

func _button(parent: Control, minimum: Vector2) -> Button:
	var button := Button.new()
	button.custom_minimum_size = minimum
	button.focus_mode = Control.FOCUS_NONE
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	parent.add_child(button)
	return button

func _refresh_text(_language: String = "") -> void:
	if hud == null: return
	picker.text = Localization.text("VILLAGE_NEXT")
	language_button.text = "EN" if Localization.get_language()=="ru" else "RU"
	hud.get_node("RootControl/TopRightPanel/RestartButton").text = Localization.text("FOREST_RETURN_START")
	_update_prompt()

func select_building(index: int) -> void:
	selected = clampi(index,0,buildings.size()-1)
	hud.reset_controls()
	player.stop_input()
	player.velocity = Vector3.ZERO
	var building: Node3D = buildings[selected]
	player.global_position = building.to_global(building.record.entry + Vector3(0,0.15,3.0))
	player.facing_direction = Vector3.FORWARD
	camera_rig.stop_look()
	camera_rig.reset_view()
	camera_rig.set_mouse_capture(is_input_available())
	feedback_time = 0.0
	_update_prompt()

func is_input_available() -> bool:
	return focus_ok and window_focus_ok and app_active and not get_tree().paused

func interact() -> void:
	if not is_input_available(): return
	_update_prompt()
	if current_door == null: return
	if not current_door.try_toggle(player) and current_door.blocked:
		feedback_time = 1.5
	_update_prompt()

func _physics_process(delta: float) -> void:
	if player == null: return
	feedback_time = maxf(0.0,feedback_time-delta)
	if player.global_position.y < -8.0: select_building(selected)
	_update_prompt()

func _update_prompt() -> void:
	if hud == null or player == null: return
	current_door = null
	var best := INF
	var inside_key := ""
	for building in buildings:
		var door: Node3D = building.door
		var distance: float = door.target_point().distance_squared_to(player.global_position+Vector3.UP)
		if is_input_available() and door.can_interact(player) and distance < best:
			current_door = door
			best = distance
		if building.contains(player.global_position): inside_key = building.record.title_key
	for building in buildings: building.door.set_highlight(building.door==current_door)
	hud.set_objective("VILLAGE_OUTSIDE" if inside_key.is_empty() else inside_key)
	interact_button.disabled = current_door == null
	var key := "VILLAGE_OPEN"
	if current_door != null:
		var would_close: bool = current_door.goal > 0.5 if current_door.moving else current_door.fraction > 0.0
		if would_close:
			key = "VILLAGE_CLOSE"
	interact_button.text = Localization.text(key)
	if current_door == null:
		hud.set_prompt("")
	elif feedback_time > 0.0 or current_door.blocked and current_door.moving:
		hud.set_prompt(Localization.text("VILLAGE_DOOR_BLOCKED"))
	elif current_door.moving:
		hud.set_prompt(Localization.text("VILLAGE_DOOR_MOVING"))
	else:
		hud.set_prompt(Localization.text(key) if OS.get_name()=="Android" else "E · "+Localization.text(key))

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT: focus_ok = false
		NOTIFICATION_APPLICATION_FOCUS_IN: focus_ok = true
		NOTIFICATION_WM_WINDOW_FOCUS_OUT: window_focus_ok = false
		NOTIFICATION_WM_WINDOW_FOCUS_IN: window_focus_ok = true
		NOTIFICATION_APPLICATION_PAUSED: app_active = false
		NOTIFICATION_APPLICATION_RESUMED: app_active = true
		_: return
	sync_input_state()

func sync_input_state() -> void:
	if player == null or camera_rig == null or hud == null: return
	var available := is_input_available()
	player.input_enabled = available
	camera_rig.input_enabled = available
	for building in buildings: building.door.suspended = not available
	if not available:
		hud.reset_controls()
		player.stop_input()
		camera_rig.stop_look()

func _exit_tree() -> void:
	if is_instance_valid(camera_rig): camera_rig.stop_look()
