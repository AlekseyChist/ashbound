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
## WORLD-BUILD-01E (D-118, Codex contract 218): the desert city's 43 plots on the same ground - its
## levels from the ground under each plot (the bowl is flat to 0.6 m; the stores outside the east gate
## stand on 1-1.5 m), set in grade_streets. Its codes overlap the snow city's (s1/s2/s10/s11): a lot's
## `key` is its code in the snow city, "desert:" + code in the desert.
const DESERT_PLAN := "res://assets/world/desert-city-v1/plan.json"
## WORLD-BUILD-01F: the lowland city (the council's fortress, D-118) the same way; its piers and its
## shacks on stilts over the water stand on their own (no ground levelled under them).
const LOWLAND_PLAN := "res://assets/world/lowland-city-v1/plan.json"
const HALF := 1000.0
const GRID := 5.0
const FINE := 1.25
const FLAT := 2.0
## The slum's shacks keep a narrower level yard (Codex 106ecf5: their 2 m yards on the steep slope rose
## as earth humps along the lane); the floor clamp keeps the ground under their floors, plinths fill.
const FLAT_SHACK := 1.0
const APRON := 3.0
const SHACK_FRONT := 1.0
const BLEND := 3.0
## A plot cut into a slope (the ground over its level) fades into it over its height / CUT_GRADE m,
## up to CUT_BLEND_MAX (owner 14 Oct, Codex 925dd80 010/028-030: a 3 m fade under a 3-4 m cut left
## 45-50 deg earth banks behind the houses). Inside another plot's level ground the 3 m stays (its
## floor is never dug under). Fills keep BLEND: a wider fill only grows the earth humps.
const CUT_GRADE := 0.577
const CUT_BLEND_MAX := 8.0
const KEEP := 2.0
const BUCKET := 20.0
## Plinth: under a house the ground falls more than this below its floor -> a stone plinth.
const PLINTH_HANG := 0.12
const PLINTH_LEDGE := 0.25
## A shack's yard platform stays this far off a street's edge, cut back in YARD_STEP m.
const YARD_CLEAR := 0.2
const YARD_STEP := 0.25
const YARD_DOOR := 2.5
## A yard's paving slabs and their joints.
const PAVE := 0.9
const JOINT := 0.06
## A street's uphill bank higher than LANE_WALL_MIN over the street becomes a stone wall over the whole
## bank (its STREET_BLEND band past the edge), its top on the ground at the bank's top, sloping with
## the street (Codex 27c3f38 010/028/029/032: the slum's lane ran in a trench of 50 deg earth cuts).
## Only in runs of LANE_WALL_RUN m or more; not across a door stair, a house or another street.
const LANE_WALL_MIN := 0.6
const LANE_WALL_RUN := 5
const LANE_WALL_PROUD := 0.15
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
## The academy street, book 1056/307 -> 1100/286, and its route through the moved mine gate.
const MINE_STREET_FROM := Vector2(1056, 307)
const MINE_STREET_BOOK_END := Vector2(1100, 286)
const MINE_STREET_ROUTE := [Vector2(1056, 307), Vector2(1062, 296), Vector2(1083, 296), Vector2(1083, 303), Vector2(1082, 306.8), Vector2(1081, 331.4)]
const MINE_GATE := Vector2(1082, 306.8)
## A street is graded along a smoothed profile of its ground (window +-STREET_SMOOTH m), level
## across; over its width + 0.3 m it rules the plots' ground, fading out over STREET_BLEND m.
const STREET_STEP := 1.0
const STREET_SMOOTH := 3
const STREET_BLEND := 2.0
const STREET_PIN := 3.0
const JUNCTION := 1.5
const END_PAD := 3.0
## Along a house's front the street lies at its floor's level (the street within PIN_REACH m of its
## facade, PIN_SIDE m past its corners); between such fronts a straight ramp (owner 14 Oct, Codex G03:
## graded on the slope's own ground, the slum's lane ran 3-4 m under or over the terraced yards beside
## it and the ground between cut 50 deg banks).
const PIN_REACH := 6.0
const PIN_SIDE := 0.5
## The steepest a graded street runs (tan 25 deg).
const STREET_GRADE := 0.466
## SNOW-G03 (Codex 335/350, choice A): the slum's steep lane (street-8 by vs3/vs4, up to 25 deg) is a
## stone stair-street - treads of STAIR_RISE on its graded profile, its flat stretches (pinned to the
## doors' thresholds) landings; no earth under it: the ground lies just under its treads, and its body
## stands to the ground as masonry (the ridge and the earth cut at vs4 were the old earth lane).
const STAIR_STREETS := [Vector2(1000.9, 419.5)]
const STAIR_RISE := 0.18
## Map-frame tread records [x, z, top, yaw, depth, width, rail] for book.build_stairs.
var stair_street_steps: Array = []
## Their treads [at, reach, top] for the ground's clamp only (the lane walls keep to the street).
var _street_treads: Array = []
## [centre, out, depth from, depth to, half width, floor] per cave arch (set by world.gd from the mouths).
var arch_zones: Array = []
const STOOP_MAX := 24
## A straight stoop must meet the ground within this many steps, or the stair turns along the facade
## after a LANDING m deep landing at the door.
const STOOP_OUT := 4
const STOOP_LEVEL := 4
const LANDING := 1.2
const STOOP_RUN := 0.35
const STOOP_WIDTH := 1.6
## A door step's collision stops this far under its visible top (the slab above carries the hero).
const STOOP_UNDER := 0.08
## A snow flight stands in a bank of earth (owner 14 Oct: the flights' bodies rose as tall stepped
## stone walls over the falling slope): at a tread's side the ground lies FILL_TOP under its top and
## falls away at FILL_SLOPE (a 29 deg bank), fading into the slope over its last 3 of FILL_REACH m - never under a bridge deck, nor
## inside a plot's level ground. The bank's cells are drawn in the fine lattice.
const FILL_TOP := 0.3
const FILL_SLOPE := 0.55
const FILL_REACH := 12.0
const FILL_FINE := 5.0
const FILL_DECK := 6.0
const FILL_CAP := 1.0

var lots: Array[Dictionary] = []
var refined := {}
var _buckets := {}
var _keep := {}
var holes := {}
var _collars: Array = []
var _treads: Array = []
## Each snow flight's two ends: [the point past its end tread, the outward direction, its top].
var _ends: Array = []
## The book's streets (plan lines of kind street): [points (map frame), width].
var streets: Array = []
## Each door stair's walking line, code -> points (world frame): the door, (a landing,) the stair's end.
var stoop_paths := {}
## Graded streets: [points (world frame), cumulative distance at each point, the profile every
## STREET_STEP m, half width]; and their buckets.
var _profiles: Array = []
var _street_b := {}
var _cache := {}
## The bank: [centre (world frame), half extent, top] per tread, and their buckets.
var _fill: Array = []
## Floors that stand off the ground, "city:code" -> level (set by world.gd from world_lowland_water).
var extra_levels := {}
var _fill_b := {}


