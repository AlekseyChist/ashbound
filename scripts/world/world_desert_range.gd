extends Node3D
## DA-FIELD01 (book sheet of the desert city, PDF141 p.37-39; Codex 485): the longbow range beside the
## pavilion Лк - the plan's field line (1716,300)->(1664,298), 5 m wide, 52 m long, shot westward at
## "the fire sign on the cliff" by 1662/298. The ground there is a 9 deg slope with no cliff, so the
## target is an edge-rocks cliff stone set on it, its long face east, the sign painted on its real face
## (a decal, so it lies on the rock). A timber shooting sill at the start, stakes at 20 and 40 m, a few
## low stones beside the strip (no kerb). No fire, no new light (Codex 485: the city's shadow budget).
## Frame: the world root's (map - 1000).
const PLAN := "res://assets/world/desert-city-v1/plan.json"
const CLIFF := "res://assets/environment/world-props-v1/namaqualand_boulder_03.glb"
## the desert's own big boulder, x3.4: about 10.5 m across the range, 8.2 deep, 5 m high (the edge-rocks
## cliff read grey, a heap of stones beside the ochre desert)
const CLIFF_SCALE := 3.4
const STONE := "res://assets/environment/world-props-v1/namaqualand_boulder_06.glb"
const WOOD := "res://assets/environment/village-house-materials-v1/fine_grained_wood_col_1k.jpg"
const HALF := 1000.0
## the cliff stone's half depth (its model z, turned to face east) and how far its face stands west of
## the book's mark
const CLIFF_HALF_DEPTH := 1.2 * 3.4
const SIGN_SIZE := 2.2
const SIGN_HEIGHT := 2.0

var world: Node3D
var start := Vector2.ZERO          # map frame
var end := Vector2.ZERO
var axis := Vector2.ZERO           # unit, start -> end (west)
var across := Vector2.ZERO         # unit, to the axis's right (north)
var width := 5.0
var cliff: Node3D
var sign_decal: Decal
var sign_hit := {}
var parts: Array[Node3D] = []


func build(scene: Node3D) -> void:
	world = scene
	name = "DesertRange"
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLAN))
	for line in plan.get("lines", []):
		if str(line.kind) == "field":
			start = Vector2(float(line.pts[0][0]), float(line.pts[0][1]))
			end = Vector2(float(line.pts[-1][0]), float(line.pts[-1][1]))
			width = float(line.width)
	if start == end:
		push_warning("DESERT_RANGE no field line in the plan")
		return
	axis = (end - start).normalized()
	across = Vector2(-axis.y, axis.x)
	_sill()
	for metres in [20.0, 40.0]:
		_stake(start + axis * metres + across * (width * 0.5 + 0.5), metres)
	_edge_stones()
	_cliff()
	_sign_after_physics.call_deferred()


func _at(map: Vector2, lift := 0.0) -> Vector3:
	var x := map.x - HALF
	var z := map.y - HALF
	return Vector3(x, float(world.world_ground(x, z)) + lift, z)


func _wood() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(WOOD)
	m.albedo_color = Color(.55, .42, .30)
	m.roughness = .95
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 1.4
	return m


## The shooting sill: a squared timber across the strip at its start, sunk into the ground so the hero
## steps over it (no collider: it is the line, not a fence).
func _sill() -> void:
	var beam := MeshInstance3D.new()
	beam.name = "ShootingSill"
	var box := BoxMesh.new()
	box.size = Vector3(width + 0.4, 0.16, 0.2)
	beam.mesh = box
	beam.material_override = _wood()
	var low := INF
	for k in [-0.5, 0.0, 0.5]:
		low = minf(low, _at(start + across * width * k).y)
	beam.position = _at(start)
	beam.position.y = low + 0.03
	beam.rotation.y = atan2(-axis.y, axis.x) + PI * 0.5
	add_child(beam)
	parts.append(beam)


## A distance stake beside the strip's north edge: a post with a red band, solid.
func _stake(map: Vector2, metres: float) -> void:
	var root := Node3D.new()
	root.name = "Stake%d" % int(metres)
	root.position = _at(map)
	add_child(root)
	parts.append(root)
	var post := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 1.3, 0.12)
	post.mesh = box
	post.material_override = _wood()
	post.position.y = 0.6
	root.add_child(post)
	var band := MeshInstance3D.new()
	var band_box := BoxMesh.new()
	band_box.size = Vector3(0.13, 0.16, 0.13)
	band.mesh = band_box
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(.55, .14, .08)
	red.roughness = .9
	band.material_override = red
	band.position.y = 1.08 if metres < 30.0 else 0.88
	root.add_child(band)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var col := BoxShape3D.new()
	col.size = Vector3(0.14, 1.3, 0.14)
	shape.shape = col
	shape.position.y = 0.6
	body.add_child(shape)
	root.add_child(body)


