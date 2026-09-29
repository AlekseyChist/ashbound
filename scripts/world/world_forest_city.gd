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
	_civic_buildings()
	_water_wheels()
	_outer_buildings()
	_wheat_field()
	print("FOREST_CITY stakes=%d towers=%d houses=%d wheat=%d wheels=%d" % [stake_count, tower_count, house_count, wheat_count, wheels.size()])


# --- Step 2: the town hall and the barracks (Codex civic-concept-v1, owner-approved) ---------------

## Enterable halls from art/blender/forest-city-v1 (built by the village kit, entry turned to +z).
const CIVIC := {
	# art/blender/forest_city_halls.py: the door is in the body's front wall; the steps start at the
	# front of the gallery / porch (stair_front) and climb the plinth over stair_run.
	"town_hall": {"id": "R01", "scene_path": "res://assets/buildings/forest-city-v1/r01.glb", "width": 24.0, "depth": 12.0,
		"entry": Vector3(0, 1.0, 3.6), "floor_height": 1.0, "stair_front": 6.0, "stair_run": 2.0, "own_lights": true,
		"title_key": "WORLD_FOREST_CITY_TOWN_HALL"},
	"barracks": {"id": "K01", "scene_path": "res://assets/buildings/forest-city-v1/k01.glb", "width": 20.0, "depth": 10.0,
		"entry": Vector3(2.5, 0.8, 5.0), "floor_height": 0.8, "stair_run": 1.8, "own_lights": true,
		"title_key": "WORLD_FOREST_CITY_BARRACKS"},
}
const Hall = preload("res://scripts/world/village_building.gd")
const Entry = preload("res://scripts/world/closed_house_entry.gd")
var halls: Array[Node3D] = []

func _civic_buildings() -> void:
	var plaza := Vector2(float(plan.plaza.center[0]), float(plan.plaza.center[1]))
	for b in plan.buildings:
		if not CIVIC.has(str(b.kind)):
			continue
		var record: Dictionary = CIVIC[str(b.kind)].duplicate()
		record.position = Vector3.ZERO
		record.entry_width = 2.4
		var map := Vector2(float(b.map[0]), float(b.map[1]))
		var at := ground_at(map)
		# The entry (+z) faces the plaza.
		var to_plaza := plaza - map
		var yaw := atan2(to_plaza.x, to_plaza.y)
		var basis := Basis(Vector3.UP, yaw)
		var high := -INF
		var low := INF
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var corner: Vector3 = at + basis * Vector3(c.x * float(record.width) * 0.5, 0, c.y * float(record.depth) * 0.5)
			var g: float = world.world_ground(corner.x, corner.z)
			high = maxf(high, g)
			low = minf(low, g)
		var hall := Hall.new()
		add_child(hall)
		hall.build(record)
		var rect := _extent(hall.model)
		var spot := _clear_spot(Vector2(at.x, at.z), basis, rect)
		# Squeezed between the road and the palisade the pushes can see-saw and give up still
		# inside a keep-out (K01, Codex 085): then the nearest clear spot on rings round the plan
		# point, the entry still turned to the plaza.
		if float(_intrusion(spot, basis, rect)[0]) > 0.0:
			spot = _ring_spot(Vector2(at.x, at.z), basis, rect, spot)
		if float(_intrusion(spot, basis, rect)[0]) > 0.0:
			push_warning("FOREST_CITY %s still %.2f m into a road, the palisade or a neighbour" % [record.id, float(_intrusion(spot, basis, rect)[0])])
		if spot.distance_to(Vector2(at.x, at.z)) > 0.05:
			print("FOREST_CITY_CLEARED %s moved %.1f m" % [record.id, spot.distance_to(Vector2(at.x, at.z))])
			at = Vector3(spot.x, 0, spot.y)
			high = -INF
			low = INF
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var corner: Vector3 = at + basis * Vector3(c.x * float(record.width) * 0.5, 0, c.y * float(record.depth) * 0.5)
				var g: float = world.world_ground(corner.x, corner.z)
				high = maxf(high, g)
				low = minf(low, g)
		hall.position = Vector3(at.x, high, at.z)
		hall.rotation.y = yaw
		# The model's plinth reaches 1.2 m down; a steeper site gets a stone pad under it.
		if high - low > 1.0:
			_box(hall, Vector3(0, -(high - low) * 0.5 + 0.02, 0), Vector3(float(record.width) + 0.4, high - low + 0.1, float(record.depth) + 0.4), _stone())
		_workshop_skin(hall.model)
		preload("res://scripts/world/civic_dressing.gd").new().dress(hall, str(record.id), float(record.floor_height))
		halls.append(hall)
		_placed.append([Vector2(at.x, at.z), basis, rect])


