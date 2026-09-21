extends Node3D
## FirstCourtyard — локальный уровень-упражнение «бытовой двор».
## Все состояния эфемерны и живут только внутри сцены.

signal journal_changed()

enum State { MEET_HOST, FETCH_WOOD, RETURN_WOOD, MEET_GUARD, PRACTICE, REPORT, DONE }

const FACING_DOT_MIN := 0.2
const MAX_DUMMY_HITS := 3

@export var interact_radius: float = 2.2
@export var strike_range: float = 1.8
var state: int = State.MEET_HOST
var dummy_hits: int = 0
var reward_claimed: bool = false

@onready var _player: CharacterBody3D = $Actors/Player
@onready var _innkeeper: Node3D = $Actors/Innkeeper
@onready var _watchman: Node3D = $Actors/Watchman
@onready var _woodpile: Node3D = $Interactions/Woodpile
@onready var _camera_rig: Node3D = $CameraRig
@onready var _camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var _hud: Node = $HUD
@onready var _interaction_feedback: Node3D = $InteractionFocus
@onready var _attack_feedback: Node3D = $AttackFocus

var _player_spawn: Vector3 = Vector3.ZERO
var _current_target: Node = null
var _current_attack_target: Node3D = null
var _last_focus_prompt: String = ""
var _capture_path: String = ""
var _capture_started: bool = false
var _capture_frames: int = 0
var _pending_interact: bool = false
var _dummy_flash_t: float = 0.0
var _dummy_base_scale: Vector3 = Vector3.ONE


func _ready() -> void:
	_player_spawn = _player.global_position
	var dummy: Node3D = _get_dummy()
	if dummy != null:
		var visual: Node3D = _dummy_visual(dummy)
		if visual != null:
			_dummy_base_scale = visual.scale
	_connect_signals()
	Localization.language_changed.connect(_on_language_changed)
	_hud.set_prompt("")
	_camera_rig.set_target(_player)
	_snap_camera_to_player()
	_apply_state(State.MEET_HOST)
	print("ASHBOUND_COURTYARD_READY")
	# Скриншот-хук только при явном аргументе запуска.
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--capture-courtyard="):
			_capture_path = a.substr("--capture-courtyard=".length())


func _connect_signals() -> void:
	_hud.move_changed.connect(_player.set_move_input)
	_hud.interact_pressed.connect(_on_hud_interact)
	_hud.attack_pressed.connect(_on_hud_attack)
	_hud.run_changed.connect(_player.set_run_input)
	_hud.restart_pressed.connect(_on_restart_pressed)
	_player.interact_requested.connect(_on_interact_requested)
	_player.strike_requested.connect(_on_strike_requested)
	_innkeeper.interacted.connect(_on_point_interacted)
	_woodpile.interacted.connect(_on_point_interacted)
	_watchman.interacted.connect(_on_point_interacted)


func _physics_process(_delta: float) -> void:
	# Все рейкасты по физическому пространству — только здесь.
	if _pending_interact:
		_pending_interact = false
		var t: Node = _nearest_interactable()
		if t != null:
			t.interacted.emit(t)
	_update_interaction_prompt()


func _process(delta: float) -> void:
	_update_dummy_flash(delta)
	if _capture_path != "" and not _capture_started:
		if DisplayServer.get_name() == "headless":
			printerr("courtyard: capture requested under headless renderer — frame_post_draw will never fire; aborting")
			get_tree().quit(1)
			return
		_capture_frames += 1
		if _capture_frames >= 12:
			_capture_started = true
			await RenderingServer.frame_post_draw
			_finish_capture()


# --- Камера ---------------------------------------------------------------

func _snap_camera_to_player() -> void:
	_camera_rig.reset_view()


# --- Взаимодействие -------------------------------------------------------

func _nearest_interactable() -> Node:
	var best: Node = null
	var best_d: float = INF
	for p in [_innkeeper, _watchman, _woodpile, get_node_or_null("Interactions/MapStand")]:
		if p == null or not is_instance_valid(p):
			continue
		var d: float = _planar_distance(_player.global_position, p.global_position)
		if d <= interact_radius and d < best_d and _has_line_of_sight(_player.global_position, p.global_position):
			best = p
			best_d = d
	return best


