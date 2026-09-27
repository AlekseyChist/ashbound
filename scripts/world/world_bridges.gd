extends Node3D
## BRIDGES-01 (owner 27 Sep: "we need proper bridges"): a timber bridge on every river crossing.
## The road's deck strip stays as the walking surface (its collision) but is hidden; over it
## - a deck of boards laid across the road (Poly Haven brown_planks_04, as the inn's roof);
## - two stringers under the deck edges;
## - piles every PILE_STEP metres down to the river bed;
## - posts and handrails on both sides, solid, so the hero stays on the bridge.
const BOARDS := "res://assets/props/tavern-v1/roof/brown_planks_04_%s_1k.jpg"
const OAK := "res://assets/buildings/forest-inn-v1/t03a_Forest_oak.png"
const DECK_THICKNESS := 0.18
const PILE_STEP := 2.5
const RAIL_HEIGHT := 1.0
const VISIBLE := 180.0

var world: Node3D
var boards: StandardMaterial3D
var timber: StandardMaterial3D
var bridge_count := 0
var _rails: StaticBody3D


func configure(scene: Node3D) -> void:
	world = scene
	boards = StandardMaterial3D.new()
	boards.albedo_texture = load(BOARDS % "diff")
	boards.normal_enabled = true
	boards.normal_texture = load(BOARDS % "nor_gl")
	boards.roughness_texture = load(BOARDS % "rough")
	boards.albedo_color = Color(0.8, 0.72, 0.62)
	timber = StandardMaterial3D.new()
	timber.albedo_texture = load(OAK)
	timber.albedo_color = Color(0.6, 0.5, 0.42)
	timber.uv1_triplanar = true
	timber.uv1_scale = Vector3.ONE * 0.8
	timber.roughness = 0.9
	_rails = StaticBody3D.new()
	_rails.name = "BridgeRails"
	_rails.set_meta("footstep_surface", "wood")
	add_child(_rails)


## One bridge over `run` (deck points in the world frame) for a road `width` metres wide.
func build_bridge(run: PackedVector3Array, width: float) -> void:
	if run.size() < 2:
		return
	var bridge := Node3D.new()
	bridge.name = "Bridge_%d" % bridge_count
	add_child(bridge)
	var half := maxf(width, 3.0) * 0.5
	var sides: Array[Vector3] = []
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var rows := []
	for i in run.size():
		var a := run[maxi(i - 1, 0)]
		var b := run[mini(i + 1, run.size() - 1)]
		var side := Vector3(-(b.z - a.z), 0.0, b.x - a.x).normalized()
		if i > 0:
			along += run[i].distance_to(run[i - 1])
		var top := run[i] + Vector3.UP * 0.06
		rows.append([top - side * half, top + side * half, along, side])
	# Deck: the top with boards across the road, and its two side faces.
	for i in rows.size() - 1:
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		var down := Vector3.DOWN * DECK_THICKNESS
		for face in [[r0[0], r0[1], r1[1], r1[0], true], [r0[0], r1[0], r1[0] + down, r0[0] + down, false], [r0[1], r0[1] + down, r1[1] + down, r1[1], false]]:
			var uv := [Vector2(0.0, r0[2]), Vector2(half, r0[2]), Vector2(half, r1[2]), Vector2(0.0, r1[2])] if face[4] else \
				[Vector2(r0[2], 0.0), Vector2(r1[2], 0.0), Vector2(r1[2], 0.2), Vector2(r0[2], 0.2)]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_uv(uv[k] / 2.0)
				st.add_vertex(face[k])
	st.generate_normals()
	st.generate_tangents()
	var deck := MeshInstance3D.new()
	deck.name = "Deck"
	deck.mesh = st.commit()
	deck.material_override = boards
	deck.visibility_range_end = VISIBLE
	bridge.add_child(deck)
	# Stringers, rails and piles, segment by segment.
	var next_pile := 0.0
	for i in rows.size() - 1:
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		for s in [0, 1]:
			var p0: Vector3 = r0[s]
			var p1: Vector3 = r1[s]
			var inward: Vector3 = (r0[3] as Vector3) * (0.12 if s == 0 else -0.12)
			_beam(bridge, p0 + inward + Vector3.DOWN * (DECK_THICKNESS + 0.15), p1 + inward + Vector3.DOWN * (DECK_THICKNESS + 0.15), Vector2(0.24, 0.3))
			_beam(bridge, p0 + inward + Vector3.UP * RAIL_HEIGHT, p1 + inward + Vector3.UP * RAIL_HEIGHT, Vector2(0.1, 0.12), true)
		while next_pile <= r1[2]:
			var t: float = inverse_lerp(r0[2], r1[2], next_pile) if r1[2] > r0[2] else 0.0
			for s in [0, 1]:
				var inward: Vector3 = (r0[3] as Vector3) * (0.12 if s == 0 else -0.12)
				var top: Vector3 = (r0[s] as Vector3).lerp(r1[s], t) + inward
				var bed: float = world.world_ground(top.x, top.z) - 0.5
				_post(bridge, Vector3(top.x, bed, top.z), top.y + RAIL_HEIGHT + 0.05 - bed)
			next_pile += PILE_STEP
	bridge_count += 1


func _beam(parent: Node3D, from: Vector3, to: Vector3, section: Vector2, solid: bool = false) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	var box := BoxMesh.new()
	box.size = Vector3(section.x, section.y, length + 0.1)
	var beam := MeshInstance3D.new()
	beam.mesh = box
	beam.material_override = timber
	var basis := Basis.looking_at(to - from, Vector3.UP)
	beam.transform = Transform3D(basis, (from + to) * 0.5)
	beam.visibility_range_end = VISIBLE
	parent.add_child(beam)
	if solid:
		var shape := CollisionShape3D.new()
		var wall := BoxShape3D.new()
		wall.size = Vector3(0.2, RAIL_HEIGHT + 0.3, length + 0.1)
		shape.shape = wall
		shape.transform = Transform3D(basis, (from + to) * 0.5 + Vector3.DOWN * (RAIL_HEIGHT * 0.5))
		_rails.add_child(shape)


func _post(parent: Node3D, base: Vector3, height: float) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.2, height, 0.2)
	var post := MeshInstance3D.new()
	post.mesh = box
	post.material_override = timber
	post.position = base + Vector3.UP * height * 0.5
	post.visibility_range_end = VISIBLE
	parent.add_child(post)
