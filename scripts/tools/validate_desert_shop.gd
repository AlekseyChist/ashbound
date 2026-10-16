extends SceneTree
## Requirements-based fixture/portal/lifecycle checks; the actual-world route is separate.
var failures: Array[String] = []
var checks := 0
var house
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
	house = load("res://scenes/buildings/world-architecture-v1/d_shop_6x5.tscn").instantiate()
	room.add_child(house)
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
	actor.position = Vector3(-1.2, .03, 3.3)
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
	require(house.door.leaves.size() > 0, "Actual imported entry hinge has no moving leaf")
	require(house.interior_meshes.size() > 0, "Imported goods/furniture role missing")
	require(house.find_children("*", "OmniLight3D", true, false).size() == 1, "Shop must use one local fixture light")
	var canopy_ray := PhysicsRayQueryParameters3D.create(Vector3(-1.2, 3.35, 3.1), Vector3(-1.2, 2.3, 3.1), 1)
	var canopy_hit := room.get_world_3d().direct_space_state.intersect_ray(canopy_ray)
	require(not canopy_hit.is_empty() and str(canopy_hit.collider.name) == "EntryCanopyContact", "Opaque entry canopy is missing camera contact")
	if not canopy_hit.is_empty():
		require(absf(canopy_hit.position.y - 2.781) < .015, "Canopy contact does not follow visible sloped cloth")
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 3.035, -.2), Vector3(0, 3.25, -.2), 1)
	var hit := room.get_world_3d().direct_space_state.intersect_ray(ray)
	require(not hit.is_empty() and absf(hit.position.y - 3.04) < .015, "Lantern cord has no physical ceiling support")
	var cord := house.get_node("RoomLantern/LanternCord") as MeshInstance3D
	var cord_box := cord.mesh as BoxMesh
	require(cord_box.size.y > .05, "Lantern suspension has no positive length")
	require(absf(cord.position.y + cord_box.size.y * .5 - 3.04) < .001, "Cord misses ceiling underside")
	var body := house.get_node("LanternContact") as StaticBody3D
	var contact := body.get_child(0) as CollisionShape3D
	var contact_box := contact.shape as BoxShape3D
	require(body.position.y - contact_box.size.y * .5 > 1.85, "Lantern obstructs adult head clearance")
	var body_rid := body.get_rid()
	var collision_count: int = house.find_children("*", "CollisionShape3D", true, false).size()
	for collider in house.find_children("*", "StaticBody3D", true, false):
		if str(collider.name).begins_with("counter") or str(collider.name).begins_with("shelf") or str(collider.name).begins_with("chest"):
			require((collider.collision_layer & 8) != 0, "Furniture omitted from door swing obstacles: " + str(collider.name))
	require(not house.set_interior_visible(false, true), "Occupied shop allowed sleeping interior")
	require(house.set_interior_visible(false), "Closed empty shop refused sleeping interior")
	for mesh in house.interior_meshes:
		require(not mesh.visible, "Sleeping interior retained goods draw")
	require(not house.lamp_root.visible and not house.interior_light.visible, "Sleeping fixture/light still draws")
	require(body.get_rid() == body_rid and house.find_children("*", "CollisionShape3D", true, false).size() == collision_count, "Sleeping removed physical contacts")
	require(house.door.try_toggle(actor), "Actual door interaction rejected exterior actor")
	await settle(2)
	require(house.interior_visible, "Opening sleeping door did not wake interior")
	require(not house.set_interior_visible(false), "Moving door allowed interior sleep")
	await settle(90)
	require(house.door.fraction > .99 and not house.door.blocked, "Door failed full swing with real furniture and fixture")
	require(not house.set_interior_visible(false), "Open door allowed interior sleep")
	await walk(Vector2(-1.2, 1.3), "street through open threshold")
	await walk(Vector2(-1.2, 0), "room entry")
	require(house.door.try_toggle(actor), "Actual door interaction rejected interior actor")
	await settle(90)
	require(house.door.fraction < .01 and not house.door.blocked, "Door failed close from inside")
	require(not house.set_interior_visible(false, true), "Closed occupied interior allowed sleep")
	await walk(Vector2(0, -.8), "shelf browsing aisle")
	await walk(Vector2(1.9, .6), "counter browsing aisle")
	house.set_interior_lights_enabled(false)
	require(not house.interior_light.visible, "Disabled light still enabled")
	house.set_interior_lights_enabled(true)
	require(house.interior_light.visible, "Near visible room light did not restore")
	camera.position = Vector3(100, 3, 0)
	await settle(40)
	require(not house.interior_light.visible, "Far camera retained local light")
	house.set_interior_lights_enabled(false)
	house.set_interior_lights_enabled(true)
	require(not house.interior_light.visible, "Global toggle bypassed far-camera light gate")
	require(house.set_interior_visible(false), "Empty-state lifecycle request rejected")
	require(house.set_interior_visible(true), "Far interior restore rejected")
	require(not house.interior_light.visible, "Interior restore bypassed far-camera light gate")
	camera.position = Vector3(0, 3, 0)
	await settle(40)
	require(house.interior_light.visible, "Returning camera failed to restore light")
	require(body.get_rid() == body_rid, "Light lifecycle replaced physical fixture")
	print("DESERT_SHOP_CHECKS ", checks, " FAILURES ", failures.size())
	room.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
