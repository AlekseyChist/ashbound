extends Node3D
## WORLD-BUILD-01G: the caves' mouths on the surface - a rock outcrop with an arch into the hill
## (art/blender/world-architecture-v1/build_cave_mouth.py) at every open exit of the caves' plan
## (assets/world/caves-v1/plan.json). The interiors are separate scenes (Codex 300, option B); the
## transition at the mouth's CavePortal is Codex's. Children sit in the world_root frame (map - HALF).

const PLAN := "res://assets/world/caves-v1/plan.json"
const MOUTH := "res://assets/caves-v1/cave_mouth.glb"
const ROCK := "res://assets/environment/cave-rock-v1/rock_face_03_%s_1k.jpg"
const EARTH := "res://assets/environment/village-surfaces-v1/forest_ground_04_%s_1k.jpg"
## The spring's mouth is the headwaters' own (its water runs out of it): not doubled here.
const SKIPPED := ["spring_cave:E"]
## The arch's floor 3 cm over the ground at the exit point (no flicker with the terrain).
const LIFT := 0.03
## Where a slope runs up into the arch, the terrain's points inside this box of the mouth (metres,
## x across, depth into the hill) drop under the floor; the rock hides the cut round them.
const NOTCH_HALF_WIDTH := 4.5
const NOTCH_DEPTH := Vector2(-2.0, 9.0)
const NOTCH_RISE := 0.3
const NOTCH_UNDER := 0.4

var mouths: Array[Node3D] = []
## The ground at each exit before the cut (notch), by exit id: the arch's floor level.
var floors := {}


## The open exits with a place on the map: [{id, map: Vector2, facing: Vector2 (out of the hill)}].
static func exits() -> Array:
	var result: Array = []
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLAN))
	for cave in plan.caves:
		for exit in cave.exits:
			if exit.map == null or str(exit.state) != "open" or SKIPPED.has(str(exit.id)):
				continue
			var facing := Vector2(float(exit.facing[0]), float(exit.facing[1])).normalized()
			result.append({"id": str(exit.id), "map": Vector2(float(exit.map[0]), float(exit.map[1])), "facing": facing})
	return result


## A copy of the world grid with the terrain cut under each arch where the slope climbs into it.
## Flat ground is left alone. `height` is the grid's own sampler (world frame).
func notch(grid: PackedFloat32Array, width: int, step: float, half: float, height: Callable) -> PackedFloat32Array:
	var result := grid.duplicate()
	for exit in exits():
		var at: Vector2 = exit.map - Vector2(half, half)
		var out: Vector2 = exit.facing
		var floor_y: float = height.call(at.x, at.y)
		floors[exit.id] = floor_y
		var reach := NOTCH_DEPTH.y + NOTCH_HALF_WIDTH
		for gz in range(maxi(0, floori((at.y - reach + half) / step)), mini(width, ceili((at.y + reach + half) / step) + 1)):
			for gx in range(maxi(0, floori((at.x - reach + half) / step)), mini(width, ceili((at.x + reach + half) / step) + 1)):
				var d := Vector2(gx * step - half, gz * step - half) - at
				var depth := -d.dot(out)
				var across := absf(d.dot(Vector2(-out.y, out.x)))
				if across > NOTCH_HALF_WIDTH or depth < NOTCH_DEPTH.x or depth > NOTCH_DEPTH.y:
					continue
				var i := gz * width + gx
				if result[i] > floor_y + NOTCH_RISE:
					result[i] = floor_y - NOTCH_UNDER
	return result


## Places a mouth at every exit; `height` gives the world-frame ground (world.world_ground).
func build(height: Callable, half: float) -> void:
	var scene: PackedScene = load(MOUTH)
	var rock := _surface(ROCK, 4.0)
	var earth := _surface(EARTH, 3.0)
	for exit in exits():
		var at: Vector2 = exit.map - Vector2(half, half)
		var mouth: Node3D = scene.instantiate()
		mouth.name = "CaveMouth_" + str(exit.id).replace(":", "_")
		mouth.set_meta("exit_id", exit.id)
		mouth.position = Vector3(at.x, float(floors.get(exit.id, height.call(at.x, at.y))) + LIFT, at.y)
		# the model's +z points out of the arch
		mouth.rotation.y = atan2(exit.facing.x, exit.facing.y)
		add_child(mouth)
		_dress(mouth, rock, earth)
		mouths.append(mouth)


func _dress(node: Node, rock: Material, earth: Material) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		for s in mesh.get_surface_count():
			var name := mesh.surface_get_material(s).resource_name if mesh.surface_get_material(s) else ""
			if name.contains("rock"):
				node.set_surface_override_material(s, rock)
			elif name.contains("earth"):
				node.set_surface_override_material(s, earth)
	for child in node.get_children():
		_dress(child, rock, earth)


## Triplanar in world space: the rock keeps its scale over the bulges with no UV seams.
func _surface(path: String, metres: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path % "diff")
	m.normal_enabled = true
	m.normal_texture = load(path % "nor_gl")
	m.roughness = 0.95
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / metres
	return m
