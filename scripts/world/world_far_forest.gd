extends Node3D
## WORLD-DRESS-01A (D-097): the world map outside the dressed start area reads as conifer forest.
## Positions are baked offline (art/world/far-forest-v1/bake.py -> instances.bin): forest biome,
## below the treeline, not on steep slopes, clear of roads, rivers, the lake, cities, places,
## the capital ruins, the village and the trail forest (which keep their own real trees).
## Each tree is one low-poly spruce (trunk + three cones, ~70 triangles), batched per chunk with
## a visibility range that follows the Draw distance setting; trunks block the hero.
const INSTANCES := "res://assets/world/far-forest-v1/instances.bin"
const RECORD_FLOATS := 5
## TREES-01 (owner 27 Sep): near the hero the same detailed trees as along the trail (the village
## kit, D-090) instead of the cones; the cones stay only past NEAR_END as the far silhouette.
## Chunks are small so the switch happens tree by tree, not a whole block at once.
const CHUNK := 40.0
## Base visibility end at the default draw distance of 220 m (VillageSettings.apply_distance scales it).
const VISIBLE_END := 230.0
## On a phone the detailed trees reach 80 m (S23 in the forest: 42 FPS at 110 m and draw distance 300).
var NEAR_END := 80.0 if OS.has_feature("mobile") else 110.0
const NEAR_KINDS := ["pine_tall", "spruce", "pine_young"]
## Height of a cone tree at scale 1 (the detailed kinds are scaled to match it).
const CONE_HEIGHT := 10.6
const TRUNK_RADIUS := 0.35
const TRUNK_HEIGHT := 4.0
## Linear colours matched by eye to the village spruce (D-090) in daylight.
const FOLIAGE_DARK := Color(0.020, 0.036, 0.014)
const FOLIAGE_LIGHT := Color(0.066, 0.096, 0.024)
const BARK := Color(0.070, 0.040, 0.020)

var world: Node3D
var tree_count := 0
var chunk_count := 0
var mesh: ArrayMesh
## Per near kind: [[mesh, part transform, foliage?], ...], each part scaled to CONE_HEIGHT.
var near_parts: Array = []

func build(scene: Node3D) -> void:
	world = scene
	var data := FileAccess.get_file_as_bytes(INSTANCES).to_float32_array()
	if data.is_empty():
		push_error("far forest: no %s" % INSTANCES)
		return
	mesh = _spruce_mesh()
	for kind in NEAR_KINDS:
		near_parts.append(_kind_parts(kind))
	var chunks: Dictionary = {}
	for i in range(0, data.size() - RECORD_FLOATS + 1, RECORD_FLOATS):
		var map := Vector2(data[i], data[i + 1])
		var key := Vector2i(floori(map.x / CHUNK), floori(map.y / CHUNK))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(i)
	for key: Vector2i in chunks:
		_build_chunk(key, chunks[key], data)
	print("WORLD_FAR_FOREST trees=%d chunks=%d" % [tree_count, chunk_count])


func _build_chunk(key: Vector2i, records: Array, data: PackedFloat32Array) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = records.size()
	var body := StaticBody3D.new()
	body.name = "Trunks"
	var trunk := CylinderShape3D.new()
	trunk.radius = TRUNK_RADIUS
	trunk.height = TRUNK_HEIGHT
	var centre := Vector3((key.x + 0.5) * CHUNK - world.HALF, 0.0, (key.y + 0.5) * CHUNK - world.HALF)
	centre.y = world.world_ground(centre.x, centre.z)
	for n in records.size():
		var i: int = records[n]
		var p := Vector3(data[i] - world.HALF, 0.0, data[i + 1] - world.HALF)
		# A little into the ground so no root floats on the 5 m terrain triangles.
		p.y = world.world_ground(p.x, p.z) - 0.25
		var scale: float = data[i + 2]
		var basis := Basis(Vector3.UP, data[i + 3]).scaled(Vector3.ONE * scale)
		multimesh.set_instance_transform(n, Transform3D(basis, p - centre))
		var tint: float = data[i + 4]
		multimesh.set_instance_color(n, Color(tint, tint, tint * 0.96))
		var shape := CollisionShape3D.new()
		shape.shape = trunk
		shape.position = p - centre + Vector3.UP * (TRUNK_HEIGHT * 0.5)
		body.add_child(shape)
	var batch := MultiMeshInstance3D.new()
	batch.name = "FarForest_%d_%d" % [key.x, key.y]
	batch.multimesh = multimesh
	batch.position = centre
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	batch.visibility_range_begin = NEAR_END
	batch.visibility_range_begin_margin = 5.0
	batch.visibility_range_end = VISIBLE_END
	batch.visibility_range_end_margin = 10.0
	batch.set_meta("base_visibility_begin", NEAR_END)
	batch.set_meta("base_visibility_end", VISIBLE_END)
	batch.add_to_group(&"draw_distance_scaled")
	batch.add_child(body)
	_add_near(batch, records, data, multimesh)
	body.position = Vector3.ZERO
	add_child(batch)
	tree_count += records.size()
	chunk_count += 1


