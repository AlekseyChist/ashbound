extends Node3D
## WORLD-BUILD-01A (D-118): grey volumes at the new places of the accepted world book (PLACES.md) -
## the capital ruins on their terrace, the band's camp in the Old Pine Grove, Wolf Hollow, Watch
## Rock, the salt works, the peat farmstead and the outskirts farmsteads. The graybox landmarks'
## palette, no new looks: the buildings come later, place by place, from Codex's sheets. Solid boxes
## (the hero walks round the walls and climbs the lookout's steps); each stands on the lowest ground
## under it and reaches 0.3 m into it, so nothing floats on a slope.

const PALETTE := {
	"clay": Color("#92938b"),
	"roof": Color("#766a56"),
	"rock": Color("#777970"),
	"dark": Color("#252a29"),
	"timber": Color("#6e5f4c"),
	"salt": Color("#d6d3c8"),
	"peat": Color("#3b2f26"),
}
const HALF := 1000.0
const SINK := 0.3

var world: Node
var boxes := 0
var _materials := {}


func build(world_node: Node, places: Array) -> void:
	world = world_node
	name = "BookPlaces"
	for place in places:
		var node := Node3D.new()
		node.name = str(place.id)
		add_child(node)
		var at := Vector2(float(place.point[0]) - HALF, float(place.point[1]) - HALF)
		match str(place.kind):
			"ruins":
				_ruins(node, at)
			"camp":
				_camp(node, at)
			"hollow":
				_hollow(node, at)
			"lookout":
				_lookout(node, at)
			"saltworks":
				_saltworks(node, at)
			"viewpoint":
				_viewpoint(node, at)
			"farmstead":
				_farmstead(node, at)
			"farmsteads":
				for offset in [Vector2(-50, -20), Vector2(40, 10), Vector2(0, 55)]:
					_farmstead(node, at + offset)
			_:
				push_warning("BOOK_PLACES unknown kind %s" % place.kind)
	print("BOOK_PLACES places=%d boxes=%d" % [places.size(), boxes])


## A box whose footprint centre is `c` (world frame x/z), `size` metres, turned by `yaw` degrees:
## its base on the lowest ground under its corners, SINK below; `lift` raises it off that base.
func _box(parent: Node3D, c: Vector2, size: Vector3, colour: String, yaw := 0.0, lift := 0.0, solid := true, tilt := 0.0) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw))
	var low := INF
	for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2.ZERO]:
		var p: Vector3 = basis * Vector3(k.x * size.x * 0.5, 0, k.y * size.z * 0.5)
		low = minf(low, ground(c.x + p.x, c.y + p.z))
	var height := size.y + SINK
	var centre := Vector3(c.x, low - SINK + lift + height * 0.5, c.y)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x, height, size.z)
	mesh.mesh = box
	mesh.material_override = _material(colour)
	mesh.position = centre
	mesh.rotation = Vector3(deg_to_rad(tilt), deg_to_rad(yaw), 0)
	mesh.visibility_range_end = 450.0
	parent.add_child(mesh)
	boxes += 1
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = box.size
		shape.shape = bs
		body.add_child(shape)
		body.position = centre
		body.rotation.y = deg_to_rad(yaw)
		parent.add_child(body)


## The ground the hero walks on at a world-frame point: near the start the village's own terrain
## (the world lifts its grid round it), elsewhere the world grid.
func ground(x: float, z: float) -> float:
	var off: Vector3 = world.world_root.position
	return world.ground_height_local(x + off.x, z + off.z) - off.y


const MASONRY := "res://assets/environment/village-house-materials-v1/stone_wall_02_%s_1k.jpg"
const WOOD := "res://assets/environment/village-house-materials-v1/fine_grained_wood_%s_1k.jpg"
## Codex a406d48 native: the flights' flat pale treads and flat brown rails and decks read as grey
## blocks - the treads take the same stone, lighter and finer; the rails and decks the village houses'
## timber. [texture, tint, uv scale] in world space.
const TEXTURED := {
	"masonry": [MASONRY, Color(0.78, 0.77, 0.72), 0.45],
	"tread": [MASONRY, Color(0.95, 0.93, 0.88), 0.9],
	"wood": [WOOD, Color(0.62, 0.52, 0.42), 0.8],
}

