extends SceneTree
func _initialize() -> void:
	call_deferred("show_kit")

func show_kit() -> void:
	root.size = Vector2i(1280,720)
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("3f514d")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("8b9b9b")
	env.environment.ambient_light_energy = 0.45
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42,-35,0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	scene.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40,35)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("414b30")
	ground.material_override = mat
	scene.add_child(ground)
	var positions := {"h01":Vector3(-4,0,0),"spruce":Vector3(3,0,-2),"pine_tall":Vector3(8,0,-5),"pine_young":Vector3(8,0,3),"fern":Vector3(2,0,4),"boulder":Vector3(4,0,4),"stump":Vector3(1,0,5),"grass":Vector3(3,0,5)}
	for label in positions:
		var node := (load("res://models/%s.glb"%label) as PackedScene).instantiate() as Node3D
		scene.add_child(node)
		node.position = positions[label]
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.position = Vector3(16,11,22)
	cam.look_at(Vector3(0,3,0))
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 22
	cam.make_current()
	for i in range(20): await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("user://kit-with-house.png")
	print("FOREST_COMPARISON ",result," path=",ProjectSettings.globalize_path("user://kit-with-house.png"))
	quit(result)
