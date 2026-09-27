extends Node3D
## Static blockout geometry for the 633 m forest route prototype.
## Called once after add_child: build(main_path, loop_path).

const GRID := 4.0
const X_MIN := -190.0
const X_MAX := 200.0
const Z_MIN := -740.0
const Z_MAX := 55.0
const RIVER_Z0 := -315.0
const RIVER_Z1 := -333.0
const WATER_Y := -1.0
const LOOKOUT_R := 12.0

var _main: PackedVector3Array = []
var _loop: PackedVector3Array = []
var _segs: Array = []   # {a: Vector2, b: Vector2, y0: float, y1: float}
var _rng := RandomNumberGenerator.new()

func build(main_path: PackedVector3Array, loop_path: PackedVector3Array) -> void:
	_main = main_path
	_loop = loop_path
	_rng.seed = 20240607
	_build_segments()
	var ground := Node3D.new(); ground.name = "Ground"; add_child(ground)
	ground.add_child(_build_terrain())
	var forest := Node3D.new(); forest.name = "Forest"; add_child(forest)
	forest.add_child(_build_forest())
	var rocks := Node3D.new(); rocks.name = "Rocks"; add_child(rocks)
	rocks.add_child(_build_rocks())
	add_child(_build_bridge())
	add_child(_build_river())
	var outsk := Node3D.new(); outsk.name = "Outskirts"; add_child(outsk)
	outsk.add_child(_build_outskirts())
	var city := Node3D.new(); city.name = "CityVista"; add_child(city)
	city.add_child(_build_city())

func _build_segments() -> void:
	_segs.clear()
	for path in [_main, _loop]:
		for i in range(path.size() - 1):
			var a: Vector3 = path[i]
			var b: Vector3 = path[i + 1]
			_segs.append({"a": Vector2(a.x, a.z), "b": Vector2(b.x, b.z), "y0": a.y, "y1": b.y})

func _nearest_path(x: float, z: float) -> Vector3:
	# returns (dist_xz, interpolated_y, 0.0)
	var best_d := INF
	var best_y := 0.0
	for s in _segs:
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var ab := b - a
		var t: float = (Vector2(x, z) - a).dot(ab) / maxf(ab.length_squared(), 0.001)
		t = clampf(t, 0.0, 1.0)
		var p := a + ab * t
		var d := Vector2(x, z).distance_to(p)
		if d < best_d:
			best_d = d
			best_y = lerpf(s["y0"], s["y1"], t)
	return Vector3(best_d, best_y, 0.0)

func terrain_height(x: float, z: float) -> float:
	var np := _nearest_path(x, z)
	var d: float = np.x
	var py: float = np.y
	var h := py + 0.4 * sin(x * 0.05) * cos(z * 0.043) + 0.25 * sin((x + z) * 0.11)
	# suppress unevenness near road
	var shoulder := clampf((d - 8.0) / 14.0, 0.0, 1.0)
	h = lerpf(py, h, shoulder)
	# river channel: banks at y=3, bottom reaches ~-3.5 (water at -1 stays visible)
	if z > RIVER_Z1 and z < RIVER_Z0:
		var t := (z - RIVER_Z1) / (RIVER_Z0 - RIVER_Z1)
		var depth := 6.5 * sin(PI * t)
		h = minf(h, py - depth)
	# flat lookout at last main point
	var end := _main[_main.size() - 1]
	var lookout_distance := Vector2(x, z).distance_to(Vector2(end.x, end.z))
	h = lerpf(h, end.y, smoothstep(LOOKOUT_R * 2.0, LOOKOUT_R, lookout_distance))
	# flat start clearing
	if Vector2(x, z).distance_to(Vector2(_main[0].x, _main[0].z)) < 16.0:
		h = _main[0].y
	# Visible steep rim contains this finite prototype without invisible walls.
	var edge := minf(minf(x - X_MIN, X_MAX - x), minf(z - Z_MIN, Z_MAX - z))
	h += 32.0 * pow(clampf((20.0 - edge) / 20.0, 0.0, 1.0), 2.0)
	return h

