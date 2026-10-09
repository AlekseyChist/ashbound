extends Node
## INN-BRAWL-01 (D-092, chapter #141 edition 2, D-111/112/113): the morning after the first night in
## the forest inn. Three of the moneylender's men wait at the table by the door for a debtor and pick on
## the innkeeper's daughter. When the hero comes down into the hall the scene plays its lines and offers
## three answers; two start the fight, "I just came down" leaves it waiting (offered again at the table).
## The fight uses the world's combat session: the three are "guard" enemies of the hero, the brute fights
## the daughter (inn_brawl_ally.gd) until she is out. Beaten men give up and leave through the door; the
## first one to give up takes the others along. Winning, or being knocked out (HERO_KO_HITS blows taken;
## the hero comes to on the bed), makes the bed the hero's for good. A fight left halfway (out of the inn,
## a restart) starts over from before the fight. The scene's state lives in the inn's file (inn_lodging.gd).
signal finished(outcome: String)

## Inn frame (x, floor, z): the door is at +z, the stairs come down at the left rear, the bar is right.
const FLOOR := 0.36
const LEADER_AT := Vector3(1.25, FLOOR, 5.2)
const BRUTE_AT := Vector3(3.4, FLOOR, 7.0)
const YOUNG_AT := Vector3(1.5, FLOOR, 8.8)
const DAUGHTER_AT := Vector3(1.2, FLOOR, 4.0)
## Where the daughter goes when she is out, and where she stands after the scene.
const DAUGHTER_OUT := Vector3(1.6, FLOOR, -5.0)
const DAUGHTER_AFTER := Vector3(1.5, FLOOR, -0.6)
## Beaten men run here, out through the double door.
const DOOR_OUT := Vector3(0.0, FLOOR, 13.0)
## Codex 159: from the door round the near left corner, along the side wall (ground height there);
## Codex 163: each of the three ends at his own place along the wall, not all on one point.
const OUTSIDE_CORNER := Vector3(-7.5, FLOOR, 13.0)
const OUTSIDE_END := {"leader": Vector3(-7.5, FLOOR, 8.0), "brute": Vector3(-7.6, FLOOR, 6.4), "young": Vector3(-7.4, FLOOR, 4.8)}
## Trial numbers (D-113): blows each man takes before he gives up; the brute counts the daughter's too.
const GIVE_UP := {"leader": 3, "brute": 5, "young": 2}
const HERO_KO_HITS := 6
const LINE_TIME := 3.2
## Shouts in the fight leave the screen by themselves, never take taps (Codex 135).
const SHOUT_TIME := 3.0
## The answers are offered again when the hero comes this close to the ringleader.
const OFFER_RADIUS := 2.2
## The lines start when the hero is this near the ringleader and has him in view (Codex 135: stage the
## start, do not turn the camera) - not as soon as the hero steps into the hall with them behind him.
const START_RADIUS := 7.0
const START_VIEW_COS := 0.64
## Codex's drawn sets (inn-v1: the daughter, bridge 147; the three, e35ff4e).
const FINAL_FRAMES_DIR := "res://assets/characters/inn-v1/"
const FRAMES := {"leader": "thug_leader_frames.tres", "brute": "thug_brute_frames.tres",
	"young": "thug_young_frames.tres"}
const DAUGHTER_FRAMES := "daughter_frames.tres"

static func frames_path(file: String) -> String:
	return FINAL_FRAMES_DIR + file

## Codex return 9 Oct: world-sized names filled the screen near the camera and shrank to dots far away;
## the scene's names keep one size on screen (about the HUD's small text).
static func _screen_label(label: Label3D) -> void:
	if label == null:
		return
	label.fixed_size = true
	label.pixel_size = 0.0007
const NAMES := {"leader": "INN_THUG_LEADER_NAME", "brute": "INN_THUG_BRUTE_NAME", "young": "INN_THUG_YOUNG_NAME"}

var world: Node3D
var lodging: Node
var session: Node
var inn: Node3D
## Runtime phase: "off", "staged", "intro", "offer", "waiting", "fight", "after", "done".
var phase := "off"
var men := {}
var daughter: CharacterBody3D
var hero_hits := 0
## Checks shorten these; the game keeps the trial numbers above.
var ko_hits := HERO_KO_HITS
var line_time := LINE_TIME
var outcome := ""
var _first_gone := ""
var _leader_threat := false
var _offer_armed := true
var _logged_phase := ""
var _silent: Node

