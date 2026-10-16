extends Node3D
## WORLD-PROPS-01 (owner 27 Sep): Poly Haven models (CC0, reduced in Blender:
## art/blender/world-props-v1) placed over the world.
## - The desert: boulders, piles of rocks, dead quiver trees, dry branches, succulents - on sand
##   only, off roads, steep slopes and places; the big ones are solid.
## - The harbour of the lowland city (atlas: the port at map ~1130/1780, in the bay at the river
##   mouth): two large ships at anchor and a pier; the fishing hamlet's cove: a smaller ship, a pier.
const MODELS := "res://assets/environment/world-props-v1/%s.glb"
const SEED := 270927
const CELL := 10.0
const CHUNK := 100.0
## [model, chance per 10 m cell, scale range, visible to (m, at draw distance 220), solid (> 0: its own hull collides)]
const DESERT := [
	["namaqualand_boulder_03", 0.045, Vector2(1.5, 3.5), 300.0, 1.0],
	["namaqualand_boulder_04", 0.045, Vector2(1.5, 3.5), 300.0, 1.0],
	["namaqualand_boulder_05", 0.06, Vector2(1.5, 3.5), 160.0, 0.5],
	["namaqualand_boulder_06", 0.06, Vector2(1.5, 3.5), 160.0, 0.4],
	["namaqualand_boulders_01", 0.06, Vector2(2.0, 5.0), 140.0, 0.0],
	["dead_quiver_trunk", 0.014, Vector2(1.6, 2.8), 220.0, 0.2],
	["dead_quiver_branch_01", 0.04, Vector2(2.0, 3.5), 80.0, 0.0],
	["crystalline_iceplant", 0.06, Vector2(1.0, 1.8), 80.0, 0.0],
]
const PORT := Vector2(1130, 1780)
const COVE := Vector2(1690, 1848)

var world: Node3D
var counts := {}
var ships := 0
## SHIPS-SCALE-01 (owner 28 Sep: "the frigate is the size of a man"): the models are 34 m (large) and
## 24 m (medium) long, 15 heights of the ~2.3 m painted hero; a frigate of the age is 45-55 m, about
## 25 heights of a man. Scaled by 1.7 and sunk to the scaled waterline.
const SHIP_SCALE := 1.7
const SHIP_DRAFT := 2.6 * SHIP_SCALE


func build(scene: Node3D) -> void:
	world = scene
	_dress_desert()
	_harbour(PORT, ["dutch_ship_large_01", "dutch_ship_large_02"])
	_harbour(COVE, ["dutch_ship_medium"])
	print("WORLD_PROPS desert=%s ships=%d" % [counts, ships])


func _mesh_of(asset: String) -> Mesh:
	var model := (load(MODELS % asset) as PackedScene).instantiate()
	var found: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh: Mesh = found.mesh
	model.free()
	return mesh


func _ground(map: Vector2) -> float:
	return world.world_ground(map.x - world.HALF, map.y - world.HALF)


func _sea_level() -> float:
	var sea: Variant = world.world_layout.get("sea")
	return float(sea.level) if sea is Dictionary else -INF


# --- Desert ----------------------------------------------------------------------------------

