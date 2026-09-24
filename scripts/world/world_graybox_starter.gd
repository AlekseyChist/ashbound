extends Node3D
## Passive coarse graybox for the AshBound starter region: untextured houses and conifers.
## Positions are supplied by the coordinator; this helper only builds geometry and collision.

const COLOR_CLAY := Color("#92938b")
const COLOR_ROOF := Color("#766a56")
const COLOR_ROCK := Color("#777970")
const COLOR_DARK := Color("#252a29")
const COLOR_TRUNK := Color("#6e5f4c")
const COLOR_CONIFER := Color("#405044")

const ROOF_SLOPE_DEG: float = 28.0
const EAVE_OVERHANG: float = 0.4


func add_house(origin: Vector3, yaw: float, size: Vector3, foundation: float) -> Node3D:
	var root := Node3D.new()
	root.name = "House"
	root.position = origin
	root.rotation.y = yaw
	add_child(root)

	var wall_height: float = maxf(size.y, 0.01)
	var roof_half_span: float = size.x * 0.5 + EAVE_OVERHANG
	var slope_rad: float = deg_to_rad(ROOF_SLOPE_DEG)
	var roof_rise: float = roof_half_span * tan(slope_rad)
	var roof_slope_len: float = roof_half_span / cos(slope_rad)
	var roof_thick: float = 0.12

	var wall_mat := _make_material(COLOR_CLAY)
	var roof_mat := _make_material(COLOR_ROOF)
	var rock_mat := _make_material(COLOR_ROCK)
	var dark_mat := _make_material(COLOR_DARK)

	# Stone foundation, full footprint.
	var foundation_mesh := BoxMesh.new()
	foundation_mesh.size = Vector3(size.x, foundation, size.z)
	foundation_mesh.material = rock_mat
	var foundation_node := MeshInstance3D.new()
	foundation_node.name = "Foundation"
	foundation_node.mesh = foundation_mesh
	foundation_node.position = Vector3(0.0, foundation * 0.5, 0.0)
	root.add_child(foundation_node)

	# Walls as a single box from foundation top to wall top.
	var walls_mesh := BoxMesh.new()
	walls_mesh.size = Vector3(size.x, wall_height, size.z)
	walls_mesh.material = wall_mat
	var walls_node := MeshInstance3D.new()
	walls_node.name = "Walls"
	walls_node.mesh = walls_mesh
	walls_node.position = Vector3(0.0, foundation + wall_height * 0.5, 0.0)
	root.add_child(walls_node)

	# Pitched roof: two slabs hinged at the ridge along local Z.
	var wall_top_y: float = foundation + wall_height
	var ridge_y: float = wall_top_y + roof_rise
	var slab_center_y: float = wall_top_y + roof_rise * 0.5
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(roof_slope_len, roof_thick, size.z + 0.8)
	slab_mesh.material = roof_mat
	var slab_a := MeshInstance3D.new()
	slab_a.name = "RoofA"
	slab_a.mesh = slab_mesh
	slab_a.transform = Transform3D(Basis(Vector3.BACK, slope_rad), Vector3(-roof_half_span * 0.5, slab_center_y, 0.0))
	root.add_child(slab_a)
	var slab_b := MeshInstance3D.new()
	slab_b.name = "RoofB"
	slab_b.mesh = slab_mesh
	slab_b.transform = Transform3D(Basis(Vector3.BACK, -slope_rad), Vector3(roof_half_span * 0.5, slab_center_y, 0.0))
	root.add_child(slab_b)

	# Closed dark door on the +Z face.
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(1.2, 2.2, 0.06)
	door_mesh.material = dark_mat
	var door_node := MeshInstance3D.new()
	door_node.name = "Door"
	door_node.mesh = door_mesh
	door_node.position = Vector3(-0.9, foundation + 1.1, size.z * 0.5 + 0.03)
	root.add_child(door_node)

	# One small window beside the door.
	var win_mesh := BoxMesh.new()
	win_mesh.size = Vector3(0.8, 0.8, 0.06)
	win_mesh.material = dark_mat
	var win_node := MeshInstance3D.new()
	win_node.name = "Window"
	win_node.mesh = win_mesh
	win_node.position = Vector3(0.9, foundation + 1.4, size.z * 0.5 + 0.03)
	root.add_child(win_node)

	# Single collider covering foundation + walls; roof is non-colliding.
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, foundation + wall_height, size.z)
	col.shape = shape
	col.position = Vector3(0.0, (foundation + wall_height) * 0.5, 0.0)
	body.add_child(col)
	root.add_child(body)

	return root


