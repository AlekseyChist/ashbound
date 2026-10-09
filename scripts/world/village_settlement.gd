extends "res://scripts/world/village_walkthrough.gd"
const Terrain = preload("res://scripts/world/village_terrain.gd")
const Dressing = preload("res://scripts/world/village_dressing.gd")
const Atmosphere = preload("res://scripts/world/village_atmosphere.gd")
var layout: Dictionary
var terrain: Node3D
var dressing: Node3D
var environment: Environment
var sun: DirectionalLight3D
var assembled := false
var atmosphere: Node
var settings: RefCounted
var settings_menu: Control
var audio: Node
## D-115/D-116: spoken lines (English) under the HUD subtitles.
var voice: Node
var pocket: CanvasLayer
var grass: Node3D

func _ready() -> void:
	super._ready()
	var index := 0
	for item in layout.buildings:
		if int(item.phase) != 1: continue
		var building: Node3D = buildings[index]
		building.position = Vector3(float(item.x)-Terrain.ORIGIN.x,item.elevation_m,float(item.y)-Terrain.ORIGIN.y)
		building.rotation.y = -deg_to_rad(item.angle)
		index += 1
	assembled = true
	dressing = Dressing.new()
	add_child(dressing)
	dressing.build(terrain,buildings)
	camera_rig.get_camera().far = 220.0
	select_building(0)
	atmosphere=Atmosphere.new();atmosphere.name="Atmosphere";add_child(atmosphere);atmosphere.configure(self)
	settings=preload("res://scripts/world/village_settings.gd").new()
	settings.load_settings();settings.apply_distance(self)
	grass = preload("res://scripts/world/village_grass.gd").new()
	grass.name = "Grass"
	add_child(grass)
	grass.configure(self, settings.grass_percent / 100.0, settings.grass_distance)
	audio=preload("res://scripts/world/village_audio.gd").new();audio.name="VillageAudio";add_child(audio);audio.configure(self,settings)
	pocket = preload("res://scenes/world/village_pocket_menu.tscn").instantiate()
	pocket.world = self
	rig.add_child(pocket)
	settings_menu = preload("res://scripts/world/village_settings_menu.gd").new()
	settings_menu.name = "VillageSettings"
	pocket.get_pocket_panel().use_settings_page(settings_menu)
	settings_menu.configure(self, settings)
	voice = preload("res://scripts/world/world_voice.gd").new()
	voice.name = "Voice"
	add_child(voice)
	voice.configure(self)
	hud.voice = voice
	hud.set_subtitles(settings.subtitles, settings.subtitle_language)
	# UI-CLEAN-01: the game screen keeps only play controls; checking tools are in Settings -> Debug,
	# the language choice is already in Settings.
	hud.get_node("RootControl/HousePicker").hide()
	hud.get_node("RootControl/TopRightPanel").hide()
	_layout_play_controls()
	DisplayServer.window_set_title("AshBound — Forest Village 0.23.6")
	print("VILLAGE_SETTLEMENT_READY version=0.23.6 houses=3 trees=",dressing.tree_positions.size())

func _environment() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world/village-layout-v1.json"))
	_prepare_layout(layout)
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	_prepare_terrain(terrain)
	terrain.configure(layout)
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("596e70")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("718389")
	environment.ambient_light_energy = .42
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("667975")
	environment.fog_density = .0018
	world.environment = environment
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42,-35,0)
	sun.light_color = Color("ffe2ae")
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)

## Hook for a host scene (the world) to extend the plan before the ground is built.
func _prepare_layout(_plan: Dictionary) -> void:
	pass

## Hook for a host scene to set ground mesh options before the ground is built.
func _prepare_terrain(_ground: Node3D) -> void:
	pass

func select_building(index: int) -> void:
	super.select_building(index)
	if not assembled: return
	var building: Node3D = buildings[selected]
	var at := building.to_global(building.record.entry+Vector3(0,0,4.0))
	at.y = terrain.height_at(at.x,at.z)+.12
	player.global_position = at
	player.facing_direction = -building.global_basis.z
	camera_rig._yaw = building.rotation.y
	camera_rig._apply_rotation()
	camera_rig.snap_to_target()
	player.get_node("Visual").reset_motion_interpolation()

## UI-CLEAN-01: one right column 32 px from the edges, as wide as "Things": Things at the top,
## Run / Action / Attack at the bottom (the Block button sits left of Attack, world_block_toolbar.gd).
const COLUMN_RIGHT := 32.0
const COLUMN_WIDTH := 298.0
func _layout_play_controls() -> void:
	var things: Button = pocket.get_open_button()
	things.offset_right = -COLUMN_RIGHT
	things.offset_left = -COLUMN_RIGHT-COLUMN_WIDTH
	things.offset_top = 24.0
	things.offset_bottom = 144.0
	var column: Control = hud.get_node("RootControl/BottomRight")
	column.offset_right = -COLUMN_RIGHT+8.0
	column.offset_left = -COLUMN_RIGHT-COLUMN_WIDTH-8.0
	column.offset_bottom = -COLUMN_RIGHT+8.0
	column.offset_top = column.offset_bottom-412.0
	(column.get_node("VBox") as BoxContainer).alignment = BoxContainer.ALIGNMENT_END
	# DIALOG-LINE-01: the HUD lays the line out itself above the Block/Attack line and the quick bar.
	# The "E · action" prompt at the bottom centre stays clear of Block on a 16:9 screen.
	var prompt: Control = hud.get_node("RootControl/PromptLabel")
	prompt.offset_left = -300.0
	prompt.offset_right = 300.0
	# JUMP-01: Jump sits above Block, left of Action (phone only; Space on a PC).
	var jump: Button = hud.get_node("RootControl/JumpButton")
	jump.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	jump.offset_right = -COLUMN_RIGHT-COLUMN_WIDTH-12.0
	jump.offset_left = jump.offset_right-COLUMN_WIDTH
	jump.offset_bottom = -32.0-120.0-12.0
	jump.offset_top = jump.offset_bottom-120.0
	jump.visible = hud.force_touch_controls
	if not hud.jump_pressed.is_connected(player.request_jump):
		hud.jump_pressed.connect(player.request_jump)

## From Settings -> Debug: close the menu and go to the next house.
func _on_picker_pressed() -> void:
	if settings_menu == null or pocket.state == pocket.State.CLOSED:
		super._on_picker_pressed()
		return
	pocket.close_menu()
	select_building((selected+1)%buildings.size())

func is_input_available() -> bool:
	return super.is_input_available() and (pocket==null or pocket.state==pocket.State.CLOSED)
