extends RefCounted
## WORLD-BUILD-01C (Codex's survey of the 41 snow plots: the 5 m ground grid could not hold a 6 m house
## level next to a neighbour 2-3 m away on another level - the ground rose 0.1-0.9 m over floors and
## fell up to 4.4 m under them). Under the snow city's plots the terrain is drawn in the shore's finer
## 1.25 m cells (world_graybox_geometry.refine_cell), on this ground:
## - level under every building's walls + FLAT (a 1.25 m triangle touching a wall has all three corners
##   inside) and its door's yard APRON deep; the slum's shacks face a sloping lane - a 1 m step only;
## - BLEND m of smoothstep back to the ground round that;
## - where two plots overlap, the lower level (the ground never covers a floor); the upper house then
##   stands on a stone plinth (the plan's `plinth`), built by build_plinths;
## - roads and stair flights keep their ground, the plot fading out over KEEP m from them.
## The plots are the book's (not moved). World frame = map - 1000, as world.world_ground.

const PLAN := "res://assets/world/snow-city-v1/plan.json"
const HALF := 1000.0
const GRID := 5.0
const FINE := 1.25
const FLAT := 2.0
const APRON := 3.0
const SHACK_FRONT := 1.0
const BLEND := 3.0
const KEEP := 2.0
const BUCKET := 20.0
## Plinth: under a house the ground falls more than this below its floor -> a stone plinth.
const PLINTH_HANG := 0.12
const PLINTH_LEDGE := 0.25
## The ground under a building's walls lies this far under its floor (no shared plane).
const FLOOR_GAP := 0.05
## The library's lower hall (S-L: its floor 3.2 m under the entrance) needs the ground dug out: no
## terrain under the cells the walls touch; a paved collar at the floor's level fills the rest of those
## cells and holds the cut as a retaining wall CUT m deep.
const CUTS := {"Бб": 3.5}
## Behind the cut: a sunken yard at the lower hall's floor (LOWER m down) from the lower door in the
## back wall to the rock - the library's lab door (S-L LabPortal) opens into it, not into the collar.
## [width, length] in metres.
const AREAWAYS := {"Бб": [3.0, 3.5]}
const LOWER := {"Бб": 3.2}
## A door whose front falls away gets stone steps of STOOP_RISE down to the ground (at most STOOP_MAX).
const STOOP_RISE := 0.18
const STOOP_MAX := 16
const STOOP_RUN := 0.35
const STOOP_WIDTH := 1.6

var lots: Array[Dictionary] = []
var refined := {}
var _buckets := {}
var _keep := {}
var holes := {}
var _collars: Array = []
var _treads: Array = []
var _cache := {}


