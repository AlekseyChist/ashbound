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

const VERSION := "0.31.1"
const WORLD_LAYOUT := "res://assets/world/graybox-v1/layout.json"
const WORLD_HEIGHTS := "res://assets/world/graybox-v1/heights.bin"
const WORLD_COLORS := "res://assets/world/graybox-v1/colors.bin"
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


## The courtyard lesson runs in the village (PLAYER-WORLD-01C); the pocket menu reads its journal here.
signal journal_changed()
var lesson: Node3D
## COMBAT-WORLD-01B: the wolf by the trail to the forest inn and the Block button.
var combat: Node
## WORLD-SAVE-01: inventory, hero place and progress; only when the world is the running scene.
var save: Node
var inn: Node3D
var inn_keeper: Node3D
var inn_talk: QuestTracker


func _ready() -> void:
	super._ready()
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
	_start_save.call_deferred()
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
	world_root.add_child(world_terrain)
	world_terrain.build(world_heights, _world_colors(), world_width, GRID)
	_build_roads()
	_build_rivers()
	_build_water_and_sites()


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
	p.y = world_ground(p.x, p.z) + lift
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
				_world_of_plan(STREET_EXIT_PLAN, 0.05)])
		"forest_cave_trail":
			# From the village north edge to the forest cave.
			var head: Array = [_world_of_plan(CAVE_EXIT_PLAN, 0.05),
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
	for road in world_layout.roads:
		var points := _road_points(road)
		if points.size() < 2:
			continue
		# Overlap end caps slightly so shared junctions have no open edge (same as the graybox).
		points.insert(0, points[0] + (points[0] - points[1]).normalized() * 0.5)
		points.append(points[-1] + (points[-1] - points[-2]).normalized() * 0.5)
		var width: float = road.get("width_m", 6.0)
		var strip: MeshInstance3D = roads.add_strip(points, width, ROAD_TINT, true)
		if strip == null:
			continue
		strip.name = str(road.id)
		_paint(strip, Color(ROAD_TINT.srgb_to_linear(), 1.0))
		_build_shoulders(shoulders, points, width)
	_mark_surfaces(roads, "dirt")
	_mark_surfaces(shoulders, "ground")


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
			var on_land := p.y - world_ground(p.x, p.z) < 2.0 and not VILLAGE_RECT.has_point(bank_map)
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
			var side := Vector3(-tangent.z, 0, tangent.x).normalized() * float(river.world_widths[i]) * 0.5
			left.append(points[i] + side)
			right.append(points[i] - side)
		var band: MeshInstance3D = water.add_band(left, right, Color("537d91"), false)
		if band != null:
			band.name = str(river.id)


func _build_water_and_sites() -> void:
	var water := Headwaters.new()
	water.name = "Headwaters"
	world_root.add_child(water)
	for lake in world_layout.lakes:
		var p: Array = lake.center
		water.add_lake(Vector3(p[0] - HALF, p[2], p[1] - HALF), Vector2(lake.radii_m[0], lake.radii_m[1]))
	for spring in world_layout.springs:
		var p: Array = spring.mouth
		var direction: Array = spring.facing
		water.add_spring_cave(Vector3(p[0] - HALF, p[2] - 1, p[1] - HALF), Vector3(direction[0], 0, direction[2]))
	for city in world_layout.cities:
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
		if str(site.id) == INN_SITE:
			_build_inn(site)
			continue
		var landmark := Landmarks.new()
		landmark.name = str(site.id)
		world_root.add_child(landmark)
		var direction: Array = site.facing
		var s: Array = site.spawn
		landmark.build(site.kind, Vector3(s[0], float(site.point[2]), s[2]), Vector3(direction[0], 0, direction[2]))


func get_journal_entry() -> Dictionary:
	return lesson.journal_entry() if lesson != null else {}


## A lesson character or the woodpile nearby takes the action button before a door.
func interact() -> void:
	if lesson != null and is_input_available():
		var point: Node3D = lesson.nearest_point()
		if point != null:
			lesson.interact(point)
			_update_prompt()
			return
		if inn_keeper_in_reach():
			talk_to_inn_keeper()
			_update_prompt()
			return
	super.interact()


func _update_prompt() -> void:
	super._update_prompt()
	if lesson == null or hud == null or player == null:
		return
	_offer_inn_door()
	var inside := false
	for building in buildings:
		if building.contains(player.global_position):
			inside = true
	if not inside:
		var entry: Dictionary = lesson.journal_entry()
		hud.set_objective(entry.objective_key, entry.params)
	var point: Node3D = lesson.nearest_point() if is_input_available() else null
	if point == null and is_input_available() and inn_keeper_in_reach():
		point = inn_keeper
	if point == null:
		return
	current_door = null
	for building in buildings:
		building.door.set_highlight(false)
	var action: String = Localization.text(point.prompt)
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


## Where the inn stands (world frame): centre, yaw and the level of its pad (the trail end).
func _inn_frame() -> Dictionary:
	for site in world_layout.sites:
		if str(site.id) != INN_SITE:
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
	var frame := _inn_frame()
	if frame.is_empty():
		return grid
	var result := grid.duplicate()
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
	return result

func _build_inn(site: Dictionary) -> void:
	var frame := _inn_frame()
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
	inn = InnBuilding.new()
	world_root.add_child(inn)
	inn.build(INN_RECORD)
	inn.name = "ForestInn"
	inn.position = Vector3(center.x, high, center.z)
	inn.rotation.y = yaw
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
		inn.add_child(plinth)
	_add_inn_keeper()
	# TAVERN-03: props, rugs, lanterns and candles, the hearth fire with its light and crackle.
	var dressing := preload("res://scripts/world/inn_dressing.gd").new()
	dressing.name = "InnDressing"
	inn.add_child(dressing)
	dressing.build()


## The inn is not one of the village yards (the house picker and the yard tests stay three),
## but its door works with the same action button when no village door is nearer.
func _offer_inn_door() -> void:
	if inn == null or inn.door == null:
		return
	var door: Node3D = inn.door
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
	if inn.contains(player.global_position):
		hud.set_objective(INN_RECORD.title_key)


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

func talk_to_inn_keeper() -> bool:
	var line: DialogueLineData = inn_talk.line_for(&"inn_keeper")
	if line == null:
		return false
	hud.show_message(line.name_key, line.line_key)
	inn_talk.apply_line(line)
	return true