func _build_terrain() -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	var mesh := ArrayMesh.new()
	var verts: PackedVector3Array = []
	var cols: PackedColorArray = []
	var idx: PackedInt32Array = []
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	for i in range(ceili((X_MAX - X_MIN) / GRID) + 1):
		xs.append(minf(X_MIN + i * GRID, X_MAX))
	for i in range(ceili((Z_MAX - Z_MIN) / GRID) + 1):
		zs.append(maxf(Z_MAX - i * GRID, Z_MIN))
	# Exact bank rows prevent interpolation from lowering the approach to the deck.
	for bank in [RIVER_Z0, RIVER_Z1]:
		if not zs.has(bank):
			zs.append(bank)
	zs.sort()
	zs.reverse()
	var nx := xs.size() - 1
	var nz := zs.size() - 1
	var road_c := Color(0.24, 0.21, 0.17)
	var ground_c := Color(0.22, 0.30, 0.16)
	for iz in range(nz + 1):
		for ix in range(nx + 1):
			var x := xs[ix]
			var z := zs[iz]
			var h := terrain_height(x, z)
			verts.append(Vector3(x, h, z))
			var np := _nearest_path(x, z)
			var d: float = np.x
			var c: Color
			if d < 4.0:
				c = road_c
			elif d < 8.0:
				c = road_c.lerp(ground_c, (d - 4.0) / 4.0)
			else:
				c = ground_c
			var edge := minf(minf(x - X_MIN, X_MAX - x), minf(z - Z_MIN, Z_MAX - z))
			c = c.lerp(Color(0.29, 0.30, 0.28), clampf((20.0 - edge) / 16.0, 0.0, 1.0))
			# slight variation
			var v := 0.9 + 0.2 * fposmod(sin(ix * 12.9898 + iz * 78.233) * 43758.5453, 1.0)
			c = c * v
			cols.append(c.srgb_to_linear())
	for iz in range(nz):
		for ix in range(nx):
			var a := iz * (nx + 1) + ix
			var b := a + 1
			var c := a + (nx + 1)
			var d2 := c + 1
			idx.append_array([a, c, b, b, c, d2])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_NORMAL] = _normals(verts)
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	mi.add_child(body)
	return mi

func _normals(verts: PackedVector3Array) -> PackedVector3Array:
	var n := verts.size()
	var out := PackedVector3Array()
	out.resize(n)
	for i in range(n):
		out[i] = Vector3.UP
	return out

