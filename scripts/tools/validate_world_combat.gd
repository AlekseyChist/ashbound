extends Node
## COMBAT-WORLD-01B (D-087): the wolf by the trail to the forest inn, in the world.
## Stays home while the hero is in the village; chases and lunges on the sloped trail on the
## ground; an unblocked lunge hits, a held block blocks, a press in the cue is a perfect block;
## the hero's strike staggers it; walking away sends it home; pause/menu stop the fight;
## the Block button is on screen without sandbox controls.
const Scene = preload("res://scenes/world/world.tscn")
var world: Node3D
var combat: Node
var session: Node
var wolf: CharacterBody3D
var player: CharacterBody3D
var events: Array[String] = []
var failures: Array[String] = []
var checks := 0

func _ready() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("WORLD_COMBAT_FAIL ", label)

func settle() -> void:
	for i in 3: await get_tree().physics_frame

func tick(seconds: float) -> void:
	var left := seconds
	while left > .0000001:
		var dt := minf(left, 1.0 / 60.0)
		session.advance(dt)
		left -= dt

func until_state(wanted: String, timeout := 5.0) -> bool:
	for i in int(ceil(timeout * 60)):
		if wolf.state == wanted: return true
		tick(1.0 / 60.0)
	return wolf.state == wanted

func until_contact(before: int, timeout := 3.0) -> bool:
	for i in int(ceil(timeout * 60)):
		if wolf.contacts > before: return true
		tick(1.0 / 60.0)
	return wolf.contacts > before

func until_cue() -> bool:
	for i in 180:
		if session.is_block_window_open(): return true
		tick(1.0 / 60.0)
	return false

func on_ground(node: Node3D) -> float:
	return absf(node.global_position.y - combat.ground_at(node.global_position.x, node.global_position.z) - .02)

## Hero on the trail, `distance` metres from the wolf along the trail, facing it.
func place_near(distance: float) -> void:
	session.set_guard(false)
	wolf.reset_home()
	events.clear()
	var toward := Vector3(-.57, 0, .82)
	var at: Vector3 = wolf.global_position + toward * distance
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(at.x, combat.ground_at(at.x, at.z) + .05, at.z)
	player.facing_direction = -toward

func run() -> void:
	world = Scene.instantiate()
	add_child(world)
	await get_tree().create_timer(.6).timeout
	combat = world.combat
	session = combat.session
	wolf = combat.wolf()
	player = world.player
	session.resolved.connect(func(result: String) -> void: events.append(result))
	check(wolf != null and wolf.kind == "wolf" and session.enemies.size() == 1, "one wolf in the world")
	# Owner (25 Sep): not in the middle of the road; the wolf waits beside the trail, at its home.
	var closest := INF
	for p in world.trail_dressing.trail:
		closest = minf(closest, Vector2(p.x - wolf.global_position.x, p.z - wolf.global_position.z).length())
	check(Vector2(wolf.global_position.x, wolf.global_position.z).distance_to(Vector2(wolf.home.x, wolf.home.z)) < .05 and closest > 5.0 and closest < 12.0, "the wolf waits beside the trail (%.1f m)" % closest)
	check(wolf.flee_after_hits == combat.FLEE_HITS, "the trail wolf runs off when beaten")
	check(on_ground(wolf) < .03, "the wolf stands on the ground (%.3f)" % on_ground(wolf))
	check(player.global_position.distance_to(wolf.global_position) > 60.0, "the village start is far from the wolf")
	check(not combat.toolbar._reset_btn.is_visible_in_tree() and combat.toolbar._guard_btn.is_visible_in_tree(), "only the Block button on screen")
	var attack: Control = world.hud.get_node("RootControl/BottomRight/VBox/AttackButton")
	check(not combat.toolbar._guard_btn.get_global_rect().intersects(attack.get_global_rect()), "Block and Attack buttons do not overlap")
	tick(2.0)
	check(wolf.state == "idle" and events.is_empty(), "the wolf ignores the hero in the village")
	# Chase on the slope stays on the ground.
	place_near(2.9)
	await settle()
	var worst := 0.0
	for i in 90:
		tick(1.0 / 60.0)
		worst = maxf(worst, on_ground(wolf))
	check(worst < .05, "the wolf keeps to the sloped ground while it moves (%.3f)" % worst)
	# Unblocked lunge.
	place_near(1.8)
	await settle()
	check(until_state("windup"), "the wolf winds up a lunge")
	check(until_contact(0) and events.back() == "hit", "an unblocked lunge hits the hero")
	check(session.get_visual_action() == &"hit", "the hero recoils")
	# Walking away sends it home.
	player.global_position = wolf.global_position + Vector3(0, 0, -12)
	tick(10.0)
	check(wolf.state == "idle" and Vector2(wolf.global_position.x - wolf.home.x, wolf.global_position.z - wolf.home.z).length() < .2, "the wolf goes home when the hero leaves")
	check(on_ground(wolf) < .03, "back home on the ground")
	# Held block and perfect block.
	place_near(1.8)
	await settle()
	session.set_guard(true)
	check(until_contact(0) and events.back() == "block", "holding Block blocks")
	place_near(1.8)
	await settle()
	check(until_state("windup") and until_cue(), "the perfect-block cue opens before contact")
	session.set_guard(true)
	check(until_contact(0) and events.back() == "perfect_block" and wolf.state == "stagger", "a press in the cue is a perfect block and staggers the wolf")
	# No strike while blocking (HUD Attack button).
	session.set_guard(true)
	world.hud.attack_pressed.emit()
	check(not player.is_attacking(), "Attack is ignored while Block is held")
	session.set_guard(false)
	# The hero's strike.
	place_near(1.4)
	await settle()
	var before: int = wolf.hits_received
	player.strike_requested.emit()
	check(wolf.hits_received == before + 1 and wolf.state == "stagger", "the hero's strike staggers the wolf")
	player.facing_direction = Vector3(.57, 0, -.82)
	var turned: int = wolf.hits_received
	wolf.reset_home()
	player.strike_requested.emit()
	check(wolf.hits_received == turned, "a strike facing away does not hit")
	# Pause (the pocket menu pauses the tree) stops the fight.
	place_near(1.8)
	await settle()
	until_state("windup")
	get_tree().paused = true
	check(not session.enabled() and not session.is_block_window_open(), "paused: no fight")
	get_tree().paused = false
	await settle()
	print("WORLD_COMBAT_CHECKS checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
