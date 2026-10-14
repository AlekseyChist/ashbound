extends SceneTree
var actor:CharacterBody3D
func _initialize():call_deferred("run")
func walk(target:Vector3)->bool:
    for tick in range(900):
        await physics_frame
        var d=target-actor.position;d.y=0
        if d.length()<.1:break
        actor.velocity=d.normalized()*2
        actor.velocity.y=0 if actor.is_on_floor() else actor.velocity.y-9.8/60
        actor.move_and_slide()
    if actor.position.distance_to(target)>.2:
        push_error("DORM_ROUTE_FAILED target="+str(target)+" actual="+str(actor.position));return false
    return true
func run():
    var b=load("res://scenes/buildings/world-architecture-v1/s_apprentice_dorm.tscn").instantiate();root.add_child(b)
    var ground=StaticBody3D.new();var col=CollisionShape3D.new();var floor_shape=BoxShape3D.new()
    floor_shape.size=Vector3(40,.1,40);col.shape=floor_shape;col.position.y=-.05;ground.add_child(col);root.add_child(ground)
    actor=CharacterBody3D.new();actor.collision_layer=2;actor.floor_snap_length=.35
    var capsule=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.75
    var shape=CollisionShape3D.new();shape.shape=capsule;actor.add_child(shape);root.add_child(actor);actor.position=Vector3(0,.9,4.2)
    await physics_frame
    if b.door.leaves.size()!=5 or b.interior_meshes.is_empty():push_error("Dorm door/furniture missing");quit(1);return
    for tick in range(80):
        await physics_frame
        actor.velocity=Vector3(0,-2,-2);actor.move_and_slide()
    if actor.position.z<2.05:push_error("Closed entry allows passage");quit(1);return
    actor.position=Vector3(0,.9,4.2);await physics_frame
    if b.set_interior_visible(false,true) or not b.set_interior_visible(false):push_error("Visibility guards failed");quit(1);return
    if not b.door.try_toggle(actor):push_error("Outside door toggle failed");quit(1);return
    for tick in range(100):await physics_frame
    if not is_equal_approx(b.door.fraction,1.0) or not b.interior_visible or b.set_interior_visible(false):push_error("Door/open interior guard failed");quit(1);return
    var targets=[Vector3(0,.875,1.0),Vector3(0,.875,-.2),Vector3(-2.5,.875,-.2),Vector3(0,.875,-.2),Vector3(2.5,.875,-.2),Vector3(0,.875,-.2),Vector3(0,.875,0),Vector3(-2,.875,.9),Vector3(0,.875,0),Vector3(2.05,.875,1.0),Vector3(0,.875,0),Vector3(0,.875,1.0)]
    for target in targets:
        if not await walk(target):quit(1);return
    if not b.door.try_toggle(actor):push_error("Inside close failed");quit(1);return
    for tick in range(100):await physics_frame
    # The small room's initial waiting point is inside the leaf's swing arc.
    # It must stop on the actor and finish closing once the actor steps back.
    if not b.door.blocked or is_zero_approx(b.door.fraction):push_error("Door closed through occupant in swing arc");quit(1);return
    if not await walk(Vector3(0,.875,0)):quit(1);return
    for tick in range(100):await physics_frame
    if not is_zero_approx(b.door.fraction) or not b.door.try_toggle(actor):push_error("Inside reopen failed");quit(1);return
    for tick in range(100):await physics_frame
    if not await walk(Vector3(0,.875,4.2)):quit(1);return
    var space=b.get_world_3d().direct_space_state
    var mouth=PhysicsRayQueryParameters3D.create(Vector3(-3,8,.9),Vector3(-3,5.9,.9),1)
    if not space.intersect_ray(mouth).is_empty():push_error("Chimney mouth blocked");quit(1);return
    var camera=Camera3D.new();root.add_child(camera);camera.make_current();camera.position=Vector3(100,3,0)
    for tick in range(40):await physics_frame
    for light in b.interior_lights:
        if light.visible:push_error("Far interior light awake");quit(1);return
    camera.position=Vector3(0,1.6,0)
    for tick in range(40):await physics_frame
    for light in b.interior_lights:
        if not light.visible:push_error("Near interior light asleep");quit(1);return
    b.set_interior_lights_enabled(false)
    for light in b.interior_lights:
        if light.visible:push_error("World light override ignored");quit(1);return
    print("DORM_PASS legs=14 beds=3 workplaces=2 door_both_sides=true occupant_sweep_guard=true chimney_mouth=true visibility_and_lights=true")
    quit()
