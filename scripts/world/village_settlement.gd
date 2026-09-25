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
	grass=preload("res://scripts/world/village_grass.gd").new();grass.name="Grass";add_child(grass);grass.configure(self);grass.set_mode(1)
	settings=preload("res://scripts/world/village_settings.gd").new()
	settings.load_settings();settings.apply_distance(self)
	audio=preload("res://scripts/world/village_audio.gd").new();audio.name="VillageAudio";add_child(audio);audio.configure(self,settings)
	pocket = preload("res://scenes/world/village_pocket_menu.tscn").instantiate()
	pocket.world = self
	rig.add_child(pocket)
	settings_menu = preload("res://scripts/world/village_settings_menu.gd").new()
	settings_menu.name = "VillageSettings"
	pocket.get_pocket_panel().use_settings_page(settings_menu)
	settings_menu.configure(self, settings)
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

func is_input_available() -> bool:
	return super.is_input_available() and (pocket==null or pocket.state==pocket.State.CLOSED)
