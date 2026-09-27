extends Node3D
## Small geometry helper for graybox paths and markers.
## Strips are continuous ribbons built from pre-sampled world-space points.


func add_strip(points: PackedVector3Array, width: float, color: Color, collidable: bool) -> MeshInstance3D:
	if points.size() < 2:
		push_error("world_graybox_shapes.add_strip: need at least 2 points")
		return null
	if not is_finite(width) or width <= 0.0:
		push_error("world_graybox_shapes.add_strip: width must be > 0")
		return null

	var half_width: float = width * 0.5
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for i in range(points.size()):
		var tangent: Vector3 = _horizontal_tangent(points, i)
		if tangent.length_squared() < 1.0e-8:
			push_error("world_graybox_shapes.add_strip: degenerate horizontal tangent at point %d" % i)
			return null
		tangent = tangent.normalized()
		var perp: Vector3 = Vector3(-tangent.z, 0.0, tangent.x)
		var left: Vector3 = points[i] + perp * half_width
		var right: Vector3 = points[i] - perp * half_width
		var normal: Vector3 = _strip_normal(points, i)
		vertices.append(left)
		vertices.append(right)
		normals.append(normal)
		normals.append(normal)
		if i < points.size() - 1:
			var a: int = i * 2
			var b: int = a + 1
			var c: int = (i + 1) * 2
			var d: int = c + 1
			indices.append(a)
			indices.append(b)
			indices.append(c)
			indices.append(b)
			indices.append(d)
			indices.append(c)

	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.surface_set_material(0, material)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

	if collidable:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body)
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)

	return mi


func add_band(left: PackedVector3Array, right: PackedVector3Array, color: Color, collidable: bool) -> MeshInstance3D:
	if left.size() < 2 or right.size() < 2:
		push_error("world_graybox_shapes.add_band: need at least 2 points per side")
		return null
	if left.size() != right.size():
		push_error("world_graybox_shapes.add_band: left and right must have the same point count")
		return null

	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for i in range(left.size()):
		vertices.append(left[i])
		vertices.append(right[i])
		var before := maxi(0, i - 1)
		var after := mini(left.size() - 1, i + 1)
		var tangent := (left[after] + right[after] - left[before] - right[before]) * 0.5
		var normal := tangent.cross(right[i] - left[i]).normalized()
		if normal.length_squared() < 0.01: normal = Vector3.UP
		if normal.y < 0: normal = -normal
		normals.append(normal)
		normals.append(normal)
		if i < left.size() - 1:
			var a: int = i * 2
			var b: int = a + 1
			var c: int = (i + 1) * 2
			var d: int = c + 1
			indices.append(a)
			indices.append(b)
			indices.append(c)
			indices.append(b)
			indices.append(d)
			indices.append(c)

	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.surface_set_material(0, material)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

	if collidable:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body)
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)

	return mi


func add_marker(center: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = center
	add_child(mi)
	return mi


func _horizontal_tangent(points: PackedVector3Array, i: int) -> Vector3:
	var n: int = points.size()
	var t: Vector3
	if i == 0:
		t = points[1] - points[0]
	elif i == n - 1:
		t = points[n - 1] - points[n - 2]
	else:
		t = points[i + 1] - points[i - 1]
	return Vector3(t.x, 0.0, t.z)


func _strip_normal(points: PackedVector3Array, i: int) -> Vector3:
	var n: int = points.size()
	var prev: Vector3 = points[maxi(i - 1, 0)]
	var next: Vector3 = points[mini(i + 1, n - 1)]
	var tangent: Vector3 = (next - prev)
	tangent.y = 0.0
	if tangent.length_squared() < 1.0e-8:
		return Vector3.UP
	tangent = tangent.normalized()
	var perp: Vector3 = Vector3(-tangent.z, 0.0, tangent.x)
	var slope: Vector3 = (next - prev).normalized()
	var normal: Vector3 = (perp.cross(slope)).normalized()
	if normal.y < 0.0:
		normal = -normal
	return normal
