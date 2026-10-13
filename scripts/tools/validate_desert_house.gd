extends SceneTree

var failures: Array[String] = []
var root3d: Node3D
var actor: CharacterBody3D

func _initialize() -> void:
    call_deferred("run")

func require(ok: bool, detail: String) -> void:
    if not ok:
        failures.append(detail)
        push_error(detail)

func walk(to: Vector2, detail: String) -> void:
    for tick in range(600):
        await physics_frame
        var offset := Vector3(to.x - actor.position.x, 0, to.y - actor.position.z)
        if offset.length() < 0.08:
            print("D_H_WALK ", detail, " ", actor.position)
            return
        actor.velocity = offset.normalized() * 2.0
        actor.velocity.y = -2.0
        actor.move_and_slide()
    require(false, "No physical passage: " + detail + " at " + str(actor.position))

func run() -> void:
    root3d = Node3D.new()
    root.add_child(root3d)
    var packed := load("res://scenes/buildings/world-architecture-v1/d_courtyard_house.tscn") as PackedScene
    require(packed != null, "GLB failed to import")
    if packed == null:
        quit(1)
        return
    var house := packed.instantiate() as Node3D
    root3d.add_child(house)
    var colliders := house.find_children("*", "CollisionShape3D", true, false)
    require(colliders.size() == 45, "Expected38 static boxes and7 moving door colliders; got " + str(colliders.size()))
    var visuals := house.find_children("*", "MeshInstance3D", true, false)
    require(visuals.size() == 17, "Expected10 static material meshes and7 door parts; got " + str(visuals.size()))
    require(house.interior_meshes.size() == 2, "Interior furniture grouping missing")
    require(not house.set_interior_visible(false, true), "Occupied house allowed hiding furniture")
    require(house.set_interior_visible(false), "Closed-house hiding failed")
    for mesh in house.interior_meshes:
        require(not mesh.visible, "Furniture remained visible")
    require(house.find_children("*", "CollisionShape3D", true, false).size() == 45, "Furniture hiding changed physics")
    require(house.set_interior_visible(true), "Furniture restore failed")
    for node in visuals:
        var mesh := node as MeshInstance3D
        require(mesh.mesh != null, "Null mesh")
        for surface in range(mesh.mesh.get_surface_count()):
            var mat := mesh.get_active_material(surface) as StandardMaterial3D
            require(mat != null, "Missing imported material")
            if mat != null and (mat.resource_name.contains("plaster") or mat.resource_name.contains("room limewash") or mat.resource_name.contains("sandstone") or mat.resource_name.contains("oak")):
                require(mat.albedo_texture != null, "Embedded paint texture lost on import: " + mat.resource_name)
                require(mat.albedo_color.r>mat.albedo_color.b+.03,"Warm material tint was lost on import: "+mat.resource_name)
            if mat != null and mat.resource_name.contains("plaster"):
                require(mat.vertex_color_use_as_albedo,"Wall weather colours were lost on import")
    var ground := StaticBody3D.new()
    var ground_col := CollisionShape3D.new()
    var ground_box := BoxShape3D.new()
    ground_box.size = Vector3(30, 0.1, 30)
    ground_col.shape = ground_box
    ground_col.position.y = -0.05
    ground.add_child(ground_col)
    root3d.add_child(ground)
    actor = CharacterBody3D.new()
    actor.collision_layer = 2
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.30
    capsule.height = 1.75
    var shape := CollisionShape3D.new()
    shape.shape = capsule
    actor.add_child(shape)
    root3d.add_child(actor)
    actor.position = Vector3(0, 0.90, 6)
    for i in range(10):
        await physics_frame
        actor.velocity = Vector3(0,-2,0)
        actor.move_and_slide()
    var door = house.get("door")
    require(door != null and door.leaves.size() == 7, "Door hinge/parts missing")
    if door == null:
        quit(1)
        return
    for i in range(90):
        await physics_frame
        actor.velocity = Vector3(0, 0, -2)
        actor.move_and_slide()
    require(actor.position.z > 4.6, "Closed door allowed passage")
    actor.position.z = 5.6
    await physics_frame
    require(house.set_interior_visible(false), "Hiding before opening failed")
    var obstacle := StaticBody3D.new()
    obstacle.collision_layer = 8
    obstacle.position = Vector3(.2, 1.2, 3.75)
    var obstacle_shape := CollisionShape3D.new()
    var obstacle_box := BoxShape3D.new()
    obstacle_box.size = Vector3(.3, 2, .3)
    obstacle_shape.shape = obstacle_box
    obstacle.add_child(obstacle_shape)
    root3d.add_child(obstacle)
    await physics_frame
    require(door.try_toggle(actor), "Exterior door interaction failed")
    for i in range(90): await physics_frame
    require(door.blocked and door.fraction < 1.0, "Door swept through obstacle")
    obstacle.queue_free()
    for i in range(90): await physics_frame
    require(is_equal_approx(door.fraction, 1.0), "Door did not open fully")
    require(house.interior_visible, "Opening did not restore furniture")
    require(not house.set_interior_visible(false), "Open portal allowed hiding furniture")
    await walk(Vector2(0,3.0), "street through main entrance")
    await walk(Vector2(0,0), "courtyard")
    await walk(Vector2(.65,-.6), "living door approach")
    await walk(Vector2(.65,-1.9), "living room threshold")
    await walk(Vector2(1.7,-2.5), "inside living room")
    await walk(Vector2(.65,-1.9), "return to room threshold")
    await walk(Vector2(.65,-.6), "room to courtyard")
    await walk(Vector2(-.7,2.1), "pantry approach")
    await walk(Vector2(-2.2,2.1), "inside pantry")
    await walk(Vector2(-.7,2.1), "pantry return")
    await walk(Vector2(0,2.3), "return outside door swing")
    require(door.try_toggle(actor), "Interior door closing failed")
    for i in range(90): await physics_frame
    require(is_zero_approx(door.fraction), "Door did not close from courtyard")
    require(door.try_toggle(actor), "Interior door opening failed")
    for i in range(90): await physics_frame
    require(is_equal_approx(door.fraction, 1.0), "Door did not open from courtyard")
    await walk(Vector2(0,6.0), "outside return")
    require(actor.is_on_floor(), "Lost floor contact")
    require(abs(actor.position.y-.875)<.08, "Wrong floor elevation")
    actor.position=Vector3(3.4,.90,3.3)
    for tick in range(90):
        await physics_frame
        actor.velocity=Vector3(2,-2,0)
        actor.move_and_slide()
    require(actor.position.x > 3.70 and actor.position.x < 3.85, "East exterior wall contact at unexpected position")
    print("D_H_BLOCKED_WALL ",actor.position)
    var report := {"failures":failures,"collision_shapes":colliders.size(),"visual_meshes":visuals.size(),"walk_segments":12,"capsule":{"radius":.30,"height":1.75},"scope":"isolated actual Godot imported asset; no campaign or phone acceptance"}
    DirAccess.make_dir_recursive_absolute("res://local/qa/world-3d-assets")
    var file := FileAccess.open("res://local/qa/world-3d-assets/result.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  "))
    if failures.is_empty():
        print("D_H_GODOT_OK colliders=45 meshes=17 walk_segments=12 door_sides=2 obstacle_stop=1 interior_guards=1")
        quit(0)
    else:
        quit(1)
