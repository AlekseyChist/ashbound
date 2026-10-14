extends Node3D
## FOREST-CITY-02, night (Codex's night route 14 Oct over the book's light sheet light-weather-v1, C):
## lanterns on posts where the hero needs a light to read the way - outside each gate, at the
## ford's near bank, by the pier's landward end, by the market well. The civic halls' accepted
## lantern (tavern-v1 wooden_lantern_01) on a timber post with an arm; a warm light without shadows,
## lit from dusk to dawn, asleep when the camera is far (as the halls' lights).
const LANTERN := "res://assets/props/tavern-v1/wooden_lantern_01.glb"
const POST_HEIGHT := 2.9
const AWAKE := 45.0
const DUSK := 18.5
const DAWN := 6.5
## Map points (x, z) of the lanterns besides the gates' (from the plan's additions and the well).
const EXTRA := {
	"ford": Vector2(389.5, 909.5),       # the near bank where the ford's marker poles start
	"pier": Vector2(438.2, 917.8),       # beside the pier's landward end (pier 434.1/920.3, yaw -39.3)
}

var city: Node3D
var posts: Array[Node3D] = []
var lights: Array[OmniLight3D] = []
var _check := 0.0
var _lit := false


func build(forest_city: Node3D) -> void:
	city = forest_city
	name = "Lanterns"
	var plan: Dictionary = city.plan
	var centre := Vector2(float(plan.palisade.center[0]), float(plan.palisade.center[1]))
	var radius := float(plan.palisade.radius)
	# Outside each gate, either side of the way out, 3.5 m past the stakes.
	for gate in plan.palisade.gates:
		var out := Vector2.from_angle(deg_to_rad(float(gate.deg)))
		var side := Vector2(-out.y, out.x)
		for s in [-1.0, 1.0]:
			var at: Vector2 = centre + out * (radius + 3.5) + side * s * (city.GATE_WIDTH * 0.5 + 1.0)
			_post(at, -out)
	for key in EXTRA:
		_post(EXTRA[key], Vector2.ZERO)
	# By the market well: the plaza's centre a step aside.
	var plaza := Vector2(float(plan.plaza.center[0]), float(plan.plaza.center[1]))
	_post(plaza + Vector2(3.0, -2.0), Vector2.ZERO)
	_apply(false)
	print("FOREST_CITY_LANTERNS posts=%d" % posts.size())


## A post at the map point `at`; its arm reaches towards `facing` (or +x).
func _post(at: Vector2, facing: Vector2) -> void:
	var ground: Vector3 = city.ground_at(at)
	var post := Node3D.new()
	post.name = "LanternPost%d" % posts.size()
	post.position = ground
	if facing != Vector2.ZERO:
		post.rotation.y = atan2(facing.x, facing.y)
	add_child(post)
	var pole := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.16, POST_HEIGHT + 0.4, 0.16)
	pole.mesh = box
	pole.material_override = city.timber
	pole.position = Vector3(0, (POST_HEIGHT - 0.4) * 0.5, 0)
	post.add_child(pole)
	var arm := MeshInstance3D.new()
	var arm_box := BoxMesh.new()
	arm_box.size = Vector3(0.1, 0.1, 0.75)
	arm.mesh = arm_box
	arm.material_override = city.timber
	arm.position = Vector3(0, POST_HEIGHT - 0.1, 0.35)
	post.add_child(arm)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var shape_box := BoxShape3D.new()
	shape_box.size = Vector3(0.2, POST_HEIGHT, 0.2)
	shape.shape = shape_box
	shape.position = Vector3(0, POST_HEIGHT * 0.5, 0)
	body.add_child(shape)
	post.add_child(body)
	# The lantern hangs from the arm's end on a short cord.
	var hook := Vector3(0, POST_HEIGHT - 0.15, 0.65)
	var lantern: Node3D = (load(LANTERN) as PackedScene).instantiate()
	lantern.position = hook - Vector3(0, 0.75, 0)
	post.add_child(lantern)
	for mesh in lantern.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(mesh as GeometryInstance3D).visibility_range_end = 120.0
	var cord := MeshInstance3D.new()
	var cord_box := BoxMesh.new()
	cord_box.size = Vector3(0.02, 0.4, 0.02)
	cord.mesh = cord_box
	var cord_mat := StandardMaterial3D.new()
	cord_mat.albedo_color = Color(0.25, 0.18, 0.1)
	cord.material_override = cord_mat
	cord.position = hook - Vector3(0, 0.2, 0)
	post.add_child(cord)
	var light := OmniLight3D.new()
	light.name = "LanternLight"
	light.position = hook - Vector3(0, 0.57, 0)
	light.omni_range = 7.0
	light.light_energy = 0.9
	light.light_color = Color(1.0, 0.76, 0.5)
	light.shadow_enabled = false
	post.add_child(light)
	posts.append(post)
	lights.append(light)


func _apply(lit: bool) -> void:
	_lit = lit
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	for i in lights.size():
		var near := camera != null and camera.global_position.distance_to(posts[i].global_position) < AWAKE
		lights[i].visible = lit and near


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	var atmosphere: Node = city.world.get("atmosphere") if city != null and city.world != null else null
	var hour: float = float(atmosphere.hour) if atmosphere != null else 12.0
	_apply(hour >= DUSK or hour < DAWN)
