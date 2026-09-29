extends "res://scripts/world/village_settlement.gd"
## The game world: the starter village (D-072..078) placed on the 2x2 km world map (D-081, variant A).
## The village keeps its own local frame at the scene origin; the world map is laid under it
## with an offset, so every village system (doors, weather, sound, menu) works unchanged.

const Geometry = preload("res://scripts/world/world_graybox_geometry.gd")
const Shapes = preload("res://scripts/world/world_graybox_shapes.gd")
const Headwaters = preload("res://scripts/world/world_graybox_headwaters.gd")
const Landmarks = preload("res://scripts/world/world_graybox_landmarks.gd")
## TAVERN-01B (D-089): the forest inn — a one-storey log hall with beds on the loft — replaces
## the grey landmark at the forest_inn site, door towards the trail.
const InnBuilding = preload("res://scripts/world/village_building.gd")
const INN_SITE := "forest_inn"
## INN-CROSSROADS-01 (owner 28 Sep: "put our ready tavern there"): the same hall with its dressing
## stands at the crossroads inn; the innkeeper, his talk and the rented bed stay in the forest inn.
## INN-STONE-01 (owner 28 Sep): in the forest a log hall, in the desert the same hall in stone (T03B).
const INN_SITES := {
	"forest_inn": {"name": "ForestInn", "id": "T03A", "scene_path": "res://assets/buildings/forest-inn-v1/t03a.glb"},
	"crossroads_inn": {"name": "CrossroadsInn", "id": "T03B", "scene_path": "res://assets/buildings/desert-inn-v1/t03b.glb"},
}
## TAVERN-02 (owner 25 Sep): twice the floor, an L-shaped bar, straight stairs to the loft.
const INN_RECORD := {
	"id": "T03A",
	"title_key": "WORLD_SITE_FOREST_INN",
	"scene_path": "res://assets/buildings/forest-inn-v1/t03a.glb",
	"position": Vector3.ZERO,
	"entry": Vector3(0, 0.36, 10.5),
	"width": 13.0,
	"depth": 21.0,
	"floor_height": 0.36,
	"entry_width": 2.4,
}
## Door 3 m in front of the site spawn, like the landmark it replaces.
const INN_BACK_FROM_SPAWN := 13.5
## Behind the bar (Blender x 4.6, y 1.5 -> Godot x 4.6, z -1.5), guard look for now.
const INN_KEEPER_AT := Vector3(4.6, 0.36, -1.5)
const INN_KEEPER_TALK: QuestData = preload("res://data/quests/forest_inn_keeper.tres")
const INN_TALK_RADIUS := 2.8
const Pad = preload("res://scripts/world/world_settlement_pad.gd")

const VERSION := "0.36.27"
const WORLD_LAYOUT := "res://assets/world/graybox-v1/layout.json"
const WORLD_HEIGHTS := "res://assets/world/graybox-v1/heights.bin"
const WORLD_COLORS := "res://assets/world/graybox-v1/colors.bin"
## ROADS-UNIFY-01: a 1 m road mask over the map; the ground paints roads from it, like the village.
const WORLD_ROADS := "res://assets/world/graybox-v1/roads.png"
## A road deck mesh only where it stands this far over the ground: over a river channel (water + 0.6 m
## over a bed 1-2.8 m deep); the village ring lowers the ground by less than this under a trail.
const BRIDGE_RISE := 1.2
## Map point (metres) of the village's local origin, i.e. plan point (95, 95).
const VILLAGE_ORIGIN_MAP := Vector2(140, 1430)
## The 225 x 175 m plan on the map. Edges lie on the 5 m world grid.
const VILLAGE_RECT := Rect2(45, 1335, 225, 175)
## World height of village level 0 and width of the blend ring (measured: 95th percentile slope 32°).
const BASE_HEIGHT := 46.0
const RING := 100.0
const GRID := 5.0
## Village ground step that divides the world grid, so the seam shares its vertices.
const VILLAGE_MESH_STEP := 5.0 / 3.0
## Map half extent: map (x, z) is Godot (x - HALF, h, z - HALF) in the world frame.
const HALF := 1000.0
const SITE_SKIPPED := "start_hamlet"
## Plan points where world trails meet the village paths.
const STREET_EXIT_PLAN := Vector2(198, 0)
const CAVE_EXIT_PLAN := Vector2(17.25, 0)
const ROAD_TINT := Color("554837")

var world_layout: Dictionary
var world_width := 0
var original_heights: PackedFloat32Array
var world_heights: PackedFloat32Array
var pad: RefCounted
var world_root: Node3D
var world_terrain: Node3D
var road_mask: Image
var world_colors: PackedColorArray
## GRASS-WORLD-01: road and river pieces near the grass, bucketed by 32 m cells (scene frame).
const GRASS_CELL := 32.0
var _grass_segments := {}
var _grass_blocks: Array[Vector3] = []


## The courtyard lesson runs in the village (PLAYER-WORLD-01C); the pocket menu reads its journal here.
signal journal_changed()
var lesson: Node3D
## COMBAT-WORLD-01B: the wolf by the trail to the forest inn and the Block button.
var combat: Node
## WORLD-SAVE-01: inventory, hero place and progress; only when the world is the running scene.
var save: Node
var inn: Node3D
## Every inn hall on the map (the forest inn first); their doors work like the village doors.
var inns: Array[Node3D] = []
var inn_keeper: Node3D
var inn_talk: QuestTracker
## INN-REST-01: the rented bed in the inn loft and sleeping until the morning.
var lodging: Node
## TRAIL-01: the pine forest along the trail from the village to the forest inn.
var trail_dressing: Node3D
## WORLD-DRESS-01A: low-poly forest over the rest of the map (baked positions).
var far_forest: Node3D
## WORLD-SEA-01: the sea along the south edge (D-099).
var sea: Node3D
## WORLD-EDGES-01: mountains, cliffs and boulders at the north, west and east edges.
var edges: Node3D
## BRIDGES-01: timber bridges over the river crossings.
var bridges: Node3D
## FOREST-CITY-01: the forest city of the Exiles.
var forest_city: Node3D
## WORLD-PROPS-01: desert rocks and plants, ships and piers in the harbours.
var props: Node3D
## SNOW-01 / SAND-01: prints in the snow and the sand.
var footprints: Node3D
## WATER-01: spray over the rapids; SAND-01: whirls of sand in the desert wind.
var water_spray: Node3D
var dust_devils: Node3D
## DIALOG-CHOICE-01: answers to choose from in a conversation (the innkeeper first).
var choices: CanvasLayer
const DRINK_PRICE := 1
## DEBUG-MAP-01: Settings -> Debug -> Map.
var debug_map: CanvasLayer