# --- Step 4 (first part): the suburbs, the field, the water wheels ----------------------------------

## The village's log cabins stand in for the suburbs' houses: closed (no furniture, one box to collide
## with), their door towards the nearest road. The workshops use them too until their own models
## (Codex's concept sheets) are built - then they get interiors.
## The closed shells (forest_village_kit.py --closed): no furniture or ceilings, shutters shut.
const KIT := {
	"H01": {"path": "res://assets/buildings/forest-village-v1/h01_closed.glb", "size": Vector3(6, 3.2, 8)},
	"W01": {"path": "res://assets/buildings/forest-village-v1/w01_closed.glb", "size": Vector3(7, 3.2, 9)},
	"B01": {"path": "res://assets/buildings/forest-village-v1/b01_closed.glb", "size": Vector3(8, 3.7, 10)},
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
		elif kind == "water_mill" or kind == "sawmill":
			continue
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
	var house: Node3D = (load(KIT[kit].path) as PackedScene).instantiate()
	# The whole model - porch, ramp, roof overhang - not the kit's nominal walls.
	# The stone skirt reaches 0.1 m past the model; the clearance keeps it in the footprint too.
	var rect := _extent(house).grow(0.15)
	# The entry apron (_entry_wedge) may run up to 1.5 m out in front (+z): it keeps clear too.
	rect.size.y += 1.5
	# Placement audit (Codex 023, owner 28 Sep): the turned footprint keeps off the road bed and its
	# shoulder and off the river - pushed straight away from what it touches, never across it.
	var pushed := _clear_spot(Vector2(at.x, at.z), basis, rect)
	var road_after := _nearest_road(pushed, 40.0)
	if road_after != Vector2.INF and pushed.distance_to(Vector2(at.x, at.z)) > 0.05:
		yaw = atan2(road_after.x - pushed.x, road_after.y - pushed.y)
		basis = Basis(Vector3.UP, yaw)
		pushed = _clear_spot(pushed, basis, rect)
	var left: float = _intrusion(pushed, basis, rect)[0]
	if left > 0.0:
		# Wedged between two keep-outs (a road and the river, a neighbour): the nearest free spot on
		# rings round the plan point, each turned to its own road.
		var found := false
		for ring in range(1, 31):
			var count := ring * 6
			for k in count:
				var angle := TAU * k / count
				var cand := Vector2(float(b.map[0]) - float(world.HALF), float(b.map[1]) - float(world.HALF)) + Vector2(cos(angle), sin(angle)) * ring
				var cand_road := _nearest_road(cand, 40.0)
				var cand_basis := basis if cand_road == Vector2.INF else Basis(Vector3.UP, atan2(cand_road.x - cand.x, cand_road.y - cand.y))
				if float(_intrusion(cand, cand_basis, rect)[0]) <= 0.0:
					pushed = cand
					basis = cand_basis
					yaw = basis.get_euler().y
					found = true
					break
			if found:
				break
		left = _intrusion(pushed, basis, rect)[0]
	if left > 0.0:
		push_warning("FOREST_CITY %s %s still %.2f m into a road, the river or a neighbour" % [str(b.kind), str(b.map), left])
	at = Vector3(pushed.x, world.world_ground(pushed.x, pushed.y), pushed.y)
	# What stands on the ground - walls, porch, steps, ramp - not the roof overhang.
	var base := _extent(house, 0.6)
	var high := -INF
	var low := INF
	for gx in 5:
		for gz in 5:
			var local := base.position + base.size * Vector2(gx / 4.0, gz / 4.0)
			var corner: Vector3 = at + basis * Vector3(local.x, 0, local.y)
			# The real (shore-refined) ground: on a river bank the base grid lies higher than the mesh.
			var g: float = world.shore_ground(corner.x, corner.z)
			# The floor sits on the walls' ground; the porch and the ramp only reach down to theirs.
			if absf(local.x) <= size.x * 0.5 + 0.2 and absf(local.y) <= size.z * 0.5 + 0.2:
				high = maxf(high, g)
			low = minf(low, g)
	# A house far above the ground at its door is set lower, its back into the slope: the apron down
	# from the steps then stays short (at most 0.6 m of drop, 1.5 m long).
	var door_ground: float = world.shore_ground((at + basis * Vector3(0, 0, size.z * 0.5 + 1.5)).x, (at + basis * Vector3(0, 0, size.z * 0.5 + 1.5)).z)
	if high - door_ground > 0.6:
		high = door_ground + 0.6
	house.name = "%s_%s_%d" % [str(b.kind), kit, house_count]
	house.position = Vector3(at.x, high, at.z)
	house.rotation.y = yaw
	_placed.append([Vector2(at.x, at.z), basis, rect])
	# A trodden yard round the house: no grass on its steps, ramp or porch.
	var mid: Vector2 = rect.get_center()
	var yard: Vector3 = at + basis * Vector3(mid.x, 0, mid.y)
	yards.append(Vector3(yard.x, yard.z, rect.size.length() * 0.5 + 0.5))
	house.set_meta("cleared_m", pushed.distance_to(Vector2(float(b.map[0]) - float(world.HALF), float(b.map[1]) - float(world.HALF))))
	# A closed house (owner 28 Sep): no interior - furniture and ceilings go - and the shell is solid
	# by its real geometry, the porch and its steps included; the shut door keeps the hero out.
	for node in house.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var role := str(mesh.get_meta("extras", {}).get("part_role", ""))
		if role == "furniture" or role == "ceiling" or role == "interior":
			mesh.queue_free()
			continue
		mesh.visibility_range_end = VISIBLE
		# Steps and the barn ramp are walked on a smooth wedge (below), not their risers.
		if str(mesh.get_meta("extras", {}).get("item_id", "")) == "entry_steps":
			continue
		var body := StaticBody3D.new()
		body.set_meta("footstep_surface", "stone" if role == "foundation" else "wood")
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = mesh.mesh.create_trimesh_shape()
		body.add_child(shape)
		mesh.add_child(body)
	add_child(house)
	# On a slope: compact stone supports under the body, the steps and the canopy posts, and the
	# steps walked on down to the ground (closed_house_entry, shared with the village neighbours).
	var ground := func(p: Vector3) -> float: return world.shore_ground(p.x, p.z)
	Entry.add(house, ground, _stone(), Entry.skirt(house, ground, _stone()))
	house_count += 1


func _city_centre() -> Vector2:
	return Vector2(float(plan.palisade.center[0]) - float(world.HALF), float(plan.palisade.center[1]) - float(world.HALF))

const ROAD_SHOULDER := 1.5
const HOUSE_GAP := 2.0
## Between the stakes and the widest part of a building (its roof): a walkway round its back.
const PALISADE_CLEAR := 1.2
## A tower's roof reaches (TOWER + 1) * 0.72 / sqrt(2) from its middle.
const TOWER_REACH := 2.65
## Grass-free circles (x, z, radius) round the closed houses, read by world.gd's grass obstacles.
var yards: Array[Vector3] = []
var _placed: Array = []
const RIVER_BANK := 1.5
## Segments of the roads and rivers near the city: [a, b, keep-off distance from the axis].
var _keepout: Array = []

func _keepout_segments() -> Array:
	if not _keepout.is_empty():
		return _keepout
	var centre := Vector2(float(plan.palisade.center[0]) - float(world.HALF), float(plan.palisade.center[1]) - float(world.HALF))
	for road in world.world_layout.roads:
		var pts: Array = road.world_points
		for i in range(pts.size() - 1):
			var a := Vector2(float(pts[i][0]), float(pts[i][2]))
			var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][2]))
			if a.distance_to(centre) < 220.0:
				_keepout.append([a, b, float(road.get("width_m", 6.0)) * 0.5 + ROAD_SHOULDER])
	for river in world.world_layout.rivers:
		var pts: Array = river.world_points
		for i in range(pts.size() - 1):
			var a := Vector2(float(pts[i][0]), float(pts[i][2]))
			var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][2]))
			if a.distance_to(centre) < 220.0:
				_keepout.append([a, b, float(river.world_widths[i]) * 0.5 + RIVER_BANK])
	return _keepout

