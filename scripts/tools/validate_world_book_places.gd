extends SceneTree
# WORLD-BUILD-01A: the world book's terrain pads and new places in the real world scene.
# - every pad: the ground over its inner part at the book's level (+-0.3 m);
# - every new place: its spawn on the ground, its grey volumes resting on the ground (none floats,
#   none buried) and clear of every road's deck;
# - the debug list offers the places, and a teleport to the ruins puts the hero on the terrace;
# - the ruins' west approach from the road to the gate is walkable on foot.

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func require(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		push_error(detail)

func run() -> void:
	var w = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(w)
	await create_timer(1.5).timeout
	var layout: Dictionary = w.world_layout
	var pads: Array = layout.get("book_pads", [])
	var places: Array = layout.get("book_places", [])
	require(pads.size() == 3, "Expected 3 book pads, got %d" % pads.size())
	require(places.size() == 7, "Expected 7 book places, got %d" % places.size())

	# Pads: sample a grid over the polygon shrunk towards its centroid (the margin eases outside it).
	for pad in pads:
		var poly: Array = pad.poly
		var centre := Vector2.ZERO
		for p in poly:
			centre += Vector2(float(p[0]), float(p[1]))
		centre /= poly.size()
		var worst := 0.0
		for p in poly:
			for t in [0.0, 0.4, 0.8]:
				var at := centre.lerp(Vector2(float(p[0]), float(p[1])), t)
				worst = maxf(worst, absf(w.world_ground(at.x - 1000.0, at.y - 1000.0) - float(pad.level)))
		print("BOOK_PAD %s level=%.1f worst=%.2f" % [pad.id, float(pad.level), worst])
		require(worst <= 0.3, "Pad %s off its level by %.2f m" % [pad.id, worst])

	# Roads' decks (world frame) for the clearance check.
	var segments: Array = []
	for r in layout.roads:
		var pts: Array = r.world_points
		for i in range(pts.size() - 1):
			segments.append([Vector2(pts[i][0], pts[i][2]), Vector2(pts[i + 1][0], pts[i + 1][2]), float(r.get("width_m", 6.0)) * 0.5])

	var book: Node = w.world_root.get_node_or_null("BookPlaces")
	require(book != null, "No BookPlaces node in the world")
	if book != null:
		for place in places:
			var s: Array = place.spawn
			var node: Node = book.get_node_or_null(str(place.id))
			require(node != null and node.get_child_count() > 0, "No volumes at %s" % place.id)
			if node == null:
				continue
			var arrive: Array = place.arrival
			require(absf(float(s[0]) + 1000.0 - float(arrive[0])) < 0.01 and absf(float(s[2]) + 1000.0 - float(arrive[1])) < 0.01, "Spawn of %s off its arrival" % place.id)
			# The arrival is clear: no far-forest trunk within 5 m, no grey volume within 2 m.
			var at := Vector2(float(s[0]), float(s[2]))
			var trees := 0
			for batch in w.far_forest.find_children("FarForest_*", "MultiMeshInstance3D", false, false):
				for shape in batch.get_node("Trunks").get_children():
					var tp: Vector3 = batch.position + shape.position
					if Vector2(tp.x, tp.z).distance_to(at) < 5.0:
						trees += 1
			var blocking := 0
			for m in node.find_children("*", "MeshInstance3D", false, false):
				var mi := m as MeshInstance3D
				var size: Vector3 = (mi.mesh as BoxMesh).size
				if Vector2(mi.position.x, mi.position.z).distance_to(at) < Vector2(size.x, size.z).length() * 0.5 + 2.0:
					blocking += 1
			print("BOOK_ARRIVAL %s at=%s trees=%d volumes_near=%d" % [place.id, arrive, trees, blocking])
			require(trees == 0, "%s: %d trees at the arrival" % [place.id, trees])
			require(blocking == 0, "%s: %d volumes right at the arrival" % [place.id, blocking])
			var meshes := node.find_children("*", "MeshInstance3D", false, false)
			var floating := 0
			var on_road := 0
			for m in meshes:
				var mi := m as MeshInstance3D
				var size: Vector3 = (mi.mesh as BoxMesh).size
				var bottom := mi.position.y - size.y * 0.5
				var ground: float = book.ground(mi.position.x, mi.position.z)
				# Lifted roof sheets sit on walls; only the ground-standing pieces must reach the ground.
				if bottom < ground + 0.5 and bottom > ground + 0.02:
					floating += 1
				var c := Vector2(mi.position.x, mi.position.z)
				var reach := Vector2(size.x, size.z).length() * 0.5
				for seg in segments:
					if Geometry2D.get_closest_point_to_segment(c, seg[0], seg[1]).distance_to(c) < float(seg[2]) + reach * 0.5:
						on_road += 1
						break
			print("BOOK_PLACE %s volumes=%d floating=%d on_road=%d" % [place.id, meshes.size(), floating, on_road])
			require(floating == 0, "%s: %d volumes float over the ground" % [place.id, floating])
			require(on_road == 0, "%s: %d volumes on a road" % [place.id, on_road])

	# The debug list offers every book place.
	var listed := 0
	for p in w.debug_locations():
		for place in places:
			if str(p.id) == str(place.id):
				listed += 1
	require(listed == places.size(), "Debug list offers %d of %d book places" % [listed, places.size()])

	# Teleport to every place: the hero lands on the ground (the ruins: on the 128 m terrace).
	for place in places:
		w.teleport_to(place)
		for i in 30:
			await physics_frame
		var local: Vector3 = w.world_root.to_local(w.player.global_position)
		var g: float = book.ground(local.x, local.z) if book != null else 0.0
		print("BOOK_TELEPORT %s hero=%s ground=%.2f floor=%s" % [place.id, local, g, w.player.is_on_floor()])
		require(w.player.is_on_floor() and absf(local.y - g) < 1.5, "Teleport to %s: hero not on the ground" % place.id)
		if str(place.id) == "capital_ruins":
			require(absf(local.y - 128.0) < 1.0, "Hero not on the ruins terrace: %.2f" % local.y)

	# The ruins' approach on foot: from the lower valley road up the west slope to the west gate and
	# in (a capsule moving like the hero: no downward push on the floor, gravity in the air, a 0.4 m
	# floor snap, the 45 deg floor limit; no step-up, so it is stricter than the hero).
	var actor := CharacterBody3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.75
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	actor.add_child(shape)
	actor.collision_layer = 2
	actor.floor_snap_length = 0.4
	w.world_root.add_child(actor)
	w.player.process_mode = Node.PROCESS_MODE_DISABLED
	var start := Vector2(1104, 1140) - Vector2(1000, 1000)
	actor.position = Vector3(start.x, w.world_ground(start.x, start.y) + 1.2, start.y)
	var route := [Vector2(1110, 1160), Vector2(1116, 1180), Vector2(1124, 1196), Vector2(1137, 1203), Vector2(1152, 1206)]
	for target_map in route:
		var target: Vector2 = target_map - Vector2(1000, 1000)
		var reached := false
		for tick in 1800:
			await physics_frame
			var offset := Vector2(target.x - actor.position.x, target.y - actor.position.z)
			if offset.length() < 0.5:
				reached = true
				break
			var horizontal := Vector3(offset.x, 0, offset.y).normalized() * 3.0
			var fall := 0.0 if actor.is_on_floor() else actor.velocity.y - 22.0 / 60.0
			actor.velocity = Vector3(horizontal.x, fall, horizontal.z)
			actor.move_and_slide()
		print("BOOK_RUINS_WALK to=%s at=%s reached=%s" % [target_map, actor.position + Vector3(1000, 0, 1000), reached])
		require(reached, "The ruins' west approach is not walkable towards %s (stuck at %s)" % [target_map, actor.position + Vector3(1000, 0, 1000)])
		if not reached:
			break
	require(absf(actor.position.y - 0.875 - 128.0) < 0.6, "Not on the ruins terrace after the gate: %.2f" % (actor.position.y - 0.875))

	print("WORLD_BOOK_PLACES_CHECKS checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
