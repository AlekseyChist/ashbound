extends SceneTree
## Codex-owned checks: no delayed strike after an input/lifecycle interruption.
var errors: Array[String] = []
var groups := 0
var strikes := 0
var level: Node
var player: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		errors.append(label)
		printerr("ATTACK_INTERRUPTION_FAIL: " + label)

func reset_attack() -> void:
	paused = false
	player.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	player.input_enabled = true
	player.stop_input()
	player.velocity = Vector3.ZERO
	player.position = Vector3(-2, 0.1, 7)
	strikes = 0

func tick(delta: float) -> void:
	player._physics_process(delta)

func begin_windup() -> void:
	reset_attack()
	player.request_attack()
	tick(0.06)
	check(player.is_attacking() and strikes == 0, "windup before contact")

func finish_group(label: String) -> void:
	groups += 1
	print("ATTACK_GROUP %d %s" % [groups, label])

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	level = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame
	player = level.get_node("Actors/Player")
	player.set_physics_process(false)
	level.set_physics_process(false)
	level.get_node("CameraRig").set_mouse_capture(false)
	player.strike_requested.connect(func(): strikes += 1)
	# 1: the existing timings and explicit air attack remain unchanged.
	for delta in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 144.0, 0.7]:
		reset_attack()
		player.request_attack()
		for i in int(ceil(0.8 / delta)):
			tick(delta)
		check(strikes == 1, "one contact at step %f" % delta)
		check(not player.is_attacking(), "attack completes at step %f" % delta)
	finish_group("timesteps and air strike")
	# 2: repeated requests neither restart the windup nor add contacts.
	begin_windup()
	for i in 48:
		player.request_attack()
		tick(0.01)
	check(strikes == 1, "spam before 0.55 seconds has one contact")
	tick(0.02)
	player.request_attack()
	tick(0.13)
	check(strikes == 2, "new attack allowed after original cooldown")
	finish_group("repeat input and recovery")
	# 3: merely disabling input must cancel the pending hit immediately.
	begin_windup()
	player.input_enabled = false
	check(not player.is_attacking(), "input lock cancels immediately")
	player.input_enabled = true
	player.request_attack()
	tick(0.13)
	check(strikes == 0, "unlock cannot resurrect or restart interrupted attack")
	tick(0.5)
	player.request_attack()
	tick(0.13)
	check(strikes == 1, "attack works after unlock and cooldown")
	finish_group("input lock")
	# 4: OS focus loss cancels, clears motion and rejects commands until return.
	begin_windup()
	player.set_move_input(Vector2.ONE)
	player.set_run_input(true)
	player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not player.is_attacking(), "focus loss cancels immediately")
	check(player._touch_move == Vector2.ZERO and not player._touch_run, "focus clears touch motion")
	tick(0.6)
	player.request_attack()
	tick(0.13)
	check(strikes == 0, "no attacks without application focus")
	player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	player.request_attack()
	tick(0.13)
	check(strikes == 1, "explicit attack works after focus return")
	finish_group("focus lifecycle")
	# 5: Android pause is independent of focus notification order.
	begin_windup()
	player.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(not player.is_attacking(), "application pause cancels immediately")
	player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	tick(0.6)
	player.request_attack()
	tick(0.13)
	check(strikes == 0, "focus in cannot override application pause")
	player.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	player.request_attack()
	tick(0.13)
	check(strikes == 1, "resume permits fresh command")
	begin_windup()
	player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	player.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	player.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	tick(0.6)
	player.request_attack()
	tick(0.13)
	check(strikes == 0, "resume cannot override lost focus")
	finish_group("Android lifecycle ordering")
	# 6: real SceneTree pause; a paused node must reject direct HUD requests too.
	begin_windup()
	paused = true
	check(not player.is_attacking(), "tree pause cancels immediately")
	player.request_attack()
	check(not player.is_attacking(), "direct request rejected while tree paused")
	paused = false
	tick(0.6)
	check(strikes == 0, "tree resume has no delayed contact")
	player.request_attack()
	tick(0.13)
	check(strikes == 1, "explicit attack after tree resume")
	finish_group("scene pause")
	# 7: interrupt after contact, and the rest of the frame, cannot hit again.
	reset_attack()
	player.request_attack()
	tick(0.13)
	check(strikes == 1, "contact before interruption")
	player.input_enabled = false
	tick(0.7)
	check(strikes == 1 and not player.is_attacking(), "no extra post-contact hit")
	finish_group("post-contact interruption")
	# 8: a signal listener may cancel while contact is being emitted.
	reset_attack()
	var cancel_at_contact := func(): player.input_enabled = false
	player.strike_requested.connect(cancel_at_contact)
	player.request_attack()
	tick(0.13)
	check(strikes == 1 and not player.is_attacking(), "reentrant cancellation")
	tick(0.7)
	check(strikes == 1, "reentrant cancellation stays final")
	player.strike_requested.disconnect(cancel_at_contact)
	finish_group("contact callback interruption")
	# 9: actual lesson hit is resolved only at contact, never after cancellation.
	reset_attack()
	level._apply_state(4)
	level.dummy_hits = 0
	player.position = Vector3(5.7, 0.1, 3.0)
	player.facing_direction = Vector3.RIGHT
	await physics_frame
	player.request_attack()
	tick(0.06)
	player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	tick(0.2)
	check(level.dummy_hits == 0, "interrupted contact cannot advance lesson")
	player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	tick(0.5)
	player.request_attack()
	tick(0.13)
	check(level.dummy_hits == 1, "fresh contact advances lesson exactly once")
	finish_group("lesson integration")
	# 10: node lifecycle outside the scene and a disabled ancestor.
	reset_attack()
	var detached: Node = load("res://scenes/courtyard/courtyard_player.tscn").instantiate()
	detached.request_attack()
	check(not detached.is_attacking(), "detached player cannot start attack")
	detached.free()
	player.request_attack()
	tick(0.06)
	level.process_mode = Node.PROCESS_MODE_DISABLED
	check(not player.is_attacking(), "disabled ancestor cancels pending contact")
	player.request_attack()
	check(not player.is_attacking(), "disabled ancestor rejects request")
	level.process_mode = Node.PROCESS_MODE_INHERIT
	tick(0.6)
	check(strikes == 0, "reenabled ancestor has no pending hit")
	player.request_attack()
	tick(0.13)
	check(strikes == 1, "fresh request after ancestor reenabled")
	finish_group("node lifecycle")
	player.stop_input()
	level.queue_free()
	await process_frame
	check(groups == 10, "all groups completed")
	if errors.is_empty():
		print("ASHBOUND_ATTACK_INTERRUPTION_OK groups=10")
		quit(0)
	else:
		printerr("ASHBOUND_ATTACK_INTERRUPTION_FAILED count=%d groups=%d" % [errors.size(), groups])
		quit(1)
