extends Node3D
## WORLD-EDGES-01 (owner 27 Sep): the world ends in mountains on the north, west and east.
## build.py raises a ridge along those edges (steeper than the hero can climb); here it gets
## - a massif beyond the map (a coarse ring of peaks with snow), so no void shows past the edge;
## - Poly Haven cliffs (CC0, reduced in Blender: art/blender/edge-rocks-v1) on the ridge's face;
## - boulders at its foot, solid.
## The south is the sea: the massif sinks under the water there.
const ROCKS := "res://assets/environment/edge-rocks-v1/%s.glb"
const CLIFFS := ["mountainside", "namaqualand_cliff_01", "namaqualand_cliff_02"]
const BOULDER := "namaqualand_boulder_02"
const SEED := 270926
const OUTER := 1200.0
const CELL := 20.0
const CLIFF_STEP := 22.0
const BOULDER_STEP := 35.0
const CHUNK := 300.0
## Base visibility ends at the default draw distance (220 m); VillageSettings scales them.
const CLIFF_VISIBLE := 450.0
const BOULDER_VISIBLE := 160.0

var world: Node3D
var cliff_count := 0
var boulder_count := 0
var massif: MeshInstance3D


func build(scene: Node3D) -> void:
	world = scene
	_build_massif()
	_dress_ridge()
	_build_walls()
	print("WORLD_EDGES cliffs=%d boulders=%d seat=%d ms" % [cliff_count, boulder_count, seat_usec / 1000])


## Map metres of the nearest point on the north, west or east edge, and how far outside it is.
func _edge_height(map: Vector2) -> float:
	var inside := Vector2(clampf(map.x, 0.0, 2000.0), clampf(map.y, 0.0, 2000.0))
	return world.world_ground(inside.x - world.HALF, inside.y - world.HALF)


## Ridged fractal peaks rising from the ridge at the edge; the range sinks into the sea in the south.
var _noise: FastNoiseLite

func _massif_height(map: Vector2) -> float:
	var inside := Vector2(clampf(map.x, 0.0, 2000.0), clampf(map.y, 0.0, 2000.0))
	var out := map.distance_to(inside)
	var base := _edge_height(map)
	# Inside the map the range runs on under the ground, so no slit of sky shows at the seam.
	if out <= 0.0:
		return base - 4.0
	# Separate sharp peaks (the noise to the power 1.5), not an even wall along the edge; a finer
	# layer breaks the slopes into ribs and gullies.
	var peaks := pow((_noise.get_noise_2d(map.x, map.y) + 1.0) * 0.5, 1.5)
	var ribs := _noise.get_noise_2d(map.x * 4.0 + 913.0, map.y * 4.0 - 377.0)
	# A range on the horizon, not a wall overhead: it rises over 700 m to peaks up to ~350 m over
	# the edge (seen from 250 m inside the map, about 15-20 degrees up).
	var rise := smoothstep(0.0, 700.0, out)
	var h := base + (45.0 + 320.0 * peaks) * rise + 30.0 * ribs * rise
	var sink := smoothstep(1650.0, 1900.0, map.y)
	return lerpf(h, -25.0, sink)