## The model's footprint in its own x/z (every mesh's box through the node chain; furniture and
## ceilings, which the closed houses drop, left out).
func _extent(model: Node3D, below := INF) -> Rect2:
	var rect := Rect2()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var role := str(mesh.get_meta("extras", {}).get("part_role", ""))
		if role == "furniture" or role == "ceiling" or mesh.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mesh
		while n != model and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var box := mesh.get_aabb()
		if below != INF and (xf * box).position.y > below:
			continue
		for i in 8:
			var p: Vector3 = xf * box.get_endpoint(i)
			if first:
				rect = Rect2(Vector2(p.x, p.z), Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(Vector2(p.x, p.z))
	return rect

## Where the footprint (`rect` in the model's x/z about `at`, turned by `basis`) is clear of every
## keep-out segment and every placed building: the worst intrusion pushes it away, 0.5 m a step.
func _clear_spot(at: Vector2, basis: Basis, rect: Rect2) -> Vector2:
	for step in 80:
		var hit := _intrusion(at, basis, rect)
		if float(hit[0]) <= 0.0:
			return at
		at += (hit[1] as Vector2) * minf(float(hit[0]) + 0.1, 0.5)
	return at

## The nearest spot on rings (1 m apart, up to 30 m) round `origin` where the footprint, turned by
## `basis`, is clear of every keep-out; `fallback` when there is none.
func _ring_spot(origin: Vector2, basis: Basis, rect: Rect2, fallback: Vector2) -> Vector2:
	for ring in range(1, 31):
		var count := ring * 6
		for k in count:
			var angle := TAU * k / count
			var cand := origin + Vector2(cos(angle), sin(angle)) * ring
			if float(_intrusion(cand, basis, rect)[0]) <= 0.0:
				return cand
	return fallback

## [worst intrusion in metres (<= 0 when clear), the direction to push]: the footprint sampled every
## 1.5 m (its edges and corners included) against the keep-out segments and the placed buildings.
func _intrusion(at: Vector2, basis: Basis, rect: Rect2) -> Array:
	var ax := Vector2(basis.x.x, basis.x.z)
	var az := Vector2(basis.z.x, basis.z.z)
	# Only what can touch the footprint: one distance per segment and building, not one per sample.
	var centre := at + ax * rect.get_center().x + az * rect.get_center().y
	var reach := rect.size.length() * 0.5
	var segments: Array = []
	for seg in _keepout_segments():
		if centre.distance_to(Geometry2D.get_closest_point_to_segment(centre, seg[0], seg[1])) < reach + float(seg[2]):
			segments.append(seg)
	var neighbours: Array = []
	for other in _placed:
		if centre.distance_to(other[0]) < reach + (other[2] as Rect2).size.length() + HOUSE_GAP:
			neighbours.append(other)
	var ring_centre := Vector2(float(plan.palisade.center[0]) - float(world.HALF), float(plan.palisade.center[1]) - float(world.HALF))
	var ring_radius := float(plan.palisade.radius)
	var inside := at.distance_to(ring_centre) < ring_radius
	# The inside every 1.5 m (a road or a neighbour crossing it), the outline every 0.25 m: a 1.5 m
	# step let a corner between two samples reach 0.19 m into a road's shoulder (Codex 085).
	var nx := maxi(3, ceili(rect.size.x / 1.5) + 1)
	var nz := maxi(3, ceili(rect.size.y / 1.5) + 1)
	var samples: Array[Vector2] = []
	for gx in nx:
		for gz in nz:
			samples.append(rect.position + rect.size * Vector2(float(gx) / (nx - 1), float(gz) / (nz - 1)))
	var ex := maxi(2, ceili(rect.size.x / 0.25))
	var ez := maxi(2, ceili(rect.size.y / 0.25))
	for i in ex + 1:
		var fx := float(i) / ex
		samples.append(rect.position + rect.size * Vector2(fx, 0.0))
		samples.append(rect.position + rect.size * Vector2(fx, 1.0))
	for i in ez + 1:
		var fz := float(i) / ez
		samples.append(rect.position + rect.size * Vector2(0.0, fz))
		samples.append(rect.position + rect.size * Vector2(1.0, fz))
	var worst := -INF
	var away := Vector2.ZERO
	for local in samples:
		var q := at + ax * local.x + az * local.y
		for seg in segments:
			var near := Geometry2D.get_closest_point_to_segment(q, seg[0], seg[1])
			var into: float = float(seg[2]) - q.distance_to(near)
			if into > worst:
				worst = into
				# Across the segment, to the side the house's centre is on (outwards if on it).
				var dir: Vector2 = (seg[1] - seg[0]).normalized()
				var normal := Vector2(-dir.y, dir.x)
				var side := normal.dot(at - seg[0])
				if absf(side) < 0.3:
					side = normal.dot(at - _city_centre())
				away = normal * signf(side if side != 0.0 else 1.0)
		# The palisade ring (Codex 080: the barracks, pushed off the road, ran its back corner
		# into it): the whole footprint, roof overhang included, keeps PALISADE_CLEAR off the
		# stakes on its own side - a walkway round the back of every building.
		var from_ring := q.distance_to(ring_centre)
		var ring_into: float = (from_ring - (ring_radius - STAKE_RADIUS - PALISADE_CLEAR)) if inside \
			else ((ring_radius + STAKE_RADIUS + PALISADE_CLEAR) - from_ring)
		if ring_into > worst:
			worst = ring_into
			away = (ring_centre - q).normalized() if inside else (q - ring_centre).normalized()
		# Other buildings: [origin, basis, footprint rect], kept HOUSE_GAP apart.
		for other in neighbours:
			var ob: Basis = other[1]
			var orect: Rect2 = other[2]
			var d: Vector2 = q - other[0]
			var l := Vector2(d.dot(Vector2(ob.x.x, ob.x.z)), d.dot(Vector2(ob.z.x, ob.z.z)))
			var grown := orect.grow(HOUSE_GAP)
			if grown.has_point(l):
				var into := minf(minf(l.x - grown.position.x, grown.end.x - l.x), minf(l.y - grown.position.y, grown.end.y - l.y))
				if into > worst:
					worst = into
					var c: Vector2 = orect.get_center()
					away = (at - (other[0] + Vector2(ob.x.x, ob.x.z) * c.x + Vector2(ob.z.x, ob.z.z) * c.y)).normalized()
	return [worst, away]


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

func _field_blocked(q: Vector2, segments: Array) -> bool:
	for seg in segments:
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q, seg[0], seg[1])) < float(seg[2]):
			return true
	for other in _placed:
		var ob: Basis = other[1]
		var d: Vector2 = q - other[0]
		if (other[2] as Rect2).grow(1.0).has_point(Vector2(d.dot(Vector2(ob.x.x, ob.x.z)), d.dot(Vector2(ob.z.x, ob.z.z)))):
			return true
	return false

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
	# The field keeps the same shoulder off the roads and the river as the houses, and off buildings.
	var box := Rect2(lo - Vector2(float(world.HALF), float(world.HALF)), hi - lo).grow(12.0)
	var near_segments: Array = []
	for seg in _keepout_segments():
		if box.intersects(Rect2(seg[0], Vector2.ZERO).expand(seg[1]).grow(float(seg[2]))):
			near_segments.append(seg)
	var z := lo.y
	while z <= hi.y:
		var x := lo.x
		while x <= hi.x:
			var m := Vector2(x + rng.randf_range(-0.3, 0.3), z + rng.randf_range(-0.3, 0.3))
			if Geometry2D.is_point_in_polygon(m, polygon) and not _field_blocked(m - Vector2(float(world.HALF), float(world.HALF)), near_segments):
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


