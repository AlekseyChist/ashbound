extends Node3D
## Graybox landmark silhouettes for world layout (coarse, untextured, passive markers).
## Not final assets: no collision, interiors, labels or input.

const _PALETTE := {
	"clay": Color("#92938b"),
	"roof": Color("#766a56"),
	"rock": Color("#777970"),
	"dark": Color("#252a29"),
	"timber": Color("#6e5f4c"),
	"ore": Color("#5a5148"),
}


func build(kind: String, origin: Vector3, facing: Vector3) -> void:
	if kind != "settlement" and kind != "tavern" and kind != "cave" and kind != "mine":
		push_error("world_graybox_landmarks: unknown kind '%s'" % kind)
		return

	# Clear previous children on rebuild.
	for child in get_children():
		remove_child(child)
		child.queue_free()

	position = origin
	if facing.x != 0.0 or facing.z != 0.0:
		rotation.y = atan2(facing.x, facing.z)

	match kind:
		"settlement":
			_build_settlement()
		"tavern":
			_build_tavern()
		"cave":
			_build_cave()
		"mine":
			_build_mine()


func _box(center: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.emission_enabled = false
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = center
	add_child(node)
	return node


# --- settlement: three small houses, walls + two-slope pitched roofs ---

func _build_settlement() -> void:
	var wall_color: Color = _PALETTE["clay"]
	var roof_color: Color = _PALETTE["roof"]
	# House positions: either side and back, all behind the approach (z < -2).
	var spots: Array[Vector3] = [
		Vector3(-6.0, 0.0, -8.0),
		Vector3(6.0, 0.0, -9.0),
		Vector3(0.0, 0.0, -14.0),
	]
	for spot in spots:
		_house(spot, wall_color, roof_color)


func _house(at: Vector3, wall_color: Color, roof_color: Color) -> void:
	# Walls: 3 x 2.4 x 3 box, bottom at y=0.
	_box(at + Vector3(0.0, 1.2, 0.0), Vector3(3.0, 2.4, 3.0), wall_color)
	# Pitched roof: two thin rotated box slopes meeting at the ridge (y ~ 3.6).
	var slope := _box(at + Vector3(-0.85, 3.1, 0.0), Vector3(2.4, 0.15, 3.6), roof_color)
	slope.rotation.z = deg_to_rad(28.0)
	var slope2 := _box(at + Vector3(0.85, 3.1, 0.0), Vector3(2.4, 0.15, 3.6), roof_color)
	slope2.rotation.z = deg_to_rad(-28.0)


# --- tavern: larger two-story house at z=-12 with chimney, porch and signpost ---

func _build_tavern() -> void:
	var wall_color: Color = _PALETTE["clay"]
	var roof_color: Color = _PALETTE["roof"]
	var dark_color: Color = _PALETTE["dark"]
	var base := Vector3(0.0, 0.0, -12.0)
	# Two-story body: 6 x 5 x 5.
	_box(base + Vector3(0.0, 2.5, 0.0), Vector3(6.0, 5.0, 5.0), wall_color)
	# Pitched roof over the whole building.
	var slope := _box(base + Vector3(-1.7, 5.9, 0.0), Vector3(4.2, 0.2, 6.4), roof_color)
	slope.rotation.z = deg_to_rad(28.0)
	var slope2 := _box(base + Vector3(1.7, 5.9, 0.0), Vector3(4.2, 0.2, 6.4), roof_color)
	slope2.rotation.z = deg_to_rad(-28.0)
	# Chimney on the roof.
	_box(base + Vector3(2.0, 5.6, -1.2), Vector3(0.8, 2.0, 0.8), _PALETTE["rock"])
	# Doorway: dark flat box on the approach face (local +z side of the house).
	_box(base + Vector3(0.0, 1.1, 2.56), Vector3(1.4, 2.2, 0.12), dark_color)
	# Porch columns flanking the doorway.
	_box(base + Vector3(-1.1, 1.0, 2.9), Vector3(0.3, 2.0, 0.3), _PALETTE["timber"])
	_box(base + Vector3(1.1, 1.0, 2.9), Vector3(0.3, 2.0, 0.3), _PALETTE["timber"])
	# Signpost outside the doorway to one side.
	var post := _box(base + Vector3(2.6, 1.0, 3.4), Vector3(0.15, 2.0, 0.15), _PALETTE["timber"])
	post.rotation.y = deg_to_rad(15.0)
	_box(base + Vector3(2.6, 1.7, 3.4), Vector3(1.2, 0.5, 0.1), roof_color)


# --- cave: two rock pillars + cap forming a ~4m opening, dark back panel at z=-12 ---

func _build_cave() -> void:
	var rock_color: Color = _PALETTE["rock"]
	var dark_color: Color = _PALETTE["dark"]
	# Dark back panel.
	_box(Vector3(0.0, 2.5, -12.0), Vector3(9.0, 5.0, 0.6), dark_color)
	# Two irregular rock pillars (slightly rotated boxes for a rocky feel).
	var left := _box(Vector3(-3.0, 2.2, -8.0), Vector3(2.4, 4.4, 3.0), rock_color)
	left.rotation.y = deg_to_rad(6.0)
	var right := _box(Vector3(3.0, 2.2, -8.0), Vector3(2.4, 4.4, 3.0), rock_color)
	right.rotation.y = deg_to_rad(-5.0)
	# Rock cap bridging the pillars; opening between them is ~4m wide.
	var cap := _box(Vector3(0.0, 4.6, -8.0), Vector3(9.0, 1.6, 3.2), rock_color)
	cap.rotation.y = deg_to_rad(2.0)


# --- mine: cave portal reinforced with timber, two rails and an ore pile ---

func _build_mine() -> void:
	var rock_color: Color = _PALETTE["rock"]
	var dark_color: Color = _PALETTE["dark"]
	var timber_color: Color = _PALETTE["timber"]
	var ore_color: Color = _PALETTE["ore"]
	# Portal back panel.
	_box(Vector3(0.0, 2.5, -12.0), Vector3(8.0, 5.0, 0.6), dark_color)
	# Rock pillars framing the mouth.
	var left := _box(Vector3(-2.6, 2.2, -8.0), Vector3(2.0, 4.4, 2.8), rock_color)
	left.rotation.y = deg_to_rad(4.0)
	var right := _box(Vector3(2.6, 2.2, -8.0), Vector3(2.0, 4.4, 2.8), rock_color)
	right.rotation.y = deg_to_rad(-4.0)
	_box(Vector3(0.0, 4.5, -8.0), Vector3(7.6, 1.4, 3.0), rock_color)
	# Muted timber reinforcement around the portal.
	var beam_l := _box(Vector3(-2.6, 2.2, -6.4), Vector3(0.5, 4.4, 0.5), timber_color)
	beam_l.rotation.y = deg_to_rad(8.0)
	var beam_r := _box(Vector3(2.6, 2.2, -6.4), Vector3(0.5, 4.4, 0.5), timber_color)
	beam_r.rotation.y = deg_to_rad(-8.0)
	_box(Vector3(0.0, 4.4, -6.4), Vector3(6.0, 0.5, 0.5), timber_color)
	# Two short parallel rails entering the mouth.
	_box(Vector3(-0.7, 0.15, -5.2), Vector3(0.25, 0.3, 4.0), timber_color)
	_box(Vector3(0.7, 0.15, -5.2), Vector3(0.25, 0.3, 4.0), timber_color)
	# Small ore pile: three rotated boxes aside.
	var o1 := _box(Vector3(-4.6, 0.5, -5.0), Vector3(1.6, 1.0, 1.6), ore_color)
	o1.rotation.y = deg_to_rad(20.0)
	var o2 := _box(Vector3(-3.8, 0.4, -4.2), Vector3(1.2, 0.8, 1.2), ore_color)
	o2.rotation.y = deg_to_rad(-35.0)
	var o3 := _box(Vector3(-4.9, 0.35, -4.0), Vector3(1.0, 0.7, 1.0), ore_color)
	o3.rotation.y = deg_to_rad(60.0)
