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
const CELL := 40.0
const CLIFF_STEP := 22.0
const BOULDER_STEP := 35.0
const CHUNK := 300.0
## Base visibility ends at the default draw distance (220 m); VillageSettings scales them.
const CLIFF_VISIBLE := 450.0
const BOULDER_VISIBLE := 160.0
const ROCK := Color(0.55, 0.56, 0.54)
const SNOW := Color(0.84, 0.86, 0.83)

var world: Node3D
var cliff_count := 0
var boulder_count := 0
var massif: MeshInstance3D


func build(scene: Node3D) -> void:
	world = scene
	_build_massif()
	_dress_ridge()
	print("WORLD_EDGES cliffs=%d boulders=%d" % [cliff_count, boulder_count])


## Map metres of the nearest point on the north, west or east edge, and how far outside it is.
func _edge_height(map: Vector2) -> float:
	var inside := Vector2(clampf(map.x, 0.0, 2000.0), clampf(map.y, 0.0, 2000.0))
	return world.world_ground(inside.x - world.HALF, inside.y - world.HALF)


func _massif_height(map: Vector2) -> float:
	var inside := Vector2(clampf(map.x, 0.0, 2000.0), clampf(map.y, 0.0, 2000.0))
	var out := map.distance_to(inside)
	var base := _edge_height(map)
	var noise := 0.55 + 0.25 * sin(map.x / 173.0 + map.y / 211.0) + 0.2 * cos(map.x / 97.0 - map.y / 131.0)
	var h := base + 30.0 + 280.0 * smoothstep(0.0, 500.0, out) * noise
	# Towards the south the range runs into the sea.
	var sink := smoothstep(1650.0, 1900.0, map.y)
	return lerpf(h, -25.0, sink)


func _colour(h: float) -> Color:
	var c := ROCK.lerp(SNOW, smoothstep(300.0, 380.0, h)).srgb_to_linear()
	var luminance := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	var scale := lerpf(0.24, 0.62, smoothstep(0.3, 0.7, luminance))
	return Color(c.r * scale, c.g * scale, c.b * scale, 0.0)


func _build_massif() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := -OUTER
	var hi := 2000.0 + OUTER
	var n := int((hi - lo) / CELL)
	for j in n:
		for i in n:
			var a := Vector2(lo + i * CELL, lo + j * CELL)
			var centre := a + Vector2(CELL, CELL) * 0.5
			# Only outside the map, and not out on the southern sea.
			if Rect2(0, 0, 2000, 2000).grow(-1.0).has_point(centre) or centre.y > 2000.0 + CELL:
				continue
			var quad := [a, a + Vector2(CELL, 0), a + Vector2(CELL, CELL), a + Vector2(0, CELL)]
			var p: Array[Vector3] = []
			for q: Vector2 in quad:
				var h := _massif_height(q)
				p.append(Vector3(q.x - world.HALF, h, q.y - world.HALF))
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(_colour(p[k].y))
				st.add_vertex(p[k])
	st.generate_normals()
	massif = MeshInstance3D.new()
	massif.name = "Massif"
	massif.mesh = st.commit()
	massif.material_override = world.terrain.material
	massif.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(massif)


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
			if not _near_sea(face) and not _kept_clear(face):
				var kind := rng.randi_range(0, cliffs.size() - 1)
				var scale := rng.randf_range(2.5, 4.5)
				var yaw := atan2(inward.x, inward.y) + rng.randf_range(-0.35, 0.35)
				var at := _add(batches, cliffs[kind], "cliff%d" % kind, face, scale, yaw, -2.5 * scale, CLIFF_VISIBLE)
				# Solid: the hero and the camera stay outside the rock (80 % of its bounds).
				var box := BoxShape3D.new()
				var bounds: AABB = cliffs[kind].get_aabb()
				box.size = bounds.size * scale * 0.8
				var shape := CollisionShape3D.new()
				shape.shape = box
				shape.transform = Transform3D(Basis(Vector3.UP, yaw), at + Basis(Vector3.UP, yaw) * (bounds.get_center() * scale))
				solid.add_child(shape)
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
	p.y = world.world_ground(p.x, p.z) + sink
	entry.transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), p - entry.centre))
	return p


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