## WATER WORKSHOPS: the plan's water_wheels are [water mill, sawmill]; each is found its nearest river
## point and flow and built there as one workshop (below).
var wheels: Array[Node3D] = []
var wheel_speeds: Array[float] = []
const WATER_WORKS := ["water_mill", "sawmill"]

func _water_wheels() -> void:
	for w in plan.water_wheels.size():
		var p: Array = plan.water_wheels[w]
		var here := Vector2(float(p[0]) - float(world.HALF), float(p[1]) - float(world.HALF))
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
		# n: across the flow, towards the side the plan puts the building on.
		var n := Vector3(-flow.z, 0, flow.x)
		if n.dot(Vector3(here.x - axis.x, 0, here.y - axis.z)) < 0.0:
			n = -n
		_workshop(WORKSHOPS[WATER_WORKS[w]], axis, flow, n, water, half)


## WATER-WORKSHOPS-02 (owner 28 Sep: "build new buildings, don't bolt a wheel onto a house"): each
## workshop is one model from art/blender/water_workshops.py - body, wheel bay, axle, pier, frame, dry
## entry in one frame. Local +x is the river side, the entry +z; the origin is the land-side ground,
## the design water `water` below it. The wheel turns on its `*_wheel_hinge` about local x.
const WORKSHOPS := {
	"water_mill": {"id": "M01", "name": "WaterMill", "scene_path": "res://assets/buildings/forest-city-v1/m01.glb",
		"width": 9.0, "depth": 11.0, "entry": Vector3(0, 1.05, 5.5), "floor_height": 1.05, "lantern_y": 3.5, "stair_run": 2.2,
		"title_key": "WORLD_FOREST_CITY_WATER_MILL", "water": -0.5, "river_wall": 4.5, "door": true},
	# The sawmill is an open shed: walked into over the log skids, no door to offer.
	"sawmill": {"id": "S01", "name": "Sawmill", "scene_path": "res://assets/buildings/forest-city-v1/s01.glb",
		"width": 8.0, "depth": 12.0, "entry": Vector3(-0.3, 0.6, 6.0), "floor_height": 0.6, "lantern_y": 3.1,
		"title_key": "WORLD_FOREST_CITY_SAWMILL", "water": -0.5, "river_wall": 4.0, "door": false},
}
## Enterable workshops without a door (the sawmill): kept apart from `halls`, which get a door offer.
var sheds: Array[Node3D] = []