func _ready() -> void:
	super._ready()
	trail_dressing = preload("res://scripts/world/world_trail_dressing.gd").new()
	trail_dressing.name = "TrailDressing"
	add_child(trail_dressing)
	trail_dressing.build_trail(self)
	trail_dressing.borrow_wind(dressing)
	far_forest = preload("res://scripts/world/world_far_forest.gd").new()
	far_forest.name = "FarForest"
	world_root.add_child(far_forest)
	far_forest.build(self)
	settings.apply_distance(self)
	lesson = preload("res://scripts/world/village_lesson.gd").new()
	lesson.name = "VillageLesson"
	add_child(lesson)
	lesson.configure(self)
	lesson.journal_changed.connect(func(): journal_changed.emit())
	hud.get_node("RootControl/BottomRight/VBox/AttackButton").show()
	# As in the combat sandbox: no strike while the Block button is held.
	hud.attack_pressed.connect(func():
		if combat == null or not combat.session.snapshot().get("guarding", false):
			player.request_attack())
	combat = preload("res://scripts/combat/world_combat.gd").new()
	combat.name = "Combat"
	add_child(combat)
	combat.configure(self)
	lodging = preload("res://scripts/world/inn_lodging.gd").new()
	lodging.name = "InnLodging"
	add_child(lodging)
	lodging.configure(self)
	lodging.changed.connect(_update_prompt)
	lodging.changed.connect(func(): journal_changed.emit())
	choices = preload("res://scripts/world/dialogue_choices.gd").new()
	choices.name = "DialogueChoices"
	add_child(choices)
	choices.configure(self)
	footprints = preload("res://scripts/world/world_footprints.gd").new()
	footprints.name = "Footprints"
	add_child(footprints)
	footprints.configure(self)
	audio.stepped.connect(footprints.step)
	water_spray = preload("res://scripts/world/world_water_spray.gd").new()
	water_spray.name = "WaterSpray"
	add_child(water_spray)
	water_spray.configure(self)
	dust_devils = preload("res://scripts/world/world_dust_devils.gd").new()
	dust_devils.name = "DustDevils"
	add_child(dust_devils)
	dust_devils.configure(self)
	debug_map = preload("res://scripts/world/world_debug_map.gd").new()
	debug_map.name = "DebugMap"
	add_child(debug_map)
	debug_map.configure(self)
	_start_save.call_deferred()
	lesson.sync_pack.call_deferred()
	_update_prompt()
	DisplayServer.window_set_title("AshBound — World %s" % VERSION)
	print("WORLD_VILLAGE_READY version=%s base=%.1f ring=%.0f" % [VERSION, BASE_HEIGHT, RING])


func _prepare_layout(plan: Dictionary) -> void:
	# The cave path ended 13 m inside the plan; lead it to the north edge where the world trail starts.
	plan.roads.append({"id": "world_cave_link", "name": "К лесной тропе", "width": 1.8,
		"points": [[17.25, 13.0], [CAVE_EXIT_PLAN.x, CAVE_EXIT_PLAN.y]]})


func _prepare_terrain(ground: Node3D) -> void:
	ground.grid_spacing = VILLAGE_MESH_STEP
	pad = Pad.new(VILLAGE_RECT, VILLAGE_ORIGIN_MAP, BASE_HEIGHT, RING, ground.height_at)
	ground.mesh_height = _village_mesh_height


func _environment() -> void:
	super._environment()
	_build_world()


## Village ground heights; on the plan edge they follow the world grid exactly.
func _village_mesh_height(x: float, z: float) -> float:
	var map := Vector2(x, z) + VILLAGE_ORIGIN_MAP
	if pad.is_on_border(map.x, map.y):
		return pad.border_height(map.x, map.y, GRID) - BASE_HEIGHT
	return terrain.height_at(x, z)


func _build_world() -> void:
	world_layout = JSON.parse_string(FileAccess.get_file_as_string(WORLD_LAYOUT))
	world_width = int(world_layout.width)
	original_heights = FileAccess.get_file_as_bytes(WORLD_HEIGHTS).to_float32_array()
	world_heights = _flatten_inn(_raise_west_rim(pad.apply(original_heights, world_width, GRID)))
	world_root = Node3D.new()
	world_root.name = "WorldMap"
	world_root.position = Vector3(HALF - VILLAGE_ORIGIN_MAP.x, -BASE_HEIGHT, HALF - VILLAGE_ORIGIN_MAP.y)
	add_child(world_root)
	world_terrain = Geometry.new()
	world_terrain.name = "Terrain"
	world_terrain.skip_cell = func(x: int, z: int) -> bool: return pad.covers_cell(x, z, GRID)
	world_terrain.material = terrain.material
	world_terrain.surface_meta = "ground"
	# SHORE-MESH-01: the banks along the water in 1.25 m cells, on the channel's own profile.
	_index_shore()
	world_terrain.refine_cell = func(x: int, z: int) -> bool:
		var near := _shore_near((x + 0.5) * GRID - HALF, (z + 0.5) * GRID - HALF)
		return not near.is_empty() and near[0] < near[2] + SHORE_REACH + GRID * 0.75
	world_terrain.shore_height = _shore_height
	world_terrain.shore_color = _shore_color
	world_root.add_child(world_terrain)
	world_colors = _world_colors()
	world_terrain.build(world_heights, world_colors, world_width, GRID)
	_build_roads()
	_apply_road_mask()
	_build_rivers()
	_build_water_and_sites()
	sea = preload("res://scripts/world/world_sea.gd").new()
	sea.name = "Sea"
	world_root.add_child(sea)
	sea.build(self)
	edges = preload("res://scripts/world/world_edges.gd").new()
	edges.name = "Edges"
	world_root.add_child(edges)
	edges.build(self)
	props = preload("res://scripts/world/world_props.gd").new()
	props.name = "Props"
	world_root.add_child(props)
	props.build(self)


## The map ends 45 m west of the village. A steep rise there (steeper than the hero can climb)
## closes the world naturally instead of an edge into the void or an invisible wall.
const RIM_WIDTH := 30.0
const RIM_RISE := 45.0

func _raise_west_rim(grid: PackedFloat32Array) -> PackedFloat32Array:
	var columns := int(RIM_WIDTH / GRID)
	for zi in range(world_width):
		for xi in range(columns + 1):
			grid[zi * world_width + xi] += RIM_RISE * (1.0 - smoothstep(0.0, RIM_WIDTH, xi * GRID))
	return grid


## Map colours brought to the village palette; near the village they become its own ground colour.
func _world_colors() -> PackedColorArray:
	var raw := FileAccess.get_file_as_bytes(WORLD_COLORS).to_float32_array()
	var colors := PackedColorArray()
	colors.resize(world_width * world_width)
	var blend := 150.0
	for zi in range(world_width):
		for xi in range(world_width):
			var i := zi * world_width + xi
			var c := Color(raw[i * 4], raw[i * 4 + 1], raw[i * 4 + 2], 0.0)
			# The baked map is linear clay; village grass is far darker under its texture detail.
			var luminance := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			var scale := lerpf(0.24, 0.62, smoothstep(0.3, 0.7, luminance))
			c = Color(c.r * scale, c.g * scale, c.b * scale, 0.0)
			var x := xi * GRID
			var z := zi * GRID
			var d: float = pad.distance_to_rect(x, z)
			if d < blend:
				var local := Color(terrain.color_at(x - VILLAGE_ORIGIN_MAP.x, z - VILLAGE_ORIGIN_MAP.y))
				c = c.lerp(local, 1.0 - smoothstep(0.0, blend, d))
			colors[i] = c
	return colors


# --- Heights --------------------------------------------------------------------------------