func configure(scene: Node3D) -> void:
	world = scene
	lodging = world.lodging
	session = world.combat.session
	inn = world.inn
	if inn == null:
		return
	lodging.woke.connect(_on_woke)
	session.resolved.connect(_on_hero_contact)
	if lodging.brawl == "pending":
		stage()
	elif lodging.brawl == "done":
		_daughter_after()

func _on_woke() -> void:
	if lodging.brawl == "pending" and phase == "off":
		stage()

## Puts the three at their table and the daughter with her tray; nobody fights yet.
func stage() -> void:
	for role in ["leader", "brute", "young"]:
		if not men.has(role):
			var at: Vector3 = inn.to_global(_home(role))
			var man: CharacterBody3D = session.spawn_enemy("guard", at)
			man.name = "Moneylender" + role.capitalize()
			man.label_key = NAMES[role]
			man._update_label_text()
			man.ground_height = floor_at
			man.get_node("Visual").use_frames(frames_path(FRAMES[role]))
			man.pose_fps = 15.0
			man.detour_obstacles = true
			_screen_label(man.get_node("EnemyLabel"))
			men[role] = man
		_settle(men[role], role)
	if daughter == null:
		daughter = preload("res://scripts/world/inn_brawl_ally.gd").new()
		daughter.name = "InnDaughter"
		world.add_child(daughter)
		daughter.setup(session, floor_at, inn.to_global(DAUGHTER_AT), _dir(DAUGHTER_AT, LEADER_AT))
		_screen_label(daughter.get_node("NameLabel"))
	daughter.restore()
	daughter.place(inn.to_global(DAUGHTER_AT), _dir(DAUGHTER_AT, LEADER_AT))
	hero_hits = 0
	_first_gone = ""
	_leader_threat = false
	phase = "staged"

func _home(role: String) -> Vector3:
	return {"leader": LEADER_AT, "brute": BRUTE_AT, "young": YOUNG_AT}[role]

## A man at his place, waiting, not fighting, standing again if he had left.
func _settle(man: CharacterBody3D, role: String) -> void:
	man.reset_home()
	man.engaged = false
	man.opponent = null
	man.flee_after_hits = GIVE_UP[role]
	man.flee_point = inn.to_global(DOOR_OUT)
	# Codex returns 155/159: beaten, he walks the aisle to the door, out, and round the near left corner
	# (round tables and benches); he is gone only once he is outside, on the outer part of the way and
	# out of sight (his whole figure behind walls or out of the frame).
	var route: Array[Vector3] = []
	for local in [Vector3(0.0, FLOOR, 8.1), Vector3(0.0, FLOOR, 11.0), DOOR_OUT, OUTSIDE_CORNER, OUTSIDE_END[role]]:
		route.append(inn.to_global(local))
	man.flee_route = route
	man.flee_done = func() -> bool: return _left_hall(man) and man._route_index >= 3 and out_of_sight(man)
	man.visible = true
	man.collision_layer = 4
	man.collision_mask = 7
	man.facing_direction = _dir(_home(role), DAUGHTER_AT)

func _dir(from: Vector3, to: Vector3) -> Vector3:
	var d: Vector3 = inn.to_global(to) - inn.to_global(from)
	d.y = 0.0
	return d.normalized()

## The floor under a point in the inn: a ray from just above the floor, below benches and the loft.
func floor_at(x: float, z: float) -> float:
	var base: float = inn.global_position.y + FLOOR
	var space := world.get_world_3d().direct_space_state
	var inside: bool = inn.contains(Vector3(x, base, z))
	# Outside (the beaten men's way round the corner) the ground may lie well below the floor. The ray
	# starts just above floor level - from higher it caught the porch roof (Codex 161: men jumped 3 m);
	# only if nothing is below it is tried from above (ground rising round the corner).
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, base + 0.5, z), Vector3(x, base - (1.0 if inside else 6.0), z), 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty() and not inside:
		query = PhysicsRayQueryParameters3D.create(Vector3(x, base + 2.0, z), Vector3(x, base + 0.5, z), 1)
		hit = space.intersect_ray(query)
	# Owner 9 Oct: staged right after loading, the inn's floor is not in the physics space yet and the ray
	# hits the ground under it (0.36 m lower) - the daughter stood sunk into the floor. Inside, never below it.
	if hit.is_empty() or (hit.position.y < base - 0.1 and inside):
		return base
	return hit.position.y

