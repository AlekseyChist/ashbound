extends Node3D
## Bounded architectural asset. City placement and weather remain with the world.
const Door = preload("res://scripts/world/village_door.gd")
const Lantern = preload("res://assets/props/tavern-v1/wooden_lantern_01.glb")
const FLOOR_HEIGHTS := [0.0, 3.6, 7.2]
var door: Node3D
var maintenance_door: Node3D
var interior_meshes: Array[MeshInstance3D] = []
var interior_visible := true
var lamp_root: Node3D
var interior_lights: Array[OmniLight3D] = []
var lights_enabled := true
var light_check := 0.0

func _ready() -> void:
    var entry := find_child("EntryPortal", true, false) as Node3D
    var maintenance := find_child("MaintenancePortal", true, false) as Node3D
    assert(entry != null and maintenance != null, "Academy tower requires both physical portals")
    door = Door.new()
    door.name = "Door"
    entry.add_child(door)
    door.configure(entry, str(get_instance_id()) + ":entry", Vector3(0, 0, 5.3))
    maintenance_door = Door.new()
    maintenance_door.name = "MaintenanceDoor"
    maintenance.add_child(maintenance_door)
    maintenance_door.configure(maintenance, str(get_instance_id()) + ":maintenance", Vector3.ZERO)
    for node in find_children("*", "MeshInstance3D", true, false):
        if node.get_meta("extras", {}).get("part_role", "") == "interior_furniture":
            interior_meshes.append(node)
    lamp_root = Node3D.new()
    lamp_root.name = "InteriorLanterns"
    add_child(lamp_root)
    for height in FLOOR_HEIGHTS:
        _add_lamp(Vector3(-1, height + 2.65, 0), height + 3.36)
    _add_lamp(Vector3(-3, 9.85, 0), 10.56)
    set_physics_process(false)

func _add_lamp(at: Vector3, ceiling: float) -> void:
    var lantern := Lantern.instantiate() as Node3D
    lantern.position = at
    lamp_root.add_child(lantern)
    for mesh in lantern.find_children("*", "GeometryInstance3D", true, false):
        mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var top := at.y + .5174
    assert(ceiling > top)
    var rope := MeshInstance3D.new()
    rope.name = "SupportCord"
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
    for portal in [door, maintenance_door]:
        if portal.moving or not is_zero_approx(portal.fraction):
            set_interior_visible(true)

func set_interior_visible(enabled: bool, occupied: bool = false) -> bool:
    if not enabled:
        if occupied:
            return false
        for portal in [door, maintenance_door]:
            if portal == null or portal.moving or not is_zero_approx(portal.fraction):
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
