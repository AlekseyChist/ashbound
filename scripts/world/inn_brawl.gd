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
			men[role] = man
		_settle(men[role], role)
	if daughter == null:
		daughter = preload("res://scripts/world/inn_brawl_ally.gd").new()
		daughter.name = "InnDaughter"
		world.add_child(daughter)
		daughter.setup(session, floor_at, inn.to_global(DAUGHTER_AT), _dir(DAUGHTER_AT, LEADER_AT))
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
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, base + 0.5, z), Vector3(x, base - 1.0, z), 1)
	var hit := space.intersect_ray(query)
	# Owner 9 Oct: staged right after loading, the inn's floor is not in the physics space yet and the ray
	# hits the ground under it (0.36 m lower) - the daughter stood sunk into the floor. Inside, never below it.
	if hit.is_empty() or (hit.position.y < base - 0.1 and inn.contains(Vector3(x, base, z))):
		return base
	return hit.position.y

## The scene is running: the innkeeper's menu waits.
func busy() -> bool:
	return phase in ["intro", "offer", "fight", "after"]

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

func _watch_fight() -> void:
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
		if man.state != "gone":
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
		var man: Node = men[role]
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