## Ground height of a grid at a point in the world frame (same triangles as the terrain mesh).
func _grid_height(grid: PackedFloat32Array, x: float, z: float) -> float:
	var gx := clampf((x + HALF) / GRID, 0.0, world_width - 1.0001)
	var gz := clampf((z + HALF) / GRID, 0.0, world_width - 1.0001)
	var ix := int(gx)
	var iz := int(gz)
	var u := gx - ix
	var v := gz - iz
	var a := grid[iz * world_width + ix]
	var b := grid[iz * world_width + ix + 1]
	var c := grid[(iz + 1) * world_width + ix]
	var d := grid[(iz + 1) * world_width + ix + 1]
	return a + u * (b - a) + v * (c - a) if u + v <= 1.0 else d + (1.0 - u) * (c - d) + (1.0 - v) * (b - d)


## World-frame ground height after the village was pressed in.
func world_ground(x: float, z: float) -> float:
	return _grid_height(world_heights, x, z)


## Ground height in the scene (village) frame at a scene point, inside or outside the village.
func ground_height_local(x: float, z: float) -> float:
	var map := Vector2(x, z) + VILLAGE_ORIGIN_MAP
	if VILLAGE_RECT.has_point(map):
		return terrain.height_at(x, z)
	return world_ground(map.x - HALF, map.y - HALF) - BASE_HEIGHT


func fall_limit() -> float:
	if player == null or world_heights.is_empty():
		return super.fall_limit()
	return ground_height_local(player.global_position.x, player.global_position.z) - 8.0


func _map_of(p: Vector3) -> Vector2:
	return Vector2(p.x + HALF, p.z + HALF)


func _world_of_plan(plan_point: Vector2, lift: float) -> Vector3:
	var map := plan_point - Vector2(95, 95) + VILLAGE_ORIGIN_MAP
	var p := Vector3(map.x - HALF, 0.0, map.y - HALF)
	# On the village edge the hero stands on the village ground, not on the world grid under it,
	# so a trail head starts flush with it (WORLD-TERRAIN-02: no lip at the exits).
	var scene_p := p + world_root.position
	p.y = ground_height_local(scene_p.x, scene_p.z) - world_root.position.y + lift
	return p


## Keeps a deck point at the same height above ground after the ring reshaped the ground.
func _follow_ground(p: Vector3) -> Vector3:
	var map := _map_of(p)
	if pad.distance_to_rect(map.x, map.y) > RING + 1.0:
		return p
	return Vector3(p.x, p.y + world_ground(p.x, p.z) - _grid_height(original_heights, p.x, p.z), p.z)


# --- Roads ----------------------------------------------------------------------------------

func _points_of(record: Dictionary) -> PackedVector3Array:
	var points := PackedVector3Array()
	for p in record.world_points:
		points.append(Vector3(p[0], p[1], p[2]))
	return points


func _road_points(road: Dictionary) -> PackedVector3Array:
	var source := _points_of(road)
	var result := PackedVector3Array()
	match str(road.id):
		"start_trail":
			# From the forest inn down to the village street; the old tail crossed the village.
			for p in source:
				if _map_of(p).y > 1318.0:
					break
				result.append(_follow_ground(p))
			_append_tail(result, [_world_of_plan(STREET_EXIT_PLAN + Vector2(5.3, -10.0), 0.0),
				_world_of_plan(STREET_EXIT_PLAN, -0.1)])
		"forest_cave_trail":
			# From the village north edge to the forest cave.
			# The head sits 10 cm under the village ground, so the strip's end cap hides in it (no lip).
			var head: Array = [_world_of_plan(CAVE_EXIT_PLAN, -0.1),
				_world_of_plan(CAVE_EXIT_PLAN + Vector2(3.75, -15.0), 0.0)]
			var kept := PackedVector3Array()
			var started := false
			for p in source:
				if not started and _map_of(p).y > 1300.0:
					continue
				started = true
				kept.append(_follow_ground(p))
			result.append(head[0])
			_append_tail(result, [head[1], kept[0]])
			result.remove_at(result.size() - 1)
			result.append_array(kept)
		_:
			for p in source:
				var map := _map_of(p)
				if pad.distance_to_rect(map.x, map.y) <= 0.0:
					continue
				result.append(_follow_ground(p))
	return result


## Appends straight pieces every 2 m; the height above ground eases from the last point's to the target's.
func _append_tail(points: PackedVector3Array, targets: Array) -> void:
	for target: Vector3 in targets:
		var from := points[points.size() - 1]
		var from_lift := from.y - world_ground(from.x, from.z)
		var to_lift := target.y - world_ground(target.x, target.z)
		var length := Vector2(target.x - from.x, target.z - from.z).length()
		var steps := maxi(1, int(ceil(length / 2.0)))
		for s in range(1, steps + 1):
			var t := float(s) / steps
			var p := from.lerp(target, t)
			p.y = world_ground(p.x, p.z) + lerpf(from_lift, to_lift, t)
			points.append(p)


func _build_roads() -> void:
	var roads := Shapes.new()
	roads.name = "Roads"
	world_root.add_child(roads)
	var shoulders := Shapes.new()
	shoulders.name = "Shoulders"
	world_root.add_child(shoulders)
	# BRIDGES-01: a timber bridge shows over every deck; the deck strip only carries the hero.
	bridges = preload("res://scripts/world/world_bridges.gd").new()
	bridges.name = "Bridges"
	world_root.add_child(bridges)
	bridges.configure(self)
	for road in world_layout.roads:
		var points := _road_points(road)
		if points.size() < 2:
			continue
		var width: float = road.get("width_m", 6.0)
		# ROADS-UNIFY-01: the road is painted on the ground (the terrain already lies at its height,
		# build.py); a deck is kept only across a river channel, two samples onto each bank.
		var bridge := PackedByteArray()
		bridge.resize(points.size())
		for i in points.size():
			if points[i].y - world_ground(points[i].x, points[i].z) > BRIDGE_RISE and _over_river(points[i]):
				for k in range(maxi(0, i - 2), mini(points.size(), i + 3)):
					bridge[k] = 1
		# BRIDGES-02 (owner 28 Sep: "a ramp to the bridge, no gaps, a smooth way up"): each bridge runs
		# on until the road meets the ground on the bank, so its ramp can end on the ground itself -
		# at most 2 m up or down the bank (on a steep bank the road beyond is the ground's own).
		for i in points.size():
			if bridge[i] == 1 and (i == 0 or bridge[i - 1] == 0):
				var k := i - 1
				while k >= 0 and i - k <= 8 and points[k].y - world_ground(points[k].x, points[k].z) > 0.12 and absf(points[k].y - points[i].y) < 2.0:
					bridge[k] = 2
					k -= 1
				if k >= 0:
					bridge[k] = 2
		for i in range(points.size() - 1, -1, -1):
			if bridge[i] == 1 and (i == points.size() - 1 or bridge[i + 1] == 0):
				var k := i + 1
				while k < points.size() and k - i <= 8 and points[k].y - world_ground(points[k].x, points[k].z) > 0.12 and absf(points[k].y - points[i].y) < 2.0:
					bridge[k] = 2
					k += 1
				if k < points.size():
					bridge[k] = 2
		var run := PackedVector3Array()
		var core := PackedByteArray()
		for i in points.size() + 1:
			if i < points.size() and bridge[i] > 0:
				run.append(points[i])
				core.append(1 if bridge[i] == 1 else 0)
				continue
			if run.size() >= 2:
				# The hero walks the same profile the bridge shows: ramps down to the ground at both ends.
				var strip: MeshInstance3D = roads.add_strip(bridges.deck_profile(run, core), width, ROAD_TINT, true)
				if strip != null:
					strip.name = "%s_bridge_%d" % [road.id, i]
					_paint(strip, Color(ROAD_TINT.srgb_to_linear(), 1.0))
					strip.visible = false
					bridges.build_bridge(run, width, core)
			run.clear()
			core.clear()
	_mark_surfaces(roads, "dirt")
	_mark_surfaces(shoulders, "ground")