func setup(layout: Dictionary) -> void:
	var levels := {}
	for lot in layout.get("snow_lots", []):
		levels[str(lot.code)] = float(lot.level)
	if levels.is_empty():
		return
	_read_plan(PLAN, "snow", levels)
	_read_plan(DESERT_PLAN, "desert", {})
	_read_plan(LOWLAND_PLAN, "lowland", {})
	var area := Rect2()
	for i in lots.size():
		var lot := lots[i]
		var reach: float = Vector2(lot.w * 0.5 + FLAT, lot.d * 0.5 + FLAT + APRON).length() + CUT_BLEND_MAX
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
		# the smugglers' switchbacks too (Codex 351/352: on the 5 m grid a flight rising 2.4 m inside one
		# cell either buried its lower treads or left a pit at its end): their ground on the fine lattice,
		# in earth banks, with a pad past each end at its end tread's level
		if not (str(flight.id).begins_with("snow") or str(flight.id).begins_with("smugglers")):
			continue
		for st in flight.steps:
			var reach := maxf(float(st[4]), float(st[5])) * 0.5 + 0.5
			var at := Vector2(float(st[0]) - HALF, float(st[1]) - HALF)
			_add_keep(Rect2(at, Vector2.ZERO).grow(reach + KEEP), [at, at, reach])
			_treads.append([at, reach, float(st[2])])
		var decks: Array = []
		for st in flight.steps:
			if st.size() > 6 and int(st[6]) == 4:
				decks.append(Vector2(float(st[0]) - HALF, float(st[1]) - HALF))
		for st in flight.steps:
			var at := Vector2(float(st[0]) - HALF, float(st[1]) - HALF)
			var near_deck := false
			for d: Vector2 in decks:
				near_deck = near_deck or at.distance_to(d) < FILL_DECK
			if near_deck:
				continue
			var half := maxf(float(st[4]), float(st[5])) * 0.5
			# no earth bank by the smugglers' flights (tests61: it rose over trail 2's deck beside the Sh2
			# stair); they stand on their own masonry
			var bank := not str(flight.id).begins_with("smugglers")
			var i := _fill.size()
			if bank:
				_fill.append([at, half, float(st[2])])
			var box := Rect2(at, Vector2.ZERO).grow(half + FILL_REACH)
			for bx in range(floori(box.position.x / BUCKET), floori(box.end.x / BUCKET) + 1):
				for bz in range(floori(box.position.y / BUCKET), floori(box.end.y / BUCKET) + 1):
					var key := Vector2i(bx, bz)
					if not _fill_b.has(key):
						_fill_b[key] = []   # the bucket still reaches height()'s tread clamp
					if bank:
						_fill_b[key].append(i)
			var r := half + FILL_FINE + GRID * 0.72
			for cx in range(floori((at.x - r + HALF) / GRID), floori((at.x + r + HALF) / GRID) + 1):
				for cz in range(floori((at.y - r + HALF) / GRID), floori((at.y + r + HALF) / GRID) + 1):
					var centre := Vector2((cx + 0.5) * GRID - HALF, (cz + 0.5) * GRID - HALF)
					if centre.distance_to(at) < r:
						refined[Vector2i(cx, cz)] = true
		var steps: Array = flight.steps
		if steps.size() >= 2:
			for pair in [[steps[0], steps[1]], [steps[steps.size() - 1], steps[steps.size() - 2]]]:
				var end := Vector2(float(pair[0][0]) - HALF, float(pair[0][1]) - HALF)
				var inner := Vector2(float(pair[1][0]) - HALF, float(pair[1][1]) - HALF)
				var half := maxf(float(pair[0][4]), float(pair[0][5])) * 0.5
				_ends.append([end + (end - inner).normalized() * half, (end - inner).normalized(), float(pair[0][2])])
	print("SNOW_LOTS lots=%d refined_cells=%d keep_buckets=%d" % [lots.size(), refined.size(), _keep.size()])


## One city's plan: its streets and its plots (levels given, or NAN until grade_streets).
func _read_plan(path: String, city: String, levels: Dictionary) -> void:
	if not FileAccess.file_exists(path):
		return
	var plan = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not plan is Dictionary:
		return
	for line in plan.get("lines", []):
		if str(line.kind) == "street":
			var pts := PackedVector2Array()
			for q in line.pts:
				pts.append(Vector2(float(q[0]), float(q[1])))
			# D-121 deviation agreed with Codex (bridge 183/184): the academy street's book end - the
			# mine gate at 1089/290 and 1100/286 outside it - lies 30 m up the cliff behind the shelf,
			# off the real mine road (mine_approach passes 45 m south). The gate moves into the shelf's
			# south-east wall at 1082/306.8 and the street runs on to the mine road at 1081/331.4.
			if city == "snow" and pts[0].distance_to(MINE_STREET_FROM) < 1.0 and pts[pts.size() - 1].distance_to(MINE_STREET_BOOK_END) < 1.0:
				pts = PackedVector2Array(MINE_STREET_ROUTE)
			streets.append([pts, float(line.width)])
	for b in plan.get("buildings", []):
		var code := str(b.code)
		if city == "snow" and not levels.has(code):
			continue
		if city == "lowland" and (str(b.kind) == "pier" or str(b.kind) == "shack"):
			continue
		var yaw := deg_to_rad(float(b.yaw))
		var f := Vector2(-sin(yaw), cos(yaw))
		var lot := {
			"code": code, "key": code if city == "snow" else city + ":" + code, "city": city,
			"c": Vector2(float(b.x) - HALF, float(b.z) - HALF), "f": f, "s": Vector2(f.y, -f.x),
			"w": float(b.w), "d": float(b.d), "level": float(levels.get(code, NAN)), "shack": str(b.kind) == "shack",
			"plinth": bool(b.get("plinth", false)),
		}
		lots.append(lot)


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


## The plot's authored level (its floor), NAN if the plan has no such plot - Codex's builder sets
## each module's floor here (the ground under it lies FLOOR_GAP lower).
func level_of(code: String, city := "snow") -> float:
	for lot in lots:
		if lot.code == code and lot.city == city:
			return lot.level
	# a floor not on the ground (the lowland's shacks on stilts: world_lowland_water)
	return float(extra_levels.get(city + ":" + code, NAN))


