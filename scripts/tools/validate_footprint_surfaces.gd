extends SceneTree
## Real collider -> step event -> actual footprint consumer. No world save or graphical window.
class Walker extends CharacterBody3D:
	var facing_direction := Vector3.FORWARD
	func is_running() -> bool:
		return false

class TerrainFallback extends RefCounted:
	func color_at(_x: float, _z: float) -> Color:
		return Color(0, 0, 0, 0)

class PlainWorld extends Node3D:
	var player: Walker
	var terrain := TerrainFallback.new()
	var input_available := true
	var road := 0.0
	var ground_y := 0.0
	func road_at(_x: float, _z: float) -> float:
		return road
	func grass_height(_x: float, _z: float) -> float:
		return ground_y
	func is_input_available() -> bool:
		return input_available

class BiomeWorld extends PlainWorld:
	var kind := "sand"
	func ground_kind(_x: float, _z: float) -> String:
		return kind

var checks := 0
var failures: Array[String] = []
var events: Array = []
var world: PlainWorld
var audio: Node
var footprints: Node3D
var floor_body: StaticBody3D

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FOOTPRINT_SURFACE_FAIL " + label)

func setup(biomes: bool) -> void:
	world = BiomeWorld.new() if biomes else PlainWorld.new()
	root.add_child(world)
	floor_body = StaticBody3D.new()
	floor_body.position.y = 0.9
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 0.2, 20)
	shape.shape = box
	floor_body.add_child(shape)
	world.add_child(floor_body)
	world.player = Walker.new()
	var capsule := CollisionShape3D.new()
	var body := CapsuleShape3D.new()
	body.height = 1.7
	body.radius = 0.3
	capsule.shape = body
	capsule.position.y = 0.85
	world.player.add_child(capsule)
	world.add_child(world.player)
	world.player.position = Vector3(0, 1.05, 0)
	var audio_script: Script = load("res://scripts/world/village_audio.gd")
	audio = audio_script.new()
	world.add_child(audio)
	audio.set_process(false)
	audio.set_physics_process(false)
	audio.world = world
	audio.step = AudioStreamPlayer.new()
	audio.add_child(audio.step)
	for surface in ["grass", "dirt", "stone", "wood", "snow"]:
		var variants: Array[AudioStream] = []
		for i in range(4):
			variants.append(load("res://assets/audio/village-v1/step_%s_%d.ogg" % [surface, i]))
		audio.samples[surface] = variants
	var prints_script: Script = load("res://scripts/world/world_footprints.gd")
	footprints = prints_script.new()
	world.add_child(footprints)
	footprints.configure(world)
	audio.stepped.connect(func(at: Vector3, kind: String): events.append([at, kind]))
	audio.stepped.connect(footprints.step)
	await settle_player()

func settle_player() -> void:
	for i in range(8):
		await physics_frame
		world.player.velocity = Vector3(0, -4, 0)
		world.player.move_and_slide()
	check(world.player.is_on_floor(), "fixture player has real floor contact")

func step_check(tag: String, biome: String, road: float, expected_sound: String, expected_kind: String) -> void:
	floor_body.set_meta("footstep_surface", tag)
	world.kind = biome
	world.road = road
	world.ground_y = 1.0 if tag == "ground" else 0.0
	var label := "%s above %s road=%.1f" % [tag, biome, road]
	await physics_frame
	check(audio.surface_at(world.player.global_position) == expected_sound, label + " sound surface")
	events.clear()
	var old_count: int = audio.step_count
	var old_print: int = footprints.get("_next")
	audio.last_position = world.player.global_position
	audio.travel = 1.3
	world.player.position.x += 0.1
	audio._physics_process(1.0 / 60.0)
	check(events.size() == 1 and audio.step_count == old_count + 1, label + " one step")
	var wants_print := expected_kind in ["sand", "snow"]
	check(events.size() == 1 and (events[0][1] == expected_kind if wants_print else events[0][1] not in ["sand", "snow"]), label + " event deformation kind")
	check(audio.last_surface == expected_sound and audio.step.stream in audio.samples[expected_sound], label + " same sound bank")
	check(int(footprints.get("_next")) == old_print + (1 if wants_print else 0), label + " actual footprint count")
	if wants_print:
		var mark: MeshInstance3D = footprints.get("_prints")[old_print]
		check(mark.visible and absf(mark.global_position.y - 1.03) < 0.001, label + " ground print height")
	print("FOOTPRINT_CASE ", label, " emitted=", events, " prints=", int(footprints.get("_next")) - old_print)

func suppressed_step(reason: String, movement: float) -> void:
	events.clear()
	var old_count: int = audio.step_count
	var old_print: int = footprints.get("_next")
	audio.last_position = world.player.global_position
	audio.travel = 1.34
	world.player.position.x += movement
	audio._physics_process(1.0 / 60.0)
	check(events.is_empty() and audio.step_count == old_count and int(footprints.get("_next")) == old_print, reason + " no sound event or print")

func teardown() -> void:
	audio.step.stop()
	world.queue_free()
	await process_frame
	await process_frame
	events.clear()

func run() -> void:
	await setup(true)
	for kind in ["sand", "snow"]:
		for surface in ["wood", "stone", "dirt", "grass", "unknown"]:
			var sound: String = "stone" if surface == "unknown" else surface
			await step_check(surface, kind, 0, sound, sound)
	await step_check("ground", "sand", 0, "dirt", "sand")
	await step_check("ground", "snow", 0, "snow", "snow")
	await step_check("ground", "sand", 1, "dirt", "dirt")
	await step_check("ground", "snow", 1, "dirt", "dirt")
	await step_check("ground", "ground", 0, "grass", "grass")
	# Return to hard flooring after snow: the previous ground kind must not leak into this step.
	await step_check("wood", "snow", 0, "wood", "wood")
	suppressed_step("stationary", 0)
	suppressed_step("teleport", 2)
	world.input_available = false
	suppressed_step("paused input", 0.1)
	world.input_available = true
	world.player.position.y += 3
	await physics_frame
	world.player.velocity = Vector3.UP
	world.player.move_and_slide()
	check(not world.player.is_on_floor(), "fixture airborne")
	suppressed_step("airborne", 0.1)
	await teardown()
	await setup(false)
	floor_body.set_meta("footstep_surface", "ground")
	await physics_frame
	check(audio.surface_at(world.player.global_position) == "grass", "legacy world without ground_kind")
	events.clear()
	audio.last_position = world.player.global_position
	audio.travel = 1.3
	world.player.position.x += 0.1
	audio._physics_process(1.0 / 60.0)
	check(events.size() == 1 and events[0][1] == "grass" and int(footprints.get("_next")) == 0, "legacy step preserved")
	await teardown()
	print("FOOTPRINT_SURFACE_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