func _material(colour: String) -> StandardMaterial3D:
	if TEXTURED.has(colour) and not _materials.has(colour):
		# The stairs' supporting bodies (Codex 14 Oct: tall flat grey planes): the village houses' CC0
		# stone wall, projected in world space so neighbouring blocks run on as one masonry wall.
		var spec: Array = TEXTURED[colour]
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(spec[0] % ("col" if spec[0] == WOOD else "diff"))
		m.normal_enabled = true
		m.normal_texture = load(spec[0] % "nor_gl")
		m.roughness_texture = load(spec[0] % "rough")
		m.albedo_color = spec[1]
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * float(spec[2])
		_materials[colour] = m
	if not _materials.has(colour):
		var m := StandardMaterial3D.new()
		m.albedo_color = PALETTE[colour]
		m.roughness = 1.0
		_materials[colour] = m
	return _materials[colour]


## A wall from a to b (world frame), `thick` wide, `height` tall.
func _wall(parent: Node3D, a: Vector2, b: Vector2, thick: float, height: float, colour := "rock") -> void:
	var d := b - a
	_box(parent, (a + b) * 0.5, Vector3(thick, height, d.length()), colour, rad_to_deg(atan2(d.x, d.y)))


## A wall from a to b in pieces of about 6 m with uneven broken tops; `gaps` are [from, to] metres
## along it left open (gates and breaches).
func _broken_wall(parent: Node3D, a: Vector2, b: Vector2, low: float, high: float, gaps: Array, seed: int) -> void:
	var length := a.distance_to(b)
	var count := maxi(1, int(round(length / 6.0)))
	for i in count:
		var t0 := float(i) / count * length
		var t1 := float(i + 1) / count * length
		var open := false
		for g in gaps:
			if t1 > float(g[0]) and t0 < float(g[1]):
				open = true
		if open:
			continue
		var h := lerpf(low, high, fposmod(sin(float(seed * 31 + i * 7)) * 43758.5453, 1.0))
		_wall(parent, a.lerp(b, t0 / length), a.lerp(b, t1 / length), 1.2, h)


## Four broken walls round a w x d footprint (no roof): a ruined building, door gap on `door` side.
func _shell(parent: Node3D, c: Vector2, w: float, d: float, low: float, high: float, door_side: int, seed: int) -> void:
	var h := Vector2(w, d) * 0.5
	var corners := [c + Vector2(-h.x, -h.y), c + Vector2(h.x, -h.y), c + Vector2(h.x, h.y), c + Vector2(-h.x, h.y)]
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var gaps := []
		if side == door_side:
			var mid := a.distance_to(b) * 0.5
			gaps = [[mid - 1.8, mid + 1.8]]
		_broken_wall(parent, a, b, low, high, gaps, seed + side)


# --- the capital ruins (book sheet 15): a walled plateau at 128 m, gates west and south -------------

