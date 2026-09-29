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
	# [model, gable axis, half size to the gable, floor, along from, along to, door span to skip,
	# centre across the gables (default 0), sides to test (default both)].
	# The halls' gables face +-x; the water mill's (owner 29 Sep: a slit at its back wall and by the
	# door) face +-z, the doorway itself is open by design.
	for spec in [["r01", "x", 12.0, 1.0, -5.2, 2.9, []], ["k01", "x", 10.0, 0.8, -4.3, 4.3, []],
			["m01", "z", 5.5, 1.05, -4.0, 3.2, [-1.05, 1.05]],
			# Terem T1: gables at x +-6.5, the body z -5.4 .. 2.4 (Godot), floor 1.0.
			["t1", "x", 6.5, 1.0, -5.0, 2.0, []],
			# Terem T2: the tall block's gables at z -5.5 / +2.5 (x -7..0), the wing's at x 7 (z -5.5..1).
			["t2", "z", 4.0, 1.0, -6.6, -0.4, [], -1.5], ["t2", "x", 7.0, 1.0, -5.0, 0.6, [], 0.0, [1.0]],
			# Terem T3: the body's gable at x -6.5 (z -5.5..1.5), the wing's gables at z 3.5 / -5.5 (x 1.5..6.5).
			["t3", "x", 6.5, 1.0, -5.0, 1.0, [], 0.0, [-1.0]], ["t3", "z", 4.5, 1.0, 1.9, 6.1, [], -1.0]]:
		var id: String = spec[0]
		var on_z: bool = spec[1] == "z"
		var half_width: float = spec[2]
		var floor_y: float = spec[3]
		var door: Array = spec[6]
		var centre: float = spec[7] if spec.size() > 7 else 0.0
		var sides: Array = spec[8] if spec.size() > 8 else [-1.0, 1.0]
		var hall: Node3D = load("res://assets/buildings/forest-city-v1/%s.glb" % id).instantiate()
		root.add_child(hall)
		var parts := triangles_for(hall)
		var at := func(across: float, along: float, y: float) -> Vector3:
			return Vector3(along, y, across) if on_z else Vector3(across, y, along)
		for side in sides:
			var inner: float = centre + side * (half_width - 0.5)
			var outer: float = centre + side * (half_width + 0.5)
			check(covered(parts, at.call(inner, float(spec[4]), floor_y + 0.3), at.call(outer, float(spec[4]), floor_y + 0.3)), "%s side %s control intersects actual lower log" % [id, side])
			for sample in 8:
				var along := lerpf(float(spec[4]), float(spec[5]), float(sample) / 7.0)
				if not door.is_empty() and along > float(door[0]) and along < float(door[1]):
					continue
				for height in [0.03, 0.075]:
					var from: Vector3 = at.call(inner, along, floor_y + height)
					var to: Vector3 = at.call(outer, along, floor_y + height)
					check(covered(parts, from, to), "%s side %s along %.3f height %.3f floor-to-wall seal" % [id, side, along, height])
		hall.free()
	print("CIVIC_FLOOR_SEAMS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
