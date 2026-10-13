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
            print("S_H_WALK ", detail, " ", actor.position)
            return
        actor.velocity = offset.normalized() * 2.0
        actor.velocity.y = -2.0
        actor.move_and_slide()
    require(false, "No physical passage: " + detail + " at " + str(actor.position))

func run() -> void:
    root3d = Node3D.new()
    root.add_child(root3d)
    var packed := load("res://scenes/buildings/world-architecture-v1/s_warm_house.tscn") as PackedScene
    require(packed != null, "GLB failed to import")
    if packed == null:
        quit(1)
        return
    var house := packed.instantiate() as Node3D
    root3d.add_child(house)
    var colliders := house.find_children("*", "CollisionShape3D", true, false)
    require(colliders.size() == 33, "Expected26 static and7 door colliders; got " + str(colliders.size()))
    var visuals := house.find_children("*", "MeshInstance3D", true, false)
    require(visuals.size() == 16, "Expected9 static meshes and7 door parts; got " + str(visuals.size()))
    require(house.interior_meshes.size() == 2, "Furniture role grouping missing")
    require(not house.set_interior_visible(false, true), "Occupied house allowed hiding contents")
    require(house.set_interior_visible(false), "Closed empty house did not hide furniture")
    for mesh in house.interior_meshes:
        require(not mesh.visible, "Furniture remained visible")
    require(house.find_children("*", "CollisionShape3D", true, false).size() == 33, "Interior hiding changed physics")
    require(house.set_interior_visible(true), "Furniture did not restore")
    for node in visuals:
        var mesh := node as MeshInstance3D
        require(mesh.mesh != null, "Null mesh")
        for surface in range(mesh.mesh.get_surface_count()):
            var mat := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
            require(mat != null, "Missing imported material")
            if mat != null and (mat.resource_name.contains("limewash") or mat.resource_name.contains("stone") or mat.resource_name.contains("timber") or mat.resource_name.contains("slate") or mat.resource_name.contains("boards")):
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
    for i in range(120):
        await physics_frame
        actor.velocity = Vector3(0, 0, -2)
        actor.move_and_slide()
    require(actor.position.z > 3.6, "Closed door allowed passage")
    actor.position.z = 4.6
    await physics_frame
    require(house.set_interior_visible(false), "Closed-house hiding before interaction failed")
    require(door.try_toggle(actor), "Exterior opening failed")
    for i in range(90): await physics_frame
    require(is_equal_approx(door.fraction, 1.0), "Exterior opening incomplete")
    require(house.interior_visible, "Opening did not restore hidden furniture")
    require(not house.set_interior_visible(false), "Open portal allowed hiding contents")
    await walk(Vector2(0,2.6), "street into vestibule")
    await walk(Vector2(0,1.3), "vestibule into room")
    await walk(Vector2(1.3,0), "past table")
    await walk(Vector2(1.4,-1.7), "living space")
    await walk(Vector2(1.3,0), "return past table")
    await walk(Vector2(0,1.3), "room to vestibule threshold")
    require(door.try_toggle(actor), "Interior closing failed")
    for i in range(90): await physics_frame
    require(is_zero_approx(door.fraction), "Interior closing incomplete")
    require(door.try_toggle(actor), "Interior opening failed")
    for i in range(90): await physics_frame
    require(is_equal_approx(door.fraction, 1.0), "Interior opening incomplete")
    await walk(Vector2(0,2.6), "inside vestibule on return")
    await walk(Vector2(0,6.0), "outside return")
    require(actor.is_on_floor(), "Lost floor contact")
    require(abs(actor.position.y-.875)<.08, "Wrong floor elevation")
    actor.position=Vector3(3.0,.90,2.4)
    for tick in range(90):
        await physics_frame
        actor.velocity=Vector3(2,-2,0)
        actor.move_and_slide()
    require(actor.position.x > 3.29 and actor.position.x < 3.40, "East exterior wall contact at unexpected position")
    print("S_H_BLOCKED_WALL ",actor.position)
    var ray := PhysicsRayQueryParameters3D.create(Vector3(1,10,0),Vector3(1,0,0))
    var roof_hit := root3d.get_world_3d().direct_space_state.intersect_ray(ray)
    require(not roof_hit.is_empty(), "Roof has no physical surface")
    if not roof_hit.is_empty():
        require(roof_hit.position.y>6.1 and roof_hit.position.y<6.4,"Unexpected roof contact height")
        print("S_H_ROOF_CONTACT ",roof_hit.position)
    var report := {"failures":failures,"collision_shapes":colliders.size(),"visual_meshes":visuals.size(),"walk_segments":8,"capsule":{"radius":.30,"height":1.75},"scope":"isolated actual Godot imported asset; no campaign or phone acceptance"}
    DirAccess.make_dir_recursive_absolute("res://local/qa/world-snow-assets")
    var file := FileAccess.open("res://local/qa/world-snow-assets/result.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  "))
    if failures.is_empty():
        print("S_H_GODOT_OK colliders=33 meshes=16 walk_segments=8 roof_contact=1 door_sides=2 interior_guards=1")
        quit(0)
    else:
        quit(1)
