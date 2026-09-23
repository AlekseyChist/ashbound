extends Node3D
## Exploration-only route. Reuses input/visuals without courtyard quests or saves.
const Layout := preload("res://scripts/world/forest_route_layout.gd")
const EnvironmentBuilder := preload("res://scripts/world/forest_route_environment.gd")
const PlayerScene := preload("res://scenes/courtyard/courtyard_player.tscn")
const CameraScene := preload("res://scenes/courtyard/third_person_camera.tscn")
const HudScene := preload("res://scenes/courtyard/courtyard_hud.tscn")

var player: CharacterBody3D
var camera_rig: Node3D
var hud: CanvasLayer
var terrain: Node3D
var location_key := ""
var reached_lookout := false

func _ready() -> void:
	DisplayServer.window_set_title("AshBound — Forest Route")
	terrain = EnvironmentBuilder.new()
	terrain.name = "RouteEnvironment"
	add_child(terrain)
	terrain.build(Layout.main_path(), Layout.loop_path())
	_add_light()
	player = PlayerScene.instantiate()
	player.name = "Player"
	add_child(player)
	camera_rig = CameraScene.instantiate()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.set_target(player)
	camera_rig.get_camera().far = 420.0
	hud = HudScene.instantiate()
	hud.name = "HUD"
	hud.force_touch_controls = true
	add_child(hud)
	hud.move_changed.connect(player.set_move_input)
	hud.run_changed.connect(player.set_run_input)
	hud.attack_pressed.connect(player.request_attack)
	hud.restart_pressed.connect(reset_route)
	_configure_hud()
	Localization.language_changed.connect(_refresh_text)
	reset_route()
	print("ASHBOUND_FOREST_ROUTE_READY length=%.2f" % Layout.length_of(Layout.main_path()))

func _add_light() -> void:
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.21, 0.27, 0.30)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.63, 0.71, 0.76)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.30, 0.37, 0.39)
	env.fog_density = 0.0018
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "OvercastLight"
	sun.rotation_degrees = Vector3(-52, -32, 0)
	sun.light_color = Color(0.93, 0.92, 0.84)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	add_child(sun)

func _configure_hud() -> void:
	for path in ["TopLeftPanel/VBox/TitleLabel", "TopLeftPanel/VBox/SubtitleLabel",
			"BottomLeft/LegendLabel", "BottomRight/VBox/InteractButton", "PromptLabel"]:
		hud.get_node("RootControl/" + path).hide()
	var panel: PanelContainer = hud.get_node("RootControl/TopLeftPanel")
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.offset_right = 700.0
	panel.offset_bottom = 104.0
	var objective: Label = hud.get_node("RootControl/TopLeftPanel/VBox/ObjectiveLabel")
	objective.custom_minimum_size = Vector2(0, 60)
	objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var restart: PanelContainer = hud.get_node("RootControl/TopRightPanel")
	restart.offset_left = -340.0
	restart.offset_bottom = 164.0
	var button: Button = restart.get_node("RestartButton")
	button.custom_minimum_size = Vector2(288, 120)
	hud.clear_message()
	_refresh_text()

func _refresh_text(_language: String = "") -> void:
	if hud == null:
		return
	hud.get_node("RootControl/TopRightPanel/RestartButton").text = Localization.text("FOREST_RETURN_START")
	if not location_key.is_empty():
		hud.set_objective(location_key)

func reset_route() -> void:
	hud.reset_controls()
	player.stop_input()
	player.velocity = Vector3.ZERO
	player.position = Layout.main_path()[0] + Vector3.UP * 0.1
	player.facing_direction = Vector3.FORWARD
	camera_rig.stop_look()
	camera_rig.reset_view()
	camera_rig.set_mouse_capture(true)
	reached_lookout = false
	_update_location()

func _physics_process(_delta: float) -> void:
	if player == null:
		return
	# Last-resort recovery outside the finite prototype, not a death system.
	if player.position.y < -35.0:
		reset_route()
	_update_location()

func _update_location() -> void:
	var z := player.position.z
	var next_key := "FOREST_OUTSKIRTS"
	if z < -510.0:
		next_key = "FOREST_LOOKOUT"
	elif z < -350.0:
		next_key = "FOREST_ASCENT"
	elif z < -290.0:
		next_key = "FOREST_BRIDGE"
	elif z < -140.0:
		next_key = "FOREST_FORK"
	elif z < -55.0:
		next_key = "FOREST_ROAD"
	if player.position.distance_to(Layout.main_path()[-1]) < 10.0:
		reached_lookout = true
	if next_key != location_key:
		location_key = next_key
		hud.set_objective(location_key)

func _exit_tree() -> void:
	if is_instance_valid(camera_rig):
		camera_rig.stop_look()
