extends Node3D
## Deterministic dressing; vegetation repetitions are batched in spatial chunks.
var tree_positions: Array[Vector3] = []
var terrain: Node3D
var foliage_batches: Array[MultiMeshInstance3D] = []
var rng := RandomNumberGenerator.new()
var household: Node3D
## LANDSCAPE-01: CC0 Poly Haven forest floor (assets/environment/forest-floor-v1), lightened for the phone.
const FLOOR_KIT := "res://assets/environment/forest-floor-v1/%s.glb"
## Stones on the meadow, boulders in the woods: single rocks out of the two mossy sets.
const STONES := [["rock_moss_set_02", "rock_moss_set_02_rock08"], ["rock_moss_set_02", "rock_moss_set_02_rock12"]]
const BOULDERS := [["rock_moss_set_02", "rock_moss_set_02_rock07"], ["rock_moss_set_02", "rock_moss_set_02_rock11"]]
const FERNS := [["fern_02", "fern_02_b"], ["fern_02", "fern_02_c"]]
## Placed forest-floor pieces by kind, for the tests: {kind: count}.
var floor_counts: Dictionary = {}
## A separate generator, so the trees, grass and ferns keep their reviewed places.
var floor_rng := RandomNumberGenerator.new()
## (x, z, radius) the grass keeps clear of: trunks, logs, rocks (village_grass.gd).
var clearings: Array[Vector3] = []
## Every scattered kit piece as [part name, footprint transform] (headless builds keep no MultiMesh data).
var floor_pieces: Array = []

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
		clearings.append(Vector3(at.x,at.z,1.8*size))
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
	var ferns: Array = [[], []]
	var rocks: Array = [[], []]
	floor_rng.seed = 250925
	for i in range(3000):
		var point := Vector2(rng.randf_range(-55,80),rng.randf_range(-60,70))
		if terrain.reserved(point,.5): continue
		var road: Vector2 = terrain.road_info(point)
		if road.x < road.y*.5+.8: continue
		var at := Vector3(point.x,terrain.height_at(point.x,point.y),point.y)
		var size := rng.randf_range(.7,1.4)
		var transform := Transform3D(Basis(Vector3.UP,rng.randf_range(-PI,PI)).scaled(Vector3.ONE*size),at)
		if i%11==0: ferns[floor_rng.randi_range(0,1)].append(transform)
		elif i%31==0:
			var stone := Transform3D(transform.basis.scaled(Vector3.ONE*.45),at)
			var kind := floor_rng.randi_range(0,1)
			rocks[kind].append(stone)
			_solid(STONES[kind],stone,.3)
		else: grass.append(transform)
	_batch("grass",grass,false,42)
	for kind in 2:
		_scatter(FERNS[kind],ferns[kind],false,65,56,true)
		_scatter(STONES[kind],rocks[kind],true,95,56,false)
	floor_counts["fern"]=ferns[0].size()+ferns[1].size()
	floor_counts["stone"]=rocks[0].size()+rocks[1].size()
	_forest_floor()
	var well: Dictionary = terrain.data.well
	var at := Vector3(float(well.x)-terrain.ORIGIN.x,well.elevation_m,float(well.y)-terrain.ORIGIN.y)
	_prop("res://assets/buildings/ashbound/courtyard_well.glb",at,0,Vector3.ONE,true)
	for building in buildings:
		_dress_yard(building)
	_neighbours(buildings)
	household = preload("res://scripts/world/village_props.gd").new()
	household.name = "Household"
	add_child(household)
	household.build(terrain, buildings)
	print("VILLAGE_DRESSING trees=",tree_positions.size()," grass=",grass.size()," floor=",floor_counts)

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

