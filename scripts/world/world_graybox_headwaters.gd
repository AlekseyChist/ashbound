extends Node3D
# Passive untextured graybox helper for headwaters landmarks. No input, physics or process loops.

const _WATER_COLOR := Color("537d91")
const _ROCK_COLOR := Color("777970")
const _DARK_COLOR := Color("252a29")


func add_lake(center: Vector3, radii: Vector2) -> MeshInstance3D:
	if not (is_finite(radii.x) and is_finite(radii.y)) or radii.x <= 0.0 or radii.y <= 0.0:
		push_warning("world_graybox_headwaters: invalid lake radii %s" % radii)
		return null
	var segments := 96
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.append(Vector3(center.x, center.y, center.z))
	normals.append(Vector3.UP)
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		vertices.append(Vector3(
			center.x + radii.x * cos(angle),
			center.y,
			center.z + radii.y * sin(angle)
		))
		normals.append(Vector3.UP)
	for i in range(segments):
		var current := 1 + i
		var next := 1 + (i + 1) % segments
		indices.append_array(PackedInt32Array([0, current, next]))
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = _WATER_COLOR
	material.roughness = 1.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	add_child(instance)
	return instance


func add_spring_cave(origin: Vector3, facing: Vector3) -> Node3D:
	var horizontal := Vector2(facing.x, facing.z)
	if not (is_finite(horizontal.x) and is_finite(horizontal.y)) or horizontal.length_squared() <= 0.0:
		push_warning("world_graybox_headwaters: invalid spring cave facing %s" % facing)
		return null
	var root := Node3D.new()
	root.position = origin
	root.rotation.y = atan2(facing.x, facing.z)
	add_child(root)
	_add_box(root, _ROCK_COLOR, Vector3(-10.0, 7.0, -8.0), Vector3(12.0, 14.0, 22.0))
	_add_box(root, _ROCK_COLOR, Vector3(10.0, 7.0, -8.0), Vector3(12.0, 14.0, 22.0))
	_add_box(root, _ROCK_COLOR, Vector3(0.0, 11.0, -8.0), Vector3(32.0, 6.0, 22.0))
	_add_box(root, _DARK_COLOR, Vector3(0.0, 4.0, -17.0), Vector3(8.0, 8.0, 1.0))
	return root


func _add_box(parent: Node3D, color: Color, position: Vector3, size: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)
