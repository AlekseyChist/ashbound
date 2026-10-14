extends SceneTree
## Revision2 coordinator QA: actual movement over every tread, no local JSON dependency.
const LEVELS := [0.0,3.6,7.2,10.8,14.4,18.0,21.6,25.2]
const STARTS := [Vector2(6.25,3),Vector2(3,-6.25),Vector2(-6.25,-3),Vector2(-3,6.25)]
const ENDS := [Vector2(6.25,-3),Vector2(-3,-6.25),Vector2(-6.25,3),Vector2(3,6.25)]
const CORNERS := [Vector2(6.25,-6.25),Vector2(-6.25,-6.25),Vector2(-6.25,6.25),Vector2(6.25,6.25)]
class AtmosphereFixture extends Node:
    var daylight := 1.0 # The verified existing settlement property, not a new clock.
var actor: CharacterBody3D
var building: Node3D
var clock: AtmosphereFixture
var segments := 0
var clearance_samples := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> bool:
    if not ok:
        failures += 1
        push_error("ACADEMY_TOWER_R2 " + message)
    return ok
func rendered_support(from:Vector3,to:Vector3)->bool:
    # Repair-scaffold bearers are visual architecture in the accepted GLB.
    # Verify their real triangles; never accept the new fixture's own mesh.
    for mesh in building.find_children("*","MeshInstance3D",true,false):
        if building.lamp_root.is_ancestor_of(mesh):continue
        for surface in mesh.mesh.get_surface_count():
            var arrays:Array=mesh.mesh.surface_get_arrays(surface)
            var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
            var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
            for i in range(0,indices.size(),3):
                var a:Vector3=mesh.to_global(vertices[indices[i]])
                var b:Vector3=mesh.to_global(vertices[indices[i+1]])
                var c:Vector3=mesh.to_global(vertices[indices[i+2]])
                if Geometry3D.segment_intersects_triangle(from,to,a,b,c)!=null:return true
    return false
func settle(count: int = 60) -> void:
    for tick in range(count):
        await physics_frame
        actor.velocity = Vector3(0,actor.velocity.y-9.8/60,0)
        actor.move_and_slide()
func walk(target: Vector3) -> bool:
    for tick in range(1100):
        await physics_frame
        var direction := target-actor.position; direction.y=0
        if direction.length() < .045: break
        actor.velocity.x=direction.normalized().x*2
        actor.velocity.z=direction.normalized().z*2
        actor.velocity.y=-.5 if actor.is_on_floor() else actor.velocity.y-9.8/60
        actor.move_and_slide()
        if tick%8==0:
            var foot := actor.position-Vector3(0,.875,0)
            var hit := actor.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(foot+Vector3(0,.20,0),foot+Vector3(0,2.4,0),1))
            clearance_samples+=1
            if not check(hit.is_empty(),"HEADROOM "+str(foot)+" hit="+str(hit)):return false
    await settle(10)
    segments+=1
    print("TOWER_R2_POINT ",segments," ",actor.position)
    return check(actor.position.distance_to(target)<.18,"ROUTE target="+str(target)+" actual="+str(actor.position))
func go(points: Array) -> bool:
    for point in points:
        if not await walk(point):return false
    return true
func internal_points(h: float) -> Array:
    var points: Array=[Vector3(2.5,h+.875,2.75),Vector3(2.5,h+.875,2)]
    for k in range(1,11):points.append(Vector3(2.5,h+.875+k*.18,2-k*.3))
    points.append(Vector3(2.5,h+2.675,-1.6));points.append(Vector3(4.05,h+2.675,-1.6));points.append(Vector3(4.05,h+2.675,-1))
    for k in range(1,11):points.append(Vector3(4.05,h+2.675+k*.18,-1+k*.3))
    points.append(Vector3(4.05,h+4.475,2.75))
    return points
