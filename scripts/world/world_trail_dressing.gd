extends "res://scripts/world/village_dressing.gd"
## TRAIL-01 (owner, 25 Sep): the trail from the village to the forest inn runs through a pine
## forest instead of an empty meadow. The village kit (our trees, D-090) and the Poly Haven
## forest floor, both sides of start_trail: trees and boulders past the shoulders, tufts of grass
## and small stones on the verge, nothing on any road, in the village or at the inn.
## Deterministic (own seed); batched in chunks like the village dressing.
const SEED := 250926
const TREE_BAND := Vector2(9.0, 34.0)
const FLOOR_BAND := Vector2(8.5, 30.0)
## The shoulders reach 8 m from a road's centre line; the verge is the grassy part of them.
const SHOULDER := 8.0
const TREE_SPACING := 5.0
const INN_CLEAR := 24.0
const ROAD_CELL := 12.0
const LIMITS := {"tree": 360, "boulder": 40, "log": 26, "branches": 60, "fern": 170, "stone": 90, "grass": 1600}

var world: Node3D
## Scene-frame trail points (village exit -> inn).
var trail: PackedVector3Array = PackedVector3Array()
var trail_width := 3.0
var counts: Dictionary = {}
var _roads: Dictionary = {}

func build_trail(scene: Node3D) -> void:
	world = scene
	floor_rng.seed = SEED
	for road in world.world_layout.roads:
		var points: PackedVector3Array = world._road_points(road)
		for i in points.size():
			points[i] += world.world_root.position
		if str(road.id) == "start_trail":
			trail = points
			trail_width = float(road.get("width_m", 3.0))
		for i in points.size():
			var key := _cell(Vector2(points[i].x, points[i].z))
			if not _roads.has(key): _roads[key] = []
			_roads[key].append(Vector3(points[i].x, points[i].z, float(road.get("width_m", 6.0))))
	if trail.size() < 2:
		push_error("trail dressing: no start_trail")
		return
	var inn: Vector3 = world.inn.global_position if world.inn != null else Vector3(INF, 0, INF)
	var trees: Array = [[], [], []]
	var boulders: Array = [[], []]
	var stones: Array = [[], []]
	var ferns: Array = [[], []]
	var logs: Array = []
	var branches: Array = []
	var grass: Array = []
	for key in LIMITS: counts[key] = 0
	var taken: Array[Vector2] = []
	for attempt in range(30000):
		var i := floor_rng.randi_range(0, trail.size() - 2)
		var a := trail[i]
		var b := trail[i + 1]
		var along := a.lerp(b, floor_rng.randf())
		var tangent := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var side := Vector3(-tangent.z, 0, tangent.x) * (1.0 if floor_rng.randf() < .5 else -1.0)
		var kind := _pick(attempt)
		if kind == "":
			continue
		var band: Vector2 = TREE_BAND if kind == "tree" else FLOOR_BAND
		if kind == "stone" or kind == "grass":
			band = Vector2(trail_width * .5 + .5, SHOULDER - .4)
		var d := floor_rng.randf_range(band.x, band.y)
		var at := along + side * d
		var p := Vector2(at.x, at.z)
		if _in_village(p) or Vector2(inn.x, inn.z).distance_to(p) < INN_CLEAR:
			continue
		var verge := kind == "stone" or kind == "grass"
		if _road_clearance(p) < (trail_width * .5 + .4 if verge else SHOULDER + .5):
			continue
		if kind == "tree" or kind == "boulder" or kind == "log":
			var clear := true
			for other in taken:
				if other.distance_squared_to(p) < (TREE_SPACING * TREE_SPACING if kind == "tree" else 9.0):
					clear = false
					break
			if not clear:
				continue
			taken.append(p)
		# Ground: the relief past the shoulders; on the verge the shoulder slope from road to relief.
		var ground: float = world.ground_height_local(at.x, at.z)
		if verge:
			var t := clampf((d - trail_width * .5) / (SHOULDER - trail_width * .5), 0.0, 1.0)
			ground = lerpf(along.y, ground, t)
		var y := ground - .04
		var turn := Basis(Vector3.UP, floor_rng.randf_range(-PI, PI))
		match kind:
			"tree":
				var size := floor_rng.randf_range(.85, 1.3)
				var spot := Vector3(at.x, y + .04, at.z)
				trees[floor_rng.randi_range(0, 2)].append(Transform3D(turn.scaled(Vector3.ONE * size), spot))
				tree_positions.append(spot)
				_trunk(spot, size)
			"boulder":
				var which := floor_rng.randi_range(0, 1)
				var rock := Transform3D(turn.scaled(Vector3.ONE * floor_rng.randf_range(.5, .95)), Vector3(at.x, y - .08, at.z))
				boulders[which].append(rock)
				_solid(BOULDERS[which], rock, 0.0)
			"log":
				var fallen := Transform3D(turn.scaled(Vector3.ONE * floor_rng.randf_range(1.1, 1.5)), Vector3(at.x, y, at.z))
				logs.append(fallen)
				_solid(["dead_tree_trunk", "dead_tree_trunk"], fallen, 0.0)
			"branches":
				branches.append(Transform3D(turn.scaled(Vector3.ONE * floor_rng.randf_range(.8, 1.3)), Vector3(at.x, y + .03, at.z)))
			"fern":
				ferns[floor_rng.randi_range(0, 1)].append(Transform3D(turn.scaled(Vector3.ONE * floor_rng.randf_range(.8, 1.4)), Vector3(at.x, y + .04, at.z)))
			"stone":
				stones[floor_rng.randi_range(0, 1)].append(Transform3D(turn.scaled(Vector3.ONE * floor_rng.randf_range(.25, .45)), Vector3(at.x, y, at.z)))
			"grass":
				grass.append(Transform3D(turn.scaled(Vector3.ONE * floor_rng.randf_range(.8, 1.35)), Vector3(at.x, y + .04, at.z)))
		counts[kind] += 1
	for v in 3:
		_batch(["pine_tall", "spruce", "pine_young"][v], trees[v], true, 180)
	var roots: Array = []
	for i in range(0, tree_positions.size(), 3):
		roots.append(Transform3D(Basis(Vector3.UP, floor_rng.randf_range(-PI, PI)).scaled(Vector3.ONE * floor_rng.randf_range(.8, 1.15)), tree_positions[i] - Vector3.UP * .03))
	_scatter(["pine_roots", "pine_roots_a"], roots, false, 50, 56, false)
	counts["roots"] = roots.size()
	for v in 2:
		_scatter(BOULDERS[v], boulders[v], true, 110, 56, false)
		_scatter(STONES[v], stones[v], true, 70, 56, false)
		_scatter(FERNS[v], ferns[v], false, 65, 56, true)
	_scatter(["dead_tree_trunk", "dead_tree_trunk"], logs, true, 70, 56, false)
	_scatter(["dry_branches_medium_01", "dry_branches_medium_01_a"], branches, false, 40, 56, false)
	_batch("grass", grass, false, 42)
	print("TRAIL_DRESSING ", counts)