func _planar_distance(a: Vector3, b: Vector3) -> float:
	var da: Vector2 = Vector2(a.x, a.z)
	var db: Vector2 = Vector2(b.x, b.z)
	return da.distance_to(db)


func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from + Vector3(0.0, 1.0, 0.0), to + Vector3(0.0, 1.0, 0.0), 1, [_player.get_rid()])
	var hit: Dictionary = space.intersect_ray(query)
	# Любой коллайдер на World-маске (стены/предметы) блокирует видимость.
	return hit.is_empty()


func _update_interaction_prompt() -> void:
	var t: Node = _nearest_interactable()
	if t != _current_target:
		_current_target = t
		_apply_interaction_feedback(t)
	var at: Node3D = _eligible_attack_target()
	if at != _current_attack_target:
		_current_attack_target = at
		_apply_attack_feedback(at)
	_set_focus_prompt()


func _apply_interaction_feedback(t: Node) -> void:
	if t == null:
		_interaction_feedback.clear_target()
		return
	if t == _woodpile:
		var visual: Node3D = get_node_or_null("Environment/Props/Woodpile")
		if visual != null:
			_interaction_feedback.set_target(visual, &"interact", 0.85)
		else:
			_interaction_feedback.set_target(t, &"interact", 0.85)
	else:
		_interaction_feedback.set_target(t, &"interact", 0.48)


func _apply_attack_feedback(at: Node3D) -> void:
	if at == null:
		_attack_feedback.clear_target()
		return
	_attack_feedback.set_target(at, &"attack", 0.65)


func _set_focus_prompt() -> void:
	var touch_mode: bool = OS.has_feature("android") or _hud.force_touch_controls
	var lines: PackedStringArray = PackedStringArray()
	if _current_target != null:
		var name: String = _current_target.get_display_name()
		var action: String = _current_target.get_prompt()
		var key: String = "COURTYARD_FOCUS_INTERACT_TOUCH" if touch_mode else "COURTYARD_FOCUS_INTERACT_DESKTOP"
		lines.append(Localization.text(key, {"name": name, "action": action}))
	if _current_attack_target != null:
		var dummy_name: String = Localization.text("COURTYARD_NAME_DUMMY")
		var key: String = "COURTYARD_FOCUS_ATTACK_TOUCH" if touch_mode else "COURTYARD_FOCUS_ATTACK_DESKTOP"
		lines.append(Localization.text(key, {"name": dummy_name}))
	var text: String = "\n".join(lines)
	if text != _last_focus_prompt:
		_last_focus_prompt = text
		_hud.set_prompt(text)


func _on_language_changed(_language: String) -> void:
	# Только обновление переведённых подписей; никаких игровых действий.
	if not is_node_ready():
		return
	_refresh_objective()
	_set_focus_prompt()


func get_interaction_target() -> Node:
	return _current_target


func get_attack_target() -> Node3D:
	return _current_attack_target


func _on_hud_interact() -> void:
	_player.request_interaction()


func _on_interact_requested() -> void:
	# Запрос ставится в очередь и выполняется в _physics_process.
	_pending_interact = true


func _on_point_interacted(point: Node) -> void:
	match point.interaction_id:
		"innkeeper":
			_on_innkeeper_interact()
		"woodpile":
			_on_woodpile_interact()
		"watchman":
			_on_watchman_interact()


# --- Удары ----------------------------------------------------------------

func _on_hud_attack() -> void:
	_player.request_attack()


func _eligible_attack_target() -> Node3D:
	if state != State.PRACTICE:
		return null
	var dummy: Node3D = _get_dummy()
	if dummy == null:
		return null
	var p: Vector3 = _player.global_position
	var dpos: Vector3 = dummy.global_position
	if _planar_distance(p, dpos) > strike_range:
		return null
	var to_dummy: Vector2 = (Vector2(dpos.x, dpos.z) - Vector2(p.x, p.z)).normalized()
	var facing: Vector2 = Vector2(_player.facing_direction.x, _player.facing_direction.z).normalized()
	if facing.dot(to_dummy) < FACING_DOT_MIN:
		return null
	if not _strike_line_clear(p, dummy):
		return null
	return dummy