func exterior_points(k: int) -> Array:
    var a: Vector2=STARTS[k%4];var b: Vector2=ENDS[k%4];var h:=k*3.6
    var points: Array=[]
    for step in range(21):
        var p:=a.lerp(b,step/20.0)
        points.append(Vector3(p.x,h+.875+step*.18,p.y))
    var c: Vector2=CORNERS[k%4];var next: Vector2=STARTS[(k+1)%4]
    points.append(Vector3(c.x,h+4.475,c.y));points.append(Vector3(next.x,h+4.475,next.y))
    return points
func toggle(portal: Node3D) -> bool:
    if not check(portal.try_toggle(actor),"Portal interaction "+str(actor.position)):return false
    await settle(90)
    return check(not portal.moving and not portal.blocked,"Unobstructed door failed to settle")
# The seven relocated windows must have open upper panes through both the wall
# and the exterior flight. Sample each side of the central mullion; the lower
# part may legitimately look onto the flight's solid guard.
func check_relocated_windows() -> bool:
    var space:=building.get_world_3d().direct_space_state
    var clear:=true
    var samples:=0
    for spec in [[3.6,Vector3(2.2,0,-5.3),Vector3(0,0,-1)], [7.2,Vector3(-5.3,0,-2.2),Vector3(-1,0,0)], [10.8,Vector3(-2.2,0,5.3),Vector3(0,0,1)], [14.4,Vector3(5.3,0,2.2),Vector3(1,0,0)], [18.0,Vector3(2.2,0,-5.3),Vector3(0,0,-1)], [21.6,Vector3(-5.3,0,-2.2),Vector3(-1,0,0)], [25.2,Vector3(-2.2,0,5.3),Vector3(0,0,1)]]:
        var normal:Vector3=spec[2]
        var side:=normal.cross(Vector3.UP)
        for offset in [-.20,.20]:
            for eye in [1.95,2.15]:
                var target:Vector3=spec[1]+Vector3.UP*(float(spec[0])+eye)+side*offset
                var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(target-normal*.5,target+normal*2.3,1))
                samples+=1
                if not check(hit.is_empty(),"Relocated window blocked at floor "+str(spec[0])+" offset="+str(offset)+" height="+str(eye)):
                    clear=false
    print("TOWER_RELOCATED_WINDOWS samples=",samples," clear=",clear)
    return clear
