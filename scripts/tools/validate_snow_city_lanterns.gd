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
func run() -> void:
    var plan=JSON.parse_string(FileAccess.get_file_as_string(Lanterns.PLAN))
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
