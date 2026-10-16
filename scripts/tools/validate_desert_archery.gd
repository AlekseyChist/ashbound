extends SceneTree
## Physical entrances, real ceiling support and sleeping-interior lifecycle.
## The actual-world route and source-art review run separately.
var failures: Array[String] = []
var checks := 0
var pavilion
var actor: CharacterBody3D
var camera: Camera3D

func _initialize() -> void:
	run.call_deferred()

func require(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		push_error(detail)

func settle(count: int) -> void:
	for i in count:
		await physics_frame

func walk(target: Vector2, label: String) -> void:
	var reached := false
	for tick in 500:
		await physics_frame
		var delta := Vector3(target.x - actor.position.x, 0, target.y - actor.position.z)
		if delta.length() < .09:
			reached = true
			break
		actor.velocity = delta.normalized() * 2
		actor.velocity.y = -2
		actor.move_and_slide()
	require(reached, "Physical walk failed: " + label + " " + str(actor.position))

func run() -> void:
	var room := Node3D.new()
	root.add_child(room)
	pavilion = load("res://scenes/buildings/world-architecture-v1/d_archery_8x5.tscn").instantiate()
	room.add_child(pavilion)
	camera = Camera3D.new()
	camera.position = Vector3(0, 3, 0)
	room.add_child(camera)
	camera.make_current()
	actor = CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	var capsule := CapsuleShape3D.new()
	capsule.radius = .28
	capsule.height = 1.75
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = .875
	actor.add_child(shape)
	actor.position = Vector3(-1, .03, 3.4)
	room.add_child(actor)
	var ground := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(20, .1, 20)
	floor_shape.shape = floor_box
	floor_shape.position.y = -.05
	ground.add_child(floor_shape)
	room.add_child(ground)
	await settle(5)
	for node in pavilion.find_children("*", "Node3D", true, false):
		require(not (node.has_method("can_interact") and node.has_method("target_point") and node.has_method("set_highlight")), "Open pavilion fabricated an interactive door")
	require(pavilion.interior_meshes.size() > 0, "Imported furniture role missing")
	require(pavilion.find_children("*", "OmniLight3D", true, false).size() == 1, "Pavilion must use one local fixture light")
	var space := room.get_world_3d().direct_space_state
	for x in [-1.0, 0.0, 1.0]:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(x, 1.4, 3.5), Vector3(x, 1.4, 1.5), 1)
		var entry_hit := space.intersect_ray(ray)
		require((not entry_hit.is_empty()) == is_zero_approx(x), "Two open entrances and intentional central pier x=" + str(x))
	var support_ray := PhysicsRayQueryParameters3D.create(Vector3(0, 3.035, -.2), Vector3(0, 3.25, -.2), 1)
	var support := space.intersect_ray(support_ray)
	var owned_ceiling: bool = not support.is_empty() and pavilion.is_ancestor_of(support.collider)
	require(owned_ceiling, "Lantern has no own physical ceiling support")
	if owned_ceiling:
		require(absf(support.position.y - 3.04) < .005 and support.normal.dot(Vector3.UP) < -.99, "Suspension misses ceiling underside")
	var cord := pavilion.get_node("RoomLantern/LanternCord") as MeshInstance3D
	var cord_box := cord.mesh as BoxMesh
	require(cord_box.size.y > .05, "Lantern suspension has no positive length")
	require(absf(cord.position.y + cord_box.size.y * .5 - 3.04) < .001, "Cord misses ceiling underside")
	var lantern := pavilion.get_node("RoomLantern/WoodenLantern") as Node3D
	var visual_low := INF
	var visual_high := -INF
	for mesh in lantern.find_children("*", "MeshInstance3D", true, false):
		var box := (mesh as MeshInstance3D).get_aabb()
		for i in 8:
			var point: Vector3 = pavilion.to_local(mesh.to_global(box.get_endpoint(i)))
			visual_low = minf(visual_low, point.y)
			visual_high = maxf(visual_high, point.y)
	require(visual_low > 1.85, "Visible fixture obstructs adult head clearance")
	require(absf(cord.position.y - cord_box.size.y * .5 - visual_high) < .001, "Cord does not meet actual visible lantern top")
	var body := pavilion.get_node("LanternContact") as StaticBody3D
	var contact := body.get_child(0) as CollisionShape3D
	var contact_box := contact.shape as BoxShape3D
	require(body.position.y - contact_box.size.y * .5 > 1.85, "Fixture contact obstructs adult head clearance")
	var body_rid := body.get_rid()
	var collision_count: int = pavilion.find_children("*", "CollisionShape3D", true, false).size()
	require(not pavilion.set_interior_visible(false, true), "Occupied pavilion allowed sleeping interior")
	require(pavilion.set_interior_visible(false), "Empty pavilion refused sleeping interior")
	for mesh in pavilion.interior_meshes:
		require(not mesh.visible, "Sleeping interior retained furniture draw")
	require(not pavilion.lamp_root.visible and not pavilion.interior_light.visible, "Sleeping fixture/light still draws")
	require(body.get_rid() == body_rid and pavilion.find_children("*", "CollisionShape3D", true, false).size() == collision_count, "Sleeping removed physical contacts")
	# Rays and movement must still respect furniture/shell while only draws sleep.
	var pier_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 1.4, 3.5), Vector3(0, 1.4, 1.5), 1))
	require(not pier_hit.is_empty(), "Sleeping pavilion removed central pier contact")
	require(pavilion.set_interior_visible(true), "Pavilion refused waking interior")
	await walk(Vector2(-1, 1.2), "left entrance")
	await walk(Vector2(-2.35, -1), "left bow aisle")
	await walk(Vector2(0, -1), "quiver aisle")
	await walk(Vector2(2.35, -1), "right bow aisle")
	await walk(Vector2(1, 1.2), "right entrance inside")
	await walk(Vector2(1, 3.4), "right entrance exit")
	pavilion.set_interior_lights_enabled(false)
	require(not pavilion.interior_light.visible, "Disabled light still enabled")
	pavilion.set_interior_lights_enabled(true)
	require(pavilion.interior_light.visible, "Near visible pavilion light did not restore")
	camera.position = Vector3(100, 3, 0)
	await settle(40)
	require(not pavilion.interior_light.visible, "Far camera retained local light")
	pavilion.set_interior_lights_enabled(false)
	pavilion.set_interior_lights_enabled(true)
	require(not pavilion.interior_light.visible, "Global toggle bypassed far-camera gate")
	require(pavilion.set_interior_visible(false), "Empty far pavilion refused sleep")
	require(pavilion.set_interior_visible(true), "Far pavilion refused restore")
	require(not pavilion.interior_light.visible, "Interior restore bypassed far-camera gate")
	camera.position = Vector3(0, 3, 0)
	await settle(40)
	require(pavilion.interior_light.visible, "Returning camera failed to restore light")
	require(body.get_rid() == body_rid and pavilion.find_children("*", "CollisionShape3D", true, false).size() == collision_count, "Lifecycle replaced physical contacts")
	print("DESERT_ARCHERY_CHECKS ", checks, " FAILURES ", failures.size())
	room.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