func setup(layout: Dictionary) -> void:
	var levels := {}
	for lot in layout.get("snow_lots", []):
		levels[str(lot.code)] = float(lot.level)
	if levels.is_empty() or not FileAccess.file_exists(PLAN):
		return
	var plan = JSON.parse_string(FileAccess.get_file_as_string(PLAN))
	if not plan is Dictionary:
		return
	for b in plan.get("buildings", []):
		var code := str(b.code)
		if not levels.has(code):
			continue
		var yaw := deg_to_rad(float(b.yaw))
		var f := Vector2(-sin(yaw), cos(yaw))
		var lot := {
			"code": code, "c": Vector2(float(b.x) - HALF, float(b.z) - HALF), "f": f, "s": Vector2(f.y, -f.x),
			"w": float(b.w), "d": float(b.d), "level": levels[code], "shack": str(b.kind) == "shack",
		}
		lots.append(lot)
	var area := Rect2()
	for i in lots.size():
		var lot := lots[i]
		var reach: float = Vector2(lot.w * 0.5 + FLAT, lot.d * 0.5 + FLAT + APRON).length() + BLEND
		var c: Vector2 = lot.c
		for bx in range(floori((c.x - reach) / BUCKET), floori((c.x + reach) / BUCKET) + 1):
			for bz in range(floori((c.y - reach) / BUCKET), floori((c.y + reach) / BUCKET) + 1):
				var key := Vector2i(bx, bz)
				if not _buckets.has(key):
					_buckets[key] = []
				_buckets[key].append(i)
		var box := Rect2(c - Vector2.ONE * reach, Vector2.ONE * reach * 2.0)
		area = box if i == 0 else area.merge(box)
		# the cells to refine: any part within the blend (a cell's centre is <= 3.54 m from its corners)
		for cx in range(floori((c.x - reach + HALF) / GRID), floori((c.x + reach + HALF) / GRID) + 1):
			for cz in range(floori((c.y - reach + HALF) / GRID), floori((c.y + reach + HALF) / GRID) + 1):
				var centre := Vector2((cx + 0.5) * GRID - HALF, (cz + 0.5) * GRID - HALF)
				if _dist(lot, centre) < BLEND + GRID * 0.72:
					refined[Vector2i(cx, cz)] = true
	area = area.grow(BLEND + KEEP + 10.0)
	for lot in lots:
		if not CUTS.has(lot.code):
			continue
		# the cut is drawn in whole 5 m cells; the plan turns this one 0 deg (an axis-aligned collar)
		var walls := Rect2(lot.c - Vector2(lot.w, lot.d) * 0.5, Vector2(lot.w, lot.d))
		if absf(lot.f.x) > 0.001:
			walls = Rect2(lot.c - Vector2.ONE * maxf(lot.w, lot.d) * 0.5, Vector2.ONE * maxf(lot.w, lot.d))
			push_warning("SNOW_LOTS %s is turned; its cut is squared" % lot.code)
		var voids: Array[Rect2] = [walls]
		if AREAWAYS.has(lot.code):
			var aw: Array = AREAWAYS[lot.code]
			voids.append(Rect2(lot.c.x - float(aw[0]) * 0.5, walls.position.y - float(aw[1]), float(aw[0]), float(aw[1])))
		var span: Rect2 = voids[0]
		for v in voids:
			span = span.merge(v)
		var c0 := Vector2i(floori((span.position.x + HALF) / GRID), floori((span.position.y + HALF) / GRID))
		var c1 := Vector2i(floori((span.end.x + HALF - 0.01) / GRID), floori((span.end.y + HALF - 0.01) / GRID))
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				holes[Vector2i(cx, cz)] = true
		var hole := Rect2(Vector2(c0.x * GRID - HALF, c0.y * GRID - HALF), Vector2((c1.x - c0.x + 1) * GRID, (c1.y - c0.y + 1) * GRID))
		_collars.append([lot, hole, voids])
	for road in layout.get("roads", []):
		var pts: Array = road.world_points
		var half := float(road.get("width_m", 3.0)) * 0.5
		for k in range(pts.size() - 1):
			var a := Vector2(float(pts[k][0]), float(pts[k][2]))
			var b := Vector2(float(pts[k + 1][0]), float(pts[k + 1][2]))
			if area.intersects(Rect2(a, Vector2.ZERO).expand(b).grow(half)):
				_add_keep(Rect2(a, Vector2.ZERO).expand(b).grow(half + 0.5 + KEEP), [a, b, half + 0.5])
	for flight in layout.get("book_stairs", []):
		if not str(flight.id).begins_with("snow"):
			continue
		for st in flight.steps:
			var reach := maxf(float(st[4]), float(st[5])) * 0.5 + 0.5
			var at := Vector2(float(st[0]) - HALF, float(st[1]) - HALF)
			_add_keep(Rect2(at, Vector2.ZERO).grow(reach + KEEP), [at, at, reach])
			_treads.append([at, reach, float(st[2])])
	print("SNOW_LOTS lots=%d refined_cells=%d keep_buckets=%d" % [lots.size(), refined.size(), _keep.size()])


## Roads and stair treads near the plots, as segments [a, b, half width], by the lots' buckets.
func _add_keep(box: Rect2, segment: Array) -> void:
	for bx in range(floori(box.position.x / BUCKET), floori(box.end.x / BUCKET) + 1):
		for bz in range(floori(box.position.y / BUCKET), floori(box.end.y / BUCKET) + 1):
			var key := Vector2i(bx, bz)
			if not _buckets.has(key):
				continue
			if not _keep.has(key):
				_keep[key] = []
			_keep[key].append(segment)


func refines(cell_x: int, cell_z: int) -> bool:
	return refined.has(Vector2i(cell_x, cell_z))


func skips(cell_x: int, cell_z: int) -> bool:
	return holes.has(Vector2i(cell_x, cell_z))


func _inside_walls(lot: Dictionary, p: Vector2) -> bool:
	var d: Vector2 = p - lot.c
	return absf(d.dot(lot.s)) < lot.w * 0.5 and absf(d.dot(lot.f)) < lot.d * 0.5


