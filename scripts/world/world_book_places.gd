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
	print("BOOK_PLACES places=%d boxes=%d models=%d" % [places.size(), boxes, models])


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
		var r := fposmod(sin(float(seed * 31 + i * 7)) * 43758.5453, 1.0)
		var h := lerpf(low, high, r)
		# BOOK-DRESS-03: dressed stone, a ragged top course, fallen stones at the foot
		var p0 := a.lerp(b, t0 / length)
		var p1 := a.lerp(b, t1 / length)
		_wall(parent, p0, p1, 1.2, h, "masonry")
		var f := 0.25 + 0.5 * fposmod(r * 7.31, 1.0)
		_wall(parent, p0.lerp(p1, f * 0.4), p0.lerp(p1, f * 0.4 + 0.45), 1.0, h + 0.4 + 0.6 * r, "masonry")
		var side := Vector2(-(b - a).y, (b - a).x).normalized() * (1.2 + r)
		_model(parent, "boulder", (p0 + p1) * 0.5 + side * (1.0 if i % 2 == 0 else -1.0), r * 300.0, 0.35 + 0.4 * r, -0.1)


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
		_box(parent, corner, Vector3(4, 7, 4), "masonry")
	_shell(parent, o + Vector2(22, -22), 36, 20, 5.0, 11.0, 3, 10)      # cathedral, door west
	_shell(parent, o + Vector2(-34, 20), 16, 10, 2.5, 4.5, 0, 20)      # archive
	_shell(parent, o + Vector2(40, 26), 14, 9, 2.5, 4.5, 3, 30)        # mint
	_shell(parent, o + Vector2(-40, -32), 12, 8, 2.0, 3.5, 2, 40)      # royal kennel
	_box(parent, o + Vector2(18, 44), Vector3(4, 1.6, 3), "timber", 15.0)   # marauders' tent
	for rubble: Vector2 in [Vector2(55, 50), Vector2(10, 5), Vector2(-15, -40)]:
		# a heap of fallen masonry (BOOK-DRESS-03): boulders of the kit, solid
		for k in 5:
			var off := Vector2(cos(k * 1.3), sin(k * 1.7)) * (0.6 + 0.4 * k)
			_model(parent, "bigboulder", o + rubble + off, k * 70.0, 0.55 - 0.06 * k, -0.15, 0.0, 1.0, true)


# --- BOOK-DRESS-01: the three places by the start (camp, Wolf Hollow, Watch Rock) dressed from the
# project's own kit (village forest, forest floor and edge rocks - Poly Haven CC0 - the tavern props,
# the caves' rock mouth) instead of grey boxes. The other places keep their volumes until their sheets.
const KIT := {
	"boulder": "res://assets/environment/village-forest-v1/boulder.glb",
	"stump": "res://assets/environment/village-forest-v1/stump.glb",
	"trunk": "res://assets/environment/forest-floor-v1/dead_tree_trunk.glb",
	"branches": "res://assets/environment/forest-floor-v1/dry_branches_medium_01.glb",
	"roots": "res://assets/environment/forest-floor-v1/pine_roots.glb",
	"mossrock": "res://assets/environment/forest-floor-v1/rock_moss_set_02.glb",
	"cliff": "res://assets/environment/edge-rocks-v1/namaqualand_cliff_01.glb",
	"bigboulder": "res://assets/environment/world-props-v1/namaqualand_boulder_03.glb",
	"bucket": "res://assets/props/tavern-v1/wooden_bucket_01.glb",
	"barrel": "res://assets/props/tavern-v1/wine_barrel_01.glb",
	"axe": "res://assets/props/civic-v1/wooden_axe_03.glb",
	"mouth": "res://assets/caves-v1/cave_mouth.glb",
	"woodpile": "res://assets/buildings/ashbound/courtyard_woodpile.glb",
}
var models := 0
var _scenes := {}


## A kit model at `c` (world frame), on the ground there + `lift`, turned `yaw` degrees, `size` a
## number or a Vector3; `solid` > 0: a cylinder of that radius and `height` round it; `trimesh`: its
## own surfaces become colliders (rocks the hero climbs or walks round).
func _model(parent: Node3D, kind: String, c: Vector2, yaw: float, size: Variant, lift := 0.0, solid := 0.0, height := 1.0, trimesh := false, pitch := 0.0, roll := 0.0) -> Node3D:
	if not _scenes.has(kind):
		_scenes[kind] = load(KIT[kind])
	var node: Node3D = _scenes[kind].instantiate()
	var g := ground(c.x, c.y)
	node.position = Vector3(c.x, g + lift, c.y)
	node.rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), deg_to_rad(roll))
	node.scale = size if size is Vector3 else Vector3.ONE * float(size)
	parent.add_child(node)
	models += 1
	if trimesh:
		for m in node.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).create_trimesh_collision()
	elif solid > 0.0:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = solid
		cyl.height = height
		shape.shape = cyl
		body.add_child(shape)
		body.position = Vector3(c.x, g + height * 0.5, c.y)
		parent.add_child(body)
	return node


