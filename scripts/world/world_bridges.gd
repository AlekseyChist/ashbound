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
## The ramp at each end starts this far over the ground and climbs at most this grade.
const RAMP_TOE := 0.04
const RAMP_GRADE := 0.25

var world: Node3D
var boards: StandardMaterial3D
var timber: StandardMaterial3D
## The ramp side boards: the deck's boards, seen from both sides (a single wall, no back face).
var skirt_material: StandardMaterial3D
var bridge_count := 0
var _rails: StaticBody3D
## Centres of the bridges built so far: where two roads share a crossing, one bridge stands.
var _centres: Array[Vector3] = []
var _spans: Array[PackedVector3Array] = []


func configure(scene: Node3D) -> void:
	world = scene
	boards = StandardMaterial3D.new()
	boards.albedo_texture = load(BOARDS % "diff")
	boards.normal_enabled = true
	boards.normal_texture = load(BOARDS % "nor_gl")
	boards.roughness_texture = load(BOARDS % "rough")
	boards.albedo_color = Color(0.8, 0.72, 0.62)
	skirt_material = boards.duplicate()
	skirt_material.cull_mode = BaseMaterial3D.CULL_DISABLED
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


## The deck's own heights over `run`: level over the water; at both ends a ramp (BRIDGES-02, owner
## 28 Sep: "a ramp to the bridge, no gaps, a smooth way up") from the ground on the bank up to it.
## `core` marks the samples over the water (the deck height comes from them, not from the road
## climbing the bank); `on_land` (optional) is filled with 1 where the ramp stands over the bank.
func deck_profile(run: PackedVector3Array, core: PackedByteArray, on_land: PackedByteArray = PackedByteArray()) -> PackedVector3Array:
	var deck_top := -INF
	for i in run.size():
		if core[i] == 1:
			deck_top = maxf(deck_top, run[i].y)
	var along := PackedFloat32Array([0.0])
	for i in range(1, run.size()):
		along.append(along[i - 1] + Vector2(run[i].x - run[i - 1].x, run[i].z - run[i - 1].z).length())
	var total: float = along[along.size() - 1]
	var ends := [world.world_ground(run[0].x, run[0].z) + RAMP_TOE, world.world_ground(run[run.size() - 1].x, run[run.size() - 1].z) + RAMP_TOE]
	var result := PackedVector3Array()
	on_land.resize(run.size())
	for i in run.size():
		var from_start: float = along[i]
		var from_end: float = total - along[i]
		var near_start := from_start <= from_end
		var toe: float = ends[0] if near_start else ends[1]
		# At most RAMP_GRADE, never longer than a third of the bridge.
		var length := clampf(absf(deck_top - toe) / RAMP_GRADE, 1.0, total / 3.0)
		var t := smoothstep(0.0, length, from_start if near_start else from_end)
		result.append(Vector3(run[i].x, lerpf(toe, deck_top, t), run[i].z))
		on_land[i] = 1 if t < 1.0 else 0
	return result


## One bridge over `run` (deck points in the world frame) for a road `width` metres wide.
func build_bridge(run: PackedVector3Array, width: float, core: PackedByteArray) -> void:
	if run.size() < 2:
		return
	# The centre of the part over the water: two roads sharing a crossing reach different banks.
	var first := core.find(1)
	var last := core.rfind(1)
	var mid := (run[first] + run[last]) * 0.5 if first >= 0 else (run[0] + run[run.size() - 1]) * 0.5
	for other in _centres:
		if Vector2(other.x - mid.x, other.z - mid.z).length() < 12.0:
			return
	# Two roads sharing a crossing but not its middle (they leave it for different banks): the second
	# is skipped when most of its span over the water lies on a bridge already built.
	var span := PackedVector3Array()
	for i in run.size():
		if core[i] == 1:
			span.append(run[i])
	var shared := 0
	for p in span:
		for built in _spans:
			if _near(p, built, 4.0):
				shared += 1
				break
	if shared * 2 >= span.size() and span.size() > 0:
		return
	_spans.append(span)
	_centres.append(mid)
	var on_land := PackedByteArray()
	run = deck_profile(run, core, on_land)
	var bridge := Node3D.new()
	bridge.name = "Bridge_%d" % bridge_count
	add_child(bridge)
	var half := maxf(width, 3.0) * 0.5
	var sides: Array[Vector3] = []
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Flat normals: smoothed with the side faces the top leaned 45 degrees and the boards lit dim.
	st.set_smooth_group(0xFFFFFFFF)
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
	# BRIDGES-02 (owner 28 Sep, forest city: rails but no deck): the faces' winding follows the road's
	# direction, so on a road drawn the other way the deck faced down and was culled from above.
	# Swap the sides so the top always faces up.
	if rows.size() >= 2:
		var r0: Array = rows[0]
		var r1: Array = rows[1]
		if ((r0[1] as Vector3) - (r0[0] as Vector3)).cross((r1[0] as Vector3) - (r0[0] as Vector3)).y > 0.0:
			for row in rows:
				var left: Vector3 = row[0]
				row[0] = row[1]
				row[1] = left
				row[3] = -(row[3] as Vector3)
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
	# Under the ramps, boards from the deck edge down into the bank: no gap to see through at the sides.
	var skirt := SurfaceTool.new()
	skirt.begin(Mesh.PRIMITIVE_TRIANGLES)
	skirt.set_smooth_group(0xFFFFFFFF)
	var skirted := false
	for i in rows.size() - 1:
		if on_land[i] == 0 and on_land[i + 1] == 0:
			continue
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		for s in [0, 1]:
			var a: Vector3 = (r0[s] as Vector3) + Vector3.DOWN * DECK_THICKNESS
			var b: Vector3 = (r1[s] as Vector3) + Vector3.DOWN * DECK_THICKNESS
			var a_low := Vector3(a.x, minf(world.world_ground(a.x, a.z) - 0.3, a.y), a.z)
			var b_low := Vector3(b.x, minf(world.world_ground(b.x, b.z) - 0.3, b.y), b.z)
			var quad := [a, b, b_low, a_low]
			for k in [0, 1, 2, 0, 2, 3]:
				skirt.set_uv(Vector2(float(r0[2] if k in [0, 3] else r1[2]), (quad[k] as Vector3).y) * 0.5)
				skirt.add_vertex(quad[k])
			skirted = true
	if skirted:
		skirt.generate_normals()
		var ramp_sides := MeshInstance3D.new()
		ramp_sides.name = "RampSides"
		ramp_sides.mesh = skirt.commit()
		ramp_sides.material_override = skirt_material
		ramp_sides.visibility_range_end = VISIBLE
		bridge.add_child(ramp_sides)
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


func _near(p: Vector3, points: PackedVector3Array, reach: float) -> bool:
	for q in points:
		if Vector2(p.x - q.x, p.z - q.z).length() < reach:
			return true
	return false


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