## The scene is running: the innkeeper's menu waits.
func busy() -> bool:
	return phase in ["intro", "offer", "fight", "after"]

## Codex return 9 Oct: four names at once ran together. In the fight none (the speaker is named in the
## line panel); before it only the nearest of the four within NAME_RADIUS of the hero.
const NAME_RADIUS := 6.0
func _show_one_name(inside: bool) -> void:
	var people: Array[Node3D] = []
	for role in men:
		people.append(men[role])
	if daughter != null:
		people.append(daughter)
	var nearest: Node3D = null
	if inside and not phase in ["fight", "after"]:
		var best := NAME_RADIUS
		for person in people:
			var d := _planar(person.global_position, world.player.global_position)
			if d < best:
				best = d
				nearest = person
	for person in people:
		var label: Node = person.get_node_or_null("EnemyLabel")
		if label == null:
			label = person.get_node_or_null("NameLabel")
		if label != null:
			label.set_meta("scene_hidden", person != nearest)

func _process(_delta: float) -> void:
	if inn == null or world.player == null:
		return
	if phase != _logged_phase:
		_logged_phase = phase
		print("INN_BRAWL_PHASE ", phase)
	var inside: bool = inn.contains(world.player.global_position)
	if phase in ["staged", "waiting"] and _struck_first():
		# The hero hit one of them before any word: that is the answer.
		world.hud.show_message("INN_THUG_LEADER_NAME", "INN_BRAWL_LEADER_LANDLORD", {}, SHOUT_TIME)
		_start_fight()
		return
	_show_one_name(inside)
	match phase:
		"staged":
			if inside and _sees_men():
				_intro()
		"waiting":
			var leader: Node3D = men["leader"]
			var near: bool = _planar(leader.global_position, world.player.global_position) <= OFFER_RADIUS
			if not near:
				_offer_armed = true
			elif _offer_armed and world.is_input_available():
				_offer_armed = false
				_offer(false)
		"fight":
			if not inside:
				# Left the hall in the middle of the fight: it starts over from before it.
				stage()
				phase = "waiting"
				_offer_armed = true
				world.hud.clear_message()
				return
			_watch_fight()

## The ringleader is near and inside the camera's view.
func _sees_men() -> bool:
	var leader: Node3D = men.get("leader")
	if leader == null or _planar(leader.global_position, world.player.global_position) > START_RADIUS:
		return false
	var camera: Camera3D = world.get_viewport().get_camera_3d()
	if camera == null:
		return true
	var to: Vector3 = leader.global_position - camera.global_position
	to.y = 0.0
	var ahead: Vector3 = -camera.global_basis.z
	ahead.y = 0.0
	return to.normalized().dot(ahead.normalized()) >= START_VIEW_COS

func _struck_first() -> bool:
	for role in men:
		if men[role].hits_received > 0:
			return true
	return false

## The world's voice (world_voice.gd); a silent stand-in where a scene has none.
func _voice() -> Node:
	if world.get("voice") != null:
		return world.voice
	if _silent == null:
		_silent = preload("res://scripts/world/world_voice.gd").new()
		_silent.enabled = false
		add_child(_silent)
	return _silent

func _planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _intro() -> void:
	phase = "intro"
	await _lines([
		["INN_THUG_LEADER_NAME", "INN_BRAWL_LEADER_ASK"],
		["INN_THUG_LEADER_NAME", "INN_BRAWL_LEADER_SIT"],
		["INN_DAUGHTER_NAME", "INN_BRAWL_DAUGHTER_PAY"],
		["INN_KEEPER_NAME", "INN_BRAWL_KEEPER_OUT"],
		["INN_THUG_BRUTE_NAME", "INN_BRAWL_BRUTE_THREE"],
	])
	if phase != "intro":
		return
	if not inn.contains(world.player.global_position):
		phase = "staged"
		return
	_offer(true)