func _ruins(parent: Node3D, o: Vector2) -> void:
	var ring := [o + Vector2(-64, -50), o + Vector2(64, -50), o + Vector2(64, 60), o + Vector2(-64, 60)]
	# north, east, south (gate at x 0, 10 m), west (gate at z -10, 8 m) - with two breaches
	_broken_wall(parent, ring[0], ring[1], 2.0, 5.0, [[40, 52]], 1)
	_broken_wall(parent, ring[1], ring[2], 2.0, 5.0, [[70, 78]], 2)
	_broken_wall(parent, ring[2], ring[3], 2.0, 5.0, [[59, 69]], 3)
	_broken_wall(parent, ring[3], ring[0], 2.0, 5.0, [[65, 73]], 4)
	for corner in ring:
		_box(parent, corner, Vector3(4, 7, 4), "rock")
	_shell(parent, o + Vector2(22, -22), 36, 20, 5.0, 11.0, 3, 10)      # cathedral, door west
	_shell(parent, o + Vector2(-34, 20), 16, 10, 2.5, 4.5, 0, 20)      # archive
	_shell(parent, o + Vector2(40, 26), 14, 9, 2.5, 4.5, 3, 30)        # mint
	_shell(parent, o + Vector2(-40, -32), 12, 8, 2.0, 3.5, 2, 40)      # royal kennel
	_box(parent, o + Vector2(18, 44), Vector3(4, 1.6, 3), "timber", 15.0)   # marauders' tent
	for rubble in [Vector2(55, 50), Vector2(10, 5), Vector2(-15, -40)]:
		_box(parent, o + rubble, Vector3(5, 1.2, 4), "rock", 25.0)


# --- the band's glade in the Old Pine Grove (book sheet 01: common pot, lean-tos) -------------------

func _camp(parent: Node3D, o: Vector2) -> void:
	for k in 8:
		var a := TAU * k / 8.0
		_box(parent, o + Vector2(cos(a), sin(a)) * 1.1, Vector3(0.4, 0.3, 0.4), "rock", rad_to_deg(a), 0.0, false)
	_box(parent, o, Vector3(0.9, 0.15, 0.9), "dark", 0.0, 0.0, false)
	for side in [-1, 1]:
		var c := o + Vector2(side * 5.5, -3.0)
		_box(parent, c + Vector2(0, 1.2), Vector3(3.2, 1.9, 0.2), "timber")                 # back screen
		_box(parent, c, Vector3(3.4, 0.12, 2.4), "roof", 0.0, 1.6, false)                    # roof sheet
		_box(parent, o + Vector2(side * 2.6, 1.8), Vector3(2.2, 0.4, 0.4), "timber", 90.0 * side)  # log seat


# --- Wolf Hollow: boulders round the pack's lair ----------------------------------------------------

func _hollow(parent: Node3D, o: Vector2) -> void:
	var stones := [[Vector2(-7, -3), 3.0, 20.0], [Vector2(6, -5), 2.4, -35.0], [Vector2(2, 7), 3.6, 60.0],
		[Vector2(-4, 6), 1.8, 10.0], [Vector2(9, 4), 2.0, 75.0]]
	for s in stones:
		_box(parent, o + s[0], Vector3(s[1] * 1.3, s[1], s[1]), "rock", s[2])
	_box(parent, o + Vector2(0, -9), Vector3(4, 2.2, 3), "dark", 0.0)   # the lair under the bank


# --- Watch Rock: an outcrop with steps to a viewing ledge -------------------------------------------

func _lookout(parent: Node3D, o: Vector2) -> void:
	_box(parent, o + Vector2(0, -4), Vector3(9, 3.2, 7), "rock", 8.0)
	_box(parent, o + Vector2(2, -6), Vector3(5, 5.0, 4), "rock", -12.0)
	# rough steps up the near side to the ledge (0.32 m each)
	for k in 9:
		_box(parent, o + Vector2(-3.5, 3.0 - k * 0.45), Vector3(1.6, 0.32 * (k + 1), 0.5), "rock")
	_box(parent, o + Vector2(0, -4), Vector3(0.6, 1.2, 0.6), "rock", 0.0, 3.2)   # cairn on the ledge


# --- the salt works (sheet 22): boiling shed, evaporation pans, salt heaps --------------------------