## Grades the streets; `ground` takes world-frame x, z (the world's grid before the plots).
func grade_streets(ground: Callable) -> void:
	# the desert's plots: each at the mean of its ground (walls and their corners), to 5 cm
	for lot in lots:
		if not is_nan(float(lot.level)):
			continue
		var sum := 0.0
		var top := -INF
		for u in [-0.5, 0.0, 0.5]:
			for v in [-0.5, 0.0, 0.5]:
				var q: Vector2 = lot.c + lot.s * (lot.w * u) + lot.f * (lot.d * v)
				var h := float(ground.call(q.x, q.y))
				sum += h
				top = maxf(top, h)
		# a building the book sets on a stone plinth (the lowland citadel and port on the spur and the
		# bank): its floor over the highest ground under it, the plinth taking up the fall and door
		# steps down from it (Ts1's door had faced a 0.49 m climb)
		lot.level = snappedf(top + 0.15 if lot.plinth else sum / 9.0, 0.05)
	# Grade each street (Codex 0208cfd / the lane walk: between the slum's plots of different levels
	# the lane folded into a 55 deg crease; by the foot of stair C the street crossed a 46 deg bank).
	for street in streets:
		var map_pts: PackedVector2Array = street[0]
		var pts := PackedVector2Array()
		var cum := PackedFloat32Array()
		var run := 0.0
		for k in map_pts.size():
			var q: Vector2 = map_pts[k] - Vector2(HALF, HALF)
			if k > 0:
				run += q.distance_to(pts[k - 1])
			pts.append(q)
			cum.append(run)
		# the ground along it, but not over a stair flight's treads (the middle terrace's street crosses
		# stair A's well): those samples are bridged between their neighbours
		var raw := PackedFloat32Array()
		var valid: Array[bool] = []
		var n := int(ceil(run / STREET_STEP)) + 1
		for i in n:
			var q := _along(pts, cum, minf(i * STREET_STEP, run))
			# over a stair flight the street meets its treads: the nearest tread's top (Codex 6ef4e04:
			# graded on the well's ground, the academy street reached stair C's top 3.4 m low and the
			# middle street lay 0.83 m under stair A's top)
			var tread_top := NAN
			var near := INF
			for t in _treads:
				var dt: float = q.distance_to(t[0])
				if dt < float(t[1]) and dt < near:
					near = dt
					tread_top = float(t[2])
			raw.append(float(ground.call(q.x, q.y)) if is_nan(tread_top) else tread_top)
			valid.append(true)
		for i in n:
			if valid[i]:
				continue
			var a := i - 1
			while a >= 0 and not valid[a]:
				a -= 1
			var b := i + 1
			while b < n and not valid[b]:
				b += 1
			if a >= 0 and b < n:
				raw[i] = lerpf(raw[a], raw[b], float(i - a) / float(b - a))
			elif a >= 0:
				raw[i] = raw[a]
			elif b < n:
				raw[i] = raw[b]
		var smooth := PackedFloat32Array()
		for i in n:
			var sum := 0.0
			var count := 0
			for j in range(maxi(0, i - STREET_SMOOTH), mini(n, i + STREET_SMOOTH + 1)):
				sum += raw[j]
				count += 1
			smooth.append(sum / count)
		# the houses' fronts: their levels, and straight ramps between them
		var pins := PackedFloat32Array()
		pins.resize(n)
		for i in n:
			var q := _along(pts, cum, minf(i * STREET_STEP, run))
			var sum := 0.0
			var count := 0
			for lot in lots:
				var d: Vector2 = q - lot.c
				var out: float = d.dot(lot.f) - lot.d * 0.5
				if absf(d.dot(lot.s)) <= lot.w * 0.5 + PIN_SIDE and out >= 0.0 and out <= PIN_REACH:
					sum += lot.level
					count += 1
			var on_tread := false
			for t in _treads:
				on_tread = on_tread or q.distance_to(t[0]) < float(t[1])
			pins[i] = sum / count if count > 0 and not on_tread else NAN
		var last := -1
		for i in n:
			if is_nan(pins[i]):
				continue
			smooth[i] = pins[i]
			if last >= 0 and i - last > 1:
				for j in range(last + 1, i):
					smooth[j] = lerpf(pins[last], pins[i], float(j - last) / float(i - last))
			last = i
		# eased over +-2 m: no kink where a ramp meets a front, nor a step where the fronts on the two
		# sides of a lane overlap
		var eased := PackedFloat32Array()
		var steepest := 0.0
		for i in n:
			var sum := 0.0
			var count := 0
			for j in range(maxi(0, i - 2), mini(n, i + 3)):
				sum += smooth[j]
				count += 1
			eased.append(sum / count)
			if i > 0:
				steepest = maxf(steepest, absf(eased[i] - eased[i - 1]) / STREET_STEP)
		# no steeper than STREET_GRADE: where the fronts' levels need more, they give way to the ramp
		for pass_i in 200:
			var moved := false
			for i in n - 1:
				var excess := absf(eased[i + 1] - eased[i]) - STREET_GRADE * STREET_STEP
				if excess > 0.001:
					var push := signf(eased[i + 1] - eased[i]) * excess * 0.5
					eased[i] += push
					eased[i + 1] -= push
					moved = true
			if not moved:
				break
		steepest = 0.0
		for i in range(1, n):
			steepest = maxf(steepest, absf(eased[i] - eased[i - 1]) / STREET_STEP)
		smooth = eased
		print("SNOW_STREET %d length=%.0f steepest=%.0f deg" % [_profiles.size(), run, rad_to_deg(atan(steepest))])
		var half := float(street[1]) * 0.5
		var index := _profiles.size()
		_profiles.append([pts, cum, smooth, half])
		var reach := half + 0.3 + STREET_BLEND
		for i in n:
			var q := _along(pts, cum, minf(i * STREET_STEP, run))
			for bx in range(floori((q.x - reach) / BUCKET), floori((q.x + reach) / BUCKET) + 1):
				for bz in range(floori((q.y - reach) / BUCKET), floori((q.y + reach) / BUCKET) + 1):
					var key := Vector2i(bx, bz)
					if not _street_b.has(key):
						_street_b[key] = []
					if not _street_b[key].has(index):
						_street_b[key].append(index)
			for cx in range(floori((q.x - reach - GRID + HALF) / GRID), floori((q.x + reach + GRID + HALF) / GRID) + 1):
				for cz in range(floori((q.y - reach - GRID + HALF) / GRID), floori((q.y + reach + GRID + HALF) / GRID) + 1):
					refined[Vector2i(cx, cz)] = true
	# the stair-streets (STAIR_STREETS): treads on each one's graded profile
	for target in STAIR_STREETS:
		var w: Vector2 = target - Vector2(HALF, HALF)
		var si := -1
		var best := INF
		for j in _profiles.size():
			var d := float(_street_at(j, w)[0])
			if d < best:
				best = d
				si = j
		if si < 0 or best > 3.0:
			continue
		var pts: PackedVector2Array = _profiles[si][0]
		var cum: PackedFloat32Array = _profiles[si][1]
		var smooth: PackedFloat32Array = _profiles[si][2]
		var width := float(_profiles[si][3]) * 2.0
		var run: float = cum[cum.size() - 1]
		var height_at := func(t: float) -> float:
			var f := t / STREET_STEP
			var a := clampi(floori(f), 0, smooth.size() - 1)
			var b := mini(a + 1, smooth.size() - 1)
			return lerpf(smooth[a], smooth[b], f - a)
		var t0 := 0.0
		var top: float = height_at.call(0.0)
		var t := 0.0
		while t < run:
			t = minf(t + 0.02, run)
			var h: float = height_at.call(t)
			if absf(h - top) >= STAIR_RISE or t >= run:
				var mid := (t0 + t) * 0.5
				var q := _along(pts, cum, mid)
				var dir := (_along(pts, cum, minf(mid + 0.3, run)) - _along(pts, cum, maxf(mid - 0.3, 0.0))).normalized()
				var depth := t - t0 + 0.02
				stair_street_steps.append([q.x + HALF, q.y + HALF, top, rad_to_deg(atan2(dir.x, dir.y)), depth, width, 0])
				_street_treads.append([q, dir, depth * 0.5, width * 0.5, top])
				top += STAIR_RISE * signf(h - top) if absf(h - top) >= STAIR_RISE else 0.0
				t0 = t
	# Where streets meet, one height: a street running through the junction keeps its own and the
	# streets ending there come to it; where streets only end there, they meet at their mean. Each
	# ending street eases to it over its last STREET_PIN m (Codex 0208cfd: graded alone, the streets'
	# profiles disagreed at shared points).
	var ends: Array = []
	for si in _profiles.size():
		var pts: PackedVector2Array = _profiles[si][0]
		ends.append([si, 0, pts[0]])
		ends.append([si, 1, pts[pts.size() - 1]])
	var targets: Array = []
	for e in ends:
		var through := NAN
		var sum := 0.0
		var count := 0
		for sj in _profiles.size():
			var at: Array = _street_at(sj, e[2])
			if float(at[0]) > JUNCTION:
				continue
			var pts: PackedVector2Array = _profiles[sj][0]
			var at_end: bool = pts[0].distance_to(e[2]) < JUNCTION or pts[pts.size() - 1].distance_to(e[2]) < JUNCTION
			if not at_end and is_nan(through):
				through = float(at[1])
			sum += float(at[1])
			count += 1
		targets.append(through if not is_nan(through) else sum / maxi(count, 1))
	for k in ends.size():
		var si: int = ends[k][0]
		var smooth: PackedFloat32Array = _profiles[si][2]
		var n := smooth.size()
		var last := n - 1 if ends[k][1] == 1 else 0
		var delta: float = targets[k] - smooth[last]
		for i in n:
			var to_end := float(absi(i - last)) * STREET_STEP
			if to_end < STREET_PIN:
				smooth[i] += delta * (1.0 - to_end / STREET_PIN)
		_profiles[si][2] = smooth


