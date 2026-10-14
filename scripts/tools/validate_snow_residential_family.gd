extends SceneTree
const TYPES = ["s_home_8x6", "s_home_9x6", "s_home_8x5", "s_home_7x5", "s_home_6x5", "s_cottage_6x5"]
var failures: Array[String] = []
var actor: CharacterBody3D
var stage: Node3D
var camera: Camera3D
var results: Array = []
func _initialize() -> void: call_deferred("run")
func require(ok: bool, detail: String) -> void:
    if not ok:
        failures.append(detail)
        push_error(detail)
func settle(ticks: int = 90) -> void:
    for i in range(ticks): await physics_frame
func walk(target: Vector2, label: String) -> void:
    for i in range(450):
        await physics_frame
        var offset := Vector3(target.x - actor.position.x, 0, target.y - actor.position.z)
        if offset.length() < .07:
            require(actor.is_on_floor(), "Floor contact lost: " + label)
            require(absf(actor.position.y - .875) < .05, "Floor elevation: " + label)
            return
        actor.velocity = offset.normalized() * 3
        actor.velocity.y = -2
        actor.move_and_slide()
    require(false, "Blocked route " + label + " " + str(actor.position))
func run() -> void:
    stage = Node3D.new(); root.add_child(stage)
    var ground := StaticBody3D.new(); ground.collision_layer = 16
    var gc := CollisionShape3D.new(); var gs := BoxShape3D.new()
    gs.size = Vector3(40,.1,40); gc.shape = gs; gc.position.y = -.05
    ground.add_child(gc); stage.add_child(ground)
    actor = CharacterBody3D.new(); actor.collision_layer = 2; actor.collision_mask = 1 | 16
    var shape := CollisionShape3D.new(); var cap := CapsuleShape3D.new()
    cap.radius = .3; cap.height = 1.75; shape.shape = cap
    actor.add_child(shape); stage.add_child(actor)
    camera = Camera3D.new(); stage.add_child(camera); camera.make_current()
    for slug in TYPES:
        var packed := load("res://scenes/buildings/world-architecture-v1/" + slug + ".tscn") as PackedScene
        require(packed != null, slug + " import")
        if packed == null: continue
        var house = packed.instantiate(); stage.add_child(house)
        await settle(3)
        var fact_path: String = "res://local/qa/snow-residential-family/"+slug+".json"
        if not FileAccess.file_exists(fact_path): fact_path = "res://facts/"+slug+".json"
        require(FileAccess.file_exists(fact_path),slug+" rebuild generator to produce local measurements")
        if not FileAccess.file_exists(fact_path):
            house.queue_free()
            continue
        var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fact_path))
        var entry: float = house.door.entry.z
        require(absf(entry - (house.wall_depth/2-.18)) < .001, slug + " native entry")
        require(house.get_node_or_null("EntryAnchor") != null, slug + " root EntryAnchor")
        require(house.scale == Vector3.ONE, slug + " runtime scale")
        # Compute bounds from every actual imported vertex after transforms settle.
        var lo := Vector3(INF,INF,INF); var hi := -lo
        for node in house.find_children("*", "MeshInstance3D", true, false):
            if house.lamp_assembly.is_ancestor_of(node): continue
            for s in range(node.mesh.get_surface_count()):
                var arrays: Array = node.mesh.surface_get_arrays(s)
                for vertex in arrays[Mesh.ARRAY_VERTEX]:
                    var p: Vector3 = house.to_local(node.to_global(vertex))
                    lo = lo.min(p); hi = hi.max(p)
        var lamp_min := INF
        var lamp_top := -INF
        for mesh in house.lamp_assembly.find_children("*", "MeshInstance3D",true,false):
            if mesh.name == "SupportCord": continue
            for s in range(mesh.mesh.get_surface_count()):
                for vertex in mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
                    var p: Vector3 = house.to_local(mesh.to_global(vertex))
                    lamp_min = minf(lamp_min,p.y); lamp_top = maxf(lamp_top,p.y)
        require(lamp_min >= 1.85,slug+" lantern adult head clearance "+str(lamp_min))
        var cord = house.lamp_assembly.get_node("SupportCord")
        require(absf(cord.position.y-cord.mesh.size.y/2-lamp_top)<.002,slug+" lantern cord contact")
        require(absf(cord.position.y+cord.mesh.size.y/2-(house.ceiling_height-.13))<.002,slug+" ceiling support cord contact")
        var expected: Array = facts.whole_bounds_godot
        require(lo.distance_to(Vector3(expected[0][0],expected[0][1],expected[0][2])) < .015, slug + " whole vertex min "+str(lo))
        require(hi.distance_to(Vector3(expected[1][0],expected[1][1],expected[1][2])) < .015, slug + " whole vertex max "+str(hi))
        require(not house.interior_meshes.is_empty(), slug + " furniture metadata")
        var count: int = house.find_children("*", "CollisionShape3D",true,false).size()
        require(not house.set_interior_visible(false,true), slug + " occupied guard")
        require(house.set_interior_visible(false), slug + " empty hide")
        require(not house.lamp_assembly.visible and not house.interior_light.visible, slug + " hidden lamp")
        require(count == house.find_children("*", "CollisionShape3D",true,false).size(), slug + " physics survives hide")
        actor.position = Vector3(0,.875,entry+1.5)
        for i in range(90):
            await physics_frame
            actor.velocity = Vector3(0,-2,-3);actor.move_and_slide()
        require(actor.position.z > entry+.30, slug + " closed door blocks capsule")
        actor.position = Vector3(0,.875,entry+1.5)
        await settle(2)
        # An actual layer2 occupant in the inward sweep must jam the leaf.
        var occupant := CharacterBody3D.new(); occupant.collision_layer = 2
        var oc := CollisionShape3D.new(); oc.shape = cap.duplicate()
        occupant.add_child(oc);stage.add_child(occupant)
        occupant.position = Vector3(-.25,.875,entry-.70)
        await settle(2)
        require(house.door.try_toggle(actor), slug + " outside toggle")
        await settle()
        require(house.door.blocked and house.door.fraction < 1, slug + " sweep occupant guard")
        require(house.interior_visible and not house.set_interior_visible(false), slug + " moving/open visibility guard")
        occupant.queue_free(); await settle()
        require(is_equal_approx(house.door.fraction,1), slug + " unjam opening")
        camera.position = Vector3(100,2,0); await settle(40)
        require(not house.interior_light.visible, slug + " far light sleep")
        house.set_interior_lights_enabled(true)
        require(not house.interior_light.visible,slug+" far switch must respect distance immediately")
        camera.position = Vector3(0,1.6,0); await settle(40)
        require(house.interior_light.visible, slug + " near light resume")
        house.set_interior_lights_enabled(false)
        require(not house.interior_light.visible, slug + " light switch")
        house.set_interior_lights_enabled(true)
        await walk(Vector2(0,entry-.9),slug+" entry")
        await walk(Vector2(0,0),slug+" centre")
        # Each whole prop is approached along its clear front/side, never through it.
        var bedz: float = -(house.wall_depth/2-1.5)
        await walk(Vector2(0,bedz),slug+" beds")
        await walk(Vector2(house.wall_width/2-2.05,bedz),slug+" stove front")
        await walk(Vector2(0,bedz),slug+" back aisle")
        await walk(Vector2(0,0),slug+" centre return")
        await walk(Vector2(house.wall_width/2-1.75,.05),slug+" wash")
        await walk(Vector2(0,0),slug+" wash return")
        await walk(Vector2(0,house.wall_depth/2-1.95),slug+" front aisle")
        await walk(Vector2(-house.wall_width/2+1.15,house.wall_depth/2-1.95),slug+" table front")
        await walk(Vector2(0,house.wall_depth/2-1.95),slug+" table return")
        await walk(Vector2(house.wall_width/2-.80,house.wall_depth/2-1.65),slug+" drying front")
        await walk(Vector2(0,house.wall_depth/2-1.65),slug+" drying return")
        await walk(Vector2(0,entry-1.45),slug+" inside door reach")
        require(house.door.try_toggle(actor), slug + " inside close")
        await settle(); require(is_zero_approx(house.door.fraction),slug+" complete close")
        require(house.door.try_toggle(actor),slug+" inside open")
        await settle(); require(is_equal_approx(house.door.fraction,1),slug+" reverse side open")
        await walk(Vector2(0,entry+2),slug+" outside return")
        var space := stage.get_world_3d().direct_space_state
        var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,1,0),Vector3(0,-.5,0),1))
        require(not floor_hit.is_empty() and house.is_ancestor_of(floor_hit.collider),slug+" authored floor actual collision")
        var roof_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(1,12,0),Vector3(1,0,0),1))
        require(not roof_hit.is_empty() and roof_hit.position.y > house.ceiling_height+.5,slug+" roof collision")
        var ceiling := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,1.6,-.5),Vector3(0,4,-.5),1))
        require(not ceiling.is_empty(),slug+" closed loft")
        var cx: float = facts.stove[0]; var cz: float = -facts.stove[1]
        var mouth_y: float = facts.chimney_mouth_y + .14
        var mouth := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(cx-.6,mouth_y,cz),Vector3(cx+.6,mouth_y,cz),1))
        require(mouth.is_empty(),slug+" smoke mouth clear")
        var flue_gap := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(cx+.31,house.ceiling_height+.20,cz),Vector3(cx+.31,facts.chimney_mouth_y+.20,cz),1))
        require(flue_gap.is_empty(),slug+" roof has actual flue aperture")
        var window_xs: Array = [-house.wall_width/2+1.15]
        if slug != "s_cottage_6x5": window_xs.append(house.wall_width/2-2.1)
        for x in window_xs:
            var window_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,1.85,-house.wall_depth/2-1),Vector3(x,1.85,-house.wall_depth/2+.50),1))
            require(window_hit.is_empty(),slug+" rear window aperture unobstructed "+str(x))
        results.append({"slug":slug,"bounds_min":lo,"bounds_max":hi,"colliders":count,"routes":15,"door_sides":2,"capsule_height":1.75})
        print("FAMILY_VARIANT_CHECKED ",slug)
        house.queue_free();await settle(3)
    var report := {"failures":failures,"variants":results,"scope":"isolated native imported geometry; no full city/phone/art acceptance"}
    DirAccess.make_dir_recursive_absolute("res://local/qa/snow-residential-family")
    var output := FileAccess.open("res://local/qa/snow-residential-family/result.json",FileAccess.WRITE)
    output.store_string(JSON.stringify(report,"  "));output.close()
    print("FAMILY_QA ", "PASS" if failures.is_empty() else "FAIL", " variants=",results.size())
    quit(0 if failures.is_empty() else 1)
