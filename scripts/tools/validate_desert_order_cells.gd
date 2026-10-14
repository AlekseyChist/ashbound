extends SceneTree
var house:Node3D
var actor:CharacterBody3D
var failures:=0
var legs:=0
func _initialize()->void:call_deferred("run")
func require(ok:bool,label:String)->bool:
    if not ok:failures+=1;push_error("ORDER_CELLS "+label)
    return ok
func settle(n:int=45)->void:
    for i in n:
        await physics_frame
        actor.velocity=Vector3(0,-.5 if actor.is_on_floor() else actor.velocity.y-9.8/60,0)
        actor.move_and_slide()
func walk(x:float,z:float,label:String)->bool:
    var target=Vector3(x,.875,z)
    for tick in range(600):
        await physics_frame
        var d=target-actor.position;d.y=0
        if d.length()<.045:break
        var direction=d.normalized()*2
        actor.velocity=Vector3(direction.x,-.5 if actor.is_on_floor() else actor.velocity.y-9.8/60,direction.z)
        actor.move_and_slide()
    await settle(3);legs+=1
    if absf(x)<6.6 and absf(z)<3.1:
        var hit=house.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(actor.position,actor.position-Vector3.UP*1.1,1))
        if not require(not hit.is_empty() and house.is_ancestor_of(hit.collider),label+" model floor supports adult"):return false
    return require(actor.position.distance_to(target)<.09 and actor.is_on_floor(),label+" target="+str(target)+" actual="+str(actor.position))
func go(points:Array,label:String)->bool:
    for point in points:
        if not await walk(point.x,point.y,label):return false
    return true
func toggle()->bool:
    print("ORDER_DOOR_BEFORE actor=",actor.position," fraction=",house.door.fraction," sign=",house.door.opening_sign," legs=",legs)
    if not require(house.door.try_toggle(actor),"door interaction"):return false
    await settle(60)
    print("ORDER_DOOR_AFTER actor=",actor.position," fraction=",house.door.fraction," sign=",house.door.opening_sign," blocked=",house.door.blocked," pivot=",house.door.leaves[0].rest)
    return require(not house.door.moving and not house.door.blocked,"door settles")
