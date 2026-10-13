extends SceneTree
var actor: CharacterBody3D
func _initialize():call_deferred("run")
func walk(target:Vector3) -> bool:
    for tick in range(900):
        await physics_frame
        var direction=target-actor.position;direction.y=0
        if direction.length()<.08:break
        actor.velocity=direction.normalized()*2
        actor.velocity.y=0 if actor.is_on_floor() else actor.velocity.y-9.8/60
        actor.move_and_slide()
    if actor.position.distance_to(target)>.15:
        push_error("DP_ROUTE_FAILED target="+str(target)+" actual="+str(actor.position));return false
    return true
func run():
    var house=load("res://scenes/buildings/world-architecture-v1/d_pilgrim.tscn").instantiate()
    root.add_child(house)
    var ground=StaticBody3D.new();var floor_shape=BoxShape3D.new()
    floor_shape.size=Vector3(30,.1,30)
    var floor_col=CollisionShape3D.new();floor_col.shape=floor_shape;floor_col.position.y=-.05
    ground.add_child(floor_col);root.add_child(ground)
    actor=CharacterBody3D.new();actor.collision_layer=2;actor.floor_snap_length=.35
    var shape=CollisionShape3D.new();var capsule=CapsuleShape3D.new()
    capsule.radius=.3;capsule.height=1.75;shape.shape=capsule
    actor.add_child(shape);root.add_child(actor);actor.position=Vector3(0,.9,5)
    await physics_frame
    var space=actor.get_world_3d().direct_space_state
    var mouth=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(4.8,6,2.5),Vector3(4.8,3,2.5),1))
    if mouth.is_empty() or absf(mouth.position.y-3.7)>.02:
        push_error("Cooking flue blocked by roofing");quit(1);return
    if house.door.leaves.size()!=5 or house.service_door.leaves.size()!=5:
        push_error("Portal leaf groups not independent");quit(1);return
    if house.interior_meshes.is_empty() or house.set_interior_visible(false,true):
        push_error("Furniture metadata or occupancy guard failed");quit(1);return
    if not house.set_interior_visible(false):
        push_error("Closed empty furniture cannot hide");quit(1);return
    if house.lamp_root.visible or house.lights.size()!=2:
        push_error("Lamp assembly visibility/count failed");quit(1);return
    for tick in range(100):
        await physics_frame
        actor.velocity=Vector3(0,-2,-2);actor.move_and_slide()
    if actor.position.z<3.5:
        push_error("Closed entry allowed passage");quit(1);return
    if not house.door.try_toggle(actor):
        push_error("Entry interaction failed");quit(1);return
    for tick in range(90):await physics_frame
    if not is_zero_approx(house.service_door.fraction):
        push_error("Entry opened service leaf");quit(1);return
    if not house.interior_visible or house.set_interior_visible(false):
        push_error("Entry portal visibility guard failed");quit(1);return
    var camera=Camera3D.new();root.add_child(camera);camera.make_current()
    camera.position=Vector3(100,3,0)
    for tick in range(40):await physics_frame
    for light in house.lights:
        if light.visible:
            push_error("Distant lamp stayed active");quit(1);return
    camera.position=Vector3(0,1.6,0)
    for tick in range(40):await physics_frame
    for light in house.lights:
        if not light.visible:
            push_error("Nearby lamp did not recover");quit(1);return
    house.set_interior_lights_enabled(false)
    for light in house.lights:
        if light.visible:
            push_error("World lighting override ignored");quit(1);return
    house.set_interior_lights_enabled(true)
    for target in [Vector3(0,.875,.25),Vector3(-2,.875,.25),Vector3(-2,.875,2.3),Vector3(-2,.875,-2.3),Vector3(-2,.875,.25),Vector3(0,.875,.25),Vector3(3,.875,.25),Vector3(3,.875,-2.4),Vector3(3,.875,.25),Vector3(0,.875,.25),Vector3(0,.875,-1.6)]:
        if not await walk(target):quit(1);return
    if not house.service_door.try_toggle(actor):
        push_error("Service door interior interaction failed");quit(1);return
    for tick in range(90):await physics_frame
    if not is_equal_approx(house.door.fraction,1):
        push_error("Service door changed entry leaf");quit(1);return
    if not await walk(Vector3(0,.875,-5)):quit(1);return
    if not house.service_door.try_toggle(actor):
        push_error("Service exterior closing failed");quit(1);return
    for tick in range(90):await physics_frame
    if not is_zero_approx(house.service_door.fraction):
        push_error("Service closure failed");quit(1);return
    if not house.service_door.try_toggle(actor):
        push_error("Service exterior reopening failed");quit(1);return
    for tick in range(90):await physics_frame
    if not await walk(Vector3(0,.875,1.6)):quit(1);return
    if not house.door.try_toggle(actor):
        push_error("Entry interior closing failed");quit(1);return
    for tick in range(90):await physics_frame
    if house.set_interior_visible(false):
        push_error("Open service exit failed to protect furniture");quit(1);return
    if not house.door.try_toggle(actor):
        push_error("Entry interior reopening failed");quit(1);return
    for tick in range(90):await physics_frame
    if not await walk(Vector3(0,.875,5)):quit(1);return
    print("D_P_BOTH_PORTALS_ROOMS_RETURN_PASS")
    quit(0)
