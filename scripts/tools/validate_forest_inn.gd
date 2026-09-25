extends Node
## TAVERN-01B/02 (D-089): the forest inn in the world, 13 x 21 m. It replaces the grey landmark at forest_inn,
## stands on a level pad at the trail's height, its door works with the action button, and the
## hero walks from the trail end through the door into the common room. The village keeps its
## three yards (the house picker and the yard checks are not affected).
## TAVERN-03: the big hearth between the rear windows burns with a light and a crackle, a pig on the
## spit, a chest at every loft bed, hay, props on the bar and tables; every light hangs or stands
## as a visible lantern; nothing blocks the foot of the stairs.
const Scene = preload("res://scenes/world/world.tscn")
const INN_TALK: QuestData = preload("res://data/quests/forest_inn_keeper.tres")
var world: Node3D
var inn: Node3D
var failures: Array[String] = []
var checks := 0

func _ready() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("INN_FAIL ", label)

func settle(seconds: float = .3) -> void:
	await get_tree().create_timer(seconds, false, true).timeout

func drive(goal: Vector3, seconds: float, near := .6) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		var offset: Vector3 = goal - world.player.global_position
		offset.y = 0
		if offset.length() < near: break
		var camera: Camera3D = world.camera_rig.get_camera()
		var right := camera.global_basis.x; right.y = 0; right = right.normalized()
		var back := camera.global_basis.z; back.y = 0; back = back.normalized()
		world.player.set_move_input(Vector2(offset.normalized().dot(right), offset.normalized().dot(back)))
		await get_tree().physics_frame
	world.player.stop_input()
	var rest: Vector3 = goal - world.player.global_position
	rest.y = 0
	return rest.length() < near + .5