func _saltworks(parent: Node3D, o: Vector2) -> void:
	_box(parent, o + Vector2(0, -10), Vector3(8, 3.0, 5), "clay")
	_box(parent, o + Vector2(0, -10), Vector3(8.8, 0.3, 5.8), "roof", 0.0, 3.0, false)
	_box(parent, o + Vector2(3, -12), Vector3(0.8, 4.5, 0.8), "rock")   # boiling-house chimney
	for i in 3:
		for j in 2:
			var c := o + Vector2(-8 + i * 8, 2 + j * 7)
			_box(parent, c, Vector3(6, 0.25, 5), "salt", 0.0, 0.0, false)
	for c in [Vector2(10, -6), Vector2(12, -2)]:
		_box(parent, o + c, Vector3(2.0, 1.2, 2.0), "salt", 45.0)


# --- a lone farmstead (peat farmstead, outskirts): house, shed, stacks --------------------------------

func _farmstead(parent: Node3D, o: Vector2) -> void:
	_box(parent, o + Vector2(0, -6), Vector3(8, 3.0, 6), "clay")
	for side in [-1, 1]:
		var slope := Vector3(8.6, 0.18, 3.7)
		_box(parent, o + Vector2(0, -6 + side * 1.55), slope, "roof", 0.0, 3.55, false, side * 28.0)
	_box(parent, o + Vector2(8, -4), Vector3(5, 2.4, 4), "timber")
	_box(parent, o + Vector2(8, -4), Vector3(5.6, 0.2, 4.6), "roof", 0.0, 2.4, false)
	for k in 3:
		_box(parent, o + Vector2(-8 + k * 2.2, 4), Vector3(1.6, 1.1, 1.0), "peat", 10.0 * k, 0.0, false)


# --- the W1 viewpoint (sheet wfW1): a 6 x 4 m stone platform by ledge 2, a low parapet towards the falls

func _viewpoint(parent: Node3D, o: Vector2) -> void:
	_box(parent, o, Vector3(6.0, 0.3, 4.0), "rock")
	_box(parent, o + Vector2(-2.85, 0), Vector3(0.3, 0.9, 4.0), "rock", 0.0, 0.3)
	for z in [-1.85, 1.85]:
		_box(parent, o + Vector2(-1.5, z), Vector3(2.7, 0.6, 0.3), "rock", 0.0, 0.3)


# --- the W1 stair flights (sheet wfW1, Codex ACK160): stone treads and landings from build.py's
# book_stairs, each a block from its tread down into the ground - a solid stair where it stands over
# lower ground, set into the cut where the slope is above it