func _dress_desert() -> void:
	# the caves' open vaults (Codex 417/418 SPRING-PROP-05: a boulder stood in the spring's passage):
	# [map, facing, depth to, half width] - filtered after the draws, so every other rock keeps its place
	_mouths.clear()
	if world.get("cave_mouths") != null:
		for exit in world.cave_mouths.exits():
			_mouths.append([exit.map, exit.facing, float(exit.get("depth", 9.0)) + 2.0, float(exit.get("inside_half", 3.0)) + 2.0])
	# the cities' streets (map frame) for DESERT-ROAD-PROP-03: [a, b, half width]
	_street_segs.clear()
	if world.get("snow_lots") != null:
		for street in world.snow_lots.streets:
			var pts: PackedVector2Array = street[0]
			for i in pts.size() - 1:
				_street_segs.append([pts[i], pts[i + 1], float(street[1]) * 0.5])
		# DA-FIELD01 (Codex 485): nothing random on the longbow range - its strip, run on 10 m past its end
		# over the fire-sign boulder
		_field_segs.clear()
		for field in world.snow_lots.fields:
			var fp: PackedVector2Array = field[0]
			for i in fp.size() - 1:
				var tail := (fp[i + 1] - fp[i]).normalized() * 10.0 if i == fp.size() - 2 else Vector2.ZERO
				_field_segs.append([fp[i], fp[i + 1] + tail, float(field[1]) * 0.5])
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var meshes: Array[Mesh] = []
	for item in DESERT:
		meshes.append(_mesh_of(item[0]))
		counts[item[0]] = 0
	var batches := {}
	var solid := StaticBody3D.new()
	solid.name = "DesertRocks"
	solid.set_meta("footstep_surface", "stone")
	add_child(solid)
	var offset := Vector2(world.world_root.position.x, world.world_root.position.z)
	var z := 0.0
	while z < 1570.0:
		var x := 1210.0
		while x < 2000.0:
			for k in DESERT.size():
				var item: Array = DESERT[k]
				if rng.randf() >= float(item[1]):
					continue
				var map := Vector2(x + rng.randf() * CELL, z + rng.randf() * CELL)
				var scale := rng.randf_range(item[2].x, item[2].y)
				var yaw := rng.randf_range(-PI, PI)
				if not _desert_ground(map):
					continue
				# Codex 461 DESERT-ROAD-PROP-03: a solid rock stays off every road and street with all of
				# its outline and the hero's width (its centre alone on sand let the hull reach the way)
				if float(item[4]) > 0.0 and _blocks_way(map, _reach_of(k, meshes[k]) * scale + WAY_CLEAR):
					continue
				if _on_field(map, (_reach_of(k, meshes[k]) if float(item[4]) > 0.0 else 1.0) * scale + WAY_CLEAR):
					continue
				var at := _add(batches, meshes[k], item[0], map, scale, yaw, float(item[3]))
				counts[item[0]] += 1
				if float(item[4]) > 0.0:
					# the rock's own hull, turned and scaled as drawn (Codex 450 FALLS-W5-PROP-01: a sphere of
					# radius 1.0 x scale left boulder_03's 1.54 m long side open, the hero walked into it)
					var shape := CollisionShape3D.new()
					var hull := ConvexPolygonShape3D.new()
					var points := PackedVector3Array()
					for point in _hull_of(k, meshes[k]):
						points.append(point * scale)
					hull.points = points
					shape.shape = hull
					shape.transform = Transform3D(Basis(Vector3.UP, yaw), at)
					solid.add_child(shape)
			x += CELL
		z += CELL
	_commit(batches)


var _mouths: Array = []
var _hulls := {}
var _reaches := {}
var _street_segs: Array = []
var _field_segs: Array = []


func _on_field(map: Vector2, reach: float) -> bool:
	for seg in _field_segs:
		var near := Geometry2D.get_closest_point_to_segment(map, seg[0], seg[1])
		if map.distance_to(near) <= float(seg[2]) + reach:
			return true
	return false
## The hero's capsule radius 0.28 and a little more: the clear way kept beside a solid rock.
const WAY_CLEAR := 0.4


## The farthest the model's hull reaches from its origin across the ground (any yaw).
func _reach_of(k: int, mesh: Mesh) -> float:
	if not _reaches.has(k):
		var reach := 0.0
		for point in _hull_of(k, mesh):
			reach = maxf(reach, Vector2(point.x, point.z).length())
		_reaches[k] = reach
	return _reaches[k]


## Does a circle of `reach` round `map` touch a road (the mask) or a city's street (its plan width)?
func _blocks_way(map: Vector2, reach: float) -> bool:
	for seg in _street_segs:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var near := Geometry2D.get_closest_point_to_segment(map, a, b)
		if map.distance_to(near) <= float(seg[2]) + reach:
			return true
	var origin := Vector2(world.world_root.position.x, world.world_root.position.z) - Vector2(world.HALF, world.HALF)
	for ring in [0.0, 0.5, 1.0]:
		var steps := 1 if ring == 0.0 else 12
		for i in steps:
			var a := TAU * i / steps
			var p: Vector2 = map + Vector2(cos(a), sin(a)) * reach * ring + origin
			if world.road_at(p.x, p.y) > 0.02:
				return true
	return false


## The model's simplified convex hull in its own frame (32 points), computed once per model, with every
## point also dropped 0.5 m under the model's base: the rock's sides run straight down to the ground from
## its widest outline (Codex 459 FALLS-W5-CAMERA-02: under boulder_03's rounded overhang the hero walked
## into a pocket where the camera saw only the ground).
func _hull_of(k: int, mesh: Mesh) -> PackedVector3Array:
	if not _hulls.has(k):
		var points := (mesh.create_convex_shape(true, true) as ConvexPolygonShape3D).points
		var base := INF
		for point in points:
			base = minf(base, point.y)
		var full := PackedVector3Array(points)
		for point in points:
			full.append(Vector3(point.x, base - 0.5, point.z))
		_hulls[k] = full
	return _hulls[k]


