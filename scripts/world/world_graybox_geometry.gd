extends Node3D
## Graybox terrain grid: renders and collides a baked height/color grid as 40x40-cell chunks.

const CHUNK_CELLS := 40


## Optional: Callable(cell_x: int, cell_z: int) -> bool; true leaves the cell out (a settlement fills it).
var skip_cell: Callable
## Optional: replaces the default vertex-colour material.
var material: Material
## Optional: footstep surface stored on every terrain collider.
var surface_meta: String = ""
## SHORE-MESH-01 (owner 28 Sep: "the banks are still triangles, zigzags"): the water line cut the
## 5 m triangles in saw teeth. Optional: refine_cell(x, z) -> bool splits a cell REFINE x REFINE;
## shore_height(world_x, world_z, coarse_height) -> float gives its inner points (the banks). Points on
## an edge towards an unrefined cell keep the coarse surface, so the two meshes meet without a crack.
var refine_cell: Callable
var shore_height: Callable
const REFINE := 4


func build(heights: PackedFloat32Array, colors: PackedColorArray, width: int, spacing: float) -> void:
	if width < 2 or spacing <= 0.0 or heights.size() != width * width or colors.size() != width * width:
		push_error("world_graybox_geometry: invalid input (width=%d spacing=%.3f h=%d c=%d)" % [width, spacing, heights.size(), colors.size()])
		return
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var half := (width - 1) * spacing * 0.5
	var cell_count := width - 1
	var mat: Material = material
	if mat == null:
		var standard := StandardMaterial3D.new()
		standard.vertex_color_use_as_albedo = true
		standard.roughness = 1.0
		mat = standard

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
	mat: Material
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
			if skip_cell.is_valid() and skip_cell.call(x, z):
				continue
			if _refined(x, z, width):
				_add_refined(heights, colors, width, spacing, half, x, z, verts, normals, cols, idx)
				continue
			var a := (z - z0) * (x1 - x0 + 1) + (x - x0)
			var b := a + 1
			var c := a + (x1 - x0 + 1)
			var d := c + 1
			# Godot front faces use clockwise winding, including trimesh collision.
			idx.append_array([a, b, c, b, d, c])

	if idx.is_empty():
		return
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
	if not surface_meta.is_empty():
		body.set_meta("footstep_surface", surface_meta)
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	mi.add_child(body)
	add_child(mi)


func _refined(x: int, z: int, width: int) -> bool:
	if not refine_cell.is_valid() or not shore_height.is_valid():
		return false
	if x < 0 or z < 0 or x >= width - 1 or z >= width - 1:
		return false
	return refine_cell.call(x, z)


## One cell as REFINE x REFINE quads; the coarse surface is its two triangles [a,b,c], [b,d,c].
func _add_refined(heights: PackedFloat32Array, colors: PackedColorArray, width: int, spacing: float, half: float,
		x: int, z: int, verts: PackedVector3Array, normals: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array) -> void:
	var ha := heights[z * width + x]
	var hb := heights[z * width + x + 1]
	var hc := heights[(z + 1) * width + x]
	var hd := heights[(z + 1) * width + x + 1]
	var ca := colors[z * width + x]
	var cb := colors[z * width + x + 1]
	var cc := colors[(z + 1) * width + x]
	var cd := colors[(z + 1) * width + x + 1]
	var open_w := not _refined(x - 1, z, width)
	var open_e := not _refined(x + 1, z, width)
	var open_n := not _refined(x, z - 1, width)
	var open_s := not _refined(x, z + 1, width)
	var n := REFINE + 1
	var grid := PackedFloat32Array()
	grid.resize(n * n)
	for j in n:
		for i in n:
			var u := float(i) / REFINE
			var v := float(j) / REFINE
			var base := ha + (hb - ha) * u + (hc - ha) * v if u + v <= 1.0 else hd + (hc - hd) * (1.0 - u) + (hb - hd) * (1.0 - v)
			var corner := (i == 0 or i == REFINE) and (j == 0 or j == REFINE)
			var border := (i == 0 and open_w) or (i == REFINE and open_e) or (j == 0 and open_n) or (j == REFINE and open_s)
			grid[j * n + i] = base if corner or border else float(shore_height.call((x + u) * spacing - half, (z + v) * spacing - half, base))
	var first := verts.size()
	var step := spacing / REFINE
	for j in n:
		for i in n:
			var u := float(i) / REFINE
			var v := float(j) / REFINE
			verts.append(Vector3((x + u) * spacing - half, grid[j * n + i], (z + v) * spacing - half))
			var il := maxi(i - 1, 0)
			var ir := mini(i + 1, REFINE)
			var jl := maxi(j - 1, 0)
			var jr := mini(j + 1, REFINE)
			var dhdx := (grid[j * n + ir] - grid[j * n + il]) / float((ir - il) * step)
			var dhdz := (grid[jr * n + i] - grid[jl * n + i]) / float((jr - jl) * step)
			normals.append(Vector3(-dhdx, 1.0, -dhdz).normalized())
			cols.append(ca.lerp(cb, u).lerp(cc.lerp(cd, u), v))
	for j in REFINE:
		for i in REFINE:
			var a := first + j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])


func _normal_at(heights: PackedFloat32Array, width: int, x: int, z: int, spacing: float) -> Vector3:
	var xm := maxi(x - 1, 0)
	var xp := mini(x + 1, width - 1)
	var zm := maxi(z - 1, 0)
	var zp := mini(z + 1, width - 1)
	var dhdx := (heights[z * width + xp] - heights[z * width + xm]) / float((xp - xm) * spacing)
	var dhdz := (heights[zp * width + x] - heights[zm * width + x]) / float((zp - zm) * spacing)
	return Vector3(-dhdx, 1.0, -dhdz).normalized()
