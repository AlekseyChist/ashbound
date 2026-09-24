extends SceneTree
func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var names := ["pine_tall", "spruce", "pine_young", "boulder", "stump", "fern", "grass"]
	var failed := false
	for label in names:
		var scene := load("res://models/%s.glb" % label) as PackedScene
		if scene == null:
			failed = true
			continue
		var model := scene.instantiate() as Node3D
		root.add_child(model)
		var bounds := AABB()
		var count := 0
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var box := mesh.global_transform * mesh.get_aabb()
			bounds = box if count == 0 else bounds.merge(box)
			count += 1
		var size := bounds.size
		var valid := size.is_finite() and bounds.position.y > -0.01 and size.y > 0.1
		if label == "pine_tall": valid = valid and size.y >= 8.5 and size.y <= 12.0
		if label == "spruce": valid = valid and size.y >= 6.5 and size.y <= 10.0
		if label == "pine_young": valid = valid and size.y >= 3.5 and size.y <= 6.0
		if not valid: failed = true
		print("ASSET_IMPORT ", label, " valid=",valid," meshes=",count," bounds=",bounds)
		model.free()
	if not failed: print("FOREST_IMPORT_PASS assets=7")
	quit(1 if failed else 0)
