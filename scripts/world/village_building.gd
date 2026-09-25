extends Node3D
const Door = preload("res://scripts/world/village_door.gd")
var record: Dictionary
var model: Node3D
var door: Node3D
var house_materials: RefCounted

func build(data: Dictionary) -> void:
	record = data.duplicate(true)
	name = record.id
	position = record.position
	model = (load(record.scene_path) as PackedScene).instantiate()
	model.name = "Model"
	add_child(model)
	house_materials=preload("res://scripts/world/village_house_materials.gd").new()
	house_materials.apply(model,str(record.id))
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if "entry_leaf" in mesh.name: continue
		var metadata: Dictionary = mesh.get_meta("extras", {})
		var role := str(metadata.get("part_role", ""))
		if role == "foundation" and record.id != "B01": continue
		# A straight flight of stairs is walked on a hidden ramp: the hero does not step up 19 cm risers.
		if "stairs" in str(metadata.get("item_id", "")):
			_stairs_ramp(mesh)
			continue
		var body := StaticBody3D.new()
		body.name = "StaticCollision"
		body.set_meta("footstep_surface", "stone" if role=="foundation" else "wood")
		body.collision_layer = 1 | Door.OBSTACLE_LAYER if role == "furniture" else 1
		body.collision_mask = 0
		mesh.add_child(body)
		var collider := CollisionShape3D.new()
		var shape := mesh.mesh.create_trimesh_shape()
		shape.backface_collision = true
		collider.shape = shape
		body.add_child(collider)
	if record.id != "B01": _stair_proxy()
	door = Door.new()
	door.name = "Door"
	add_child(door)
	door.configure(model, record.id, record.entry)
	var light := OmniLight3D.new()
	light.name = "InteriorFill"
	light.position = Vector3(0, 2.35, 0)
	light.omni_range = 6.5
	light.light_energy = 0.9
	light.light_color = Color(1.0, 0.83, 0.64)
	add_child(light)

func contains(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) < record.width * 0.5 and absf(local.z) < record.depth * 0.5 and local.y > -0.15 and local.y < 3.0

func _stair_proxy() -> void:
	# A continuous collision surface follows the stair noses; visuals stay untouched.
	var platform := BoxShape3D.new()
	platform.size = Vector3(record.width + 0.4, record.floor_height, record.depth + 0.4)
	_add_shape("FoundationCollision", platform, Vector3(0, record.floor_height * 0.5, 0))
	var points := PackedVector3Array()
	var width := 1.8 if record.id == "H01" else 3.0
	var front: float = record.entry.z
	var top: float = record.floor_height
	for x in [-width * 0.5, width * 0.5]:
		for yz in [Vector2(0, front + 1.75), Vector2(top * 0.5, front + 1.4), Vector2(top, front + 0.8), Vector2(top, front + 0.2), Vector2(0, front + 0.2)]:
			points.append(Vector3(record.entry.x + x, yz.x, yz.y))
	var ramp := ConvexPolygonShape3D.new()
	ramp.points = points
	_add_shape("StairWalkingSurface", ramp, Vector3.ZERO)

## A wedge under the treads of a straight flight: from the floor at the low end up to the top
## step at the high end, across the flight's width. The flight runs along local x or z.
func _stairs_ramp(mesh: MeshInstance3D) -> void:
	var faces := mesh.mesh.get_faces()
	if faces.is_empty():
		return
	var to_building: Transform3D = global_transform.affine_inverse() * mesh.global_transform
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	var points: Array[Vector3] = []
	for v in faces:
		var p: Vector3 = to_building * v
		points.append(p)
		low = low.min(p)
		high = high.max(p)
	var along_z := (high.z - low.z) >= (high.x - low.x)
	# The high end is the one whose points reach the top.
	var top_at_max := 0.0
	var top_at_min := 0.0
	for p in points:
		var t: float = (p.z - low.z) / maxf(high.z - low.z, .001) if along_z else (p.x - low.x) / maxf(high.x - low.x, .001)
		if t > .9: top_at_max = maxf(top_at_max, p.y)
		if t < .1: top_at_min = maxf(top_at_min, p.y)
	var top_y := maxf(top_at_max, top_at_min)
	var bottom_end := 0.0 if top_at_max >= top_at_min else 1.0
	var top_end := 1.0 - bottom_end
	var wedge := PackedVector3Array()
	for side in [0.0, 1.0]:
		for e in [[bottom_end, low.y], [top_end, low.y], [top_end, top_y]]:
			var a: float = lerpf(low.z, high.z, e[0]) if along_z else lerpf(low.x, high.x, e[0])
			var b: float = lerpf(low.x, high.x, side) if along_z else lerpf(low.z, high.z, side)
			wedge.append(Vector3(b, e[1], a) if along_z else Vector3(a, e[1], b))
	var ramp := ConvexPolygonShape3D.new()
	ramp.points = wedge
	_add_shape("StairsRamp", ramp, Vector3.ZERO)

func _add_shape(label: String, shape: Shape3D, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.set_meta("footstep_surface", "stone")
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
