extends Node3D
## Native PDF141 homes. Canonical scene supplies model physics; VillageDoor owns the leaf.
const Door = preload("res://scripts/world/village_door.gd")
const Lantern = preload("res://assets/props/tavern-v1/wooden_lantern_01.glb")
var door: Node3D
var interior_meshes: Array[MeshInstance3D] = []
var interior_visible := true
var lamp_root: Node3D
var interior_light: OmniLight3D
var lights_enabled := true
var light_check := 0.0

func _ready() -> void:
	var contract := find_child("ResidenceContract", true, false)
	var extras: Dictionary = contract.get_meta("extras", {})
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.get_meta("extras", {}).get("part_role", "") == "interior_furniture":
			interior_meshes.append(mesh)
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material != null and (material.resource_name.contains("adobe") or material.resource_name.contains("plaster")):
				var own := material.duplicate() as StandardMaterial3D
				own.vertex_color_use_as_albedo = true
				own.vertex_color_is_srgb = false
				mesh.set_surface_override_material(surface, own)
	# Imported collision-only meshes preserve their extras on the body in Godot4.7.
	for body in find_children("*", "StaticBody3D", true, false):
		body.collision_layer = 1
		if body.name.contains("bed") or body.name.contains("table") or body.name.contains("stool") or body.name.contains("chest"):
			body.collision_layer |= Door.OBSTACLE_LAYER
	door = Door.new()
	door.name = "Door"
	add_child(door)
	door.configure(self, str(get_instance_id()), Vector3(0, 0, float(extras["godot_entry_z"])))
	_build_lamp()
	set_physics_process(false)

func _build_lamp() -> void:
	var anchor := find_child("LampAnchor", true, false) as Node3D
	var ceiling := find_child("LampCeiling", true, false) as Node3D
	lamp_root = Node3D.new()
	lamp_root.name = "RoomLantern"
	add_child(lamp_root)
	var lantern := Lantern.instantiate() as Node3D
	lantern.position = to_local(anchor.global_position)
	lamp_root.add_child(lantern)
	for mesh in lantern.find_children("*", "GeometryInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var top := lantern.position.y + .5174
	var underside := to_local(ceiling.global_position).y
	var rope := MeshInstance3D.new()
	rope.name = "LanternCord"
	var cord := BoxMesh.new()
	cord.size = Vector3(.02, underside - top, .02)
	rope.mesh = cord
	rope.position = Vector3(lantern.position.x, (underside + top) * .5, lantern.position.z)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.25, .18, .1)
	rope.material_override = material
	lamp_root.add_child(rope)
	# Physical lantern above adult head; retained when interior visuals sleep.
	var body := StaticBody3D.new()
	body.name = "LanternContact"
	body.collision_layer = 1 | Door.OBSTACLE_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.36, .54, .36)
	shape.shape = box
	body.position = lantern.position + Vector3(0, .25, 0)
	body.add_child(shape)
	add_child(body)
	interior_light = OmniLight3D.new()
	interior_light.position = lantern.position + Vector3(0, .18, 0)
	interior_light.light_color = Color(1, .76, .5)
	interior_light.light_energy = .8
	interior_light.omni_range = 6
	interior_light.shadow_enabled = true
	lamp_root.add_child(interior_light)

func _process(delta: float) -> void:
	light_check += delta
	if light_check < .5:
		return
	light_check = 0
	var camera := get_viewport().get_camera_3d()
	interior_light.visible = lights_enabled and interior_visible and (camera == null or camera.global_position.distance_to(interior_light.global_position) < 45)

func set_interior_lights_enabled(enabled: bool) -> void:
	lights_enabled = enabled
	interior_light.visible = enabled and interior_visible

func _physics_process(_delta: float) -> void:
	if door.moving or not is_zero_approx(door.fraction):
		set_interior_visible(true)

func set_interior_visible(enabled: bool, occupied: bool = false) -> bool:
	if not enabled and (occupied or door == null or door.moving or not is_zero_approx(door.fraction)):
		return false
	for mesh in interior_meshes:
		mesh.visible = enabled
	interior_visible = enabled
	lamp_root.visible = enabled
	if not enabled:
		interior_light.visible = false
	set_physics_process(not enabled)
	return true
