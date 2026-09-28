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
## [model, chance per 10 m cell, scale range, visible to (m, at draw distance 220), solid radius (x scale)]
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
				var at := _add(batches, meshes[k], item[0], map, scale, yaw, float(item[3]))
				counts[item[0]] += 1
				if float(item[4]) > 0.0:
					var shape := CollisionShape3D.new()
					var sphere := SphereShape3D.new()
					sphere.radius = float(item[4]) * scale
					shape.shape = sphere
					shape.position = at + Vector3.UP * sphere.radius * 0.6
					solid.add_child(shape)
			x += CELL
		z += CELL
	_commit(batches)


## Sand, gently sloped, off roads and away from cities and places.
func _desert_ground(map: Vector2) -> bool:
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
