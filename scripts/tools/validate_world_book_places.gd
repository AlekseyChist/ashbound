extends SceneTree
# WORLD-BUILD-01A: the world book's terrain pads and new places in the real world scene.
# - every pad: the ground over its inner part at the book's level (+-0.3 m);
# - every new place: its spawn on the ground, its grey volumes resting on the ground (none floats,
#   none buried) and clear of every road's deck;
# - the debug list offers the places, and a teleport to the ruins puts the hero on the terrace;
# - the ruins' west approach from the road to the gate is walkable on foot;
# - the snow city's 41 plots: level under the walls, a plinth over a fall, a door front without a ledge.

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
		var in_wells := 0
		for p in poly:
			for t in [0.0, 0.4, 0.8]:
				var at := centre.lerp(Vector2(float(p[0]), float(p[1])), t)
				# a stair well cut into the terrace (route A ends inside the middle terrace) is not the
				# terrace's level: samples within 6 m of a tread are counted apart
				var by_stairs := false
				for flight in layout.get("book_stairs", []):
					for st in flight.steps:
						if Vector2(float(st[0]), float(st[1])).distance_to(at) < 6.0:
							by_stairs = true
							break
					if by_stairs:
						break
				if by_stairs:
					in_wells += 1
					continue
				worst = maxf(worst, absf(w.world_ground(at.x - 1000.0, at.y - 1000.0) - float(pad.level)))
		print("BOOK_PAD %s level=%.1f worst=%.2f stair_well_samples=%d" % [pad.id, float(pad.level), worst, in_wells])
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
	# W1, the snow city's routes A/B/C and the smugglers' trail's three switchbacks (WORLD-BUILD-01G)
	require(stairs.size() == 7, "Expected the W1 flights, the snow city's routes A/B/C and the smugglers' three stairs, got %d" % stairs.size())
	for flight in stairs:
		var steps: Array = flight.steps
		var worst_rise := 0.0
		var buried := 0
		for i in steps.size():
			var st: Array = steps[i]
			if i > 0 and float(st[4]) < 0.6 and float(steps[i - 1][4]) < 0.6:
				worst_rise = maxf(worst_rise, absf(float(st[2]) - float(steps[i - 1][2])))
			if int(st[6]) != 4 and w.world_ground(float(st[0]) - 1000.0, float(st[1]) - 1000.0) > float(st[2]) + 0.02:
				buried += 1
		print("BOOK_STAIRS %s steps=%d worst_rise=%.3f buried=%d" % [flight.id, steps.size(), worst_rise, buried])
		require(worst_rise <= 0.2 + 0.001, "%s: a rise of %.2f m" % [flight.id, worst_rise])
		require(buried == 0, "%s: %d treads under the ground" % [flight.id, buried])
		var flight_node: Node = book.get_node_or_null(str(flight.id)) if book != null else null
		require(flight_node != null and flight_node.get_child_count() > 0, "%s not built" % flight.id)
		for leg in [["down" if float(steps[0][2]) > float(steps[steps.size() - 1][2]) else "up", 0, steps.size() - 1], ["back", steps.size() - 1, 0]]:
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
					print("BOOK_STAIRS_WALK %s %s stuck before step %d %s at %s" % [flight.id, leg[0], idx, str(steps[idx]), actor.position + Vector3(1000, 0, 1000)])
					break
			print("BOOK_STAIRS_WALK %s %s done=%s at=%s" % [flight.id, leg[0], not stuck, actor.position + Vector3(1000, 0, 1000)])
			require(not stuck, "%s not walkable %s" % [flight.id, leg[0]])

	# WORLD-BUILD-01C: the snow city's 41 plots on the ACTUAL colliders (terrain and plinths only): under
	# the walls nothing over the floor and nothing more than 0.35 m under it (a plinth fills a fall);
	# from the threshold out the ground starts at the floor and climbs in steps of <= 0.25 m; and
	# world_ground (where the builder sets each floor) reads the terrain's own 1.25 m triangles.
	var space: PhysicsDirectSpaceState3D = w.get_world_3d().direct_space_state
	var origin: Vector3 = w.world_root.global_position
	var lots: Array = w.snow_lots.lots
	# the snow city's 41 plots and the desert city's 43 (WORLD-BUILD-01E), the same checks for both
	var in_snow := lots.filter(func(l): return l.city == "snow").size()
	var in_desert := lots.filter(func(l): return l.city == "desert").size()
	require(in_snow == 41, "Expected 41 snow plots, got %d" % in_snow)
	require(in_desert == 43, "Expected 43 desert plots, got %d" % in_desert)
	# the lowland city's 50 less its 4 piers and 13 shacks on stilts (WORLD-BUILD-01F)
	var in_lowland := lots.filter(func(l): return l.city == "lowland").size()
	require(in_lowland == 33, "Expected 33 lowland ground plots, got %d" % in_lowland)
	var worst_read := 0.0
	var side_stairs: Array[String] = []
	for lot in lots:
		if w.snow_lots.CUTS.has(lot.code):
			# the library's cut: inside the walls no terrain/plinth above its lower hall (3.2 m down)
			var blocked := 0
			for i in 9:
				for j in 9:
					var p: Vector2 = lot.c + lot.s * lerpf(-lot.w * 0.5 + 0.1, lot.w * 0.5 - 0.1, i / 8.0) + lot.f * lerpf(-lot.d * 0.5 + 0.1, lot.d * 0.5 - 0.1, j / 8.0)
					var y = _lot_ray(space, origin, p, lot.level)
					if y != null and y > lot.level - 3.3:
						blocked += 1
			print("SNOW_LOT %s cut blocked=%d" % [lot.key, blocked])
			require(blocked == 0, "%s: the lower hall's cut is filled at %d points" % [lot.key, blocked])
			# the sunken yard behind it: its floor at the lower hall's, clear above
			if w.snow_lots.AREAWAYS.has(lot.code):
				var aw: Array = w.snow_lots.AREAWAYS[lot.code]
				var floor_y: float = lot.level - float(w.snow_lots.LOWER[lot.code])
				var off_floor := 0
				for i in 5:
					for j in 5:
						var p: Vector2 = lot.c + lot.s * lerpf(-float(aw[0]) * 0.5 + 0.2, float(aw[0]) * 0.5 - 0.2, i / 4.0) - lot.f * (lot.d * 0.5 + lerpf(0.2, float(aw[1]) - 0.2, j / 4.0))
						var y = _lot_ray(space, origin, p, lot.level)
						if y == null or absf(float(y) - floor_y) > 0.05:
							off_floor += 1
				print("SNOW_LOT %s yard off_floor=%d" % [lot.key, off_floor])
				require(off_floor == 0, "%s: the sunken yard behind the lower door is not clear to its floor at %d points" % [lot.key, off_floor])
		var above := -INF
		var below := -INF
		var miss := 0
		for i in 9:
			for j in 9:
				var u := lerpf(-lot.w * 0.5 + 0.1, lot.w * 0.5 - 0.1, i / 8.0)
				var v := lerpf(-lot.d * 0.5 + 0.1, lot.d * 0.5 - 0.1, j / 8.0)
				var p: Vector2 = lot.c + lot.s * u + lot.f * v
				var y = _lot_ray(space, origin, p, lot.level)
				if w.snow_lots.CUTS.has(lot.code):
					break
				if y == null:
					miss += 1
					continue
				above = maxf(above, y - lot.level)
				below = maxf(below, lot.level - y)
				if not _on_plinth(space, origin, p, lot.level):
					worst_read = maxf(worst_read, absf(float(w.world_ground(p.x, p.y)) - y))
		# ... and over any 0.5 m no more than 0.42 m (about 40 deg: steps of 0.18 in 0.35 pass, a 54 deg
		# bank does not - the vs12 lane). One walkable line is the door's path: the middle or 0.6 m to
		# either side (an uphill door's bank may rise steeper beside the path).
		var door := INF
		var climb := INF
		for q in [-0.6, 0.0, 0.6]:
			var prev = null
			var ys: Array[float] = []
			var step := 0.0
			for k in 36:
				var p: Vector2 = lot.c + lot.f * (lot.d * 0.5 + 0.05 + k * 0.1) + lot.s * q
				var y = _lot_ray(space, origin, p, lot.level)
				if y == null:
					step = INF
					break
				# the threshold within 0.06 (the ground under the floor lies 0.05 lower, see FLOOR_GAP)
				step = maxf(step, absf(lot.level - y) * 4.0 if prev == null else absf(y - prev))
				prev = y
				ys.append(float(y))
			var rise := 0.0
			for k in range(5, ys.size()):
				rise = maxf(rise, absf(ys[k] - ys[k - 5]))
			if maxf(step / 0.25, rise / 0.42) < maxf(door / 0.25, climb / 0.42):
				door = step
				climb = rise
		print("SNOW_LOT %s level=%.2f above=%.2f below=%.2f miss=%d door_step=%.2f door_climb=%.2f" % [lot.key, lot.level, above, below, miss, door, climb])
		require(miss == 0 and above <= 0.03, "%s: ground over the floor (%.2f m) or no ground" % [lot.key, above])
		require(below <= 0.35, "%s: hangs %.2f m over the ground under its walls" % [lot.key, below])
		# a door with a stair along its facade is walked down that stair below instead
		var turned: bool = w.snow_lots.stoop_paths.has(lot.key) and w.snow_lots.stoop_paths[lot.key].size() == 3
		if turned:
			side_stairs.append(lot.key)
		else:
			require(door <= 0.25, "%s: its door front climbs %.2f m in a step (or a gap at the threshold)" % [lot.key, door])
			require(climb <= 0.42, "%s: its door front climbs %.2f m in 0.5 m - too steep to walk" % [lot.key, climb])
	print("SNOW_LOTS_GROUND_READ worst=%.3f" % worst_read)

	# The door stairs along a facade (the slum): from the door down to the stair's end and back, by
	# the capsule with the hero's step-up.
	for code in side_stairs:
		var path: PackedVector2Array = w.snow_lots.stoop_paths[code]
		for leg in [path, _reversed(path)]:
			var a: Vector2 = leg[0]
			actor.velocity = Vector3.ZERO
			var down := PhysicsRayQueryParameters3D.create(origin + Vector3(a.x, 400, a.y), origin + Vector3(a.x, -50, a.y))
			down.exclude = [actor.get_rid()]
			var hit := space.intersect_ray(down)
			actor.position = Vector3(a.x, ((hit.position.y - origin.y) if not hit.is_empty() else w.world_ground(a.x, a.y)) + 1.2, a.y)
			for i in 20:
				await physics_frame
				actor.velocity = Vector3(0, 0.0 if actor.is_on_floor() else actor.velocity.y - 22.0 / 60.0, 0)
				actor.move_and_slide()
			var walked := true
			for k in range(1, leg.size()):
				var target: Vector2 = leg[k]
				var reached := false
				for tick in 900:
					await physics_frame
					var off := Vector2(target.x - actor.position.x, target.y - actor.position.z)
					if off.length() < 0.35:
						reached = true
						break
					var hv := Vector3(off.x, 0, off.y).normalized() * 2.0
					actor.velocity = Vector3(hv.x, 0.0 if actor.is_on_floor() else actor.velocity.y - 22.0 / 60.0, hv.z)
					_step_up(actor, 1.0 / 60.0)
					actor.move_and_slide()
				if not reached:
					walked = false
					var against := ""
					for c in actor.get_slide_collision_count():
						var col := actor.get_slide_collision(c)
						var body := col.get_collider() as Node
						var size = ((body.get_child(0) as CollisionShape3D).shape as BoxShape3D).size if body.get_child_count() > 0 and (body.get_child(0) is CollisionShape3D) and ((body.get_child(0) as CollisionShape3D).shape is BoxShape3D) else "-"
						against += " %s %s n=%s at=%s" % [str(body.get_path()).get_slice("/", 5), size, col.get_normal(), col.get_position() - origin + Vector3(1000, 0, 1000)]
					print("SNOW_DOOR_STAIR %s stuck before %s at %s against%s" % [code, target + Vector2(1000, 1000), actor.position + Vector3(1000, 0, 1000), against])
					break
			require(walked, "%s: its door stair along the facade is not walkable" % code)
	print("SNOW_DOOR_STAIRS along_facade=%s" % [side_stairs])

	# The snow city's streets (the book's plan): each walked end to end and back by the capsule with
	# the hero's step-up, on the terrain, plinths and door stairs alone (no buildings loaded here).
	# Each street whole, its ends at the stairs included; the capsule starts on the first surface
	# under it.
	var treads: Array = []
	for flight in layout.get("book_stairs", []):
		if str(flight.id).begins_with("snow"):
			for st in flight.steps:
				treads.append([Vector2(float(st[0]), float(st[1])), maxf(float(st[4]), float(st[5])) * 0.5 + 0.5])
	for street in w.snow_lots.streets:
		# whole, ends at the stairs included (the street-stair joins are part of the route)
		var pts: PackedVector2Array = street[0]
		if pts.size() < 2:
			continue
		for leg in [pts, _reversed(pts)]:
			var from: Vector2 = leg[0] - Vector2(1000, 1000)
			actor.velocity = Vector3.ZERO
			var down := PhysicsRayQueryParameters3D.create(origin + Vector3(from.x, 400, from.y), origin + Vector3(from.x, -50, from.y))
			down.exclude = [actor.get_rid()]
			var hit := space.intersect_ray(down)
			var floor_y: float = (hit.position.y - origin.y) if not hit.is_empty() else w.world_ground(from.x, from.y)
			actor.position = Vector3(from.x, floor_y + 1.2, from.y)
			for i in 20:
				await physics_frame
				actor.velocity = Vector3(0, 0.0 if actor.is_on_floor() else actor.velocity.y - 22.0 / 60.0, 0)
				actor.move_and_slide()
			var walked := true
			for k in range(1, leg.size()):
				var target: Vector2 = leg[k] - Vector2(1000, 1000)
				var reached := false
				for tick in 1800:
					await physics_frame
					var off := Vector2(target.x - actor.position.x, target.y - actor.position.z)
					if off.length() < 0.5:
						reached = true
						break
					var hv := Vector3(off.x, 0, off.y).normalized() * 3.0
					actor.velocity = Vector3(hv.x, 0.0 if actor.is_on_floor() else actor.velocity.y - 22.0 / 60.0, hv.z)
					_step_up(actor, 1.0 / 60.0)
					actor.move_and_slide()
				if not reached:
					walked = false
					var against := ""
					for c in actor.get_slide_collision_count():
						var col := actor.get_slide_collision(c)
						against += " %s n=%s" % [str((col.get_collider() as Node).get_path()).get_slice("/", 5) + "/" + str((col.get_collider() as Node).get_path()).get_slice("/", 6), col.get_normal()]
					print("SNOW_STREET_WALK %s stuck before %s at %s against%s" % [leg[0], leg[k], actor.position + Vector3(1000, 0, 1000), against])
					break
			require(walked, "Snow street from %s not walkable" % leg[0])
	print("SNOW_STREETS streets=%d" % w.snow_lots.streets.size())
	# WORLD-BUILD-01F: the lowland's boardwalks on stilts, walked end to end and back; its 13 shacks on
	# stilts have floors for the builder
	require(w.lowland_water != null and w.lowland_water.stilt_levels.size() == 13, "Expected 13 lowland shacks on stilts")
	for bw in (w.lowland_water.boardwalks if w.lowland_water != null else []):
		var line: PackedVector2Array = bw[0]
		var tops: PackedFloat32Array = bw[1]
		for leg in [line, _reversed(line)]:
			var a: Vector2 = leg[0]
			var a_top: float = tops[0] if leg == line else tops[tops.size() - 1]
			actor.velocity = Vector3.ZERO
			actor.position = Vector3(a.x, a_top + 1.0, a.y)
			for i in 20:
				await physics_frame
				actor.velocity = Vector3(0, 0.0 if actor.is_on_floor() else actor.velocity.y - 22.0 / 60.0, 0)
				actor.move_and_slide()
			var target: Vector2 = leg[leg.size() - 1]
			var reached := false
			# time enough for the whole boardwalk at 2 m/s, and half again
			var length := 0.0
			for k in range(1, leg.size()):
				length += leg[k].distance_to(leg[k - 1])
			for tick in int(length / 2.0 * 60.0 * 1.5) + 600:
				await physics_frame
				var off := Vector2(target.x - actor.position.x, target.y - actor.position.z)
				if off.length() < 0.5:
					reached = true
					break
				# along the boardwalk: aim at the next point of the leg ahead of the actor
				var nearest := 0
				var best := INF
				for k in leg.size():
					var dd := Vector2(actor.position.x, actor.position.z).distance_to(leg[k])
					if dd < best:
						best = dd
						nearest = k
				var aim: Vector2 = leg[mini(nearest + 1, leg.size() - 1)]
				var o2 := Vector2(aim.x - actor.position.x, aim.y - actor.position.z)
				var hv := Vector3(o2.x, 0, o2.y).normalized() * 2.0
				actor.velocity = Vector3(hv.x, 0.0 if actor.is_on_floor() else actor.velocity.y - 22.0 / 60.0, hv.z)
				_step_up(actor, 1.0 / 60.0)
				actor.move_and_slide()
			var against := ""
			if not reached:
				for c in actor.get_slide_collision_count():
					var col := actor.get_slide_collision(c)
					against += " %s n=%s at=%s" % [str((col.get_collider() as Node).get_path()).get_slice("/", 5), col.get_normal(), col.get_position() - origin + Vector3(1000, 0, 1000)]
			print("LOWLAND_BOARDWALK reached=%s at %s%s" % [reached, actor.position + Vector3(1000, 0, 1000), against])
			require(reached, "A lowland boardwalk is not walkable (stuck at %s)" % [actor.position + Vector3(1000, 0, 1000)])


	require(worst_read <= 0.02, "world_ground misreads the snow plots' terrain by %.3f m" % worst_read)

	print("WORLD_BOOK_PLACES_CHECKS checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## The first terrain or plinth under a point (world frame), skipping anything else on the plot.
func _lot_ray(space: PhysicsDirectSpaceState3D, origin: Vector3, p: Vector2, level: float):
	var top := origin + Vector3(p.x, level + 6.0, p.y)
	var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 20.0)
	var skip: Array[RID] = []
	for k in 8:
		q.exclude = skip
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return null
		var body: Node = hit.collider
		if body.get_parent().is_in_group("graybox_terrain_chunk") or str(body.get_path()).contains("SnowPlinths"):
			return hit.position.y - origin.y
		skip.append(hit.rid)
	return null


