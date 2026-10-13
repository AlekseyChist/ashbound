extends SceneTree
# WORLD-BUILD-01A: the world book's terrain pads and new places in the real world scene.
# - every pad: the ground over its inner part at the book's level (+-0.3 m);
# - every new place: its spawn on the ground, its grey volumes resting on the ground (none floats,
#   none buried) and clear of every road's deck;
# - the debug list offers the places, and a teleport to the ruins puts the hero on the terrace.

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
			require(absf(float(s[0]) + 1000.0 - float(place.point[0])) < 0.01 and absf(float(s[2]) + 1000.0 - float(place.point[1])) < 0.01, "Spawn of %s off its point" % place.id)
			var node: Node = book.get_node_or_null(str(place.id))
			require(node != null and node.get_child_count() > 0, "No volumes at %s" % place.id)
			if node == null:
				continue
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

	print("WORLD_BOOK_PLACES_CHECKS checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
