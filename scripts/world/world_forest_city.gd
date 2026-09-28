extends Node3D
## FOREST-CITY-01 (D-111): the forest city of the Exiles by the agreed plan (schema v5, Middlehill -
## Watabou MFCG seed 7736 - on the game's terrain), assets/world/forest-city-v1/plan.json.
## Step 1: the palisade of sharpened logs (one MultiMesh), its log towers and the three gates.
## Map metres (x east, z south) become the world frame as map - HALF.
const PLAN := "res://assets/world/forest-city-v1/plan.json"
const OAK := "res://assets/buildings/forest-inn-v1/t03a_Forest_oak.png"
const BOARDS := "res://assets/props/tavern-v1/roof/brown_planks_04_%s_1k.jpg"
const STAKE_RADIUS := 0.17
const STAKE_SPACING := 0.33
## Height over the ground; each stake is sunk SINK into it so it never stands on air on a slope.
const STAKE_HEIGHT := 5.0
const SINK := 0.8
const GATE_WIDTH := 6.0
const TOWER := 4.2
const TOWER_HEIGHT := 6.4
const LOG := 0.3
const VISIBLE := 400.0

var world: Node3D
var plan: Dictionary
var timber: StandardMaterial3D
var roof: StandardMaterial3D
var stake_count := 0
var tower_count := 0


func build(scene: Node3D) -> void:
	world = scene
	plan = JSON.parse_string(FileAccess.get_file_as_string(PLAN))
	timber = StandardMaterial3D.new()
	timber.albedo_texture = load(OAK)
	timber.albedo_color = Color(0.55, 0.46, 0.38)
	timber.uv1_triplanar = true
	timber.uv1_scale = Vector3.ONE * 0.7
	timber.roughness = 0.92
	roof = StandardMaterial3D.new()
	roof.albedo_texture = load(BOARDS % "diff")
	roof.normal_enabled = true
	roof.normal_texture = load(BOARDS % "nor_gl")
	roof.albedo_color = Color(0.62, 0.55, 0.48)
	roof.uv1_triplanar = true
	roof.uv1_scale = Vector3.ONE * 0.5
	_palisade()
	_outer_buildings()
	_wheat_field()
	_water_wheels()
	print("FOREST_CITY stakes=%d towers=%d houses=%d wheat=%d wheels=%d" % [stake_count, tower_count, house_count, wheat_count, wheels.size()])


# --- Step 4 (first part): the suburbs, the field, the water wheels ----------------------------------

## The village's log cabins stand in for the suburbs' houses: closed (no furniture, one box to collide
## with), their door towards the nearest road. The workshops use them too until their own models
## (Codex's concept sheets) are built - then they get interiors.
const KIT := {
	"H01": {"path": "res://assets/buildings/forest-village-v1/h01.glb", "size": Vector3(6, 3.2, 8)},
	"W01": {"path": "res://assets/buildings/forest-village-v1/w01.glb", "size": Vector3(7, 3.2, 9)},
	"B01": {"path": "res://assets/buildings/forest-village-v1/b01.glb", "size": Vector3(8, 3.7, 10)},
}
const WORKSHOP_KIT := {"water_mill": "W01", "sawmill": "B01", "log_yard": "B01", "bakery": "W01", "granary": "H01",
	"carpenter": "H01", "smithy": "H01", "charcoal_burner": "H01", "tar_kiln": "H01"}
var house_count := 0

func _outer_buildings() -> void:
	for b in plan.buildings:
		var kind := str(b.kind)
		var kit := ""
		if kind == "house":
			var area := float(b.size[0]) * float(b.size[1])
			kit = "H01" if area <= 48.0 else ("W01" if area <= 63.0 else "B01")
		elif WORKSHOP_KIT.has(kind):
			kit = WORKSHOP_KIT[kind]
		else:
			continue
		_closed_house(b, kit)


