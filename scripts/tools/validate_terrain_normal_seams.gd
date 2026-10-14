extends SceneTree

const Geometry = preload("res://scripts/world/world_graybox_geometry.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var g := Geometry.new()
	root.add_child(g)
	var width := 43
	var heights := PackedFloat32Array()
	var colors := PackedColorArray()
	for z in width:
		for x in width:
			heights.append(0.1 * x + 0.2 * z)
			colors.append(Color(0.2, 0.4, 0.3, 0.0))
	g.refine_cell = func(x: int, z: int) -> bool: return x >= 37 and x <= 41 and z >= 17 and z <= 22
	g.shore_height = func(x: float, z: float, base: float) -> float: return base + sin(x * 0.29) * cos(z * 0.23) * 2.0
	g.build(heights, colors, width, 5.0)
	var signature := _inspect(g, "curved")
	# At x=37*5 the refined patch meets a coarse cell. Its intermediate boundary vertices must
	# shade like the coarse edge, rather than use the steep artificial interior displacement.
	var boundary_expected := Vector3(-0.02, 1.0, -0.04).normalized()
	for child in g.get_children():
		var edge_arrays: Array = child.mesh.surface_get_arrays(0)
		for index in edge_arrays[Mesh.ARRAY_INDEX]:
			var p: Vector3 = edge_arrays[Mesh.ARRAY_VERTEX][index]
			if is_equal_approx(p.x, 80.0) and p.z > -20.0 and p.z < 0.0:
				_check(edge_arrays[Mesh.ARRAY_NORMAL][index].distance_to(boundary_expected) < 0.0003, "coarse/fine edge lighting mismatch")
	g.build(heights, colors, width, 5.0)
	_check(signature == _inspect(g, "rebuild"), "rebuild changed geometry")
	g.shore_height = func(_x: float, _z: float, base: float) -> float: return base
	g.build(heights, colors, width, 5.0)
	_inspect(g, "plane")
	var expected := Vector3(-0.02, 1.0, -0.04).normalized()
	for child in g.get_children():
		var a: Array = child.mesh.surface_get_arrays(0)
		for index in a[Mesh.ARRAY_INDEX]:
			# ArrayMesh packs normals; allow its quantization, not visible angular discontinuities.
			_check(a[Mesh.ARRAY_NORMAL][index].distance_to(expected) < 0.0003, "plane normal differs")
	print(JSON.stringify({"failures": failures, "geometry_sha256": signature}))
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)

func _inspect(g: Node3D, label: String) -> String:
	var shared := {}
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var max_delta := 0.0
	var repeated := 0
	for child in g.get_children():
		var a: Array = child.mesh.surface_get_arrays(0)
		context.update(var_to_bytes([a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_INDEX], a[Mesh.ARRAY_COLOR]]))
		var used := {}
		for index in a[Mesh.ARRAY_INDEX]:
			used[index] = true
		for index in used:
			var p: Vector3 = a[Mesh.ARRAY_VERTEX][index]
			var n: Vector3 = a[Mesh.ARRAY_NORMAL][index]
			if shared.has(p):
				max_delta = maxf(max_delta, n.distance_to(shared[p]))
				repeated += 1
			else:
				shared[p] = n
	_check(repeated > 100, label + ": fixture lacks shared vertices")
	_check(max_delta < 0.00002, label + ": shared terrain vertices have different normals")
	print("NORMAL_SEAMS %s repeats=%d max_delta=%.8f" % [label, repeated, max_delta])
	return context.finish().hex_encode()
