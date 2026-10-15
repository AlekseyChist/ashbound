extends Node3D
## WORLD-BUILD-01G: the caves' mouths on the surface - a rock outcrop with an arch into the hill
## (art/blender/world-architecture-v1/build_cave_mouth.py) at every open exit of the caves' plan
## (assets/world/caves-v1/plan.json). The interiors are separate scenes (Codex 300, option B); the
## transition at the mouth's CavePortal is Codex's. Children sit in the world_root frame (map - HALF).

const PLAN := "res://assets/world/caves-v1/plan.json"
const MOUTH := "res://assets/caves-v1/cave_mouth.glb"
## Three bodies of rock by seed (Codex MOUTH-02: one model at every exit read as a placed object).
const MOUTHS := [MOUTH, "res://assets/caves-v1/cave_mouth_b.glb", "res://assets/caves-v1/cave_mouth_c.glb"]
## The Crown mine's portal and its old drainage adit Ш2 (assets/world/mine-v1/plan.json): the same
## hill with a timbered adit and rails (build_cave_mouth.py -- mine).
const MINE_PLAN := "res://assets/world/mine-v1/plan.json"
const MINE_PORTAL := "res://assets/caves-v1/mine_portal.glb"
const TIMBER := "res://assets/environment/village-house-materials-v1/fine_grained_wood_%s_1k.jpg"
const ROCK := "res://assets/environment/cave-rock-v1/rock_face_03_%s_1k.jpg"
const EARTH := "res://assets/environment/village-surfaces-v1/forest_ground_04_%s_1k.jpg"
const SKIPPED: Array[String] = []
## The spring cave's one mouth (Codex 403 SPRING-MOUTH-01 A) on the east river's source (layout springs):
## a wide low vault over the 8 m stream with a dry ledge beside it (build_cave_mouth.py -- spring); its
## cut is wider and deeper - the ground under the stream lies under its water.
const SPRING_EXIT := "spring_cave:E"
const SPRING_MOUTH := "res://assets/caves-v1/cave_mouth_spring.glb"
const SPRING_CUT := {"inside_half": 6.0, "notch_half": 8.0, "depth": 17.0, "under": 1.6}
## The arch's floor 3 cm over the ground at the exit point (no flicker with the terrain).
const LIFT := 0.03
## Where a slope runs up into the arch, the terrain's points inside this box of the mouth (metres,
## x across, depth into the hill) drop under the floor; the rock hides the cut round them.
const NOTCH_HALF_WIDTH := 4.5
const NOTCH_DEPTH := Vector2(-2.0, 9.0)
const NOTCH_RISE := 0.3
const NOTCH_UNDER := 0.4
const INSIDE_HALF_WIDTH := 3.0
## A book stair starting this close to an exit sets the arch's floor.
const STAIR_REACH := 5.0
## On a slope the arch's floor takes the ground before its rock (FRONT m out), not the slope's
## brow at the exit point: the rock sinks into the hill and no drop opens before the entrance.
const FRONT := 3.0
## No forest tree inside this circle round the rock hill's middle (HILL_CENTRE m into the hill),
## nor on a narrow way up to the arch (Codex MOUTH-03: at forest X the spruce branches hid the hero
## and the mouth 12 m out): circles of APPROACH_CLEAR along it, out to APPROACH_REACH m.
const HILL_CENTRE := 4.0
const HILL_CLEAR := 14.0
const APPROACH_CLEAR := 3.5
const APPROACH_REACH := 22.0

var mouths: Array[Node3D] = []
## The ground at each exit before the cut (notch), by exit id: the arch's floor level.
var floors := {}


## The open exits with a place on the map: [{id, map: Vector2, facing: Vector2 (out of the hill)}].
static func exits() -> Array:
	var result: Array = []
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLAN))
	var n := 0
	for cave in plan.caves:
		for exit in cave.exits:
			if exit.map == null or str(exit.state) != "open" or SKIPPED.has(str(exit.id)):
				continue
			var facing := Vector2(float(exit.facing[0]), float(exit.facing[1])).normalized()
			var entry := {"id": str(exit.id), "map": Vector2(float(exit.map[0]), float(exit.map[1])), "facing": facing}
			if str(exit.id) == SPRING_EXIT:
				entry.scene = SPRING_MOUTH
				entry.merge(SPRING_CUT)
			else:
				entry.scene = MOUTHS[n % MOUTHS.size()]
				n += 1
			result.append(entry)
	var mine: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MINE_PLAN))
	for exit in mine.exits:
		if exit.get("map") == null or str(exit.state) != "open":
			continue
		var facing := Vector2(float(exit.facing[0]), float(exit.facing[1])).normalized()
		result.append({"id": str(exit.id), "map": Vector2(float(exit.map[0]), float(exit.map[1])), "facing": facing, "scene": MINE_PORTAL})
	return result


