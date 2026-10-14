extends SceneTree
## Independent physical-support and lifecycle fixture; not full city acceptance.
const Lanterns = preload("res://scripts/world/snow_city_lanterns.gd")
class Clock extends Node:
    var hour := 23.0
class World extends Node3D:
    var world_root: Node3D
    var atmosphere: Node
    func world_ground(_x: float,_z: float) -> float: return 0.0
class City extends Node3D:
    var world: Node3D
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func expect(ok: bool,label: String) -> void:
    if not ok:failures.append(label);print("SNOW_LANTERN_FAIL ",label)
func settle(n: int=35) -> void:
    for i in n:await physics_frame
func count(lamps: Node3D) -> int:
    var active := 0
    for light in lamps.lights:
        if light.visible:active+=1
        expect(not light.shadow_enabled,"street shadow maps remain disabled")
    return active
func blocked_approaches(at: Vector2,buildings: Array) -> Array[String]:
    var blocked: Array[String] = []
    for plot in buildings:
        var local := (at-Vector2(float(plot.x),float(plot.z))).rotated(-deg_to_rad(float(plot.yaw)))
        var front := float(plot.d)*.5
        # Adult radius .28m + pole half-width .1m + .12m clearance.
        # Include the actual exterior approach and the three shops' hanging-sign lane.
        var routes := [[Vector2(0,front+2.82),Vector2(0,front+.8)]]
        if str(plot.code) in ["л1","л2","л3"]:
            routes.append([Vector2(0,front+2.82),Vector2(1.4,front+.5)])
            routes.append([Vector2(1.4,front+.5),Vector2(2.2,front+.5)])
        for segment in routes:
            var nearest := Geometry2D.get_closest_point_to_segment(local,segment[0],segment[1])
            if local.distance_to(nearest)<.5:blocked.append(str(plot.code))
    return blocked
func run() -> void:
    var plan=JSON.parse_string(FileAccess.get_file_as_string(Lanterns.PLAN))
    var buildings: Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/world/snow-city-v1/plan.json")).buildings
    for post in plan.posts:
        expect(blocked_approaches(Vector2(post.at[0],post.at[1]),buildings).is_empty(),"clear entry/sign corridor "+str(post.label))
    for old in [[996.209609467,329.713093492,"л1"],[954.491765913,326.221180697,"Б11"],[995.994593078,415.575290658,"вс3"],[1000.393750187,422.417857036,"вс4"]]:
        expect(str(old[2]) in blocked_approaches(Vector2(old[0],old[1]),buildings),"regression catches original tight approach "+str(old[2]))
    # On the authored narrow lane, uphill motion slides to this shoulder.
    # Preserve a capsule-wide corridor around the measured real-hero passage.
    var passage_a:=Vector2(991.343567,408.7864)
    var passage_b:=Vector2(990.0,404.0)
    var old_pole:=Vector2(990.9945930782675,408.5752906583803)
    expect(old_pole.distance_to(Geometry2D.get_closest_point_to_segment(old_pole,passage_a,passage_b))<.5,"regression catches uphill lane pole")
    for post in plan.posts:
        var at:=Vector2(float(post.at[0]),float(post.at[1]))
        expect(at.distance_to(Geometry2D.get_closest_point_to_segment(at,passage_a,passage_b))>=.5,"clear uphill lane "+str(post.label))
    for missing in [false,true]:
        var w=World.new();root.add_child(w)
        w.world_root=Node3D.new();w.add_child(w.world_root)
        w.world_root.position=Vector3(121,11,-44)
        w.atmosphere=Clock.new();w.add_child(w.atmosphere)
        for i in plan.posts.size():
            if missing and i==0:continue
            var spec:Dictionary=plan.posts[i]
            # Independent collider tops: ground sample is deliberately wrong by21.7cm at first post.
            var height:float=(.217 if i==0 else 0.0) if spec.level==null else float(spec.level)
            var body=StaticBody3D.new();w.world_root.add_child(body)
            body.position=Vector3(spec.at[0]-1000,height-.25,spec.at[1]-1000)
            var shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(.5,.5,.5)
            shape.shape=box;body.add_child(shape)
        var city=City.new();city.world=w;w.world_root.add_child(city)
        var lamps=Lanterns.new();city.add_child(lamps);lamps.set_lighting_enabled(false);lamps.build(city)
        await settle()
        expect(lamps.posts.size()==plan.posts.size()-(1 if missing else 0),"physical support count")
        expect(lamps.complete==not missing,"missing support cannot claim completion")
        expect(lamps.unresolved.size()==(1 if missing else 0),"missing support explicit")
        expect(count(lamps)==0,"disabled before deferred build")
        if missing:
            w.queue_free();await settle(3);continue
        expect(absf(lamps.posts[0].position.y-.217)<.001,"base follows actual collider instead of sampled ground")
        var observer=Camera3D.new();w.add_child(observer);observer.current=true
        observer.global_position=lamps.lights[0].global_position
        lamps.set_lighting_enabled(true)
        for item in [[12.0,false],[18.49,false],[18.5,true],[23.0,true],[6.49,true],[6.5,false]]:
            w.atmosphere.hour=item[0];await settle()
            var n=count(lamps)
            expect((n>0)==item[1] and n<=8,"clock boundary "+str(item[0]))
        w.atmosphere.hour=23;await settle()
        lamps.set_lighting_enabled(false)
        expect(count(lamps)==0,"master disable immediate")
        await settle();expect(count(lamps)==0,"night tick must not re-enable disabled lights")
        lamps.set_lighting_enabled(true);await settle()
        expect(count(lamps)>0,"master restore")
        observer.global_position=lamps.lights[0].global_position+Vector3(45,0,0)
        await settle();expect(not lamps.lights[0].visible,"45m boundary excluded")
        for light in lamps.lights:
            if light.visible:expect(observer.global_position.distance_to(light.global_position)<45,"visible lights are nearby")
        observer.global_position=Vector3(10000,10000,10000);await settle()
        expect(count(lamps)==0,"remote camera sleeps lights")
        observer.queue_free();await settle();expect(count(lamps)==0,"missing camera sleeps lights")
        w.queue_free();await settle(3)
    print("SNOW_LANTERN_FIXTURE posts=",plan.posts.size()," failures=",failures.size()," full_city_ready=false")
    quit(0 if failures.is_empty() else 1)