func _on_strike_requested() -> void:
	var dummy: Node3D = _eligible_attack_target()
	if dummy == null:
		return
	dummy_hits = mini(dummy_hits + 1, MAX_DUMMY_HITS)
	_flash_dummy()
	_refresh_objective()
	print("courtyard: strike hit %d/3" % dummy_hits)
	if dummy_hits >= MAX_DUMMY_HITS:
		_apply_state(State.REPORT)


func _strike_line_clear(from: Vector3, dummy: Node3D) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from + Vector3(0.0, 1.0, 0.0), dummy.global_position + Vector3(0.0, 1.0, 0.0), 1, [_player.get_rid()])
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider: Object = hit.get("collider")
	if collider == null:
		return false
	var n: Node = collider as Node
	if n == null:
		return false
	# Пропускаем только мишень и её коллайдеры; всё остальное блокирует удар.
	return dummy.is_ancestor_of(n)


func _get_dummy() -> Node3D:
	var d: Node = get_node_or_null("Environment/Props/Dummy")
	if d == null:
		d = get_node_or_null("Environment/Dummy")
	return d as Node3D


func _dummy_visual(dummy: Node3D) -> Node3D:
	for c in dummy.get_children():
		if c is Node3D and not (c is CollisionObject3D):
			return c as Node3D
	return null


func _flash_dummy() -> void:
	var dummy: Node3D = _get_dummy()
	var visual: Node3D = _dummy_visual(dummy) if dummy != null else null
	if visual == null:
		return
	visual.scale = _dummy_base_scale * 1.15
	_dummy_flash_t = 0.15


func _update_dummy_flash(delta: float) -> void:
	if _dummy_flash_t <= 0.0:
		return
	var dummy: Node3D = _get_dummy()
	var visual: Node3D = _dummy_visual(dummy) if dummy != null else null
	if visual == null:
		return
	_dummy_flash_t -= delta
	if _dummy_flash_t <= 0.0:
		visual.scale = _dummy_base_scale


# --- Состояния ------------------------------------------------------------

func _apply_state(s: int) -> void:
	state = s
	_refresh_objective()


func get_journal_entry() -> Dictionary:
	var entry := {
		"id": "courtyard_lesson",
		"title_key": "MENU_JOURNAL_COURTYARD",
		"objective_key": "",
		"params": {},
		"completed": false,
	}
	match state:
		State.MEET_HOST:
			entry.objective_key = "COURTYARD_OBJECTIVE_MEET_HOST"
		State.FETCH_WOOD:
			entry.objective_key = "COURTYARD_OBJECTIVE_FETCH_WOOD"
		State.RETURN_WOOD:
			entry.objective_key = "COURTYARD_OBJECTIVE_RETURN_WOOD"
		State.MEET_GUARD:
			entry.objective_key = "COURTYARD_OBJECTIVE_MEET_GUARD"
		State.PRACTICE:
			entry.objective_key = "COURTYARD_OBJECTIVE_PRACTICE"
			entry.params = {"hits": dummy_hits, "total": MAX_DUMMY_HITS}
		State.REPORT:
			entry.objective_key = "COURTYARD_OBJECTIVE_REPORT"
		State.DONE:
			entry.objective_key = "COURTYARD_OBJECTIVE_DONE"
			entry.completed = true
		_:
			return {}
	return entry

func _refresh_objective() -> void:
	var entry := get_journal_entry()
	if entry.is_empty():
		return
	_hud.set_objective(entry.objective_key, entry.params)
	journal_changed.emit()


func _on_innkeeper_interact() -> void:
	match state:
		State.MEET_HOST:
			_hud.show_message("COURTYARD_NAME_INNKEEPER", "COURTYARD_DIALOGUE_HOST_JOB")
			_apply_state(State.FETCH_WOOD)
		State.RETURN_WOOD:
			if not reward_claimed:
				reward_claimed = true
				_hud.show_message("COURTYARD_NAME_INNKEEPER", "COURTYARD_DIALOGUE_HOST_REWARD")
				_apply_state(State.MEET_GUARD)
			else:
				_hud.show_message("COURTYARD_NAME_INNKEEPER", "COURTYARD_DIALOGUE_HOST_ACCEPTED")
		State.FETCH_WOOD:
			_hud.show_message("COURTYARD_NAME_INNKEEPER", "COURTYARD_DIALOGUE_HOST_REMIND")
		_:
			_hud.show_message("COURTYARD_NAME_INNKEEPER", "COURTYARD_DIALOGUE_HOST_AFTER")