## A copy of the world grid with the terrain cut under each arch where the slope climbs into it.
## Flat ground is left alone. `height` is the grid's own sampler (world frame).
## `stairs`: the layout's book stairs - a flight starting at an exit sets that arch's floor (Codex 351:
## foothill X's floor came 3.26 m under its stair's top from the ground the stair's cut had lowered).
func notch(grid: PackedFloat32Array, width: int, step: float, half: float, height: Callable, stairs: Array = []) -> PackedFloat32Array:
	var result := grid.duplicate()
	for exit in exits():
		var at: Vector2 = exit.map - Vector2(half, half)
		var out: Vector2 = exit.facing
		var floor_y: float = minf(height.call(at.x, at.y), height.call(at.x + out.x * FRONT, at.y + out.y * FRONT))
		var nearest := STAIR_REACH
		for flight in stairs:
			for st in [flight.steps[0], flight.steps[flight.steps.size() - 1]]:
				var d := Vector2(float(st[0]) - half, float(st[1]) - half).distance_to(at)
				if d < nearest:
					nearest = d
					floor_y = float(st[2])
		floors[exit.id] = floor_y
		var half_w: float = exit.get("notch_half", NOTCH_HALF_WIDTH)
		var inside_w: float = exit.get("inside_half", INSIDE_HALF_WIDTH)
		var deep: float = exit.get("depth", NOTCH_DEPTH.y)
		var under: float = exit.get("under", NOTCH_UNDER)
		var reach := deep + half_w
		for gz in range(maxi(0, floori((at.y - reach + half) / step)), mini(width, ceili((at.y + reach + half) / step) + 1)):
			for gx in range(maxi(0, floori((at.x - reach + half) / step)), mini(width, ceili((at.x + reach + half) / step) + 1)):
				var d := Vector2(gx * step - half, gz * step - half) - at
				var depth := -d.dot(out)
				var across := absf(d.dot(Vector2(-out.y, out.x)))
				if across > half_w or depth < NOTCH_DEPTH.x or depth > deep:
					continue
				var i := gz * width + gx
				# inside the arch the ground always lies under its floor (Codex 351: terrain showed through
				# the bent way's bottom and across the mine's adit); before it only where the slope climbs
				var inside := depth >= 0.5 and across <= inside_w
				if result[i] > floor_y + NOTCH_RISE or (inside and result[i] > floor_y - under):
					result[i] = floor_y - under
	return result


## The arches' footprints for the fine ground (world_snow_lots.arch_zones), after notch():
## [centre, out, depth from, depth to, half width, floor] in the world_root frame.
func arch_zones(half: float) -> Array:
	var result: Array = []
	for exit in exits():
		if floors.has(exit.id):
			result.append([exit.map - Vector2(half, half), exit.facing, -1.0, float(exit.get("depth", NOTCH_DEPTH.y)), float(exit.get("inside_half", INSIDE_HALF_WIDTH)), float(floors[exit.id]) + LIFT])
	return result


## Circles (x, z, radius) in the world_root frame that the forest keeps clear of.
static func clearings(half: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for exit in exits():
		var at: Vector2 = exit.map - Vector2(half, half) - exit.facing * HILL_CENTRE
		result.append(Vector3(at.x, at.y, HILL_CLEAR))
		var out := 6.0
		while out <= APPROACH_REACH:
			var w: Vector2 = exit.map - Vector2(half, half) + exit.facing * out
			result.append(Vector3(w.x, w.y, APPROACH_CLEAR))
			out += 4.0
	return result


## Places a mouth at every exit; `height` gives the world-frame ground (world.world_ground).
func build(height: Callable, half: float) -> void:
	var scenes := {}
	var rock := _surface(ROCK, 4.0)
	var earth := _surface(EARTH, 3.0)
	var timber := _surface(TIMBER, 0.8, "col")
	for exit in exits():
		var at: Vector2 = exit.map - Vector2(half, half)
		if not scenes.has(exit.scene):
			scenes[exit.scene] = load(exit.scene)
		var mouth: Node3D = scenes[exit.scene].instantiate()
		mouth.name = "CaveMouth_" + str(exit.id).replace(":", "_")
		mouth.set_meta("exit_id", exit.id)
		mouth.position = Vector3(at.x, float(floors.get(exit.id, height.call(at.x, at.y))) + LIFT, at.y)
		# the model's +z points out of the arch
		mouth.rotation.y = atan2(exit.facing.x, exit.facing.y)
		add_child(mouth)
		_dress(mouth, rock, earth, timber)
		mouths.append(mouth)


func _dress(node: Node, rock: Material, earth: Material, timber: Material) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		for s in mesh.get_surface_count():
			var name := mesh.surface_get_material(s).resource_name if mesh.surface_get_material(s) else ""
			if name.contains("rock"):
				node.set_surface_override_material(s, rock)
			elif name.contains("earth"):
				node.set_surface_override_material(s, earth)
			elif name.contains("timber"):
				node.set_surface_override_material(s, timber)
	for child in node.get_children():
		_dress(child, rock, earth, timber)


## Triplanar in world space: the rock keeps its scale over the bulges with no UV seams.
func _surface(path: String, metres: float, colour := "diff") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path % colour)
	m.normal_enabled = true
	m.normal_texture = load(path % "nor_gl")
	m.roughness = 0.95
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / metres
	# the GLB's vertex colour darkens the arch into the hill
	m.vertex_color_use_as_albedo = true
	return m
