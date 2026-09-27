class_name VillageGridMesh
extends RefCounted

const EPSILON: float = 0.1

static func build(x_min: float, z_min: float, x_max: float, z_max: float, spacing: float, height_at: Callable, color_at: Callable) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if x_max <= x_min or z_max <= z_min or spacing <= 0.0:
		push_error("VillageGridMesh.build: invalid bounds or spacing")
		return mesh
	var cols := int(ceil((x_max - x_min) / spacing)) + 1
	var rows := int(ceil((z_max - z_min) / spacing)) + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	for r in rows:
		for c in cols:
			var x: float = minf(x_min + c * spacing, x_max)
			var z: float = minf(z_min + r * spacing, z_max)
			var h: float = height_at.call(x, z)
			vertices.append(Vector3(x, h, z))
			normals.append(_normal(x, z, height_at))
			colors.append(color_at.call(x, z))
			uvs.append(Vector2(x * 0.2, z * 0.2))
	var indices := PackedInt32Array()
	for r in rows - 1:
		for c in cols - 1:
			var a: int = r * cols + c
			var b: int = a + 1
			var d: int = a + cols
			var e: int = d + 1
			indices.append_array([a, b, d, b, e, d])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _normal(x: float, z: float, height_at: Callable) -> Vector3:
	var e: float = EPSILON
	var hx0: float = height_at.call(x - e, z)
	var hx1: float = height_at.call(x + e, z)
	var hz0: float = height_at.call(x, z - e)
	var hz1: float = height_at.call(x, z + e)
	return Vector3(hx0 - hx1, 2.0 * e, hz0 - hz1).normalized()
