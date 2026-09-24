extends Node3D
## Deterministic dressing; vegetation repetitions are batched in spatial chunks.
var tree_positions: Array[Vector3] = []
var terrain: Node3D
var foliage_batches: Array[MultiMeshInstance3D] = []
var rng := RandomNumberGenerator.new()

func build(ground: Node3D, buildings: Array[Node3D]) -> void:
	terrain = ground
	rng.seed = 240926
	var variants: Array = [[],[],[]]
	for attempt in range(6000):
		if tree_positions.size() >= 280: break
		var point := Vector2(rng.randf_range(-91,126),rng.randf_range(-91,76))
		if not terrain.forest_contains(point) or terrain.reserved(point,2.0): continue
		var road: Vector2 = terrain.road_info(point)
		if road.x < road.y*.5+3.4: continue
		var near := false
		for other in tree_positions:
			if Vector2(other.x,other.z).distance_squared_to(point)<28.0:
				near=true
				break
		if near: continue
		var at := Vector3(point.x,terrain.height_at(point.x,point.y),point.y)
		tree_positions.append(at)
		var size := rng.randf_range(.85,1.25)
		var transform := Transform3D(Basis(Vector3.UP,rng.randf_range(-PI,PI)).scaled(Vector3.ONE*size),at)
		variants[rng.randi_range(0,2)].append(transform)
		var body := StaticBody3D.new()
		body.collision_layer=1
		body.collision_mask=0
		body.position=at+Vector3.UP*1.2
		var shape := CollisionShape3D.new()
		var trunk := CylinderShape3D.new()
		trunk.radius=.26*size
		trunk.height=2.4
		shape.shape=trunk
		body.add_child(shape)
		add_child(body)
	for i in range(3): _batch(["pine_tall","spruce","pine_young"][i],variants[i],true,180)
	var grass: Array = []
	var ferns: Array = []
	var rocks: Array = []
	for i in range(3000):
		var point := Vector2(rng.randf_range(-55,80),rng.randf_range(-60,70))
		if terrain.reserved(point,.5): continue
		var road: Vector2 = terrain.road_info(point)
		if road.x < road.y*.5+.8: continue
		var at := Vector3(point.x,terrain.height_at(point.x,point.y),point.y)
		var size := rng.randf_range(.7,1.4)
		var transform := Transform3D(Basis(Vector3.UP,rng.randf_range(-PI,PI)).scaled(Vector3.ONE*size),at)
		if i%11==0: ferns.append(transform)
		elif i%31==0: rocks.append(transform)
		else: grass.append(transform)
	_batch("grass",grass,false,42)
	_batch("fern",ferns,false,65)
	_batch("boulder",rocks,true,95)
	var well: Dictionary = terrain.data.well
	var at := Vector3(float(well.x)-terrain.ORIGIN.x,well.elevation_m,float(well.y)-terrain.ORIGIN.y)
	_prop("res://assets/buildings/ashbound/courtyard_well.glb",at,0,Vector3.ONE,true)
	for building in buildings:
		_dress_yard(building)
	print("VILLAGE_DRESSING trees=",tree_positions.size()," grass=",grass.size()," fern=",ferns.size())

func _batch(asset: String, transforms: Array, shadows: bool, distance: float) -> void:
	var model := (load("res://assets/environment/village-forest-v1/%s.glb"%asset) as PackedScene).instantiate() as Node3D
	add_child(model)
	var chunks: Dictionary = {}
	for transform: Transform3D in transforms:
		var key := Vector2i(floori(transform.origin.x/28),floori(transform.origin.z/28))
		if not chunks.has(key): chunks[key]=[]
		chunks[key].append(transform)
	for child: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		for key in chunks:
			var list: Array = chunks[key]
			var batch := MultiMeshInstance3D.new()
			batch.name=asset+"_"+child.name
			var multi := MultiMesh.new()
			multi.transform_format=MultiMesh.TRANSFORM_3D
			multi.mesh=child.mesh
			multi.instance_count=list.size()
			var center := Vector3(float(key.x)*28+14,0,float(key.y)*28+14)
			for i in range(list.size()):
				var transform: Transform3D=list[i]*child.global_transform
				transform.origin -= center
				multi.set_instance_transform(i,transform)
			batch.multimesh=multi
			batch.position=center
			batch.visibility_range_end=distance
			batch.visibility_range_end_margin=10
			batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(batch)
			if child.get_meta("extras",{}).get("part_role","")=="foliage": foliage_batches.append(batch)
	model.free()

func _prop(path: String, at: Vector3, yaw: float, size: Vector3, collision: bool) -> Node3D:
	var model := (load(path) as PackedScene).instantiate() as Node3D
	add_child(model)
	model.position=at
	model.rotation.y=yaw
	model.scale=size
	if collision:
		for child: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false): child.create_trimesh_collision()
	return model

func _dress_yard(building: Node3D) -> void:
	var width: float = building.record.width
	var depth: float = building.record.depth
	var decorations := [Vector3(width*.5+1.1,0,-depth*.25),Vector3(-width*.5-1.0,0,-depth*.4)]
	for i in range(decorations.size()):
		var at: Vector3 = building.to_global(decorations[i])
		at.y=terrain.height_at(at.x,at.z)
		_prop("res://assets/environment/medieval_kit/detail-barrel.glb" if i==0 else "res://assets/environment/medieval_kit/detail-crate.glb",at,building.rotation.y,Vector3.ONE,true)
	# Side and back fences retain a wide open frontage and the reviewed entry clearance.
	for side in [-1,1]:
		for segment in range(4):
			var local := Vector3(side*(width*.5+3.0),0,-depth*.5+float(segment)*2.0)
			var at: Vector3=building.to_global(local)
			at.y=terrain.height_at(at.x,at.z)
			_prop("res://assets/environment/medieval_kit/fence-wood.glb",at,building.rotation.y+PI*.5,Vector3.ONE,true)
	var at: Vector3=building.to_global(Vector3(width*.5+1.2,0,depth*.15))
	at.y=terrain.height_at(at.x,at.z)
	_prop("res://assets/environment/village-forest-v1/stump.glb",at,0,Vector3.ONE,true)
