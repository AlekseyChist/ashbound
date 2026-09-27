extends Node
## WORLD-DRESS-01A checks (D-097): the baked forest over the world map.
## Count, clear places (roads, rivers, lake, village, cities, sites, ruins), trees on the ground,
## trunks that block the hero and a visibility range that follows the Draw distance setting.
const Scene = preload("res://scenes/world/world.tscn")
const Forest = preload("res://scripts/world/world_far_forest.gd")
var world: Node3D
var forest: Node3D
var failures: Array[String] = []
var checks := 0

func _ready() -> void: call_deferred("run_checks")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAR_FOREST_FAIL ", label)

func settle(seconds: float = .25) -> void:
	await get_tree().create_timer(seconds, false, true).timeout

func seg_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0 if ab.length_squared() == 0.0 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func polyline_distance(p: Vector2, points: Array) -> float:
	var best := INF
	for i in range(points.size() - 1):
		best = minf(best, seg_distance(p, Vector2(points[i][0], points[i][1]), Vector2(points[i + 1][0], points[i + 1][1])))
	return best

## All tree positions in map metres, from the trunk shapes the game built (the headless renderer
## does not keep MultiMesh instance transforms, physics nodes are real everywhere).
func tree_points() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for batch: MultiMeshInstance3D in forest.find_children("FarForest_*", "MultiMeshInstance3D", false, false):
		for shape: CollisionShape3D in batch.get_node("Trunks").get_children():
			var p: Vector3 = batch.position + shape.position - Vector3.UP * (Forest.TRUNK_HEIGHT * 0.5)
			result.append(Vector3(p.x + world.HALF, p.y, p.z + world.HALF))
	return result

func run_checks() -> void:
	world = Scene.instantiate()
	add_child(world)
	world.atmosphere.force_pause = true
	await settle(.5)
	forest = world.far_forest
	check(forest != null and forest.get_parent() == world.world_root, "the far forest is built in the world frame")
	var trees := tree_points()
	check(trees.size() == forest.tree_count and trees.size() > 5000, "thousands of trees (%d)" % trees.size())
	check(forest.chunk_count > 50, "trees are batched in chunks (%d)" % forest.chunk_count)
	var layout: Dictionary = world.world_layout
	var on_road := 0
	var in_river := 0
	var in_place := 0
	var floating := 0
	var village := 0
	for t in trees:
		var map := Vector2(t.x, t.z)
		for road in layout.roads:
			if polyline_distance(map, road.points) < float(road.get("width_m", 6.0)) * 0.5 + 1.0: on_road += 1
		for river in layout.rivers:
			if polyline_distance(map, river.points) < 6.0: in_river += 1
		for city in layout.cities:
			if map.distance_to(Vector2(city.point[0], city.point[1])) < 120.0: in_place += 1
		for site in layout.sites:
			if map.distance_to(Vector2(site.point[0], site.point[1])) < 20.0: in_place += 1
		if map.distance_to(Vector2(1180, 1230)) < 140.0: in_place += 1
		if world.VILLAGE_RECT.grow(60.0).has_point(map): village += 1
		var ground: float = world.world_ground(t.x - world.HALF, t.z - world.HALF)
		if absf(t.y - (ground - 0.25)) > 0.05: floating += 1
	check(on_road == 0, "no tree on a road (%d)" % on_road)
	check(in_river == 0, "no tree in a river (%d)" % in_river)
	check(in_place == 0, "cities, places and the capital ruins stay clear (%d)" % in_place)
	check(village == 0, "the village and its edge keep their own trees (%d)" % village)
	check(floating == 0, "every tree stands on the terrain (%d off)" % floating)
	# A trunk blocks: a ray at chest height hits it.
	var sample: Vector3 = trees[trees.size() / 2]
	var base: Vector3 = Vector3(sample.x - world.HALF, sample.y, sample.z - world.HALF) + world.world_root.position
	var space := world.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(base + Vector3(-3, 1.5, 0), base + Vector3(3, 1.5, 0), 1)
	query.exclude = [world.player.get_rid()]
	var hit := space.intersect_ray(query)
	check(not hit.is_empty() and hit.collider.get_parent() is MultiMeshInstance3D, "a trunk blocks the way at chest height")
	# The Draw distance setting scales the forest like the village trees.
	var batch: MultiMeshInstance3D = forest.get_child(0)
	var before: float = world.settings.draw_distance
	world.settings.draw_distance = 110.0
	world.settings.apply_distance(world)
	check(is_equal_approx(batch.visibility_range_end, Forest.VISIBLE_END * 110.0 / 220.0), "the forest follows Draw distance (%.1f)" % batch.visibility_range_end)
	world.settings.draw_distance = before
	world.settings.apply_distance(world)
	check(is_equal_approx(batch.visibility_range_end, Forest.VISIBLE_END * before / 220.0), "Draw distance restores the forest range")
	print("FAR_FOREST_CHECKS checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
