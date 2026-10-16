extends Node3D
## Open PDF141 longbow pavilion. Imported shell/furniture retain their contacts.
const Lantern = preload("res://assets/props/tavern-v1/wooden_lantern_01.glb")
var interior_meshes: Array[MeshInstance3D] = []
var interior_visible := true
var lamp_root: Node3D
var interior_light: OmniLight3D
var lights_enabled := true
var light_check := 0.0

func _ready() -> void:
	for mesh in find_children("*", "MeshInstance3D", true, false):
		if mesh.get_meta("extras", {}).get("part_role", "") == "interior_furniture":
			interior_meshes.append(mesh)
	_build_lamp()
	_sync_light()

func _build_lamp() -> void:
	var anchor := get_node("LampAnchor") as Node3D
	var ceiling := get_node("LampCeiling") as Node3D
	lamp_root = Node3D.new()
	lamp_root.name = "RoomLantern"
	add_child(lamp_root)
	var lantern := Lantern.instantiate() as Node3D
	lantern.name = "WoodenLantern"
	lantern.position = anchor.position
	lamp_root.add_child(lantern)
	for mesh in lantern.find_children("*", "GeometryInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var top := lantern.position.y + .5174
	var underside := ceiling.position.y
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
	var body := StaticBody3D.new()
	body.name = "LanternContact"
	body.collision_layer = 1 | 8
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.36, .54, .36)
	shape.shape = box
	body.position = lantern.position + Vector3(0, .25, 0)
	body.add_child(shape)
	add_child(body)
	interior_light = OmniLight3D.new()
	interior_light.name = "ArcheryLight"
	interior_light.position = lantern.position + Vector3(0, .18, 0)
	interior_light.light_color = Color(1, .76, .5)
	interior_light.light_energy = .8
	interior_light.omni_range = 6
	interior_light.shadow_enabled = true
	interior_light.distance_fade_enabled = true
	interior_light.distance_fade_begin = 35
	interior_light.distance_fade_length = 10
	lamp_root.add_child(interior_light)

func _sync_light() -> void:
	var camera := get_viewport().get_camera_3d()
	interior_light.visible = lights_enabled and interior_visible and (camera == null or camera.global_position.distance_to(interior_light.global_position) < 45)

func _process(delta: float) -> void:
	light_check += delta
	if light_check >= .5:
		light_check = 0
		_sync_light()

func set_interior_lights_enabled(enabled: bool) -> void:
	lights_enabled = enabled
	_sync_light()

func set_interior_visible(enabled: bool, occupied: bool = false) -> bool:
	if not enabled and occupied:
		return false
	# The world builder polls every frame; contacts remain active while draws sleep.
	if enabled == interior_visible:
		return true
	for mesh in interior_meshes:
		mesh.visible = enabled
	interior_visible = enabled
	lamp_root.visible = enabled
	_sync_light()
	return true