## A few low stones off both edges, alternating sides every 7 m - a hint of the strip, never a kerb;
## no colliders (they are ankle high).
func _edge_stones() -> void:
	var scene: PackedScene = load(STONE)
	var side := 1.0
	var metres := 7.0
	while metres < 48.0:
		var stone: Node3D = scene.instantiate()
		var map := start + axis * metres + across * side * (width * 0.5 + 0.6)
		stone.position = _at(map, -0.06)
		stone.rotation.y = metres * 1.7
		stone.scale = Vector3.ONE * (0.45 + 0.1 * fmod(metres, 3.0))
		add_child(stone)
		parts.append(stone)
		side = -side
		metres += 7.0


## The target stone: its long side across the range, its face 2.19 m east of its centre, that face by the
## book's mark (x 1662); its base on the lower (east) ground there, sunk 0.3 m; its own surfaces collide.
func _cliff() -> void:
	cliff = (load(CLIFF) as PackedScene).instantiate()
	cliff.name = "FireSignCliff"
	var mark := Vector2(1662.0, 298.0)
	var centre := mark + axis * CLIFF_HALF_DEPTH       # axis points west: the centre stands west of the face
	var base := INF
	for k in [-1.0, 0.0, 1.0]:
		base = minf(base, _at(mark + across * 5.0 * k).y)
	cliff.position = Vector3(centre.x - HALF, base - 0.35, centre.y - HALF)
	# its long model z across the range, model +x to the start (east)
	cliff.rotation.y = atan2(axis.y, -axis.x)
	cliff.scale = Vector3.ONE * CLIFF_SCALE
	add_child(cliff)
	for m in cliff.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).create_trimesh_collision()


## The fire sign: once the cliff's colliders are in, a ray from the start's side finds its real face at
## SIGN_HEIGHT over the ground there; a decal paints the sign onto that surface, facing the start.
func _sign_after_physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_instance_valid(cliff):
		return
	var mark := Vector2(1662.0, 298.0)
	var probe_map := mark - axis * 3.0
	var from_local := _at(probe_map, SIGN_HEIGHT)
	var to_local := from_local + Vector3(axis.x, 0, axis.y) * 8.0
	var space := get_world_3d().direct_space_state
	var parent := get_parent() as Node3D
	var query := PhysicsRayQueryParameters3D.create(parent.to_global(from_local), parent.to_global(to_local))
	var hit := space.intersect_ray(query)
	if hit.is_empty() or not cliff.is_ancestor_of(hit.collider):
		push_warning("DESERT_RANGE the sign's ray missed the cliff")
		return
	sign_hit = {"position": parent.to_local(hit.position), "normal": hit.normal}
	sign_decal = Decal.new()
	sign_decal.name = "FireSign"
	sign_decal.size = Vector3(SIGN_SIZE, 1.4, SIGN_SIZE)
	sign_decal.texture_albedo = _sign_texture()
	sign_decal.cull_mask = 1
	add_child(sign_decal)
	# the decal paints along its -Y: -Y along the range into the rock, so the sign faces the start
	# (Codex 485: about east, 2.2 deg south) whatever the rock's bumps; 1.4 m deep to lie over them
	var n: Vector3 = parent.global_basis * Vector3(-axis.x, 0, -axis.y)
	var y_axis := n.normalized()
	var x_axis := Vector3.UP.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	sign_decal.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), hit.position)
	print("DESERT_RANGE sign at %s normal %s" % [sign_hit.position, n])


## A round sign: a soot-dark rim, an ochre disc, a red flame with a yellow heart (the Order's fire);
## weathered by a little noise. 256 px, transparent outside the disc.
func _sign_texture() -> Texture2D:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var rim := Color(.36, .12, .06)
	var ochre := Color(.93, .78, .48)
	var red := Color(.80, .18, .06)
	var yellow := Color(1.0, .86, .38)
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(c) / (size * 0.5)
			if d > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var col := ochre if d < 0.9 else rim
			if d > 0.80 and d < 0.83:
				col = rim
			# the flame: in picture space u across (-1..1), v up (-1..1)
			var u := (x - c.x) / (size * 0.5)
			var v := (c.y - y) / (size * 0.5)
			var t := (v + 0.55) / 1.15                  # 0 at the flame's foot, 1 at its tip
			if t > 0.0 and t < 1.0:
				var half := 0.42 * sin(PI * pow(t, 0.75)) * (1.0 - 0.35 * t)
				var bend := 0.10 * sin(t * 5.0)
				if absf(u - bend * t) < half:
					col = red
					if t < 0.62 and absf(u - bend * t) < half * 0.45 and t > 0.08:
						col = yellow
			var grain := fposmod(sin(float(x * 12.9898 + y * 78.233)) * 43758.5453, 1.0)
			col = col.darkened(0.12 * grain)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, 0.95 if d < 0.97 else 0.95 * (1.0 - d) / 0.03))
	return ImageTexture.create_from_image(img)
