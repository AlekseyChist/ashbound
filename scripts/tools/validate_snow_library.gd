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
    actor=CharacterBody3D.new();actor.collision_layer=2;actor.floor_snap_length=.35
    var capsule=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.75
    var shape=CollisionShape3D.new();shape.shape=capsule
    actor.add_child(shape);root.add_child(actor);actor.position=Vector3(0,.9,4.5)
    await physics_frame
    var space=actor.get_world_3d().direct_space_state
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
    for target in targets:
        if not await walk(target):quit(1);return
        print("S_LIBRARY_POINT ",actor.position)
    if not building.door.try_toggle(actor):
        push_error("Interior door closing failed");quit(1);return
    for tick in range(90):await physics_frame
    if not is_zero_approx(building.door.fraction):
        push_error("Interior door not fully closed");quit(1);return
    if not building.door.try_toggle(actor):
        push_error("Interior reopening failed");quit(1);return
    for tick in range(90):await physics_frame
    if not await walk(Vector3(0,.875,4.5)):quit(1);return
    print("S_LIBRARY_ROOMS_STAIRS_RETURN_PASS segments=",targets.size()+1)
    quit(0)
