extends SceneTree
## The actual placed civic meshes must fit inside the actual log perimeter.
## A road-clear footprint alone cannot establish this. Check geometry, not
## _intrusion(), so omitting the perimeter in the solver cannot green this test.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)
	await create_timer(.5).timeout
	var city: Node3D = world.forest_city
	var plan: Dictionary = city.plan.palisade
	var centre := Vector2(float(plan.center[0]) - float(world.HALF), float(plan.center[1]) - float(world.HALF))
	var inner: float = float(plan.radius) - float(city.STAKE_RADIUS)
	for id in ["R01", "K01"]:
		var hall: Node3D = city.get_node(id)
		var max_radius := 0.0
		var mesh_count := 0
		var offender := ""
		var vertex := Vector3.ZERO
		for mesh in hall.model.find_children("*", "MeshInstance3D", true, false):
			var role: String = str(mesh.get_meta("extras", {}).get("part_role", ""))
			if role not in ["roof", "shell", "gable", "frame", "foundation"]:
				continue
			mesh_count += 1
			for p in mesh.mesh.get_faces():
				var at: Vector3 = city.to_local(mesh.to_global(p))
				var radius := Vector2(at.x, at.z).distance_to(centre)
				if radius > max_radius:
					max_radius = radius
					offender = str(mesh.name)
					vertex = at
		var gap := inner - max_radius
		checks += 1
		var ok := mesh_count > 0 and gap >= 0.0
		print("CIVIC_PALISADE_", "PASS " if ok else "FAIL ", id, " gap=", gap, " mesh=", offender, " vertex=", vertex)
		if not ok: failures.append(id)
	world.queue_free()
	await process_frame
	await create_timer(.2).timeout
	print("CIVIC_PALISADE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