func _along(pts: PackedVector2Array, cum: PackedFloat32Array, t: float) -> Vector2:
	for k in range(1, pts.size()):
		if t <= cum[k] or k == pts.size() - 1:
			var span := maxf(cum[k] - cum[k - 1], 0.001)
			return pts[k - 1].lerp(pts[k], clampf((t - cum[k - 1]) / span, 0.0, 1.0))
	return pts[0]


## [distance across the street, its graded level] at a world-frame point.
func _street_at(index: int, p: Vector2) -> Array:
	var prof: Array = _profiles[index]
	var pts: PackedVector2Array = prof[0]
	var cum: PackedFloat32Array = prof[1]
	var smooth: PackedFloat32Array = prof[2]
	var best := INF
	var t := 0.0
	for k in range(1, pts.size()):
		var q := Geometry2D.get_closest_point_to_segment(p, pts[k - 1], pts[k])
		var d := p.distance_to(q)
		if d < best:
			best = d
			t = cum[k - 1] + pts[k - 1].distance_to(q)
	var f := t / STREET_STEP
	var i := clampi(floori(f), 0, smooth.size() - 1)
	var j := mini(i + 1, smooth.size() - 1)
	return [best, lerpf(smooth[i], smooth[j], f - i)]


func refines(cell_x: int, cell_z: int) -> bool:
	return refined.has(Vector2i(cell_x, cell_z))


func skips(cell_x: int, cell_z: int) -> bool:
	return holes.has(Vector2i(cell_x, cell_z))


## Inside the walls grown by one lattice cell: every 1.25 m triangle under the floor has all three
## corners lowered (Codex 0208cfd: with only the corners inside the walls lowered, the triangles rose
## back to the floor's level 0.65 m inside them).
## Distance from a building's walls (0 inside).
func _wall_dist(lot: Dictionary, p: Vector2) -> float:
	var d: Vector2 = p - lot.c
	var du := maxf(absf(d.dot(lot.s)) - lot.w * 0.5, 0.0)
	var dv := maxf(absf(d.dot(lot.f)) - lot.d * 0.5, 0.0)
	return Vector2(du, dv).length()


func _inside_walls(lot: Dictionary, p: Vector2) -> bool:
	var d: Vector2 = p - lot.c
	return absf(d.dot(lot.s)) < lot.w * 0.5 + FINE and absf(d.dot(lot.f)) < lot.d * 0.5 + FINE


## Distance from a lot's level ground (walls + FLAT, its yard in front), 0 inside.
func _dist(lot: Dictionary, p: Vector2) -> float:
	var d: Vector2 = p - lot.c
	var u := d.dot(lot.s)
	var v := d.dot(lot.f)
	var flat: float = FLAT_SHACK if lot.shack else FLAT
	var front: float = SHACK_FRONT if lot.shack else FLAT + APRON
	var du := maxf(absf(u) - (lot.w * 0.5 + flat), 0.0)
	var dv := maxf(maxf(-lot.d * 0.5 - flat - v, v - lot.d * 0.5 - front), 0.0)
	return Vector2(du, dv).length()


## The ground at a world-frame point given the ground there without the plots.
func height(p: Vector2, base: float) -> float:
	var key := Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET))
	if not _buckets.has(key) and not _street_b.has(key) and not _fill_b.has(key):
		return base
	var h := INF
	var core := INF
	var dists: Array[float] = []
	for i in _buckets.get(key, []):
		var d := _dist(lots[i], p)
		dists.append(d)
		core = minf(core, d)
	var in_flat := core == 0.0
	var n := 0
	for i in _buckets.get(key, []):
		var lot := lots[i]
		var d: float = dists[n]
		n += 1
		var blend := BLEND
		if base > lot.level and not in_flat:
			blend = clampf((base - lot.level) / CUT_GRADE, BLEND, CUT_BLEND_MAX)
		if d >= blend:
			continue
		# a shack's yard is a stone platform where the slope falls under it (build_plinths): the ground
		# is cut down to its level but never banked up to it (Codex G03, direction A)
		var target: float = minf(lot.level, base) if lot.shack else lot.level
		h = minf(h, lerpf(target, base, smoothstep(0.0, blend, d)))
		# under a building's own floor the ground lies FLOOR_GAP lower (Codex d086d7a native: the
		# floors shared the terrain's plane and flickered gravel through the boards)
		if d == 0.0 and _inside_walls(lot, p):
			h = minf(h, lot.level - FLOOR_GAP)
	# the plots fade out at roads and stair flights (their ground kept)
	var keep := 1.0
	for r in _keep.get(key, []):
		var q := Geometry2D.get_closest_point_to_segment(p, r[0], r[1])
		keep = minf(keep, smoothstep(r[2], r[2] + KEEP, p.distance_to(q)))
	var g := base if h == INF else lerpf(base, h, keep)
	var graded := h != INF
	# the flights' bank, under the streets (they ride over it) and out of the plots' level ground
	# - and never over a lower tread nearby by more than FILL_CAP per metre from its edge (at a turn of
	# a flight the upper run's bank buried the lower run's treads)
	var bank := -INF
	var cap := INF
	for i in _fill_b.get(key, []):
		var t: Array = _fill[i]
		var out := maxf(p.distance_to(t[0]) - float(t[1]), 0.0)
		if out < FILL_REACH:
			cap = minf(cap, float(t[2]) - FILL_TOP + out * FILL_CAP)
			var b := float(t[2]) - FILL_TOP - out * FILL_SLOPE
			if b > g:
				bank = maxf(bank, lerpf(b, g, smoothstep(FILL_REACH - 3.0, FILL_REACH, out)))
	bank = minf(bank, cap)
	if bank > g:
		g = lerpf(g, bank, smoothstep(0.0, BLEND, core) if core != INF else 1.0)
		graded = true
	# the streets over that, up to the stairs they meet, yielding to a plot only within a lattice cell
	# of its walls (Codex 6ef4e04: yielding to the whole yard left a berm in the slum's lane that
	# pushed the hero onto vs3's plinth; under the flights' kept ground the academy street reached
	# stair C's top 3.4 m low and the middle street lay 0.83 m under stair A's top)
	for si in _street_b.get(key, []):
		var at: Array = _street_at(si, p)
		var edge: float = float(_profiles[si][3]) + 0.3
		if float(at[0]) < edge + STREET_BLEND:
			var walls := INF
			for i in _buckets.get(key, []):
				walls = minf(walls, _wall_dist(lots[i], p))
			var w := (1.0 - smoothstep(edge, edge + STREET_BLEND, float(at[0]))) * smoothstep(FINE, FINE + 1.0, walls)
			g = lerpf(g, float(at[1]), w)
			graded = true
	# past each end of a snow flight, a pad at its end tread's top - only beyond the end
	for e in _ends:
		var off: Vector2 = p - e[0]
		if off.length() < END_PAD + STREET_BLEND and off.dot(e[1]) > -0.2:
			g = lerpf(g, float(e[2]), 1.0 - smoothstep(END_PAD, END_PAD + STREET_BLEND, off.length()))
			graded = true
	# a tread close by always grades the point (a flight cut into the slope, where no bank or street
	# touched the ground, left the ground over 12 of the smugglers' mid treads)
	if not graded:
		for t in _treads:
			if p.distance_to(t[0]) < float(t[1]) - 0.5:
				graded = true
				break
	# the caves' arches (world_cave_mouths.arch_zones): inside one the ground lies under its floor
	# (Codex 364 MOUTH-FLOOR-01: on the fine lattice the stair's end pad lifted it 0.21-0.36 m over
	# foothill X's floor)
	var arch_floor := INF
	for z in arch_zones:
		var off: Vector2 = p - z[0]
		var out: Vector2 = z[1]
		var depth := -off.dot(out)
		if depth >= z[2] and depth <= z[3] and absf(off.dot(Vector2(-out.y, out.x))) <= z[4]:
			arch_floor = minf(arch_floor, float(z[5]))
	if arch_floor < INF:
		graded = true
	if not graded:
		return base
	if arch_floor < INF:
		g = minf(g, arch_floor - 0.06)
	# never over a stair tread (the stairs stay on top: Codex 6ef4e04 had three of C's buried) ...
	for t in _treads:
		if p.distance_to(t[0]) < float(t[1]) - 0.5:
			g = minf(g, float(t[2]) - 0.02)
	# ... nor over the stair-street's (SNOW-G03): no earth under it
	for t in _street_treads:
		# within the tread's own footprint only (Codex 363/364 G03-DOOR-JOIN-01: a round reach lowered the
		# ground beside the stair-street, and the stoops of vs3/vs4 met its side 0.7 m under its treads)
		var off: Vector2 = p - t[0]
		var dir: Vector2 = t[1]
		if absf(off.dot(dir)) <= float(t[2]) and absf(off.dot(Vector2(-dir.y, dir.x))) <= float(t[3]) - 0.05:
			g = minf(g, float(t[4]) - 0.02)
	# ... nor over a floor within a cell of its walls
	for i in _buckets.get(key, []):
		var lot := lots[i]
		var walls := _wall_dist(lot, p)
		if walls < FINE:
			g = minf(g, lot.level - (FLOOR_GAP if walls == 0.0 else 0.0))
	return g


