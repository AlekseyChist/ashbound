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
        push_error("D_BATHS_ROUTE_FAILED target="+str(target)+" actual="+str(actor.position))
        return false
    return true
func run():
    var building=load("res://scenes/buildings/world-architecture-v1/d_baths.tscn").instantiate()
    root.add_child(building)
    var ground=StaticBody3D.new()
    var ground_shape=BoxShape3D.new();ground_shape.size=Vector3(40,.1,40)
    var ground_col=CollisionShape3D.new();ground_col.shape=ground_shape;ground_col.position.y=-1.05
    ground.add_child(ground_col);root.add_child(ground)
    var platform=StaticBody3D.new();var pc=CollisionShape3D.new();var ps=BoxShape3D.new();ps.size=Vector3(3,.2,2);pc.shape=ps;pc.position=Vector3(-4,-.1,4.2);platform.add_child(pc);root.add_child(platform)
    actor=CharacterBody3D.new();actor.collision_layer=2;actor.floor_snap_length=.35
    var capsule=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.75
    var shape=CollisionShape3D.new();shape.shape=capsule
    actor.add_child(shape);root.add_child(actor);actor.position=Vector3(-4,.9,4.5)
    await physics_frame
    var space=actor.get_world_3d().direct_space_state
    for segment in [[Vector3(1.6,3,0),Vector3(1.6,4.55,0)],[Vector3(1.6,4.43,0),Vector3(2.3,4.43,0)]]:
        if not space.intersect_ray(PhysicsRayQueryParameters3D.create(segment[0],segment[1],1)).is_empty():
            push_error("Bath ventilation chamber or side outlet blocked");quit(1);return
    var front_roof=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,5,3),Vector3(0,3,3),1))
    var rear_roof=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,5,-3),Vector3(0,3,-3),1))
    if front_roof.is_empty() or rear_roof.is_empty() or front_roof.position.y-rear_roof.position.y<.08:
        push_error("Bath roof collision does not follow drainage slope");quit(1);return
    for x in [-4.6,4.6]:
        var outlet=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,3.6,-3.3),Vector3(x,3.6,-4.1),1))
        if not outlet.is_empty():push_error("Roof parapet outlet blocked");quit(1);return
    for segment in [[Vector3(-6.2,-.5,-.8),Vector3(-1,-.5,-.8)],[Vector3(0,-.5,.8),Vector3(3.35,-.5,.8)],[Vector3(4,-.5,.8),Vector3(6.2,-.5,.8)]]:
        var passage=space.intersect_ray(PhysicsRayQueryParameters3D.create(segment[0],segment[1],1))
        if not passage.is_empty():
            push_error("Bath covered water duct blocked at "+str(passage.position));quit(1);return
    for point in [Vector3(-3,-.5,-.8),Vector3(1.6,-.5,.8),Vector3(5,-.5,.8)]:
        var sill=space.intersect_ray(PhysicsRayQueryParameters3D.create(point,point-Vector3.UP*.3,1))
        var head=space.intersect_ray(PhysicsRayQueryParameters3D.create(point,point+Vector3.UP*.3,1))
        if sill.is_empty() or head.is_empty() or absf(sill.position.y+.62)>.02 or absf(head.position.y+.38)>.02:
            push_error("Covered duct unsupported or incorrect clear height");quit(1);return
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
    var targets=[Vector3(-4,.875,2.7),Vector3(-3,.875,2.7),Vector3(-1.5,.875,2.7),Vector3(1.5,.875,2.7),Vector3(5.2,.875,2.7),Vector3(5.2,.875,-2.5),Vector3(1.6,.875,-2.5),Vector3(1.6,.875,2.5),Vector3(-1.5,.875,2.5),Vector3(-3,.875,2.5),Vector3(-3,.875,-2.7),Vector3(-4,.875,-2.7),Vector3(-3,.875,-2.7),Vector3(-3,.875,2.5),Vector3(-4,.875,1.1)]
    for target in targets:
        if not await walk(target):quit(1);return
        print("D_BATHS_POINT ",actor.position)
    var pool_targets=[Vector3(-3,.875,2.5),Vector3(-1.5,.875,2.5),Vector3(1.6,.875,2.5),Vector3(1.6,.875,-2.5),Vector3(-.15,.875,-2.5),Vector3(-.15,.175,0),Vector3(-.15,.875,-2.5),Vector3(3.35,.875,-2.5),Vector3(3.35,.175,0),Vector3(3.35,.875,-2.5),Vector3(5.2,.875,-2.5),Vector3(5.2,.875,2.5),Vector3(-1.5,.875,2.5),Vector3(-3,.875,2.5),Vector3(-4,.875,1.1)]
    for target in pool_targets:
        if not await walk(target):quit(1);return
    if not building.door.try_toggle(actor):
        push_error("Interior door closing failed");quit(1);return
    for tick in range(90):await physics_frame
    if not is_zero_approx(building.door.fraction):
        push_error("Interior door not fully closed");quit(1);return
    if not building.door.try_toggle(actor):
        push_error("Interior reopening failed");quit(1);return
    for tick in range(90):await physics_frame
    for target in [Vector3(-3,.875,1.1),Vector3(-3,.875,2.7),Vector3(-4,.875,2.7),Vector3(-4,.875,4.5)]:
        if not await walk(target):quit(1);return
    print("D_BATHS_ROOMS_STAIRS_RETURN_PASS segments=",targets.size()+pool_targets.size()+4)
    quit(0)
