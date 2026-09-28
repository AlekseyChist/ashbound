extends RefCounted
## Closed houses (forest city suburbs, village neighbours): the entry steps or the barn ramp - the
## kit's "entry_steps" meshes, which get no trimesh of their own - are walked on one even slope.
## `ground` gives the terrain height at a point of the house's parent frame.

## The closed house's steps or ramp as one even slope (Codex 046: a hero does not climb 25 cm stone
## risers), carried on down to the real ground in front when the house stands higher than it - that
## part is a visible stone apron as well.
static func add(house: Node3D, ground: Callable, stone: Material, skirt_front: float) -> void:
	var box := AABB()
	var first := true
	for node in house.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if str(mesh.get_meta("extras", {}).get("item_id", "")) != "entry_steps" or mesh.is_queued_for_deletion():
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mesh
		while n != house and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var part: AABB = xf * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	if first:
		return
	# The flight rises towards the wall (-z); its low end is box.end.z.
	var top := box.end.y
	var near := box.position.z
	var far := box.end.z
	# Past the steps' foot the skirt's flat top (at 0.02) may carry on to its front edge; the apron runs
	# 1.5 m out from there and lands on the ground where it ends (the lowest of the two probes).
	var flat := maxf(far, skirt_front)
	var drop := 0.0
	for z in [flat + 0.3, flat + 1.5]:
		var probe: Vector3 = house.transform * Vector3(box.get_center().x, 0, z)
		drop = maxf(drop, house.position.y - float(ground.call(probe)))
	var run_out := flat + clampf(drop * 2.5, 0.5, 1.5)
	if drop < 0.05 and skirt_front == -INF:
		flat = far
		run_out = far
		drop = 0.0
	var low := -drop
	# Two convex pieces: the flight (top of the steps to their foot, carried over the skirt's flat top)
	# and the apron (the skirt's edge down to the ground).
	var profiles := [[Vector2(top, near), Vector2(top, near + 0.35), Vector2(0.02, far), Vector2(0.02, flat), Vector2(-0.4, flat), Vector2(-0.4, near)]]
	if run_out > flat:
		profiles.append([Vector2(0.02, flat), Vector2(low, run_out), Vector2(low - 0.3, run_out), Vector2(-0.4, flat)])
	var body := StaticBody3D.new()
	body.name = "EntryWedge"
	body.set_meta("footstep_surface", "stone")
	body.collision_layer = 1
	body.collision_mask = 0
	for profile in profiles:
		var points := PackedVector3Array()
		for x in [box.position.x, box.end.x]:
			for yz in profile:
				points.append(Vector3(x, yz.x, yz.y))
		var shape := CollisionShape3D.new()
		var hull := ConvexPolygonShape3D.new()
		hull.points = points
		shape.shape = hull
		body.add_child(shape)
	house.add_child(body)
	if drop > 0.05:
		# The stone apron from the foot of the steps down to the ground.
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var a := Vector3(box.position.x, 0.02, flat)
		var b := Vector3(box.end.x, 0.02, flat)
		var c := Vector3(box.end.x, low, run_out)
		var d := Vector3(box.position.x, low, run_out)
		var e := Vector3(box.position.x, low, flat)
		var f := Vector3(box.end.x, low, flat)
		for tri in [[a, d, c], [a, c, b], [a, e, d], [b, c, f]]:
			for v in tri:
				st.set_uv(Vector2(v.x, v.z) * 0.5)
				st.add_vertex(v)
		st.generate_normals()
		var apron := MeshInstance3D.new()
		apron.name = "EntryApron"
		apron.mesh = st.commit()
		apron.material_override = stone
		house.add_child(apron)