func _closed_house(b: Dictionary, kit: String) -> void:
	var map := Vector2(float(b.map[0]), float(b.map[1]))
	var at := ground_at(map)
	var yaw := -deg_to_rad(float(b.yaw_deg))
	var road := _nearest_road(Vector2(at.x, at.z), 40.0)
	if road != Vector2.INF:
		# The kit's entry is on its +z side.
		var to_road := road - Vector2(at.x, at.z)
		yaw = atan2(to_road.x, to_road.y)
	var size: Vector3 = KIT[kit].size
	var basis := Basis(Vector3.UP, yaw)
	var high := -INF
	for c in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
		var corner: Vector3 = at + basis * (c * Vector3(size.x * 0.5, 0, size.z * 0.5))
		high = maxf(high, world.world_ground(corner.x, corner.z))
	var house: Node3D = (load(KIT[kit].path) as PackedScene).instantiate()
	house.name = "%s_%s_%d" % [str(b.kind), kit, house_count]
	house.position = Vector3(at.x, high, at.z)
	house.rotation.y = yaw
	for mesh in house.find_children("*", "MeshInstance3D", true, false):
		var role := str((mesh as MeshInstance3D).get_meta("extras", {}).get("part_role", ""))
		if role == "furniture" or role == "ceiling":
			mesh.queue_free()
		else:
			(mesh as MeshInstance3D).visibility_range_end = VISIBLE
	add_child(house)
	var body := StaticBody3D.new()
	body.set_meta("footstep_surface", "wood")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size + Vector3(0.3, 0.6, 0.3)
	shape.shape = box
	shape.position = Vector3(0, size.y * 0.5, 0)
	body.add_child(shape)
	house.add_child(body)
	house_count += 1


func _nearest_road(at: Vector2, reach: float) -> Vector2:
	var best := Vector2.INF
	var nearest := reach
	for road in world.world_layout.roads:
		for p in road.world_points:
			var q := Vector2(float(p[0]), float(p[2]))
			var d := q.distance_to(at)
			if d < nearest:
				nearest = d
				best = q
	return best