## SHORE-MESH-01 (owner 28 Sep: "the banks are still triangles, zigzags"): within SHORE_REACH of the
## water's edge the ground follows the channel as build.py cuts it - the bed under the water, a
## smooth rise to 0.5 m over it just past the edge, then 1:1 - and blends back to the 5 m ground.
const SHORE_REACH := 5.0
## The sea beach's sand (build.py 0.74, 0.68, 0.52 sRGB), linear and darkened like _world_colors().
const RIVER_SAND := Color(0.176, 0.146, 0.082, 0.0)
const SHORE_CELL := 12.0
var _shore_cells := {}
var _shore_rivers: Array = []

func _index_shore() -> void:
	for r in world_layout.rivers.size():
		var river: Dictionary = world_layout.rivers[r]
		var pts := PackedVector3Array()
		var halves := PackedFloat32Array()
		var depths := PackedFloat32Array()
		for i in river.world_points.size():
			var p: Array = river.world_points[i]
			pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
			halves.append(float(river.world_widths[i]) * 0.5)
			depths.append(float(river.world_depths[i]) if river.has("world_depths") else 1.0)
			var key := Vector2i(floori(float(p[0]) / SHORE_CELL), floori(float(p[2]) / SHORE_CELL))
			if not _shore_cells.has(key):
				_shore_cells[key] = []
			_shore_cells[key].append(Vector2i(r, i))
		_shore_rivers.append([pts, halves, depths])