## A pole (timber, textured) from a to b (world frame, heights absolute), `r` thick.
func _pole(parent: Node3D, a: Vector3, b: Vector3, r: float) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(r, a.distance_to(b), r)
	mesh.mesh = box
	mesh.material_override = _material("wood")
	mesh.position = (a + b) * 0.5
	mesh.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	parent.add_child(mesh)
	models += 1


# --- the band's glade in the Old Pine Grove (book sheet 01: common pot, lean-tos) -------------------

func _camp(parent: Node3D, o: Vector2) -> void:
	# the fire: a ring of stones, ash, a tripod over it with the common pot
	for k in 9:
		var a := TAU * k / 9.0
		_model(parent, "boulder", o + Vector2(cos(a), sin(a)) * 1.05, rad_to_deg(a) * 1.7, 0.26 + 0.05 * (k % 3), -0.08)
	_box(parent, o, Vector3(1.4, 0.06, 1.4), "dark", 0.0, 0.0, false)
	var top := Vector3(o.x, ground(o.x, o.y) + 1.9, o.y)
	for k in 3:
		var a := TAU * k / 3.0 + 0.5
		var foot := o + Vector2(cos(a), sin(a)) * 1.25
		_pole(parent, Vector3(foot.x, ground(foot.x, foot.y) - 0.1, foot.y), top + Vector3(0, 0.15, 0), 0.07)
	_model(parent, "bucket", o, 0.0, 1.6, 0.75)
	# two lean-tos: forked posts, a ridge pole, a sloping roof of branches over a back screen
	for side in [-1.0, 1.0]:
		var c := o + Vector2(side * 5.5, -3.0)
		var g := ground(c.x, c.y)
		for dx in [-1.5, 1.5]:
			_pole(parent, Vector3(c.x + dx, g - 0.2, c.y + 0.9), Vector3(c.x + dx, g + 1.75, c.y + 0.9), 0.12)
		_pole(parent, Vector3(c.x - 1.8, g + 1.72, c.y + 0.9), Vector3(c.x + 1.8, g + 1.72, c.y + 0.9), 0.1)
		_box(parent, c + Vector2(0, -0.1), Vector3(3.4, 0.08, 2.3), "roof", 0.0, 1.25, false, -34.0)
		for k in 4:
			_model(parent, "branches", c + Vector2(-1.2 + k * 0.8, -0.1), 90.0 + k * 7.0, 1.5, 1.3 + 0.02 * k, 0.0, 1.0, false, -34.0)
		_box(parent, c + Vector2(0, -0.95), Vector3(3.2, 0.9, 0.15), "wood", 0.0, 0.0, true)
		# a log to sit on facing the fire, a stump with the axe in it by one shelter
		_model(parent, "trunk", o + Vector2(side * 2.7, 1.9), 90.0 + side * 12.0, Vector3(0.8, 1.7, 1.7), 0.05, 0.0)
	var stump := o + Vector2(-3.2, -6.4)
	_model(parent, "stump", stump, 30.0, 1.0, -0.05, 0.35, 0.6)
	_model(parent, "axe", stump + Vector2(0.05, 0), 20.0, 1.2, 0.85, 0.0, 1.0, false, 0.0, 25.0)
	_model(parent, "barrel", o + Vector2(7.6, -4.4), 0.0, 1.0, 0.0, 0.42, 0.9)
	_model(parent, "roots", o + Vector2(-8.0, 2.5), 40.0, 1.3, -0.02)


# --- Wolf Hollow: boulders round the pack's lair under the bank -------------------------------------