func _workshop(spec: Dictionary, axis: Vector3, flow: Vector3, n: Vector3, water: float, half: float) -> void:
	var x_b := -n
	var z_b := x_b.cross(Vector3.UP)
	var basis := Basis(x_b, Vector3.UP, z_b)
	# The river wall stands 0.3 m into the water: the wheel, the pier and the race are in the river.
	var origin := Vector3(axis.x, water - float(spec.water), axis.z) + n * (half + float(spec.river_wall) - 0.3)
	var record := spec.duplicate()
	record.position = Vector3.ZERO
	record.entry_width = 2.0
	var hall := Hall.new()
	add_child(hall)
	hall.build(record)
	hall.name = str(spec.name)
	_workshop_skin(hall.model)
	hall.transform = Transform3D(basis, origin)
	# The whole unit with its wheel bay and porch keeps the houses off.
	_placed.append([Vector2(origin.x, origin.z), basis, _extent(hall.model)])
	if spec.door:
		halls.append(hall)
	else:
		sheds.append(hall)
	house_count += 1
	var land := INF
	var high := -INF
	for c in [Vector2(-1, -1), Vector2(-1, 1), Vector2(0, 1), Vector2(0, -1)]:
		var corner: Vector3 = origin + basis * Vector3(c.x * float(spec.width) * 0.5, 0, c.y * float(spec.depth) * 0.5)
		var g: float = world.shore_ground(corner.x, corner.z)
		land = minf(land, g)
		high = maxf(high, g)
	print("WORKSHOP %s origin=%s water=%.2f half=%.2f land=%.2f..%.2f (origin y %.2f)" % [spec.id, origin, water, half, land, high, origin.y])
	# Loose logs waiting outside lie on the real bank, each on its own.
	for node in hall.model.find_children("*logpile*", "MeshInstance3D", true, false):
		var log_mesh := node as MeshInstance3D
		var box := log_mesh.get_aabb()
		var centre: Vector3 = log_mesh.global_transform * box.get_center()
		var bottom: float = (log_mesh.global_transform * box.position).y
		log_mesh.global_position.y += float(world.shore_ground(centre.x, centre.z)) - 0.06 - bottom
	var hinge := hall.model.find_child("*_wheel_hinge", true, false) as Node3D
	if hinge:
		wheels.append(hinge)
		# The lower paddles go with the water: v(bottom) = -w R z_local.
		wheel_speeds.append(-0.5 * signf(z_b.dot(flow)))