## Between the trees: roots at some trunks, fallen logs, dry branches, mossy boulders.
func _forest_floor() -> void:
	var roots: Array = []
	for i in range(tree_positions.size()):
		if i%3!=0: continue
		var at: Vector3=tree_positions[i]
		roots.append(Transform3D(Basis(Vector3.UP,floor_rng.randf_range(-PI,PI)).scaled(Vector3.ONE*floor_rng.randf_range(.8,1.15)),at-Vector3.UP*.03))
	_scatter(["pine_roots","pine_roots_a"],roots,false,50,56,false)
	floor_counts["roots"]=roots.size()
	var logs: Array = []
	var branches: Array = []
	var boulders: Array = [[],[]]
	var taken: Array[Vector2] = []
	for attempt in range(4000):
		if logs.size()>=34 and branches.size()>=70 and boulders[0].size()+boulders[1].size()>=44: break
		var point := Vector2(floor_rng.randf_range(-91,126),floor_rng.randf_range(-91,76))
		if not terrain.forest_contains(point) or terrain.reserved(point,2.5): continue
		var road: Vector2 = terrain.road_info(point)
		if road.x < road.y*.5+2.5: continue
		var clear := true
		for tree in tree_positions:
			if Vector2(tree.x,tree.z).distance_squared_to(point)<2.6:
				clear=false
				break
		for other in taken:
			if other.distance_squared_to(point)<5.0:
				clear=false
				break
		if not clear: continue
		var at := Vector3(point.x,terrain.height_at(point.x,point.y)-.04,point.y)
		var turn := Basis(Vector3.UP,floor_rng.randf_range(-PI,PI))
		var pick := attempt%3
		if pick==0 and logs.size()<34:
			var fallen := Transform3D(turn.scaled(Vector3.ONE*floor_rng.randf_range(1.1,1.5)),at)
			logs.append(fallen)
			_solid(["dead_tree_trunk","dead_tree_trunk"],fallen,0.0)
		elif pick==1 and branches.size()<70:
			branches.append(Transform3D(turn.scaled(Vector3.ONE*floor_rng.randf_range(.8,1.3)),at+Vector3.UP*.03))
		elif pick==2 and boulders[0].size()+boulders[1].size()<44:
			var kind := floor_rng.randi_range(0,1)
			var rock := Transform3D(turn.scaled(Vector3.ONE*floor_rng.randf_range(.45,.85)),at-Vector3.UP*.08)
			boulders[kind].append(rock)
			_solid(BOULDERS[kind],rock,0.0)
		else:
			continue
		taken.append(point)
	_scatter(["dead_tree_trunk","dead_tree_trunk"],logs,true,70,56,false)
	_scatter(["dry_branches_medium_01","dry_branches_medium_01_a"],branches,false,40,56,false)
	for kind in 2:
		_scatter(BOULDERS[kind],boulders[kind],true,110,56,false)
	floor_counts["log"]=logs.size()
	floor_counts["branches"]=branches.size()
	floor_counts["boulder"]=boulders[0].size()+boulders[1].size()

var _parts: Dictionary = {}

## One mesh out of a kit model, moved so that its footprint centre sits on the origin and its base on y 0.
func _part(piece: Array) -> Dictionary:
	var key := "%s/%s"%piece
	if _parts.has(key): return _parts[key]
	var model := (load(FLOOR_KIT%piece[0]) as PackedScene).instantiate() as Node3D
	var found := {}
	for child: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if child.name!=piece[1]: continue
		var local := child.transform
		var parent := child.get_parent()
		while parent!=model and parent is Node3D:
			local=(parent as Node3D).transform*local
			parent=parent.get_parent()
		var box: AABB=local*child.mesh.get_aabb()
		var centre := box.get_center()
		found={"mesh":child.mesh,"offset":Transform3D(Basis(),Vector3(-centre.x,-box.position.y,-centre.z))*local,"size":box.size}
		break
	model.free()
	if found.is_empty(): push_error("forest floor part missing: "+key)
	_parts[key]=found
	return found

## Batches one kit part in spatial chunks, like _batch; ferns join the wind (foliage) batches.
func _scatter(piece: Array, transforms: Array, shadows: bool, distance: float, chunk: float, foliage: bool) -> void:
	if transforms.is_empty(): return
	var part := _part(piece)
	var chunks: Dictionary = {}
	for transform: Transform3D in transforms:
		floor_pieces.append([piece[1],transform])
		var key := Vector2i(floori(transform.origin.x/chunk),floori(transform.origin.z/chunk))
		if not chunks.has(key): chunks[key]=[]
		chunks[key].append(transform)
	for key in chunks:
		var list: Array = chunks[key]
		var batch := MultiMeshInstance3D.new()
		batch.name="%s_%d_%d"%[piece[1],key.x,key.y]
		var multi := MultiMesh.new()
		multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.mesh=part.mesh
		multi.instance_count=list.size()
		var center := Vector3(float(key.x)*chunk+chunk*.5,0,float(key.y)*chunk+chunk*.5)
		for i in range(list.size()):
			var transform: Transform3D=list[i]*part.offset
			transform.origin -= center
			multi.set_instance_transform(i,transform)
		batch.multimesh=multi
		batch.position=center
		batch.visibility_range_end=distance
		batch.visibility_range_end_margin=10
		batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch)
		if foliage: foliage_batches.append(batch)