func build_stairs(stairs: Array) -> void:
	for flight in stairs:
		var node := Node3D.new()
		node.name = str(flight.id)
		add_child(node)
		var all: Array = flight.steps
		for n in all.size():
			var st: Array = all[n]
			var at := Vector2(float(st[0]) - HALF, float(st[1]) - HALF)
			var top := float(st[2])
			var yaw := float(st[3])
			var depth := float(st[4])
			var width := float(st[5]) if st.size() > 5 else 2.0
			var rail := int(st[6]) if st.size() > 6 else 0
			var basis := Basis(Vector3.UP, deg_to_rad(yaw))
			var low := INF
			for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var p: Vector3 = basis * Vector3(k.x * width * 0.5, 0, k.y * depth * 0.5)
				low = minf(low, ground(at.x + p.x, at.y + p.z))
			if rail == 4:
				# a rope-bridge deck (the snow city's meltwater channel): planks on two stringers, rails
				# both sides, a pair of posts down to the ground every other plank row. Each piece is
				# tilted along the line through its neighbours, so the pieces meet without a ledge (Codex
				# be13087: 0.11 m between flat pieces stopped the hero on stairs B).
				var tilt := basis * Basis(Vector3.RIGHT, -atan(_deck_slope(all, n)))
				_tilted_block(node, Vector3(at.x, top - 0.08, at.y), Vector3(width, 0.16, depth + 0.04), tilt, "wood", true)
				for sx in [-1.0, 1.0]:
					var off: Vector3 = basis * Vector3(sx * (width * 0.5 - 0.05), 0, 0)
					_tilted_block(node, Vector3(at.x + off.x, top + 0.5, at.y + off.z), Vector3(0.08, 1.0, depth), tilt, "wood", true)
					var g: float = ground(at.x + off.x, at.y + off.z)
					if top - g > 0.4 and int(round(at.x * 3.0 + at.y * 7.0)) % 2 == 0:
						var post_h := top - 0.16 - (g - SINK)
						_stair_block(node, Vector3(at.x + off.x, g - SINK + post_h * 0.5, at.y + off.z), Vector3(0.18, post_h, 0.18), yaw, "wood", false)
				continue
			var height := maxf(top - (low - SINK), 0.3)
			var tread := depth < 0.6
			_stair_block(node, Vector3(at.x, top - height * 0.5, at.y), Vector3(width, height, depth), yaw, "masonry", not tread)
			# a dressed-stone tread over the masonry body: its nosing reads the steps from the side
			# 4/8 mm over the body's top and alternating, so no two faces share a plane (Codex a406d48:
			# stripes on the top treads of B and C, where a tread and its landing lie at one level)
			var lift := 0.004 * (1 + n % 2)
			_stair_block(node, Vector3(at.x, top - 0.06 + lift, at.y), Vector3(width + 0.06, 0.12, depth + 0.02), yaw, "tread", false)
			if tread:
				# Walking surface: a 32 deg slab from each tread's back edge at the step above to its front
				# edge on the tread itself - so a flight meets its landings flush at both ends (Codex
				# 95e5a47: through the treads' centres it stopped 0.165 m short of the terrace landing and
				# the real hero could not step onto it). The stone block collides only below the slab.
				var body_top := top - 0.1
				var body_h := maxf(body_top - (low - SINK), 0.1)
				_stair_collider(node, Vector3(at.x, body_top - body_h * 0.5, at.y), Vector3(width, body_h, depth), basis)
				# The slab rises from this tread's level at its low (+z) edge to the level of the record on
				# its high side - the next tread, or a landing at its own level (then flat: Codex be13087,
				# the last tread of a flight stood 0.18 m proud of the terrace).
				var rise := _slab_high(all, n) - top
				var pitch := atan2(rise, depth - 0.02)
				var slab := basis * Basis(Vector3.RIGHT, pitch)
				if rise > 0.02:
					_stair_collider(node, Vector3(at.x, top + rise * 0.5 - 0.03, at.y), Vector3(width, 0.06, (depth - 0.02) / cos(pitch) + 0.04), slab)
				else:
					# flat at its landing's level: it starts 3 cm in from its low edge and 2 mm down, under
					# the end of the slope coming up to it (that end overshoots 2 cm; the flat slab's edge
					# above it stopped the capsule with a 47 deg contact)
					var inward: Vector3 = basis * Vector3(0, 0, -0.015)
					_stair_collider(node, Vector3(at.x + inward.x, top - 0.032, at.y + inward.z), Vector3(width, 0.06, depth - 0.03), basis)
				# Below its low edge: a landing, a deck or the ground (no lower tread whose slab already
				# reaches this tread) - the slope carried down onto that plane (Codex be13087: the actual
				# hero stopped at the entries of snow stairs A/B/C).
				var below := _side(all, n, 1.0)
				var covered := below >= 0 and float(all[below][4]) < 0.6 and _rail(all[below]) != 4 and absf(_slab_high(all, below) - top) < 0.03
				var drop := STAIR_RISE if below < 0 else top - float(all[below][2])
				if not covered and drop > 0.02 and drop < 0.4:
					var entry := atan2(drop, STAIR_RUN_ENTRY)
					var edge: Vector3 = basis * Vector3(0, 0, depth * 0.5 + STAIR_RUN_ENTRY * 0.5)
					_stair_collider(node, Vector3(at.x + edge.x, top - drop * 0.5 - 0.03, at.y + edge.z), Vector3(width, 0.06, STAIR_RUN_ENTRY / cos(entry) + 0.04), basis * Basis(Vector3.RIGHT, entry))
			# rails: 1 m over the tread, solid
			var rails: Array = []
			if rail == -1 or rail == 3:
				rails.append([Vector3(-width * 0.5 + 0.05, 0, 0), Vector3(0.1, 1.0, depth)])
			if rail == 1 or rail == 3:
				rails.append([Vector3(width * 0.5 - 0.05, 0, 0), Vector3(0.1, 1.0, depth)])
			if rail == 2:
				rails.append([Vector3(0, 0, depth * 0.5 - 0.05), Vector3(width, 1.0, 0.1)])
			for r in rails:
				var off: Vector3 = basis * (r[0] as Vector3)
				_stair_block(node, Vector3(at.x + off.x, top + 0.5, at.y + off.z), r[1], yaw, "wood")
	print("BOOK_STAIRS flights=%d boxes=%d" % [stairs.size(), boxes])