## Codex's workshop finishes (local/previews/water-workshops-02/materials, 1K copies in
## assets/buildings/forest-city-v1/materials): the model's UVs are metres with V along the grain / the
## roof's fall line. Timber for logs and beams, shingles for the roofs, the CC0 stone for the base,
## planks for floors and doors.
const SKIN_DIR := "res://assets/buildings/forest-city-v1/materials/"
const STONE_MAPS := "res://assets/environment/village-house-materials-v1/stone_wall_02_%s_1k.jpg"
const JOINERY := "res://assets/environment/village-house-materials-v1/fine_grained_wood_%s_1k.jpg"
## Codex 090: a trial tint over the oak to take off its yellow (<= 1, no brightening).
var FURNITURE_TINT := Color(0.82, 0.87, 0.96)
const RUG_WEAVE := "res://assets/props/tavern-v1/rugs/fabric_pattern_05_nor_1k.jpg"
var _skins := {}

func _skin(kind: String) -> StandardMaterial3D:
	if _skins.has(kind):
		return _skins[kind]
	var m := StandardMaterial3D.new()
	m.roughness = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	match kind:
		"timber":
			m.albedo_texture = load(SKIN_DIR + "weathered_timber_1k.jpg")
			m.uv1_scale = Vector3(1.0 / 1.2, 1.0 / 1.6, 1)
		"shingles":
			m.albedo_texture = load(SKIN_DIR + "wood_shingles_1k.jpg")
			m.uv1_scale = Vector3(1.0 / 1.8, 1.0 / 1.8, 1)
		"furniture":
			# CIVIC-FURNITURE-01 V1 (owner-approved sheet): planed boards of Poly Haven Stained Pine
			# (CC0, 0.9 m tile) as they are - no multiplier over the PBR map.
			m.albedo_texture = load(SKIN_DIR + "oak_veneer_01_diff_1k.jpg")
			m.normal_enabled = true
			m.normal_texture = load(SKIN_DIR + "oak_veneer_01_nor_gl_1k.jpg")
			m.roughness_texture = load(SKIN_DIR + "oak_veneer_01_rough_1k.jpg")
			m.roughness = 1.0
			m.uv1_scale = Vector3(1.0 / 1.83, 1.0 / 1.83, 1)
			m.albedo_color = FURNITURE_TINT
		"wool", "linen":
			# The sheet's muted green wool (#515844) and unbleached linen (#AAA08A), a weave in the normal.
			m.albedo_color = Color("515844") if kind == "wool" else Color("aaa08a")
			m.normal_enabled = true
			m.normal_texture = load(RUG_WEAVE)
			m.roughness = 1.0
			m.uv1_scale = Vector3(2.0, 2.0, 1)
		"chest":
			# Not yet chosen (sheet 3: a CC0 candidate to rework): the provisional dark wood.
			m.albedo_texture = load(JOINERY % "col")
			m.normal_enabled = true
			m.normal_texture = load(JOINERY % "nor_gl")
			m.roughness_texture = load(JOINERY % "rough")
			m.roughness = 1.0
			m.albedo_color = Color(1.05, 0.72, 0.58)
			m.uv1_scale = Vector3(1.0 / 1.2, 1.0 / 1.2, 1)
		"planks":
			m.albedo_texture = load(BOARDS % "diff")
			m.normal_enabled = true
			m.normal_texture = load(BOARDS % "nor_gl")
			m.uv1_scale = Vector3(0.5, 0.5, 1)
		"stone":
			m.albedo_texture = load(STONE_MAPS % "diff")
			m.normal_enabled = true
			m.normal_texture = load(STONE_MAPS % "nor_gl")
			m.roughness_texture = load(STONE_MAPS % "rough")
			m.roughness = 1.0
			m.uv1_scale = Vector3(0.5, 0.5, 1)
	_skins[kind] = m
	return m