## The same at a point of the 1.25 m lattice, computed once (the mesh and world_ground share them).
func lattice(ix: int, iz: int, base: Callable) -> float:
	var key := Vector2i(ix, iz)
	if not _cache.has(key):
		_cache[key] = base.call(ix * FINE, iz * FINE)
	return _cache[key]


## Steps of STOOP_RUN from `start` along `dir` (the stair `width` wide across it): on each the
## walking surface is the highest ground along the stair's middle, but never more than a riser under
## the step before; where the ground under it falls away, a stone block at it. Returns [steps built,
## met the ground again (done), the point past the last step]. `place` false only measures.
func _steps(book: Node3D, node: Node3D, ground: Callable, start: Vector2, dir: Vector2, across: Vector2, width: float, walk0: float, slots: int, place: bool) -> Array:
	var walk := walk0
	var idle := 0
	var built := 0
	var yaw := rad_to_deg(atan2(dir.x, dir.y))
	var end: Vector2 = start
	# the walking slabs, merged while their pitch holds: [high edge, its height, low edge, its height,
	# pitch] - one long slab per even run (Codex/validator: the capsule caught the joints of nine
	# separate 27 deg slabs on vs3's door stair)
	var run_slab: Array = []
	for k in range(1, slots + 1):
		var p: Vector2 = start + dir * (STOOP_RUN * (k - 0.5))
		end = p + dir * (STOOP_RUN * 0.5)
		var high := -INF
		var low := INF
		var foot := INF
		for a in [-0.5, -0.17, 0.17, 0.5]:
			for q in [-1.5, -0.85, -0.5, -0.25, 0.0, 0.25, 0.5, 0.85, 1.5]:
				var e: Vector2 = p + dir * (STOOP_RUN * a) + across * (width * q)
				var h := float(ground.call(e.x, e.y))
				# the footing reaches the ground a little past its sides too (Codex cd261e9 014/024:
				# stepped bases showed over the falling slope beside the stair)
				foot = minf(foot, h)
				if absf(q) > 0.6:
					continue
				if absf(q) < 0.3:
					high = maxf(high, h)
					low = minf(low, h)
		var top := minf(maxf(high, walk - STOOP_RISE), walk)
		var before := walk
		walk = top
		# ground within reach of the walking level - and, after a block, no more than a riser under it
		# (Codex 106ecf5: vs13's foot ended 0.287 m over the ground just past its last block)
		if low >= top - 0.05 and (built == 0 or before - low <= STOOP_RISE + 0.02):
			idle += 1
			# done once its steps meet the ground for STOOP_LEVEL steps (Codex 6ef4e04: after two, vs13's
			# bank fell on 0.68 m past the stair's foot)
			if built > 0 and idle >= STOOP_LEVEL:
				_flush_slab(book, node, run_slab, width, yaw)
				return [built, true, end]
			if built == 0 and idle >= 3:
				_flush_slab(book, node, run_slab, width, yaw)
				return [0, true, end]
			continue
		idle = 0
		built += 1
		if place:
			# deep into the slope below: the stair stands on a solid wall, never on a visible edge
			# (Codex 27c3f38 014/015: stepped undersides read as cantilevers over the falling snow)
			var bottom := foot - 1.2
			book._stair_block(node, Vector3(p.x, (top + bottom) * 0.5, p.y), Vector3(width, top - bottom, STOOP_RUN + 0.03), yaw, "masonry", false)
			# its collision stops STOOP_UNDER under its top: the walking slab below carries the hero (the
			# block's edge 3 cm over the slab caught the capsule at vs3 - as the flights' treads do)
			var body_top := top - STOOP_UNDER
			book._stair_collider(node, Vector3(p.x, (body_top + bottom) * 0.5, p.y), Vector3(width, body_top - bottom, STOOP_RUN + 0.03), Basis(Vector3.UP, deg_to_rad(yaw)))
			# its walking surface: a slab from the step before down to this one, as the flights'
			# treads have (the capsule caught the short risers' edges on the slum's door stairs)
			var pitch := atan2(before - top, STOOP_RUN)
			var hi: Vector2 = p - dir * (STOOP_RUN * 0.5)
			var lo: Vector2 = p + dir * (STOOP_RUN * 0.5)
			if not run_slab.is_empty() and absf(float(run_slab[4]) - pitch) < 0.01:
				run_slab[2] = lo
				run_slab[3] = top
			else:
				_flush_slab(book, node, run_slab, width, yaw)
				run_slab = [hi, before, lo, top, pitch]
			book._stair_block(node, Vector3(p.x, top - 0.05, p.y), Vector3(width + 0.04, 0.1, STOOP_RUN + 0.02), yaw, "tread", false)
	_flush_slab(book, node, run_slab, width, yaw)
	return [built, false, end]


## One walking slab over a run of door steps: from its high edge (height) to its low edge (height).
func _flush_slab(book: Node3D, node: Node3D, run_slab: Array, width: float, yaw: float) -> void:
	if run_slab.is_empty():
		return
	var hi: Vector2 = run_slab[0]
	var lo: Vector2 = run_slab[2]
	var h0: float = run_slab[1]
	var h1: float = run_slab[3]
	var length := hi.distance_to(lo)
	var pitch := atan2(h0 - h1, length)
	var mid: Vector2 = (hi + lo) * 0.5
	var turn := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, pitch)
	book._stair_collider(node, Vector3(mid.x, (h0 + h1) * 0.5 - 0.03, mid.y), Vector3(width, 0.06, length / cos(pitch) + 0.04), turn)


