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
        push_error("S_LIBRARY_ROUTE_FAILED target="+str(target)+" actual="+str(actor.position))
        return false
    return true
func run():
    var building=load("res://scenes/buildings/world-architecture-v1/s_library.tscn").instantiate()
    root.add_child(building)
    var ground=StaticBody3D.new()
    var ground_shape=BoxShape3D.new();ground_shape.size=Vector3(40,.1,40)
    var ground_col=CollisionShape3D.new();ground_col.shape=ground_shape;ground_col.position.y=-3.4
    ground.add_child(ground_col);root.add_child(ground)
    var platform=StaticBody3D.new()
    var slab=CollisionShape3D.new();var slab_shape=BoxShape3D.new();slab_shape.size=Vector3(3,.2,2);slab.shape=slab_shape;slab.position=Vector3(0,-.1,4.2);platform.add_child(slab);root.add_child(platform)
    var lower_platform=StaticBody3D.new();var lower_col=CollisionShape3D.new();var lower_shape=BoxShape3D.new();lower_shape.size=Vector3(3,.2,3);lower_col.shape=lower_shape;lower_col.position=Vector3(0,-3.3,-4.7);lower_platform.add_child(lower_col);root.add_child(lower_platform)
    actor=CharacterBody3D.new();actor.collision_layer=2;actor.floor_snap_length=.35
    var capsule=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.75
    var shape=CollisionShape3D.new();shape.shape=capsule
    actor.add_child(shape);root.add_child(actor);actor.position=Vector3(0,.9,4.5)
    await physics_frame
    if building.door.leaves.size()!=8 or building.lab_door.leaves.size()!=8:
        push_error("Library portals not independent");quit(1);return
    var space=actor.get_world_3d().direct_space_state
    var mouth=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(1.1,8,.65),Vector3(1.1,6,.65),1))
    if mouth.is_empty() or absf(mouth.position.y-6.7)>.02:
        push_error("Library chimney mouth obstructed");quit(1);return
    for height in [.7,-2.5]:
        var stove=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,height,.65),Vector3(1.4,height,.65),1))
        if stove.is_empty() or absf(stove.position.x-.575)>.02:
            push_error("Library stove lacks collision");quit(1);return
    if building.interior_meshes.is_empty() or building.set_interior_visible(false,true):
        push_error("Interior metadata or occupancy guard missing");quit(1);return
    if not building.set_interior_visible(false):
        push_error("Closed vacant interior cannot hide");quit(1);return
    if building.lamp_root.visible or building.interior_lights.size()!=3:
        push_error("Hidden lamp assembly or source count incorrect");quit(1);return
    for light in building.interior_lights:
        if light.visible:
            push_error("Hidden room light remained enabled");quit(1);return
    for tick in range(100):
        await physics_frame
        actor.velocity=Vector3(0,-2,-2);actor.move_and_slide()
    if actor.position.z<3.6:
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
    var targets=[Vector3(0,.875,2),Vector3(0,.875,.5),Vector3(-1,.875,.5),Vector3(-1,.875,-.5),Vector3(0,.875,-.5),Vector3(0,.875,-2.4),Vector3(2.7,.875,-2.4),Vector3(2.7,.875,-1.05),Vector3(2.7,-.725,1.75),Vector3(4.05,-.725,1.75),Vector3(4.05,-2.325,-1.05),Vector3(4.05,-2.325,-2.4),Vector3(0,-2.325,-2.4),Vector3(-1,-2.325,-2.4),Vector3(-1,-2.325,2),Vector3(0,-2.325,2),Vector3(0,-2.325,-2.4),Vector3(4.05,-2.325,-2.4),Vector3(4.05,-2.325,-1.05),Vector3(4.05,-.725,1.75),Vector3(2.7,-.725,1.75),Vector3(2.7,.875,-1.05),Vector3(2.7,.875,-2.4),Vector3(0,.875,-2.4),Vector3(0,.875,1.3)]
    var lab_tested=false
    for target in targets:
        if not await walk(target):quit(1);return
        print("S_LIBRARY_POINT ",actor.position)
        if not lab_tested and target.distance_to(Vector3(0,-2.325,-2.4))<.01:
            lab_tested=true
            if not building.lab_door.try_toggle(actor):push_error("Lab portal interaction failed");quit(1);return
            for tick in range(90):await physics_frame
            if not await walk(Vector3(0,-2.325,-5.4)):quit(1);return
            if not building.lab_door.try_toggle(actor):push_error("Lab portal outside close failed");quit(1);return
            for tick in range(90):await physics_frame
            if not is_zero_approx(building.lab_door.fraction):push_error("Lab portal did not close");quit(1);return
            if not building.lab_door.try_toggle(actor):push_error("Lab portal outside reopen failed");quit(1);return
            for tick in range(90):await physics_frame
            if not await walk(Vector3(0,-2.325,-1.2)):quit(1);return
            if not building.lab_door.try_toggle(actor):push_error("Lab portal inside close failed");quit(1);return
            for tick in range(90):await physics_frame
            if not is_zero_approx(building.lab_door.fraction):push_error("Lab portal inside closing blocked");quit(1);return
            if not await walk(target):quit(1);return
    if not building.door.try_toggle(actor):
        push_error("Interior door closing failed");quit(1);return
    for tick in range(90):await physics_frame
    if not is_zero_approx(building.door.fraction):
        push_error("Interior door not fully closed");quit(1);return
    var guard_route=[Vector3(0,.875,-2.4),Vector3(2.7,.875,-2.4),Vector3(2.7,.875,-1.05),Vector3(2.7,-.725,1.75),Vector3(4.05,-.725,1.75),Vector3(4.05,-2.325,-1.05),Vector3(4.05,-2.325,-2.4),Vector3(0,-2.325,-1.2)]
    for target in guard_route:
        if not await walk(target):quit(1);return
    if building.set_interior_visible(false,true):
        push_error("Occupied lower hall allowed hiding");quit(1);return
    # Exercise the caller's vacant state explicitly; collisions stay live.
    if not building.set_interior_visible(false):
        push_error("Both closed portals prevented vacant hide");quit(1);return
    if not building.lab_door.try_toggle(actor):
        push_error("Hidden lower portal interaction failed");quit(1);return
    for tick in range(90):await physics_frame
    if not building.interior_visible or building.set_interior_visible(false):
        push_error("Rear-only open portal allowed hidden interior");quit(1);return
    if not building.lab_door.try_toggle(actor):
        push_error("Rear-only guard closing failed");quit(1);return
    for tick in range(90):await physics_frame
    if not is_zero_approx(building.lab_door.fraction):
        push_error("Rear-only guard door still open");quit(1);return
    var guard_return=[Vector3(0,-2.325,-2.4),Vector3(4.05,-2.325,-2.4),Vector3(4.05,-2.325,-1.05),Vector3(4.05,-.725,1.75),Vector3(2.7,-.725,1.75),Vector3(2.7,.875,-1.05),Vector3(2.7,.875,-2.4),Vector3(0,.875,-2.4),Vector3(0,.875,1.3)]
    for target in guard_return:
        if not await walk(target):quit(1);return
    if not building.door.try_toggle(actor):
        push_error("Interior reopening failed");quit(1);return
    for tick in range(90):await physics_frame
    if not await walk(Vector3(0,.875,4.5)):quit(1);return
    print("S_LIBRARY_ROOMS_STAIRS_RETURN_PASS segments=",targets.size()+4+guard_route.size()+guard_return.size())
    quit(0)
