extends Node
## WORLD-VILLAGE-01 checks: the starter village on the world map (D-081).
## Seam without gaps, ground everywhere around, gentle ring, and real walks along the trails.
const Scene = preload("res://scenes/world/world.tscn")
var world: Node3D
var failures: Array[String] = []
var checks := 0
var lowest_clearance := INF

func _ready() -> void: call_deferred("run_checks")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("WORLD_VILLAGE_FAIL ", label)

func settle(seconds: float = .25) -> void:
	await get_tree().create_timer(seconds, false, true).timeout

## Height of the ground itself (village ground or world terrain), looking through houses, trees and props.
func ray_height(x: float, z: float) -> float:
	var space := world.get_world_3d().direct_space_state
	var exclude: Array[RID] = [world.player.get_rid()]
	for attempt in range(12):
		var query := PhysicsRayQueryParameters3D.create(Vector3(x, 300, z), Vector3(x, -300, z), 1)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty(): return NAN
		if str(hit.collider.get_meta("footstep_surface", "")) == "ground": return hit.position.y
		exclude.append(hit.rid)
	return NAN

func plan(point: Vector2) -> Vector3:
	var local := point - Vector2(95, 95)
	return Vector3(local.x, world.terrain.height_at(local.x, local.y), local.y)

func trail(id: String) -> Array:
	for road in world.world_layout.roads:
		if str(road.id) == id:
			var points: PackedVector3Array = world._road_points(road)
			var result: Array = []
			for p in points: result.append(p + world.world_root.position)
			return result
	return []

## Every ~6 m of a path, as waypoints.
func thin(points: Array, step: float = 6.0) -> Array:
	var result: Array = [points[0]]
	for p: Vector3 in points:
		if Vector2(p.x - result[-1].x, p.z - result[-1].z).length() >= step: result.append(p)
	if result[-1] != points[-1]: result.append(points[-1])
	return result

func drive(goal: Vector3, seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000 / Engine.time_scale)
	world.player.set_run_input(true)
	while Time.get_ticks_msec() < until:
		var at: Vector3 = world.player.global_position
		var clearance: float = at.y - world.ground_height_local(at.x, at.z)
		lowest_clearance = minf(lowest_clearance, clearance)
		var offset: Vector3 = goal - at
		offset.y = 0
		if offset.length() < .9: break
		var camera: Camera3D = world.camera_rig.get_camera()
		var right := camera.global_basis.x; right.y = 0; right = right.normalized()
		var back := camera.global_basis.z; back.y = 0; back = back.normalized()
		world.player.set_move_input(Vector2(offset.normalized().dot(right), offset.normalized().dot(back)))
		await get_tree().physics_frame
	var offset: Vector3 = goal - world.player.global_position
	offset.y = 0
	return offset.length() < 1.5

func walk(label: String, waypoints: Array) -> void:
	world.select_building(0)
	await settle(.3)
	lowest_clearance = INF
	var start_count := failures.size()
	for i in range(waypoints.size()):
		var goal: Vector3 = waypoints[i]
		var distance := Vector2(goal.x - world.player.global_position.x, goal.z - world.player.global_position.z).length()
		if not await drive(goal, distance / 3.0 + 4.0):
			var at: Vector3 = world.player.global_position
			check(false, "%s: stuck before waypoint %d/%d at local %s, map %s" % [label, i, waypoints.size(), at.round(), (Vector2(at.x, at.z) + world.VILLAGE_ORIGIN_MAP).round()])
			break
	world.player.stop_input()
	check(lowest_clearance > -0.6, "%s: hero stays on the ground (lowest %.2f m)" % [label, lowest_clearance])
	if failures.size() == start_count:
		print("WORLD_VILLAGE_WALK ", label, " ok waypoints=", waypoints.size())