## [distance from the axis, water height, half width, depth] of the nearest river, or [] far from one.
func _shore_near(wx: float, wz: float) -> Array:
	var cell := Vector2i(floori(wx / SHORE_CELL), floori(wz / SHORE_CELL))
	var best := INF
	var hit := Vector2i(-1, -1)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for ref: Vector2i in _shore_cells.get(cell + Vector2i(dx, dz), []):
				var q: Vector3 = _shore_rivers[ref.x][0][ref.y]
				var d := (q.x - wx) * (q.x - wx) + (q.z - wz) * (q.z - wz)
				if d < best:
					best = d
					hit = ref
	if hit.x < 0:
		return []
	var pts: PackedVector3Array = _shore_rivers[hit.x][0]
	var halves: PackedFloat32Array = _shore_rivers[hit.x][1]
	var depths: PackedFloat32Array = _shore_rivers[hit.x][2]
	var result := [sqrt(best), pts[hit.y].y, halves[hit.y], depths[hit.y]]
	# The segments either side of the nearest point give the true distance to the axis.
	for k in [hit.y - 1, hit.y]:
		if k < 0 or k + 1 >= pts.size():
			continue
		var a := Vector2(pts[k].x, pts[k].z)
		var b := Vector2(pts[k + 1].x, pts[k + 1].z)
		var ab := b - a
		var t := clampf((Vector2(wx, wz) - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var d := (a + ab * t).distance_to(Vector2(wx, wz))
		if d < result[0]:
			result = [d, lerpf(pts[k].y, pts[k + 1].y, t), lerpf(halves[k], halves[k + 1], t), lerpf(depths[k], depths[k + 1], t)]
	return result

## The ground under a world-frame point as the terrain shows it, the finer banks included.
func shore_ground(wx: float, wz: float) -> float:
	var base := world_ground(wx, wz)
	var near := _shore_near(wx, wz)
	if near.is_empty() or near[0] >= near[2] + SHORE_REACH:
		return base
	return _shore_height(wx, wz, base)

## SANDY-BANKS-01 (owner 28 Sep: "make all the river banks sandy, it fits the lore better"): the bed
## and the bank up to SAND_REACH past the water's edge are river sand (the beach's, darkened as the
## map colours are), fading into the ground over the next 1.5 m. No grass grows on it.
const SAND_REACH := 2.5
func _shore_color(wx: float, wz: float, base: Color) -> Color:
	var near := _shore_near(wx, wz)
	if near.is_empty():
		return base
	return base.lerp(RIVER_SAND, 1.0 - smoothstep(float(near[2]) + SAND_REACH, float(near[2]) + SAND_REACH + 1.5, float(near[0])))

func on_river_sand(wx: float, wz: float) -> bool:
	var near := _shore_near(wx, wz)
	return not near.is_empty() and float(near[0]) < float(near[2]) + SAND_REACH + 0.75

func _shore_height(wx: float, wz: float, base: float) -> float:
	var near := _shore_near(wx, wz)
	if near.is_empty():
		return base
	var d: float = near[0]
	var water: float = near[1]
	var edge: float = near[2]
	var profile := water - float(near[3]) + (float(near[3]) + 0.5) * smoothstep(edge - 1.5, edge + 0.5, d) + maxf(d - (edge + 0.5), 0.0)
	# Never over the coarse ground, except to hold the water (0.5 m over it): the 1:1 bank rose over
	# a road's deck and buried the bridge ramps in a mound (owner 28 Sep).
	return minf(lerpf(profile, base, smoothstep(edge + 1.0, edge + SHORE_REACH, d)), maxf(base, water + 0.5))


## BRIDGES-02: a bridge only over a river. On a steep switchback the 5 m ground mesh can dip more than
## BRIDGE_RISE under the road; a bridge stood there on the hillside with no water under it.
var _bridge_river_cells := {}
func _over_river(p: Vector3) -> bool:
	if _bridge_river_cells.is_empty():
		for river in world_layout.rivers:
			for i in river.world_points.size():
				var q: Array = river.world_points[i]
				var key := Vector2i(floori(float(q[0]) / 32.0), floori(float(q[2]) / 32.0))
				if not _bridge_river_cells.has(key):
					_bridge_river_cells[key] = []
				_bridge_river_cells[key].append(Vector3(float(q[0]), float(river.world_widths[i]) * 0.5 + 3.0, float(q[2])))
	var cell := Vector2i(floori(p.x / 32.0), floori(p.z / 32.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for q: Vector3 in _bridge_river_cells.get(cell + Vector2i(dx, dz), []):
				if Vector2(p.x - q.x, p.z - q.z).length() <= q.y:
					return true
	return false


## The baked mask, with the village ring redrawn from the trail heads built here at run time
## and nothing inside the village itself (its ground paints its own paths).
func _apply_road_mask() -> void:
	road_mask = (load(WORLD_ROADS) as Texture2D).get_image()
	if road_mask.is_compressed():
		road_mask.decompress()
	road_mask.convert(Image.FORMAT_L8)
	var ring := VILLAGE_RECT.grow(RING + 10.0)
	road_mask.fill_rect(Rect2i(ring.position.floor(), ring.size.ceil()), Color.BLACK)
	for road in world_layout.roads:
		var points := _road_points(road)
		var width: float = road.get("width_m", 6.0)
		for i in range(points.size() - 1):
			var a := _map_of(points[i])
			var b := _map_of(points[i + 1])
			if ring.has_point(a) or ring.has_point(b):
				_stamp_segment(a, b, width, ring)
	var material: ShaderMaterial = terrain.material
	material.set_shader_parameter("use_road_mask", true)
	material.set_shader_parameter("road_mask", ImageTexture.create_from_image(road_mask))
	var corner := world_root.to_global(Vector3(-HALF, 0.0, -HALF))
	material.set_shader_parameter("road_mask_rect", Vector4(corner.x, corner.z, 2000.0, 2000.0))
	material.set_shader_parameter("road_tint", ROAD_TINT)


## Same soft edge as the village paths (village_terrain.gd color_at), 1 px = 1 m of the map.
func _stamp_segment(a: Vector2, b: Vector2, width: float, clip: Rect2) -> void:
	var inner := width * 0.42
	var outer := width * 0.65 + 0.5
	var lo := Vector2i((a.min(b) - Vector2.ONE * outer).floor())
	var hi := Vector2i((a.max(b) + Vector2.ONE * outer).ceil())
	for z in range(maxi(lo.y, 0), mini(hi.y, road_mask.get_height() - 1) + 1):
		for x in range(maxi(lo.x, 0), mini(hi.x, road_mask.get_width() - 1) + 1):
			var p := Vector2(x + 0.5, z + 0.5)
			if not clip.has_point(p) or VILLAGE_RECT.has_point(p):
				continue
			var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
			var v := 1.0 - smoothstep(inner, outer, d)
			if v > road_mask.get_pixel(x, z).r:
				road_mask.set_pixel(x, z, Color(v, v, v))


# --- Grass (GRASS-WORLD-01): the village blade grass over the whole map -----------------------

func grass_extent() -> Rect2:
	return Rect2(world_root.position.x - HALF, world_root.position.z - HALF, 2000.0, 2000.0)


func _scene_in_village(x: float, z: float) -> bool:
	return VILLAGE_RECT.has_point(Vector2(x - world_root.position.x + HALF, z - world_root.position.z + HALF))


## The ground the player sees: the village mesh inside it, the world grid outside.
func grass_height(x: float, z: float) -> float:
	if _scene_in_village(x, z):
		return terrain.height_at(x, z)
	return world_ground(x - world_root.position.x, z - world_root.position.z) + world_root.position.y


func grass_color(x: float, z: float) -> Color:
	if _scene_in_village(x, z):
		return terrain.color_at(x, z)
	var gx := clampf((x - world_root.position.x + HALF) / GRID, 0.0, world_width - 1.0001)
	var gz := clampf((z - world_root.position.z + HALF) / GRID, 0.0, world_width - 1.0001)
	var i := int(gz) * world_width + int(gx)
	var fx := gx - int(gx)
	var fz := gz - int(gz)
	return world_colors[i].lerp(world_colors[i + 1], fx).lerp(world_colors[i + world_width].lerp(world_colors[i + world_width + 1], fx), fz)


## Grass only on green ground (forest, meadows, lowlands) above the sea; not on sand, rock or snow.
func grass_grows(x: float, y: float, z: float, ground: Color) -> bool:
	if _scene_in_village(x, z):
		return true
	var sea_level: float = float(world_layout.sea.level) if world_layout.get("sea") is Dictionary else -INF
	if y - world_root.position.y < sea_level + 0.3:
		return false
	if on_river_sand(x - world_root.position.x, z - world_root.position.z):
		return false
	return ground.g > ground.r * 1.2 and ground.g < 0.12


## Roads and rivers near an area (as the village's own path segments) and places kept clear.
func grass_obstacles(area: Rect2) -> Dictionary:
	if _grass_segments.is_empty():
		_index_grass_obstacles()
	var segments: Array = []
	var seen := {}
	var lo := Vector2i((area.position / GRASS_CELL).floor())
	var hi := Vector2i((area.end / GRASS_CELL).floor())
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			for segment in _grass_segments.get(Vector2i(cx, cz), []):
				if not seen.has(segment.id):
					seen[segment.id] = true
					segments.append(segment)
	var blocks: Array = []
	for block in _grass_blocks:
		if area.grow(block.z).has_point(Vector2(block.x, block.y)):
			blocks.append(block)
	return {"segments": segments, "blocks": blocks}


func _index_grass_obstacles() -> void:
	var offset := Vector2(world_root.position.x, world_root.position.z)
	var pieces: Array = []
	for road in world_layout.roads:
		var points := _road_points(road)
		for i in range(points.size() - 1):
			pieces.append([Vector2(points[i].x, points[i].z) + offset, Vector2(points[i + 1].x, points[i + 1].z) + offset, float(road.get("width_m", 6.0))])
	for river in world_layout.rivers:
		var points := _points_of(river)
		for i in range(points.size() - 1):
			pieces.append([Vector2(points[i].x, points[i].z) + offset, Vector2(points[i + 1].x, points[i + 1].z) + offset, river_half_width(float(river.world_widths[i])) * 2.0])
	for n in pieces.size():
		var piece: Array = pieces[n]
		var segment := {"id": n, "a": piece[0], "b": piece[1], "width": piece[2]}
		var box := Rect2(piece[0], Vector2.ZERO).expand(piece[1]).grow(piece[2] * 0.5 + 1.5)
		for cz in range(floori(box.position.y / GRASS_CELL), floori(box.end.y / GRASS_CELL) + 1):
			for cx in range(floori(box.position.x / GRASS_CELL), floori(box.end.x / GRASS_CELL) + 1):
				var key := Vector2i(cx, cz)
				if not _grass_segments.has(key):
					_grass_segments[key] = []
				_grass_segments[key].append(segment)
	# Cities (grey blocks round the plaza), hamlets, the inn and the landmarks stay clear; lakes too.
	for city in world_layout.cities:
		_grass_blocks.append(Vector3(float(city.spawn[0]) + offset.x, float(city.spawn[2]) + offset.y, 48.0))
	for site in world_layout.sites:
		if str(site.id) == SITE_SKIPPED:
			continue
		var radius := 30.0 if site.kind == "settlement" else 16.0
		_grass_blocks.append(Vector3(float(site.spawn[0]) + offset.x, float(site.spawn[2]) + offset.y, radius))
	for site_id in INN_SITES:
		var inn_frame := _inn_frame(site_id)
		if not inn_frame.is_empty():
			_grass_blocks.append(Vector3(inn_frame.center.x + offset.x, inn_frame.center.z + offset.y, 14.0))
	# WATER-WORKSHOPS-02: the forest city's enterable halls (the mill stands outside the palisade).
	if forest_city != null:
		for hall in forest_city.halls + forest_city.sheds:
			var at: Vector3 = hall.global_position
			_grass_blocks.append(Vector3(at.x, at.z, maxf(float(hall.record.width), float(hall.record.depth)) * 0.55))
			# A trodden patch before the door and its steps.
			var door: Vector3 = hall.global_transform * (hall.record.entry + Vector3(0, 0, 1.8))
			_grass_blocks.append(Vector3(door.x, door.z, 3.2))
		# The yards are in the world_root frame, the grass blocks in the scene's.
		for yard in forest_city.yards:
			_grass_blocks.append(Vector3(yard.x + offset.x, yard.y + offset.y, yard.z))
	# LAKE-SHORE-01: a lake is an ellipse; one circle over its long radius kept the whole shore bare.
	# Circles of the short radius along the long axis cover the water and leave the shore to the grass.
	for lake in world_layout.lakes:
		var c: Array = lake.center
		var rx := float(lake.radii_m[0])
		var rz := float(lake.radii_m[1])
		var r := minf(rx, rz) + 2.0
		var reach := absf(rx - rz)
		for k in range(-2, 3):
			var along := reach * k / 2.0
			var at := Vector2(along, 0.0) if rx >= rz else Vector2(0.0, along)
			_grass_blocks.append(Vector3(float(c[0]) - HALF + at.x + offset.x, float(c[1]) - HALF + at.y + offset.y, r))


## MUSIC-REGION-01: which track plays here - "main" at home (the village and its ring), otherwise the
## biome of the map as build.py colours it: mountains over 165 m, the desert east, the lowlands south.
func music_region(at: Vector3) -> String:
	var map := Vector2(at.x - world_root.position.x + HALF, at.z - world_root.position.z + HALF)
	if VILLAGE_RECT.grow(RING).has_point(map):
		return "main"
	if at.y - world_root.position.y > 165.0:
		return "mountains"
	if map.x > 1210.0 and map.y < 1570.0:
		return "desert"
	if map.y > 1390.0 + 110.0 * sin(map.x / 200.0):
		return "lowlands"
	return "forest"


## SNOW-01 / SAND-01: what the ground is at a scene point - "snow" (the white of the mountains),
## "sand" (the desert), otherwise "ground".
func ground_kind(x: float, z: float) -> String:
	if _scene_in_village(x, z):
		return "ground"
	var c := grass_color(x, z)
	var luminance := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	if luminance > 0.22:
		return "snow"
	if c.r > c.g * 1.15 and music_region(Vector3(x, 0.0, z)) == "desert":
		return "sand"
	return "ground"


## How much a scene point is road (0..1): the village ground's own paint inside it, the mask outside.
func road_at(x: float, z: float) -> float:
	var map := Vector2(x - world_root.position.x + HALF, z - world_root.position.z + HALF)
	if VILLAGE_RECT.has_point(map) or road_mask == null:
		return terrain.color_at(x, z).a
	var px := Vector2i(clampi(int(map.x), 0, road_mask.get_width() - 1), clampi(int(map.y), 0, road_mask.get_height() - 1))
	return road_mask.get_pixel(px.x, px.y).r


func _build_shoulders(shapes: Node3D, points: PackedVector3Array, width: float) -> void:
	# Join land to the deck so the hero can leave a road without a step (graybox rule).
	for side in [-1.0, 1.0]:
		var inner := PackedVector3Array()
		var outer := PackedVector3Array()
		for i in range(points.size()):
			var p := points[i]
			var tangent := points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]
			var perpendicular: Vector3 = Vector3(-tangent.z, 0, tangent.x).normalized() * side
			var edge := p + perpendicular * width * 0.5
			var bank := p + perpendicular * 8.0
			var bank_map := _map_of(bank)
			# WORLD-TERRAIN-02: the ground now meets the deck; a shoulder only where the deck stands
			# clearly above it (bridge heads), so no painted bands run along every road.
			var rise := p.y - world_ground(p.x, p.z)
			var on_land := rise > 0.35 and rise < 2.0 and not VILLAGE_RECT.has_point(bank_map)
			bank.y = world_ground(bank.x, bank.z) + 0.02
			if not on_land:
				_add_shoulder(shapes, inner, outer, side)
				inner.clear()
				outer.clear()
				continue
			inner.append(edge)
			outer.append(bank)
		_add_shoulder(shapes, inner, outer, side)


func _add_shoulder(shapes: Node3D, inner: PackedVector3Array, outer: PackedVector3Array, side: float) -> void:
	if inner.size() < 2:
		return
	var band: MeshInstance3D = shapes.add_band(outer if side > 0 else inner, inner if side > 0 else outer, Color("8c836d"), true)
	if band != null:
		var map := _map_of(inner[0])
		var grass := Color(terrain.color_at(map.x - VILLAGE_ORIGIN_MAP.x, map.y - VILLAGE_ORIGIN_MAP.y))
		_paint(band, Color(grass.r, grass.g, grass.b, 0.0))


## Gives a strip vertex colours and the village ground material, so roads share its textures.
func _paint(instance: MeshInstance3D, color: Color) -> void:
	var arrays: Array = instance.mesh.surface_get_arrays(0)
	var colors := PackedColorArray()
	colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	colors.fill(color)
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	instance.mesh = mesh
	instance.material_override = terrain.material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _mark_surfaces(root: Node, surface: String) -> void:
	for body in root.find_children("*", "StaticBody3D", true, false):
		body.set_meta("footstep_surface", surface)


## RIVER-BANKS-01: the water ribbon reaches 3 m past the channel (at least 3 m from the axis), so its
## edges tuck under the banks that build.py raises over the water; the bank hides the rest.
func river_half_width(width: float) -> float:
	return maxf(width * 0.5, 3.0) + 3.0


func _build_rivers() -> void:
	var water := Shapes.new()
	water.name = "Rivers"
	world_root.add_child(water)
	for river in world_layout.rivers:
		var points := _points_of(river)
		var left := PackedVector3Array()
		var right := PackedVector3Array()
		for i in range(points.size()):
			var tangent := points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]
			var side := Vector3(-tangent.z, 0, tangent.x).normalized() * river_half_width(float(river.world_widths[i]))
			left.append(points[i] + side)
			right.append(points[i] - side)
		var band := _river_mesh(points, left, right, river.world_widths)
		band.name = str(river.id)
		water.add_child(band)


## WATER-01: a river ribbon with a flow frame for the water shader - UV.x across, UV.y metres
## downstream, UV2 = (width in metres, steepness 0..1: rapids where the bed falls fast).
func _river_mesh(points: PackedVector3Array, left: PackedVector3Array, right: PackedVector3Array, widths: Array) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var rows := []
	# WATER-02 (owner 28 Sep: "on the drops and joints the water looks untidy"): the steepness over
	# +-10 m and only from 12 % (the natural rivers made nearly every mountain stretch a white
	# rapid), UV.y the distance along the water itself, and the ribbon's own tilted normal.
	for i in points.size():
		if i > 0:
			along += points[i].distance_to(points[i - 1])
		var a := points[maxi(i - 5, 0)]
		var b := points[mini(i + 5, points.size() - 1)]
		var run := maxf(Vector2(b.x - a.x, b.z - a.z).length(), 0.1)
		var steep := clampf((absf(b.y - a.y) / run - 0.12) / 0.3, 0.0, 1.0)
		var tangent := (b - a).normalized()
		var normal := (right[i] - left[i]).cross(tangent).normalized()
		if normal.y < 0.0:
			normal = -normal
		rows.append([left[i], right[i], along, left[i].distance_to(right[i]), steep, normal])
	for i in rows.size() - 1:
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		var quad := [[r0[0], 0.0, r0], [r0[1], 1.0, r0], [r1[1], 1.0, r1], [r1[0], 0.0, r1]]
		for k in [0, 1, 2, 0, 2, 3]:
			var v: Array = quad[k]
			var row: Array = v[2]
			st.set_normal(row[5])
			st.set_uv(Vector2(v[1], row[2]))
			st.set_uv2(Vector2(row[3], row[4]))
			st.add_vertex(v[0])
	var band := MeshInstance3D.new()
	band.mesh = st.commit()
	band.material_override = water_material(true)
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return band


## The flowing (river) or still (lake, sea) water material.
func water_material(flowing: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/world_water.gdshader")
	material.set_shader_parameter("river", flowing)
	return material


func _build_water_and_sites() -> void:
	var water := Headwaters.new()
	water.name = "Headwaters"
	world_root.add_child(water)
	for lake in world_layout.lakes:
		var p: Array = lake.center
		var lake_mesh: MeshInstance3D = water.add_lake(Vector3(p[0] - HALF, p[2], p[1] - HALF), Vector2(lake.radii_m[0], lake.radii_m[1]))
		if lake_mesh != null:
			lake_mesh.material_override = water_material(false)
	for spring in world_layout.springs:
		var p: Array = spring.mouth
		var direction: Array = spring.facing
		water.add_spring_cave(Vector3(p[0] - HALF, p[2] - 1, p[1] - HALF), Vector3(direction[0], 0, direction[2]))
	for city in world_layout.cities:
		# FOREST-CITY-01 (D-111): the forest city is built by its plan, not grey blocks.
		if str(city.id) == "forest":
			forest_city = preload("res://scripts/world/world_forest_city.gd").new()
			forest_city.name = "ForestCity"
			world_root.add_child(forest_city)
			forest_city.build(self)
			# Its halls open like the inns' doors (the action button when no village door is nearer).
			for hall in forest_city.halls:
				inns.append(hall)
			continue
		var p: Array = city.spawn
		for offset in [Vector3(-28, 0, 15), Vector3(26, 0, 18), Vector3(-20, 0, -25)]:
			var size := Vector3(12, 12 + float(city.number) * 3, 16)
			var base: Vector3 = Vector3(p[0], 0, p[2]) + offset
			base.y = world_ground(base.x, base.z)
			var marker := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = size
			marker.mesh = box
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("92938b")
			marker.material_override = material
			marker.position = base + Vector3.UP * size.y * 0.5
			world_root.add_child(marker)
	for site in world_layout.sites:
		if str(site.id) == SITE_SKIPPED or site.kind == "lake" or site.kind == "spring_cave":
			continue
		if INN_SITES.has(str(site.id)):
			_build_inn(site)
			continue
		var landmark := Landmarks.new()
		landmark.name = str(site.id)
		world_root.add_child(landmark)
		var direction: Array = site.facing
		var s: Array = site.spawn
		landmark.build(site.kind, Vector3(s[0], float(site.point[2]), s[2]), Vector3(direction[0], 0, direction[2]))


func open_debug_map() -> void:
	debug_map.open()


## Settings -> Debug: the four cities and every site of the atlas, for checking the world by hand.
func debug_locations() -> Array:
	var places := []
	for city in world_layout.cities:
		places.append(city)
	for site in world_layout.sites:
		places.append(site)
	return places


## Puts the hero on the floor at a city or site spawn, looking at the place itself.
func teleport_to(place: Dictionary) -> void:
	var s: Array = place.spawn
	var at := world_root.to_global(Vector3(float(s[0]), float(s[1]), float(s[2])))
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 40.0, at + Vector3.DOWN * 40.0)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		at = hit.position
	var p: Array = place.point
	var look := world_root.to_global(Vector3(float(p[0]) - HALF, at.y, float(p[1]) - HALF)) - at
	look.y = 0.0
	if look.length() < 1.0:
		var f: Array = place.get("facing", [0, 0, -1])
		look = Vector3(float(f[0]), 0.0, float(f[2]))
	player.velocity = Vector3.ZERO
	player.global_position = at + Vector3.UP * 0.12
	player.facing_direction = look.normalized()
	camera_rig._yaw = atan2(-look.x, -look.z)
	camera_rig._apply_rotation()
	camera_rig.snap_to_target()
	player.get_node("Visual").reset_motion_interpolation()
	if sea != null and sea.has_method("forget_safe_point"):
		sea.forget_safe_point()
	print("WORLD_TELEPORT id=%s at=%s" % [place.id, player.global_position])


func get_journal_entry() -> Dictionary:
	if lesson == null:
		return {}
	var entry: Dictionary = lesson.journal_entry()
	# UI-CLEAN-01: after the watchman pays, the objective leads to the inn bed and past the first night.
	if entry.completed and lodging != null:
		if lodging.rented:
			entry.objective_key = "INN_OBJECTIVE_SLEEP"
		elif lodging.nights == 0:
			entry.objective_key = "INN_OBJECTIVE_RENT"
			entry.params = {"price": str(lodging.PRICE)}
		else:
			entry.objective_key = "INN_OBJECTIVE_MORNING"
	return entry


## A lesson character or the woodpile nearby takes the action button before a door.
func interact() -> void:
	if lesson != null and is_input_available():
		var point: Node3D = lesson.nearest_point()
		if point != null:
			lesson.interact(point)
			_update_prompt()
			return
		if inn_keeper_in_reach():
			if inn_talk.flags.get(&"greeted", false):
				await keeper_menu()
			else:
				talk_to_inn_keeper()
			_update_prompt()
			return
		if lodging.bed_in_reach():
			await lodging.sleep()
			_update_prompt()
			return
	super.interact()


func _update_prompt() -> void:
	super._update_prompt()
	if lesson == null or hud == null or player == null:
		return
	_offer_inn_door()
	# UI-CLEAN-01: the corner always shows the current step, also inside houses and the inn.
	var entry := get_journal_entry()
	hud.set_objective(entry.objective_key, entry.params)
	var point: Node3D = lesson.nearest_point() if is_input_available() else null
	var action := ""
	if point == null and is_input_available() and inn_keeper_in_reach():
		point = inn_keeper
		if inn_talk.flags.get(&"greeted", false):
			action = Localization.text("COURTYARD_ACTION_TALK")
	if point == null and is_input_available() and lodging.bed_in_reach():
		action = Localization.text("INN_ACTION_SLEEP")
	elif point == null:
		return
	current_door = null
	for building in buildings:
		building.door.set_highlight(false)
	if action == "":
		action = Localization.text(point.prompt)
	interact_button.disabled = false
	interact_button.text = action
	hud.set_prompt(action if OS.get_name() == "Android" else "E · " + action)


func _start_save() -> void:
	if get_tree().current_scene != self or OS.get_cmdline_user_args().has("--no-world-save"):
		return
	save = preload("res://scripts/world/world_save.gd").new()
	save.name = "WorldSave"
	add_child(save)
	save.initialize(self)


## Where an inn stands (world frame): centre, yaw and the level of its pad (the trail end).
func _inn_frame(site_id: String = INN_SITE) -> Dictionary:
	for site in world_layout.sites:
		if str(site.id) != site_id:
			continue
		var s: Array = site.spawn
		var direction: Array = site.facing
		var yaw := atan2(float(direction[0]), float(direction[2]))
		var center := Vector3(float(s[0]), 0, float(s[2])) + Basis(Vector3.UP, yaw) * Vector3(0, 0, -INN_BACK_FROM_SPAWN)
		# The site spawn height is the end of the trail embankment: the pad meets the trail without a step.
		return {"center": center, "yaw": yaw, "level": float(s[1])}
	return {}

## A level pad under the inn: the footprint grown by one grid step is flat at the trail's height,
## then 10 m blend back to the slope. Without it the door stood a metre above the ground.
func _flatten_inn(grid: PackedFloat32Array) -> PackedFloat32Array:
	var result := grid.duplicate()
	for site_id in INN_SITES:
		_flatten_inn_pad(result, _inn_frame(site_id))
	return result

func _flatten_inn_pad(result: PackedFloat32Array, frame: Dictionary) -> void:
	if frame.is_empty():
		return
	var inverse := Basis(Vector3.UP, frame.yaw).inverse()
	# Footprint plus 0.2 m, and the entry steps/canopy in front (+z).
	var half_x: float = INN_RECORD.width * .5 + .2 + GRID
	var z0: float = -INN_RECORD.depth * .5 - .2
	var z1: float = INN_RECORD.depth * .5 + 1.9
	for gz in range(world_width):
		for gx in range(world_width):
			var world_point := Vector3(gx * GRID - HALF, 0, gz * GRID - HALF)
			var local: Vector3 = inverse * (world_point - frame.center)
			var dz := maxf(absf(local.z - (z0 + z1) * .5) - ((z1 - z0) * .5 + GRID), 0.0)
			var dx := maxf(absf(local.x) - half_x, 0.0)
			var d := Vector2(dx, dz).length()
			if d >= 10.0:
				continue
			var index := gz * world_width + gx
			result[index] = lerpf(float(frame.level), result[index], smoothstep(0.0, 10.0, d))

func _build_inn(site: Dictionary) -> void:
	var frame := _inn_frame(str(site.id))
	var yaw: float = frame.yaw
	var basis := Basis(Vector3.UP, yaw)
	var center: Vector3 = frame.center
	# Stand on the highest corner so nothing sinks; a stone plinth fills down to the lowest one.
	var high := -INF
	var low := INF
	var hx: float = INN_RECORD.width * .5 + .2
	for corner in [Vector3(-hx, 0, -INN_RECORD.depth * .5 - .2), Vector3(hx, 0, -INN_RECORD.depth * .5 - .2), Vector3(-hx, 0, INN_RECORD.depth * .5 + 1.9), Vector3(hx, 0, INN_RECORD.depth * .5 + 1.9)]:
		var at: Vector3 = center + basis * corner
		var h := world_ground(at.x, at.z)
		high = maxf(high, h)
		low = minf(low, h)
	var hall := InnBuilding.new()
	world_root.add_child(hall)
	var kind: Dictionary = INN_SITES[str(site.id)]
	var record := INN_RECORD.duplicate()
	record.title_key = str(site.key)
	record.id = kind.id
	record.scene_path = kind.scene_path
	hall.build(record)
	hall.name = kind.name
	hall.position = Vector3(center.x, high, center.z)
	hall.rotation.y = yaw
	inns.append(hall)
	var drop := high - low
	if drop > 0.02:
		var plinth := MeshInstance3D.new()
		plinth.name = "Plinth"
		var box := BoxMesh.new()
		box.size = Vector3(INN_RECORD.width + .4, drop + 0.1, INN_RECORD.depth + .4)
		plinth.mesh = box
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color("6d6b63")
		stone.roughness = .95
		plinth.material_override = stone
		plinth.position = Vector3(0, -drop * 0.5 + 0.02, 0)
		hall.add_child(plinth)
	if str(site.id) == INN_SITE:
		inn = hall
		_add_inn_keeper()
	# TAVERN-03: props, rugs, lanterns and candles, the hearth fire with its light and crackle.
	var dressing := preload("res://scripts/world/inn_dressing.gd").new()
	dressing.name = "InnDressing"
	hall.add_child(dressing)
	dressing.build()


## The inn is not one of the village yards (the house picker and the yard tests stay three),
## but its door works with the same action button when no village door is nearer.
func _offer_inn_door() -> void:
	var door: Node3D = null
	for hall in inns:
		if hall.door == null:
			continue
		hall.door.set_highlight(false)
		if door == null or hall.door.can_interact(player):
			door = hall.door
	if door == null:
		return
	var usable: bool = is_input_available() and door.can_interact(player)
	door.set_highlight(usable and current_door == null)
	if not usable or current_door != null:
		return
	current_door = door
	var key := "VILLAGE_OPEN"
	var would_close: bool = door.goal > 0.5 if door.moving else door.fraction > 0.0
	if would_close:
		key = "VILLAGE_CLOSE"
	interact_button.disabled = false
	interact_button.text = Localization.text(key)
	if door.moving:
		hud.set_prompt(Localization.text("VILLAGE_DOOR_MOVING"))
	else:
		hud.set_prompt(Localization.text(key) if OS.get_name() == "Android" else "E · " + Localization.text(key))


## The innkeeper stands behind the bar (guard look until an own one is drawn); lines are data.
func _add_inn_keeper() -> void:
	inn_talk = QuestTracker.new(INN_KEEPER_TALK)
	inn_keeper = preload("res://scenes/courtyard/resident.tscn").instantiate()
	inn_keeper.name = "InnKeeper"
	inn_keeper.interaction_id = &"inn_keeper"
	inn_keeper.display_name = "INN_KEEPER_NAME"
	inn_keeper.prompt = "COURTYARD_ACTION_TALK"
	inn_keeper.appearance = preload("res://assets/characters/courtyard/watchman_frames.tres")
	inn_keeper.position = INN_KEEPER_AT
	inn.add_child(inn_keeper)

func inn_keeper_in_reach() -> bool:
	if inn_keeper == null or player == null:
		return false
	var offset := inn_keeper.global_position - player.global_position
	return Vector2(offset.x, offset.z).length() <= INN_TALK_RADIUS and absf(offset.y) < 1.2

## After the greeting the innkeeper asks what the hero wants: a bed (until one is rented), a mug of
## ale, or nothing. The answer is carried out and the innkeeper replies.
func keeper_menu() -> void:
	var answers := []
	if not lodging.rented:
		answers.append([&"rent", Localization.text("INN_ANSWER_RENT", {"price": str(lodging.PRICE)})])
	answers.append([&"drink", Localization.text("INN_ANSWER_DRINK", {"price": str(DRINK_PRICE)})])
	answers.append([&"leave", Localization.text("INN_ANSWER_LEAVE")])
	choices.open("INN_KEEPER_NAME", "INN_KEEPER_ASK", answers)
	var id: StringName = await choices.chosen
	match id:
		&"rent":
			lodging.rent()
		&"drink":
			var purse: Node = get_node("/root/Inventory")
			if purse.has_gold(DRINK_PRICE) and purse.remove_gold(DRINK_PRICE):
				hud.show_message("INN_KEEPER_NAME", "INN_KEEPER_DRINK")
			else:
				hud.show_message("INN_KEEPER_NAME", "INN_KEEPER_DRINK_NO_MONEY", {"price": str(DRINK_PRICE)})
		_:
			hud.show_message("INN_KEEPER_NAME", "INN_KEEPER_BYE")


func is_input_available() -> bool:
	return super.is_input_available() and (choices == null or not choices.is_open)


func talk_to_inn_keeper() -> bool:
	var line: DialogueLineData = inn_talk.line_for(&"inn_keeper")
	if line == null:
		return false
	hud.show_message(line.name_key, line.line_key)
	inn_talk.apply_line(line)
	return true