## The daughter's quiet word to the hero, with the three answers.
func _offer(first: bool) -> void:
	phase = "offer"
	var answers := [
		[&"step_in", Localization.text("INN_BRAWL_ANSWER_STEP_IN")],
		[&"pay_up", Localization.text("INN_BRAWL_ANSWER_PAY_UP")],
		[&"just_came", Localization.text("INN_BRAWL_ANSWER_JUST_CAME")],
	]
	var hint := "INN_BRAWL_DAUGHTER_HINT" if first else "INN_BRAWL_DAUGHTER_AGAIN"
	world.choices.open("INN_DAUGHTER_NAME", hint, answers)
	# D-116: the daughter says her quiet word aloud while the answers wait.
	_voice().play(hint, "INN_DAUGHTER_NAME")
	var id: StringName = await world.choices.chosen
	if phase != "offer":
		return
	# The hero says the chosen answer aloud, then the other side answers.
	var answer: String = {&"step_in": "INN_BRAWL_ANSWER_STEP_IN", &"pay_up": "INN_BRAWL_ANSWER_PAY_UP"}.get(id, "INN_BRAWL_ANSWER_JUST_CAME")
	var said: float = _voice().length_of(answer, "INN_HERO_NAME")
	if said > 0.0:
		world.hud.show_message("INN_HERO_NAME", answer, {}, said + 0.2)
		await get_tree().create_timer(said + 0.2, false).timeout
		if phase != "offer":
			return
	match id:
		&"step_in":
			world.hud.show_message("INN_THUG_LEADER_NAME", "INN_BRAWL_LEADER_LANDLORD", {}, SHOUT_TIME)
			_start_fight()
		&"pay_up":
			world.hud.show_message("INN_THUG_LEADER_NAME", "INN_BRAWL_LEADER_EVERYONE", {}, SHOUT_TIME)
			_start_fight()
		_:
			world.hud.show_message("INN_DAUGHTER_NAME", "INN_BRAWL_DAUGHTER_STAIRS", {}, LINE_TIME + 1.0)
			phase = "waiting"
			_offer_armed = false

func _start_fight() -> void:
	phase = "fight"
	hero_hits = 0
	for role in men:
		var man: CharacterBody3D = men[role]
		man.engaged = true
		man.detect_radius = 14.0
		man.leash_radius = 16.0
	men["brute"].opponent = daughter
	daughter.fight(men["brute"], inn.to_global(DAUGHTER_OUT))

func _on_hero_contact(result: String) -> void:
	if phase != "fight" or result != "hit":
		return
	hero_hits += 1
	if hero_hits >= ko_hits:
		_knockout()

## A beaten man at a closed door opens it the usual way (it swings away from him) and goes out.
func _open_door_for_the_beaten() -> void:
	var door: Node3D = inn.door
	if door == null or door.moving or not is_zero_approx(door.fraction):
		return
	for role in men:
		var man: CharacterBody3D = men[role]
		if man.state == "flee" and door.can_interact(man):
			door.try_toggle(man)
			return

## Out of the hall on his way (the fight is won by that, whether or not he is still seen).
func _left_hall(man: Node3D) -> bool:
	return man.state == "gone" or (man.state == "flee" and not inn.contains(man.global_position))

## His whole figure (feet, body, head; both edges) is behind world geometry or out of the frame.
func out_of_sight(man: Node3D) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return true
	var space := world.get_world_3d().direct_space_state
	var right := camera.global_basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 1e-6 else Vector3.RIGHT
	for height in [0.15, 0.9, 1.75]:
		for side in [-0.3, 0.0, 0.3]:
			var point: Vector3 = man.global_position + Vector3(0.0, float(height), 0.0) + right * float(side)
			if not camera.is_position_in_frustum(point):
				continue
			var query := PhysicsRayQueryParameters3D.create(camera.global_position, point, 1)
			query.exclude = [(man as CollisionObject3D).get_rid()]
			if space.intersect_ray(query).is_empty():
				return false
	return true

func _watch_fight() -> void:
	_open_door_for_the_beaten()
	var left := 0
	for role in men:
		var man: CharacterBody3D = men[role]
		if man.state == "flee" or man.state == "gone":
			if _first_gone.is_empty():
				_first_gone = role
				# The first one to give up takes the others along: one more blow each and they go.
				for other in men:
					var o: CharacterBody3D = men[other]
					if o.state != "flee" and o.state != "gone":
						o.flee_after_hits = o.hits_received + 1
				if role != "leader":
					world.hud.show_message(NAMES[role], "INN_BRAWL_ENOUGH", {}, SHOUT_TIME)
			if role == "leader" and not _leader_threat:
				_leader_threat = true
				world.hud.show_message("INN_THUG_LEADER_NAME", "INN_BRAWL_LEADER_THREAT", {}, SHOUT_TIME)
		if not _left_hall(man):
			left += 1
	if left == 0:
		_win()