func _on_plinth(space: PhysicsDirectSpaceState3D, origin: Vector3, p: Vector2, level: float) -> bool:
	var top := origin + Vector3(p.x, level + 6.0, p.y)
	var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 20.0)
	var skip: Array[RID] = []
	for k in 8:
		q.exclude = skip
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return false
		var body: Node = hit.collider
		if body.get_parent().is_in_group("graybox_terrain_chunk"):
			return false
		if str(body.get_path()).contains("SnowPlinths"):
			return true
		skip.append(hit.rid)
	return false


func _reversed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(pts.size() - 1, -1, -1):
		out.append(pts[i])
	return out


## A street's ends moved 2.5 m along it, away from any stair tread within 2 m.
func _off_stairs(pts: PackedVector2Array, treads: Array) -> PackedVector2Array:
	var out := pts.duplicate()
	for end in [out.size() - 1, 0]:
		var near := false
		for t in treads:
			near = near or (t[0] as Vector2).distance_to(out[end]) < float(t[1])
		if not near:
			continue
		var inner: Vector2 = out[1] if end == 0 else out[out.size() - 2]
		var along: float = out[end].distance_to(inner)
		if along <= 3.0:
			out.remove_at(end)
		else:
			out[end] = out[end].move_toward(inner, 2.5)
	return out
