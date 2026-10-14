extends SceneTree
var house
var actor:CharacterBody3D
var failures:Array=[]
var legs:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
    if not ok:failures.append(label);push_error("STORE_QA "+label)
func settle(n:int=30)->void:
    for i in n:
        await physics_frame
        actor.velocity=Vector3(0,-.5 if actor.is_on_floor() else actor.velocity.y-9.8/60,0)
        actor.move_and_slide()
func move_to(p:Vector2,expect_reached:bool=true)->void:
    var target=Vector3(p.x,.875,p.y)
    for i in 400:
        await physics_frame
        var d=target-actor.position;d.y=0
        if d.length()<.07:break
        var v=d.normalized()*2
        actor.velocity=Vector3(v.x,-.5 if actor.is_on_floor() else actor.velocity.y-9.8/60,v.z)
        actor.move_and_slide()
    await settle(3);legs+=1
    var reached=actor.position.distance_to(target)<.13
    check(reached==expect_reached,"movement target="+str(p)+" actual="+str(actor.position))
    check(actor.is_on_floor(),"adult stays on floor")
    if reached and absf(p.x)<3.5 and absf(p.y)<2.5:
        var hit=house.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(actor.position,actor.position-Vector3.UP*1.1,1))
        check(not hit.is_empty() and house.is_ancestor_of(hit.collider),"model owns floor")
func run()->void:
    house=load("res://scenes/buildings/world-architecture-v1/d_store_8x6.tscn").instantiate();root.add_child(house)
    var ground=StaticBody3D.new();ground.collision_layer=16;var shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(30,.2,20);shape.shape=box;shape.position.y=-.1;ground.add_child(shape);root.add_child(ground)
    actor=CharacterBody3D.new();actor.collision_layer=2;actor.collision_mask=17;actor.floor_snap_length=.35
    var col=CollisionShape3D.new();var capsule=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.75;col.shape=capsule;actor.add_child(col);root.add_child(actor);actor.position=Vector3(0,.9,5)
    var camera=Camera3D.new();root.add_child(camera);camera.make_current();camera.position=Vector3(0,2,5)
    await settle(60)
    await move_to(Vector2(0,1.5),false)
    check(house.door.try_toggle(actor),"entry door toggle");await settle(60)
    for p in [Vector2(0,2),Vector2(0,0),Vector2(0,-2),Vector2(-1,-2),Vector2(-1,0),Vector2(-.6,1.5),Vector2(0,1.5),Vector2(1,1.5),Vector2(1,0),Vector2(1,-2),Vector2(0,-2),Vector2(0,0)]:await move_to(p)
    # A filled stack must block torso-height motion, independently of decorative planks.
    for z in [.9,-1.3]:
        var hit=house.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(.6,.9,z),Vector3(3.4,.9,z),1))
        check(not hit.is_empty(),"timber stack blocks torso at z="+str(z))
    check(not house.set_interior_visible(false),"open door keeps furnishings")
    await move_to(Vector2(0,5))
    check(house.door.try_toggle(actor),"exit door closes");await settle(60)
    check(not house.set_interior_visible(false,true),"occupancy protects furniture")
    check(house.set_interior_visible(false),"empty closed store sleeps")
    check(house.door.try_toggle(actor),"reopen sleeping door");await settle(60)
    check(house.interior_visible,"reopening restores furniture")
    camera.position=Vector3(100,3,0);await settle(60)
    check(not house.lights[0].visible,"far light sleeps")
    camera.position=Vector3(0,2,0);await settle(60)
    check(house.lights[0].visible,"near light resumes")
    house.set_interior_lights_enabled(false);await settle(60);check(not house.lights[0].visible,"world light override")
    print("STORE_QA_DONE legs=",legs," failures=",failures.size()," whole_world_ready=false")
    quit(0 if failures.is_empty() else 1)