func _build_massif() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = SEED
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0022
	_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_noise.fractal_octaves = 5
	_noise.fractal_gain = 0.5
	# One shared vertex per grid point (normals from the neighbouring heights), triangles only for the
	# cells outside the map - built straight into arrays, far faster than a SurfaceTool on a phone.
	var lo := -OUTER
	var n := int((2000.0 + 2.0 * OUTER) / CELL)
	var row := n + 1
	var heights := PackedFloat32Array()
	heights.resize(row * row)
	for j in row:
		for i in row:
			heights[j * row + i] = _massif_height(Vector2(lo + i * CELL, lo + j * CELL))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.resize(row * row)
	normals.resize(row * row)
	for j in row:
		for i in row:
			var k := j * row + i
			vertices[k] = Vector3(lo + i * CELL - world.HALF, heights[k], lo + j * CELL - world.HALF)
			var dx := heights[j * row + mini(i + 1, n)] - heights[j * row + maxi(i - 1, 0)]
			var dz := heights[mini(j + 1, n) * row + i] - heights[maxi(j - 1, 0) * row + i]
			normals[k] = Vector3(-dx, 2.0 * CELL, -dz).normalized()
	var indices := PackedInt32Array()
	for j in n:
		for i in n:
			var centre := Vector2(lo + (i + 0.5) * CELL, lo + (j + 0.5) * CELL)
			# Only outside the map, and not out on the southern sea.
			if Rect2(0, 0, 2000, 2000).grow(-2.0 * CELL).has_point(centre) or centre.y > 2000.0 + CELL:
				continue
			var a := j * row + i
			indices.append_array(PackedInt32Array([a, a + 1, a + row + 1, a, a + row + 1, a + row]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	massif = MeshInstance3D.new()
	massif.name = "Massif"
	massif.mesh = mesh
	var rock: StandardMaterial3D = _mesh_of("mountainside").surface_get_material(0)
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/world_massif.gdshader")
	material.set_shader_parameter("rock_albedo", rock.albedo_texture)
	material.set_shader_parameter("rock_normal", rock.normal_texture)
	massif.material_override = material
	# The same scanned rock on every steep slope of the map itself.
	var ground: ShaderMaterial = world.terrain.material
	ground.set_shader_parameter("use_cliff", true)
	ground.set_shader_parameter("cliff_albedo", rock.albedo_texture)
	ground.set_shader_parameter("cliff_normal", rock.normal_texture)
	massif.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(massif)


## A safety behind the ridge: invisible walls up to the sky on the north, west and east edges.
func _build_walls() -> void:
	var walls := StaticBody3D.new()
	walls.name = "EdgeWalls"
	add_child(walls)
	var span: float = 2.0 * world.HALF + 4.0
	for spec in [[Vector3(-world.HALF - 1.0, 600.0, 0.0), Vector3(2.0, 1600.0, span)],
			[Vector3(world.HALF + 1.0, 600.0, 0.0), Vector3(2.0, 1600.0, span)],
			[Vector3(0.0, 600.0, -world.HALF - 1.0), Vector3(span, 1600.0, 2.0)]]:
		var box := BoxShape3D.new()
		box.size = spec[1]
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.position = spec[0]
		walls.add_child(shape)


func _mesh_of(asset: String) -> Mesh:
	var model := (load(ROCKS % asset) as PackedScene).instantiate()
	var found: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh: Mesh = found.mesh
	model.free()
	return mesh


## Cliffs on the ridge face every CLIFF_STEP metres, facing into the map; boulders at its foot.
func _dress_ridge() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var cliffs: Array[Mesh] = []
	for c in CLIFFS:
		cliffs.append(_mesh_of(c))
	var boulder := _mesh_of(BOULDER)
	var batches := {}
	var solid := StaticBody3D.new()
	solid.name = "Rocks"
	add_child(solid)
	# Three edges: [start, direction along, inward normal].
	for side in [[Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)], [Vector2(0, 0), Vector2(0, 1), Vector2(1, 0)], [Vector2(2000, 0), Vector2(0, 1), Vector2(-1, 0)]]:
		var start: Vector2 = side[0]
		var dir: Vector2 = side[1]
		var inward: Vector2 = side[2]
		var t := 10.0
		while t < 1990.0:
			var along := start + dir * t
			# Outcrops at the foot of the ridge, sunk a quarter of their height: rock rising out of the
			# slope, never hanging over it.
			var face := along + inward * rng.randf_range(38.0, 48.0)
			var cornered := t < 60.0 or t > 1940.0
			if not cornered and not _near_sea(face) and not _kept_clear(face):
				var kind := rng.randi_range(0, cliffs.size() - 1)
				var scale := rng.randf_range(2.5, 4.5)
				var yaw := atan2(inward.x, inward.y) + rng.randf_range(-0.35, 0.35)
				var at := _add(batches, cliffs[kind], "cliff%d" % kind, face, scale, yaw, -0.6 * scale, CLIFF_VISIBLE)
				# Solid: the hero and the camera stay outside the rock (80 % of its bounds).
				var box := BoxShape3D.new()
				var bounds: AABB = cliffs[kind].get_aabb()
				box.size = bounds.size * scale * 0.8
				var shape := CollisionShape3D.new()
				shape.shape = box
				shape.transform = Transform3D(Basis(Vector3.UP, yaw), at + Basis(Vector3.UP, yaw) * (bounds.get_center() * scale))
				solid.add_child(shape)
				cliff_count += 1
			# A second row higher up the ridge covers its face with rock.
			var up := along + inward * rng.randf_range(20.0, 30.0)
			if not cornered and not _near_sea(up) and not _kept_clear(up) and rng.randf() < 0.8:
				var kind2 := rng.randi_range(0, cliffs.size() - 1)
				var scale2 := rng.randf_range(3.0, 5.0)
				var yaw2 := atan2(inward.x, inward.y) + rng.randf_range(-0.5, 0.5)
				_add(batches, cliffs[kind2], "cliff%d" % kind2, up, scale2, yaw2, -0.8 * scale2, CLIFF_VISIBLE)
				cliff_count += 1
			t += CLIFF_STEP * rng.randf_range(0.8, 1.2)
		t = 20.0
		while t < 1980.0:
			var foot := start + dir * t + inward * rng.randf_range(45.0, 60.0)
			if rng.randf() < 0.55 and not _near_sea(foot) and not _kept_clear(foot):
				var scale := rng.randf_range(1.5, 3.0)
				var at := _add(batches, boulder, "boulder", foot, scale, rng.randf_range(-PI, PI), -0.4, BOULDER_VISIBLE)
				var shape := CollisionShape3D.new()
				var sphere := SphereShape3D.new()
				sphere.radius = 1.1 * scale
				shape.shape = sphere
				shape.position = at + Vector3.UP * 0.4 * scale
				solid.add_child(shape)
				boulder_count += 1
			t += BOULDER_STEP * rng.randf_range(0.7, 1.3)
	solid.set_meta("footstep_surface", "stone")
	for key in batches:
		var entry: Dictionary = batches[key]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = entry.mesh
		multi.instance_count = entry.transforms.size()
		for k in entry.transforms.size():
			multi.set_instance_transform(k, entry.transforms[k])
		var batch := MultiMeshInstance3D.new()
		batch.name = "Edge_%s" % key
		batch.multimesh = multi
		batch.position = entry.centre
		batch.visibility_range_end = entry.visible
		batch.visibility_range_end_margin = 20.0
		batch.set_meta("base_visibility_end", entry.visible)
		batch.add_to_group(&"draw_distance_scaled")
		add_child(batch)


## Adds one rock to its chunk batch; returns its world-frame position.
func _add(batches: Dictionary, mesh: Mesh, label: String, map: Vector2, scale: float, yaw: float, sink: float, visible: float) -> Vector3:
	var chunk := Vector2i(floori(map.x / CHUNK), floori(map.y / CHUNK))
	var key := "%s_%d_%d" % [label, chunk.x, chunk.y]
	if not batches.has(key):
		var c := (Vector2(chunk) + Vector2(0.5, 0.5)) * CHUNK
		batches[key] = {"mesh": mesh, "transforms": [], "visible": visible,
			"centre": Vector3(c.x - world.HALF, world.world_ground(c.x - world.HALF, c.y - world.HALF), c.y - world.HALF)}
	var entry: Dictionary = batches[key]
	var p := Vector3(map.x - world.HALF, 0.0, map.y - world.HALF)
	# Owner 29 Sep (Forest hamlet): rocks hung in the air - the ground was sampled on a ring, but a
	# rock's underside is ragged. Every vertex of its lower part now reaches the ground under it
	# (turned and scaled as placed), then it goes a little deeper (0.15 m per unit of scale).
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
	var top := INF
	var t0 := Time.get_ticks_usec()
	for v in _underside(mesh):
		var w: Vector3 = basis * v
		top = minf(top, world.world_ground(p.x + w.x, p.z + w.z) - w.y)
	p.y = top - 0.15 * scale
	seat_usec += Time.get_ticks_usec() - t0
	entry.transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), p - entry.centre))
	return p


