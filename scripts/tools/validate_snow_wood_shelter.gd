extends SceneTree
func _initialize():call_deferred("run")
func run():
    var stage=Node3D.new();root.add_child(stage)
    var shelter=load("res://assets/buildings/world-architecture-v1/s_wood_shelter.glb").instantiate();stage.add_child(shelter)
    var actor=CharacterBody3D.new()
    var col=CollisionShape3D.new();var capsule=CapsuleShape3D.new()
    capsule.radius=.3;capsule.height=1.75;col.shape=capsule
    actor.add_child(col);stage.add_child(actor)
    actor.position=Vector3(0,1.12,.7)
    for i in range(30):
        await physics_frame
        actor.velocity=Vector3(0,-2,0);actor.move_and_slide()
    if not actor.is_on_floor() or abs(actor.position.y-1.115)>.02:
        push_error("Raised floor contact missing");quit(1);return
    for target in [.8,-.8,0.0]:
        for i in range(180):
            await physics_frame
            if abs(actor.position.x-target)<.06:break
            actor.velocity=Vector3(sign(target-actor.position.x)*1.5,-2,0)
            actor.move_and_slide()
        if abs(actor.position.x-target)>.08:
            push_error("Shelter access strip blocked");quit(1);return
    for i in range(90):
        await physics_frame
        actor.velocity=Vector3(0,-2,-1.5);actor.move_and_slide()
    if actor.position.z<.30 or actor.position.z>.42:
        push_error("Fuel collision missing/misplaced "+str(actor.position));quit(1);return
    var ray=PhysicsRayQueryParameters3D.create(Vector3(0,4,0),Vector3(0,0,0))
    var hit=stage.get_world_3d().direct_space_state.intersect_ray(ray)
    if hit.is_empty() or hit.position.y<2 or hit.position.y>2.2:
        push_error("Shelter roof collision missing");quit(1);return
    print("S_S_SHELTER_PASS floor/access/fuel/roof ",actor.position)
    quit()