func add_forest(trees: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "Forest"
	add_child(root)

	var count: int = trees.size()
	if count == 0:
		return root

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.20
	trunk_mesh.bottom_radius = 0.28
	trunk_mesh.height = 4.0
	trunk_mesh.radial_segments = 8
	trunk_mesh.material = _make_material(COLOR_TRUNK)

	var lower_mesh := CylinderMesh.new()
	lower_mesh.top_radius = 0.0
	lower_mesh.bottom_radius = 2.6
	lower_mesh.height = 6.0
	lower_mesh.radial_segments = 8
	lower_mesh.material = _make_material(COLOR_CONIFER)

	var upper_mesh := CylinderMesh.new()
	upper_mesh.top_radius = 0.0
	upper_mesh.bottom_radius = 1.8
	upper_mesh.height = 4.2
	upper_mesh.radial_segments = 8
	upper_mesh.material = _make_material(COLOR_CONIFER)

	var trunk_mm := MultiMesh.new()
	trunk_mm.transform_format = MultiMesh.TRANSFORM_3D
	trunk_mm.instance_count = count
	trunk_mm.mesh = trunk_mesh
	var trunk_mi := MultiMeshInstance3D.new()
	trunk_mi.name = "Trunks"
	trunk_mi.multimesh = trunk_mm
	root.add_child(trunk_mi)

	var lower_mm := MultiMesh.new()
	lower_mm.transform_format = MultiMesh.TRANSFORM_3D
	lower_mm.instance_count = count
	lower_mm.mesh = lower_mesh
	var lower_mi := MultiMeshInstance3D.new()
	lower_mi.name = "LowerCrowns"
	lower_mi.multimesh = lower_mm
	root.add_child(lower_mi)

	var upper_mm := MultiMesh.new()
	upper_mm.transform_format = MultiMesh.TRANSFORM_3D
	upper_mm.instance_count = count
	upper_mm.mesh = upper_mesh
	var upper_mi := MultiMeshInstance3D.new()
	upper_mi.name = "UpperCrowns"
	upper_mi.multimesh = upper_mm
	root.add_child(upper_mi)

	var body := StaticBody3D.new()
	body.name = "TrunkColliders"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)

	for i in count:
		var record: Variant = trees[i]
		var x: float = float((record as Array)[0])
		var y: float = float((record as Array)[1])
		var z: float = float((record as Array)[2])
		var scale: float = maxf(float((record as Array)[3]), 0.01)
		var yaw: float = float((record as Array)[4])

		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
		var origin := Vector3(x, y, z)
		trunk_mm.set_instance_transform(i, Transform3D(basis, origin + Vector3(0.0, 2.0 * scale, 0.0)))
		lower_mm.set_instance_transform(i, Transform3D(basis, origin + Vector3(0.0, 5.0 * scale, 0.0)))
		upper_mm.set_instance_transform(i, Transform3D(basis, origin + Vector3(0.0, 8.0 * scale, 0.0)))

		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.28 * scale
		shape.height = 4.0 * scale
		col.shape = shape
		col.position = origin + Vector3(0.0, 2.0 * scale, 0.0)
		body.add_child(col)

	return root


func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.emission_enabled = false
	return mat