func _build_forest() -> Node3D:
	var root := Node3D.new()
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.35, 0.24, 0.15)
	trunk_mat.roughness = 1.0
	var can_mat := StandardMaterial3D.new()
	can_mat.albedo_color = Color(0.13, 0.22, 0.12)
	can_mat.roughness = 1.0
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.28
	trunk_mesh.height = 3.0
	trunk_mesh.radial_segments = 8
	trunk_mesh.material = trunk_mat
	var can_mesh := CylinderMesh.new()
	can_mesh.top_radius = 0.0
	can_mesh.bottom_radius = 1.6
	can_mesh.height = 4.0
	can_mesh.radial_segments = 8
	can_mesh.material = can_mat
	var COUNT := 650
	var trunk_mm := MultiMesh.new()
	trunk_mm.transform_format = MultiMesh.TRANSFORM_3D
	trunk_mm.instance_count = COUNT
	trunk_mm.mesh = trunk_mesh
	var can1_mm := MultiMesh.new()
	can1_mm.transform_format = MultiMesh.TRANSFORM_3D
	can1_mm.instance_count = COUNT
	can1_mm.mesh = can_mesh
	var can2_mm := MultiMesh.new()
	can2_mm.transform_format = MultiMesh.TRANSFORM_3D
	can2_mm.instance_count = COUNT
	can2_mm.mesh = can_mesh
	var trunk_mi := MultiMeshInstance3D.new(); trunk_mi.multimesh = trunk_mm
	var can1_mi := MultiMeshInstance3D.new(); can1_mi.multimesh = can1_mm
	var can2_mi := MultiMeshInstance3D.new(); can2_mi.multimesh = can2_mm
	root.add_child(trunk_mi); root.add_child(can1_mi); root.add_child(can2_mi)
	var placed := 0
	var attempts := 0
	while placed < COUNT and attempts < COUNT * 40:
		attempts += 1
		var x := _rng.randf_range(X_MIN + 6.0, X_MAX - 6.0)
		var z := _rng.randf_range(Z_MIN + 6.0, Z_MAX - 6.0)
		if not _tree_ok(x, z):
			continue
		var h := terrain_height(x, z)
		var scale := _rng.randf_range(7.0, 13.0) / 10.0
		var trunk_h := 3.0 * scale
		var t := Transform3D(Basis.IDENTITY.scaled(Vector3(scale, scale, scale)), Vector3(x, h + trunk_h * 0.5, z))
		trunk_mm.set_instance_transform(placed, t)
		var c1 := Transform3D(Basis.IDENTITY.scaled(Vector3(scale, scale, scale)), Vector3(x, h + trunk_h + 2.0 * scale, z))
		can1_mm.set_instance_transform(placed, c1)
		var c2 := Transform3D(Basis.IDENTITY.scaled(Vector3(0.7 * scale, 0.8 * scale, 0.7 * scale)), Vector3(x, h + trunk_h + 4.5 * scale, z))
		can2_mm.set_instance_transform(placed, c2)
		# modest trunk collider for accessible ground
		if h < 14.0:
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.5, trunk_h, 0.5)
			shape.shape = box
			shape.position = Vector3(x, h + trunk_h * 0.5, z)
			body.add_child(shape)
			root.add_child(body)
		placed += 1
	trunk_mm.visible_instance_count = placed
	can1_mm.visible_instance_count = placed
	can2_mm.visible_instance_count = placed
	return root

func _tree_ok(x: float, z: float) -> bool:
	var np := _nearest_path(x, z)
	if np.x < 8.0:
		return false
	# Concentrate this finite tree budget around the route, not distant empty land.
	if np.x > 50.0:
		return false
	if z > RIVER_Z1 - 4.0 and z < RIVER_Z0 + 4.0:
		return false
	var end := _main[_main.size() - 1]
	if Vector2(x, z).distance_to(Vector2(end.x, end.z)) < LOOKOUT_R + 6.0:
		return false
	if Vector2(x, z).distance_to(Vector2(_main[0].x, _main[0].z)) < 18.0:
		return false
	# north-facing sightline from lookout toward city (x~20, z~-670)
	var lo := end
	var city := Vector2(20.0, -670.0)
	var dir := (city - Vector2(lo.x, lo.z)).normalized()
	var rel := Vector2(x, z) - Vector2(lo.x, lo.z)
	if rel.length() > 10.0 and rel.length() < 380.0:
		var proj := rel.dot(dir)
		if proj > 0.0:
			var perp := (rel - dir * proj).length()
			if perp < 14.0:
				return false
	return true

func _build_rocks() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.43, 0.40)
	mat.roughness = 1.0
	var rock_mesh := SphereMesh.new()
	rock_mesh.radial_segments = 8
	rock_mesh.rings = 6
	rock_mesh.material = mat
	var spots: Array = [
		Vector3(-52.0, 0.0, -170.0), Vector3(-58.0, 0.0, -182.0),
		Vector3(-40.0, 0.0, -196.0), Vector3(-66.0, 0.0, -205.0),
		Vector3(-30.0, 0.0, -215.0), Vector3(-75.0, 0.0, -160.0),
	]
	for i in range(spots.size()):
		var p: Vector3 = spots[i]
		p.y = terrain_height(p.x, p.z)
		var s := _rng.randf_range(1.2, 3.4)
		var mi := MeshInstance3D.new()
		mi.mesh = rock_mesh
		mi.position = p + Vector3(0, s * 0.3, 0)
		mi.scale = Vector3(s, s * 0.6, s)
		root.add_child(mi)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(s * 1.6, s, s * 1.6)
		shape.shape = box
		shape.position = p + Vector3(0, s * 0.4, 0)
		body.add_child(shape)
		root.add_child(body)
	return root

