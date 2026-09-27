extends Node
## WORLD-SAVE-01: the world keeps carried things, the wallet, the hero's place/facing and
## progress across sessions; a broken newest slot falls back to the other one; bad data is
## refused; a save from under the map does not move the hero there. Own QA folder.
const Scene = preload("res://scenes/world/world.tscn")
const SaveScript = preload("res://scripts/world/world_save.gd")
const DIR := "user://world-save-qa"
var failures: Array[String] = []
var checks := 0
var inv: Node

func _ready() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("WORLD_SAVE_FAIL ", label)

func settle(seconds: float = .3) -> void:
	await get_tree().create_timer(seconds, false, true).timeout

func clear_dir() -> void:
	var abs := ProjectSettings.globalize_path(DIR)
	for name in ["slot0.sav", "slot1.sav", "slot0.sav.tmp", "slot1.sav.tmp"]:
		DirAccess.remove_absolute(abs.path_join(name))

func open_world() -> Array:
	var world: Node3D = Scene.instantiate()
	add_child(world)
	await settle(.6)
	var save: Node = SaveScript.new()
	world.add_child(save)
	var status: String = save.initialize(world, DIR)
	return [world, save, status]

func close_world(world: Node3D) -> void:
	world.queue_free()
	await settle(.2)

func run() -> void:
	inv = get_node("/root/Inventory")
	clear_dir()
	var opened: Array = await open_world()
	var world: Node3D = opened[0]
	var save: Node = opened[1]
	check(opened[2] == "empty" and save.save_count == 1, "a new world starts empty and writes its first save")
	check(not world.has_node("WorldSave"), "the world does not start its own save inside checks")
	var before: int = inv.get_item_count("bread")
	check(inv.add_item("bread", 2) and inv.get_item_count("bread") == before + 2, "bread picked up")
	inv.add_gold(7)
	var gold: int = inv.gold
	var spot := Vector3(4.0, world.terrain.height_at(4.0, 6.0) + .1, 6.0)
	world.player.global_position = spot
	world.player.facing_direction = Vector3(1, 0, 0)
	check(save.flush_now() and save.save_count >= 2, "the change is written")
	await close_world(world)
	# Another session in the same folder: things and place come back.
	inv.items = []
	inv.gold = 0
	opened = await open_world()
	world = opened[0]
	save = opened[1]
	check(opened[2] == "loaded", "the next session loads the save")
	check(inv.get_item_count("bread") == before + 2 and inv.gold == gold, "carried things and wallet come back")
	check(world.player.global_position.distance_to(spot) < .3, "the hero comes back to the same place")
	check(world.player.facing_direction.dot(Vector3(1, 0, 0)) > .99, "the hero faces the same way")
	# Refused data.
	var good: Dictionary = save.capture()
	check(save.validate(good), "a real snapshot is valid")
	var bad := good.duplicate(true)
	bad.hero.position = [NAN, 0.0, 0.0]
	check(not save.validate(bad), "a broken position is refused")
	check(not save.validate({}), "an empty snapshot is refused")
	var deep := good.duplicate(true)
	deep.hero.position = [0.0, world.fall_limit() - 5.0, 0.0]
	var place: Vector3 = world.player.global_position
	check(save.apply(deep) and world.player.global_position.distance_to(place) < .01, "a save from under the map does not move the hero")
	# Newest slot damaged: the other slot is used.
	world.player.global_position = spot + Vector3(1, 0, 0)
	save.flush_now()
	var newest: int = save.store.active_slot
	await close_world(world)
	var file := FileAccess.open(ProjectSettings.globalize_path(DIR).path_join("slot%d.sav" % newest), FileAccess.READ_WRITE)
	file.seek(file.get_length() / 2)
	file.store_8(file.get_8() ^ 0xFF)
	file.close()
	opened = await open_world()
	check(opened[2] == "recovered", "a damaged newest slot falls back to the other one (%s)" % opened[2])
	await close_world(opened[0])
	clear_dir()
	inv.remove_item("bread", 2)
	print("WORLD_SAVE_CHECKS checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