func run()->void:
    house=load("res://scenes/buildings/world-architecture-v1/d_order_cells.tscn").instantiate();root.add_child(house)
    var ground=StaticBody3D.new();ground.collision_layer=16;var col=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=Vector3(30,.2,20)
    col.shape=shape;col.position.y=-.1;ground.add_child(col);root.add_child(ground)
    actor=CharacterBody3D.new();actor.collision_layer=2;actor.collision_mask=17;actor.floor_snap_length=.35
    var capsule=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.75
    var body=CollisionShape3D.new();body.shape=capsule;actor.add_child(body);root.add_child(actor);actor.position=Vector3(0,.9,5.3)
    await settle()
    var low=Vector3(INF,INF,INF);var high=Vector3(-INF,-INF,-INF)
    for mesh in house.find_children("*","MeshInstance3D",true,false):
        for surface in mesh.mesh.get_surface_count():
            var arrays:Array=mesh.mesh.surface_get_arrays(surface)
            if not house.lamp_root.is_ancestor_of(mesh):
                var mat=mesh.get_active_material(surface) as StandardMaterial3D
                if mat!=null and mat.albedo_texture!=null:
                    var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
                    var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
                    var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
                    if not require(uv.size()==vertices.size(),"textured surface has UVs"):quit(1);return
                    for triangle in range(0,indices.size(),3):
                        var a=indices[triangle];var b=indices[triangle+1];var c=indices[triangle+2]
                        if (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).length()>.000001:
                            if not require(absf((uv[b]-uv[a]).cross(uv[c]-uv[a]))>.0000000001,"nondegenerate textured triangle "+mesh.name):quit(1);return
            for v in arrays[Mesh.ARRAY_VERTEX]:
                var p:Vector3=house.to_local(mesh.to_global(v));low=low.min(p);high=high.max(p)
    if not require(low.x>=-7.301 and high.x<=7.301 and low.z>=-3.801 and high.z<=4.701 and high.y<=4.001,"whole bounds "+str(low)+" "+str(high)):quit(1);return
    if not require(house.door.leaves.size()==5 and house.lights.size()==5 and not house.interior_meshes.is_empty(),"door/rooms/furniture exported"):quit(1);return
    var space=house.get_world_3d().direct_space_state
    for x in [-3.0,3.0]:
        var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,3.65,-3.1),Vector3(x,3.65,-3.9),1))
        if not require(hit.is_empty(),"open drain "+str(x)):quit(1);return
    for point in [Vector2(0,0),Vector2(-4.7,-.5),Vector2(4.2,2.2),Vector2(4.2,.7),Vector2(4.2,-1.3)]:
        var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(point.x,2.9,point.y),Vector3(point.x,3.2,point.y),1))
        if not require(not hit.is_empty() and absf(hit.position.y-3.04)<.02,"physical ceiling and lantern support"):quit(1);return
    if not require(not house.set_interior_visible(false,true) and house.set_interior_visible(false),"occupied/closed-empty visibility"):quit(1);return
    for i in range(80):
        await physics_frame;actor.velocity=Vector3(0,-.5,-2);actor.move_and_slide()
    if not require(actor.position.z>3.6,"closed door blocks adult"):quit(1);return
    if not await toggle():quit(1);return
    if not require(house.interior_visible and not house.set_interior_visible(false),"open door protects furniture"):quit(1);return
    var room_paths=[
        [Vector2(0,2),Vector2(0,.5),Vector2(-3,.5),Vector2(-3,-.6),Vector2(-5.5,-.6),Vector2(-5.5,.2),Vector2(-3,.2),Vector2(-3,1.625),Vector2(-5.5,1.625),Vector2(-3,1.625),Vector2(-3,.5),Vector2(0,.5)],
        [Vector2(0,2.2),Vector2(2,2.2),Vector2(3.4,2.1),Vector2(4.2,2.1),Vector2(3.4,2.1),Vector2(2,2.2),Vector2(0,2.2)],
        [Vector2(0,.7),Vector2(2,.7),Vector2(3.2,.95),Vector2(4.2,.95),Vector2(3.2,.95),Vector2(2,.7),Vector2(0,.7)],
        [Vector2(0,-1),Vector2(2,-1),Vector2(3.2,-.9),Vector2(5.4,-.9),Vector2(3.4,-.9),Vector2(3.4,-2.1),Vector2(3.4,-.9),Vector2(2,-1),Vector2(0,-1)],
    ]
    for i in room_paths.size():
        if not await go(room_paths[i],"room "+str(i)):quit(1);return
    var camera=Camera3D.new();root.add_child(camera);camera.make_current();camera.position=Vector3(100,3,0);await settle()
    for light in house.lights:
        if not require(not light.visible,"far lamp sleeps"):quit(1);return
    camera.position=Vector3(0,2,0);await settle()
    for light in house.lights:
        if not require(light.visible,"near lamp recovers"):quit(1);return
    house.set_interior_lights_enabled(false);await settle()
    for light in house.lights:
        if not require(not light.visible,"world light override"):quit(1);return
    house.set_interior_lights_enabled(true)
    if not await go([Vector2(0,1.8)],"closing arc obstruction"):quit(1);return
    if not require(house.door.try_toggle(actor),"request close with occupied swing"):quit(1);return
    await settle(60)
    if not require(house.door.blocked and house.door.moving and house.door.fraction>0,"swing protects real adult"):quit(1);return
    if not await walk(0,1.2,"leave closing arc"):quit(1);return
    await settle(60)
    if not require(not house.door.moving and not house.door.blocked and is_zero_approx(house.door.fraction),"closing recovers after adult moves"):quit(1);return
    if not await toggle():quit(1);return
    if not await walk(0,5.3,"ordinary exit"):quit(1);return
    if not await toggle():quit(1);return
    # Fixed-fps functional runs can outpace the audio thread. Finish the last
    # real door sound before tearing down the fixture and the audio server.
    var audio_deadline=Time.get_ticks_msec()+5000
    while house.door.audio.playing and Time.get_ticks_msec()<audio_deadline:await process_frame
    if not require(not house.door.audio.playing,"final door sound completes"):quit(1);return
    print("ORDER_CELLS_PASS legs=",legs," rooms=5 failures=",failures," whole_world_ready=false")
    house.queue_free()
    await process_frame
    await process_frame
    quit(0)
