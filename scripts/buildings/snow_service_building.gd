extends Node3D
## Self-contained service runtime; accepted VillageDoor and lantern only.
const Door = preload("res://scripts/world/village_door.gd")
const Lantern = preload("res://assets/props/tavern-v1/wooden_lantern_01.glb")
var door: Node3D
var entry_anchor: Node3D
var wall_width := 0.0
var wall_depth := 0.0
var ceiling_height := 3.1
var enterable := true
var kind := ""
var interior_meshes: Array[MeshInstance3D] = []
var interior_visible := true
var lights_enabled := true
var lamp_assembly: Node3D
var interior_light: OmniLight3D
var light_check := 0.0
var lamp_z := 0.0
var lamp_x := 0.0
func _ready() -> void:
    entry_anchor = find_child("EntryAnchor",true,false) as Node3D
    assert(entry_anchor != null,"Authored service entry metadata missing")
    var facts: Dictionary = entry_anchor.get_meta("extras",{})
    wall_width = float(facts["wall_width"])
    wall_depth = float(facts["wall_depth"])
    ceiling_height = float(facts["ceiling_height"])
    enterable = bool(facts["enter"])
    kind = str(facts["kind"])
    lamp_z = float(facts.get("lamp_z",0.0))
    lamp_x = float(facts.get("lamp_x",0.0))
    var entry_point := to_local(entry_anchor.global_position)
    entry_anchor.reparent(self)
    if enterable:
        door = Door.new(); door.name = "Door"; add_child(door)
        door.configure(self,str(get_instance_id()),entry_point)
    for mesh in find_children("*","MeshInstance3D",true,false):
        if mesh.get_meta("extras",{}).get("part_role","") == "interior_furniture":
            interior_meshes.append(mesh)
    if enterable: _build_lamp()
    set_physics_process(false)
func _build_lamp() -> void:
    lamp_assembly = Node3D.new();lamp_assembly.name = "ServiceLantern";add_child(lamp_assembly)
    lamp_assembly.position = Vector3(lamp_x,0,lamp_z)
    var lantern := Lantern.instantiate() as Node3D
    lantern.position = Vector3(0,ceiling_height-.70,0);lamp_assembly.add_child(lantern)
    for mesh in lantern.find_children("*","GeometryInstance3D",true,false):
        mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var cord := MeshInstance3D.new();cord.name="SupportCord"
    var shape := BoxMesh.new();shape.size=Vector3(.02,.70-.13-.5174,.02)
    cord.mesh=shape;cord.position=Vector3(0,(ceiling_height-.13+ceiling_height-.70+.5174)/2,0)
    var material := StandardMaterial3D.new();material.albedo_color=Color(.25,.18,.1)
    cord.material_override=material;lamp_assembly.add_child(cord)
    interior_light=OmniLight3D.new();interior_light.name="LanternLight"
    interior_light.position=Vector3(0,ceiling_height-.52,0)
    interior_light.light_color=Color(1,.76,.5);interior_light.light_energy=.8
    interior_light.omni_range=5;interior_light.shadow_enabled=true
    lamp_assembly.add_child(interior_light);_update_light_visibility()
func _process(delta: float) -> void:
    if interior_light == null: return
    light_check += delta
    if light_check >= .5:
        light_check=0;_update_light_visibility()
func _update_light_visibility() -> void:
    if interior_light == null: return
    var camera := get_viewport().get_camera_3d()
    interior_light.visible=lights_enabled and interior_visible and (camera == null or camera.global_position.distance_to(interior_light.global_position)<45)
func set_interior_lights_enabled(enabled: bool) -> void:
    lights_enabled=enabled;_update_light_visibility()
func _physics_process(_delta: float) -> void:
    if door != null and (door.moving or not is_zero_approx(door.fraction)):
        set_interior_visible(true)
func set_interior_visible(enabled: bool, occupied: bool = false) -> bool:
    # Open wood stores expose their real goods directly to the street at any distance.
    if not enterable and not enabled: return false
    if not enabled and (occupied or door == null or door.moving or not is_zero_approx(door.fraction)): return false
    for mesh in interior_meshes: mesh.visible=enabled
    interior_visible=enabled
    if lamp_assembly != null: lamp_assembly.visible=enabled
    _update_light_visibility();set_physics_process(enterable and not enabled)
    return true