func _on_woodpile_interact() -> void:
	match state:
		State.FETCH_WOOD:
			_hud.show_message("", "COURTYARD_DIALOGUE_WOOD_TAKEN")
			if _woodpile.has_node("Label3D"):
				_woodpile.get_node("Label3D").visible = false
			_apply_state(State.RETURN_WOOD)
		State.MEET_HOST:
			_hud.show_message("", "COURTYARD_DIALOGUE_WOOD_BEFORE")
		_:
			_hud.show_message("", "COURTYARD_DIALOGUE_WOOD_ALREADY")


func _on_watchman_interact() -> void:
	match state:
		State.MEET_GUARD:
			_hud.show_message("COURTYARD_NAME_WATCHMAN", "COURTYARD_DIALOGUE_GUARD_LESSON")
			_apply_state(State.PRACTICE)
		State.REPORT:
			var _progression: Node = _player.get_node_or_null("Progression") if _player != null else null
			if _progression != null and _progression.has_method("complete_guard_practice"):
				_progression.call("complete_guard_practice")
			_hud.show_message("COURTYARD_NAME_WATCHMAN", "COURTYARD_DIALOGUE_GUARD_REPORT")
			_apply_state(State.DONE)
		State.PRACTICE:
			_hud.show_message("COURTYARD_NAME_WATCHMAN", "COURTYARD_DIALOGUE_GUARD_REMIND")
		_:
			_hud.show_message("COURTYARD_NAME_WATCHMAN", "COURTYARD_DIALOGUE_GUARD_OTHER")


# --- Сброс ----------------------------------------------------------------

func reset_lesson() -> void:
	# Сначала закрываем меню инвентаря (открытое или открывающееся),
	# чтобы сброс не конфликтовал с его состоянием.
	var inventory_menu: Node = get_node_or_null("InventoryMenu")
	if inventory_menu != null and inventory_menu.has_method("close_menu"):
		inventory_menu.call("close_menu")
	state = State.MEET_HOST
	dummy_hits = 0
	reward_claimed = false
	_current_target = null
	_current_attack_target = null
	_pending_interact = false
	_dummy_flash_t = 0.0
	var dummy: Node3D = _get_dummy()
	if dummy != null:
		var visual: Node3D = _dummy_visual(dummy)
		if visual != null:
			visual.scale = _dummy_base_scale
	if _woodpile.has_node("Label3D"):
		_woodpile.get_node("Label3D").visible = true
	if _player != null and is_instance_valid(_player):
		var _progression: Node = _player.get_node_or_null("Progression")
		if _progression != null and _progression.has_method("reset_guard_practice"):
			_progression.call("reset_guard_practice")
		_player.stop_input()
		_player.velocity = Vector3.ZERO
		_player.input_enabled = true
		_player.global_position = _player_spawn
		_player.facing_direction = Vector3.FORWARD
	_camera_rig.stop_look()
	_snap_camera_to_player()
	_hud.reset_controls()
	_hud.clear_message()
	_interaction_feedback.clear_target()
	_attack_feedback.clear_target()
	_last_focus_prompt = ""
	_hud.set_prompt("")
	_apply_state(State.MEET_HOST)


func _on_restart_pressed() -> void:
	reset_lesson()


# --- Скриншот -------------------------------------------------------------

func _finish_capture() -> void:
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		printerr("courtyard: capture failed — viewport image is null or empty")
		get_tree().quit(1)
		return
	var err: int = img.save_png(_capture_path)
	if err == OK:
		print("courtyard: capture saved to %s" % _capture_path)
		get_tree().quit(0)
	else:
		printerr("courtyard: capture failed: %s" % error_string(err))
		get_tree().quit(1)