func _win() -> void:
	phase = "after"
	outcome = "won"
	_finish_state()
	await _lines([
		["INN_DAUGHTER_NAME", "INN_BRAWL_DAUGHTER_DOOR"],
		["INN_HERO_NAME", "INN_BRAWL_HERO_MORNING"],
		["INN_DAUGHTER_NAME", "INN_BRAWL_DAUGHTER_BREAKFAST"],
		["INN_KEEPER_NAME", "INN_BRAWL_KEEPER_BED"],
		["INN_HERO_NAME", "INN_BRAWL_HERO_ONE_FIGHT"],
		["INN_KEEPER_NAME", "INN_BRAWL_KEEPER_COULD_LEAVE"],
		["INN_DAUGHTER_NAME", "INN_BRAWL_DAUGHTER_BOOTS"],
	])
	_close()

## D-113: the three think they made their point and leave; the hero comes to on the bed upstairs.
func _knockout() -> void:
	phase = "after"
	outcome = "knocked_out"
	world.player.stop_input()
	world.hud.clear_message()
	var veil: ColorRect = lodging._veil
	var tween := create_tween()
	tween.tween_property(veil, "color:a", 1.0, lodging.FADE)
	await tween.finished
	for role in men:
		_gone(men[role])
	_finish_state()
	world.player.velocity = Vector3.ZERO
	world.player.global_position = lodging.bed_position() + Vector3.UP * 0.6
	await get_tree().create_timer(0.6, false).timeout
	tween = create_tween()
	tween.tween_property(veil, "color:a", 0.0, lodging.FADE)
	await tween.finished
	await _lines([
		["INN_THUG_LEADER_NAME", "INN_BRAWL_LEADER_THREAT"],
		["INN_DAUGHTER_NAME", "INN_BRAWL_DAUGHTER_UP"],
		["INN_KEEPER_NAME", "INN_BRAWL_KEEPER_KO_BED"],
	])
	_close()

func _gone(man: CharacterBody3D) -> void:
	man.state = "gone"
	man.visible = false
	man.collision_layer = 0
	man.collision_mask = 0

## One bed for good, once: the state is written before the closing lines; the men leave the combat
## session at once, so nothing of them can come back during the lines.
func _finish_state() -> void:
	for role in men:
		var man: CharacterBody3D = men[role]
		if man.state == "flee" and man.visible:
			# Codex 159: still walking away in sight - he keeps going and is let go once out of sight.
			man.fled.connect(func() -> void:
				session.enemies.erase(man)
				man.queue_free(), CONNECT_ONE_SHOT)
			continue
		session.enemies.erase(man)
		man.queue_free()
	men.clear()
	lodging.owned = true
	lodging.rented = false
	lodging.brawl = "done"
	lodging._changed()

func _close() -> void:
	_daughter_after()
	phase = "done"
	finished.emit(outcome)

## After the scene the daughter works by the bar.
func _daughter_after() -> void:
	if daughter == null:
		daughter = preload("res://scripts/world/inn_brawl_ally.gd").new()
		daughter.name = "InnDaughter"
		world.add_child(daughter)
		daughter.setup(session, floor_at, inn.to_global(DAUGHTER_AFTER), _dir(DAUGHTER_AFTER, Vector3(0, FLOOR, 6)))
	daughter.restore()
	daughter.place(inn.to_global(DAUGHTER_AFTER), _dir(DAUGHTER_AFTER, Vector3(0, FLOOR, 6)))
	phase = "done"

## Shows the lines one after another; stops early when the phase changed under it.
func _lines(lines: Array) -> void:
	var started := phase
	for entry in lines:
		if phase != started:
			return
		world.hud.show_message(entry[0], entry[1])
		# A voiced line lasts as long as it is spoken (D-115), a silent one line_time.
		var spoken: float = _voice().length_of(entry[1], entry[0])
		await get_tree().create_timer(maxf(line_time, spoken + 0.35 if spoken > 0.0 else 0.0), false).timeout
	if phase == started:
		world.hud.clear_message()