## Which piece this attempt tries; the mix follows the limits, trees first.
func _pick(attempt: int) -> String:
	var order := ["tree", "tree", "tree", "grass", "grass", "grass", "fern", "stone", "boulder", "log", "branches", "tree"]
	var kind: String = order[attempt % order.size()]
	return kind if counts[kind] < LIMITS[kind] else ""

func _trunk(at: Vector3, size: float) -> void:
	var body := StaticBody3D.new()
	body.name = "TrailTrunk%d" % tree_positions.size()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = at + Vector3.UP * 1.2
	var shape := CollisionShape3D.new()
	var trunk := CylinderShape3D.new()
	trunk.radius = .26 * size
	trunk.height = 2.4
	shape.shape = trunk
	body.add_child(shape)
	add_child(body)

func _in_village(p: Vector2) -> bool:
	return world.VILLAGE_RECT.grow(4.0).has_point(p + world.VILLAGE_ORIGIN_MAP)

func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / ROAD_CELL), floori(p.y / ROAD_CELL))

## Distance from a point to the nearest road edge-free centre, minus half that road's width
## plus the trail's own (roads are sampled every ~2 m, so points are close enough).
func _road_clearance(p: Vector2) -> float:
	var key := _cell(p)
	var best := INF
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			for r in _roads.get(key + Vector2i(dx, dz), []):
				best = minf(best, p.distance_to(Vector2(r.x, r.y)) - (r.z - trail_width) * .5)
	return best

## Trail trees and grass sway with the village's wind materials (same meshes, same materials).
func borrow_wind(village: Node3D) -> void:
	var by_mesh := {}
	for batch in village.foliage_batches:
		by_mesh[batch.multimesh.mesh] = batch
	for batch in foliage_batches:
		var source: MultiMeshInstance3D = by_mesh.get(batch.multimesh.mesh)
		if source != null:
			batch.material_override = source.material_override
			batch.extra_cull_margin = source.extra_cull_margin
