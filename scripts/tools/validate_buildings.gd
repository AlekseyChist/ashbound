extends SceneTree
# AshBound — headless building validator.
# Run: godot --headless --path PROJECT --script scripts/tools/validate_buildings.gd

const BUILDINGS := {
	"house": {"min": Vector3(5, 5, 5), "max": Vector3(8, 9, 9)},
	"watchtower": {"min": Vector3(2, 7, 2), "max": Vector3(5, 10, 5)},
	"gate": {"min": Vector3(7, 4, 1), "max": Vector3(10, 6, 3)},
}

const EXPECTED_TRIS := {
	"house": 22124,
	"watchtower": 11972,
	"gate": 6028,
}

var _failures: Array[String] = []
var _tris: Dictionary = {}
var _test_root: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if not _failures.is_empty():
		for f in _failures:
			push_error("ASHBOUND_BUILDINGS_FAIL: " + f)
		quit(1)
	else:
		print("ASHBOUND_BUILDINGS_OK house=%d watchtower=%d gate=%d" % [_tris.get("house", 0), _tris.get("watchtower", 0), _tris.get("gate", 0)])
		quit(0)


func _run() -> void:
	_test_root = Node3D.new()
	get_root().add_child(_test_root)

	for name in BUILDINGS.keys():
		var glb_path := "res://assets/buildings/ashbound/%s.glb" % name
		var scn_path := "res://scenes/buildings/%s.tscn" % name
		if not ResourceLoader.exists(glb_path):
			_fail("missing GLB: " + glb_path)
			continue
		if not ResourceLoader.exists(scn_path):
			_fail("missing wrapper scene: " + scn_path)
			continue
		var packed := load(scn_path) as PackedScene
		if packed == null:
			_fail("cannot load " + scn_path)
			continue
		var inst := packed.instantiate()
		if inst == null:
			_fail("cannot instantiate " + scn_path)
			continue
		_test_root.add_child(inst)
		await process_frame
		await physics_frame

		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(inst, meshes)
		if meshes.is_empty():
			_fail("%s: no MeshInstance3D found" % name)
			inst.queue_free()
			continue

		var total_tris := 0
		var merged := AABB()
		var first := true
		for mi in meshes:
			if mi.mesh == null:
				_fail("%s: MeshInstance3D without mesh" % name)
				continue
			total_tris += _count_tris(mi.mesh as Mesh)
			if not _mesh_materials_ok(mi):
				_fail("%s: surface without assigned material" % name)
			var aabb := (mi as Node3D).global_transform * (mi.mesh as Mesh).get_aabb()
			if first:
				merged = aabb
				first = false
			else:
				merged = merged.merge(aabb)

		if total_tris <= 0:
			_fail("%s: mesh has no triangle surfaces" % name)
			inst.queue_free()
			continue
		var expected := int(EXPECTED_TRIS[name])
		if total_tris != expected:
			_fail("%s: triangles %d, expected %d" % [name, total_tris, expected])
		_tris[name] = total_tris

		if not _finite(merged) or merged.size.x <= 0.0 or merged.size.y <= 0.0 or merged.size.z <= 0.0:
			_fail("%s: non-finite/empty global AABB" % name)
		else:
			var d: Vector3 = merged.size
			var lim: Dictionary = BUILDINGS[name]
			var mn: Vector3 = lim["min"]
			var mx: Vector3 = lim["max"]
			if d.x < mn.x or d.y < mn.y or d.z < mn.z or d.x > mx.x or d.y > mx.y or d.z > mx.z:
				_fail("%s: dims %s outside expected range" % [name, str(d)])

		if not _has_collision(inst):
			_fail("%s: no enabled CollisionShape3D under StaticBody3D" % name)

		inst.queue_free()
		await process_frame
		await physics_frame
		await physics_frame

	await _check_gate()
	await _check_showcase()
	_test_root.queue_free()
	_finish()


func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		_collect_meshes(c, out)


