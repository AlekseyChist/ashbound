extends SceneTree

var failures: Array[String] = []
var results: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run_checks")

func verify(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("VILLAGE_GLB_FAIL: ", message)

func inspect_node(node: Node, state: Dictionary, parent_transform: Transform3D) -> void:
	var transform := parent_transform
	if node is Node3D:
		transform = parent_transform * node.transform
	if node is Camera3D or node is Light3D:
		state.preview_nodes += 1
	if "hinge" in String(node.name).to_lower():
		state.hinges += 1
	if node is MeshInstance3D:
		state.meshes += 1
		var mesh: Mesh = node.mesh
		verify(mesh != null, "%s missing mesh" % node.name)
		if mesh != null:
			for s in range(mesh.get_surface_count()):
				verify(bool(mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_TEX_UV), "%s missing UV" % node.name)
				var material: Material = node.get_active_material(s)
				verify(material != null, "%s missing material" % node.name)
				if material is BaseMaterial3D and material.albedo_texture != null:
					state.textured_surfaces += 1
					verify(material.albedo_texture.get_width() > 0, "%s empty texture" % node.name)
			# Transform actual vertices: transforming a local AABB overestimates rotated parts.
			var points := PackedVector3Array()
			for s in range(mesh.get_surface_count()):
				var vertices: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for vertex in vertices:
					points.append(transform * vertex)
			var aabb := AABB(points[0], Vector3.ZERO)
			for point in points:
				aabb = aabb.expand(point)
			state.bounds = aabb if state.meshes == 1 else state.bounds.merge(aabb)
	for child in node.get_children():
		inspect_node(child, state, transform)

func run_checks() -> void:
	for slug in ["h01", "w01", "b01"]:
		var packed := load("res://models/%s.glb" % slug) as PackedScene
		verify(packed != null, "%s imports as PackedScene" % slug)
		if packed == null:
			continue
		var instance := packed.instantiate()
		var state := {"asset": slug, "meshes": 0, "hinges": 0, "textured_surfaces": 0, "preview_nodes": 0, "bounds": AABB()}
		inspect_node(instance, state, Transform3D.IDENTITY)
		verify(state.meshes > 15, "%s has full geometry" % slug)
		verify(state.hinges > 0, "%s preserves hinge hierarchy" % slug)
		verify(state.textured_surfaces > 0, "%s exports baked textures" % slug)
		verify(state.preview_nodes == 0, "%s excludes preview lights/cameras" % slug)
		var bounds: AABB = state.bounds
		verify(bounds.size.y > 5.0 and bounds.size.y < 10.0, "%s vertical axis/metric height %s" % [slug, bounds.size])
		# Barn depth includes the 3.5 m ramp and rear roof verge: 10 + 3.5 + .525.
		var expected_sizes := {"h01": Vector3(7.278,6.65,9.925), "w01": Vector3(9.714,6.834,10.925), "b01": Vector3(10.314,7.835,14.025)}
		var expected: Vector3 = expected_sizes[slug]
		verify((bounds.size - expected).abs().x < .05 and (bounds.size - expected).abs().y < .05 and (bounds.size - expected).abs().z < .05, "%s exact metric envelope %s expected %s" % [slug,bounds.size,expected])
		state.bounds = {"position": str(bounds.position), "size": str(bounds.size)}
		results.append(state)
		print("VILLAGE_GLB_INSPECTED ", slug, " ", JSON.stringify(state))
		instance.free()
	verify(results.size() == 3, "all three assets complete")
	var file := FileAccess.open("res://result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"results": results, "failures": failures}, "  ") + "\n")
	file.close()
	print("VILLAGE_GLB_COMPLETE assets=", results.size(), " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
