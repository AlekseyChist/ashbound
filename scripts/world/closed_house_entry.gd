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
		# The slope faces up, the two sides outwards; drawn two-sided (no culling), lit by these normals.
		var up := (d - a).cross(b - a).normalized()
		if up.y < 0.0:
			up = -up
		# Godot faces front clockwise: seen from above the slope is a, c, d and a, b, c.
		for face in [[[a, c, d], up], [[a, b, c], up], [[a, d, e], Vector3.LEFT], [[b, f, c], Vector3.RIGHT]]:
			for v in face[0]:
				st.set_normal(face[1])
				st.set_uv(Vector2(v.x, v.z) * 0.5)
				st.add_vertex(v)
		var apron := MeshInstance3D.new()
		apron.name = "EntryApron"
		apron.set_meta("extras", {"part_role": "foundation"})
		apron.mesh = st.commit()
		var surface := _stone_for(_foundation_material(house, stone))
		if surface is BaseMaterial3D:
			surface = surface.duplicate()
			(surface as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		apron.material_override = surface
		house.add_child(apron)


## Compact stone supports down to the ground on a slope (Codex 061: no slab under the whole
## rectangle): a plinth under the body's foundation, one under the entry steps / ramp, a small pier
## under each canopy post. Each is solid, its top level with the wedge (0.02), 0.35 m below the lowest
## ground under it, in the house's own foundation stone. Returns the front edge (+z) of the steps'
## support for add(), or -INF when the steps need none.
static func skirt(house: Node3D, ground: Callable, stone: Material) -> float:
	var parts: Array = []           # [Rect2 in the house's x/z, is_steps]
	var material: Material = null
	var posts: Array[Rect2] = []
	for node in house.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or mesh.is_queued_for_deletion():
			continue
		var extras: Dictionary = mesh.get_meta("extras", {})
		var role := str(extras.get("part_role", ""))
		var steps := str(extras.get("item_id", "")) == "entry_steps"
		if not (steps or role == "foundation" or role == "canopy"):
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mesh
		while n != house and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var box: AABB = xf * mesh.get_aabb()
		if role == "foundation" and not steps:
			if material == null:
				material = mesh.material_override if mesh.material_override else mesh.get_active_material(0)
			parts.append([Rect2(box.position.x, box.position.z, box.size.x, box.size.z), false])
		elif steps:
			parts.append([Rect2(box.position.x, box.position.z, box.size.x, box.size.z), true])
		else:
			# The canopy's posts: its vertices near the ground, gathered post by post.
			for v in mesh.mesh.get_faces():
				var p: Vector3 = xf * v
				if p.y > 0.25:
					continue
				var q := Vector2(p.x, p.z)
				var found := false
				for i in posts.size():
					if posts[i].grow(0.4).has_point(q):
						posts[i] = posts[i].expand(q)
						found = true
						break
				if not found:
					posts.append(Rect2(q, Vector2.ZERO))
	for post in posts:
		parts.append([post.grow(0.12), false])
	var surface := _stone_for(material if material != null else stone)
	var front := -INF
	for part in parts:
		var rect: Rect2 = part[0]
		var low := 0.0
		for gx in 3:
			for gz in 3:
				var local := rect.position + rect.size * Vector2(gx / 2.0, gz / 2.0)
				low = minf(low, float(ground.call(house.transform * Vector3(local.x, 0, local.y))) - house.position.y)
		if low > -0.05:
			continue
		_support(house, rect, low, surface)
		if part[1]:
			front = maxf(front, rect.end.y)
	return front


static func _support(house: Node3D, rect: Rect2, low: float, surface: Material) -> void:
	var size := Vector3(rect.size.x, -low + 0.37, rect.size.y)
	var at := Vector3(rect.get_center().x, 0.02 - size.y * 0.5, rect.get_center().y)
	var mesh := MeshInstance3D.new()
	mesh.name = "Support"
	mesh.set_meta("extras", {"part_role": "foundation"})
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = surface
	mesh.position = at
	house.add_child(mesh)
	var body := StaticBody3D.new()
	body.name = "SupportCollision"
	body.set_meta("footstep_surface", "stone")
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = size
	shape.shape = hull
	shape.position = at
	body.add_child(shape)
	house.add_child(body)


## The material of the house's own foundation (the kit's stone plinth), else `fallback`.
static func _foundation_material(house: Node3D, fallback: Material) -> Material:
	for node in house.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var extras: Dictionary = mesh.get_meta("extras", {})
		if str(extras.get("part_role", "")) == "foundation" and str(extras.get("item_id", "")) != "entry_steps" and mesh.mesh != null and mesh.name != "Support":
			return mesh.material_override if mesh.material_override else mesh.get_active_material(0)
	return fallback


## The house's own foundation stone, laid in world space so a tall support is not one stretched tile.
static func _stone_for(source: Material) -> Material:
	if source is StandardMaterial3D:
		var m := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * 0.5
		return m
	return source


## Everything of the house that stands on the ground (walls, porch, steps, ramp), in its x/z.
static func ground_rect(house: Node3D) -> Rect2:
	var base := Rect2()
	var first := true
	for node in house.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var role := str(mesh.get_meta("extras", {}).get("part_role", ""))
		if role == "furniture" or role == "ceiling" or role == "interior" or mesh.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mesh
		while n != house and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var box: AABB = xf * mesh.get_aabb()
		if box.position.y > 0.6:
			continue
		var r := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
		base = r if first else base.merge(r)
		first = false
	return base
