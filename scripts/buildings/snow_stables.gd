extends Node3D
const Door = preload("res://scripts/world/village_door.gd")
const Lantern = preload("res://assets/props/tavern-v1/wooden_lantern_01.glb")
var door: Node3D
var interior_meshes: Array[MeshInstance3D] = []
var interior_visible := true
var lamp_assembly: Node3D
var interior_light: OmniLight3D
var lights_enabled := true
var light_check := 0.0
func _ready() -> void:
    door = Door.new()
    door.name = "Door"
    add_child(door)
    door.configure(self, str(get_instance_id()), Vector3(0, 0, 3.3))
    for node in find_children("*", "MeshInstance3D", true, false):
        if node.get_meta("extras", {}).get("part_role", "") == "interior_furniture":
            interior_meshes.append(node)
    _build_lamp()
    set_physics_process(false)

func _build_lamp() -> void:
    lamp_assembly = Node3D.new()
    lamp_assembly.name = "AisleLantern"
    add_child(lamp_assembly)
    var lantern := Lantern.instantiate() as Node3D
    lantern.position = Vector3(0, 2.4, 0)
    lamp_assembly.add_child(lantern)
    for mesh in lantern.find_children("*", "GeometryInstance3D", true, false):
        mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    # Measured lantern top2.9174; cross-tie underside2.97, not the roof ridge.
    var rope := MeshInstance3D.new()
    rope.name = "SupportCord"
    var cord := BoxMesh.new()
    cord.size = Vector3(.02, 2.97 - 2.9174, .02)
    rope.mesh = cord
    rope.position = Vector3(0, (2.97 + 2.9174) * .5, 0)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(.25, .18, .1)
    rope.material_override = material
    lamp_assembly.add_child(rope)
    interior_light = OmniLight3D.new()
    interior_light.name = "LanternLight"
    interior_light.position = Vector3(0, 2.58, 0)
    interior_light.light_color = Color(1, .76, .5)
    interior_light.light_energy = .8
    interior_light.omni_range = 7.5
    interior_light.shadow_enabled = true
    lamp_assembly.add_child(interior_light)

func _process(delta: float) -> void:
    light_check += delta
    if light_check < .5:
        return
    light_check = 0.0
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
    lamp_assembly.visible = enabled
    if not enabled:
        interior_light.visible = false
    set_physics_process(not enabled)
    return true
