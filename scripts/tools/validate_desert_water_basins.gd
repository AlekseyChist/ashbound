extends SceneTree
var actor: CharacterBody3D
func walk(target:Vector3)->bool:
    for tick in range(900):
        await physics_frame
        var direction=target-actor.position;direction.y=0
        if direction.length()<.1:break
        actor.velocity=direction.normalized()*2
        actor.velocity.y=0 if actor.is_on_floor() else actor.velocity.y-9.8/60
        actor.move_and_slide()
    return actor.position.distance_to(target)<.2
func _initialize(): call_deferred("run")
func run():
    for spec in [["d_cooling_pond",7.0],["d_drinking_cistern",6.0]]:
        var basin=load("res://scenes/buildings/world-architecture-v1/"+str(spec[0])+".tscn").instantiate()
        root.add_child(basin)
        await physics_frame
        var bounds:AABB
        var first=true
        for mesh in basin.find_children("*","MeshInstance3D",true,false):
            var volume=mesh.global_transform*mesh.get_aabb()
            if first:bounds=volume;first=false
            else:bounds=bounds.merge(volume)
        if absf(bounds.size.x-float(spec[1]))>.02 or absf(bounds.size.z-5)>.02:
            push_error("Basin exceeds approved outer contour "+str(bounds));quit(1);return
        var space=basin.get_world_3d().direct_space_state
        var labels=["Inlet","Outlet"] if str(spec[0])=="d_cooling_pond" else ["Inlet"]
        for label in labels:
            var port=basin.find_child(label,true,false) as Node3D
            if port==null:push_error("Missing basin port "+label);quit(1);return
            var at=port.global_position
            var axis=Vector3.RIGHT if absf(at.x)>float(spec[1])/2-.31 else Vector3.FORWARD
            var opening=space.intersect_ray(PhysicsRayQueryParameters3D.create(at-axis*.5,at+axis*.5,1))
            if not opening.is_empty():push_error("Blocked water port "+label);quit(1);return
            var sill=space.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*.1,at-Vector3.UP*.4,1))
            if sill.is_empty() or absf(sill.position.y+.15)>.02:
                push_error("Missing water port sill");quit(1);return
        for x in [-1.0,0.0,1.0]:
            var floor_hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,1,0),Vector3(x,-2,0),1))
            if floor_hit.is_empty() or absf(floor_hit.position.y+1)>.02:
                push_error("Basin floor missing or empty bowl plugged: "+str(spec[0]));quit(1);return
        for side in [-1.0,1.0]:
            var rim_x=side*(float(spec[1])/2-.16)
            var rim=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(rim_x,1,.4),Vector3(rim_x,-2,.4),1))
            if rim.is_empty() or absf(rim.position.y-.33)>.02:
                push_error("Basin rim unsupported");quit(1);return
            var wall=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,-.5,0),Vector3(side*float(spec[1]),-.5,0),1))
            if wall.is_empty() or absf(absf(wall.position.x)-(float(spec[1])/2-.30))>.02:
                push_error("Basin side wall missing");quit(1);return
        print("DESERT_BASIN_BOWL_RIM_PASS ",spec[0])
        var ground=StaticBody3D.new();var ground_col=CollisionShape3D.new();var ground_shape=BoxShape3D.new()
        ground_shape.size=Vector3(20,.1,20);ground_col.shape=ground_shape;ground_col.position.y=-.05
        ground.add_child(ground_col);root.add_child(ground)
        actor=CharacterBody3D.new();actor.collision_layer=2;actor.floor_snap_length=.35
        var capsule=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.75
        var collision=CollisionShape3D.new();collision.shape=capsule;actor.add_child(collision);root.add_child(actor)
        var outside=float(spec[1])/2+.65
        actor.position=Vector3(-outside,.9,3.15)
        var points=[Vector3(outside,.875,3.15),Vector3(outside,.875,-3.15),Vector3(-outside,.875,-3.15),Vector3(-outside,.875,3.15)]
        for target in points:
            if not await walk(target):
                push_error("Basin perimeter blocked "+str(spec[0])+" at "+str(actor.position));quit(1);return
        print("DESERT_BASIN_PERIMETER_PASS ",spec[0]," segments=4")
        actor.queue_free();ground.queue_free()
        basin.queue_free();await process_frame
    quit(0)
