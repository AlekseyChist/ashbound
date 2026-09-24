extends Node3D
## Heights, paths and reserved footprints come from the reviewed B-1.1 plan.
const Grid = preload("res://scripts/world/village_grid_mesh.gd")
const ORIGIN := Vector2(95,95)
var data: Dictionary
var segments: Array[Dictionary] = []
var ground: MeshInstance3D
var material: ShaderMaterial

func configure(layout: Dictionary) -> void:
	data = layout
	for road in data.roads:
		for i in range(road.points.size()-1):
			segments.append({"a": map_point(road.points[i]), "b": map_point(road.points[i+1]), "width": float(road.width)})
	for record in data.buildings:
		if int(record.phase) != 1: continue
		var spec: Dictionary = data.models[record.model]
		var center := Vector2(record.x,record.y)-ORIGIN
		var entry := center + Vector2(spec.door_x,float(spec.depth)*.5+2.0).rotated(deg_to_rad(record.angle))
		segments.append({"a":entry,"b":map_point(record.gate),"width":2.2})
	segments.append({"a":Vector2(data.well.x,data.well.y)-ORIGIN,"b":map_point(data.well.gate),"width":2.2})
	ground = MeshInstance3D.new()
	ground.name = "VillageGround"
	ground.mesh = Grid.build(-95,-95,130,80,2.0,height_at,color_at)
	material = ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/village_ground.gdshader")
	ground.material_override = material
	add_child(ground)
	ground.create_trimesh_collision()
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func map_point(pair: Array) -> Vector2:
	return Vector2(pair[0],pair[1])-ORIGIN

func height_at(x: float, z: float) -> float:
	var point := Vector2(x,z)+ORIGIN
	var weight_sum := 0.0
	var height_sum := 0.0
	for item in data.height_profile:
		var d := maxf(point.distance_to(Vector2(item.gate[0],item.gate[1])),1.0)
		var weight := 1.0/(d*d)
		weight_sum += weight
		height_sum += float(item.height_m)*weight
	var height := height_sum/weight_sum
	height += 8.0*(1.0-smoothstep(5.0,55.0,point.y))
	height += 3.5*(1.0-smoothstep(0.0,28.0,minf(point.x,225-point.x)))
	var road := road_info(Vector2(x,z))
	height += (.3*sin(x*.11)*cos(z*.09)+.14*sin((x+z)*.23))*smoothstep(3.0,12.0,road.x)
	for record in data.buildings:
		if int(record.phase) != 1: continue
		var spec: Dictionary = data.models[record.model]
		var local := (point-Vector2(record.x,record.y)).rotated(-deg_to_rad(record.angle))
		var beyond := Vector2(maxf(absf(local.x)-float(spec.width)*.5-2.2,0),maxf(absf(local.y)-float(spec.depth)*.5-3.0,0)).length()
		height = lerpf(float(record.elevation_m),height,smoothstep(0,4,beyond))
	var well_distance := point.distance_to(Vector2(data.well.x,data.well.y))
	height = lerpf(float(data.well.elevation_m),height,smoothstep(3.5,7.0,well_distance))
	return height

func road_info(point: Vector2) -> Vector2:
	var best := Vector2(INF,0)
	for segment in segments:
		var closest := Geometry2D.get_closest_point_to_segment(point,segment.a,segment.b)
		var distance := point.distance_to(closest)
		if distance-float(segment.width)*.5 < best.x-best.y*.5:
			best = Vector2(distance,segment.width)
	return best

func reserved(point: Vector2, clearance: float = 0.0) -> bool:
	var p := point+ORIGIN
	for record in data.buildings:
		var yard: Array = record.yard
		if Rect2(yard[0],yard[1],yard[2],yard[3]).grow(clearance).has_point(p): return true
	return p.distance_to(Vector2(data.well.x,data.well.y)) < 4.5+clearance

func forest_contains(point: Vector2) -> bool:
	for polygon in data.forest_polygons:
		var points := PackedVector2Array()
		for pair in polygon: points.append(map_point(pair))
		if Geometry2D.is_point_in_polygon(point,points): return true
	return false

func color_at(x: float,z: float) -> Color:
	var info := road_info(Vector2(x,z))
	var road := 1.0-smoothstep(info.y*.42,info.y*.65+0.5,info.x)
	var well_distance := (Vector2(x,z)+ORIGIN).distance_to(Vector2(data.well.x,data.well.y))
	road = maxf(road,1.0-smoothstep(2.4,3.6,well_distance))
	var grass := Color("27392b").lerp(Color("405038"),.5+.5*sin(x*.27)*cos(z*.21))
	return grass.lerp(Color("554837"),road).srgb_to_linear()