func _hollow(parent: Node3D, o: Vector2) -> void:
	var stones := [[Vector2(-7, -3), 3.0, 20.0], [Vector2(6, -5), 2.4, -35.0], [Vector2(2, 7), 3.6, 60.0],
		[Vector2(-4, 6), 1.8, 10.0], [Vector2(9, 4), 2.0, 75.0]]
	for s in stones:
		var k: float = s[1] / 1.5
		_model(parent, "bigboulder", o + s[0], s[2], k, -0.25 * k, 0.0, 1.0, true)
	for c in [Vector2(-9, 1), Vector2(4, -10), Vector2(11, -2)]:
		_model(parent, "mossrock", o + c, c.x * 13.0, 1.3, 0.0, 0.0, 1.0, true)
	# the lair: the caves' rock mouth, small - a low dark den under the bank (too low for the hero)
	var lair := _model(parent, "mouth", o + Vector2(0, -9), 0.0, 0.34, -0.5)
	# its rock, triplanar and darkening inward, as the mouths'; its collider comes with the import
	var cm := preload("res://scripts/world/world_cave_mouths.gd")
	var mouths: Node3D = cm.new()
	mouths._dress(lair, mouths._surface(cm.ROCK, 4.0), mouths._surface(cm.EARTH, 3.0), mouths._surface(cm.TIMBER, 0.8, "col"))
	mouths.free()
	for c in [Vector2(-2, -6), Vector2(3, -6.5), Vector2(-5, -1), Vector2(1, 3)]:
		_model(parent, "branches", o + c, c.x * 31.0, 1.4, 0.0)
	_model(parent, "roots", o + Vector2(-2.5, -7.0), 160.0, 1.4, -0.05)
	_model(parent, "trunk", o + Vector2(-1, 11), 70.0, Vector3(1.2, 2.0, 2.0), 0.08, 0.0)


# --- Watch Rock: an outcrop with stone steps to a viewing ledge and a cairn -------------------------

func _lookout(parent: Node3D, o: Vector2) -> void:
	_model(parent, "cliff", o + Vector2(0.5, -5.0), 8.0, 1.15, -0.4, 0.0, 1.0, true)
	_model(parent, "bigboulder", o + Vector2(4.5, -1.5), -40.0, 1.3, -0.3, 0.0, 1.0, true)
	_model(parent, "bigboulder", o + Vector2(-5.5, -6.0), 75.0, 1.6, -0.4, 0.0, 1.0, true)
	# the ledge: a flat stone shelf on the outcrop's front shoulder at 3.2 m, reached by rough steps
	_box(parent, o + Vector2(-1.5, -1.2), Vector3(3.6, 0.35, 2.6), "tread", 8.0, 3.2 - 0.35)
	for k in 9:
		_box(parent, o + Vector2(-3.5, 3.0 - k * 0.45), Vector3(1.6, 0.32 * (k + 1), 0.5), "tread")
	for k in 3:
		_model(parent, "boulder", o + Vector2(-1.2, -1.4), k * 70.0, 0.42 - 0.1 * k, 3.2 + 0.3 * k)


# --- the salt works (sheet 22): boiling shed, evaporation pans, salt heaps --------------------------

func _saltworks(parent: Node3D, o: Vector2) -> void:
	# BOOK-DRESS-03: the boiling house (the village's closed workshop) and its chimney, the evaporation pans
	# as stone-rimmed basins of white salt, the salt heaps as cones
	_building(parent, "res://assets/buildings/forest-village-v1/w01_closed.glb", o + Vector2(0, -10), 180.0, Vector2(7, 9))
	_box(parent, o + Vector2(3, -14.2), Vector3(0.9, 6.0, 0.9), "masonry")
	for i in 3:
		for j in 2:
			var c := o + Vector2(-8 + i * 8, 4 + j * 7)
			for side: Vector3 in [Vector3(0, 0, -2.5), Vector3(0, 0, 2.5), Vector3(-3, 0, 0), Vector3(3, 0, 0)]:
				var along := absf(side.z) > 0.0
				_box(parent, c + Vector2(side.x, side.z), Vector3(6.3 if along else 0.3, 0.35, 0.3 if along else 5.3), "masonry", 0.0, 0.0, false)
			_box(parent, c, Vector3(5.7, 0.2, 4.7), "salt", 0.0, 0.12, false)
	for c: Vector2 in [Vector2(10, -6), Vector2(12.5, -2.5), Vector2(9.5, -1.0)]:
		var at := o + c
		var cone := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.05
		mesh.bottom_radius = 1.3
		mesh.height = 1.4
		mesh.radial_segments = 14
		cone.mesh = mesh
		cone.material_override = _material("salt")
		cone.position = Vector3(at.x, ground(at.x, at.y) + 0.65, at.y)
		# under its own node: the place's direct meshes are its volumes (the book places validator)
		var holder := Node3D.new()
		holder.name = "SaltHeap"
		parent.add_child(holder)
		holder.add_child(cone)
		models += 1


# --- a lone farmstead (peat farmstead, outskirts): the village's own closed house and barn (BOOK-DRESS-02,
# instead of grey boxes), a woodpile, the peat stacks; each building on the highest ground under it (its
# masonry footing reaches 2.6 m down the slope) and solid to its walls