## A box the hero cannot walk through; pieces lower than `step` are stepped over.
func _solid(piece: Array, transform: Transform3D, step: float) -> void:
	var part := _part(piece)
	var size: Vector3=part.size*transform.basis.get_scale()
	# Short grass around it: a row of circles along its longer side (a log gets several).
	var along: Vector3=transform.basis.x.normalized() if size.x>=size.z else transform.basis.z.normalized()
	var length: float=maxf(size.x,size.z)
	var radius: float=minf(size.x,size.z)*.5+.5
	var count: int=maxi(1,ceili(length/(radius*2.0)))
	for i in count:
		var at: Vector3=transform.origin+along*((float(i)+.5)/count-.5)*length
		clearings.append(Vector3(at.x,at.z,radius))
	if size.y<=step: return
	var body := StaticBody3D.new()
	body.name="FloorSolid%d"%get_child_count()
	body.collision_layer=1
	body.collision_mask=0
	body.transform=Transform3D(transform.basis.orthonormalized(),transform.origin+Vector3.UP*size.y*.5)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size=size*Vector3(.8,1,.8)
	shape.shape=box
	body.add_child(shape)
	add_child(body)

## HOUSES-01 (owner, 25 Sep): more houses in the village, to see the phone's load. The three yard
## models again as neighbours by the roads: closed doors, no interior light or furniture, solid.
const NEIGHBOUR_COUNT := 6
const NEIGHBOUR_MODELS := ["H01", "W01", "H01", "B01", "H01", "W01"]
var neighbours: Array[Node3D] = []

func _neighbours(buildings: Array[Node3D]) -> void:
	var catalog := {}
	for record in preload("res://scripts/world/village_building_catalog.gd").all():
		catalog[record.id] = record
	var house_rng := RandomNumberGenerator.new()
	house_rng.seed = 250927
	var placed: Array[Vector2] = []
	for building in buildings:
		placed.append(Vector2(building.position.x, building.position.z))
	for attempt in range(4000):
		if neighbours.size() >= NEIGHBOUR_COUNT: break
		var record: Dictionary = catalog[NEIGHBOUR_MODELS[neighbours.size()]]
		var half := maxf(float(record.width), float(record.depth)) * .5
		var point := Vector2(house_rng.randf_range(-80, 115), house_rng.randf_range(-80, 65))
		if terrain.forest_contains(point) or terrain.reserved(point, half + 3.0): continue
		var road: Vector2 = terrain.road_info(point)
		var edge: float = road.x - road.y * .5
		if edge < half + 4.5 or edge > half + 12.0: continue
		var free := true
		for other in placed:
			if other.distance_to(point) < 16.0 + half: free = false
		for tree in tree_positions:
			if Vector2(tree.x, tree.z).distance_to(point) < half + 3.0: free = false
		if not free: continue
		# Face the nearest road: the road distance falls fastest that way.
		var toward := Vector2.ZERO
		for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			toward += dir * (terrain.road_info(point).x - terrain.road_info(point + dir).x)
		if toward.length() < .01: continue
		toward = toward.normalized()
		var yaw := atan2(toward.x, toward.y)
		var basis := Basis(Vector3.UP, yaw)
		var low := INF
		var high := -INF
		for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
			var c: Vector3 = basis * Vector3(corner.x * float(record.width) * .5, 0, corner.z * float(record.depth) * .5)
			var h: float = terrain.height_at(point.x + c.x, point.y + c.z)
			low = minf(low, h)
			high = maxf(high, h)
		if high - low > 1.2: continue
		neighbours.append(_neighbour(record, Vector3(point.x, high, point.y), yaw, high - low))
		placed.append(point)
		# The blade grass keeps off the footprint.
		for gx in [-.3, .3]:
			for gz in [-.3, .3]:
				var c: Vector3 = basis * Vector3(gx * float(record.width), 0, gz * float(record.depth))
				clearings.append(Vector3(point.x + c.x, point.y + c.z, half * .75))
	floor_counts["neighbours"] = neighbours.size()

func _neighbour(record: Dictionary, at: Vector3, yaw: float, drop: float) -> Node3D:
	var house := Node3D.new()
	house.name = "Neighbour%d_%s" % [neighbours.size(), record.id]
	house.position = at
	house.rotation.y = yaw
	add_child(house)
	var model := (load(record.scene_path) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	house.add_child(model)
	preload("res://scripts/world/village_house_materials.gd").new().apply(model, str(record.id))
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var role := str(mesh.get_meta("extras", {}).get("part_role", ""))
		# Closed house: nothing inside is ever seen.
		if role == "furniture" or role == "interior":
			mesh.visible = false
			continue
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		mesh.add_child(body)
		var collider := CollisionShape3D.new()
		collider.shape = mesh.mesh.create_trimesh_shape()
		body.add_child(collider)
		mesh.visibility_range_end = 160.0
	if drop > .05:
		# On a slope the downhill side stands on a stone plinth, like the inn.
		var plinth := MeshInstance3D.new()
		plinth.name = "Plinth"
		var box := BoxMesh.new()
		box.size = Vector3(float(record.width) + .2, drop + .1, float(record.depth) + .2)
		plinth.mesh = box
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color(0.46, 0.44, 0.4)
		stone.roughness = .95
		plinth.material_override = stone
		plinth.position = Vector3(0, -drop * .5, 0)
		house.add_child(plinth)
	return house
