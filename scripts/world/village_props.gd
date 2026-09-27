extends Node3D
## Yard props stay in building-local metres; collisions use measured visual bounds.
const Catalog = preload("res://scripts/world/village_props_catalog.gd")
const Door = preload("res://scripts/world/village_door.gd")
var items: Dictionary = {}
var bounds: Dictionary = {}
var records: Array[Dictionary] = []

func build(terrain: Node3D, buildings: Array[Node3D]) -> void:
	if not items.is_empty(): return
	records = Catalog.all()
	for record in records:
		var building: Node3D = null
		for candidate in buildings:
			if candidate.record.id == record.building: building = candidate
		if building == null:
			push_error("Unknown yard for prop: " + str(record.id))
			continue
		var packed := load("res://assets/environment/village-props-v1/%s.gltf" % record.asset) as PackedScene
		if packed == null:
			push_error("Missing yard prop: " + str(record.asset))
			continue
		var item := Node3D.new()
		item.name = record.id
		add_child(item)
		var visual := packed.instantiate() as Node3D
		item.add_child(visual)
		visual.scale = Vector3.ONE * float(record.scale)
		var box := AABB()
		var first := true
		for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
			var local_box: AABB = (item.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
			box = local_box if first else box.merge(local_box)
			first = false
			mesh.visibility_range_end = 85.0
			mesh.visibility_range_end_margin = 5.0
		# No per-axis scaling: imported metres and each object's original silhouette survive.
		visual.position.y -= box.position.y
		box.position.y = 0.0
		var point: Vector3 = building.to_global(record.at)
		point.y = terrain.height_at(point.x, point.z) + float(record.at.y)
		if not str(record.support).is_empty():
			if not items.has(record.support):
				push_error("Missing prop support: " + str(record.support))
				item.queue_free()
				continue
			point.y = items[record.support].global_position.y + bounds[record.support].size.y + float(record.at.y)
		item.global_position = point
		item.rotation.y = building.rotation.y + float(record.yaw)
		if record.solid:
			var body := StaticBody3D.new()
			body.name = "Solid"
			body.collision_layer = 1 | Door.OBSTACLE_LAYER
			body.collision_mask = 0
			item.add_child(body)
			var collider := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = box.size
			collider.shape = shape
			collider.position = box.get_center()
			body.add_child(collider)
		items[record.id] = item
		bounds[record.id] = box
	print("VILLAGE_PROPS_READY count=", items.size())
