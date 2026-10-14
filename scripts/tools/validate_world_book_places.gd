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

## courtyard_player._step_up (STEP-01), the hero's own ledge climb, for the test capsule.
const STEP_MAX := 0.4
const STEP_LAND := 0.35
const STEP_FLOOR_NORMAL := 0.7
func _step_up(body: CharacterBody3D, delta: float) -> void:
	if not body.is_on_floor() or body.velocity.y > 0.0:
		return
	var along := Vector3(body.velocity.x, 0.0, body.velocity.z) * delta
	if along.length_squared() < 0.000001:
		return
	var probe := along.normalized() * maxf(along.length(), 0.08)
	var hit := KinematicCollision3D.new()
	if not body.test_move(body.global_transform, probe, hit):
		return
	if hit.get_position().y - body.global_position.y < 0.05 and hit.get_normal().y >= STEP_FLOOR_NORMAL:
		return
	var lift_by := STEP_MAX
	var head := KinematicCollision3D.new()
	if body.test_move(body.global_transform, Vector3.UP * STEP_MAX, head):
		lift_by = head.get_travel().length() - 0.01
	if lift_by < 0.02:
		return
	var lift := Vector3.UP * lift_by
	var land := along.normalized() * maxf(along.length(), STEP_LAND)
	var raised := body.global_transform.translated(lift)
	if body.test_move(raised, land):
		return
	var down := KinematicCollision3D.new()
	if not body.test_move(raised.translated(land), -lift - Vector3.UP * 0.05, down):
		return
	if down.get_normal().y < STEP_FLOOR_NORMAL:
		return
	var rise := lift_by - down.get_travel().length()
	if rise > 0.01:
		body.global_position.y += rise + 0.001


func run() -> void:
	var w = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(w)
	await create_timer(1.5).timeout
	var layout: Dictionary = w.world_layout
	var pads: Array = layout.get("book_pads", [])
	var places: Array = layout.get("book_places", [])
	require(pads.size() == 4, "Expected 4 book pads (ruins, two snow terraces, the W1 viewpoint), got %d" % pads.size())
	require(places.size() == 8, "Expected 8 book places (seven places and the W1 viewpoint), got %d" % places.size())

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

	# The W1 footbridge both ways (Codex 14 Oct: the real hero was stopped on the way back at 305.8).
	for leg in [[Vector2(352, 440), Vector2(256, 440)], [Vector2(256, 440), Vector2(352, 440)]]:
		var a: Vector2 = leg[0] - Vector2(1000, 1000)
		var b: Vector2 = leg[1] - Vector2(1000, 1000)
		actor.velocity = Vector3.ZERO
		actor.position = Vector3(a.x, w.world_ground(a.x, a.y) + 1.2, a.y)
		for i in 20:
			await physics_frame
			actor.velocity = Vector3(0, 0.0 if actor.is_on_floor() else actor.velocity.y - 22.0 / 60.0, 0)
			actor.move_and_slide()
		var crossed := false
		for tick in 2400:
			await physics_frame
			var off := Vector2(b.x - actor.position.x, b.y - actor.position.z)
			if off.length() < 0.6:
				crossed = true
				break
			var hv := Vector3(off.x, 0, off.y).normalized() * 3.0
			actor.velocity = Vector3(hv.x, 0.0 if actor.is_on_floor() else actor.velocity.y - 22.0 / 60.0, hv.z)
			actor.move_and_slide()
		print("BOOK_W1_BRIDGE %s -> %s at=%s crossed=%s" % [leg[0], leg[1], actor.position + Vector3(1000, 0, 1000), crossed])
		require(crossed, "The W1 footbridge is not walkable %s -> %s (stuck at %s)" % [leg[0], leg[1], actor.position + Vector3(1000, 0, 1000)])

	# The W1 stair flights: even risers, every tread over its ground, built blocks; then walked down
	# and up by the capsule stepping like the hero (courtyard_player._step_up: up to 0.4 m).
	var stairs: Array = layout.get("book_stairs", [])
	if stairs.is_empty():
		print("BOOK_STAIRS none in this layout (the W1 flights wait for their route)")
	if stairs.size() == 1:
		var steps: Array = stairs[0].steps
		var worst_rise := 0.0
		var buried := 0
		for i in steps.size():
			var st: Array = steps[i]
			if i > 0:
				worst_rise = maxf(worst_rise, absf(float(st[2]) - float(steps[i - 1][2])))
			if w.world_ground(float(st[0]) - 1000.0, float(st[1]) - 1000.0) > float(st[2]) + 0.02:
				buried += 1
		print("BOOK_STAIRS steps=%d worst_rise=%.3f buried=%d" % [steps.size(), worst_rise, buried])
		require(steps.size() > 200 and worst_rise <= 0.2 + 0.001, "W1 stairs: %d steps, a rise of %.2f m" % [steps.size(), worst_rise])
		require(buried == 0, "W1 stairs: %d treads under the ground" % buried)
		var flight_node: Node = book.get_node_or_null("w1_stairs") if book != null else null
		require(flight_node != null and flight_node.find_children("*", "MeshInstance3D", false, false).size() >= steps.size(), "W1 stairs not built")
		for leg in [["down", 0, steps.size() - 1], ["up", steps.size() - 1, 0]]:
			var first: Array = steps[leg[1]]
			actor.velocity = Vector3.ZERO
			actor.position = Vector3(float(first[0]) - 1000.0, float(first[2]) + 1.0, float(first[1]) - 1000.0)
			var order := range(leg[1], leg[2] + (1 if leg[2] > leg[1] else -1), 1 if leg[2] > leg[1] else -1)
			var stuck := false
			for idx in order:
				var st: Array = steps[idx]
				var target := Vector2(float(st[0]) - 1000.0, float(st[1]) - 1000.0)
				var arrived := false
				for tick in 900:
					await physics_frame
					var off := Vector2(target.x - actor.position.x, target.y - actor.position.z)
					if off.length() < 0.35:
						arrived = true
						break
					var hv := Vector3(off.x, 0, off.y).normalized() * 2.0
					actor.velocity = Vector3(hv.x, 0.0 if actor.is_on_floor() else actor.velocity.y - 22.0 / 60.0, hv.z)
					_step_up(actor, 1.0 / 60.0)
					actor.move_and_slide()
				if not arrived:
					stuck = true
					var hits := []
					for c in actor.get_slide_collision_count():
						var col := actor.get_slide_collision(c)
						hits.append("%s n=%s p=%s" % [str((col.get_collider() as Node).get_parent().name) if col.get_collider() is Node else "?", str(col.get_normal()), str(col.get_position() + Vector3(1000, 0, 1000))])
					print("BOOK_STAIRS_WALK %s stuck before step %d %s at %s floor=%s hits=%s" % [leg[0], idx, str(steps[idx]), actor.position + Vector3(1000, 0, 1000), actor.is_on_floor(), str(hits)])
					break
			print("BOOK_STAIRS_WALK %s done=%s at=%s" % [leg[0], not stuck, actor.position + Vector3(1000, 0, 1000)])
			require(not stuck, "W1 stairs not walkable %s" % leg[0])

	print("WORLD_BOOK_PLACES_CHECKS checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
