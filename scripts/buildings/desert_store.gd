extends Node3D
## One-hall 8x6 store module. World placement and occupancy remain the caller's responsibility.
const Door = preload("res://scripts/world/village_door.gd")
const Lantern = preload("res://assets/props/tavern-v1/wooden_lantern_01.glb")
var door: Node3D
var interior_meshes: Array[MeshInstance3D] = []
var interior_visible := true
var lights_enabled := true
var lamp_root: Node3D
var lights: Array[OmniLight3D] = []
var light_check := 0.0

func _ready() -> void:
	var entry := find_child("EntryPortal", true, false) as Node3D
	assert(entry != null, "Store entry portal missing")
	door = Door.new()
	door.name = "Door"
	entry.add_child(door)
	door.configure(entry, str(get_instance_id()), Vector3(0, 0, 2.8))
	for mesh in find_children("*", "MeshInstance3D", true, false):
		if mesh.get_meta("extras", {}).get("part_role", "") == "interior_furniture":
			interior_meshes.append(mesh)
	lamp_root = Node3D.new()
	lamp_root.name = "RoomLanterns"
	add_child(lamp_root)
	var cord_material := StandardMaterial3D.new()
	cord_material.albedo_color = Color(.25, .18, .1)
	for at in [Vector3(0, 2.35, 0)]:
		var lantern := Lantern.instantiate() as Node3D
		lamp_root.add_child(lantern)
		lantern.position = at
		for mesh in lantern.find_children("*", "GeometryInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cord := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(.02, 3.04 - at.y - .5174, .02)
		cord.mesh = box
		cord.material_override = cord_material
		cord.position = Vector3(at.x, (3.04 + at.y + .5174) * .5, at.z)
		lamp_root.add_child(cord)
		var light := OmniLight3D.new()
		light.position = at + Vector3(0, .18, 0)
		light.light_color = Color(1, .76, .5)
		light.light_energy = .8
		light.omni_range = 6
		light.shadow_enabled = true
		lamp_root.add_child(light)
		lights.append(light)
	set_physics_process(false)

func _process(delta: float) -> void:
	light_check += delta
	if light_check < .5: return
	light_check = 0.0
	var camera := get_viewport().get_camera_3d()
	var nearby := camera != null and global_position.distance_to(camera.global_position) < 45.0
	for light in lights:
		light.visible = lights_enabled and interior_visible and nearby

func set_interior_lights_enabled(enabled: bool) -> void:
	lights_enabled = enabled

func _physics_process(_delta: float) -> void:
	if door.moving or not is_zero_approx(door.fraction):
		set_interior_visible(true)

func set_interior_visible(enabled: bool, occupied: bool = false) -> bool:
	if not enabled and (occupied or door == null or door.moving or not is_zero_approx(door.fraction)):
		return false
	interior_visible = enabled
	for mesh in interior_meshes: mesh.visible = enabled
	lamp_root.visible = enabled
	if not enabled:
		for light in lights: light.visible = false
	set_physics_process(not enabled)
	return true

