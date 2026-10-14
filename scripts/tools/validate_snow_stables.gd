extends SceneTree
var actor:CharacterBody3D
func _initialize():call_deferred("run")
func walk(target:Vector3)->bool:
    for tick in range(900):
        await physics_frame
        var direction=target-actor.position;direction.y=0
        if direction.length()<.1:break
        actor.velocity=direction.normalized()*2
        actor.velocity.y=0 if actor.is_on_floor() else actor.velocity.y-9.8/60
        actor.move_and_slide()
    if actor.position.distance_to(target)>.2:
        push_error("Stable route blocked target="+str(target)+" actual="+str(actor.position));return false
    return true
func run():
    var stable=load("res://scenes/buildings/world-architecture-v1/s_stables.tscn").instantiate();root.add_child(stable)
    var ground=StaticBody3D.new();var gc=CollisionShape3D.new();var gs=BoxShape3D.new();gs.size=Vector3(40,.1,40);gc.shape=gs;gc.position.y=-.05;ground.add_child(gc);root.add_child(ground)
    actor=CharacterBody3D.new();actor.collision_layer=2;actor.floor_snap_length=.35
    var capsule=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.75
    var shape=CollisionShape3D.new();shape.shape=capsule;actor.add_child(shape);root.add_child(actor);actor.position=Vector3(0,.9,4.8)
    await physics_frame
    if stable.interior_meshes.is_empty() or stable.set_interior_visible(false,true):
        push_error("Stable furniture metadata or occupied guard missing");quit(1);return
    if not stable.set_interior_visible(false) or stable.lamp_assembly.visible or stable.interior_light.visible:
        push_error("Vacant stable did not hide furniture and lamp");quit(1);return
    if stable.door.leaves.size()!=10:push_error("Stable entry leaves incorrect");quit(1);return
    for tick in range(90):
        await physics_frame;actor.velocity=Vector3(0,-2,-2);actor.move_and_slide()
    if actor.position.z<3.6:push_error("Closed stable door did not block");quit(1);return
    if not stable.door.try_toggle(actor):push_error("Stable entry interaction failed");quit(1);return
    for tick in range(90):await physics_frame
    if not stable.interior_visible or stable.set_interior_visible(false):
        push_error("Open stable entry allowed hiding");quit(1);return
    var camera=Camera3D.new();root.add_child(camera);camera.make_current();camera.position=Vector3(100,3,0)
    for tick in range(40):await physics_frame
    if stable.interior_light.visible:push_error("Far stable lamp did not sleep");quit(1);return
    camera.position=Vector3(0,2,0)
    for tick in range(40):await physics_frame
    if not stable.interior_light.visible:push_error("Near stable lamp did not recover");quit(1);return
    stable.set_interior_lights_enabled(false)
    if stable.interior_light.visible:push_error("Stable light override ignored");quit(1);return
    stable.set_interior_lights_enabled(true)
    var points=[Vector3(0,.875,1.7),Vector3(-3,.875,1.7),Vector3(-4,.875,1.7),Vector3(0,.875,1.7),Vector3(3,.875,1.7),Vector3(4,.875,1.7),Vector3(0,.875,1.7),Vector3(0,.875,-1.7),Vector3(-3,.875,-1.7),Vector3(-4,.875,-1.7),Vector3(0,.875,-1.7),Vector3(3,.875,-1.7),Vector3(4,.875,-1.7),Vector3(0,.875,-1.7),Vector3(0,.875,1.3)]
    for point in points:
        if not await walk(point):quit(1);return
    if not stable.door.try_toggle(actor):push_error("Stable inside close failed");quit(1);return
    for tick in range(90):await physics_frame
    if not is_zero_approx(stable.door.fraction):push_error("Stable door remained open");quit(1);return
    if not stable.door.try_toggle(actor):push_error("Stable inside reopen failed");quit(1);return
    for tick in range(90):await physics_frame
    if not await walk(Vector3(0,.875,4.8)):quit(1);return
    print("S_STABLES_FOUR_STALLS_RETURN_PASS segments=16");quit(0)
