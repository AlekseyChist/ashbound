extends Node3D
## PLAYER-WORLD-01C (D-085): the courtyard lesson in the village on the world map.
## The courtyard stages with village lines that tell the way (data/quests/village_lesson.tres):
## the hostess by the first house, the woodpile at the workshop, the watchman at the watchtower
## and the straw dummy by the north-east end of the Street.
## Progress is kept in user://world_lesson.cfg until the campaign save (SAVE-01) takes over.
signal journal_changed()

const LessonQuest: QuestData = preload("res://data/quests/village_lesson.tres")
const TowerScene = preload("res://scenes/buildings/watchtower.tscn")
const ResidentScene = preload("res://scenes/courtyard/resident.tscn")
const WatchmanFrames = preload("res://assets/characters/courtyard/watchman_frames.tres")
const WoodpileScene = preload("res://scenes/courtyard/props/woodpile.tscn")
const DummyScene = preload("res://scenes/courtyard/props/dummy.tscn")
const PointScript = preload("res://scripts/courtyard/interaction_point.gd")
const SAVE_PATH := "user://world_lesson.cfg"
## Village plan positions (metres, the layout's frame) and facing (degrees, 0 = +Z).
const HOSTESS_PLAN := Vector2(79.5, 93.0)
const WOODPILE_PLAN := Vector2(101.0, 83.0)
const WATCHMAN_PLAN := Vector2(154.3, 49.9)
const DUMMY_PLAN := Vector2(157.9, 50.0)
## The watchtower (M0 model) behind the watchman, a landmark seen along the Street; side to the road.
const TOWER_PLAN := Vector2(152.25, 54.6)
const TOWER_YAW := 0.605
const INTERACT_RADIUS := 2.2
## D-092: the watchman pays for driving the wolves off the barn: a meal and a bed (trial number).
const WOLF_REWARD := 5
const STRIKE_RANGE := 1.8
const FACING_DOT_MIN := 0.2

var world: Node3D
var quest := QuestTracker.new(LessonQuest)
var points: Array[Node3D] = []
var hostess: Node3D
var watchman: Node3D
var woodpile: Node3D
var dummy: Node3D
var tower: Node3D
var message_source: Node3D
var save_path := SAVE_PATH
var _dummy_visual: Node3D
var _dummy_scale := Vector3.ONE
var _flash := 0.0

func configure(scene: Node3D) -> void:
	world = scene
	hostess = _resident("innkeeper", "COURTYARD_NAME_INNKEEPER", HOSTESS_PLAN, null)
	watchman = _resident("watchman", "COURTYARD_NAME_WATCHMAN", WATCHMAN_PLAN, WatchmanFrames)
	woodpile = _woodpile()
	tower = TowerScene.instantiate()
	tower.name = "LessonWatchtower"
	tower.position = _ground(TOWER_PLAN)
	tower.rotation.y = TOWER_YAW
	add_child(tower)
	dummy = DummyScene.instantiate()
	dummy.name = "LessonDummy"
	dummy.position = _ground(DUMMY_PLAN)
	add_child(dummy)
	for child in dummy.get_children():
		if child is Node3D and not child is CollisionObject3D:
			_dummy_visual = child
			_dummy_scale = child.scale
			break
	world.player.strike_requested.connect(_on_strike)
	load_progress()
	_sync_woodpile_label()
	# The hero's progress has no world save yet: a finished lesson restores its guard practice mark.
	if LessonQuest.stages[quest.stage_index].completed:
		_run_effect(&"complete_guard_practice")

## QUEST-WOLVES-01: at the "wolves" stage the pack waits by the barn (also after a restart).
## The world calls this once its combat exists. The pack gone -> back to the watchman.
func sync_pack() -> void:
	if world.combat == null or quest.current_stage().id != &"wolves":
		return
	var pack: Array = world.combat.spawn_barn_pack()
	if not world.combat.pack_driven_off.is_connected(_on_pack_driven_off):
		world.combat.pack_driven_off.connect(_on_pack_driven_off)
	if pack.is_empty():
		push_error("village lesson: no barn for the wolves")

func _on_pack_driven_off() -> void:
	if quest.go_to(&"wolves_report"):
		world.hud.show_message("", "VILLAGE_LESSON_WOLVES_GONE")
		_changed()

func _ground(plan: Vector2) -> Vector3:
	var local: Vector2 = plan - world.terrain.ORIGIN
	return Vector3(local.x, world.terrain.height_at(local.x, local.y), local.y)

func _resident(id: String, name_key: String, plan: Vector2, frames: SpriteFrames) -> Node3D:
	var resident: Node3D = ResidentScene.instantiate()
	resident.name = "Lesson_" + id
	resident.interaction_id = StringName(id)
	resident.display_name = name_key
	resident.prompt = "COURTYARD_ACTION_TALK"
	if frames != null:
		resident.appearance = frames
	resident.position = _ground(plan)
	add_child(resident)
	points.append(resident)
	return resident