func run() -> void:
    print("TOWER_R2_VALIDATED_ASSET_SHA256 ",FileAccess.get_sha256("res://assets/buildings/world-architecture-v1/s_academy_tower.glb"))
    clock=AtmosphereFixture.new();clock.name="Atmosphere";root.add_child(clock)
    building=load("res://scenes/buildings/world-architecture-v1/s_academy_tower.tscn").instantiate();root.add_child(building)
    var ground:=StaticBody3D.new();var col:=CollisionShape3D.new();var slab:=BoxShape3D.new();slab.size=Vector3(40,.2,40)
    col.shape=slab;col.position.y=-.1;ground.add_child(col);root.add_child(ground)
    actor=CharacterBody3D.new();actor.collision_layer=2;actor.floor_snap_length=.4;actor.floor_max_angle=deg_to_rad(46)
    var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.75
    var shape:=CollisionShape3D.new();shape.shape=capsule;actor.add_child(shape);root.add_child(actor);actor.position=Vector3(0,.9,7.5)
    await settle()
    if not check_relocated_windows():quit(1);return
    if not check(building.get_meta("architecture_revision",0)==2,"Scene revision not2"):quit(1);return
    var facts:=building.find_child("TowerFacts",true,false)
    if not check(facts!=null,"Self-contained GLB facts missing"):quit(1);return
    var extras: Dictionary=facts.get_meta("extras",{})
    if not check(extras.get("internal_treads",0)==140 and extras.get("external_treads",0)==160,"Expected140+160 actual treads"):quit(1);return
    if not check(building.door.leaves.size()==8 and building.maintenance_door.leaves.size()==8,"Two eight-part portals required"):quit(1);return
    if not check(building.interior_lights.size()==30 and not building.interior_meshes.is_empty(),"8 rooms, cell lamp, 7 turns, 8 flights and 6 repair-ring lamps required"):quit(1);return
    var support_space=building.get_world_3d().direct_space_state
    var cord_count:=0;var bracket_count:=0
    for support in building.lamp_root.get_children():
        if support is MeshInstance3D and support.name.begins_with("SupportCord"):
            cord_count+=1
            var top:Vector3=support.position+Vector3.UP*support.mesh.size.y*.5
            var hit=support_space.intersect_ray(PhysicsRayQueryParameters3D.create(top-Vector3.UP*.06,top+Vector3.UP*.06,1))
            var supported:bool=not hit.is_empty() and building.is_ancestor_of(hit.collider)
            if not supported:supported=rendered_support(top-Vector3.UP*.06,top+Vector3.UP*.06)
            if not check(supported,"Cord must meet actual ceiling or scaffold bearer "+str(top)):quit(1);return
        if support is MeshInstance3D and support.name.begins_with("WallBracket"):
            bracket_count+=1
            var at:Vector3=support.position
            var normal:=Vector3(signf(at.x),0,0) if support.mesh.size.x>support.mesh.size.z else Vector3(0,0,signf(at.z))
            var hit=support_space.intersect_ray(PhysicsRayQueryParameters3D.create(at+normal*.3,at-normal*.3,1))
            if not check(not hit.is_empty() and building.is_ancestor_of(hit.collider),"Bracket must enter actual masonry "+str(at)):quit(1);return
    if not check(cord_count==17 and bracket_count==13,"All30 individual supports inspected"):quit(1);return
    if not check(building.warm_window!=null and not building.window_material.emission_enabled,"Day window incorrectly emits"):quit(1);return
    clock.daylight=0
    await settle(40)
    if not check(building.window_material.emission_enabled and building.window_material.emission_energy_multiplier>1,"Atmosphere night did not light cell window"):quit(1);return
    if not check(not building.set_interior_visible(false,true) and building.set_interior_visible(false),"Occupancy/closed vacancy guard"):quit(1);return
    if not check(building.warm_window.visible and building.window_material.emission_enabled and not building.lamp_root.visible,"Landmark window vanished with furniture culling"):quit(1);return
    building.set_interior_lights_enabled(false)
    if not check(not building.window_material.emission_enabled,"Explicit light disable left beacon active"):quit(1);return
    building.set_interior_lights_enabled(true);clock.daylight=1
    await settle(40)
    if not check(not building.window_material.emission_enabled,"Night window failed to recover daytime"):quit(1);return
    for tick in range(90):
        await physics_frame
        actor.velocity=Vector3(0,-.5,-2);actor.move_and_slide()
    if not check(actor.position.z>5.5,"Closed entrance allowed passage"):quit(1);return
    if not await toggle(building.door):quit(1);return
    if not check(building.interior_visible and not building.set_interior_visible(false),"Open portal visibility guard"):quit(1);return
    if not await go([Vector3(0,.875,3.6),Vector3(0,.875,2.75),Vector3(-1,.875,0),Vector3(0,.875,0),Vector3(0,.875,2.75)]):quit(1);return
    if not await toggle(building.door):quit(1);return
    for h in LEVELS.slice(0,7):
        if not await go(internal_points(h)):quit(1);return
        if not await walk(Vector3(0,h+4.475,2.75)):quit(1);return
        if h==3.6:
            if not await go([Vector3(-3,8.075,2.75),Vector3(-3,8.075,0),Vector3(-4.4,8.075,0),Vector3(-3,8.075,0),Vector3(-3,8.075,2.75),Vector3(0,8.075,2.75)]):quit(1);return
        if not await go([Vector3(0,h+4.475,0),Vector3(0,h+4.475,2.75)]):quit(1);return
    if not await walk(Vector3(3.2,26.075,2.5)):quit(1);return
    if not await toggle(building.maintenance_door):quit(1);return
    if not await walk(Vector3(6.25,26.075,2.5)):quit(1);return
    if not check(building.maintenance_door.try_toggle(actor),"Closing request"):quit(1);return
    await settle(90)
    if not check(building.maintenance_door.blocked,"Closing arc did not protect capsule"):quit(1);return
    if not await walk(Vector3(6.25,26.075,.5)):quit(1);return
    await settle(90)
    if not check(is_zero_approx(building.maintenance_door.fraction) and not building.maintenance_door.moving,"Door did not recover after obstruction"):quit(1);return
    # Reach the eighth exterior flight along the actual high-level ring.
    if not await go([Vector3(6.25,26.075,-6.25),Vector3(-7.55,26.075,-6.25),Vector3(-7.55,26.075,6.25),Vector3(-6.25,26.075,6.25),Vector3(-3,26.075,6.25)]):quit(1);return
    # New west bypass: physical outer masonry guard, adult capsule foot reference.
    if not await walk(Vector3(-7.55,26.075,4.5)):quit(1);return
    for tick in range(90):
        await physics_frame
        actor.velocity=Vector3(-2,-.5,0);actor.move_and_slide()
    if not check(actor.position.x>-7.9 and actor.position.y>25.95,"West bypass guard failed"):quit(1);return
    if not await go([Vector3(-7.55,26.075,6.25),Vector3(-3,26.075,6.25)]):quit(1);return
    if not await go(exterior_points(7)):quit(1);return
    # C-shaped upper repair gallery with a real south stair hole: brackets/board gallery/scaffold/rod access.
    if not await go([Vector3(6.25,29.675,-6.25),Vector3(-6.25,29.675,-6.25),Vector3(-6.25,29.675,6.25),Vector3(-4,29.675,6.25),Vector3(-6.25,29.675,6.25),Vector3(-6.25,29.675,-6.25),Vector3(6.25,29.675,-6.25),Vector3(6.25,29.675,3)]):quit(1);return
    # Closed west edge of the eighth-flight roof hole must stop a real capsule.
    if not await go([Vector3(6.25,29.675,-6.25),Vector3(-6.25,29.675,-6.25),Vector3(-6.25,29.675,6.25),Vector3(-4,29.675,6.25)]):quit(1);return
    for tick in range(90):
        await physics_frame
        actor.velocity=Vector3(2,-.5,0);actor.move_and_slide()
    if not check(actor.position.x<-3.25 and actor.position.y>29.4,"Repair stair hole end guard failed"):quit(1);return
    if not await go([Vector3(-6.25,29.675,6.25),Vector3(-6.25,29.675,-6.25),Vector3(6.25,29.675,-6.25),Vector3(6.25,29.675,3)]):quit(1);return
    for k in range(7,-1,-1):
        var points:=exterior_points(k);points.reverse()
        if not await go(points):quit(1);return
    if not await walk(Vector3(6.25,.875,3.75)):quit(1);return
    # Entire outside climb then repeat the full descent of every internal tread.
    for k in range(8):
        if not await go(exterior_points(k)):quit(1);return
    # Guard is physical masonry/repair rail, without an invisible wall.
    for tick in range(90):
        await physics_frame
        actor.velocity=Vector3(2,-.5,0);actor.move_and_slide()
    if not check(actor.position.x<7 and actor.position.y>29.4,"Upper gallery guard failed"):quit(1);return
    if not await walk(Vector3(6.25,29.675,3)):quit(1);return
    var last:=exterior_points(7);last.reverse()
    if not await go(last):quit(1);return
    if not await go([Vector3(-6.25,26.075,6.25),Vector3(-7.55,26.075,6.25),Vector3(-7.55,26.075,-6.25),Vector3(6.25,26.075,-6.25),Vector3(6.25,26.075,.5)]):quit(1);return
    if not await toggle(building.maintenance_door):quit(1);return
    if not await go([Vector3(6.25,26.075,2.5),Vector3(3.2,26.075,2.5)]):quit(1);return
    if not await toggle(building.maintenance_door):quit(1);return
    for h in [21.6,18.0,14.4,10.8,7.2,3.6,0.0]:
        var points:=internal_points(h);points.reverse()
        if not await go(points):quit(1);return
    if not await walk(Vector3(0,.875,3.6)):quit(1);return
    if not await toggle(building.door):quit(1);return
    if not await walk(Vector3(0,.875,7.5)):quit(1);return
    if not await toggle(building.door):quit(1);return
    var space:=actor.get_world_3d().direct_space_state
    var niche:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-4.7,8.7,0),Vector3(-5.6,8.7,0),1))
    if not check(not niche.is_empty() and absf(niche.position.x+5.4)<.025,"Niche backing/opening"):quit(1);return
    var mouth:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-3.8,31,-2.8),Vector3(-3.8,28.5,-2.8),1))
    if not check(not mouth.is_empty() and absf(mouth.position.y-28.95)<.025,"Open chimney obstructed by board lid"):quit(1);return
    var bed:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-3.6,8.6,-1.05),Vector3(-3.6,7.7,-1.05),1))
    if not check(not bed.is_empty() and absf(bed.position.y-8.08)<.025,"Preserved solid mattress"):quit(1);return
    for h in [0.0,3.6,7.2]:
        var stove:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-2.8,h+.7,-2.8),Vector3(-4.4,h+.7,-2.8),1))
        if not check(not stove.is_empty() and absf(stove.position.x+3.25)<.025,"Preserved stove collision"):quit(1);return
    var support:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(6,30.5,-5.15),Vector3(5,30.5,-5.15),1))
    if not check(not support.is_empty() and absf(support.position.x-5.5)<.04,"Lightning pin masonry anchor absent"):quit(1);return
    var camera:=Camera3D.new();root.add_child(camera);camera.make_current();camera.position=Vector3(120,20,0)
    await settle(40)
    for light in building.interior_lights:
        if not check(not light.visible,"Distant lantern failed to sleep"):quit(1);return
    camera.position=Vector3(0,2,0);await settle(40)
    var visible_lights:=0
    for light in building.interior_lights:
        if light.visible:visible_lights+=1
    if not check(visible_lights==8,"Nearest8 light budget at entry"):quit(1);return
    camera.position=Vector3(0,26.9,0);await settle(40)
    visible_lights=0
    for light in building.interior_lights:
        if light.visible:
            visible_lights+=1
            if not check(light.global_position.y>16,"Upper route must release distant lower lamps"):quit(1);return
    if not check(visible_lights==8,"Nearest8 light budget upstairs"):quit(1);return
    building.set_interior_lights_enabled(false)
    for light in building.interior_lights:
        if not check(not light.visible,"Master off must beat nearest-light budget"):quit(1);return
    building.set_interior_lights_enabled(true)
    var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF);var triangles:=0
    for node in building.find_children("*","MeshInstance3D",true,false):
        for surface in range(node.mesh.get_surface_count()):
            var arrays: Array=node.mesh.surface_get_arrays(surface)
            for vertex in arrays[Mesh.ARRAY_VERTEX]:
                var point: Vector3=building.to_local(node.to_global(vertex));low=low.min(point);high=high.max(point)
            var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
            triangles+=(indices.size() if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size())/3
    print("TOWER_R2_WHOLE_VERTICES min=",low," max=",high," triangles_with_lamps=",triangles)
    if not check(low.x>=-8.3 and high.x<=7.3 and low.z>=-7.3 and high.z<=7.3 and high.y>31 and high.y<35,"Complete bounded tall silhouette"):quit(1);return
    print("ACADEMY_TOWER_R2_PASS segments=",segments," headroom_samples=",clearance_samples," internal_treads=140 external_treads=160 failures=",failures)
    quit(0)