const STAIR_RISE := 0.18
const STAIR_RUN_ENTRY := 0.3


## The record next to n (n - 1 or n + 1) on the given side of n's own z axis (+1: the low side of a
## tread), or -1.
func _side(all: Array, n: int, sign: float) -> int:
	var st: Array = all[n]
	var basis := Basis(Vector3.UP, deg_to_rad(float(st[3])))
	for k in [n - 1, n + 1]:
		if k < 0 or k >= all.size():
			continue
		var d := Vector3(float(all[k][0]) - float(st[0]), 0, float(all[k][1]) - float(st[1]))
		if (basis.inverse() * d).z * sign > 0.0:
			return k
	return -1


func _rail(st: Array) -> int:
	return int(st[6]) if st.size() > 6 else 0


## The level a tread's slab rises to at its high edge: the next record's, within one riser; else flat.
func _slab_high(all: Array, n: int) -> float:
	var top := float(all[n][2])
	var k := _side(all, n, -1.0)
	if k >= 0 and float(all[k][2]) > top + 0.02 and float(all[k][2]) < top + 0.3:
		return float(all[k][2])
	return top


## A deck piece's slope along its own z: through its neighbours' levels.
func _deck_slope(all: Array, n: int) -> float:
	var st: Array = all[n]
	var basis := Basis(Vector3.UP, deg_to_rad(float(st[3])))
	var pts: Array = []
	for k in [n - 1, n, n + 1]:
		if k < 0 or k >= all.size():
			continue
		var d := Vector3(float(all[k][0]) - float(st[0]), 0, float(all[k][1]) - float(st[1]))
		pts.append(Vector2((basis.inverse() * d).z, float(all[k][2])))
	if pts.size() < 2:
		return 0.0
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[pts.size() - 1]
	return 0.0 if absf(b.x - a.x) < 0.01 else clampf((b.y - a.y) / (b.x - a.x), -0.2, 0.2)


## A box turned by a full basis (a tilted deck plank row), solid or not.
func _tilted_block(parent: Node3D, centre: Vector3, size: Vector3, turn: Basis, colour: String, solid: bool) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(colour)
	mesh.transform = Transform3D(turn, centre)
	mesh.visibility_range_end = 300.0
	parent.add_child(mesh)
	boxes += 1
	if solid:
		_stair_collider(parent, centre, size, turn)

func _stair_collider(parent: Node3D, centre: Vector3, size: Vector3, basis: Basis) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	body.transform = Transform3D(basis, centre)
	parent.add_child(body)


func _stair_block(parent: Node3D, centre: Vector3, size: Vector3, yaw: float, colour: String, solid := true) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(colour)
	mesh.position = centre
	mesh.rotation.y = deg_to_rad(yaw)
	mesh.visibility_range_end = 300.0
	parent.add_child(mesh)
	boxes += 1
	if solid:
		_stair_collider(parent, centre, size, Basis(Vector3.UP, deg_to_rad(yaw)))
