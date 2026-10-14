extends Node3D
const Door = preload("res://scripts/world/village_door.gd")
const Lantern = preload("res://assets/props/tavern-v1/wooden_lantern_01.glb")
var door: Node3D
var service_door: Node3D
var interior_meshes: Array[MeshInstance3D] = []
var interior_visible := true
var lamp_root: Node3D
var lights: Array[OmniLight3D] = []
var lights_enabled := true
var light_check := 0.0
func _ready() -> void:
    var front=find_child("EntryPortal",true,false) as Node3D
    var rear=find_child("ServicePortal",true,false) as Node3D
    door=Door.new();door.name="Door";front.add_child(door)
    door.configure(front,str(get_instance_id())+":entry",Vector3(0,0,3.3))
    service_door=Door.new();service_door.name="ServiceDoor";rear.add_child(service_door)
    service_door.configure(rear,str(get_instance_id())+":service",Vector3(0,0,3.3))
    for mesh in find_children("*", "MeshInstance3D", true, false):
        if mesh.get_meta("extras", {}).get("part_role", "") == "interior_furniture":
            interior_meshes.append(mesh)
    lamp_root=Node3D.new();lamp_root.name="RoomLanterns";add_child(lamp_root)
    for at in [Vector3(-3,2.3,0),Vector3(3,2.3,0)]:
        var lantern=Lantern.instantiate() as Node3D
        lantern.position=at;lamp_root.add_child(lantern)
        for mesh in lantern.find_children("*","GeometryInstance3D",true,false):
            mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        var rope=MeshInstance3D.new();var cord=BoxMesh.new()
        cord.size=Vector3(.02,3.04-(at.y+.5174),.02);rope.mesh=cord
        rope.position=Vector3(at.x,(3.04+at.y+.5174)*.5,at.z)
        var material=StandardMaterial3D.new();material.albedo_color=Color(.25,.18,.1)
        rope.material_override=material;lamp_root.add_child(rope)
        var light=OmniLight3D.new();light.position=at+Vector3(0,.18,0)
        light.light_color=Color(1,.76,.5);light.light_energy=.8
        light.omni_range=6;light.shadow_enabled=true
        lamp_root.add_child(light);lights.append(light)
    set_physics_process(false)
func _process(delta: float) -> void:
    light_check+=delta
    if light_check<.5:return
    light_check=0
    var camera=get_viewport().get_camera_3d()
    for light in lights:
        light.visible=lights_enabled and interior_visible and (camera==null or camera.global_position.distance_to(light.global_position)<45)
func set_interior_lights_enabled(enabled:bool) -> void:
    lights_enabled=enabled
    for light in lights:light.visible=enabled and interior_visible
func _physics_process(_delta: float) -> void:
    for portal in [door,service_door]:
        if portal.moving or not is_zero_approx(portal.fraction):
            set_interior_visible(true)
            break
func set_interior_visible(enabled: bool, occupied: bool = false) -> bool:
    if not enabled:
        if occupied:return false
        for portal in [door,service_door]:
            if portal == null or portal.moving or not is_zero_approx(portal.fraction):return false
    for mesh in interior_meshes:mesh.visible=enabled
    interior_visible=enabled
    lamp_root.visible=enabled
    if not enabled:
        for light in lights:light.visible=false
    set_physics_process(not enabled)
    return true
