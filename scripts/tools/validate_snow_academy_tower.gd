extends SceneTree
## Coordinator QA: physical routes, not teleports between stair endpoints.
var actor: CharacterBody3D
var building: Node3D
var segments := 0
var clearance_samples := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> bool:
    if not ok:
        failures += 1
        push_error("ACADEMY_TOWER " + message)
    return ok
func settle(count: int = 75) -> void:
    for tick in range(count):
        await physics_frame
        actor.velocity = Vector3(0, actor.velocity.y - 9.8 / 60, 0)
        actor.move_and_slide()
func walk(target: Vector3, clearance: bool = true) -> bool:
    for tick in range(900):
        await physics_frame
        var direction := target - actor.position
        direction.y = 0
        if direction.length() < .08: break
        actor.velocity.x = direction.normalized().x * 2
        actor.velocity.z = direction.normalized().z * 2
        actor.velocity.y = -.5 if actor.is_on_floor() else actor.velocity.y - 9.8 / 60
        actor.move_and_slide()
        if clearance and tick % 12 == 0:
            var foot := actor.position - Vector3(0, .875, 0)
            var hit := actor.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(foot + Vector3(0, .20, 0), foot + Vector3(0, 2.4, 0), 1))
            clearance_samples += 1
            if not check(hit.is_empty(), "HEADROOM " + str(foot) + " hit=" + str(hit)):
                return false
    await settle(12)
    segments += 1
    print("TOWER_ROUTE ", segments, " ", actor.position)
    return check(actor.position.distance_to(target) < .22, "ROUTE target=" + str(target) + " actual=" + str(actor.position))
func toggle(portal: Node3D) -> bool:
    if not check(portal.try_toggle(actor), "Door interaction from " + str(actor.position)): return false
    await settle(90)
    return check(not portal.moving and not portal.blocked, "Door swing obstructed")
func stairs_up(x1: float, x2: float, h: float) -> bool:
    for target in [Vector3(x1,h+.875,2.4),Vector3(x1,h+.875,2),Vector3(x1,h+2.675,-1),Vector3(x1,h+2.675,-1.6),Vector3(x2,h+2.675,-1.6),Vector3(x2,h+2.675,-1),Vector3(x2,h+4.475,2),Vector3(x2,h+4.475,2.75)]:
        if not await walk(target): return false
    return true
func stairs_down(x1: float, x2: float, h: float) -> bool:
    for target in [Vector3(x2,h+4.475,2.75),Vector3(x2,h+4.475,2),Vector3(x2,h+2.675,-1),Vector3(x2,h+2.675,-1.6),Vector3(x1,h+2.675,-1.6),Vector3(x1,h+2.675,-1),Vector3(x1,h+.875,2),Vector3(x1,h+.875,2.4)]:
        if not await walk(target): return false
    return true
