extends Node3D
## Bounded architectural asset. City placement and weather remain with the world.
const Door = preload("res://scripts/world/village_door.gd")
const Lantern = preload("res://assets/props/tavern-v1/wooden_lantern_01.glb")
const FLOOR_HEIGHTS := [0.0, 3.6, 7.2, 10.8, 14.4, 18.0, 21.6, 25.2]
const MAX_VISIBLE_LIGHTS := 8
var door: Node3D
var maintenance_door: Node3D
var interior_meshes: Array[MeshInstance3D] = []
var interior_visible := true
var lamp_root: Node3D
var interior_lights: Array[OmniLight3D] = []
var lights_enabled := true
var light_check := 0.0
var warm_window: MeshInstance3D
var window_material: StandardMaterial3D
var window_daylight := 1.0
var atmosphere: Node

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
    for node in find_children("*", "MeshInstance3D", true, false):
        if node.get_meta("extras", {}).get("part_role", "") == "cell_window":
            warm_window = node
    assert(warm_window != null, "Cell window beacon must be part of the architecture")
    window_material = StandardMaterial3D.new()
    window_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    window_material.roughness = .95
    window_material.emission = Color(1, .34, .08)
    warm_window.material_override = window_material
    warm_window.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    set_window_daylight(1.0)
    lamp_root = Node3D.new()
    lamp_root.name = "InteriorLanterns"
    add_child(lamp_root)
    for height in FLOOR_HEIGHTS:
        var upper := is_equal_approx(height,25.2)
        _add_lamp(Vector3(-1, height + (2.35 if upper else 2.65), 0), 28.5325 if upper else height + 3.36)
        # Eleven-metre rooms need their landing edge within useful falloff.
        interior_lights.back().light_energy=1.2
        interior_lights.back().omni_range=9.0
    _add_lamp(Vector3(-3, 9.85, 0), 10.56)
    # Each switchback is separated from the main room by its masonry spine.
    # Hang over the turn, supported by the next turn or the real board lid.
    for height in FLOOR_HEIGHTS.slice(0,7):
        _add_lamp(Vector3(3.4,height+3.9,-1.6),28.6205 if is_equal_approx(height,21.6) else height+5.16)
    for flight in range(8):
        var outward:Vector3=[Vector3.RIGHT,Vector3.FORWARD,Vector3.LEFT,Vector3.BACK][flight%4]
        _add_wall_lamp(outward,flight*3.6+3.75)
    # The repair ring runs beyond the roof; attach to surviving crown masonry,
    # keeping the low fixtures beside the inner edge of its clear walking lane.
    _add_wall_lamp(Vector3.RIGHT,30.7,Vector3(0,0,-5.15),5.7)
    _add_wall_lamp(Vector3.BACK,30.2,Vector3(4.5,0,0),5.7)
    _add_wall_lamp(Vector3.LEFT,30.7,Vector3(0,0,5.0),5.7)
    _add_wall_lamp(Vector3.LEFT,30.2,Vector3(0,0,-5.0),5.7)
    _add_wall_lamp(Vector3.RIGHT,30.2,Vector3(0,0,2.8),5.7)
    _add_lamp(Vector3(0,30.9,-6.25),31.51)
    _update_lights()
    set_physics_process(false)

func _add_lamp(at: Vector3, ceiling: float, wall_normal:Vector3=Vector3.ZERO) -> void:
    var lantern := Lantern.instantiate() as Node3D
    lantern.position = at
    lamp_root.add_child(lantern)
    for mesh in lantern.find_children("*", "GeometryInstance3D", true, false):
        mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var top := at.y + .5174
    assert(ceiling > top)
    var rope := MeshInstance3D.new()
    rope.name = ("SupportCord" if wall_normal==Vector3.ZERO else "WallHanger")+str(interior_lights.size())
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

func _add_wall_lamp(outward:Vector3,height:float,along:Vector3=Vector3.ZERO,reach:float=5.85)->void:
    var at:=outward*reach+along+Vector3.UP*height
    var hook_top:=height+.6174
    _add_lamp(at,hook_top,outward)
    var bracket:=MeshInstance3D.new();bracket.name="WallBracket"+str(interior_lights.size())
    var shape:=BoxMesh.new()
    var length:=reach+.03-5.45
    shape.size=Vector3(length,.07,.07) if absf(outward.x)>.5 else Vector3(.07,.07,length)
    bracket.mesh=shape;bracket.position=outward*((reach+.03+5.45)*.5)+along+Vector3.UP*hook_top
    var metal:=StandardMaterial3D.new();metal.albedo_color=Color(.09,.085,.075);metal.roughness=.85
    bracket.material_override=metal;lamp_root.add_child(bracket)
    interior_lights.back().light_energy=1.2
    var contact:=StaticBody3D.new();contact.name="WallLanternContact"+str(interior_lights.size())
    contact.collision_layer=1|Door.OBSTACLE_LAYER
    var collision:=CollisionShape3D.new();var bounds:=BoxShape3D.new();bounds.size=Vector3(.36,.54,.36)
    collision.shape=bounds;contact.add_child(collision);contact.position=at+Vector3(0,.25,0);add_child(contact)

func _process(delta: float) -> void:
    light_check += delta
    if light_check < .5:
        return
    light_check = 0
    # The existing settlement creates Atmosphere after child buildings are ready.
    # Retry the sibling lookup without loading its calendar/weather dependencies.
    if not is_instance_valid(atmosphere):
        var ancestor := get_parent()
        while ancestor != null:
            var candidate := ancestor.get_node_or_null("Atmosphere")
            if candidate != null:
                for property in candidate.get_property_list():
                    if property.name == "daylight":
                        atmosphere = candidate
                        break
            if is_instance_valid(atmosphere): break
            ancestor = ancestor.get_parent()
    if is_instance_valid(atmosphere):
        set_window_daylight(float(atmosphere.get("daylight")))
    _update_lights()

func _update_lights()->void:
    var camera := get_viewport().get_camera_3d()
    var observer:=camera.global_position if camera!=null else global_position
    var near:Array[Dictionary]=[]
    for light in interior_lights:
        light.visible=false
        var distance:=observer.distance_squared_to(light.global_position)
        if lights_enabled and interior_visible and distance<45*45:
            near.append({"light":light,"distance":distance})
    near.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.distance<b.distance)
    for i in range(mini(MAX_VISIBLE_LIGHTS,near.size())):near[i].light.visible=true

func set_interior_lights_enabled(enabled: bool) -> void:
    lights_enabled = enabled
    set_window_daylight(window_daylight)
    _update_lights()

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
    _update_lights()
    return true

## New bounded rendering interface. The existing Atmosphere.daylight overrides it
## when present; standalone previews can explicitly supply daylight in [0,1].
func set_window_daylight(value: float) -> void:
    if not is_finite(value): return
    window_daylight = clampf(value, 0.0, 1.0)
    if window_material == null: return
    var night := (1.0 - smoothstep(.12, .45, window_daylight)) if lights_enabled else 0.0
    window_material.albedo_color = Color(.18,.11,.04,.55).lerp(Color(.72,.27,.06,.9), night)
    window_material.emission_enabled = night > .01
    window_material.emission_energy_multiplier = 1.8 * night
