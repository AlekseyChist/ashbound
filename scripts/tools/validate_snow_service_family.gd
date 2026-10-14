extends SceneTree
const SPECS = {
    "s_porters_barracks_11x5": Vector2(11,5),
    "s_porters_barracks_10x5": Vector2(10,5),
    "s_shoemaker": Vector2(7,5), "s_saddler": Vector2(7,5),
    "s_candlemaker": Vector2(7,5), "s_caravan_inn": Vector2(12,7),
    "s_wood_store": Vector2(6,4)}
# Frozen ART revision measurements from imported Godot mesh vertex/index arrays.
# Bounds/triangles are expectations, not values recomputed from a producer report.
# Mouth heights independently measured from the shipped GLB flue collider vertices.
# No ignored measurement files are validation inputs; JSON below is output only.
const MEASURED = {
    "s_porters_barracks_11x5": {"min": Vector3(-5.85,-.24,-2.9), "max": Vector3(5.85,5.0,2.9), "triangles": 8600},
    "s_porters_barracks_10x5": {"min": Vector3(-5.35,-.24,-2.9), "max": Vector3(5.35,5.0,2.9), "triangles": 8600},
    "s_shoemaker": {"min": Vector3(-3.85,-.24,-2.9), "max": Vector3(3.85,6.8,2.9), "triangles": 8436, "mouth_y": 5.226190567},
    "s_saddler": {"min": Vector3(-3.85,-.24,-2.9), "max": Vector3(3.85,6.8,2.9), "triangles": 9148, "mouth_y": 5.226190567},
    "s_candlemaker": {"min": Vector3(-3.85,-.24,-2.9), "max": Vector3(3.85,6.8,2.9), "triangles": 8956, "mouth_y": 5.226190567},
    "s_caravan_inn": {"min": Vector3(-6.35,-.24,-3.9), "max": Vector3(6.35,6.85,3.9), "triangles": 10228, "mouth_y": 4.650875688},
    "s_wood_store": {"min": Vector3(-3.35,-.24,-2.4), "max": Vector3(3.35,4.25,2.4), "triangles": 6484}}
var failures: Array[String] = []
var results: Array = []
var actor: CharacterBody3D
var stage: Node3D
var camera: Camera3D
var walks := 0
func _initialize() -> void: call_deferred("run")
func require(ok: bool, text: String) -> void:
    if not ok: failures.append(text);push_error(text)
func settle(ticks: int = 90) -> void:
    for i in range(ticks): await physics_frame
func walk(target: Vector2, label: String) -> void:
    walks += 1
    for i in range(600):
        await physics_frame
        var offset := Vector3(target.x-actor.position.x,0,target.y-actor.position.z)
        if offset.length()<.06:
            require(actor.is_on_floor() and absf(actor.position.y-.875)<.04,"Floor contact " + label)
            return
        actor.velocity=offset.normalized()*3;actor.velocity.y=-2;actor.move_and_slide()
    require(false,"No capsule passage " + label + " " + str(actor.position))
func mesh_bounds(mesh: MeshInstance3D, relative: Node3D) -> AABB:
    var lo := Vector3(INF,INF,INF);var hi := -lo
    for s in range(mesh.mesh.get_surface_count()):
        for vertex in mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
            var p: Vector3=relative.to_local(mesh.to_global(vertex))
            lo=lo.min(p);hi=hi.max(p)
    return AABB(lo,hi-lo)