func run_checks() -> void:
	world = Scene.instantiate()
	add_child(world)
	await settle(.6)
	check(world.buildings.size() == 3, "three first yards")
	var positions := [Vector3(-21.5, 0, 1.5), Vector3(13.25, .4, -19.25), Vector3(-2.5, -.5, 48)]
	for i in range(3): check(world.buildings[i].position.is_equal_approx(positions[i]), "village keeps its yard positions " + str(i))
	check(world.world_root != null and world.world_root.position.is_equal_approx(Vector3(860, -46, -430)), "world map under the village at start_hamlet")
	check_seam()
	check_coverage()
	check_ring()
	check_trail_forest()
	check_neighbours()
	Engine.max_physics_steps_per_frame = 16
	Engine.time_scale = 4.0
	var gate := plan(Vector2(83.19, 97.63))
	var street: Array = [gate]
	for p in [[82.75, 82.5], [111.25, 88.75], [131.75, 79], [145.75, 56], [157, 39.75], [187, 20.75], [198, 0]]: street.append(plan(Vector2(p[0], p[1])))
	var to_inn: Array = trail("start_trail")
	to_inn.reverse()
	await walk("village -> forest inn", street + thin(to_inn))
	check(Vector2(world.player.global_position.x, world.player.global_position.z).distance_to(Vector2(420, 1210) - world.VILLAGE_ORIGIN_MAP) < 8.0, "reached the forest inn road (420, 1210)")
	var cave: Array = [gate]
	for p in [[82.75, 82.5], [59.5, 73], [33.5, 67.25], [37.25, 50], [27.5, 34.25], [17.25, 13], [17.25, 0]]: cave.append(plan(Vector2(p[0], p[1])))
	await walk("village -> forest cave", cave + thin(trail("forest_cave_trail")))
	check(Vector2(world.player.global_position.x, world.player.global_position.z).distance_to(Vector2(115, 1170) - world.VILLAGE_ORIGIN_MAP) < 8.0, "reached the forest cave (115, 1170)")
	var barn: Array = [gate]
	for p in [[82.75, 82.5], [83.25, 102.5], [77.25, 122.5], [80, 141], [83, 175], [83, 205], [83, 235]]: barn.append(plan(Vector2(p[0], p[1])))
	await walk("village -> down the south slope", barn)
	await check_west_rim(gate)
	Engine.time_scale = 1.0
	print("WORLD_VILLAGE_CHECKS checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

## Along the whole plan edge: ground on both sides and on the line, same height across it.
func check_seam() -> void:
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var worst_pair := Vector2.ZERO
	var gaps := 0
	var samples := 0
	var edges := [[Vector2(-95, -95), Vector2(130, -95), Vector2(0, 1)], [Vector2(130, -95), Vector2(130, 80), Vector2(-1, 0)],
		[Vector2(130, 80), Vector2(-95, 80), Vector2(0, -1)], [Vector2(-95, 80), Vector2(-95, -95), Vector2(1, 0)]]
	for edge in edges:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		var inward: Vector2 = edge[2]
		var length := a.distance_to(b)
		for s in range(int(length) + 1):
			var p := a.lerp(b, s / length)
			var h_line := ray_height(p.x, p.y)
			var h_in := ray_height(p.x + inward.x * .02, p.y + inward.y * .02)
			var h_out := ray_height(p.x - inward.x * .02, p.y - inward.y * .02)
			samples += 1
			if is_nan(h_line) or is_nan(h_in) or is_nan(h_out):
				gaps += 1
				continue
			if absf(h_in - h_out) > worst:
				worst = absf(h_in - h_out)
				worst_at = p
				worst_pair = Vector2(h_in, h_out)
	print("WORLD_VILLAGE_SEAM samples=", samples, " gaps=", gaps, " worst_step=", snappedf(worst, .001), " at local ", worst_at, " inside/outside ", worst_pair)
	check(gaps == 0, "no holes along the village edge (%d)" % gaps)
	check(worst < .05, "village edge meets the world within 5 cm (worst %.3f m)" % worst)

## Every 2.5 m around the village there is ground under the hero.
func check_coverage() -> void:
	var holes := 0
	var x := -95.0 - 120.0
	while x <= 130.0 + 120.0:
		var z := -95.0 - 120.0
		while z <= 80.0 + 120.0:
			var map: Vector2 = Vector2(x, z) + world.VILLAGE_ORIGIN_MAP
			# The map itself ends 45 m west of the village; only points on the map count.
			if map.x > 0.0 and map.y > 0.0 and is_nan(ray_height(x + .37, z + .41)): holes += 1
			z += 2.5
		x += 2.5
	check(holes == 0, "ground everywhere on the map within 120 m of the village (%d holes)" % holes)

## The ring stays walkable: measured on the grid around the plan.
func check_ring() -> void:
	var slopes: Array[float] = []
	var grid: PackedFloat32Array = world.world_heights
	var w: int = world.world_width
	for zi in range(1, w - 1):
		for xi in range(1, w - 1):
			var d: float = world.pad.distance_to_rect(xi * 5.0, zi * 5.0)
			# The west rim is meant to be unclimbable; it is checked by walking into it.
			if d <= 0.0 or d > world.RING or xi * 5.0 <= world.RIM_WIDTH: continue
			var gx := (grid[zi * w + xi + 1] - grid[zi * w + xi - 1]) / 10.0
			var gz := (grid[(zi + 1) * w + xi] - grid[(zi - 1) * w + xi]) / 10.0
			slopes.append(rad_to_deg(atan(Vector2(gx, gz).length())))
	slopes.sort()
	var p95 := slopes[int(slopes.size() * .95)]
	print("WORLD_VILLAGE_RING median=", snappedf(slopes[slopes.size() / 2], .1), " p95=", snappedf(p95, .1))
	check(p95 <= 35.0, "ring 95th percentile slope <= 35° (%.1f)" % p95)

## The map ends 45 m west of the village: the hero must be stopped by the rim, not fall off the world.
func check_west_rim(gate: Vector3) -> void:
	world.select_building(0)
	await settle(.3)
	lowest_clearance = INF
	for p in [gate, plan(Vector2(82.75, 82.5)), plan(Vector2(59.5, 73)), plan(Vector2(33.5, 67.25)), plan(Vector2(0, 57.25))]:
		await drive(p, 30.0)
	await drive(plan(Vector2(0, 57.25)) + Vector3(-80, 0, 0), 12.0)
	world.player.stop_input()
	var map: Vector2 = Vector2(world.player.global_position.x, world.player.global_position.z) + world.VILLAGE_ORIGIN_MAP
	print("WORLD_VILLAGE_RIM stopped at map ", map.round())
	check(map.x > 1.0, "west rim stops the hero on the map (map x %.1f)" % map.x)
	check(lowest_clearance > -0.6, "west rim: hero stays on the ground (lowest %.2f m)" % lowest_clearance)

## TRAIL-01 (owner): a pine forest along the trail to the inn, nothing on a road, the wolf off the trail.
func check_trail_forest() -> void:
	var dressing: Node3D = world.trail_dressing
	var counts: Dictionary = dressing.counts
	check(int(counts.tree) >= 200 and int(counts.grass) >= 1000 and int(counts.fern) >= 150 and int(counts.boulder) >= 30 and int(counts.log) >= 20, "trees and forest floor along the trail " + str(counts))
	var on_road := 0
	var in_village := 0
	for tree in dressing.tree_positions:
		var p := Vector2(tree.x, tree.z)
		if dressing._road_clearance(p) < dressing.SHOULDER: on_road += 1
		if dressing._in_village(p): in_village += 1
	check(on_road == 0, "no trail tree on a road or its shoulders (%d)" % on_road)
	check(in_village == 0, "the trail forest stays out of the village (%d)" % in_village)
	var verge_on_road := 0
	for placed in dressing.floor_pieces:
		var at: Vector3 = (placed[1] as Transform3D).origin
		if dressing._road_clearance(Vector2(at.x, at.z)) < dressing.trail_width * .5 + .3: verge_on_road += 1
	check(verge_on_road == 0, "no stone, log or fern on the trail (%d)" % verge_on_road)
	var inn: Vector3 = world.inn.global_position
	var near_inn := 0
	for tree in dressing.tree_positions:
		if Vector2(tree.x - inn.x, tree.z - inn.z).length() < dressing.INN_CLEAR: near_inn += 1
	check(near_inn == 0, "the inn's clearing is free (%d)" % near_inn)
	var trunk := 0
	for body in dressing.get_children():
		if body is StaticBody3D and String(body.name).begins_with("TrailTrunk"): trunk += 1
	check(trunk == dressing.tree_positions.size(), "trail trees are solid")
	var wind := 0
	for batch in dressing.foliage_batches:
		if batch.material_override is ShaderMaterial: wind += 1
	check(wind > 0 and wind == dressing.foliage_batches.size(), "trail trees and grass sway with the village wind (%d/%d)" % [wind, dressing.foliage_batches.size()])
	var wolf: Node3D = world.combat.wolf()
	var closest := INF
	for p in dressing.trail:
		closest = minf(closest, Vector2(p.x - wolf.home.x, p.z - wolf.home.z).length())
	check(closest > 5.0, "the trail wolf waits beside the trail, not on it (%.1f m)" % closest)

## HOUSES-01 (owner): six more houses by the village roads, closed and solid, off the roads and yards.
func check_neighbours() -> void:
	var dressing: Node3D = world.dressing
	check(dressing.neighbours.size() == 6, "six neighbour houses (%d)" % dressing.neighbours.size())
	var space := world.get_world_3d().direct_space_state
	for house in dressing.neighbours:
		var p := Vector2(house.position.x, house.position.z)
		var road: Vector2 = world.terrain.road_info(p)
		check(road.x - road.y * .5 > 5.0, "%s stands off the road (%.1f m)" % [house.name, road.x - road.y * .5])
		check(not world.terrain.reserved(p, 3.0), "%s is not in a yard or at the well" % house.name)
		var top: Vector3 = house.global_position + Vector3.UP * 20.0
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, house.global_position - Vector3.UP, 1))
		check(not hit.is_empty() and hit.position.y > house.global_position.y + 1.0, "%s has a solid roof" % house.name)
		var lights: Array = house.find_children("*", "Light3D", true, false)
		check(lights.is_empty(), "%s adds no light" % house.name)
		for other in world.buildings:
			check(Vector2(other.position.x, other.position.z).distance_to(p) > 14.0, "%s keeps away from %s" % [house.name, other.name])