## The underside of a rock mesh: every distinct vertex of its lower quarter (each must reach the
## ground - a sample left hanging edges on steep slopes), cached per mesh.
var seat_usec := 0
var _undersides := {}
func _underside(mesh: Mesh) -> PackedVector3Array:
	if _undersides.has(mesh):
		return _undersides[mesh]
	var box := mesh.get_aabb()
	var cut := box.position.y + box.size.y * 0.25
	var seen := {}
	for v in mesh.get_faces():
		if v.y < cut:
			seen[v.snapped(Vector3.ONE * 0.001)] = true
	var out := PackedVector3Array(seen.keys())
	_undersides[mesh] = out
	return out


func _near_sea(map: Vector2) -> bool:
	var sea: Variant = world.world_layout.get("sea")
	if not sea is Dictionary:
		return false
	return world.world_ground(map.x - world.HALF, map.y - world.HALF) < float(sea.level) + 1.0


## The village, roads and places keep their ground.
func _kept_clear(map: Vector2) -> bool:
	if world.VILLAGE_RECT.grow(15.0).has_point(map):
		return true
	var scene := Vector2(map.x - world.HALF + world.world_root.position.x, map.y - world.HALF + world.world_root.position.z)
	return world.road_at(scene.x, scene.y) > 0.05
