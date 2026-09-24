extends Node3D
## Static collision heightfield masks precipitation at ground, roofs and the well.
## It is data sampled from this assembled scene, never an edited character image.
var world: Node3D
var drops: MultiMeshInstance3D
var splashes: MultiMeshInstance3D
var cover_image: Image
var materials: Array[ShaderMaterial] = []
var ready_to_draw := false

func configure(scene: Node3D) -> void:
	world=scene
	_build_cover.call_deferred()

func _build_cover() -> void:
	await get_tree().physics_frame
	cover_image=Image.create(226,176,false,Image.FORMAT_RF)
	var space:=world.get_world_3d().direct_space_state
	for z in range(176):
		for x in range(226):
			var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x-95,25,z-95),Vector3(x-95,-8,z-95),1))
			var height: float=hit.position.y if not hit.is_empty() else world.terrain.height_at(x-95,z-95)
			cover_image.set_pixel(x,z,Color(height,0,0,1))
	var texture:=ImageTexture.create_from_image(cover_image)
	drops=_batch(1100,false,texture)
	splashes=_batch(180,true,texture)
	ready_to_draw=true
	print("VILLAGE_RAIN_READY cover=226x176 drops=1100 splashes=180")

func _batch(count: int, splash: bool, texture: Texture2D) -> MultiMeshInstance3D:
	var node:=MultiMeshInstance3D.new()
	node.name="Splashes" if splash else "Rain"
	var multi:=MultiMesh.new()
	multi.transform_format=MultiMesh.TRANSFORM_3D
	multi.use_custom_data=true
	if splash:
		var mesh:=PlaneMesh.new();mesh.size=Vector2(.4,.4);multi.mesh=mesh
	else:
		var mesh:=QuadMesh.new();mesh.size=Vector2(.035,.48);multi.mesh=mesh
	multi.instance_count=count
	var rng:=RandomNumberGenerator.new();rng.seed=390 if splash else 391
	for i in range(count):
		multi.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3(rng.randf_range(-13,13),0,rng.randf_range(-13,13))))
		multi.set_instance_custom_data(i,Color(rng.randf(),rng.randf(),0,1))
	node.multimesh=multi
	node.custom_aabb=AABB(Vector3(-15,-4,-15),Vector3(30,25,30))
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material:=ShaderMaterial.new();material.shader=preload("res://assets/shaders/village_rain.gdshader")
	material.set_shader_parameter("cover_heights",texture)
	material.set_shader_parameter("splash",splash)
	node.material_override=material
	materials.append(material)
	add_child(node)
	return node

func update_weather(time: float, intensity: float, wind: float, daylight: float) -> void:
	if not ready_to_draw: return
	global_position=world.player.global_position
	visible=intensity>.005
	drops.multimesh.visible_instance_count=int(1100*intensity)
	splashes.multimesh.visible_instance_count=int(180*intensity)
	for material in materials:
		material.set_shader_parameter("volume_center",global_position)
		material.set_shader_parameter("effect_time",time)
		material.set_shader_parameter("intensity",minf(intensity*1.4,1.0))
		material.set_shader_parameter("wind_strength",wind)
		material.set_shader_parameter("daylight",daylight)

func cover_height(at: Vector2) -> float:
	if cover_image==null: return -INF
	return cover_image.get_pixel(clampi(roundi(at.x+95),0,225),clampi(roundi(at.y+95),0,175)).r