## WHEAT: tufts of stalks over the field polygon (one MultiMesh), swaying a little in the wind.
var wheat_count := 0
const WHEAT_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert;
uniform vec3 base_colour : source_color = vec3(0.55, 0.45, 0.2);
uniform vec3 ear_colour : source_color = vec3(0.86, 0.72, 0.36);
void vertex() {
	float sway = sin(TIME * 1.3 + (MODEL_MATRIX[3].x + MODEL_MATRIX[3].z) * 0.35) * 0.08 * UV.y;
	VERTEX.x += sway;
}
void fragment() {
	// Thin stalks: the card is cut into five blades, an ear at the top of each.
	float blade = abs(fract(UV.x * 5.0) - 0.5);
	float width = mix(0.18, 0.06, UV.y);
	if (blade > width + (UV.y > 0.72 ? 0.12 : 0.0)) discard;
	ALBEDO = mix(base_colour, ear_colour, smoothstep(0.35, 0.8, UV.y));
	ROUGHNESS = 0.9;
}
"""

func _wheat_field() -> void:
	var polygon := PackedVector2Array()
	for p in plan.wheat_field:
		polygon.append(Vector2(float(p[0]), float(p[1])))
	var lo := polygon[0]
	var hi := polygon[0]
	for p in polygon:
		lo = lo.min(p)
		hi = hi.max(p)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1402
	var transforms: Array[Transform3D] = []
	var step := 0.75
	var z := lo.y
	while z <= hi.y:
		var x := lo.x
		while x <= hi.x:
			var m := Vector2(x + rng.randf_range(-0.3, 0.3), z + rng.randf_range(-0.3, 0.3))
			if Geometry2D.is_point_in_polygon(m, polygon):
				var at := ground_at(m)
				var s := rng.randf_range(0.85, 1.15)
				transforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * PI).scaled(Vector3(s, s, s)), at))
			x += step
		z += step
	var card := QuadMesh.new()
	card.size = Vector2(0.9, 1.0)
	card.center_offset = Vector3(0, 0.5, 0)
	var st := SurfaceTool.new()
	st.create_from(card, 0)
	# Two crossed cards per tuft.
	var cross := ArrayMesh.new()
	st.commit(cross)
	st.create_from(card, 0)
	var turned := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	st.append_from(card, 0, turned)
	var tuft := st.commit()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = tuft
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = WHEAT_SHADER
	material.shader = shader
	var field := MultiMeshInstance3D.new()
	field.name = "WheatField"
	field.multimesh = multimesh
	field.material_override = material
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	field.visibility_range_end = 220.0
	add_child(field)
	wheat_count = transforms.size()


## WATER WHEELS: by the mill and the sawmill, dipping into the river, turning with the flow.
var wheels: Array[Node3D] = []
const WHEEL_RADIUS := 2.3

func _water_wheels() -> void:
	for p in plan.water_wheels:
		var map := Vector2(float(p[0]), float(p[1]))
		var here := Vector2(map.x - float(world.HALF), map.y - float(world.HALF))
		# The nearest river point and the flow there.
		var best := INF
		var axis := Vector3.ZERO
		var flow := Vector3.FORWARD
		var water := 0.0
		var half := 4.0
		for river in world.world_layout.rivers:
			var pts: Array = river.world_points
			for i in range(1, pts.size() - 1):
				var q := Vector2(float(pts[i][0]), float(pts[i][2]))
				var d := q.distance_to(here)
				if d < best:
					best = d
					axis = Vector3(q.x, float(pts[i][1]), q.y)
					flow = Vector3(float(pts[i + 1][0]) - float(pts[i - 1][0]), 0, float(pts[i + 1][2]) - float(pts[i - 1][2])).normalized()
					water = float(pts[i][1])
					half = float(river.world_widths[i]) * 0.5
		# On the building's side of the river, just inside the water's edge.
		var side := Vector3(here.x - axis.x, 0, here.y - axis.z)
		var normal := Vector3(-flow.z, 0, flow.x)
		if normal.dot(side) < 0.0:
			normal = -normal
		var centre := Vector3(axis.x, water + WHEEL_RADIUS - 0.9, axis.z) + normal * (half - 1.2)
		var wheel := _wheel()
		wheel.position = centre
		# The wheel turns about the axis across the flow.
		wheel.basis = Basis.looking_at(normal, Vector3.UP)
		add_child(wheel)
		wheels.append(wheel)


func _wheel() -> Node3D:
	var root := Node3D.new()
	root.name = "WaterWheel"
	var spin := Node3D.new()
	spin.name = "Spin"
	root.add_child(spin)
	var paddles := 12
	for k in paddles:
		var a := TAU * k / paddles
		var dir := Vector3(0, sin(a), cos(a))
		# Spoke from the hub, a paddle board at the rim, rim segments between.
		_box_at(spin, dir * WHEEL_RADIUS * 0.5, Vector3(0.12, WHEEL_RADIUS, 0.12), a, timber)
		_box_at(spin, dir * WHEEL_RADIUS, Vector3(1.2, 0.08, 0.55), a, timber)
		var b := TAU * (k + 0.5) / paddles
		_box_at(spin, Vector3(0, sin(b), cos(b)) * (WHEEL_RADIUS - 0.05), Vector3(0.14, 0.14, TAU * WHEEL_RADIUS / paddles), b + PI * 0.5, timber)
	var hub := CylinderMesh.new()
	hub.top_radius = 0.28
	hub.bottom_radius = 0.28
	hub.height = 1.6
	var hub_mesh := MeshInstance3D.new()
	hub_mesh.mesh = hub
	hub_mesh.material_override = timber
	hub_mesh.rotation.z = PI * 0.5
	root.add_child(hub_mesh)
	return root


func _box_at(parent: Node3D, at: Vector3, size: Vector3, angle: float, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.rotation.x = -angle
	instance.visibility_range_end = VISIBLE
	parent.add_child(instance)


func _process(delta: float) -> void:
	for wheel in wheels:
		(wheel.get_node("Spin") as Node3D).rotate_x(-0.6 * delta)


## The world-frame point of a map point on the ground.
func ground_at(map: Vector2) -> Vector3:
	var x: float = map.x - float(world.HALF)
	var z: float = map.y - float(world.HALF)
	return Vector3(x, world.world_ground(x, z), z)


func _palisade() -> void:
	var p: Dictionary = plan.palisade
	var centre := Vector2(float(p.center[0]), float(p.center[1]))
	var radius := float(p.radius)
	var gates: Array[float] = []
	for gate in p.gates:
		gates.append(deg_to_rad(float(gate.deg)))
	# A gate leaves a gap of GATE_WIDTH and has a tower on either side of it.
	var gap := GATE_WIDTH / radius * 0.5
	var tower_gap := (GATE_WIDTH * 0.5 + TOWER * 0.5) / radius
	var rng := RandomNumberGenerator.new()
	rng.seed = 7736
	var stakes := MultiMesh.new()
	stakes.transform_format = MultiMesh.TRANSFORM_3D
	stakes.mesh = _stake_mesh()
	var transforms: Array[Transform3D] = []
	var body := StaticBody3D.new()
	body.name = "PalisadeWall"
	body.set_meta("footstep_surface", "wood")
	add_child(body)
	var count := int(TAU * radius / STAKE_SPACING)
	var run_start := -1.0
	var last := Vector3.INF
	for i in count + 1:
		var angle := TAU * i / count
		var at_gate := false
		for g in gates:
			if absf(wrapf(angle - g, -PI, PI)) < gap + TOWER * 0.5 / radius:
				at_gate = true
		var at := ground_at(centre + Vector2.from_angle(angle) * radius)
		if not at_gate and i < count:
			var h := STAKE_HEIGHT + rng.randf_range(-0.3, 0.25)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, (h + SINK) / (STAKE_HEIGHT + SINK), 1.0))
			transforms.append(Transform3D(basis, at + Vector3.DOWN * SINK))
			# The wall's collision: one box per 4 m of stakes.
			if last == Vector3.INF:
				last = at
			elif at.distance_to(last) >= 4.0:
				_wall_box(body, last, at)
				last = at
		else:
			if last != Vector3.INF and at.distance_to(last) > 0.3:
				_wall_box(body, last, at)
			last = Vector3.INF
	stakes.instance_count = transforms.size()
	for i in transforms.size():
		stakes.set_instance_transform(i, transforms[i])
	stake_count = transforms.size()
	var instance := MultiMeshInstance3D.new()
	instance.name = "Palisade"
	instance.multimesh = stakes
	instance.material_override = timber
	instance.visibility_range_end = VISIBLE
	add_child(instance)
	# Towers: ten along the wall away from the gates, and two at each gate.
	for i in int(p.towers):
		var angle := deg_to_rad(i * 36.0 + 18.0)
		var near_gate := false
		for g in gates:
			if absf(wrapf(angle - g, -PI, PI)) < deg_to_rad(14.0):
				near_gate = true
		if not near_gate:
			_tower(centre, radius, angle, false)
	for g in gates:
		for side in [-1.0, 1.0]:
			_tower(centre, radius, g + side * tower_gap, true)


func _wall_box(body: StaticBody3D, a: Vector3, b: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.45, STAKE_HEIGHT + SINK, a.distance_to(b) + 0.3)
	shape.shape = box
	var mid := (a + b) * 0.5 + Vector3.UP * (STAKE_HEIGHT - SINK) * 0.5
	shape.transform = Transform3D(Basis.looking_at(b - a, Vector3.UP), mid)
	body.add_child(shape)


## A sharpened log: 8 sides, a cone tip, from the bottom of its sunk part up to STAKE_HEIGHT.
func _stake_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 8
	var top := STAKE_HEIGHT + SINK - 0.45
	var tip := STAKE_HEIGHT + SINK
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var p0 := Vector3(cos(a0), 0, sin(a0)) * STAKE_RADIUS
		var p1 := Vector3(cos(a1), 0, sin(a1)) * STAKE_RADIUS
		for v in [p0, p1 + Vector3.UP * top, p1, p0, p0 + Vector3.UP * top, p1 + Vector3.UP * top]:
			st.add_vertex(v)
		for v in [p0 + Vector3.UP * top, Vector3.UP * tip, p1 + Vector3.UP * top]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## A log tower: a crib of horizontal logs, a platform, four posts and a pyramid roof.
func _tower(centre: Vector2, radius: float, angle: float, gate: bool) -> void:
	var map := centre + Vector2.from_angle(angle) * radius
	var base := ground_at(map)
	var tower := Node3D.new()
	tower.name = "%sTower_%d" % ["Gate" if gate else "Wall", tower_count]
	tower.position = base
	# Faces out of the town.
	tower.rotation.y = -angle + PI * 0.5
	add_child(tower)
	var half := TOWER * 0.5
	var logs := MultiMesh.new()
	logs.transform_format = MultiMesh.TRANSFORM_3D
	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = LOG * 0.5
	log_mesh.bottom_radius = LOG * 0.5
	log_mesh.height = TOWER + 0.5
	log_mesh.radial_segments = 8
	log_mesh.rings = 1
	logs.mesh = log_mesh
	var rows: Array[Transform3D] = []
	var y := -0.3 + LOG * 0.5
	var course := 0
	var crib_top := TOWER_HEIGHT - 1.6
	while y < crib_top:
		# Two walls on one course, the other two half a log higher (the corner joint).
		var along_x := course % 2 == 0
		for s in [-1.0, 1.0]:
			var pos := Vector3(0, y, s * (half - LOG * 0.5)) if along_x else Vector3(s * (half - LOG * 0.5), y, 0)
			var rot := Basis(Vector3.FORWARD, PI * 0.5) if along_x else Basis(Vector3.RIGHT, PI * 0.5)
			rows.append(Transform3D(rot, pos))
		y += LOG * 0.5
		course += 1
	logs.instance_count = rows.size()
	for i in rows.size():
		logs.set_instance_transform(i, rows[i])
	var crib := MultiMeshInstance3D.new()
	crib.multimesh = logs
	crib.material_override = timber
	crib.visibility_range_end = VISIBLE
	tower.add_child(crib)
	# The fighting platform: posts and a rail above the crib, then the roof.
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_box(tower, Vector3(cx * (half - 0.15), crib_top + 0.8, cz * (half - 0.15)), Vector3(0.22, 1.6, 0.22), timber)
	_box(tower, Vector3(0, crib_top + 0.05, 0), Vector3(TOWER + 0.3, 0.12, TOWER + 0.3), timber)
	for s in [-1.0, 1.0]:
		_box(tower, Vector3(0, crib_top + 0.9, s * (half - 0.15)), Vector3(TOWER, 0.1, 0.12), timber)
		_box(tower, Vector3(s * (half - 0.15), crib_top + 0.9, 0), Vector3(0.12, 0.1, TOWER), timber)
	var pyramid := CylinderMesh.new()
	pyramid.top_radius = 0.05
	pyramid.bottom_radius = (TOWER + 1.0) * 0.72
	pyramid.height = 2.2
	pyramid.radial_segments = 4
	pyramid.rings = 1
	var roof_mesh := MeshInstance3D.new()
	roof_mesh.mesh = pyramid
	roof_mesh.material_override = roof
	roof_mesh.position = Vector3(0, crib_top + 1.6 + 1.1, 0)
	roof_mesh.rotation.y = PI * 0.25
	roof_mesh.visibility_range_end = VISIBLE
	tower.add_child(roof_mesh)
	var body := StaticBody3D.new()
	body.set_meta("footstep_surface", "wood")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(TOWER, crib_top + 0.3, TOWER)
	shape.shape = box
	shape.position = Vector3(0, (crib_top + 0.3) * 0.5 - 0.3, 0)
	body.add_child(shape)
	tower.add_child(body)
	tower_count += 1


func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.visibility_range_end = VISIBLE
	parent.add_child(instance)
