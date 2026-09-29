extends SceneTree
## Check the visible shell itself: a collision ramp or plinth cannot prove that
## the 3–7.5 cm strip above the interior floor is closed to the outside.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("CIVIC_SEAM_FAIL ", label)

func triangles_for(hall: Node3D) -> Array:
	var result: Array = []
	for node in hall.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var extras: Dictionary = mesh.get_meta("extras", {})
		# Props can obscure a hole from one angle, but they must not be its seal.
		if str(extras.get("part_role", "")) not in ["shell", "gable", "frame", "floor", "foundation", "lining"]:
			continue
		var faces: PackedVector3Array = mesh.mesh.get_faces()
		for i in faces.size():
			faces[i] = mesh.global_transform * faces[i]
		result.append([mesh.global_transform * mesh.get_aabb(), faces])
	return result

func covered(parts: Array, from: Vector3, to: Vector3) -> bool:
	for part in parts:
		var box: AABB = part[0]
		if box.intersects_segment(from, to) == null:
			continue
		var faces: PackedVector3Array = part[1]
		for i in range(0, faces.size(), 3):
			if Geometry3D.segment_intersects_triangle(from, to, faces[i], faces[i + 1], faces[i + 2]) != null:
				return true
	return false

func run() -> void:
	for spec in [["r01", 12.0, 1.0, -5.2, 2.9], ["k01", 10.0, 0.8, -4.3, 4.3]]:
		var id: String = spec[0]
		var half_width: float = spec[1]
		var floor_y: float = spec[2]
		var hall: Node3D = load("res://assets/buildings/forest-city-v1/%s.glb" % id).instantiate()
		root.add_child(hall)
		var parts := triangles_for(hall)
		for side in [-1.0, 1.0]:
			var inner_x: float = side * (half_width - 0.5)
			var outer_x: float = side * (half_width + 0.5)
			check(covered(parts, Vector3(inner_x, floor_y + 0.3, 0), Vector3(outer_x, floor_y + 0.3, 0)), "%s side %s control intersects actual lower log" % [id, side])
			for sample in 8:
				var z := lerpf(float(spec[3]), float(spec[4]), float(sample) / 7.0)
				for height in [0.03, 0.075]:
					var from := Vector3(inner_x, floor_y + height, z)
					var to := Vector3(outer_x, floor_y + height, z)
					check(covered(parts, from, to), "%s side %s z %.3f height %.3f floor-to-wall seal" % [id, side, z, height])
		hall.free()
	print("CIVIC_FLOOR_SEAMS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