func _mesh_materials_ok(mi: MeshInstance3D) -> bool:
	var mesh := mi.mesh as Mesh
	if mesh == null:
		return false
	for i in mesh.get_surface_count():
		var mat := mi.get_active_material(i)
		if mat == null:
			return false
	return true


func _count_tris(mesh: Mesh) -> int:
	var total := 0
	for i in mesh.get_surface_count():
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arr: Array = mesh.surface_get_arrays(i)
		if arr.is_empty():
			continue
		var indices: Variant = null
		var vertices: Variant = null
		if Mesh.ARRAY_INDEX < arr.size():
			indices = arr[Mesh.ARRAY_INDEX]
		if Mesh.ARRAY_VERTEX < arr.size():
			vertices = arr[Mesh.ARRAY_VERTEX]
		if indices != null and (indices as Array).size() > 0:
			total += int((indices as Array).size()) / 3
		elif vertices != null and (vertices as Array).size() > 0:
			total += int((vertices as Array).size()) / 3
	return total


func _finite(aabb: AABB) -> bool:
	return aabb.position.is_finite() and aabb.size.is_finite()


func _has_collision(n: Node) -> bool:
	if n is StaticBody3D:
		for c in n.get_children():
			if c is CollisionShape3D:
				var cs := c as CollisionShape3D
				if cs.shape != null and not cs.disabled:
					return true
	for c in n.get_children():
		if _has_collision(c):
			return true
	return false


func _ray(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	var res: Dictionary = _test_root.get_world_3d().direct_space_state.intersect_ray(q)
	return res.has("position")


func _check_gate() -> void:
	var packed := load("res://scenes/buildings/gate.tscn") as PackedScene
	if packed == null:
		_fail("gate: cannot load for physics check")
		return
	var gate := packed.instantiate()
	if gate == null:
		_fail("gate: cannot instantiate for physics check")
		return
	_test_root.add_child(gate)
	await process_frame
	await physics_frame
	await physics_frame

	if _ray(Vector3(0, 1, 5), Vector3(0, 1, -5)):
		_fail("gate: central passage ray (0,1,5)->(0,1,-5) must miss")
	if not _ray(Vector3(3, 1, 5), Vector3(3, 1, -5)):
		_fail("gate: pier ray at x=3 must hit")

	gate.queue_free()
	await process_frame
	await physics_frame
	await physics_frame


func _check_showcase() -> void:
	var path := "res://scenes/environments/building_showcase.tscn"
	if not ResourceLoader.exists(path):
		_fail("missing " + path)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		_fail("cannot load " + path)
		return
	var inst := packed.instantiate()
	if inst == null:
		_fail("cannot instantiate " + path)
		return
	_test_root.add_child(inst)
	await process_frame
	await physics_frame

	var has_cam := false
	var has_env := false
	for n in _walk(inst):
		if n is Camera3D:
			has_cam = true
		elif n is WorldEnvironment:
			if (n as WorldEnvironment).environment != null:
				has_env = true

	var ok_buildings := true
	for i in 3:
		var child_name := "Building%d" % i
		var found := false
		for c in inst.get_children():
			if c.name == child_name:
				found = true
				var meshes: Array[MeshInstance3D] = []
				_collect_meshes(c, meshes)
				var has_mesh := false
				for mi in meshes:
					if mi.mesh != null:
						has_mesh = true
						break
				if not has_mesh:
					_fail("showcase: %s contains no meshes" % child_name)
					ok_buildings = false
				break
		if not found:
			_fail("showcase: missing root child " + child_name)
			ok_buildings = false

	if not has_cam:
		_fail("showcase: no Camera3D")
	if not has_env:
		_fail("showcase: no WorldEnvironment with environment")
	if not ok_buildings:
		_fail("showcase: Building0/1/2 must each contain meshes")

	inst.queue_free()
	await process_frame
	await physics_frame
	await physics_frame


func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