## The detailed trees of one chunk: each tree gets one of the near kinds (from its record, so the
## choice never changes), placed and scaled like its cone; foliage sways with the village wind.
func _add_near(batch: MultiMeshInstance3D, records: Array, data: PackedFloat32Array, cones: MultiMesh) -> void:
	var by_kind: Array = [[], [], []]
	for n in records.size():
		var i: int = records[n]
		by_kind[int(floor(data[i] * 7.0 + data[i + 1] * 13.0)) % NEAR_KINDS.size()].append(cones.get_instance_transform(n))
	var wind := {}
	var dressing: Node = world.get("dressing")
	if dressing != null:
		for source: MultiMeshInstance3D in dressing.foliage_batches:
			wind[source.multimesh.mesh] = source
	for k in NEAR_KINDS.size():
		var list: Array = by_kind[k]
		if list.is_empty():
			continue
		for part: Array in near_parts[k]:
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = part[0]
			multi.instance_count = list.size()
			for n in list.size():
				multi.set_instance_transform(n, (list[n] as Transform3D) * (part[1] as Transform3D))
			var near := MultiMeshInstance3D.new()
			near.name = "Near_%s_%d" % [NEAR_KINDS[k], near.get_instance_id()]
			near.multimesh = multi
			near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			near.visibility_range_end = NEAR_END
			near.visibility_range_end_margin = 5.0
			near.set_meta("base_visibility_end", NEAR_END)
			near.add_to_group(&"draw_distance_scaled")
			var source: MultiMeshInstance3D = wind.get(part[0])
			if part[2] and source != null:
				near.material_override = source.material_override
				near.extra_cull_margin = source.extra_cull_margin
			batch.add_child(near)


func _kind_parts(kind: String) -> Array:
	var model := (load("res://assets/environment/village-forest-v1/%s.glb" % kind) as PackedScene).instantiate() as Node3D
	add_child(model)
	var parts: Array = []
	var top := 0.1
	# Part transforms relative to the model (the model sits under the offset world frame).
	var inverse := model.global_transform.affine_inverse()
	for child: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (inverse * child.global_transform) * child.mesh.get_aabb()
		top = maxf(top, box.end.y)
	var fit := Transform3D.IDENTITY.scaled(Vector3.ONE * (CONE_HEIGHT / top))
	for child: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var foliage: bool = child.get_meta("extras", {}).get("part_role", "") == "foliage"
		parts.append([child.mesh, fit * inverse * child.global_transform, foliage])
	model.free()
	return parts


## One spruce, about 10 m tall at scale 1: a short trunk and three stacked cones, dark at the
## bottom, lighter at the tips. Vertex colours carry the look; the instance colour varies it.
func _spruce_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cylinder(st, 0.28, 0.0, 2.2, 6, BARK)
	var tiers := [[2.9, 1.0, 5.0], [2.4, 2.8, 7.0], [1.8, 4.6, 8.8], [1.1, 6.4, 10.6]]
	for t in tiers.size():
		var tier: Array = tiers[t]
		var low := FOLIAGE_DARK.lerp(FOLIAGE_LIGHT, t * 0.2)
		_cone(st, tier[0], tier[1], tier[2], 8, low, low.lerp(FOLIAGE_LIGHT, 0.8))
	# Shared vertices give smooth cones instead of hard facets.
	st.index()
	st.generate_normals()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	st.set_material(material)
	return st.commit()


func _cylinder(st: SurfaceTool, radius: float, bottom: float, top: float, sides: int, color: Color) -> void:
	for s in sides:
		var a := TAU * s / sides
		var b := TAU * (s + 1) / sides
		var p0 := Vector3(cos(a) * radius, bottom, sin(a) * radius)
		var p1 := Vector3(cos(b) * radius, bottom, sin(b) * radius)
		var p2 := Vector3(cos(b) * radius, top, sin(b) * radius)
		var p3 := Vector3(cos(a) * radius, top, sin(a) * radius)
		for p in [p0, p2, p1, p0, p3, p2]:
			st.set_color(color)
			st.add_vertex(p)


func _cone(st: SurfaceTool, radius: float, bottom: float, tip: float, sides: int, low: Color, high: Color) -> void:
	for s in sides:
		var a := TAU * s / sides
		var b := TAU * (s + 1) / sides
		var p0 := Vector3(cos(a) * radius, bottom, sin(a) * radius)
		var p1 := Vector3(cos(b) * radius, bottom, sin(b) * radius)
		var apex := Vector3(0.0, tip, 0.0)
		st.set_color(low); st.add_vertex(p0)
		st.set_color(high); st.add_vertex(apex)
		st.set_color(low); st.add_vertex(p1)
		# The underside, so a cone seen from below on a slope is not see-through.
		# Slightly inside the rim, so it does not share (and bend) the side normals.
		var under := Vector3(0.0, bottom + 0.35, 0.0)
		st.set_color(low); st.add_vertex(p1 * Vector3(0.97, 1.0, 0.97))
		st.set_color(low); st.add_vertex(under)
		st.set_color(low); st.add_vertex(p0 * Vector3(0.97, 1.0, 0.97))
