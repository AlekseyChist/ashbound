extends SceneTree
var actor: CharacterBody3D
func _initialize(): call_deferred("run")
func walk(target: Vector3) -> bool:
    for tick in range(900):
        await physics_frame
        var direction=target-actor.position;direction.y=0
        if direction.length()<.1:break
        actor.velocity=direction.normalized()*2
        actor.velocity.y=0 if actor.is_on_floor() else actor.velocity.y-9.8/60
        actor.move_and_slide()
    if actor.position.distance_to(target)>.2:
        push_error("S_KITCHEN_ROUTE_FAILED target="+str(target)+" actual="+str(actor.position))
        return false
    return true
func run():
    var building=load("res://scenes/buildings/world-architecture-v1/s_porters_kitchen.tscn").instantiate()
    root.add_child(building)
    var ground=StaticBody3D.new()
    var ground_shape=BoxShape3D.new();ground_shape.size=Vector3(40,.1,40)
    var ground_col=CollisionShape3D.new();ground_col.shape=ground_shape;ground_col.position.y=-.05
    ground.add_child(ground_col);root.add_child(ground)
    actor=CharacterBody3D.new();actor.collision_layer=2;actor.floor_snap_length=.35
    var capsule=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.75
    var shape=CollisionShape3D.new();shape.shape=capsule
    actor.add_child(shape);root.add_child(actor);actor.position=Vector3(0,.9,4)
    await physics_frame
    var space=actor.get_world_3d().direct_space_state
    var mouth=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(2.7,7.5,-1.5),Vector3(2.7,5.8,-1.5),1))
    if mouth.is_empty() or absf(mouth.position.y-6.2)>.02:
        push_error("Kitchen chimney mouth blocked");quit(1);return
    var stove=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(1,.7,-1.5),Vector3(3,.7,-1.5),1))
    if stove.is_empty() or absf(stove.position.x-2.05)>.02:
        push_error("Kitchen stove footprint lacks collision");quit(1);return
    if building.interior_meshes.is_empty() or building.set_interior_visible(false,true):
        push_error("Interior metadata or occupancy guard missing");quit(1);return
    if not building.set_interior_visible(false):
        push_error("Closed vacant interior cannot hide");quit(1);return
    if building.lamp_root.visible or building.interior_lights.size()!=2:
        push_error("Hidden lamp assembly or source count incorrect");quit(1);return
    for light in building.interior_lights:
        if light.visible:
            push_error("Hidden room light remained enabled");quit(1);return
    for tick in range(100):
        await physics_frame
        actor.velocity=Vector3(0,-2,-2);actor.move_and_slide()
    if actor.position.z<3.1:
        push_error("Closed entry did not block actor");quit(1);return
    if not building.door.try_toggle(actor):
        push_error("Entry interaction failed");quit(1);return
    for tick in range(90):await physics_frame
    if not building.interior_visible or building.set_interior_visible(false):
        push_error("Open portal visibility guard failed");quit(1);return
    var camera=Camera3D.new();root.add_child(camera);camera.make_current()
    camera.position=Vector3(100,5,0)
    for tick in range(40):await physics_frame
    for light in building.interior_lights:
        if light.visible:
            push_error("Distant room light did not sleep");quit(1);return
    camera.position=Vector3(0,2,0)
    for tick in range(40):await physics_frame
    for light in building.interior_lights:
        if not light.visible:
            push_error("Nearby room light did not recover");quit(1);return
    building.set_interior_lights_enabled(false)
    for light in building.interior_lights:
        if light.visible:
            push_error("Lighting override ignored");quit(1);return
    building.set_interior_lights_enabled(true)
    var targets=[Vector3(0,.875,1.9),Vector3(0,.875,0),Vector3(-1,.875,0),Vector3(-2.2,.875,0),Vector3(0,.875,0),Vector3(0,.875,-1.5),Vector3(1.5,.875,-1.5),Vector3(0,.875,-1.5),Vector3(0,.875,-2.2),Vector3(0,.875,0),Vector3(1.2,.875,0),Vector3(2.4,.875,0),Vector3(1.2,.875,0),Vector3(0,.875,0),Vector3(0,.875,1.1)]
    for target in targets:
        if not await walk(target):quit(1);return
        print("S_KITCHEN_POINT ",actor.position)
    if not building.door.try_toggle(actor):
        push_error("Interior door closing failed");quit(1);return
    for tick in range(90):await physics_frame
    if not is_zero_approx(building.door.fraction):
        push_error("Interior door not fully closed");quit(1);return
    if not building.door.try_toggle(actor):
        push_error("Interior reopening failed");quit(1);return
    for tick in range(90):await physics_frame
    if not await walk(Vector3(0,.875,4)):quit(1);return
    print("S_KITCHEN_ROOMS_STAIRS_RETURN_PASS segments=",targets.size()+1)
    quit(0)
