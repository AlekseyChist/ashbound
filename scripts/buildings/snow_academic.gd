extends Node3D
const Door = preload("res://scripts/world/village_door.gd")
const Lantern = preload("res://assets/props/tavern-v1/wooden_lantern_01.glb")
var door: Node3D
var interior_meshes: Array[MeshInstance3D] = []
var interior_visible := true
var lamp_root: Node3D
var interior_lights: Array[OmniLight3D] = []
var lights_enabled := true
var light_check := 0.0
func _ready() -> void:
    door = Door.new()
    door.name = "Door"
    add_child(door)
    door.configure(self, str(get_instance_id()), Vector3(0, 0, 5.8))
    for node in find_children("*", "MeshInstance3D", true, false):
        if node.get_meta("extras", {}).get("part_role", "") == "interior_furniture":
            interior_meshes.append(node)
    lamp_root = Node3D.new()
    lamp_root.name = "InteriorLanterns"
    add_child(lamp_root)
    _add_lamp(Vector3(-5, 2.6, 0), 3.36)
    _add_lamp(Vector3(5, 2.6, 3), 3.36)
    _add_lamp(Vector3(6.45, 6, -4.06), 7.08)
    set_physics_process(false)

func _add_lamp(at: Vector3, ceiling: float) -> void:
    var lantern := Lantern.instantiate() as Node3D
    lantern.position = at
    lamp_root.add_child(lantern)
    for mesh in lantern.find_children("*", "GeometryInstance3D", true, false):
        mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var top := at.y + .5174
    var rope := MeshInstance3D.new()
    var cord := BoxMesh.new()
    cord.size = Vector3(.02, ceiling - top, .02)
    rope.mesh = cord
    rope.position = Vector3(at.x, (ceiling + top) * .5, at.z)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(.25, .18, .1)
    rope.material_override = material
    lamp_root.add_child(rope)
    var light := OmniLight3D.new()
    light.position = at + Vector3(0, .18, 0)
    light.light_color = Color(1, .76, .5)
    light.light_energy = .8
    light.omni_range = 7.5
    light.shadow_enabled = true
    lamp_root.add_child(light)
    interior_lights.append(light)

func _process(delta: float) -> void:
    light_check += delta
    if light_check < .5:
        return
    light_check = 0
    var camera := get_viewport().get_camera_3d()
    for light in interior_lights:
        light.visible = lights_enabled and interior_visible and (camera == null or camera.global_position.distance_to(light.global_position) < 45)

func set_interior_lights_enabled(enabled: bool) -> void:
    lights_enabled = enabled
    for light in interior_lights:
        light.visible = enabled and interior_visible
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
        for light in interior_lights:
            light.visible = false
    set_physics_process(not enabled)
    return true