func _woodpile() -> Node3D:
	var point := Node3D.new()
	point.set_script(PointScript)
	point.name = "Lesson_woodpile"
	point.interaction_id = &"woodpile"
	point.display_name = "COURTYARD_NAME_WOODPILE"
	point.prompt = "COURTYARD_ACTION_TAKE_WOOD"
	point.position = _ground(WOODPILE_PLAN)
	add_child(point)
	var pile: Node3D = WoodpileScene.instantiate()
	pile.name = "Pile"
	point.add_child(pile)
	var label := Label3D.new()
	label.name = "Label3D"
	label.position = Vector3(0, 1.4, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = .006
	label.font_size = 32
	label.outline_size = 8
	label.text = "COURTYARD_NAME_WOODPILE"
	point.add_child(label)
	points.append(point)
	return point

## The lesson point the hero can talk to right now, or null.
func nearest_point() -> Node3D:
	var best: Node3D = null
	var best_distance := INTERACT_RADIUS
	for point in points:
		var offset: Vector3 = point.global_position - world.player.global_position
		var distance := Vector2(offset.x, offset.z).length()
		if distance <= best_distance and quest.line_for(point.interaction_id) != null:
			best = point
			best_distance = distance
	return best

func interact(point: Node3D) -> void:
	message_source = point
	talk_to(point.interaction_id)

## One exchange from the data: effects, the line, then the flag and stage.
func talk_to(speaker: StringName) -> bool:
	var line: DialogueLineData = quest.line_for(speaker)
	if line == null:
		return false
	for effect in line.effects:
		_run_effect(effect)
	world.hud.show_message(line.name_key, line.line_key)
	var flagged := line.set_flag != &""
	if quest.apply_line(line) or flagged:
		_changed()
		sync_pack()
	return true

func _run_effect(effect: StringName) -> void:
	match effect:
		&"hide_woodpile_label":
			woodpile.get_node("Label3D").visible = false
		&"pay_wolf_reward":
			world.get_node("/root/Inventory").add_gold(WOLF_REWARD)
		&"complete_guard_practice":
			var progression: Node = world.player.get_node_or_null("Progression")
			if progression != null and progression.has_method("complete_guard_practice"):
				progression.call("complete_guard_practice")
		_:
			push_error("village lesson: unknown effect %s" % effect)

func can_strike() -> bool:
	if not quest.counts(&"dummy_hits"):
		return false
	var offset: Vector3 = dummy.global_position - world.player.global_position
	var planar := Vector2(offset.x, offset.z)
	if planar.length() > STRIKE_RANGE:
		return false
	var facing := Vector2(world.player.facing_direction.x, world.player.facing_direction.z).normalized()
	return facing.dot(planar.normalized()) >= FACING_DOT_MIN

func _on_strike() -> void:
	if not can_strike():
		return
	var reached := quest.add_count(&"dummy_hits")
	if _dummy_visual != null:
		_dummy_visual.scale = _dummy_scale * 1.15
		_flash = .15
	if reached:
		quest.finish_counter()
	_changed()

func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0 and _dummy_visual != null:
			_dummy_visual.scale = _dummy_scale
	if message_source != null:
		var offset: Vector3 = message_source.global_position - world.player.global_position
		if Vector2(offset.x, offset.z).length() > INTERACT_RADIUS + .75:
			world.hud.clear_message()
			message_source = null

func journal_entry() -> Dictionary:
	return quest.journal_entry()

func _changed() -> void:
	save_progress()
	journal_changed.emit()

func _sync_woodpile_label() -> void:
	woodpile.get_node("Label3D").visible = quest.stage_index < LessonQuest.stage_index(&"return_wood")

## Switch to another progress file (checks use their own) and continue from it.
func use_save(path: String) -> void:
	save_path = path
	load_progress()
	_sync_woodpile_label()
	journal_changed.emit()

func save_progress() -> Error:
	var config := ConfigFile.new()
	config.set_value("lesson", "stage", quest.stage_index)
	config.set_value("lesson", "counters", quest.counters)
	config.set_value("lesson", "flags", quest.flags)
	return config.save(save_path)

## Missing or damaged progress starts the lesson over; values are clamped to the data.
func load_progress() -> void:
	quest.reset()
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return
	var stage: Variant = config.get_value("lesson", "stage", 0)
	var counters: Variant = config.get_value("lesson", "counters", {})
	var flags: Variant = config.get_value("lesson", "flags", {})
	if not (stage is int and counters is Dictionary and flags is Dictionary):
		return
	quest.stage_index = clampi(stage, 0, LessonQuest.stages.size() - 1)
	for key in quest.counters.keys():
		quest.counters[key] = clampi(int(counters.get(key, 0)), 0, 99)
	for key in quest.flags.keys():
		quest.flags[key] = bool(flags.get(key, false))