## Distance from a lot's level ground (walls + FLAT, its yard in front), 0 inside.
func _dist(lot: Dictionary, p: Vector2) -> float:
	var d: Vector2 = p - lot.c
	var u := d.dot(lot.s)
	var v := d.dot(lot.f)
	var front: float = SHACK_FRONT if lot.shack else FLAT + APRON
	var du := maxf(absf(u) - (lot.w * 0.5 + FLAT), 0.0)
	var dv := maxf(maxf(-lot.d * 0.5 - FLAT - v, v - lot.d * 0.5 - front), 0.0)
	return Vector2(du, dv).length()


## The ground at a world-frame point given the ground there without the plots.
func height(p: Vector2, base: float) -> float:
	var key := Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET))
	if not _buckets.has(key):
		return base
	var h := INF
	for i in _buckets[key]:
		var lot := lots[i]
		var d := _dist(lot, p)
		if d >= BLEND:
			continue
		h = minf(h, lerpf(lot.level, base, smoothstep(0.0, BLEND, d)))
		# under a building's own floor the ground lies FLOOR_GAP lower (Codex d086d7a native: the
		# floors shared the terrain's plane and flickered gravel through the boards)
		if d == 0.0 and _inside_walls(lot, p):
			h = minf(h, lot.level - FLOOR_GAP)
	if h == INF:
		return base
	var keep := 1.0
	for r in _keep.get(key, []):
		var q := Geometry2D.get_closest_point_to_segment(p, r[0], r[1])
		keep = minf(keep, smoothstep(r[2], r[2] + KEEP, p.distance_to(q)))
	return lerpf(base, h, keep)


## The same at a point of the 1.25 m lattice, computed once (the mesh and world_ground share them).
func lattice(ix: int, iz: int, base: Callable) -> float:
	var key := Vector2i(ix, iz)
	if not _cache.has(key):
		_cache[key] = base.call(ix * FINE, iz * FINE)
	return _cache[key]


