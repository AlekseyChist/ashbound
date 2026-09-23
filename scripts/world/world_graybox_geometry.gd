extends Node3D
## Graybox terrain grid: renders and collides a baked height/color grid as 40x40-cell chunks.

const CHUNK_CELLS := 40


func build(heights: PackedFloat32Array, colors: PackedColorArray, width: int, spacing: float) -> void:
	if width < 2 or spacing <= 0.0 or heights.size() != width * width or colors.size() != width * width:
		push_error("world_graybox_geometry: invalid input (width=%d spacing=%.3f h=%d c=%d)" % [width, spacing, heights.size(), colors.size()])
		return
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var half := (width - 1) * spacing * 0.5
	var cell_count := width - 1
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0

	var chunk_cols := int(ceil(float(cell_count) / float(CHUNK_CELLS)))
	for cz in range(chunk_cols):
		var z0 := cz * CHUNK_CELLS
		var z1 := mini(z0 + CHUNK_CELLS, cell_count)
		for cx in range(chunk_cols):
			var x0 := cx * CHUNK_CELLS
			var x1 := mini(x0 + CHUNK_CELLS, cell_count)
			_build_chunk(heights, colors, width, spacing, half, x0, x1, z0, z1, mat)


func _build_chunk(
	heights: PackedFloat32Array,
	colors: PackedColorArray,
	width: int,
	spacing: float,
	half: float,
	x0: int,
	x1: int,
	z0: int,
	z1: int,
	mat: StandardMaterial3D
) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var i := z * width + x
			verts.append(Vector3(x * spacing - half, heights[i], z * spacing - half))
			normals.append(_normal_at(heights, width, x, z, spacing))
			cols.append(colors[i])

	for z in range(z0, z1):
		for x in range(x0, x1):
			var a := (z - z0) * (x1 - x0 + 1) + (x - x0)
			var b := a + 1
			var c := a + (x1 - x0 + 1)
			var d := c + 1
			# Godot front faces use clockwise winding, including trimesh collision.
			idx.append_array([a, b, c, b, d, c])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.name = "Terrain_%d_%d" % [x0, z0]
	mi.add_to_group("graybox_terrain_chunk")
	mi.mesh = mesh
	mi.material_override = mat

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	mi.add_child(body)
	add_child(mi)


func _normal_at(heights: PackedFloat32Array, width: int, x: int, z: int, spacing: float) -> Vector3:
	var xm := maxi(x - 1, 0)
	var xp := mini(x + 1, width - 1)
	var zm := maxi(z - 1, 0)
	var zp := mini(z + 1, width - 1)
	var dhdx := (heights[z * width + xp] - heights[z * width + xm]) / float((xp - xm) * spacing)
	var dhdz := (heights[zp * width + x] - heights[zm * width + x]) / float((zp - zm) * spacing)
	return Vector3(-dhdx, 1.0, -dhdz).normalized()