func run() -> void:
    stage=Node3D.new();root.add_child(stage)
    var ground:=StaticBody3D.new();ground.collision_layer=16
    var gc:=CollisionShape3D.new();var gs:=BoxShape3D.new();gs.size=Vector3(40,.1,40)
    gc.shape=gs;gc.position.y=-.05;ground.add_child(gc);stage.add_child(ground)
    actor=CharacterBody3D.new();actor.collision_layer=2;actor.collision_mask=1|16
    var col:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.75
    col.shape=capsule;actor.add_child(col);stage.add_child(actor)
    camera=Camera3D.new();stage.add_child(camera);camera.make_current()
    for slug in SPECS:
        var size:Vector2=SPECS[slug]
        var house=load("res://scenes/buildings/world-architecture-v1/"+slug+".tscn").instantiate()
        stage.add_child(house);await settle(3)
        var start_walks:=walks
        var shed:bool=slug=="s_wood_store"
        var barracks:bool=slug.begins_with("s_porters")
        var inn:bool=slug=="s_caravan_inn"
        var heated:bool=not shed and not barracks
        require(house.scale==Vector3.ONE,slug+" native scale")
        require(house.wall_width==size.x and house.wall_depth==size.y,slug+" exact book dimensions")
        require(house.enterable==not shed,slug+" exact enter flag")
        var entry:float=house.entry_anchor.position.z
        require(absf(entry-(size.y/2-.18))<.001,slug+" true entry depth")
        var lo:=Vector3(INF,INF,INF);var hi:= -lo;var triangles:=0;var measured_beds:Array=[];var goods:Dictionary={}
        for node in house.find_children("*","MeshInstance3D",true,false):
            if house.lamp_assembly!=null and house.lamp_assembly.is_ancestor_of(node):continue
            var bounds:=mesh_bounds(node,house);lo=lo.min(bounds.position);hi=hi.max(bounds.end)
            for s in range(node.mesh.get_surface_count()):
                var a:Array=node.mesh.surface_get_arrays(s)
                triangles += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX]!=null and not a[Mesh.ARRAY_INDEX].is_empty() else a[Mesh.ARRAY_VERTEX].size())/3
            var semantic:String=node.get_meta("extras",{}).get("semantic","")
            if semantic=="adult_mattress":
                measured_beds.append(bounds)
                require(bounds.size.z>=2.0 and bounds.size.x>=.95,slug+" full adult mattress measured from vertices")
            if semantic not in ["","furniture","adult_mattress"]:
                var vertex_count:=0
                for surface in range(node.mesh.get_surface_count()):vertex_count+=node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size()
                require(vertex_count>24,slug+" shaped whole prop vertices, not one placeholder box: "+semantic)
                goods[semantic]=goods.get(semantic,0)+1
        require(measured_beds.size()==(4 if barracks or inn else 0),slug+" four actual adult guest/porter beds")
        var expected: Dictionary = MEASURED[slug]
        require(lo.distance_to(expected["min"])<.015 and hi.distance_to(expected["max"])<.015,slug+" deferred actual whole vertex bounds")
        require(triangles==expected["triangles"],slug+" imported rendered triangle count")
        var expected_goods:Dictionary={"s_shoemaker":["boot","last"],"s_saddler":["saddle","harness"],"s_candlemaker":["closed_pot","mould","candle"],"s_wood_store":["firewood"]}
        for semantic in expected_goods.get(slug,[]):require(goods.has(semantic),slug+" real wares missing "+semantic)
        var space:=stage.get_world_3d().direct_space_state
        var floor_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,1,1),Vector3(0,-.5,1),1))
        require(not floor_hit.is_empty() and house.is_ancestor_of(floor_hit.collider),slug+" native floor mask1, not fixture16")
        if not floor_hit.is_empty():
            var floor_shapes:Array=floor_hit.collider.find_children("*","CollisionShape3D",true,false)
            require(not floor_shapes.is_empty(),slug+" physical floor shape exists")
            var floor_shape:CollisionShape3D=floor_shapes[0] if not floor_shapes.is_empty() else null
            require(floor_shape!=null and (floor_shape.shape is ConvexPolygonShape3D or floor_shape.shape is ConcavePolygonShape3D),slug+" physical floor actual vertices available")
            if floor_shape!=null and (floor_shape.shape is ConvexPolygonShape3D or floor_shape.shape is ConcavePolygonShape3D):
                var floor_lo:=Vector3(INF,INF,INF);var floor_hi:= -floor_lo
                var floor_vertices:PackedVector3Array=floor_shape.shape.points if floor_shape.shape is ConvexPolygonShape3D else floor_shape.shape.get_faces()
                for p in floor_vertices:
                    var vertex:Vector3=house.to_local(floor_shape.to_global(p));floor_lo=floor_lo.min(vertex);floor_hi=floor_hi.max(vertex)
                require(absf(floor_hi.x-floor_lo.x-size.x)<.002 and absf(floor_hi.z-floor_lo.z-size.y)<.002,slug+" physical floor vertices exact book footprint")
        actor.position=Vector3(0,.875,entry+1.5);await settle(2)
        if shed:
            require(house.door==null and house.interior_light==null and house.lamp_assembly==null,slug+" no invented door/light")
            require(not house.set_interior_visible(false),slug+" open store must retain street-visible wood")
            house.set_interior_lights_enabled(false);house.set_interior_lights_enabled(true)
            require(house.set_interior_visible(true),slug+" nullable guard safe")
            await walk(Vector2(0,.80),slug+" open front")
            await walk(Vector2(0,-.50),slug+" wood rack aisle")
            for side in [-1.0,1.0]:
                await walk(Vector2(side*.70,-.50),slug+" rack approach")
                await walk(Vector2(0,-.50),slug+" rack return")
            # The fuel stack has real volume and rejects an adult body.
            for i in range(60):
                await physics_frame;actor.velocity=Vector3(3,-2,0);actor.move_and_slide()
            require(actor.position.x<1.02,slug+" wood stack blocks capsule")
            await walk(Vector2(0,.80),slug+" rack exit")
        else:
            require(house.door!=null and house.door.leaves.size()==7,slug+" accepted seven-part door")
            require(not house.set_interior_visible(false,true),slug+" occupied hide guard")
            var collision_count:int=house.find_children("*","CollisionShape3D",true,false).size()
            require(house.set_interior_visible(false),slug+" empty closed hiding")
            require(not house.interior_light.visible and not house.lamp_assembly.visible,slug+" hidden light assembly")
            require(collision_count==house.find_children("*","CollisionShape3D",true,false).size(),slug+" hiding preserves physics")
            for i in range(90):
                await physics_frame;actor.velocity=Vector3(0,-2,-3);actor.move_and_slide()
            require(actor.position.z>entry+.30,slug+" shut leaf blocks adult")
            actor.position=Vector3(0,.875,entry+1.5);await settle(2)
            var occupant:=CharacterBody3D.new();occupant.collision_layer=2
            var oc:=CollisionShape3D.new();oc.shape=capsule.duplicate();occupant.add_child(oc);stage.add_child(occupant)
            occupant.position=Vector3(-.25,.875,entry-.70);await settle(2)
            house.door.suspended=true
            require(not house.door.try_toggle(actor),slug+" suspended interaction guard")
            house.door.suspended=false
            require(house.door.try_toggle(actor),slug+" exterior open")
            await settle();require(house.door.blocked and house.door.fraction<1,slug+" occupied sweep cannot clip")
            require(house.interior_visible and not house.set_interior_visible(false),slug+" moving/open hide guard")
            occupant.queue_free();await settle();require(is_equal_approx(house.door.fraction,1),slug+" resumed opening")
            var lamp_lo:=INF;var lamp_hi:= -INF
            for mesh in house.lamp_assembly.find_children("*","MeshInstance3D",true,false):
                if mesh.name=="SupportCord":continue
                var bounds:=mesh_bounds(mesh,house);lamp_lo=minf(lamp_lo,bounds.position.y);lamp_hi=maxf(lamp_hi,bounds.end.y)
            require(lamp_lo>=1.85,slug+" lantern above adult heads")
            var cord=house.lamp_assembly.get_node("SupportCord")
            require(absf(cord.position.y-cord.mesh.size.y/2-lamp_hi)<.002 and absf(cord.position.y+cord.mesh.size.y/2-(house.ceiling_height-.13))<.002,slug+" supported lantern endpoints")
            camera.position=Vector3(100,2,0);await settle(40)
            house.set_interior_lights_enabled(true);require(not house.interior_light.visible,slug+" 45m sleeping light and immediate switch guard")
            camera.position=house.interior_light.global_position+Vector3(45.01,0,0);await settle(40)
            require(not house.interior_light.visible,slug+" exact 45m outer light guard")
            camera.position=house.interior_light.global_position+Vector3(44.99,0,0);await settle(40)
            require(house.interior_light.visible,slug+" exact 45m inner light guard")
            camera.position=Vector3(0,1.65,0);await settle(40);require(house.interior_light.visible,slug+" near light awake")
            house.set_interior_lights_enabled(false);require(not house.interior_light.visible,slug+" world light switch")
            house.set_interior_lights_enabled(true)
            await walk(Vector2(0,entry-.9),slug+" entry")
            await walk(Vector2(0,1.1 if inn else .65),slug+" common aisle")
            if barracks:
                for bed in measured_beds:
                    await walk(Vector2(bed.get_center().x,.65),slug+" adult bed front")
                await walk(Vector2(0,.65),slug+" sleeping return")
                await walk(Vector2(-size.x/2+2.1,1.0),slug+" common bench front")
                await walk(Vector2(0,.65),slug+" bench return")
            elif inn:
                await walk(Vector2(-1.25,2.0),slug+" hall table/benches")
                await walk(Vector2(0,1.1),slug+" hall return")
                await walk(Vector2(1.2,1.1),slug+" guest passage approach")
                await walk(Vector2(1.2,-.35),slug+" actual guest room passage")
                for bed in measured_beds:await walk(Vector2(bed.get_center().x,-.35),slug+" guest bed approach")
                await walk(Vector2(-.75,-.35),slug+" second guest passage approach")
                await walk(Vector2(-.75,1.1),slug+" second guest passage exit")
                await walk(Vector2(-.75,-.35),slug+" second guest passage return")
                await walk(Vector2(1.2,-.35),slug+" guest return")
                await walk(Vector2(1.2,1.1),slug+" guest exit passage")
                await walk(Vector2(0,1.1),slug+" common hall return")
                await walk(Vector2(5.05,1.1),slug+" common hall stove front")
                await walk(Vector2(0,1.1),slug+" stove hall return")
            else:
                await walk(Vector2(-1.8,.48),slug+" counter front")
                await walk(Vector2(0,.50),slug+" counter return")
                await walk(Vector2(-1.7,-.30),slug+" workbench front")
                await walk(Vector2(0,.50),slug+" workbench return")
                await walk(Vector2(1.45,-1.5),slug+" stove working space")
                await walk(Vector2(0,.65),slug+" stove return")
            await walk(Vector2(2.0,2.0) if inn else Vector2(size.x/2-.8,size.y/2-1.65),slug+" drying area")
            await walk(Vector2(0,entry-1.45),slug+" inside door reach")
            require(house.door.try_toggle(actor),slug+" interior close");await settle()
            require(is_zero_approx(house.door.fraction),slug+" full close")
            require(house.door.try_toggle(actor),slug+" interior open");await settle()
            require(is_equal_approx(house.door.fraction,1),slug+" other-side open")
            var window_xs:Array=[-size.x/2+1.15,size.x/2-2.1] if heated else [-size.x/2+1.15,-.50,size.x/2-1.15]
            for x in window_xs:
                var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,1.85,-size.y/2-1),Vector3(x,1.85,-size.y/2+.5),1))
                require(hit.is_empty(),slug+" real clear rear aperture "+str(x))
            if heated:
                var cx:float=size.x/2-.95;var cz:float=2.0 if inn else -(size.y/2-1)
                var gap:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(cx+.31,house.ceiling_height+.20,cz),Vector3(cx+.31,float(expected["mouth_y"])+.20,cz),1))
                require(gap.is_empty(),slug+" roof actual flue opening")
                var mouth:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(cx-.6,float(expected["mouth_y"])+.14,cz),Vector3(cx+.6,float(expected["mouth_y"])+.14,cz),1))
                require(mouth.is_empty(),slug+" open smoke mouth")
        await walk(Vector2(0,entry+2),slug+" exterior return")
        var roof:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(1,12,0),Vector3(1,0,0),1))
        require(not roof.is_empty() and roof.position.y>house.ceiling_height+.5,slug+" supported physical roof")
        results.append({"slug":slug,"actual_bounds_min":lo,"actual_bounds_max":hi,"actual_triangles":triangles,"actual_adult_beds":measured_beds.size(),"goods":goods,"walk_segments":walks-start_walks,"enter":not shed})
        print("SERVICE_VARIANT_CHECKED ",slug);house.queue_free();await settle(3)
    DirAccess.make_dir_recursive_absolute("res://local/qa/snow-service-family")
    var file:=FileAccess.open("res://local/qa/snow-service-family/result.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"failures":failures,"variants":results,"physical_walk_segments":walks,"capsule":{"height":1.75,"radius":.30},"scope":"isolated assets; no city/phone/owner art acceptance"},"  "));file.close()
    print("SERVICE_QA ","PASS" if failures.is_empty() else "FAIL"," variants=",results.size()," walks=",walks)
    quit(0 if failures.is_empty() else 1)
