extends RefCounted
## WORLD-BUILD-01C: the snow city's walls from the book's plan (lines of kind wall): the lower city's
## ring (1.8 m thick) and the Academy shelf's wall (2.0 m), their gaps the gates. Built in 2 m blocks of
## the stairs' masonry stepping with the ground - from below the lowest ground under a block to the
## wall's height over its highest - with merlons along the top. A block is left out where a street, a
## stair flight or a road passes (logged: the book's check had them meet only at the gates).
## The mine gate moved to the shelf's south-east wall (D-121, bridge 183/184): the east gap closes
## and a 6 m gate opens on the wall's line at 1082/306.8.

const PLAN := "res://assets/world/snow-city-v1/plan.json"
const HALF := 1000.0
const BLOCK := 2.0
## wall thickness (plan) -> height over the ground
const HEIGHT := {1.8: 4.5, 2.0: 3.5}
const MERLON := Vector3(0.9, 0.7, 0.0)   # width, height (thickness = the wall's)
const CLEAR := 0.6
const MINE_GATE := Vector2(1082, 306.8)
const MINE_GATE_WIDTH := 6.0
## The book's east gap of the shelf's wall, closed (its two ends).
const EAST_GAP := [Vector2(1088.8, 287.0), Vector2(1089.2, 293.0)]

var blocks := 0
var skipped: Array = []


func build(book: Node3D, ground: Callable, layout: Dictionary, streets: Array) -> void:
	if not FileAccess.file_exists(PLAN):
		return
	var plan = JSON.parse_string(FileAccess.get_file_as_string(PLAN))
	if not plan is Dictionary:
		return
	var node := Node3D.new()
	node.name = "SnowWalls"
	book.add_child(node)
	var keep := _keep_out(layout, streets)
	var lines: Array = []
	for line in plan.get("lines", []):
		if str(line.kind) != "wall":
			continue
		var pts := PackedVector2Array()
		for q in line.pts:
			pts.append(Vector2(float(q[0]), float(q[1])))
		lines.append([pts, float(line.width)])
	lines.append([PackedVector2Array(EAST_GAP), 2.0])
	for line in lines:
		var pts: PackedVector2Array = line[0]
		var width: float = line[1]
		var height: float = HEIGHT.get(width, 4.0)
		# along the line in BLOCK pieces
		var run := 0.0
		var lengths := PackedFloat32Array([0.0])
		for k in range(1, pts.size()):
			run += pts[k - 1].distance_to(pts[k])
			lengths.append(run)
		var n := maxi(1, int(round(run / BLOCK)))
		for i in n:
			var a := _along(pts, lengths, run * i / n)
			var b := _along(pts, lengths, run * (i + 1) / n)
			var mid := (a + b) * 0.5
			if width == 2.0 and mid.distance_to(MINE_GATE) < MINE_GATE_WIDTH * 0.5:
				continue
			var why := _blocked(mid, a.distance_to(b), width, keep)
			if why != "":
				skipped.append([mid, why])
				continue
			var lo := INF
			var hi := -INF
			for t in [0.0, 0.5, 1.0]:
				for side in [-0.5, 0.5]:
					var dir := (b - a).normalized()
					var e: Vector2 = a.lerp(b, t) + Vector2(-dir.y, dir.x) * width * side
					var h := float(ground.call(e.x - HALF, e.y - HALF))
					lo = minf(lo, h)
					hi = maxf(hi, h)
			var top := hi + height
			var bottom := lo - 0.5
			var yaw := rad_to_deg(atan2(b.x - a.x, b.y - a.y))
			var length := a.distance_to(b) + 0.05
			book._stair_block(node, Vector3(mid.x - HALF, (top + bottom) * 0.5, mid.y - HALF), Vector3(width, top - bottom, length), yaw, "masonry")
			blocks += 1
			# a merlon on every other block
			if i % 2 == 0:
				book._stair_block(node, Vector3(mid.x - HALF, top + MERLON.y * 0.5, mid.y - HALF), Vector3(width, MERLON.y, MERLON.x), yaw, "masonry")
	print("SNOW_WALLS blocks=%d skipped=%d %s" % [blocks, skipped.size(), str(skipped.map(func(s): return "%s:%s" % [s[0], s[1]]))])


func _along(pts: PackedVector2Array, lengths: PackedFloat32Array, t: float) -> Vector2:
	for k in range(1, pts.size()):
		if t <= lengths[k] or k == pts.size() - 1:
			var span := maxf(lengths[k] - lengths[k - 1], 0.001)
			return pts[k - 1].lerp(pts[k], clampf((t - lengths[k - 1]) / span, 0.0, 1.0))
	return pts[0]


## Streets (map frame), stair treads and roads near the walls, as [a, b, reach, kind].
func _keep_out(layout: Dictionary, streets: Array) -> Array:
	var out: Array = []
	for street in streets:
		var pts: PackedVector2Array = street[0]
		for k in range(pts.size() - 1):
			out.append([pts[k], pts[k + 1], float(street[1]) * 0.5, "street"])
	for flight in layout.get("book_stairs", []):
		if not str(flight.id).begins_with("snow"):
			continue
		for st in flight.steps:
			var p := Vector2(float(st[0]), float(st[1]))
			out.append([p, p, maxf(float(st[4]), float(st[5])) * 0.5, "stair"])
	for road in layout.get("roads", []):
		var wp: Array = road.world_points
		for k in range(wp.size() - 1):
			var a := Vector2(float(wp[k][0]) + HALF, float(wp[k][2]) + HALF)
			var b := Vector2(float(wp[k + 1][0]) + HALF, float(wp[k + 1][2]) + HALF)
			if a.x < 880 or a.x > 1120 or a.y < 240 or a.y > 420:
				continue
			out.append([a, b, float(road.get("width_m", 3.0)) * 0.5, str(road.id)])
	return out


func _blocked(mid: Vector2, length: float, width: float, keep: Array) -> String:
	for r in keep:
		var q := Geometry2D.get_closest_point_to_segment(mid, r[0], r[1])
		if mid.distance_to(q) < float(r[2]) + width * 0.5 + length * 0.5 + CLEAR:
			return str(r[3])
	return ""
