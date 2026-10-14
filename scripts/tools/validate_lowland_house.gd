extends SceneTree
# L-H (l_town_house.tscn over the GLB, WORLD-PLAN-01 plate L): the canonical scene on its own - collisions, embedded
# photo materials with their tint, and a physical walk street -> ground floor -> stair -> upper room ->
# back out, plus wall contacts. Pattern: Codex's validate_desert_house.gd. Not a campaign or phone check.
# Movement follows the hero: no downward push on the floor, gravity in the air, 0.4 m floor snap.
# Godot frame: Blender (x, y, z) -> (x, z, -y); the entry faces +z.

const SCENE := "res://scenes/buildings/world-architecture-v1/l_town_house.tscn"
const FLOOR_TOP := 3.24
const CENTRE := 0.875             # capsule centre over the floor (height 1.75)

var failures: Array[String] = []
var actor: CharacterBody3D

func _initialize() -> void:
	call_deferred("run")

func require(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error(detail)

func walk(to: Vector2, detail: String) -> void:
	for tick in range(900):
		await physics_frame
		var offset := Vector3(to.x - actor.position.x, 0, to.y - actor.position.z)
		if offset.length() < 0.08:
			print("L_H_WALK ", detail, " ", actor.position)
			return
		step(offset.normalized() * 2.0)
	var hits := []
	for i in actor.get_slide_collision_count():
		var c := actor.get_slide_collision(i)
		hits.append("%s n=%s at %s" % [str((c.get_collider() as Node).name) if c.get_collider() is Node else "?", str(c.get_normal()), str(c.get_position())])
	require(false, "No physical passage: " + detail + " at " + str(actor.position) + " touching " + str(hits))

## One physics step the way the hero moves (courtyard_player.gd): on the floor no downward speed,
## in the air gravity 22; the floor snap reaches 0.4 m.
func step(horizontal: Vector3) -> void:
	var fall := 0.0 if actor.is_on_floor() else actor.velocity.y - 22.0 / 60.0
	actor.velocity = Vector3(horizontal.x, fall, horizontal.z)
	actor.move_and_slide()

func settle() -> void:
	actor.velocity = Vector3.ZERO
	for i in range(40):
		await physics_frame
		step(Vector3.ZERO)

func push(direction: Vector3, ticks: int) -> void:
	for tick in range(ticks):
		await physics_frame
		step(direction * 2.0)

## The mean colour of a material's imported albedo texture (times its colour), white when missing.
func _average(visuals: Array, material: String) -> Color:
	for node in visuals:
		var mesh := (node as MeshInstance3D).mesh
		for surface in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(surface) as StandardMaterial3D
			if mat == null or mat.resource_name != material or mat.albedo_texture == null:
				continue
			var image := mat.albedo_texture.get_image()
			if image.is_compressed():
				image.decompress()
			image.resize(16, 16)
			var sum := Color(0, 0, 0, 0)
			for y in 16:
				for x in 16:
					sum += image.get_pixel(x, y)
			return Color(sum.r / 256.0, sum.g / 256.0, sum.b / 256.0) * mat.albedo_color
	return Color.WHITE

func run() -> void:
	var root3d := Node3D.new()
	root.add_child(root3d)
	var packed := load(SCENE) as PackedScene
	require(packed != null, "Scene/GLB failed to load")
	if packed == null:
		quit(1)
		return
	var house := packed.instantiate() as Node3D
	root3d.add_child(house)
	var colliders := house.find_children("*", "CollisionShape3D", true, false)
	require(colliders.size() == 42, "Expected 42 collision shapes (34 boxes, stair ramp, roof, 6 door parts); got " + str(colliders.size()))
	var visuals := house.find_children("*", "MeshInstance3D", true, false)
	require(visuals.size() >= 18, "Too few visual meshes: " + str(visuals.size()))
	var door = house.get("door")
	require(door != null and door.leaves.size() == 6, "Door hinge/parts missing")
	require(house.interior_meshes.size() > 0, "No interior_furniture meshes")
	var tints := {}
	for node in visuals:
		var mesh := (node as MeshInstance3D).mesh
		require(mesh != null, "Null mesh " + str(node.name))
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(surface) as StandardMaterial3D
			require(mat != null, "Missing imported material on " + str(node.name))
			if mat == null:
				continue
			var name := mat.resource_name
			if name.contains("plaster") or name.contains("stone") or name.contains("timber") or name.contains("tile"):
				require(mat.albedo_texture != null, "Embedded texture lost on import: " + name)
			tints[name] = mat.albedo_color
	print("L_H_MATERIALS ", tints)
	# The tints are baked into the photo textures (glTF drops a Multiply node): the warm plaster has to
	# come back warm and the timber dark in the imported pixels, not only in Blender.
	var plaster := _average(visuals, "L warm plaster")
	print("L_H_PLASTER_AVG ", plaster)
	require(plaster.r > plaster.b + 0.08, "Plaster tint lost on export: " + str(plaster))
	var timber := _average(visuals, "L dark timber")
	print("L_H_TIMBER_AVG ", timber)
	require(timber.get_luminance() < 0.25, "Timber tint lost on export: " + str(timber))

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
	actor.floor_snap_length = 0.4
	# The hero's layer (village_door.gd: actors on 2, its ray looks for layer 1 only).
	actor.collision_layer = 2
	root3d.add_child(actor)

	actor.position = Vector3(-1.8, 0.9, 6.0)
	await settle()
	# The shut leaf blocks the doorway.
	await push(Vector3(0, 0, -1), 120)
	print("L_H_DOOR_SHUT ", actor.position)
	require(actor.position.z > 3.6, "Closed door allowed passage: " + str(actor.position))
	# Far interior: hidden while shut and empty; an obstacle in the swing stops the leaf.
	require(house.set_interior_visible(false), "Hiding the furniture with the door shut failed")
	require(not house.set_interior_visible(false, true), "Hiding allowed while occupied")
	var obstacle := StaticBody3D.new()
	obstacle.collision_layer = 8
	obstacle.position = Vector3(-1.4, 1.2, 2.9)
	var obstacle_shape := CollisionShape3D.new()
	var obstacle_box := BoxShape3D.new()
	obstacle_box.size = Vector3(0.3, 2.0, 0.3)
	obstacle_shape.shape = obstacle_box
	obstacle.add_child(obstacle_shape)
	root3d.add_child(obstacle)
	await physics_frame
	require(door.try_toggle(actor), "Opening the door from the street failed")
	for i in 90: await physics_frame
	require(door.blocked and door.fraction < 1.0, "The leaf swept through an obstacle")
	obstacle.queue_free()
	for i in 90: await physics_frame
	require(is_equal_approx(door.fraction, 1.0), "The door did not open fully")
	require(house.interior_visible, "Opening did not show the furniture again")
	require(not house.set_interior_visible(false), "Hiding allowed with the door open")
	await walk(Vector2(-1.8, 3.5), "street to the door")
	await walk(Vector2(-1.8, 2.2), "through the door")
	await walk(Vector2(-2.0, -2.62), "along the stair to its foot")
	await walk(Vector2(-3.05, -2.62), "stair foot")
	require(absf(actor.position.y - CENTRE) < 0.08, "Not on the ground floor at the stair foot: " + str(actor.position))
	await walk(Vector2(-3.05, 2.4), "up the stair to the landing")
	require(actor.is_on_floor(), "No floor on the landing")
	require(absf(actor.position.y - (FLOOR_TOP + CENTRE)) < 0.08, "Landing not at the upper floor: " + str(actor.position))
	await walk(Vector2(-1.0, 2.9), "landing to the window")
	await walk(Vector2(1.0, -0.5), "across the upper room")
	await walk(Vector2(1.6, 1.7), "to the bed")
	require(absf(actor.position.y - (FLOOR_TOP + CENTRE)) < 0.08, "Upper room floor height wrong: " + str(actor.position))
	await walk(Vector2(1.0, -0.5), "back across the room")
	await walk(Vector2(-1.0, 2.6), "to the landing")
	await walk(Vector2(-3.05, 2.4), "stair head")
	await walk(Vector2(-3.05, -2.62), "down the stair")
	require(absf(actor.position.y - CENTRE) < 0.08, "Not back on the ground floor: " + str(actor.position))
	await walk(Vector2(-2.0, -2.62), "off the stair")
	await walk(Vector2(-1.8, 2.2), "back to the door")
	# From inside, clear of the leaf's swing (radius 1.2 round the hinge at x -2.4, z 3.38): shut it,
	# then open it again (it swings out, away from the hero).
	await walk(Vector2(-1.6, 1.8), "clear of the door's swing")
	require(door.try_toggle(actor), "Closing the door from inside failed")
	for i in 90: await physics_frame
	require(is_zero_approx(door.fraction), "The door did not close from inside")
	require(door.try_toggle(actor), "Opening the door from inside failed")
	for i in 90: await physics_frame
	require(is_equal_approx(door.fraction, 1.0), "The door did not open from inside")
	await walk(Vector2(-1.8, 6.0), "out to the street")
	require(actor.is_on_floor(), "Lost floor contact")
	require(absf(actor.position.y - CENTRE) < 0.08, "Wrong street elevation: " + str(actor.position))

	# Wall contacts: the upper east wall (inner face x 3.78) and the ground east wall (inner face x 3.5).
	actor.position = Vector3(1.0, FLOOR_TOP + CENTRE + 0.02, -0.5)
	await settle()
	await push(Vector3(1, 0, 0), 150)
	print("L_H_UPPER_WALL ", actor.position)
	require(actor.position.x > 3.40 and actor.position.x < 3.50, "Upper east wall contact at an unexpected place: " + str(actor.position))
	require(absf(actor.position.y - (FLOOR_TOP + CENTRE)) < 0.08, "Fell through the upper floor: " + str(actor.position))
	actor.position = Vector3(0.0, CENTRE + 0.02, 1.5)
	await settle()
	await push(Vector3(1, 0, 0), 150)
	print("L_H_GROUND_WALL ", actor.position)
	require(actor.position.x > 3.12 and actor.position.x < 3.22, "Ground east wall contact at an unexpected place: " + str(actor.position))
	# The outside: walking into the rear wall from the yard stops at its outer face (y 3.5 -> z -3.5).
	actor.position = Vector3(0.0, CENTRE + 0.02, -6.0)
	await settle()
	await push(Vector3(0, 0, 1), 200)
	print("L_H_REAR_WALL ", actor.position)
	require(actor.position.z < -3.75 and actor.position.z > -3.9, "Rear exterior wall contact at an unexpected place: " + str(actor.position))

	var report := {"failures": failures, "collision_shapes": colliders.size(), "visual_meshes": visuals.size(),
		"walk_segments": 16, "door": "shut blocks, obstacle stops, opens both sides, interior guards", "materials": str(tints), "capsule": {"radius": 0.30, "height": 1.75},
		"scope": "isolated imported asset in Godot; no campaign placement, no phone check"}
	DirAccess.make_dir_recursive_absolute("res://local/qa/world-lowland-assets")
	var file := FileAccess.open("res://local/qa/world-lowland-assets/lh-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	if failures.is_empty():
		print("L_H_GODOT_OK colliders=%d meshes=%d walk_segments=16 door_sides=2 obstacle_stop=1 interior_guards=1" % [colliders.size(), visuals.size()])
		quit(0)
	else:
		quit(1)
