extends RefCounted
## WORLD-BUILD-01F (D-118, the book's lowland sheet): what the lowland city stands on over the water -
## the slum's boardwalks on stilts along the west bank, a platform on stilts for each of its shacks (at
## the boardwalk's level by its door; the builder floors the shack there through level_of), the river
## piers by the customs house with their ramps down from the port street, and the stone sea mole with
## its quay 1.5 m over the sea. Built of the stairs' wood and masonry; walkable, the posts down to the
## bed.

const PLAN := "res://assets/world/lowland-city-v1/plan.json"
const HALF := 1000.0
## A boardwalk lies at least this far over its ground and over the river's water next to it.
const DECK_OVER_GROUND := 0.7
const DECK_OVER_WATER := 1.0
const DECK_STEP := 2.0
const DECK_THICK := 0.16
const POST := 0.16
## A river pier over the water; the sea mole's quay over the sea (the book: +1.5 m).
const PIER_OVER_WATER := 0.8
const MOLE_TOP := 1.5
const SEA := 0.0

## Each shack on stilts: code -> its platform's top (its floor).
var stilt_levels := {}
## Each boardwalk as walked: [points (world frame) every DECK_STEP, their tops].
var boardwalks: Array = []
var _rivers: Array = []


func build(book: Node3D, ground: Callable, layout: Dictionary) -> void:
	if not FileAccess.file_exists(PLAN):
		return
	var plan = JSON.parse_string(FileAccess.get_file_as_string(PLAN))
	if not plan is Dictionary:
		return
	for r in layout.get("rivers", []):
		for p in r.world_points:
			_rivers.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	var node := Node3D.new()
	node.name = "LowlandWater"
	book.add_child(node)
	# the boardwalks
	for line in plan.get("lines", []):
		if str(line.kind) != "deck":
			continue
		var pts := PackedVector2Array()
		for q in line.pts:
			pts.append(Vector2(float(q[0]) - HALF, float(q[1]) - HALF))
		_boardwalk(book, node, ground, pts, float(line.width))
	# the shacks on stilts, each at the boardwalk's level nearest its door
	for b in plan.get("buildings", []):
		var kind := str(b.kind)
		var c := Vector2(float(b.x) - HALF, float(b.z) - HALF)
		var yaw := deg_to_rad(float(b.yaw))
		var f := Vector2(-sin(yaw), cos(yaw))
		if kind == "shack":
			var door: Vector2 = c + f * (float(b.d) * 0.5)
			var level := _deck_level_at(door, ground)
			stilt_levels[str(b.code)] = level
			_platform(book, node, ground, c, yaw, float(b.w) + 0.4, float(b.d) + 0.6, level, "wood")
		elif kind == "pier":
			var over := MOLE_TOP if str(b.code) == "Мл" else _water(c) + PIER_OVER_WATER
			_platform(book, node, ground, c, yaw, float(b.w), float(b.d), over, "masonry" if str(b.code) == "Мл" else "wood")
	# the ramps from the port street down to the piers and the mole
	for line in plan.get("lines", []):
		if str(line.kind) != "ramp":
			continue
		var a := Vector2(float(line.pts[0][0]) - HALF, float(line.pts[0][1]) - HALF)
		var z := Vector2(float(line.pts[1][0]) - HALF, float(line.pts[1][1]) - HALF)
		var ha := float(ground.call(a.x, a.y))
		var hz := maxf(_pier_top_near(z, plan), float(ground.call(z.x, z.y)))
		_plank_run(book, node, ground, PackedVector2Array([a, z]), PackedFloat32Array([ha, hz]), float(line.width))
	print("LOWLAND_WATER boardwalks=%d stilts=%d" % [boardwalks.size(), stilt_levels.size()])


## The river's water level nearest a point (world frame), or the sea.
func _water(p: Vector2) -> float:
	var best := INF
	var level := SEA
	for r: Vector3 in _rivers:
		var d := Vector2(r.x, r.z).distance_squared_to(p)
		if d < best:
			best = d
			level = r.y
	return level if best < 60.0 * 60.0 else SEA


func _deck_level_at(p: Vector2, ground: Callable) -> float:
	var best := INF
	var level := maxf(float(ground.call(p.x, p.y)) + DECK_OVER_GROUND, _water(p) + DECK_OVER_WATER)
	for bw in boardwalks:
		var pts: PackedVector2Array = bw[0]
		var tops: PackedFloat32Array = bw[1]
		for i in pts.size():
			var d := pts[i].distance_squared_to(p)
			if d < best:
				best = d
				level = tops[i]
	return level