## A stone plinth under every house whose ground falls away below its floor (the uphill neighbour of a
## lower plot, a stair well's edge): the house's walls + PLINTH_LEDGE, from its floor down into the
## lowest ground under it. `book` draws it in the stair flights' masonry.
func build_plinths(book: Node3D, ground: Callable) -> void:
	var node := Node3D.new()
	node.name = "SnowPlinths"
	book.add_child(node)
	var count := 0
	for lot in lots:
		if CUTS.has(lot.code):
			continue
		var low := INF
		var hw: float = lot.w * 0.5 + PLINTH_LEDGE
		var hd: float = lot.d * 0.5 + PLINTH_LEDGE
		for i in 13:
			for j in 13:
				var u := lerpf(-hw, hw, i / 12.0)
				var v := lerpf(-hd, hd, j / 12.0)
				var p: Vector2 = lot.c + lot.s * u + lot.f * v
				low = minf(low, float(ground.call(p.x, p.y)))
		if lot.level - low <= PLINTH_HANG:
			continue
		var top: float = lot.level - 0.02
		var bottom := low - 0.4
		var yaw := rad_to_deg(atan2(lot.f.x, lot.f.y))
		book._stair_block(node, Vector3(lot.c.x, (top + bottom) * 0.5, lot.c.y), Vector3(hw * 2.0, top - bottom, hd * 2.0), yaw, "masonry")
		count += 1
	# Stone steps down from a door whose front falls away (the slum's lane runs down past it).
	var steps := 0
	for lot in lots:
		if CUTS.has(lot.code):
			continue
		var out: float = lot.d * 0.5 + PLINTH_LEDGE
		var yaw := rad_to_deg(atan2(lot.f.x, lot.f.y))
		# Out from the door slot by slot, the walking surface S: on each slot the highest ground along
		# the path's middle, but never more than one riser under the slot before - where the ground
		# under S falls away, a stone step at S (Codex d086d7a, the actual hero at vs12: the shack's
		# 1 m level front, then the lane 2.1 m down within the next 0.7 m). The block's foot is the
		# lowest ground over the step's whole width (the lane also falls sideways).
		var walk: float = lot.level - 0.02
		var idle := 0
		var built := 0
		for k in range(1, STOOP_MAX + 1):
			var p: Vector2 = lot.c + lot.f * (out + STOOP_RUN * (k - 0.5))
			var high := -INF
			var low := INF
			var foot := INF
			for a in [-0.5, -0.17, 0.17, 0.5]:
				for q in [-STOOP_WIDTH * 0.5, -0.4, 0.0, 0.4, STOOP_WIDTH * 0.5]:
					var e: Vector2 = p + lot.f * (STOOP_RUN * a) + lot.s * q
					var h := float(ground.call(e.x, e.y))
					foot = minf(foot, h)
					if absf(q) < 0.5:
						high = maxf(high, h)
						low = minf(low, h)
			var top := minf(maxf(high, walk - STOOP_RISE), walk)
			walk = top
			if low >= top - 0.05:
				idle += 1
				# done once its steps have met the ground again (a level front first is walked)
				if built > 0 and idle >= 2:
					break
				continue
			idle = 0
			built += 1
			var bottom := foot - 0.4
			book._stair_block(node, Vector3(p.x, (top + bottom) * 0.5, p.y), Vector3(STOOP_WIDTH, top - bottom, STOOP_RUN + 0.03), yaw, "masonry")
			steps += 1
	# the cuts' collars: the hole's cells less the walls and the sunken yard, paved blocks at the
	# floor's level (along the back edge raised to the rock's ground where that stands higher, so no gap
	# shows)
	var collars := 0
	for item in _collars:
		var lot: Dictionary = item[0]
		var hole: Rect2 = item[1]
		var voids: Array = item[2]
		var depth: float = CUTS[lot.code]
		var xs: Array[float] = [hole.position.x, hole.end.x]
		var zs: Array[float] = [hole.position.y, hole.end.y]
		for v: Rect2 in voids:
			xs.append_array([clampf(v.position.x, hole.position.x, hole.end.x), clampf(v.end.x, hole.position.x, hole.end.x)])
			zs.append_array([clampf(v.position.y, hole.position.y, hole.end.y), clampf(v.end.y, hole.position.y, hole.end.y)])
		# a stair flight brushing the hole: the collar is cut round its treads and goes under them
		var near: Array = []
		var zone := Rect2()
		for t in _treads:
			var box := Rect2(t[0], Vector2.ZERO).grow(t[1])
			if box.intersects(hole):
				zone = box.intersection(hole) if near.is_empty() else zone.merge(box.intersection(hole))
				near.append(t)
		if not near.is_empty():
			xs.append_array([zone.position.x, zone.end.x])
			zs.append_array([zone.position.y, zone.end.y])
		xs.sort()
		zs.sort()
		for i in xs.size() - 1:
			for j in zs.size() - 1:
				var r := Rect2(xs[i], zs[j], xs[i + 1] - xs[i], zs[j + 1] - zs[j])
				if r.size.x < 0.05 or r.size.y < 0.05:
					continue
				var inside := false
				for v: Rect2 in voids:
					inside = inside or v.has_point(r.get_center())
				if inside:
					continue
				var top: float = lot.level
				for k in 9:
					for edge in [Vector2(lerpf(r.position.x, r.end.x, k / 8.0), r.position.y), Vector2(lerpf(r.position.x, r.end.x, k / 8.0), r.end.y),
							Vector2(r.position.x, lerpf(r.position.y, r.end.y, k / 8.0)), Vector2(r.end.x, lerpf(r.position.y, r.end.y, k / 8.0))]:
						var p: Vector2 = edge
						# only the back edge, against the rock (a stair flight comes up past a side)
						if absf(p.y - hole.position.y) < 0.01:
							top = maxf(top, minf(float(ground.call(p.x, p.y)), lot.level + 3.0))
				for t in near:
					var q := Vector2(clampf(t[0].x, r.position.x, r.end.x), clampf(t[0].y, r.position.y, r.end.y))
					if q.distance_to(t[0]) < float(t[1]):
						top = minf(top, float(t[2]) - 0.05)
				var bottom: float = lot.level - depth
				var c: Vector2 = r.get_center()
				book._stair_block(node, Vector3(c.x, (top + bottom) * 0.5, c.y), Vector3(r.size.x, top - bottom, r.size.y), 0.0, "masonry")
				collars += 1
		# the sunken yard's floor
		if AREAWAYS.has(lot.code):
			var yard: Rect2 = voids[1]
			var floor_y: float = lot.level - float(LOWER[lot.code])
			var c: Vector2 = yard.get_center()
			book._stair_block(node, Vector3(c.x, floor_y - 0.2, c.y), Vector3(yard.size.x, 0.4, yard.size.y), 0.0, "masonry")
			collars += 1
	print("SNOW_PLINTHS count=%d stoop_steps=%d cut_collars=%d" % [count, steps, collars])
