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
    require(colliders.size() == 38, "Expected38 physical boxes; got " + str(colliders.size()))
    var visuals := house.find_children("*", "MeshInstance3D", true, false)
    require(visuals.size() == 8, "Expected8 merged material meshes; got " + str(visuals.size()))
    for node in visuals:
        var mesh := node as MeshInstance3D
        require(mesh.mesh != null, "Null mesh")
        for surface in range(mesh.mesh.get_surface_count()):
            var mat := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
            require(mat != null, "Missing imported material")
            if mat != null and (mat.resource_name.contains("plaster") or mat.resource_name.contains("sandstone") or mat.resource_name.contains("oak")):
                require(mat.albedo_texture != null, "Embedded paint texture lost on import: " + mat.resource_name)
    var ground := StaticBody3D.new()
    var ground_col := CollisionShape3D.new()
    var ground_box := BoxShape3D.new()
    ground_box.size = Vector3(30, 0.1, 30)
    ground_col.shape = ground_box
    ground_col.position.y = -0.05
    ground.add_child(ground_col)
    root3d.add_child(ground)
    actor = CharacterBody3D.new()
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
    await walk(Vector2(0,3.0), "return to entrance")
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
        print("D_H_GODOT_OK colliders=38 meshes=8 walk_segments=12")
        quit(0)
    else:
        quit(1)