func run() -> void:
    building = load("res://scenes/buildings/world-architecture-v1/s_academy_tower.tscn").instantiate()
    root.add_child(building)
    var ground := StaticBody3D.new()
    var collider := CollisionShape3D.new()
    var box := BoxShape3D.new(); box.size = Vector3(40,.2,40)
    collider.shape = box; collider.position.y = -.1
    ground.add_child(collider); root.add_child(ground)
    actor = CharacterBody3D.new(); actor.collision_layer = 2
    actor.floor_snap_length = .4; actor.floor_max_angle = deg_to_rad(46)
    var capsule := CapsuleShape3D.new(); capsule.radius = .3; capsule.height = 1.75
    var shape := CollisionShape3D.new(); shape.shape = capsule; actor.add_child(shape)
    root.add_child(actor); actor.position = Vector3(0,.9,7.5)
    await settle()
    if not check(building.door.leaves.size() == 8 and building.maintenance_door.leaves.size() == 8, "Expected two independent eight-part leaves"): quit(1); return
    if not check(building.interior_lights.size() == 4, "Four supported lantern sources required"): quit(1); return
    if not check(not building.interior_meshes.is_empty(), "Furniture metadata missing"): quit(1); return
    if not check(not building.set_interior_visible(false,true), "Occupied interior allowed hiding"): quit(1); return
    if not check(building.set_interior_visible(false) and not building.lamp_root.visible, "Vacant closed hide failed"): quit(1); return
    # Closed door blocks physical capsule before interaction.
    for tick in range(90):
        await physics_frame
        actor.velocity = Vector3(0,-.5,-2); actor.move_and_slide()
    if not check(actor.position.z > 5.5, "Closed door failed to block"): quit(1); return
    if not await toggle(building.door): quit(1); return
    if not check(building.interior_visible and not building.set_interior_visible(false), "Open-door visibility guard"): quit(1); return
    for target in [Vector3(0,.875,3.6),Vector3(0,.875,2.75),Vector3(-1,.875,2.75),Vector3(-1,.875,0),Vector3(0,.875,0),Vector3(0,.875,2.75)]:
        if not await walk(target): quit(1); return
    if not await toggle(building.door): quit(1); return
    for h in [0.0,3.6,7.2]:
        if not await walk(Vector3(2.5,h+.875,2.75)): quit(1); return
        if not await stairs_up(2.5,4.05,h): quit(1); return
        if not await walk(Vector3(0,h+4.475,2.75)): quit(1); return
        if is_equal_approx(h, 3.6):
            for target in [Vector3(-3,8.075,2.75),Vector3(-3,8.075,0),Vector3(-4.4,8.075,0),Vector3(-3,8.075,0),Vector3(-3,8.075,2.75),Vector3(0,8.075,2.75)]:
                if not await walk(target): quit(1); return
        if h < 7.2:
            for target in [Vector3(-1,h+4.475,2.75),Vector3(-1,h+4.475,0),Vector3(0,h+4.475,0),Vector3(0,h+4.475,2.75)]:
                if not await walk(target): quit(1); return
            if not await walk(Vector3(0,h+4.475,0)): quit(1); return
            for tick in range(90):
                await physics_frame
                actor.velocity = Vector3(2,-.5,0); actor.move_and_slide()
            if not check(actor.position.x < 1.5 and actor.position.y > h+4.4, "Internal stairwell guard failed"): quit(1); return
            for target in [Vector3(0,h+4.475,0),Vector3(0,h+4.475,2.75)]:
                if not await walk(target): quit(1); return
    # Maintenance door from inside, exterior descent and return ascent.
    if not await walk(Vector3(3.2,11.675,2.5)): quit(1); return
    if not await toggle(building.maintenance_door): quit(1); return
    if not await walk(Vector3(6.7,11.675,2.5)): quit(1); return
    # Deliberately stand in the closing arc: the existing API must refuse
    # crushing the capsule, then complete closing once the actor steps away.
    if not check(building.maintenance_door.try_toggle(actor), "Maintenance closing request"): quit(1); return
    await settle(90)
    if not check(building.maintenance_door.blocked and building.maintenance_door.moving, "Door obstruction interlock failed"): quit(1); return
    if not await walk(Vector3(7.4,11.675,2.5)): quit(1); return
    await settle(90)
    if not check(is_zero_approx(building.maintenance_door.fraction) and not building.maintenance_door.moving, "Door failed to recover after obstruction"): quit(1); return
    for tick in range(90):
        await physics_frame
        actor.velocity = Vector3(-2,-.5,0); actor.move_and_slide()
    if not check(actor.position.x > 5.5, "Closed maintenance portal failed to block"): quit(1); return
    if not await walk(Vector3(7.4,11.675,2.5)): quit(1); return
    for h in [7.2,3.6,0.0]:
        if not await stairs_down(6.4,8.0,h): quit(1); return
        if h > 0 and not await walk(Vector3(8.0,h+.875,2.75)): quit(1); return
    for h in [0.0,3.6,7.2]:
        if not await stairs_up(6.4,8.0,h): quit(1); return
        if h < 7.2 and not await walk(Vector3(6.4,h+4.475,2.75)): quit(1); return
    # Guard blocks walking off the upper landing, with no artificial collider wall.
    if not await walk(Vector3(8.0,11.675,2.75)): quit(1); return
    for tick in range(90):
        await physics_frame
        actor.velocity = Vector3(2,-.5,0); actor.move_and_slide()
    if not check(actor.position.x < 9.05 and actor.position.y > 11.4, "Exterior landing guard failed"): quit(1); return
    if not await walk(Vector3(7.4,11.675,2.5)): quit(1); return
    if not await toggle(building.maintenance_door): quit(1); return
    if not await walk(Vector3(3.2,11.675,2.5)): quit(1); return
    if not await toggle(building.maintenance_door): quit(1); return
    for h in [7.2,3.6,0.0]:
        if not await stairs_down(2.5,4.05,h): quit(1); return
        if h > 0 and not await walk(Vector3(4.05,h+.875,2.75)): quit(1); return
    if not await walk(Vector3(0,.875,3.6)): quit(1); return
    if not await toggle(building.door): quit(1); return
    if not await walk(Vector3(0,.875,7.5)): quit(1); return
    if not await toggle(building.door): quit(1); return
    var camera := Camera3D.new(); root.add_child(camera); camera.make_current()
    camera.position = Vector3(100,20,0)
    for tick in range(40): await physics_frame
    for light in building.interior_lights:
        if not check(not light.visible, "Distant light remained active"): quit(1); return
    camera.position = Vector3(0,2,0)
    for tick in range(40): await physics_frame
    for light in building.interior_lights:
        if not check(light.visible, "Near light failed to wake"): quit(1); return
    building.set_interior_lights_enabled(false)
    for light in building.interior_lights:
        if not check(not light.visible, "Light override failed"): quit(1); return
    building.set_interior_lights_enabled(true)
    if not check(building.set_interior_visible(false) and not building.lamp_root.visible, "Final vacant hide failed"): quit(1); return
    var space := actor.get_world_3d().direct_space_state
    var niche := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-4.7,8.7,0),Vector3(-5.6,8.7,0),1))
    if not check(not niche.is_empty() and absf(niche.position.x + 5.4) < .025, "Stash niche blocked or backing missing"): quit(1); return
    var mouth := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-3.8,16,-2.8),Vector3(-3.8,14,-2.8),1))
    if not check(not mouth.is_empty() and absf(mouth.position.y - 14.56) < .025, "Chimney mouth closed or flue unsupported"): quit(1); return
    for h in [0.0,3.6,7.2]:
        var stove := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-2.8,h+.7,-2.8),Vector3(-4.4,h+.7,-2.8),1))
        if not check(not stove.is_empty() and absf(stove.position.x + 3.25) < .025, "Stove collision missing"): quit(1); return
        var support := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-1,h+3.2,0),Vector3(-1,h+3.5,0),1))
        if not check(not support.is_empty(), "Lantern ceiling support missing"): quit(1); return
    for x in [-2.2,2.2]:
        var ridge := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,14.8,0),Vector3(x,14.2,0),1))
        if not check(not ridge.is_empty() and absf(ridge.position.y - 14.5) < .025, "Lightning mast lacks ridge roof support"): quit(1); return
    var bed := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-3.6,8.6,-1.05),Vector3(-3.6,7.7,-1.05),1))
    if not check(not bed.is_empty() and absf(bed.position.y - 8.08) < .025, "Complete shaped mattress collision missing"): quit(1); return
    # The space between bed and stove is physically free at capsule height.
    var bed_gap := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-3.6,8,-1.75),Vector3(-3.6,8,-2.15),1))
    if not check(bed_gap.is_empty(), "Bed intersects stove or approach gap"): quit(1); return
    print("TOWER_NICHE_CHIMNEY_STOVES_LAMP_ROD_SUPPORT_PASS")
    # Bounds include actual vertices of all meshes, lanterns and moving leaves.
    var low := Vector3(INF,INF,INF); var high := Vector3(-INF,-INF,-INF)
    var triangles := 0
    for mesh in building.find_children("*", "MeshInstance3D", true, false):
        for surface in range(mesh.mesh.get_surface_count()):
            var arrays: Array = mesh.mesh.surface_get_arrays(surface)
            for vertex in arrays[Mesh.ARRAY_VERTEX]:
                var p: Vector3 = building.to_local(mesh.to_global(vertex))
                low = low.min(p); high = high.max(p)
            var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
            triangles += (indices.size() if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
    print("TOWER_WHOLE_VERTEX_BOUNDS min=",low," max=",high," triangles_with_lanterns=",triangles)
    print("TOWER_RUNTIME_BUDGET meshes=",building.find_children("*", "MeshInstance3D", true, false).size()," static_bodies=",building.find_children("*", "StaticBody3D", true, false).size()-building.find_children("*", "AnimatableBody3D", true, false).size()," door_bodies=",building.find_children("*", "AnimatableBody3D", true, false).size()," shadow_lights=",building.interior_lights.size())
    if not check(low.x >= -6.2 and high.x <= 9.3 and low.z >= -6.2 and high.z <= 7.3 and high.y <= 16.5, "Module escaped bounded extent"): quit(1); return
    print("ACADEMY_TOWER_PASS segments=",segments," clearance_samples=",clearance_samples," failures=",failures)
    quit(0)