func _building(parent: Node3D, path: String, c: Vector2, yaw: float, footprint: Vector2) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw))
	var top := -INF
	for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2.ZERO]:
		var p: Vector3 = basis * Vector3(k.x * footprint.x * 0.5, 0, k.y * footprint.y * 0.5)
		top = maxf(top, ground(c.x + p.x, c.y + p.z))
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var node: Node3D = _scenes[path].instantiate()
	node.position = Vector3(c.x, top, c.y)
	node.rotation.y = deg_to_rad(yaw)
	parent.add_child(node)
	models += 1
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(footprint.x, 5.0, footprint.y)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(c.x, top + 2.5, c.y)
	body.rotation.y = deg_to_rad(yaw)
	parent.add_child(body)


func _farmstead(parent: Node3D, o: Vector2) -> void:
	_building(parent, "res://assets/buildings/forest-village-v1/h01_closed.glb", o + Vector2(0, -6), 0.0, Vector2(6, 8))
	_building(parent, "res://assets/buildings/forest-village-v1/b01_closed.glb", o + Vector2(11, -4), -90.0, Vector2(8, 10))
	_model(parent, "woodpile", o + Vector2(-4.8, -1.5), 0.0, 1.0, 0.0, 0.6, 1.0)
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
				# a dressed cheek along each open side, on the slope of the flight (owner 14 Oct: the
				# treads' blocks showed as a sawtooth along the flights' sides): it covers the steps'
				# profile down into the bank of earth the flight stands in (world_snow_lots FILL_TOP)
				for sx in [-1.0, 1.0]:
					var side: Vector3 = basis * Vector3(sx * (width * 0.5 - 0.06), 0, 0)
					var beyond: Vector3 = basis * Vector3(sx * (width * 0.5 + 0.4), 0, 0)
					if ground(at.x + beyond.x, at.y + beyond.z) > top - 0.15:
						continue
					_tilted_block(node, Vector3(at.x + side.x, top + rise * 0.5 + CHEEK.y * 0.5 - CHEEK.z, at.y + side.z), Vector3(CHEEK.x, CHEEK.y, (depth - 0.02) / cos(pitch) + 0.06), slab, "tread", false)
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
			# rails: 1 m over the tread, solid - only where it stands 0.5 m or more over the ground (a
			# flight's first landing at ground level had rails across the street running past it)
			var rails: Array = []
			if top - low < RAIL_DROP:
				rail = 0
			if rail == -1 or rail == 3:
				rails.append([Vector3(-width * 0.5 + 0.05, 0, 0), Vector3(0.1, 1.0, depth)])
			if rail == 1 or rail == 3:
				rails.append([Vector3(width * 0.5 - 0.05, 0, 0), Vector3(0.1, 1.0, depth)])
			if rail == 2:
				rails.append([Vector3(0, 0, depth * 0.5 - 0.05), Vector3(width, 1.0, 0.1)])
			for r in rails:
				var off: Vector3 = basis * (r[0] as Vector3)
				if not tread:
					_stair_block(node, Vector3(at.x + off.x, top + 0.5, at.y + off.z), r[1], yaw, "wood")
					continue
				# on a flight (Codex 106ecf5: a stepped run of blocks read as blockout): the guard keeps
				# its collision, unseen; seen are a handrail on the slope, joining the next tread's, and
				# a post on every third tread
				_stair_collider(node, Vector3(at.x + off.x, top + 0.5, at.y + off.z), r[1], basis)
				var rise := _slab_high(all, n) - top
				var tilt := basis * Basis(Vector3.RIGHT, atan2(rise, depth - 0.02))
				var rail_size: Vector3 = r[1]
				var along_x: bool = rail_size.x > rail_size.z
				_tilted_block(node, Vector3(at.x + off.x, top + rise * 0.5 + 0.95, at.y + off.z), Vector3(rail_size.x, 0.08, 0.08) if along_x else Vector3(0.08, 0.08, depth / cos(atan2(rise, depth - 0.02)) + 0.02), tilt, "wood", false)
				if n % 3 == 0:
					_stair_block(node, Vector3(at.x + off.x, top + 0.48, at.y + off.z), Vector3(0.08, 0.96, 0.08), yaw, "wood", false)
	print("BOOK_STAIRS flights=%d boxes=%d" % [stairs.size(), boxes])


const STAIR_RISE := 0.18
## A flight's cheek: width, height, depth under the walking line.
const CHEEK := Vector3(0.18, 0.5, 0.36)
const RAIL_DROP := 0.5
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