func _pier_top_near(p: Vector2, plan: Dictionary) -> float:
	var best := INF
	var top := 0.0
	for b in plan.get("buildings", []):
		if str(b.kind) != "pier":
			continue
		var c := Vector2(float(b.x) - HALF, float(b.z) - HALF)
		var d := c.distance_to(p)
		if d < best:
			best = d
			top = MOLE_TOP if str(b.code) == "Мл" else _water(c) + PIER_OVER_WATER
	return top


## A boardwalk along pts: its top every DECK_STEP over its ground and the water, eased +-2 samples.
func _boardwalk(book: Node3D, node: Node3D, ground: Callable, pts: PackedVector2Array, width: float) -> void:
	var line := PackedVector2Array()
	for k in range(pts.size() - 1):
		var n := maxi(1, int(ceil(pts[k].distance_to(pts[k + 1]) / DECK_STEP)))
		for i in n:
			line.append(pts[k].lerp(pts[k + 1], float(i) / n))
	line.append(pts[pts.size() - 1])
	var raw := PackedFloat32Array()
	for p in line:
		raw.append(maxf(float(ground.call(p.x, p.y)) + DECK_OVER_GROUND, _water(p) + DECK_OVER_WATER))
	var tops := PackedFloat32Array()
	for i in raw.size():
		var sum := 0.0
		var count := 0
		for j in range(maxi(0, i - 2), mini(raw.size(), i + 3)):
			sum += raw[j]
			count += 1
		tops.append(maxf(sum / count, raw[i] - 0.3))
	boardwalks.append([line, tops])
	_plank_run(book, node, ground, line, tops, width)


## Planks along a polyline at the given tops, each piece tilted between its two ends, with a pair of
## posts down to the ground at every point.
func _plank_run(book: Node3D, node: Node3D, ground: Callable, line: PackedVector2Array, tops: PackedFloat32Array, width: float) -> void:
	for i in range(line.size() - 1):
		var a: Vector2 = line[i]
		var b: Vector2 = line[i + 1]
		var length := a.distance_to(b)
		if length < 0.05:
			continue
		var dir := (b - a) / length
		var yaw := atan2(dir.x, dir.y)
		var pitch := atan2(tops[i] - tops[i + 1], length)
		var mid: Vector2 = (a + b) * 0.5
		var turn := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		book._tilted_block(node, Vector3(mid.x, (tops[i] + tops[i + 1]) * 0.5 - DECK_THICK * 0.5, mid.y), Vector3(width, DECK_THICK, length / cos(pitch) + 0.06), turn, "wood", true)
	for i in line.size():
		var p: Vector2 = line[i]
		var dir := (line[mini(i + 1, line.size() - 1)] - line[maxi(i - 1, 0)]).normalized()
		var across := Vector2(-dir.y, dir.x)
		for sx in [-1.0, 1.0]:
			var q: Vector2 = p + across * (sx * (width * 0.5 - 0.1))
			_post(book, node, ground, q, tops[i] - DECK_THICK)


## A platform on stilts: a deck w x d at `top`, posts at its corners and mid-sides down to the ground.
func _platform(book: Node3D, node: Node3D, ground: Callable, c: Vector2, yaw: float, w: float, d: float, top: float, colour: String) -> void:
	var f := Vector2(-sin(yaw), cos(yaw))
	var s := Vector2(f.y, -f.x)
	var thick := 0.5 if colour == "masonry" else DECK_THICK
	var low := top - thick
	if colour == "masonry":
		# the mole: a solid stone body down to the sea bed
		var bed := INF
		for u in [-0.5, 0.0, 0.5]:
			for v in [-0.5, 0.0, 0.5]:
				var q: Vector2 = c + s * (w * u) + f * (d * v)
				bed = minf(bed, float(ground.call(q.x, q.y)))
		low = minf(bed, SEA) - 1.0
	book._stair_block(node, Vector3(c.x, (top + low) * 0.5, c.y), Vector3(w, top - low, d), rad_to_deg(-yaw), colour)
	if colour == "masonry":
		book._stair_block(node, Vector3(c.x, top + 0.04, c.y), Vector3(w + 0.1, 0.12, d + 0.1), rad_to_deg(-yaw), "tread", false)
		return
	for u in [-0.5, 0.0, 0.5]:
		for v in [-0.5, 0.5]:
			_post(book, node, ground, c + s * (w * u * 0.95) + f * (d * v * 0.95), low)


## A post from `top` down into the ground under it.
func _post(book: Node3D, node: Node3D, ground: Callable, q: Vector2, top: float) -> void:
	var g := float(ground.call(q.x, q.y))
	if top - g < 0.15:
		return
	var bottom := g - 0.5
	book._stair_block(node, Vector3(q.x, (top + bottom) * 0.5, q.y), Vector3(POST, top - bottom, POST), 0.0, "wood", false)
