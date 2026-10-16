extends Node3D
## Own local production candidate: the builder registers the door synchronously.
## World-dependent effects wait for player/weather and the physics snapshot.
const Door=preload("res://scripts/world/village_door.gd")
const Fire=preload("res://scripts/world/desert_cathedral_fire.gd")
const Interior=preload("res://scripts/world/desert_cathedral_lanterns.gd")
const Route=preload("res://scripts/world/desert_cathedral_route_lanterns.gd")
var door:Node3D
var fire:Node3D
var lamps:Node3D
var route_lamps:Node3D
var world:Node3D
var observer:Node3D
var runtime_ready:=false
var runtime_state:="waiting_for_world"
var lighting_enabled:=true
var generation:=0
var check_left:=0.0

func _enter_tree()->void:
	if is_node_ready():call_deferred("refresh_runtime")

func _ready()->void:
	door=Door.new();door.name="EntryDoor";add_child(door);door.configure(self,"desert:С",Vector3(0,0,7.9))
	fire=Fire.new();fire.name="BasinRuntime";add_child(fire)
	lamps=Interior.new();lamps.name="InteriorRuntime";add_child(lamps)
	route_lamps=Route.new();route_lamps.name="RouteRuntime";add_child(route_lamps)
	process_mode=Node.PROCESS_MODE_PAUSABLE
	call_deferred("refresh_runtime")

func refresh_runtime()->void:
	generation+=1
	var ticket:=generation
	runtime_ready=false;runtime_state="waiting_for_world"
	# An explicit refresh can revoke a still-alive viewer; retire its old effects now.
	if is_instance_valid(fire):fire.restore()
	if is_instance_valid(lamps):lamps.restore()
	if is_instance_valid(route_lamps):route_lamps.restore()
	var city:=get_parent()
	world=city.get("world") as Node3D if is_instance_valid(city) and city.has_method("get_doors") else null
	if not is_instance_valid(world):runtime_state="world_unavailable";return
	for frame in 2:
		await get_tree().physics_frame
		if ticket!=generation or not is_inside_tree() or not is_instance_valid(world):return
	observer=world.get("player") as Node3D
	if not is_instance_valid(observer):runtime_state="observer_unavailable";return
	var weather=world.get("atmosphere") as Node
	if not fire.configure(self,observer) or not lamps.configure(self,observer) or not route_lamps.configure(self,observer,weather):
		fire.restore();lamps.restore();route_lamps.restore();runtime_state="support_or_component_refused";return
	runtime_ready=true;runtime_state="ready";set_interior_lights_enabled(lighting_enabled)

func set_interior_lights_enabled(value:bool)->void:
	lighting_enabled=value
	if runtime_ready:
		fire.set_enabled(value);lamps.set_enabled(value);route_lamps.set_enabled(value)

func _process(delta:float)->void:
	check_left-=delta
	if check_left>0:return
	check_left=.5
	if not is_instance_valid(world):
		if runtime_ready:
			fire.restore();lamps.restore();route_lamps.restore()
			runtime_ready=false;runtime_state="world_unavailable";observer=null
		return
	var current=world.get("player") as Node3D
	if current!=observer or (runtime_ready and not is_instance_valid(current)) or (runtime_state=="observer_unavailable" and is_instance_valid(current)):
		fire.restore();lamps.restore();route_lamps.restore();observer=current
		if is_instance_valid(current):refresh_runtime()
		else:runtime_ready=false;runtime_state="observer_unavailable"

func _exit_tree()->void:
	generation+=1;runtime_ready=false;runtime_state="unloaded";world=null;observer=null