func _workshop_skin(model: Node3D) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var role := str(mesh.get_meta("extras", {}).get("part_role", ""))
		for i in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(i)
			var kind := source.resource_name.trim_prefix("Forest_") if source else ""
			var skin := ""
			if kind == "oak":
				# Owner 29 Sep: walls, furniture and chests each their own wood, or it all runs together.
				if role in ["floor", "loft", "door"]:
					skin = "planks"
				elif role == "furniture":
					skin = "chest" if str(mesh.name).to_lower().contains("chest") else "furniture"
				else:
					skin = "timber"
			elif kind == "cloth":
				# The hall textiles by their part name; the barracks' painted shields keep their cloth.
				var part := str(mesh.name).to_lower()
				if part.contains("banner_trim"):
					skin = "linen"
				elif part.contains("banner") or part.contains("cushion") or part.contains("blanket"):
					skin = "wool"
			elif kind == "roof":
				skin = "shingles"
			elif kind == "stone":
				skin = "stone"
			if skin != "":
				mesh.set_surface_override_material(i, _skin(skin))
		mesh.visibility_range_end = VISIBLE


var _stone_material: StandardMaterial3D
func _stone() -> StandardMaterial3D:
	if _stone_material == null:
		_stone_material = StandardMaterial3D.new()
		_stone_material.albedo_color = Color("6d6b63")
		_stone_material.roughness = 0.95
	return _stone_material


func _process(delta: float) -> void:
	for i in wheels.size():
		wheels[i].rotate_object_local(Vector3.RIGHT, wheel_speeds[i] * delta)


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
	# The towers stand into the town: buildings keep clear of them like of a neighbour.
	_placed.append([Vector2(base.x, base.z), Basis(Vector3.UP, tower.rotation.y), Rect2(-TOWER_REACH, -TOWER_REACH, TOWER_REACH * 2.0, TOWER_REACH * 2.0)])
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
