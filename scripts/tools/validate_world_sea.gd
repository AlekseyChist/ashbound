extends Node
## WORLD-SEA-01 checks (D-099): the sea along the south edge.
## Water surface at the sea level to the horizon, a beach and a seabed in the heights, the hero
## walks into the water and stops chest-deep saying he cannot swim, no trees in the water, the
## fishing hamlet by the water and the river ending in the bay.
const Scene = preload("res://scenes/world/world.tscn")
var world: Node3D
var failures: Array[String] = []
var checks := 0

func _ready() -> void: call_deferred("run_checks")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("WORLD_SEA_FAIL ", label)

func settle(seconds: float = .25) -> void:
	await get_tree().create_timer(seconds, false, true).timeout

## Scene point of a map point (metres), on the ground or on the given height of the world frame.
func scene_point(map: Vector2, world_y: float = NAN) -> Vector3:
	var local := Vector3(map.x - world.HALF, 0.0, map.y - world.HALF)
	local.y = world.world_ground(local.x, local.z) if is_nan(world_y) else world_y
	return world.world_root.to_global(local)

func run_checks() -> void:
	world = Scene.instantiate()
	add_child(world)
	world.atmosphere.force_pause = true
	await settle(.5)
	var sea: Node3D = world.sea
	var layout: Dictionary = world.world_layout
	check(sea != null and layout.get("sea") is Dictionary, "the world has a sea")
	var level: float = float(layout.sea.level)
	check(is_equal_approx(sea.surface.position.y, level), "the surface lies at the sea level")
	var plane: PlaneMesh = sea.surface.mesh
	check(sea.surface.position.z + plane.size.y * 0.5 > world.HALF + 5000.0, "the water goes on past the horizon")
	# Heights: beach above the water along the coast, seabed under it, the north unchanged.
	var coast: Array = layout.sea.coast
	var dry := 0
	var drowned := 0
	for p: Array in coast:
		var x := float(p[0])
		if x <= 10.0 or x >= 1990.0: continue
		# A river mouth is water inland of the coast by design; only dry land counts.
		var inland := Vector2(x - world.HALF, float(p[1]) - 30.0 - world.HALF)
		var in_river := false
		for river in layout.rivers:
			for i in river.world_points.size():
				var w: Array = river.world_points[i]
				if inland.distance_to(Vector2(w[0], w[2])) < float(river.world_widths[i]) * 0.5 + 8.0: in_river = true
		if not in_river and world.world_ground(inland.x, inland.y) <= level: drowned += 1
		if world.world_ground(x - world.HALF, float(p[1]) + 40.0 - world.HALF) >= level: dry += 1
	check(drowned == 0, "land 30 m inland of the coast is above the water (%d)" % drowned)
	check(dry == 0, "40 m out to sea the seabed is under the water (%d)" % dry)
	# The fishing hamlet stands by the water; the main river ends in the bay.
	for site in layout.sites:
		if str(site.id) == "lowland_hamlet":
			var p := Vector2(site.point[0], site.point[1])
			var near_water := false
			for dz in range(0, 80, 5):
				if world.world_ground(p.x - world.HALF, p.y + dz - world.HALF) < level: near_water = true
			check(near_water and world.world_ground(p.x - world.HALF, p.y - world.HALF) > level, "the fishing hamlet is on dry land by the water")
	for river in layout.rivers:
		if str(river.id) == "main":
			var end: Array = river.points[-1]
			check(float(end[1]) < 1800.0 and float(end[2]) <= 0.5, "the main river ends in the bay")
	# No tree in the water or on the beach line.
	var wet := 0
	for batch: MultiMeshInstance3D in world.far_forest.find_children("FarForest_*", "MultiMeshInstance3D", false, false):
		for shape: CollisionShape3D in batch.get_node("Trunks").get_children():
			var p: Vector3 = batch.position + shape.position
			if world.world_ground(p.x, p.z) < level + 2.0: wet += 1
	check(wet == 0, "no tree in the water or on the beach (%d)" % wet)
	# WORLD-EDGES-01: from the beach the hero walks into ever deeper water on the seabed and stops
	# where it would reach his chest, saying he cannot swim.
	var player: CharacterBody3D = world.player
	# The first water south of a beach at x 700 (map metres), found on the ground itself.
	var shore := INF
	for z in range(1700, 1995):
		if world.world_ground(700.0 - world.HALF, float(z) - world.HALF) < level:
			shore = float(z)
			break
	check(shore < 1990.0, "the beach at x 700 meets the water (z %.0f)" % shore)
	world.camera_rig._yaw = PI
	world.camera_rig._apply_rotation()
	player.global_position = scene_point(Vector2(700, shore - 6.0)) + Vector3.UP * 0.2
	player.velocity = Vector3.ZERO
	await settle(.3)
	player.set_move_input(Vector2.UP)
	var deepest := 0.0
	var entered := false
	for i in 40:
		await settle(.25)
		var d: float = sea.depth_at(player.global_position)
		deepest = maxf(deepest, d)
		if d > 0.3: entered = true
	player.set_move_input(Vector2.ZERO)
	var reached: float = world.world_root.to_local(player.global_position).z + world.HALF
	check(entered, "the hero walks into the water (deepest %.2f m)" % deepest)
	check(deepest <= sea.STOP_DEPTH + 0.15, "he never goes deeper than his chest (%.2f m)" % deepest)
	check(deepest > sea.STOP_DEPTH - 0.4, "he stops at the depth limit, not before (%.2f m)" % deepest)
	check(reached < 1990.0, "he stops well before the map edge (z %.1f)" % reached)
	check(world.hud.get("_message_key") == "WORLD_SEA_TOO_DEEP", "he says he would drown")
	check(not str(Localization.text("WORLD_SEA_TOO_DEEP")).begins_with("WORLD_"), "the remark is translated")
	# The mountain lake too (owner: "I walked into the lake over my head").
	var lake: Dictionary = layout.lakes[0]
	var c: Array = lake.center
	# From the dry bank south of the lake (the basin rim is under water right by the ellipse).
	var start := Vector2(float(c[0]), float(c[1]) + float(lake.radii_m[1]) + 8.0)
	while world.world_ground(start.x - world.HALF, start.y - world.HALF) < float(c[2]) + 0.3 and start.y < float(c[1]) + 200.0:
		start.y += 2.0
	world.hud.clear_message()
	world.teleport_to({"id": "lake", "spawn": [start.x - world.HALF, world.world_ground(start.x - world.HALF, start.y - world.HALF) + 0.3, start.y - world.HALF], "point": [float(c[0]), float(c[1])]})
	await settle(.5)
	player.set_move_input(Vector2.UP)
	var lake_deepest := 0.0
	for i in 40:
		await settle(.2)
		lake_deepest = maxf(lake_deepest, sea.depth_at(player.global_position))
	player.set_move_input(Vector2.ZERO)
	check(lake_deepest <= sea.STOP_DEPTH + 0.15 and world.hud.get("_message_key") == "WORLD_SEA_TOO_DEEP", "the lake stops the hero too (%.2f m)" % lake_deepest)
	print("WORLD_SEA_CHECKS checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