## The lane walls (see LANE_WALL_MIN), after build_plinths (they keep off its door stairs).
func build_lane_walls(book: Node3D, ground: Callable) -> void:
	var node := Node3D.new()
	node.name = "SnowLaneWalls"
	book.add_child(node)
	var count := 0
	for si in _profiles.size():
		var pts: PackedVector2Array = _profiles[si][0]
		var cum: PackedFloat32Array = _profiles[si][1]
		var edge: float = float(_profiles[si][3]) + 0.3
		var run: float = cum[cum.size() - 1]
		var n := int(floor(run / STREET_STEP))
		for sx in [-1.0, 1.0]:
			# each sample: [centre, along, across, street level, top] or null
			var samples: Array = []
			for i in n:
				var t := (i + 0.5) * STREET_STEP
				var q := _along(pts, cum, t)
				var dir := (_along(pts, cum, minf(t + 0.5, run)) - _along(pts, cum, maxf(t - 0.5, 0.0))).normalized()
				var across: Vector2 = Vector2(-dir.y, dir.x) * sx
				var level := float(_street_at(si, q)[1])
				var top := -INF
				for k in 5:
					var e: Vector2 = q + across * (edge + STREET_BLEND * k / 4.0)
					top = maxf(top, float(ground.call(e.x, e.y)))
				var centre: Vector2 = q + across * (edge + STREET_BLEND * 0.5)
				var ok := top - level >= LANE_WALL_MIN
				if ok:
					for sj in _profiles.size():
						if sj != si and float(_street_at(sj, centre)[0]) < float(_profiles[sj][3]) + 0.3 + STREET_BLEND:
							ok = false
					for lot in lots:
						if _wall_dist(lot, centre) < STREET_BLEND * 0.5 + 0.1:
							ok = false
					for code in stoop_paths:
						var sp: PackedVector2Array = stoop_paths[code]
						for k in sp.size() - 1:
							if centre.distance_to(Geometry2D.get_closest_point_to_segment(centre, sp[k], sp[k + 1])) < STOOP_WIDTH * 0.5 + STREET_BLEND * 0.5 + 0.2:
								ok = false
					for tr in _treads:
						if centre.distance_to(tr[0]) < float(tr[1]) + STREET_BLEND * 0.5:
							ok = false
				samples.append([centre, dir, across, level, top] if ok else null)
			# runs only
			var i := 0
			while i < n:
				if samples[i] == null:
					i += 1
					continue
				var j := i
				while j < n and samples[j] != null:
					j += 1
				if j - i >= LANE_WALL_RUN:
					# one continuous body per run (Codex 62bbf35 029: tilted boxes opened black joints and
					# stepped tops): the joints' points shared along the street - the face at the street's
					# edge, the top on the bank's top ground, the back at the bank's far side - and whole
					# end faces; the coping a continuous strip on its front edge. Collision per block.
					var front := PackedVector3Array()
					var back := PackedVector3Array()
					var tops := PackedFloat32Array()
					var lows := PackedFloat32Array()
					for k in range(i, j + 1):
						var t := minf(k * STREET_STEP, run)
						var q := _along(pts, cum, t)
						var dir := (_along(pts, cum, minf(t + 0.5, run)) - _along(pts, cum, maxf(t - 0.5, 0.0))).normalized()
						var across: Vector2 = Vector2(-dir.y, dir.x) * sx
						var top: float = maxf(float(samples[maxi(k - 1, i)][4]), float(samples[mini(k, j - 1)][4]))
						var f2: Vector2 = q + across * edge
						var b2: Vector2 = q + across * (edge + STREET_BLEND)
						front.append(Vector3(f2.x, 0, f2.y))
						back.append(Vector3(b2.x, 0, b2.y))
						# 0.15 over the bank's highest ground: the top never shares the snow's plane (Codex
						# 24159a5 031: the ground showed through it as a flat pale face)
						tops.append(top + LANE_WALL_PROUD)
						lows.append(float(_street_at(si, q)[1]) - 1.5)
					_wall_strip(book, node, front, back, tops, lows, "masonry")
					# the coping: 0.34 deep on the front edge, 0.12 over the top
					var lip_b := PackedVector3Array()
					var lip_t := PackedFloat32Array()
					var lip_l := PackedFloat32Array()
					for k in front.size():
						lip_b.append(front[k] + (back[k] - front[k]).normalized() * 0.34)
						lip_t.append(tops[k] + 0.08)
						lip_l.append(tops[k] - 0.04)
					var lip_f := PackedVector3Array()
					for k in front.size():
						lip_f.append(front[k] - (back[k] - front[k]).normalized() * 0.03)
					_wall_strip(book, node, lip_f, lip_b, lip_t, lip_l, "tread")
					for k in range(i, j):
						var a2: Array = samples[k]
						var t0: float = tops[k - i]
						var t1: float = tops[k - i + 1]
						var top_y := (t0 + t1) * 0.5
						var bottom_y := minf(float(a2[3]), minf(t0, t1)) - 1.5
						var dir2: Vector2 = a2[1]
						var turn := Basis(Vector3.UP, atan2(dir2.x, dir2.y)) * Basis(Vector3.RIGHT, -atan((t1 - t0) / STREET_STEP))
						var c: Vector2 = a2[0]
						book._stair_collider(node, Vector3(c.x, (top_y + bottom_y) * 0.5, c.y), Vector3(STREET_BLEND, top_y - bottom_y, STREET_STEP + 0.02), turn)
						count += 1
				i = j
	print("SNOW_LANE_WALLS blocks=%d" % count)


## Terrace walls (owner 14 Oct "chopped slopes"; slope census 15 Oct: the straight 45-60 deg banks of
## the city were the book's pads - the middle terrace and the academy shelf - levelled in build.py with a
## 4 m margin, a 4-8 m drop over it, houses right under). Along a snow pad's edge, where the ground
## falls more than PAD_WALL_MIN over its margin, a stone retaining wall at the bank's foot holds the
## terrace: its face at the margin's outer side, its top over the terrace's edge, the bank inside it.
## Not where a street, a door stair, a flight or a house is within the bank (they keep their ground).
const PAD_WALL_MIN := 0.8
const PAD_WALL_RUN := 3