func _build_bridge() -> Node3D:
	var root := Node3D.new()
	root.name = "Bridge"
	var a: Vector3 = _main[5]
	var b: Vector3 = _main[6]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.30, 0.18)
	mat.roughness = 1.0
	var len := Vector2(b.x - a.x, b.z - a.z).length()
	var mid: Vector3 = (a + b) * 0.5
	# deck: top at y=3.0, mesh centre at y=2.85, height 0.3; length along Z
	var deck := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(6.0, 0.3, len + 2.0)
	box.material = mat
	deck.mesh = box
	deck.position = Vector3(mid.x, 2.87, mid.z)
	root.add_child(deck)
	# rails along Z on both X sides, height 1, centre y=3.5
	for side in [-3.0, 3.0]:
		var rail := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(0.2, 1.0, len + 2.0)
		rb.material = mat
		rail.mesh = rb
		rail.position = Vector3(mid.x + side, 3.5, mid.z)
		root.add_child(rail)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	# deck collider matches mesh exactly
	var shape := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(6.0, 0.3, len + 2.0)
	shape.shape = bshape
	shape.position = Vector3(mid.x, 2.87, mid.z)
	body.add_child(shape)
	# rail colliders only (no end caps)
	for side in [-3.0, 3.0]:
		var rshape := CollisionShape3D.new()
		var rbshape := BoxShape3D.new()
		rbshape.size = Vector3(0.2, 1.0, len + 2.0)
		rshape.shape = rbshape
		rshape.position = Vector3(mid.x + side, 3.5, mid.z)
		body.add_child(rshape)
	root.add_child(body)
	return root

func _build_river() -> Node3D:
	var root := Node3D.new()
	root.name = "River"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.45, 0.45)
	mat.roughness = 1.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(390.0, RIVER_Z0 - RIVER_Z1 + 8.0)
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = Vector3((X_MIN + X_MAX) * 0.5, WATER_Y, (RIVER_Z0 + RIVER_Z1) * 0.5)
	root.add_child(mi)
	return root

func _build_outskirts() -> Node3D:
	var root := Node3D.new()
	var house := preload("res://scenes/buildings/house.tscn")
	var tower := preload("res://scenes/buildings/watchtower.tscn")
	var spots: Array = [
		["h", Vector3(-15.0, 0.0, -10.0)], ["t", Vector3(16.0, 0.0, -28.0)],
	]
	for s in spots:
		var kind: String = s[0]
		var pos: Vector3 = s[1]
		var inst: Node3D = (house if kind == "h" else tower).instantiate()
		inst.position = pos + Vector3(0, terrain_height(pos.x, pos.z), 0)
		root.add_child(inst)
	return root

func _build_city() -> Node3D:
	var root := Node3D.new()
	var house := preload("res://scenes/buildings/house.tscn")
	var tower := preload("res://scenes/buildings/watchtower.tscn")
	var base := Vector2(20.0, -670.0)
	var offs: Array = [
		["h", Vector2(-18, 4)], ["h", Vector2(0, 8)], ["h", Vector2(18, 3)],
		["h", Vector2(-9, -6)], ["h", Vector2(9, -8)], ["h", Vector2(24, 12)],
		["t", Vector2(-26, 10)], ["t", Vector2(28, -4)],
	]
	for o in offs:
		var kind: String = o[0]
		var off: Vector2 = o[1]
		var p := base + off
		var inst: Node3D = (house if kind == "h" else tower).instantiate()
		inst.position = Vector3(p.x, terrain_height(p.x, p.y), p.y)
		root.add_child(inst)
	return root