## Sand, gently sloped, off roads and away from cities and places, out of the caves' vaults.
func _desert_ground(map: Vector2) -> bool:
	for m in _mouths:
		var off: Vector2 = map - m[0]
		var depth := -off.dot(m[1])
		if depth >= -4.0 and depth <= float(m[2]) and absf(off.dot(Vector2(-m[1].y, m[1].x))) <= float(m[3]):
			return false
	var scene := Vector2(map.x - world.HALF + world.world_root.position.x, map.y - world.HALF + world.world_root.position.z)
	var colour: Color = world.grass_color(scene.x, scene.y)
	if colour.r <= colour.g or world.road_at(scene.x, scene.y) > 0.02:
		return false
	var h := _ground(map)
	if h < _sea_level() + 1.0:
		return false
	for d in [Vector2(3, 0), Vector2(0, 3)]:
		if absf(_ground(map + d) - h) > 1.6:   # steeper than ~28 deg
			return false
	for city in world.world_layout.cities:
		if map.distance_to(Vector2(float(city.spawn[0]), float(city.spawn[2])) + Vector2(world.HALF, world.HALF)) < 55.0:
			return false
	for site in world.world_layout.sites:
		if map.distance_to(Vector2(float(site.spawn[0]), float(site.spawn[2])) + Vector2(world.HALF, world.HALF)) < 25.0:
			return false
	return true


func _add(batches: Dictionary, mesh: Mesh, label: String, map: Vector2, scale: float, yaw: float, visible: float) -> Vector3:
	var chunk := Vector2i(floori(map.x / CHUNK), floori(map.y / CHUNK))
	var key := "%s_%d_%d" % [label.get_file(), chunk.x, chunk.y]
	if not batches.has(key):
		var c := (Vector2(chunk) + Vector2(0.5, 0.5)) * CHUNK
		batches[key] = {"mesh": mesh, "transforms": [], "visible": visible,
			"centre": Vector3(c.x - world.HALF, _ground(c), c.y - world.HALF)}
	var entry: Dictionary = batches[key]
	var p := Vector3(map.x - world.HALF, _ground(map) - 0.08 * scale, map.y - world.HALF)
	entry.transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), p - entry.centre))
	return p


func _commit(batches: Dictionary) -> void:
	for key in batches:
		var entry: Dictionary = batches[key]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = entry.mesh
		multi.instance_count = entry.transforms.size()
		for k in entry.transforms.size():
			multi.set_instance_transform(k, entry.transforms[k])
		var batch := MultiMeshInstance3D.new()
		batch.name = "Props_%s" % key
		batch.multimesh = multi
		batch.position = entry.centre
		batch.visibility_range_end = entry.visible
		batch.visibility_range_end_margin = 10.0
		batch.set_meta("base_visibility_end", entry.visible)
		batch.add_to_group(&"draw_distance_scaled")
		add_child(batch)


# --- Harbours --------------------------------------------------------------------------------

## Ships at anchor where the water is over 4 m deep nearest to `near`, lying along the shore; a pier
## from the nearest beach straight out into the water.
func _harbour(near: Vector2, ship_models: Array) -> void:
	var level := _sea_level()
	if level == -INF:
		return
	var shore := _nearest(near, func(m: Vector2) -> bool: return absf(_ground(m) - level) < 0.6)
	if shore == Vector2.INF:
		return
	# Out to sea: the direction in which the ground falls.
	var out := Vector2(_ground(shore + Vector2(-4, 0)) - _ground(shore + Vector2(4, 0)), _ground(shore + Vector2(0, -4)) - _ground(shore + Vector2(0, 4))).normalized()
	if out == Vector2.ZERO:
		out = Vector2.DOWN
	var pier := _place_model("modular_wooden_pier", shore + out * 9.0, atan2(out.x, out.y), level - 1.4)
	var deck := StaticBody3D.new()
	deck.name = "PierDeck"
	deck.set_meta("footstep_surface", "wood")
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 0.3, 19.0)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.transform = Transform3D(Basis(Vector3.UP, atan2(out.x, out.y)), Vector3(pier.x, level + 0.9, pier.z))
	deck.add_child(shape)
	add_child(deck)
	var along := Vector2(-out.y, out.x)
	for n in ship_models.size():
		var spot := _nearest(shore + out * 70.0 + along * (float(n) - 0.5 * (ship_models.size() - 1)) * 70.0,
			func(m: Vector2) -> bool: return _ground(m) < level - SHIP_DRAFT - 1.5)
		if spot == Vector2.INF:
			continue
		_place_model(ship_models[n], spot, atan2(along.x, along.y) + 0.15 * n, level - SHIP_DRAFT, SHIP_SCALE)
		ships += 1


func _nearest(from: Vector2, ok: Callable) -> Vector2:
	for r in range(0, 200, 4):
		for k in 24:
			var m := from + Vector2.from_angle(TAU * k / 24.0) * float(r)
			if m.x > 5.0 and m.x < 1995.0 and m.y > 5.0 and m.y < 1995.0 and ok.call(m):
				return m
	return Vector2.INF


func _place_model(asset: String, map: Vector2, yaw: float, base: float, scale: float = 1.0) -> Vector3:
	var model := (load(MODELS % asset) as PackedScene).instantiate() as Node3D
	model.name = asset
	var p := Vector3(map.x - world.HALF, base, map.y - world.HALF)
	model.position = p
	model.rotation.y = yaw
	model.scale = Vector3.ONE * scale
	for mesh in model.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).visibility_range_end = 900.0
	add_child(model)
	return p