func build_pad_walls(book: Node3D, ground: Callable, layout: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "SnowPadWalls"
	book.add_child(node)
	var count := 0
	for pad in layout.get("book_pads", []):
		if not str(pad.id).begins_with("snow_"):
			continue
		var poly := PackedVector2Array()
		for q in pad.poly:
			poly.append(Vector2(float(q[0]) - HALF, float(q[1]) - HALF))
		var centre := Vector2.ZERO
		for q in poly:
			centre += q
		centre /= poly.size()
		var margin: float = float(pad.get("margin", 4))
		for e in poly.size():
			var a: Vector2 = poly[e]
			var b: Vector2 = poly[(e + 1) % poly.size()]
			var dir := (b - a).normalized()
			var out := Vector2(-dir.y, dir.x)
			if out.dot((a + b) * 0.5 - centre) < 0.0:
				out = -out
			var n := int(floor(a.distance_to(b) / STREET_STEP))
			var samples: Array = []
			for i in n:
				var q: Vector2 = a + dir * (i + 0.5) * STREET_STEP
				var top := float(ground.call(q.x - out.x * 0.5, q.y - out.y * 0.5))
				var foot := float(ground.call(q.x + out.x * (margin + 0.4), q.y + out.y * (margin + 0.4)))
				var c: Vector2 = q + out * margin * 0.5
				var ok := top - foot >= PAD_WALL_MIN
				if ok:
					for si in _profiles.size():
						if float(_street_at(si, c)[0]) < float(_profiles[si][3]) + 0.3 + margin * 0.5 + 0.5:
							ok = false
					for lot in lots:
						if _wall_dist(lot, c) < margin * 0.5 + 0.5:
							ok = false
					for code in stoop_paths:
						var sp: PackedVector2Array = stoop_paths[code]
						for k in sp.size() - 1:
							if c.distance_to(Geometry2D.get_closest_point_to_segment(c, sp[k], sp[k + 1])) < STOOP_WIDTH * 0.5 + margin * 0.5 + 0.3:
								ok = false
					for tr in _treads:
						if c.distance_to(tr[0]) < float(tr[1]) + margin * 0.5 + 0.3:
							ok = false
				samples.append([top, foot] if ok else null)
			var i := 0
			while i < n:
				if samples[i] == null:
					i += 1
					continue
				var j := i
				while j < n and samples[j] != null:
					j += 1
				if j - i >= PAD_WALL_RUN:
					var front := PackedVector3Array()
					var back := PackedVector3Array()
					var tops := PackedFloat32Array()
					var lows := PackedFloat32Array()
					for k in range(i, j + 1):
						var q: Vector2 = a + dir * k * STREET_STEP
						var s0: Array = samples[maxi(k - 1, i)]
						var s1: Array = samples[mini(k, j - 1)]
						var f2: Vector2 = q + out * margin
						var b2: Vector2 = q - out * 0.3
						front.append(Vector3(f2.x, 0, f2.y))
						back.append(Vector3(b2.x, 0, b2.y))
						tops.append(maxf(float(s0[0]), float(s1[0])) + LANE_WALL_PROUD)
						lows.append(minf(float(s0[1]), float(s1[1])) - 1.5)
					_wall_strip(book, node, front, back, tops, lows, "masonry")
					var lip_f := PackedVector3Array()
					var lip_b := PackedVector3Array()
					var lip_t := PackedFloat32Array()
					var lip_l := PackedFloat32Array()
					for k in front.size():
						var inward := (back[k] - front[k]).normalized()
						lip_f.append(front[k] - inward * 0.03)
						lip_b.append(front[k] + inward * 0.34)
						lip_t.append(tops[k] + 0.08)
						lip_l.append(tops[k] - 0.04)
					_wall_strip(book, node, lip_f, lip_b, lip_t, lip_l, "tread")
					for k in range(i, j):
						var q0: Vector3 = (front[k - i] + back[k - i] + front[k - i + 1] + back[k - i + 1]) * 0.25
						var top_y := (tops[k - i] + tops[k - i + 1]) * 0.5
						var bottom_y := minf(lows[k - i], lows[k - i + 1])
						var turn := Basis(Vector3.UP, atan2(dir.x, dir.y))
						book._stair_collider(node, Vector3(q0.x, (top_y + bottom_y) * 0.5, q0.z), Vector3(margin + 0.3, top_y - bottom_y, STREET_STEP + 0.02), turn)
						count += 1
				i = j
	print("SNOW_PAD_WALLS blocks=%d" % count)


## A continuous prism along a polyline: at each point k its front and back points (y unused), the
## top and bottom heights; faces front, top, back, bottom and the two ends, normals outward.
func _wall_strip(book: Node3D, node: Node3D, front: PackedVector3Array, back: PackedVector3Array, tops: PackedFloat32Array, lows: PackedFloat32Array, colour: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := front.size()
	# outward: away from the middle of the segment the face belongs to
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3) -> void:
		var normal := (b - a).cross(d - a).normalized()
		if normal.dot((a + b + c + d) * 0.25 - inside) < 0.0:
			var tmp := b
			b = d
			d = tmp
			normal = -normal
		# Godot's front faces wind clockwise seen from outside
		for v in [a, c, b, a, d, c]:
			st.set_normal(normal)
			st.add_vertex(v)
	for k in n - 1:
		var ft0 := front[k] + Vector3(0, tops[k], 0)
		var ft1 := front[k + 1] + Vector3(0, tops[k + 1], 0)
		var fb0 := front[k] + Vector3(0, lows[k], 0)
		var fb1 := front[k + 1] + Vector3(0, lows[k + 1], 0)
		var bt0 := back[k] + Vector3(0, tops[k], 0)
		var bt1 := back[k + 1] + Vector3(0, tops[k + 1], 0)
		var bb0 := back[k] + Vector3(0, lows[k], 0)
		var bb1 := back[k + 1] + Vector3(0, lows[k + 1], 0)
		var mid := (ft0 + ft1 + fb0 + fb1 + bt0 + bt1 + bb0 + bb1) / 8.0
		quad.call(fb0, fb1, ft1, ft0, mid)
		quad.call(ft0, ft1, bt1, bt0, mid)
		quad.call(bb0, bt0, bt1, bb1, mid)
		quad.call(fb0, bb0, bb1, fb1, mid)
		if k == 0:
			quad.call(fb0, bb0, bt0, ft0, mid)
		if k == n - 2:
			quad.call(fb1, bb1, bt1, ft1, mid)
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = book._material(colour)
	mesh.visibility_range_end = 300.0
	node.add_child(mesh)


## A yard's paving: PAVE m slabs with JOINT joints over the rect (u, v round the lot's centre along
## its s, f), outside the walls, their tops at `top`, as one mesh.
func _paving(book: Node3D, node: Node3D, lot: Dictionary, u0: float, u1: float, v0: float, v1: float, top: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	var nu := maxi(1, int(round((u1 - u0) / PAVE)))
	var nv := maxi(1, int(round((v1 - v0) / PAVE)))
	var su := (u1 - u0) / nu
	var sv := (v1 - v0) / nv
	for i in nu:
		for j in nv:
			var cu := u0 + su * (i + 0.5)
			var cv := v0 + sv * (j + 0.5)
			if absf(cu) < lot.w * 0.5 and absf(cv) < lot.d * 0.5:
				continue
			var hu := (su - JOINT) * 0.5
			var hv := (sv - JOINT) * 0.5
			var c: Vector2 = lot.c + lot.s * cu + lot.f * cv
			var corners: Array = []
			for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var q: Vector2 = c + lot.s * (k.x * hu) + lot.f * (k.y * hv)
				corners.append(q)
			var t: Array = corners.map(func(q): return Vector3(q.x, top, q.y))
			var b: Array = corners.map(func(q): return Vector3(q.x, top - 0.06, q.y))
			_box_faces(st, t, b)
			count += 1
	if count == 0:
		return
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = book._material("tread")
	mesh.visibility_range_end = 300.0
	node.add_child(mesh)


## The six faces of a box from its four top and four bottom corners (same order), normals outward,
## clockwise seen from outside (Godot's front faces).
func _box_faces(st: SurfaceTool, t: Array, b: Array) -> void:
	var mid: Vector3 = Vector3.ZERO
	for v in t + b:
		mid += v
	mid /= 8.0
	var faces: Array = [[t[0], t[1], t[2], t[3]], [b[0], b[3], b[2], b[1]]]
	for k in 4:
		var j := (k + 1) % 4
		faces.append([b[k], b[j], t[j], t[k]])
	for f in faces:
		var a: Vector3 = f[0]
		var bb: Vector3 = f[1]
		var c: Vector3 = f[2]
		var d: Vector3 = f[3]
		var normal := (bb - a).cross(d - a).normalized()
		if normal.dot((a + bb + c + d) * 0.25 - mid) < 0.0:
			var tmp := bb
			bb = d
			d = tmp
			normal = -normal
		for v in [a, c, bb, a, d, c]:
			st.set_normal(normal)
			st.add_vertex(v)


## A house's plinth past its walls on each side [left, right, back, front]: PLINTH_LEDGE; a shack's
## its yard at the sides and back (FLAT_SHACK), each side cut back by YARD_STEP until it stays
## YARD_CLEAR clear of every street's edge.
func _yard(lot: Dictionary) -> Array:
	if not lot.shack:
		return [PLINTH_LEDGE, PLINTH_LEDGE, PLINTH_LEDGE, PLINTH_LEDGE]
	# the door's side keeps the narrow ledge: its stair comes down there and the street lies at the
	# floor's level along the front (grade_streets)
	var out := [FLAT_SHACK, FLAT_SHACK, FLAT_SHACK, PLINTH_LEDGE]
	for side in 4:
		while float(out[side]) > PLINTH_LEDGE:
			var e: float = out[side]
			var pts: Array = []
			for k in 5:
				var t := lerpf(-0.5, 0.5, k / 4.0)
				match side:
					0: pts.append(lot.c + lot.s * (-lot.w * 0.5 - e) + lot.f * (t * (lot.d + 2.0 * e)))
					1: pts.append(lot.c + lot.s * (lot.w * 0.5 + e) + lot.f * (t * (lot.d + 2.0 * e)))
					2: pts.append(lot.c + lot.f * (-lot.d * 0.5 - e) + lot.s * (t * (lot.w + 2.0 * e)))
					3: pts.append(lot.c + lot.f * (lot.d * 0.5 + e) + lot.s * (t * (lot.w + 2.0 * e)))
			var clear := true
			for q: Vector2 in pts:
				for si in _profiles.size():
					if float(_street_at(si, q)[0]) < float(_profiles[si][3]) + YARD_CLEAR:
						clear = false
				# nor over another house, its sides or its door's approach (Codex: vs11's yard stood
				# over vs2's door 1.07 m above its floor)
				for other in lots:
					if other.code == lot.code:
						continue
					var d: Vector2 = q - other.c
					var u := absf(d.dot(other.s))
					var v := d.dot(other.f)
					if u < other.w * 0.5 + YARD_CLEAR and v > -other.d * 0.5 - YARD_CLEAR and v < other.d * 0.5 + YARD_DOOR:
						clear = false
			if clear:
				break
			out[side] = maxf(e - YARD_STEP, PLINTH_LEDGE)
			if is_equal_approx(float(out[side]), PLINTH_LEDGE):
				break
	return out


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
		var yard := _yard(lot)
		lot["yard"] = yard
		# the rect: -u (left), +u, -v (back), +v (front) past the walls
		var u0: float = -lot.w * 0.5 - yard[0]
		var u1: float = lot.w * 0.5 + yard[1]
		var v0: float = -lot.d * 0.5 - yard[2]
		var v1: float = lot.d * 0.5 + yard[3]
		var low := INF
		for i in 13:
			for j in 13:
				var p: Vector2 = lot.c + lot.s * lerpf(u0, u1, i / 12.0) + lot.f * lerpf(v0, v1, j / 12.0)
				low = minf(low, float(ground.call(p.x, p.y)))
		if lot.level - low <= PLINTH_HANG:
			continue
		# its foot: the lowest ground up to 1 m round it, 0.8 m under that (Codex 27c3f38 015: a high
		# plinth's lower edge showed over the snow falling away past its corner)
		var foot := low
		for i in 9:
			for j in 9:
				var p: Vector2 = lot.c + lot.s * lerpf(u0 - 1.0, u1 + 1.0, i / 8.0) + lot.f * lerpf(v0 - 1.0, v1 + 1.0, j / 8.0)
				foot = minf(foot, float(ground.call(p.x, p.y)))
		var top: float = lot.level - 0.02
		var bottom := foot - 0.8
		var yaw := rad_to_deg(atan2(lot.f.x, lot.f.y))
		var mid: Vector2 = lot.c + lot.s * ((u0 + u1) * 0.5) + lot.f * ((v0 + v1) * 0.5)
		book._stair_block(node, Vector3(mid.x, (top + bottom) * 0.5, mid.y), Vector3(u1 - u0, top - bottom, v1 - v0), yaw, "masonry")
		if lot.shack:
			# the yard's dressed edge
			book._stair_block(node, Vector3(mid.x, top - 0.05, mid.y), Vector3(u1 - u0 + 0.06, 0.12, v1 - v0 + 0.06), yaw, "tread", false)
			# paved: dressed slabs with open joints, one mesh a yard (Codex 925dd80 031: the platform's top
			# read as a flat grey-green face)
			_paving(book, node, lot, u0, u1, v0, v1, top + 0.02)
		count += 1
	# Stone steps down from a door whose front falls away. Straight out where the ground is met within
	# STOOP_OUT; otherwise a landing at the door and a stair down along the facade, towards the lower
	# side (Codex 0208cfd: straight stairs ran 5-6 m into the slum's lane and closed it - the lane
	# walk stopped at vs12's). Each stair's walking line is kept in stoop_paths (its own test).
	var steps := 0
	for lot in lots:
		if CUTS.has(lot.code):
			continue
		var out: float = lot.d * 0.5 + float(lot.get("yard", [0, 0, 0, PLINTH_LEDGE])[3])
		var door: Vector2 = lot.c + lot.f * (lot.d * 0.5 + 0.3)
		var level: float = lot.level - 0.02
		var straight := _steps(book, node, ground, lot.c + lot.f * out, lot.f, lot.s, STOOP_WIDTH, level, STOOP_OUT, false)
		if straight[1]:
			if straight[0] > 0:
				var placed := _steps(book, node, ground, lot.c + lot.f * out, lot.f, lot.s, STOOP_WIDTH, level, STOOP_OUT, true)
				steps += int(placed[0])
				stoop_paths[lot.key] = PackedVector2Array([door, placed[2]])
			continue
		# the landing before the door, then along the facade
		var landing: Vector2 = lot.c + lot.f * (out + LANDING * 0.5)
		var yaw := rad_to_deg(atan2(lot.f.x, lot.f.y))
		var low := INF
		for a in [-0.5, 0.0, 0.5]:
			for q in [-0.5, 0.0, 0.5]:
				var e: Vector2 = landing + lot.f * (LANDING * a) + lot.s * (STOOP_WIDTH * q)
				low = minf(low, float(ground.call(e.x, e.y)))
		if low < level - 0.05:
			book._stair_block(node, Vector3(landing.x, (level + low - 1.2) * 0.5, landing.y), Vector3(STOOP_WIDTH, level - low + 1.2, LANDING), yaw, "masonry")
			steps += 1
		var probe := 3.0
		var left := float(ground.call((landing - lot.s * probe).x, (landing - lot.s * probe).y))
		var right := float(ground.call((landing + lot.s * probe).x, (landing + lot.s * probe).y))
		var side: Vector2 = lot.s if right < left else -lot.s
		var start: Vector2 = landing + side * (STOOP_WIDTH * 0.5)
		var flight := _steps(book, node, ground, start, side, lot.f, LANDING, level, STOOP_MAX, true)
		steps += int(flight[0])
		stoop_paths[lot.key] = PackedVector2Array([door, landing, flight[2]])
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
