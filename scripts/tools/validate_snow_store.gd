extends SceneTree
func _initialize(): call_deferred("run")
func run():
    var stage=Node3D.new()
    root.add_child(stage)
    var house=load("res://scenes/buildings/world-architecture-v1/s_caravan_store.tscn").instantiate()
    stage.add_child(house)
    var ground=StaticBody3D.new()
    var ground_col=CollisionShape3D.new()
    var ground_shape=BoxShape3D.new()
    ground_shape.size=Vector3(40,.1,40)
    ground_col.shape=ground_shape;ground_col.position.y=-.05
    ground.add_child(ground_col);stage.add_child(ground)
    var actor=CharacterBody3D.new()
    actor.collision_layer=2
    var col=CollisionShape3D.new()
    var capsule=CapsuleShape3D.new()
    capsule.radius=.3;capsule.height=1.75
    col.shape=capsule;actor.add_child(col);stage.add_child(actor)
    actor.position=Vector3(0,.875,5.3)
    await physics_frame
    if house.interior_meshes.is_empty():
        push_error("Interior visibility metadata missing");quit(1);return
    if house.set_interior_visible(false, true):
        push_error("Occupied interior was hidden");quit(1);return
    if not house.set_interior_visible(false):
        push_error("Closed vacant interior cannot hide");quit(1);return
    if house.lamp_assembly.visible or house.interior_light.visible:
        push_error("Hidden interior kept its lamp enabled");quit(1);return
    for mesh in house.interior_meshes:
        if mesh.visible:
            push_error("Hidden furniture still visible");quit(1);return
    if house.door.leaves.size()!=10:
        push_error("Door parts missing");quit(1);return
    for i in range(90):
        await physics_frame
        actor.velocity=Vector3(0,-2,-2);actor.move_and_slide()
    if actor.position.z<4.1:
        push_error("Closed loading doors allowed passage");quit(1);return
    actor.position=Vector3(0,.875,5.3)
    await physics_frame
    var obstruction=StaticBody3D.new()
    obstruction.collision_layer=8;obstruction.position=Vector3(-.65,1.3,3.25)
    var obstruction_col=CollisionShape3D.new();var obstruction_shape=BoxShape3D.new()
    obstruction_shape.size=Vector3(.3,2,.3);obstruction_col.shape=obstruction_shape
    obstruction.add_child(obstruction_col);stage.add_child(obstruction)
    await physics_frame
    if not house.door.try_toggle(actor):
        push_error("Door interaction failed");quit(1);return
    for i in range(90):await physics_frame
    if not house.interior_visible or house.set_interior_visible(false):
        push_error("Opening door did not protect interior visibility");quit(1);return
    if not house.lamp_assembly.visible or not house.interior_light.visible:
        push_error("Opening did not restore the visible lamp");quit(1);return
    var camera=Camera3D.new();stage.add_child(camera);camera.make_current()
    camera.position=Vector3(100,3,0)
    for tick in range(40):await physics_frame
    if house.interior_light.visible:
        push_error("Distant interior light did not sleep");quit(1);return
    camera.position=Vector3(0,1.6,2)
    for tick in range(40):await physics_frame
    if not house.interior_light.visible:
        push_error("Nearby lamp did not recover");quit(1);return
    house.set_interior_lights_enabled(false)
    if house.interior_light.visible:
        push_error("World lighting override ignored");quit(1);return
    house.set_interior_lights_enabled(true)
    if not house.door.blocked or house.door.fraction>=1.0:
        push_error("Door swept through obstruction");quit(1);return
    obstruction.queue_free()
    for i in range(90):await physics_frame
    if not is_equal_approx(house.door.fraction,1.0):
        push_error("Double door opening incomplete");quit(1);return
    for target in [Vector3(0,.875,2),Vector3(0,.875,-2),Vector3(0,.875,1.5)]:
        for i in range(600):
            await physics_frame
            var offset=target-actor.position;offset.y=0
            if offset.length()<.08:break
            actor.velocity=offset.normalized()*2
            actor.velocity.y=-2
            actor.move_and_slide()
        if actor.position.distance_to(target)>.12:
            push_error("Loading aisle blocked at "+str(actor.position));quit(1);return
    if not house.door.try_toggle(actor):
        push_error("Interior closing failed");quit(1);return
    for i in range(90):await physics_frame
    if not is_zero_approx(house.door.fraction):
        push_error("Interior close incomplete");quit(1);return
    if not house.door.try_toggle(actor):
        push_error("Interior reopening failed");quit(1);return
    for i in range(90):await physics_frame
    for i in range(600):
        await physics_frame
        if actor.position.z > 5.2:break
        actor.velocity=Vector3(0,-2,2);actor.move_and_slide()
    if actor.position.z < 5.2:
        push_error("Return blocked "+str(actor.position));quit(1);return
    print("S_S_LOADING_RETURN_PASS ",actor.position)
    quit(0)
