extends SceneTree
## Regression: a solid closed-house staircase must actually be walkable by the normal hero.
## Run with an isolated APPDATA/user directory after importing the project. No save files are read.
var world
const TEREM_ENTRY := {"T1": Vector3(0, 1.0, 2.4), "T2": Vector3(1.6, 1.0, 1.0), "T3": Vector3(0, 1.0, 1.5), "T4": Vector3(2.0, 2.2, 4.0)}
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func _process(_delta: float) -> bool:
	if is_instance_valid(world):
		world.focus_ok = true
		world.window_focus_ok = true
		world.app_active = true
	return false

func check(ok: bool, message: String) -> void:
	checks += 1
	print("CLOSED_WALK_", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)

func walk_to(goal: Vector3, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		var delta: Vector3 = goal - world.player.global_position
		delta.y = 0
		if delta.length() < .18:
			world.player.stop_input()
			return true
		var camera: Camera3D = world.camera_rig.get_camera()
		var right := camera.global_basis.x
		var back := camera.global_basis.z
		right.y = 0
		back.y = 0
		world.player.set_move_input(Vector2(delta.normalized().dot(right.normalized()), delta.normalized().dot(back.normalized())))
		await physics_frame
	world.player.stop_input()
	return false

func put_on_ground(at: Vector3) -> void:
	var local: Vector3 = world.world_root.to_local(at)
	local.y = world.shore_ground(local.x, local.z) + .3
	world.player.global_position = world.world_root.to_global(local)
	world.player.velocity = Vector3.ZERO
	world.player.stop_input()
	world.camera_rig.snap_to_target()
	await create_timer(.35).timeout

func run() -> void:
	world = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)
	await create_timer(1.5).timeout
	var catalog := {}
	for row in preload("res://scripts/world/village_building_catalog.gd").all():
		catalog[row.id] = row
	var houses: Array[Node3D] = []
	for house in world.forest_city.get_children():
		if house is Node3D and house.has_meta("cleared_m"): houses.append(house)
	# Eighteen kit houses and the terems built so far (forest_city_terems.py): T1-T4.
	check(houses.size() == 22, "all twenty-two closed city houses are included")
	var neighbours: Array = world.find_children("Neighbour*", "Node3D", true, false)
	check(neighbours.size() == 6, "all six closed village neighbours are included")
	for house in neighbours: houses.append(house)
	for house in houses:
		var id := str(house.name)
		var kit := id.split("_")[-1] if id.begins_with("Neighbour") else id.split("_")[-2]
		# A terem is its own model: the door at the body's front (Blender y -2.4 -> +z 2.4), floor 1.0.
		var entry: Vector3 = TEREM_ENTRY[kit] if TEREM_ENTRY.has(kit) else catalog[kit].entry
		var porch := entry + Vector3(0, 0, .7)
		var start := entry + Vector3(0, 0, 4.5)
		# Start beyond the actual visible model, including any apron on a slope. Starting inside
		# a new apron would test recovery from penetration instead of a normal ground approach.
		for mesh in house.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
			var xf: Transform3D = house.global_transform.affine_inverse() * mesh.global_transform
			var bounds: AABB = xf * mesh.get_aabb()
			start.z = maxf(start.z, bounds.end.z + 1.0)
		await put_on_ground(house.to_global(start))
		var reached := await walk_to(house.to_global(porch), 5.0)
		check(reached, id + " climb from actual terrain without jumping")
		var local: Vector3 = house.to_local(world.player.global_position)
		check(reached and absf(local.y - entry.y) < .12, id + " feet stand on the visible porch")
		# Isolate the doorway check even when the approach fails: start ON the porch.
		world.player.global_position = house.to_global(porch + Vector3.UP * .08)
		world.player.velocity = Vector3.ZERO
		await create_timer(.3).timeout
		await walk_to(house.to_global(entry - Vector3(0, 0, .8)), 1.1)
		local = house.to_local(world.player.global_position)
		check(local.z >= entry.z - .12, id + " closed door blocks entry")
		check(await walk_to(house.to_global(start), 5.0), id + " descend to ground")
		var ground: Vector3 = world.world_root.to_local(world.player.global_position)
		check(absf(ground.y - world.shore_ground(ground.x, ground.z)) < .2, id + " feet return to actual terrain")
	print("CLOSED_HOUSE_WALK_DONE checks=", checks, " failures=", failures.size())
	world.queue_free()
	await process_frame
	await process_frame
	await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)