func run() -> void:
	world = Scene.instantiate()
	add_child(world)
	await settle(.8)
	inn = world.inn
	check(inn != null and inn.record.id == "T03A", "the forest inn is built")
	check(world.world_root.get_node_or_null("forest_inn") == null, "the grey landmark is gone")
	check(world.buildings.size() == 3 and not world.buildings.has(inn), "the village keeps its three yards")
	check(inn.door != null and not inn.door.leaves.is_empty(), "the inn door has its leaves")
	# Level pad: the grid is flat under the whole footprint, at the floor's base.
	var worst := 0.0
	var hx: float = inn.record.width * .5 + .2
	var hz: float = inn.record.depth * .5
	for corner in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, hz + 1.9), Vector3(hx, 0, hz + 1.9), Vector3.ZERO]:
		var at: Vector3 = inn.global_transform * corner - world.world_root.global_position
		worst = maxf(worst, absf(world.world_ground(at.x, at.z) + world.world_root.global_position.y - inn.global_position.y))
	check(worst < .05, "level ground under the inn (worst %.3f m)" % worst)
	# From the trail end to the door.
	var outside: Vector3 = inn.to_global(Vector3(0, 0, 14.5))
	world.player.global_position = outside + Vector3.UP * .5
	world.player.velocity = Vector3.ZERO
	await settle(.5)
	check(absf(world.player.global_position.y - inn.global_position.y) < .5, "the trail end is level with the inn (%.2f m)" % (world.player.global_position.y - inn.global_position.y))
	world.camera_rig._yaw = inn.rotation.y
	world.camera_rig._apply_rotation()
	world.camera_rig.snap_to_target()
	check(await drive(inn.to_global(Vector3(0, 0, 12.0)), 6.0), "walks up to the door")
	world._update_prompt()
	check(world.current_door == inn.door and not world.interact_button.disabled, "the action button offers the inn door")
	world.interact()
	await settle(1.2)
	check(inn.door.fraction > .9, "the door opens")
	check(await drive(inn.to_global(Vector3(0, .4, 7.0)), 8.0), "walks through the door into the hall")
	check(inn.contains(world.player.global_position), "the hero is inside the inn")
	check(world.player.global_position.y > inn.global_position.y + .2, "stands on the floor, not under it")
	# The counter and tables are solid.
	# The bar: the long counter at x 2.8 blocks the way to the innkeeper.
	check(await drive(inn.to_global(Vector3(4.6, .4, -1.0)), 4.0, .3) == false, "the bar blocks the way behind it")
	# The innkeeper across the bar.
	world.player.global_position = inn.to_global(Vector3(2.0, .5, -1.5))
	world.player.facing_direction = inn.global_basis.x
	await settle(.3)
	world._update_prompt()
	check(world.inn_keeper != null and world.inn_keeper_in_reach(), "the innkeeper can be reached across the bar")
	check(world.interact_button.text == Localization.text("COURTYARD_ACTION_TALK"), "the action button offers to talk")
	world.interact()
	check(world.hud._message_visible and world.inn_talk.flags[&"greeted"], "the innkeeper greets the hero")
	var first: DialogueLineData = INN_TALK.lines[0]
	check(first.line_key == "INN_KEEPER_GREETING", "the greeting comes first")
	check(world.inn_talk.line_for(&"inn_keeper").line_key == "INN_KEEPER_REPEAT", "then the regular line")
	await check_dressing()
	# Up the stairs to the loft (the flight rises towards the back wall, -z in the inn frame).
	# From the middle aisle to the foot of the flight: no table in the way any more.
	world.player.global_position = inn.to_global(Vector3(-1.6, .5, 1.2))
	world.player.velocity = Vector3.ZERO
	await settle(.3)
	check(await drive(inn.to_global(Vector3(-3.6, .4, -1.0)), 5.0, .4), "walks from the aisle to the foot of the stairs")
	world.player.global_position = inn.to_global(Vector3(-3.6, .5, -1.1))
	world.player.velocity = Vector3.ZERO
	world.camera_rig._yaw = inn.rotation.y
	world.camera_rig._apply_rotation()
	world.camera_rig.snap_to_target()
	await settle(.3)
	check(await drive(inn.to_global(Vector3(-3.6, 4, -7.3)), 8.0, .5), "climbs the stairs")
	var loft_height: float = world.player.global_position.y - inn.global_position.y
	check(loft_height > 3.6 and loft_height < 4.1, "stands on the loft floor (%.2f m)" % loft_height)
	check(await drive(inn.to_global(Vector3(0.5, 4, -7.3)), 6.0, .5) and await drive(inn.to_global(Vector3(0.5, 4, -2.0)), 6.0, .5), "walks across the loft around the stairwell")
	loft_height = world.player.global_position.y - inn.global_position.y
	check(loft_height > 3.6 and loft_height < 4.1, "still on the loft (%.2f m)" % loft_height)
	print("FOREST_INN_CHECKS checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func named(root: Node, part: String) -> Array[Node]:
	var found: Array[Node] = []
	for node in root.find_children("*", "Node3D", true, false):
		if part in String(node.name):
			found.append(node)
	return found

func from_scene(root: Node, model: String) -> Array[Node]:
	var found: Array[Node] = []
	for node in root.find_children("*", "Node3D", true, false):
		if node.scene_file_path.ends_with("/%s.glb" % model):
			found.append(node)
	return found

func check_dressing() -> void:
	var dressing: Node3D = inn.get_node_or_null("InnDressing")
	check(dressing != null, "the inn is dressed")
	if dressing == null:
		return
	# The hearth stands between the two rear windows (x 1.0, back wall), the fire burns in its mouth.
	var hearth := named(inn, "inn_hearth")
	check(not hearth.is_empty(), "the big hearth is in the model")
	if not hearth.is_empty():
		var at: Vector3 = inn.to_local((hearth[0] as Node3D).global_position)
		check(absf(at.x - 1.0) < .3 and at.z < -8.5, "the hearth is at the back wall between the windows (%.1f, %.1f)" % [at.x, at.z])
		var box := AABB()
		var first := true
		for mesh in hearth[0].find_children("*", "MeshInstance3D", true, false):
			var b: AABB = inn.global_transform.affine_inverse() * (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		check(box.size.x > 2.4, "the hearth is twice the old size (%.2f m wide)" % box.size.x)
	check(not named(inn, "spit_roast").is_empty(), "a pig roasts on the spit")
	check(dressing.flames != null and dressing.flames.emitting and dressing.flames.amount >= 20, "the fire burns")
	check(dressing.flames != null and inn.to_local(dressing.flames.global_position).distance_to(Vector3(1.0, .86, -8.9)) < .5, "the fire is in the hearth's mouth")
	var sound: AudioStreamPlayer3D = dressing.get_node_or_null("HearthSound")
	check(sound != null and sound.stream != null and sound.autoplay, "the fire crackles")
	var energy: float = dressing.fire_light.light_energy
	await settle(.15)
	check(dressing.fire_light != null and dressing.fire_light.light_energy != energy, "the firelight flickers")
	# Every light in the inn has its lantern (or is the fire).
	var lanterns := from_scene(inn, "wooden_lantern_01")
	var lights := inn.find_children("*", "OmniLight3D", true, false)
	var loose := 0
	for light in lights:
		if light == dressing.fire_light:
			continue
		var owned := false
		for lantern in lanterns:
			if (lantern as Node3D).global_position.distance_to((light as Node3D).global_position) < .5:
				owned = true
		if not owned:
			loose += 1
	check(loose == 0, "no light without a lantern (%d loose)" % loose)
	check(lights.size() <= 6, "a phone-sized light budget (%d lights)" % lights.size())
	# Chests at the foot of the 8 loft beds, hay, clutter.
	var chests := named(inn, "bed_chest")
	var roots := 0
	var whole := RegEx.create_from_string("^bed_chest[0-9]$")
	for chest in chests:
		if whole.search(String(chest.name)) != null:
			roots += 1
	check(roots == 8, "a chest at every loft bed (%d)" % roots)
	check(named(inn, "loft_hay").size() >= 4, "hay in the loft")
	# Props, candles and rugs.
	check(from_scene(dressing, "wine_bottles_01").size() >= 3 and from_scene(dressing, "brass_goblets").size() >= 2, "bottles and goblets")
	check(from_scene(dressing, "hamburger_buns").size() + from_scene(dressing, "food_apple_01").size() + from_scene(dressing, "carved_wooden_plate").size() >= 5, "food on the bar and tables")
	check(from_scene(dressing, "wooden_candlestick").size() == 3, "candles on the tables")
	var rugs := 0
	for mesh in dressing.find_children("*", "MeshInstance3D", false, false):
		var plane: Mesh = (mesh as MeshInstance3D).mesh
		if plane is PlaneMesh and not plane is QuadMesh:
			rugs += 1
	check(rugs == 3, "rugs on the floors (%d)" % rugs)
	# The village houses: their fill light hangs as a lantern too.
	for building in world.buildings:
		var fill: Node3D = building.get_node_or_null("InteriorFill")
		var lantern: Node3D = building.get_node_or_null("Lantern")
		check(fill == null or (lantern != null and lantern.position.distance_to(fill.position) < .5), "house %s: its light hangs as a lantern" % building.record.id)
	# The centre lantern's rope reaches the ceiling in every building, the inn's tall hall included.
	for building in world.buildings + [inn]:
		var rope: MeshInstance3D = building.get_node_or_null("LanternRope")
		if rope == null:
			continue
		var top: Vector3 = building.to_global(rope.position + Vector3(0, (rope.mesh as BoxMesh).size.y * .5 - .03, 0))
		var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3.UP * 8.0, 1))
		var gap: float = (hit.position.y - top.y - .03) if not hit.is_empty() else 99.0
		check(gap < .08, "%s: the lantern rope reaches the ceiling (gap %.2f m)" % [building.record.id, gap])
